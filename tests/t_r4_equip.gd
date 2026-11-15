extends SceneTree
## Round 4 probe: a picked-up gun auto-equips (N2) and DayNight feeds the spawner (N1).

var fails := 0


func check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		fails += 1


func _init() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await create_timer(1.0).timeout
	var ItemDB = load("res://scripts/world/item_db.gd")
	var p = main.local_player
	check(p != null, "local player exists")
	if p != null:
		p.weapons.slots.clear()
		p.weapons.current_slot = -1
		ItemDB.give_to(p, "weapon_pistol", 1)
		ItemDB.give_to(p, "weapon_ak", 1)
		var cur: String = str(p.weapons.slots[p.weapons.current_slot]["id"]) if p.weapons.current_slot >= 0 else ""
		check(cur == "ak", "second picked-up gun auto-equips (current=%s)" % cur)
	var dn = main.world.day_night
	check(dn.is_in_group("daynight"), "DayNight in group daynight")
	dn.paused = true
	dn.set_time(0.0)
	await create_timer(6.0).timeout
	check(main.spawner.night_factor > 0.9, "spawner night_factor at midnight = %.2f" % main.spawner.night_factor)
	dn.set_time(12.0)
	await create_timer(6.0).timeout
	check(main.spawner.night_factor < 0.1, "spawner night_factor at noon = %.2f" % main.spawner.night_factor)
	quit(1 if fails > 0 else 0)
