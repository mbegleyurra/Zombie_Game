extends Control
## Main menu, built entirely in code. Play Solo / Host / Join (IP[:port]) / Quit.
## Command line shortcuts (after `--`): --solo, --host  or  --join=<ip[:port]>
## Controls button opens the shared keybind help + mouse sensitivity panel (Esc / B closes it).

const PauseMenu := preload("res://scripts/ui/pause_menu.gd")

var _net = null
var _ip: LineEdit
var _status: Label
## Public so headless tests can emit `pressed`.
var solo_btn: Button
var host_btn: Button
var join_btn: Button
var controls_btn: Button
var quit_btn: Button
var controls_panel: Control


func _ready() -> void:
	_net = get_node_or_null("/root/Net")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build()
	solo_btn.grab_focus.call_deferred()
	if _net == null:
		_status.text = "Net autoload missing (check project.godot)"
		return
	_net.world_seed_received.connect(_go)
	_net.connection_failed.connect(func(reason: String): _status.text = reason)
	_net.server_closed.connect(func(): _status.text = "Host closed the game")
	for arg in OS.get_cmdline_user_args():
		if arg == "--solo":
			_on_solo.call_deferred()
		elif arg == "--host":
			_on_host.call_deferred()
		elif arg.begins_with("--join="):
			_ip.text = arg.substr(7)
			_on_join.call_deferred()


## Solo = loopback-only host, so Net.active is true and building works.
func _on_solo() -> void:
	if _net.host_solo() != OK:
		return
	_go(_net.world_seed)


func _on_host() -> void:
	var err: int = _net.host(Net_default_port())
	if err != OK:
		return
	_status.text = "Hosting on port %d (max 4 players)" % Net_default_port()
	_go(0)


func _on_join() -> void:
	var text := _ip.text.strip_edges()
	var port: int = Net_default_port()
	var addr := text
	if ":" in text:
		addr = text.get_slice(":", 0)
		port = int(text.get_slice(":", 1))
	if addr == "":
		addr = "127.0.0.1"
	_status.text = "Connecting to %s:%d ..." % [addr, port]
	_net.join(addr, port)


func _go(_seed: int) -> void:
	var err: int = _net.start_game()
	if err != OK:
		_status.text = "World scene (scenes/main.tscn) is not available yet"
		_net.leave()


func Net_default_port() -> int:
	return _net.DEFAULT_PORT


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and controls_panel != null and controls_panel.visible:
		_close_controls()
		get_viewport().set_input_as_handled()


func _open_controls() -> void:
	controls_panel.visible = true
	(controls_panel.get_meta("back_btn") as Button).grab_focus()


func _close_controls() -> void:
	controls_panel.visible = false
	controls_btn.grab_focus()


func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.08, 0.06)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(520, 0)
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)

	var title := Label.new()
	title.text = "DEAD ACRES"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 72)
	box.add_child(title)
	var sub := Label.new()
	sub.text = "Co-op survival, 2-4 players"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 26)
	box.add_child(sub)

	solo_btn = Button.new()
	solo_btn.text = "Play Solo"
	PauseMenu.style_button(solo_btn)
	solo_btn.pressed.connect(_on_solo)
	box.add_child(solo_btn)

	host_btn = Button.new()
	host_btn.text = "Host Game"
	PauseMenu.style_button(host_btn)
	host_btn.pressed.connect(_on_host)
	box.add_child(host_btn)

	_ip = LineEdit.new()
	_ip.placeholder_text = "Host IP (e.g. 192.168.1.20 or ip:port)"
	_ip.text = "127.0.0.1"
	_ip.custom_minimum_size = Vector2(0, 52)
	_ip.add_theme_font_size_override("font_size", 22)
	_ip.text_submitted.connect(func(_t: String) -> void: _on_join())
	box.add_child(_ip)
	join_btn = Button.new()
	join_btn.text = "Join Game"
	PauseMenu.style_button(join_btn)
	join_btn.pressed.connect(_on_join)
	box.add_child(join_btn)

	controls_btn = Button.new()
	controls_btn.text = "Controls"
	PauseMenu.style_button(controls_btn)
	controls_btn.pressed.connect(_open_controls)
	box.add_child(controls_btn)

	quit_btn = Button.new()
	quit_btn.text = "Quit"
	PauseMenu.style_button(quit_btn)
	quit_btn.pressed.connect(func(): get_tree().quit())
	box.add_child(quit_btn)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 22)
	box.add_child(_status)

	var tip := Label.new()
	tip.text = "Play Solo to start. Open Controls to see every key.\nIn game: E - Interact   LMB - Shoot   R - Reload   Esc - Menu"
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.add_theme_font_size_override("font_size", 20)
	tip.modulate = Color(1, 1, 1, 0.85)
	box.add_child(tip)

	controls_panel = PauseMenu.make_controls_panel(_close_controls)
	add_child(controls_panel)
