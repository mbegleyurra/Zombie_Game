extends Node3D
## First-person hands and per-weapon reload animation.
##
## A Hands node is attached as a child of the gun mesh that WeaponController builds, so both hands
## and forearms ride with the gun (sway, recoil, ADS, lowering). Local player only: the controller
## attaches it just when it has authority, so remote peers never build it (they see the existing
## PlayerModel / avatar body instead).
##
## Hands are skin-coloured box meshes with sleeve-coloured forearms that stretch back to a shoulder
## anchor. Detachable gun parts (magazine, slide, charging handle, bolt, pump forend) are not
## separate meshes in GunMesh, so the box meshes that sit inside a tuned AABB are re-parented into
## a pivot node at attach time; the pivot is what the reload animates.
##
## Reload styles (picked per weapon from TUNING, else derived from its WeaponData):
##   pistol : tilt, left hand pulls the mag, new mag from a pouch, seat it, slide rack when empty
##   rifle  : same mag swap with a charging-handle pull when empty (rifles, SMGs, new guns)
##   bolt   : bolt opened, clip pushed in from the top, bolt closed
##   shell  : tube gun, one shell at a time to the loading port, pump rack when empty
## Duration is WeaponData.reload_time(), the same number the controller's reload timer uses.
## The animation is purely visual: it never changes weapon state and is cancelled by
## cancel() (weapon switch frees the gun and the hands with it; death/cancel_reload call cancel()).
##
## API: static attach(gun, wd) -> Node3D, play_reload(wd, empty, missing) -> float, play_rack(wd) -> float,
##      cancel(), is_playing(), duration(), style(), advance(delta), set_hands_visible(v),
##      static style_of(wd), static tuning_key(model). Signal reload_finished (natural end only).

signal reload_finished

const SCRIPT_PATH := "res://scripts/weapons/viewmodel.gd"
const SKIN := Color(0.86, 0.66, 0.52)
const SLEEVE := Color(0.2, 0.26, 0.2)
const MAG_COLOR := Color(0.1, 0.1, 0.11)
const SHELL_COLOR := Color(0.72, 0.1, 0.08)
const CLIP_COLOR := Color(0.7, 0.55, 0.2)
const ANCHOR_R := Vector3(0.12, -0.22, 0.5)     ## gun-local shoulder points the forearms stretch to
const ANCHOR_L := Vector3(-0.42, -0.24, 0.5)
const ARM_W := 0.062
const WRIST_LEN := 0.08
const MIN_DURATION := 0.05

