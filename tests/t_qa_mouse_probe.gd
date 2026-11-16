extends SceneTree
## QA probe (RAT): does headless Godot retain Input.mouse_mode = CAPTURED? Explains t_respawn mouse-recapture failures.
func _init() -> void:
	print("start mode=", Input.mouse_mode, " display=", DisplayServer.get_name())
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	print("after set CAPTURED, read=", Input.mouse_mode)
	await process_frame
	print("next frame read=", Input.mouse_mode)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	print("after set VISIBLE, read=", Input.mouse_mode)
	quit(0)
