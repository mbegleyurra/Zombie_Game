class_name Player
extends CharacterBody3D
## First-person survival controller. The node NAME is the owning peer id
## ("1" for the host, offline play can use any name). Only the node with
## multiplayer authority reads input, owns inventory/stats and enables its camera.
##
## Public API (used by world / net / building / zombies):
##   add_item(id, n) / remove_item(id, n) -> removed / count_item(id) / has_item(id, n)
##   use_item(id) -> bool            (medkit, food, water)
##   give_weapon(id) -> slot         ("pistol","ak","m4","shotgun","hunting")
##   request_damage(amount, headshot, attacker_peer)   (routes to the owning peer)
##   emit_noise(pos, radius)         (zombies hear it; routed to the server)
##   respawn(pos) / net_respawn(pos) (rpc, call from server)
##   is_head_hit(world_pos), speed_ratio(), apply_look_delta(yaw_deg, pitch_deg)
##   get_hud_state() -> Dictionary
## Replication: this scene adds its own MultiplayerSynchronizer ("PlayerSync")
## for position, yaw, pitch, crouch, health, death and equipped weapon.

signal died(peer_id: int)
signal respawned
signal inventory_changed
signal stats_changed
signal damaged(amount: float)
signal item_used(id: String)

const WALK_SPEED := 4.2
const SPRINT_SPEED := 7.2
const CROUCH_SPEED := 2.0
const JUMP_VELOCITY := 5.2
const GRAVITY := 17.0
const STAND_HEIGHT := 1.8
const CROUCH_HEIGHT := 1.1
const EYE_STAND := 1.62
const EYE_CROUCH := 1.0
const BASE_FOV := 75.0
const JUMP_STAMINA := 10.0
const HUNGER_RATE := 0.045   ## per second (about 37 minutes from full to empty)
const THIRST_RATE := 0.07

## Loot/ItemDB ids and weapon_db ids differ ("ammo_9mm" vs "9mm", "hunting_rifle" vs
## "hunting"). Every inventory call funnels through normalize_id so both forms work.
const ID_ALIASES := {
	"ammo_9mm": "9mm", "ammo_556": "556", "ammo_762": "762", "ammo_12ga": "12ga",
	"5.56": "556", "7.62": "762", "ammo_5.56": "556", "ammo_7.62": "762",
	"hunting_rifle": "hunting", "hunting rifle": "hunting", "rifle": "hunting",
	"ak47": "ak", "ak_47": "ak", "m4a1": "m4",
}

@export var start_with_loadout: bool = true
@export var mouse_sensitivity: float = 0.0022
@export var max_health: float = 100.0

var peer_id: int = 1
var health: float = 100.0
var stamina: float = 100.0
var hunger: float = 100.0
var thirst: float = 100.0
var is_dead: bool = false
var is_sprinting: bool = false
var crouching: bool = false
var look_pitch: float = 0.0
var equipped_id: String = ""
var base_fov: float = BASE_FOV
var inventory: Dictionary = {}

var _stamina_lock: bool = false
var _stamina_delay: float = 0.0
var _step_timer: float = 0.0
var _interact_timer: float = 0.0
var _hurt_flash: float = 0.0
var _anim_t: float = 0.0
var _last_pos: Vector3 = Vector3.ZERO
var _remote_speed: float = 0.0
var _shown_gun_id: String = "?"
var relay: DamageRelay

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var weapons: WeaponController = $Head/Camera3D/Weapons
@onready var body_shape: CollisionShape3D = $Collision

var _avatar: Node3D
var _avatar_gun: Node3D
var _model: PlayerModel   ## Kenney body (null when the asset is missing: the box avatar is used)
var _legs: Array[Node3D] = []
var _arms: Array[Node3D] = []
var _hud: CanvasLayer
var _lbl_stats: Label
var _lbl_ammo: Label
var _lbl_prompt: Label
var _lbl_dead: Label
var _crosshair: Label
var _hurt_rect: ColorRect
var _hovered: Object = null


# ================================================================== setup

## Registers every input action in code so project.godot needs no edits.
static func register_inputs() -> void:
	_key("move_forward", [KEY_W, KEY_UP])
	_key("move_back", [KEY_S, KEY_DOWN])
	_key("move_left", [KEY_A, KEY_LEFT])
	_key("move_right", [KEY_D, KEY_RIGHT])
	_key("sprint", [KEY_SHIFT])
	_key("crouch", [KEY_CTRL, KEY_C])
	_key("jump", [KEY_SPACE])
	_key("reload", [KEY_R])
	_key("interact", [KEY_E])
	_key("use_medkit", [KEY_H])
	_key("use_food", [KEY_J])
	_key("use_water", [KEY_K])
	_mouse("fire", MOUSE_BUTTON_LEFT)
	_mouse("aim", MOUSE_BUTTON_RIGHT)
	for i in range(5):
		_key("slot_%d" % (i + 1), [KEY_1 + i])


