extends SceneTree
## World determinism + interior probe.
## Run: godot --headless --path . --script res://tests/t_world.gd -- <seed>
## Prints one "WORLD ..." summary line; compare it between two runs of the same seed.

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
	var seed_value := 20260101
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		seed_value = int(args[0])
	var world: Node3D = (load("res://scenes/world/world.tscn") as PackedScene).instantiate()
	root.add_child(world)
	world.build(seed_value)
	for _i in 5:
		await physics_frame

	var sig := PackedStringArray()
	for l in world.get_locations():
		var p: Vector3 = l["pos"]
		sig.append("%s|%s|%.2f,%.2f,%.2f|%.3f" % [l["type"], l["name"], p.x, p.y, p.z, float(l["rot"])])
	var containers := 0
	var ground_items := 0
	var ids: Array = world.loot_by_id.keys()
	ids.sort()
	for id in ids:
		var n = world.loot_by_id[id]
		if n.is_in_group("loot_container"):
			containers += 1
			sig.append("C%d|%s|%s|%s" % [id, n.kind, n.table, str(n.contents)])
		else:
			ground_items += 1
			var gp: Vector3 = n.global_position
			sig.append("I%d|%s|%d|%.2f,%.2f,%.2f" % [id, n.item_id, n.count, gp.x, gp.y, gp.z])
	var hash_text := "\n".join(sig).md5_text()
	var types := {}
	for l in world.get_locations():
		types[l["type"]] = int(types.get(l["type"], 0)) + 1
	print("WORLD seed=%d locations=%d loot_nodes=%d containers=%d ground_items=%d types=%s hash=%s" % [
		seed_value, world.get_locations().size(), world.loot_by_id.size(), containers, ground_items, str(types), hash_text])

	check(world.get_locations().size() >= 5, "open world has several locations (%d)" % world.get_locations().size())
	check(world.loot_by_id.size() > 50, "world has loot (%d nodes)" % world.loot_by_id.size())
	check(types.has("farm") and types.has("gas_station") and types.has("hospital"), "farm, gas_station and hospital all present")
	var h0: float = world.get_height(0.0, 0.0)
	var h1: float = world.get_height(120.0, -90.0)
	check(not is_equal_approx(h0, h1), "terrain has relief (%.2f vs %.2f)" % [h0, h1])
	check(world.get_spawn_point(0) != world.get_spawn_point(1), "distinct spawn slots")

	# Interior probe on first farm: ray through the door gap must pass, ray through solid wall must hit.
	var farm: Dictionary = {}
	for l in world.get_locations("farm"):
		farm = l
		break
	if farm.is_empty():
		check(false, "farm location available for interior probe")
	else:
		var node: Node3D = farm["node"]
		var space := node.get_world_3d().direct_space_state
		var y := 1.3
		var door_from: Vector3 = node.to_global(Vector3(0.0, y, 8.0))
		var door_to: Vector3 = node.to_global(Vector3(0.0, y, 0.5))
		var solid_from: Vector3 = node.to_global(Vector3(-1.5, y, 8.0))
		var solid_to: Vector3 = node.to_global(Vector3(-1.5, y, 0.5))
		var r_door := space.intersect_ray(PhysicsRayQueryParameters3D.create(door_from, door_to, 1))
		var r_solid := space.intersect_ray(PhysicsRayQueryParameters3D.create(solid_from, solid_to, 1))
		check(r_door.is_empty(), "farmhouse door gap is open (ray passes into interior)%s" % ("" if r_door.is_empty() else " hit " + str(r_door.get("position"))))
		check(not r_solid.is_empty(), "farmhouse wall beside door is solid")
		# Loot inside the house footprint (local x,z in [-5,5]x[-4,4]). Baked loot lives under Markers, so this checks
		# position only, not parentage.
		var inside := 0
		for id in world.loot_by_id:
			var n = world.loot_by_id[id]
			if n is Node3D and is_instance_valid(n):
				var lp: Vector3 = node.to_local(n.global_position)
				if absf(lp.x) < 5.0 and absf(lp.z) < 4.0 and absf(lp.y) < 4.0:
					inside += 1
		check(inside >= 2, "farmhouse interior holds loot (%d items/containers)" % inside)
		# Roof: ray straight down from above the house must be stopped by the roof
		var r_roof := space.intersect_ray(PhysicsRayQueryParameters3D.create(node.to_global(Vector3(0, 12, 0)), node.to_global(Vector3(0, 0.5, 0)), 1))
		check(not r_roof.is_empty(), "farmhouse has a roof")

	var hmin := 1e9
	var hmax := -1e9
	for ix in range(-19, 20):
		for iz in range(-19, 20):
			var hh: float = world.get_height(ix * 10.0, iz * 10.0)
			hmin = minf(hmin, hh)
			hmax = maxf(hmax, hh)
	print("INFO  terrain height range over 390x390 m: %.2f .. %.2f" % [hmin, hmax])
	check(hmax - hmin > 3.0, "terrain relief range > 3 m (%.2f)" % (hmax - hmin))

	print("RESULT  failures=%d" % fails)
	quit(1 if fails > 0 else 0)
