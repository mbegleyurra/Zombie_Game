extends SceneTree
## Lean (hold Q / G) and the third-person / remote held gun.
##   - lean slides the Head ~0.35 m and rolls it ~14 deg, eased; the first-person weapon and third-person camera follow
##   - a wall on the lean side limits the lean so the camera stays out of it; blocked in a vehicle and while dead
##   - respawn resets it; "lean" is in the PlayerSync replication list; a remote body tilts its torso with it
##   - the remote body's gun barrel points along the player's aim (dot > 0.9) at look pitch -30 / 0 / +30
## Run: xvfb-run -a godot --headless --path . --script res://tests/t_lean.gd

var fails := 0


func check(cond: bool, label: String) -> void:
	if cond:
		print("PASS  ", label)
	else:
		fails += 1
		print("FAIL  ", label)


func _initialize() -> void:
	_run.call_deferred()


func _frames(n: int = 2) -> void:
	for _i in n:
		await process_frame


## Real-time wait: headless frames are only a few ms long, so a frame count does not let the eases settle.
func _secs(t: float) -> void:
	await create_timer(t).timeout
	await process_frame


func _spawn(peer: String, pos: Vector3, loadout: bool = true) -> Player:
	var p := (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as Player
	p.name = peer
	p.start_with_loadout = loadout
	p.position = pos
	root.add_child(p)
	return p


func _box(size: Vector3, pos: Vector3) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	b.add_child(cs)
	b.position = pos
	root.add_child(b)
	return b


func _run() -> void:
	await physics_frame
	_box(Vector3(200, 1, 200), Vector3(0, -0.5, 0))
	Player.register_inputs()
	check(InputMap.has_action("lean_left") and InputMap.has_action("lean_right"), "lean_left / lean_right actions registered")
	var lk: Array = []
	for a in ["lean_left", "lean_right"]:
		for ev in InputMap.action_get_events(a):
			lk.append((ev as InputEventKey).physical_keycode)
	check(lk == [KEY_Q, KEY_G], "lean keys are Q and G (E stays interact): %s" % [lk])

	var me := _spawn("1", Vector3(0, 0, 0))
	await _frames(10)
	var head0 := me.head.global_position
	var wpn0 := me.weapons.global_position
	var tp0 := me._tp_camera.global_position

	# --- free lean right
	me.set_lean_input(1.0)
	await _secs(1.2)
	check(absf(me.lean - 1.0) < 0.01, "full lean right with room (lean %.3f)" % me.lean)
	check(absf(me.head.position.x - Player.LEAN_OFFSET) < 0.01, "head slides %.2f m (want %.2f)" % [me.head.position.x, Player.LEAN_OFFSET])
	check(absf(me.head.global_position.x - head0.x - Player.LEAN_OFFSET) < 0.01, "head moves right in world space")
	var roll := rad_to_deg(me.head.rotation.z)
	check(roll < -12.0 and roll > -15.5, "head rolls right %.1f deg (12-15)" % roll)
	check(me.weapons.global_position.x - wpn0.x > 0.25, "first-person weapon follows the camera (dx %.2f)" % (me.weapons.global_position.x - wpn0.x))
	check(me._tp_camera.global_position.distance_to(tp0) > 0.2, "third-person camera leans too (moved %.2f m)" % me._tp_camera.global_position.distance_to(tp0))

	# --- eased, not snapped
	me.set_lean_input(-1.0)
	await _frames(1)
	check(me.lean > -0.9, "lean eases toward the new side (after 1 frame %.3f)" % me.lean)
	await _secs(1.2)
	check(absf(me.lean + 1.0) < 0.01, "full lean left (lean %.3f)" % me.lean)
	check(absf(me.head.position.x + Player.LEAN_OFFSET) < 0.01, "head slides left")
	check(rad_to_deg(me.head.rotation.z) > 12.0, "head rolls left %.1f deg" % rad_to_deg(me.head.rotation.z))
	me.set_lean_input(0.0)
	await _secs(1.2)
	check(absf(me.lean) < 0.01 and absf(me.head.position.x) < 0.01, "release returns to centre")

	# --- wall on the right: lean is limited, the camera stays out of it
	var wall_face := 0.45
	var wall := _box(Vector3(0.4, 4, 4), Vector3(wall_face + 0.2, 2, 0))
	await physics_frame
	await physics_frame
	me.set_lean_input(1.0)
	await _secs(1.2)
	check(me.lean > 0.3 and me.lean < 0.9, "wall limits the lean (lean %.3f)" % me.lean)
	var cam_x := me.camera.global_position.x
	check(cam_x + 0.1 < wall_face, "camera stays out of the wall (cam x %.3f, face %.2f)" % [cam_x, wall_face])
	check(me.lean_room(1.0) < 0.9 and me.lean_room(-1.0) > 0.99, "lean_room right %.2f, left %.2f" % [me.lean_room(1.0), me.lean_room(-1.0)])
	# wall right against the shoulder: no lean at all
	wall.position.x = 0.36 + 0.2
	await physics_frame
	await physics_frame
	await _frames(5)
	var face2 := 0.36
	check(me.lean < 0.5, "near wall clamps the lean at once (lean %.3f)" % me.lean)
	check(me.camera.global_position.x + 0.1 < face2, "camera stays out of the near wall (cam x %.3f, face %.2f)" % [me.camera.global_position.x, face2])
	wall.queue_free()
	await physics_frame
	await physics_frame
	await _secs(1.2)
	check(me.lean > 0.99, "wall gone: full lean again (lean %.3f)" % me.lean)

	# --- blocked in a vehicle and while dead
	var fake_vehicle := Node.new()
	me.vehicle = fake_vehicle
	await _secs(1.2)
	check(absf(me.lean) < 0.01, "no lean while seated in a vehicle (lean %.3f)" % me.lean)
	me.vehicle = null
	fake_vehicle.free()
	await _secs(1.2)
	check(me.lean > 0.99, "lean back after leaving the vehicle")
	me.take_damage(1000.0)
	await _secs(1.2)
	check(me.is_dead and absf(me.lean) < 0.01, "no lean while dead (lean %.3f)" % me.lean)

	# --- respawn resets
	me.respawn(Vector3(0, 0, 0))
	check(me.lean == 0.0 and me.head.position.x == 0.0, "respawn resets lean and head offset")
	me.set_lean_input(0.0)
	await _frames(5)
	check(absf(me.lean) < 0.01, "stays centred after respawn")

	# --- replication
	var sync := me.get_node_or_null("PlayerSync") as MultiplayerSynchronizer
	check(sync != null and sync.replication_config.has_property(NodePath(".:lean")), "lean is in the PlayerSync replication list")

	# --- remote body: torso tilts with lean, head offset mirrors it
	var other := _spawn("7", Vector3(5, 0, 0), false)
	await _frames(10)
	check(not other.is_multiplayer_authority(), "peer 7 is a remote body here")
	var model: PlayerModel = other._model
	check(model != null, "remote body uses the Kenney model")
	var torso := model._skel.find_bone("torso")
	await _frames(3)
	var t0: Quaternion = model._skel.get_bone_pose_rotation(torso)
	other.lean = 1.0
	await _frames(3)
	var t1: Quaternion = model._skel.get_bone_pose_rotation(torso)
	var tilt_deg := rad_to_deg(t0.angle_to(t1))
	check(tilt_deg > 10.0 and tilt_deg < 20.0, "remote torso tilts %.1f deg with lean" % tilt_deg)
	check(absf(other.head.position.x - Player.LEAN_OFFSET) < 0.01, "remote head offset follows the replicated lean")
	other.lean = 0.0

	# --- remote held gun direction
	other.equipped_id = "ak"
	await _frames(5)
	check(other._avatar_gun != null and other._avatar_gun.get_parent() == model, "remote gun is held by the body")
	for p in [-30.0, 0.0, 30.0]:
		other.look_pitch = p
		await _frames(4)
		var aim := (-other.head.global_basis.z).normalized()
		var fwd := model.gun_forward()
		var d := fwd.dot(aim)
		check(d > 0.9, "barrel along aim at pitch %+d (dot %.3f)" % [int(p), d])
		var muzzle := GunMesh.muzzle_of(other._avatar_gun)
		if muzzle != null:
			var local := other.global_transform.affine_inverse() * muzzle.global_position
			check(local.z < -0.3, "muzzle is in front of the body at pitch %+d (z %.2f)" % [int(p), local.z])
	other.look_pitch = 0.0
	other.crouching = true
	await _frames(40)
	var gy := other._avatar_gun.global_position.y - other.global_position.y
	check(gy < 0.75, "gun drops with the crouch (grip y %.2f)" % gy)
	check(model.gun_forward().dot(-other.global_basis.z) > 0.9, "crouched barrel still forward")

	print("\nt_lean: %d failures" % fails)
	quit(1 if fails > 0 else 0)