## Per-weapon tuning, keyed by GunMesh model key (ar_t1..3 reuse "ar"). Gun-local metres, gun points -Z.
## style, grip_r/grip_l (hand rest), mag_pos (pivot at the top of the magazine), mag_region (boxes that
## form the magazine), slide_region / charge_region / bolt_region / pump_region (the moving top part),
## slide_pos / charge_pos / bolt_hand / port (where hands go), slide_travel, grab_off, proxy* (fallback mag).
## Unlisted models get a derived profile (see _profile_for), so a new weapon_db entry still animates.
const TUNING := {
	"pistol": {
		"style": "pistol",
		"grip_r": Vector3(0.022, -0.06, -0.03), "grip_l": Vector3(-0.022, -0.07, -0.045),
		"mag_pos": Vector3(0.0, -0.103, -0.012),
		"mag_region": AABB(Vector3(-0.03, -0.12, -0.04), Vector3(0.06, 0.03, 0.07)),
		"proxy": true, "proxy_size": Vector3(0.026, 0.095, 0.04), "proxy_center": Vector3(0.0, 0.058, 0.0), "proxy_tilt": -12.0,
		"slide_region": AABB(Vector3(-0.03, 0.025, -0.215), Vector3(0.06, 0.055, 0.21)),
		"slide_pos": Vector3(0.0, 0.052, -0.03), "slide_travel": 0.05,
	},
	"ak": {
		"style": "rifle",
		"grip_r": Vector3(0.0, -0.075, -0.04), "grip_l": Vector3(0.0, -0.045, -0.4),
		"mag_pos": Vector3(0.0, -0.07, -0.19),
		"mag_region": AABB(Vector3(-0.03, -0.2, -0.26), Vector3(0.06, 0.135, 0.12)),
		"charge_region": AABB(Vector3(0.02, -0.02, -0.03), Vector3(0.015, 0.02, 0.02)),
		"charge_pos": Vector3(0.04, -0.01, -0.02), "slide_travel": 0.06,
	},
	"m4": {
		"style": "rifle",
		"grip_r": Vector3(0.0, -0.08, -0.03), "grip_l": Vector3(0.0, -0.045, -0.4),
		"mag_pos": Vector3(0.0, -0.065, -0.17),
		"mag_region": AABB(Vector3(-0.03, -0.2, -0.23), Vector3(0.06, 0.14, 0.12)),
		"charge_region": AABB(Vector3(-0.02, 0.09, -0.04), Vector3(0.04, 0.02, 0.03)),
		"charge_pos": Vector3(0.0, 0.135, -0.03), "slide_travel": 0.06,
	},
	"ar": {
		"style": "rifle",
		"grip_r": Vector3(0.0, -0.08, -0.03), "grip_l": Vector3(0.0, -0.045, -0.45),
		"mag_pos": Vector3(0.0, -0.06, -0.17),
		"mag_region": AABB(Vector3(-0.03, -0.26, -0.21), Vector3(0.06, 0.21, 0.08)),
		"charge_region": AABB(Vector3(-0.02, 0.055, -0.025), Vector3(0.04, 0.015, 0.035)),
		"charge_pos": Vector3(0.0, 0.095, -0.01), "slide_travel": 0.06,
	},
	"shotgun": {
		"style": "shell",
		"grip_r": Vector3(0.0, -0.075, -0.03), "grip_l": Vector3(0.0, -0.05, -0.42),
		"port": Vector3(0.0, -0.05, -0.06),
		"pump_region": AABB(Vector3(-0.03, -0.03, -0.52), Vector3(0.06, 0.04, 0.22)),
		"slide_travel": 0.12,
	},
	"hunting": {
		"style": "bolt",
		"grip_r": Vector3(0.0, -0.065, -0.025), "grip_l": Vector3(0.0, -0.045, -0.35),
		"port": Vector3(0.0, 0.07, -0.12), "bolt_hand": Vector3(0.07, 0.03, -0.05),
		"bolt_region": AABB(Vector3(0.03, 0.01, -0.07), Vector3(0.05, 0.03, 0.04)),
		"slide_travel": 0.09,
	},
}

static var _mats: Dictionary = {}

var _gun: Node3D
var _wd: WeaponData
var _p: Dictionary = {}
var _style: String = "rifle"
var _hand_l: Node3D
var _hand_r: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _sleeve_l: MeshInstance3D
var _sleeve_r: MeshInstance3D
var _mag: Node3D            ## magazine pivot (pistol / rifle)
var _mag_baked: bool = false ## true when real gun meshes were captured into the pivot
var _mag_rest: Vector3 = Vector3.ZERO
var _slide: Node3D          ## slide / charging handle / bolt / pump forend pivot
var _prop: MeshInstance3D   ## shell or clip held in the left hand
var _l_rest: Vector3 = Vector3.ZERO
var _r_rest: Vector3 = Vector3.ZERO

var _playing: bool = false
var _t: float = 0.0
var _dur: float = 1.0
var _rounds: int = 0
var _rack: bool = false

# pose written by the _pose_* functions, applied by _apply()
var _g_pos: Vector3 = Vector3.ZERO
var _g_rot: Vector3 = Vector3.ZERO
var _l: Vector3 = Vector3.ZERO
var _r: Vector3 = Vector3.ZERO
var _mag_off: Vector3 = Vector3.ZERO
var _mag_vis: bool = true
var _slide_z: float = 0.0
var _prop_vis: bool = false
var _prop_pos: Vector3 = Vector3.ZERO


# ------------------------------------------------------------------ public API

