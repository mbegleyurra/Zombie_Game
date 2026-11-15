extends SceneTree
## Round 2 loot checks: weapons from pickups, ammo reserve keys, planks/scrap -> Building.stock.
## Run: godot --headless --path . --script res://tests/t_loot_r2.gd

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
	var ItemDB = load("res://scripts/world/item_db.gd")
	var LootItem = load("res://scripts/world/loot_item.gd")
	var net: Node = root.get_node_or_null("Net")
	var building: Node = root.get_node_or_null("Building")
	await physics_frame
	var host_seed := 777
	check(net.host(17891, host_seed) == OK, "host")
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	for _i in 30:
		await physics_frame
	var p: Node = net.players.get(1)
	check(p != null, "player spawned by Net")
	if p == null:
		quit(1)
		return
	for wid in ["pistol", "ak", "m4", "shotgun", "hunting"]:
		var item_id: String = "weapon_" + wid
		check(ItemDB.has_item(item_id), "item_db has " + item_id)
		var it = LootItem.create(item_id, 1, 9000)
		main.add_child(it)
		check(it.interact(p), "pickup " + item_id)
		check(p.weapons.weapon_ids().has(wid), "player has " + wid)
	for pair in [["ammo_9mm", "9mm"], ["ammo_556", "556"], ["ammo_762", "762"], ["ammo_12ga", "12ga"]]:
		var before: int = p.count_item(pair[1])
		var it2 = LootItem.create(pair[0], 10, 9001)
		main.add_child(it2)
		it2.interact(p)
		check(p.count_item(pair[1]) == before + 10, "%s -> reserve %s" % [pair[0], pair[1]])
	check(ItemDB.canonical("5.56") == "ammo_556" and ItemDB.canonical("ammo_556") == "ammo_556", "both id forms resolve")
	var before_pl: int = int(building.stock.get(1, {}).get("planks", 0))
	var it3 = LootItem.create("planks", 5, 9002)
	main.add_child(it3)
	it3.interact(p)
	var after_pl: int = int(building.stock.get(1, {}).get("planks", 0))
	check(after_pl == before_pl + 5, "planks pickup feeds Building.stock (%d -> %d)" % [before_pl, after_pl])
	var sp := get_nodes_in_group("spawner")
	check(sp.size() == 1, "one spawner")
	net.leave()
	print("RESULT  failures=%d" % fails)
	quit(1 if fails > 0 else 0)
