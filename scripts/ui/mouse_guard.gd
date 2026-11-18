extends Node
## Keeps the mouse inside the game window while the game wants it captured.
## Some virtual machines (absolute-pointer / tablet integration) ignore Godot's
## pointer grab, so the cursor drifts out of the window. This guard:
##  1. re-applies CAPTURED whenever the window regains focus or the mouse re-enters,
##  2. falls back to recentring the pointer if it drifts toward the window edge
##     while the mode is CAPTURED.

const EDGE_MARGIN := 40.0

var _want_captured := false
var _just_warped := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_window().focus_entered.connect(_reapply)
	get_window().mouse_entered.connect(_reapply)


func _process(_delta: float) -> void:
	# Track what the game asked for: CAPTURED means the game wants a locked mouse.
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_want_captured = true
	elif Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		_want_captured = false


func _reapply() -> void:
	if _want_captured and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_reapply()


func _input(event: InputEvent) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or not (event is InputEventMouseMotion):
		return
	var win := get_window()
	var size := Vector2(win.size)
	var center := size * 0.5
	var motion := event as InputEventMouseMotion
	if _just_warped and motion.position.distance_to(center) < 4.0:
		# This motion event was caused by our own warp; do not turn it into a camera jump.
		_just_warped = false
		get_viewport().set_input_as_handled()
		return
	var p := motion.position
	if p.x < EDGE_MARGIN or p.y < EDGE_MARGIN \
			or p.x > size.x - EDGE_MARGIN or p.y > size.y - EDGE_MARGIN:
		_just_warped = true
		Input.warp_mouse(center)
