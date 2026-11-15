extends SceneTree
## Round 4, N2 (RAT): a picked-up gun is auto-equipped (no slot key needed). Real flow: host_solo + main.tscn.
## Also: picking up a gun already owned does not duplicate or switch; ammo pickup does not switch weapons.
## Run: godot --headless --path . --script res://tests/t_r4_rat_equip.gd

var fails := 0


func check(cond: bool, label: String) -> void:
	if cond:
		print("PASS  ", label)
	else:
		fails += 1
		print("FAIL  ", label)


func _initialize() -> void:
	_run.call_deferred()


func _cur_id(p) -> String:
	var wc = p.weapons
	if wc.current_slot < 0 or wc.current_slot >= wc.slots.size():
		return ""
	return str(wc.slots[wc.current_slot]["id"])


func _run() -> void:
	await physics_frame
	var net: Node = root.get_node_or_null("Net")
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
	check(_cur_id(p) == "pistol", "starts holding the pistol (%s)" % _cur_id(p))
	var n := 6000
	for id in ["ak", "m4", "shotgun", "hunting"]:
		var it = LootItem.create("weapon_" + id, 1, n)
		n += 1
		root.add_child(it)
		var ok: bool = it.interact(p)
		await physics_frame
		check(ok, "interact(weapon_%s) accepted" % id)
		check(p.weapons.has_weapon(id), "%s is in the inventory" % id)
		check(_cur_id(p) == id, "N2: %s auto-equipped on pickup, no slot key (current=%s)" % [id, _cur_id(p)])
	var slots_before: int = p.weapons.slots.size()
	p.weapons.equip(p.weapons._find_slot("ak"))
	var dup = LootItem.create("weapon_m4", 1, n)
	n += 1
	root.add_child(dup)
	dup.interact(p)
	await physics_frame
	check(p.weapons.slots.size() == slots_before, "second m4 pickup adds no slot (%d -> %d)" % [slots_before, p.weapons.slots.size()])
	check(_cur_id(p) == "ak", "second pickup of an owned gun does not change the weapon in hand (%s)" % _cur_id(p))
	var am = LootItem.create("ammo_556", 10, n)
	root.add_child(am)
	am.interact(p)
	await physics_frame
	check(_cur_id(p) == "ak", "ammo pickup does not change the weapon in hand (%s)" % _cur_id(p))
	var w = p.weapons
	var wd: WeaponData = WeaponDB.get_weapon("ak")
	w.state = WeaponController.State.READY
	w._cooldown = 0.0
	var s: Dictionary = w.slots[w.current_slot]
	var before: int = int(s["mag"]) + (1 if bool(s["chambered"]) else 0)
	w._try_fire(wd)
	s = w.slots[w.current_slot]
	var after: int = int(s["mag"]) + (1 if bool(s["chambered"]) else 0)
	check(after == before - 1, "auto-equipped ak fires one round (%d -> %d)" % [before, after])
	print("RESULT  failures=%d" % fails)
	quit(1 if fails > 0 else 0)
