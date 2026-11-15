extends SceneTree
## Round 5 (D2): damage to a LATE JOINER must actually apply, and the wind-up must replicate.
## Host + client 1 (early) + client 2 (late joiner, joins while a zombie exists), real main.tscn.
##   1. host hits client 2 with request_damage() the instant its node exists (the window that used
##      to log "Attempt to call an RPC to a peer that cannot see this node")
##   2. a real zombie is placed next to client 2 and attacks it: health must drop by >= one hit
##   3. same zombie check for the early client 1 (control)
##   4. the zombie's replicated `winding` flag is seen true on the host AND on a client
##   5. the relay queue drains (every hit acknowledged)
## Run: godot --headless --path . --script res://tests/t_r5_dmg.gd > /tmp/r5.log 2>&1 ; grep "cannot see" /tmp/r5.log
## Helper processes are launched by the host with user args: client <idx>.

const PORT := 17911
const SEED := 515151

var role := "host"
var idx := 0
var net: Node
var reports := {}
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
		"--script", "res://tests/t_r5_dmg.gd", "--", "client", str(i)])


## Drops a walker next to `target`, alerts it, and returns the lowest health seen on the
## target over `secs` plus whether `winding` was observed true on the zombie.
func _zombie_hit_test(sp: Node, main: Node, target: Node) -> Dictionary:
	var tp: Vector3 = target.global_position
	var zx := tp.x + 1.3
	var zz := tp.z
	var z = sp.spawn_zombie_at(Vector3(zx, tp.y + 0.2, zz), false, 0)
	var h0: float = target.health
	var low := [h0]
	var wound := [false]
	var t := 0.0
	while t < 10.0:
		if is_instance_valid(z):
			z.alert_to(target)
			if z.winding:
				wound[0] = true
		low[0] = minf(low[0], target.health)
		if low[0] <= h0 - 11.0:
			break
		await create_timer(0.1).timeout
		t += 0.1
	if is_instance_valid(z):
		z.queue_free()
	return {"h0": h0, "low": low[0], "wound": wound[0]}


func _host() -> void:
	net.client_report.connect(func(from: int, msg: String) -> void:
		reports[msg.get_slice(":", 0)] = [from, msg.get_slice(":", 1)])
	check(net.host(PORT, SEED) == OK, "host() ok")
	var main := _boot_main()
	for _i in 30:
		await physics_frame
	var sp = get_first_node_in_group("spawner")
	sp.enabled = false
	sp.kill_all()
	var pids: Array = [_launch(1)]
	check(await _wait_for(func() -> bool: return net.players.size() == 2, 40.0), "client 1 joined")
	var base: Vector3 = net.players[1].global_position
	# a zombie already exists before the late joiner arrives
	sp.spawn_zombie_at(Vector3(base.x + 25, main.world.get_height(base.x + 25, base.z) + 0.6, base.z), false, 0)

	# ---- late joiner + immediate hit (the old failure window)
	pids.append(_launch(2))
	check(await _wait_for(func() -> bool: return net.players.size() == 3, 40.0), "late client 2 joined")
	var late_id := 0
	var early_id := 0
	for id in net.players:
		if id != 1:
			if reports.has("hello2") and int(reports["hello2"][0]) == id:
				late_id = id
	for id in net.players.keys():
		if id != 1 and id != late_id:
			early_id = id
	if late_id == 0:   # hello not in yet: the newest peer id is the late one
		var ids: Array = net.players.keys()
		ids.sort()
		late_id = ids[ids.size() - 1]
		early_id = ids[ids.size() - 2]
	var late = net.players[late_id]
	var early = net.players[early_id]
	var h_start: float = late.health
	late.request_damage(10.0, false, 0)   # immediately after the node exists on the host
	check(late.relay.pending_count() >= 0, "late joiner has a DamageRelay")
	var dropped: bool = await _wait_for(func() -> bool: return late.health <= h_start - 9.5, 20.0)
	info("late joiner health %.1f -> %.1f after a direct 10 hp hit (pending=%d)" % [h_start, late.health, late.relay.pending_count()])
	check(dropped, "late joiner's health DROPPED after request_damage (%.1f -> %.1f)" % [h_start, late.health])

	# ---- real zombie hits
	await create_timer(3.0).timeout
	var r_late := await _zombie_hit_test(sp, main, late)
	info("zombie vs late joiner: health %.1f -> low %.1f, winding seen=%s" % [r_late["h0"], r_late["low"], str(r_late["wound"])])
	check(r_late["low"] <= r_late["h0"] - 11.0, "zombie hit LOWERED the late joiner's health by >= 11 (%.1f -> %.1f)" % [r_late["h0"], r_late["low"]])
	check(r_late["wound"], "zombie `winding` flag went true before the swing (host view)")
	var r_early := await _zombie_hit_test(sp, main, early)
	check(r_early["low"] <= r_early["h0"] - 11.0, "zombie hit lowered the EARLY client's health by >= 11 (%.1f -> %.1f)" % [r_early["h0"], r_early["low"]])
	var drained: bool = await _wait_for(func() -> bool: return late.relay.pending_count() == 0 and early.relay.pending_count() == 0, 10.0)
	check(drained, "relay queues drained: every hit acknowledged (late %d, early %d pending)" % [late.relay.pending_count(), early.relay.pending_count()])
	check(late.relay.dropped == 0 and early.relay.dropped == 0, "no hit was dropped")

	# a client sees the wind-up flag too
	var z2 = sp.spawn_zombie_at(Vector3(base.x + 6, main.world.get_height(base.x + 6, base.z) + 0.6, base.z), false, 0)
	var host_pl = net.players[1]
	var saw := false
	var t := 0.0
	while t < 12.0 and not saw:
		if is_instance_valid(z2):
			z2.alert_to(host_pl)
		saw = reports.has("windseen2") or reports.has("windseen1")
		await create_timer(0.1).timeout
		t += 0.1
	check(saw, "a client observed the replicated `winding` flag true (%s)" % str(reports.keys()))
	for pid in pids:
		if pid > 0 and OS.is_process_running(pid):
			OS.kill(pid)
	print("RESULT  failures=%d" % fails)
	quit(1 if fails > 0 else 0)


func _client() -> void:
	if net.join("127.0.0.1", PORT) != OK:
		quit(1)
		return
	if not await _wait_for(func() -> bool: return net.world_seed == SEED, 20.0):
		print("[%s] never received the seed" % role)
		quit(3)
		return
	var main := _boot_main()
	var cid: int = net.local_id()
	await _wait_for(func() -> bool: return is_instance_valid(net.players.get(cid)) and is_instance_valid(net.players.get(1)), 60.0)
	net.report("hello%d:%d" % [idx, cid])
	var sp = get_first_node_in_group("spawner")
	var me = net.players.get(cid)
	var low: float = me.health
	var seen := false
	var t := 0.0
	while t < 70.0:
		await create_timer(0.1).timeout
		t += 0.1
		low = minf(low, me.health)
		if not seen and sp != null and sp.container != null:
			for z in sp.container.get_children():
				if "winding" in z and z.winding:
					seen = true
					net.report("windseen%d:1" % idx)
					break
	print("[%s] INFO  lowest own health %.1f, applied_total %.1f" % [role, low, me.relay.applied_total])
	quit(0)
