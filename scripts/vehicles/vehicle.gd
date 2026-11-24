extends VehicleBody3D
## Drivable car built from a Kenney Car Kit model (the same .glb files KenneyDressing uses).
## Baked into scenes/world/baked/vehicles.tscn (exported `kind`), so every peer loads the same cars at the same paths
## (World/Vehicles/Car_N); the model, collider and wheels are built in _ready. No class_name on purpose: callers preload this script.
##
## Interaction: Player's hover ray finds this node (interact + get_prompt), so E enters; Player._interact
## forwards E to us while seated, so E exits. Enter/exit go through the server (any peer -> server validates ->
## _rpc_set_driver to everyone). The driver's peer owns the car physics while driving (multiplayer authority moves
## to them); everyone else sees a frozen kinematic copy that follows the replicated position/rotation.
## The driver's Player is hidden, parked on the seat each physics frame and told `vehicle = self` so it stops walking.

const ModelUtil = preload("res://scripts/world/model_util.gd")
## Kenney Car Kit folder and per-kind fitted height (also read by the bake-only tools/worldgen/kenney_dressing.gd).
const CARS := "res://assets/kenney/cars/"
const CAR_H := {
	"sedan": 1.45, "sedan-sports": 1.35, "hatchback-sports": 1.35, "suv": 1.75, "suv-luxury": 1.75,
	"van": 2.1, "truck": 2.6, "taxi": 1.45, "police": 1.5, "ambulance": 2.3, "delivery": 2.5,
	"garbage-truck": 3.0, "firetruck": 3.1,
}

const FORWARD := Vector3(0.0, 0.0, -1.0)   ## local travel direction; the glb front (+Z) is turned to match
const MAX_SPEED := 30.0
const MAX_REVERSE := 8.0
const MAX_STEER := 0.5
const ENGINE_PER_MASS := 1.6     ## engine force per traction wheel = this * mass (4 traction wheels)
const BRAKE_FORCE := 22.0
const HANDBRAKE := 45.0
const PARK_BRAKE := 25.0
const COAST_BRAKE := 1.0
const ENTER_RANGE := 6.0
const TOGGLE_DEBOUNCE_MSEC := 400   ## E both enters (hover ray) and exits (Player forward): ignore the echo
const REST := 0.2

@export var kind: String = "sedan"
var driver_id: int = 0
var size := Vector3(1.8, 1.4, 4.0)
## Control inputs, -1..1. Read from the keyboard for the local driver unless `scripted` is set (tests).
var throttle_in: float = 0.0
var steer_in: float = 0.0   ## +1 = left
var handbrake_in: float = 0.0
var scripted: bool = false

var _wheels: Array = []   # {"vw": VehicleWheel3D, "mesh": Node3D, "front": bool, "spin": float}
var _sync: MultiplayerSynchronizer
var _cam: Camera3D
var _hud: CanvasLayer
var _hud_label: Label
var _last_toggle: int = -100000
var _flip_t: float = 0.0
var _seat := Vector3(-0.35, 0.6, 0.0)


func setup(p_kind: String) -> void:
	kind = p_kind


func _ready() -> void:
	add_to_group("vehicles")
	collision_layer = 1
	collision_mask = 1
	_build()
	_build_sync()
	_update_sim_mode()
	if multiplayer.has_multiplayer_peer():
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	var net := get_node_or_null("/root/Net")
	if net != null and net.has_signal("peer_scene_ready"):
		net.peer_scene_ready.connect(func(_id: int) -> void: _refresh_visibility())


# ================================================================== build

func _build() -> void:
	var h: float = float(CAR_H.get(kind, 1.6))
	var m: Node3D = ModelUtil.load_fit(CARS + kind + ".glb", h)
	if m == null:
		push_warning("[Vehicle] missing model %s, collider only (no primitive visual)" % kind)
		m = Node3D.new()
		m.set_meta("size", Vector3(1.8, h, 4.2))
	size = m.get_meta("size") as Vector3
	m.rotation.y = PI   # glb front is +Z, the vehicle drives toward -Z
	add_child(m)
	mass = 700.0 + 350.0 * h
	linear_damp = 0.05
	angular_damp = 0.6
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0.0, 0.25, 0.0)
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	can_sleep = true
	# chassis: one box above the wheels
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	var clearance := 0.45
	bs.size = Vector3(size.x * 0.9, maxf(size.y - clearance, 0.5), size.z * 0.95)
	cs.shape = bs
	cs.position = Vector3(0.0, clearance + bs.size.y * 0.5, 0.0)
	add_child(cs)
	_seat = Vector3(-size.x * 0.2, 0.6, -size.z * 0.05)
	_build_wheels(m)


