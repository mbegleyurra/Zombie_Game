class_name WeaponController
extends Node3D
## First-person weapon handling. Lives under the player's Camera3D.
## Owns: weapon slots, magazine + chambered round state, reload, ballistics
## (segmented ray along a gravity arc with penetration), recoil, spread, sway.
## Only simulated on the node with multiplayer authority.

signal ammo_changed
signal weapon_changed(weapon_id: String)
signal reload_started(weapon_id: String, duration: float)
signal shot_fired(weapon_id: String)
signal hit_confirmed(headshot: bool)
signal dry_fire

enum State { READY, RELOADING, SWITCHING }

## Flip to true for the later PVP mode: bullets then also hit other players.
static var pvp_enabled: bool = false

const HIP_POS := Vector3(0.2, -0.21, -0.4)
const WORLD_MASK := 1
const PLAYER_MASK := 2
const ZOMBIE_MASK := 4
const GRAVITY := 9.81
const SWITCH_TIME := 0.4
const PERMANENT_RECOIL := 0.4   ## share of each kick that does not recover

var player: Player
var camera: Camera3D

## Each slot: {"id": String, "mag": int, "chambered": bool}
var slots: Array = []
var current_slot: int = -1
var state: State = State.READY
var aiming: bool = false

var _cooldown: float = 0.0
var _reload_timer: float = 0.0
var _reload_total: float = 0.0
var _reload_phase: int = 0            # 0 loading, 1 chambering (tube guns)
var _switch_timer: float = 0.0
var _shot_index: int = 0
var _shot_idle: float = 0.0
var _bloom: float = 0.0
var _recoil_target: Vector2 = Vector2.ZERO
var _recoil_cur: Vector2 = Vector2.ZERO
var _ads: float = 0.0
var _kickback: float = 0.0
var _sway: Vector2 = Vector2.ZERO
var _mouse_rel: Vector2 = Vector2.ZERO
var _bob_t: float = 0.0
var _time: float = 0.0
var _vm: Node3D
var _gun: Node3D
var _muzzle: Node3D
var _flash_light: OmniLight3D
var _flash_mesh: MeshInstance3D
var _flash_time: float = 0.0
var _enabled: bool = false

static var _tracer_mat: StandardMaterial3D
static var _impact_mats: Dictionary = {}


func setup(p_player: Player, p_camera: Camera3D, enabled: bool) -> void:
	player = p_player
	camera = p_camera
	_enabled = enabled
	_vm = Node3D.new()
	_vm.name = "ViewModel"
	_vm.position = HIP_POS
	add_child(_vm)
	visible = enabled
	set_process(enabled)
	set_process_unhandled_input(enabled)


# ------------------------------------------------------------------ public API

func weapon_data() -> WeaponData:
	if current_slot < 0 or current_slot >= slots.size():
		return null
	return WeaponDB.get_weapon(str(slots[current_slot]["id"]))


func has_weapon(id: String) -> bool:
	return _find_slot(id) >= 0


func weapon_ids() -> Array:
	var out: Array = []
	for s in slots:
		out.append(str(s["id"]))
	return out


## Adds a weapon (loaded by default). Returns its slot index or -1 for an unknown id.
func give_weapon(id: String, loaded: bool = true) -> int:
	if not WeaponDB.has_weapon(id):
		return -1
	var existing := _find_slot(id)
	if existing >= 0:
		return existing
	var wd := WeaponDB.get_weapon(id)
	var s := {"id": id, "mag": wd.mag_size - 1 if loaded else 0, "chambered": loaded}
	slots.append(s)
	var idx := slots.size() - 1
	if current_slot < 0:
		equip(idx)
	return idx


## Picks up a found weapon: adds it (loaded) and switches to it when it is new.
## Returns the slot index, or -1 for an unknown id.
func pickup_weapon(id: String, auto_equip: bool = true) -> int:
	if not WeaponDB.has_weapon(id):
		return -1
	var had := has_weapon(id)
	var idx := give_weapon(id)   # never duplicates: returns the existing slot
	if idx >= 0 and not had and auto_equip:
		equip(idx)
	ammo_changed.emit()
	return idx


