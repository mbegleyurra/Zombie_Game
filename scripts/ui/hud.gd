extends CanvasLayer
## Dead Acres HUD. Autoload "Hud" (scene res://scenes/ui/hud.tscn).
##
## Shows only while Net.active. Reads the local player automatically: either
## player.get_hud_state() -> {health, max_health, hunger, max_hunger, thirst,
## max_thirst, ammo, reserve}, or plain properties health/max_health/hunger/
## thirst/ammo/reserve_ammo. Other code can call the setters below directly.

signal loot_taken(index: int)
signal loot_closed
signal pause_changed(on: bool)

const COL_HEALTH := Color(0.85, 0.2, 0.2)
const COL_HUNGER := Color(0.9, 0.6, 0.15)
const COL_THIRST := Color(0.25, 0.55, 0.95)
const PauseMenu := preload("res://scripts/ui/pause_menu.gd")

var _net = null
var _building = null
var _bars := {}
var _bar_vals := {}
var _weapon_label: Label
var _ammo_label: Label
var _ammo_hint: Label
var _ammo_panel: PanelContainer
var _prompt_label: Label
var _prompt_panel: PanelContainer
var _build_label: Label
var _ping_label: Label
var _hint_label: Label
var _hint_panel: PanelContainer
var _loot_panel: PanelContainer
var _loot_title: Label
var _loot_list: VBoxContainer
var _prompts := {}
var _player: Node = null
var _ping_timer := 0.0
var _prev_mouse := Input.MOUSE_MODE_CAPTURED
var _pause: Control = null
var paused := false


func _ready() -> void:
	layer = 10
	_net = get_node_or_null("/root/Net")
	_building = get_node_or_null("/root/Building")
	_build_ui()
	if _building != null:
		_building.prompt_changed.connect(func(t: String): set_prompt(t, "building"))
		_building.mode_changed.connect(func(_on: bool): _refresh_build())
		_building.selection_changed.connect(func(_k: String): _refresh_build())
		_building.stock_changed.connect(func(_s: Dictionary): _refresh_build())
		_building.build_rejected.connect(_on_build_rejected)
	if _net != null:
		_net.ping_result.connect(func(ms: float): _ping_label.text = "PING %d ms" % int(round(ms)))
		_net.left.connect(func() -> void: close_pause(false))
	_pause = PauseMenu.new()
	add_child(_pause)
	_pause.resume_requested.connect(func() -> void: close_pause(true))
	_pause.disconnect_requested.connect(_on_pause_disconnect)
	_pause.quit_requested.connect(func() -> void: get_tree().quit())
	_refresh_build()
	visible = false


# ---------------------------------------------------------------- public API

func set_vital(key: String, value: float, max_value: float = 100.0) -> void:
	var bar := _bars.get(key) as ProgressBar
	if bar != null:
		bar.max_value = max_value
		bar.value = value
		(_bar_vals[key] as Label).text = str(roundi(value))


func set_ammo(mag: int, reserve: int) -> void:
	_ammo_label.text = "AMMO  %d / %d" % [mag, reserve]


## weapon: WeaponController.status() -> {weapon, name, mag, reserve, chambered}.
func set_weapon(w: Dictionary) -> void:
	if str(w.get("weapon", "")) == "":
		_ammo_panel.visible = false
		return
	_ammo_panel.visible = true
	var mag := int(w.get("mag", 0))
	var reserve := int(w.get("reserve", 0))
	var chamber := "+1" if bool(w.get("chambered", false)) else ""
	_weapon_label.text = "WEAPON  %s" % str(w.get("name", "?"))
	_ammo_label.text = "AMMO  %d%s / %d" % [mag, chamber, reserve]
	if mag == 0 and chamber == "" and reserve > 0:
		_ammo_hint.text = "R - Reload  (magazine empty)"
		_ammo_hint.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35))
	elif mag == 0 and chamber == "":
		_ammo_hint.text = "Out of ammo - find more"
		_ammo_hint.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35))
	else:
		_ammo_hint.text = "LMB - Shoot     R - Reload"
		_ammo_hint.add_theme_color_override("font_color", Color(1, 1, 1))


