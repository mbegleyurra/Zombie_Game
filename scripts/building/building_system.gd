extends Node3D
## Dead Acres building system. Autoload name: "Building".
##
## Grid: CELL (2 m) squares in X/Z, vertical snap of YSTEP. A piece lives in a
## slot, keyed by Vector4i(cell_x, y_step, cell_z, slot):
##   slot 0 = floor (cell centre)
##   slot 1 = wall-type piece on the cell's min-Z edge (runs along X)
##   slot 2 = wall-type piece on the cell's min-X edge (runs along Z)
## Wall-type kinds: wall, door, window, barricade (one per slot).
##
## The server validates every request (kind, slot, occupancy, reach, materials)
## and broadcasts the result by RPC. Late joiners receive a full snapshot.
##
## Keys (read directly, no InputMap changes): B build mode, 1-5 / wheel select,
## LMB place, X or RMB remove, F open/close the door you are looking at.
## Player/weapon code should not fire while Building.build_mode is true.

signal piece_placed(id: int, kind: String)
signal piece_removed(id: int)
signal mode_changed(on: bool)
signal selection_changed(kind: String)
signal stock_changed(stock: Dictionary)
signal build_rejected(reason: String)
signal prompt_changed(text: String)
signal crafted(recipe_id: String)

const CELL := 2.0
const WALL_H := 2.5
const YSTEP := 0.25
const REACH := 8.0
const USE_REACH := 4.0
const SLOT_FLOOR := 0
const SLOT_EDGE_X := 1
const SLOT_EDGE_Z := 2
const SLOT_BENCH := 3   ## workbench on the cell centre; shares the cell with a floor piece

const Recipes := preload("res://scripts/world/recipes.gd")
const CraftingUI := preload("res://scripts/ui/crafting_ui.gd")
const Extras := preload("res://scripts/building/building_extras.gd")
const BaseSystem := preload("res://scripts/building/base_system.gd")

const KINDS: Array[String] = ["wall", "floor", "door", "window", "barricade", "workbench", "stairs", "base_core", "chest", "assembler"]
const DEFS := {
	"wall": {"cost": {"planks": 4}, "hp": 200.0, "slot": "edge"},
	"floor": {"cost": {"planks": 3}, "hp": 150.0, "slot": "floor"},
	"door": {"cost": {"planks": 4, "scrap": 2}, "hp": 120.0, "slot": "edge"},
	"window": {"cost": {"planks": 3, "scrap": 1}, "hp": 150.0, "slot": "edge"},
	"barricade": {"cost": {"planks": 2, "scrap": 1}, "hp": 80.0, "slot": "edge"},
	"workbench": {"cost": {"planks": 8, "scrap": 6}, "hp": 250.0, "slot": "bench"},
	"stairs": Extras.DEFS["stairs"],
	"base_core": Extras.DEFS["base_core"],
	"chest": Extras.DEFS["chest"],
	"assembler": Extras.DEFS["assembler"],
}

const COL_WOOD := Color(0.55, 0.38, 0.2)
const COL_WOOD_DARK := Color(0.4, 0.27, 0.14)
const COL_WOOD_LIGHT := Color(0.64, 0.47, 0.27)
const COL_SCRAP := Color(0.45, 0.47, 0.5)

## id -> {kind, key, hp, open, node}
var pieces := {}
## slot key (Vector4i) -> piece id
var slots := {}
## Server only: peer id -> {planks, scrap}
var stock := {}
## This peer's own materials (mirrored from the server) for HUD/ghost.
var local_stock := {"planks": 0, "scrap": 0}
var starting_stock := {"planks": 20, "scrap": 10}
## Optional external inventory. take_hook(peer, cost: Dictionary, commit: bool) -> bool
## checks (commit=false) or spends (commit=true). give_hook(peer, item, n) refunds.
var take_hook := Callable()
var give_hook := Callable()
var build_mode := false
var selected := 0
## Base layer (core, chests, assemblers): scripts/building/base_system.gd
var base: Node = null