func _find_wheels(n: Node, xf: Transform3D, out: Array) -> void:
	for c in n.get_children():
		if c is Node3D:
			var t: Transform3D = xf * (c as Node3D).transform
			if str(c.name).begins_with("wheel"):
				out.append({"node": c, "pos": t.origin})
			else:
				_find_wheels(c, t, out)


func _build_wheels(m: Node3D) -> void:
	var found: Array = []
	_find_wheels(m, Transform3D.IDENTITY, found)
	var spots: Array = []   # {"pos": Vector3 (body space), "radius": float, "mesh": Node3D or null}
	var rot := Basis(Vector3.UP, PI)
	if found.size() >= 4:
		for f in found:
			var p: Vector3 = rot * (f["pos"] as Vector3)
			spots.append({"pos": p, "radius": clampf(float((f["pos"] as Vector3).y), 0.22, 0.7), "mesh": f["node"]})
	else:
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				spots.append({"pos": Vector3(float(sx) * size.x * 0.42, 0.33, float(sz) * size.z * 0.3), "radius": 0.33, "mesh": null})
	for s in spots:
		var p: Vector3 = s["pos"]
		var r: float = float(s["radius"])
		var vw := VehicleWheel3D.new()
		vw.position = Vector3(p.x, r + REST, p.z)
		vw.wheel_radius = r
		vw.wheel_rest_length = REST
		vw.suspension_travel = 0.4
		vw.suspension_stiffness = mass * 0.09
		vw.suspension_max_force = mass * 12.0
		vw.damping_compression = 0.9
		vw.damping_relaxation = 1.1
		vw.wheel_friction_slip = 2.0
		vw.wheel_roll_influence = 0.02
		var front: bool = p.dot(FORWARD) > 0.0
		vw.use_as_steering = front
		vw.use_as_traction = true
		add_child(vw)
		_wheels.append({"vw": vw, "mesh": s["mesh"], "front": front, "spin": 0.0})


