class_name PlayerModel
extends Node3D
## Visible player body built from a Kenney Mini Character. Purely cosmetic and local to each
## peer: it reads state that Player already replicates (look_pitch, crouching, is_dead,
## is_sprinting) plus a speed the caller measures, so it needs no RPCs and works on a remote
## peer. For the local (authority) player every mesh is shadows-only: the body casts a shadow
## but is never drawn, so the first-person view is unchanged.
##
## Public API:
##   build(peer_id, local) -> bool   (false = asset missing; caller keeps its fallback body)
##   animate(delta, speed, pitch_deg, crouching, sprinting, dead, armed, lean = 0.0)
##   hold(gun)                       (parents the gun to the body; animate() keeps it in the hands, aimed by pitch)
##   static clip_for(speed, crouching, sprinting, dead, armed) -> String
##   current_clip() -> String

const ItemDB := preload("res://scripts/world/item_db.gd")
const ModelUtil := preload("res://scripts/world/model_util.gd")

const MODEL_DIR := "res://assets/kenney/mini/"
const BACK_BONE := "torso"
## Bone space (x 2.32 = metres; Kenney faces +Z, so -Z is the back). Every pack's front face rests on the back of the
## torso and its bottom sits just above the belt, so a taller worn_size rides higher: the large pack rises past the
## shoulders and stands out behind the (big) head, where the third-person camera sees it.
const BACK_SURFACE_Z := -0.125
const PACK_BOTTOM_Y := 0.02
const MODELS := [
	"character-male-a", "character-female-a", "character-male-b", "character-female-b",
	"character-male-c", "character-female-c", "character-male-d", "character-female-d",
	"character-male-e", "character-female-e", "character-male-f", "character-female-f",
]
const TARGET_HEIGHT := 1.8     ## metres, same as Player.STAND_HEIGHT
const MAX_AIM_DEG := 60.0      ## how far the head follows look_pitch
const ARM_AIM_DEG := 70.0      ## how far the arms (and the held gun) follow look_pitch
const SPRINT_CARRY_DEG := -35.0   ## low-ready pitch of the gun while sprinting
const LEAN_BODY_DEG := 15.0    ## torso roll at full lean (lean = +-1)
## Bone units (x 2.32 = metres). The rig has no hand bones: the fist is at the far end of each arm bone, along -X for
## arm-right and +X for arm-left (measured from the skinned vertices and rendered markers).
const FIST_REACH := 0.40
const GRIP_SIDE := 0.04        ## grip sits this far to the body's right of the shoulder midpoint
const GRIP_DROP := 0.03        ## and this far below the shoulder line
const GUN_SCALE := 1.5         ## the gun is scaled up to read against the chunky body
const WALK_MIN := 0.3          ## m/s above which the walk clip plays
const SPRINT_MIN := 4.6        ## m/s above which the sprint clip plays
const LOOPED := ["idle", "walk", "sprint", "crouch", "holding-both"]

var local_view: bool = false
var _ap: AnimationPlayer
var _skel: Skeleton3D
var _head_bone: int = -1
var _torso_bone: int = -1
var _arm_r: int = -1
var _arm_l: int = -1
var _gun: Node3D
var _clip: String = ""
var _meshes: Array[MeshInstance3D] = []
var _pack_id: String = ""
var _pack_att: BoneAttachment3D
var _pack_meshes: Array[MeshInstance3D] = []


func build(peer_id: int, local: bool) -> bool:
	local_view = local
	var path := MODEL_DIR + String(MODELS[absi(peer_id) % MODELS.size()]) + ".glb"
	if not ResourceLoader.exists(path):
		return false
	var ps := load(path) as PackedScene
	if ps == null:
		return false
	var model := ps.instantiate() as Node3D
	if model == null:
		return false
	_skel = model.find_child("Skeleton3D", true, false) as Skeleton3D
	_ap = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _skel == null or _ap == null:
		model.free()
		return false
	_head_bone = _skel.find_bone("head")
	_torso_bone = _skel.find_bone("torso")
	_arm_r = _skel.find_bone("arm-right")
	_arm_l = _skel.find_bone("arm-left")
	if _head_bone < 0 or not _ap.has_animation("idle") or not _ap.has_animation("walk"):
		model.free()
		return false
	_ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for n in LOOPED:
		if _ap.has_animation(n):
			_ap.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		_meshes.append(mi)
		if local:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	model.rotation.y = PI   # Kenney faces +Z; players face -Z
	model.scale = Vector3.ONE * (TARGET_HEIGHT / maxf(_rest_height(model), 0.01))
	add_child(model)
	_play("idle", 0.0)
	return true


