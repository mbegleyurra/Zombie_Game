class_name SkeletonSpawner
extends Node
## Spawns KayKit skeletons. Normally created by ZombieSpawner._ready as its child
## "SkeletonSpawner" (so the node path is identical on every peer); it can also be added
## standalone. Only the multiplayer server spawns.
##
## 1. Open world: a few skeletons mixed in with the zombies, more at night. Uses the parent
##    ZombieSpawner's `enabled`, `night_factor` and out-of-sight point picker.
## 2. Dungeon markers (public API): any Node3D in group "dungeon_skeleton_spawn" with meta
##    "type" = warrior / minion / rogue / mage gets one skeleton of that type at its position
##    the first time a living player is within ACTIVATE_DIST (40 m). The marker is tagged with
##    meta "skeleton_spawned"; the skeleton is a `guard` (never pruned by distance).
##
## API: spawn_skeleton_at(pos, type) -> SkeletonEnemy, poll_markers() -> int, pick_type(),
##      alive_count(), kill_all(), signals skeleton_spawned(s) / skeleton_killed(s)

signal skeleton_spawned(s: SkeletonEnemy)
signal skeleton_killed(s: SkeletonEnemy)

const SCENE := "res://scenes/zombies/skeleton.tscn"
const MARKER_GROUP := "dungeon_skeleton_spawn"
const ACTIVATE_DIST := 40.0
const HandMapData = preload("res://scripts/world/hand_map_data.gd")

@export var enabled: bool = true
@export var day_cap_per_player: int = 1
@export var night_cap_per_player: int = 3
@export var hard_cap: int = 8
@export var interval_day: float = 18.0
@export var interval_night: float = 7.0
@export var day_spawn_chance: float = 0.3
@export var despawn_dist: float = 140.0

var container: Node
var night_factor: float = 0.0
var kills: int = 0
var _seq: int = 0                 ## deterministic round-robin counter; no random draws
var _chance_acc: float = 0.5      ## spawn-chance accumulator (replaces a random roll)
var _last_row: Array = []         ## authored row [x, z, yaw, roll, variant_seed] for the next skeleton
var _mp_spawner: MultiplayerSpawner
var _packed: PackedScene
var _timer: float = 12.0
var _marker_timer: float = 0.5
var _prune_timer: float = 3.0


func _ready() -> void:
	add_to_group("skeleton_spawner")
	if container != null:
		return
	_packed = load(SCENE) as PackedScene
	if _packed == null:
		push_error("SkeletonSpawner: cannot load " + SCENE)
	container = Node.new()
	container.name = "SkeletonContainer"
	add_child(container)
	_mp_spawner = MultiplayerSpawner.new()
	_mp_spawner.name = "SkeletonMP"
	add_child(_mp_spawner)
	_mp_spawner.spawn_path = NodePath("../SkeletonContainer")
	_mp_spawner.add_spawnable_scene(SCENE)
	var net := get_node_or_null("/root/Net")
	if net != null:
		net.peer_scene_ready.connect(_on_peer_scene_ready)


func _gate_visibility(s: SkeletonEnemy) -> void:
	var sync := s.get_node_or_null("ZombieSync") as MultiplayerSynchronizer
	var net := get_node_or_null("/root/Net")
	if sync == null or net == null:
		return
	sync.public_visibility = false
	for id in net.scene_ready_peers:
		sync.set_visibility_for(id, true)


func _on_peer_scene_ready(id: int) -> void:
	if container == null or not multiplayer.is_server():
		return
	for c in container.get_children():
		var sync := c.get_node_or_null("ZombieSync") as MultiplayerSynchronizer
		if sync != null:
			sync.set_visibility_for(id, true)


func alive_count(include_guards: bool = true) -> int:
	var n := 0
	if container == null:
		return 0
	for c in container.get_children():
		var s := c as SkeletonEnemy
		if s != null and s.state_id != Zombie.State.DEAD and (include_guards or not s.guard):
			n += 1
	return n


func kill_all() -> void:
	if container == null or not multiplayer.is_server():
		return
	for c in container.get_children():
		c.queue_free()


