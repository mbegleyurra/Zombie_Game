extends SceneTree
## Renders walker / runner / bloater side by side (needs a real renderer: run under xvfb-run, NOT --headless).
## godot --path . --script res://tests/r_kenney_render.gd -- /abs/out_dir

var out_dir := "/tmp/kenney_render"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _shot(name: String, cam: Camera3D, pos: Vector3, look: Vector3) -> void:
	cam.global_position = pos
	cam.look_at(look, Vector3.UP)
	for _i in 6:
		await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [out_dir, name])
	print("SAVED ", name, " ", img.get_size())


func _run() -> void:
	await physics_frame
	var net: Node = root.get_node_or_null("Net")
	net.host_solo(31337)
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	for _i in 40:
		await physics_frame
	var p = net.players.get(1)
	var sp = get_first_node_in_group("spawner")
	sp.enabled = false
	sp.kill_all()
	var base: Vector3 = p.global_position + Vector3(0, 0, -12)
	var zs := []
	var kinds := [Zombie.KIND_WALKER, Zombie.KIND_RUNNER, Zombie.KIND_BLOATER]
	for i in 3:
		var pos: Vector3 = base + Vector3(-3 + 3 * i, 0, 0)
		pos.y = main.world.get_height(pos.x, pos.z) + 0.6
		zs.append(sp.spawn_zombie_at(pos, false, kinds[i]))
	for _i in 30:
		await physics_frame
	var cam := Camera3D.new()
	cam.fov = 50
	root.add_child(cam)
	cam.current = true
	var mid: Vector3 = zs[0].global_position + Vector3(3, 1.0, 0)
	# front view (zombies face -Z by default, so camera on -Z side looks +Z)
	await _shot("1_front_idle", cam, mid + Vector3(0, 0.4, -7), mid)
	await _shot("2_side_idle", cam, mid + Vector3(8, 0.4, 0), mid)
	# a player-eye view from ~6 m, standing height
	await _shot("3_player_eye", cam, zs[0].global_position + Vector3(0.5, 1.6, -6), zs[0].global_position + Vector3(0, 1.3, 0))
	# chase pose
	for z in zs:
		z.alert_to(p)
	for _i in 20:
		await physics_frame
	for z in zs:
		z.global_position = z.global_position  # keep
	await _shot("4_chase_front", cam, zs[0].global_position + Vector3(0, 1.4, 7), zs[0].global_position + Vector3(0, 1.0, 0))
	await _shot("5_chase_side", cam, zs[0].global_position + Vector3(7, 1.2, 0), zs[0].global_position + Vector3(0, 1.0, 0))
	quit(0)
