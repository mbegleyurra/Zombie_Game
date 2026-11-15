extends Control
## Escape / pause overlay: Resume, Controls, Disconnect, Quit. Built in code, owned by the Hud autoload.
## It does NOT pause the SceneTree: the game is networked, so the world keeps running for everyone.
## Buttons are public so tests can emit `pressed`.
##
## This script also holds the shared controls/keybind help panel and the mouse sensitivity setting
## (static helpers) so the main menu can reuse them. Sensitivity is stored as a percent of the
## player's default look speed in user://settings.cfg; the Hud applies it to the local player.

signal resume_requested
signal disconnect_requested
signal quit_requested

const BASE_SENS := 0.0022  # matches Player.mouse_sensitivity default
const SENS_MIN := 25.0
const SENS_MAX := 300.0
const SETTINGS_PATH := "user://settings.cfg"
const BTN_SIZE := Vector2(340, 54)
const BTN_FONT := 22
const KEY_COL := Color(0.95, 0.8, 0.35)
## [action, keys] shown on the controls screen. Matches Player.register_inputs and Building.
const CONTROL_ROWS := [
	["Move", "W A S D  /  Arrow keys"],
	["Look", "Mouse"],
	["Sprint", "Shift (while moving forward)"],
	["Crouch", "Ctrl  /  C"],
	["Jump", "Space"],
	["Fire", "Left mouse button"],
	["Aim", "Right mouse button"],
	["Reload", "R"],
	["Weapon slots", "1 - 5"],
	["Interact / loot", "E"],
	["Medkit / Food / Water", "H  /  J  /  K"],
	["Build mode", "B  (1-5 or wheel select, LMB place, X or RMB remove, F door)"],
	["Pause / back", "Esc"],
	["Hide HUD hints", "F1"],
]

static var _sens_pct: float = -1.0

var resume_btn: Button
var controls_btn: Button
var disconnect_btn: Button
var quit_btn: Button
var controls_panel: Control


# ------------------------------------------------------------ shared settings

static func sens_pct() -> float:
	if _sens_pct < 0.0:
		var pct := 100.0
		var cf := ConfigFile.new()
		if cf.load(SETTINGS_PATH) == OK:
			pct = float(cf.get_value("controls", "sens_pct", 100.0))
		_sens_pct = clampf(pct, SENS_MIN, SENS_MAX)
	return _sens_pct


static func set_sens_pct(pct: float) -> void:
	_sens_pct = clampf(pct, SENS_MIN, SENS_MAX)
	var cf := ConfigFile.new()
	cf.load(SETTINGS_PATH)  # keep any other saved keys; a missing file is fine
	cf.set_value("controls", "sens_pct", _sens_pct)
	cf.save(SETTINGS_PATH)


## Radians per pixel to give Player.mouse_sensitivity.
static func sens_value() -> float:
	return BASE_SENS * sens_pct() / 100.0


static func style_button(b: Button) -> void:
	b.custom_minimum_size = BTN_SIZE
	b.add_theme_font_size_override("font_size", BTN_FONT)
	b.focus_mode = Control.FOCUS_ALL


## Full-screen, initially hidden controls help + sensitivity slider. on_back is called by the Back
## button; the owner is responsible for Esc handling. Panel meta: "back_btn", "slider".
static func make_controls_panel(on_back: Callable) -> Control:
	var panel := Control.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.04, 0.03, 0.92)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(620, 0)
	box.add_theme_constant_override("separation", 8)
	center.add_child(box)

	var title := Label.new()
	title.text = "CONTROLS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	box.add_child(title)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 32)
	grid.add_theme_constant_override("v_separation", 4)
	box.add_child(grid)
	for row in CONTROL_ROWS:
		var a := Label.new()
		a.text = row[0]
		a.custom_minimum_size = Vector2(210, 0)
		a.add_theme_font_size_override("font_size", 18)
		grid.add_child(a)
		var k := Label.new()
		k.text = row[1]
		k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		k.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		k.add_theme_font_size_override("font_size", 18)
		k.add_theme_color_override("font_color", KEY_COL)
		grid.add_child(k)

	var sens_row := HBoxContainer.new()
	sens_row.add_theme_constant_override("separation", 16)
	box.add_child(sens_row)
	var sl := Label.new()
	sl.text = "Mouse sensitivity"
	sl.custom_minimum_size = Vector2(210, 0)
	sl.add_theme_font_size_override("font_size", 18)
	sens_row.add_child(sl)
	var slider := HSlider.new()
	slider.min_value = SENS_MIN
	slider.max_value = SENS_MAX
	slider.step = 5.0
	slider.value = sens_pct()
	slider.custom_minimum_size = Vector2(260, 34)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.focus_mode = Control.FOCUS_ALL
	sens_row.add_child(slider)
	var val := Label.new()
	val.text = "%d%%" % int(slider.value)
	val.custom_minimum_size = Vector2(60, 0)
	val.add_theme_font_size_override("font_size", 18)
	sens_row.add_child(val)
	slider.value_changed.connect(func(v: float) -> void:
		val.text = "%d%%" % int(v)
		set_sens_pct(v))

	var note := Label.new()
	note.text = "Menus: arrow keys / D-pad to move, Enter / A to select, Esc / B to go back.\nIn-game actions are keyboard and mouse only."
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_font_size_override("font_size", 14)
	note.modulate = Color(1, 1, 1, 0.7)
	box.add_child(note)

	var back := Button.new()
	back.text = "Back"
	style_button(back)
	back.pressed.connect(func() -> void: on_back.call())
	box.add_child(back)
	panel.set_meta("back_btn", back)
	panel.set_meta("slider", slider)
	return panel


# -------------------------------------------------------------------- overlay

func _ready() -> void:
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(340, 0)
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)

	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	box.add_child(title)
	var note := Label.new()
	note.text = "The world keeps running."
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(note)

	resume_btn = _button(box, "Resume", func() -> void: resume_requested.emit())
	controls_btn = _button(box, "Controls", open_controls)
	disconnect_btn = _button(box, "Disconnect", func() -> void: disconnect_requested.emit())
	quit_btn = _button(box, "Quit Game", func() -> void: quit_requested.emit())

	var hint := Label.new()
	hint.text = "Esc / B: resume"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 14)
	hint.modulate = Color(1, 1, 1, 0.7)
	box.add_child(hint)

	controls_panel = make_controls_panel(close_controls)
	add_child(controls_panel)
	visibility_changed.connect(_on_visibility_changed)


func _button(parent: Control, text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	style_button(b)
	b.pressed.connect(on_press)
	parent.add_child(b)
	return b


func _on_visibility_changed() -> void:
	if visible:
		controls_panel.visible = false
		resume_btn.grab_focus()


func controls_open() -> bool:
	return controls_panel != null and controls_panel.visible


func open_controls() -> void:
	controls_panel.visible = true
	(controls_panel.get_meta("back_btn") as Button).grab_focus()


func close_controls() -> void:
	controls_panel.visible = false
	if visible:
		controls_btn.grab_focus()
