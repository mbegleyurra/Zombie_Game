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
##
## SWAPPING WEAPON MODELS (e.g. the ITHappy Weapons Free pack) IS A DATA CHANGE, NOT A CODE CHANGE.
## Grip and reload logic never read mesh names; they read per-weapon anchor data in gun-local metres
## (gun points -Z, origin at the rear of the receiver, +Y up):
##   grip_r / grip_l      resting palm positions of the right (trigger) and left (support) hand
##   mag_pos / grab_off   top of the magazine, and where under it the left hand grabs
##   slide_pos / charge_pos / bolt_hand / port   where the hand goes to rack, charge, work the bolt, load a shell
##   slide_travel         how far the moving part slides back
##   clip_file / clip_h / clip_scale   optional separate magazine mesh shown while the hand handles it
## Two sources feed them: the TUNING table below (hand-tuned, per GunMesh model key) and the "vm_profile"
## meta on the gun root, which GunMesh.build derives from a model's own geometry. To add a model, give its
## GunMesh entry (or its TUNING entry) these anchors; nothing in this file or in WeaponController changes.
## Hand and arm size are tied to the camera, not the gun, so they stay readable with any model.

signal reload_finished

const SCRIPT_PATH := "res://scripts/weapons/viewmodel.gd"
const SKIN := Color(0.86, 0.66, 0.52)
const SKIN_TIP := Color(0.78, 0.58, 0.45)   ## knuckles and fingertips, a shade darker so the hand reads as a hand
const SLEEVE := Color(0.2, 0.26, 0.2)
const SLEEVE_CUFF := Color(0.3, 0.36, 0.28)
const MAG_COLOR := Color(0.1, 0.1, 0.11)
const SHELL_COLOR := Color(0.72, 0.1, 0.08)
const CLIP_COLOR := Color(0.7, 0.55, 0.2)
const ANCHOR_R := Vector3(0.55, -0.5, 0.4)     ## gun-local shoulder points the forearms stretch to (right one angles out so it clears the stock)
const ANCHOR_L := Vector3(-0.42, -0.4, 0.5)
const GRIP_MIN_Y := -0.1   ## lowest gun-local y a trigger-hand palm may sit at (keeps it on screen)
const HOLD_BELOW := 0.045    ## rifle palms sit at most this far above the bottom of the gun's bounds
const CHARGE_SIDE := 0.07    ## rifle charging hand sits this far left of the gun's centre line
const BOLT_SIDE := 0.11      ## bolt-gun clip loading point sits this far left of the gun's centre line
const VIEW_MARGIN := 0.62    ## a palm may reach this share of the way from view centre to the bottom edge (leaves room for the forearm to show)
const ARM_W_R := 0.034       ## right forearm: it runs nearer the camera, so it is thinner to read the same width as the left
const ARM_W := 0.045         ## forearm thickness; the first-person camera sees them at 0.4-0.8 m, so they are life-size
const HAND_SCALE := 0.8      ## palm is 0.088 * this wide, small enough that the gun stays readable between the hands
const MIN_SEP := 0.15        ## the two palms never get closer than this (metres); a scaled palm is about 7 cm wide
const MIN_SEP_PX := 126.0    ## the palms stay at least this far apart on screen (px at 720p; the tests demand 100)
const PISTOL_GRIP_X := 0.04   ## gun-local x of the pistol trigger-hand palm (grip half-width plus half a rolled palm)
const PISTOL_ROLL := -70.0    ## degrees the pistol trigger hand rolls so the palm meets the grip from the side
const WRIST_LEN := 0.11
const MIN_DURATION := 0.05
const GUN_GRIP_Z := -0.03    ## gun-local z of the trigger-hand grip (same as GunMesh.GRIP_Z)
## sniper_rifle_001 (the pack's bolt gun), gun-local, measured from the mesh (vertices with x > 0.02 are the bolt handle: x 0.021 to 0.048, y -0.021 to 0.012, z -0.261 to -0.229)
const BOLT_KNOB := Vector3(0.046, -0.005, -0.245)   ## centre of the bolt knob at rest
const BOLT_LOAD := Vector3(-0.07, 0.03, -0.21)      ## support palm while it pushes the clip into the receiver (fingers reach the loading opening at z -0.27)
const ARM_REF_DEPTH := 0.4   ## camera distance (m) at which an arm has its true width; farther hands get a wider arm
const REST_ROLL_L := 70.0    ## degrees the support hand rolls at rest: palm flat on the left face of the handguard (or pistol grip), fingers curled under and round to the right
const WRAP_GAP := 0.016      ## support palm centre sits this far left of the handguard's left face at rest (half a rolled palm's thickness)
const BORE_REACH := 0.04     ## a forend section reaches at least this far below the bore (GunMesh.MUZZLE_Y); a thinner one is bare barrel / scope
const SECTION_HALF := 0.025  ## half the thickness (z) of the mesh slice _section_at measures
const FOREND_INSET := 0.01   ## when the rest grip is pulled back onto the forend, the palm centre sits this far inside its front end
const CUP_DROP := 0.01       ## pistol support palm sits this far below the trigger palm, cupping the grip under it (kept out of the view clamp)
const MAG_LIFT_FADE := 0.07  ## a held magazine follows the palm-separation shove fully this far from its seat, none at the seat
const CYL_SWING := 75.0      ## degrees a revolver cylinder swings out to the left on its crane
const REV_ROLL_R := Vector3(0.03, -0.03, 0.035)   ## trigger palm offset on the grip while it rolls the revolver out for the speedloader
const SPEEDLOADER_COLOR := Color(0.72, 0.58, 0.25)

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
var _slide_rest: Transform3D = Transform3D.IDENTITY
var _slide_kind: String = ""   ## GunMesh "MovingPart" kind (cylinder swings, everything else slides along Z)
var _bolt_proxy: MeshInstance3D  ## visible bolt handle for a fused bolt gun
var _prop: MeshInstance3D   ## shell or clip held in the left hand
var _l_rest: Vector3 = Vector3.ZERO
var _r_rest: Vector3 = Vector3.ZERO
var _revolver: bool = false   ## pistol-family gun with a swing-out cylinder: speedloader reload instead of a magazine swap
var _mag_seated: bool = false  ## the magazine is drawn in the well at rest (captured gun parts or a seated pack clip)
var _mag_top: int = -1         ## last draw-on-top state written to a seated clip (-1 = never)

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
var _cyl: float = 0.0      ## revolver cylinder swing, 0 closed .. 1 fully out
var _sep_w: float = 1.0    ## how much the palm-separation safety nets apply (a pistol cup at rest lets the palms touch)
var _prop_vis: bool = false
var _prop_pos: Vector3 = Vector3.ZERO
var _roll_l: float = 0.0   ## degrees the support hand rolls about the gun's axis
var _yaw_l: float = 0.0    ## degrees the support hand turns about the gun's up axis


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
	if _style == "pistol":
		_hand_r.rotation_degrees.z = PISTOL_ROLL
	add_child(_hand_r)
	add_child(_hand_l)
	_arm_r = _build_arm("Arm_R", ARM_W_R)
	_arm_l = _build_arm("Arm_L", ARM_W)
	_sleeve_r = _arm_r.get_node("Sleeve") as MeshInstance3D
	_sleeve_l = _arm_l.get_node("Sleeve") as MeshInstance3D
	add_child(_arm_r)
	add_child(_arm_l)
	var slide_key := ""
	_revolver = _style == "pistol" and bool(_p.get("revolver", false))
	match _style:
		"pistol", "rifle" when _revolver:
			_mag = _make_speedloader(gun)
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
			_mag_seated = _mag_baked or bool(_p.get("clip_seated", false))
			slide_key = "slide_region" if _style == "pistol" else "charge_region"
		"bolt":
			slide_key = "bolt_region"
			_prop = _make_prop(false)
		"shell":
			slide_key = "pump_region"
			_prop = _make_prop(true)
	var moving := gun.get_node_or_null("MovingPart") as Node3D
	if moving != null:
		# the pack gun's own moving part (GunMesh built it: drum, pump, charging handle or the cut-out bolt)
		_slide = moving
		_slide_kind = str(moving.get_meta("kind", ""))
	elif slide_key != "" and _p.has(slide_key):
		_slide = Node3D.new()
		_slide.name = "Slide"
		gun.add_child(_slide)
		_capture(_p[slide_key], _style != "bolt", _slide)
	if _slide != null:
		_slide_rest = _slide.transform
	if _style == "bolt" and _slide != null and _slide.get_child_count() == 0:
		# A fused pack gun has no separate bolt: a dark handle rides the bolt hand so the cycle is visible.
		_bolt_proxy = _box(_slide, Vector3(0.022, 0.022, 0.05), _p["bolt_hand"], MAG_COLOR, Vector3.ZERO, 2)
		_bolt_proxy.name = "BoltProxy"
		_bolt_proxy.visible = false
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
	# ITHappy pack guns are one fused mesh: no box parts to capture, and hand/mag points come from the
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
	# Keep the trigger hand inside the first-person frame: a deep derived grip (long pistol grip, big
	# magazine well) would otherwise put the palm below the bottom edge of the view.
	var gr: Vector3 = p["grip_r"]
	gr.y = maxf(gr.y, GRIP_MIN_Y)
	# Both palms hold the underside of the gun, not its middle: a long bolt rifle's derived grips sit level with
	# the receiver, so the hands (drawn over the gun) would hide it. Pistols keep their hand-tuned grip height.
	if not pistol and p.has("extent"):
		var low_y: float = (p["extent"]["lo"] as Vector3).y
		gr.y = minf(gr.y, low_y + HOLD_BELOW)
		var gl2: Vector3 = p["grip_l"]
		gl2.y = minf(gl2.y, low_y + HOLD_BELOW + 0.015)
		p["grip_l"] = gl2
	p["grip_r"] = gr
	_dflt(p, "grab_off", Vector3(0.0, -0.02, 0.0) if pistol else Vector3(0.0, -0.09, 0.0))
	_dflt(p, "slide_pos", Vector3(0.0, 0.052, -0.03))
	_dflt(p, "charge_pos", Vector3(0.0, 0.11, -0.03))
	_dflt(p, "bolt_hand", Vector3(0.07, 0.03, -0.05))
	_dflt(p, "port", Vector3(0.0, 0.07, -0.12) if style_name == "bolt" else Vector3(0.0, -0.05, -0.06))
	_dflt(p, "slide_travel", 0.05 if pistol else 0.06)
	_dflt(p, "proxy_size", Vector3(0.026, 0.095, 0.04) if pistol else Vector3(0.04, 0.13, 0.06))
	_dflt(p, "proxy_center", Vector3(0.0, 0.058, 0.0) if pistol else Vector3(0.0, -0.07, 0.0))
	_dflt(p, "proxy_tilt", -12.0 if pistol else 0.0)
	# A palm is about 9 cm wide, so the support hand must work a point well clear of the trigger hand or the
	# two merge into one mass: rifles charge forward of the grip, tube guns load forward of it, and a pistol
	# mag is fetched from under the front of the grip with the support hand resting forward and low.
	if style_name == "rifle":
		var cp: Vector3 = p["charge_pos"]
		if p.has("handle"):
			cp = p["handle"]   ## the gun's real charging handle / bolt knob (GunMesh "MovingPart")
		else:
			cp.z = minf(cp.z, GUN_GRIP_Z - 0.2)
		p["charge_pos"] = cp
		var rgo: Vector3 = p["grab_off"]
		p["grab_off"] = Vector3(rgo.x - 0.02, rgo.y + 0.05, rgo.z - 0.02)   ## fist on the magazine's left face, mid-height, so the hand meets the well
	if style_name == "shell":
		# shotgun_001's loading gate is the underside of the receiver (mesh: bottom y about -0.05, z -0.21 to -0.09);
		# the fist cannot sit on the gate itself: the palm must stay MIN_SEP (0.15 m) from the trigger palm, which puts
		# it at z = GUN_GRIP_Z - MIN_SEP, and the fingers (and the shell) reach the gate at z -0.13 from there
		p["port"] = Vector3(0.0, -0.05, GUN_GRIP_Z - MIN_SEP)
	if style_name == "bolt" and gun.has_meta("vm_profile"):
		# measured from the sniper_rifle_001 mesh: the right palm works the real bolt knob, the support palm
		# pushes the clip into the receiver opening ahead of it (the derived port at z -0.21 was the wrong spot)
		p["bolt_hand"] = BOLT_KNOB + Vector3(0.0, 0.015, 0.015)
		p["port"] = BOLT_LOAD
		p["slide_travel"] = 0.05
	elif style_name == "bolt":
		var bp: Vector3 = p["port"]
		bp.z = minf(bp.z, GUN_GRIP_Z - 0.18)   ## clip goes in ahead of the bolt hand
		bp.x = minf(bp.x, -BOLT_SIDE)           ## and from the left, so the support forearm does not lie across the receiver
		bp.y = minf(bp.y, 0.03)                 ## low enough that the support forearm is not a tall slab over the gun
		p["port"] = bp
		var bh: Vector3 = p["bolt_hand"]
		bh.x = minf(bh.x, 0.03)
		bh.y = minf(bh.y, 0.0)                  ## the bolt hand rides the bolt, level with the receiver, not floating above it
		p["bolt_hand"] = bh
	if not pistol:
		# the support hand rests on the handguard, near enough to the camera that its forearm reads as thick as in a reload
		var gl3: Vector3 = p["grip_l"]
		gl3.z = maxf(gl3.z, GUN_GRIP_Z - 0.31)
		gl3.x = -0.012
		# a short forend (sniper_rifle_001 ends at z -0.30, ahead of it only barrel and scope): pull the rest grip back
		# to the last z where the section still reaches below the bore, so the fist wraps wood, not the barrel
		var sec0 := _section_at(gun, gl3.z)
		if not sec0.is_empty() and float(sec0["lo"]) > GunMesh.MUZZLE_Y - BORE_REACH:
			var z := gl3.z
			while z < GUN_GRIP_Z - MIN_SEP:
				var s1 := _section_at(gun, z)
				if not s1.is_empty() and float(s1["lo"]) <= GunMesh.MUZZLE_Y - BORE_REACH:
					break
				z += 0.005
			gl3.z = minf(z + SECTION_HALF + FOREND_INSET, GUN_GRIP_Z - MIN_SEP)   ## the slab caught the forend's front end SECTION_HALF ahead of z
		# wrapped round it: palm flat on the handguard's left face (rolled REST_ROLL_L), fingers curled under it, set
		# from the model's own cross-section at the rest z (pump forend included)
		var sec := _section_at(gun, gl3.z)
		if not sec.is_empty():
			gl3.x = float(sec["left"]) - WRAP_GAP
			gl3.y = lerpf(float(sec["lo"]), float(sec["hi"]), 0.4)
		p["grip_l"] = gl3
	if pistol:
		if gun.has_meta("vm_profile") and not p.has("revolver"):
			p["proxy_center"] = Vector3(0.0, -0.048, 0.0)
			p["pull_proxy"] = true
		var go: Vector3 = p["grab_off"]
		p["grab_off"] = Vector3(go.x - 0.03, go.y - 0.02, go.z - 0.04)
		var pgr: Vector3 = p["grip_r"]
		p["grip_r"] = Vector3(maxf(pgr.x, PISTOL_GRIP_X), pgr.y, pgr.z)   ## palm on the right face of the grip, not on top of it
		# two-handed cup: support palm on the grip's left face just under the trigger palm, rolled REST_ROLL_L so its
		# fingers wrap the front of the grip over the trigger hand's fingers (the separation nets are off at rest)
		var r0: Vector3 = p["grip_r"]
		p["grip_l"] = Vector3(-PISTOL_GRIP_X * 0.8, r0.y - CUP_DROP, r0.z - 0.012)
		var sp: Vector3 = p["slide_pos"]
		p["slide_pos"] = Vector3(sp.x, sp.y, sp.z - 0.05)   ## rack from the front of the slide, clear of the trigger hand
		if p.has("revolver"):
			p["slide_pos"] = p["handle"]   ## the support thumb opens and closes the cylinder
			p["grab_off"] = Vector3(-0.01, 0.035, 0.015)   ## palm over the open cylinder, fingers down round the speedloader (height above the trigger palm keeps the separation net from shoving it off)
	return p


