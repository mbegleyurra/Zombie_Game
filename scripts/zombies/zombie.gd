class_name Zombie
extends CharacterBody3D
## Low-poly humanoid zombie. AI runs ONLY on the multiplayer server; clients
## receive position/rotation/state/health through a MultiplayerSynchronizer built
## in _ready and only play animation. Works without a baked navmesh (whisker
## steering); uses NavigationAgent3D automatically if a navmesh region exists.
##
## Public API:
##   request_damage(amount, headshot, attacker_peer)  (bullets call this; routes to server)
##   is_head_hit(world_pos)
##   hear_noise(pos, radius)    (called via group "zombies" by Player.emit_noise)
##   alert_to(player)           (aggro on a player)
##   signal died(zombie)

signal died(zombie: Zombie)

enum State { IDLE, WANDER, INVESTIGATE, CHASE, ATTACK, DEAD }

const GRAVITY := 18.0
const MASK_WORLD := 1
const KIND_WALKER := 0
const KIND_RUNNER := 1
const KIND_BLOATER := 2
const FLINCH_TIME := 0.28
const DEATH_TIME := 1.1   ## seconds for the full collapse animation
const WALKER_MODEL := "res://assets/kenney/mini/character-zombie.glb"
const WALKER_SCALE := 2.43       ## Kenney model is ~0.70 tall: x2.43 = ~1.70 m (was 2.6 = 1.82 m, taller than the 1.8 m player once the huge head is counted)
const WALKER_WIDTH := 0.8        ## extra x/z squash on the Kenney model: its chibi head is ~0.94 m wide at unit scale, so height alone left it looking giant; ~0.7 m wide head now
const WALKER_HEIGHT := 1.7       ## walker capsule height (feet to crown)
const WALKER_HEAD_LINE := 1.36   ## head hit line for the Kenney walker (head spans ~0.9-1.77 m); must stay above the ~1.32 m a 300 m rifle drop lands at
const WALKER_RADIUS := 0.34      ## collision capsule radius for the Kenney walker: its scaled head/legs are ~0.6-0.7 m wide, the stock 0.32 let shots pass through the head edge
const WALKER_HEAD_RADIUS := 0.36 ## extra head sphere: the head is ~0.7 m wide, wider than the capsule; centre offset + radius must stay under half the narrowest door (1.2 m)

# --- dismemberment: bit flags in `severed` (replicated) ---
const PART_HEAD := 1
const PART_ARM_L := 2    ## _arms[0], zombie-local -X side
const PART_ARM_R := 4    ## _arms[1], +X side
const PART_LEG_L := 8    ## _legs[0], -X side
const PART_LEG_R := 16   ## _legs[1], +X side
const ARM_SEVER_FRAC := 0.3     ## damage a limb must take, as a fraction of max health, before it comes off
const LEG_SEVER_FRAC := 0.4
const HEAD_SEVER_FRAC := 0.9    ## accumulated head damage that decapitates (a killing headshot always does)
const ARM_REACH_LOSS := 0.2     ## attack range lost per missing arm
const ARM_DAMAGE_LOSS := 0.3    ## attack damage lost per missing arm
const LEG_SPEED := [1.0, 0.55, 0.25]   ## speed multiplier by number of missing legs (2 = crawling)
const CRAWL_HEIGHT := 0.5       ## head line and collision height multiplier while crawling
const MAX_GIBS := 16
const MAX_DECALS := 48

@export var max_health: float = 100.0
@export var walk_speed: float = 1.1
@export var investigate_speed: float = 2.3
@export var chase_speed: float = 3.4
@export var runner_speed: float = 5.4
@export var sight_range: float = 28.0
@export var sight_fov_deg: float = 110.0
@export var attack_range: float = 1.55
@export var attack_damage: float = 12.0
@export var attack_interval: float = 1.2
@export var wind_up_time: float = 0.55      ## telegraphed, planted wind-up before a swing lands
@export var hearing_scale: float = 1.0
@export var wander_radius: float = 12.0
@export var corpse_time: float = 20.0
@export var piece_damage: float = 20.0      ## damage per swing against a player-built piece
@export var piece_interval: float = 1.0

## Replicated (spawn + continuous):
var state_id: int = State.IDLE:
	set(v):
		state_id = v
		_on_state_applied()
var health: float = 100.0
var runner: bool = false
## 0 walker, 1 runner, 2 bloater. Must be set before the zombie enters the tree.
var kind: int = KIND_WALKER
var variant_seed: int = 0:
	set(v):
		variant_seed = v
		if _built:
			_apply_variant()
## True while the zombie is planted and winding up a swing (replicated, so every peer
## shows the telegraph). Falling edge = the swing: plays the strike on every peer.
var winding: bool = false:
	set(v):
		if winding and not v and state_id != State.DEAD:
			_attack_anim = 0.6
		winding = v
## Bit mask of PART_* flags for body parts shot off. Server writes it; the setter plays the
## visuals/gib on every peer and reapplies the gameplay effects (reach, crawl).
var severed: int = 0:
	set(v):
		severed = v
		if _built:
			_apply_severed(true)
## Set by the spawner at creation (server only uses these).
var night_mult: float = 0.0

var _target: Player = null
var _last_known: Vector3 = Vector3.ZERO
var _lost_timer: float = 0.0
var _home: Vector3 = Vector3.ZERO
var _wander_target: Vector3 = Vector3.ZERO
var _investigate_pos: Vector3 = Vector3.ZERO
var _state_time: float = 0.0
var _state_limit: float = 4.0
var _think_timer: float = 0.0
var _avoid_timer: float = 0.0
var _avoid_angle: float = 0.0
var _attack_timer: float = 0.0
var _attack_cool: float = 0.0
var _piece_cool: float = 0.0
var _attack_wind: bool = false
var _stagger: float = 0.0
var _sep: Vector3 = Vector3.ZERO
var _jump_cool: float = 0.0
var _nav_timer: float = 0.0
var _use_nav: bool = false
var _dead_handled: bool = false
# dismemberment bookkeeping
var _part_dmg: Dictionary = {}          ## PART_* -> damage taken so far (server)
var _sev_applied: int = 0               ## bits whose visuals are already applied on this peer
var _base_range: float = -1.0
var _base_damage: float = -1.0
var _leg_speed: float = 1.0
var _crawling: bool = false
var _stumps: Array[Node] = []
var last_gib: RigidBody3D = null
static var _gibs: Array = []
static var _decals: Array = []
static var _blood_mat: StandardMaterial3D

# visuals / animation
var _built: bool = false
var _body: Node3D
var _head: Node3D
var _arms: Array[Node3D] = []
var _legs: Array[Node3D] = []
var _skel: Skeleton3D          ## Kenney walker rig (null for the procedural bodies)
var _bone_head: int = -1
var _bone_arm: Array[int] = []
var _bone_leg: Array[int] = []
var _mat_skin: StandardMaterial3D
var _mat_shirt: StandardMaterial3D
var _mat_pants: StandardMaterial3D
var _mat_blood: StandardMaterial3D
var _prev_health: float = 100.0
var _flinch: float = 0.0
var _flinch_side: float = 1.0
var _anim_phase: float = 0.0
var _anim_speed: float = 0.0
var _last_pos: Vector3 = Vector3.ZERO
var _attack_anim: float = 0.0
var _hit_flash: float = 0.0
var _wind_pose: float = 0.0
var _fall: float = 0.0

@onready var nav: NavigationAgent3D = $NavAgent


