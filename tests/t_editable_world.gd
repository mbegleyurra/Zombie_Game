extends SceneTree
## Hand-editable world. Run:  godot --headless --path . --script res://tests/t_editable_world.gd
## (1) no MultiMeshInstance3D in any scene under scenes/world (file text and the loaded world_baked.tscn);
## (2) every tree / bush / rock / grass tuft is its own node (2450) under per-type groups, roads are per-piece nodes;
## (3) moving one tree node (as the editor would) moves its collider, its map dot and its spawn-blocking footprint;
##     deleting / adding a node is reflected by forest_data.

const ForestData = preload("res://scripts/world/forest_data.gd")
const MapUI = preload("res://scripts/ui/map_ui.gd")
const KR = preload("res://scripts/world/kaykit_resources.gd")

var fails := 0


func check(cond: bool, label: String) -> void:
	if cond:
		print("PASS  ", label)
	else:
		fails += 1
		print("FAIL  ", label)


func _initialize() -> void:
	_run.call_deferred()


func _tscn_files(dir: String, out: Array) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".tscn"):
			out.append(dir.path_join(f))
	for sd in d.get_directories():
		_tscn_files(dir.path_join(sd), out)


func _tree_pixel(img: Image, half: float, cell: float, p: Vector2) -> bool:
	var x := int((p.x + half) / cell - 0.5 + 0.5)
	var y := int((p.y + half) / cell - 0.5 + 0.5)
	var c: Color = img.get_pixel(clampi(x, 0, img.get_width() - 1), clampi(y, 0, img.get_height() - 1))
	var near := func(a: Color, b: Color) -> bool: return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) < 0.02
	return c.a > 0.5 and (near.call(c, MapUI.TREE_COL) or near.call(c, MapUI.TREE_HI))


func _map(w: Node) -> Image:
	var img := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	MapUI._stamp_vegetation(img, w, 256, 256.0, 2.0)
	return img


func _solid_at(p: Vector3) -> Array:
	var q := PhysicsPointQueryParameters3D.new()
	q.position = p
	q.collide_with_areas = false
	var hits: Array = []
	for h in root.get_world_3d().direct_space_state.intersect_point(q, 8):
		hits.append(h["collider"])
	return hits


