extends SceneTree
## Round 3 probe: why did an AK shot at a zombie 9 m ahead not register? Prints aim geometry, then
## aims the camera exactly at the zombie's chest and fires in the same frame.
## Run: godot --headless --path . --script res://tests/t_r3_hitprobe.gd

var fails := 0


func check(cond: bool, label: String) -> void:
	if cond:
		print("PASS  ", label)
	else:
		fails += 1
		print("FAIL  ", label)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await physics_frame
	var net: Node = root.get_node_or_null("Net")
	net.host_solo(31337)
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	for _i in 40:
		await physics_frame
	var p = net.players[1]
	var sp = get_first_node_in_group("spawner")
	sp.enabled = false
	var w = p.weapons
	w.give_weapon("ak")
	w.equip(w._find_slot("ak"))
	await create_timer(1.5).timeout
	var cam: Camera3D = p.camera
	var fwd: Vector3 = -cam.global_transform.basis.z
	print("INFO  player pos=%s cam pos=%s cam fwd=%s on_floor=%s" % [str(p.global_position), str(cam.global_position), str(fwd), str(p.is_on_floor())])
	var fh := Vector3(fwd.x, 0, fwd.z).normalized()
	var pos: Vector3 = cam.global_position + fh * 9.0
	pos.y = main.world.get_height(pos.x, pos.z) + 0.3
	var z = sp.spawn_zombie_at(pos, false)
	await create_timer(0.8).timeout
	print("INFO  zombie pos=%s state=%d health=%.0f layer=%d" % [str(z.global_position), z.state_id, z.health, z.collision_layer])
	var chest: Vector3 = z.global_position + Vector3(0, 1.0, 0)
	var space: PhysicsDirectSpaceState3D = p.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(cam.global_position, chest, 1 | 4, [p.get_rid()])
	var r: Dictionary = space.intersect_ray(q)
	print("INFO  ray cam->chest hit: ", r.get("collider", "nothing"), " at ", r.get("position", "-"))
	check(not r.is_empty() and r["collider"] == z, "unobstructed ray from camera to zombie chest hits the zombie")
	# aim exactly and fire in the same frame
	cam.look_at(chest, Vector3.UP)
	var hp0: float = z.health
	w._cooldown = 0.0
	w._try_fire(w.weapon_data())
	var hit: bool = false
	for _i in 30:
		await physics_frame
		if not is_instance_valid(z) or z.health < hp0:
			hit = true
			break
	check(hit, "exactly aimed AK shot damages the zombie (hp %.0f -> %.0f)" % [hp0, z.health if is_instance_valid(z) else -1.0])
	print("RESULT  failures=%d" % fails)
	net.leave()
	quit(1 if fails > 0 else 0)
