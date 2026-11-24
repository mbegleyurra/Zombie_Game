extends SceneTree
## KayKit dungeon: deterministic layout, connectivity, loot, guard markers, no overlaps, solid floor.
## Run: godot --headless --path . --script res://tests/t_dungeon.gd -- <seed>

const DB = preload("res://tools/worldgen/dungeon_builder.gd")
const IDB = preload("res://scripts/world/item_db.gd")

var fails := 0


func check(cond: bool, label: String) -> void:
	if cond:
		print("PASS  ", label)
	else:
		fails += 1
		print("FAIL  ", label)


func _initialize() -> void:
	_run.call_deferred()


func _build(seed_value: int) -> Node3D:
	var world: Node3D = (load("res://scenes/world/world.tscn") as PackedScene).instantiate()
	root.add_child(world)
	world.build(seed_value)
	return world


func _signature(world: Node3D) -> String:
	var d: Node = world.get_node_or_null("Dungeon")
	var sig := PackedStringArray()
	if d == null:
		return ""
	for c in get_nodes_in_group("loot_container"):
		if _in_dungeon(d, c):
			sig.append("%s|%s|%s|%s" % [c.kind, str(c.position), c.table, str(c.contents)])
	for m in get_nodes_in_group("dungeon_skeleton_spawn"):
		if _in_dungeon(d, m):
			sig.append("M|%s|%s|%s" % [str(m.position), str(m.get_meta("type")), str(m.get_meta("room"))])
	return "\n".join(sig).md5_text() + "|" + str((world.get_meta("dungeon_site") as Dictionary)["origin"])


