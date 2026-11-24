extends SceneTree
## City kit rebuild (scripts/world/city_kit.gd, road_kit.gd). Run:
##   xvfb-run -a godot --headless --path . --script res://tests/t_citykit.gd
## Checks: every Kenney kit is used (commercial / industrial / suburban buildings, mini-shop / mini-arcade
## fixtures, city-kit-roads tiles and street props), no model failed to load, buildings and street props have
## collision, roads add no collision (terrain stays the drivable ground), and the world is identical per run.

const HandLayout = preload("res://tools/worldgen/hand_layout.gd")
const ModelUtil = preload("res://scripts/world/model_util.gd")

const STREET_HALF_W := 3.2   ## city streets are 6.4 m wide (road_kit CITY_W)

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


## World-space bounds of every BoxShape3D collider under n.
func _box_aabbs(n: Node, out: Array) -> void:
	if n is CollisionShape3D and (n as CollisionShape3D).shape is BoxShape3D:
		var cs := n as CollisionShape3D
		var sz: Vector3 = (cs.shape as BoxShape3D).size
		out.append(cs.global_transform * AABB(-sz * 0.5, sz))
	for ch in n.get_children():
		_box_aabbs(ch, out)


## Instanced kit models (wrapper nodes) whose first child was instanced from the given .glb (Godot renames duplicate nodes, so names are no use).
func _wrappers(n: Node, glb: String, out: Array) -> void:
	if n is Node3D and n.get_child_count() > 0 and n.get_child(0).scene_file_path.ends_with(glb):
		out.append(n)
	for ch in n.get_children():
		_wrappers(ch, glb, out)


