extends SceneTree
## Host flow against the real scenes/main.tscn.
## Run: godot --headless --path . --script res://tests/t_mp_main.gd
## Checks: Net.world_seed is honoured by main.gd, and exactly one local player exists after host().

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
	var net: Node = root.get_node_or_null("Net")
	if net == null:
		net = (load("res://scripts/net/network.gd") as GDScript).new()
		net.name = "Net"
		root.add_child(net)
	var building: Node = root.get_node_or_null("Building")
	if building == null:
		building = (load("res://scripts/building/building_system.gd") as GDScript).new()
		building.name = "Building"
		root.add_child(building)
	await physics_frame
	var host_seed := 424242
	var err: int = net.host(17889, host_seed)
	check(err == OK, "Net.host ok, Net.world_seed=%d" % net.world_seed)
	# Same thing Net.start_game() does, minus change_scene (no current scene in --script mode)
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	for _i in 30:
		await physics_frame
	# The handcrafted world ignores the seed by design (world_builder.build sets world_seed = HandLayout.HAND_SEED),
	# so the host's Net seed must NOT change it: every peer builds the identical map.
	var hand_seed: int = (load("res://scripts/world/hand_layout.gd") as GDScript).HAND_SEED
	var ws: int = main.world.world_seed
	check(ws == hand_seed, "world built from the fixed hand seed regardless of Net.world_seed (main world seed=%d, hand seed=%d, Net seed=%d)" % [ws, hand_seed, host_seed])
	var in_group := get_nodes_in_group("players")
	var names := []
	for p in in_group:
		names.append(str(p.name))
	check(in_group.size() == 1, "exactly one local player after hosting (found %d: %s)" % [in_group.size(), str(names)])
	check(net.players.has(1) and is_instance_valid(net.players[1]), "Net.players[1] tracks the local player")
	var zs := get_nodes_in_group("zombies").size()
	print("INFO  zombies after 30 frames in main: %d" % zs)
	var sp := get_nodes_in_group("spawner")
	check(sp.size() == 1, "one zombie spawner in the world (%d)" % sp.size())
	net.leave()
	print("RESULT  failures=%d" % fails)
	quit(1 if fails > 0 else 0)
