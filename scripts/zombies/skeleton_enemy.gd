class_name SkeletonEnemy
extends Zombie
## KayKit skeleton enemies (CC0 free pack) built on the Zombie AI: same senses, state
## machine, wind-up attack, damage relay, head-hit test and MultiplayerSynchronizer
## replication, so bullets hit them and they die exactly like zombies. They stay in group
## "zombies" (noise, alerts, separation) and also join "skeletons".
##
## Four kinds (stored in `kind`, replicated): warrior (sword + large shield), minion (fast,
## weak, axe), rogue (fast, blade + small shield), mage (ranged: slow bolt, staff).
##
## Animation: shared Rig_Medium clips (Idle/Walking/Running/Hit/Death) driven manually from
## _process. The free animation pack has no melee-attack clip, so the right arm's wind-up and
## strike are posed procedurally (see _aim_right_arm). Missing clips fall back to a
## procedural leg swing / topple.
##
## Public API (on top of Zombie's): static kind_for_type(name), type_of_kind(kind),
## is_skeleton_kind(kind), `guard` (true = placed by a dungeon marker, never despawned).

const KIND_WARRIOR := 10
const KIND_MINION := 11
const KIND_ROGUE := 12
const KIND_MAGE := 13
const TYPE_NAMES: Array[String] = ["warrior", "minion", "rogue", "mage"]

const BASE := "res://assets/kaykit/skeletons/KayKit_Skeletons_1.1_FREE/"
const MODEL_PATH := BASE + "characters/gltf/Skeleton_%s.glb"
const ACCESSORY_PATH := BASE + "assets/gltf/Skeleton_%s.gltf"
const ANIM_FILES: Array[String] = [
	BASE + "Animations/gltf/Rig_Medium/Rig_Medium_General.glb",
	BASE + "Animations/gltf/Rig_Medium/Rig_Medium_MovementBasic.glb",
]
const LOOPING_CLIPS: Array[String] = ["Idle_A", "Idle_B", "Walking_A", "Walking_B", "Walking_C", "Running_A", "Running_B"]
const HEAD_LINE_FRAC := 1.34        ## head hit line = 1.34 * scale (skull starts at 1.31 * scale)
const BODY_RADIUS := 0.36
const HIT_TIME := 0.45
const RAISE_ANGLE := -2.4           ## right-arm pitch while winding up (0 = hanging, -pi/2 = forward, -2.4 = raised)
const SWING_END := -0.6
const BOLT_SPEED := 11.0

## Per kind: scale, "tall" = measured top of helmet/hat/hood per unit scale (so height = scale * tall,
## 1.56-1.93 m, measured in the idle pose), right-hand / left-hand accessories.
const LOOKS := {
	KIND_WARRIOR: {"model": "Warrior", "scale": 0.7, "tall": 2.75, "right": "Blade", "left": "Shield_Large_A"},
	KIND_MINION: {"model": "Minion", "scale": 0.72, "tall": 2.17, "right": "Axe", "left": ""},
	KIND_ROGUE: {"model": "Rogue", "scale": 0.78, "tall": 2.41, "right": "Blade", "left": "Shield_Small_B"},
	KIND_MAGE: {"model": "Mage", "scale": 0.68, "tall": 2.62, "right": "Staff", "left": ""},
}

static var _clip_cache: AnimationLibrary = null

## True for skeletons placed by a dungeon marker: the spawner never prunes them.
var guard: bool = false
var bolts_fired: int = 0
var last_bolt: SkeletonBolt = null

var _sk: Skeleton3D
var _ap: AnimationPlayer
var _model: Node3D
var _head_line: float = 1.15
var _hit_anim: float = 0.0
var _cur_clip: String = ""
var _death_clip: String = "Death_A"
var _bone_ua_r: int = -1
var _bone_ul: Array[int] = []
var _arm_overlay: bool = false
var _flash_mats: Array = []         ## [StandardMaterial3D, original albedo]
var _accessories: Dictionary = {}   ## "right"/"left" -> Node3D


static func is_skeleton_kind(k: int) -> bool:
	return k >= KIND_WARRIOR and k <= KIND_MAGE


static func kind_for_type(type_name: String) -> int:
	var i := TYPE_NAMES.find(type_name.to_lower())
	return KIND_WARRIOR + (i if i >= 0 else 0)


static func type_of_kind(k: int) -> String:
	return TYPE_NAMES[clampi(k - KIND_WARRIOR, 0, TYPE_NAMES.size() - 1)]