## Builds the hands for `wd` under `gun` (the node GunMesh.build returned) and returns them.
static func attach(gun: Node3D, wd: WeaponData) -> Node3D:
	var vm: Node3D = (load(SCRIPT_PATH) as GDScript).new()
	gun.add_child(vm)
	vm.call("_setup", gun, wd)
	return vm


## "shell" for tube guns, "pistol" for a semi-auto handgun, "bolt" for a small-magazine manual
## rifle, otherwise "rifle" (assault rifles, SMGs, anything automatic).
static func style_of(wd: WeaponData) -> String:
	var key := tuning_key(wd.model)
	if key != "":
		return str((TUNING[key] as Dictionary)["style"])
	if wd.per_round_reload:
		return "shell"
	if wd.automatic:
		return "rifle"
	return "bolt" if wd.mag_size <= 8 else "pistol"


static func tuning_key(model: String) -> String:
	if TUNING.has(model):
		return model
	var base := model.get_slice("_t", 0)
	return base if TUNING.has(base) else ""


## Starts the reload animation; returns its duration (WeaponData.reload_time).
## empty = nothing chambered (adds the rack / charge), missing = rounds a tube gun will load.
func play_reload(wd: WeaponData, empty: bool, missing: int) -> float:
	_begin()
	_rack = empty
	_rounds = maxi(missing, 0) if _style == "shell" else 0
	_dur = maxf(wd.reload_time(empty, missing if wd.per_round_reload else -1), MIN_DURATION)
	_start()
	return _dur


## Only the pump / charge motion (a tube gun chambering after an interrupted reload).
func play_rack(wd: WeaponData) -> float:
	_begin()
	_rack = true
	_rounds = 0
	_dur = maxf(wd.chamber_time, MIN_DURATION)
	_start()
	return _dur


## Stops at once and snaps hands and gun back to the rest pose. Safe when idle.
func cancel() -> void:
	_end(false)


func is_playing() -> bool:
	return _playing


func duration() -> float:
	return _dur


func style() -> String:
	return _style


func progress() -> float:
	return clampf(_t / _dur, 0.0, 1.0) if _playing else 0.0


func set_hands_visible(v: bool) -> void:
	visible = v


## Steps the animation. _process calls this; tests call it directly for deterministic time.
func advance(delta: float) -> void:
	if not _playing:
		return
	_t += delta
	if _t >= _dur:
		_end(true)
	else:
		_pose(_t)


func _process(delta: float) -> void:
	advance(delta)


# ------------------------------------------------------------------ setup

func _setup(gun: Node3D, wd: WeaponData) -> void:
	_gun = gun
	_wd = wd
	name = "Hands"
	_p = _profile_for(wd, gun)
	_style = str(_p["style"])
	_l_rest = _p["grip_l"]
	_r_rest = _p["grip_r"]
	_hand_r = _build_hand(1.0)
	_hand_l = _build_hand(-1.0)
	add_child(_hand_r)
	add_child(_hand_l)
	_arm_r = _build_arm("Arm_R")
	_arm_l = _build_arm("Arm_L")
	_sleeve_r = _arm_r.get_node("Sleeve") as MeshInstance3D
	_sleeve_l = _arm_l.get_node("Sleeve") as MeshInstance3D
	add_child(_arm_r)
	add_child(_arm_l)
	var slide_key := ""
	match _style:
		"pistol", "rifle":
			_mag_rest = _p["mag_pos"]
			_mag = Node3D.new()
			_mag.name = "Mag"
			_mag.position = _mag_rest
			gun.add_child(_mag)
			var n := 0
			if _p.has("mag_region"):
				n = _capture(_p["mag_region"], true, _mag)
			_mag_baked = n > 0
			if n == 0 or bool(_p.get("proxy", false)):
				_make_proxy_mag(_mag)
			slide_key = "slide_region" if _style == "pistol" else "charge_region"
		"bolt":
			slide_key = "bolt_region"
			_prop = _make_prop(false)
		"shell":
			slide_key = "pump_region"
			_prop = _make_prop(true)
	if slide_key != "" and _p.has(slide_key):
		_slide = Node3D.new()
		_slide.name = "Slide"
		gun.add_child(_slide)
		_capture(_p[slide_key], _style != "bolt", _slide)
	_rest_pose()
	_apply()
	set_process(false)


