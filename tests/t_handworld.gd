extends SceneTree
## Handcrafted world (scripts/world/hand_layout.gd, hand_builder.gd). Run:
##   godot --headless --path . --script res://tests/t_handworld.gd
## Checks: the world ignores the seed (identical for seeds 1 and 424242), roads are a network (crossroads, a loop,
## no star around the spawn), a dense reachable city with tall towers, the countryside spawn outside it, every
## location / the city / the dungeon gate connected to the spawn by roads, houses beside roads, cars on roads,
## and the map texture builds with the hand footprints.

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


func _signature(world: Node3D) -> String:
	var sig := PackedStringArray()
	for l in world.get_locations():
		var p: Vector3 = l["pos"]
		sig.append("%s|%s|%.2f,%.2f,%.2f|%.3f" % [l["type"], l["name"], p.x, p.y, p.z, float(l["rot"])])
	for i in world.terrain.road_a.size():
		sig.append("R%s>%s" % [str(world.terrain.road_a[i]), str(world.terrain.road_b[i])])
	sig.append(str(world.get_meta("hand_footprints", []).size()))
	sig.append(str(world.get_meta("dungeon_site", {}).get("origin", Vector2.ZERO)))
	sig.append(str(world.spawn_center))
	return "\n".join(sig).md5_text()


## Segments touch when an endpoint of one lies within `tol` metres of the other.
func _touch(a0: Vector2, a1: Vector2, b0: Vector2, b1: Vector2, tol: float) -> bool:
	for p in [a0, a1]:
		if (p as Vector2).distance_to(Geometry2D.get_closest_point_to_segment(p, b0, b1)) <= tol:
			return true
	for p in [b0, b1]:
		if (p as Vector2).distance_to(Geometry2D.get_closest_point_to_segment(p, a0, a1)) <= tol:
			return true
	return false


func _find(parent: PackedInt32Array, i: int) -> int:
	var r := i
	while parent[r] != r:
		r = parent[r]
	return r


## Is p inside the (x, z, w, d, yaw) footprint rectangle grown by `margin` metres?
func _in_rect(p: Vector2, f: Array, margin: float) -> bool:
	var d: Vector2 = p - Vector2(float(f[0]), float(f[1]))
	var yaw: float = float(f[4])
	var lx: float = d.x * cos(yaw) - d.y * sin(yaw)
	var lz: float = d.x * sin(yaw) + d.y * cos(yaw)
	return absf(lx) <= float(f[2]) * 0.5 + margin and absf(lz) <= float(f[3]) * 0.5 + margin


## Indices of the footprints a road segment passes through (sampled every 0.25 m, far finer than any building).
func _crossed_footprints(a: Vector2, b: Vector2, fps: Array, margin: float) -> Array:
	var out: Array = []
	var n: int = maxi(int(a.distance_to(b) / 0.25), 1)
	for k in n + 1:
		var p: Vector2 = a.lerp(b, float(k) / float(n))
		for fi in fps.size():
			if not out.has(fi) and _in_rect(p, fps[fi], margin):
				out.append(fi)
	return out