func _ready() -> void:
	add_to_group("zombies")
	collision_layer = 4
	collision_mask = MASK_WORLD
	if runner and kind == KIND_WALKER:
		kind = KIND_RUNNER   # older callers only set `runner`
	_apply_kind()
	if variant_seed == 0:
		variant_seed = randi_range(1, 2147483000)
	health = max_health
	_prev_health = health
	_build_body()
	_apply_variant()
	_setup_sync()
	_home = global_position
	_last_pos = global_position
	_think_timer = randf() * 0.2
	_avoid_timer = randf() * 0.1
	_state_limit = randf_range(2.0, 6.0)
	nav.path_desired_distance = 1.0
	nav.target_desired_distance = 1.2
	nav.avoidance_enabled = false


func _setup_sync() -> void:
	var cfg := SceneReplicationConfig.new()
	for prop in ["position", "rotation", "state_id", "health", "runner", "kind", "variant_seed", "winding", "severed"]:
		var path := NodePath(".:" + prop)
		cfg.add_property(path)
		cfg.property_set_spawn(path, true)
		cfg.property_set_replication_mode(path, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	var sync := MultiplayerSynchronizer.new()
	sync.name = "ZombieSync"
	sync.replication_config = cfg
	sync.replication_interval = 0.05
	add_child(sync)


# ================================================================== damage

func request_damage(amount: float, headshot: bool = false, attacker: int = 0) -> void:
	if multiplayer.is_server():
		_take_damage(amount, headshot, attacker)
	else:
		rpc_id(1, "_rpc_damage", amount, headshot, attacker)


## Like request_damage, but also carries where the bullet hit (world position, picks the body
## part for dismemberment) and its direction (blood spray + knockback). Bullets call this.
func request_hit(amount: float, headshot: bool = false, attacker: int = 0, hit_pos: Vector3 = Vector3.ZERO, shot_dir: Vector3 = Vector3.ZERO) -> void:
	if multiplayer.is_server():
		_take_damage(amount, headshot, attacker, hit_pos, shot_dir)
	else:
		rpc_id(1, "_rpc_hit", amount, headshot, attacker, hit_pos, shot_dir)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_damage(amount: float, headshot: bool, attacker: int) -> void:
	if multiplayer.is_server():
		_take_damage(amount, headshot, attacker)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_hit(amount: float, headshot: bool, attacker: int, hit_pos: Vector3, shot_dir: Vector3) -> void:
	if multiplayer.is_server():
		_take_damage(amount, headshot, attacker, hit_pos, shot_dir)


func is_head_hit(world_pos: Vector3) -> bool:
	return world_pos.y > global_position.y + _head_y() * (CRAWL_HEIGHT if _crawling else 1.0)


## Server only. `hit_pos` ZERO = unknown (region falls back to the headshot flag).
func _take_damage(amount: float, headshot: bool, attacker: int, hit_pos: Vector3 = Vector3.ZERO, shot_dir: Vector3 = Vector3.ZERO) -> void:
	if state_id == State.DEAD or amount <= 0.0:
		return
	health -= amount
	_hit_flash = 0.15
	var dir := _push_dir(attacker, shot_dir)
	# dismemberment: the part under the bullet takes the damage and comes off past its threshold
	var part := _part_at(hit_pos, headshot)
	var fatal := health <= 0.0
	var off := _damage_part(part, amount, fatal)
	if off != 0:
		_gib_dir = dir
		severed |= off
		if off & PART_HEAD:
			health = 0.0   # no head, no zombie
			fatal = true
	_hit_fx_all(hit_pos, dir, amount, headshot or (off & PART_HEAD) != 0)
	if fatal:
		health = 0.0
		_die()
		return
	var push := _knock(dir, amount, headshot)
	_stagger = maxf((0.35 if headshot else 0.2) * (0.4 if kind == KIND_BLOATER else 1.0), push / 14.0)
	# a hit interrupts a swing in progress
	if winding:
		winding = false
		_attack_wind = false
		_attack_cool = maxf(_attack_cool, 0.3)
	# getting shot draws the zombie to the shooter
	for n in get_tree().get_nodes_in_group("players"):
		var p := n as Player
		if p != null and p.peer_id == attacker and not p.is_dead:
			alert_to(p)
			break


## Horizontal direction the hit shoves the zombie: along the shot when known, else away
## from the shooter, else straight back.
func _push_dir(attacker: int, shot_dir: Vector3) -> Vector3:
	var d := shot_dir
	d.y = 0.0
	if d.length_squared() < 0.01:
		d = Vector3.ZERO
		for n in get_tree().get_nodes_in_group("players"):
			var p := n as Player
			if p != null and p.peer_id == attacker:
				d = global_position - p.global_position
				d.y = 0.0
				break
	if d.length_squared() < 0.01:
		d = global_transform.basis.z   # zombies face -Z: shoved backwards
		d.y = 0.0
	return d.normalized()


## Server only: shove the zombie along `dir`. Scales with damage, harder on a headshot,
## bloaters barely move. Returns the horizontal speed added.
func _knock(dir: Vector3, amount: float, headshot: bool) -> float:
	var push := clampf(4.5 + amount * 0.08, 4.5, 10.0)
	if headshot:
		push *= 1.4
	if kind == KIND_BLOATER:
		push *= 0.35
	velocity.x += dir.x * push
	velocity.z += dir.z * push
	velocity.y = maxf(velocity.y, 1.6)   # small hop so the shove reads
	return push


func _die() -> void:
	_set_state(State.DEAD)
	velocity = Vector3.ZERO
	died.emit(self)
	get_tree().create_timer(corpse_time).timeout.connect(func() -> void:
		if is_instance_valid(self):
			queue_free())


# ================================================================== dismemberment & gore

var _crawl_t: float = 0.0
var _gib_dir: Vector3 = Vector3.BACK


## Body-region lines in zombie-local metres. Subclasses with another build override these.
func _head_y() -> float:
	return WALKER_HEAD_LINE if _skel != null else 1.48


func _leg_y() -> float:
	return 0.65     ## below this a hit is a leg


func _arm_x() -> float:
	return 0.4 if kind == KIND_BLOATER else 0.24   ## beyond this sideways offset a torso-height hit is an arm


func _stump_color() -> Color:
	return Color(0.4, 0.04, 0.04)


func _gib_color(part: int) -> Color:
	if (part & (PART_LEG_L | PART_LEG_R)) != 0:
		return Color(0.25, 0.28, 0.35)
	return Color(0.6, 0.66, 0.52)


func _supports_crawl() -> bool:
	return true


## Which PART_* a bullet at `hit_pos` struck (0 = torso). ZERO position = unknown: the
## headshot flag alone decides.
func _part_at(hit_pos: Vector3, headshot: bool) -> int:
	if hit_pos == Vector3.ZERO:
		return PART_HEAD if headshot else 0
	if headshot or is_head_hit(hit_pos):
		return PART_HEAD
	var l := to_local(hit_pos)
	var k := CRAWL_HEIGHT if _crawling else 1.0
	if l.y < _leg_y() * k:
		return PART_LEG_L if l.x < 0.0 else PART_LEG_R
	if absf(l.x) > _arm_x():
		return PART_ARM_L if l.x < 0.0 else PART_ARM_R
	return 0


## Server: adds `amount` to the part's damage tally. Returns the part when it comes off
## (tally past its threshold, or the hit is fatal), else 0.
func _damage_part(part: int, amount: float, fatal: bool) -> int:
	if part == 0 or (severed & part) != 0:
		return 0
	var total := float(_part_dmg.get(part, 0.0)) + amount
	_part_dmg[part] = total
	var frac := LEG_SEVER_FRAC
	if part == PART_HEAD:
		frac = HEAD_SEVER_FRAC
	elif part == PART_ARM_L or part == PART_ARM_R:
		frac = ARM_SEVER_FRAC
	if fatal or total >= max_health * frac:
		return part
	return 0


func _part_list() -> Array:
	return [PART_HEAD, PART_ARM_L, PART_ARM_R, PART_LEG_L, PART_LEG_R]


## Runs on every peer when `severed` changes (gibs = a live change, not a late-join catch-up).
func _apply_severed(gibs: bool) -> void:
	var diff := severed & ~_sev_applied
	_sev_applied = severed
	for part in _part_list():
		if (diff & part) != 0:
			_hide_part(part)
			_add_stump(part)
			if gibs:
				_spawn_gib(part)
	_recompute_limb_effects()
	_apply_sever_pose()


func _hide_part(part: int) -> void:
	var n: Node3D = null
	match part:
		PART_HEAD:
			n = _head
		PART_ARM_L:
			n = _arms[0] if _arms.size() > 0 else null
		PART_ARM_R:
			n = _arms[1] if _arms.size() > 1 else null
		PART_LEG_L:
			n = _legs[0] if _legs.size() > 0 else null
		PART_LEG_R:
			n = _legs[1] if _legs.size() > 1 else null
	if n != null:
		n.visible = false


## Zombie-local position of the joint a part comes off at.
func _joint_local(part: int) -> Vector3:
	var sx := 1.0
	if (part & (PART_ARM_L | PART_LEG_L)) != 0:
		sx = -1.0
	if part == PART_HEAD:
		return Vector3(0.0, _head_y() - 0.02, 0.0)
	if part == PART_ARM_L or part == PART_ARM_R:
		return Vector3(sx * _arm_x() * 1.15, _head_y() - 0.2, 0.0)
	return Vector3(sx * 0.13, _leg_y() + 0.1, 0.0)


func _add_stump(part: int) -> void:
	if _body == null:
		return
	var sm := SphereMesh.new()
	sm.radius = 0.11 if part == PART_HEAD else 0.07
	sm.height = sm.radius * 2.0
	sm.radial_segments = 8
	sm.rings = 4
	var mi := _mesh(_body, sm, _joint_local(part), _material(_stump_color(), 0.6))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_stumps.append(mi)


## Skinned bodies cannot hide a limb by visibility: scale its bone to nothing instead
## (reapplied every frame, animation clips rewrite bone poses).
func _apply_sever_pose() -> void:
	if _skel == null:
		return
	var tiny := Vector3(0.001, 0.001, 0.001)
	if (severed & PART_HEAD) != 0 and _bone_head >= 0:
		_skel.set_bone_pose_scale(_bone_head, tiny)
	for i in range(mini(_bone_arm.size(), 2)):
		if (severed & (PART_ARM_L if i == 0 else PART_ARM_R)) != 0 and _bone_arm[i] >= 0:
			_skel.set_bone_pose_scale(_bone_arm[i], tiny)
	for i in range(mini(_bone_leg.size(), 2)):
		if (severed & (PART_LEG_L if i == 0 else PART_LEG_R)) != 0 and _bone_leg[i] >= 0:
			_skel.set_bone_pose_scale(_bone_leg[i], tiny)


static func _bits(v: int, a: int, b: int) -> int:
	return (1 if (v & a) != 0 else 0) + (1 if (v & b) != 0 else 0)


## Gameplay effects of missing limbs: arms cut reach and damage, legs cut speed, two
## legs gone = crawling (low, slow, smaller hitbox).
func _recompute_limb_effects() -> void:
	if _base_range < 0.0:
		_base_range = attack_range
		_base_damage = attack_damage
	var arms := _bits(severed, PART_ARM_L, PART_ARM_R)
	var legs := _bits(severed, PART_LEG_L, PART_LEG_R)
	attack_range = _base_range * (1.0 - ARM_REACH_LOSS * arms)
	attack_damage = _base_damage * (1.0 - ARM_DAMAGE_LOSS * arms)
	_leg_speed = float(LEG_SPEED[legs])
	var crawl := legs >= 2 and _supports_crawl()
	if crawl and not _crawling:
		_crawling = true
		_apply_crawl_shape()


func _apply_crawl_shape() -> void:
	var cs := get_node_or_null("Collision") as CollisionShape3D
	if cs != null and cs.shape is CapsuleShape3D:
		var shape := (cs.shape as CapsuleShape3D).duplicate() as CapsuleShape3D   # never edit the shared scene shape
		shape.height = maxf(shape.radius * 2.0 + 0.02, shape.height * CRAWL_HEIGHT)
		cs.shape = shape
		cs.position.y = shape.height * 0.5
	var hc := get_node_or_null("HeadCollision") as CollisionShape3D
	if hc != null:
		hc.position.y *= CRAWL_HEIGHT


func _fx_root() -> Node:
	if not is_inside_tree():
		return null
	var cur := get_tree().current_scene
	return cur if cur != null else get_tree().root


## A severed part tumbling away: a real physics body that never collides with actors.
func _spawn_gib(part: int) -> RigidBody3D:
	var scene := _fx_root()
	if scene == null:
		return null
	var rb := RigidBody3D.new()
	rb.collision_layer = 0
	rb.collision_mask = MASK_WORLD
	rb.mass = 2.0
	var mi := MeshInstance3D.new()
	var cshape := CollisionShape3D.new()
	if part == PART_HEAD:
		var s := SphereShape3D.new()
		s.radius = 0.17
		cshape.shape = s
		mi.mesh = _sphere_mesh(0.17, 10, 6)
	else:
		var r := 0.06 if (part == PART_ARM_L or part == PART_ARM_R) else 0.08
		var h := 0.6 if r < 0.07 else 0.8
		var c := CapsuleShape3D.new()
		c.radius = r
		c.height = h
		cshape.shape = c
		mi.mesh = _capsule_mesh(r, h, 8, 3)
	mi.material_override = _material(_gib_color(part))
	rb.add_child(mi)
	rb.add_child(cshape)
	scene.add_child(rb)
	rb.global_position = global_transform * _joint_local(part)
	var away := _gib_dir
	if away.length_squared() < 0.01:
		away = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized()
	rb.linear_velocity = away * randf_range(2.5, 4.5) + Vector3(randf_range(-1.0, 1.0), randf_range(2.5, 4.5), randf_range(-1.0, 1.0))
	rb.angular_velocity = Vector3(randf_range(-9.0, 9.0), randf_range(-9.0, 9.0), randf_range(-9.0, 9.0))
	_blood_burst(rb.global_position, away, 40, 1.3)
	while _gibs.size() >= MAX_GIBS:
		var old = _gibs.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	_gibs.append(rb)
	get_tree().create_timer(12.0).timeout.connect(func() -> void:
		if is_instance_valid(rb):
			rb.queue_free())
	last_gib = rb
	return rb


## Particles for one hit: more with damage, much more on a headshot.
static func blood_amount(amount: float, headshot: bool) -> int:
	var n := 10 + int(amount * 0.6)
	if headshot:
		n = int(n * 1.8)
	return clampi(n, 10, 90)


## Server: shows the hit on this peer and tells the rest.
func _hit_fx_all(hit_pos: Vector3, dir: Vector3, amount: float, headshot: bool) -> void:
	var p := hit_pos if hit_pos != Vector3.ZERO else global_position + Vector3.UP * 1.2
	_hit_fx(p, dir, amount, headshot)
	if multiplayer.has_multiplayer_peer() and multiplayer.get_peers().size() > 0:
		rpc("_rpc_hit_fx", p, dir, amount, headshot)


@rpc("authority", "call_remote", "unreliable")
func _rpc_hit_fx(pos: Vector3, dir: Vector3, amount: float, headshot: bool) -> void:
	_hit_fx(pos, dir, amount, headshot)


func _hit_fx(pos: Vector3, dir: Vector3, amount: float, headshot: bool) -> CPUParticles3D:
	_gib_dir = dir
	var ps := _blood_burst(pos, dir, blood_amount(amount, headshot), 1.0 + (0.4 if headshot else 0.0))
	_floor_splat(pos, amount, headshot)
	return ps


static func _blood_material() -> StandardMaterial3D:
	if _blood_mat == null:
		_blood_mat = _material(Color(0.5, 0.02, 0.02), 0.4)
	return _blood_mat


func _blood_burst(pos: Vector3, dir: Vector3, n: int, speed: float = 1.0) -> CPUParticles3D:
	var scene := _fx_root()
	if scene == null:
		return null
	var ps := CPUParticles3D.new()
	ps.one_shot = true
	ps.amount = n
	ps.lifetime = 0.7
	ps.explosiveness = 1.0
	ps.direction = (dir + Vector3.UP * 0.35).normalized()
	ps.spread = 38.0
	ps.initial_velocity_min = 1.5 * speed
	ps.initial_velocity_max = (3.0 + n * 0.04) * speed
	ps.gravity = Vector3(0.0, -9.8, 0.0)
	var sm := SphereMesh.new()
	sm.radius = 0.03
	sm.height = 0.06
	sm.radial_segments = 4
	sm.rings = 2
	ps.mesh = sm
	ps.material_override = _blood_material()
	ps.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene.add_child(ps)
	ps.global_position = pos
	ps.emitting = true
	get_tree().create_timer(1.3).timeout.connect(func() -> void:
		if is_instance_valid(ps):
			ps.queue_free())
	return ps


## Flat blood puddles on the floor below the hit: more and bigger for harder hits.
func _floor_splat(pos: Vector3, amount: float, headshot: bool) -> void:
	var scene := _fx_root()
	if scene == null:
		return
	var q := PhysicsRayQueryParameters3D.create(pos, pos + Vector3.DOWN * 3.0, MASK_WORLD, [get_rid()])
	var res := get_world_3d().direct_space_state.intersect_ray(q)
	if res.is_empty():
		return
	var count := clampi(1 + int(amount / 40.0) + (2 if headshot else 0), 1, 4)
	for i in range(count):
		var cm := CylinderMesh.new()
		cm.top_radius = randf_range(0.08, 0.16) + minf(amount, 100.0) * 0.002
		cm.bottom_radius = cm.top_radius
		cm.height = 0.004
		cm.radial_segments = 8
		cm.rings = 1
		var mi := MeshInstance3D.new()
		mi.mesh = cm
		mi.material_override = _blood_material()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		scene.add_child(mi)
		var fp: Vector3 = res["position"]
		mi.global_position = fp + Vector3(randf_range(-0.5, 0.5), 0.012 + 0.002 * i, randf_range(-0.5, 0.5))
		while _decals.size() >= MAX_DECALS:
			var old = _decals.pop_front()
			if is_instance_valid(old):
				old.queue_free()
		_decals.append(mi)


# ================================================================== senses / alerts

func hear_noise(pos: Vector3, radius: float) -> void:
	if not multiplayer.is_server() or state_id == State.DEAD:
		return
	var d := global_position.distance_to(pos)
	var eff := radius * hearing_scale * (1.0 + 0.3 * night_mult)
	if d > eff:
		return
	if state_id == State.CHASE or state_id == State.ATTACK:
		return
	# loud + close: go straight at it; otherwise investigate the noise spot
	var jitter := Vector3(randf_range(-3.0, 3.0), 0.0, randf_range(-3.0, 3.0)) * clampf(d / 40.0, 0.2, 1.5)
	if state_id != State.INVESTIGATE or d < global_position.distance_to(_investigate_pos):
		_investigate_pos = pos + jitter
	_set_state(State.INVESTIGATE)


func alert_to(p: Player) -> void:
	if not multiplayer.is_server() or state_id == State.DEAD or p == null:
		return
	_target = p
	_last_known = p.global_position
	_lost_timer = 0.0
	if state_id != State.CHASE and state_id != State.ATTACK:
		_set_state(State.CHASE)
		_alert_neighbors(p)


func _alert_neighbors(p: Player) -> void:
	for n in get_tree().get_nodes_in_group("zombies"):
		var z := n as Zombie
		if z == null or z == self or z.state_id == State.DEAD:
			continue
		if z.state_id == State.CHASE or z.state_id == State.ATTACK:
			continue
		if z.global_position.distance_to(global_position) < 14.0:
			z._target = p
			z._last_known = p.global_position
			z._lost_timer = 0.0
			z._set_state(State.CHASE)


func _vis_mult(p: Player) -> float:
	var m := 1.0 + 0.25 * night_mult
	if p.is_sprinting:
		m *= 1.35
	elif p.crouching:
		m *= 0.55
	return m


func _can_see(p: Player, d: float) -> bool:
	if d > sight_range * _vis_mult(p):
		return false
	var to := p.global_position - global_position
	to.y = 0.0
	if d > 3.0:
		var fwd := -global_transform.basis.z
		fwd.y = 0.0
		if fwd.normalized().dot(to.normalized()) < cos(deg_to_rad(sight_fov_deg * 0.5)):
			return false
	var from := global_position + Vector3.UP * 1.6
	var q := PhysicsRayQueryParameters3D.create(from, p.global_position + Vector3.UP * 1.4, MASK_WORLD, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _perceive() -> void:
	var best: Player = null
	var best_d := INF
	for n in get_tree().get_nodes_in_group("players"):
		var p := n as Player
		if p == null or p.is_dead:
			continue
		var d := global_position.distance_to(p.global_position)
		if d < best_d and _can_see(p, d):
			best = p
			best_d = d
	if best != null:
		_target = best
		_last_known = best.global_position
		_lost_timer = 0.0
		if state_id != State.CHASE and state_id != State.ATTACK:
			_set_state(State.CHASE)
			_alert_neighbors(best)
	elif state_id == State.CHASE or state_id == State.ATTACK:
		_lost_timer += 0.2
		if _lost_timer > 6.0:
			_target = null
			_investigate_pos = _last_known
			_set_state(State.INVESTIGATE)


func _separation() -> void:
	_sep = Vector3.ZERO
	for n in get_tree().get_nodes_in_group("zombies"):
		var z := n as Zombie
		if z == null or z == self or z.state_id == State.DEAD:
			continue
		var off := global_position - z.global_position
		off.y = 0.0
		var d := off.length()
		if d < 1.0 and d > 0.001:
			_sep += off / d * (1.0 - d)


# ================================================================== state machine

func _set_state(s: int) -> void:
	state_id = s
	_state_time = 0.0
	match s:
		State.IDLE:
			_state_limit = randf_range(3.0, 8.0)
		State.WANDER:
			var ang := randf() * TAU
			var r := randf_range(3.0, wander_radius)
			_wander_target = _home + Vector3(cos(ang) * r, 0.0, sin(ang) * r)
			_state_limit = 12.0
		State.INVESTIGATE:
			_state_limit = 16.0
		State.ATTACK:
			_attack_wind = false
			_attack_timer = 0.0
	if s != State.ATTACK:
		winding = false


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	if state_id == State.DEAD:
		if not is_on_floor():
			velocity.y -= GRAVITY * delta
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = maxf(velocity.y, -1.0)
	_state_time += delta
	_jump_cool = maxf(0.0, _jump_cool - delta)
	_attack_cool = maxf(0.0, _attack_cool - delta)
	_think_timer -= delta
	if _think_timer <= 0.0:
		_think_timer = 0.2
		_perceive()
		_separation()
	_nav_timer -= delta
	if _nav_timer <= 0.0:
		_nav_timer = 2.0
		_use_nav = NavigationServer3D.map_get_regions(nav.get_navigation_map()).size() > 0
	if _stagger > 0.0:
		_stagger -= delta
		velocity.x = move_toward(velocity.x, 0.0, 10.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 10.0 * delta)
		move_and_slide()
		return
	match state_id:
		State.IDLE:
			_do_idle(delta)
		State.WANDER:
			_do_wander(delta)
		State.INVESTIGATE:
			_do_investigate(delta)
		State.CHASE:
			_do_chase(delta)
		State.ATTACK:
			_do_attack(delta)
	move_and_slide()


func _do_idle(delta: float) -> void:
	_halt(delta)
	if _state_time > _state_limit:
		_set_state(State.WANDER)


func _do_wander(delta: float) -> void:
	var to := _wander_target - global_position
	to.y = 0.0
	if to.length() < 1.2 or _state_time > _state_limit:
		_set_state(State.IDLE)
		return
	_steer(_wander_target, walk_speed * _speed_mult(), delta)


func _do_investigate(delta: float) -> void:
	var to := _investigate_pos - global_position
	to.y = 0.0
	if to.length() < 1.6:
		_halt(delta)
		if _state_time > 3.0 + _state_limit * 0.0:
			_home = global_position
			_set_state(State.WANDER)
		return
	if _state_time > _state_limit:
		_set_state(State.WANDER)
		return
	_steer(_investigate_pos, investigate_speed * _speed_mult(), delta)


func _do_chase(delta: float) -> void:
	if _target == null or not is_instance_valid(_target) or _target.is_dead:
		_target = null
		_investigate_pos = _last_known
		_set_state(State.INVESTIGATE)
		return
	var tp := _target.global_position
	var flat := tp - global_position
	flat.y = 0.0
	if flat.length() < attack_range * 0.9 and absf(tp.y - global_position.y) < 1.6:
		_set_state(State.ATTACK)
		return
	if _attack_blocking_piece(tp, delta):
		return
	var spd := (runner_speed if runner else chase_speed) * _speed_mult()
	_steer(tp, spd, delta)


func _do_attack(delta: float) -> void:
	if _target == null or not is_instance_valid(_target) or _target.is_dead:
		_target = null
		_set_state(State.INVESTIGATE)
		_investigate_pos = _last_known
		return
	var to := _target.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	_face(to, 10.0, delta)
	velocity.x = move_toward(velocity.x, 0.0, 30.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 30.0 * delta)
	if _attack_wind:
		_attack_timer -= delta
		if _attack_timer <= 0.0:
			_attack_wind = false
			winding = false
			_attack_cool = attack_interval
			if dist < attack_range * 1.3:
				_target.request_damage(attack_damage * (1.0 + 0.3 * night_mult), false, 0)
		return
	if dist > attack_range * 1.3:
		if _attack_cool <= 0.0:
			_set_state(State.CHASE)
		return
	if _attack_cool <= 0.0:
		_attack_wind = true
		_attack_timer = wind_up_time
		winding = true


func _speed_mult() -> float:
	return (1.0 + 0.2 * night_mult) * _leg_speed


## While chasing: if a player-built piece (wall, barricade, window, closed door) is in
## the way, stop and chew through it via Building.damage_piece (server only).
## Returns true when the zombie is busy attacking a piece this frame.
func _attack_blocking_piece(tp: Vector3, delta: float) -> bool:
	_piece_cool = maxf(0.0, _piece_cool - delta)
	var building := get_node_or_null("/root/Building")
	if building == null:
		return false
	var piece_id := _find_blocking_piece(building, tp)
	if piece_id <= 0:
		return false
	var to := tp - global_position
	to.y = 0.0
	_face(to, 10.0, delta)
	_halt(delta)
	if _piece_cool <= 0.0:
		_piece_cool = piece_interval
		_attack_anim = 0.6
		building.call("damage_piece", piece_id, piece_damage * (1.0 + 0.3 * night_mult))
	return true


func _find_blocking_piece(building: Node, tp: Vector3) -> int:
	var pieces: Dictionary = building.get("pieces")
	# 1) what the last move bumped into
	for i in range(get_slide_collision_count()):
		var c := get_slide_collision(i)
		if absf(c.get_normal().y) > 0.5:
			continue
		var id := _piece_id_of(c.get_collider(), pieces)
		if id > 0:
			return id
	# 2) a piece directly between the zombie and its target
	var flat := tp - global_position
	flat.y = 0.0
	if flat.length_squared() < 0.01:
		return 0
	var from := global_position + Vector3.UP * 1.0
	var to := from + flat.normalized() * (attack_range * 1.1 + 0.3)
	var q := PhysicsRayQueryParameters3D.create(from, to, MASK_WORLD, [get_rid()])
	var res := get_world_3d().direct_space_state.intersect_ray(q)
	if res.is_empty():
		return 0
	return _piece_id_of(res["collider"], pieces)


## Walks up from a collider to the node carrying the "piece_id" meta. 0 = not a
## player-built piece (or an open door, which can be walked through).
func _piece_id_of(col: Object, pieces: Dictionary) -> int:
	var node := col as Node
	for _i in range(4):
		if node == null:
			return 0
		if node.has_meta("piece_id"):
			var id := int(node.get_meta("piece_id"))
			var info: Dictionary = pieces.get(id, {})
			if info.is_empty() or bool(info.get("open", false)):
				return 0
			return id
		node = node.get_parent()
	return 0


# ================================================================== movement helpers

func _halt(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 12.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 12.0 * delta)


func _face(dir: Vector3, turn: float, delta: float) -> void:
	if dir.length_squared() < 0.0001:
		return
	var yaw := atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, yaw, clampf(turn * delta, 0.0, 1.0))


func _steer(target_pos: Vector3, speed: float, delta: float) -> void:
	var aim := target_pos
	if _use_nav:
		nav.target_position = target_pos
		if not nav.is_navigation_finished():
			aim = nav.get_next_path_position()
	var dir := aim - global_position
	dir.y = 0.0
	if dir.length() < 0.05:
		_halt(delta)
		return
	dir = dir.normalized()
	_avoid_timer -= delta
	if _avoid_timer <= 0.0:
		_avoid_timer = 0.12
		_avoid_angle = _pick_clear_angle(dir)
	dir = dir.rotated(Vector3.UP, _avoid_angle)
	dir = (dir + _sep * 0.8).normalized()
	var accel := 14.0
	velocity.x = move_toward(velocity.x, dir.x * speed, accel * delta)
	velocity.z = move_toward(velocity.z, dir.z * speed, accel * delta)
	_face(dir, 7.0 if state_id != State.CHASE else 10.0, delta)
	if is_on_wall() and is_on_floor() and _jump_cool <= 0.0 and (state_id == State.CHASE or state_id == State.INVESTIGATE):
		velocity.y = 5.0   # clamber low fences / curbs
		_jump_cool = 1.0


## Whisker probe: returns the smallest turn (radians) that has a clear path ahead.
func _pick_clear_angle(dir: Vector3) -> float:
	var space := get_world_3d().direct_space_state
	var base := global_position + Vector3.UP * 0.5
	var angles := [0.0, 0.6, -0.6, 1.2, -1.2, 1.9, -1.9]
	if _avoid_angle < 0.0:
		angles = [0.0, -0.6, 0.6, -1.2, 1.2, -1.9, 1.9]
	for a in angles:
		var d := dir.rotated(Vector3.UP, a as float)
		var q := PhysicsRayQueryParameters3D.create(base, base + d * 1.7, MASK_WORLD, [get_rid()])
		if space.intersect_ray(q).is_empty():
			return a as float
	return 2.6


# ================================================================== visuals

func _process(delta: float) -> void:
	if not _built:
		return
	var moved := global_position - _last_pos
	moved.y = 0.0
	_last_pos = global_position
	_anim_speed = lerpf(_anim_speed, moved.length() / maxf(delta, 0.0001), clampf(delta * 8.0, 0.0, 1.0))
	_anim_phase += delta * (2.0 + _anim_speed * 1.6)
	_attack_anim = maxf(0.0, _attack_anim - delta)
	_hit_flash = maxf(0.0, _hit_flash - delta)
	_crawl_t = move_toward(_crawl_t, 1.0 if _crawling else 0.0, delta * 2.5)
	if _sev_applied != severed:
		_apply_severed(false)   # late joiner: parts already gone when this zombie spawned here
	_wind_pose = move_toward(_wind_pose, 1.0 if winding else 0.0, delta * (5.0 if winding else 16.0))
	# a drop in (replicated) health is a hit on every peer: play the flinch
	if health < _prev_health - 0.01 and state_id != State.DEAD:
		_flinch = FLINCH_TIME
		_flinch_side = 1.0 if (variant_seed + int(_prev_health)) % 2 == 0 else -1.0
	_prev_health = health
	_flinch = maxf(0.0, _flinch - delta)
	var dead := state_id == State.DEAD
	_fall = move_toward(_fall, 1.0 if dead else 0.0, delta / (DEATH_TIME * (1.3 if kind == KIND_BLOATER else 1.0)))
	if dead:
		_death_pose()
		_sync_rig()
		return
	_body.rotation.x = 0.0
	_body.position.y = 0.0
	var swing := sin(_anim_phase * 2.0) * clampf(_anim_speed / 2.5, 0.15, 1.0)
	# wind-up: planted feet, no step cycle, arms cocked overhead, body leaning back
	swing *= 1.0 - _wind_pose
	if _legs.size() == 2:
		_legs[0].rotation.x = swing * 0.7
		_legs[1].rotation.x = -swing * 0.7
	var reach := state_id == State.CHASE or state_id == State.ATTACK
	# Zombie faces -Z; a +X rotation swings a hanging arm toward -Z (forward).
	var arm_base := 1.35 if reach else 0.25
	if _arms.size() == 2:
		var punch := 0.0
		if _attack_anim > 0.0:
			punch = sin((0.6 - _attack_anim) / 0.6 * PI) * 0.9
		_arms[0].rotation.x = arm_base - swing * 0.2 + punch
		_arms[1].rotation.x = arm_base + swing * 0.2 + punch
		_arms[0].rotation.x = lerpf(_arms[0].rotation.x, 2.75, _wind_pose)
		_arms[1].rotation.x = lerpf(_arms[1].rotation.x, 2.75, _wind_pose)
		_arms[0].rotation.z = 0.1 + sin(_anim_phase) * 0.05
		_arms[1].rotation.z = -0.1 - sin(_anim_phase) * 0.05
	var lurch := 0.12 if reach else 0.05
	_body.rotation.x += lurch + absf(swing) * 0.05
	_body.rotation.x -= 1.0 * _crawl_t   # legless: pitched onto the arms, dragging forward
	_body.rotation.z = sin(_anim_phase) * 0.04
	_body.rotation.x -= 0.4 * _wind_pose
	_head.rotation.z = sin(_anim_phase * 0.7) * 0.12
	_head.rotation.x = (0.1 if reach else 0.25) - 0.35 * _wind_pose
	if _flinch > 0.0:
		_apply_flinch()
	_sync_rig()
	# hit flash tint
	if _mat_skin:
		_mat_skin.emission_enabled = _hit_flash > 0.0
		_mat_skin.emission = Color(0.8, 0.1, 0.1)


func _on_state_applied() -> void:
	if state_id == State.DEAD and not _dead_handled:
		_dead_handled = true
		# bullets and bodies pass through corpses on every peer
		collision_layer = 0
		collision_mask = MASK_WORLD


func _build_body() -> void:
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)
	_mat_skin = _material(Color(0.6, 0.66, 0.52))
	_mat_shirt = _material(Color(0.4, 0.3, 0.3))
	_mat_pants = _material(Color(0.25, 0.28, 0.35))
	_mat_blood = _material(Color(0.35, 0.03, 0.03), 0.6)
	match kind:
		KIND_RUNNER:
			_build_runner()
		KIND_BLOATER:
			_build_bloater()
		_:
			_build_walker()
	_built = true


