extends SceneTree
## Drivable cars (scripts/vehicles/). Run:
##   godot --headless --path . --script res://tests/t_vehicles.gd
## Part 1, over 3 seeds: cars are placed, on/near roads, inside the map, deterministic for a seed.
## Part 2, on a flat floor: enter with the interact path, drive forward, brake, exit; player hidden/seated/released.

const Vehicle = preload("res://scripts/vehicles/vehicle.gd")

var fails := 0


func check(cond: bool, label: String) -> void:
	if cond:
		print("PASS  ", label)
	else:
		fails += 1
		print("FAIL  ", label)


func _initialize() -> void:
	_run()


func _frames(n: int) -> void:
	for _i in range(n):
		await physics_frame


func _sig(w: Node3D) -> String:
	var parts := PackedStringArray()
	for c in w.get_node("Vehicles").get_children():
		var car := c as Node3D
		parts.append("%s,%.2f,%.2f,%.2f,%.3f" % [str(car.get("kind")), car.position.x, car.position.y, car.position.z, car.rotation.y])
	return "\n".join(parts).md5_text()


func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _road_dist(w: Node3D, p: Vector2) -> float:
	var best := 1e9
	for i in w.terrain.road_a.size():
		best = minf(best, _seg_dist(p, w.terrain.road_a[i], w.terrain.road_b[i]))
	return best


func _build(seed_value: int) -> Node3D:
	var w: Node3D = (load("res://scenes/world/world.tscn") as PackedScene).instantiate()
	root.add_child(w)
	w.build(seed_value)
	return w


func _run() -> void:
	await physics_frame
	for seed_value in [20260101, 31337, 7]:
		var w := _build(seed_value)
		await _frames(2)
		var vn := w.get_node_or_null("Vehicles")
		check(vn != null, "seed %d: Vehicles node exists" % seed_value)
		if vn == null:
			continue
		var cars := vn.get_children()
		print("INFO  seed %d: %d cars" % [seed_value, cars.size()])
		check(cars.size() >= 4 and cars.size() <= 10, "seed %d: car count sane (%d)" % [seed_value, cars.size()])
		var off_road := 0
		var out := 0
		for c in cars:
			var p := Vector2((c as Node3D).position.x, (c as Node3D).position.z)
			if _road_dist(w, p) > 4.5:
				off_road += 1
			if absf(p.x) > 256.0 - 30.0 or absf(p.y) > 256.0 - 30.0:
				out += 1
		check(off_road == 0, "seed %d: every car within 4.5 m of a road (%d off)" % [seed_value, off_road])
		check(out == 0, "seed %d: every car inside the map edge margin" % seed_value)
		var sig1 := _sig(w)
		w.queue_free()
		await _frames(2)
		var w2 := _build(seed_value)
		await _frames(2)
		check(_sig(w2) == sig1, "seed %d: same seed => same cars" % seed_value)
		w2.queue_free()
		await _frames(2)

	await _drive_test()
	print("RESULT  fails=%d" % fails)
	quit(1 if fails > 0 else 0)


func _drive_test() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(600, 1, 600)
	cs.shape = box
	floor_body.add_child(cs)
	floor_body.position = Vector3(0, -0.5, 0)
	root.add_child(floor_body)

	var player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	player.name = "1"
	player.position = Vector3(3, 0.2, 0)
	root.add_child(player)
	var car = Vehicle.new()
	car.setup("sedan")
	car.name = "TestCar"
	car.position = Vector3(0, 0.7, 0)
	root.add_child(car)
	await _frames(150)
	check(car.is_in_group("vehicles"), "car in group vehicles")
	check(car.has_method("interact") and car.has_method("get_prompt"), "car exposes interact/get_prompt")
	check(car.linear_velocity.length() < 0.5, "parked car settles (v=%.2f)" % car.linear_velocity.length())
	check(car.global_position.y < 0.5 and car.global_position.y > -0.3, "car rests on the ground (y=%.2f)" % car.global_position.y)

	# enter
	car.interact(player)
	await _frames(3)
	check(car.driver_id == 1, "driver_id set after enter")
	check(player.vehicle == car, "player.vehicle set")
	check(not player.visible, "player hidden while driving")
	var cam: Camera3D = car.get_node_or_null("ChaseCam")
	check(cam != null and cam.current, "chase camera is current")

	# a second player cannot take the seat
	var other = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	other.name = "2"
	other.position = Vector3(3, 0.2, 3)
	root.add_child(other)
	await _frames(2)
	car._server_handle(true, 2)
	check(car.driver_id == 1, "occupied car refuses a second driver")
	other.queue_free()

	# drive forward
	car.scripted = true
	car.throttle_in = 1.0
	var start: Vector3 = car.global_position
	await _frames(240)
	var fwd: Vector3 = -car.global_transform.basis.z
	var moved: float = (car.global_position - start).dot(fwd)
	print("INFO  drove %.1f m forward, speed %.1f m/s" % [moved, car.forward_speed()])
	check(moved > 15.0, "throttle drives the car forward (%.1f m)" % moved)
	check(car.forward_speed() > 5.0, "forward speed positive (%.1f)" % car.forward_speed())
	check(player.global_position.distance_to(car.to_global(car._seat)) < 1.5, "seated player follows the car")

	# steer
	var f0: Vector3 = -car.global_transform.basis.z
	car.steer_in = 1.0
	await _frames(90)
	var f1: Vector3 = -car.global_transform.basis.z
	var turned: float = absf(angle_difference(atan2(f0.x, f0.z), atan2(f1.x, f1.z)))
	print("INFO  steering turned the car %.2f rad (steering=%.3f angvel=%s speed=%.1f)" % [turned, car.steering, str(car.angular_velocity), car.forward_speed()])
	check(turned > 0.2, "steering turns the car (%.2f rad)" % turned)

	# brake
	car.steer_in = 0.0
	car.throttle_in = 0.0
	car.handbrake_in = 1.0
	await _frames(240)
	check(car.linear_velocity.length() < 1.0, "handbrake stops the car (v=%.2f)" % car.linear_velocity.length())

	# exit
	car.scripted = false
	await create_timer(0.5).timeout
	car.interact(player)
	await _frames(3)
	check(car.driver_id == 0, "driver_id cleared after exit")
	check(player.vehicle == null, "player.vehicle cleared")
	check(player.visible, "player visible after exit")
	check(player.global_position.distance_to(car.global_position) > 1.0, "player placed beside the car")
	check(player.camera.current or player.third_person, "a player camera is current again")
	await _frames(20)
	check(player.global_position.y > -1.0, "player did not fall through the world after exit")
