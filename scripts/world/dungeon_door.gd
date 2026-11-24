extends StaticBody3D
## An interactable dungeon door. Baked into scenes/world/baked/dungeon.tscn as Door_N (the bake-only
## tools/worldgen/dungeon_builder.gd originally built it with setup()): it reuses the leaf mesh
## ("wall_doorway_door") that ships inside wall_doorway.gltf, swings it on its hinge, and moves ONE leaf collider with
## the door state: closed = the leaf fills the opening, open = the leaf stands against the side wall (the opening is
## about 1.5 m clear). The open leaf keeps its collider so it can still be aimed at and closed with E.
## Contract (same as loot containers): group "interactable", interact(by) -> bool, get_prompt() -> String.
## Multiplayer: a client asks the host (_rpc_request), the host broadcasts _rpc_state to everyone, and a peer that
## joins late is sent the state of every open door when Net.peer_scene_ready fires. Every peer loads the same baked
## scene, so the Door_N node paths match. The exported is_open is the state the door starts in.

signal toggled(door, open)

const LEAF_SIZE := Vector3(1.9, 2.75, 0.5)
const LEAF_CX := 0.82            # leaf centre, measured from the hinge along the closed leaf
const SWING := -PI * 0.5
const ANIM_TIME := 0.35

@export var is_open: bool = false
@export var hinge_x: float = -0.82

var _pivot: Node3D
var _shape: CollisionShape3D
var _tween: Tween


## Call once. `leaf` is the wall_doorway_door node inside the placed doorway model (or null: collider only).
## This body must share the doorway model's transform so the leaf can move under it unchanged.
func setup(leaf: Node3D) -> void:
	_pivot = Node3D.new()
	_pivot.name = "Hinge"
	add_child(_pivot)
	if leaf != null:
		hinge_x = leaf.position.x
		_pivot.transform = leaf.transform
		leaf.get_parent().remove_child(leaf)
		_pivot.add_child(leaf)
		leaf.transform = Transform3D.IDENTITY
	else:
		_pivot.position = Vector3(hinge_x, 0.0, 0.0)
	_shape = CollisionShape3D.new()
	_shape.name = "Leaf"
	var bs := BoxShape3D.new()
	bs.size = LEAF_SIZE
	_shape.shape = bs
	add_child(_shape)
	_shape.transform = _shape_xf(false)


func _shape_xf(open: bool) -> Transform3D:
	if open:
		return Transform3D(Basis(Vector3.UP, SWING), Vector3(hinge_x, LEAF_SIZE.y * 0.5, LEAF_CX))
	return Transform3D(Basis(), Vector3(hinge_x + LEAF_CX, LEAF_SIZE.y * 0.5, 0.0))


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("dungeon_door")
	if _pivot == null:   # loaded from a baked scene: setup() did not run, the hinge and leaf are saved children
		_pivot = get_node_or_null("Hinge") as Node3D
		_shape = get_node_or_null("Leaf") as CollisionShape3D
		apply_open_state(is_open, false)   # same state: syncs hinge + collider to the exported flag, no toggled signal
	var net := get_node_or_null("/root/Net")
	if net != null and net.has_signal("peer_scene_ready"):
		net.peer_scene_ready.connect(_on_peer_ready)


func get_prompt() -> String:
	return "Close Door" if is_open else "Open Door"


func interact(_by = null) -> bool:
	if multiplayer.is_server():
		_server_set(not is_open)
	else:
		_rpc_request.rpc_id(1)
	return true


## Marks the door open or closed, moves the collider at once and animates the leaf. Safe to call on any peer.
func apply_open_state(open: bool, animate: bool = true) -> void:
	var changed := open != is_open
	is_open = open
	if _shape != null:
		_shape.transform = _shape_xf(open)
	if _pivot != null:
		var target: float = SWING if open else 0.0
		if _tween != null and _tween.is_valid():
			_tween.kill()
		if animate and is_inside_tree():
			_tween = create_tween()
			_tween.tween_property(_pivot, "rotation:y", target, ANIM_TIME).set_trans(Tween.TRANS_SINE)
		else:
			_pivot.rotation.y = target
	if changed:
		toggled.emit(self, open)


func _server_set(open: bool) -> void:
	if multiplayer.get_peers().is_empty():
		apply_open_state(open)
	else:
		_rpc_state.rpc(open)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request() -> void:
	if multiplayer.is_server():
		_server_set(not is_open)


@rpc("authority", "call_local", "reliable")
func _rpc_state(open: bool) -> void:
	apply_open_state(open)


func _on_peer_ready(id: int) -> void:
	if multiplayer.is_server() and is_open:
		_rpc_state.rpc_id(id, true)