static func _key(action: String, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action, 0.2)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k as Key
		InputMap.action_add_event(action, ev)


static func _mouse(action: String, button: MouseButton) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action, 0.2)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)


func _enter_tree() -> void:
	var n := str(name)
	peer_id = n.to_int() if n.is_valid_int() else 1
	set_multiplayer_authority(peer_id)


func _ready() -> void:
	register_inputs()
	add_to_group("players")
	collision_layer = 2
	collision_mask = 1
	relay = DamageRelay.new()
	relay.name = "DamageRelay"
	add_child(relay)
	var local := is_multiplayer_authority()
	camera.current = local
	head.position.y = EYE_STAND
	weapons.setup(self, camera, local)
	_build_avatar(local)
	_setup_sync()
	_last_pos = global_position
	if local:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_build_hud()
		weapons.ammo_changed.connect(_refresh_hud)
		weapons.weapon_changed.connect(func(id: String) -> void: equipped_id = id)
		weapons.hit_confirmed.connect(_on_hit_confirmed)
		if start_with_loadout:
			give_weapon("pistol")
			add_item("9mm", 45)
			add_item("medkit", 1)
			add_item("food", 1)
			add_item("water", 1)
		_refresh_hud()


func _setup_sync() -> void:
	var cfg := SceneReplicationConfig.new()
	for prop in ["position", "rotation", "look_pitch", "crouching", "is_dead", "health", "equipped_id", "is_sprinting"]:
		var path := NodePath(".:" + prop)
		cfg.add_property(path)
		cfg.property_set_spawn(path, true)
		cfg.property_set_replication_mode(path, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	var sync := MultiplayerSynchronizer.new()
	sync.name = "PlayerSync"
	sync.replication_config = cfg
	# Hidden from every peer until that peer confirms it has spawned this node;
	# Net grants visibility per peer (network.gd _rpc_spawned).
	sync.public_visibility = false
	sync.set_multiplayer_authority(peer_id)
	add_child(sync)


# ================================================================== frame loops

func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not is_dead:
		var rel := (event as InputEventMouseMotion).relative
		var s := mouse_sensitivity * (0.6 if weapons.aiming else 1.0)
		rotate_y(-rel.x * s)
		look_pitch = clampf(look_pitch - rad_to_deg(rel.y * s), -89.0, 89.0)
		head.rotation_degrees.x = look_pitch
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("interact") and not is_dead:
		_interact()
	elif event.is_action_pressed("use_medkit") and not is_dead:
		use_item("medkit")
	elif event.is_action_pressed("use_food") and not is_dead:
		use_item("food")
	elif event.is_action_pressed("use_water") and not is_dead:
		use_item("water")


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	_update_stats(delta)
	if is_dead:
		velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 20.0 * delta)
		if not is_on_floor():
			velocity.y -= GRAVITY * delta
		move_and_slide()
		return
	_update_crouch(delta)
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		input = Vector2.ZERO
	var on_floor := is_on_floor()
	var want_sprint := Input.is_action_pressed("sprint") and input.y < -0.1 and not crouching \
		and not _stamina_lock and on_floor and not weapons.aiming
	is_sprinting = want_sprint and stamina > 0.0
	var speed := CROUCH_SPEED if crouching else (SPRINT_SPEED if is_sprinting else WALK_SPEED)
	if weapons.aiming:
		speed *= 0.65
	if hunger <= 0.0 or thirst <= 0.0:
		speed *= 0.8
	var dir := (transform.basis * Vector3(input.x, 0.0, input.y)).normalized()
	var accel := 45.0 if on_floor else 6.0
	velocity.x = move_toward(velocity.x, dir.x * speed, accel * delta)
	velocity.z = move_toward(velocity.z, dir.z * speed, accel * delta)
	if on_floor:
		if Input.is_action_just_pressed("jump") and not crouching and stamina >= JUMP_STAMINA \
				and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			velocity.y = JUMP_VELOCITY
			stamina -= JUMP_STAMINA
			_stamina_delay = 1.0
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()
	_update_stamina(delta)
	_footsteps(delta)
	var target_fov := BASE_FOV + (8.0 if is_sprinting else 0.0)
	base_fov = lerpf(base_fov, target_fov, clampf(delta * 8.0, 0.0, 1.0))


