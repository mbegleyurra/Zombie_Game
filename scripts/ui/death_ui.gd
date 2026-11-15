extends Control
## Death screen with a Respawn button (and the R key). Owned by the Hud autoload.
## Shown while the local player is dead (polled, so it works for any cause of death and for every peer's own player).
## Respawn puts the player back on a world spawn point (Net.spawn_slot_for -> world.get_spawn_point, the same points the
## host uses for first spawn) and calls player.respawn(pos) on the owning peer; is_dead / position / health replicate
## through PlayerSync, so the other peers see it. Inventory and weapons are KEPT on death (Player.respawn does not touch
## them); health is restored and hunger / thirst are raised to at least 60.
## The mouse is freed while this screen is up and recaptured on respawn (unless the pause menu is open).

signal shown
signal respawned

const PauseMenu := preload("res://scripts/ui/pause_menu.gd")

const GROUP_OPEN := "ui_open"
const GROUP_ALL := "overlay_ui"
const FONT_TITLE := 84
const FONT_BODY := 26

var button: Button
## Tests: skip the Net/Hud gating and let bind_player drive the screen.
var standalone := false

var _player: Node = null
var _showing := false


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.25, 0.0, 0.0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	center.add_child(box)
	var title := Label.new()
	title.text = "YOU DIED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", FONT_TITLE)
	title.add_theme_color_override("font_color", Color(0.9, 0.12, 0.12))
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.add_theme_constant_override("outline_size", 8)
	box.add_child(title)
	var note := Label.new()
	note.text = "You keep your inventory and weapons."
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_font_size_override("font_size", FONT_BODY)
	box.add_child(note)
	button = Button.new()
	button.text = "Respawn  (R)"
	button.custom_minimum_size = Vector2(360, 72)
	PauseMenu.style_button(button)
	button.add_theme_font_size_override("font_size", 34)
	button.pressed.connect(respawn)
	box.add_child(button)


# ---------------------------------------------------------------- public API

func is_open() -> bool:
	return visible


## Points the screen at a player (the Hud finds the local one automatically when this is never called).
func bind_player(p: Node) -> void:
	_player = p


## Re-evaluates the screen against the bound player's is_dead. Called every frame by _process.
func update_state() -> void:
	var dead: bool = _player != null and is_instance_valid(_player) and bool(_player.get("is_dead"))
	if dead and not _showing:
		_show()
	elif not dead and _showing:
		_hide()
	if _showing and Input.mouse_mode != Input.MOUSE_MODE_VISIBLE and not _paused():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Where the local player respawns: the world's spawn point for this peer, with sane fallbacks.
func spawn_position() -> Vector3:
	var net := get_node_or_null("/root/Net")
	var id: int = int(net.local_id()) if net != null and net.has_method("local_id") else 0
	var slot: int = int(net.spawn_slot_for(id)) if net != null and net.has_method("spawn_slot_for") else 0
	var main := get_tree().get_first_node_in_group("main_world") if get_tree() != null else null
	var w = main.get("world") if main != null else null
	if w != null and is_instance_valid(w) and w.has_method("get_spawn_point"):
		return w.get_spawn_point(slot)
	if net != null and net.has_method("spawn_position_for"):
		return net.spawn_position_for(id)
	return Vector3(0.0, 3.0, 0.0)


## Respawns the bound player and closes the screen. Returns false when there is nobody dead to respawn.
func respawn() -> bool:
	if _player == null or not is_instance_valid(_player) or not bool(_player.get("is_dead")):
		return false
	_player.respawn(spawn_position())
	_hide()
	respawned.emit()
	return true


# ------------------------------------------------------------------ internals

func _process(_delta: float) -> void:
	if not standalone:
		var net := get_node_or_null("/root/Net")
		if net == null or not bool(net.active):
			if _showing:
				_hide(false)
			return
		if _player == null or not is_instance_valid(_player):
			_player = net.get_local_player()
	update_state()


func _input(event: InputEvent) -> void:
	if _showing and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_R:
		if respawn():
			get_viewport().set_input_as_handled()


func _show() -> void:
	_showing = true
	get_tree().call_group("overlay_ui", "close", false)   # inventory / map must not stay open under the death screen
	visible = true
	add_to_group(GROUP_OPEN)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	button.grab_focus.call_deferred()
	shown.emit()


func _hide(recapture: bool = true) -> void:
	_showing = false
	visible = false
	remove_from_group(GROUP_OPEN)
	if recapture and not _paused():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _paused() -> bool:
	if standalone:
		return false
	var hud := get_node_or_null("/root/Hud")
	return hud != null and bool(hud.is_paused())
