extends SceneTree
## KayKit Resource Bits: item defs, models, loot tables, building-stock feed and world pickups.
## Run: godot --headless --path . --script res://tests/t_resources.gd -- <seed>

const KR = preload("res://scripts/world/kaykit_resources.gd")
const IDB = preload("res://scripts/world/item_db.gd")

var fails := 0


class FakePlayer extends Node:
	var got := {}

	func add_item(id: String, n: int) -> bool:
		got[id] = int(got.get(id, 0)) + n
		return true


class FakeMain extends Node:
	var mats := {}

	func give_materials(item: String, n: int) -> void:
		mats[item] = int(mats.get(item, 0)) + n


func check(cond: bool, label: String) -> void:
	if cond:
		print("PASS  ", label)
	else:
		fails += 1
		print("FAIL  ", label)


func _initialize() -> void:
	_run.call_deferred()


func _scatter_sig(world: Node3D) -> Array:
	var sig := PackedStringArray()
	var kinds := {}
	var ids: Array = world.loot_by_id.keys()
	ids.sort()
	var dungeon: Node = world.get_node_or_null("Dungeon")
	for id in ids:
		var n = world.loot_by_id[id]
		if n.is_in_group("loot_container") or (dungeon != null and dungeon.is_ancestor_of(n)):
			continue
		if KR.ITEMS.has(n.item_id) or KR.VISUALS.has(n.item_id):
			var p: Vector3 = n.global_position
			sig.append("%d|%s|%d|%.2f,%.2f,%.2f" % [id, n.item_id, n.count, p.x, p.y, p.z])
			kinds[n.item_id] = int(kinds.get(n.item_id, 0)) + 1
	return ["\n".join(sig).md5_text(), sig.size(), kinds, sig]