## Shared head: faceted skull, neck, jaw, eyes, ears, teeth and hair tufts.
func _build_head(y: float, radius: float, eye_color: Color, z_off: float = 0.0) -> void:
	_head = Node3D.new()
	_head.position = Vector3(0, y, z_off)
	_body.add_child(_head)
	_mesh(_head, _sphere_mesh(radius, 16, 9, 1.05), Vector3(0, radius * 0.8, 0), _mat_skin)
	_mesh(_head, _capsule_mesh(0.055, 0.2, 8, 3), Vector3(0, -0.04, 0), _mat_skin)             # neck
	_mesh(_head, _box_mesh(Vector3(radius * 0.7, 0.045, radius * 0.5)), Vector3(0, 0.0, -radius * 0.6), _mat_skin)   # jaw
	var eye := _material(eye_color)
	eye.emission_enabled = true
	eye.emission = eye_color
	eye.emission_energy_multiplier = 1.5
	for side in [-1.0, 1.0]:
		_mesh(_head, _sphere_mesh(0.02, 6, 3), Vector3(radius * 0.37 * side, radius * 1.0, -radius * 0.9), eye)
		_mesh(_head, _box_mesh(Vector3(0.03, 0.05, 0.02)), Vector3(radius * 0.95 * side, radius * 0.8, 0.0), _mat_skin)   # ear
	var teeth := _material(Color(0.8, 0.78, 0.6))
	for i in range(4):
		_mesh(_head, _box_mesh(Vector3(0.016, 0.02, 0.012)), Vector3((i - 1.5) * 0.026, radius * 0.2, -radius * 0.95), teeth)
	_mesh(_head, _box_mesh(Vector3(radius * 0.8, 0.04, 0.03)), Vector3(0, radius * 0.1, -radius * 0.9), _mat_blood)  # gore around the mouth
	var hair := _material(Color(0.12, 0.1, 0.08))
	for i in range(3):
		_mesh(_head, _box_mesh(Vector3(0.05, 0.03, 0.05)), Vector3((i - 1) * 0.07, radius * 1.65, 0.02 * i), hair)