func _run() -> void:
	var seed_value := 20260101
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		seed_value = int(args[0])

	# ---- static layout
	var cells: Dictionary = DB.cells()
	var reach: Array = DB.reachable_cells()
	check(DB.ROOMS.size() >= 6, "dungeon has several rooms (%d)" % DB.ROOMS.size())
	check(reach.size() == cells.size(), "every cell reachable from the entrance (%d of %d)" % [reach.size(), cells.size()])
	var rooms_reached := {}
	for v in reach:
		rooms_reached[DB.region_of(v)] = true
	var all_rooms := true
	for rid in DB.ROOMS:
		if not rooms_reached.has(rid):
			all_rooms = false
	check(all_rooms, "all rooms connected to the entrance")
	var overlap := false
	var seen := {}
	for rid in DB.ROOMS:
		var rm: Dictionary = DB.ROOMS[rid]
		for r in range(int(rm["r0"]), int(rm["r1"]) + 1):
			for c in range(int(rm["c0"]), int(rm["c1"]) + 1):
				if seen.has(Vector2i(c, r)):
					overlap = true
				seen[Vector2i(c, r)] = true
	for cc in DB.CORRIDORS:
		if seen.has(cc):
			overlap = true
	check(not overlap, "room and corridor cells never overlap")
	var doors_ok := true
	for d in DB.DOORS:
		if DB.region_of(d[0]) == "" or DB.region_of(d[1]) == "":
			doors_ok = false
	check(doors_ok, "every doorway joins two occupied cells")

	# ---- built world
	var world := _build(seed_value)
	for _i in 6:
		await physics_frame
	var d: Node = world.get_node_or_null("Dungeon")
	check(d != null, "world has a Dungeon node")
	if d == null:
		print("RESULT fails=%d" % fails)
		quit(1)
		return
	var stats: Dictionary = d.get_meta("stats")
	var site: Dictionary = d.get_meta("site")
	print("DUNGEON seed=%d stats=%s site=%s" % [seed_value, str(stats), str(site["origin"])])
	check(int(stats["missing"]) == 0, "no missing models (%d)" % int(stats["missing"]))
	check(int(stats["walls"]) > 40, "walls placed (%d)" % int(stats["walls"]))
	check(int(stats["doors"]) == DB.DOORS.size(), "one doorway per DOORS entry (%d)" % int(stats["doors"]))
	check(int(stats["lights"]) >= 8 and int(stats["lights"]) <= 24, "a handful of torch lights (%d)" % int(stats["lights"]))

	# site is away from roads and every location
	var origin: Vector2 = site["origin"]
	var far := true
	var nearest := 1.0e9
	for l in world.get_locations():
		var gap: float = origin.distance_to(l["pos2"]) - float(l["radius"])
		nearest = minf(nearest, gap)
		if gap < 40.0:
			far = false
	check(far, "site is 40 m+ clear of every location pad (nearest gap %.0f m)" % nearest)
	check(world.terrain.road_distance(origin.x, origin.y) > 25.0, "site is off the roads (%.0f m)" % world.terrain.road_distance(origin.x, origin.y))

	# containers and loot
	var chests := 0
	var gold := 0
	var with_loot := 0
	var cons: Array = []
	for c in get_nodes_in_group("loot_container"):
		if _in_dungeon(d, c):
			cons.append(c)
			if str(c.get("dkind")) == "chest":
				chests += 1
			elif str(c.get("dkind")) == "gold_chest":
				gold += 1
			if (c.contents as Array).size() > 0:
				with_loot += 1
	check(chests >= 6, "chests present (%d)" % chests)
	check(gold >= 3, "gold chests present (%d)" % gold)
	check(with_loot == cons.size() and cons.size() >= 20, "every container holds loot (%d of %d)" % [with_loot, cons.size()])
	var prize_ok := false
	var valid_ids := true
	for c in cons:
		for it in c.contents:
			if not IDB.has_item(str(it["id"])):
				valid_ids = false
			if str(c.get("dkind")) == "gold_chest" and str(it["id"]) == "weapon_ar":
				prize_ok = true
	check(prize_ok, "a gold chest holds the rifle (weapon_ar)")
	check(valid_ids, "every item id in dungeon loot exists in ItemDB")
	var ids_unique := true
	var idset := {}
	for id in world.loot_by_id.keys():
		idset[id] = true
	ids_unique = idset.size() == world.loot_by_id.size()
	check(ids_unique, "loot ids unique (%d nodes)" % world.loot_by_id.size())

	# guard markers
	var types := {}
	var boss := 0
	var markers: Array = []
	for m in get_nodes_in_group("dungeon_skeleton_spawn"):
		if _in_dungeon(d, m):
			markers.append(m)
			types[str(m.get_meta("type"))] = int(types.get(str(m.get_meta("type")), 0)) + 1
			if m.has_meta("boss"):
				boss += 1
	check(markers.size() >= 10 and markers.size() <= 13, "guard markers present, about half the old 25 (%d)" % markers.size())
	check(types.has("warrior") and types.has("minion") and types.has("rogue") and types.has("mage"), "all four skeleton types placed %s" % str(types))
	check(boss == 1, "exactly one boss marker (%d)" % boss)
	var vault_n := 0
	for m in markers:
		if str(m.get_meta("room")) == "vault":
			vault_n += 1
	check(vault_n >= 3, "boss room has several guards (%d)" % vault_n)

	# nothing overlaps: container footprints (XZ) pairwise, markers off containers
	var clash := 0
	for i in cons.size():
		var a = cons[i]
		var ra := Rect2(Vector2(a.global_position.x, a.global_position.z) - Vector2(a.model_size.x, a.model_size.z) * 0.5, Vector2(a.model_size.x, a.model_size.z))
		for j in range(i + 1, cons.size()):
			var b = cons[j]
			var rb := Rect2(Vector2(b.global_position.x, b.global_position.z) - Vector2(b.model_size.x, b.model_size.z) * 0.5, Vector2(b.model_size.x, b.model_size.z))
			if ra.grow(-0.02).intersects(rb.grow(-0.02)):
				clash += 1
				print("  overlap ", a.dkind, "@", a.position, " ", b.dkind, "@", b.position)
	check(clash == 0, "no two containers overlap (%d clashes)" % clash)
	var mclash := 0
	for m in markers:
		for c in cons:
			if Vector2(m.global_position.x - c.global_position.x, m.global_position.z - c.global_position.z).length() < 0.5:
				mclash += 1
	check(mclash == 0, "no guard marker stands inside a container (%d)" % mclash)

	# solid floor under every marker and container, and a roof above the rooms
	var space := world.get_world_3d().direct_space_state
	var no_floor := 0
	var no_roof := 0
	for n in markers + cons:
		var p: Vector3 = n.global_position
		var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 1.0, 0), p + Vector3(0, -1.0, 0))
		if space.intersect_ray(q).is_empty():
			no_floor += 1
		var q2 := PhysicsRayQueryParameters3D.create(p + Vector3(0, 0.5, 0), p + Vector3(0, 6.0, 0))
		if space.intersect_ray(q2).is_empty():
			no_roof += 1
	check(no_floor == 0, "solid floor collider under every marker and container (%d without)" % no_floor)
	check(no_roof == 0, "roof collider above every marker and container (%d without)" % no_roof)

	# the stairs: a walkable ramp from the rim down to the antechamber
	var top: Vector3 = Vector3(origin.x, float(site["h0"]) + 3.0, float(site["gz"]) - 15.0)
	var qs := PhysicsRayQueryParameters3D.create(top, top + Vector3(0, -6.0, 0))
	var hit := space.intersect_ray(qs)
	check(not hit.is_empty() and absf((hit["position"] as Vector3).y - (float(site["h0"]) + 0.05)) < 0.4, "stair top is solid at rim height")
	var bot: Vector3 = DB.cell_pos(site, 4.5, 0.5) + Vector3(0, 3.0, 0)
	var qb := PhysicsRayQueryParameters3D.create(bot, bot + Vector3(0, -6.0, 0))
	var hb := space.intersect_ray(qb)
	check(not hb.is_empty() and absf((hb["position"] as Vector3).y - (float(site["floor_y"]) + 0.05)) < 0.2, "antechamber floor solid at dungeon level")
	# the ramp is continuous: samples every 2 m follow the 0.5 m-per-metre slope within 0.3 m
	var ramp_bad := 0
	var za: float = float(site["gz"]) - 15.6
	for k in 9:
		var zz: float = za + 2.0 * float(k)
		var expect: float = float(site["floor_y"]) + 0.05 + 8.0 - 0.5 * (zz - za)
		var o := Vector3(origin.x + 1.0, expect + 3.0, zz)
		var hr := space.intersect_ray(PhysicsRayQueryParameters3D.create(o, o + Vector3(0, -6.0, 0)))
		if hr.is_empty() or absf((hr["position"] as Vector3).y - expect) > 0.3:
			ramp_bad += 1
			print("  ramp sample z=%.1f expect=%.2f got=%s" % [zz, expect, str(hr.get("position", "none"))])
	check(ramp_bad == 0, "stair ramp collider is continuous from rim to dungeon floor (%d bad samples)" % ramp_bad)

	# determinism: a second world from the same seed has the identical dungeon
	var sig1 := _signature(world)
	world.queue_free()
	await process_frame
	await process_frame
	var world2 := _build(seed_value)
	for _i in 3:
		await physics_frame
	var sig2 := _signature(world2)
	check(sig1 != "" and sig1 == sig2, "same seed gives an identical dungeon (%s)" % sig1.get_slice("|", 0))

	print("RESULT fails=%d" % fails)
	quit(1 if fails > 0 else 0)


## Dungeon content. Before the bake it sat under World/Dungeon; the baked scene keeps containers and guard markers
## under Markers (LootContainers / DungeonSkeletonSpawns), so a dungeon container (it has dkind) or a guard marker
## anywhere in this world counts too.
func _in_dungeon(dn: Node, n: Node) -> bool:
	if dn == null:
		return false
	if dn.is_ancestor_of(n):
		return true
	var w: Node = dn.get_parent()
	return w != null and w.is_ancestor_of(n) and (n.is_in_group("dungeon_skeleton_spawn") or ("dkind" in n and str(n.get("dkind")) != ""))