## All Rig_Medium clips we use, merged from the animation packs (loaded once).
static func clip_library() -> AnimationLibrary:
	if _clip_cache != null:
		return _clip_cache
	var lib := AnimationLibrary.new()
	for path in ANIM_FILES:
		if not ResourceLoader.exists(path):
			continue
		var ps := load(path) as PackedScene
		if ps == null:
			continue
		var n := ps.instantiate()
		var ap := n.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if ap != null:
			for a in ap.get_animation_list():
				if a.ends_with("_Pose") or a == "T-Pose" or lib.has_animation(a):
					continue
				var clip := ap.get_animation(a).duplicate() as Animation
				if LOOPING_CLIPS.has(a):
					clip.loop_mode = Animation.LOOP_LINEAR
				lib.add_animation(a, clip)
		n.free()
	_clip_cache = lib
	return lib


# ================================================================== stats

func _apply_kind() -> void:
	if not is_skeleton_kind(kind):
		kind = KIND_WARRIOR
	runner = false
	match kind:
		KIND_WARRIOR:
			max_health = 130.0
			walk_speed = 1.0
			investigate_speed = 2.0
			chase_speed = 2.7
			attack_damage = 16.0
			attack_interval = 1.3
			wind_up_time = 0.6
			attack_range = 1.7
			sight_range = 26.0
			piece_damage = 30.0
		KIND_MINION:
			max_health = 45.0
			walk_speed = 1.4
			investigate_speed = 2.8
			chase_speed = 4.3
			attack_damage = 7.0
			attack_interval = 0.8
			wind_up_time = 0.3
			attack_range = 1.45
			sight_range = 24.0
			piece_damage = 12.0
		KIND_ROGUE:
			max_health = 70.0
			walk_speed = 1.3
			investigate_speed = 3.0
			chase_speed = 5.0
			attack_damage = 11.0
			attack_interval = 0.7
			wind_up_time = 0.3
			attack_range = 1.55
			sight_range = 30.0
			piece_damage = 18.0
		KIND_MAGE:
			max_health = 60.0
			walk_speed = 0.9
			investigate_speed = 1.8
			chase_speed = 2.4
			attack_damage = 14.0     ## bolt damage
			attack_interval = 2.4
			wind_up_time = 0.8
			attack_range = 15.0      ## cast range (ATTACK state starts at 0.9 x this)
			sight_range = 34.0
			piece_damage = 10.0


func _apply_variant() -> void:
	pass   # fixed look per type


# ================================================================== damage / head

func is_head_hit(world_pos: Vector3) -> bool:
	return world_pos.y > global_position.y + _head_line


## Dismemberment regions follow the skeleton's own scale (see Zombie._part_at). Skeletons
## lose bones the same way zombies lose limbs, but never crawl (their clips drive the pose).
func _head_y() -> float:
	return _head_line


func _leg_y() -> float:
	return _head_line * 0.45


func _arm_x() -> float:
	return 0.28


func _stump_color() -> Color:
	return Color(0.8, 0.78, 0.7)


func _gib_color(_part: int) -> Color:
	return Color(0.85, 0.84, 0.78)


func _supports_crawl() -> bool:
	return false


const SEVER_BONES := {
	Zombie.PART_HEAD: "head", Zombie.PART_ARM_L: "upperarm.l", Zombie.PART_ARM_R: "upperarm.r",
	Zombie.PART_LEG_L: "upperleg.l", Zombie.PART_LEG_R: "upperleg.r",
}


## Hides severed bones by scaling them away; clips rewrite bone poses, so _process reapplies.
func _apply_sever_pose() -> void:
	if _sk == null:
		return
	for part in SEVER_BONES:
		if (severed & int(part)) != 0:
			var b := _sk.find_bone(str(SEVER_BONES[part]))
			if b >= 0:
				_sk.set_bone_pose_scale(b, Vector3(0.001, 0.001, 0.001))


# ================================================================== mage AI

func _do_attack(delta: float) -> void:
	if kind != KIND_MAGE:
		super(delta)
		return
	if _target == null or not is_instance_valid(_target) or _target.is_dead:
		_target = null
		_set_state(State.INVESTIGATE)
		_investigate_pos = _last_known
		return
	var tp := _target.global_position
	var to := tp - global_position
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
				_launch_bolt(tp + Vector3.UP * 1.2)
		return
	if dist > attack_range * 1.3:
		if _attack_cool <= 0.0:
			_set_state(State.CHASE)
		return
	if not _has_line_of_fire(tp):
		_steer(tp, chase_speed * _speed_mult(), delta)   # walk until it can see the target
		return
	if _attack_cool <= 0.0:
		_attack_wind = true
		_attack_timer = wind_up_time
		winding = true