## Spec sheet of the weapon in hand (empty dict when unarmed): ammo type, drop,
## reload times, rpm. Includes the live reload time for the current magazine state.
func inspect_current() -> Dictionary:
	var wd := weapon_data()
	if wd == null:
		return {}
	var d := wd.inspect()
	var s: Dictionary = slots[current_slot]
	d["mag"] = int(s["mag"])
	d["chambered"] = bool(s["chambered"])
	d["reload_now"] = wd.reload_time(not bool(s["chambered"]), wd.mag_size - int(s["mag"]))
	return d


func remove_weapon(id: String) -> void:
	var idx := _find_slot(id)
	if idx < 0:
		return
	slots.remove_at(idx)
	if idx == current_slot:
		current_slot = -1
		_clear_viewmodel()
		if slots.size() > 0:
			equip(0)
		else:
			weapon_changed.emit("")
	elif idx < current_slot:
		current_slot -= 1
	ammo_changed.emit()


func equip(idx: int) -> void:
	if idx < 0 or idx >= slots.size() or idx == current_slot:
		return
	current_slot = idx
	state = State.SWITCHING
	_switch_timer = SWITCH_TIME
	_reload_timer = 0.0
	_shot_index = 0
	_recoil_target = Vector2.ZERO
	_build_viewmodel()
	weapon_changed.emit(str(slots[idx]["id"]))
	ammo_changed.emit()


func equip_next(step: int) -> void:
	if slots.size() < 2:
		return
	equip(posmod(current_slot + step, slots.size()))


## HUD-friendly snapshot.
func status() -> Dictionary:
	var wd := weapon_data()
	if wd == null:
		return {"weapon": "", "name": "", "mag": 0, "chambered": false, "reserve": 0, "state": int(state)}
	var s: Dictionary = slots[current_slot]
	return {
		"weapon": wd.id, "name": wd.display_name, "mag": int(s["mag"]),
		"chambered": bool(s["chambered"]), "reserve": player.count_item(wd.caliber),
		"state": int(state), "auto": wd.automatic,
	}


func start_reload() -> bool:
	var wd := weapon_data()
	if wd == null or state != State.READY:
		return false
	var s: Dictionary = slots[current_slot]
	if int(s["mag"]) >= wd.mag_size:
		return false
	if player.count_item(wd.caliber) <= 0:
		return false
	state = State.RELOADING
	_reload_phase = 0
	if wd.per_round_reload:
		_reload_total = wd.round_time
	else:
		_reload_total = wd.reload_tactical if bool(s["chambered"]) else wd.reload_empty
	_reload_timer = _reload_total
	reload_started.emit(wd.id, _reload_total)
	return true


func cancel_reload() -> void:
	if state == State.RELOADING:
		state = State.READY
		_reload_timer = 0.0


# ------------------------------------------------------------------ input

func _unhandled_input(event: InputEvent) -> void:
	if player == null or player.is_dead:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_mouse_rel += (event as InputEventMouseMotion).relative
	elif event is InputEventMouseButton and event.pressed and not _build_mode_active():
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			equip_next(-1)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			equip_next(1)
	if _build_mode_active():
		return   # number keys select building pieces in build mode
	for i in range(5):
		if event.is_action_pressed("slot_%d" % (i + 1)):
			equip(i)


func _process(delta: float) -> void:
	if player == null:
		return
	_time += delta
	var wd := weapon_data()
	_vm.visible = wd != null and not player.is_dead
	_update_timers(delta, wd)
	if wd != null and not player.is_dead:
		_handle_actions(wd)
	_update_recoil(delta, wd)
	_update_viewmodel(delta, wd)


