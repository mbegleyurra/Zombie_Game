extends SceneTree
## Player model: Kenney body for remote peers + shadow-only body for the local player.
## Peer "1" is the local authority; peer "2" is a REMOTE player (not the tree's unique id), driven only
## by replicated vars (look_pitch / crouching / is_dead / is_sprinting) plus the speed it measures itself.
## Run: godot --headless --path . --script res://tests/t_player_model.gd

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


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _spawn(peer: String, pos: Vector3) -> Player:
	var p := (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as Player
	p.name = peer
	p.position = pos
	root.add_child(p)
	return p


func _mesh_height(model: Node3D) -> float:
	var lo := INF
	var hi := -INF
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var box := mi.global_transform * mi.mesh.get_aabb()
		lo = minf(lo, box.position.y)
		hi = maxf(hi, box.end.y)
	return hi - lo


func _head_forward_y(m: PlayerModel) -> float:
	var skel := m._skel
	var xf := skel.global_transform * skel.get_bone_global_pose(m._head_bone)
	return (xf.basis * Vector3(0, 0, 1)).normalized().y   # Kenney faces +Z in bone space


func _run() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	cs.shape = box
	floor_body.add_child(cs)
	floor_body.position = Vector3(0, -0.5, 0)
	root.add_child(floor_body)

	var local := _spawn("1", Vector3(0, 0.2, 0))
	var remote := _spawn("2", Vector3(6, 0.0, 0))
	await _frames(10)
	check(local.is_multiplayer_authority() and not remote.is_multiplayer_authority(), "peer 1 is local authority, peer 2 is remote")
	check(local._model != null and remote._model != null, "both players built the Kenney body (no box fallback)")
	if local._model == null or remote._model == null:
		print("RESULT  failures=", fails)
		quit(1)
		return

	# ---- local: shadow only, never drawn in the first-person camera
	var lm: Array[MeshInstance3D] = local._model._meshes
	var rm: Array[MeshInstance3D] = remote._model._meshes
	var all_shadow := lm.size() > 0
	for mi in lm:
		all_shadow = all_shadow and mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	check(all_shadow, "local body: all %d meshes are shadows-only (invisible to the first-person view)" % lm.size())
	var all_drawn := rm.size() > 0
	for mi in rm:
		all_drawn = all_drawn and mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	check(all_drawn, "remote body: all %d meshes are drawn normally" % rm.size())
	check(local.camera.current and not remote.camera.current, "only the local player's camera is current")

	# ---- size
	var h := _mesh_height(remote._model)
	info("remote body mesh height %.3f m" % h)
	check(absf(h - 1.8) < 0.2, "remote body is about 1.8 m tall (%.2f)" % h)

	# ---- clip selection table
	var cf := PlayerModel.clip_for
	check(cf.call(0.0, false, false, false, false) == "idle", "standing still -> idle")
	check(cf.call(0.0, false, false, false, true) == "holding-both", "standing still with a gun -> holding-both")
	check(cf.call(2.5, false, false, false, false) == "walk", "2.5 m/s -> walk")
	check(cf.call(5.5, false, true, false, false) == "sprint", "5.5 m/s sprinting -> sprint")
	check(cf.call(2.5, true, false, false, false) == "crouch", "crouching -> crouch")
	check(cf.call(5.5, true, true, true, true) == "die", "dead beats everything -> die")

	# ---- remote walk/idle driven purely by measured movement
	var start_x := remote.global_position.x
	for _i in 40:
		await process_frame
		remote.global_position.x += 2.5 * _dt()
	info("remote speed estimate %.2f m/s, clip %s, moved %.2f m" % [remote._remote_speed, remote._model.current_clip(), remote.global_position.x - start_x])
	check(remote._model.current_clip() == "walk", "remote peer moving ~2.5 m/s plays walk (clip %s)" % remote._model.current_clip())
	var pose_a: Quaternion = remote._model._skel.get_bone_pose_rotation(remote._model._skel.find_bone("leg-left"))
	var changed := 0
	for _i in 12:
		await _frames(4)
		var q: Quaternion = remote._model._skel.get_bone_pose_rotation(remote._model._skel.find_bone("leg-left"))
		if not q.is_equal_approx(pose_a):
			changed += 1
		remote.global_position.x += 2.5 * _dt() * 4.0
	check(changed >= 3, "walk animation moves the legs (%d of 12 samples differ)" % changed)
	await _frames(120)
	check(remote._model.current_clip() == "idle", "remote peer standing still returns to idle (clip %s, speed %.2f)" % [remote._model.current_clip(), remote._remote_speed])

	# ---- crouch + sprint flags (replicated vars) pick their clips
	remote.crouching = true
	await _frames(5)
	check(remote._model.current_clip() == "crouch", "replicated crouching -> crouch clip")
	remote.crouching = false

	# ---- aim: the head follows the replicated look_pitch
	remote.look_pitch = 45.0
	await _frames(5)
	var up_y := _head_forward_y(remote._model)
	remote.look_pitch = -45.0
	await _frames(5)
	var down_y := _head_forward_y(remote._model)
	remote.look_pitch = 0.0
	await _frames(5)
	var level_y := _head_forward_y(remote._model)
	info("head forward y: pitch +45 -> %.2f, 0 -> %.2f, -45 -> %.2f" % [up_y, level_y, down_y])
	check(up_y > level_y + 0.2 and level_y > down_y + 0.2, "head tips up for +pitch and down for -pitch")

	# ---- armed remote shows the equipped gun on its avatar
	remote.equipped_id = "pistol"
	await _frames(5)
	check(remote._avatar_gun != null and remote._model.current_clip() == "holding-both", "remote with a pistol shows the gun and holds it (clip %s)" % remote._model.current_clip())

	# ---- death
	remote.is_dead = true
	await _frames(5)
	check(remote._model.current_clip() == "die", "dead remote plays die")
	remote.is_dead = false

	# ---- local player still animates from its own velocity and its first-person camera is untouched
	await _frames(20)
	check(local._model.current_clip() in ["idle", "holding-both"], "local body idles while standing (clip %s)" % local._model.current_clip())
	check(is_equal_approx(local.head.position.y, Player.EYE_STAND) and local.camera.current, "first-person eye height and camera unchanged")

	print("RESULT  failures=", fails)
	quit(1 if fails > 0 else 0)


var _last_us: int = 0


## Real seconds since the previous call (clamped), so simulated movement matches the measured speed.
func _dt() -> float:
	var now := Time.get_ticks_usec()
	var d := clampf(float(now - _last_us) / 1000000.0, 0.0, 0.1) if _last_us > 0 else 0.016
	_last_us = now
	return d
