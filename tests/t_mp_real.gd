extends SceneTree
## Two-process co-op test using the REAL scenes/player/player.tscn (the shipped selftest uses a stand-in node).
## Run: godot --headless --path . --script res://tests/t_mp_real.gd            (host; launches the client itself)
## Checks: both peers spawn both players, node name/authority, camera ownership, position replication.

const PORT := 17890
const SEED := 99

var role := "host"
var net: Node
var world: Node3D
var reports := {}
var fails := 0


func check(cond: bool, label: String) -> void:
	if cond:
		print("[%s] PASS  %s" % [role, label])
	else:
		fails += 1
		print("[%s] FAIL  %s" % [role, label])


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		role = args[0]
	_run.call_deferred()


func _mk_floor() -> void:
	world = Node3D.new()
	world.name = "World"
	root.add_child(world)
	var fb := StaticBody3D.new()
	fb.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	cs.shape = box
	fb.add_child(cs)
	fb.position = Vector3(0, -0.5, 0)
	world.add_child(fb)


func _wait_for(cond: Callable, timeout: float) -> bool:
	var t := 0.0
	while t < timeout:
		if cond.call():
			return true
		await create_timer(0.1).timeout
		t += 0.1
	return cond.call()


func _run() -> void:
	await physics_frame
	net = root.get_node_or_null("Net")
	if net == null:
		net = (load("res://scripts/net/network.gd") as GDScript).new()
		net.name = "Net"
		root.add_child(net)
	_mk_floor()
	net.spawn_root = world
	if role == "host":
		await _host()
	else:
		await _client()


func _host() -> void:
	net.client_report.connect(func(_from: int, msg: String) -> void:
		print("[host] client says: ", msg)
		reports[msg.get_slice(":", 0)] = msg)
	check(net.host(PORT, SEED) == OK, "host() ok")
	var pid := OS.create_process(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--script", "res://tests/t_mp_real.gd", "--", "client"])
	check(pid > 0, "client process launched")
	var ok: bool = await _wait_for(func() -> bool: return net.players.size() == 2, 20.0)
	check(ok, "host sees 2 players (%s)" % str(net.players.keys()))
	if ok:
		await create_timer(1.0).timeout
		for id in net.players:
			var p = net.players[id]
			check(p is Player, "host: player %d is the real Player scene" % id)
			check(p.name == str(id) and p.get_multiplayer_authority() == id, "host: player %d named/authority = peer id" % id)
		var me = net.players[1]
		check(me.camera.current, "host: own camera current")
		var other_id := 0
		for id in net.players:
			if id != 1:
				other_id = id
		check(not net.players[other_id].camera.current, "host: remote player's camera NOT current")
		me.global_position = Vector3(10, 0.2, 10)
		await _wait_for(func() -> bool: return reports.has("pos_ok") or reports.has("fail"), 15.0)
		check(reports.has("pos_ok"), "client received host position by replication (%s)" % str(reports.get("pos_ok", reports.get("fail", "no report"))))
		check(reports.has("spawn_ok"), "client spawn/authority/camera checks (%s)" % str(reports.get("spawn_ok", "no report")))
		var back := await _wait_for(func() -> bool: return net.players.has(other_id) and net.players[other_id].global_position.distance_to(Vector3(-10, 0.2, -10)) < 1.5, 10.0)
		check(back, "host received client position by replication (client player at %s)" % str(net.players[other_id].global_position))
	if pid > 0 and OS.is_process_running(pid):
		OS.kill(pid)
	print("RESULT  failures=%d" % fails)
	quit(1 if fails > 0 else 0)


func _client() -> void:
	if net.join("127.0.0.1", PORT) != OK:
		quit(1)
		return
	var ok: bool = await _wait_for(func() -> bool: return net.players.size() == 2 and net.world_seed == SEED, 20.0)
	if not ok:
		net.report("fail:client sees players %s seed %d" % [str(net.players.keys()), net.world_seed])
		await create_timer(1.0).timeout
		quit(1)
		return
	await create_timer(1.5).timeout
	var cid: int = net.local_id()
	var me = net.players[cid]
	var host_p = net.players[1]
	var good: bool = me is Player and host_p is Player and me.is_multiplayer_authority() and not host_p.is_multiplayer_authority() \
		and me.camera.current and not host_p.camera.current and me.name == str(cid) and host_p.name == "1"
	net.report(("spawn_ok:" if good else "fail:spawn/authority/camera ") + "me=%d auth_me=%s auth_host=%s cam_me=%s cam_host=%s" % [
		cid, me.is_multiplayer_authority(), host_p.is_multiplayer_authority(), me.camera.current, host_p.camera.current])
	var got := await _wait_for(func() -> bool: return host_p.global_position.distance_to(Vector3(10, 0.2, 10)) < 1.5, 10.0)
	net.report(("pos_ok:" if got else "fail:position ") + str(host_p.global_position))
	me.global_position = Vector3(-10, 0.2, -10)
	await create_timer(6.0).timeout
	quit(0)
