extends SceneTree
## Headless multiplayer self-test (two real processes over ENet loopback).
##
## Run (host process launches its own client process automatically):
##   godot --headless --path <proj> --script res://scripts/net/selftest.gd
## Optional: append `-- host <port>` to change the port (default 17777).
## The client role is `-- client <port>` and is started by the host.
##
## Proves: join handshake (session seed delivered), synced player spawn (node name =
## peer id, authority = peer id), ping RPC round trip, server-validated building
## placement synced both ways, and duplicate placement rejection.
## Exit code 0 = PASS, 1 = FAIL. Prints "SELFTEST PASS" / "SELFTEST FAIL: ...".

const PORT := 17777
const SEED := 424242
const TIMEOUT := 25.0
const NEEDED := ["seed_ok", "pong_ok", "place_ok", "reject_ok", "spawn_ok", "sync_ok"]

var role := "host"
var port := PORT
var net: Node
var building: Node
var world: Node3D
var t := 0.0
var step := 0
var step_t := 0.0
var client_pid := -1
var reports := {}
var pong := false
var rejected := ""
var floor_placed := false
var quit_at := -1.0
var result := -1
var _ready_done := false


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		role = args[0]
	if args.size() > 1:
		port = int(args[1])


## Runs on the first frame: nodes added to root inside _initialize are not yet
## in the tree, so Node.multiplayer would be null.
func _setup() -> void:
	net = root.get_node_or_null("Net")
	if net == null:
		net = _mk("res://scripts/net/network.gd", "Net")
	building = root.get_node_or_null("Building")
	if building == null:
		building = _mk("res://scripts/building/building_system.gd", "Building")
	world = Node3D.new()
	world.name = "World"
	root.add_child(world)
	net.spawn_root = world
	net.player_scene_override = _make_player_scene()
	net.client_report.connect(_on_report)
	net.ping_result.connect(func(ms: float): pong = true; _log("pong %.2f ms" % ms))
	building.build_rejected.connect(func(r: String): rejected = r)
	if role == "host":
		_start_host()
	else:
		_start_client()


func _mk(path: String, node_name: String) -> Node:
	var n: Node = (load(path) as GDScript).new()
	n.name = node_name
	root.add_child(n)
	return n


func _make_player_scene() -> PackedScene:
	var n := Node3D.new()
	n.name = "Player"
	var ps := PackedScene.new()
	ps.pack(n)
	n.free()
	return ps


func _log(msg: String) -> void:
	print("SELFTEST[%s] %s" % [role, msg])


func _finish(ok: bool, why: String = "") -> void:
	if result != -1:
		return
	result = 0 if ok else 1
	if role == "host":
		print("SELFTEST PASS" if ok else "SELFTEST FAIL: " + why)
		if client_pid > 0 and OS.is_process_running(client_pid):
			OS.kill(client_pid)
		quit_at = t
	else:
		_log("client done ok" if ok else "client FAIL: " + why)
		if not ok:
			net.report("fail:" + why)
		quit_at = t + 1.0  # let the final reliable RPC flush


# ---------------------------------------------------------------------- host

func _start_host() -> void:
	var err: int = net.host(port, SEED)
	if err != OK:
		_finish(false, "host() failed: %s" % error_string(err))
		return
	_log("hosting on %d seed %d" % [port, SEED])
	var args := ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--script", "res://scripts/net/selftest.gd", "--", "client", str(port)]
	client_pid = OS.create_process(OS.get_executable_path(), args)
	if client_pid <= 0:
		_finish(false, "could not start client process")


func _host_tick() -> void:
	for k in reports:
		if String(k) == "fail":
			_finish(false, "client reported " + String(reports[k]))
			return
	if reports.has("reject_ok") and not floor_placed:
		floor_placed = true
		building.request_place("floor", Vector4i(0, 0, 0, 0))
	for k in NEEDED:
		if not reports.has(k):
			return
	if building.pieces.size() != 2:
		_finish(false, "host sees %d pieces, expected 2" % building.pieces.size())
	elif net.players.size() != 2 or not net.players.has(1):
		_finish(false, "host sees players %s" % str(net.players.keys()))
	else:
		_finish(true)


func _on_report(from: int, msg: String) -> void:
	_log("report from %d: %s" % [from, msg])
	reports[msg.get_slice(":", 0)] = msg


# -------------------------------------------------------------------- client

func _start_client() -> void:
	var err: int = net.join("127.0.0.1", port)
	if err != OK:
		_finish(false, "join() failed")


func _advance(next: int) -> void:
	step = next
	step_t = t


func _client_tick() -> void:
	match step:
		0:
			if net.world_seed != 0:
				if net.world_seed != SEED:
					_finish(false, "seed mismatch %d" % net.world_seed)
					return
				net.report("seed_ok:%d id=%d" % [net.world_seed, net.local_id()])
				net.ping()
				_advance(1)
		1:
			if pong:
				net.report("pong_ok")
				building.request_place("wall", Vector4i(0, 0, 0, 1))
				_advance(2)
		2:
			if building.pieces.size() == 1:
				net.report("place_ok")
				building.request_place("wall", Vector4i(0, 0, 0, 1))
				_advance(3)
		3:
			if rejected != "":
				net.report("reject_ok:" + rejected)
				_advance(4)
		4:
			var ok: bool = net.players.size() == 2 and net.players.has(1) and net.players.has(net.local_id())
			if ok:
				for id in net.players:
					var p: Node = net.players[id]
					if p.name != str(id) or p.get_multiplayer_authority() != id:
						_finish(false, "player %d bad name/authority" % id)
						return
				net.report("spawn_ok")
				_advance(5)
		5:
			if building.pieces.size() == 2:
				net.report("sync_ok:2")
				_finish(true)


# ---------------------------------------------------------------------- loop

func _process(delta: float) -> bool:
	if not _ready_done:
		_ready_done = true
		_setup()
		return false
	t += delta
	if quit_at >= 0.0:
		if t >= quit_at:
			quit(result)
			return true
		return false
	if result == -1:
		if role == "host":
			_host_tick()
		else:
			_client_tick()
		if result == -1 and t > TIMEOUT:
			_finish(false, "timeout after %.0fs at step %d, reports=%s" % [TIMEOUT, step, str(reports.keys())])
	return false