## Several systems may set prompts; the first non-empty source is shown.
func set_prompt(text: String, source: String = "game") -> void:
	_prompts[source] = text
	_prompt_label.text = ""
	for s in _prompts:
		if _prompts[s] != "":
			_prompt_label.text = _prompts[s]
			break
	_prompt_panel.visible = _prompt_label.text != ""


## items: Array of {name: String, count: int}. Emits loot_taken(index) on click.
func show_loot(title: String, items: Array) -> void:
	_loot_title.text = title
	for c in _loot_list.get_children():
		c.queue_free()
	for i in items.size():
		var it: Dictionary = items[i]
		var b := Button.new()
		b.text = "%s  x%d" % [str(it.get("name", "?")), int(it.get("count", 1))]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		PauseMenu.style_button(b)
		b.custom_minimum_size = Vector2(0, 50)
		b.pressed.connect(func(): loot_taken.emit(i))
		_loot_list.add_child(b)
	if _loot_list.get_child_count() > 0:
		(_loot_list.get_child(0) as Button).grab_focus.call_deferred()
	if not _loot_panel.visible:
		_prev_mouse = Input.mouse_mode
	_loot_panel.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func hide_loot() -> void:
	if not _loot_panel.visible:
		return
	_loot_panel.visible = false
	Input.mouse_mode = _prev_mouse
	loot_closed.emit()


func is_loot_open() -> bool:
	return _loot_panel.visible


func is_paused() -> bool:
	return paused


## True while any overlay owns the mouse; gameplay input (building clicks) must stand down.
func is_ui_open() -> bool:
	return paused or _loot_panel.visible


func open_pause() -> void:
	if paused or _net == null or not _net.active:
		return
	paused = true
	_pause.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	pause_changed.emit(true)


## recapture: give the mouse back to the player (not wanted when leaving the game).
func close_pause(recapture: bool = true) -> void:
	if not paused:
		return
	paused = false
	_pause.visible = false
	if recapture:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	pause_changed.emit(false)


func _on_pause_disconnect() -> void:
	close_pause(false)
	if _net != null:
		_net.leave_to_menu()


func _input(event: InputEvent) -> void:
	if _net == null or not _net.active:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F1:
		_hint_label.visible = not _hint_label.visible
		_hint_panel.visible = not _hint_panel.visible
		get_viewport().set_input_as_handled()
		return
	if not event.is_action_pressed("ui_cancel"):
		return
	if paused:
		if _pause.controls_open():
			_pause.close_controls()
		else:
			close_pause(true)
	elif _loot_panel.visible:
		hide_loot()
	else:
		open_pause()
	get_viewport().set_input_as_handled()


func apply_state(st: Dictionary) -> void:
	if st.has("health"):
		set_vital("health", float(st["health"]), float(st.get("max_health", 100.0)))
	if st.has("hunger"):
		set_vital("hunger", float(st["hunger"]), float(st.get("max_hunger", 100.0)))
	if st.has("thirst"):
		set_vital("thirst", float(st["thirst"]), float(st.get("max_thirst", 100.0)))
	if st.has("stamina"):
		set_vital("stamina", float(st["stamina"]), float(st.get("max_stamina", 100.0)))
	if st.has("ammo"):
		set_ammo(int(st["ammo"]), int(st.get("reserve", st.get("reserve_ammo", 0))))
	if st.get("weapon") is Dictionary:
		set_weapon(st["weapon"])


# ------------------------------------------------------------------ internals

func _process(delta: float) -> void:
	var on: bool = _net != null and _net.active
	visible = on
	if not on:
		return
	_poll_player()
	_ping_timer -= delta
	if _ping_timer <= 0.0:
		_ping_timer = 2.0
		if _net.is_host():
			_ping_label.text = "HOST"
		else:
			_net.ping()