func _profile_for(wd: WeaponData, gun: Node3D) -> Dictionary:
	var key := tuning_key(wd.model)
	var p: Dictionary = {}
	if key != "":
		p = (TUNING[key] as Dictionary).duplicate()
	var style_name: String = str(p.get("style", style_of(wd)))
	p["style"] = style_name
	# Blaster Kit guns are one fused mesh: no box parts to capture, and hand/mag points come from the
	# model's own geometry (GunMesh meta "vm_profile") instead of the hand-tuned procedural numbers.
	if gun.has_meta("vm_profile"):
		for k in ["mag_region", "slide_region", "charge_region", "bolt_region", "pump_region", "proxy"]:
			p.erase(k)
		var vp: Dictionary = gun.get_meta("vm_profile")
		for k in vp:
			p[k] = vp[k]
	var mz := -0.5
	var marker := GunMesh.muzzle_of(gun)
	if marker != null:
		mz = marker.position.z
	var pistol := style_name == "pistol"
	_dflt(p, "grip_r", Vector3(0.022, -0.06, -0.03) if pistol else Vector3(0.0, -0.075, -0.03))
	_dflt(p, "grip_l", Vector3(-0.022, -0.07, -0.045) if pistol else Vector3(0.0, -0.045, clampf(mz * 0.5, -0.6, -0.12)))
	_dflt(p, "mag_pos", Vector3(0.0, -0.103, -0.012) if pistol else Vector3(0.0, -0.065, clampf(mz * 0.22, -0.3, -0.1)))
	_dflt(p, "grab_off", Vector3(0.0, -0.02, 0.0) if pistol else Vector3(0.0, -0.09, 0.0))
	_dflt(p, "slide_pos", Vector3(0.0, 0.052, -0.03))
	_dflt(p, "charge_pos", Vector3(0.0, 0.11, -0.03))
	_dflt(p, "bolt_hand", Vector3(0.07, 0.03, -0.05))
	_dflt(p, "port", Vector3(0.0, 0.07, -0.12) if style_name == "bolt" else Vector3(0.0, -0.05, -0.06))
	_dflt(p, "slide_travel", 0.05 if pistol else 0.06)
	_dflt(p, "proxy_size", Vector3(0.026, 0.095, 0.04) if pistol else Vector3(0.04, 0.13, 0.06))
	_dflt(p, "proxy_center", Vector3(0.0, 0.058, 0.0) if pistol else Vector3(0.0, -0.07, 0.0))
	_dflt(p, "proxy_tilt", -12.0 if pistol else 0.0)
	return p


static func _dflt(p: Dictionary, k: String, v: Variant) -> void:
	if not p.has(k):
		p[k] = v


## Moves the gun's box meshes whose centre is inside `region` under `pivot`.
func _capture(region: AABB, boxes_only: bool, pivot: Node3D) -> int:
	var n := 0
	for c in _gun.get_children():
		var mi := c as MeshInstance3D
		if mi == null:
			continue
		if boxes_only and not (mi.mesh is BoxMesh):
			continue
		if not region.has_point(mi.position):
			continue
		var keep := mi.position
		_gun.remove_child(mi)
		pivot.add_child(mi)
		mi.position = keep - pivot.position
		n += 1
	return n


func _make_proxy_mag(pivot: Node3D) -> void:
	if _p.has("clip_file") and _make_clip_proxy(pivot):
		return
	var sz: Vector3 = _p["proxy_size"]
	var c: Vector3 = _p["proxy_center"]
	var tilt: float = _p["proxy_tilt"]
	var mi := _box(pivot, sz, c, MAG_COLOR, Vector3(tilt, 0.0, 0.0))
	mi.name = "ProxyMag"


