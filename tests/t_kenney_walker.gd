extends SceneTree
## Kenney walker probe (RAT). Run: godot --headless --path . --script res://tests/t_kenney_walker.gd

var fails := 0


func check(cond: bool, label: String) -> void:
	if cond:
		print("PASS  ", label)
	else:
		fails += 1
		print("FAIL  ", label)


func info(msg: String) -> void:
	print("INFO  ", msg)


func _initialize() -> void:
	_run.call_deferred()


func _ground(main: Node, v: Vector3) -> Vector3:
	return Vector3(v.x, main.world.get_height(v.x, v.z) + 0.6, v.z)


## World-space (y-extent) of all meshes under a node, from the skinned vertex positions at the current pose.
func _mesh_extent(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var bb := mi.global_transform * mi.get_aabb()
		out = bb if first else out.merge(bb)
		first = false
	return out


func _bone_world(z: Node3D, skel: Skeleton3D, name: String) -> Vector3:
	var i := skel.find_bone(name)
	return skel.global_transform * skel.get_bone_global_pose(i).origin


func _run() -> void:
	await physics_frame
	var net: Node = root.get_node_or_null("Net")
	check(net.host_solo(31337) == OK, "Net.host_solo ok")
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	for _i in 40:
		await physics_frame
	var p = net.players.get(1)
	var sp = get_first_node_in_group("spawner")
	sp.enabled = false
	sp.kill_all()
	await physics_frame
	var base: Vector3 = p.global_position

	var w = sp.spawn_zombie_at(_ground(main, base + Vector3(30, 0, 30)), false, Zombie.KIND_WALKER)
	var r = sp.spawn_zombie_at(_ground(main, base + Vector3(34, 0, 30)), false, Zombie.KIND_RUNNER)
	var b = sp.spawn_zombie_at(_ground(main, base + Vector3(38, 0, 30)), false, Zombie.KIND_BLOATER)
	for _i in 15:
		await physics_frame

	# ---- 1. who uses the Kenney rig
	check(w._skel != null, "walker has Kenney skeleton")
	check(r._skel != null and b._skel != null, "runner and bloater also use the downloaded Kenney rig (no primitive bodies)")
	if w._skel == null:
		print("RESULT  failures=%d" % fails)
		quit(1)
		return
	var skel: Skeleton3D = w._skel
	var names := []
	for i in skel.get_bone_count():
		names.append("%s(parent %d)" % [skel.get_bone_name(i), skel.get_bone_parent(i)])
	info("bones: %s" % str(names))
	var mesh_n: int = w.find_children("*", "MeshInstance3D", true, false).size()
	info("walker mesh instances: %d (runner %d, bloater %d)" % [mesh_n, r.find_children("*", "MeshInstance3D", true, false).size(), b.find_children("*", "MeshInstance3D", true, false).size()])
	check(w.find_children("*", "AnimationPlayer", true, false).is_empty(), "stock AnimationPlayer removed from walker")

	# ---- 2. size and position
	var gy: float = w.global_position.y
	var ext := _mesh_extent(w._body)
	info("walker origin y=%.3f ; mesh AABB y %.3f..%.3f (height %.3f, feet offset %.3f), x width %.3f, z depth %.3f" % [gy, ext.position.y, ext.end.y, ext.size.y, ext.position.y - gy, ext.size.x, ext.size.z])
	var head_w := _bone_world(w, skel, "head")
	info("head bone world y above origin: %.3f ; head hit line %.2f" % [head_w.y - gy, Zombie.WALKER_HEAD_LINE])
	check(absf(ext.size.y - 1.75) < 0.25, "walker mesh height %.2f is near 1.75 m" % ext.size.y)
	check(absf(ext.position.y - gy) < 0.15, "feet are at the zombie origin (offset %.3f)" % (ext.position.y - gy))

	# ---- 3. collision shape vs model
	var cs := w.get_node_or_null("Collision") as CollisionShape3D
	if cs != null and cs.shape is CapsuleShape3D:
		var cap := cs.shape as CapsuleShape3D
		info("walker capsule r=%.2f h=%.2f centre y=%.2f (spans %.2f..%.2f) ; mesh width %.2f depth %.2f" % [cap.radius, cap.height, cs.position.y, cs.position.y - cap.height * 0.5, cs.position.y + cap.height * 0.5, ext.size.x, ext.size.z])
		check(cs.position.y + cap.height * 0.5 >= ext.size.y - 0.1, "capsule top (%.2f) covers model top (%.2f)" % [cs.position.y + cap.height * 0.5, ext.size.y])
	else:
		info("no capsule named Collision found")

	# ---- 4. head line vs hit test
	for y in [1.30, 1.36, 1.40, 1.70, 1.80, 1.95]:
		var hp := Vector3(w.global_position.x, gy + y, w.global_position.z)
		info("is_head_hit at +%.2f m -> walker %s | runner %s | bloater %s" % [y, str(w.is_head_hit(hp)), str(r.is_head_hit(hp)), str(b.is_head_hit(hp))])
	check(not w.is_head_hit(Vector3(0, gy + 1.0, 0)) and w.is_head_hit(Vector3(0, gy + 1.7, 0)), "walker body hit below 1.0 m, head hit at 1.7 m")
	# the head bone origin is the NECK BASE; the head spans from there up to the top of the mesh
	var head_top: float = ext.end.y - gy
	var neck: float = head_w.y - gy
	check(Zombie.WALKER_HEAD_LINE > neck and Zombie.WALKER_HEAD_LINE < head_top, "head line %.2f lies inside the head span (neck %.2f .. top %.2f); head-hit share of head %.0f%%" % [Zombie.WALKER_HEAD_LINE, neck, head_top, 100.0 * (head_top - Zombie.WALKER_HEAD_LINE) / (head_top - neck)])

	# ---- 5. real raycast against the body: where does the hitbox physically sit
	var space: PhysicsDirectSpaceState3D = w.get_world_3d().direct_space_state
	var hits := []
	for y in [0.2, 0.9, 1.3, 1.5, 1.7, 1.85, 2.0]:
		var from := Vector3(w.global_position.x + 5.0, gy + y, w.global_position.z)
		var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(-10, 0, 0))
		q.exclude = [p.get_rid()]
		var res: Dictionary = space.intersect_ray(q)
		var who := "miss"
		if res.size() > 0:
			var col: Object = res.collider
			who = "ZOMBIE" if col == w else (str((col as Node).name) + "<" + str((col as Node).get_parent().name))
		hits.append("%.2f:%s" % [y, who])
	info("side raycasts at heights: %s" % " ".join(hits))

	# ---- 6. arms: idle, chase, wind-up (direction of the arm bone's tip relative to zombie forward)
	var fwd: Vector3 = -w.global_transform.basis.z
	var arm_dirs := {}
	for st in ["idle", "chase", "wind0", "wind5", "wind10"]:
		match st:
			"chase":
				w.alert_to(p)
			"wind0":
				w._wind_pose = 0.0
			"wind5":
				w._wind_pose = 0.5
			"wind10":
				w._wind_pose = 1.0
		for _i in 6:
			await physics_frame
		var res_s := []
		for side in ["arm-left", "arm-right"]:
			var bi := skel.find_bone(side)
			# arm bone Y axis points along the limb in the Kenney rig? measure via child or via basis axes
			var t: Transform3D = skel.global_transform * skel.get_bone_global_pose(bi)
			# limb axis in the rest pose is +-X (model left arm = +X); carry it through the current pose
			var rest_axis := Vector3.RIGHT if side == "arm-left" else Vector3.LEFT
			var local_axis: Vector3 = skel.get_bone_global_rest(bi).basis.inverse() * rest_axis
			var tip: Vector3 = (skel.global_transform.basis * (skel.get_bone_global_pose(bi).basis * local_axis)).normalized()
			var f: Vector3 = (-w.global_transform.basis.z)
			res_s.append("%s fwd=%.2f up=%.2f side=%.2f" % [side, tip.dot(f), tip.y, tip.dot(w.global_transform.basis.x)])
		arm_dirs[st] = res_s
		info("arms %s (state %d, wind %.1f): %s" % [st, w.state_id, w._wind_pose, " | ".join(res_s)])
	w._wind_pose = 0.0

	# ---- 7. walk animation: legs and arms must change over time
	w.alert_to(p)
	var samples := []
	for _i in 12:
		for _j in 5:
			await physics_frame
		samples.append(skel.get_bone_pose_rotation(skel.find_bone("leg-left")))
	var distinct := 0
	for i in range(1, samples.size()):
		if not (samples[i] as Quaternion).is_equal_approx(samples[0]):
			distinct += 1
	info("leg-left pose changed in %d of %d later samples" % [distinct, samples.size() - 1])
	check(distinct >= 3, "walk animation moves the legs")

	# ---- 8. death pose, flinch, bloater/runner still alive
	w.request_damage(10000.0, false, 1)
	for _i in 90:
		await physics_frame
	var dext := _mesh_extent(w._body)
	info("dead walker mesh AABB y %.2f..%.2f (height %.2f); body rot %s" % [dext.position.y - gy, dext.end.y - gy, dext.size.y, str(w._body.rotation)])
	check(w.state_id == Zombie.State.DEAD, "walker dies")
	check(dext.size.y < ext.size.y * 0.8 or dext.size.y < 1.2, "dead walker mesh is lying down / collapsed (height %.2f)" % dext.size.y)

	# ---- 9. multiple walkers do not share mutated material (hit flash)
	var w2 = sp.spawn_zombie_at(_ground(main, base + Vector3(30, 0, 40)), false, Zombie.KIND_WALKER)
	var w3 = sp.spawn_zombie_at(_ground(main, base + Vector3(34, 0, 40)), false, Zombie.KIND_WALKER)
	for _i in 10:
		await physics_frame
	check(w2._mat_skin != w3._mat_skin, "walkers have private skin materials")
	w2.request_damage(5.0, false, 1)
	for _i in 2:
		await physics_frame
	info("hit flash: w2 emission=%s w3 emission=%s" % [str(w2._mat_skin.emission_enabled), str(w3._mat_skin.emission_enabled)])
	check(not w3._mat_skin.emission_enabled, "hit flash on one walker does not light another")

	# ---- 10. frame cost of 30 walkers (CPU side, headless)
	var many := []
	for i in 30:
		many.append(sp.spawn_zombie_at(_ground(main, base + Vector3(-60 + (i % 10) * 3, 0, 60 + int(i / 10) * 3)), false, Zombie.KIND_WALKER))
	var t0 := Time.get_ticks_usec()
	for _i in 60:
		await physics_frame
	info("60 physics frames with 30 walkers + others: %.1f ms avg" % ((Time.get_ticks_usec() - t0) / 60000.0))

	print("RESULT  failures=%d" % fails)
	quit(1 if fails > 0 else 0)
