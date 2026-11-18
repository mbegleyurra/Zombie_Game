extends SceneTree
## More ammo: every WeaponDB gun has a reachable ammo source (loot table + workbench recipe), and the
## starting reserve, duplicate-gun pickup, crafted batch and loot amounts are >= 1.5x the old values.
## Run: godot --headless --path . --script res://tests/t_more_ammo.gd

const IDB = preload("res://scripts/world/item_db.gd")
const Recipes = preload("res://scripts/world/recipes.gd")

## Values before the ammo boost.
const OLD_CRAFT := {"9mm": 30, "556": 30, "762": 20, "12ga": 12, "545": 30, "68": 30, "300": 30}
const OLD_START_9MM := 45

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
	check(WeaponDB.START_RESERVE_9MM >= int(ceil(OLD_START_9MM * 1.5)), "starting 9mm reserve %d >= %d" % [WeaponDB.START_RESERVE_9MM, int(ceil(OLD_START_9MM * 1.5))])
	for id in WeaponDB.ids():
		var wd: WeaponData = WeaponDB.get_weapon(id)
		var cal: String = wd.caliber
		var item: String = IDB.ammo_item_for(cal)
		check(item != "" and IDB.reserve_key(item) == cal, "%s: caliber %s maps to ammo item %s" % [id, cal, item])
		# duplicate-gun pickup: old value was one magazine
		check(WeaponDB.dup_pickup_rounds(wd) >= int(ceil(wd.mag_size * 1.5)), "%s: duplicate pickup %d rounds >= 1.5 mags (%d)" % [id, WeaponDB.dup_pickup_rounds(wd), wd.mag_size])
		# workbench recipe
		var rc := Recipes.get_recipe("ammo_" + cal)
		var old: int = int(OLD_CRAFT.get(cal, 20))
		check(not rc.is_empty() and int(rc["count"]) >= int(ceil(old * 1.5)), "%s: craft batch %d >= %d" % [id, int(rc.get("count", 0)), int(ceil(old * 1.5))])
		# world loot: at least one table can drop this ammo
		var tables_with: Array = []
		for t in IDB.table_names():
			for e in (IDB._tables()[t]["entries"] as Array):
				if str(e[0]) == item:
					tables_with.append(t)
					break
		check(not tables_with.is_empty(), "%s: ammo %s drops from tables %s" % [id, item, str(tables_with)])
	# loot amounts: sampled minimum is at least 1.5x the old minimum for known entries
	check(IDB.AMMO_LOOT_MULT >= 2, "AMMO_LOOT_MULT = %d" % IDB.AMMO_LOOT_MULT)
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var old_min := {"police": ["ammo_9mm", 8], "gas_station": ["ammo_9mm", 6], "farm": ["ammo_12ga", 2]}
	for t in old_min:
		var want: String = old_min[t][0]
		var lo := 1 << 30
		for _i in 3000:
			var p: Dictionary = IDB.pick_one(t, rng)
			if str(p["id"]) == want:
				lo = mini(lo, int(p["count"]))
		check(lo >= int(ceil(int(old_min[t][1]) * 1.5)), "%s %s min drop %d >= %d" % [t, want, lo, int(ceil(int(old_min[t][1]) * 1.5))])
	print("t_more_ammo fails=", fails)
	quit(1 if fails > 0 else 0)