## Tower footprints that have no matching box collider (same centre and footprint) or whose collider TOP is lower than the
## model top (enterable buildings use a wall ring plus a roof slab, so the top of the highest matching box is what counts).
func _collider_problems(world: Node3D, fps: Array, boxes: Array) -> Dictionary:
	var missing := PackedStringArray()
	var short := PackedStringArray()
	for f in fps:
		if str(f[5]) != "tower":
			continue
		var hit := false
		var tallest := 0.0
		for b in boxes:
			var bb: AABB = b
			var c: Vector3 = bb.get_center()
			if absf(c.x - float(f[0])) < 0.05 and absf(c.z - float(f[1])) < 0.05 and absf(bb.size.x - float(f[2])) < 0.05 and absf(bb.size.z - float(f[3])) < 0.05:
				hit = true
				tallest = maxf(tallest, bb.end.y - world.get_height(float(f[0]), float(f[1])) + 0.05)
		if hit and tallest < float(f[6]) - 0.05:
			short.append("(%.1f,%.1f) collider %.2f m < model %.2f m" % [float(f[0]), float(f[1]), tallest, float(f[6])])
		if not hit:
			missing.append("(%.1f,%.1f)" % [float(f[0]), float(f[1])])
	return {"missing": missing, "short": short}


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
	# one MeshInstance3D per road segment / junction (editable per piece), each a single kit-material surface
	var pieces := 0
	var single := true
	var aabb := AABB()
	if hb != null:
		for ch in hb.get_children():
			var mi := ch as MeshInstance3D
			if mi == null or mi.mesh == null:
				single = false
				continue
			single = single and mi.mesh.get_surface_count() == 1
			var g: AABB = mi.global_transform * mi.mesh.get_aabb()
			aabb = g if pieces == 0 else aabb.merge(g)
			pieces += 1
	check(pieces > 50 and single, "roads render as %d per-piece kit meshes, one surface each" % pieces)
	if pieces > 0:
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
	# every single tower footprint keeps its own box collider: same centre, same footprint, and as tall as the model
	var boxes: Array = []
	for ch in w1.get_children():
		_box_aabbs(ch, boxes)
	var problems: Dictionary = _collider_problems(w1, fps, boxes)
	var missing_collider: PackedStringArray = problems["missing"]
	var short_collider: PackedStringArray = problems["short"]
	check(missing_collider.is_empty(), "every kit building footprint has its own box collider (missing: %s)" % ", ".join(missing_collider))
	check(short_collider.is_empty(), "every building collider is as tall as its model (%s)" % ", ".join(short_collider))
	# the checker itself must be able to fail: no colliders at all, or one footprint's collider removed
	var none: Dictionary = _collider_problems(w1, fps, [])
	check((none["missing"] as PackedStringArray).size() == towers, "self-test: with every collider removed all %d towers are reported missing" % towers)
	var f0: Array = []
	for f in fps:
		if str(f[5]) == "tower":
			f0 = f
			break
	var minus_one: Array = []
	for b in boxes:
		var mb: AABB = b
		var mc: Vector3 = mb.get_center()
		if absf(mc.x - float(f0[0])) < 0.05 and absf(mc.z - float(f0[1])) < 0.05:
			continue
		minus_one.append(b)
	check((_collider_problems(w1, fps, minus_one)["missing"] as PackedStringArray).size() >= 1, "self-test: removing one building's collider is detected")
	# physics level: a ray dropped on every tower roof must hit solid geometry at roof height (a collider that sits in the
	# scene tree but not in the physics space would pass the box test above and fail here)
	var space: PhysicsDirectSpaceState3D = w1.get_world_3d().direct_space_state
	var roof_miss := PackedStringArray()
	var roof_rays := 0
	for f in fps:
		if str(f[5]) != "tower":
			continue
		var gx: float = float(f[0])
		var gz: float = float(f[1])
		var gy: float = w1.get_height(gx, gz)
		var q := PhysicsRayQueryParameters3D.create(Vector3(gx, gy + float(f[6]) + 6.0, gz), Vector3(gx, gy - 1.0, gz))
		var r: Dictionary = space.intersect_ray(q)
		roof_rays += 1
		if r.is_empty() or float((r["position"] as Vector3).y) < gy + float(f[6]) - 0.3:
			roof_miss.append("(%.1f,%.1f)" % [gx, gz])
	check(roof_rays >= 20 and roof_miss.is_empty(), "a ray dropped on every tower roof hits its collider (%d rays, misses: %s)" % [roof_rays, ", ".join(roof_miss)])
	# pavement strip / suburban driveway: sized from the REAL mesh bounds, never reaching into the 6.4 m street beside the lot
	var strip_bad := PackedStringArray()
	var strip_n := 0
	for spec in [["roads_tile-low*", "res://assets/kenney/city-kit-roads/tile-low.glb", 1.0, 1.0], ["suburban_driveway-short*", "res://assets/kenney/city-kit-suburban/driveway-short.glb", 0.36, 0.2]]:
		var tmp: Node3D = (load(str(spec[1])) as PackedScene).instantiate() as Node3D
		var tb: AABB = ModelUtil.bounds(tmp)
		tmp.free()
		check(absf(tb.size.x - float(spec[2])) < 0.03 and absf(tb.size.z - float(spec[3])) < 0.03, "%s mesh is %.2f x %.2f m as the strip sizing assumes (%.2f x %.2f)" % [str(spec[0]), float(spec[2]), float(spec[3]), tb.size.x, tb.size.z])
		var found_nodes: Array = []
		_wrappers(w1, str(spec[1]).get_file(), found_nodes)
		for n in found_nodes:
			var wrap := n as Node3D
			var inst: Node3D = wrap.get_child(0) as Node3D
			var hx: float = tb.size.x * inst.scale.x * 0.5
			var hz: float = tb.size.z * inst.scale.z * 0.5
			if absf(sin(wrap.rotation.y)) > 0.7:
				var tmp_h: float = hx
				hx = hz
				hz = tmp_h
			var cx: float = wrap.global_position.x
			var cz: float = wrap.global_position.z
			strip_n += 1
			for sz in HandLayout.CITY_Z:
				if cz + hz > float(sz) - STREET_HALF_W and cz - hz < float(sz) + STREET_HALF_W and cx + hx > HandLayout.CITY_MIN.x and cx - hx < HandLayout.CITY_MAX.x:
					strip_bad.append("%s at (%.1f,%.1f) %.1f x %.1f m reaches street z=%.0f" % [wrap.name, cx, cz, hx * 2.0, hz * 2.0, float(sz)])
			for sx in HandLayout.CITY_X:
				if cx + hx > float(sx) - STREET_HALF_W and cx - hx < float(sx) + STREET_HALF_W and cz + hz > HandLayout.CITY_MIN.y and cz - hz < HandLayout.CITY_MAX.y:
					strip_bad.append("%s at (%.1f,%.1f) %.1f x %.1f m reaches street x=%.0f" % [wrap.name, cx, cz, hx * 2.0, hz * 2.0, float(sx)])
	check(strip_n >= 12, "pavement strips and suburban driveways placed (%d)" % strip_n)
	check(strip_bad.is_empty(), "no pavement strip or driveway overlaps a street (%s)" % "; ".join(strip_bad))
	# industrial plaza props (water tower / chimney) do not collide with any other box collider in xz
	var plaza_checked := 0
	var plaza_overlaps := PackedStringArray()
	for blk in HandLayout.CITY_BLOCKS:
		if float(blk[0]) < 112.0:
			continue
		for b in boxes:
			var pb: AABB = b
			var pc: Vector3 = pb.get_center()
			if absf(pc.x - float(blk[0])) > 0.05 or absf(pc.z - float(blk[1])) > 0.05 or pb.size.y < 3.0:
				continue
			plaza_checked += 1
			for o in boxes:
				var ob: AABB = o
				if ob.position == pb.position and ob.size == pb.size:
					continue
				var ox: float = minf(pb.end.x, ob.end.x) - maxf(pb.position.x, ob.position.x)
				var oz: float = minf(pb.end.z, ob.end.z) - maxf(pb.position.z, ob.position.z)
				if ox > 0.0 and oz > 0.0:
					plaza_overlaps.append("(%.0f,%.0f) vs box at %s" % [float(blk[0]), float(blk[1]), str(ob.get_center())])
	check(plaza_checked >= 2, "industrial plaza props have colliders (%d)" % plaza_checked)
	check(plaza_overlaps.is_empty(), "plaza water tower / chimney collide with nothing else (%s)" % ", ".join(plaza_overlaps))
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