func _process(delta: float) -> void:
	_anim_t += delta
	if is_multiplayer_authority():
		_process_local(delta)
	else:
		_process_remote(delta)
	_update_avatar(delta)


func _process_local(delta: float) -> void:
	if is_dead:
		head.position.y = lerpf(head.position.y, 0.35, clampf(delta * 3.0, 0.0, 1.0))
		head.rotation.z = lerpf(head.rotation.z, 0.9, clampf(delta * 3.0, 0.0, 1.0))
	else:
		head.rotation.z = lerpf(head.rotation.z, 0.0, clampf(delta * 8.0, 0.0, 1.0))
	_interact_timer -= delta
	if _interact_timer <= 0.0:
		_interact_timer = 0.1
		_update_hover()
	_hurt_flash = maxf(0.0, _hurt_flash - delta * 1.6)
	if _hurt_rect:
		_hurt_rect.color.a = _hurt_flash * 0.45
	_refresh_hud()


func _process_remote(delta: float) -> void:
	head.rotation_degrees.x = look_pitch
	var moved := global_position - _last_pos
	moved.y = 0.0
	_remote_speed = lerpf(_remote_speed, moved.length() / maxf(delta, 0.0001), clampf(delta * 8.0, 0.0, 1.0))
	_last_pos = global_position
	var eye := EYE_CROUCH if crouching else EYE_STAND
	head.position.y = lerpf(head.position.y, eye, clampf(delta * 10.0, 0.0, 1.0))
	_apply_shape(crouching, delta)


func _update_crouch(delta: float) -> void:
	var want := Input.is_action_pressed("crouch")
	if want:
		crouching = true
	elif crouching:
		# only stand if there is headroom
		var up := Vector3.UP * (STAND_HEIGHT - CROUCH_HEIGHT + 0.05)
		if not test_move(global_transform, up):
			crouching = false
	head.position.y = lerpf(head.position.y, EYE_CROUCH if crouching else EYE_STAND, clampf(delta * 12.0, 0.0, 1.0))
	_apply_shape(crouching, delta)


func _apply_shape(crouch: bool, delta: float) -> void:
	var cap := body_shape.shape as CapsuleShape3D
	var h := lerpf(cap.height, CROUCH_HEIGHT if crouch else STAND_HEIGHT, clampf(delta * 12.0, 0.0, 1.0))
	cap.height = h
	body_shape.position.y = h * 0.5


# ================================================================== stats

func _update_stats(delta: float) -> void:
	if is_dead:
		return
	hunger = maxf(0.0, hunger - HUNGER_RATE * delta)
	thirst = maxf(0.0, thirst - THIRST_RATE * delta)
	if hunger <= 0.0 or thirst <= 0.0:
		_hurt(0.8 * delta, false)
	elif hunger > 60.0 and thirst > 60.0 and health < max_health:
		health = minf(max_health, health + 0.6 * delta)


func _update_stamina(delta: float) -> void:
	if is_sprinting and velocity.length() > 0.5:
		stamina = maxf(0.0, stamina - 14.0 * delta)
		_stamina_delay = 1.0
		if stamina <= 0.0:
			_stamina_lock = true
	else:
		_stamina_delay -= delta
		if _stamina_delay <= 0.0:
			var rate := 18.0 if not crouching else 26.0
			if hunger <= 0.0 or thirst <= 0.0:
				rate *= 0.4
			stamina = minf(100.0, stamina + rate * delta)
	if _stamina_lock and stamina >= 20.0:
		_stamina_lock = false


func speed_ratio() -> float:
	return clampf(Vector2(velocity.x, velocity.z).length() / SPRINT_SPEED, 0.0, 1.0)


func _footsteps(delta: float) -> void:
	var spd := Vector2(velocity.x, velocity.z).length()
	if spd < 0.8 or not is_on_floor():
		_step_timer = 0.0
		return
	_step_timer -= delta
	if _step_timer <= 0.0:
		_step_timer = 0.55
		var radius := 12.0 if is_sprinting else (2.5 if crouching else 6.5)
		emit_noise(global_position, radius)


# ================================================================== damage / death

