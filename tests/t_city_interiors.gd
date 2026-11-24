extends SceneTree
## Enterable downtown ground floors with Mini Shop / Mini Arcade props (scripts/world/city_interiors.gd). Run:
##   xvfb-run -a godot --headless --path . --script res://tests/t_city_interiors.gd
## Checks: shop and arcade rooms exist with props from both kits, every prop footprint lies inside its room, props
## overlap neither each other nor the door lane, a player-sized sphere walks from the street through the door to the
## back wall without touching anything while the walls beside the door are solid, no loot / pickup / interactable sits
## in a room, nothing failed to load, and the interiors are identical for seeds 1 and 424242.

const InteriorsScript = preload("res://tools/worldgen/city_interiors.gd")

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


func _local(room: Dictionary, wx: float, wz: float) -> Vector2:
	var v: Vector3 = Basis(Vector3.UP, float(room["yaw"])).inverse() * Vector3(wx - float(room["x"]), 0.0, wz - float(room["z"]))
	return Vector2(v.x, v.z)


func _to_world(room: Dictionary, lx: float, lz: float) -> Vector3:
	var v: Vector3 = Basis(Vector3.UP, float(room["yaw"])) * Vector3(lx, 0.0, lz)
	return Vector3(float(room["x"]) + v.x, 0.0, float(room["z"]) + v.z)


## The four corners of a placed prop's footprint, in its room's local frame.
func _corners(room: Dictionary, p: Dictionary) -> Array:
	var out: Array = []
	var b := Basis(Vector3.UP, float(p["yaw"]))
	for sx in [-0.5, 0.5]:
		for sz in [-0.5, 0.5]:
			var v: Vector3 = b * Vector3(sx * float(p["w"]), 0.0, sz * float(p["d"]))
			out.append(_local(room, float(p["x"]) + v.x, float(p["z"]) + v.z))
	return out


func _aabb(room: Dictionary, p: Dictionary) -> Rect2:
	var cs: Array = _corners(room, p)
	var r := Rect2(cs[0] as Vector2, Vector2.ZERO)
	for c in cs:
		r = r.expand(c as Vector2)
	return r


func _room_of(rooms: Array, lot: int) -> Dictionary:
	for r in rooms:
		if int(r["lot"]) == lot:
			return r
	return {}


func _hit(space: PhysicsDirectSpaceState3D, pos: Vector3, radius: float) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	var s := SphereShape3D.new()
	s.radius = radius
	q.shape = s
	q.transform = Transform3D(Basis(), pos)
	return not space.intersect_shape(q, 1).is_empty()