var _net = null
var _next_id := 1
var _ghost: Node3D = null
var _ghost_kind := ""
var _ghost_key := Vector4i.ZERO
var _ghost_valid := false
var _tint_state := -1
var _ghost_ok_mat: StandardMaterial3D
var _ghost_bad_mat: StandardMaterial3D
var _mats := {}
var _prompt := ""
var _craft_ui: Control = null


func _ready() -> void:
	_ghost_ok_mat = _make_ghost_mat(Color(0.2, 1.0, 0.3, 0.45))
	_ghost_bad_mat = _make_ghost_mat(Color(1.0, 0.2, 0.2, 0.45))
	_net = get_node_or_null("/root/Net")
	base = BaseSystem.new()
	base.name = "BaseSystem"
	add_child(base)
	if _net != null:
		_net.hosted.connect(_on_hosted)
		_net.player_connected.connect(_on_player_connected)
		_net.player_disconnected.connect(_on_player_left)
		_net.left.connect(clear_all)


# ---------------------------------------------------------------- public API

func current_kind() -> String:
	return KINDS[selected]


func set_build_mode(on: bool) -> void:
	if build_mode == on:
		return
	build_mode = on
	if not on:
		_hide_ghost()
	mode_changed.emit(on)


func select_kind(kind: String) -> void:
	var idx := KINDS.find(kind)
	if idx < 0 or idx == selected:
		return
	selected = idx
	selection_changed.emit(kind)


func cycle(dir: int) -> void:
	selected = posmod(selected + dir, KINDS.size())
	selection_changed.emit(KINDS[selected])


func key_position(key: Vector4i) -> Vector3:
	var y := key.y * YSTEP
	if Extras.is_stair_slot(key.w):
		return Vector3((key.x + 0.5) * CELL, y, (key.z + 0.5) * CELL)
	match key.w:
		SLOT_FLOOR, SLOT_BENCH:
			return Vector3((key.x + 0.5) * CELL, y, (key.z + 0.5) * CELL)
		SLOT_EDGE_X:
			return Vector3((key.x + 0.5) * CELL, y, key.z * CELL)
		_:
			return Vector3(key.x * CELL, y, (key.z + 0.5) * CELL)


func key_yaw(key: Vector4i) -> float:
	if Extras.is_stair_slot(key.w):
		return Extras.stair_yaw(key.w - Extras.SLOT_STAIR)
	return PI * 0.5 if key.w == SLOT_EDGE_Z else 0.0


func request_place(kind: String, key: Vector4i) -> void:
	if not _in_game():
		return
	if _net.is_host():
		_server_place(1, kind, key)
	else:
		_rpc_request_place.rpc_id(1, kind, key)


func request_remove(id: int) -> void:
	if not _in_game():
		return
	if _net.is_host():
		_server_remove(1, id)
	else:
		_rpc_request_remove.rpc_id(1, id)


func request_toggle(id: int) -> void:
	if not _in_game():
		return
	if _net.is_host():
		_server_toggle(1, id)
	else:
		_rpc_request_toggle.rpc_id(1, id)


## Server only. Zombies call this to chew through barricades and walls.
func damage_piece(id: int, amount: float) -> void:
	if not _server() or not pieces.has(id):
		return
	pieces[id]["hp"] = float(pieces[id]["hp"]) - amount
	if pieces[id]["hp"] <= 0.0:
		_rpc_remove.rpc(id)


## Loot pickups call this on the picking peer: Building.give("planks", 3).
## Clients ask the host to credit them; only planks/scrap count.
## Legacy server form give(peer, item, n) still works (main.gd uses it).
func give(a, b, c = 0) -> void:
	var item: String
	var n: int
	var peer := 0
	if a is String:
		item = a
		n = int(b)
		peer = int(c)
	else:
		peer = int(a)
		item = String(b)
		n = int(c)
	if not _in_game() or n <= 0 or not (item == "planks" or item == "scrap"):
		return
	if not _server():
		if peer == 0 or peer == _net.local_id():
			_rpc_request_give.rpc_id(1, item, n)
		return
	if peer == 0:
		peer = 1
	if give_hook.is_valid():
		give_hook.call(peer, item, n)
		return
	var s: Dictionary = stock.get(peer, {"planks": 0, "scrap": 0})
	s[item] = int(s.get(item, 0)) + n
	stock[peer] = s
	_push_stock(peer)


