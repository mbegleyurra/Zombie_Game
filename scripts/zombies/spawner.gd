class_name ZombieSpawner
extends Node
## Horde spawner. Add ONE node with this script to the world scene (same path on
## every peer). It joins group "spawner", and only the multiplayer server spawns.
## Zombies are created under a child container that a MultiplayerSpawner
## replicates to clients.
##
## Night scaling: reads a node in group "daynight" (or "day_night") that offers
## get_night_factor() -> 0..1, a `night_factor` property, or is_night() -> bool.
## Otherwise call set_night_factor(f) yourself.
##
## Instancing: main.gd may `ZombieSpawner.new()` it (name it "ZombieSpawner" so the
## MultiplayerSpawner path matches on every peer). It is inert on non-servers, but
## clients still need the same node so replicated zombies have a parent.
##
## Public API:
##   set_night_factor(f), spawn_zombie_at(pos, runner, kind=-1) -> Zombie, pick_kind(), spawn_horde(center, count),
##   alive_count(), kill_all(), signal zombie_spawned(z), zombie_killed(z), horde_started(count)

signal zombie_spawned(z: Zombie)
signal zombie_killed(z: Zombie)
signal horde_started(count: int)

const ZOMBIE_SCENE := "res://scenes/zombies/zombie.tscn"
const MASK_WORLD := 1
const HandMapData = preload("res://scripts/world/hand_map_data.gd")

@export var enabled: bool = true
@export var base_cap: int = 8
@export var day_cap_per_player: int = 6
@export var night_cap_per_player: int = 20
@export var hard_cap: int = 90
@export var interval_day: float = 4.0
@export var interval_night: float = 1.0
@export var min_spawn_dist: float = 32.0
@export var max_spawn_dist: float = 60.0
@export var despawn_dist: float = 140.0
@export var horde_on_nightfall: bool = true

var night_factor: float = 0.0
var container: Node
var skeletons: Node   ## SkeletonSpawner child (open-world skeletons + dungeon markers)
var _mp_spawner: MultiplayerSpawner
var _packed: PackedScene
var _timer: float = 2.0
var _night_poll: float = 0.0
var _was_night: bool = false
var _prune_timer: float = 0.0
var kills: int = 0
var _seq: int = 0                 ## deterministic round-robin counter (player choice, row cycling); no random draws
var _cursor: Dictionary = {}      ## section -> next authored spawn row to try
var _last_row: Array = []         ## authored row [x, z, yaw, roll, variant_seed] picked for the next spawn


func _ready() -> void:
	add_to_group("spawner")
	if container != null:
		return   # already built: safe against a second _ready / re-parenting
	_packed = load(ZOMBIE_SCENE) as PackedScene
	if _packed == null:
		push_error("ZombieSpawner: cannot load " + ZOMBIE_SCENE)
	container = Node.new()
	container.name = "ZombieContainer"
	add_child(container)
	_mp_spawner = MultiplayerSpawner.new()
	_mp_spawner.name = "ZombieMP"
	add_child(_mp_spawner)
	_mp_spawner.spawn_path = NodePath("../ZombieContainer")
	_mp_spawner.add_spawnable_scene(ZOMBIE_SCENE)
	var net := get_node_or_null("/root/Net")
	if net != null:
		net.peer_scene_ready.connect(_on_peer_scene_ready)
	skeletons = SkeletonSpawner.new()
	skeletons.name = "SkeletonSpawner"   # child of this node: same path on every peer
	add_child(skeletons)


## Zombies are hidden from every peer until that peer reports its main scene is built
## (Net.peer_scene_ready); otherwise the spawn packet hits a missing Main/Spawner/ZombieMP.
func _gate_visibility(z: Zombie) -> void:
	var sync := z.get_node_or_null("ZombieSync") as MultiplayerSynchronizer
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


func set_night_factor(f: float) -> void:
	night_factor = clampf(f, 0.0, 1.0)


