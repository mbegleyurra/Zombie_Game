extends SceneTree
## Hand-authored world data, as BAKED into scenes/world/baked/. Run:
##   xvfb-run -a godot --headless --path . --script res://tests/t_handmap.gd
## The authored rows (data/hand_map/placements.json, read through the bake-only tools/worldgen/hand_map_data.gd) must
## match the baked markers one for one.
## Checks: (1) two world loads (different seeds) give identical placements: every node transform, every multimesh
## instance, every loot item/container with its contents, and a terrain height grid; (2) the authored data sections
## exist with real counts and the baked scene carries every row; (3) no RandomNumberGenerator / randf / randi / noise / seed use in world placement code.

const HandMapData = preload("res://tools/worldgen/hand_map_data.gd")

const SCAN_DIRS := ["res://scripts/world", "res://tools/worldgen"]
const SCAN_FILES := ["res://scripts/zombies/spawner.gd", "res://scripts/zombies/skeleton_spawner.gd"]
## item_db keeps roll_table/pick_one for gameplay and tests; nothing in world placement calls them.
const SCAN_SKIP := ["item_db.gd"]
const BANNED := ["RandomNumberGenerator", "randf", "randi", "FastNoiseLite", "shuffle", "pick_random", "rng.seed", ".seed ="]

var fails := 0
var _dumps := 0


func check(cond: bool, label: String) -> void:
	if cond:
		print("PASS  ", label)
	else:
		fails += 1
		print("FAIL  ", label)


func _initialize() -> void:
	_run.call_deferred()


func _make(seed_value: int) -> Node3D:
	var world: Node3D = (load("res://scenes/world/world.tscn") as PackedScene).instantiate()
	root.add_child(world)
	world.build(seed_value)
	return world


func _walk(n: Node, sig: PackedStringArray, counts: Dictionary) -> void:
	if n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh != null:
		var mm: MultiMesh = (n as MultiMeshInstance3D).multimesh
		var h := PackedStringArray()
		for i in mm.instance_count:
			var t: Transform3D = mm.get_instance_transform(i)
			h.append("%.3f,%.3f,%.3f,%.3f" % [t.origin.x, t.origin.y, t.origin.z, t.basis.get_euler().y])
		sig.append("MM|%s|%d|%s" % [n.name, mm.instance_count, "|".join(h).md5_text()])
		counts["multimesh_instances"] = int(counts.get("multimesh_instances", 0)) + mm.instance_count
	elif n is Node3D and not (n is Camera3D):
		var t: Transform3D = (n as Node3D).global_transform
		sig.append("%s|%s|%.3f,%.3f,%.3f|%.3f" % [n.get_class(), "" if str(n.name).begins_with("@") else str(n.name), t.origin.x, t.origin.y, t.origin.z, t.basis.get_euler().y])
		counts["nodes3d"] = int(counts.get("nodes3d", 0)) + 1
	if n.is_in_group("loot_container"):
		var cont: Array = []
		for it in n.contents:
			cont.append("%s:%d" % [str(it["id"]), int(it["count"])])
		sig.append("LC|%d|%s|%s" % [n.loot_id, n.kind, ",".join(cont)])
		counts["containers"] = int(counts.get("containers", 0)) + 1
	elif n.is_in_group("loot_item"):
		counts["loot_items"] = int(counts.get("loot_items", 0)) + 1
	for c in n.get_children():
		_walk(c, sig, counts)


func _signature(world: Node3D, counts: Dictionary) -> String:
	var sig := PackedStringArray()
	_walk(world, sig, counts)
	for l in world.get_locations():
		var p: Vector3 = l["pos"]
		sig.append("L|%s|%.2f,%.2f,%.2f|%.3f" % [l["name"], p.x, p.y, p.z, float(l["rot"])])
	var hs := PackedStringArray()
	var x := -250.0
	while x <= 250.0:
		var z := -250.0
		while z <= 250.0:
			hs.append("%.4f" % world.terrain.height_at(x, z))
			z += 12.5
		x += 12.5
	sig.append("H|%d|%s" % [hs.size(), "|".join(hs).md5_text()])
	counts["height_samples"] = hs.size()
	var dump := OS.get_environment("HM_DUMP")
	if dump != "":
		var f := FileAccess.open(dump + str(_dumps) + ".txt", FileAccess.WRITE)
		f.store_string("\n".join(sig))
		_dumps += 1
	return "\n".join(sig).md5_text()


func _scan(path: String, hits: Array) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return 0
	var n := 0
	var ln := 0
	while not f.eof_reached():
		var line := f.get_line()
		ln += 1
		var code := line.split("#")[0]
		for b in BANNED:
			if code.contains(b):
				hits.append("%s:%d: %s" % [path, ln, line.strip_edges()])
		n += 1
	return n


func _run() -> void:
	var counts_a := {}
	var counts_b := {}
	var wa := _make(1337)
	var sa := _signature(wa, counts_a)
	wa.queue_free()
	await process_frame
	await process_frame
	var wb := _make(987654)
	var sb := _signature(wb, counts_b)
	wb.queue_free()
	await process_frame
	print("build A: ", counts_a, " sig ", sa)
	print("build B: ", counts_b, " sig ", sb)
	check(sa == sb, "two builds (seeds 1337 / 987654) give identical placements")
	check(int(counts_a.get("nodes3d", 0)) > 1000, "world has real content (%d nodes)" % int(counts_a.get("nodes3d", 0)))
	check(int(counts_a.get("containers", 0)) == HandMapData.section("CONTAINERS").size(), "every authored container is built (%d)" % int(counts_a.get("containers", 0)))

	for sec in ["FOREST", "DRESSING", "VEHICLES", "PICKUPS", "CONTAINERS", "SCATTER", "LOCAL", "ZOMBIE_SPAWNS", "SKELETON_SPAWNS", "DUN_SITE"]:
		var n: int = HandMapData.section(sec).size()
		print("      data %-16s %d rows" % [sec, n])
		check(n > 0, "authored data section %s is not empty" % sec)
	check(FileAccess.file_exists("res://data/hand_map/terrain.bin"), "authored terrain grid file exists")
	var wc := _make(1)
	await process_frame
	for pair in [["ZOMBIE_SPAWNS", "zombie_spawn"], ["SKELETON_SPAWNS", "skeleton_spawn"], ["VEHICLES", "vehicles"]]:
		var rows: int = HandMapData.section(pair[0]).size()
		var baked: int = 0
		for n in get_nodes_in_group(pair[1]):
			if wc.is_ancestor_of(n):
				baked += 1
		check(baked == rows, "baked %s nodes match authored %s rows (%d / %d)" % [pair[1], pair[0], baked, rows])
	wc.queue_free()
	await process_frame

	var hits: Array = []
	var files := 0
	var lines := 0
	for d in SCAN_DIRS:
		for fn in DirAccess.get_files_at(d):
			if fn.ends_with(".gd") and not SCAN_SKIP.has(fn):
				files += 1
				lines += _scan(d + "/" + fn, hits)
	for p in SCAN_FILES:
		files += 1
		lines += _scan(p, hits)
	for h in hits:
		print("      RNG USE ", h)
	check(hits.is_empty(), "no RNG / noise in world placement code (%d files, %d lines scanned)" % [files, lines])

	print("RESULT fails=", fails)
	quit(1 if fails > 0 else 0)
