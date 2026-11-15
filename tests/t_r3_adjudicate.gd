extends SceneTree
## Round 3 adjudication of t_core "picked-up planks become usable Building material" (stock 3 -> 3).
## Run: godot --headless --path . --script res://tests/t_r3_adjudicate.gd
## A: reproduce the t_core setup (player + host Net, but NO node in group "main_world").
## B: Building.give called directly works.
## C: same pickup with the real main.tscn present feeds Building.stock.

var fails := 0


func check(cond: bool, label: String) -> void:
	if cond:
		print("PASS  ", label)
	else:
		fails += 1
		print("FAIL  ", label)


func _initialize() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for _i in n:
		await physics_frame


func _stock(B: Node) -> int:
	return int(B.stock.get(1, {}).get("planks", 0))


func _run() -> void:
	await physics_frame
	var net: Node = root.get_node_or_null("Net")
	var B: Node = root.get_node_or_null("Building")
	var LootItem = load("res://scripts/world/loot_item.gd")
	check(net.host(17896, 4242) == OK, "Net.host ok")
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	cs.shape = box
	floor_body.add_child(cs)
	floor_body.position = Vector3(0, -0.5, 0)
	root.add_child(floor_body)
	var player: Node = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	player.name = "1"
	player.position = Vector3(0, 1, 0)
	root.add_child(player)
	await _frames(5)

	# A: t_core setup
	check(get_first_node_in_group("main_world") == null, "A: no node in group main_world (this is the t_core setup)")
	var s0 := _stock(B)
	var it = LootItem.create("planks", 5, 7001)
	root.add_child(it)
	it.interact(player)
	await _frames(2)
	var s1 := _stock(B)
	print("INFO  A: player planks=%d, Building.stock %d -> %d" % [player.count_item("planks"), s0, s1])
	check(player.count_item("planks") >= 5, "A: player inventory did receive the planks")
	check(s1 == s0, "A: reproduces the t_core result (stock unchanged without a main_world node)")

	# B: Building.give directly
	B.give("planks", 5)
	await _frames(1)
	var s2 := _stock(B)
	check(s2 == s1 + 5, "B: Building.give('planks',5) credits stock directly (%d -> %d)" % [s1, s2])

	# C: with the real main scene present
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _frames(10)
	check(get_first_node_in_group("main_world") == main, "C: main.tscn registers itself in group main_world")
	var it2 = LootItem.create("planks", 5, 7002)
	root.add_child(it2)
	it2.interact(player)
	await _frames(2)
	var s3 := _stock(B)
	check(s3 == s2 + 5, "C: with main_world present the same pickup feeds Building.stock (%d -> %d)" % [s2, s3])
	var it3 = LootItem.create("scrap", 3, 7003)
	root.add_child(it3)
	var sc0 := int(B.stock.get(1, {}).get("scrap", 0))
	it3.interact(player)
	await _frames(2)
	var sc1 := int(B.stock.get(1, {}).get("scrap", 0))
	check(sc1 == sc0 + 3, "C: scrap pickup feeds Building.stock (%d -> %d)" % [sc0, sc1])
	print("RESULT  failures=%d" % fails)
	net.leave()
	quit(1 if fails > 0 else 0)