func _update_timers(delta: float, wd: WeaponData) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	_shot_idle += delta
	if _shot_idle > 0.3:
		_shot_index = 0
	_bloom = maxf(0.0, _bloom - 1.6 * delta)
	if state == State.SWITCHING:
		_switch_timer -= delta
		if _switch_timer <= 0.0:
			state = State.READY
	elif state == State.RELOADING and wd != null:
		_reload_timer -= delta
		if _reload_timer <= 0.0:
			_advance_reload(wd)
	if _flash_time > 0.0:
		_flash_time -= delta
		if _flash_time <= 0.0:
			if _flash_light:
				_flash_light.light_energy = 0.0
			if _flash_mesh:
				_flash_mesh.visible = false


## True while the Building autoload is in build mode (left/right click build or remove).
func _build_mode_active() -> bool:
	var b := get_node_or_null("/root/Building")
	return b != null and bool(b.get("build_mode"))


func _handle_actions(wd: WeaponData) -> void:
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var building := _build_mode_active()
	aiming = captured and not building and Input.is_action_pressed("aim") and state != State.RELOADING \
		and state != State.SWITCHING and not player.is_sprinting
	if Input.is_action_just_pressed("reload"):
		start_reload()
	if not captured or building:
		return
	var wants_fire := Input.is_action_pressed("fire") if wd.automatic else Input.is_action_just_pressed("fire")
	if not wants_fire or _cooldown > 0.0:
		return
	if state == State.SWITCHING:
		return
	if state == State.RELOADING:
		# Tube-fed guns can be interrupted by a shot if a round is chambered.
		if wd.per_round_reload and _reload_phase == 0 and bool(slots[current_slot]["chambered"]):
			cancel_reload()
		else:
			return
	_try_fire(wd)


# ------------------------------------------------------------------ firing

func _try_fire(wd: WeaponData) -> void:
	var s: Dictionary = slots[current_slot]
	if not bool(s["chambered"]):
		if int(s["mag"]) > 0:
			if wd.per_round_reload:
				# Interrupted tube reload with nothing chambered: rack the pump first.
				state = State.RELOADING
				_reload_phase = 1
				_reload_total = wd.chamber_time
				_reload_timer = wd.chamber_time
				reload_started.emit(wd.id, _reload_total)
			else:
				_chamber(s)
				ammo_changed.emit()
		elif not start_reload():
			dry_fire.emit()
			_cooldown = 0.25
		else:
			pass
		return
	s["chambered"] = false
	if int(s["mag"]) > 0:
		s["mag"] = int(s["mag"]) - 1
		s["chambered"] = true
	_cooldown = wd.seconds_between_shots()
	_fire_shot(wd)
	ammo_changed.emit()


func _fire_shot(wd: WeaponData) -> void:
	var cam_t := camera.global_transform
	var muzzle_pos := _muzzle.global_position if _muzzle != null else cam_t.origin
	var spread := _current_spread(wd)
	var hits: Dictionary = {}
	var tracer_end := cam_t.origin + (-cam_t.basis.z) * 50.0
	for i in range(wd.pellets):
		var dir := _spread_dir(cam_t.basis, spread)
		tracer_end = _simulate_bullet(cam_t.origin, dir, wd, hits, muzzle_pos)
	_apply_hits(hits)
	# recoil: part is permanent for this burst, part is recoverable kick
	var kick := wd.kick_for_shot(_shot_index)
	if aiming:
		kick *= 0.8
	if player.crouching:
		kick *= 0.85
	player.apply_look_delta(kick.x * PERMANENT_RECOIL, kick.y * PERMANENT_RECOIL)
	_recoil_target += kick * (1.0 - PERMANENT_RECOIL)
	_shot_index += 1
	_shot_idle = 0.0
	_bloom += wd.bloom_per_shot
	_kickback = minf(_kickback + 0.03 + wd.recoil_pitch * 0.004, 0.12)
	_flash()
	player.emit_noise(player.global_position, wd.noise_radius)
	player.broadcast_shot(muzzle_pos, tracer_end)
	spawn_tracer(self, muzzle_pos, tracer_end)
	shot_fired.emit(wd.id)


