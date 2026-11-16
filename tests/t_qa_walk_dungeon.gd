extends SceneTree
## QA gate (RAT): drives the REAL Player (scenes/player/player.tscn, its own _physics_process and capsule) through the
## dungeon entrance. The Player ignores input unless Input.mouse_mode is CAPTURED, and headless Godot ignores that
## write, so run this under a display: xvfb-run -a godot --rendering-driver opengl3 --path . --script res://tests/t_qa_walk_dungeon.gd
## It steers with Input.action_press("move_forward") and sets the yaw each frame; nothing but input drives the body.

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


func _go(p: CharacterBody3D, target: Vector3, max_frames: int = 900) -> bool:
	for _i in max_frames:
		await physics_frame
		var to := target - p.global_position
		to.y = 0.0
		if to.length() < 0.7:
			Input.action_release("move_forward")
			return true
		p.rotation.y = atan2(-to.x, -to.z)
		Input.action_press("move_forward")
	Input.action_release("move_forward")
	return false


func _route(player: CharacterBody3D, start: Vector3, pts: Array, label: String, frames: int = 900, quiet: bool = false) -> bool:
	player.global_position = start
	player.velocity = Vector3.ZERO
	await physics_frame
	for p in pts:
		if not await _go(player, p, frames):
			if not quiet:
				print("  stalled on '%s' at %s heading for %s" % [label, str(player.global_position), str(p)])
			return false
	return true


func _run() -> void:
	var seed_value := 20260101
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		seed_value = int(args[0])
	var world: Node3D = (load("res://scenes/world/world.tscn") as PackedScene).instantiate()
	root.add_child(world)
	world.build(seed_value)
	var player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	player.name = "1"
	root.add_child(player)
	for _i in 10:
		await physics_frame
	print("mouse_mode=", Input.mouse_mode, " (2 = captured)")
	check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "real Player has captured mouse (input is live)")
	var dn: Node = world.get_node("Dungeon")
	var site: Dictionary = dn.get_meta("site")
	var o: Vector2 = site["origin"]
	var gz: float = float(site["gz"])
	var floor_y: float = float(site["floor_y"])
	var gate_z := gz - 22.0
	var ante := Vector3(o.x, 0.0, gz + 5.0)

	# sanity: pressing forward really moves the player (proves the harness is not vacuous)
	player.global_position = Vector3(o.x, _ground(world, o.x, gz - 40.0) + 0.3, gz - 40.0)
	await physics_frame
	var p0: Vector3 = player.global_position
	player.rotation.y = PI
	Input.action_press("move_forward")
	for _i in 30:
		await physics_frame
	Input.action_release("move_forward")
	check(player.global_position.distance_to(p0) > 1.5, "harness: forward input moves the real Player (%.2f m)" % player.global_position.distance_to(p0))

	var in_ok := 0
	var starts: Array = [Vector2(o.x, gz - 32.0), Vector2(o.x - 9.0, gz - 29.0), Vector2(o.x + 9.0, gz - 29.0), Vector2(o.x, gz - 24.0), Vector2(o.x - 3.0, gz - 30.0), Vector2(o.x + 3.0, gz - 30.0)]
	for s in starts:
		var start := Vector3(s.x, _ground(world, s.x, s.y) + 0.3, s.y)
		var pts: Array = [Vector3(o.x, 0, gate_z), Vector3(o.x, 0, gz - 17.0), Vector3(o.x, 0, gz - 8.0), ante]
		if await _route(player, start, pts, "in from %s" % str(s)):
			in_ok += 1
	check(in_ok == starts.size(), "real Player walks in through the gate and down the stairs from %d approaches (%d ok)" % [starts.size(), in_ok])
	check(player.global_position.y < floor_y + 1.2, "Player ended on the dungeon floor (y=%.2f, floor %.2f)" % [player.global_position.y, floor_y])
	var out_ok: bool = await _route(player, Vector3(ante.x, floor_y + 0.3, ante.z), [Vector3(o.x, 0, gz - 8.0), Vector3(o.x, 0, gz - 17.0), Vector3(o.x, 0, gate_z), Vector3(o.x, 0, gz - 32.0)], "out")
	check(out_ok, "real Player walks back up the stairs and out of the gate")
	check(player.global_position.y > floor_y + 3.0, "Player is back on the surface (y=%.2f)" % player.global_position.y)

	# doors: closed one blocks the real Player; E (the real interact path) opens it
	var doors: Array = get_nodes_in_group("dungeon_door").filter(func(d): return dn.is_ancestor_of(d))
	doors.sort_custom(func(a, b): return a.name.naturalnocasecmp_to(b.name) < 0)
	var blocked := 0
	var passed := 0
	for d in doors:
		d.apply_open_state(false, false)
		await physics_frame
		var a: Vector3 = d.to_global(Vector3(0, 0.1, -2.0))
		var z: Vector3 = d.to_global(Vector3(0, 0.1, 2.0))
		if not await _route(player, a, [z], "closed " + str(d.name), 150, true):
			blocked += 1
		d.apply_open_state(true, false)
		await physics_frame
		if await _route(player, a, [z], "open " + str(d.name)):
			passed += 1
		d.apply_open_state(false, false)
	check(blocked == doors.size(), "closed doors block the real Player (%d of %d)" % [blocked, doors.size()])
	check(passed == doors.size(), "open doors let the real Player through (%d of %d)" % [passed, doors.size()])

	for d in doors:
		d.apply_open_state(true, false)
	await physics_frame
	var deep: Array = [Vector3(o.x, 0, gate_z), Vector3(o.x, 0, gz - 17.0), Vector3(o.x, 0, gz - 8.0), ante, Vector3(o.x, 0, gz + 18.0), Vector3(o.x, 0, gz + 32.0)]
	check(await _route(player, Vector3(o.x, _ground(world, o.x, gz - 30.0) + 0.3, gz - 30.0), deep, "to vault"), "real Player walks gate -> vault with all doors open")
	print("RESULT fails=%d" % fails)
	quit(1 if fails > 0 else 0)
