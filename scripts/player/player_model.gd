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
##   animate(delta, speed, pitch_deg, crouching, sprinting, dead, armed)
##   static clip_for(speed, crouching, sprinting, dead, armed) -> String
##   current_clip() -> String

const MODEL_DIR := "res://assets/kenney/mini/"
const MODELS := [
	"character-male-a", "character-female-a", "character-male-b", "character-female-b",
	"character-male-c", "character-female-c", "character-male-d", "character-female-d",
	"character-male-e", "character-female-e", "character-male-f", "character-female-f",
]
const TARGET_HEIGHT := 1.8     ## metres, same as Player.STAND_HEIGHT
const MAX_AIM_DEG := 60.0      ## how far the head follows look_pitch
const WALK_MIN := 0.3          ## m/s above which the walk clip plays
const SPRINT_MIN := 4.6        ## m/s above which the sprint clip plays
const LOOPED := ["idle", "walk", "sprint", "crouch", "holding-both"]

var local_view: bool = false
var _ap: AnimationPlayer
var _skel: Skeleton3D
var _head_bone: int = -1
var _clip: String = ""
var _meshes: Array[MeshInstance3D] = []


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


func _play(clip: String, blend: float = 0.15) -> void:
	if clip == _clip or _ap == null or not _ap.has_animation(clip):
		return
	_clip = clip
	_ap.play(clip, blend)


## Call once per frame. speed = horizontal m/s (velocity locally, measured on a remote peer).
func animate(delta: float, speed: float, pitch_deg: float, crouching: bool, sprinting: bool, dead: bool, armed: bool) -> void:
	if _ap == null:
		return
	_play(clip_for(speed, crouching, sprinting, dead, armed))
	_ap.advance(delta)
	if dead:
		return
	# aim: tip the head with the (replicated) look pitch, on top of the clip's own pose
	var a := deg_to_rad(clampf(pitch_deg, -MAX_AIM_DEG, MAX_AIM_DEG))
	_skel.set_bone_pose_rotation(_head_bone, _skel.get_bone_pose_rotation(_head_bone) * Quaternion(Vector3.RIGHT, -a))
