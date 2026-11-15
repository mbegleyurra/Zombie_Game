extends SceneTree
## Solo (Net inactive) flow on the real main.tscn: seed fallback, one local player, one spawner.
## Run: godot --headless --path . --script res://tests/t_solo_r2.gd

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
	await physics_frame
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	for _i in 30:
		await physics_frame
	check(main.world.world_seed == 20260101, "solo seed fallback 20260101 (got %d)" % main.world.world_seed)
	check(get_nodes_in_group("players").size() == 1, "one local player solo (%d)" % get_nodes_in_group("players").size())
	check(get_nodes_in_group("spawner").size() == 1, "one spawner solo")
	var p: Node = get_nodes_in_group("players")[0] if get_nodes_in_group("players").size() > 0 else null
	if p != null:
		print("INFO  weapons: ", p.weapons.slots.map(func(s): return s["id"]))
	print("RESULT  failures=%d" % fails)
	quit(1 if fails > 0 else 0)
