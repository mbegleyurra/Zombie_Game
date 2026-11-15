extends SceneTree
## UI readability: font sizes, context prompts, controls strip + help screen vs real bindings,
## and no overlap / clipping of HUD panels at 1280x720 and 1920x1080.
## Real flow: host_solo + main.tscn. Not covered: how it LOOKS (headless uses a dummy renderer,
## so contrast over the 3D world and outline rendering are not checked).
## Run: godot --headless --path . --script res://tests/t_ui_readable.gd

const PauseMenu := preload("res://scripts/ui/pause_menu.gd")
const MIN_BODY := 20
const MIN_HEAD := 32

var fails := 0


func check(cond: bool, label: String) -> void:
	if cond:
		print("PASS  ", label)
	else:
		fails += 1
		print("FAIL  ", label)


func _initialize() -> void:
	_run.call_deferred()


func _texts(n: Node, out: Array) -> void:
	if n is Label and str((n as Label).text) != "":
		out.append(n)
	elif n is Button and str((n as Button).text) != "":
		out.append(n)
	for c in n.get_children():
		_texts(c, out)


func _min_font(n: Node) -> Array:
	var found := []
	_texts(n, found)
	var lo := 999
	var who := ""
	for c in found:
		var fs: int = (c as Control).get_theme_font_size("font_size")
		if fs < lo:
			lo = fs
			who = str(c.get("text"))
	return [lo, who, found.size()]


func _has_key(action: String, keycode: int) -> bool:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey and (ev as InputEventKey).physical_keycode == keycode:
			return true
	return false


func _has_mouse(action: String, button: int) -> bool:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == button:
			return true
	return false


func _rows_text() -> String:
	var s := ""
	for r in PauseMenu.CONTROL_ROWS:
		s += "%s=%s\n" % [r[0], r[1]]
	return s


func _layout(hud: Node, w: int, h: int) -> void:
	root.size = Vector2i(w, h)
	for _i in 4:
		await process_frame
	var vp := Rect2(Vector2.ZERO, Vector2(w, h))
	var panels := {
		"vitals": (hud._bars["health"] as Control).get_parent().get_parent().get_parent(),
		"ammo": hud._ammo_panel,
		"build": hud._build_label.get_parent(),
		"hint": hud._hint_panel,
		"msg": hud._prompt_panel,
	}
	var rects := {}
	for k in panels:
		var c: Control = panels[k]
		rects[k] = c.get_global_rect()
		check(vp.encloses(rects[k]), "%dx%d: %s panel inside the screen %s" % [w, h, k, str(rects[k])])
	var keys := rects.keys()
	for i in keys.size():
		for j in range(i + 1, keys.size()):
			var a: Rect2 = rects[keys[i]]
			var b: Rect2 = rects[keys[j]]
			check(not a.intersects(b), "%dx%d: %s and %s panels do not overlap" % [w, h, keys[i], keys[j]])
	# the player's own prompt sits at screen centre: nothing may cover the crosshair or it
	var centre := Rect2(Vector2(w, h) * 0.5 - Vector2(300, 40), Vector2(600, 120))
	for k in rects:
		check(not (rects[k] as Rect2).intersects(centre), "%dx%d: %s panel clear of the centre prompt zone" % [w, h, k])