func alive_count() -> int:
	var n := 0
	if container == null:
		return 0
	for c in container.get_children():
		var z := c as Zombie
		if z != null and z.state_id != Zombie.State.DEAD:
			n += 1
	return n


func kill_all() -> void:
	if container == null or not multiplayer.is_server():
		return
	for c in container.get_children():
		c.queue_free()
	if skeletons != null:
		skeletons.call("kill_all")


# ================================================================== loop

func _physics_process(delta: float) -> void:
	if not enabled or container == null or not multiplayer.is_server():
		return
	_night_poll -= delta
	if _night_poll <= 0.0:
		_night_poll = 1.0
		_poll_night()
	_prune_timer -= delta
	if _prune_timer <= 0.0:
		_prune_timer = 3.0
		_prune_far()
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = lerpf(interval_day, interval_night, night_factor)
	var players := _alive_players()
	if players.is_empty():
		return
	var per_player := lerpf(float(day_cap_per_player), float(night_cap_per_player), night_factor)
	var cap := mini(int(per_player * players.size()) + base_cap, hard_cap)
	if alive_count() < cap:
		_try_spawn(players)


func _poll_night() -> void:
	for g in ["daynight", "day_night"]:
		var n := get_tree().get_first_node_in_group(g)
		if n == null:
			continue
		if n.has_method("get_night_factor"):
			night_factor = clampf(float(n.call("get_night_factor")), 0.0, 1.0)
		elif "night_factor" in n:
			night_factor = clampf(float(n.get("night_factor")), 0.0, 1.0)
		elif n.has_method("get_darkness"):
			night_factor = clampf(float(n.call("get_darkness")), 0.0, 1.0)
		elif n.has_method("is_night"):
			night_factor = 1.0 if bool(n.call("is_night")) else 0.0
		break
	var is_night := night_factor > 0.6
	if is_night and not _was_night and horde_on_nightfall:
		var players := _alive_players()
		if not players.is_empty():
			var p: Player = players[_seq % players.size()]
			_seq += 1
			spawn_horde(p.global_position, 6 + 4 * players.size())
	_was_night = is_night


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
		var z := c as Zombie
		if z == null:
			continue
		var near := false
		for p in players:
			if p.global_position.distance_to(z.global_position) < despawn_dist:
				near = true
				break
		if not near:
			z.queue_free()


# ================================================================== spawning

func _try_spawn(players: Array[Player]) -> void:
	var p: Player = players[_seq % players.size()]
	_seq += 1
	for _attempt in range(8):
		var pos = _pick_point(p, players)
		if pos != null:
			spawn_zombie_at(pos as Vector3, false, pick_kind())
			return


## Returns a ground point 32-60 m from `anchor` that no player can currently see, or null. Candidates are the
## AUTHORED spawn rows of `section` in data/hand_map/placements.json, walked from a rolling cursor (no random draws).
## The row used is left in _last_row for the spawn that follows.
func _pick_point(anchor: Player, players: Array[Player], section: String = "ZOMBIE_SPAWNS") -> Variant:
	var rows: Array = HandMapData.section(section)
	if rows.is_empty():
		return null
	var start: int = int(_cursor.get(section, 0))
	var space := anchor.get_world_3d().direct_space_state
	var flat := Vector2(anchor.global_position.x, anchor.global_position.z)
	var tested := 0
	for k in rows.size():
		var i: int = (start + k) % rows.size()
		var row: Array = rows[i]
		var d: float = Vector2(float(row[0]), float(row[1])).distance_to(flat)
		if d < min_spawn_dist or d > max_spawn_dist:
			continue
		_cursor[section] = i + 1
		tested += 1
		var pos = _unseen_ground(float(row[0]), float(row[1]), anchor, players, space)
		if pos != null:
			_last_row = row
			return pos
		if tested >= 3:
			return null
	return null