func _current_spread(wd: WeaponData) -> float:
	var s := wd.spread_deg
	if aiming:
		s *= wd.ads_spread_mult
	if player.crouching:
		s *= 0.7
	s += wd.move_spread_deg * player.speed_ratio()
	if not player.is_on_floor():
		s += 3.0
	return s + _bloom


static func _spread_dir(basis: Basis, cone_deg: float) -> Vector3:
	var ang := tan(deg_to_rad(cone_deg))
	var theta := randf() * TAU
	var r := sqrt(randf()) * ang
	var d := -basis.z + basis.x * cos(theta) * r + basis.y * sin(theta) * r
	return d.normalized()


## Steps a bullet along its ballistic arc using short ray segments. Bodies are
## recorded in `hits` ({collider: [damage, headshot]}); each body passed
## reduces damage by weapon penetration. Returns the end point (for the tracer).
func _simulate_bullet(origin: Vector3, dir: Vector3, wd: WeaponData, hits: Dictionary, _muzzle_pos: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var mask := WORLD_MASK | ZOMBIE_MASK
	if pvp_enabled:
		mask |= PLAYER_MASK
	var exclude: Array[RID] = [player.get_rid()]
	var v := wd.muzzle_velocity
	# sights are zeroed: launch slightly high so the arc crosses the aim line at zero_range
	var lift_axis := dir.cross(Vector3.UP)
	if lift_axis.length_squared() > 0.0001:
		dir = dir.rotated(lift_axis.normalized(), wd.zero_angle())
	var seg_dt := clampf(10.0 / v, 0.004, 0.05)
	var g := GRAVITY * wd.gravity_scale
	var t := 0.0
	var p0 := origin
	var end_point := origin
	var travelled := 0.0
	var dmg := wd.damage
	var pen_left := wd.max_penetrations
	var guard := 0
	while travelled < wd.max_range and guard < 400:
		guard += 1
		var t1 := t + seg_dt
		var p1 := origin + dir * v * t1 + Vector3.DOWN * 0.5 * g * t1 * t1
		var q := PhysicsRayQueryParameters3D.create(p0, p1, mask, exclude)
		var res := space.intersect_ray(q)
		if res.is_empty():
			travelled += p0.distance_to(p1)
			p0 = p1
			t = t1
			end_point = p1
			continue
		var hit_pos: Vector3 = res["position"]
		travelled += p0.distance_to(hit_pos)
		end_point = hit_pos
		var col: Object = res["collider"]
		if col != null and col.has_method("request_damage"):
			var d := dmg * _falloff(wd, travelled)
			var head := col.has_method("is_head_hit") and bool(col.call("is_head_hit", hit_pos))
			if head:
				d *= wd.headshot_mult
			var entry: Array = hits.get(col, [0.0, false])
			entry[0] = float(entry[0]) + d
			entry[1] = bool(entry[1]) or head
			hits[col] = entry
			_impact(hit_pos, Color(0.55, 0.05, 0.05))
			exclude.append((col as CollisionObject3D).get_rid())
			if pen_left <= 0:
				break
			pen_left -= 1
			dmg *= wd.penetration
			p0 = hit_pos
			continue
		_impact(hit_pos, Color(0.6, 0.58, 0.5))
		break
	return end_point


static func _falloff(wd: WeaponData, dist: float) -> float:
	if dist <= wd.falloff_start:
		return 1.0
	var k := clampf((dist - wd.falloff_start) / maxf(wd.falloff_end - wd.falloff_start, 0.01), 0.0, 1.0)
	return lerpf(1.0, wd.min_damage_frac, k)


func _apply_hits(hits: Dictionary) -> void:
	for col in hits.keys():
		if not is_instance_valid(col):
			continue
		var entry: Array = hits[col]
		var head := bool(entry[1])
		col.call("request_damage", float(entry[0]), head, player.get_multiplayer_authority())
		hit_confirmed.emit(head)


# ------------------------------------------------------------------ reload

func _advance_reload(wd: WeaponData) -> void:
	var s: Dictionary = slots[current_slot]
	if wd.per_round_reload:
		if _reload_phase == 1:
			_chamber(s)
			_finish_reload()
			return
		var got := player.remove_item(wd.caliber, 1)
		if got > 0:
			s["mag"] = int(s["mag"]) + 1
		ammo_changed.emit()
		if got == 0 or int(s["mag"]) >= wd.mag_size:
			if not bool(s["chambered"]) and int(s["mag"]) > 0:
				_reload_phase = 1
				_reload_total = wd.chamber_time
				_reload_timer = wd.chamber_time
			else:
				_finish_reload()
		else:
			_reload_timer = wd.round_time
		return
	var room := wd.mag_size - int(s["mag"])
	var removed := player.remove_item(wd.caliber, room)
	s["mag"] = int(s["mag"]) + removed
	if not bool(s["chambered"]) and int(s["mag"]) > 0:
		_chamber(s)
	_finish_reload()


func _chamber(s: Dictionary) -> void:
	if int(s["mag"]) > 0:
		s["mag"] = int(s["mag"]) - 1
		s["chambered"] = true


func _finish_reload() -> void:
	state = State.READY
	_reload_timer = 0.0
	ammo_changed.emit()


# ------------------------------------------------------------------ recoil / viewmodel

func _update_recoil(delta: float, wd: WeaponData) -> void:
	var prev := _recoil_cur
	_recoil_cur = _recoil_cur.lerp(_recoil_target, clampf(delta * 30.0, 0.0, 1.0))
	var d := _recoil_cur - prev
	if d.length_squared() > 0.0:
		player.apply_look_delta(d.x, d.y)
	if _shot_idle > 0.05:
		var rec := (wd.recoil_recovery if wd != null else 6.0) * delta
		_recoil_target = _recoil_target.move_toward(Vector2.ZERO, rec)
	_kickback = move_toward(_kickback, 0.0, delta * 0.5)


func _update_viewmodel(delta: float, wd: WeaponData) -> void:
	var ads_time := wd.ads_time if wd != null else 0.15
	_ads = move_toward(_ads, 1.0 if aiming else 0.0, delta / maxf(ads_time, 0.01))
	var ease_ads := _ads * _ads * (3.0 - 2.0 * _ads)
	var ads_pos := Vector3(0.0, -(wd.sight_height if wd != null else 0.07), -0.4)
	var pos := HIP_POS.lerp(ads_pos, ease_ads)
	var sway_mult := wd.sway if wd != null else 1.0
	# mouse-driven sway: the gun lags behind view movement
	var target_sway := Vector2(-_mouse_rel.x, _mouse_rel.y) * 0.0007 * sway_mult
	_mouse_rel = Vector2.ZERO
	_sway = _sway.lerp(target_sway.limit_length(0.06), clampf(delta * 10.0, 0.0, 1.0))
	pos.x += _sway.x * (1.0 - 0.7 * ease_ads)
	pos.y += _sway.y * (1.0 - 0.7 * ease_ads)
	# walk bob and breathing
	var spd := player.speed_ratio()
	if player.is_on_floor() and spd > 0.05:
		_bob_t += delta * (6.0 + 8.0 * spd)
	pos.y += sin(_bob_t * 2.0) * 0.006 * spd * (1.0 - 0.85 * ease_ads)
	pos.x += cos(_bob_t) * 0.008 * spd * (1.0 - 0.85 * ease_ads)
	pos.y += sin(_time * 1.3) * 0.0012 * sway_mult
	pos.z += _kickback
	var rot := Vector3(_kickback * 2.5 + _sway.y * 0.6, _sway.x * 0.6, _sway.x * 1.2)
	# lower the gun while reloading or switching
	var lower := 0.0
	if state == State.RELOADING and _reload_total > 0.0:
		var prog := 1.0 - clampf(_reload_timer / _reload_total, 0.0, 1.0)
		lower = sin(prog * PI)
	elif state == State.SWITCHING:
		var prog2 := 1.0 - clampf(_switch_timer / SWITCH_TIME, 0.0, 1.0)
		lower = 1.0 - prog2
	pos.y -= lower * 0.18
	rot.x -= lower * 0.5
	rot.z += lower * 0.3
	if player.is_sprinting and not aiming:
		pos += Vector3(-0.05, -0.04, 0.0)
		rot.y += 0.5
	_vm.position = _vm.position.lerp(pos, clampf(delta * 18.0, 0.0, 1.0))
	_vm.rotation = _vm.rotation.lerp(rot, clampf(delta * 14.0, 0.0, 1.0))
	if camera != null:
		var base_fov := player.base_fov
		var tgt := lerpf(base_fov, wd.ads_fov if wd != null else base_fov, ease_ads)
		camera.fov = tgt


func _build_viewmodel() -> void:
	_clear_viewmodel()
	var wd := weapon_data()
	if wd == null:
		return
	_gun = GunMesh.build(wd.model)
	_vm.add_child(_gun)
	_muzzle = GunMesh.muzzle_of(_gun)
	if _muzzle != null:
		_flash_light = OmniLight3D.new()
		_flash_light.light_color = Color(1.0, 0.75, 0.4)
		_flash_light.omni_range = 6.0
		_flash_light.light_energy = 0.0
		_muzzle.add_child(_flash_light)
		_flash_mesh = MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.035
		sm.height = 0.07
		sm.radial_segments = 8
		sm.rings = 4
		_flash_mesh.mesh = sm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.85, 0.4)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.7, 0.25)
		mat.emission_energy_multiplier = 4.0
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flash_mesh.material_override = mat
		_flash_mesh.visible = false
		_flash_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_muzzle.add_child(_flash_mesh)