func _poll_player() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = _net.get_local_player()
	if _player == null:
		return
	# Mouse sensitivity setting -> local player's existing look variable (no player.gd change).
	var want_sens: float = PauseMenu.sens_value()
	if not is_equal_approx(float(_player.get("mouse_sensitivity")), want_sens):
		_player.set("mouse_sensitivity", want_sens)
	var st := {}
	if _player.has_method("get_hud_state"):
		st = _player.get_hud_state()
	else:
		for k in ["health", "max_health", "hunger", "thirst", "ammo", "reserve_ammo"]:
			var v = _player.get(k)
			if v != null:
				st[k] = v
	apply_state(st)


func _refresh_build() -> void:
	if _building == null:
		return
	var s: Dictionary = _building.local_stock
	var mats := "PLANKS %d     SCRAP %d" % [int(s.get("planks", 0)), int(s.get("scrap", 0))]
	if _building.build_mode:
		var kind: String = _building.current_kind()
		_build_label.text = "BUILD MODE: %s\n1-5 / Wheel - Select     LMB - Place\nX / RMB - Remove     B - Exit\n%s" % [kind.to_upper(), mats]
	else:
		_build_label.text = "B - Build mode     " + mats


func _on_build_rejected(reason: String) -> void:
	set_prompt(reason, "buildmsg")
	get_tree().create_timer(2.0).timeout.connect(func(): set_prompt("", "buildmsg"))


## Always-visible controls strip (toggle: F1; H is already the medkit key). Matches Player.register_inputs.
const HINT_TEXT := "WASD Move   Shift Sprint   Ctrl Crouch   Space Jump\nLMB Shoot   RMB Aim   R Reload   1-5 Weapons\nE Interact   H Medkit   J Food   K Water\nB Build   Esc Menu / Controls   F1 Hide hints"
const FONT_BODY := 20
const FONT_BIG := 30


func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Vitals, top-left, on a dark backing.
	var vp := _panel(root, Control.PRESET_TOP_LEFT, 16, 16, 16, 16, false)
	var vitals := VBoxContainer.new()
	vp.add_child(vitals)
	vitals.add_child(_make_bar("health", "HEALTH", COL_HEALTH))
	vitals.add_child(_make_bar("stamina", "STAMINA", Color(0.55, 0.8, 0.3)))
	vitals.add_child(_make_bar("hunger", "FOOD", COL_HUNGER))
	vitals.add_child(_make_bar("thirst", "WATER", COL_THIRST))

	# Weapon + ammo + reload cue, bottom-right.
	_ammo_panel = _panel(root, Control.PRESET_BOTTOM_RIGHT, -360, -20, -20, -20, true)
	var abox := VBoxContainer.new()
	_ammo_panel.add_child(abox)
	_weapon_label = _text(FONT_BODY + 4, HORIZONTAL_ALIGNMENT_RIGHT)
	abox.add_child(_weapon_label)
	_ammo_label = _text(FONT_BIG + 4, HORIZONTAL_ALIGNMENT_RIGHT)
	_ammo_label.text = "AMMO  - / -"
	abox.add_child(_ammo_label)
	_ammo_hint = _text(FONT_BODY, HORIZONTAL_ALIGNMENT_RIGHT)
	abox.add_child(_ammo_hint)
	_ammo_panel.visible = false

	var cross := Control.new()
	cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cross.set_anchors_preset(Control.PRESET_CENTER)
	root.add_child(cross)
	for r in [Rect2(-12, -1, 8, 2), Rect2(4, -1, 8, 2), Rect2(-1, -12, 2, 8), Rect2(-1, 4, 2, 8)]:
		var cr := ColorRect.new()
		cr.color = Color(1, 1, 1, 0.85)
		cr.position = r.position
		cr.size = r.size
		cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cross.add_child(cr)

	# Messages (e.g. build rejections), below the player's own interaction prompt.
	_prompt_panel = _panel(root, Control.PRESET_CENTER, -250, 110, 250, 110, false)
	_prompt_label = _text(FONT_BODY + 4, HORIZONTAL_ALIGNMENT_CENTER)
	_prompt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_prompt_panel.add_child(_prompt_label)
	_prompt_panel.visible = false

	_build_label_panel(root)

	_ping_label = _make_label(root, Control.PRESET_TOP_RIGHT, Rect2(-216, 12, 200, 28), HORIZONTAL_ALIGNMENT_RIGHT, FONT_BODY)

	_hint_panel = _panel(root, Control.PRESET_TOP_RIGHT, -596, 46, -16, 46, false)
	_hint_panel.custom_minimum_size = Vector2(580, 0)
	_hint_label = _text(FONT_BODY, HORIZONTAL_ALIGNMENT_LEFT)
	_hint_label.text = HINT_TEXT
	_hint_panel.add_child(_hint_label)

	_loot_panel = PanelContainer.new()
	_loot_panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_loot_panel.offset_left = -400
	_loot_panel.offset_right = -20
	_loot_panel.offset_top = -190
	_loot_panel.offset_bottom = 190
	_loot_panel.visible = false
	root.add_child(_loot_panel)
	var box := VBoxContainer.new()
	_loot_panel.add_child(box)
	_loot_title = Label.new()
	_loot_title.text = "Loot"
	_loot_title.add_theme_font_size_override("font_size", 32)
	box.add_child(_loot_title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_loot_list = VBoxContainer.new()
	_loot_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_loot_list)
	var close := Button.new()
	close.text = "Close  (Esc)"
	PauseMenu.style_button(close)
	close.pressed.connect(hide_loot)
	box.add_child(close)