## Height of the model's meshes at unit scale, measured from the vertex data.
func _rest_height(model: Node3D) -> float:
	var lo := INF
	var hi := -INF
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var xf := Transform3D.IDENTITY
		var node: Node = mi
		while node != null and node != model:
			xf = (node as Node3D).transform * xf
			node = node.get_parent()
		var box := xf * mi.mesh.get_aabb()
		lo = minf(lo, box.position.y)
		hi = maxf(hi, box.end.y)
	return hi - lo if hi > lo else 0.7


static func clip_for(speed: float, crouching: bool, sprinting: bool, dead: bool, armed: bool) -> String:
	if dead:
		return "die"
	if crouching:
		return "crouch"
	if sprinting and speed > SPRINT_MIN * 0.6 or speed > SPRINT_MIN:
		return "sprint"
	if speed > WALK_MIN:
		return "walk"
	return "holding-both" if armed else "idle"


func current_clip() -> String:
	return _clip


## First person (first_person=true): meshes are shadows-only, the body is never drawn.
## Third person: the full body is drawn.
func set_local_view(first_person: bool) -> void:
	local_view = first_person
	var mode := GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if first_person \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for mi in _meshes:
		mi.cast_shadow = mode


## Wears (or removes, id "") a backpack on the torso bone. Model and size come from the ItemDB item's worn_* keys. It is
## attached to the animated skeleton so it moves with the body, and follows the first / third person drawing mode.
func set_backpack(id: String) -> void:
	if id == _pack_id or _skel == null:
		return
	_pack_id = id
	for mi in _pack_meshes:
		_meshes.erase(mi)
	_pack_meshes.clear()
	if _pack_att != null:
		_pack_att.get_parent().remove_child(_pack_att)
		_pack_att.queue_free()
		_pack_att = null
	if id == "" or _skel.find_bone(BACK_BONE) < 0:
		return
	var d: Dictionary = ItemDB.get_item(id)
	var size: Vector3 = d.get("worn_size", Vector3(0.14, 0.17, 0.07)) as Vector3
	var yaw: float = float(d.get("worn_yaw", 0.0))
	var turned := absf(fposmod(yaw, 180.0) - 90.0) < 1.0   # a quarter turn swaps the model's x / z extents
	var m: Node3D = ModelUtil.fit_box(str(d.get("worn_model", "")), Vector3(size.z, size.y, size.x) if turned else size)
	if m == null:
		return
	m.rotation_degrees.y = yaw
	m.position = Vector3(0.0, PACK_BOTTOM_Y + size.y * 0.5, BACK_SURFACE_Z - size.z * 0.5)
	_pack_att = BoneAttachment3D.new()
	_pack_att.name = "Backpack"
	_pack_att.bone_name = BACK_BONE
	_skel.add_child(_pack_att)
	_pack_att.add_child(m)
	var mode := GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if local_view \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for n in m.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		mi.cast_shadow = mode
		_meshes.append(mi)
		_pack_meshes.append(mi)


func _play(clip: String, blend: float = 0.15) -> void:
	if clip == _clip or _ap == null or not _ap.has_animation(clip):
		return
	_clip = clip
	_ap.play(clip, blend)


## Call once per frame. speed = horizontal m/s (velocity locally, measured on a remote peer).
## lean = -1 (full left) .. +1 (full right): rolls the upper body; the arms and gun follow it.
func animate(delta: float, speed: float, pitch_deg: float, crouching: bool, sprinting: bool, dead: bool, armed: bool,
		lean: float = 0.0) -> void:
	if _ap == null:
		return
	_play(clip_for(speed, crouching, sprinting, dead, armed))
	_ap.advance(delta)
	if dead:
		_place_gun_on_arm()
		return
	# lean: roll the torso about the body's forward axis (Kenney faces +Z, its right is -X, so +angle tips right)
	if _torso_bone >= 0 and absf(lean) > 0.001:
		var roll := Quaternion(Vector3.BACK, deg_to_rad(LEAN_BODY_DEG) * clampf(lean, -1.0, 1.0))
		_skel.set_bone_pose_rotation(_torso_bone, roll * _skel.get_bone_pose_rotation(_torso_bone))
	# aim: tip the head with the (replicated) look pitch, on top of the clip's own pose
	var a := deg_to_rad(clampf(pitch_deg, -MAX_AIM_DEG, MAX_AIM_DEG))
	_skel.set_bone_pose_rotation(_head_bone, _skel.get_bone_pose_rotation(_head_bone) * Quaternion(Vector3.RIGHT, -a))
	if armed and _arm_r >= 0 and _arm_l >= 0:
		var p := SPRINT_CARRY_DEG if sprinting and not crouching else clampf(pitch_deg, -ARM_AIM_DEG, ARM_AIM_DEG)
		_aim_arms(deg_to_rad(p), deg_to_rad(LEAN_BODY_DEG) * clampf(lean, -1.0, 1.0))


