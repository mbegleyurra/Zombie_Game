extends SceneTree
## QA (RAT): mouse sensitivity setting. Checks clamping, the radians-per-pixel conversion, persistence to
## user://settings.cfg and that the Hud pushes the value onto the local player. The user's real settings file is
## backed up first and restored at the end (set_sens_pct writes to it).
## Run: godot --headless --path . --script res://tests/t_qa_sens.gd

const PauseMenu := preload("res://scripts/ui/pause_menu.gd")   # no class_name: the Hud preloads it the same way

var fails := 0


func check(cond: bool, label: String) -> void:
	if cond:
		print("PASS  ", label)
	else:
		fails += 1
		print("FAIL  ", label)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var path: String = PauseMenu.SETTINGS_PATH
	var had := FileAccess.file_exists(path)
	var backup := FileAccess.get_file_as_string(path) if had else ""
	PauseMenu._sens_pct = -1.0
	PauseMenu.set_sens_pct(100.0)
	check(is_equal_approx(PauseMenu.sens_value(), PauseMenu.BASE_SENS), "100%% = base sensitivity (%.4f rad/px)" % PauseMenu.sens_value())
	PauseMenu.set_sens_pct(200.0)
	check(is_equal_approx(PauseMenu.sens_value(), PauseMenu.BASE_SENS * 2.0) or PauseMenu.sens_pct() == PauseMenu.SENS_MAX, "200%% doubles sensitivity (or clamps to max %.0f)" % PauseMenu.SENS_MAX)
	PauseMenu.set_sens_pct(-50.0)
	check(PauseMenu.sens_pct() == PauseMenu.SENS_MIN, "below-range value clamps to SENS_MIN (%.0f)" % PauseMenu.sens_pct())
	PauseMenu.set_sens_pct(99999.0)
	check(PauseMenu.sens_pct() == PauseMenu.SENS_MAX, "above-range value clamps to SENS_MAX (%.0f)" % PauseMenu.sens_pct())
	PauseMenu.set_sens_pct(150.0)
	PauseMenu._sens_pct = -1.0   # simulate a fresh launch: must reload from disk
	check(is_equal_approx(PauseMenu.sens_pct(), clampf(150.0, PauseMenu.SENS_MIN, PauseMenu.SENS_MAX)), "value persists across a reload (%.0f)" % PauseMenu.sens_pct())
	var cf := ConfigFile.new()
	check(cf.load(path) == OK and cf.has_section_key("controls", "sens_pct"), "settings.cfg has [controls] sens_pct")

	# the Hud applies it to the local player (real solo flow)
	PauseMenu.set_sens_pct(150.0)
	var net: Node = root.get_node_or_null("Net")
	net.host_solo(4242)
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	for _i in 60:
		await physics_frame
	var p = net.players.get(1)
	check(p != null, "local player exists")
	if p != null:
		check(is_equal_approx(float(p.mouse_sensitivity), PauseMenu.sens_value()), "Hud applied sensitivity to the player (%.5f vs %.5f)" % [float(p.mouse_sensitivity), PauseMenu.sens_value()])
		PauseMenu.set_sens_pct(50.0)
		for _i in 10:
			await physics_frame
			await process_frame
		check(is_equal_approx(float(p.mouse_sensitivity), PauseMenu.sens_value()), "Hud follows a later change to 50%% (%.5f)" % float(p.mouse_sensitivity))

	# restore the real settings file exactly as it was
	if had:
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(backup)
		f.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	PauseMenu._sens_pct = -1.0
	print("RESULT  failures=", fails)
	quit(1 if fails > 0 else 0)
