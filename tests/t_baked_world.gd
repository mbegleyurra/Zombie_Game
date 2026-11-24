extends SceneTree
## Baked world (Phase 2). Run:
##   godot --headless --path . --script res://tests/t_baked_world.gd
## Checks: (1) loading the world runs no generator script (nothing under tools/worldgen is loaded or present in the
## tree); (2) node counts match scenes/world/baked/BAKE_NOTES.md; (3) an edit to a baked node survives save+reload of a
## temp copy; (4) the baked heightmap matches the terrain collision within 0.1 m at sampled points; (5) every loot_id
## is unique.

const GEN_DIR := "res://tools/worldgen/"
const ForestData = preload("res://scripts/world/forest_data.gd")
const GEN_SCRIPTS := ["terrain", "building_factory", "city_interiors", "city_kit", "road_kit", "dungeon_builder",
	"hand_builder", "hand_layout", "hand_map_data", "kaykit_forest", "kenney_dressing", "prop_factory", "mesh_util",
	"vehicle_spawner", "gen_world", "kaykit_scatter"]
const TMP_SCENE := "user://t_baked_world_vehicles_copy.tscn"

var fails := 0


func check(cond: bool, label: String) -> void:
	if cond:
		print("PASS  ", label)
	else:
		fails += 1
		print("FAIL  ", label)


func _initialize() -> void:
	_run.call_deferred()


func _count_group(w: Node, g: String) -> int:
	var n := 0
	for x in get_nodes_in_group(g):
		if w.is_ancestor_of(x):
			n += 1
	return n


func _scripts_in(n: Node, out: Dictionary) -> void:
	var s: Script = n.get_script()
	if s != null:
		out[s.resource_path] = true
	for c in n.get_children():
		_scripts_in(c, out)