## Blaster Kit magazine: the kit clip .glb hangs below the pivot (its origin is the clip base).
## The fused mesh keeps its own magazine, so this clip is only shown while the hand handles it.
func _make_clip_proxy(pivot: Node3D) -> bool:
	var path: String = GunMesh.blaster_dir + str(_p["clip_file"]) + ".glb"
	if not ResourceLoader.exists(path):
		return false
	var ps := load(path) as PackedScene
	if ps == null:
		return false
	var inst := ps.instantiate() as Node3D
	if inst == null:
		return false
	var cs: float = _p["clip_scale"]
	inst.name = "ProxyMag"
	inst.scale = Vector3.ONE * cs
	inst.position = Vector3(0.0, -float(_p["clip_h"]) * cs, 0.0)
	pivot.add_child(inst)
	return true


func _make_prop(is_shell: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "HeldShell" if is_shell else "HeldClip"
	if is_shell:
		var cm := CylinderMesh.new()
		cm.top_radius = 0.011
		cm.bottom_radius = 0.011
		cm.height = 0.055
		cm.radial_segments = 8
		cm.rings = 1
		mi.mesh = cm
		mi.rotation_degrees = Vector3(90.0, 0.0, 0.0)
		mi.material_override = _mat(SHELL_COLOR)
	else:
		var bm := BoxMesh.new()
		bm.size = Vector3(0.03, 0.012, 0.07)
		mi.mesh = bm
		mi.material_override = _mat(CLIP_COLOR)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	add_child(mi)
	return mi


static func _mat(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.85
	_mats[key] = m
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, color: Color, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = _mat(color)
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## side +1 = right hand, -1 = left. Origin sits at the palm.
func _build_hand(side: float) -> Node3D:
	var h := Node3D.new()
	h.name = "Hand_R" if side > 0.0 else "Hand_L"
	_box(h, Vector3(0.05, 0.032, 0.07), Vector3.ZERO, SKIN).name = "Palm"
	_box(h, Vector3(0.05, 0.022, 0.04), Vector3(0.0, -0.026, -0.04), SKIN).name = "Fingers"
	_box(h, Vector3(0.014, 0.014, 0.05), Vector3(-side * 0.03, 0.012, -0.025), SKIN).name = "Thumb"
	return h


## Forearm: a short skin wrist plus a sleeve that stretches to the shoulder anchor (+Z of the node).
func _build_arm(arm_name: String) -> Node3D:
	var a := Node3D.new()
	a.name = arm_name
	_box(a, Vector3(0.05, 0.05, WRIST_LEN), Vector3(0.0, 0.0, WRIST_LEN * 0.5), SKIN).name = "Wrist"
	_box(a, Vector3(ARM_W, ARM_W, 1.0), Vector3.ZERO, SLEEVE).name = "Sleeve"
	return a


func _place_arm(arm: Node3D, sleeve: MeshInstance3D, hand: Vector3, anchor: Vector3) -> void:
	var d := anchor - hand
	var dist := d.length()
	if dist < 0.01:
		return
	var dir := d / dist
	arm.transform = Transform3D(Basis.looking_at(-dir, Vector3.UP), hand)
	var slen := maxf(dist - WRIST_LEN, 0.02)
	sleeve.scale = Vector3(1.0, 1.0, slen)
	sleeve.position = Vector3(0.0, 0.0, WRIST_LEN + slen * 0.5)


# ------------------------------------------------------------------ playback

func _begin() -> void:
	if _playing:
		_end(false)
	_t = 0.0


func _start() -> void:
	_playing = true
	set_process(true)
	_pose(0.0)


func _end(natural: bool) -> void:
	var was := _playing
	_playing = false
	_t = 0.0
	set_process(false)
	if _gun == null or not is_instance_valid(_gun):
		return
	_rest_pose()
	_apply()
	if was and natural:
		reload_finished.emit()


func _rest_pose() -> void:
	_g_pos = Vector3.ZERO
	_g_rot = Vector3.ZERO
	_l = _l_rest
	_r = _r_rest
	_mag_off = Vector3.ZERO
	_mag_vis = _mag_baked
	_slide_z = 0.0
	_prop_vis = false


func _pose(t: float) -> void:
	_rest_pose()
	var p := clampf(t / _dur, 0.0, 1.0)
	match _style:
		"pistol":
			_pose_mag(p, 0.3, [0.14, 0.27, 0.4, 0.46, 0.72], 0.0)
		"rifle":
			_pose_mag(p, 0.4, [0.1, 0.22, 0.38, 0.44, 0.72], 0.04)
		"bolt":
			_pose_bolt(p)
		"shell":
			_pose_shell(t)
	_apply()


func _apply() -> void:
	_gun.position = _g_pos
	_gun.rotation = _g_rot
	_hand_l.position = _l
	_hand_r.position = _r
	_place_arm(_arm_l, _sleeve_l, _l, ANCHOR_L)
	_place_arm(_arm_r, _sleeve_r, _r, ANCHOR_R)
	if _mag != null:
		_mag.position = _mag_rest + _mag_off
		_mag.visible = _mag_vis
	if _slide != null:
		_slide.position = Vector3(0.0, 0.0, _slide_z)
	if _prop != null:
		_prop.visible = _prop_vis
		_prop.position = _prop_pos


# ------------------------------------------------------------------ reload poses

## Magazine swap. `ts` = [grab done, mag out, mag gone, new mag in hand, seated] as progress values.
func _pose_mag(p: float, cant: float, ts: Array, lift: float) -> void:
	var grab := _mag_rest + (_p["grab_off"] as Vector3)
	var out := grab + Vector3(0.0, -0.13, 0.03)
	var pouch := grab + Vector3(-0.13, -0.24, 0.14)
	var under := grab + Vector3(0.0, -0.15, 0.02)
	var t_grab: float = ts[0]
	var t_out: float = ts[1]
	var t_gone: float = ts[2]
	var t_new: float = ts[3]
	var t_seat: float = ts[4]
	var l := _l_rest
	l = l.lerp(grab, smoothstep(0.0, t_grab, p))
	l = l.lerp(out, smoothstep(t_grab, t_out, p))
	l = l.lerp(pouch, smoothstep(t_out, t_new - 0.01, p))
	l = l.lerp(under, smoothstep(t_new + 0.04, t_seat - 0.1, p))
	l = l.lerp(grab, smoothstep(t_seat - 0.1, t_seat, p))
	# tilt the gun toward the mag well while the left hand works, and a small seat bump
	_g_rot.z = cant * (smoothstep(0.0, t_grab, p) - smoothstep(0.8, 0.95, p))
	_g_rot.x = lift * (smoothstep(0.0, t_grab, p) - smoothstep(0.8, 0.95, p))
	_g_rot.x -= 0.06 * sin(PI * clampf((p - (t_seat - 0.04)) / 0.08, 0.0, 1.0))
	# magazine: follows the hand out, falls away, reappears in the hand, rides it up and seats
	var vis := true
	var off := Vector3.ZERO
	if p < t_grab:
		off = Vector3.ZERO
	elif p < t_out:
		off = l - grab
	elif p < t_gone:
		var f := (p - t_out) / (t_gone - t_out)
		off = (out - grab) + Vector3(0.0, -1.2 * f * f, 0.25 * f)
		vis = f < 1.0 and _mag_baked
	elif p < t_new:
		vis = false
	elif p < t_seat:
		off = l - grab
	_mag_off = off
	_mag_vis = vis or (_mag_baked and p >= t_seat)
	if not _mag_baked:
		_mag_vis = p >= t_new and p < t_seat + 0.05
		if _p.has("clip_file"):
			_mag_vis = _mag_vis or (p >= t_grab and p < t_gone)   # the clip the hand pulls out of the fused mesh
	# after seating: charge handle / slide rack when nothing was chambered, else just return
	var hand_pos: Vector3 = _p["slide_pos"] if _style == "pistol" else _p["charge_pos"]
	var travel: float = _p["slide_travel"]
	if _rack:
		l = l.lerp(hand_pos, smoothstep(0.76, 0.84, p))
		l = l.lerp(hand_pos + Vector3(0.0, 0.0, travel), smoothstep(0.84, 0.9, p))
		l = l.lerp(hand_pos, smoothstep(0.9, 0.93, p))
		l = l.lerp(_l_rest, smoothstep(0.93, 1.0, p))
		_slide_z = travel * (smoothstep(0.84, 0.9, p) - smoothstep(0.9, 0.93, p))
	else:
		l = l.lerp(_l_rest, smoothstep(0.78, 1.0, p))
	_l = l


func _pose_bolt(p: float) -> void:
	var bolt: Vector3 = _p["bolt_hand"]
	var port: Vector3 = _p["port"]
	var travel: float = _p["slide_travel"]
	var pouch := port + Vector3(-0.14, -0.25, 0.12)
	var above := port + Vector3(0.0, 0.06, 0.0)
	var hover := port + Vector3(-0.02, 0.08, 0.02)
	_g_rot.z = 0.15 * (smoothstep(0.0, 0.15, p) - smoothstep(0.85, 1.0, p))
	var r := _r_rest
	r = r.lerp(bolt, smoothstep(0.0, 0.1, p))
	r = r.lerp(bolt + Vector3(0.0, 0.025, 0.0), smoothstep(0.1, 0.18, p))
	r = r.lerp(bolt + Vector3(0.0, 0.025, travel), smoothstep(0.18, 0.32, p))
	r = r.lerp(bolt + Vector3(0.0, 0.025, 0.0), smoothstep(0.7, 0.82, p))
	r = r.lerp(bolt, smoothstep(0.82, 0.86, p))
	r = r.lerp(_r_rest, smoothstep(0.88, 1.0, p))
	_r = r
	_slide_z = travel * (smoothstep(0.18, 0.32, p) - smoothstep(0.7, 0.82, p))
	var l := _l_rest
	l = l.lerp(pouch, smoothstep(0.1, 0.3, p))
	l = l.lerp(above, smoothstep(0.3, 0.52, p))
	l = l.lerp(port + Vector3(0.0, 0.02, 0.0), smoothstep(0.52, 0.62, p))
	l = l.lerp(hover, smoothstep(0.62, 0.72, p))
	l = l.lerp(_l_rest, smoothstep(0.8, 0.97, p))
	_l = l
	_prop_vis = p >= 0.3 and p < 0.6
	_prop_pos = l + Vector3(0.0, 0.025, 0.0)


## Tube gun. `t` in seconds: `_rounds` shell cycles of round_time each, then the pump (chamber_time).
func _pose_shell(t: float) -> void:
	var port: Vector3 = _p["port"]
	var pump: float = _p["slide_travel"]
	var rt := maxf(_wd.round_time, 0.05)
	var hover := port + Vector3(-0.03, -0.11, 0.06)
	var pouch := port + Vector3(-0.16, -0.12, 0.2)
	var roll := smoothstep(0.0, 0.2, t) - smoothstep(_dur - 0.2, _dur, t)
	_g_rot.z = 0.35 * roll
	_g_rot.x = 0.1 * roll
	var load_end := float(_rounds) * rt
	var l := _l_rest
	if _rounds > 0 and t < load_end:
		var i := mini(int(t / rt), _rounds - 1)
		var f := (t - float(i) * rt) / rt
		var from := _l_rest if i == 0 else hover
		var to := hover if (i < _rounds - 1 or _rack) else _l_rest
		l = from.lerp(pouch, smoothstep(0.0, 0.32, f))
		l = l.lerp(port, smoothstep(0.32, 0.66, f))
		l = l.lerp(to, smoothstep(0.78, 1.0, f))
		_prop_vis = f >= 0.32 and f < 0.72
		_prop_pos = l + Vector3(0.0, 0.03, 0.0)
	elif _rack:
		var f2 := clampf((t - load_end) / maxf(_dur - load_end, 0.01), 0.0, 1.0)
		var from2 := hover if _rounds > 0 else _l_rest
		l = from2.lerp(_l_rest, smoothstep(0.0, 0.3, f2))
		l = l.lerp(_l_rest + Vector3(0.0, 0.0, pump), smoothstep(0.3, 0.55, f2))
		l = l.lerp(_l_rest, smoothstep(0.55, 0.85, f2))
		_slide_z = pump * (smoothstep(0.3, 0.55, f2) - smoothstep(0.55, 0.85, f2))
	_l = l