func clear_all() -> void:
	for id in pieces.keys():
		var n = pieces[id]["node"]
		if is_instance_valid(n):
			n.queue_free()
	pieces.clear()
	slots.clear()
	stock.clear()
	base.clear()
	_next_id = 1
	_set_local_stock({"planks": 0, "scrap": 0})
	if _ghost != null:
		_ghost.queue_free()
		_ghost = null
		_ghost_kind = ""
	build_mode = false
	if _craft_ui != null:
		_craft_ui.close(false)
	_set_prompt("")


# --------------------------------------------------------------------- input

func _input(event: InputEvent) -> void:
	if not _in_game() or _ui_open():
		return
	if event is InputEventKey:
		var ke := event as InputEventKey
		if not ke.pressed or ke.echo:
			return
		if ke.physical_keycode == KEY_B:
			set_build_mode(not build_mode)
		elif ke.physical_keycode == KEY_F:
			_try_toggle_door()
		elif ke.physical_keycode == KEY_E:
			_try_use_bench()
		elif build_mode and ke.physical_keycode == KEY_X:
			_try_remove()
		elif build_mode:
			var idx: int = 9 if ke.physical_keycode == KEY_0 else ke.physical_keycode - KEY_1   # KEY_0 picks the 10th kind
			if idx >= 0 and idx < KINDS.size():
				select_kind(KINDS[idx])
	elif build_mode and event is InputEventMouseButton:
		var me := event as InputEventMouseButton
		if not me.pressed:
			return
		match me.button_index:
			MOUSE_BUTTON_LEFT:
				if _ghost_valid:
					request_place(KINDS[selected], _ghost_key)
				else:
					build_rejected.emit("Cannot place there")
				get_viewport().set_input_as_handled()
			MOUSE_BUTTON_RIGHT:
				_try_remove()
				get_viewport().set_input_as_handled()
			MOUSE_BUTTON_WHEEL_UP:
				cycle(-1)
			MOUSE_BUTTON_WHEEL_DOWN:
				cycle(1)


func _physics_process(_delta: float) -> void:
	if not _in_game():
		_hide_ghost()
		_set_prompt("")
		return
	var hit := _aim(REACH)
	_update_prompt(hit)
	if not build_mode or hit.is_empty():
		_hide_ghost()
		return
	var kind := KINDS[selected]
	_ensure_ghost(kind)
	_ghost_key = _compute_key(hit, kind)
	_ghost.position = key_position(_ghost_key)
	_ghost.rotation.y = key_yaw(_ghost_key)
	_ghost.visible = true
	_ghost_valid = not slots.has(_ghost_key) and _local_can_afford(kind)
	var state := 1 if _ghost_valid else 0
	if state != _tint_state:
		_tint_state = state
		_tint(_ghost, _ghost_ok_mat if _ghost_valid else _ghost_bad_mat)


func _try_toggle_door() -> void:
	var id := _aimed_piece_id(USE_REACH)
	if id != 0 and pieces.has(id) and pieces[id]["kind"] == "door":
		request_toggle(id)


func _try_remove() -> void:
	var id := _aimed_piece_id(REACH)
	if id != 0:
		request_remove(id)


func _try_use_bench() -> void:
	var id := _aimed_piece_id(USE_REACH)
	if id == 0 or not pieces.has(id):
		return
	if pieces[id]["kind"] == "workbench":
		open_crafting()
	else:
		base.use_piece(id)


## Opens the workbench crafting overlay (scripts/ui/crafting_ui.gd), creating it on first use.
func open_crafting() -> void:
	if _craft_ui == null:
		var layer := CanvasLayer.new()
		layer.layer = 60
		add_child(layer)
		_craft_ui = CraftingUI.new()
		layer.add_child(_craft_ui)
	_craft_ui.open()


