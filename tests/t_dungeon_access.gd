extends SceneTree
## Dungeon access: a player-sized body walks in and out of the entrance (no invisible wall), every door blocks when
## closed and lets a body through when open (collider follows the state, still aimable when open), the door sync
## handlers exist, and the dungeon has about half the guards it used to.
## Run: godot --headless --path . --script res://tests/t_dungeon_access.gd -- <seed>

const DB = preload("res://tools/worldgen/dungeon_builder.gd")

const ORIGINAL_GUARDS := 25      # guard markers before the "easier dungeon" pass
const MAX_GUARDS := 13           # ceil(ORIGINAL_GUARDS / 2)
const MIN_GUARDS := 8            # still defended
const DT := 1.0 / 60.0

var fails := 0


func check(cond: bool, label: String) -> void:
	if cond:
		print("PASS  ", label)
	else:
		fails += 1
		print("FAIL  ", label)


func _initialize() -> void:
	_run.call_deferred()


func _ground(world: Node3D, x: float, z: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 120.0, z), Vector3(x, -60.0, z), 1)
	var hit := world.get_world_3d().direct_space_state.intersect_ray(q)
	return float((hit["position"] as Vector3).y) if not hit.is_empty() else 0.0


func _body(world: Node3D, pos: Vector3) -> CharacterBody3D:
	var b := CharacterBody3D.new()
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	cs.shape = cap
	cs.position = Vector3(0, 0.9, 0)
	b.add_child(cs)
	b.collision_layer = 2
	b.collision_mask = 1
	world.add_child(b)
	b.global_position = pos
	return b


## Steers the body at `target` (horizontal) until it is within 0.6 m or the frames run out.
func _walk(b: CharacterBody3D, target: Vector3, max_frames: int = 700) -> bool:
	for _i in max_frames:
		await physics_frame
		var to := target - b.global_position
		to.y = 0.0
		if to.length() < 0.6:
			return true
		var dir := to.normalized()
		b.velocity = Vector3(dir.x * 4.0, b.velocity.y - 20.0 * DT, dir.z * 4.0)
		b.move_and_slide()
	return false


func _route(world: Node3D, start: Vector3, points: Array, label: String, verbose: bool = true) -> bool:
	var b := _body(world, start)
	var ok := true
	for p in points:
		if not await _walk(b, p):
			ok = false
			if verbose:
				print("  stalled on route '%s' at %s heading for %s" % [label, str(b.global_position), str(p)])
			break
	b.queue_free()
	return ok


func _open_all(doors: Array, open: bool) -> void:
	for d in doors:
		d.apply_open_state(open, false)


