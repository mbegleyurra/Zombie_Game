extends SceneTree
## Round 3: two-process co-op on the REAL main.tscn + REAL player.tscn.
## Host: Net.host + main.tscn. Client (launched by the host): Net.join + main.tscn.
## Checks: client builds an identical world (md5 of locations/loot/heights), host seed used, one player
## per peer, host movement visible on the client, client movement visible on the host, zombies replicate.
## Run: godot --headless --path . --script res://tests/t_r3_mp_main.gd

const PORT := 17895
const SEED := 424242

var role := "host"
var net: Node
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


func _wait_for(cond: Callable, timeout: float) -> bool:
	var t := 0.0
	while t < timeout:
		if cond.call():
			return true
		await create_timer(0.1).timeout
		t += 0.1
	return cond.call()


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _sig(world) -> String:
	var sig := PackedStringArray()
	for l in world.get_locations():
		var pp: Vector3 = l["pos"]
		sig.append("%s|%s|%.2f,%.2f,%.2f|%.3f" % [l["type"], l["name"], pp.x, pp.y, pp.z, float(l["rot"])])
	var ids: Array = world.loot_by_id.keys()
	ids.sort()
	for id in ids:
		var n = world.loot_by_id[id]
		if n.is_in_group("loot_container"):
			sig.append("C%d|%s|%s|%s" % [id, n.kind, n.table, str(n.contents)])
		else:
			var gp: Vector3 = n.global_position
			sig.append("I%d|%s|%d|%.2f,%.2f,%.2f" % [id, n.item_id, n.count, gp.x, gp.y, gp.z])
	for q in [Vector2(0, 0), Vector2(60, -40), Vector2(-120, 90)]:
		sig.append("H%.3f" % world.get_height(q.x, q.y))
	return "\n".join(sig).md5_text()


func _parse(msg: String) -> Dictionary:
	var d := {}
	for kv in msg.get_slice(":", 1).split("|"):
		d[kv.get_slice("=", 0)] = kv.get_slice("=", 1)
	return d


func _boot_main() -> Node:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	return main


func _run() -> void:
	await physics_frame
	net = root.get_node_or_null("Net")
	if role == "host":
		await _host()
	else:
		await _client()