func _run() -> void:
	await physics_frame
	var net: Node = root.get_node_or_null("Net")
	var hud: Node = root.get_node_or_null("Hud")
	check(net != null and hud != null, "Net and Hud autoloads present")
	if net == null or hud == null:
		print("RESULT  failures=%d" % fails)
		quit(1)
		return

	# ---- main menu (before any game): fonts
	var menu: Node = (load("res://scenes/ui/menu.tscn") as PackedScene).instantiate()
	root.add_child(menu)
	current_scene = menu
	await process_frame
	var mf := _min_font(menu)
	check(int(mf[2]) > 5 and int(mf[0]) >= MIN_BODY, "menu: smallest text is %d (>= %d) over %d widgets, e.g. '%s'" % [mf[0], MIN_BODY, mf[2], mf[1]])
	var mt: Label = null
	for l in menu.find_children("*", "Label", true, false):
		if (l as Label).text == "DEAD ACRES":
			mt = l
	check(mt != null and mt.get_theme_font_size("font_size") >= MIN_HEAD, "menu title is a heading size (>= %d)" % MIN_HEAD)
	var mc: Control = menu.controls_panel
	var cf := _min_font(mc)
	check(int(cf[2]) > 20 and int(cf[0]) >= MIN_BODY, "controls help: smallest text is %d (>= %d) over %d widgets, e.g. '%s'" % [cf[0], MIN_BODY, cf[2], cf[1]])
	menu.queue_free()
	await process_frame

	# ---- controls help matches the real bindings (InputMap after Player.register_inputs)
	var Pl = load("res://scripts/player/player.gd")
	Pl.register_inputs()
	var rt := _rows_text()
	check(_has_key("move_forward", KEY_W) and _has_key("move_left", KEY_A) and _has_key("move_back", KEY_S) and _has_key("move_right", KEY_D) and "W A S D" in rt, "help: Move = WASD matches InputMap")
	check(_has_key("sprint", KEY_SHIFT) and "Shift" in rt, "help: Sprint = Shift matches InputMap")
	check(_has_key("crouch", KEY_CTRL) and _has_key("crouch", KEY_C) and "Ctrl" in rt and "C" in rt, "help: Crouch = Ctrl / C matches InputMap")
	check(_has_key("jump", KEY_SPACE) and "Space" in rt, "help: Jump = Space matches InputMap")
	check(_has_mouse("fire", MOUSE_BUTTON_LEFT) and "Fire=Left mouse button" in rt, "help: Fire = left mouse matches InputMap")
	check(_has_mouse("aim", MOUSE_BUTTON_RIGHT) and "Aim=Right mouse button" in rt, "help: Aim = right mouse matches InputMap")
	check(_has_key("reload", KEY_R) and "Reload=R" in rt, "help: Reload = R matches InputMap")
	check(_has_key("interact", KEY_E) and "loot=E" in rt, "help: Interact = E matches InputMap")
	check(_has_key("use_medkit", KEY_H) and _has_key("use_food", KEY_J) and _has_key("use_water", KEY_K) and "H  /  J  /  K" in rt, "help: Medkit/Food/Water = H/J/K matches InputMap")
	var slots_ok := true
	for i in 5:
		slots_ok = slots_ok and _has_key("slot_%d" % (i + 1), KEY_1 + i)
	check(slots_ok and "1 - 5" in rt, "help: weapon slots 1-5 match InputMap")
	check("Show / hide controls strip=F1" in rt, "help: lists F1 for the controls strip (H stays medkit)")

	# ---- real session
	check(net.host_solo(31338) == OK, "Net.host_solo ok")
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	for _i in 30:
		await physics_frame
	var p = net.players.get(1)
	check(p != null, "player spawned")
	if p == null:
		print("RESULT  failures=%d" % fails)
		quit(1)
		return
	await process_frame
	await process_frame
	check(hud.visible, "Hud visible during play")

	# ---- HUD fonts and names
	var hf := _min_font(hud._ammo_panel.get_parent())
	check(int(hf[2]) > 8 and int(hf[0]) >= MIN_BODY, "hud: smallest text is %d (>= %d) over %d widgets, e.g. '%s'" % [hf[0], MIN_BODY, hf[2], hf[1]])
	var pf := _min_font(hud._pause)
	check(int(pf[0]) >= MIN_BODY, "pause menu: smallest text is %d (>= %d), e.g. '%s'" % [pf[0], MIN_BODY, pf[1]])
	check(hud._loot_title.get_theme_font_size("font_size") >= MIN_HEAD, "loot panel title is a heading size")
	check(p._lbl_prompt.get_theme_font_size("font_size") >= MIN_BODY, "player interaction prompt font >= %d" % MIN_BODY)
	check(p._lbl_dead.get_theme_font_size("font_size") >= MIN_HEAD, "'YOU DIED' font >= %d" % MIN_HEAD)
	var caps := []
	for k in hud._bars:
		caps.append(((hud._bars[k] as Control).get_parent().get_child(0) as Label).text)
	check("HEALTH" in caps and "FOOD" in caps and "WATER" in caps, "vitals are named: %s" % str(caps))
	check(not ("STAMINA" in caps) and not hud._bars.has("stamina"), "stamina bar is removed")
	hud.apply_state({"stamina": 50.0})   # legacy key must be ignored, not crash
	check(p.get_node_or_null("PlayerHUD") != null and p._lbl_prompt != null, "player keeps its prompt layer")

	# ---- weapon / ammo labels and reload cue
	hud.set_weapon({"weapon": "pistol", "name": "Pistol", "mag": 7, "reserve": 21, "chambered": true})
	check(hud._ammo_panel.visible and hud._weapon_label.text == "WEAPON  Pistol", "weapon label: '%s'" % hud._weapon_label.text)
	check(hud._ammo_label.text == "AMMO  7+1 / 21", "ammo label: '%s'" % hud._ammo_label.text)
	check("LMB - Shoot" in hud._ammo_hint.text and "R - Reload" in hud._ammo_hint.text, "shoot/reload cue: '%s'" % hud._ammo_hint.text)
	hud.set_weapon({"weapon": "pistol", "name": "Pistol", "mag": 0, "reserve": 21, "chambered": false})
	check(hud._ammo_hint.text.begins_with("R - Reload"), "empty mag with reserve -> '%s'" % hud._ammo_hint.text)
	hud.set_weapon({"weapon": "pistol", "name": "Pistol", "mag": 0, "reserve": 0, "chambered": false})
	check(hud._ammo_hint.text.begins_with("Out of ammo"), "no ammo anywhere -> '%s'" % hud._ammo_hint.text)
	hud.set_weapon({"weapon": "", "name": "", "mag": 0, "reserve": 0, "chambered": false})
	check(not hud._ammo_panel.visible, "ammo panel hidden when unarmed")
	hud.set_weapon({"weapon": "pistol", "name": "Pistol", "mag": 7, "reserve": 21, "chambered": true})
	hud.set_vital("health", 63.0)
	check((hud._bar_vals["health"] as Label).text == "63", "health shows its number")

	# ---- controls strip: visible by default, F1 toggles, text matches bindings
	check(hud._hint_panel.visible and hud._hint_label.visible, "controls strip visible by default")
	var ht: String = hud._hint_label.text
	for want in ["LMB Shoot", "R Reload", "E Interact", "H Medkit", "J Food", "K Water", "B Build", "F1 Hide hints", "Shift Sprint", "Space Jump", "1-5 Weapons"]:
		check(want in ht, "strip says '%s'" % want)
	var f1 := InputEventKey.new()
	f1.keycode = KEY_F1
	f1.physical_keycode = KEY_F1
	f1.pressed = true
	hud._input(f1)
	check(not hud._hint_panel.visible, "F1 hides the controls strip")
	hud._input(f1)
	check(hud._hint_panel.visible, "F1 shows the controls strip again")
	check(not _has_key("use_medkit", KEY_F1) and _has_key("use_medkit", KEY_H), "H is still the medkit key (strip toggle is F1, not H)")

	# ---- build prompt wording
	var bm: Node = root.get_node_or_null("Building")
	if bm != null:
		hud._refresh_build()
		check("B - Build mode" in hud._build_label.text and "PLANKS" in hud._build_label.text, "build hint: '%s'" % hud._build_label.text.replace("\n", " | "))

	# ---- hud message panel follows set_prompt
	hud.set_prompt("Not enough planks", "buildmsg")
	check(hud._prompt_panel.visible and hud._prompt_label.text == "Not enough planks", "message panel shows set_prompt text")

	# ---- interaction prompt: a real interactable straight ahead of the camera
	var src := GDScript.new()
	src.source_code = "extends StaticBody3D\nfunc get_prompt() -> String:\n\treturn \"Open chest\"\nfunc interact(_by = null) -> bool:\n\treturn true\n"
	check(src.reload() == OK, "test interactable script compiles")
	var body := StaticBody3D.new()
	body.set_script(src)
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.2, 1.2, 1.2)
	cs.shape = bs
	body.add_child(cs)
	main.add_child(body)
	var cam: Camera3D = p.camera
	body.global_position = cam.global_position + (-cam.global_transform.basis.z) * 1.6
	await create_timer(0.5).timeout
	check(p._lbl_prompt.text == "E - Open chest", "looking at a chest: prompt is '%s'" % p._lbl_prompt.text)
	check(p._prompt_panel.visible, "prompt has its backing panel shown")
	body.queue_free()
	await create_timer(0.5).timeout
	check(p._lbl_prompt.text == "" and not p._prompt_panel.visible, "looking away: prompt and panel hidden")

	# ---- loot prompt strings (real classes)
	var LootItem = load("res://scripts/world/loot_item.gd")
	check(LootItem != null, "loot_item.gd loads (prompt text 'Pick up <item> xN' is rendered as 'E - Pick up ...')")

	# ---- layout at both target resolutions
	await _layout(hud, 1280, 720)
	await _layout(hud, 1920, 1080)

	# ---- pause + controls screens fit the screen
	for sz in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = sz
		hud.open_pause()
		hud._pause.open_controls()
		for _i in 4:
			await process_frame
		var cp: Control = hud._pause.controls_panel
		var box: Control = cp.get_child(1).get_child(0)
		var r := box.get_global_rect()
		check(Rect2(Vector2.ZERO, Vector2(sz)).encloses(r), "%dx%d: controls help fits the screen %s" % [sz.x, sz.y, str(r)])
		hud._pause.close_controls()
		var pbox: Control = hud._pause.get_child(1).get_child(0)
		var pr := pbox.get_global_rect()
		check(Rect2(Vector2.ZERO, Vector2(sz)).encloses(pr), "%dx%d: pause menu fits the screen %s" % [sz.x, sz.y, str(pr)])
		hud.close_pause(false)

	print("RESULT  failures=%d" % fails)
	quit(1 if fails > 0 else 0)
