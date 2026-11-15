extends SceneTree
## Death screen + respawn (scripts/ui/death_ui.gd): shows on death, frees the mouse, Respawn button and R key put the
## player back on the world spawn point, inventory and weapons are kept, mouse recaptured. Part 1 drives the screen
## standalone against a stub world; part 2 is the real flow (host_solo + main.tscn through the Hud autoload, the owning peer).
## Not covered: a second remote peer (needs two processes and fixed ports); is_dead / position replicate through
## PlayerSync as before.
## Run: godot --headless --path . --script res://tests/t_respawn.gd

const DeathUI := preload("res://scripts/ui/death_ui.gd")
const InvUI := preload("res://scripts/ui/inventory_ui.gd")

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


func _key(code: int) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.physical_keycode = code as Key
	ev.pressed = true
	return ev


func _run() -> void:
	await physics_frame
	# ---------- part 1: standalone against a stub world
	var stub := Node.new()
	var gs := GDScript.new()
	gs.source_code = "extends Node\nvar world = self\nfunc get_spawn_point(i: int = 0) -> Vector3:\n\treturn Vector3(30.0 + i, 4.0, -20.0)\n"
	gs.reload()
	stub.set_script(gs)
	stub.add_to_group("main_world")
	root.add_child(stub)

	var player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	player.name = "1"
	player.position = Vector3(0, 0.2, 0)
	root.add_child(player)
	await _frames(5)
	var inv_ui: Control = InvUI.new()
	inv_ui.standalone = true
	root.add_child(inv_ui)
	inv_ui.bind_player(player)
	var ui: Control = DeathUI.new()
	ui.standalone = true
	root.add_child(ui)
	ui.bind_player(player)
	await _frames()
	player.add_item("scrap", 5)
	player.add_item("m4")
	var weapons_before: Array = player.weapons.weapon_ids().duplicate()
	var inv_before: Dictionary = player.inventory.duplicate()

	check(not ui.visible, "death screen hidden while alive")
	check(not ui.respawn(), "respawn() does nothing while alive")
	check(ui.button.text.begins_with("Respawn") and ui.button.get_theme_font_size("font_size") >= 32, "Respawn button is labelled and large")

	inv_ui.open()
	check(inv_ui.visible, "inventory open before death")
	player.health = 5.0
	player._hurt(50.0)
	check(player.is_dead, "player died")
	await _frames(2)
	check(ui.visible and ui.is_in_group("ui_open"), "death screen shows on death and joins ui_open")
	check(not inv_ui.visible, "an open inventory is closed when the death screen shows")
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "mouse is freed while the death screen is shown")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await _frames(2)
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "mouse stays freed even if something recaptures it")
	check(ui.spawn_position() == Vector3(30.0, 4.0, 0.0 - 20.0), "spawn position comes from the world spawn point")

	ui.button.pressed.emit()
	check(not player.is_dead and player.health == player.max_health, "Respawn button revives the player at full health")
	check(player.global_position.distance_to(Vector3(30.0, 4.0, -20.0)) < 0.01, "player is placed on the world spawn point")
	check(not ui.visible and not ui.is_in_group("ui_open"), "death screen closes")
	check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "mouse is recaptured after respawn")
	check(player.inventory == inv_before, "inventory is kept on death")
	check(player.weapons.weapon_ids() == weapons_before, "weapons are kept on death")
	await _frames(2)
	check(not ui.visible, "screen stays closed once alive")

	# R key
	player._hurt(500.0)
	await _frames(2)
	check(ui.visible and player.is_dead, "second death shows the screen again")
	ui._input(_key(KEY_E))
	check(player.is_dead, "other keys do not respawn")
	ui._input(_key(KEY_R))
	check(not player.is_dead and not ui.visible, "R respawns")
	check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "mouse recaptured after R respawn")

	ui.queue_free()
	inv_ui.queue_free()
	player.queue_free()
	stub.queue_free()
	await _frames(3)
	await _real_session()
	print("RESULT  failures=%d" % fails)
	quit(1 if fails > 0 else 0)


func _real_session() -> void:
	var net: Node = root.get_node_or_null("Net")
	var hud: Node = root.get_node_or_null("Hud")
	check(net != null and hud != null, "Net and Hud autoloads present")
	if net == null or hud == null:
		return
	check(net.host_solo(31353) == OK, "Net.host_solo ok")
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	for _i in 30:
		await physics_frame
	var p = net.get_local_player()
	check(p != null, "local player spawned")
	if p == null:
		return
	var ui: Node = null
	for c in hud.get_children():
		if c.get_script() != null and str(c.get_script().resource_path).ends_with("death_ui.gd"):
			ui = c
	check(ui != null, "Hud owns a death_ui child")
	if ui == null:
		return
	await _frames(3)
	check(not ui.visible, "no death screen while alive in a real session")
	var spawn: Vector3 = main.world.get_spawn_point(net.spawn_slot_for(net.local_id()))
	p.add_item("scrap", 3)
	var inv_before: Dictionary = p.inventory.duplicate()
	p._hurt(1000.0)
	await _frames(3)
	check(p.is_dead and ui.visible and hud.is_ui_open(), "death screen shows in the real session (Hud.is_ui_open true)")
	check(ui.size.is_equal_approx(root.get_visible_rect().size), "death screen fills the screen (%s)" % str(ui.size))
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "mouse freed on death in the real session")
	p.global_position = Vector3(100, 50, 100)
	ui.button.pressed.emit()
	check(not p.is_dead and p.health == p.max_health, "Respawn revives the owning peer's player")
	check(p.global_position.distance_to(spawn) < 0.01, "respawn lands on the world spawn point %s" % str(spawn))
	check(p.inventory == inv_before, "inventory kept in the real session")
	await _frames(2)
	check(not ui.visible and not hud.is_ui_open() and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "screen closed, mouse recaptured")
	# Esc while dead opens the pause menu on top, and the mouse stays free for it
	p._hurt(1000.0)
	await _frames(2)
	hud.open_pause()
	check(hud.is_paused() and ui.visible, "pause menu can open over the death screen")
	hud.close_pause(true)
	await _frames(2)
	check(ui.visible and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "closing pause while dead keeps the mouse free")
	ui.respawn()
	await _frames(2)
	check(not p.is_dead and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "final respawn recaptures the mouse")
