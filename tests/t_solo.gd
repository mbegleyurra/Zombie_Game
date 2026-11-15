extends SceneTree
## Play Solo flow: Net.host_solo -> seed set -> main.tscn -> exactly one player per peer; Building.give feeds stock.
## Run: godot --headless --path . --script res://tests/t_solo.gd

var fails := 0


func check(cond: bool, label: String) -> void:
	print("%s  %s" % ["PASS" if cond else "FAIL", label])
	if not cond:
		fails += 1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var net: Node = root.get_node("Net")
	var b: Node = root.get_node("Building")
	check(net.host_solo() == OK, "host_solo() ok")
	check(net.active and net.is_host(), "Net.active and host")
	check(net.world_seed != 0, "world_seed set before scene load (%d)" % net.world_seed)
	check(net.start_game() == OK, "start_game() ok")
	for i in 90:
		await process_frame
	var main := current_scene
	check(main != null and main.scene_file_path == "res://scenes/main.tscn", "main.tscn loaded")
	var n := 0
	for p in get_nodes_in_group("players"):
		n += 1
		print("  player node: ", p.get_path())
	check(n == 1, "exactly one player for solo (%d)" % n)
	check(net.players.size() == 1 and net.players.has(1), "Net.players = {1}")
	var before := int(b.local_stock["planks"])
	b.give("planks", 3)
	check(int(b.local_stock["planks"]) == before + 3, "Building.give(planks,3): %d -> %d" % [before, int(b.local_stock["planks"])])
	b.give("scrap", 2)
	b.give("food", 5)
	check(int(b.local_stock["scrap"]) == 10 + 2, "Building.give(scrap,2); non-building item ignored")
	print("RESULT  failures=%d" % fails)
	quit(1 if fails > 0 else 0)