static func _dflt(p: Dictionary, k: String, v: Variant) -> void:
	if not p.has(k):
		p[k] = v


## Cross-section of the gun's own mesh in a thin slice at `z`: {"lo", "hi", "left"} gun-local ({} when empty).
func _section_at(gun: Node3D, z: float) -> Dictionary:
	var vs := PackedVector3Array()
	for c in gun.get_children():
		if c != self:
			GunMesh._collect_verts(c, Transform3D.IDENTITY, vs)
	var lo := INF
	var hi := -INF
	var left := 0.0
	for v in vs:
		if absf(v.z - z) < SECTION_HALF and absf(v.x) < 0.06:
			lo = minf(lo, v.y)
			hi = maxf(hi, v.y)
			left = minf(left, v.x)
	return {} if lo == INF else {"lo": lo, "hi": hi, "left": left}


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
	# a proxy that only exists while handled (fused pack gun) draws over the fist like the pack clip, or the palm hides it
	var mi := _box(pivot, sz, c, MAG_COLOR, Vector3(tilt, 0.0, 0.0), 0 if _mag_baked else 5)
	mi.name = "ProxyMag"


## Pack magazine: the clip .glb hangs below the pivot by its top (clip_h = top y above its origin), turned
## clip_yaw like the gun. The fused mesh keeps its own magazine, so this clip is only shown while handled.
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
	inst.rotation.y = float(_p.get("clip_yaw", 0.0))
	inst.position = Vector3(0.0, -float(_p["clip_h"]) * cs, 0.0)
	GunMesh.apply_pack_material(inst)
	if bool(_p.get("clip_seated", false)):
		_store_top_mats(inst, 5)   ## seated in the well it is part of the gun (depth tested); drawn on top only while handled
	else:
		_draw_on_top(inst, 5)
	pivot.add_child(inst)
	return true