func _run() -> void:
	var seed_value := 20260101
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		seed_value = int(args[0])
	var world: Node3D = (load("res://scenes/world/world.tscn") as PackedScene).instantiate()
	root.add_child(world)
	world.build(seed_value)
	for _i in 8:
		await physics_frame
	var dn: Node = world.get_node_or_null("Dungeon")
	check(dn != null, "world has a Dungeon node")
	if dn == null:
		print("RESULT fails=%d" % fails)
		quit(1)
		return
	var site: Dictionary = dn.get_meta("site")
	var o: Vector2 = site["origin"]
	var gz: float = float(site["gz"])
	var floor_y: float = float(site["floor_y"])

	# ---- fewer enemies, loot kept
	var markers: Array = []
	var boss := 0
	var types := {}
	for m in get_nodes_in_group("dungeon_skeleton_spawn"):
		if _in_dungeon(dn, m):
			markers.append(m)
			types[str(m.get_meta("type"))] = true
			if m.has_meta("boss"):
				boss += 1
	check(markers.size() <= MAX_GUARDS, "guard count is at most half the original %d (%d <= %d)" % [ORIGINAL_GUARDS, markers.size(), MAX_GUARDS])
	check(markers.size() >= MIN_GUARDS, "the dungeon is still guarded (%d >= %d)" % [markers.size(), MIN_GUARDS])
	check(boss == 1 and types.size() == 4, "boss and all four skeleton types remain (boss=%d types=%s)" % [boss, str(types.keys())])
	var cons := 0
	var golds := 0
	for c in get_nodes_in_group("loot_container"):
		if _in_dungeon(dn, c):
			cons += 1
			if str(c.get("dkind")) == "gold_chest":
				golds += 1
	check(cons >= 20 and golds >= 3, "loot kept: %d containers, %d gold chests" % [cons, golds])

	# ---- doors exist, start closed, expose the interaction + sync contract
	var doors: Array = get_nodes_in_group("dungeon_door").filter(func(d): return dn.is_ancestor_of(d))
	doors.sort_custom(func(a, b): return a.name.naturalnocasecmp_to(b.name) < 0)
	check(doors.size() == DB.DOORS.size(), "one openable door per doorway (%d of %d)" % [doors.size(), DB.DOORS.size()])
	var contract := true
	for d in doors:
		if not (d.has_method("interact") and d.has_method("get_prompt") and d.is_in_group("interactable") and not d.is_open):
			contract = false
	check(contract, "every door is interactable (E) and starts closed")
	if doors.is_empty():
		print("RESULT fails=%d" % fails)
		quit(1)
		return
	check(doors[0].has_method("_rpc_request") and doors[0].has_method("_rpc_state"), "doors carry the request and state RPC handlers")
	var d0 = doors[0]
	var prompt_closed: String = d0.get_prompt()
	d0.interact(null)
	await physics_frame
	check(d0.is_open and d0.get_prompt() != prompt_closed, "interact() opens a closed door and changes its prompt (%s -> %s)" % [prompt_closed, d0.get_prompt()])
	d0.interact(null)
	await physics_frame
	check(not d0.is_open, "interact() closes it again")
	d0._rpc_state(true)
	await physics_frame
	check(d0.is_open, "the network state handler opens the door on a peer")
	d0._rpc_state(false)
	await physics_frame

	# ---- every door: closed blocks a walking body, open lets it through, the open leaf can still be aimed at
	var space := world.get_world_3d().direct_space_state
	var door_bad := 0
	for d in doors:
		var a: Vector3 = d.to_global(Vector3(0.0, 0.1, -2.0))
		var z: Vector3 = d.to_global(Vector3(0.0, 0.1, 2.0))
		d.apply_open_state(false, false)
		await physics_frame
		var ray_a: Vector3 = d.to_global(Vector3(0.3, 1.0, -1.0))
		var ray_b: Vector3 = d.to_global(Vector3(0.3, 1.0, 1.0))
		var closed_hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(ray_a, ray_b, 1))
		var blocked: bool = not await _route(world, a, [z], "closed " + str(d.name), false)
		d.apply_open_state(true, false)
		await physics_frame
		var open_hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(ray_a, ray_b, 1))
		var passed: bool = await _route(world, a, [z], "open " + str(d.name))
		var lf: Vector3 = d.to_global(Vector3(d.hinge_x + 1.0, 1.0, d.LEAF_CX))
		var lt: Vector3 = d.to_global(Vector3(d.hinge_x - 1.0, 1.0, d.LEAF_CX))
		var aim: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(lf, lt, 1))
		var aimable: bool = not aim.is_empty() and aim["collider"] == d
		var closed_ray_ok: bool = not closed_hit.is_empty() and closed_hit["collider"] == d
		if not (blocked and passed and closed_ray_ok and open_hit.is_empty() and aimable):
			door_bad += 1
			print("  door %s blocked_when_closed=%s passes_when_open=%s ray_closed_hits_door=%s ray_open_clear=%s open_leaf_aimable=%s" % [
				d.name, str(blocked), str(passed), str(closed_ray_ok), str(open_hit.is_empty()), str(aimable)])
		d.apply_open_state(false, false)
	check(door_bad == 0, "all %d doors block when closed, pass when open, stay aimable when open (%d bad)" % [doors.size(), door_bad])

	# ---- the entrance: walk in from the surface and back out, from three approaches, doors still closed
	var gate_z := gz - 22.0
	var ante := Vector3(o.x, 0.0, gz + 5.0)
	var in_ok := 0
	var starts: Array = [Vector2(o.x, gz - 32.0), Vector2(o.x - 9.0, gz - 29.0), Vector2(o.x + 9.0, gz - 29.0), Vector2(o.x, gz - 24.0)]
	for s in starts:
		var start := Vector3(s.x, _ground(world, s.x, s.y) + 0.3, s.y)
		var pts: Array = [Vector3(o.x, 0, gate_z), Vector3(o.x, 0, gz - 17.0), Vector3(o.x, 0, gz - 8.0), ante]
		if await _route(world, start, pts, "in from %s" % str(s)):
			in_ok += 1
	check(in_ok == starts.size(), "a player-sized body walks in through the gate and down the stairs from every approach (%d of %d)" % [in_ok, starts.size()])
	var out_ok: bool = await _route(world, Vector3(ante.x, floor_y + 0.3, ante.z), [Vector3(o.x, 0, gz - 8.0), Vector3(o.x, 0, gz - 17.0), Vector3(o.x, 0, gate_z), Vector3(o.x, 0, gz - 32.0)], "out")
	check(out_ok, "the same body walks back up the stairs and out of the gate")

	# ---- with the doors open, the whole dungeon is walkable from the entrance down to the vault and back out
	_open_all(doors, true)
	await physics_frame
	var deep: Array = [Vector3(o.x, 0, gz - 17.0), Vector3(o.x, 0, gz - 8.0), ante, Vector3(o.x, 0, gz + 18.0), Vector3(o.x, 0, gz + 32.0)]
	var start_in := Vector3(o.x, _ground(world, o.x, gz - 30.0) + 0.3, gz - 30.0)
	check(await _route(world, start_in, deep, "to the vault"), "with every door open a body walks from the gate to the vault")
	var back: Array = [Vector3(o.x, 0, gz + 18.0), ante, Vector3(o.x, 0, gz - 8.0), Vector3(o.x, 0, gz - 17.0), Vector3(o.x, 0, gz - 32.0)]
	check(await _route(world, Vector3(o.x, floor_y + 0.3, gz + 32.0), back, "back from the vault"), "and back from the vault to the surface")

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
