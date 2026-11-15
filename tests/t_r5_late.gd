extends SceneTree
## Round 5 (RAT): D1 + D2 with a LATE joiner. Host + client 1 join first, zombies exist, then client 2 joins late.
## D1: client 2 must see the zombies that already existed and one spawned afterwards.
## D2 measurement: a zombie attacks client 2 (the late joiner); client 2's own health must drop below 100.
## The host log must contain no RPC errors; use tests/run_r5_late.sh, which greps the combined log.
## Run: godot --headless --path . --script res://tests/t_r5_late.gd   (helper processes: -- client <idx>)

const PORT := 17898
const SEED := 515151

var role := "host"
var idx := 0
var net: Node
var reports := {}
var from_ids := {}
var fails := 0


func check(cond: bool, label: String) -> void:
	if cond:
		print("[%s] PASS  %s" % [role, label])
	else:
		fails += 1
		print("[%s] FAIL  %s" % [role, label])


func info(msg: String) -> void:
	print("[%s] INFO  %s" % [role, msg])


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		role = args[0]
	if args.size() > 1:
		idx = int(args[1])
	if role == "client":
		role = "client%d" % idx
	_run.call_deferred()


func _wait_for(cond: Callable, timeout: float) -> bool:
	var t := 0.0
	while t < timeout:
		if cond.call():
			return true
		await create_timer(0.1).timeout
		t += 0.1
	return cond.call()


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


func _launch(i: int) -> int:
	return OS.create_process(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--script", "res://tests/t_r5_late.gd", "--", "client", str(i)])


func _last_hp(key: String) -> float:
	return float(reports.get(key, "%s:-1" % key).get_slice(":", 1))


func _host() -> void:
	net.client_report.connect(func(from: int, msg: String) -> void:
		var key := msg.get_slice(":", 0)
		reports[key] = msg
		from_ids[key] = from)
	check(net.host(PORT, SEED) == OK, "host() ok")
	var main := _boot_main()
	for _i in 30:
		await physics_frame
	var pids: Array = [_launch(1)]
	await _wait_for(func() -> bool: return net.players.size() == 2, 40.0)
	var sp = get_first_node_in_group("spawner")
	sp.enabled = false
	sp.kill_all()
	await physics_frame
	var p: Vector3 = net.players[1].global_position
	for k in [0, 1, 2]:
		var zx: float = p.x + 25 + 4 * k
		var zz: float = p.z + 25
		sp.spawn_zombie_at(Vector3(zx, main.world.get_height(zx, zz) + 0.6, zz), false, k)
	for _i in 20:
		await physics_frame
	check(sp.container.get_child_count() == 3, "host has 3 zombies before the late join (%d)" % sp.container.get_child_count())
	pids.append(_launch(2))
	var three: bool = await _wait_for(func() -> bool: return net.players.size() == 3, 40.0)
	check(three, "host sees 3 players after the late join (%s)" % str(net.players.keys()))
	await _wait_for(func() -> bool: return reports.has("zhello2") and reports.has("zhello1"), 60.0)
	for i in [1, 2]:
		var key := "zhello%d" % i
		if not reports.has(key):
			check(false, "client %d sent its zombie report" % i)
			continue
		var d := {}
		for kv in reports[key].get_slice(":", 1).split("|"):
			d[kv.get_slice("=", 0)] = kv.get_slice("=", 1)
		check(int(d.get("count", "-1")) == 3, "client %d (%s) sees the 3 pre-existing zombies (%s visible, kinds %s)" % [i, "late joiner" if i == 2 else "early", d.get("count", "?"), d.get("kinds", "?")])
		if i == 2:
			check(is_equal_approx(float(d.get("hp", "-1")), 100.0), "late joiner starts at 100 health (%s)" % d.get("hp", "?"))
	# zombie spawned after the late join
	var lx: float = p.x + 35
	var lz: float = p.z + 35
	sp.spawn_zombie_at(Vector3(lx, main.world.get_height(lx, lz) + 0.6, lz), false, 1)
	await _wait_for(func() -> bool: return reports.has("zlate2") and reports.has("zlate1"), 30.0)
	check(int(reports.get("zlate2", "x:-1").get_slice(":", 1)) == 4, "late joiner sees the zombie spawned afterwards (%s visible, want 4)" % reports.get("zlate2", "none").get_slice(":", 1))
	check(int(reports.get("zlate1", "x:-1").get_slice(":", 1)) == 4, "early joiner sees 4 zombies (%s)" % reports.get("zlate1", "none").get_slice(":", 1))
	# D2: put a zombie next to the late joiner and let it attack
	var cid: int = from_ids.get("zhello2", 0)
	var victim = net.players.get(cid)
	check(victim != null and is_instance_valid(victim), "host has the late joiner's player node (peer %d)" % cid)
	if victim != null and is_instance_valid(victim):
		var vp: Vector3 = victim.global_position
		var z = sp.spawn_zombie_at(vp + Vector3(1.0, 0.3, 0.0), false, 0)
		check(z != null, "attacker zombie spawned next to the late joiner")
		if z != null:
			z.alert_to(victim)
		var dropped: bool = await _wait_for(func() -> bool: return _last_hp("hp2") < 99.0, 25.0)
		info("late joiner health reports: %s" % reports.get("hp2", "none"))
		check(dropped, "D2: late joiner's health dropped after a zombie hit (last report %.1f)" % _last_hp("hp2"))
		check(_last_hp("hp2") <= 88.5 and _last_hp("hp2") > 0.0, "D2: drop is a plausible hit amount (12 dmg x night scale), health %.1f" % _last_hp("hp2"))
	for pid in pids:
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
		quit(3)
		return
	var main := _boot_main()
	var cid: int = net.local_id()
	var n_expected := 3 if idx == 2 else 2
	await _wait_for(func() -> bool: return net.players.size() >= n_expected and is_instance_valid(net.players.get(cid)), 60.0)
	await create_timer(3.0).timeout
	var me = net.players.get(cid)
	var zs = main.spawner
	var kinds := {}
	var cnt := 0
	if zs != null and zs.container != null:
		cnt = zs.container.get_child_count()
		for z in zs.container.get_children():
			kinds[int(z.kind)] = true
	var kl: Array = kinds.keys()
	kl.sort()
	net.report("zhello%d:count=%d|kinds=%s|hp=%f" % [idx, cnt, ",".join(PackedStringArray(kl.map(func(k): return str(k)))), me.health if me != null else -1.0])
	await create_timer(6.0).timeout
	cnt = zs.container.get_child_count() if zs != null and zs.container != null else 0
	net.report("zlate%d:%d" % [idx, cnt])
	if idx == 2:
		for _i in 40:
			net.report("hp2:%f" % (me.health if me != null else -1.0))
			await create_timer(1.0).timeout
	else:
		await create_timer(50.0).timeout
	quit(0)
