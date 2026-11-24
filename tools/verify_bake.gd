extends SceneTree
## Checks the baked world against the bake manifest: loads scenes/world/world_baked.tscn (no generator code runs),
## counts nodes and semantic contents per sub-scene, then adds it to the tree once so every script's _ready runs.
## Run: godot --headless --path . --script res://tools/verify_bake.gd   (exit 0 = all counts match)

const Bake = preload("res://tools/bake_world.gd")
const ForestData = preload("res://scripts/world/forest_data.gd")
const RES := "res://scenes/world/baked/res/"


func _init() -> void:
	call_deferred("_run")


func _count(n: Node) -> int:
	var c := 0
	for ch in n.get_children():
		c += 1 + _count(ch)
	return c


func _run() -> void:
	var man: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(RES + "bake_manifest.json"))
	var w: Node = (load("res://scenes/world/world_baked.tscn") as PackedScene).instantiate()
	var fails := 0
	var totals := {"loot_containers": 0, "ground_loot": 0, "vehicles": 0, "veg_nodes": 0, "multimeshes": 0}
	print("scene        nodes(bake/load)  semantic")
	for s in Bake.SCENES:
		var sub: Node = w.get_node_or_null(String(s).capitalize().replace(" ", ""))
		if sub == null:
			print("VERIFY FAIL: sub-scene root %s missing; roots are %s" % [s, str(w.get_children().map(func(c): return String(c.name)))])
			quit(1)
			return
		var want: Dictionary = man["scenes"][s]
		var got_n := _count(sub)
		var got_s: Dictionary = Bake.semantic_counts(sub)
		var ok: bool = got_n == int(want["nodes"])
		for k in got_s:
			if int(got_s[k]) != int(want["semantic"][k]):
				ok = false
			if totals.has(k):
				totals[k] += int(got_s[k])
		if not ok:
			fails += 1
		print("%-12s %6d/%-6d %s %s" % [s, int(want["nodes"]), got_n, "OK  " if ok else "FAIL", JSON.stringify(got_s)])
	var mk: Node = w.get_node("Markers")
	var b: Dictionary = man["builder"]
	# Vegetation is one node per object; each blocking one carries its own collider inside its prop scene.
	var forest: Node = w.get_node("Vegetation/KayKitForest")
	var veg_shapes := forest.find_children("*", "CollisionShape3D", true, false).size()
	var veg_degenerate := 0
	for n in ForestData.nodes(forest):
		if absf((n as Node3D).transform.basis.determinant()) < 1e-6:
			veg_degenerate += 1
	var checks := [
		["loot_nodes", int(b["loot_nodes"]), totals["loot_containers"] + totals["ground_loot"]],
		["vehicles", int(b["vehicles"]), totals["vehicles"]],
		["locations", int(b["locations"]), mk.get_node("Locations").get_child_count()],
		["forest nodes", int(b["forest"]["instances"]), totals["veg_nodes"]],
		["forest sites", int(b["forest"]["instances"]), ForestData.sites(forest).size()],
		["forest degenerate", 0, veg_degenerate],
		["multimeshes", 0, totals["multimeshes"]],
		["dressing models", int(b["dressing"]["models"]), w.get_node("Props/KenneyDressing").get_child_count()],
		["dressing shapes", int(b["dressing"]["shapes"]), w.get_node("Props/KenneyDressing").find_children("*", "CollisionShape3D", true, false).size()],
		["forest shapes", int(b["forest"]["shapes"]), veg_shapes],
		["player spawns", 8, mk.get_node("PlayerSpawns").get_child_count()],
	]
	for c in checks:
		var ok: bool = c[1] == c[2]
		if not ok:
			fails += 1
		print("%-20s builder=%-6d baked=%-6d %s" % [c[0], c[1], c[2], "OK" if ok else "FAIL"])
	var moving := 0
	for car in w.get_node("Vehicles/Vehicles").get_children():
		if (car as VehicleBody3D).linear_velocity.length() > 0.001:
			moving += 1
	print("baked cars with velocity: %d" % moving)
	if moving > 0:
		fails += 1
	var hm := load(RES + "heightmap.res") as Image
	print("heightmap %dx%d format=%d origin=%s cell=%s" % [hm.get_width(), hm.get_height(), hm.get_format(), str(hm.get_meta("origin")), str(hm.get_meta("cell"))])
	# Live: add to the tree so _ready runs (loot visuals, vehicle bodies, door refs, container refs).
	root.add_child(w)
	await process_frame
	await process_frame
	var groups := {}
	for g in ["player_spawn", "location", "zombie_spawn", "skeleton_spawn", "dungeon_skeleton_spawn", "vehicle_spawn",
			"loot_container", "loot_item", "vehicles", "dungeon_door", "interactable", "daynight"]:
		groups[g] = get_nodes_in_group(g).size()
	print("live groups ", JSON.stringify(groups))
	var bad_ct := 0
	for c in get_nodes_in_group("loot_container"):
		var m = c.get("_model") if c.get_script().resource_path.ends_with("dungeon_container.gd") else c.get("_body_model")
		if m == null or c.loot_id < 0:
			bad_ct += 1
	var bad_door := 0
	for d in get_nodes_in_group("dungeon_door"):
		if d.get("_pivot") == null or d.get("_shape") == null:
			bad_door += 1
	print("containers missing model ref or id: %d   doors missing hinge/leaf: %d" % [bad_ct, bad_door])
	if bad_ct + bad_door > 0:
		fails += 1
	print("VERIFY %s (%d failing checks)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(0 if fails == 0 else 1)