func _unseen_ground(x: float, z: float, anchor: Player, players: Array[Player], space: PhysicsDirectSpaceState3D) -> Variant:
	var xz := Vector3(x, 0.0, z)
	var q := PhysicsRayQueryParameters3D.create(
		Vector3(xz.x, anchor.global_position.y + 80.0, xz.z),
		Vector3(xz.x, anchor.global_position.y - 80.0, xz.z), MASK_WORLD)
	var res := space.intersect_ray(q)
	if res.is_empty():
		return null
	var ground: Vector3 = res["position"]
	var spot := ground + Vector3.UP * 1.0
	for pl in players:
		var d := pl.global_position.distance_to(ground)
		if d < min_spawn_dist * 0.7:
			return null
		if _player_can_see(pl, space, spot):
			return null
	return ground + Vector3.UP * 0.1


func _player_can_see(pl: Player, space: PhysicsDirectSpaceState3D, spot: Vector3) -> bool:
	var eye := pl.camera.global_position
	var fwd := -pl.camera.global_transform.basis.z
	var to := (spot - eye).normalized()
	if fwd.dot(to) < 0.2:
		return false   # behind / far to the side
	var q := PhysicsRayQueryParameters3D.create(eye, spot, MASK_WORLD, [pl.get_rid()])
	return space.intersect_ray(q).is_empty()


## The authored row for the next spawn: the one _pick_point just chose, else the next row in file order.
func _row() -> Array:
	if _last_row.is_empty():
		var rows: Array = HandMapData.section("ZOMBIE_SPAWNS")
		if rows.is_empty():
			_last_row = [0.0, 0.0, 0.0, 0.5, 1]
		else:
			_last_row = rows[_seq % rows.size()]
			_seq += 1
	return _last_row


## Variant mix from the authored row's roll (0..1), scaled by the night factor: by day mostly walkers, by
## night many more runners and bloaters.
func pick_kind(roll: float = -1.0) -> int:
	var r: float = roll if roll >= 0.0 else float(_row()[3])
	var bloater_p := 0.04 + 0.12 * night_factor
	var runner_p := 0.05 + 0.35 * night_factor
	if r < bloater_p:
		return Zombie.KIND_BLOATER
	if r < bloater_p + runner_p:
		return Zombie.KIND_RUNNER
	return Zombie.KIND_WALKER


## `kind` < 0 means "walker, or runner when `runner` is true" (back-compat);
## otherwise it is Zombie.KIND_WALKER / KIND_RUNNER / KIND_BLOATER.
func spawn_zombie_at(pos: Vector3, runner: bool = false, kind: int = -1) -> Zombie:
	if not multiplayer.is_server() or _packed == null:
		return null
	var z := _packed.instantiate() as Zombie
	z.night_mult = night_factor
	z.kind = (Zombie.KIND_RUNNER if runner else Zombie.KIND_WALKER) if kind < 0 else kind
	z.runner = z.kind == Zombie.KIND_RUNNER
	var row: Array = _row()
	_last_row = []
	z.variant_seed = int(row[4])
	z.position = pos
	z.rotation.y = float(row[2])
	container.add_child(z, true)
	_gate_visibility(z)
	z.died.connect(_on_zombie_died)
	zombie_spawned.emit(z)
	return z


func spawn_horde(center: Vector3, count: int) -> void:
	if not multiplayer.is_server():
		return
	var players := _alive_players()
	var anchor: Player = null
	var best := INF
	for p in players:
		var d := p.global_position.distance_to(center)
		if d < best:
			best = d
			anchor = p
	if anchor == null:
		return
	var made := 0
	for _i in range(count * 4):
		if made >= count:
			break
		var pos = _pick_point(anchor, players)
		if pos == null:
			continue
		var z := spawn_zombie_at(pos as Vector3, false, pick_kind())
		if z != null:
			z._investigate_pos = center
			z._set_state(Zombie.State.INVESTIGATE)
			made += 1
	if made > 0:
		horde_started.emit(made)


func _on_zombie_died(z: Zombie) -> void:
	kills += 1
	zombie_killed.emit(z)