## True when this peer's own stock (or the external take_hook) can pay `cost`.
func can_afford_cost(cost: Dictionary) -> bool:
	if take_hook.is_valid():
		return true
	for item in cost:
		if int(local_stock.get(item, 0)) < int(cost[item]):
			return false
	return true


func request_craft(recipe_id: String) -> void:
	if not _in_game():
		return
	if _server():
		_server_craft(1, recipe_id)
	else:
		_rpc_request_craft.rpc_id(1, recipe_id)


## Server only: materials are taken here, then the owning peer is told to add the result.
func _server_craft(peer: int, recipe_id: String) -> void:
	var r := Recipes.get_recipe(recipe_id)
	if r.is_empty():
		_reject(peer, "Unknown recipe")
		return
	if not _near_bench(peer):
		_reject(peer, "Need a workbench nearby")
		return
	var cost: Dictionary = r["cost"]
	if not _take(peer, cost, false):
		_reject(peer, "Not enough materials")
		return
	_take(peer, cost, true)
	if peer == 1:
		_deliver(recipe_id)
	else:
		_rpc_crafted.rpc_id(peer, recipe_id)


func _near_bench(peer: int) -> bool:
	for id in pieces:
		if pieces[id]["kind"] == "workbench" and not _too_far(peer, key_position(pieces[id]["key"]), USE_REACH + 3.0):
			return true
	return false


## Runs on the crafting peer: hands the result to its own player (inventory is peer-owned).
func _deliver(recipe_id: String) -> void:
	var r := Recipes.get_recipe(recipe_id)
	var pl: Node = _net.get_local_player() if _net != null else null
	if not r.is_empty() and pl != null and pl.has_method("add_item"):
		pl.add_item(String(r["give"]), int(r["count"]))
	crafted.emit(recipe_id)


# ------------------------------------------------------------------- aiming

func _in_game() -> bool:
	return _net != null and _net.active


## The pause menu / loot panel own the mouse; clicks must not place or remove pieces.
func _ui_open() -> bool:
	var hud := get_node_or_null("/root/Hud")
	return hud != null and hud.has_method("is_ui_open") and bool(hud.is_ui_open())


func _server() -> bool:
	return _net != null and _net.is_host()