## One arm: shoulder pivot, sleeve, forearm, hand with finger knuckles.
func _build_arm(_side: float, shoulder: Vector3, length: float, radius: float, seg: int) -> void:
	var arm := Node3D.new()
	arm.position = shoulder
	_body.add_child(arm)
	_mesh(arm, _capsule_mesh(radius, length, seg, 5), Vector3(0, -length * 0.45, 0), _mat_skin)
	_mesh(arm, _capsule_mesh(radius * 1.12, length * 0.45, seg, 4), Vector3(0, -length * 0.19, 0), _mat_shirt)
	_mesh(arm, _sphere_mesh(radius * 1.25, 8, 5), Vector3(0, -length * 0.95, 0), _mat_skin)             # hand
	for i in range(3):
		_mesh(arm, _box_mesh(Vector3(radius * 0.5, radius * 1.6, radius * 0.5)), Vector3((i - 1) * radius * 0.7, -length - radius * 0.9, -0.01), _mat_skin)  # fingers
	_arms.append(arm)


## One leg: hip pivot, thigh/shin capsule, knee, shoe.
func _build_leg(_side: float, hip: Vector3, length: float, radius: float, seg: int) -> void:
	var leg := Node3D.new()
	leg.position = hip
	_body.add_child(leg)
	_mesh(leg, _capsule_mesh(radius, length, seg, 5), Vector3(0, -length * 0.49, 0), _mat_pants)
	_mesh(leg, _sphere_mesh(radius * 1.1, 8, 4), Vector3(0, -length * 0.5, -0.01), _mat_pants)           # knee
	_mesh(leg, _box_mesh(Vector3(radius * 1.8, 0.07, radius * 3.2)), Vector3(0, -length * 0.99, -radius * 0.8), _material(Color(0.12, 0.1, 0.09)))   # shoe
	_legs.append(leg)