func request_damage(amount: float, _headshot: bool = false, _attacker: int = 0) -> void:
	if is_multiplayer_authority():
		_hurt(amount, true)
	else:
		# Not rpc_id on this node: a peer that has not confirmed our spawn cannot "see"
		# it. The relay child has no synchronizer, retries and is acked (damage_relay.gd).
		relay.send(get_multiplayer_authority(), amount)


func take_damage(amount: float) -> void:
	request_damage(amount)


## Legacy entry point, kept so the RPC table is unchanged; request_damage uses the relay.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_hurt(amount: float) -> void:
	if is_multiplayer_authority():
		_hurt(amount, true)


func _hurt(amount: float, flash: bool = true) -> void:
	if is_dead or amount <= 0.0:
		return
	health -= amount
	if flash:
		_hurt_flash = 1.0
		damaged.emit(amount)
	if health <= 0.0:
		health = 0.0
		_die()


func _die() -> void:
	is_dead = true
	is_sprinting = false
	weapons.cancel_reload()
	if _lbl_dead:
		_lbl_dead.visible = true
	died.emit(peer_id)


func is_head_hit(world_pos: Vector3) -> bool:
	var top := 1.45 if not crouching else 0.95
	return world_pos.y > global_position.y + top


## Called by the owning peer (or via net_respawn from the server).
func respawn(pos: Vector3) -> void:
	health = max_health
	stamina = 100.0
	hunger = maxf(hunger, 60.0)
	thirst = maxf(thirst, 60.0)
	is_dead = false
	crouching = false
	velocity = Vector3.ZERO
	global_position = pos
	head.rotation.z = 0.0
	head.position.y = EYE_STAND
	if _lbl_dead:
		_lbl_dead.visible = false
	respawned.emit()
	_refresh_hud()


@rpc("any_peer", "call_local", "reliable")
func net_respawn(pos: Vector3) -> void:
	if is_multiplayer_authority():
		respawn(pos)


# ================================================================== inventory

## Maps any loot/ItemDB spelling to the id the weapon code uses.
static func normalize_id(id: String) -> String:
	var k := id.strip_edges().to_lower()
	return str(ID_ALIASES.get(k, k))


## Weapon items ("pistol", "ak", "m4", "shotgun", "hunting") are not stored in
## `inventory`; they go to the weapon controller, which equips a newly found gun.
## Picking up a gun you already own gives one magazine of its ammo instead.
func add_item(id: String, n: int = 1) -> void:
	if n <= 0:
		return
	id = normalize_id(id)
	if WeaponDB.has_weapon(id):
		if weapons.has_weapon(id):
			var wd := WeaponDB.get_weapon(id)
			inventory[wd.caliber] = int(inventory.get(wd.caliber, 0)) + wd.mag_size
		else:
			weapons.pickup_weapon(id)
		inventory_changed.emit()
		weapons.ammo_changed.emit()
		return
	inventory[id] = int(inventory.get(id, 0)) + n
	inventory_changed.emit()
	weapons.ammo_changed.emit()


## Removes up to n; returns how many were actually removed.
func remove_item(id: String, n: int = 1) -> int:
	id = normalize_id(id)
	if WeaponDB.has_weapon(id):
		if n > 0 and weapons.has_weapon(id):
			weapons.remove_weapon(id)
			inventory_changed.emit()
			return 1
		return 0
	var have := int(inventory.get(id, 0))
	var take := mini(have, n)
	if take <= 0:
		return 0
	if have - take <= 0:
		inventory.erase(id)
	else:
		inventory[id] = have - take
	inventory_changed.emit()
	return take


func count_item(id: String) -> int:
	id = normalize_id(id)
	if WeaponDB.has_weapon(id):
		return 1 if weapons.has_weapon(id) else 0
	return int(inventory.get(id, 0))


func has_item(id: String, n: int = 1) -> bool:
	return count_item(id) >= n


## Gives a weapon and equips it when it is new (no duplicates). Returns the slot or -1.
func give_weapon(id: String) -> int:
	return weapons.pickup_weapon(normalize_id(id))


func use_item(id: String) -> bool:
	if is_dead or count_item(id) <= 0:
		return false
	match id:
		"medkit":
			if health >= max_health:
				return false
			health = minf(max_health, health + 50.0)
		"food":
			if hunger >= 100.0:
				return false
			hunger = minf(100.0, hunger + 35.0)
			health = minf(max_health, health + 3.0)
		"water":
			if thirst >= 100.0:
				return false
			thirst = minf(100.0, thirst + 40.0)
		_:
			return false
	remove_item(id, 1)
	item_used.emit(id)
	stats_changed.emit()
	return true