func _run() -> void:
	# ---- (1) no MultiMesh anywhere in scenes/world
	var files: Array = []
	_tscn_files("res://scenes/world", files)
	var mm_files: Array = []
	for f in files:
		if FileAccess.get_file_as_string(f).contains("MultiMesh"):
			mm_files.append(f)
	check(files.size() > 40 and mm_files.is_empty(), "no MultiMesh in %d scenes under scenes/world (%s)" % [files.size(), str(mm_files)])
	var baked: Node = (load("res://scenes/world/world_baked.tscn") as PackedScene).instantiate()
	check(baked.find_children("*", "MultiMeshInstance3D", true, false).is_empty(), "world_baked.tscn: 0 MultiMeshInstance3D")

	# ---- (2) individual nodes
	var bforest: Node = baked.get_node("Vegetation/KayKitForest")
	var bveg: Array = ForestData.nodes(bforest)
	check(bveg.size() == 2450, "world_baked.tscn: 2450 individual vegetation nodes (%d)" % bveg.size())
	var per := {}
	for g in ["Trees", "Bushes", "Rocks", "Grass"]:
		per[g] = bforest.get_node(g).get_child_count()
	check(int(per["Trees"]) == 520 and int(per["Bushes"]) == 260 and int(per["Rocks"]) == 170 and int(per["Grass"]) == 1500,
		"per-type groups Trees/Bushes/Rocks/Grass %s" % str(per))
	var inst_ok := 0
	for n in bveg:
		if str(n.scene_file_path).begins_with("res://scenes/world/props/vegetation/") and String(n.name).contains("_0"):
			inst_ok += 1
	check(inst_ok == 2450, "each is a named prop-scene instance, e.g. %s (%d)" % [bforest.get_node("Trees").get_child(0).name, inst_ok])
	var roads: Node = baked.get_node("Roads/Roads")
	check(roads.get_child_count() > 50 and roads.get_child(0) is MeshInstance3D, "roads split into %d per-piece nodes" % roads.get_child_count())
	baked.free()

	# ---- (3) edit the live world like the editor would
	var w: Node3D = (load("res://scenes/world/world.tscn") as PackedScene).instantiate()
	root.add_child(w)
	w.build(1)
	for _i in 3:
		await physics_frame
	var forest: Node = w.get_node("KayKitForest")
	var veg: Array = ForestData.nodes(forest)
	# a tree with no other blocking object within 6 m, moved to a spot with nothing within 10 m
	var tree: Node3D = null
	for n in veg:
		if str(n.get_meta("kind")) != "tree":
			continue
		var p: Vector3 = (n as Node3D).global_position
		var lonely := true
		for o in veg:
			if o != n and str(o.get_meta("kind")) in ["tree", "rock"] and (o as Node3D).global_position.distance_to(p) < 6.0:
				lonely = false
				break
		if lonely:
			tree = n
			break
	check(tree != null, "found a free-standing tree")
	var old: Vector3 = tree.global_position
	var target := Vector3.INF
	for gx in range(-200, 201, 20):
		for gz in range(-200, 201, 20):
			var cand := Vector2(float(gx), float(gz))
			var clear := true
			for o in veg:
				var op: Vector3 = (o as Node3D).global_position
				if Vector2(op.x, op.z).distance_to(cand) < 10.0:
					clear = false
					break
			if clear and not KR.blocked_by_dressing(w, cand, 3.0) and _solid_at(Vector3(cand.x, w.get_height(cand.x, cand.y) + 1.0, cand.y)).is_empty():
				target = Vector3(cand.x, w.get_height(cand.x, cand.y), cand.y)
				break
		if target != Vector3.INF:
			break
	check(target != Vector3.INF, "found an empty spot to move it to %s" % str(target))
	var body: Node = tree.get_node("Body")
	var img0 := _map(w)
	check(_tree_pixel(img0, 256.0, 2.0, Vector2(old.x, old.z)), "map: dot at the tree's original position")
	check(_solid_at(old + Vector3(0, 1, 0)).has(body), "collision: tree's own collider at the original position")

	tree.global_position = target   # the editor move
	for _i in 3:
		await physics_frame
	var found := false
	for s in ForestData.sites(forest):
		if s[0] == "tree" and Vector2(s[1], s[2]).distance_to(Vector2(target.x, target.z)) < 0.01:
			found = true
	check(found, "forest_data: sees the tree at its new position")
	var img1 := _map(w)
	check(_tree_pixel(img1, 256.0, 2.0, Vector2(target.x, target.z)), "map: dot moved to the new position")
	check(not _tree_pixel(img1, 256.0, 2.0, Vector2(old.x, old.z)), "map: no dot left at the old position")
	check(_solid_at(target + Vector3(0, 1, 0)).has(body), "collision: collider moved with the tree")
	check(not _solid_at(old + Vector3(0, 1, 0)).has(body), "collision: nothing left at the old position")
	check(KR.blocked_by_dressing(w, Vector2(target.x, target.z), 0.0) and not KR.blocked_by_dressing(w, Vector2(old.x, old.z), 0.0),
		"spawn placement (blocked_by_dressing) follows the moved tree")

	# delete / add
	var before: int = ForestData.sites(forest).size()
	tree.get_parent().remove_child(tree)
	tree.free()
	check(ForestData.sites(forest).size() == before - 1, "delete: forest_data drops the deleted tree (%d)" % ForestData.sites(forest).size())
	var added: Node3D = (load("res://scenes/world/props/vegetation/Tree_1_A.tscn") as PackedScene).instantiate()
	forest.get_node("Trees").add_child(added)
	added.global_position = target
	check(ForestData.sites(forest).size() == before, "add: an instanced prop scene is picked up (%d)" % ForestData.sites(forest).size())

	print("RESULT %s (%d failing)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(0 if fails == 0 else 1)
