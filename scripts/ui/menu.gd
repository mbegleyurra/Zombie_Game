extends Control
## Main menu, built entirely in code. Play Solo / Host / Join (IP[:port]) / Quit.
## Command line shortcuts (after `--`): --solo, --host  or  --join=<ip[:port]>

var _net = null
var _ip: LineEdit
var _status: Label
## Public so headless tests can emit `pressed`.
var solo_btn: Button
var host_btn: Button
var join_btn: Button
var quit_btn: Button


func _ready() -> void:
	_net = get_node_or_null("/root/Net")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build()
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
	box.custom_minimum_size = Vector2(340, 0)
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)

	var title := Label.new()
	title.text = "DEAD ACRES"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 56)
	box.add_child(title)
	var sub := Label.new()
	sub.text = "Co-op survival, 2-4 players"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)

	solo_btn = Button.new()
	solo_btn.text = "Play Solo"
	solo_btn.pressed.connect(_on_solo)
	box.add_child(solo_btn)

	host_btn = Button.new()
	host_btn.text = "Host Game"
	host_btn.pressed.connect(_on_host)
	box.add_child(host_btn)

	_ip = LineEdit.new()
	_ip.placeholder_text = "Host IP (e.g. 192.168.1.20 or ip:port)"
	_ip.text = "127.0.0.1"
	box.add_child(_ip)
	join_btn = Button.new()
	join_btn.text = "Join Game"
	join_btn.pressed.connect(_on_join)
	box.add_child(join_btn)

	quit_btn = Button.new()
	quit_btn.text = "Quit"
	quit_btn.pressed.connect(func(): get_tree().quit())
	box.add_child(quit_btn)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)
