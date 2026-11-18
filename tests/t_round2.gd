extends SceneTree
## Round 2 checks for the player/weapons/zombies owner: ammo id aliases, weapon pickup,
## build-mode gate, zombie vs player-built piece, spawner safety.
## Run: godot --headless --path . --script res://tests/t_round2.gd

var fails := 0
var building: Node
var player
var w


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
	if root.get_node_or_null("Net") == null:
		_mk("res://scripts/net/network.gd", "Net")
	building = root.get_node_or_null("Building")
	if building == null:
		building = _mk("res://scripts/building/building_system.gd", "Building")
	await _frames(2)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 1, 400)
	cs.shape = box
	floor_body.add_child(cs)
	floor_body.position = Vector3(0, -0.5, 0)
	root.add_child(floor_body)
	player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	player.name = "1"
	player.position = Vector3(0, 0.2, 0)
	root.add_child(player)
	await _frames(30)
	w = player.weapons

	# (4) ammo id aliases
	var pairs := {"ammo_9mm": "9mm", "ammo_556": "556", "ammo_762": "762", "ammo_12ga": "12ga"}
	for loot_id in pairs:
		var cal: String = pairs[loot_id]
		var before: int = player.count_item(cal)
		player.add_item(loot_id, 10)
		check(player.count_item(cal) == before + 10, "%s pickup raises %s reserve %d -> %d" % [loot_id, cal, before, player.count_item(cal)])
		check(player.count_item(loot_id) == player.count_item(cal), "count_item(%s) == count_item(%s)" % [loot_id, cal])
	check(not player.inventory.has("ammo_556"), "no stray ammo_556 key in inventory")
	player.add_item("556", 5)
	player.give_weapon("m4")
	w.equip(w._find_slot("m4"))
	check(int(w.status()["reserve"]) == 15, "m4 status reserve counts loot ammo (%s)" % str(w.status()["reserve"]))
	var took: int = player.remove_item("ammo_556", 4)
	check(took == 4 and player.count_item("556") == 11, "remove_item(ammo_556) removes from 556 reserve")

	# (6) weapon pickup
	check(not w.has_weapon("ak"), "ak not owned before pickup")
	player.add_item("ak", 1)
	check(w.has_weapon("ak"), "add_item('ak') gives the weapon")
	check(w.weapon_data() != null and w.weapon_data().id == "ak", "new weapon is equipped")
	check(not player.inventory.has("ak"), "weapon id is not stored as a stackable item")
	player.add_item("hunting rifle", 1)
	check(w.has_weapon("hunting"), "'hunting rifle' alias gives hunting")
	player.add_item("shotgun", 1)
	check(w.has_weapon("shotgun"), "shotgun pickup")
	var r762: int = player.count_item("762")
	player.add_item("ak", 1)
	check(player.count_item("762") == r762 + WeaponDB.dup_pickup_rounds(WeaponDB.get_weapon("ak")), "duplicate ak pickup gives %d mags of 762 (%d -> %d)" % [WeaponDB.DUP_PICKUP_MAGS, r762, player.count_item("762")])
	player.add_item("planks", 3)
	check(player.count_item("planks") == 3, "non-weapon items still stack")

	# (8) build-mode gate
	building.build_mode = false
	check(not w._build_mode_active(), "build mode off -> gate open")
	building.build_mode = true
	check(w._build_mode_active(), "build mode on -> weapons gated")
	building.build_mode = false

	# (9) zombie breaks a built wall that blocks it
	# Building.damage_piece is server-only: it needs Net.active (offline peer is the server).
	root.get_node("Net").active = true
	var key := Vector4i(0, 0, -6, building.SLOT_EDGE_X)
	building._add_piece(900, "wall", key, 100.0, false)
	var wp: Vector3 = building.key_position(key)
	check(building.pieces.has(900), "test wall placed")
	player.global_position = Vector3(wp.x, 0.1, wp.z - 4.0)
	player.velocity = Vector3.ZERO
	var z = (load("res://scenes/zombies/zombie.tscn") as PackedScene).instantiate()
	z.position = Vector3(wp.x, 0.05, wp.z + 1.6)
	root.add_child(z)
	await _frames(10)
	z.alert_to(player)
	var hp0 := 100.0
	var t := 0.0
	while t < 5.0 and building.pieces.has(900) and float(building.pieces[900]["hp"]) >= hp0:
		await _frames(6)
		t += 0.1
		z._target = player   # keep aggro even though the wall blocks sight
		z._lost_timer = 0.0
	var gone: bool = not building.pieces.has(900)
	var hp_now: float = 0.0 if gone else float(building.pieces[900]["hp"])
	check(gone or hp_now < hp0, "zombie damaged the wall (hp %.0f -> %.0f)" % [hp0, hp_now])

	# (1) spawner can be instanced from code
	var sp := ZombieSpawner.new()
	sp.name = "ZombieSpawner"
	check(sp.alive_count() == 0, "spawner.alive_count() safe before _ready")
	root.add_child(sp)
	await _frames(3)
	check(sp.container != null and sp.is_in_group("spawner"), "spawner builds container + joins group")
	check(sp.get_node_or_null("ZombieMP") != null, "spawner has MultiplayerSpawner child")

	print("RESULT  failures=%d" % fails)
	quit(1 if fails > 0 else 0)
