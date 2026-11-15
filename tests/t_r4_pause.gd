extends SceneTree
## Round 4: pause menu (Hud autoload). Real flow: host_solo + main.tscn.
## The overlay must not pause the SceneTree (networked game), must open/close via ui_cancel and its
## buttons, must stay closed when Net is inactive, and Disconnect must leave the game.
## Real mouse capture is not available headless; mouse_mode assertions are made only where it can change.
## Run: godot --headless --path . --script res://tests/t_r4_pause.gd

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


func _esc() -> void:
	var ev := InputEventAction.new()
	ev.action = "ui_cancel"
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := InputEventAction.new()
	up.action = "ui_cancel"
	up.pressed = false
	Input.parse_input_event(up)


func _run() -> void:
	await physics_frame
	var hud: Node = root.get_node_or_null("Hud")
	var net: Node = root.get_node_or_null("Net")
	check(hud != null, "Hud autoload present")
	check(FileAccess.file_exists("res://scripts/ui/pause_menu.gd"), "pause_menu.gd exists")
	if hud == null:
		print("RESULT  failures=%d" % fails)
		quit(1)
		return
	check(hud.has_method("open_pause") and hud.has_method("close_pause") and hud.has_method("is_paused"), "Hud exposes open_pause/close_pause/is_paused")
	# Net inactive: pause must refuse (nothing to pause, menu is the start scene)
	hud.open_pause()
	check(not hud.is_paused(), "open_pause is refused while Net is inactive")

	check(net.host_solo(31337) == OK, "Net.host_solo ok")
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	for _i in 30:
		await physics_frame
	var p = net.players.get(1)
	check(p != null, "player spawned")
	var pm: Control = hud._pause
	check(pm != null and not pm.visible and not hud.is_paused(), "pause overlay hidden at game start")
	check(pm.resume_btn != null and pm.disconnect_btn != null and pm.quit_btn != null, "overlay has Resume, Disconnect and Quit buttons")
	check(pm.resume_btn.text == "Resume" and pm.disconnect_btn.text == "Disconnect" and pm.quit_btn.text == "Quit Game", "button labels (%s / %s / %s)" % [pm.resume_btn.text, pm.disconnect_btn.text, pm.quit_btn.text])

	var changes := []
	hud.pause_changed.connect(func(on: bool) -> void: changes.append(on))

	# open via API
	hud.open_pause()
	check(hud.is_paused() and pm.visible, "open_pause shows the overlay")
	check(hud.is_ui_open(), "is_ui_open() true while paused (gameplay input stands down)")
	check(not paused, "SceneTree is NOT paused (world keeps running for co-op)")
	var sp = get_first_node_in_group("spawner")
	var z0: Vector3 = p.global_position
	var fr := Engine.get_physics_frames()
	await create_timer(0.5).timeout
	check(Engine.get_physics_frames() > fr + 5, "physics keeps running while the overlay is open")
	hud.open_pause()
	check(changes.size() == 1, "second open_pause is a no-op (pause_changed fired %d times)" % changes.size())
	# resume button
	pm.resume_btn.pressed.emit()
	check(not hud.is_paused() and not pm.visible, "Resume button closes the overlay")
	check(changes == [true, false], "pause_changed emitted true then false (%s)" % str(changes))

	# ui_cancel toggle through the real input pipeline
	_esc()
	await physics_frame
	await physics_frame
	info("after Esc: Hud.paused=%s overlay visible=%s" % [hud.is_paused(), pm.visible])
	check(hud.is_paused() and pm.visible, "Esc (ui_cancel) opens the overlay")
	_esc()
	await physics_frame
	await physics_frame
	check(not hud.is_paused() and not pm.visible, "Esc again closes the overlay")

	# loot panel interplay: Esc with loot open closes loot, not pause
	if hud.has_method("is_loot_open"):
		check(not hud.is_loot_open(), "loot panel closed by default")

	# players keep taking game state while paused: damage still applies
	hud.open_pause()
	var hp: float = p.health
	p.take_damage(5.0)
	await physics_frame
	check(p.health < hp, "game state keeps updating while paused: damage applies (%.1f -> %.1f)" % [hp, p.health])

	# quit button wiring only (do not press: it would quit the test)
	check(pm.quit_requested.get_connections().size() >= 1, "Quit button signal is wired")
	# disconnect
	var left := [false]
	net.left.connect(func() -> void: left[0] = true)
	pm.disconnect_btn.pressed.emit()
	await physics_frame
	await physics_frame
	check(not hud.is_paused() and not pm.visible, "Disconnect closes the overlay")
	check(not net.active, "Disconnect leaves the network session (Net.active=%s)" % net.active)
	check(left[0], "Net.left signal fired on Disconnect")
	print("RESULT  failures=%d" % fails)
	quit(1 if fails > 0 else 0)