func _build_walker() -> void:
	if not _build_kenney_walker():
		_build_walker_procedural()


## Walker: the Kenney Mini Characters zombie, scaled up to near-human height. Its pose is
## driven from code through the same pivots the procedural bodies use (_head/_arms/_legs
## are empty Node3Ds whose rotations _sync_rig copies onto the bones). Returns false, so the
## procedural body is built instead, when the asset or its bones are missing.
func _build_kenney_walker() -> bool:
	if not ResourceLoader.exists(WALKER_MODEL):
		return false
	var ps := load(WALKER_MODEL) as PackedScene
	if ps == null:
		return false
	var model := ps.instantiate() as Node3D
	if model == null:
		return false
	var skel := model.find_child("Skeleton3D", true, false) as Skeleton3D
	if skel == null:
		model.free()
		return false
	var head_b := skel.find_bone("head")
	var arm_b: Array[int] = [skel.find_bone("arm-left"), skel.find_bone("arm-right")]
	var leg_b: Array[int] = [skel.find_bone("leg-left"), skel.find_bone("leg-right")]
	if head_b < 0 or arm_b.has(-1) or leg_b.has(-1):
		model.free()
		return false
	var ap := model.find_child("AnimationPlayer", true, false)
	if ap != null:
		ap.get_parent().remove_child(ap)   # poses come from code, not the stock clips
		ap.free()
	model.scale = Vector3(WALKER_SCALE * WALKER_WIDTH, WALKER_SCALE, WALKER_SCALE * WALKER_WIDTH)
	model.rotation.y = PI   # Kenney faces +Z; zombies face -Z
	_body.add_child(model)
	# one fixed look for every walker: the model's own texture. Private copy so the hit
	# flash does not light up every walker sharing the imported material.
	var tex_mat: StandardMaterial3D = null
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if tex_mat == null:
			var src := mi.mesh.surface_get_material(0) as StandardMaterial3D
			if src != null:
				tex_mat = src.duplicate() as StandardMaterial3D
		if tex_mat != null:
			mi.material_override = tex_mat
	if tex_mat != null:
		_mat_skin = tex_mat
	_head = Node3D.new()
	_body.add_child(_head)
	for _i in range(2):
		var arm := Node3D.new()
		_body.add_child(arm)
		_arms.append(arm)
		var leg := Node3D.new()
		_body.add_child(leg)
		_legs.append(leg)
	_skel = skel
	_bone_head = head_b
	_bone_arm = arm_b
	_bone_leg = leg_b
	var cs := get_node_or_null("Collision") as CollisionShape3D
	if cs != null and cs.shape is CapsuleShape3D:
		var shape := (cs.shape as CapsuleShape3D).duplicate() as CapsuleShape3D   # scene sub-resource is shared by every zombie
		shape.radius = WALKER_RADIUS
		shape.height = WALKER_HEIGHT
		cs.shape = shape
		cs.position.y = WALKER_HEIGHT * 0.5
	_add_walker_head_shape()
	return true


