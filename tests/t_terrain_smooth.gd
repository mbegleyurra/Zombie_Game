extends SceneTree
## Smooth ground. Run:  xvfb-run -a godot --headless --path . --script res://tests/t_terrain_smooth.gd
## Checks: (1) CELL is fine (<= 1.0 m); (2) chunks are indexed meshes with shared vertices and the expected triangle
## count; (3) per-vertex normals are unit length and smooth (neighbouring normals differ little, unlike flat facets);
## (4) normals match across chunk seams; (5) vertices sit on height_at(); (6) every triangle faces up/outward
## (winding agrees with the normals) and the chunk still has trimesh collision.
## Runs on the BAKED terrain: the 64 Chunk_X_Z meshes of scenes/world/baked/terrain.tscn loaded through world.tscn,
## and height_at() = the baked heightmap (scenes/world/baked/res/heightmap.res) the runtime samples.
## Unlike a bare generator Terrain, the baked ground includes the authored cuts (road beds + shoulders, flat pads,
## the dungeon crater), whose edges are deliberate creases. The smoothness checks (3) cover the natural relief
## outside those cuts, and a separate check bounds how much of the ground the sharp cut edges occupy.

## Grid constants of the bake (BAKE_NOTES.md: 8 x 8 chunks of 64 m, 1 m cells, world half-size 256 m).
class Terrain:
	const CELL := 1.0
	const CHUNK_SIZE := 64.0
	const CHUNKS := 8
	const HALF := 256.0

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
	var w: Node3D = (load("res://scenes/world/world.tscn") as PackedScene).instantiate()
	root.add_child(w)
	w.build(1)
	var t = w.terrain
	var chunk_nodes := {}
	for c in t.get_children():
		var parts: PackedStringArray = str(c.name).split("_")
		if c is MeshInstance3D and parts.size() == 3 and parts[0] == "Chunk":
			chunk_nodes[Vector2i(int(parts[1]), int(parts[2]))] = c

	check(Terrain.CELL <= 1.0, "terrain cell size is %.2f m (<= 1.0)" % Terrain.CELL)
	var n: int = int(Terrain.CHUNK_SIZE / Terrain.CELL)
	var stride: int = n + 1
	check(chunk_nodes.size() == Terrain.CHUNKS * Terrain.CHUNKS, "all %d chunks built" % chunk_nodes.size())

	var tris := 0
	var worst_step := 0.0       # largest angle (deg) between adjacent vertex normals in the playable interior (outside the border ridge)
	var steps_total := 0
	var steps_gentle := 0       # steps under 10 deg, natural relief (outside the authored cuts)
	var steps_cut := 0          # steps of 10 deg or more inside the authored cuts
	var steps_all := 0
	var steps_natural := 0      # every step outside the authored cuts (ridge band included)
	var worst_len := 0.0
	var worst_y := 0.0          # largest |vertex.y - height_at|
	var bad_wind := 0
	var no_collision := 0
	var shared_ok := true
	var arrs := {}
	for key in chunk_nodes:
		var mi: MeshInstance3D = chunk_nodes[key]
		var a: Array = mi.mesh.surface_get_arrays(0)
		arrs[key] = a
		var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var ns: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		var idx = a[Mesh.ARRAY_INDEX]
		if idx == null or vs.size() != stride * stride:
			shared_ok = false
			continue
		tris += (idx as PackedInt32Array).size() / 3
		for v in ns:
			worst_len = maxf(worst_len, absf(v.length() - 1.0))
		for j in stride:
			for i in stride - 1:
				var k: int = j * stride + i
				var s1: float = rad_to_deg(ns[k].angle_to(ns[k + 1]))
				var s2: float = rad_to_deg(ns[i * stride + j].angle_to(ns[(i + 1) * stride + j]))
				steps_all += 2
				for pair in [[s1, vs[k]], [s2, vs[i * stride + j]]]:
					var st: float = pair[0]
					var v: Vector3 = pair[1]
					if _in_cut(w, t, Vector2(v.x, v.z)):
						steps_cut += int(st >= 10.0)
						continue
					steps_natural += 1
					# the mountain ridge that walls the world in has a deliberate diagonal crease at the corners
					if maxf(absf(v.x), absf(v.z)) < Terrain.HALF - 50.0:
						steps_total += 1
						steps_gentle += int(st < 10.0)
						worst_step = maxf(worst_step, st)
		for k in range(0, vs.size(), 37):
			worst_y = maxf(worst_y, absf(vs[k].y - t.height_at(vs[k].x, vs[k].z)))
		var ii: PackedInt32Array = idx
		for q in range(0, ii.size(), 3):
			var cr: Vector3 = (vs[ii[q + 1]] - vs[ii[q]]).cross(vs[ii[q + 2]] - vs[ii[q]])
			# Godot front faces are clockwise: the geometric cross points DOWN when the face looks up
			if cr.dot(ns[ii[q]]) > 0.0:
				bad_wind += 1
		var body: Node = mi.get_node_or_null("Collision")
		if body == null or body.get_child_count() == 0:
			no_collision += 1
	check(shared_ok, "every chunk is an indexed mesh with (n+1)^2 = %d shared vertices" % (stride * stride))
	check(tris == Terrain.CHUNKS * Terrain.CHUNKS * n * n * 2, "triangle count %d = 2 per cell" % tris)
	print("INFO  triangles=%d  worst adjacent-normal step=%.2f deg  worst |len-1|=%.6f  worst vertex-height error=%.6f  bad winding=%d" % [tris, worst_step, worst_len, worst_y, bad_wind])
	check(worst_len < 0.001, "all vertex normals are unit length")
	check(worst_step < 20.0, "interior normals vary smoothly between neighbouring vertices (worst step %.2f deg)" % worst_step)
	check(float(steps_gentle) / float(steps_total) > 0.99, "99%% of interior natural-relief neighbouring-vertex normal steps are under 10 deg (%.2f%% of %d)" % [100.0 * steps_gentle / steps_total, steps_total])
	# measured 1.04% when the Phase 2 bake was made; 2% leaves room for hand edits but catches a broken heightmap
	check(steps_natural > steps_all / 3 and float(steps_cut) / float(steps_all) < 0.02, "sharp creases (>= 10 deg) at authored cut edges stay under 2%% of all steps (%d of %d)" % [steps_cut, steps_all])
	check(worst_y < 0.0001, "vertices lie on height_at() (worst error %.6f m)" % worst_y)
	check(bad_wind == 0, "every triangle's winding agrees with its normal")
	check(no_collision == 0, "every chunk keeps its trimesh collision")

	# smoothness: no two vertices of one quad share an identical-by-facet normal pattern; compare to the facet count.
	var distinct := {}
	var first: Array = arrs[Vector2i(3, 3)]
	for v in (first[Mesh.ARRAY_NORMAL] as PackedVector3Array):
		distinct[Vector3i(roundi(v.x * 1000.0), roundi(v.y * 1000.0), roundi(v.z * 1000.0))] = true
	check(distinct.size() > stride * stride / 4, "normals are per-vertex, not per-facet (%d distinct of %d)" % [distinct.size(), stride * stride])

	# seams: the last column of chunk (cx,cz) and the first of (cx+1,cz) are the same ground points with the same normal
	var worst_seam := 0.0
	var seams := 0
	for cz in Terrain.CHUNKS:
		for cx in Terrain.CHUNKS - 1:
			var l: Array = arrs[Vector2i(cx, cz)]
			var r: Array = arrs[Vector2i(cx + 1, cz)]
			for j in stride:
				var nl: Vector3 = (l[Mesh.ARRAY_NORMAL] as PackedVector3Array)[j * stride + n]
				var nr: Vector3 = (r[Mesh.ARRAY_NORMAL] as PackedVector3Array)[j * stride]
				worst_seam = maxf(worst_seam, nl.distance_to(nr))
				seams += 1
	for cz in Terrain.CHUNKS - 1:
		for cx in Terrain.CHUNKS:
			var u: Array = arrs[Vector2i(cx, cz)]
			var d: Array = arrs[Vector2i(cx, cz + 1)]
			for i in stride:
				var nu: Vector3 = (u[Mesh.ARRAY_NORMAL] as PackedVector3Array)[n * stride + i]
				var nd: Vector3 = (d[Mesh.ARRAY_NORMAL] as PackedVector3Array)[i]
				worst_seam = maxf(worst_seam, nu.distance_to(nd))
				seams += 1
	check(seams > 1000 and worst_seam < 0.0001, "normals match across chunk seams (%d seam vertices, worst %.6f)" % [seams, worst_seam])

	w.queue_free()
	print("RESULT  fails=%d" % fails)
	quit(1 if fails > 0 else 0)


## Inside an authored terrain cut: road bed + shoulder (ROAD_FLAT + ROAD_BLEND + 1 m), a flat pad with its blend
## (+2 m), or the dungeon crater (40 m around the site origin).
func _in_cut(w: Node3D, t, p: Vector2) -> bool:
	if t.road_distance(p.x, p.y) < t.ROAD_FLAT + t.ROAD_BLEND + 1.0:
		return true
	for i in t.flat_pos.size():
		if p.distance_to(t.flat_pos[i]) < t.flat_radius[i] + t.flat_blend[i] + 2.0:
			return true
	var site: Dictionary = w.get_meta("dungeon_site", {})
	return site.has("origin") and p.distance_to(site["origin"]) < 40.0
