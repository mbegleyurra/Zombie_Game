extends SceneTree
## Flat roads. Run:  xvfb-run -a godot --headless --path . --script res://tests/t_flatroads.gd
## The terrain is carved to a level road bed under every road (terrain.gd ROAD_FLAT / ROAD_BLEND) and the Kenney road
## tiles sit on it. Checks: (1) the layout is untouched - the signature equals the one recorded BEFORE the change and is
## identical across two builds; (2) across every road the ground is level; (3) along a road the height has no bumps
## (second difference of the centreline ~0); (4) the city grid is one single height; (5) the road tile mesh never dips
## below the ground and never floats; (6) two independent builds give the same heights.

const HandLayout = preload("res://tools/worldgen/hand_layout.gd")

## md5 of the layout (locations, every road segment, every flat pad, footprints, dungeon site, spawn, tile counts).
## Re-recorded when the two industrial plaza props (water tower, chimney) gained minimap footprints (47 -> 49); the
## roads, pads, locations and tile counts in it are unchanged.
## Re-recorded for the baked world: location yaw is hashed as (cos, sin) and footprint floats at 3 decimals, because the
## baked markers store yaw wrapped to -PI..PI and the meta as float32. The generator (tools/worldgen) and the baked
## scenes give the identical value under this form.
const LAYOUT_SIG := "fb27846aba8745b852f75e074a07a6c3"
const LAYOUT_ROADS := 86
const LAYOUT_FLATS := 40
const LAYOUT_FOOTPRINTS := 49

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


func _layout_sig(world: Node3D) -> String:
	var t = world.terrain
	var sig := PackedStringArray()
	for l in world.get_locations():
		var p2: Vector2 = l["pos2"]
		var rot := float(l["rot"])
		sig.append("%s|%s|%.2f,%.2f|%.3f,%.3f" % [l["type"], l["name"], p2.x, p2.y, snappedf(cos(rot), 0.001) + 0.0, snappedf(sin(rot), 0.001) + 0.0])
	for i in t.road_a.size():
		sig.append("R%s>%s" % [str(t.road_a[i]), str(t.road_b[i])])
	for i in t.flat_pos.size():
		sig.append("F%s|%.3f|%.3f" % [str(t.flat_pos[i]), t.flat_radius[i], t.flat_blend[i]])
	for f in world.get_meta("hand_footprints", []):
		var parts := PackedStringArray()
		for e in f:
			parts.append("%.3f" % e if (e is float or e is int) else str(e))
		sig.append("P" + ",".join(parts))
	sig.append(str(world.get_meta("dungeon_site", {}).get("origin", Vector2.ZERO)))
	sig.append(str(world.spawn_center))
	var ck: Dictionary = world.get_meta("citykit", {})
	var tiles: Dictionary = ck.get("tiles", {})
	var tile_keys: Array = tiles.keys()
	tile_keys.sort()   # the baked meta comes back with sorted keys; order is not layout
	var tile_parts := PackedStringArray()
	for k in tile_keys:
		tile_parts.append("%s=%s" % [str(k), str(tiles[k])])
	sig.append("tiles=%s junctions=%s" % [",".join(tile_parts), str(ck.get("junctions", -1))])
	return "\n".join(sig).md5_text()


func _height_sig(world: Node3D) -> String:
	var parts := PackedStringArray()
	var t = world.terrain
	for i in t.road_a.size():
		var a: Vector2 = t.road_a[i]
		var b: Vector2 = t.road_b[i]
		for k in 6:
			var p: Vector2 = a.lerp(b, float(k) / 5.0)
			parts.append("%.4f" % world.get_height(p.x, p.y))
	for gx in range(-240, 241, 40):
		for gz in range(-240, 241, 40):
			parts.append("%.4f" % world.get_height(float(gx), float(gz)))
	return "\n".join(parts).md5_text()


## True when another road's bed overlaps the one at p: any other segment within `hi` metres, except the parallel twin
## city track (same height by construction). Junction and driveway approaches are excluded from the level/grade checks,
## because a side road carries its own grade there.
func _foreign_road_in_band(t, p: Vector2, skip: int, lo: float, hi: float) -> bool:
	var own: Vector2 = t.road_b[skip] - t.road_a[skip]
	for j in t.road_a.size():
		if j == skip:
			continue
		var d: float = p.distance_to(Geometry2D.get_closest_point_to_segment(p, t.road_a[j], t.road_b[j]))
		var other: Vector2 = t.road_b[j] - t.road_a[j]
		var parallel: bool = absf(own.normalized().cross(other.normalized())) < 0.02
		if parallel and d <= lo:
			continue
		if d < hi:
			return true
	return false