func _has_line_of_fire(tp: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 1.5, tp + Vector3.UP * 1.3, MASK_WORLD, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## Server only: fires a damaging bolt at `aim` and tells clients to show a visual copy.
func _launch_bolt(aim: Vector3) -> void:
	var fwd := -global_transform.basis.z
	var origin := global_position + Vector3.UP * 1.5 + fwd * 0.6
	var vel := (aim - origin).normalized() * BOLT_SPEED
	bolts_fired += 1
	last_bolt = _spawn_bolt(origin, vel, true)
	if multiplayer.has_multiplayer_peer() and multiplayer.get_peers().size() > 0:
		rpc("_rpc_bolt", origin, vel)


@rpc("authority", "call_remote", "unreliable")
func _rpc_bolt(origin: Vector3, vel: Vector3) -> void:
	_spawn_bolt(origin, vel, false)


func _spawn_bolt(origin: Vector3, vel: Vector3, damaging: bool) -> SkeletonBolt:
	var bolt := SkeletonBolt.new()
	bolt.velocity = vel
	bolt.damage = attack_damage * (1.0 + 0.3 * night_mult)
	bolt.damaging = damaging
	bolt.position = origin
	get_tree().root.add_child(bolt)
	return bolt


# ================================================================== visuals

func _build_body() -> void:
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)
	var look: Dictionary = LOOKS[kind]
	var s: float = look["scale"]
	_head_line = HEAD_LINE_FRAC * s
	var height: float = s * float(look["tall"])
	_size_collision(height)
	var path: String = MODEL_PATH % look["model"]
	var ps := load(path) as PackedScene if ResourceLoader.exists(path) else null
	var model := ps.instantiate() as Node3D if ps != null else null
	var sk := model.find_child("Skeleton3D", true, false) as Skeleton3D if model != null else null
	if sk == null:
		if model != null:
			model.free()
		_build_placeholder(height)   # asset missing: plain capsule so the enemy still works
		_built = true
		return
	model.scale = Vector3(s, s, s)
	model.rotation.y = PI   # KayKit faces +Z; enemies face -Z
	_body.add_child(model)
	_model = model
	_sk = sk
	_privatize_materials(model)
	_bone_ua_r = sk.find_bone("upperarm.r")
	_bone_ul = [sk.find_bone("upperleg.l"), sk.find_bone("upperleg.r")]
	_attach(look["right"], "handslot.r", "right")
	_attach(look["left"], "handslot.l", "left")
	_ap = AnimationPlayer.new()
	_ap.name = "Anim"
	model.add_child(_ap)   # clip tracks are "Rig_Medium/Skeleton3D:bone", relative to the model root
	_ap.add_animation_library("", clip_library())
	_ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_death_clip = "Death_A" if variant_seed % 2 == 0 else "Death_B"
	_built = true


func _size_collision(height: float) -> void:
	var cs := get_node_or_null("Collision") as CollisionShape3D
	if cs != null and cs.shape is CapsuleShape3D:
		var shape := (cs.shape as CapsuleShape3D).duplicate() as CapsuleShape3D   # scene sub-resource is shared
		shape.radius = BODY_RADIUS
		shape.height = height
		cs.shape = shape
		cs.position.y = height * 0.5


func _build_placeholder(height: float) -> void:
	_mesh(_body, _capsule_mesh(BODY_RADIUS * 0.8, height * 0.85, 10, 4), Vector3(0, height * 0.5, 0), _material(Color(0.85, 0.84, 0.78)))


## Imported materials are shared by every skeleton: give this one private copies so the hit
## flash does not light up the whole crowd.
func _privatize_materials(model: Node) -> void:
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in range(mi.mesh.get_surface_count()):
			var src := mi.mesh.surface_get_material(i) as StandardMaterial3D
			if src == null:
				continue
			var mat := src.duplicate() as StandardMaterial3D
			mi.set_surface_override_material(i, mat)
			_flash_mats.append([mat, mat.albedo_color])


func _attach(accessory: String, bone: String, slot: String) -> void:
	if accessory == "" or _sk == null or _sk.find_bone(bone) < 0:
		return
	var path: String = ACCESSORY_PATH % accessory
	if not ResourceLoader.exists(path):
		return
	var ps := load(path) as PackedScene
	if ps == null:
		return
	var holder := BoneAttachment3D.new()
	holder.name = "Hold_" + slot
	_sk.add_child(holder)
	holder.bone_name = bone
	var item := ps.instantiate() as Node3D
	holder.add_child(item)
	_accessories[slot] = item


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
	_wind_pose = move_toward(_wind_pose, 1.0 if winding else 0.0, delta * (5.0 if winding else 16.0))
	# a drop in (replicated) health is a hit on every peer
	if health < _prev_health - 0.01 and state_id != State.DEAD:
		_hit_anim = HIT_TIME
		_hit_flash = 0.15
	_prev_health = health
	_hit_anim = maxf(0.0, _hit_anim - delta)
	if _sev_applied != severed:
		_apply_severed(false)
	_update_clip(delta)
	_apply_sever_pose()
	_update_flash()


