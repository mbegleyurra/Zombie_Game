extends Camera3D
## Placeholder free-fly camera used by main.gd when res://scenes/player/player.tscn does not exist yet.
## Click to capture the mouse, WASD/QE to fly, Shift = fast, Esc releases the mouse.

@export var speed: float = 25.0
var _yaw: float = 0.0
var _pitch: float = -0.35


func _ready() -> void:
	current = true
	rotation = Vector3(_pitch, _yaw, 0.0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * 0.003
		_pitch = clampf(_pitch - event.relative.y * 0.003, -1.5, 1.5)
		rotation = Vector3(_pitch, _yaw, 0.0)


func _process(delta: float) -> void:
	var dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		dir -= global_transform.basis.z
	if Input.is_key_pressed(KEY_S):
		dir += global_transform.basis.z
	if Input.is_key_pressed(KEY_A):
		dir -= global_transform.basis.x
	if Input.is_key_pressed(KEY_D):
		dir += global_transform.basis.x
	if Input.is_key_pressed(KEY_E):
		dir += Vector3.UP
	if Input.is_key_pressed(KEY_Q):
		dir -= Vector3.UP
	if dir != Vector3.ZERO:
		var s: float = speed * (3.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0)
		global_position += dir.normalized() * s * delta