func _build_sync() -> void:
	var cfg := SceneReplicationConfig.new()
	for prop in ["position", "rotation"]:
		var path := NodePath(".:" + prop)
		cfg.add_property(path)
		cfg.property_set_replication_mode(path, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	_sync = MultiplayerSynchronizer.new()
	_sync.name = "VehicleSync"
	_sync.replication_config = cfg
	_sync.replication_interval = 0.05
	add_child(_sync)
	_refresh_visibility()


## Visibility follows the project convention (see zombies/spawner.gd): the host shows the car only to peers whose
## main scene exists. A client that is driving owns the sync and shows it to everyone.
func _refresh_visibility() -> void:
	if _sync == null or not is_multiplayer_authority():
		return
	var net := get_node_or_null("/root/Net")
	if net == null:
		return
	if multiplayer.is_server():
		_sync.public_visibility = false
		for id in net.scene_ready_peers:
			_sync.set_visibility_for(id, true)
	else:
		_sync.public_visibility = true


## Only the authority simulates; every other peer holds a kinematic copy driven by the synchronizer.
func _update_sim_mode() -> void:
	freeze = not is_multiplayer_authority()
	if freeze:
		engine_force = 0.0
		steering = 0.0


# ================================================================== interaction (called by Player's hover/E)

func get_prompt() -> String:
	return "Drive %s" % kind.replace("-", " ")


func interact(by: Node) -> void:
	if by == null or Time.get_ticks_msec() - _last_toggle < TOGGLE_DEBOUNCE_MSEC:
		return
	var pid: int = int(by.get("peer_id"))
	if driver_id == 0:
		_request(true, pid)
	elif driver_id == pid:
		_request(false, pid)


func _online() -> bool:
	var peer := multiplayer.multiplayer_peer
	return peer != null and not (peer is OfflineMultiplayerPeer) \
		and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func _request(enter: bool, pid: int) -> void:
	_last_toggle = Time.get_ticks_msec()
	if not _online() or multiplayer.is_server():
		_server_handle(enter, pid)
	else:
		_rpc_request.rpc_id(1, enter)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request(enter: bool) -> void:
	if multiplayer.is_server():
		_server_handle(enter, multiplayer.get_remote_sender_id())


## Server-side validation. Never trusts a client-supplied peer id: callers pass the RPC sender.
func _server_handle(enter: bool, pid: int) -> void:
	var p := _player_of(pid)
	if enter:
		if driver_id != 0 or p == null or bool(p.get("is_dead")) or p.get("vehicle") != null:
			return
		if p.global_position.distance_to(global_position) > ENTER_RANGE + size.z * 0.5:
			return
		_broadcast_driver(pid)
	elif driver_id == pid:
		_broadcast_driver(0)


func _broadcast_driver(pid: int) -> void:
	if _online():
		_rpc_set_driver.rpc(pid)
	else:
		_apply_driver(pid)


@rpc("any_peer", "call_local", "reliable")
func _rpc_set_driver(pid: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return   # only the host may assign drivers
	_apply_driver(pid)


func _on_peer_disconnected(id: int) -> void:
	if multiplayer.is_server() and id == driver_id:
		_broadcast_driver(0)


func _player_of(pid: int) -> Node3D:
	if pid == 0:
		return null
	for p in get_tree().get_nodes_in_group("players"):
		if int(p.get("peer_id")) == pid:
			return p as Node3D
	return null


## Runs on every peer.
func _apply_driver(pid: int) -> void:
	_last_toggle = Time.get_ticks_msec()
	var old := _player_of(driver_id)
	if old != null:
		_release_player(old)
	driver_id = pid
	var np := _player_of(pid)
	if np != null:
		_seat_player(np)
	set_multiplayer_authority(pid if pid != 0 else 1, true)
	_update_sim_mode()
	_refresh_visibility()
	if pid == 0:
		throttle_in = 0.0
		steer_in = 0.0
		handbrake_in = 0.0


func _is_local_driver() -> bool:
	return driver_id != 0 and driver_id == multiplayer.get_unique_id()


func _seat_player(p: Node3D) -> void:
	p.set("vehicle", self)
	p.visible = false
	p.set("velocity", Vector3.ZERO)
	var w = p.get("weapons")
	if w != null and p.is_multiplayer_authority():
		w.set_process(false)
		w.set_process_unhandled_input(false)
	if p.is_multiplayer_authority():
		p.global_position = to_global(_seat)
		_start_driver_view()


func _release_player(p: Node3D) -> void:
	p.set("vehicle", null)
	p.visible = true
	var w = p.get("weapons")
	if w != null and p.is_multiplayer_authority():
		w.set_process(true)
		w.set_process_unhandled_input(true)
	if p.is_multiplayer_authority():
		p.global_position = _exit_pos()
		p.rotation.y = rotation.y
		p.set("velocity", Vector3.ZERO)
		_stop_driver_view(p)


## A spot beside the car (driver side first, then the other side, then behind) that has ground and a clear line.
func _exit_pos() -> Vector3:
	var space := get_world_3d().direct_space_state
	var b := global_transform.basis
	var from := global_position + Vector3.UP * 0.9
	var half := size.x * 0.5 + 0.9
	var back := -(b * FORWARD)
	for side in [-1.0, 1.0, 0.0]:
		var p: Vector3
		if side == 0.0:
			p = global_position + back * (size.z * 0.5 + 1.0)
		else:
			p = global_position + b.x * (half * float(side))
		var to := Vector3(p.x, from.y, p.z)
		if not space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1, [get_rid()])).is_empty():
			continue
		var r := space.intersect_ray(PhysicsRayQueryParameters3D.create(to + Vector3.UP * 2.0, to + Vector3.DOWN * 6.0, 1, [get_rid()]))
		if r.is_empty():
			continue
		return (r["position"] as Vector3) + Vector3.UP * 0.9
	return global_position + Vector3.UP * (size.y + 1.2)


# ================================================================== local driver view (camera + HUD)

func _start_driver_view() -> void:
	if _cam != null:
		return
	_cam = Camera3D.new()
	_cam.name = "ChaseCam"
	_cam.top_level = true
	_cam.fov = 75.0
	add_child(_cam)
	_cam.global_position = _chase_target()
	_cam.look_at(_focus(), Vector3.UP)
	_cam.current = true
	_hud = CanvasLayer.new()
	_hud.name = "VehicleHUD"
	_hud_label = Label.new()
	_hud_label.position = Vector2(24, 24)
	_hud_label.add_theme_font_size_override("font_size", 22)
	_hud_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_hud_label.add_theme_constant_override("outline_size", 6)
	_hud.add_child(_hud_label)
	add_child(_hud)


func _stop_driver_view(p: Node3D) -> void:
	if _cam != null:
		_cam.queue_free()
		_cam = null
	if _hud != null:
		_hud.queue_free()
		_hud = null
		_hud_label = null
	# Hand the view back: set_third_person re-asserts whichever of the two player cameras was in use.
	if p.has_method("set_third_person"):
		p.call("set_third_person", bool(p.get("third_person")))
	var pc = p.get("camera")
	if pc is Camera3D and not bool(p.get("third_person")):
		(pc as Camera3D).current = true


