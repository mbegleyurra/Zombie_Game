extends SceneTree
## City kit rebuild (scripts/world/city_kit.gd, road_kit.gd). Run:
##   xvfb-run -a godot --headless --path . --script res://tests/t_citykit.gd
## Checks: every Kenney kit is used (commercial / industrial / suburban buildings, mini-shop / mini-arcade
## fixtures, city-kit-roads tiles and street props), no model failed to load, buildings and street props have
## collision, roads add no collision (terrain stays the drivable ground), and the world is identical per run.

const HandLayout = preload("res://scripts/world/hand_layout.gd")

var fails := 0


func check(cond: bool, label: String) -> void:
	if cond:
		print("PASS  ", label)
	else:
		fails += 1
		print("FAIL  ", label)


func _initialize() -> void:
	_run.call_deferred()


func _make(seed_value: int) -> Node3D:
	var world: Node3D = (load("res://scenes/world/world.tscn") as PackedScene).instantiate()
	root.add_child(world)
	world.build(seed_value)
	return world


func _models_under(kit_dir: String, models: Dictionary) -> int:
	var n := 0
	for p in models:
		if str(p).begins_with("res://assets/kenney/" + kit_dir + "/"):
			n += int(models[p])
	return n


func _count_shapes(n: Node) -> int:
	var c := 0
	if n is CollisionShape3D:
		c += 1
	for ch in n.get_children():
		c += _count_shapes(ch)
	return c


func _run() -> void:
	var w1: Node3D = _make(1)
	var w2: Node3D = _make(424242)
	for _i in 3:
		await physics_frame
	var info: Dictionary = w1.get_meta("citykit", {})
	check(not info.is_empty(), "world publishes citykit info")
	var models: Dictionary = info.get("models", {})
	var tiles: Dictionary = info.get("tiles", {})
	var bld: Dictionary = info.get("buildings", {})
	check((info.get("missing", ["x"]) as Array).is_empty(), "no kit model is missing or failed to load (%s)" % str(info.get("missing")))
	for kit in ["commercial", "industrial", "suburban"]:
		check(int(bld.get(kit, 0)) >= 4, "%s buildings placed (%d)" % [kit, int(bld.get(kit, 0))])
		check(_models_under("city-kit-" + kit, models) >= 4, "city-kit-%s models used" % kit)
	check(_models_under("mini-shop", models) >= 4, "mini-shop fixtures placed in commercial buildings")
	check(_models_under("mini-arcade", models) >= 2, "mini-arcade fixtures placed in commercial buildings")
	check(_models_under("city-kit-roads", models) >= 8, "road kit street props placed (lights, signs)")
	for f in ["road-straight", "road-crossroad", "road-bend", "road-intersection", "road-end"]:
		check(int(tiles.get(f, 0)) >= 1, "road tile %s used (%d)" % [f, int(tiles.get(f, 0))])
	check(int(info.get("junctions", 0)) >= 16, "junction tiles placed (%d)" % int(info.get("junctions", 0)))
	# city streets and countryside both get tiles: count tiles outside the city grid
	var hb: Node = w1.find_child("Roads", true, false)
	check(hb is MeshInstance3D and (hb as MeshInstance3D).mesh.get_surface_count() == 1, "all roads render as one kit mesh")
	if hb is MeshInstance3D:
		var aabb: AABB = (hb as MeshInstance3D).mesh.get_aabb()
		check(aabb.size.x > 300.0 and aabb.size.z > 300.0, "road mesh spans the whole map, not just the city (%.0f x %.0f m)" % [aabb.size.x, aabb.size.z])
		check(_count_shapes(hb) == 0, "road tiles carry no collision (terrain is the drivable ground)")
	# collision: the hand world body has shapes for the kit buildings (24 lots) plus props
	var fps: Array = w1.get_meta("hand_footprints", []) as Array
	var towers := 0
	for f in fps:
		if str(f[5]) == "tower":
			towers += 1
	check(towers >= 20, "city towers keep their footprints (%d)" % towers)
	var body_shapes := 0
	for ch in w1.get_children():
		body_shapes += _count_shapes(ch)
	check(body_shapes >= towers + 20, "buildings and props have collision shapes (%d)" % body_shapes)
	# kit footprints stay inside their lots
	var inside := true
	for blk in HandLayout.CITY_BLOCKS:
		for t in blk[2]:
			var found := false
			for f in fps:
				if str(f[5]) == "tower" and absf(float(f[0]) - (float(blk[0]) + float(t[0]))) < 0.01 and absf(float(f[1]) - (float(blk[1]) + float(t[1]))) < 0.01:
					found = float(f[2]) <= float(t[2]) + 0.01 and float(f[3]) <= float(t[3]) + 0.01
			if not found:
				inside = false
	check(inside, "every kit footprint is inside its HandLayout lot")
	# determinism: seeds 1 and 424242 give the same city kit
	var info2: Dictionary = w2.get_meta("citykit", {})
	check(str(info.get("models")) == str(info2.get("models")) and str(info.get("tiles")) == str(info2.get("tiles")), "city kit is identical for seeds 1 and 424242")
	print("RESULT failures=%d" % fails)
	quit(1 if fails > 0 else 0)