## Second collision shape over the walker's head, centred on the head mesh's rest-pose x/z
## bounds (zombie-local), so shots at the head edge that the capsule misses still hit.
func _add_walker_head_shape() -> void:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for n in _body.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var xf := Transform3D.IDENTITY
		var node: Node = mi
		while node != null and node != self:
			xf = (node as Node3D).transform * xf
			node = node.get_parent()
		var verts: PackedVector3Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for v in verts:
			var w := xf * v
			if w.y >= WALKER_HEAD_LINE:
				lo = Vector2(minf(lo.x, w.x), minf(lo.y, w.z))
				hi = Vector2(maxf(hi.x, w.x), maxf(hi.y, w.z))
	if lo.x > hi.x:
		return
	var sphere := SphereShape3D.new()
	sphere.radius = WALKER_HEAD_RADIUS
	var head_cs := CollisionShape3D.new()
	head_cs.name = "HeadCollision"
	head_cs.shape = sphere
	head_cs.position = Vector3((lo.x + hi.x) * 0.5, 1.33, (lo.y + hi.y) * 0.5)
	add_child(head_cs)


## Copies the pivot rotations onto the Kenney bones. The model is turned 180 deg about Y, so
## X/Z rotations flip sign; arms are aimed by direction (the rest pose is a T-pose along +-X).
## _arms[0]/_legs[0] sit on the zombie's -X side = the model's +X side = "arm-left"/"leg-left".
func _sync_rig() -> void:
	if _skel == null:
		return
	_skel.set_bone_pose_rotation(_bone_head, Quaternion.from_euler(Vector3(-_head.rotation.x, 0.0, -_head.rotation.z)))
	for i in range(2):
		_skel.set_bone_pose_rotation(_bone_leg[i], Quaternion(Vector3.RIGHT, -_legs[i].rotation.x))
		var r := _arms[i]
		var el := -PI * 0.5 + r.rotation.x   # 0 rad = hanging, +x swings up/forward
		var out := absf(r.rotation.z) * (1.0 if i == 0 else -1.0)
		var d := Vector3(out, sin(el), cos(el)).normalized()   # model +Z = zombie forward
		_skel.set_bone_pose_rotation(_bone_arm[i], Quaternion(Vector3.RIGHT if i == 0 else Vector3.LEFT, d))
	_apply_sever_pose()


