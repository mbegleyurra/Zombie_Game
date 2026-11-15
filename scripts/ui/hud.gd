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
var _ammo_label: Label
var _prompt_label: Label
var _build_label: Label
var _ping_label: Label
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


func set_ammo(mag: int, reserve: int) -> void:
	_ammo_label.text = "%d / %d" % [mag, reserve]


## Several systems may set prompts; the first non-empty source is shown.
func set_prompt(text: String, source: String = "game") -> void:
	_prompts[source] = text
	_prompt_label.text = ""
	for s in _prompts:
		if _prompts[s] != "":
			_prompt_label.text = _prompts[s]
			break


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
		b.pressed.connect(func(): loot_taken.emit(i))
		_loot_list.add_child(b)
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
	if not event.is_action_pressed("ui_cancel") or _net == null or not _net.active:
		return
	if paused:
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
	if st.has("ammo"):
		set_ammo(int(st["ammo"]), int(st.get("reserve", st.get("reserve_ammo", 0))))


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
	var mats := "PLANKS %d   SCRAP %d" % [int(s.get("planks", 0)), int(s.get("scrap", 0))]
	if _building.build_mode:
		var kind: String = _building.current_kind()
		_build_label.text = "BUILD: %s   [1-5/wheel] select  [LMB] place  [X/RMB] remove  [B] exit\n%s" % [kind.to_upper(), mats]
	else:
		_build_label.text = "[B] build   " + mats


func _on_build_rejected(reason: String) -> void:
	set_prompt(reason, "buildmsg")
	get_tree().create_timer(2.0).timeout.connect(func(): set_prompt("", "buildmsg"))


func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var vitals := VBoxContainer.new()
	vitals.position = Vector2(16, 16)
	root.add_child(vitals)
	vitals.add_child(_make_bar("health", "HEALTH", COL_HEALTH))
	vitals.add_child(_make_bar("hunger", "HUNGER", COL_HUNGER))
	vitals.add_child(_make_bar("thirst", "THIRST", COL_THIRST))

	_ammo_label = _make_label(root, Control.PRESET_BOTTOM_RIGHT, Rect2(-260, -70, 240, 50), HORIZONTAL_ALIGNMENT_RIGHT, 32)
	_ammo_label.text = "- / -"

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

	_prompt_label = _make_label(root, Control.PRESET_CENTER, Rect2(-250, 50, 500, 30), HORIZONTAL_ALIGNMENT_CENTER, 20)
	_build_label = _make_label(root, Control.PRESET_CENTER_BOTTOM, Rect2(-420, -70, 840, 55), HORIZONTAL_ALIGNMENT_CENTER, 16)
	_ping_label = _make_label(root, Control.PRESET_TOP_RIGHT, Rect2(-176, 12, 160, 24), HORIZONTAL_ALIGNMENT_RIGHT, 14)

	_loot_panel = PanelContainer.new()
	_loot_panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_loot_panel.offset_left = -340
	_loot_panel.offset_right = -20
	_loot_panel.offset_top = -160
	_loot_panel.offset_bottom = 160
	_loot_panel.visible = false
	root.add_child(_loot_panel)
	var box := VBoxContainer.new()
	_loot_panel.add_child(box)
	_loot_title = Label.new()
	_loot_title.text = "Loot"
	box.add_child(_loot_title)
	_loot_list = VBoxContainer.new()
	_loot_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_loot_list)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(hide_loot)
	box.add_child(close)


func _make_label(parent: Control, preset: int, rect: Rect2, align: int, font_size: int) -> Label:
	var l := Label.new()
	l.set_anchors_preset(preset)
	l.offset_left = rect.position.x
	l.offset_top = rect.position.y
	l.offset_right = rect.position.x + rect.size.x
	l.offset_bottom = rect.position.y + rect.size.y
	l.horizontal_alignment = align as HorizontalAlignment
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _make_bar(key: String, caption: String, color: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = caption
	l.custom_minimum_size = Vector2(76, 0)
	l.add_theme_font_size_override("font_size", 13)
	row.add_child(l)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(220, 16)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.show_percentage = false
	bar.max_value = 100.0
	bar.value = 100.0
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	bar.add_theme_stylebox_override("fill", fill)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.5)
	bar.add_theme_stylebox_override("background", bg)
	row.add_child(bar)
	_bars[key] = bar
	return row