func _focus() -> Vector3:
	return global_position + Vector3.UP * (size.y * 0.7)


func _chase_target() -> Vector3:
	var back := -(global_transform.basis * FORWARD)
	back.y = 0.0
	back = back.normalized() if back.length() > 0.01 else Vector3.BACK
	return _focus() + back * (size.z * 0.5 + 4.5) + Vector3.UP * 1.6


func _process(delta: float) -> void:
	if _cam != null:
		_cam.global_position = _cam.global_position.lerp(_chase_target(), 1.0 - exp(-6.0 * delta))
		_cam.look_at(_focus(), Vector3.UP)
	if _hud_label != null:
		var kmh := linear_velocity.length() * 3.6
		_hud_label.text = "%s  %d km/h\nW/S throttle   A/D steer   Space handbrake   E exit" % [kind.replace("-", " "), int(kmh)]
	_spin_wheels(delta)


## Cosmetic: roll the model's wheel meshes with the physics wheels and turn the front pair with the steering.
func _spin_wheels(delta: float) -> void:
	for w in _wheels:
		var mesh = w["mesh"]
		if mesh == null or not is_instance_valid(mesh):
			continue
		var vw: VehicleWheel3D = w["vw"]
		var spin: float = float(w["spin"]) + vw.get_rpm() * TAU / 60.0 * delta
		w["spin"] = spin
		var steer: float = -steering if bool(w["front"]) else 0.0
		(mesh as Node3D).basis = Basis(Vector3.UP, steer) * Basis(Vector3.RIGHT, -spin)


# ================================================================== driving

func _axis(neg: String, pos: String) -> float:
	if not (InputMap.has_action(neg) and InputMap.has_action(pos)):
		return 0.0
	return Input.get_axis(neg, pos)


func _read_input() -> void:
	var live := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	throttle_in = _axis("move_back", "move_forward") if live else 0.0
	steer_in = _axis("move_right", "move_left") if live else 0.0
	handbrake_in = 1.0 if live and InputMap.has_action("jump") and Input.is_action_pressed("jump") else 0.0


func forward_speed() -> float:
	return linear_velocity.dot(global_transform.basis * FORWARD)


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	if driver_id == 0:
		engine_force = 0.0
		brake = PARK_BRAKE
		steering = move_toward(steering, 0.0, delta * 2.0)
		_check_flip(delta)
		return
	var p := _player_of(driver_id)
	if _is_local_driver() or scripted:
		if p != null and bool(p.get("is_dead")):
			_request(false, driver_id)
		if not scripted:
			_read_input()
	_drive(delta)
	if p != null and p.is_multiplayer_authority():
		p.global_position = to_global(_seat)
		p.set("velocity", Vector3.ZERO)
	_check_flip(delta)


func _drive(delta: float) -> void:
	var fwd := forward_speed()
	var unit := ENGINE_PER_MASS * mass
	var eng := 0.0
	var br := 0.0
	if throttle_in > 0.01:
		if fwd < -1.0:
			br = BRAKE_FORCE * throttle_in
		elif fwd < MAX_SPEED:
			eng = throttle_in * unit
	elif throttle_in < -0.01:
		if fwd > 1.0:
			br = BRAKE_FORCE * -throttle_in
		elif fwd > -MAX_REVERSE:
			eng = throttle_in * unit * 0.6
	else:
		br = COAST_BRAKE
	if handbrake_in > 0.5:
		br = HANDBRAKE
		eng = 0.0
	engine_force = -eng   # VehicleBody3D pushes toward +Z for positive force; this car drives toward -Z
	brake = br
	var max_st := lerpf(MAX_STEER, 0.05, clampf(absf(fwd) / 18.0, 0.0, 1.0))
	steering = move_toward(steering, steer_in * max_st, delta * 2.5)


## A car resting on its roof stands back up after a couple of seconds.
func _check_flip(delta: float) -> void:
	if global_transform.basis.y.y < 0.2 and linear_velocity.length() < 2.5:
		_flip_t += delta
		if _flip_t > 2.5:
			_flip_t = 0.0
			global_transform = Transform3D(Basis(Vector3.UP, rotation.y), global_position + Vector3.UP * 1.2)
			linear_velocity = Vector3.ZERO
			angular_velocity = Vector3.ZERO
	else:
		_flip_t = 0.0