# ================================================================== interaction

func _hover_target() -> Object:
	var from := camera.global_position
	var to := from + (-camera.global_transform.basis.z) * 3.0
	var q := PhysicsRayQueryParameters3D.create(from, to, 0xFFFFFFFF, [get_rid()])
	var res := get_world_3d().direct_space_state.intersect_ray(q)
	if res.is_empty():
		return null
	var node: Node = res["collider"] as Node
	for _i in range(4):
		if node == null:
			break
		if node.has_method("interact"):
			return node
		node = node.get_parent()
	return null


func _update_hover() -> void:
	_hovered = _hover_target() if not is_dead else null
	if _lbl_prompt:
		var text := ""
		if _hovered != null:
			text = "[E] " + (str(_hovered.call("get_prompt")) if _hovered.has_method("get_prompt") else "Interact")
		_lbl_prompt.text = text


func _interact() -> void:
	var t := _hover_target()
	if t != null:
		t.call("interact", self)


# ================================================================== noise / shot fx

## Zombies hear this. Clients route it to the server, which owns all AI.
func emit_noise(pos: Vector3, radius: float) -> void:
	if multiplayer.is_server():
		get_tree().call_group("zombies", "hear_noise", pos, radius)
	else:
		rpc_id(1, "_rpc_noise", pos, radius)


@rpc("any_peer", "call_remote", "unreliable")
func _rpc_noise(pos: Vector3, radius: float) -> void:
	if multiplayer.is_server():
		get_tree().call_group("zombies", "hear_noise", pos, radius)


func broadcast_shot(from: Vector3, to: Vector3) -> void:
	if multiplayer.has_multiplayer_peer() and multiplayer.get_peers().size() > 0:
		rpc("_rpc_shot_fx", from, to)


@rpc("authority", "call_remote", "unreliable")
func _rpc_shot_fx(from: Vector3, to: Vector3) -> void:
	WeaponController.spawn_tracer(self, from, to)


func apply_look_delta(yaw_deg: float, pitch_deg: float) -> void:
	if yaw_deg != 0.0:
		rotate_y(-deg_to_rad(yaw_deg))
	look_pitch = clampf(look_pitch + pitch_deg, -89.0, 89.0)
	head.rotation_degrees.x = look_pitch


# ================================================================== avatar (what other players see)

func _build_avatar(local: bool) -> void:
	_avatar = Node3D.new()
	_avatar.name = "Avatar"
	add_child(_avatar)
	# Kenney body; the local player's copy is shadows-only so the first-person view is unchanged
	var model := PlayerModel.new()
	if model.build(peer_id, local):
		_model = model
		_avatar.add_child(model)
		return
	model.free()
	var rng := RandomNumberGenerator.new()
	rng.seed = peer_id
	var shirt := Color.from_hsv(rng.randf(), 0.55, 0.6)
	var skin := Color(0.85, 0.66, 0.5)
	var pants := Color(0.2, 0.22, 0.3)
	_part(_avatar, BoxMesh.new(), Vector3(0.5, 0.6, 0.26), Vector3(0, 1.15, 0), shirt)
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.15
	head_mesh.height = 0.3
	head_mesh.radial_segments = 10
	head_mesh.rings = 6
	_part(_avatar, head_mesh, Vector3.ONE, Vector3(0, 1.6, 0), skin)
	for side in [-1.0, 1.0]:
		var leg := Node3D.new()
		leg.position = Vector3(0.12 * side, 0.8, 0)
		_avatar.add_child(leg)
		_part(leg, BoxMesh.new(), Vector3(0.18, 0.8, 0.2), Vector3(0, -0.4, 0), pants)
		_legs.append(leg)
		var arm := Node3D.new()
		arm.position = Vector3(0.33 * side, 1.4, 0)
		_avatar.add_child(arm)
		_part(arm, BoxMesh.new(), Vector3(0.14, 0.6, 0.14), Vector3(0, -0.3, 0), shirt)
		_arms.append(arm)
	# Local players see their own viewmodel, not their body.
	_avatar.visible = not local


func _part(parent: Node3D, mesh: Mesh, size: Vector3, pos: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	if mesh is BoxMesh:
		(mesh as BoxMesh).size = size
	mi.mesh = mesh
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)