func _run() -> void:
	var w1: Node3D = _make(1)
	var w2: Node3D = _make(424242)
	for _i in 3:
		await physics_frame
	var ci: Node = w1.find_child("CityInteriors", true, false)
	check(ci != null, "world has a CityInteriors node")
	if ci == null:
		print("RESULT failures=%d" % fails)
		quit(1)
		return
	var rooms: Array = ci.get_meta("rooms", []) as Array
	var placed: Array = ci.get_meta("placed", []) as Array
	var kinds := {}
	for r in rooms:
		kinds[str(r["kind"])] = int(kinds.get(str(r["kind"]), 0)) + 1
	check(int(kinds.get("shop", 0)) >= 2, "shop rooms exist (%d)" % int(kinds.get("shop", 0)))
	check(int(kinds.get("arcade", 0)) >= 1, "arcade room exists (%d)" % int(kinds.get("arcade", 0)))
	var shop_n := 0
	var arc_n := 0
	for p in placed:
		if str(p["kit"]) == "mini-shop":
			shop_n += 1
		elif str(p["kit"]) == "mini-arcade":
			arc_n += 1
	check(shop_n >= 8, "mini-shop props placed inside the buildings (%d)" % shop_n)
	check(arc_n >= 4, "mini-arcade props placed inside the buildings (%d)" % arc_n)
	var has_register := false
	for p in placed:
		has_register = has_register or str(p["file"]) == "cash-register"
	check(has_register, "a cash register stands on a counter")
	var info: Dictionary = w1.get_meta("citykit", {})
	check((info.get("missing", ["x"]) as Array).is_empty(), "no model failed to load (%s)" % str(info.get("missing")))
	# every room has props, each inside its room, none touching another or the door lane
	var inside := true
	var lane_clear := true
	var no_overlap := true
	var per_room := true
	for room in rooms:
		var hw: float = float(room["w"]) * 0.5
		var hd: float = float(room["d"]) * 0.5
		var mine: Array = []
		for p in placed:
			if int(p["lot"]) == int(room["lot"]):
				mine.append(p)
		per_room = per_room and mine.size() >= 5
		var rects: Array = []
		for p in mine:
			for c in _corners(room, p):
				var cv: Vector2 = c
				if absf(cv.x) > hw - InteriorsScript.WALL_T + 0.02 or absf(cv.y) > hd - InteriorsScript.WALL_T + 0.02:
					inside = false
					print("  outside room lot=%d %s at %s" % [int(room["lot"]), str(p["file"]), str(cv)])
			var r: Rect2 = _aabb(room, p)
			if bool(p["collide"]):
				if r.position.x < InteriorsScript.LANE - 0.2 and r.end.x > -(InteriorsScript.LANE - 0.2):
					lane_clear = false
					print("  lane blocked lot=%d %s rect=%s" % [int(room["lot"]), str(p["file"]), str(r)])
				for o in rects:
					if r.grow(-0.02).intersects(o as Rect2):
						no_overlap = false
						print("  overlap lot=%d %s rect=%s" % [int(room["lot"]), str(p["file"]), str(r)])
				rects.append(r)
	check(per_room, "every room is furnished (5+ props)")
	check(inside, "every prop footprint is inside its building interior")
	check(lane_clear, "no prop stands in the door lane")
	check(no_overlap, "colliding props do not overlap each other")
	# walk the door lane with a player-sized sphere; walls beside the door must be solid (positive control)
	var space: PhysicsDirectSpaceState3D = w1.get_world_3d().direct_space_state
	var walkable := true
	var walls_solid := true
	for room in rooms:
		var hd: float = float(room["d"]) * 0.5
		var hw: float = float(room["w"]) * 0.5
		var z: float = hd + 3.0
		while z >= -hd + 1.6:
			var p: Vector3 = _to_world(room, 0.0, z)
			var ground: float = w1.get_height(p.x, p.z)
			for h in [0.6, 1.1, 1.7]:
				if _hit(space, Vector3(p.x, ground + h, p.z), 0.4):
					walkable = false
					print("  door lane blocked lot=%d at local z=%.1f height %.1f" % [int(room["lot"]), z, h])
			z -= 0.5
		var wp: Vector3 = _to_world(room, hw - 0.3, 0.0)
		walls_solid = walls_solid and _hit(space, Vector3(wp.x, w1.get_height(wp.x, wp.z) + 1.0, wp.z), 0.2)
		var fp: Vector3 = _to_world(room, 3.0, hd - 0.25)
		walls_solid = walls_solid and _hit(space, Vector3(fp.x, w1.get_height(fp.x, fp.z) + 1.0, fp.z), 0.2)
	check(rooms.size() > 0 and walkable, "a player sphere walks from the street through the door to the back wall")
	check(rooms.size() > 0 and walls_solid, "side and front walls stay solid (the room is not open)")
	# nothing pickable or lootable sits inside a room or under a prop
	var loot_ok := true
	var loot_n := 0
	for g in ["loot_item", "loot_container", "interactable"]:
		for n in get_nodes_in_group(g):
			if not (n is Node3D) or not w1.is_ancestor_of(n):
				continue
			loot_n += 1
			var gp: Vector3 = (n as Node3D).global_position
			for room in rooms:
				var l: Vector2 = _local(room, gp.x, gp.z)
				if absf(l.x) <= float(room["w"]) * 0.5 + 0.5 and absf(l.y) <= float(room["d"]) * 0.5 + 0.5:
					loot_ok = false
					print("  loot node %s inside room lot=%d" % [str(n.name), int(room["lot"])])
	check(loot_ok, "no loot, pickup or interactable sits in or against a furnished building (%d checked)" % loot_n)
	# determinism
	var ci2: Node = w2.find_child("CityInteriors", true, false)
	check(ci2 != null and str(ci2.get_meta("placed")) == str(placed) and str(ci2.get_meta("rooms")) == str(rooms),
		"interiors are identical for seeds 1 and 424242")
	print("RESULT failures=%d" % fails)
	quit(1 if fails > 0 else 0)