func _aim(reach: float) -> Dictionary:
	var vp := get_viewport()
	if vp == null:
		return {}
	var cam := vp.get_camera_3d()
	if cam == null:
		return {}
	var center := vp.get_visible_rect().size * 0.5
	var from := cam.project_ray_origin(center)
	var to := from + cam.project_ray_normal(center) * reach
	var q := PhysicsRayQueryParameters3D.create(from, to)
	var lp: Node = _net.get_local_player() if _net != null else null
	if lp is CollisionObject3D:
		q.exclude = [(lp as CollisionObject3D).get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		hit["from"] = from
	return hit


func _aimed_piece_id(reach: float) -> int:
	var hit := _aim(reach)
	if hit.is_empty():
		return 0
	return _piece_id_of(hit["collider"])


func _piece_id_of(node: Node) -> int:
	var n: Node = node
	while n != null and n != self:
		if n.has_meta("piece_id"):
			return int(n.get_meta("piece_id"))
		n = n.get_parent()
	return 0


func _update_prompt(hit: Dictionary) -> void:
	var text := ""
	if not hit.is_empty() and Vector3(hit["from"]).distance_to(hit["position"]) <= USE_REACH:
		var id := _piece_id_of(hit["collider"])
		if id != 0 and pieces.has(id) and pieces[id]["kind"] == "door":
			text = "[F] Close door" if pieces[id]["open"] else "[F] Open door"
		elif id != 0 and pieces.has(id) and pieces[id]["kind"] == "workbench":
			text = "[E] Use workbench"
		elif id != 0 and pieces.has(id):
			text = base.prompt_for(String(pieces[id]["kind"]))
		_set_prompt(text)


func _set_prompt(text: String) -> void:
	if text != _prompt:
		_prompt = text
		prompt_changed.emit(text)


func _compute_key(hit: Dictionary, kind: String) -> Vector4i:
	var p: Vector3 = hit["position"]
	var nrm: Vector3 = hit["normal"]
	p.x += nrm.x * 0.1
	p.z += nrm.z * 0.1
	var yk := roundi(p.y / YSTEP)
	var other := _piece_id_of(hit["collider"])
	if other != 0 and nrm.y < 0.5 and pieces.has(other):
		yk = (pieces[other]["key"] as Vector4i).y
	var gx := floori(p.x / CELL)
	var gz := floori(p.z / CELL)
	if other != 0 and pieces.has(other) and pieces[other]["kind"] == "stairs" and (kind == "floor" or kind == "stairs"):
		var sk: Vector4i = pieces[other]["key"]
		return Extras.landing_key(sk) if kind == "floor" else Extras.chain_key(sk)
	if DEFS[kind]["slot"] == "stair":
		return Extras.stair_key(gx, yk, gz, hit["from"], hit["position"])
	if DEFS[kind]["slot"] == "bench":
		return Vector4i(gx, yk, gz, SLOT_BENCH)
	if DEFS[kind]["slot"] == "floor":
		return Vector4i(gx, yk, gz, SLOT_FLOOR)
	var fx := p.x / CELL - gx
	var fz := p.z / CELL - gz
	var d: Array[float] = [fz, 1.0 - fz, fx, 1.0 - fx]
	var best := 0
	for i in 4:
		if d[i] < d[best]:
			best = i
	match best:
		0:
			return Vector4i(gx, yk, gz, SLOT_EDGE_X)
		1:
			return Vector4i(gx, yk, gz + 1, SLOT_EDGE_X)
		2:
			return Vector4i(gx, yk, gz, SLOT_EDGE_Z)
		_:
			return Vector4i(gx + 1, yk, gz, SLOT_EDGE_Z)


func _local_can_afford(kind: String) -> bool:
	if take_hook.is_valid():
		return true
	var cost: Dictionary = DEFS[kind]["cost"]
	for item in cost:
		if int(local_stock.get(item, 0)) < int(cost[item]):
			return false
	return true


# ------------------------------------------------------------ server logic

func _reject(peer: int, reason: String) -> void:
	if peer == 1:
		build_rejected.emit(reason)
	else:
		_rpc_reject.rpc_id(peer, reason)


func _too_far(peer: int, pos: Vector3, reach: float) -> bool:
	var pl = _net.players.get(peer)
	if pl != null and is_instance_valid(pl) and pl is Node3D:
		return (pl as Node3D).global_position.distance_to(pos) > reach
	return false  # no player node to measure against (e.g. headless tests)


func _server_place(peer: int, kind: String, key: Vector4i) -> void:
	if not DEFS.has(kind):
		_reject(peer, "Unknown piece")
		return
	var slot_kind: String = DEFS[kind]["slot"]
	var bad_slot := false
	if slot_kind == "floor":
		bad_slot = key.w != SLOT_FLOOR
	elif slot_kind == "bench":
		bad_slot = key.w != SLOT_BENCH
	elif slot_kind == "stair":
		bad_slot = not Extras.is_stair_slot(key.w)
	else:
		bad_slot = key.w != SLOT_EDGE_X and key.w != SLOT_EDGE_Z
	if bad_slot:
		_reject(peer, "Bad slot")
		return
	if absi(key.x) > 4096 or absi(key.z) > 4096 or absi(key.y) > 4000:
		_reject(peer, "Out of bounds")
		return
	if slots.has(key):
		_reject(peer, "Occupied")
		return
	var why := Extras.validate(self, kind, key)
	if why != "":
		_reject(peer, why)
		return
	if _too_far(peer, key_position(key), REACH + 4.0):
		_reject(peer, "Too far")
		return
	var cost: Dictionary = DEFS[kind]["cost"]
	if not _take(peer, cost, false):
		_reject(peer, "Not enough materials")
		return
	_take(peer, cost, true)
	var id := _next_id
	_next_id += 1
	_rpc_place.rpc(id, kind, key, float(DEFS[kind]["hp"]), false)


func _server_remove(peer: int, id: int) -> void:
	if not pieces.has(id):
		return
	var info: Dictionary = pieces[id]
	if _too_far(peer, key_position(info["key"]), REACH + 4.0):
		_reject(peer, "Too far")
		return
	var blocked: String = base.remove_blocked(id)
	if blocked != "":
		_reject(peer, blocked)
		return
	var cost: Dictionary = DEFS[info["kind"]]["cost"]
	for item in cost:
		give(item, int(int(cost[item]) * 0.5), peer)
	_rpc_remove.rpc(id)


func _server_toggle(peer: int, id: int) -> void:
	if not pieces.has(id) or pieces[id]["kind"] != "door":
		return
	if _too_far(peer, key_position(pieces[id]["key"]), USE_REACH + 3.0):
		return
	_rpc_door.rpc(id, not pieces[id]["open"])


func _take(peer: int, cost: Dictionary, commit: bool) -> bool:
	if take_hook.is_valid():
		return take_hook.call(peer, cost, commit)
	var s: Dictionary = stock.get(peer, {})
	for item in cost:
		if int(s.get(item, 0)) < int(cost[item]):
			return false
	if commit:
		for item in cost:
			s[item] = int(s.get(item, 0)) - int(cost[item])
		stock[peer] = s
		_push_stock(peer)
	return true


func _push_stock(peer: int) -> void:
	if take_hook.is_valid() or give_hook.is_valid():
		return
	var s: Dictionary = stock.get(peer, {"planks": 0, "scrap": 0})
	if peer == 1:
		_set_local_stock(s)
	else:
		_rpc_stock.rpc_id(peer, int(s.get("planks", 0)), int(s.get("scrap", 0)))


func _set_local_stock(s: Dictionary) -> void:
	local_stock = {"planks": int(s.get("planks", 0)), "scrap": int(s.get("scrap", 0))}
	stock_changed.emit(local_stock)


func _on_hosted(_port: int) -> void:
	stock[1] = starting_stock.duplicate()
	_push_stock(1)


func _on_player_connected(id: int) -> void:
	if not _server():
		return
	stock[id] = starting_stock.duplicate()
	var snapshot := []
	for pid in pieces:
		var info: Dictionary = pieces[pid]
		snapshot.append([pid, info["kind"], info["key"], info["hp"], info["open"]])
	_rpc_full_sync.rpc_id(id, snapshot)
	_push_stock(id)


func _on_player_left(id: int) -> void:
	stock.erase(id)


# ---------------------------------------------------------------------- RPCs

@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_place(kind: String, key: Vector4i) -> void:
	if _server():
		_server_place(multiplayer.get_remote_sender_id(), kind, key)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_remove(id: int) -> void:
	if _server():
		_server_remove(multiplayer.get_remote_sender_id(), id)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_toggle(id: int) -> void:
	if _server():
		_server_toggle(multiplayer.get_remote_sender_id(), id)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_give(item: String, n: int) -> void:
	if _server():
		give(item, mini(n, 100), multiplayer.get_remote_sender_id())


@rpc("authority", "call_local", "reliable")
func _rpc_place(id: int, kind: String, key: Vector4i, hp: float, open: bool) -> void:
	_add_piece(id, kind, key, hp, open)


@rpc("authority", "call_local", "reliable")
func _rpc_remove(id: int) -> void:
	_drop_piece(id)


@rpc("authority", "call_local", "reliable")
func _rpc_door(id: int, open: bool) -> void:
	if not pieces.has(id):
		return
	pieces[id]["open"] = open
	_apply_door(pieces[id]["node"], open, true)


@rpc("authority", "call_remote", "reliable")
func _rpc_full_sync(snapshot: Array) -> void:
	# The snapshot is authoritative: drop anything the host no longer has.
	var keep := {}
	for e in snapshot:
		keep[int(e[0])] = true
	for id in pieces.keys():
		if not keep.has(id):
			_drop_piece(id)
	for e in snapshot:
		_add_piece(int(e[0]), String(e[1]), e[2], float(e[3]), bool(e[4]))


@rpc("authority", "call_remote", "reliable")
func _rpc_stock(planks: int, scrap: int) -> void:
	_set_local_stock({"planks": planks, "scrap": scrap})


@rpc("authority", "call_remote", "reliable")
func _rpc_reject(reason: String) -> void:
	build_rejected.emit(reason)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_craft(recipe_id: String) -> void:
	if _server():
		_server_craft(multiplayer.get_remote_sender_id(), recipe_id)


@rpc("authority", "call_remote", "reliable")
func _rpc_crafted(recipe_id: String) -> void:
	_deliver(recipe_id)


# --------------------------------------------------------------- piece nodes

func _add_piece(id: int, kind: String, key: Vector4i, hp: float, open: bool) -> void:
	if pieces.has(id) or not DEFS.has(kind):
		return
	var node := _make_piece(kind, false)
	node.set_meta("piece_id", id)
	node.add_to_group("building")
	if kind == "workbench":
		node.add_to_group("workbench")
	if kind == "barricade" or kind == "wall" or kind == "door" or kind == "window":
		node.add_to_group("breakable_" + kind)
	add_child(node)
	node.position = key_position(key)
	node.rotation.y = key_yaw(key)
	pieces[id] = {"kind": kind, "key": key, "hp": hp, "open": open, "node": node}
	slots[key] = id
	if open:
		_apply_door(node, true, false)
	piece_placed.emit(id, kind)


func _drop_piece(id: int) -> void:
	if not pieces.has(id):
		return
	var info: Dictionary = pieces[id]
	slots.erase(info["key"])
	if is_instance_valid(info["node"]):
		info["node"].queue_free()
	pieces.erase(id)
	piece_removed.emit(id)


func _apply_door(node: Node3D, open: bool, animate: bool) -> void:
	var hinge := node.get_node_or_null("Hinge") as Node3D
	if hinge == null:
		return
	var target := deg_to_rad(-100.0) if open else 0.0
	if animate and is_inside_tree():
		create_tween().tween_property(hinge, "rotation:y", target, 0.25)
	else:
		hinge.rotation.y = target


func _make_piece(kind: String, ghost: bool) -> Node3D:
	var root: Node3D
	if ghost:
		root = Node3D.new()
	else:
		root = StaticBody3D.new()
	var half := WALL_H * 0.5
	match kind:
		"wall":
			_box(root, Vector3(CELL, WALL_H, 0.2), Vector3(0, half, 0), COL_WOOD, ghost)
			_box(root, Vector3(CELL, 0.12, 0.26), Vector3(0, 0.5, 0), COL_WOOD_DARK, ghost, false)
			_box(root, Vector3(CELL, 0.12, 0.26), Vector3(0, 1.25, 0), COL_WOOD_DARK, ghost, false)
			_box(root, Vector3(CELL, 0.12, 0.26), Vector3(0, 2.0, 0), COL_WOOD_DARK, ghost, false)
		"floor":
			for i in 4:
				var col := COL_WOOD_LIGHT if i % 2 == 0 else COL_WOOD
				_box(root, Vector3(CELL, 0.15, CELL * 0.25 - 0.02), Vector3(0, -0.075, -0.75 + i * 0.5), col, ghost)
		"window":
			_box(root, Vector3(CELL, 0.9, 0.2), Vector3(0, 0.45, 0), COL_WOOD, ghost)
			_box(root, Vector3(CELL, 0.5, 0.2), Vector3(0, WALL_H - 0.25, 0), COL_WOOD, ghost)
			_box(root, Vector3(0.3, 1.1, 0.2), Vector3(-0.85, 1.45, 0), COL_WOOD_DARK, ghost)
			_box(root, Vector3(0.3, 1.1, 0.2), Vector3(0.85, 1.45, 0), COL_WOOD_DARK, ghost)
		"door":
			_box(root, Vector3(0.4, WALL_H, 0.2), Vector3(-0.8, half, 0), COL_WOOD_DARK, ghost)
			_box(root, Vector3(0.4, WALL_H, 0.2), Vector3(0.8, half, 0), COL_WOOD_DARK, ghost)
			_box(root, Vector3(1.2, 0.5, 0.2), Vector3(0, WALL_H - 0.25, 0), COL_WOOD_DARK, ghost)
			var hinge := Node3D.new()
			hinge.name = "Hinge"
			hinge.position = Vector3(-0.6, 0, 0)
			root.add_child(hinge)
			var leaf: Node3D
			if ghost:
				leaf = Node3D.new()
			else:
				leaf = StaticBody3D.new()
			leaf.name = "Leaf"
			hinge.add_child(leaf)
			_box(leaf, Vector3(1.2, 2.0, 0.1), Vector3(0.6, 1.0, 0), COL_WOOD_LIGHT, ghost)
			_box(leaf, Vector3(0.1, 0.1, 0.14), Vector3(1.0, 1.0, 0), COL_SCRAP, ghost, false)
		"barricade":
			var ys := [0.55, 1.05, 1.55]
			var tilt := [0.04, -0.05, 0.03]
			for i in 3:
				var b := _box(root, Vector3(1.9, 0.22, 0.1), Vector3(0, ys[i], 0.03 * (i % 2 * 2 - 1)), COL_WOOD_DARK if i % 2 == 0 else COL_WOOD, ghost, false)
				b.rotation.z = tilt[i]
			_box(root, Vector3(0.12, 1.5, 0.12), Vector3(-0.8, 0.85, 0), COL_SCRAP, ghost, false)
			_box(root, Vector3(0.12, 1.5, 0.12), Vector3(0.8, 0.85, 0), COL_SCRAP, ghost, false)
			if not ghost:
				var cs := CollisionShape3D.new()
				var bs := BoxShape3D.new()
				bs.size = Vector3(CELL - 0.1, 1.6, 0.3)
				cs.shape = bs
				cs.position = Vector3(0, 0.9, 0)
				root.add_child(cs)
		"workbench":
			_box(root, Vector3(1.5, 0.1, 0.8), Vector3(0, 0.9, 0), COL_WOOD_LIGHT, ghost)          # top slab
			for sx in [-0.65, 0.65]:
				for sz in [-0.3, 0.3]:
					_box(root, Vector3(0.12, 0.85, 0.12), Vector3(sx, 0.425, sz), COL_WOOD_DARK, ghost)  # legs
			_box(root, Vector3(1.4, 0.06, 0.7), Vector3(0, 0.3, 0), COL_WOOD, ghost, false)        # lower shelf
			_box(root, Vector3(0.2, 0.14, 0.14), Vector3(-0.5, 1.02, -0.2), COL_SCRAP, ghost, false)  # vise
			_box(root, Vector3(0.05, 0.05, 0.4), Vector3(0.3, 0.98, 0.0), COL_SCRAP, ghost, false)    # tool bar
		"stairs", "base_core", "chest", "assembler":
			Extras.build_piece(self, root, kind, ghost)
	return root


func _box(parent: Node3D, size: Vector3, pos: Vector3, color: Color, ghost: bool, collide := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	if ghost:
		mi.material_override = _ghost_ok_mat
	else:
		mi.material_override = _mat(color)
	parent.add_child(mi)
	if not ghost and collide and parent is CollisionObject3D:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		cs.position = pos
		parent.add_child(cs)
	return mi


func _mat(color: Color) -> StandardMaterial3D:
	if not _mats.has(color):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 1.0
		_mats[color] = m
	return _mats[color]


func _make_ghost_mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _ensure_ghost(kind: String) -> void:
	if _ghost != null and _ghost_kind == kind:
		return
	if _ghost != null:
		_ghost.queue_free()
	_ghost = _make_piece(kind, true)
	_ghost_kind = kind
	_tint_state = -1
	add_child(_ghost)


func _hide_ghost() -> void:
	_ghost_valid = false
	if _ghost != null:
		_ghost.visible = false


func _tint(node: Node, mat: Material) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = mat
	for c in node.get_children():
		_tint(c, mat)