## Parents the avatar gun to this body (null = none). animate() places it every frame.
func hold(gun: Node3D) -> void:
	_gun = gun
	if gun == null:
		return
	if gun.get_parent() != null:
		gun.get_parent().remove_child(gun)
	add_child(gun)
	gun.scale = Vector3.ONE * GUN_SCALE


## Upper-body aim, in skeleton space (forward +Z, right -X). Builds a hold frame at the shoulder midpoint turned by
## pitch and lean, puts the grip within the right fist's reach and the left fist on the barrel line, rotates both
## arm bones to point at those targets and places the gun with its barrel along the frame's forward axis.
func _aim_arms(pitch: float, roll: float) -> void:
	var rs := _skel.get_bone_global_pose(_arm_r).origin
	var ls := _skel.get_bone_global_pose(_arm_l).origin
	var pivot := (rs + ls) * 0.5
	var frame := Basis(Vector3.BACK, roll) * Basis(Vector3.RIGHT, -pitch)
	var inv := frame.inverse()
	var rl := inv * (rs - pivot)
	var gx := -GRIP_SIDE
	var gy := -GRIP_DROP
	var gz := rl.z + sqrt(maxf(FIST_REACH * FIST_REACH - (gx - rl.x) * (gx - rl.x) - (gy - rl.y) * (gy - rl.y), 0.0004))
	var grip := pivot + frame * Vector3(gx, gy, gz)
	var fwd := frame * Vector3.BACK
	# left fist: the point on the barrel line (ahead of the grip) at FIST_REACH from the left shoulder
	var d := grip - ls
	var b := d.dot(fwd)
	var disc := b * b - (d.length_squared() - FIST_REACH * FIST_REACH)
	var t := (-b + sqrt(disc)) if disc >= 0.0 else -b
	var fore := grip + fwd * clampf(t, 0.06, 0.3)
	_point_arm(_arm_r, Vector3.LEFT, grip)
	_point_arm(_arm_l, Vector3.RIGHT, fore)
	_place_gun(grip, fwd, frame * Vector3.UP)


## Rotates arm bone `bone` (minimal rotation) so its local `axis` points from the shoulder at `target`.
func _point_arm(bone: int, axis: Vector3, target: Vector3) -> void:
	var g := _skel.get_bone_global_pose(bone)
	var want := target - g.origin
	if want.length_squared() < 1e-6:
		return
	var cur := (g.basis.orthonormalized() * axis).normalized()
	var new_basis := Basis(Quaternion(cur, want.normalized())) * g.basis.orthonormalized()
	var parent := _skel.get_bone_parent(bone)
	var pb := _skel.get_bone_global_pose(parent).basis.orthonormalized() if parent >= 0 else Basis.IDENTITY
	_skel.set_bone_pose_rotation(bone, (pb.inverse() * new_basis).get_rotation_quaternion())


## Places the gun (gun-local -Z = barrel) with its grip at `grip_skel`, pointing along `fwd_skel` (skeleton space).
func _place_gun(grip_skel: Vector3, fwd_skel: Vector3, up_skel: Vector3) -> void:
	if _gun == null or not is_instance_valid(_gun):
		return
	var sx := _skel.global_transform
	var g := to_local(sx * grip_skel)
	var fwd := (to_local(sx * (grip_skel + fwd_skel)) - g).normalized()
	var up := (to_local(sx * (grip_skel + up_skel)) - g).normalized()
	var basis := Basis.looking_at(fwd, up)
	# GunMesh grip is at gun-local z = -0.03, a little below the receiver top: shift so the fist closes on it
	var origin := g - basis * (Vector3(0.0, -0.03, -0.03) * GUN_SCALE)
	_gun.transform = Transform3D(basis.scaled(Vector3.ONE * GUN_SCALE), origin)


## Dead (or unarmed fallback): the gun simply stays at the right fist, along the arm.
func _place_gun_on_arm() -> void:
	if _gun == null or _arm_r < 0:
		return
	var g := _skel.get_bone_global_pose(_arm_r)
	var b := g.basis.orthonormalized()
	var fist := g.origin + b * (Vector3.LEFT * FIST_REACH)
	_place_gun(fist, b * Vector3.BACK, b * Vector3.UP)


## World-space barrel direction of the held gun (zero when none). Used by tests.
func gun_forward() -> Vector3:
	if _gun == null or not is_instance_valid(_gun):
		return Vector3.ZERO
	return (-_gun.global_basis.z).normalized()
