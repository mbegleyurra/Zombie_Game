extends Control
## Escape / pause overlay: Resume, Disconnect, Quit. Built in code, owned by the Hud autoload.
## It does NOT pause the SceneTree: the game is networked, so the world keeps running for everyone.
## Buttons are public so tests can emit `pressed`.

signal resume_requested
signal disconnect_requested
signal quit_requested

var resume_btn: Button
var disconnect_btn: Button
var quit_btn: Button


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
	box.custom_minimum_size = Vector2(300, 0)
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

	resume_btn = _button(box, "Resume", resume_requested)
	disconnect_btn = _button(box, "Disconnect", disconnect_requested)
	quit_btn = _button(box, "Quit Game", quit_requested)


func _button(parent: Control, text: String, sig: Signal) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(func() -> void: sig.emit())
	parent.add_child(b)
	return b
