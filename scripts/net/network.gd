extends Node
## Dead Acres networking. Autoload name: "Net".
##
## Host-based ENet co-op, 2-4 players. The host owns the world seed and the
## player roster. Players are spawned by manual RPC (no MultiplayerSpawner) so
## the world scene needs no special node. Every peer instantiates
## res://scenes/player/player.tscn, names the node after the peer id and gives
## that peer multiplayer authority over it.

signal hosted(port: int)
signal connection_succeeded
signal connection_failed(reason: String)
signal server_closed
signal world_seed_received(world_seed: int)
signal player_connected(id: int)
signal player_disconnected(id: int)
signal player_spawned(id: int, node: Node)
signal player_despawned(id: int)
signal ping_result(ms: float)
signal ping_received(from: int, token: int)
signal client_report(from: int, message: String)
## Host only: a client's main scene (Main/Spawner/...) now exists, so scene-bound nodes may replicate to it.
signal peer_scene_ready(id: int)
signal left

const DEFAULT_PORT := 7777
const MAX_PLAYERS := 4
const PLAYER_SCENE_PATH := "res://scenes/player/player.tscn"
const GAME_SCENE_PATH := "res://scenes/main.tscn"
const MENU_SCENE_PATH := "res://scenes/ui/menu.tscn"

## True from host()/join() until leave().
var active := false
## Shared world seed. The host picks it; clients receive it right after joining.
var world_seed := 0
## Peer ids currently in the game (host is always 1).
var roster: Array[int] = []
## peer id -> spawned player node.
var players := {}
## Node that receives player nodes. Null = current scene (unless it is the menu).
var spawn_root: Node = null
## Tests can inject a PackedScene instead of the real player scene.
var player_scene_override: PackedScene = null
## Optional Callable(peer_id: int) -> Vector3. Must be deterministic per id.
var spawn_position_provider := Callable()
var last_ping_ms := -1.0

## Host only: peers that reported their main scene is built (see notify_scene_ready).
var scene_ready_peers: Array[int] = []

var _pending: Array[int] = []
## Peers that confirmed they spawned OUR player node; its PlayerSync is shown only to them.
var _ack_peers: Array[int] = []
var _warned_missing := false


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


# ---------------------------------------------------------------- public API

func is_host() -> bool:
	return active and multiplayer.is_server()


func local_id() -> int:
	return multiplayer.get_unique_id() if active else 0


func get_local_player() -> Node:
	var p = players.get(local_id())
	return p if p != null and is_instance_valid(p) else null


## local_only binds loopback and admits one client (Play Solo). silent suppresses connection_failed.
func host(port: int = DEFAULT_PORT, seed_value: int = 0, local_only: bool = false, silent: bool = false) -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	if local_only:
		peer.set_bind_ip("127.0.0.1")
	var err := peer.create_server(port, 1 if local_only else MAX_PLAYERS - 1)
	if err != OK:
		if not silent:
			connection_failed.emit("Cannot host on port %d (%s)" % [port, error_string(err)])
		return err
	multiplayer.multiplayer_peer = peer
	world_seed = seed_value if seed_value != 0 else (randi() % 2000000000) + 1
	active = true
	roster = [1]
	_queue_spawn(1)
	hosted.emit(port)
	return OK


## Single player: a loopback-only host so Net.active is true and building works.
func host_solo(seed_value: int = 0) -> Error:
	var err := ERR_CANT_CREATE
	for i in 16:
		err = host(DEFAULT_PORT + 100 + i, seed_value, true, true)
		if err == OK:
			return OK
	connection_failed.emit("Cannot start a solo game (%s)" % error_string(err))
	return err


func join(address: String, port: int = DEFAULT_PORT) -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		connection_failed.emit("Cannot connect to %s:%d (%s)" % [address, port, error_string(err)])
		return err
	multiplayer.multiplayer_peer = peer
	active = true
	return OK


