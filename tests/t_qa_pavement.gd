extends SceneTree
## QA gate 3: the downtown pavement strips (road kit tile-low, scale 12, city_kit.gd _frontage) must not overlap any road
## tile, and the suburban driveway-short strips (scale 10) must not either. Measures the real mesh bounds of every strip
## against the baked road mesh. Run:  xvfb-run -a godot --headless --path . --script res://tests/t_qa_pavement.gd
## Known failing at gate 3 (strips reach 4.3 m into the street); owner PLAGUEMASTER.

var fails := 0


func check(cond: bool, label: String) -> void:
	if cond:
		print("PASS  ", label)
	else:
		fails += 1
		print("FAIL  ", label)


func _initialize() -> void:
	_run.call_deferred()


func _mesh_aabbs(n: Node, out: Array) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var mi := n as MeshInstance3D
		out.append(mi.global_transform * mi.mesh.get_aabb())
	for c in n.get_children():
		_mesh_aabbs(c, out)


func _run() -> void:
	var world: Node3D = (load("res://scenes/world/world.tscn") as PackedScene).instantiate()
	root.add_child(world)
	world.build(1)
	for _i in 3:
		await physics_frame
	# Roads is one MeshInstance3D per segment / junction; gather every triangle vertex in world space.
	var roads: Node = world.find_child("Roads", true, false)
	var vs := PackedVector3Array()
	var ids := PackedInt32Array()
	for piece in roads.get_children():
		var mi := piece as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var arr: Array = mi.mesh.surface_get_arrays(0)
		var base: int = vs.size()
		for v in (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array):
			vs.append(mi.global_transform * v)
		for i in (arr[Mesh.ARRAY_INDEX] as PackedInt32Array):
			ids.append(base + i)
	check(ids.size() > 0, "road pieces have triangles (%d pieces)" % roads.get_child_count())
	for pat in ["*tile-low*", "*driveway-short*"]:
		var strips := world.find_children(pat, "Node3D", true, false)
		check(strips.size() >= 8, "%s strips placed (%d)" % [pat, strips.size()])
		var bad := 0
		var worst := 0.0
		for nd in strips:
			var bbs: Array = []
			_mesh_aabbs(nd, bbs)
			var r: AABB = bbs[0]
			for b in bbs:
				r = r.merge(b)
			var rect := Rect2(r.position.x, r.position.z, r.size.x, r.size.z)
			var inner := rect.grow(-0.05)
			var depth := 0.0
			for t in range(0, ids.size(), 3):
				for k in 3:
					var v: Vector3 = vs[ids[t + k]]
					if inner.has_point(Vector2(v.x, v.z)):
						depth = maxf(depth, minf(minf(v.x - rect.position.x, rect.end.x - v.x), minf(v.z - rect.position.y, rect.end.y - v.z)))
			if depth > 0.0:
				bad += 1
				worst = maxf(worst, depth)
		check(bad == 0, "%s: no strip overlaps a road tile (%d of %d overlap, worst %.2f m deep)" % [pat, bad, strips.size(), worst])
	print("RESULT  fails=%d" % fails)
	quit(1 if fails > 0 else 0)
