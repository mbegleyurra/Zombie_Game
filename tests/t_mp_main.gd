extends SceneTree
## Host flow against the real scenes/main.tscn.
## Run: godot --headless --path . --script res://tests/t_mp_main.gd
## Checks: Net.host works, the baked map is identical regardless of Net.world_seed, and exactly one local player
## exists after host().

var fails := 0


func check(cond: bool, label: String) -> void:
	if cond:
		print("PASS  ", label)
	else:
		fails += 1
		print("FAIL  ", label)


func _initialize() -> void:
	_run.call_deferred()


## md5 of what makes up the map: every location (type, name, position) and the ground height on a 40 m grid.
func _world_sig(w: Node) -> String:
	if w == null or not w.has_method("get_locations"):
		return ""
	var parts := PackedStringArray()
	for l in w.get_locations():
		var p2: Vector2 = l["pos2"]
		parts.append("%s|%s|%.2f,%.2f" % [l["type"], l["name"], p2.x, p2.y])
	for gx in range(-240, 241, 40):
		for gz in range(-240, 241, 40):
			parts.append("%.3f" % w.get_height(float(gx), float(gz)))
	return "\n".join(parts).md5_text()


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
	# The world is baked (scenes/world/world_baked.tscn), so the host's Net seed must NOT change it: every peer loads
	# the identical map. Compare the host's world with a standalone world built from a different seed.
	var other: Node3D = (load("res://scenes/world/world.tscn") as PackedScene).instantiate()
	root.add_child(other)
	other.build(1)
	var sig_main := _world_sig(main.world)
	var sig_other := _world_sig(other)
	check(sig_main != "" and sig_main == sig_other, "world map is identical regardless of Net.world_seed (Net seed=%d vs seed 1: %s / %s)" % [host_seed, sig_main, sig_other])
	other.queue_free()
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
