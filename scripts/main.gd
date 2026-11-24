extends Node3D
## Entry scene for Dead Acres. Loads the baked world (scenes/world/world_baked.tscn via world_builder.gd) and spawns
## the local player. Command line (after "--"): --no-player skips the local player. --seed=N is still accepted and
## kept as the session seed, but it no longer changes the world: every peer loads the same baked scenes.
##
## Public API:
##   build_world(seed)               loads the baked world (done automatically in _ready; seed is ignored)
##   spawn_player(slot, peer_id)     instances res://scenes/player/player.tscn (or a fallback camera), returns the node
## Nodes in group "spawner" that implement on_world_ready(world, main) are called once the world exists.
## Signal: world_ready(world)

signal world_ready(world)

const WORLD_SCENE := "res://scenes/world/world.tscn"
const PLAYER_SCENE := "res://scenes/player/player.tscn"
const FallbackCamera = preload("res://scripts/world/fallback_camera.gd")
const SPAWNER_SCRIPT := "res://scripts/zombies/spawner.gd"
const SOLO_SEED := 20260101

@export var world_seed: int = 20260101
@export var spawn_local_player: bool = true

var world: Node3D
var players: Node3D
var local_player: Node = null
var spawner: Node = null


func _ready() -> void:
	add_to_group("main_world")
	for arg in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			world_seed = int(arg.substr(7))
		elif arg == "--no-player":
			spawn_local_player = false
	var net := _net()
	var net_active: bool = net != null and bool(net.active)
	if net_active and int(net.world_seed) != 0:
		world_seed = int(net.world_seed)
	players = Node3D.new()
	players.name = "Players"
	add_child(players)
	build_world(world_seed)
	if net_active:
		# Net spawns every player (host included); place them on the world's spawn points.
		net.spawn_position_provider = Callable(self, "_net_spawn_position")
	elif spawn_local_player:
		local_player = spawn_player(0, 1)
	_add_spawner()
	if net_active:
		net.notify_scene_ready.call_deferred()   # host starts replicating zombies to us only now
	_notify_spawners.call_deferred()
	world_ready.emit(world)


func _exit_tree() -> void:
	var net := _net()
	if net != null and net.spawn_position_provider == Callable(self, "_net_spawn_position"):
		net.spawn_position_provider = Callable()


func _net() -> Node:
	return get_node_or_null("/root/Net")


func _net_spawn_position(peer_id: int) -> Vector3:
	var net := _net()
	return world.get_spawn_point(net.spawn_slot_for(peer_id) if net != null else peer_id % 4)


## Zombie spawner. Present on every peer (its MultiplayerSpawner needs the same path
## everywhere); only the multiplayer server actually spawns.
func _add_spawner() -> void:
	spawner = (load(SPAWNER_SCRIPT) as GDScript).new()
	spawner.name = "Spawner"
	add_child(spawner)


## Loot pickups call this (via ItemDB.give_to) so planks/scrap feed the building stock.
func give_materials(item: String, n: int) -> void:
	var net := _net()
	if net == null or not net.active or n <= 0:
		return
	if multiplayer.is_server():
		var b := get_node_or_null("/root/Building")
		if b != null:
			b.give(1, item, n)
	else:
		_rpc_give_materials.rpc_id(1, item, n)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_give_materials(item: String, n: int) -> void:
	if not multiplayer.is_server() or (item != "planks" and item != "scrap"):
		return
	var b := get_node_or_null("/root/Building")
	if b != null:
		b.give(multiplayer.get_remote_sender_id(), item, clampi(n, 1, 30))


func build_world(p_seed: int) -> void:
	world_seed = p_seed
	var packed: PackedScene = load(WORLD_SCENE)
	world = packed.instantiate()
	world.name = "World"
	add_child(world)
	world.build(world_seed)


func spawn_player(slot: int = 0, peer_id: int = 1) -> Node:
	var pos: Vector3 = world.get_spawn_point(slot)
	var node: Node = null
	if ResourceLoader.exists(PLAYER_SCENE):
		var packed = load(PLAYER_SCENE)
		if packed is PackedScene:
			node = packed.instantiate()
	var fallback := false
	if node == null:
		node = FallbackCamera.new()
		fallback = true
	node.name = "Player_%d" % peer_id
	players.add_child(node)
	if node is Node3D:
		(node as Node3D).global_position = pos + (Vector3(0, 6, 0) if fallback else Vector3.ZERO)
	print("[Main] spawned %s at %s (%s)" % [node.name, pos, "fallback camera" if fallback else "player scene"])
	return node


func _notify_spawners() -> void:
	for n in get_tree().get_nodes_in_group("spawner"):
		if n.has_method("on_world_ready"):
			n.on_world_ready(world, self)
