extends SceneTree
## Round 4: 4-peer co-op (host + 3 clients) on the REAL main.tscn + player.tscn, run as 4 processes.
## Covers: 4 players visible on every peer, identical world, one spawner, per-peer authority/camera,
## LATE-JOIN building (client 3 joins after pieces exist and must receive them), 5th peer refused,
## movement of every client visible on the host, zombie kinds replicate, a client leaving frees its player.
## Run: godot --headless --path . --script res://tests/t_r4_mp4.gd
## Helper processes are launched by the host with user args: client <idx>.

const PORT := 17897
const SEED := 424242

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


func _launch(i: int) -> int:
	return OS.create_process(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--script", "res://tests/t_r4_mp4.gd", "--", "client", str(i)])


# ====================================================================== host

func _host() -> void:
	var B: Node = root.get_node_or_null("Building")
	net.client_report.connect(func(from: int, msg: String) -> void:
		var key := msg.get_slice(":", 0)
		print("[host] report ", key, " from ", from)
		reports[key] = msg
		from_ids[key] = from)
	check(net.host(PORT, SEED) == OK, "host() ok")
	var main := _boot_main()
	for _i in 30:
		await physics_frame
	check(main.world.world_seed == SEED, "host world built from Net seed")
	var host_sig := _sig(main.world)
	var pids: Array = []
	pids.append(_launch(1))
	pids.append(_launch(2))
	var three: bool = await _wait_for(func() -> bool: return net.players.size() == 3, 40.0)
	check(three, "host sees 3 players after 2 joins (%s)" % str(net.players.keys()))

	# ---- build BEFORE the third client joins (late-join test)
	var me = net.players[1]
	var p: Vector3 = me.global_position
	var cx := int(floor(p.x / B.CELL))
	var cz := int(floor(p.z / B.CELL))
	var cy := int(round(p.y / B.YSTEP))
	var rej := [""]
	B.build_rejected.connect(func(r: String) -> void: rej[0] = r)
	B.request_place("floor", Vector4i(cx, cy, cz, 0))
	B.request_place("wall", Vector4i(cx, cy, cz, 1))
	B.request_place("door", Vector4i(cx + 1, cy, cz, 1))
	for _i in 10:
		await physics_frame
	info("host player at %s, cell (%d,%d,%d), rejected=%s" % [str(p), cx, cy, cz, rej[0]])
	check(B.pieces.size() == 3, "host placed 3 pieces before the late join (%d, rej=%s)" % [B.pieces.size(), rej[0]])
	for id in B.pieces:
		if B.pieces[id]["kind"] == "door":
			B.request_toggle(id)
	for _i in 10:
		await physics_frame
	var door_open := false
	for id in B.pieces:
		if B.pieces[id]["kind"] == "door" and bool(B.pieces[id]["open"]):
			door_open = true
	check(door_open, "door toggled open on host")
	var planks_host := int(B.local_stock["planks"])

	# ---- zombies of each kind exist before the late client joins
	var sp = get_first_node_in_group("spawner")
	sp.enabled = false
	sp.kill_all()
	for k in [0, 1, 2]:
		var zx: float = p.x + 20 + 4 * k
		var zz: float = p.z + 20
		sp.spawn_zombie_at(Vector3(zx, main.world.get_height(zx, zz) + 0.6, zz), false, k)

	# ---- late joiner
	pids.append(_launch(3))
	var four: bool = await _wait_for(func() -> bool: return net.players.size() == 4, 40.0)
	check(four, "host sees 4 players (%s)" % str(net.players.keys()))
	check(get_nodes_in_group("players").size() == 4, "host has exactly 4 player nodes (%d)" % get_nodes_in_group("players").size())
	check(net.roster.size() == 4, "roster has 4 (%s)" % str(net.roster))

	# ---- fifth peer must be refused
	pids.append(_launch(4))
	await create_timer(10.0).timeout
	check(net.players.size() == 4 and net.roster.size() == 4, "5th peer refused: still 4 players, roster %s" % str(net.roster))
	check(not reports.has("hello4"), "5th peer never got in (no report)")

	# ---- gather the three client reports
	await _wait_for(func() -> bool: return reports.has("hello1") and reports.has("hello2") and reports.has("hello3"), 60.0)
	for i in [1, 2, 3]:
		var key := "hello%d" % i
		if not reports.has(key):
			check(false, "client %d sent hello" % i)
			continue
		var h := _parse(reports[key])
		check(int(h.get("seed", "0")) == SEED, "client %d used host seed" % i)
		check(h.get("sig", "") == host_sig, "client %d built the IDENTICAL world" % i)
		check(h.get("players", "") == "4", "client %d sees 4 player nodes (%s)" % [i, h.get("players", "?")])
		check(h.get("spawners", "") == "1", "client %d has one spawner (%s)" % [i, h.get("spawners", "?")])
		check(h.get("auth", "") == "true", "client %d: own authority+camera only (%s)" % [i, h.get("auth", "?")])
		check(int(h.get("pieces", "-1")) == 3, "client %d has the 3 pre-existing pieces (late-join snapshot) (%s)" % [i, h.get("pieces", "?")])
		check(h.get("door_open", "") == "true", "client %d sees the door open (%s)" % [i, h.get("door_open", "?")])
		check(h.get("hostpos", "") == "true", "client %d sees the host player where the host is (%s)" % [i, h.get("hostpos", "?")])
		check(int(h.get("planks", "-1")) == 20, "client %d has its own starting 20 planks (%s)" % [i, h.get("planks", "?")])
		check(h.get("kinds", "") == "0,1,2", "client %d sees zombie kinds 0,1,2 replicated (%s)" % [i, h.get("kinds", "?")])
	check(planks_host == int(B.local_stock["planks"]), "host stock unchanged by joins")

	# ---- zombie spawned AFTER everyone joined: late joiner must see it as well
	var sp2 = get_first_node_in_group("spawner")
	var lx: float = p.x + 30
	var lz: float = p.z + 30
	sp2.spawn_zombie_at(Vector3(lx, main.world.get_height(lx, lz) + 0.6, lz), false, 1)
	await _wait_for(func() -> bool: return reports.has("zlate1") and reports.has("zlate3"), 30.0)
	for i in [1, 3]:
		var zk := "zlate%d" % i
		var cnt: int = int(reports.get(zk, "%s:-1" % zk).get_slice(":", 1))
		check(cnt >= 1, "client %d sees a zombie spawned after it joined (%d visible)" % [i, cnt])

	# ---- every client's movement visible on host
	await _wait_for(func() -> bool: return reports.has("move1") and reports.has("move2") and reports.has("move3"), 40.0)
	for i in [1, 2, 3]:
		var key := "move%d" % i
		if not reports.has(key):
			check(false, "client %d reported a move" % i)
			continue
		var cm: String = reports[key].get_slice(":", 1)
		var tgt := Vector3(float(cm.get_slice(",", 0)), 0, float(cm.get_slice(",", 1)))
		var cid: int = from_ids[key]
		var seen: bool = await _wait_for(func() -> bool: return net.players.has(cid) and _flat(net.players[cid].global_position, tgt) < 2.0, 15.0)
		check(seen, "host SEES client %d (peer %d) move to %s" % [i, cid, str(tgt)])

	# ---- a client leaving frees its player and keeps the building
	var gone: int = from_ids.get("hello2", 0)
	var left: bool = await _wait_for(func() -> bool: return net.players.size() == 3 and not net.players.has(gone), 40.0)
	check(left, "client 2 left: host down to 3 players (%s)" % str(net.players.keys()))
	check(get_nodes_in_group("players").size() == 3, "left player node freed (%d)" % get_nodes_in_group("players").size())
	check(B.pieces.size() == 3, "building intact after a peer leaves (%d)" % B.pieces.size())

	for pid in pids:
		if pid > 0 and OS.is_process_running(pid):
			OS.kill(pid)
	print("RESULT  failures=%d" % fails)
	quit(1 if fails > 0 else 0)


# ==================================================================== client

func _client() -> void:
	var B: Node = root.get_node_or_null("Building")
	if net.join("127.0.0.1", PORT) != OK:
		quit(1)
		return
	var ok: bool = await _wait_for(func() -> bool: return net.world_seed == SEED, 20.0)
	if not ok:
		print("[%s] never received the seed (refused or host gone)" % role)
		quit(3)
		return
	var main := _boot_main()
	var cid: int = net.local_id()
	var full: bool = await _wait_for(func() -> bool: return net.players.size() == 4 and is_instance_valid(net.players.get(cid)) and is_instance_valid(net.players.get(1)), 60.0)
	if not full:
		net.report("fail%d:players %s" % [idx, str(net.players.keys())])
		await create_timer(1.0).timeout
		quit(1)
		return
	await create_timer(3.0).timeout
	var me = net.players[cid]
	var host_p = net.players[1]
	var auth: bool = me.is_multiplayer_authority() and not host_p.is_multiplayer_authority() and me.camera.current and not host_p.camera.current
	var others_ok := true
	for id in net.players:
		if id != cid and (net.players[id].is_multiplayer_authority() or net.players[id].camera.current):
			others_ok = false
	auth = auth and others_ok
	var door_open := false
	for id in B.pieces:
		if B.pieces[id]["kind"] == "door" and bool(B.pieces[id]["open"]):
			door_open = true
	var kinds := {}
	var zs = main.spawner
	if zs != null and zs.container != null:
		for z in zs.container.get_children():
			kinds[int(z.kind)] = true
	var kl: Array = kinds.keys()
	kl.sort()
	var kstr := ",".join(PackedStringArray(kl.map(func(k): return str(k))))
	# the host player sits at its spawn point (spawn slot 1 % 4 world position); compare against replicated pos
	var hp3: Vector3 = host_p.global_position
	var hsp: Vector3 = main.world.get_spawn_point(1 % 4)
	var hostpos_ok: bool = hp3.y > -50.0 and hp3.distance_to(hsp) < 60.0
	net.report("hello%d:seed=%d|sig=%s|players=%d|spawners=%d|auth=%s|pieces=%d|door_open=%s|hostpos=%s|planks=%d|kinds=%s" % [
		idx, main.world.world_seed, _sig(main.world), get_nodes_in_group("players").size(), get_nodes_in_group("spawner").size(),
		str(auth), B.pieces.size(), str(door_open), str(hostpos_ok), int(B.local_stock["planks"]), kstr])
	var spc: Vector3 = main.world.get_spawn_point(cid % 4)
	var cx := spc.x + 12.0 * idx
	var cz := spc.z + 14.0
	me.global_position = Vector3(cx, main.world.get_height(cx, cz) + 0.5, cz)
	me.velocity = Vector3.ZERO
	net.report("move%d:%f,%f" % [idx, cx, cz])
	if idx != 2:
		await create_timer(6.0).timeout
		var zc := 0
		if zs != null and zs.container != null:
			zc = zs.container.get_child_count()
		net.report("zlate%d:%d" % [idx, zc])
	if idx == 2:
		await create_timer(8.0).timeout
		net.leave()
		quit(0)
		return
	await create_timer(45.0).timeout
	quit(0)