func leave() -> void:
	var was_active := active
	if multiplayer.has_multiplayer_peer():
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	for id in players.keys():
		_despawn(id)
	players.clear()
	roster.clear()
	_pending.clear()
	_ack_peers.clear()
	scene_ready_peers.clear()
	active = false
	world_seed = 0
	last_ping_ms = -1.0
	if was_active:
		left.emit()


## Loads the world scene. Call after host() or after world_seed_received.
func start_game() -> Error:
	if not ResourceLoader.exists(GAME_SCENE_PATH):
		push_warning("Net: %s does not exist yet" % GAME_SCENE_PATH)
		return ERR_FILE_NOT_FOUND
	return get_tree().change_scene_to_file(GAME_SCENE_PATH)


func leave_to_menu() -> void:
	leave()
	if ResourceLoader.exists(MENU_SCENE_PATH):
		get_tree().change_scene_to_file.call_deferred(MENU_SCENE_PATH)


func _is_connected() -> bool:
	return multiplayer.has_multiplayer_peer() \
		and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


## Spawn slot 0..MAX_PLAYERS-1 = the peer's place in the roster. Peer ids are random 32-bit
## numbers, so `id % 4` collides (two players on one spawn point) in most 4-peer games.
func spawn_slot_for(id: int) -> int:
	var i := roster.find(id)
	return (i if i >= 0 else absi(id)) % MAX_PLAYERS


func spawn_position_for(id: int) -> Vector3:
	if spawn_position_provider.is_valid():
		return spawn_position_provider.call(id)
	return Vector3(float(spawn_slot_for(id)) * 2.0, 3.0, 0.0)


## Round-trip time probe (client -> host -> client). Result: ping_result.
func ping() -> void:
	if not active or is_host() or not _is_connected():
		return
	_rpc_ping.rpc_id(1, Time.get_ticks_usec())


## Client -> host: "my main scene is built". The host then starts replicating scene-bound
## nodes (zombies) to this peer; before that they would hit a missing Main/Spawner path.
func notify_scene_ready() -> void:
	if not active or is_host() or not _is_connected():
		return
	_rpc_scene_ready.rpc_id(1)


## Client -> host free-form message (used by the self-test).
func report(message: String) -> void:
	if not active or not _is_connected():
		return
	if is_host():
		client_report.emit(1, message)
	else:
		_rpc_report.rpc_id(1, message)


# ------------------------------------------------------------------ spawning

func _process(_delta: float) -> void:
	if _pending.is_empty():
		return
	var root := _resolve_spawn_root()
	if root == null:
		return
	var scene := _player_scene()
	if scene == null:
		if not _warned_missing:
			_warned_missing = true
			push_warning("Net: %s missing, players will spawn once it exists" % PLAYER_SCENE_PATH)
		return
	var todo := _pending.duplicate()
	_pending.clear()
	for id in todo:
		_spawn(id, root, scene)


func _queue_spawn(id: int) -> void:
	if not _pending.has(id) and not players.has(id):
		_pending.append(id)


func _resolve_spawn_root() -> Node:
	if spawn_root != null and is_instance_valid(spawn_root) and spawn_root.is_inside_tree():
		return spawn_root
	var cs := get_tree().current_scene
	if cs != null and cs.is_inside_tree() and cs.scene_file_path != MENU_SCENE_PATH:
		return cs
	return null


func _player_scene() -> PackedScene:
	if player_scene_override != null:
		return player_scene_override
	if ResourceLoader.exists(PLAYER_SCENE_PATH):
		return load(PLAYER_SCENE_PATH) as PackedScene
	return null


func _spawn(id: int, root: Node, scene: PackedScene) -> void:
	if players.has(id) and is_instance_valid(players[id]):
		return
	var p := scene.instantiate()
	p.name = str(id)
	p.set_multiplayer_authority(id)
	root.add_child(p)
	if p is Node3D:
		(p as Node3D).global_position = spawn_position_for(id)
	players[id] = p
	player_spawned.emit(id, p)
	_announce_spawn(id)