func _run() -> void:
	var w1: Node3D = _make(1)
	for _i in 3:
		await physics_frame
	var sig1: String = _signature(w1)
	var terrain = w1.terrain
	var spawn: Vector2 = w1.spawn_center

	# ---- roads: a network, not a star
	var n: int = terrain.road_a.size()
	check(n >= 70, "many road segments (%d): countryside plus the city grid" % n)
	var deg := {}
	for i in n:
		for p in [terrain.road_a[i], terrain.road_b[i]]:
			var k := Vector2i(roundi(p.x), roundi(p.y))
			deg[k] = int(deg.get(k, 0)) + 1
	var max_deg := 0
	var crossroads := 0
	for k in deg:
		max_deg = maxi(max_deg, int(deg[k]))
		if int(deg[k]) >= 4 and not HandLayout.in_city(Vector2(k.x, k.y), 3.0):
			crossroads += 1
	check(max_deg <= 8, "no single point is a hub for the roads (max degree %d, the old star had ~12)" % max_deg)
	check(crossroads >= 1, "countryside has a crossroads (%d vertices of degree >= 4)" % crossroads)
	var at_spawn := 0
	for i in n:
		if (terrain.road_a[i] as Vector2).distance_to(spawn) < 2.0 or (terrain.road_b[i] as Vector2).distance_to(spawn) < 2.0:
			at_spawn += 1
	check(at_spawn <= 3, "few roads meet at the spawn (%d)" % at_spawn)
	var loop := false
	for r in HandLayout.COUNTRY_ROADS:
		var pts: Array = r[1]
		if pts.size() > 3 and (pts[0] as Vector2).is_equal_approx(pts[pts.size() - 1]):
			loop = true
	check(loop, "countryside has a closed loop road")

	# ---- connectivity: union-find over road segments
	var parent := PackedInt32Array()
	for i in n:
		parent.append(i)
	for i in n:
		for j in range(i + 1, n):
			if _touch(terrain.road_a[i], terrain.road_b[i], terrain.road_a[j], terrain.road_b[j], 2.0):
				var ri: int = _find(parent, i)
				var rj: int = _find(parent, j)
				if ri != rj:
					parent[ri] = rj
	var spawn_seg := -1
	for i in n:
		if spawn.distance_to(Geometry2D.get_closest_point_to_segment(spawn, terrain.road_a[i], terrain.road_b[i])) < 2.0:
			spawn_seg = i
			break
	check(spawn_seg >= 0, "the spawn sits on a road")
	var spawn_root: int = _find(parent, maxi(spawn_seg, 0))
	var unreached := 0
	for l in w1.get_locations():
		var p2: Vector2 = l["pos2"]
		var ok := false
		for i in n:
			if _find(parent, i) == spawn_root and p2.distance_to(Geometry2D.get_closest_point_to_segment(p2, terrain.road_a[i], terrain.road_b[i])) < float(l["radius"]) + 2.0:
				ok = true
				break
		if not ok:
			unreached += 1
			print("  unreached: ", l["name"])
	check(unreached == 0, "every location is on the road network connected to the spawn (%d unreached)" % unreached)
	var city_reached := false
	for i in n:
		if _find(parent, i) == spawn_root and HandLayout.in_city(terrain.road_a[i], 1.0) and HandLayout.in_city(terrain.road_b[i], 1.0):
			city_reached = true
			break
	check(city_reached, "the city street grid connects to the spawn by road")
	var site: Dictionary = w1.get_meta("dungeon_site", {}) as Dictionary
	check(site.has("origin"), "dungeon site exists")
	if site.has("origin"):
		var gate := Vector2(float((site["origin"] as Vector2).x), float(site["gz"]) - 18.0)
		var gate_ok := false
		for i in n:
			if _find(parent, i) == spawn_root and gate.distance_to(Geometry2D.get_closest_point_to_segment(gate, terrain.road_a[i], terrain.road_b[i])) < 2.0:
				gate_ok = true
				break
		check(gate_ok, "a track connects the spawn roads to the dungeon gate")
		check(not HandLayout.in_city(site["origin"], 5.0), "the dungeon is not inside the city")

	# ---- city
	var fps: Array = w1.get_meta("hand_footprints", []) as Array
	var towers := 0
	var tall := 0.0
	var houses := 0
	for f in fps:
		if str(f[5]) == "tower":
			towers += 1
			tall = maxf(tall, float(f[6]))
		else:
			houses += 1
	check(towers >= 20, "city has dense tower blocks (%d towers)" % towers)
	check(tall >= 30.0, "city has tall buildings (tallest %.0f m)" % tall)
	check(houses >= 15, "countryside has cottages along the roads (%d)" % houses)
	# No road, driveway or track (terrain.road_a/b holds all of them) may cross a building footprint. The self-test
	# proves the checker is not vacuous: a segment laid through the first footprint must be flagged.
	if fps.size() > 0:
		var f0: Array = fps[0]
		var c0 := Vector2(float(f0[0]), float(f0[1]))
		check(_crossed_footprints(c0 - Vector2(40, 0), c0 + Vector2(40, 0), fps, 0.0).size() >= 1, "road/footprint checker flags a road laid through a building (self-test)")
	var crossings: Array = []
	for i in n:
		for fi in _crossed_footprints(terrain.road_a[i], terrain.road_b[i], fps, 1.0):
			crossings.append("road#%d %s>%s through %s" % [i, str(terrain.road_a[i]), str(terrain.road_b[i]), str(fps[fi])])
	for s in crossings:
		print("  crossing: ", s)
	check(crossings.is_empty(), "no road, driveway or track crosses a building footprint (%d crossings)" % crossings.size())
	var in_city_types := 0
	for t in ["hospital", "police_station", "church"]:
		for l in w1.get_locations(t):
			if HandLayout.in_city(l["pos2"]):
				in_city_types += 1
	check(in_city_types == 3, "hospital, police station and church stand in the city")
	check(not HandLayout.in_city(spawn, 20.0), "the player spawn is in the countryside, 20+ m outside the city")
	var spawn_in_building := false
	for f in fps:
		if absf(spawn.x - float(f[0])) < float(f[2]) * 0.5 + 3.0 and absf(spawn.y - float(f[1])) < float(f[3]) * 0.5 + 3.0:
			spawn_in_building = true
	check(not spawn_in_building, "nothing is built on the spawn")
	for i in 8:
		var sp: Vector3 = w1.get_spawn_point(i)
		check(not HandLayout.in_city(Vector2(sp.x, sp.z), 5.0), "spawn slot %d is outside the city" % i)
	var lamps: Node = w1.get_node_or_null("HandWorld/Collision")
	check(lamps != null and lamps.get_child_count() > 60, "hand world has collision (%d shapes)" % (lamps.get_child_count() if lamps != null else 0))

	# ---- houses beside roads
	var far_houses := 0
	for h in HandLayout.HOUSES:
		if terrain.road_distance(float(h[0]), float(h[1])) > 16.0:
			far_houses += 1
	check(far_houses == 0, "every cottage stands within 16 m of a road (%d farther)" % far_houses)

	# ---- vehicles stay on roads
	var veh: Node = w1.get_node_or_null("Vehicles")
	var off_road := 0
	var cars := 0
	if veh != null:
		for c in veh.get_children():
			cars += 1
			var p3: Vector3 = (c as Node3D).position
			if terrain.road_distance(p3.x, p3.z) > 4.5:
				off_road += 1
	check(cars >= 4 and cars <= 10, "drivable cars placed (%d)" % cars)
	check(off_road == 0, "every drivable car is within 4.5 m of a road (%d off)" % off_road)

	# ---- map texture
	var MapUI = load("res://scripts/ui/map_ui.gd")
	var tex: ImageTexture = MapUI.make_height_texture(w1, 64)
	check(tex != null and tex.get_width() == 64, "map texture builds from the hand world")

	# ---- determinism: a second world built with a different seed is identical
	w1.queue_free()
	await process_frame
	var w2: Node3D = _make(424242)
	for _i in 3:
		await physics_frame
	var sig2: String = _signature(w2)
	check(sig1 == sig2, "world is identical for seeds 1 and 424242 (%s vs %s)" % [sig1.substr(0, 8), sig2.substr(0, 8)])
	check(w2.world_seed == HandLayout.HAND_SEED, "world_seed is the fixed hand seed")

	print("RESULT failures=%d" % fails)
	quit(1 if fails > 0 else 0)
