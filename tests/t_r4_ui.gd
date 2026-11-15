extends SceneTree
## Round 4: menu buttons and pause menu, driven by emitting `pressed` (headless cannot click).
## Covers Play Solo, Host Game, Join Game (button path), pause toggle by ui_cancel, Resume,
## Disconnect (back to the menu, network and building state cleared).
## Not covered: mouse-mode capture/release (headless cannot report it) and real mouse clicks.
## Run: godot --headless --path . --script res://tests/t_r4_ui.gd

var fails := 0
var net: Node
var building: Node
var hud: Node


func check(cond: bool, label: String) -> void:
	if cond:
		print("PASS  ", label)
	else:
		fails += 1
		print("FAIL  ", label)


func _initialize() -> void:
	_run.call_deferred()


func _wait_for(cond: Callable, timeout: float) -> bool:
	var t := 0.0
	while t < timeout:
		if cond.call():
			return true
		await create_timer(0.1).timeout
		t += 0.1
	return cond.call()


func _scene_path() -> String:
	return current_scene.scene_file_path if current_scene != null else ""


func _press_escape() -> void:
	var ev := InputEventAction.new()
	ev.action = "ui_cancel"
	ev.pressed = true
	Input.parse_input_event(ev)
	await process_frame
	await process_frame
	var up := InputEventAction.new()
	up.action = "ui_cancel"
	up.pressed = false
	Input.parse_input_event(up)
	await process_frame


func _load_menu() -> Node:
	var menu: Node = (load("res://scenes/ui/menu.tscn") as PackedScene).instantiate()
	root.add_child(menu)
	current_scene = menu
	await process_frame
	return menu


func _run() -> void:
	await physics_frame
	net = root.get_node_or_null("Net")
	building = root.get_node_or_null("Building")
	hud = root.get_node_or_null("Hud")
	check(net != null and building != null and hud != null, "autoloads Net, Building, Hud present")
	if net == null or building == null or hud == null:
		quit(1)
		return

	# ---- menu exposes its buttons
	var menu := await _load_menu()
	check(menu.solo_btn != null and menu.host_btn != null and menu.join_btn != null and menu.quit_btn != null, "menu exposes solo/host/join/quit buttons")
	check(menu.solo_btn.text == "Play Solo" and menu.host_btn.text == "Host Game" and menu.join_btn.text == "Join Game", "button captions")

	# ---- Join button (no server on this port: only the button path is checked)
	menu._ip.text = "127.0.0.1:17999"
	menu.join_btn.pressed.emit()
	check(net.active and not net.is_host(), "Join button starts a client session")
	check(menu._status.text.begins_with("Connecting to 127.0.0.1:17999"), "Join parses ip:port (%s)" % menu._status.text)
	net.leave()
	check(not net.active, "leave() after join")

	# ---- Play Solo button
	menu.solo_btn.pressed.emit()
	check(net.active and net.is_host(), "Play Solo button starts a loopback host")
	var in_game: bool = await _wait_for(func() -> bool: return _scene_path() == "res://scenes/main.tscn" and net.players.size() == 1, 30.0)
	check(in_game, "Play Solo loads main.tscn with one player (scene %s, players %d)" % [_scene_path(), net.players.size()])
	check(get_nodes_in_group("players").size() == 1, "exactly one player node in solo (%d)" % get_nodes_in_group("players").size())

	# ---- pause menu
	await process_frame
	check(not hud.is_paused(), "not paused at start")
	await _press_escape()
	check(hud.is_paused() and hud._pause.visible, "ui_cancel opens the pause menu")
	check(hud.is_ui_open() and building._ui_open(), "building input stands down while paused")
	await _press_escape()
	check(not hud.is_paused() and not hud._pause.visible, "ui_cancel closes the pause menu")
	hud.open_pause()
	check(hud.is_paused(), "open_pause()")
	hud._pause.resume_btn.pressed.emit()
	check(not hud.is_paused(), "Resume button closes the pause menu")

	# ---- Disconnect button, with a building piece present to prove state is cleared
	building.request_place("floor", Vector4i(0, 0, 0, 0))
	check(building.pieces.size() == 1, "solo can place a piece (%d)" % building.pieces.size())
	hud.open_pause()
	hud._pause.disconnect_btn.pressed.emit()
	check(not net.active, "Disconnect leaves the network session")
	var back: bool = await _wait_for(func() -> bool: return _scene_path() == "res://scenes/ui/menu.tscn", 10.0)
	check(back, "Disconnect returns to the menu (scene %s)" % _scene_path())
	check(not hud.is_paused(), "pause closed after Disconnect")
	check(building.pieces.is_empty() and building.slots.is_empty(), "building state cleared after Disconnect")
	check(net.players.is_empty(), "no player nodes tracked after Disconnect")

	# ---- Host Game button
	menu = current_scene
	check(menu != null and menu.get("host_btn") != null, "menu is back and usable")
	if menu != null and menu.get("host_btn") != null:
		menu.host_btn.pressed.emit()
		check(net.active and net.is_host() and net.roster == [1], "Host Game button starts a host (roster %s)" % str(net.roster))
		var hosted: bool = await _wait_for(func() -> bool: return _scene_path() == "res://scenes/main.tscn" and net.players.size() == 1, 30.0)
		check(hosted, "Host Game loads main.tscn with the host player")
		await _press_escape()
		check(hud.is_paused(), "pause menu works while hosting")
		hud._pause.disconnect_btn.pressed.emit()
		var back2: bool = await _wait_for(func() -> bool: return _scene_path() == "res://scenes/ui/menu.tscn", 10.0)
		check(back2 and not net.active, "Disconnect from a hosted game returns to the menu")

	print("RESULT  failures=%d" % fails)
	quit(1 if fails > 0 else 0)