func _update_avatar(delta: float) -> void:
	if _model != null:
		var spd := Vector2(velocity.x, velocity.z).length() if is_multiplayer_authority() else _remote_speed
		_model.animate(delta, spd, look_pitch, crouching, is_sprinting, is_dead, equipped_id != "")
		if not is_multiplayer_authority():
			_sync_avatar_gun()
		return
	if is_multiplayer_authority():
		return
	# lie down when dead, otherwise swing legs by measured speed
	var tilt := -PI * 0.5 if is_dead else 0.0
	_avatar.rotation.x = lerpf(_avatar.rotation.x, tilt, clampf(delta * 6.0, 0.0, 1.0))
	var swing := sin(_anim_t * 9.0) * clampf(_remote_speed / 4.0, 0.0, 1.0) * 0.7
	if _legs.size() == 2:
		_legs[0].rotation.x = swing
		_legs[1].rotation.x = -swing
	if _arms.size() == 2:
		var aim_up := -look_pitch * PI / 180.0
		_arms[1].rotation.x = -1.2 + aim_up if equipped_id != "" else -swing
		_arms[0].rotation.x = -1.0 + aim_up if equipped_id != "" else swing
	_sync_avatar_gun()
	_avatar.position.y = 0.0 if not crouching else -0.35


## Remote peers see the gun the player has equipped.
func _sync_avatar_gun() -> void:
	if equipped_id == _shown_gun_id:
		return
	_shown_gun_id = equipped_id
	if _avatar_gun != null:
		_avatar_gun.queue_free()
		_avatar_gun = null
	if equipped_id != "" and WeaponDB.has_weapon(equipped_id):
		_avatar_gun = GunMesh.build(WeaponDB.get_weapon(equipped_id).model)
		_avatar_gun.position = Vector3(0.22, 1.25 if not crouching else 0.9, -0.2)
		_avatar.add_child(_avatar_gun)


# ================================================================== HUD (minimal; the full UI lives in scenes/ui)

func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.name = "PlayerHUD"
	add_child(_hud)
	_hurt_rect = ColorRect.new()
	_hurt_rect.color = Color(0.8, 0.0, 0.0, 0.0)
	_hurt_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hurt_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud.add_child(_hurt_rect)
	_crosshair = _make_label("+", Control.PRESET_CENTER, 22)
	_crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_crosshair.position -= Vector2(10, 16)
	_lbl_stats = _make_label("", Control.PRESET_TOP_LEFT, 16)
	_lbl_stats.position = Vector2(14, 12)
	_lbl_ammo = _make_label("", Control.PRESET_BOTTOM_RIGHT, 20)
	_lbl_ammo.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_lbl_ammo.position = Vector2(-260, -90)
	_lbl_ammo.size = Vector2(240, 70)
	_lbl_prompt = _make_label("", Control.PRESET_CENTER, 18)
	_lbl_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_prompt.position = Vector2(-120, 40)
	_lbl_prompt.size = Vector2(240, 30)
	_lbl_dead = _make_label("YOU DIED", Control.PRESET_CENTER, 48)
	_lbl_dead.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_dead.position = Vector2(-180, -80)
	_lbl_dead.size = Vector2(360, 80)
	_lbl_dead.modulate = Color(0.8, 0.1, 0.1)
	_lbl_dead.visible = false


func _make_label(text: String, preset: int, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(l)
	l.set_anchors_preset(preset as Control.LayoutPreset)
	return l


func _refresh_hud() -> void:
	if _lbl_stats == null:
		return
	_lbl_stats.text = "HP %d   STA %d\nFOOD %d   WATER %d" % [roundi(health), roundi(stamina), roundi(hunger), roundi(thirst)]
	var st := weapons.status()
	if str(st["weapon"]) == "":
		_lbl_ammo.text = ""
	else:
		var chamber := "+1" if bool(st["chambered"]) else ""
		_lbl_ammo.text = "%s\n%d%s / %d" % [str(st["name"]), int(st["mag"]), chamber, int(st["reserve"])]
	_crosshair.visible = not weapons.aiming and not is_dead


func _on_hit_confirmed(headshot: bool) -> void:
	if _crosshair:
		_crosshair.modulate = Color(1, 0.2, 0.2) if headshot else Color(1, 0.9, 0.5)
		get_tree().create_timer(0.12).timeout.connect(func() -> void:
			if is_instance_valid(_crosshair):
				_crosshair.modulate = Color.WHITE)


func get_hud_state() -> Dictionary:
	return {
		"health": health, "stamina": stamina, "hunger": hunger, "thirst": thirst,
		"dead": is_dead, "inventory": inventory.duplicate(), "weapon": weapons.status(),
	}