func _build_walker_procedural() -> void:
	_mesh(_body, _box_mesh(Vector3(0.5, 0.62, 0.27)), Vector3(0, 1.17, 0), _mat_shirt)
	_mesh(_body, _box_mesh(Vector3(0.46, 0.22, 0.25)), Vector3(0, 0.78, 0), _mat_pants)
	_mesh(_body, _box_mesh(Vector3(0.47, 0.05, 0.26)), Vector3(0, 0.9, 0), _material(Color(0.12, 0.1, 0.08)))   # belt
	_mesh(_body, _box_mesh(Vector3(0.18, 0.2, 0.02)), Vector3(0.08, 1.2, -0.14), _mat_blood)
	for i in range(3):   # torn shirt hem
		_mesh(_body, _box_mesh(Vector3(0.13, 0.12 + 0.04 * i, 0.275)), Vector3((i - 1) * 0.16, 0.88 - 0.02 * i, 0), _mat_shirt)
	for side in [-1.0, 1.0]:
		_mesh(_body, _sphere_mesh(0.1, 8, 5), Vector3(0.3 * side, 1.43, 0), _mat_shirt)   # shoulder
	_mesh(_body, _box_mesh(Vector3(0.12, 0.28, 0.08)), Vector3(0, 1.2, 0.17), _mat_shirt)  # hunched spine
	_build_head(1.52, 0.15, Color(0.9, 0.7, 0.1))
	for side in [-1.0, 1.0]:
		_build_arm(side, Vector3(0.34 * side, 1.4, 0), 0.62, 0.07, 10)
		_build_leg(side, Vector3(0.13 * side, 0.8, 0), 0.82, 0.09, 10)