## Tell the node's owner we have it, so it starts replicating to us. Also applies
## confirmations that arrived before our own player node existed.
func _announce_spawn(id: int) -> void:
	if id == local_id():
		_grant_visibility()
	elif _is_connected():
		_rpc_spawned.rpc_id(id, id)


func _grant_visibility() -> void:
	var p = get_local_player()
	if p == null or p.get_multiplayer_authority() != local_id():
		return
	var sync := p.get_node_or_null("PlayerSync") as MultiplayerSynchronizer
	if sync == null:
		return
	for peer in _ack_peers:
		sync.set_visibility_for(peer, true)


func _despawn(id: int) -> void:
	_pending.erase(id)
	_ack_peers.erase(id)
	scene_ready_peers.erase(id)
	var p = players.get(id)
	players.erase(id)
	if p != null and is_instance_valid(p):
		p.queue_free()
		player_despawned.emit(id)


# ------------------------------------------------------- multiplayer signals

func _on_peer_connected(id: int) -> void:
	if not is_host():
		return
	if roster.size() >= MAX_PLAYERS:
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	roster.append(id)
	_rpc_welcome.rpc_id(id, world_seed, PackedInt32Array(roster))
	for other in multiplayer.get_peers():
		if other != id:
			_rpc_peer_joined.rpc_id(other, id)
	_queue_spawn(id)
	player_connected.emit(id)


func _on_peer_disconnected(id: int) -> void:
	if not is_host():
		return
	roster.erase(id)
	for other in multiplayer.get_peers():
		_rpc_peer_left.rpc_id(other, id)
	_despawn(id)
	player_disconnected.emit(id)


func _on_connected_to_server() -> void:
	connection_succeeded.emit()


func _on_connection_failed() -> void:
	leave()
	connection_failed.emit("Host unreachable")


func _on_server_disconnected() -> void:
	leave()
	server_closed.emit()
	if get_tree().current_scene != null and get_tree().current_scene.scene_file_path != MENU_SCENE_PATH:
		leave_to_menu()


# ---------------------------------------------------------------------- RPCs

@rpc("authority", "call_remote", "reliable")
func _rpc_welcome(seed_value: int, ids: PackedInt32Array) -> void:
	world_seed = seed_value
	roster.clear()
	for id in ids:
		roster.append(id)
		_queue_spawn(id)
		if id != local_id() and id != 1:
			player_connected.emit(id)
	world_seed_received.emit(seed_value)


@rpc("authority", "call_remote", "reliable")
func _rpc_peer_joined(id: int) -> void:
	if not roster.has(id):
		roster.append(id)
	_queue_spawn(id)
	player_connected.emit(id)


@rpc("authority", "call_remote", "reliable")
func _rpc_peer_left(id: int) -> void:
	roster.erase(id)
	_despawn(id)
	player_disconnected.emit(id)


## A peer reports it has spawned our player node (id == our id): start replicating to it.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_spawned(id: int) -> void:
	if not active or id != local_id():
		return
	var from := multiplayer.get_remote_sender_id()
	if not _ack_peers.has(from):
		_ack_peers.append(from)
	_grant_visibility()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_scene_ready() -> void:
	if not is_host():
		return
	var from := multiplayer.get_remote_sender_id()
	if not roster.has(from) or scene_ready_peers.has(from):
		return
	scene_ready_peers.append(from)
	peer_scene_ready.emit(from)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_ping(token: int) -> void:
	var from := multiplayer.get_remote_sender_id()
	ping_received.emit(from, token)
	_rpc_pong.rpc_id(from, token)


@rpc("authority", "call_remote", "reliable")
func _rpc_pong(token: int) -> void:
	last_ping_ms = float(Time.get_ticks_usec() - token) / 1000.0
	ping_result.emit(last_ping_ms)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_report(message: String) -> void:
	client_report.emit(multiplayer.get_remote_sender_id(), message)
