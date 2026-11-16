extends SceneTree
## Crafting: recipe data, rifle tiers, ammo for every WeaponDB gun, ItemDB/GunMesh entries,
## end-to-end host crafting of every recipe, and the crafting overlay.
## Run: godot --headless --path . --script res://tests/t_crafting.gd

const Recipes = preload("res://scripts/world/recipes.gd")
const IDB = preload("res://scripts/world/item_db.gd")
const CraftingUI = preload("res://scripts/ui/crafting_ui.gd")

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
	_test_data()
	await _test_end_to_end()
	print("t_crafting fails=", fails)
	quit(1 if fails > 0 else 0)


func _test_data() -> void:
	# --- rifles
	var tiers := ["ar_t1", "ar_t2", "ar_t3"]
	var prev = null
	var cals := {}
	for id in tiers:
		check(WeaponDB.has_weapon(id), "%s is in WeaponDB" % id)
		var wd := WeaponDB.get_weapon(id)
		var rc := Recipes.get_recipe("gun_" + id)
		check(not rc.is_empty() and rc["kind"] == "weapon" and rc["give"] == id, "%s has a weapon recipe" % id)
		var only_mats: bool = rc["cost"].keys().all(func(k): return k == "planks" or k == "scrap")
		check(only_mats and int(rc["cost"].get("planks", 0)) > 0 and int(rc["cost"].get("scrap", 0)) > 0, "%s costs planks and scrap only" % id)
		check(IDB.has_item("weapon_" + id) and IDB.get_item("weapon_" + id)["weapon_id"] == id, "%s has an ItemDB weapon entry" % id)
		check(IDB.ammo_item_for(wd.caliber) != "" and IDB.reserve_key(IDB.ammo_item_for(wd.caliber)) == wd.caliber, "%s ammo type %s is in ItemDB with matching reserve key" % [id, wd.caliber])
		check(not cals.has(wd.caliber) and not ["9mm", "556", "762", "12ga"].has(wd.caliber), "%s has its own ammo type (%s)" % [id, wd.caliber])
		cals[wd.caliber] = true
		var gun := GunMesh.build(wd.model)
		check(GunMesh.muzzle_of(gun) != null and gun.get_child_count() > 20, "%s gun model builds with a muzzle" % id)
		gun.free()
		if prev != null:
			var pw: WeaponData = prev["wd"]
			check(wd.damage > pw.damage and wd.fire_rate_rpm > pw.fire_rate_rpm and wd.mag_size > pw.mag_size, "%s out-damages, out-fires and out-holds the previous tier" % id)
			check(int(rc["cost"]["planks"]) > int(prev["rc"]["cost"]["planks"]) and int(rc["cost"]["scrap"]) > int(prev["rc"]["cost"]["scrap"]), "%s costs more than the previous tier" % id)
		prev = {"wd": wd, "rc": rc}
	check(WeaponDB.get_weapon("ar_t1").damage > 0 and WeaponDB.get_weapon("ar_t1").damage < WeaponDB.get_weapon("ar_t2").damage, "tier 1 damage is below tier 2")

	# --- ammo for every gun in WeaponDB (old and new)
	for wid in WeaponDB.ids():
		var wd := WeaponDB.get_weapon(wid)
		var ar := Recipes.get_recipe(Recipes.ammo_id(wd.caliber))
		check(not ar.is_empty() and ar["kind"] == "ammo" and ar["give"] == wd.caliber and int(ar["count"]) > 0, "ammo recipe exists for %s (%s)" % [wid, wd.caliber])
		var only_mats: bool = ar["cost"].keys().all(func(k): return k == "planks" or k == "scrap")
		check(only_mats and not ar["cost"].is_empty(), "ammo for %s costs planks/scrap only" % wid)
	for wid in ["pistol", "shotgun", "ak", "m4", "hunting", "ar"]:
		check(WeaponDB.has_weapon(wid) and not Recipes.get_recipe(Recipes.ammo_id(WeaponDB.get_weapon(wid).caliber)).is_empty(), "pre-existing gun %s has ammo crafting" % wid)

	# --- affordability helpers
	var r := Recipes.get_recipe("gun_ar_t1")
	check(Recipes.can_afford(r, {"planks": 999, "scrap": 999}), "can_afford true with enough")
	check(not Recipes.can_afford(r, {"planks": 999, "scrap": int(r["cost"]["scrap"]) - 1}), "can_afford false one scrap short")
	check(Recipes.cost_text(r).contains("planks") and Recipes.cost_text(r).contains("scrap"), "cost_text names both materials (%s)" % Recipes.cost_text(r))