## Keeps a depth-tested and a draw-on-top material on every mesh of a seated clip so _apply can switch them.
func _store_top_mats(n: Node, priority: int) -> void:
	var mi := n as MeshInstance3D
	if mi != null and mi.material_override is StandardMaterial3D:
		var m := (mi.material_override as StandardMaterial3D).duplicate() as StandardMaterial3D
		m.no_depth_test = true
		m.render_priority = priority
		mi.set_meta("mat_base", mi.material_override)
		mi.set_meta("mat_top", m)
	for c in n.get_children():
		_store_top_mats(c, priority)


func _set_mag_top(on: bool) -> void:
	if _mag == null or _mag_top == int(on):
		return
	_mag_top = int(on)
	for c in _mag.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if mi.has_meta("mat_top"):
			mi.material_override = mi.get_meta("mat_top" if on else "mat_base")


## Revolver: the speedloader (brass ring of rounds with a dark knob behind) the support hand brings to the swung-out
## cylinder. Its pivot rest (_mag_rest) is the seated spot: centred on the open drum, just behind its rear face.
func _make_speedloader(gun: Node3D) -> Node3D:
	var r: float = _p["cyl_radius"]
	var crane: Vector3 = (_p["handle"] as Vector3) - Vector3(0.0, r, 0.0)
	var a := deg_to_rad(CYL_SWING)
	_mag_rest = crane + Vector3(-r * sin(a), r * cos(a), r * 0.45 + 0.012)
	var pivot := Node3D.new()
	pivot.name = "Mag"
	pivot.position = _mag_rest
	gun.add_child(pivot)
	for part in [[r * 0.8, 0.022, 0.0, SPEEDLOADER_COLOR], [r * 0.25, 0.018, 0.019, MAG_COLOR]]:
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = part[0]
		cm.bottom_radius = part[0]
		cm.height = part[1]
		cm.radial_segments = 10
		cm.rings = 1
		mi.mesh = cm
		mi.rotation_degrees = Vector3(90.0, 0.0, 0.0)
		mi.position = Vector3(0.0, 0.0, part[2])
		mi.material_override = _mat(part[3], 5)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.name = "Speedloader" if part[2] == 0.0 else "SpeedloaderKnob"
		pivot.add_child(mi)
	pivot.visible = false
	return pivot


