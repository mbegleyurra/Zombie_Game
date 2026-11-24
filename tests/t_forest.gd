extends SceneTree
## KayKit Forest terrain dressing (scripts/world/kaykit_forest.gd). Run:
##   godot --headless --path . --script res://tests/t_forest.gd
## Checks, over seeds 7, 31337, 20260101: counts are sane, the build is deterministic, no tree/bush/rock/grass
## instance lies on a road or inside a location (+ margin), no forest collider overlaps another collider, no loot
## item lies inside a forest collider, nothing near the spawn centre, trees/big rocks have colliders and
## bushes/grass do not.

var fails := 0
const ForestData = preload("res://scripts/world/forest_data.gd")


func check(cond: bool, label: String) -> void:
	if cond:
		print("PASS  ", label)
	else:
		fails += 1
		print("FAIL  ", label)


func info(msg: String) -> void:
	print("INFO  ", msg)


func _initialize() -> void:
	_run()


func _build(seed_value: int) -> Node3D:
	var w: Node3D = (load("res://scenes/world/world.tscn") as PackedScene).instantiate()
	root.add_child(w)
	w.build(seed_value)
	return w


## Hash of every collider transform plus every vegetation node position (each object owns its collider).
func _sig(w: Node3D) -> String:
	var parts := PackedStringArray()
	var f: Node = w.get_node("KayKitForest")
	for c in f.find_children("*", "CollisionShape3D", true, false):
		var t: Transform3D = (c as CollisionShape3D).global_transform
		parts.append("%.2f,%.2f,%.2f,%.3f" % [t.origin.x, t.origin.y, t.origin.z, t.basis.get_euler().y])
	# object positions read from the vegetation nodes (what is actually saved and rendered)
	for s in ForestData.sites(f):
		parts.append("%s %.2f,%.2f" % [s[0], float(s[1]), float(s[2])])
	return "\n".join(parts).md5_text()