func _test_end_to_end() -> void:
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
	check(net.host(17932, 4243) == OK, "Net.host ok")
	net.players[1] = player
	await _frames(3)
	var B = building
	B.stock[1] = {"planks": 1000, "scrap": 1000}
	B._push_stock(1)
	B.request_place("workbench", Vector4i(0, 0, 0, B.SLOT_BENCH))
	await _frames(3)
	check(B.pieces.size() == 1, "bench placed for crafting")
	for rc in Recipes.all():
		var have0: int = player.count_item(String(rc["give"]))
		var p0: int = int(B.local_stock["planks"])
		var s0: int = int(B.local_stock["scrap"])
		B.request_craft(String(rc["id"]))
		await _frames(2)
		var gained: int = player.count_item(String(rc["give"])) - have0
		var want: int = 1 if rc["kind"] == "weapon" else int(rc["count"])
		check(gained == want, "%s granted +%d (got +%d)" % [rc["id"], want, gained])
		check(p0 - int(B.local_stock["planks"]) == int(rc["cost"].get("planks", 0)) and s0 - int(B.local_stock["scrap"]) == int(rc["cost"].get("scrap", 0)),
			"%s took exactly its cost" % rc["id"])
	for id in ["ar_t1", "ar_t2", "ar_t3"]:
		check(player.weapons.has_weapon(id), "player owns crafted %s" % id)
	check(player.count_item("545") > 0 and player.count_item("68") > 0 and player.count_item("300") > 0, "new rifle ammo is in the reserve")

	# insufficient materials: nothing taken, nothing given
	B.stock[1] = {"planks": 0, "scrap": 0}
	B._push_stock(1)
	var rej := [""]
	B.build_rejected.connect(func(m: String) -> void: rej[0] = m)
	var m0: int = player.count_item("12ga")
	B.request_craft("ammo_12ga")
	await _frames(2)
	check(rej[0] == "Not enough materials" and player.count_item("12ga") == m0, "broke craft rejected, nothing granted (%s)" % rej[0])

	# --- overlay
	var ui: Control = CraftingUI.new()
	ui.building = B
	root.add_child(ui)
	await _frames(1)
	check(ui.open(), "crafting overlay opens")
	check(ui.rows.size() == Recipes.all().size(), "overlay lists every recipe (%d)" % ui.rows.size())
	check(ui.rows.all(func(r): return (r["button"] as Button).disabled), "no materials: every Craft button is disabled")
	check(ui.is_in_group("ui_open"), "overlay joins ui_open while visible")
	B.stock[1] = {"planks": 1000, "scrap": 1000}
	B._push_stock(1)
	await _frames(2)
	var open_rows := 0
	for row in ui.rows:
		if not (row["button"] as Button).disabled:
			open_rows += 1
	# the three rifles are owned already, everything else (ammo) is craftable
	check(open_rows == Recipes.all().size() - 3, "with materials only the owned rifles stay disabled (%d enabled)" % open_rows)
	var ammo_row: Dictionary = {}
	for row in ui.rows:
		if row["id"] == "ammo_556":
			ammo_row = row
	var r556: int = player.count_item("556")
	(ammo_row["button"] as Button).pressed.emit()
	await _frames(3)
	check(player.count_item("556") == r556 + int(Recipes.get_recipe("ammo_556")["count"]), "pressing Craft grants the ammo")
	ui.close(false)
	check(not ui.visible and not ui.is_in_group("ui_open"), "overlay closes and leaves ui_open")

	# --- ItemDB / WeaponDB inspect sanity for new guns
	var all_specs := WeaponDB.inspect_all()
	check(all_specs.has("ar_t1") and all_specs.has("ar_t2") and all_specs.has("ar_t3"), "WeaponDB.inspect_all lists the new rifles")