func _clip_ready(clip: String) -> bool:
	return _ap != null and _ap.has_animation(clip)


func _update_clip(delta: float) -> void:
	var dead := state_id == State.DEAD
	var want := ""
	var speed := 1.0
	if dead:
		want = _death_clip
	elif _hit_anim > 0.0:
		want = "Hit_A" if variant_seed % 2 == 0 else "Hit_B"
	elif _anim_speed > 3.3:
		want = "Running_B" if variant_seed % 2 == 0 else "Running_A"
		speed = clampf(_anim_speed / 5.0, 0.8, 1.4)
	elif _anim_speed > 0.25:
		want = "Walking_A" if variant_seed % 3 != 0 else "Walking_B"
		speed = clampf(_anim_speed / 1.3, 0.7, 1.8)
	else:
		want = "Idle_A" if variant_seed % 2 == 0 else "Idle_B"
	if _clip_ready(want):
		if want != _cur_clip:
			_ap.play(want, 0.12)
			_cur_clip = want
		_ap.speed_scale = speed
		_ap.advance(delta)
		_body.rotation.x = 0.0
		_body.position.y = 0.0
	else:
		_procedural_fallback(dead)
	if not dead:
		_overlay_attack_arm()


## Right-arm wind-up (raised) and strike (chop down). No melee clip exists in the free pack.
func _overlay_attack_arm() -> void:
	if _sk == null or _bone_ua_r < 0:
		return
	var theta := NAN
	if _attack_anim > 0.0:
		var u := 1.0 - _attack_anim / 0.6
		if u < 0.35:
			theta = lerpf(RAISE_ANGLE, SWING_END, smoothstep(0.0, 1.0, u / 0.35))
		else:
			theta = lerpf(SWING_END, 0.0, (u - 0.35) / 0.65)
	elif _wind_pose > 0.02:
		theta = RAISE_ANGLE * _wind_pose
	if is_nan(theta):
		if _arm_overlay:
			_arm_overlay = false   # hand the bone back; the clip rewrites it next frame
			_sk.set_bone_pose_rotation(_bone_ua_r, _sk.get_bone_rest(_bone_ua_r).basis.get_rotation_quaternion())
		return
	_arm_overlay = true
	_aim_right_arm(theta)


## Absolute pose (no accumulation): points the right upper arm along a direction in the
## sagittal plane. theta 0 = hanging, -pi/2 = forward, beyond = raised overhead.
func _aim_right_arm(theta: float) -> void:
	var dir := Vector3(-0.3, -cos(theta), -sin(theta)).normalized()
	var rest_g := _sk.get_bone_global_rest(_bone_ua_r).basis
	var parent_g := _sk.get_bone_global_pose(_sk.get_bone_parent(_bone_ua_r)).basis.orthonormalized()
	var g := Basis(Quaternion(Vector3.LEFT, dir)) * rest_g   # rest arm points along -X
	_sk.set_bone_pose_rotation(_bone_ua_r, (parent_g.inverse() * g).orthonormalized().get_rotation_quaternion())


## Used when a clip is missing: leg swing while moving, topple when dead.
func _procedural_fallback(dead: bool) -> void:
	if dead:
		_fall = move_toward(_fall, 1.0, get_process_delta_time() / DEATH_TIME)
		_body.rotation.x = -_fall * PI * 0.5
		_body.position.y = 0.1 * _fall
		return
	_body.rotation.x = 0.0
	_body.position.y = 0.0
	if _sk == null:
		return
	var swing := sin(_anim_phase * 2.0) * clampf(_anim_speed / 2.5, 0.0, 1.0) * 0.7
	for i in range(_bone_ul.size()):
		var b := _bone_ul[i]
		if b >= 0:
			_sk.set_bone_pose_rotation(b, Quaternion(Vector3.RIGHT, swing * (1.0 if i == 0 else -1.0)) * _sk.get_bone_rest(b).basis.get_rotation_quaternion())


func _update_flash() -> void:
	var on := _hit_flash > 0.0
	for e in _flash_mats:
		(e[0] as StandardMaterial3D).albedo_color = Color(1.0, 0.35, 0.35) if on else (e[1] as Color)
