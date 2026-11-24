extends SceneTree
## QA gate (RAT): independent checks of the handcrafted world, separate from t_handworld.gd.
##   godot --headless --path . --script res://tests/t_qa_world.gd -- <seed> <signature-out-file>
## Run it in several PROCESSES (different seeds) and diff the signature files: the layout must be byte-identical.
## Geometry is recomputed here from HandLayout's raw data and the built world, not copied from t_handworld.

const HandLayout = preload("res://tools/worldgen/hand_layout.gd")

var fails := 0


func check(cond: bool, label: String) -> void:
	if cond:
		print("PASS  ", label)
	else:
		fails += 1
		print("FAIL  ", label)


func _initialize() -> void:
	_run.call_deferred()


## Is p inside the (x, z, w, d, yaw) rectangle grown by margin?
func _in_rect(p: Vector2, f: Array, margin: float) -> bool:
	var d: Vector2 = p - Vector2(float(f[0]), float(f[1]))
	var yaw: float = float(f[4])
	var c := cos(yaw)
	var s := sin(yaw)
	var lx: float = d.x * c - d.y * s
	var lz: float = d.x * s + d.y * c
	return absf(lx) <= float(f[2]) * 0.5 + margin and absf(lz) <= float(f[3]) * 0.5 + margin


func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	return p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b))


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var seed_value: int = int(args[0]) if args.size() > 0 else 1
	var out_path: String = args[1] if args.size() > 1 else ""
	var world: Node3D = (load("res://scenes/world/world.tscn") as PackedScene).instantiate()
	root.add_child(world)
	world.build(seed_value)
	for _i in 6:
		await physics_frame
	var terrain = world.terrain
	var spawn: Vector2 = world.spawn_center
	var fps: Array = world.get_meta("hand_footprints", []) as Array

	# ---- signature for cross-process comparison (no seed-derived or time-derived text)
	var sig := PackedStringArray()
	sig.append("spawn %s" % str(spawn))
	for l in world.get_locations():
		sig.append("L %s %s %s %s" % [l["type"], l["name"], str(l["pos"]), str(l["rot"])])
	for i in terrain.road_a.size():
		sig.append("R %s %s" % [str(terrain.road_a[i]), str(terrain.road_b[i])])
	for f in fps:
		sig.append("F %s" % str(f))
	var veh: Node = world.get_node_or_null("Vehicles")
	if veh != null:
		for c in veh.get_children():
			sig.append("V %s %s" % [c.name, str((c as Node3D).position)])
	for i in 8:
		sig.append("S %s" % str(world.get_spawn_point(i)))
	for ix in range(-200, 201, 20):
		for iz in range(-200, 201, 20):
			sig.append("H %d %d %.3f" % [ix, iz, world.get_height(float(ix), float(iz))])
	var ids: Array = world.loot_by_id.keys()
	ids.sort()
	for id in ids:
		var n = world.loot_by_id[id]
		if is_instance_valid(n):
			sig.append("O %s %s" % [str(id), str((n as Node3D).global_position)])
	if out_path != "":
		var fh := FileAccess.open(out_path, FileAccess.WRITE)
		fh.store_string("\n".join(sig))
		fh.close()
	print("signature: %d lines, md5 %s" % [sig.size(), "\n".join(sig).md5_text()])

	# ---- the drawn roads are exactly the layout's roads
	var layout_segs: Array = HandLayout.road_segments()
	var segs: Array = []   # the roads the world really has: layout plus the driveways / dungeon track world_builder adds
	for i in terrain.road_a.size():
		segs.append([terrain.road_a[i], terrain.road_b[i]])
	var missing := 0
	for ls in layout_segs:
		var found := false
		for s2 in segs:
			if (s2[0] as Vector2).is_equal_approx(ls[0]) and (s2[1] as Vector2).is_equal_approx(ls[1]):
				found = true
				break
		if not found:
			missing += 1
	check(missing == 0 and segs.size() >= layout_segs.size(), "terrain has every layout segment (%d missing; %d total, %d from layout)" % [missing, segs.size(), layout_segs.size()])

	# ---- roads are not a star: degree histogram and share of countryside segments meeting at one point
	var deg := {}
	for sgm in segs:
		for p in sgm:
			var k := Vector2i(roundi(p.x), roundi(p.y))
			deg[k] = int(deg.get(k, 0)) + 1
	var worst := 0
	var worst_k := Vector2i.ZERO
	for k in deg:
		if HandLayout.in_city(Vector2(k.x, k.y), 3.0):
			continue
		if int(deg[k]) > worst:
			worst = int(deg[k])
			worst_k = k
	var country_n := 0
	for r in HandLayout.COUNTRY_ROADS:
		country_n += maxi((r[1] as Array).size() - 1, 0)
	print("  countryside: %d segments, busiest outside-city vertex %s degree %d" % [country_n, str(worst_k), worst])
	check(worst <= 4, "no countryside vertex has more than 4 road ends (%d)" % worst)
	var near_hub := 0
	for sgm in segs:
		if HandLayout.in_city(sgm[0], 3.0) or HandLayout.in_city(sgm[1], 3.0):
			continue
		var hub := Vector2(worst_k.x, worst_k.y)
		if (sgm[0] as Vector2).distance_to(hub) < 12.0 or (sgm[1] as Vector2).distance_to(hub) < 12.0:
			near_hub += 1
	check(near_hub * 3 <= country_n, "no more than a third of countryside segments cluster within 12 m of one point (%d of %d)" % [near_hub, country_n])
	# roads span several directions: bearing of every country segment spread across >= 3 of 4 quadrants of orientation
	var bins := {}
	for r in HandLayout.COUNTRY_ROADS:
		var pts: Array = r[1]
		for i in range(pts.size() - 1):
			var d: Vector2 = (pts[i + 1] as Vector2) - (pts[i] as Vector2)
			if d.length() > 5.0:
				bins[int(floorf(fposmod(atan2(d.y, d.x), PI) / (PI / 4.0)))] = true
	check(bins.size() >= 3, "country roads run in at least 3 of 4 orientation bins (%d)" % bins.size())

	# ---- city
	var towers: Array = []
	for f in fps:
		if str(f[5]) == "tower":
			towers.append(f)
	var inside := 0
	for t in towers:
		if HandLayout.in_city(Vector2(float(t[0]), float(t[1]))):
			inside += 1
	check(towers.size() >= 20 and inside == towers.size(), "all %d towers are inside the city box (%d inside)" % [towers.size(), inside])
	var dens := 0
	for t in towers:
		for u in towers:
			if t != u and Vector2(float(t[0]), float(t[1])).distance_to(Vector2(float(u[0]), float(u[1]))) < 25.0:
				dens += 1
				break
	check(dens >= towers.size() - 2, "towers are clustered (%d of %d have a neighbour within 25 m)" % [dens, towers.size()])
	check(spawn.distance_to(HandLayout.CITY_CENTER) > 100.0 and not HandLayout.in_city(spawn, 20.0), "spawn %s is 20+ m outside the city, %.0f m from its centre" % [str(spawn), spawn.distance_to(HandLayout.CITY_CENTER)])
	for i in 8:
		var sp: Vector3 = world.get_spawn_point(i)
		var p2 := Vector2(sp.x, sp.z)
		var in_b := false
		for f in fps:
			if _in_rect(p2, f, 2.0):
				in_b = true
		check(not HandLayout.in_city(p2, 5.0) and not in_b, "spawn slot %d %s is outside the city and every hand building" % [i, str(sp)])
		check(absf(sp.y - world.get_height(sp.x, sp.z)) < 3.0, "spawn slot %d height is near the terrain (%.2f vs %.2f)" % [i, sp.y, world.get_height(sp.x, sp.z)])
		# nothing solid in the capsule volume at the spawn
		var space := world.get_world_3d().direct_space_state
		var q := PhysicsShapeQueryParameters3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = 0.4
		cap.height = 1.6
		q.shape = cap
		q.transform = Transform3D(Basis(), sp + Vector3(0, 1.3, 0))
		var hits := space.intersect_shape(q, 4)
		var solid := 0
		for h in hits:
			var col: Object = h["collider"]
			if col is StaticBody3D and not (col as Node).is_in_group("terrain"):
				solid += 1
		check(solid == 0, "spawn slot %d capsule is clear of static colliders (%d)" % [i, solid])

	# ---- reachability: graph of segments, independent union-find, 2.5 m joint tolerance
	var n: int = segs.size()
	var parent := PackedInt32Array()
	for i in n:
		parent.append(i)
	var find := func(i: int) -> int:
		var r := i
		while parent[r] != r:
			r = parent[r]
		return r
	for i in n:
		for j in range(i + 1, n):
			var a: Array = segs[i]
			var b: Array = segs[j]
			var touch := false
			for p in a:
				if _seg_dist(p, b[0], b[1]) <= 2.5:
					touch = true
			for p in b:
				if _seg_dist(p, a[0], a[1]) <= 2.5:
					touch = true
			if touch:
				var ri: int = find.call(i)
				var rj: int = find.call(j)
				if ri != rj:
					parent[ri] = rj
	var sroot := -1
	var best := 1e9
	for i in n:
		var dd: float = _seg_dist(spawn, segs[i][0], segs[i][1])
		if dd < best:
			best = dd
			sroot = find.call(i)
	check(best < 6.0, "spawn is within 6 m of a road (%.1f m)" % best)
	var comps := {}
	for i in n:
		comps[find.call(i)] = true
	check(comps.size() == 1, "all roads form ONE connected network (%d components)" % comps.size())
	var reach := func(p: Vector2, tol: float) -> bool:
		for i in n:
			if int(find.call(i)) == sroot and _seg_dist(p, segs[i][0], segs[i][1]) <= tol:
				return true
		return false
	var city_ok := false
	for i in n:
		if int(find.call(i)) == sroot and HandLayout.in_city(segs[i][0], 1.0):
			city_ok = true
	check(city_ok, "city streets are in the spawn's road component")
	var bad := 0
	for l in world.get_locations():
		if not bool(reach.call(l["pos2"], float(l["radius"]) + 2.5)):
			bad += 1
			print("  unreached location: ", l["name"], " ", l["pos2"])
	check(bad == 0, "every location touches the spawn component (%d unreached)" % bad)
	var tower_blocked := 0
	for i in n:
		for t in towers:
			var a2: Vector2 = segs[i][0]
			var b2: Vector2 = segs[i][1]
			var steps: int = maxi(int(a2.distance_to(b2) / 0.25), 1)   # 0.25 m, finer than any tower (9 samples missed 2 of 3 towers on a 130 m segment)
			for k in steps + 1:
				if _in_rect(a2.lerp(b2, float(k) / float(steps)), t, 0.0):
					tower_blocked += 1
					print("  road %s -> %s crosses tower %s" % [str(a2), str(b2), str(t)])
					break
	check(tower_blocked == 0, "no road segment runs through a tower (%d do)" % tower_blocked)

	# ---- vehicles: on roads, not in buildings, standing on the ground
	var cars: Array = []
	if veh != null:
		for c in veh.get_children():
			cars.append(c)
	print("  drivable vehicles: %d" % cars.size())
	check(cars.size() >= 4, "at least 4 drivable vehicles (%d)" % cars.size())
	for c in cars:
		var p: Vector3 = (c as Node3D).position
		var p2 := Vector2(p.x, p.z)
		var rd: float = 1e9
		var onreach := false
		for i in n:
			var dd: float = _seg_dist(p2, segs[i][0], segs[i][1])
			rd = minf(rd, dd)
			if dd <= 4.5 and int(find.call(i)) == sroot:
				onreach = true
		var inb := false
		for f in fps:
			if _in_rect(p2, f, 1.0):
				inb = true
		check(onreach and not inb, "vehicle %s at %s: road dist %.1f m, connected to spawn, not inside a building" % [c.name, str(p2), rd])
		check(absf(p.y - world.get_height(p.x, p.z)) < 2.5, "vehicle %s rests near the terrain (%.2f vs %.2f)" % [c.name, p.y, world.get_height(p.x, p.z)])
	# static city wrecks are on streets too
	var wreck_bad := 0
	for c in HandLayout.CITY_CARS:
		var p2 := Vector2(float(c[0]), float(c[1]))
		var rd := 1e9
		for sgm in segs:
			rd = minf(rd, _seg_dist(p2, sgm[0], sgm[1]))
		if rd > 6.0:
			wreck_bad += 1
	check(wreck_bad == 0, "city wrecks sit on streets (%d off)" % wreck_bad)

	# ---- loot not buried in towers / roads not blocked by loot colliders
	var buried := 0
	for id in world.loot_by_id:
		var nd = world.loot_by_id[id]
		if not is_instance_valid(nd):
			continue
		var p3: Vector3 = (nd as Node3D).global_position
		for t in towers:
			if _in_rect(Vector2(p3.x, p3.z), t, 0.0):
				buried += 1
				print("  loot inside tower: ", nd.name)
	check(buried == 0, "no loot item is inside a tower (%d)" % buried)

	print("RESULT fails=%d" % fails)
	quit(1 if fails > 0 else 0)