func _host() -> void:
	net.client_report.connect(func(_from: int, msg: String) -> void:
		print("[host] client says: ", msg)
		reports[msg.get_slice(":", 0)] = msg)
	check(net.host(PORT, SEED) == OK, "host() ok")
	var main := _boot_main()
	for _i in 30:
		await physics_frame
	check(main.world.world_seed == SEED, "host world built from Net seed (%d)" % main.world.world_seed)
	check(net.players.size() == 1 and get_nodes_in_group("players").size() == 1, "host has exactly one player (%d)" % get_nodes_in_group("players").size())
	var host_sig := _sig(main.world)
	var pid := OS.create_process(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--script", "res://tests/t_r3_mp_main.gd", "--", "client"])
	check(pid > 0, "client process launched")
	var two: bool = await _wait_for(func() -> bool: return net.players.size() == 2, 25.0)
	check(two, "host sees 2 players (%s)" % str(net.players.keys()))
	var got: bool = await _wait_for(func() -> bool: return reports.has("hello") or reports.has("fail"), 30.0)
	check(got and reports.has("hello"), "client sent hello (%s)" % str(reports.get("hello", reports.get("fail", "none"))))
	var other := 0
	for id in net.players:
		if id != 1:
			other = id
	if reports.has("hello"):
		var h := _parse(reports["hello"])
		check(int(h.get("seed", "0")) == SEED, "client used the host seed (%s)" % h.get("seed", "?"))
		check(h.get("sig", "") == host_sig, "client built the IDENTICAL world (host %s, client %s)" % [host_sig.substr(0, 8), h.get("sig", "?").substr(0, 8)])
		check(h.get("players", "") == "2", "client sees exactly 2 player nodes (%s)" % h.get("players", "?"))
		check(h.get("spawners", "") == "1", "client has exactly one spawner (%s)" % h.get("spawners", "?"))
		check(h.get("auth", "") == "true", "client authority/camera correct (%s)" % h.get("auth", "?"))
	if other != 0 and net.players.has(other):
		check(not net.players[other].camera.current and net.players[1].camera.current, "host: own camera current, remote camera not")
		var me = net.players[1]
		var sp1: Vector3 = main.world.get_spawn_point(1 % 4)
		var tx := sp1.x + 15.0
		var tz := sp1.z + 15.0
		me.global_position = Vector3(tx, main.world.get_height(tx, tz) + 0.5, tz)
		me.velocity = Vector3.ZERO
		await _wait_for(func() -> bool: return reports.has("hostmove"), 25.0)
		check(reports.get("hostmove", "").begins_with("hostmove:ok"), "client SEES the host player move 15 m (%s)" % reports.get("hostmove", "no report"))
		await _wait_for(func() -> bool: return reports.has("clientmove"), 25.0)
		if reports.has("clientmove"):
			var cm: String = reports["clientmove"].get_slice(":", 1)
			var tgt := Vector3(float(cm.get_slice(",", 0)), 0, float(cm.get_slice(",", 1)))
			var seen: bool = await _wait_for(func() -> bool: return net.players.has(other) and _flat(net.players[other].global_position, tgt) < 2.0, 15.0)
			check(seen, "host SEES the client player move (client at %s, target %s)" % [str(net.players[other].global_position), str(tgt)])
		else:
			check(false, "client reported its move")
		var spn = get_first_node_in_group("spawner")
		var zok: bool = await _wait_for(func() -> bool: return spn != null and spn.alive_count() >= 1, 30.0)
		check(zok, "host: zombies spawn in the 2-player game (alive=%d)" % (spn.alive_count() if spn != null else -1))
		await _wait_for(func() -> bool: return reports.has("zombies"), 45.0)
		var zn := int(reports.get("zombies", "zombies:0").get_slice(":", 1))
		check(zn >= 1, "client sees replicated zombies (%d)" % zn)
	if pid > 0 and OS.is_process_running(pid):
		OS.kill(pid)
	print("RESULT  failures=%d" % fails)
	quit(1 if fails > 0 else 0)


func _client() -> void:
	if net.join("127.0.0.1", PORT) != OK:
		quit(1)
		return
	var ok: bool = await _wait_for(func() -> bool: return net.world_seed == SEED, 20.0)
	if not ok:
		net.report("fail:no seed, got %d" % net.world_seed)
		await create_timer(1.0).timeout
		quit(1)
		return
	var main := _boot_main()
	var cid: int = net.local_id()
	var ok2: bool = await _wait_for(func() -> bool: return net.players.size() == 2 and net.players.has(1) and net.players.has(cid) and is_instance_valid(net.players[1]) and is_instance_valid(net.players[cid]), 25.0)
	if not ok2:
		net.report("fail:players %s" % str(net.players.keys()))
		await create_timer(1.0).timeout
		quit(1)
		return
	await create_timer(1.5).timeout
	var me = net.players[cid]
	var host_p = net.players[1]
	var auth: bool = me.is_multiplayer_authority() and not host_p.is_multiplayer_authority() and me.camera.current and not host_p.camera.current
	net.report("hello:seed=%d|sig=%s|players=%d|spawners=%d|auth=%s" % [main.world.world_seed, _sig(main.world), get_nodes_in_group("players").size(), get_nodes_in_group("spawner").size(), str(auth)])
	var sp1: Vector3 = main.world.get_spawn_point(1 % 4)
	var tgt := Vector3(sp1.x + 15.0, 0, sp1.z + 15.0)
	var moved: bool = await _wait_for(func() -> bool: return _flat(host_p.global_position, tgt) < 2.0, 20.0)
	net.report("%s:%s|pos=%s" % ["hostmove", "ok" if moved else "fail", str(host_p.global_position)])
	var spc: Vector3 = main.world.get_spawn_point(cid % 4)
	var cx := spc.x - 15.0
	var cz := spc.z - 15.0
	me.global_position = Vector3(cx, main.world.get_height(cx, cz) + 0.5, cz)
	me.velocity = Vector3.ZERO
	net.report("clientmove:%f,%f" % [cx, cz])
	var zs = main.spawner
	await _wait_for(func() -> bool: return zs != null and zs.container != null and zs.container.get_child_count() >= 1, 45.0)
	net.report("zombies:%d" % (zs.container.get_child_count() if zs != null and zs.container != null else 0))
	await create_timer(4.0).timeout
	quit(0)
