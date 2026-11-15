extends SceneTree
## Round 3: guns in the real game flow (Play Solo = Net.host_solo + main.tscn).
## Loot pickup -> equip with the real slot_N input action -> fire -> hit a zombie; build-mode gate;
## real-flow planks feed Building.stock; guns exist in generated worlds.
## Run: godot --headless --path . --script res://tests/t_r3_guns.gd

var fails := 0


func check(cond: bool, label: String) -> void:
	if cond:
		print("PASS  ", label)
	else:
		fails += 1
		print("FAIL  ", label)


func info(s: String) -> void:
	print("INFO  ", s)


func _initialize() -> void:
	_run.call_deferred()


func _until(cond: Callable, timeout: float) -> bool:
	var t := 0.0
	while t < timeout:
		if cond.call():
			return true
		await create_timer(0.1).timeout
		t += 0.1
	return cond.call()


func _rounds(w) -> int:
	var s: Dictionary = w.slots[w.current_slot]
	return int(s["mag"]) + (1 if bool(s["chambered"]) else 0)


func _press(w, action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	w._unhandled_input(ev)


func _slot_of(w, id: String) -> int:
	for i in w.slots.size():
		if str(w.slots[i]["id"]) == id:
			return i
	return -1


func _count_guns(world) -> int:
	var n := 0
	for id in world.loot_by_id:
		var node = world.loot_by_id[id]
		if node.is_in_group("loot_container"):
			for e in node.contents:
				if str(e["id"]).begins_with("weapon_"):
					n += 1
		elif str(node.item_id).begins_with("weapon_"):
			n += 1
	return n


func _run() -> void:
	await physics_frame
	var net: Node = root.get_node_or_null("Net")
	var B: Node = root.get_node_or_null("Building")
	var LootItem = load("res://scripts/world/loot_item.gd")
	check(net.host_solo(31337) == OK, "Net.host_solo ok")
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	for _i in 40:
		await physics_frame
	var p = net.players.get(1)
	check(p != null, "player spawned")
	if p == null:
		print("RESULT  failures=%d" % fails)
		quit(1)
		return
	var sp = get_first_node_in_group("spawner")
	if sp != null:
		sp.enabled = false
	var w = p.weapons
	for i in range(1, 6):
		check(InputMap.has_action("slot_%d" % i), "input action slot_%d exists" % i)

	# guns exist in generated worlds
	var g_main: int = _count_guns(main.world)
	info("guns in main world (seed 31337): %d" % g_main)
	check(g_main >= 1, "main world (seed 31337) contains at least one lootable gun (%d)" % g_main)
	for sd in [1, 2, 3, 20260101]:
		var wd: Node = (load("res://scenes/world/world.tscn") as PackedScene).instantiate()
		root.add_child(wd)
		wd.build(sd)
		var n := _count_guns(wd)
		check(n >= 1, "world seed %d contains at least one lootable gun (%d)" % [sd, n])
		wd.queue_free()
		await physics_frame

	# pick up each gun from a LootItem, equip with the slot key action, fire
	var order := ["ak", "m4", "shotgun", "hunting"]
	var lid := 9300
	for wid in order:
		var it = LootItem.create("weapon_" + wid, 1, lid)
		lid += 1
		main.add_child(it)
		var cur_before: String = w.weapon_data().id
		var ok: bool = it.interact(p)
		check(ok and w.has_weapon(wid), "loot pickup of weapon_%s gives the weapon" % wid)
		var auto_eq: bool = w.weapon_data().id == wid
		info("after loot pickup of %s current weapon is %s (was %s) auto-equipped=%s" % [wid, w.weapon_data().id, cur_before, str(auto_eq)])
		var idx := _slot_of(w, wid)
		_press(w, "slot_%d" % (idx + 1))
		check(w.weapon_data().id == wid, "slot key equips %s" % wid)
		await _until(func() -> bool: return int(w.state) == 0, 4.0)
		await _until(func() -> bool: return w._cooldown <= 0.0, 3.0)
		var fired := [0]
		var cb := func(_i: String) -> void: fired[0] += 1
		w.shot_fired.connect(cb)
		var r0: int = _rounds(w)
		w._try_fire(w.weapon_data())
		await physics_frame
		w.shot_fired.disconnect(cb)
		check(fired[0] == 1 and _rounds(w) == r0 - 1, "%s fires one round (rounds %d -> %d)" % [wid, r0, _rounds(w)])

	# hit a zombie with the AK
	_press(w, "slot_2")
	await _until(func() -> bool: return int(w.state) == 0, 4.0)
	await _until(func() -> bool: return w._cooldown <= 0.0, 3.0)
	if sp != null:
		var cam: Camera3D = p.camera
		var fwd: Vector3 = -cam.global_transform.basis.z
		var fh := Vector3(fwd.x, 0, fwd.z).normalized()
		var pos: Vector3 = cam.global_position + fh * 9.0
		pos.y = main.world.get_height(pos.x, pos.z) + 0.3
		var z = sp.spawn_zombie_at(pos, false)
		await create_timer(0.8).timeout
		var hp0: float = z.health
		info("camera forward before aiming (after 4 test shots of recoil): %s" % str(-cam.global_transform.basis.z))
		cam.look_at(z.global_position + Vector3(0, 1.0, 0), Vector3.UP)
		w._cooldown = 0.0
		w._try_fire(w.weapon_data())
		var hit: bool = await _until(func() -> bool: return not is_instance_valid(z) or z.health < hp0, 2.5)
		check(hit, "AK shot damages a zombie in front of the player (hp %.0f -> %.0f)" % [hp0, z.health if is_instance_valid(z) else -1.0])

	# build-mode gate on weapon input
	var cur: String = w.weapon_data().id
	B.build_mode = true
	check(w._build_mode_active(), "weapon controller sees Building.build_mode")
	_press(w, "slot_1")
	check(w.weapon_data().id == cur, "slot keys ignored in build mode (still %s)" % cur)
	B.build_mode = false
	_press(w, "slot_1")
	check(w.weapon_data().id == "pistol", "slot key works again outside build mode")
	var src := FileAccess.get_file_as_string("res://scripts/weapons/weapon_controller.gd")
	check(src.contains("if not captured or building:"), "STATIC: _handle_actions returns before firing in build mode (mouse capture is not available headless, so the live fire path is not exercised)")

	# loot planks in the real flow
	var s0 := int(B.stock.get(1, {}).get("planks", 0))
	var pl = LootItem.create("planks", 5, 9400)
	main.add_child(pl)
	pl.interact(p)
	await physics_frame
	var s1 := int(B.stock.get(1, {}).get("planks", 0))
	check(s1 == s0 + 5, "real flow: planks pickup feeds Building.stock (%d -> %d)" % [s0, s1])
	print("RESULT  failures=%d" % fails)
	net.leave()
	quit(1 if fails > 0 else 0)