func _clear_viewmodel() -> void:
	if _gun != null and is_instance_valid(_gun):
		_gun.queue_free()
	_gun = null
	_muzzle = null
	_flash_light = null
	_flash_mesh = null


func _flash() -> void:
	_flash_time = 0.045
	if _flash_light:
		_flash_light.light_energy = 3.0
	if _flash_mesh:
		_flash_mesh.visible = true
		_flash_mesh.rotation = Vector3(0.0, 0.0, randf() * TAU)


func _find_slot(id: String) -> int:
	for i in range(slots.size()):
		if str(slots[i]["id"]) == id:
			return i
	return -1


# ------------------------------------------------------------------ effects (static: also used for remote players)

static func spawn_tracer(ctx: Node, from: Vector3, to: Vector3) -> void:
	var scene := ctx.get_tree().current_scene
	if scene == null:
		return
	var len := from.distance_to(to)
	if len < 0.5:
		return
	if _tracer_mat == null:
		_tracer_mat = StandardMaterial3D.new()
		_tracer_mat.albedo_color = Color(1.0, 0.9, 0.55)
		_tracer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.012, 0.012, minf(len, 14.0))
	mi.mesh = bm
	mi.material_override = _tracer_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene.add_child(mi)
	var dir := (to - from).normalized()
	# a short streak that sits near the far end of the path
	var centre := to - dir * minf(len, 14.0) * 0.5
	mi.global_position = centre
	if absf(dir.dot(Vector3.UP)) < 0.99:
		mi.look_at(centre + dir, Vector3.UP)
	else:
		mi.look_at(centre + dir, Vector3.RIGHT)
	ctx.get_tree().create_timer(0.05).timeout.connect(mi.queue_free)


func _impact(pos: Vector3, color: Color) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var key := color.to_html()
	var mat: StandardMaterial3D = _impact_mats.get(key)
	if mat == null:
		mat = StandardMaterial3D.new()
		mat.albedo_color = color
		_impact_mats[key] = mat
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.05
	sm.height = 0.1
	sm.radial_segments = 6
	sm.rings = 3
	mi.mesh = sm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene.add_child(mi)
	mi.global_position = pos
	get_tree().create_timer(0.5).timeout.connect(mi.queue_free)