## Runner: lean, long limbs, exposed ribs, torn shorts, red eyes, head thrust forward.
func _build_runner() -> void:
	_mesh(_body, _box_mesh(Vector3(0.4, 0.6, 0.21)), Vector3(0, 1.19, 0), _mat_shirt)
	_mesh(_body, _box_mesh(Vector3(0.38, 0.2, 0.22)), Vector3(0, 0.8, 0), _mat_pants)
	for i in range(4):   # ribs through the torn shirt
		_mesh(_body, _box_mesh(Vector3(0.3, 0.02, 0.02)), Vector3(0, 1.3 - i * 0.07, -0.115), _mat_skin)
	_mesh(_body, _box_mesh(Vector3(0.22, 0.24, 0.02)), Vector3(0.06, 1.22, -0.11), _mat_blood)
	for i in range(5):   # spine ridge
		_mesh(_body, _box_mesh(Vector3(0.035, 0.05, 0.04)), Vector3(0, 1.0 + i * 0.1, 0.12), _mat_skin)
	for side in [-1.0, 1.0]:
		_mesh(_body, _sphere_mesh(0.08, 8, 5), Vector3(0.26 * side, 1.44, 0), _mat_skin)
	_build_head(1.5, 0.135, Color(0.95, 0.15, 0.1), -0.07)
	for side in [-1.0, 1.0]:
		_build_arm(side, Vector3(0.27 * side, 1.42, 0), 0.74, 0.055, 10)
		_build_leg(side, Vector3(0.11 * side, 0.82, 0), 0.84, 0.075, 10)


## Bloater: huge swollen belly with glowing boils, small head, thick limbs. 260 hp.
func _build_bloater() -> void:
	var boil := _material(Color(0.7, 0.75, 0.25), 0.5)
	boil.emission_enabled = true
	boil.emission = Color(0.55, 0.6, 0.1)
	boil.emission_energy_multiplier = 0.6
	_mesh(_body, _sphere_mesh(0.46, 16, 10, 0.95), Vector3(0, 1.0, -0.04), _mat_skin)           # belly
	_mesh(_body, _sphere_mesh(0.4, 14, 8, 0.7), Vector3(0, 1.28, 0.02), _mat_shirt)             # chest in a stretched shirt
	_mesh(_body, _box_mesh(Vector3(0.6, 0.2, 0.4)), Vector3(0, 0.74, 0), _mat_pants)
	for i in range(8):   # boils round the belly
		var a := float(i) / 8.0 * TAU
		_mesh(_body, _sphere_mesh(0.065, 6, 4), Vector3(cos(a) * 0.4, 0.95 + sin(a * 2.0) * 0.12, sin(a) * 0.4 - 0.04), boil)
	_mesh(_body, _box_mesh(Vector3(0.3, 0.3, 0.03)), Vector3(0.1, 1.05, -0.45), _mat_blood)
	for side in [-1.0, 1.0]:
		_mesh(_body, _sphere_mesh(0.15, 10, 6), Vector3(0.42 * side, 1.42, 0), _mat_shirt)
	_build_head(1.5, 0.12, Color(0.8, 0.9, 0.2), -0.12)
	for side in [-1.0, 1.0]:
		_build_arm(side, Vector3(0.5 * side, 1.4, 0), 0.6, 0.12, 10)
		_build_leg(side, Vector3(0.2 * side, 0.78, 0), 0.8, 0.14, 10)


func _apply_kind() -> void:
	match kind:
		KIND_RUNNER:
			max_health = 70.0
			attack_damage = 9.0
			attack_interval = 0.9
			wind_up_time = 0.35
			sight_range = 32.0
		KIND_BLOATER:
			max_health = 260.0
			walk_speed = 0.8
			investigate_speed = 1.6
			chase_speed = 2.3
			attack_damage = 22.0
			attack_interval = 1.6
			wind_up_time = 0.8
			attack_range = 1.95
			piece_damage = 40.0
			var cs := get_node_or_null("Collision") as CollisionShape3D
			if cs != null and cs.shape is CapsuleShape3D:
				var shape := (cs.shape as CapsuleShape3D).duplicate() as CapsuleShape3D
				shape.radius = 0.5
				cs.shape = shape
		_:
			kind = KIND_WALKER
	runner = kind == KIND_RUNNER


func _apply_variant() -> void:
	if _skel != null:
		return   # Kenney walkers all share one fixed look: model texture, scale 1
	var rng := RandomNumberGenerator.new()
	rng.seed = variant_seed
	_mat_skin.albedo_color = Color(0.55 + rng.randf() * 0.2, 0.62 + rng.randf() * 0.15, 0.5 + rng.randf() * 0.1)
	_mat_shirt.albedo_color = Color.from_hsv(rng.randf(), rng.randf_range(0.1, 0.5), rng.randf_range(0.25, 0.55))
	_mat_pants.albedo_color = Color.from_hsv(rng.randf_range(0.5, 0.7), rng.randf_range(0.1, 0.4), rng.randf_range(0.15, 0.4))
	var s := rng.randf_range(0.93, 1.08)
	match kind:
		KIND_RUNNER:
			_mat_skin.albedo_color = _mat_skin.albedo_color.lerp(Color(0.75, 0.72, 0.65), 0.5)
			_body.scale = Vector3(s * 0.95, s * 1.04, s * 0.95)
		KIND_BLOATER:
			_mat_skin.albedo_color = _mat_skin.albedo_color.lerp(Color(0.55, 0.62, 0.3), 0.5)
			_body.scale = Vector3(s, 1.0, s)   # height stays put so head-hit checks hold
		_:
			_body.scale = Vector3(s, s, s)


## Hit reaction: the torso snaps back, the head whips to one side, arms jerk
## down. Purely cosmetic: no dismemberment, no sound.
func _apply_flinch() -> void:
	var f := sin(_flinch / FLINCH_TIME * PI)
	var weight := 0.5 if kind == KIND_BLOATER else 1.0
	_body.rotation.x += 0.28 * f * weight
	_body.rotation.z += 0.12 * f * _flinch_side * weight
	_head.rotation.x -= 0.35 * f
	_head.rotation.z += 0.3 * f * _flinch_side
	for a in _arms:
		a.rotation.x += 0.5 * f


## Death: knees buckle first, then the body topples (forward or backward by
## variant) while the arms fall open and the head lolls. No sound.
func _death_pose() -> void:
	var k := _fall
	var buckle := clampf(k * 2.5, 0.0, 1.0)
	var topple := clampf((k - 0.25) / 0.75, 0.0, 1.0)
	topple = topple * topple * (3.0 - 2.0 * topple)
	var side := 1.0 if variant_seed % 2 == 0 else -1.0
	var dir := 1.0 if variant_seed % 3 == 0 else -1.0   # +1 falls backwards
	_body.rotation.x = dir * topple * PI * 0.5
	_body.rotation.z = side * topple * 0.2
	_body.position.y = -0.28 * buckle * (1.0 - topple) - 0.1 * topple
	if _legs.size() == 2:
		_legs[0].rotation.x = buckle * 0.7 * (1.0 - topple) + side * 0.25 * topple
		_legs[1].rotation.x = buckle * 0.7 * (1.0 - topple) - side * 0.25 * topple
	if _arms.size() == 2:
		for i in range(2):
			var s := 1.0 if i == 0 else -1.0
			_arms[i].rotation.x = lerpf(_arms[i].rotation.x, -0.2 + dir * 0.4 * topple, 0.3)
			_arms[i].rotation.z = s * (0.15 + 0.9 * topple)
	_head.rotation.x = lerpf(0.25, dir * 0.8, topple)
	_head.rotation.z = side * 0.45 * topple


static func _box_mesh(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


static func _capsule_mesh(radius: float, height: float, seg: int = 12, rings: int = 6) -> Mesh:
	var m := CapsuleMesh.new()
	m.radius = radius
	m.height = maxf(height, radius * 2.0 + 0.001)
	m.radial_segments = seg
	m.rings = rings
	return GunMesh.faceted(m)


## Faceted ellipsoid: `squash` scales its height relative to the diameter.
static func _sphere_mesh(radius: float, seg: int = 12, rings: int = 7, squash: float = 1.0) -> Mesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0 * squash
	m.radial_segments = seg
	m.rings = rings
	return GunMesh.faceted(m)


static func _material(color: Color, rough: float = 0.95) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	return m


static func _mesh(parent: Node3D, mesh: Mesh, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi
