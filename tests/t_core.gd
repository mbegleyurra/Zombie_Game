extends SceneTree
## Core gameplay headless test: player, 5 weapons, zombie states, building, loot.
## Run: godot --headless --path . --script res://tests/t_core.gd
## Does not edit game code. Uses Net/Building autoloads (or creates them if absent).

var fails := 0
var net: Node
var building: Node
var player
var w


func check(cond: bool, label: String) -> void:
	if cond:
		print("PASS  ", label)
	else:
		fails += 1
		print("FAIL  ", label)


func info(msg: String) -> void:
	print("INFO  ", msg)


func _initialize() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for _i in n:
		await physics_frame


func _secs(s: float) -> void:
	await create_timer(s).timeout


func _mk(path: String, node_name: String) -> Node:
	var n: Node = (load(path) as GDScript).new()
	n.name = node_name
	root.add_child(n)
	return n


func _run() -> void:
	net = root.get_node_or_null("Net")
	if net == null:
		net = _mk("res://scripts/net/network.gd", "Net")
		info("Net autoload not present in --script mode; created manually")
	building = root.get_node_or_null("Building")
	if building == null:
		building = _mk("res://scripts/building/building_system.gd", "Building")
		info("Building autoload not present in --script mode; created manually")
	await _frames(2)

	# ------------------------------------------------------------ floor + player
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 1, 400)
	cs.shape = box
	floor_body.add_child(cs)
	floor_body.position = Vector3(0, -0.5, 0)
	root.add_child(floor_body)

	var packed: PackedScene = load("res://scenes/player/player.tscn")
	check(packed != null, "player.tscn loads")
	player = packed.instantiate()
	player.name = "1"
	player.position = Vector3(0, 3.0, 0)
	root.add_child(player)
	await _frames(5)
	var y_early: float = player.global_position.y
	await _frames(60)
	var y_late: float = player.global_position.y
	check(y_late < y_early or y_late < 0.5, "player falls under gravity (%.2f -> %.2f)" % [y_early, y_late])
	await _secs(1.0)
	check(player.is_on_floor(), "player settles on floor (y=%.2f)" % player.global_position.y)
	check(player.health == 100.0 and not player.is_dead, "player starts alive with 100 hp")
	check(player.camera != null and player.camera.current, "player camera is current")
	w = player.weapons
	check(w != null and w.has_weapon("pistol"), "player has starting pistol")

	# movement probe
	var p0: Vector3 = player.global_position
	# Input-driven movement is gated on Input.mouse_mode == CAPTURED (player.gd), which cannot be
	# set headless, so drive velocity directly and verify the character body actually moves/collides.
	info("headless mouse capture unavailable (mode=%d); key-driven movement NOT verifiable here" % Input.mouse_mode)
	player.velocity.x = 4.0
	await _secs(0.5)
	var moved := p0.distance_to(player.global_position)
	# (player.gd decelerates to 0 in ~0.1 s when no input, so only a small displacement is expected)
	check(moved > 0.05, "player body moves under velocity (%.2f m)" % moved)
	player.global_position = Vector3(0, 0.1, 0)
	player.velocity = Vector3.ZERO

	# ------------------------------------------------------------------ weapons
	for id in ["pistol", "ak", "m4", "shotgun", "hunting"]:
		await _test_weapon(id)

	# fire-while-building gap
	await _test_fire_in_build_mode()

	# -------------------------------------------------------------------- zombies
	await _test_zombie()

	# ------------------------------------------------------------ building + loot
	await _test_building_and_loot()

	print("RESULT  failures=%d" % fails)
	quit(1 if fails > 0 else 0)


# ===================================================================== weapons

func _ready_weapon(id: String) -> WeaponData:
	var wd: WeaponData = WeaponDB.get_weapon(id)
	if not w.has_weapon(id):
		w.give_weapon(id)
	w.equip(w._find_slot(id))
	w.state = WeaponController.State.READY
	w._cooldown = 0.0
	w._update_timers(1.0, wd)
	return wd


func _loaded(wd_id: String) -> int:
	var s: Dictionary = w.slots[w._find_slot(wd_id)]
	return int(s["mag"]) + (1 if bool(s["chambered"]) else 0)


func _test_weapon(id: String) -> void:
	var wd := _ready_weapon(id)
	player.add_item(wd.caliber, 200 - player.count_item(wd.caliber))
	player.look_pitch = 0.0
	player.head.rotation_degrees.x = 0.0
	var fired := [0]
	var cb := func(_wid: String) -> void: fired[0] += 1
	w.shot_fired.connect(cb)
	var before := _loaded(id)
	check(before == wd.mag_size, "%s: given loaded = mag_size %d rounds (has %d)" % [id, wd.mag_size, before])
	w._cooldown = 0.0
	w._try_fire(wd)
	var after := _loaded(id)
	check(fired[0] == 1 and after == before - 1, "%s: fires once, ammo %d -> %d, shot_fired x%d" % [id, before, after, fired[0]])
	# empty the magazine
	var guard := 0
	while _loaded(id) > 0 and guard < 200:
		guard += 1
		w._cooldown = 0.0
		w.state = WeaponController.State.READY
		w._try_fire(wd)
	check(_loaded(id) == 0, "%s: magazine empties after firing (%d shots total)" % [id, fired[0]])
	check(fired[0] == before, "%s: shots fired == rounds loaded (%d vs %d)" % [id, fired[0], before])
	# empty + trigger: must start a reload using reserve ammo, never fire
	var reserve_before: int = player.count_item(wd.caliber)
	w._cooldown = 0.0
	w.state = WeaponController.State.READY
	var shots_before: int = fired[0]
	w._try_fire(wd)
	check(w.state == WeaponController.State.RELOADING and fired[0] == shots_before, "%s: empty trigger pull starts reload, no shot" % id)
	var g := 0
	while w.state == WeaponController.State.RELOADING and g < 60:
		g += 1
		w._update_timers(10.0, wd)
	var reserve_after: int = player.count_item(wd.caliber)
	var loaded_now := _loaded(id)
	check(w.state == WeaponController.State.READY and loaded_now >= wd.mag_size - 1, "%s: empty reload completes (%d loaded)" % [id, loaded_now])
	check(reserve_before - reserve_after == loaded_now, "%s: reserve %s %d -> %d matches rounds loaded %d" % [id, wd.caliber, reserve_before, reserve_after, loaded_now])
	# tactical reload: fire one, reload
	w._cooldown = 0.0
	w._try_fire(wd)
	var ok: bool = w.start_reload()
	check(ok, "%s: manual reload accepted with a partly empty mag" % id)
	g = 0
	while w.state == WeaponController.State.RELOADING and g < 60:
		g += 1
		w._update_timers(10.0, wd)
	check(_loaded(id) >= wd.mag_size, "%s: tactical reload tops up to %d (has %d)" % [id, wd.mag_size, _loaded(id)])
	# no reserve: reload refused
	var save: int = player.count_item(wd.caliber)
	player.remove_item(wd.caliber, save)
	w._cooldown = 0.0
	w._try_fire(wd)
	check(not w.start_reload(), "%s: reload refused with no reserve ammo" % id)
	player.add_item(wd.caliber, save)
	w.shot_fired.disconnect(cb)
	w._recoil_target = Vector2.ZERO
	w._recoil_cur = Vector2.ZERO


func _test_fire_in_build_mode() -> void:
	var wd := _ready_weapon("ak")
	info("--- fire while Building.build_mode is true")
	var src := FileAccess.get_file_as_string("res://scripts/weapons/weapon_controller.gd")
	var src2 := FileAccess.get_file_as_string("res://scripts/player/player.gd")
	var refs := src.contains("build_mode") or src.contains("Building") or src2.contains("build_mode")
	check(refs, "weapon/player code consults Building.build_mode before firing")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	building.set_build_mode(true)
	w._cooldown = 0.0
	w.state = WeaponController.State.READY
	var before := _loaded("ak")
	Input.action_press("fire")
	w._handle_actions(wd)
	Input.action_release("fire")
	var after := _loaded("ak")
	building.set_build_mode(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if captured:
		check(after == before, "weapon does NOT fire while in build mode (ammo %d -> %d)" % [before, after])
	else:
		info("mouse capture not available headless; dynamic probe inconclusive (static check above applies)")
	w._recoil_target = Vector2.ZERO
	w._recoil_cur = Vector2.ZERO


# ===================================================================== zombies

func _test_zombie() -> void:
	info("--- zombie")
	player.global_position = Vector3(0, 0.1, 0)
	player.velocity = Vector3.ZERO
	var z = (load("res://scenes/zombies/zombie.tscn") as PackedScene).instantiate()
	z.position = Vector3(0, 0.05, -22)
	z.rotation.y = 0.0   # faces -Z, player is behind it
	root.add_child(z)
	var died_count := [0]
	z.died.connect(func(_z) -> void: died_count[0] += 1)
	await _frames(10)
	check(z.is_in_group("zombies"), "zombie in group zombies")
	check(z.state_id == Zombie.State.IDLE or z.state_id == Zombie.State.WANDER, "zombie starts IDLE/WANDER (state %d)" % z.state_id)
	check(z.health == z.max_health, "zombie starts at full health %.0f" % z.health)
	z.hear_noise(player.global_position, 60.0)
	check(z.state_id == Zombie.State.INVESTIGATE, "noise -> INVESTIGATE (state %d)" % z.state_id)
	z.alert_to(player)
	check(z.state_id == Zombie.State.CHASE, "alert -> CHASE (state %d)" % z.state_id)
	await _secs(1.0)
	var d: float = z.global_position.distance_to(player.global_position)
	check(d < 22.0 - 1.0, "chasing zombie closes distance (%.1f m after 1 s)" % d)
	z.global_position = player.global_position + Vector3(0, 0.05, -1.0)
	z.velocity = Vector3.ZERO
	var hp0: float = player.health
	var saw_attack := false
	var t := 0.0
	while t < 3.0:
		await _secs(0.1)
		t += 0.1
		if z.state_id == Zombie.State.ATTACK:
			saw_attack = true
		if player.health < hp0:
			break
	check(saw_attack, "adjacent zombie enters ATTACK")
	check(player.health < hp0, "zombie attack damages player (%.1f -> %.1f)" % [hp0, player.health])
	# shot via weapon controller
	z.request_damage(30.0, false, 1)
	check(z.health == z.max_health - 30.0, "zombie takes damage (hp %.1f)" % z.health)
	z.request_damage(10000.0, false, 1)
	check(z.state_id == Zombie.State.DEAD and died_count[0] == 1, "lethal damage -> DEAD, died emitted once")
	z.request_damage(50.0, false, 1)
	check(died_count[0] == 1 and z.health == 0.0, "dead zombie ignores further damage")
	# spawner
	var sp_script: GDScript = load("res://scripts/zombies/spawner.gd")
	var sp = sp_script.new()
	sp.enabled = false
	root.add_child(sp)
	await _frames(2)
	var nz = sp.spawn_zombie_at(Vector3(15, 0.1, 15), true)
	check(nz != null and nz.runner, "spawner.spawn_zombie_at(runner) works")
	sp.kill_all()
	await _frames(3)
	sp.queue_free()
	player.health = 100.0


# ================================================================ building+loot

func _test_building_and_loot() -> void:
	info("--- building and loot")
	var err: int = net.host(17888, 4242)
	check(err == OK, "Net.host ok")
	await _frames(3)
	var B = building
	check(int(B.stock.get(1, {}).get("planks", 0)) == 20, "host starts with 20 planks in Building.stock")
	var rejected := [""]
	B.build_rejected.connect(func(r: String) -> void: rejected[0] = r)
	var k_wall := Vector4i(0, 0, 0, 1)
	B.request_place("wall", k_wall)
	await _frames(3)
	check(B.pieces.size() == 1, "wall placed (%d pieces)" % B.pieces.size())
	check(int(B.local_stock["planks"]) == 16, "wall cost 4 planks (planks=%d)" % int(B.local_stock["planks"]))
	var pid := 0
	for id in B.pieces:
		pid = id
	var node: Node3D = B.pieces[pid]["node"]
	check(node.find_children("*", "CollisionShape3D", true, false).size() > 0, "wall piece has collision")
	B.request_place("wall", k_wall)
	await _frames(2)
	check(rejected[0] == "Occupied", "duplicate slot rejected (%s)" % rejected[0])
	B.request_place("floor", k_wall)
	await _frames(2)
	check(rejected[0] == "Bad slot", "floor in edge slot rejected (%s)" % rejected[0])
	B.request_place("door", Vector4i(1, 0, 0, 1))
	await _frames(3)
	var door_id := 0
	for id in B.pieces:
		if B.pieces[id]["kind"] == "door":
			door_id = id
	check(door_id != 0, "door placed")
	B.request_toggle(door_id)
	await _frames(3)
	check(door_id != 0 and bool(B.pieces[door_id]["open"]), "door toggles open")
	B.request_place("floor", Vector4i(0, 0, 0, 0))
	await _frames(3)
	check(B.pieces.size() == 3, "floor placed (%d pieces)" % B.pieces.size())
	var planks_before := int(B.local_stock["planks"])
	B.request_remove(pid)
	await _frames(3)
	check(not B.pieces.has(pid) and B.slots.is_empty() == false, "wall removed, slot freed")
	check(int(B.local_stock["planks"]) == planks_before + 2, "remove refunds half cost (planks %d -> %d)" % [planks_before, int(B.local_stock["planks"])])
	# exhaust materials
	rejected[0] = ""
	for i in 12:
		B.request_place("wall", Vector4i(10 + i, 0, 0, 1))
	await _frames(3)
	check(rejected[0] == "Not enough materials", "placing without materials rejected (%s)" % rejected[0])
	# zombies vs building (server API exists; does any zombie code call it?)
	var zsrc := FileAccess.get_file_as_string("res://scripts/zombies/zombie.gd")
	check(zsrc.contains("damage_piece"), "zombie.gd attacks building pieces (Building.damage_piece)")

	# ---- loot pickup
	# ItemDB.give_to credits Building.stock only through a node in group "main_world" (main.gd),
	# so instantiate the real main scene first, as t_loot_r2 does (Round 3 adjudication).
	var main_scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main_scene)
	await _frames(10)
	check(get_first_node_in_group("main_world") == main_scene, "main.tscn present and registered in group main_world")
	var LootItem = load("res://scripts/world/loot_item.gd")
	var item = LootItem.create("9mm", 7, 5001)
	root.add_child(item)
	player.global_position = Vector3(3, 0.1, 3)
	item.global_position = Vector3(3, 0.1, 2)
	await _frames(2)
	var n9: int = player.count_item("9mm")
	var picked := [false]
	item.picked_up.connect(func(_i, _b) -> void: picked[0] = true)
	var okp: bool = item.interact(player)
	await _frames(2)
	check(okp and picked[0] and player.count_item("9mm") == n9 + 7, "loot_item pickup adds 7 x 9mm to player (%d -> %d)" % [n9, player.count_item("9mm")])
	check(not is_instance_valid(item), "picked-up item removed from world")
	# loot ammo -> weapon reserve (loot ids are ammo_<cal>, weapons count their own caliber key)
	for pair in [["ammo_9mm", "9mm"], ["ammo_556", "556"], ["ammo_762", "762"], ["ammo_12ga", "12ga"]]:
		var ai = LootItem.create(pair[0], 10, 5100)
		root.add_child(ai)
		var cal_before: int = player.count_item(pair[1])
		ai.interact(player)
		await _frames(1)
		check(player.count_item(pair[1]) == cal_before + 10, "picked-up %s usable as weapon reserve '%s' (%d -> %d)" % [pair[0], pair[1], cal_before, player.count_item(pair[1])])
	# any weapon obtainable from the world?
	var idb := FileAccess.get_file_as_string("res://scripts/world/item_db.gd")
	var obtainable := idb.contains("\"ak\"") or idb.contains("\"shotgun\"") or idb.contains("\"m4\"") or idb.contains("\"hunting\"")
	check(obtainable, "ak/m4/shotgun/hunting rifle can be found as loot (item_db has weapon items)")
	# loot -> building materials
	var stock_before := int(B.stock[1]["planks"])
	var pl_item = LootItem.create("planks", 5, 5002)
	root.add_child(pl_item)
	pl_item.interact(player)
	await _frames(2)
	var stock_after := int(B.stock[1]["planks"])
	info("player inventory planks=%d, Building.stock planks %d -> %d" % [player.count_item("planks"), stock_before, stock_after])
	check(stock_after == stock_before + 5, "picked-up planks become usable Building material")
	# container
	var LootContainer = load("res://scripts/world/loot_container.gd")
	var c1 = LootContainer.new()
	c1.setup(77, "crate", "farm", 4242)
	var c2 = LootContainer.new()
	c2.setup(77, "crate", "farm", 4242)
	check(str(c1.contents) == str(c2.contents), "container contents deterministic for (seed,id)")
	root.add_child(c1)
	c1.global_position = Vector3(6, 0.1, 6)
	await _frames(2)
	check(c1.contents.size() > 0, "container rolled contents (%s)" % str(c1.contents))
	var inv_before: int = 0
	for k in player.inventory:
		inv_before += int(player.inventory[k])
	var oc: bool = c1.interact(player)
	var inv_after: int = 0
	for k in player.inventory:
		inv_after += int(player.inventory[k])
	var expect := 0
	for it in c1.contents:
		expect += int(it["count"])
	check(oc and c1.is_open and inv_after - inv_before == expect, "container search gives all contents (+%d of %d)" % [inv_after - inv_before, expect])
	check(not c1.interact(player), "opened container cannot be searched twice")
	net.leave()
	c1.free()
	c2.free()