func _run() -> void:
	var seed_value := 20260101
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		seed_value = int(args[0])

	# ---- definitions and models
	var missing := []
	for id in KR.ITEMS:
		if not IDB.has_item(id):
			missing.append(id)
		var d: Dictionary = KR.ITEMS[id]
		if load(str(d["model"])) == null:
			missing.append(str(d["model"]))
		for v in (d.get("models", []) as Array):
			if load(str(v[0])) == null:
				missing.append(str(v[0]))
	for id in KR.VISUALS:
		for v in (KR.VISUALS[id].get("models", []) as Array):
			if load(str(v[0])) == null:
				missing.append(str(v[0]))
	check(missing.is_empty(), "all %d new items resolve and every model loads %s" % [KR.ITEMS.size(), str(missing)])
	check(KR.ITEMS.size() >= 11, "ingots, nuggets, fuel, parts, logs and coin defined (%d)" % KR.ITEMS.size())
	check(IDB.get_item("planks").get("model", "") != "" and "Wood_Planks" in str(IDB.get_item("planks")["model"]), "planks use the KayKit pallet-plank model")
	check("Parts_" in str(IDB.get_item("scrap").get("model", "")), "scrap uses the KayKit parts model")
	check(IDB.has_item("weapon_ar"), "rifle (weapon_ar) exists in ItemDB for the loot tables")

	# ---- tables
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var bad := []
	var seen := {}
	for t in IDB.table_names():
		for _i in 80:
			for it in IDB.roll_table(t, rng):
				if not IDB.has_item(str(it["id"])):
					bad.append("%s:%s" % [t, it["id"]])
				if int(it["count"]) < 1:
					bad.append("%s:zero" % t)
				seen[str(it["id"])] = true
	check(bad.is_empty(), "every table rolls only valid ids and counts >= 1 %s" % str(bad))
	var all_new := true
	for id in KR.ITEMS:
		if not seen.has(id):
			all_new = false
			print("  never rolled: ", id)
	check(all_new, "every new item is reachable from some loot table")
	var gold_seen := {}
	rng.seed = 5
	for _i in 300:
		for it in IDB.roll_table("dungeon_gold", rng):
			gold_seen[str(it["id"])] = true
	check(gold_seen.has("weapon_ar") and gold_seen.has("gold_ingot") and gold_seen.has("medkit") and gold_seen.has("ammo_762"), "dungeon_gold can roll the rifle, gold, medkits and best ammo")
	var wh_has := false
	var gas_has := false
	rng.seed = 11
	for _i in 600:
		for it in IDB.roll_table("warehouse", rng):
			if it["id"] == "iron_ingot":
				wh_has = true
		for it in IDB.roll_table("gas_station", rng):
			if it["id"] == "fuel_can":
				gas_has = true
	check(wh_has and gas_has, "ordinary containers also drop resources (warehouse iron, gas station fuel)")

	# ---- building stock feed
	var main := FakeMain.new()
	main.add_to_group("main_world")
	root.add_child(main)
	var pl := FakePlayer.new()
	root.add_child(pl)
	check(IDB.give_to(pl, "iron_ingot", 2), "give_to accepts an iron ingot")
	IDB.give_to(pl, "wood_logs", 1)
	IDB.give_to(pl, "planks", 2)
	IDB.give_to(pl, "gold_ingot", 1)
	check(int(main.mats.get("scrap", 0)) == 6 and int(main.mats.get("planks", 0)) == 5 and not main.mats.has("gold_ingot"),
		"stock feed: 2 iron = 6 scrap, 1 log + 2 planks = 5 planks, gold adds none %s" % str(main.mats))
	check(int(pl.got.get("iron_ingot", 0)) == 2 and int(pl.got.get("gold_ingot", 0)) == 1, "items still land in the inventory")
	main.free()
	pl.free()

	# ---- world pickups
	var world: Node3D = (load("res://scenes/world/world.tscn") as PackedScene).instantiate()
	root.add_child(world)
	world.build(seed_value)
	for _i in 4:
		await physics_frame
	var s1: Array = _scatter_sig(world)
	var kinds: Dictionary = s1[2]
	print("SCATTER seed=%d pickups=%d kinds=%s hash=%s" % [seed_value, int(s1[1]), str(kinds), str(s1[0])])
	check(int(s1[1]) >= 18, "resource pickups scattered across the world (%d)" % int(s1[1]))
	check(kinds.size() >= 5, "several resource kinds on the ground (%d kinds)" % kinds.size())
	var blocked := 0
	var low := 0
	var nodes := 0
	var no_visual := 0
	for id in world.loot_by_id.keys():
		var n = world.loot_by_id[id]
		if n.is_in_group("loot_container"):
			continue
		if not (KR.ITEMS.has(n.item_id) or KR.VISUALS.has(n.item_id)):
			continue
		var dungeon: Node = world.get_node_or_null("Dungeon")
		if dungeon != null and dungeon.is_ancestor_of(n):
			continue
		nodes += 1
		var p: Vector3 = n.global_position
		if KR.blocked_by_dressing(world, Vector2(p.x, p.z), 0.3):
			blocked += 1
		if p.y < world.get_height(p.x, p.z) - 0.2:
			low += 1
		var meshes := 0
		var st: Array = [n]
		while not st.is_empty():
			var c: Node = st.pop_back()
			for k in c.get_children():
				st.append(k)
			if c is MeshInstance3D:
				meshes += 1
		if meshes == 0:
			no_visual += 1
	check(blocked == 0, "no pickup sits inside a dressing collider (%d of %d)" % [blocked, nodes])
	check(low == 0, "no pickup is buried below the terrain (%d)" % low)
	check(no_visual == 0, "every pickup has a visible mesh (%d without)" % no_visual)

	# a KayKit-model pickup really uses the model (taller than a flat primitive stand-in, not empty)
	var probe = world.spawn_ground_item("fuel_can", 1, Vector3(0, 60, 0), world.next_loot_id())
	var fb := AABB()
	var first := true
	var st2: Array = [probe]
	while not st2.is_empty():
		var c2: Node = st2.pop_back()
		for k2 in c2.get_children():
			st2.append(k2)
		if c2 is MeshInstance3D and (c2 as MeshInstance3D).mesh != null:
			var a: AABB = (c2 as MeshInstance3D).get_aabb()
			a = (c2 as MeshInstance3D).global_transform * a
			fb = a if first else fb.merge(a)
			first = false
	check(not first and fb.size.y > 0.25 and fb.size.y < 0.5, "fuel can renders as the 0.36 m jerrycan model (height %.2f)" % fb.size.y)

	# determinism
	world.queue_free()
	await process_frame
	await process_frame
	var world2: Node3D = (load("res://scenes/world/world.tscn") as PackedScene).instantiate()
	root.add_child(world2)
	world2.build(seed_value)
	for _i in 3:
		await physics_frame
	var s2: Array = _scatter_sig(world2)
	check(str(s1[0]) == str(s2[0]), "same seed gives identical resource pickups")

	print("RESULT fails=%d" % fails)
	quit(1 if fails > 0 else 0)
