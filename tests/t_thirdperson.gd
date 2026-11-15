extends SceneTree
## Third-person camera + stamina removal.
##   - V toggles the camera (action "toggle_camera"); first person is the default
##   - third person: full body drawn, viewmodel hidden, spring arm behind the shoulder, collides with walls
##   - shots/hover use the aim camera, which is steered onto the third-person crosshair point
##   - a remote peer never gets a third-person camera
##   - stamina is gone: sprint and jump are free, status dict still carries "stamina"
## Headless cannot render: this checks scene state and physics, never how it looks.
## Run: godot --headless --path . --script res://tests/t_thirdperson.gd

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


func _phys(n: int) -> void:
	for _i in n:
		await physics_frame


func _spawn(peer: String, pos: Vector3) -> Player:
	var p := (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as Player
	p.name = peer
	p.position = pos
	root.add_child(p)
	return p


func _box(size: Vector3, pos: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	body.position = pos
	root.add_child(body)
	return body


func _toggle(p: Player) -> void:
	var ev := InputEventAction.new()
	ev.action = "toggle_camera"
	ev.pressed = true
	p._unhandled_input(ev)


## x where the aim camera's forward ray crosses the plane z = plane_z
func _ray_x_at(cam: Camera3D, plane_z: float) -> float:
	var dir := -cam.global_transform.basis.z
	var t := (plane_z - cam.global_position.z) / dir.z
	return cam.global_position.x + dir.x * t


func _all_meshes(p: Player, mode: int) -> bool:
	var ms: Array[MeshInstance3D] = p._model._meshes
	var ok := ms.size() > 0
	for mi in ms:
		ok = ok and mi.cast_shadow == mode
	return ok


func _run() -> void:
	_box(Vector3(200, 1, 200), Vector3(0, -0.5, 0))
	var local := _spawn("1", Vector3(0, 0.2, 0))
	var remote := _spawn("2", Vector3(30, 0.2, 0))
	await _frames(10)
	await _phys(5)
	check(local.is_multiplayer_authority() and not remote.is_multiplayer_authority(), "peer 1 local, peer 2 remote")
	check(local._model != null, "local player has the Kenney body")
	if local._model == null:
		print("RESULT  failures=", fails)
		quit(1)
		return

	# ---- the input action
	check(InputMap.has_action("toggle_camera"), "toggle_camera action is registered")
	var keys: Array = []
	for ev in InputMap.action_get_events("toggle_camera"):
		if ev is InputEventKey:
			keys.append((ev as InputEventKey).physical_keycode)
	check(keys == [KEY_V], "toggle_camera is bound to V only: %s" % str(keys))
	var clash := ""
	for a in InputMap.get_actions():
		if a == "toggle_camera":
			continue
		for ev in InputMap.action_get_events(a):
			if ev is InputEventKey and (ev as InputEventKey).physical_keycode == KEY_V:
				clash = String(a)
	check(clash == "", "no other action uses V (clash: '%s')" % clash)

	# ---- default is first person
	check(not local.third_person, "starts in first person")
	check(local.camera.current and not local._tp_camera.current, "first person: FPS camera is current")
	check(_all_meshes(local, GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY), "first person: body is shadows-only (hidden)")
	check(local.weapons.visible, "first person: viewmodel is shown")

	# ---- toggle to third person
	_toggle(local)
	await _frames(3)
	await _phys(3)
	check(local.third_person, "V toggles third person on")
	check(local._tp_camera.current and not local.camera.current, "third person: spring-arm camera is current")
	check(_all_meshes(local, GeometryInstance3D.SHADOW_CASTING_SETTING_ON), "third person: full body is drawn")
	check(not local.weapons.visible, "third person: first-person viewmodel hidden")
	check(local._avatar_gun != null and local._avatar_gun.visible, "third person: body holds the equipped gun")

	# ---- camera sits behind and to the right of the head, in open ground
	var off := local._tp_camera.global_position - local.head.global_position
	var back := off.dot(local.global_transform.basis.z)
	var right := off.dot(local.global_transform.basis.x)
	info("open ground: back %.2f m, right %.2f m" % [back, right])
	check(back > 2.0, "camera is behind the player (%.2f m)" % back)
	check(right > 0.3, "camera is over the right shoulder (%.2f m)" % right)

	# ---- collision: a wall right behind pulls the camera in, removing it lets it back out
	var wall := _box(Vector3(20, 10, 0.5), Vector3(0, 2, 1.6))
	await _phys(4)
	var off2 := local._tp_camera.global_position - local.head.global_position
	var back2 := off2.dot(local.global_transform.basis.z)
	info("wall 1.35 m behind: camera back %.2f m" % back2)
	check(back2 < 1.4, "spring arm stops at the wall (%.2f m < 1.4)" % back2)
	wall.free()
	await _phys(4)
	var back3 := (local._tp_camera.global_position - local.head.global_position).dot(local.global_transform.basis.z)
	check(back3 > 2.0, "camera returns once the wall is gone (%.2f m)" % back3)

	# ---- aim: the aim camera is steered onto the third-person crosshair point
	var front := _box(Vector3(40, 20, 0.5), Vector3(0, 5, -10))
	await _phys(3)
	await _frames(3)
	var tp_x := _ray_x_at(local._tp_camera, -9.75)
	var aim_x := _ray_x_at(local.camera, -9.75)
	info("crosshair point x %.3f, aim ray x %.3f (shoulder offset %.2f)" % [tp_x, aim_x, local.TP_SHOULDER])
	check(absf(tp_x - aim_x) < 0.03, "shot ray lands on the third-person crosshair point (diff %.3f m)" % absf(tp_x - aim_x))
	check(absf(aim_x) > 0.2, "without the fix a parallel ray would miss by the shoulder offset; aim ray is steered")

	# ---- back to first person
	_toggle(local)
	await _frames(3)
	await _phys(2)
	check(not local.third_person and local.camera.current and not local._tp_camera.current, "V toggles back to first person")
	check(_all_meshes(local, GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY), "first person again: body hidden")
	check(local.weapons.visible, "first person again: viewmodel shown")
	check(local._avatar_gun == null or not local._avatar_gun.visible, "first person again: body gun hidden")
	check(local.camera.rotation.length() < 0.0001, "first person again: aim camera back to straight ahead")
	var fx := _ray_x_at(local.camera, -9.75)
	check(absf(fx) < 0.03, "first person ray is on the look axis (x %.3f)" % fx)
	front.free()

	# ---- remote peer: no third-person camera, toggle ignored
	check(remote._tp_camera == null, "remote player has no third-person camera")
	remote.set_third_person(true)
	check(not remote.third_person, "remote player cannot enter third person")
	check(remote._model != null and _all_meshes(remote, GeometryInstance3D.SHADOW_CASTING_SETTING_ON), "remote body still drawn")

	# ---- stamina is gone: sprint and jump are free
	check(local.get_hud_state().has("stamina") and is_equal_approx(float(local.get_hud_state()["stamina"]), 100.0), "status dict keeps a full 'stamina' key")
	check(not ("_stamina_lock" in local) and not local.has_method("_update_stamina"), "stamina lock and update are gone")
	# source-level: the only stamina left in player.gd is the compat var and the status key
	var src := FileAccess.get_file_as_string("res://scripts/player/player.gd")
	var stray: Array = []
	for line in src.split("\n"):
		if "stamina" in line.to_lower() and not line.begins_with("var stamina:") and not line.strip_edges().begins_with('"health": health, "stamina"') \
				and not line.strip_edges().begins_with("##") and not line.strip_edges().begins_with("#"):
			stray.append(line.strip_edges())
	check(stray.is_empty(), "no stamina logic left in player.gd (stray lines: %s)" % str(stray))

	# Input-driven sprint/jump is gated on Input.mouse_mode == CAPTURED, which headless cannot grant.
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		info("headless mouse capture unavailable (mode=%d): key-driven sprint/jump NOT verified here; checked the source instead" % Input.mouse_mode)
	else:
		Input.action_press("move_forward")
		Input.action_press("sprint")
		var sprint_frames := 0
		var min_stamina := 100.0
		for _i in 180:
			await physics_frame
			if local.is_sprinting:
				sprint_frames += 1
			min_stamina = minf(min_stamina, local.stamina)
		var spd := Vector2(local.velocity.x, local.velocity.z).length()
		check(sprint_frames >= 170, "sprint stays on for 3 s (%d/180 frames)" % sprint_frames)
		check(spd > Player.WALK_SPEED + 1.0, "sprint speed is held (%.2f m/s)" % spd)
		check(min_stamina == 100.0, "sprinting drains nothing (min stamina %.1f)" % min_stamina)
		Input.action_release("move_forward")
		Input.action_release("sprint")
		await _phys(30)
		var jumps := 0
		for _j in 12:
			Input.action_press("jump")
			await physics_frame
			if local.velocity.y > 1.0:
				jumps += 1
			Input.action_release("jump")
			await _phys(50)
		check(jumps >= 10, "jump works on every press with no stamina gate (%d/12)" % jumps)
		check(local.stamina == 100.0, "jumping drains nothing")

	print("RESULT  failures=", fails)
	quit(1 if fails > 0 else 0)