func _run() -> void:
	var w1: Node3D = _make(1)
	var t = w1.terrain

	# 1. layout unchanged
	var sig1: String = _layout_sig(w1)
	check(t.road_a.size() == LAYOUT_ROADS, "road segment count unchanged (%d)" % t.road_a.size())
	check(t.flat_pos.size() == LAYOUT_FLATS, "flat pad count unchanged (%d)" % t.flat_pos.size())
	check(w1.get_meta("hand_footprints", []).size() == LAYOUT_FOOTPRINTS, "footprint count unchanged")
	check(sig1 == LAYOUT_SIG, "layout signature equals the pre-change signature (%s)" % sig1)

	# 2 + 3. level across, smooth along
	var reach: float = t.ROAD_FLAT + t.ROAD_BLEND
	var checked_cross := 0
	var worst_cross := 0.0
	var worst_cross_at := ""
	var checked_along := 0
	var worst_along := 0.0
	var worst_along_at := ""
	var worst_grade := 0.0
	var worst_grade_at := ""
	for i in t.road_a.size():
		var a: Vector2 = t.road_a[i]
		var b: Vector2 = t.road_b[i]
		var len: float = a.distance_to(b)
		if len < 34.0:
			continue
		var dir: Vector2 = (b - a) / len
		var side := Vector2(-dir.y, dir.x)
		var s := 12.0
		while s <= len - 12.0:
			var c: Vector2 = a + dir * s
			if not _foreign_road_in_band(t, c, i, 4.0, t.ROAD_FLAT * 2.0 + 1.5):
				var hc: float = w1.get_height(c.x, c.y)
				# Paved road + shoulder (ROAD_WIDTH 3.2 + ROAD_EDGE 1.1). The ground is the baked 1 m grid (the same grid
				# the generator's terrain mesh and collision used), so beyond ~4.8 m a cell can straddle the bed edge at
				# ROAD_FLAT 6.2 m; the generator's own collision ground already dropped 0.52 m at 6 m there.
				for off in [-4.5, -3.2, -1.6, 1.6, 3.2, 4.5]:
					var q: Vector2 = c + side * float(off)
					var dev: float = absf(w1.get_height(q.x, q.y) - hc)
					if dev > worst_cross:
						worst_cross = dev
						worst_cross_at = "seg %d %s>%s s=%.1f off=%.1f centre=%s" % [i, str(a), str(b), s, float(off), str(c)]
					checked_cross += 1
				var hm: float = w1.get_height(c.x - dir.x * 2.0, c.y - dir.y * 2.0)
				var hp: float = w1.get_height(c.x + dir.x * 2.0, c.y + dir.y * 2.0)
				if absf(hm - 2.0 * hc + hp) > worst_along:
					worst_along = absf(hm - 2.0 * hc + hp)
					worst_along_at = "seg %d %s>%s at %s" % [i, str(a), str(b), str(c)]
				if absf(hp - hm) / 4.0 > worst_grade:
					worst_grade = absf(hp - hm) / 4.0
					worst_grade_at = "seg %d %s>%s at %s" % [i, str(a), str(b), str(c)]
				checked_along += 1
			s += 3.0
	print("INFO  cross samples=%d worst lateral deviation=%.5f m at %s | along samples=%d worst second difference=%.5f m at %s, steepest grade=%.3f at %s" % [checked_cross, worst_cross, worst_cross_at, checked_along, worst_along, worst_along_at, worst_grade, worst_grade_at])
	check(checked_cross > 1500 and checked_along > 150, "enough clean road samples (%d across, %d along)" % [checked_cross, checked_along])
	check(worst_cross < 0.01, "ground is level across every road, +-4.5 m from the centreline (worst %.5f m)" % worst_cross)
	check(worst_along < 0.02, "no bumps along any road centreline (worst second difference %.5f m)" % worst_along)
	check(worst_grade < 0.35, "no road grade steeper than 35%% (steepest %.3f)" % worst_grade)

	# 4. the city street grid is one height
	var n := 0
	var mean := 0.0
	var hs := PackedFloat32Array()
	var city_low := Vector2.ZERO
	var city_low_h := 1.0e9
	for x in HandLayout.CITY_X:
		var z: float = HandLayout.CITY_Z[0]
		while z <= HandLayout.CITY_Z[HandLayout.CITY_Z.size() - 1]:
			hs.append(w1.get_height(float(x), z))
			if hs[hs.size() - 1] < city_low_h:
				city_low_h = hs[hs.size() - 1]
				city_low = Vector2(float(x), z)
			z += 2.0
	for z in HandLayout.CITY_Z:
		var x: float = HandLayout.CITY_X[0]
		while x <= HandLayout.CITY_X[HandLayout.CITY_X.size() - 1]:
			hs.append(w1.get_height(x, float(z)))
			if hs[hs.size() - 1] < city_low_h:
				city_low_h = hs[hs.size() - 1]
				city_low = Vector2(x, float(z))
			x += 2.0
	for h in hs:
		mean += h
		n += 1
	mean /= float(n)
	var variance := 0.0
	var hmax := -1.0e9
	var hmin := 1.0e9
	for h in hs:
		variance += (h - mean) * (h - mean)
		hmax = maxf(hmax, h)
		hmin = minf(hmin, h)
	variance /= float(n)
	print("INFO  city centrelines: %d samples, mean=%.4f variance=%.8f range=[%.4f, %.4f] lowest at %s" % [n, mean, variance, hmin, hmax, str(city_low)])
	check(variance < 0.0001 and hmax - hmin < 0.05, "city street grid centrelines are one flat height (variance %.8f)" % variance)

	# 5. the baked road tile meshes (one MeshInstance3D per segment / junction under "Roads") sit on the ground
	var roads: Node = w1.find_child("Roads", true, false)
	var vs := PackedVector3Array()
	if roads != null:
		for piece in roads.get_children():
			var mi := piece as MeshInstance3D
			if mi != null and mi.mesh != null and mi.mesh.get_surface_count() > 0:
				for v in (mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
					vs.append(mi.global_transform * v)
	check(not vs.is_empty(), "road tile meshes exist (%d pieces)" % (roads.get_child_count() if roads else 0))
	if not vs.is_empty():
		var below := 0
		var high := 0
		var lo := 1.0e9
		var hi := -1.0e9
		for v in vs:
			var rel: float = v.y - w1.get_height(v.x, v.z)
			lo = minf(lo, rel)
			hi = maxf(hi, rel)
			if rel < 0.04:
				below += 1
			if rel > 0.6:
				high += 1
		print("INFO  road mesh: %d vertices, height above ground in [%.4f, %.4f]" % [vs.size(), lo, hi])
		check(vs.size() > 1000, "road mesh has vertices (%d)" % vs.size())
		check(below == 0, "no road tile vertex is under or in the ground (%d)" % below)
		check(high == 0, "no road tile floats above the ground (%d)" % high)

	# 5b. location driveways: the stretch from the gate to the farm side is level and no farm floor or fence is raised
	# (Hartley Farm's gate end used the city pad's 2.0 m instead of its own -6.15 m: an 8 m drop over 10 m)
	var worst_drive := 0.0
	var worst_drive_at := ""
	var worst_floor := 0.0
	var worst_floor_at := ""
	var hartley_gate_h := NAN
	var hartley_pad_h := NAN
	var drives := 0
	for l in w1.get_locations():
		var p2: Vector2 = l["pos2"]
		if HandLayout.in_city(p2):
			continue
		var rot: float = float(l["rot"])
		var dir := Vector2(sin(rot), cos(rot))
		var pad_h := NAN
		for k in t.flat_pos.size():
			if (t.flat_pos[k] as Vector2).is_equal_approx(p2):
				pad_h = t.flat_height[k]
				break
		if is_nan(pad_h):
			continue
		drives += 1
		var s := 0.0
		while s <= 10.0:
			var q: Vector2 = p2 + dir * (HandLayout.GATE_DIST - s)
			var dh: float = absf(w1.get_height(q.x, q.y) - pad_h)
			if dh > worst_drive:
				worst_drive = dh
				worst_drive_at = "%s driveway %.0f m from the gate (height %.2f, pad %.2f)" % [str(l["name"]), s, w1.get_height(q.x, q.y), pad_h]
			s += 1.0
		if str(l["name"]) == "Hartley Farm":
			var g: Vector2 = p2 + dir * HandLayout.GATE_DIST
			hartley_gate_h = w1.get_height(g.x, g.y)
			hartley_pad_h = pad_h
		if str(l["type"]) == "farm":
			# fence rectangle (local x -19..19, z -15..17) plus the yard inside it: the ground never rises above the floor
			var cr: float = cos(rot)
			var sr: float = sin(rot)
			for lx in range(-19, 20, 4):
				for lz in range(-15, 18, 4):
					var on_fence: bool = lx == -19 or lx == 19 or lz == -15 or lz == 17
					var fx: float = float(lx)
					var fz: float = float(lz)
					var wp := Vector2(p2.x + fx * cr + fz * sr, p2.y - fx * sr + fz * cr)
					var rise: float = w1.get_height(wp.x, wp.y) - pad_h
					if rise > worst_floor:
						worst_floor = rise
						worst_floor_at = "%s %s at local (%d,%d) rises %.2f m%s" % [str(l["name"]), str(wp), lx, lz, rise, " (fence)" if on_fence else ""]
	print("INFO  driveways: %d locations, worst gate-to-farm deviation %.3f m (%s); worst farm floor rise %.3f m (%s)" % [drives, worst_drive, worst_drive_at, worst_floor, worst_floor_at])
	check(drives >= 6, "driveways of the countryside locations were checked (%d)" % drives)
	check(not is_nan(hartley_gate_h) and absf(hartley_gate_h - hartley_pad_h) < 0.3 and hartley_gate_h < -5.0, "Hartley Farm gate stands at its own pad height %.2f m, not the city's 2.0 m (gate %.2f)" % [hartley_pad_h, hartley_gate_h])
	check(worst_drive < 0.5, "every driveway is level or a gentle slope (<5%%) between its gate and the site (worst %.3f m over 10 m)" % worst_drive)
	check(worst_floor < 0.5, "no road bed raises a farm floor or fence line (worst rise %.3f m)" % worst_floor)

	# 6. determinism: a second world (other seed) is identical
	var w2: Node3D = _make(424242)
	check(_layout_sig(w2) == sig1, "second build has the identical layout signature")
	check(_height_sig(w2) == _height_sig(w1), "second build has identical heights along roads and across the map")

	print("RESULT  fails=%d" % fails)
	quit(1 if fails > 0 else 0)