func _physics_process(delta: float) -> void:
	if not enabled or container == null or not multiplayer.is_server():
		return
	_marker_timer -= delta
	if _marker_timer <= 0.0:
		_marker_timer = 1.0
		poll_markers()
	var zs := get_parent()
	if zs != null and "night_factor" in zs:
		night_factor = float(zs.get("night_factor"))
	_prune_timer -= delta
	if _prune_timer <= 0.0:
		_prune_timer = 3.0
		_prune_far()
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = lerpf(interval_day, interval_night, night_factor)
	if zs == null or not zs.has_method("_pick_point") or ("enabled" in zs and not bool(zs.get("enabled"))):
		return   # open-world spawning needs the parent ZombieSpawner
	_chance_acc += lerpf(day_spawn_chance, 1.0, night_factor)
	if _chance_acc < 1.0:
		return
	_chance_acc -= 1.0
	var players := _alive_players()
	if players.is_empty():
		return
	var cap := mini(int(lerpf(float(day_cap_per_player), float(night_cap_per_player), night_factor) * players.size()), hard_cap)
	if alive_count(false) >= cap:
		return
	var p: Player = players[_seq % players.size()]
	_seq += 1
	for _attempt in range(8):
		var pos = zs.call("_pick_point", p, players, "SKELETON_SPAWNS")
		if pos != null:
			_last_row = zs.get("_last_row")
			zs.set("_last_row", [])
			spawn_skeleton_at(pos as Vector3, pick_type())
			return


func _alive_players() -> Array[Player]:
	var out: Array[Player] = []
	for n in get_tree().get_nodes_in_group("players"):
		var p := n as Player
		if p != null and not p.is_dead:
			out.append(p)
	return out


func _prune_far() -> void:
	var players := _alive_players()
	if players.is_empty():
		return
	for c in container.get_children():
		var s := c as SkeletonEnemy
		if s == null or s.guard:
			continue
		var near := false
		for p in players:
			if p.global_position.distance_to(s.global_position) < despawn_dist:
				near = true
				break
		if not near:
			s.queue_free()


## The authored row for the next skeleton: the one just picked, else the next SKELETON_SPAWNS row in file order.
func _row() -> Array:
	if _last_row.is_empty():
		var rows: Array = HandMapData.section("SKELETON_SPAWNS")
		if rows.is_empty():
			_last_row = [0.0, 0.0, 0.0, 0.5, 1]
		else:
			_last_row = rows[_seq % rows.size()]
			_seq += 1
	return _last_row


## Open-world type from the authored row's roll: mostly melee, mages are the rarest.
func pick_type(roll: float = -1.0) -> String:
	var r: float = roll if roll >= 0.0 else float(_row()[3])
	if r < 0.35:
		return "warrior"
	if r < 0.7:
		return "minion"
	if r < 0.9:
		return "rogue"
	return "mage"


## Server only. `type_name` is warrior / minion / rogue / mage (unknown -> warrior).
func spawn_skeleton_at(pos: Vector3, type_name: String = "warrior", yaw: float = NAN) -> SkeletonEnemy:
	if not multiplayer.is_server() or _packed == null or container == null:
		return null
	var s := _packed.instantiate() as SkeletonEnemy
	s.kind = SkeletonEnemy.kind_for_type(type_name)
	s.night_mult = night_factor
	var row: Array = _row()
	_last_row = []
	s.variant_seed = int(row[4])
	s.position = pos
	s.rotation.y = float(row[2]) if is_nan(yaw) else yaw
	container.add_child(s, true)
	_gate_visibility(s)
	s.died.connect(_on_skeleton_died)
	skeleton_spawned.emit(s)
	return s


## Spawns the skeleton for every marker that has a living player within ACTIVATE_DIST.
## Returns how many were spawned. Runs once a second from _physics_process.
func poll_markers() -> int:
	if not multiplayer.is_server() or container == null:
		return 0
	var players := _alive_players()
	if players.is_empty():
		return 0
	var made := 0
	for n in get_tree().get_nodes_in_group(MARKER_GROUP):
		var m := n as Node3D
		if m == null or not m.is_inside_tree() or m.has_meta("skeleton_spawned"):
			continue
		var pos := m.global_position
		var near := false
		for p in players:
			if p.global_position.distance_to(pos) <= ACTIVATE_DIST:
				near = true
				break
		if not near:
			continue
		var s := spawn_skeleton_at(pos + Vector3.UP * 0.05, str(m.get_meta("type", "warrior")), m.global_rotation.y)
		if s == null:
			continue
		s.guard = true
		m.set_meta("skeleton_spawned", true)
		m.set_meta("skeleton", s)
		made += 1
	return made


func _on_skeleton_died(s: Zombie) -> void:
	kills += 1
	skeleton_killed.emit(s as SkeletonEnemy)
