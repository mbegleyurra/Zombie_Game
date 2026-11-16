extends SceneTree
## Workbench build piece: placement, slot rules, cost, collider, refund, and crafting gated on a bench.
## Run: godot --headless --path . --script res://tests/t_workbench.gd

var fails := 0
var net: Node
var building: Node
var player


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


func _mk(path: String, node_name: String) -> Node:
	var n: Node = (load(path) as GDScript).new()
	n.name = node_name
	root.add_child(n)
	return n


func _run() -> void:
	net = root.get_node_or_null("Net")
	if net == null:
		net = _mk("res://scripts/net/network.gd", "Net")
	building = root.get_node_or_null("Building")
	if building == null:
		building = _mk("res://scripts/building/building_system.gd", "Building")
	await _frames(2)
	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 1, 400)
	cs.shape = box
	floor_body.add_child(cs)
	floor_body.position = Vector3(0, -0.5, 0)
	root.add_child(floor_body)
	player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	player.name = "1"
	player.position = Vector3(0, 0.1, 0)
	root.add_child(player)
	await _frames(5)
	check(net.host(17931, 4242) == OK, "Net.host ok")
	net.players[1] = player
	await _frames(3)
	var B = building
	var rejected := [""]
	var crafted := []
	B.build_rejected.connect(func(r: String) -> void: rejected[0] = r)
	B.crafted.connect(func(id: String) -> void: crafted.append(id))

	check(B.KINDS.has("workbench"), "workbench is a build kind")
	var cost: Dictionary = B.DEFS["workbench"]["cost"]
	check(cost.keys().all(func(k): return k == "planks" or k == "scrap") and cost.size() == 2, "workbench costs planks and scrap only")

	# crafting needs a bench
	var nine0: int = player.count_item("9mm")
	B.request_craft("ammo_9mm")
	await _frames(2)
	check(rejected[0] == "Need a workbench nearby", "craft without a bench rejected (%s)" % rejected[0])
	check(player.count_item("9mm") == nine0 and crafted.is_empty(), "nothing granted without a bench")

	# place
	var key := Vector4i(0, 0, 0, B.SLOT_BENCH)
	B.request_place("workbench", key)
	await _frames(3)
	check(B.pieces.size() == 1, "workbench placed (%d pieces)" % B.pieces.size())
	var pid := 0
	for id in B.pieces:
		pid = id
	check(B.pieces[pid]["kind"] == "workbench", "piece kind is workbench")
	check(int(B.local_stock["planks"]) == 20 - int(cost["planks"]) and int(B.local_stock["scrap"]) == 10 - int(cost["scrap"]),
		"workbench cost taken (planks=%d scrap=%d)" % [int(B.local_stock["planks"]), int(B.local_stock["scrap"])])
	var node: Node3D = B.pieces[pid]["node"]
	check(node is StaticBody3D and node.find_children("*", "CollisionShape3D", true, false).size() >= 5, "workbench has a solid collider")
	check(node.find_children("*", "MeshInstance3D", true, false).size() >= 5, "workbench has a model")
	check(node.is_in_group("workbench") and node.is_in_group("building"), "workbench is in groups workbench/building")
	check(node.position.is_equal_approx(Vector3(1, 0, 1)), "workbench sits on the cell centre %s" % str(node.position))

	# slot rules
	rejected[0] = ""
	B.request_place("workbench", key)
	await _frames(2)
	check(rejected[0] == "Occupied", "second bench in same slot rejected (%s)" % rejected[0])
	rejected[0] = ""
	B.request_place("workbench", Vector4i(3, 0, 3, B.SLOT_FLOOR))
	await _frames(2)
	check(rejected[0] == "Bad slot", "workbench in floor slot rejected (%s)" % rejected[0])
	rejected[0] = ""
	B.request_place("floor", Vector4i(5, 0, 5, B.SLOT_BENCH))
	await _frames(2)
	check(rejected[0] == "Bad slot", "floor in bench slot rejected (%s)" % rejected[0])
	rejected[0] = ""
	B.request_place("wall", Vector4i(5, 0, 5, B.SLOT_BENCH))
	await _frames(2)
	check(rejected[0] == "Bad slot", "wall in bench slot rejected (%s)" % rejected[0])
	B.request_place("floor", Vector4i(0, 0, 0, B.SLOT_FLOOR))
	await _frames(3)
	check(B.pieces.size() == 2, "bench and floor share one cell (%d pieces)" % B.pieces.size())

	# crafting at the bench
	var planks0: int = int(B.local_stock["planks"])
	var scrap0: int = int(B.local_stock["scrap"])
	var rc: Dictionary = (load("res://scripts/world/recipes.gd") as GDScript).get_recipe("ammo_9mm")
	rejected[0] = ""
	B.request_craft("ammo_9mm")
	await _frames(3)
	check(crafted == ["ammo_9mm"], "crafted signal fired (%s)" % str(crafted))
	check(player.count_item("9mm") == nine0 + int(rc["count"]), "9mm ammo granted (+%d)" % int(rc["count"]))
	check(int(B.local_stock["planks"]) == planks0 - int(rc["cost"]["planks"]) and int(B.local_stock["scrap"]) == scrap0 - int(rc["cost"]["scrap"]),
		"craft cost taken from stock (planks=%d scrap=%d)" % [int(B.local_stock["planks"]), int(B.local_stock["scrap"])])
	rejected[0] = ""
	B.request_craft("no_such_recipe")
	await _frames(2)
	check(rejected[0] == "Unknown recipe", "unknown recipe rejected (%s)" % rejected[0])

	# materials gate
	rejected[0] = ""
	B.request_place("workbench", Vector4i(1, 0, 0, B.SLOT_BENCH))
	await _frames(2)
	check(rejected[0] == "Not enough materials", "second bench without materials rejected (%s)" % rejected[0])

	# remove: refund, then crafting is closed again
	var p1: int = int(B.local_stock["planks"])
	var s1: int = int(B.local_stock["scrap"])
	B.request_remove(pid)
	await _frames(3)
	check(not B.pieces.has(pid), "workbench removed")
	check(int(B.local_stock["planks"]) == p1 + int(int(cost["planks"]) * 0.5) and int(B.local_stock["scrap"]) == s1 + int(int(cost["scrap"]) * 0.5),
		"remove refunds half cost")
	rejected[0] = ""
	B.request_craft("ammo_9mm")
	await _frames(2)
	check(rejected[0] == "Need a workbench nearby", "craft after removing the bench rejected (%s)" % rejected[0])

	# ghost preview has no collider
	var ghost: Node3D = B._make_piece("workbench", true)
	check(ghost.find_children("*", "CollisionShape3D", true, false).is_empty() and ghost.find_children("*", "MeshInstance3D", true, false).size() >= 5,
		"ghost preview is mesh-only")
	ghost.free()

	print("t_workbench fails=", fails)
	quit(1 if fails > 0 else 0)