func _run() -> void:
	await physics_frame
	for seed_value in [7, 31337, 20260101]:
		var w := _build(seed_value)
		await physics_frame
		await physics_frame
		var cnt: Dictionary = w.forest_counts
		var f: Node3D = w.get_node("KayKitForest")
		var shapes: Array = f.find_children("*", "CollisionShape3D", true, false)
		var terrain = w.terrain
		info("seed %d counts %s" % [seed_value, str(cnt)])
		check(int(cnt["trees"]) >= 200, "seed %d: trees placed (%d)" % [seed_value, int(cnt["trees"])])
		check(int(cnt["bushes"]) >= 100, "seed %d: bushes placed (%d)" % [seed_value, int(cnt["bushes"])])
		check(int(cnt["rocks"]) >= 60, "seed %d: rocks placed (%d)" % [seed_value, int(cnt["rocks"])])
		check(int(cnt["grass"]) >= 800, "seed %d: grass tufts placed (%d)" % [seed_value, int(cnt["grass"])])
		check(f.find_children("*", "MultiMeshInstance3D", true, false).is_empty(), "seed %d: no MultiMesh (one node per object)" % seed_value)
		var no_col := 0
		for n in ForestData.nodes(f):
			var solid: bool = n.find_children("*", "CollisionShape3D", true, false).size() > 0
			var kind: String = str(n.get_meta("kind"))
			if (kind == "tree" and not solid) or ((kind == "bush" or kind == "grass") and solid):
				no_col += 1
		check(no_col == 0, "seed %d: every tree owns a collider, bushes/grass none (%d wrong)" % [seed_value, no_col])
		check(int(cnt["shapes"]) == shapes.size(), "seed %d: shape counter matches collider count (%d)" % [seed_value, shapes.size()])
		# every instance (any kind) against roads, locations and the spawn centre
		var on_road := 0
		var in_loc := 0
		var near_spawn := 0
		var total := 0
		var tree_road_min := 9999.0
		var mm_total: int = ForestData.nodes(f).size()
		for s in ForestData.sites(f):
			total += 1
			var kind: String = s[0]
			var sx: float = s[1]
			var sz: float = s[2]
			var rd: float = terrain.road_distance(sx, sz)
			if kind == "tree":
				tree_road_min = minf(tree_road_min, rd)
			if rd < 2.2:
				on_road += 1
			var p := Vector2(sx, sz)
			if p.distance_to(w.spawn_center) < 20.0:
				near_spawn += 1
			for l in w.locations:
				if p.distance_to(l["pos2"] as Vector2) < float(l["radius"]) + 0.5:
					in_loc += 1
					break
		check(total == int(cnt["instances"]) and mm_total == total, "seed %d: sites (%d), vegetation nodes (%d) and counter agree" % [seed_value, total, mm_total])
		check(on_road == 0, "seed %d: no forest instance on a road (%d of %d)" % [seed_value, on_road, total])
		check(in_loc == 0, "seed %d: no forest instance inside a location (%d)" % [seed_value, in_loc])
		check(near_spawn == 0, "seed %d: nothing within 20 m of the spawn centre (%d)" % [seed_value, near_spawn])
		info("seed %d: closest tree to a road centreline %.2f m" % [seed_value, tree_road_min])
		# collider centres against roads and locations (trunk must clear the road with its own radius)
		var bad_col := 0
		for c in shapes:
			var cs: CollisionShape3D = c
			var p2 := Vector2(cs.global_position.x, cs.global_position.z)
			var reach := 0.0
			if cs.shape is CylinderShape3D:
				reach = (cs.shape as CylinderShape3D).radius
			elif cs.shape is BoxShape3D:
				var bs: Vector3 = (cs.shape as BoxShape3D).size
				reach = 0.5 * Vector2(bs.x, bs.z).length()
			if terrain.road_distance(p2.x, p2.y) < 1.6 + reach:
				bad_col += 1
				continue
			for l in w.locations:
				if p2.distance_to(l["pos2"] as Vector2) < float(l["radius"]) + reach:
					bad_col += 1
					break
		check(bad_col == 0, "seed %d: forest colliders clear of roads and locations (%d)" % [seed_value, bad_col])
		# forest colliders overlap no other collider (buildings, props, Kenney dressing)
		var space := w.get_world_3d().direct_space_state
		var overl := PackedStringArray()
		for c in shapes:
			var cs2: CollisionShape3D = c
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = cs2.shape
			q.collision_mask = 1
			q.transform = cs2.global_transform
			for hit in space.intersect_shape(q, 8):
				var col: Node = hit["collider"] as Node
				if col == null or f.is_ancestor_of(col) or col.name == "Chunk" or col.name.begins_with("Terrain"):
					continue
				if col.get_parent() != null and col.get_parent().get_parent() == terrain:
					continue
				overl.append("%s@(%.1f,%.1f) hits %s/%s" % [cs2.shape.get_class(), cs2.global_position.x, cs2.global_position.z, col.get_parent().name, col.name])
				break
		info("seed %d: %d forest shapes overlapping other non-terrain colliders: %s" % [seed_value, overl.size(), ", ".join(overl.slice(0, 6))])
		check(overl.is_empty(), "seed %d: forest colliders overlap no other collider (%d)" % [seed_value, overl.size()])
		# loot never inside a forest collider
		var bad := 0
		for id in w.loot_by_id:
			var n = w.loot_by_id[id]
			if n == null or not is_instance_valid(n):
				continue
			var lp: Vector3 = (n as Node3D).global_position
			for c in shapes:
				var cs3: CollisionShape3D = c
				var l3: Vector3 = cs3.global_transform.affine_inverse() * lp
				var half := Vector3(0.5, 0.5, 0.5)
				if cs3.shape is BoxShape3D:
					half = (cs3.shape as BoxShape3D).size * 0.5
				elif cs3.shape is CylinderShape3D:
					half = Vector3((cs3.shape as CylinderShape3D).radius, (cs3.shape as CylinderShape3D).height * 0.5, (cs3.shape as CylinderShape3D).radius)
				if absf(l3.x) < half.x + 0.3 and absf(l3.z) < half.z + 0.3 and absf(l3.y) < half.y + 0.6:
					bad += 1
					break
		check(bad == 0, "seed %d: no loot item inside a forest collider (%d)" % [seed_value, bad])
		# forest zones are denser than open ground
		var dense := 0
		var sparse := 0
		for c in shapes:
			var fd: float = terrain.forest_density(c.global_position.x, c.global_position.z)
			if fd >= 0.12:
				dense += 1
			elif fd < -0.15:
				sparse += 1
		check(dense > sparse, "seed %d: more colliders in forest zones (%d) than open ground (%d)" % [seed_value, dense, sparse])
		# determinism
		var sig1 := _sig(w)
		w.queue_free()
		await physics_frame
		await physics_frame
		var w2 := _build(seed_value)
		await physics_frame
		check(_sig(w2) == sig1, "seed %d: forest deterministic across two builds" % seed_value)
		check(w2.forest_counts == cnt, "seed %d: forest counts identical across two builds" % seed_value)
		w2.queue_free()
		await physics_frame
	print("RESULT  failures=", fails)
	quit(1 if fails > 0 else 0)
