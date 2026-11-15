extends SceneTree
## Kenney Survival/Car Kit dressing (scripts/world/kenney_dressing.gd). Run:
##   godot --headless --path . --script res://tests/t_dressing.gd
## Checks, over 3 seeds: models exist and counts are sane, determinism (same seed => same shape transforms),
## no dressing collider overlaps any location's own colliders, no loot item lies inside a dressing collider,
## nothing on the player spawn ring, and car box sizes look like cars (printed).

var fails := 0


func check(cond: bool, label: String) -> void:
	if cond:
		print("PASS  ", label)
	else:
		fails += 1
		print("FAIL  ", label)


func _initialize() -> void:
	_run()


func _build(seed_value: int) -> Node3D:
	var w: Node3D = (load("res://scenes/world/world.tscn") as PackedScene).instantiate()
	root.add_child(w)
	w.build(seed_value)
	return w


func _sig(w: Node3D) -> String:
	var body: StaticBody3D = w.get_node("KenneyDressing/Collision")
	var parts := PackedStringArray()
	for c in body.get_children():
		var t: Transform3D = (c as CollisionShape3D).transform
		parts.append("%.2f,%.2f,%.2f,%.3f" % [t.origin.x, t.origin.y, t.origin.z, t.basis.get_euler().y])
	return "\n".join(parts).md5_text()


func _run() -> void:
	await physics_frame
	for seed_value in [20260101, 31337, 7]:
		var w := _build(seed_value)
		await physics_frame
		await physics_frame
		var cnt: Dictionary = w.dressing_counts
		print("INFO  seed %d counts %s" % [seed_value, str(cnt)])
		check(int(cnt["cars"]) >= 8, "seed %d: cars placed (%d)" % [seed_value, int(cnt["cars"])])
		check(int(cnt["cones"]) >= 3, "seed %d: cones placed (%d)" % [seed_value, int(cnt["cones"])])
		check(int(cnt["camps"]) >= 3, "seed %d: camps placed (%d)" % [seed_value, int(cnt["camps"])])
		check(int(cnt["signposts"]) >= 4, "seed %d: signposts placed (%d)" % [seed_value, int(cnt["signposts"])])
		check(int(cnt["crates_barrels"]) >= 8, "seed %d: barrels/crates in warehouse+gas (%d)" % [seed_value, int(cnt["crates_barrels"])])
		check(int(cnt["trees"]) >= 20 and int(cnt["rocks"]) >= 20, "seed %d: open-terrain trees %d rocks %d" % [seed_value, int(cnt["trees"]), int(cnt["rocks"])])
		var dn: Node3D = w.get_node("KenneyDressing")
		var body: StaticBody3D = dn.get_node("Collision")
		var space := w.get_world_3d().direct_space_state
		# overlap with every location's own colliders and the procedural props
		var overl := PackedStringArray()
		for c in body.get_children():
			var cs: CollisionShape3D = c
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = cs.shape
			q.collision_mask = 1
			q.transform = cs.global_transform
			for hit in space.intersect_shape(q, 8):
				var col: Node = hit["collider"] as Node
				if col != null and col != body and col.name != "Chunk" and not col.name.begins_with("Terrain") and col.get_parent() != null and col.get_parent().get_parent() != w.get_node("Terrain"):
					var other := ""
					if col is CollisionObject3D:
						var oi: int = (col as CollisionObject3D).shape_find_owner(int(hit["shape"]))
						var on: Node3D = (col as CollisionObject3D).shape_owner_get_owner(oi) as Node3D
						var osh = (col as CollisionObject3D).shape_owner_get_shape(oi, 0)
						other = " other=%s@(%.1f,%.1f,%.1f) %s" % [osh.get_class(), on.global_position.x, on.global_position.y, on.global_position.z, str((osh as BoxShape3D).size) if osh is BoxShape3D else (str((osh as SphereShape3D).radius) if osh is SphereShape3D else "r=%s" % str((osh as CylinderShape3D).radius if osh is CylinderShape3D else "?"))]
					var mine := str((cs.shape as BoxShape3D).size) if cs.shape is BoxShape3D else "cyl"
					overl.append("%s%s@(%.1f,%.1f) hits %s/%s%s" % [cs.shape.get_class(), mine, cs.position.x, cs.position.z, col.get_parent().name, col.name, other])
					break
		info("seed %d: %d dressing shapes overlapping other non-terrain colliders: %s" % [seed_value, overl.size(), ", ".join(overl)])
		check(overl.is_empty(), "seed %d: dressing colliders overlap no location/prop collider (%d)" % [seed_value, overl.size()])
		# loot never inside a dressing shape (XZ, expanded by 0.3)
		var bad := 0
		for id in w.loot_by_id:
			var n = w.loot_by_id[id]
			if n == null or not is_instance_valid(n):
				continue
			var p: Vector3 = (n as Node3D).global_position
			for c in body.get_children():
				var cs2: CollisionShape3D = c
				var lp: Vector3 = cs2.global_transform.affine_inverse() * p
				var half := Vector3(0.5, 0.5, 0.5)
				if cs2.shape is BoxShape3D:
					half = (cs2.shape as BoxShape3D).size * 0.5
				elif cs2.shape is CylinderShape3D:
					half = Vector3((cs2.shape as CylinderShape3D).radius, (cs2.shape as CylinderShape3D).height * 0.5, (cs2.shape as CylinderShape3D).radius)
				if absf(lp.x) < half.x + 0.3 and absf(lp.z) < half.z + 0.3 and absf(lp.y) < half.y + 0.6:
					bad += 1
					break
		check(bad == 0, "seed %d: no loot item inside a dressing collider (%d)" % [seed_value, bad])
		# spawn ring clear
		var near := 0
		for c in body.get_children():
			if Vector2((c as CollisionShape3D).position.x, (c as CollisionShape3D).position.z).distance_to(w.spawn_center) < 20.0:
				near += 1
		check(near == 0, "seed %d: nothing within 20 m of the spawn centre (%d)" % [seed_value, near])
		# car shape sizes (informational + sanity)
		var cars := 0
		for m in dn.get_children():
			if m is Node3D and m.get_child_count() > 0 and (m as Node3D).has_meta("size"):
				var sz: Vector3 = (m as Node3D).get_meta("size")
				if sz.y > 1.2 and maxf(sz.x, sz.z) > 3.0:
					cars += 1
					if cars <= 3 and seed_value == 7:
						info("sample car size %.2f x %.2f x %.2f" % [sz.x, sz.y, sz.z])
		check(cars >= 5, "seed %d: %d car-sized models (>3 m long)" % [seed_value, cars])
		var sig1 := _sig(w)
		w.queue_free()
		await physics_frame
		await physics_frame
		var w2 := _build(seed_value)
		await physics_frame
		check(_sig(w2) == sig1, "seed %d: dressing deterministic across two builds" % seed_value)
		w2.queue_free()
		await physics_frame
	print("RESULT  failures=", fails)
	quit(1 if fails > 0 else 0)


func info(msg: String) -> void:
	print("INFO  ", msg)