func _build_label_panel(root: Control) -> void:
	var p := _panel(root, Control.PRESET_CENTER_BOTTOM, -270, -20, 270, -20, true)
	_build_label = _text(FONT_BODY, HORIZONTAL_ALIGNMENT_CENTER)
	_build_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	p.add_child(_build_label)


## Dark rounded backing so text stays readable over the 3D world. Offsets are explicit;
## a zero-height rect shrinks to its content and grows up (bottom anchors) or down.
func _panel(parent: Control, preset: int, l: float, t: float, r: float, b: float, grow_up: bool) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.set_anchors_preset(preset as Control.LayoutPreset)
	p.offset_left = l
	p.offset_top = t
	p.offset_right = r
	p.offset_bottom = b
	if preset == Control.PRESET_TOP_RIGHT or preset == Control.PRESET_BOTTOM_RIGHT:
		p.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	elif preset == Control.PRESET_CENTER or preset == Control.PRESET_CENTER_BOTTOM:
		p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BEGIN if grow_up else Control.GROW_DIRECTION_END
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.6)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	p.add_theme_stylebox_override("panel", sb)
	parent.add_child(p)
	return p


func _text(font_size: int, align: int) -> Label:
	var l := Label.new()
	l.horizontal_alignment = align as HorizontalAlignment
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _make_label(parent: Control, preset: int, rect: Rect2, align: int, font_size: int) -> Label:
	var l := _text(font_size, align)
	l.set_anchors_preset(preset)
	l.offset_left = rect.position.x
	l.offset_top = rect.position.y
	l.offset_right = rect.position.x + rect.size.x
	l.offset_bottom = rect.position.y + rect.size.y
	parent.add_child(l)
	return l


func _make_bar(key: String, caption: String, color: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var l := _text(FONT_BODY, HORIZONTAL_ALIGNMENT_LEFT)
	l.text = caption
	l.custom_minimum_size = Vector2(100, 0)
	row.add_child(l)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(200, 22)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.show_percentage = false
	bar.max_value = 100.0
	bar.value = 100.0
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	bar.add_theme_stylebox_override("fill", fill)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.15, 0.15, 0.15, 0.8)
	bar.add_theme_stylebox_override("background", bg)
	row.add_child(bar)
	var v := _text(FONT_BODY, HORIZONTAL_ALIGNMENT_RIGHT)
	v.text = "100"
	v.custom_minimum_size = Vector2(44, 0)
	row.add_child(v)
	_bars[key] = bar
	_bar_vals[key] = v
	return row