func _run() -> void:
	# ---- (1) no generator code on load
	var w: Node3D = (load("res://scenes/world/world.tscn") as PackedScene).instantiate()
	root.add_child(w)
	w.build(1)
	for _i in 3:
		await physics_frame
	var cached: Array = []
	for g in GEN_SCRIPTS:
		if ResourceLoader.has_cached(GEN_DIR + g + ".gd"):
			cached.append(g)
	check(cached.is_empty(), "no generator script loaded by the world load (%s)" % str(cached))
	var used := {}
	_scripts_in(w, used)
	var gen_used: Array = []
	for p in used:
		if str(p).begins_with(GEN_DIR):
			gen_used.append(p)
	check(gen_used.is_empty(), "no node in the loaded world runs a generator script (%s)" % str(gen_used))
	check((w.get_script() as Script).resource_path == "res://scripts/world/world_builder.gd", "world.tscn uses the runtime world_builder")

	# ---- (2) counts from BAKE_NOTES.md
	var chunks := 0
	for c in w.terrain.get_children():
		if str(c.name).begins_with("Chunk_"):
			chunks += 1
	check(chunks == 64, "64 terrain chunks (%d)" % chunks)
	var forest: Node = w.get_node_or_null("KayKitForest")
	var mmi := 0
	var inst := 0
	var xf_ok := 0
	if forest != null:
		for c in forest.get_children():
			if c is MultiMeshInstance3D:
				mmi += 1
				inst += (c as MultiMeshInstance3D).multimesh.instance_count
				if ForestData.buffer_ok((c as MultiMeshInstance3D).multimesh):
					xf_ok += (c as MultiMeshInstance3D).multimesh.instance_count
	check(mmi == 316 and inst == 2450, "vegetation: 316 multimeshes / 2450 instances (%d / %d)" % [mmi, inst])
	check(xf_ok == 2450, "vegetation: every instance has a saved non-zero transform (%d / 2450)" % xf_ok)
	var fcol: Node = w.get_node_or_null("KayKitForest/Collision")
	check(fcol != null and fcol.get_child_count() == 564, "vegetation collision 564 shapes (%d)" % (fcol.get_child_count() if fcol else -1))
	var dcol: Node = w.get_node_or_null("KenneyDressing/Collision")
	check(dcol != null and dcol.get_child_count() == 131, "dressing collision 131 shapes (%d)" % (dcol.get_child_count() if dcol else -1))
	check(_count_group(w, "vehicles") == 10, "10 baked cars (%d)" % _count_group(w, "vehicles"))
	check(_count_group(w, "dungeon_door") == 12, "12 dungeon doors (%d)" % _count_group(w, "dungeon_door"))
	check(_count_group(w, "zombie_spawn") == 253, "253 zombie spawn markers (%d)" % _count_group(w, "zombie_spawn"))
	check(_count_group(w, "skeleton_spawn") == 158, "158 skeleton spawn markers (%d)" % _count_group(w, "skeleton_spawn"))
	check(_count_group(w, "dungeon_skeleton_spawn") == 13, "13 dungeon guard markers (%d)" % _count_group(w, "dungeon_skeleton_spawn"))
	check(_count_group(w, "loot_item") == 141, "141 ground loot nodes (%d)" % _count_group(w, "loot_item"))
	check(w.get_locations().size() == 12, "12 locations (%d)" % w.get_locations().size())
	var loc_nodes := 0
	for l in w.get_locations():
		if l["node"] != null:
			loc_nodes += 1
	check(loc_nodes == 12, "every location marker resolves to its baked building root (%d)" % loc_nodes)
	check(_count_group(w, "player_spawn") == 8, "8 player spawn markers (%d)" % _count_group(w, "player_spawn"))

	# ---- (5) loot ids
	var ids := {}
	var dup := 0
	var total := 0
	for g in ["loot_item", "loot_container"]:
		for n in get_nodes_in_group(g):
			if w.is_ancestor_of(n):
				total += 1
				if ids.has(int(n.loot_id)):
					dup += 1
				ids[int(n.loot_id)] = true
	check(dup == 0 and total == 250, "every loot_id unique (%d nodes, %d duplicates)" % [total, dup])
	check(w.loot_by_id.size() == 250, "world registered all 250 baked loot nodes (%d)" % w.loot_by_id.size())
	var lo := 1 << 30
	var hi := -1
	for k in ids:
		lo = mini(lo, int(k))
		hi = maxi(hi, int(k))
	check(lo == 1 and hi == 250, "loot ids are 1..250 as baked (%d..%d)" % [lo, hi])
	var dyn = w.spawn_ground_item("scrap", 1, Vector3(0, 5, 0))
	check(dyn != null and int(dyn.loot_id) > 250 and not ids.has(int(dyn.loot_id)), "runtime drops get ids outside the baked range (%d)" % int(dyn.loot_id))

	# ---- (4) heightmap vs collision
	var space := w.get_world_3d().direct_space_state
	var worst := 0.0
	var samples := 0
	var missed := 0
	var x := -240.0
	while x <= 240.0:
		var z := -240.0
		while z <= 240.0:
			var q := PhysicsRayQueryParameters3D.create(Vector3(x, 400, z), Vector3(x, -400, z), 1)
			var hit := space.intersect_ray(q)
			# only compare against the terrain chunks, not buildings / trees standing on them
			var guard := 0
			while not hit.is_empty() and guard < 8 and not str((hit["collider"] as Node).get_parent().name).begins_with("Chunk_"):
				q.exclude = q.exclude + [hit["rid"]]
				hit = space.intersect_ray(q)
				guard += 1
			if hit.is_empty():
				missed += 1
			else:
				samples += 1
				worst = maxf(worst, absf(float((hit["position"] as Vector3).y) - w.get_height(x, z)))
			z += 37.0
		x += 37.0
	check(samples >= 150 and worst <= 0.1, "heightmap matches terrain collision within 0.1 m (%d samples, worst %.4f m, %d missed)" % [samples, worst, missed])
	check(is_equal_approx(w.get_height(1000.0, 1000.0), w._ray_height(1000.0, 1000.0)), "get_height falls back to the physics ray off the heightmap")

	w.queue_free()
	await process_frame

	# ---- (3) a baked edit survives save + reload (temp copy of vehicles.tscn)
	var src := load("res://scenes/world/baked/vehicles.tscn") as PackedScene
	var inst_v: Node = src.instantiate()
	var car: Node3D = inst_v.get_node("Vehicles/Car_0")
	var moved := car.position + Vector3(3.25, 0.0, -1.5)
	car.position = moved
	car.set("kind", "police")
	var out := PackedScene.new()
	var perr := out.pack(inst_v)
	var serr := ResourceSaver.save(out, TMP_SCENE)
	inst_v.free()
	var back: Node = (ResourceLoader.load(TMP_SCENE, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	var car2: Node3D = back.get_node_or_null("Vehicles/Car_0")
	check(perr == OK and serr == OK and car2 != null and car2.position.is_equal_approx(moved) and str(car2.get("kind")) == "police",
		"edit to a baked node survives save + reload of a temp copy")
	back.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_SCENE))

	print("RESULT failures=%d" % fails)
	quit(1 if fails > 0 else 0)