## The hands draw over the gun (no depth test), so a magazine the hand is working would vanish behind the
## fingers; the handled clip gets the same treatment at a higher priority so it reads as held in the palm.
func _draw_on_top(n: Node, priority: int) -> void:
	var mi := n as MeshInstance3D
	if mi != null and mi.material_override is StandardMaterial3D:
		var m := (mi.material_override as StandardMaterial3D).duplicate() as StandardMaterial3D
		m.no_depth_test = true
		m.render_priority = priority
		mi.material_override = m
	for c in n.get_children():
		_draw_on_top(c, priority)


func _make_prop(is_shell: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "HeldShell" if is_shell else "HeldClip"
	if is_shell:
		var cm := CylinderMesh.new()
		cm.top_radius = 0.014
		cm.bottom_radius = 0.014
		cm.height = 0.07
		cm.radial_segments = 8
		cm.rings = 1
		mi.mesh = cm
		mi.rotation_degrees = Vector3(90.0, 0.0, 0.0)
		mi.material_override = _mat(SHELL_COLOR, 5)   ## drawn over the hand and the gun, like the magazine clip: it must be seen in the fingers
	else:
		var bm := BoxMesh.new()
		bm.size = Vector3(0.03, 0.014, 0.07)
		mi.mesh = bm
		mi.material_override = _mat(CLIP_COLOR, 5)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	add_child(mi)
	return mi


static func _mat(color: Color, ontop_priority: int = 0) -> StandardMaterial3D:
	var key := color.to_html() + ("" if ontop_priority == 0 else "_top%d" % ontop_priority)
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.85
	if ontop_priority != 0:
		# Hands and forearms always draw over the gun: a fused gun model (stock, receiver, magazine)
		# would otherwise hide the palm and fingers from the camera. Higher priority draws later.
		m.no_depth_test = true
		m.render_priority = ontop_priority
	_mats[key] = m
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, color: Color, rot_deg: Vector3 = Vector3.ZERO, ontop_priority: int = 0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = _mat(color, ontop_priority)
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## side +1 = right hand, -1 = left. Origin sits at the palm. Life-size (about 9 cm across) so it reads
## at arm's length; fingers curl down and forward round the grip, the thumb lies along the side.
func _build_hand(side: float) -> Node3D:
	var h := Node3D.new()
	h.name = "Hand_R" if side > 0.0 else "Hand_L"
	h.scale = Vector3.ONE * HAND_SCALE
	_box(h, Vector3(0.088, 0.042, 0.095), Vector3.ZERO, SKIN, Vector3.ZERO, 3).name = "Palm"
	# four separate fingers (index to little) that curl down and forward, each with a darker tip
	var lengths := [0.056, 0.062, 0.058, 0.048]
	for i in range(4):
		var fx := (float(i) - 1.5) * 0.021
		var fl: float = lengths[i]
		_box(h, Vector3(0.019, 0.03, fl), Vector3(fx, -0.034, -0.032 - fl * 0.5), SKIN, Vector3(12.0, 0.0, 0.0), 3).name = "Finger%d" % i
		_box(h, Vector3(0.018, 0.022, 0.028), Vector3(fx, -0.058, -0.034 - fl - 0.008), SKIN_TIP, Vector3(35.0, 0.0, 0.0), 4).name = "FingerTip%d" % i
	_box(h, Vector3(0.024, 0.026, 0.075), Vector3(-side * 0.05, 0.004, -0.03), SKIN, Vector3(0.0, -side * 12.0, 0.0), 4).name = "Thumb"
	_box(h, Vector3(0.084, 0.02, 0.022), Vector3(0.0, 0.026, -0.046), SKIN_TIP, Vector3.ZERO, 4).name = "Knuckles"
	return h


## Forearm: a skin wrist, a darker sleeve cuff, and a sleeve that stretches to the shoulder anchor (+Z of the node).
func _build_arm(arm_name: String, w: float) -> Node3D:
	var a := Node3D.new()
	a.name = arm_name
	_box(a, Vector3(w + 0.01, w + 0.01, WRIST_LEN), Vector3(0.0, 0.0, WRIST_LEN * 0.5), SKIN, Vector3.ZERO, 2).name = "Wrist"
	_box(a, Vector3(w + 0.012, w + 0.012, 0.03), Vector3(0.0, 0.0, WRIST_LEN + 0.015), SLEEVE_CUFF, Vector3.ZERO, 2).name = "Cuff"
	_box(a, Vector3(w, w, 1.0), Vector3.ZERO, SLEEVE, Vector3.ZERO, 1).name = "Sleeve"
	return a


func _place_arm(arm: Node3D, sleeve: MeshInstance3D, hand: Vector3, anchor: Vector3) -> void:
	var d := anchor - hand
	var dist := d.length()
	if dist < 0.01:
		return
	var dir := d / dist
	# a far hand (support hand at rest, out on the handguard) would draw a thinner arm than a near one in a reload:
	# widen the arm with distance from the camera so its thickness on screen stays the same
	var widen := 1.0
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != null:
		var depth := -(cam.global_transform.affine_inverse() * (global_transform * hand)).z
		widen = clampf(depth / ARM_REF_DEPTH, 1.0, 1.8)
	arm.transform = Transform3D(Basis.looking_at(-dir, Vector3.UP) * Basis.from_scale(Vector3(widen, widen, 1.0)), hand)
	# a far hand shows mostly sleeve; stretch the bare wrist with the same distance factor so the forearm reads as
	# skin (as it does in a reload, when the hand is near the camera), capped so the sleeve never vanishes
	var wlen := minf(WRIST_LEN * widen * 1.6, dist * 0.7)
	var wrist := arm.get_node("Wrist") as Node3D
	var cuff := arm.get_node("Cuff") as Node3D
	wrist.scale = Vector3(1.0, 1.0, wlen / WRIST_LEN)
	wrist.position = Vector3(0.0, 0.0, wlen * 0.5)
	cuff.position = Vector3(0.0, 0.0, wlen + 0.015)
	var slen := maxf(dist - wlen, 0.02)
	sleeve.scale = Vector3(1.0, 1.0, slen)
	sleeve.position = Vector3(0.0, 0.0, wlen + slen * 0.5)


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
	_mag_vis = _mag_seated
	_slide_z = 0.0
	_cyl = 0.0
	_sep_w = 0.0 if _style == "pistol" else 1.0
	_prop_vis = false
	_roll_l = REST_ROLL_L
	_yaw_l = 0.0


func _pose(t: float) -> void:
	_rest_pose()
	var p := clampf(t / _dur, 0.0, 1.0)
	match _style:
		"pistol" when _revolver:
			_pose_revolver(p)
		"pistol":
			_pose_mag(p, 0.3, [0.1, 0.2, 0.3, 0.32, 0.8], 0.0)
		"rifle":
			_pose_mag(p, 0.4, [0.08, 0.18, 0.3, 0.32, 0.8], 0.04)
		"bolt":
			_pose_bolt(p)
		"shell":
			_pose_shell(t)
	# the support hand rests wrapped round the handguard / grip (rolled) and squares up while it works the gun; a
	# pistol cup lets the palms touch, so the separation nets fade in as the hand leaves the grip
	var at_rest := 1.0 - (smoothstep(0.0, 0.1, p) - smoothstep(0.92, 1.0, p))
	_roll_l = REST_ROLL_L * at_rest
	if _style == "pistol":
		_sep_w = 1.0 - at_rest
	_apply()


## Keeps a gun-local hand position above the bottom edge of the first-person view whatever the gun is
## doing (roll, pitch, aim-down-sights). No camera in the tree (a bare unit test) = no clamp.
func _clamp_to_view(local_pos: Vector3) -> Vector3:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return local_pos
	var gx := global_transform
	var cx := cam.global_transform
	var c := cx.affine_inverse() * (gx * local_pos)
	var depth := -c.z
	if depth <= cam.near:
		return local_pos
	var y_min := -depth * tan(deg_to_rad(cam.fov) * 0.5) * VIEW_MARGIN
	if c.y >= y_min:
		return local_pos
	c.y = y_min
	return gx.affine_inverse() * (cx * c)


## Safety net: keeps the support palm at least MIN_SEP from the trigger palm by sliding it sideways (left)
## and forward, never down, so the hands never merge and the palm stays on screen.
func _separate(l: Vector3, r: Vector3) -> Vector3:
	var d := l - r
	var need_sq := MIN_SEP * MIN_SEP - d.y * d.y
	if need_sq <= 0.0 or Vector2(d.x, d.z).length_squared() >= need_sq:
		return l
	var flat := Vector2(d.x, d.z)
	var dir := flat.normalized() + Vector2(-0.7, -0.2) if flat.length() > 0.001 else Vector2(-1.0, -0.3)
	dir = dir.normalized() * sqrt(need_sq)
	return Vector3(r.x + dir.x, l.y, r.z + dir.y)


## Screen-space twin of _separate: a gun that points along the view axis folds a forward gap into a few pixels,
## so the support palm slides sideways (camera-left) until the two palms are MIN_SEP_PX apart in the frame.
## No camera in the tree (a bare unit test) = unchanged. Scales with the viewport height so it holds at any size.
func _separate_px(l: Vector3, r: Vector3) -> Vector3:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null or get_viewport().get_visible_rect().size.y <= 0.0:
		return l
	var need := MIN_SEP_PX * get_viewport().get_visible_rect().size.y / 720.0
	var gx := global_transform
	var cx := cam.global_transform
	var pr := cam.unproject_position(gx * r)
	var c := cx.affine_inverse() * (gx * l)
	if -c.z <= cam.near:
		return l
	if cam.unproject_position(cx * c).distance_to(pr) >= need:
		return l
	# walk left in 1 cm steps until far enough, then bisect the last step so the result is continuous in the
	# gun's position (a quantised step let sub-millimetre sway change where the palm came to rest)
	var hi := c.x
	var lo := c.x
	for _i in range(40):
		lo = hi
		hi -= 0.01
		c.x = hi
		if cam.unproject_position(cx * c).distance_to(pr) >= need:
			break
	for _j in range(10):
		c.x = (lo + hi) * 0.5
		if cam.unproject_position(cx * c).distance_to(pr) >= need:
			hi = c.x
		else:
			lo = c.x
	c.x = hi
	return gx.affine_inverse() * (cx * c)


func _apply() -> void:
	_gun.position = _g_pos
	_gun.rotation = _g_rot
	# A hand never dips below the bottom of the frame: magazine, shell and clip trips are limited in view space.
	var hr := _clamp_to_view(_r)
	var hl_raw := _clamp_to_view(_l)
	var hl := _separate_px(_separate(_clamp_to_view(_separate(_l, hr)), hr), hr)
	if _sep_w < 1.0:
		hl = hl_raw.lerp(hl, _sep_w)
	var lift := hl - _l   ## what a held magazine / shell / clip is moved with the hand
	_hand_l.position = hl
	_hand_l.rotation_degrees.z = _roll_l
	_hand_l.rotation_degrees.y = _yaw_l
	_hand_r.position = hr
	_place_arm(_arm_l, _sleeve_l, hl, ANCHOR_L)
	_place_arm(_arm_r, _sleeve_r, hr, ANCHOR_R)
	if _mag != null:
		# in transit the magazine rides the fist (shove included); closing on the well it converges on the seat, so a
		# shove the nets keep applying near the trigger hand can never pop it in at the seat
		_mag.position = _mag_rest + _mag_off + lift * smoothstep(0.0, MAG_LIFT_FADE, _mag_off.length())
		_mag.visible = _mag_vis
		_set_mag_top(_mag_off != Vector3.ZERO)
	if _slide != null:
		if _slide_kind == "cylinder":
			_slide.transform = _slide_rest * Transform3D(Basis(Vector3.BACK, deg_to_rad(CYL_SWING) * _cyl), Vector3.ZERO)
		else:
			_slide.transform = _slide_rest.translated(Vector3(0.0, 0.0, _slide_z))
	if _bolt_proxy != null:
		_bolt_proxy.visible = _playing and _slide_z > 0.002
	if _prop != null:
		_prop.visible = _prop_vis
		_prop.position = _prop_pos + lift


# ------------------------------------------------------------------ reload poses

## Magazine swap. `ts` = [grab done, mag out of the well, hand at the pouch, new mag leaves the pouch, seated].
## The fist holds a magazine from the grab to the seat with no gap: it pulls the old one, carries it down to the
## pouch, swaps it there and brings the new one up to just under the well, then pushes it home. A held magazine's
## top always sits exactly grab_off above the palm, so it closes on the well as the hand does and seats when the
## palm reaches the grab point (no hold offset left to pop out at the seat).
func _pose_mag(p: float, cant: float, ts: Array, lift: float) -> void:
	var grab := _mag_rest + (_p["grab_off"] as Vector3)
	var out := grab + Vector3(-0.015, -0.055, -0.01)   ## the old mag pulled clear of the well
	var pouch := grab + Vector3(-0.04, -0.085, -0.01)   ## down and out to the left, never back toward the trigger hand
	var under := grab + Vector3(-0.005, -0.03, 0.0)     ## new mag lined up under the well, its top just entering it
	var t_grab: float = ts[0]
	var t_out: float = ts[1]
	var t_stow: float = ts[2]
	var t_new: float = ts[3]
	var t_seat: float = ts[4]
	var t_under := t_new + 0.24   ## then a steady push home to the seat
	var l := _l_rest
	l = l.lerp(grab, smoothstep(0.0, t_grab, p))
	l = l.lerp(out, smoothstep(t_grab, t_out, p))
	l = l.lerp(pouch, smoothstep(t_out, t_stow, p))
	l = l.lerp(under, smoothstep(t_new, t_under, p))
	l = l.lerp(grab, smoothstep(t_under, t_seat, p))
	# tilt the gun toward the mag well while the left hand works, and a small seat bump
	_g_rot.z = cant * (smoothstep(0.0, t_grab, p) - smoothstep(0.86, 0.97, p))
	_g_rot.x = lift * (smoothstep(0.0, t_grab, p) - smoothstep(0.86, 0.97, p))
	_g_rot.x -= 0.06 * sin(PI * clampf((p - (t_seat - 0.04)) / 0.08, 0.0, 1.0))
	# the trigger hand stays on the grip for the whole reload (small settle, under 3 cm); the support hand is
	# what keeps clear of it (_separate), so the gun is never held off its grip
	var at_well := smoothstep(0.0, t_grab, p) - smoothstep(0.86, 0.97, p)
	var settle := sin(PI * smoothstep(t_out, t_seat, p))   ## tightens round the grip while the new mag goes in
	var out_x := 0.0 if _style == "pistol" else 0.035   ## a rifle grip hand eases a little right so the support hand can reach the well without sliding off it (the held magazine draws over the fingers)
	_r = _r_rest + Vector3(out_x, -0.012, 0.012) * at_well + Vector3(0.0, 0.008, -0.012) * settle
	_g_pos.y = (0.045 if _style == "pistol" else 0.03) * at_well   ## the gun rises a little so the well stays above the bottom-of-view limit on the support palm
	# magazine: seated, then in the fist from the grab to the seat (offset = palm - grab point, continuous at both ends)
	_mag_off = l - grab if p > t_grab and p < t_seat else Vector3.ZERO
	_mag_vis = _mag_seated or (p >= t_grab and p < t_seat + 0.03)
	# after seating: charge handle / slide rack when nothing was chambered, else just return
	var hand_pos: Vector3 = _p["slide_pos"] if _style == "pistol" else _p["charge_pos"]
	var travel: float = _p["slide_travel"]
	if _rack:
		var hp := hand_pos
		if _style != "pistol" and _p.has("handle"):
			hp = hand_pos + Vector3(-0.015, 0.05, 0.0)   ## palm over the receiver, fingers hooked down onto the real handle / knob
		elif _style != "pistol":
			# the charging hand works from the left side, just above the receiver, so the forearm never lies across it
			hp = Vector3(-CHARGE_SIDE, hand_pos.y - 0.025, hand_pos.z)
		l = l.lerp(hp, smoothstep(0.82, 0.88, p))
		l = l.lerp(hp + Vector3(0.0, 0.0, travel), smoothstep(0.88, 0.92, p))
		l = l.lerp(hp, smoothstep(0.92, 0.94, p))
		l = l.lerp(_l_rest, smoothstep(0.94, 1.0, p))
		_slide_z = travel * (smoothstep(0.88, 0.92, p) - smoothstep(0.92, 0.94, p))
	else:
		l = l.lerp(_l_rest, smoothstep(0.84, 1.0, p))
	_l = l


## Revolver (pack pistol_001 + its drum): the support thumb swings the cylinder out on its crane, the gun tips
## muzzle-up to dump the empties, the hand fetches a speedloader, carries it up to the open cylinder and seats it,
## then closes the cylinder and cups the grip again. The trigger hand never leaves the grip.
func _pose_revolver(p: float) -> void:
	var cyl: Vector3 = _p["handle"]
	var r: float = _p["cyl_radius"]
	var a := deg_to_rad(CYL_SWING)
	var out_c := cyl - Vector3(0.0, r, 0.0) + Vector3(-r * sin(a), r * cos(a), 0.0)   ## drum centre when swung out
	var seat := _mag_rest + (_p["grab_off"] as Vector3)
	var push := cyl + Vector3(-0.042, -0.01, 0.0)          ## palm on the left of the frame, thumb on the drum
	var at_out := out_c + Vector3(-0.06, -0.01, -0.025)    ## fingers round the front of the open drum, steadying it, knuckles clear of the trigger hand
	var pouch := seat + Vector3(-0.05, -0.08, 0.03)
	var near := seat + Vector3(-0.005, -0.02, 0.02)         ## speedloader lined up behind the chambers
	var l := _l_rest
	l = l.lerp(push, smoothstep(0.0, 0.12, p))
	l = l.lerp(at_out, smoothstep(0.12, 0.22, p))
	l = l.lerp(pouch, smoothstep(0.28, 0.37, p))
	l = l.lerp(near, smoothstep(0.37, 0.52, p))
	l = l.lerp(seat, smoothstep(0.52, 0.76, p))
	l = l.lerp(push, smoothstep(0.78, 0.84, p))
	l = l.lerp(_l_rest, smoothstep(0.9, 1.0, p))
	_l = l
	_cyl = smoothstep(0.12, 0.22, p) - smoothstep(0.84, 0.9, p)
	var held := smoothstep(0.0, 0.12, p) - smoothstep(0.9, 1.0, p)
	_g_rot.z = 0.3 * held
	_g_rot.x = 0.3 * (smoothstep(0.22, 0.26, p) - smoothstep(0.29, 0.34, p))   ## muzzle up: the empties fall out
	_g_pos.y = 0.04 * held
	# the trigger hand rolls the gun out toward the loading hand (palm slides down and back on the grip), which also
	# gives the support palm the room over the open cylinder that the palm-separation net demands
	_r = _r_rest + REV_ROLL_R * (smoothstep(0.28, 0.4, p) - smoothstep(0.78, 0.9, p))
	# speedloader: appears in the fist at the pouch, rides it to the drum, seats, and is released (rounds stay in)
	_mag_vis = p >= 0.36 and p < 0.78
	_mag_off = l - seat if p < 0.76 else Vector3.ZERO


func _pose_bolt(p: float) -> void:
	var bolt: Vector3 = _p["bolt_hand"]
	var port: Vector3 = _p["port"]
	var travel: float = _p["slide_travel"]
	var pouch := port + Vector3(-0.03, -0.1, 0.04)   ## the clip is fetched from under the receiver on the left
	var above := port + Vector3(0.0, 0.04, 0.0)
	var push := port + Vector3(0.02, -0.012, -0.02)   ## the clip goes down into the receiver opening
	var hover := port + Vector3(-0.04, 0.05, 0.0)
	var lift := Vector3(0.0, 0.015, 0.0)
	_g_rot.z = 0.08 * (smoothstep(0.0, 0.15, p) - smoothstep(0.85, 1.0, p))
	# right hand: grips the bolt knob, lifts and pulls it back, lets go and regrips the stock while the clip goes
	# in, then goes back to the knob, pushes the bolt home and drops it
	var r := _r_rest
	r = r.lerp(bolt, smoothstep(0.0, 0.1, p))
	r = r.lerp(bolt + lift, smoothstep(0.1, 0.18, p))
	r = r.lerp(bolt + lift + Vector3(0.0, 0.0, travel), smoothstep(0.18, 0.3, p))
	r = r.lerp(_r_rest, smoothstep(0.34, 0.46, p))
	r = r.lerp(bolt + lift + Vector3(0.0, 0.0, travel), smoothstep(0.62, 0.72, p))
	r = r.lerp(bolt + lift, smoothstep(0.72, 0.82, p))
	r = r.lerp(bolt, smoothstep(0.82, 0.86, p))
	r = r.lerp(_r_rest, smoothstep(0.88, 1.0, p))
	_r = r
	_slide_z = travel * (smoothstep(0.18, 0.3, p) - smoothstep(0.72, 0.82, p))   ## the bolt stays open while the right hand is off it
	var l := _l_rest
	l = l.lerp(pouch, smoothstep(0.08, 0.28, p))
	l = l.lerp(above, smoothstep(0.3, 0.46, p))
	l = l.lerp(port, smoothstep(0.46, 0.5, p))   ## at the receiver opening by 50 percent
	l = l.lerp(push, smoothstep(0.52, 0.6, p))
	l = l.lerp(hover, smoothstep(0.6, 0.68, p))
	l = l.lerp(_l_rest, smoothstep(0.7, 0.95, p))
	_l = l
	_prop_vis = p >= 0.22 and p < 0.6
	_prop_pos = l + Vector3(0.0, 0.0, -0.06)   ## held in the fingertips, which reach forward to the opening


## Tube gun. `t` in seconds: `_rounds` shell cycles of round_time each, then the pump (chamber_time).
func _pose_shell(t: float) -> void:
	var port: Vector3 = _p["port"]
	var pump: float = _p["slide_travel"]
	var rt := maxf(_wd.round_time, 0.05)
	var pouch := port + Vector3(-0.06, -0.06, 0.04)
	var push := port + Vector3(0.0, 0.012, 0.0)   ## the fingers push the shell up into the loading gate (no closer to the trigger palm, or _separate slides the fist aside)
	var gate := Vector3(0.0, -0.05, -0.12)           ## where the shell ends up: the receiver's loading gate
	var roll := smoothstep(0.0, 0.2, t) - smoothstep(_dur - 0.2, _dur, t)
	_g_rot.z = 0.12 * roll   ## small cant: a big roll made the shotgun jump in angle and size against its rest frame
	_g_rot.x = 0.03 * roll
	var load_end := float(_rounds) * rt
	var l := _l_rest
	if _rounds > 0 and t < load_end:
		# one cycle per shell: fetch it from the pouch, carry it up to the gate, push it in; the cycle ends with the
		# shell seated at the gate (the fist is at the port), the next one starts with the fist going back to the pouch
		var i := mini(int(t / rt), _rounds - 1)
		var f := (t - float(i) * rt) / rt
		var last := i == _rounds - 1
		var fe := minf(f * 1.25, 1.0) if last else f   ## the last shell is loaded quicker, leaving time to go back to the forend for the pump
		var from := _l_rest if i == 0 else port
		l = from.lerp(pouch, smoothstep(0.0, 0.28, fe))
		l = l.lerp(port, smoothstep(0.28, 0.78, fe))
		l = l.lerp(push, smoothstep(0.78, 0.88, fe))
		if last:
			l = l.lerp(_l_rest, smoothstep(0.72, 0.97, f))   ## the last shell is followed by the pump: the fist returns to the forend
		else:
			l = l.lerp(port, smoothstep(0.88, 1.0, f))
		_prop_vis = f >= 0.2 and (fe < 0.95 if last else f < 0.99)   ## a seated last shell is gone into the tube, not left at the gate as the fist leaves
		var carried := l + Vector3(0.0, 0.0, -0.05)   ## in the fingertips
		_prop_pos = carried.lerp(gate, smoothstep(0.7, 0.95, fe))
	elif _rack:
		var f2 := clampf((t - load_end) / maxf(_dur - load_end, 0.01), 0.0, 1.0)
		var from2 := _l_rest
		l = from2.lerp(_l_rest, smoothstep(0.0, 0.3, f2))
		l = l.lerp(_l_rest + Vector3(0.0, 0.0, pump), smoothstep(0.3, 0.55, f2))
		l = l.lerp(_l_rest, smoothstep(0.55, 0.85, f2))
		_slide_z = pump * (smoothstep(0.3, 0.55, f2) - smoothstep(0.55, 0.85, f2))
	_l = l
