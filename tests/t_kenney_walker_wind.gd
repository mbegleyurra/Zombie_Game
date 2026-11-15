extends SceneTree
## Wind-up / strike arm direction: Kenney walker bones vs procedural runner arm pivots (RAT).
## Run: godot --headless --path . --script res://tests/t_kenney_walker_wind.gd


func _initialize() -> void:
	_run.call_deferred()


func _walker_arm(w: Node3D, side: String) -> Vector3:
	var skel: Skeleton3D = w._skel
	var bi := skel.find_bone(side)
	var rest_axis := Vector3.RIGHT if side == "arm-left" else Vector3.LEFT
	var local_axis: Vector3 = skel.get_bone_global_rest(bi).basis.inverse() * rest_axis
	return (skel.global_transform.basis * (skel.get_bone_global_pose(bi).basis * local_axis)).normalized()


func _run() -> void:
	await physics_frame
	var net: Node = root.get_node_or_null("Net")
	net.host_solo(31337)
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	for _i in 40:
		await physics_frame
	var p = net.players.get(1)
	var sp = get_first_node_in_group("spawner")
	sp.enabled = false
	sp.kill_all()
	var base: Vector3 = p.global_position
	var w = sp.spawn_zombie_at(Vector3(base.x + 30, main.world.get_height(base.x + 30, base.z + 30) + 0.6, base.z + 30), false, Zombie.KIND_WALKER)
	var r = sp.spawn_zombie_at(Vector3(base.x + 36, main.world.get_height(base.x + 36, base.z + 30) + 0.6, base.z + 30), false, Zombie.KIND_RUNNER)
	for _i in 20:
		await physics_frame
	for phase in ["rest", "winding", "strike"]:
		match phase:
			"winding":
				w.winding = true
				r.winding = true
				for _i in 30:
					w.winding = true
					r.winding = true
					await process_frame
			"strike":
				w.winding = false
				r.winding = false
				w._attack_anim = 0.3
				r._attack_anim = 0.3
				await process_frame
		var f: Vector3 = -w.global_transform.basis.z
		var lw := _walker_arm(w, "arm-left")
		var rw := _walker_arm(w, "arm-right")
		# procedural arm pivot hangs along -Y; direction of the limb in world space
		var fr: Vector3 = -r.global_transform.basis.z
		var la: Vector3 = (r._arms[0].global_transform.basis * Vector3.DOWN).normalized()
		var ra: Vector3 = (r._arms[1].global_transform.basis * Vector3.DOWN).normalized()
		print("%-8s wind_pose w=%.2f r=%.2f | WALKER left fwd=%.2f up=%.2f  right fwd=%.2f up=%.2f | RUNNER left fwd=%.2f up=%.2f  right fwd=%.2f up=%.2f" % [phase, w._wind_pose, r._wind_pose, lw.dot(f), lw.y, rw.dot(f), rw.y, la.dot(fr), la.y, ra.dot(fr), ra.y])
	quit(0)
