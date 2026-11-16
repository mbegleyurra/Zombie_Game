extends Node
## Base layer for Building: base core (claim marker), storage chests and assemblers.
## Created by Building as its child "BaseSystem" (Building.base). State is host-authoritative:
##   chests: piece id -> {item id: count}      (materials in, products out)
##   asms:   piece id -> {recipe, enabled, working, elapsed, duration, status, produced}
## Clients send requests (set recipe, pause, deposit, withdraw); the host validates reach, materials and
## space, changes the state and broadcasts it. Late joiners get a full snapshot on connect. Clients only
## advance `elapsed` locally so the progress bar moves between host updates.
##
## An assembler works from the nearest chest within LINK_RANGE: it takes the recipe's cost out of the
## chest when a cycle starts and puts the product in when the cycle ends (planks/scrap -> ammo, rifles, ...).
## No chest, no materials or a full chest just changes its status; nothing is lost or created.
## time_scale > 1 speeds cycles up (tests only).

signal chest_changed(id: int)
signal assembler_changed(id: int)
signal base_changed()

const Recipes := preload("res://scripts/world/recipes.gd")
const ItemDB := preload("res://scripts/world/item_db.gd")
const Extras := preload("res://scripts/building/building_extras.gd")
const BaseUI := preload("res://scripts/building/base_ui.gd")

const CHEST_CAP := 400          ## total items one chest holds
const LINK_RANGE := 6.0         ## metres from an assembler to the chest it feeds from
const CLAIM_RADIUS := 24.0      ## metres around the core that count as "the base"
const MAX_MOVE := 100           ## items per deposit / withdraw request
const USE_SLACK := 3.0          ## extra reach on top of Building.USE_REACH

var chests := {}
var asms := {}
var core_id := 0
var time_scale := 1.0

var _b: Node = null
var _net = null
var _ui: Control = null
## "peer|item" -> items the host handed to a peer that the peer has not confirmed yet.
var _pending := {}


func _ready() -> void:
	_b = get_parent()
	_net = get_node_or_null("/root/Net")
	_b.piece_placed.connect(_on_piece_placed)
	_b.piece_removed.connect(_on_piece_removed)
	if _net != null:
		_net.player_connected.connect(_on_player_connected)


# ---------------------------------------------------------------- public API

func prompt_for(kind: String) -> String:
	match kind:
		"chest":
			return "[E] Open chest"
		"assembler":
			return "[E] Use assembler"
		"base_core":
			return "[E] Base overview"
	return ""


## E on a base piece: opens its overlay. False when the piece has none.
func use_piece(id: int) -> bool:
	var info = _b.pieces.get(id)
	if info == null:
		return false
	var kind := String(info["kind"])
	if kind != "chest" and kind != "assembler" and kind != "base_core":
		return false
	open_ui(id, "core" if kind == "base_core" else kind)
	return true


func open_ui(id: int, mode: String) -> void:
	if _ui == null:
		var layer := CanvasLayer.new()
		layer.layer = 61
		add_child(layer)
		_ui = BaseUI.new()
		_ui.base = self
		layer.add_child(_ui)
	_ui.open_for(id, mode)


func clear() -> void:
	chests.clear()
	asms.clear()
	_pending.clear()
	core_id = 0
	if _ui != null:
		_ui.close(false)


func request_set_recipe(asm_id: int, recipe_id: String) -> void:
	if not _b._in_game():
		return
	if _b._server():
		_server_set_recipe(1, asm_id, recipe_id)
	else:
		_rpc_req_recipe.rpc_id(1, asm_id, recipe_id)


func request_toggle(asm_id: int) -> void:
	if not _b._in_game():
		return
	if _b._server():
		_server_toggle(1, asm_id)
	else:
		_rpc_req_toggle.rpc_id(1, asm_id)


func request_deposit(chest_id: int, item: String, n: int) -> void:
	if not _b._in_game():
		return
	if _b._server():
		_server_deposit(1, chest_id, item, n)
	else:
		_rpc_req_deposit.rpc_id(1, chest_id, item, n)


func request_withdraw(chest_id: int, item: String, n: int) -> void:
	if not _b._in_game():
		return
	if _b._server():
		_server_withdraw(1, chest_id, item, n)
	else:
		_rpc_req_withdraw.rpc_id(1, chest_id, item, n)


## "" when the piece can be taken down, else why not (Building._server_remove asks this).
func remove_blocked(id: int) -> String:
	if chests.has(id) and chest_total(id) > 0:
		return "Empty the chest first"
	if asms.has(id) and bool(asms[id]["working"]):
		return "Assembler busy"
	return ""


## The nearest chest within LINK_RANGE of an assembler (0 = none).
func linked_chest(asm_id: int) -> int:
	var info = _b.pieces.get(asm_id)
	if info == null:
		return 0
	var p: Vector3 = _b.key_position(info["key"])
	var best := 0
	var best_d := LINK_RANGE
	for cid in chests:
		var ci = _b.pieces.get(cid)
		if ci == null:
			continue
		var d := p.distance_to(_b.key_position(ci["key"]))
		if d <= best_d:
			best_d = d
			best = int(cid)
	return best


func chest_total(cid: int) -> int:
	var n := 0
	var items: Dictionary = chests.get(cid, {})
	for k in items:
		n += int(items[k])
	return n


func chest_count(cid: int, item: String) -> int:
	var items: Dictionary = chests.get(cid, {})
	return int(items.get(item, 0))


func chest_has(cid: int, cost: Dictionary) -> bool:
	for item in cost:
		if chest_count(cid, String(item)) < int(cost[item]):
			return false
	return true


## What the base owns: pieces within CLAIM_RADIUS of the core, chest storage and assembler activity.
func summary() -> Dictionary:
	var out := {
		"claimed": false, "core_pos": Vector3.ZERO, "radius": CLAIM_RADIUS, "pieces": {}, "total": 0,
		"chests": 0, "assemblers": 0, "working": 0, "storage": {},
	}
	if core_id == 0 or not _b.pieces.has(core_id):
		return out
	out["claimed"] = true
	var c: Vector3 = _b.key_position(_b.pieces[core_id]["key"])
	out["core_pos"] = c
	var by_kind: Dictionary = out["pieces"]
	var storage: Dictionary = out["storage"]
	for id in _b.pieces:
		var info: Dictionary = _b.pieces[id]
		var p: Vector3 = _b.key_position(info["key"])
		if Vector2(p.x - c.x, p.z - c.z).length() > CLAIM_RADIUS:
			continue
		var kind := String(info["kind"])
		by_kind[kind] = int(by_kind.get(kind, 0)) + 1
		out["total"] = int(out["total"]) + 1
		if kind == "chest":
			out["chests"] = int(out["chests"]) + 1
			var items: Dictionary = chests.get(id, {})
			for k in items:
				storage[k] = int(storage.get(k, 0)) + int(items[k])
		elif kind == "assembler":
			out["assemblers"] = int(out["assemblers"]) + 1
			if asms.has(id) and bool(asms[id]["working"]):
				out["working"] = int(out["working"]) + 1
	return out


# ------------------------------------------------------------------- piece hooks

static func _new_asm() -> Dictionary:
	return {"recipe": "", "enabled": true, "working": false, "elapsed": 0.0, "duration": 0.0,
		"status": "Pick a recipe", "produced": 0}


func _on_piece_placed(id: int, kind: String) -> void:
	match kind:
		"chest":
			if not chests.has(id):
				chests[id] = {}
		"assembler":
			if not asms.has(id):
				asms[id] = _new_asm()
		"base_core":
			core_id = id
	if core_id != 0:
		base_changed.emit()


func _on_piece_removed(id: int) -> void:
	chests.erase(id)
	asms.erase(id)
	if id == core_id:
		core_id = 0
	base_changed.emit()
	if _ui != null and _ui.visible and _ui.piece_id == id:
		_ui.close()


func _on_player_connected(peer: int) -> void:
	if _b._server():
		_rpc_sync.rpc_id(peer, chests, asms)


# ------------------------------------------------------------------ server logic

func _physics_process(delta: float) -> void:
	if _b == null or asms.is_empty():
		return
	var server: bool = _b._server()
	for id in asms.keys():
		var a: Dictionary = asms[id]
		if server:
			_tick_server(int(id), a, delta * time_scale)
		elif bool(a["working"]):
			a["elapsed"] = minf(float(a["elapsed"]) + delta, float(a["duration"]))
		_update_light(int(id), a)


func _tick_server(id: int, a: Dictionary, dt: float) -> void:
	var r := Recipes.get_recipe(String(a["recipe"]))
	if r.is_empty():
		_set_status(id, a, "Pick a recipe")
		return
	var working := bool(a["working"])
	if not working and not bool(a["enabled"]):
		_set_status(id, a, "Paused")
		return
	var cid := linked_chest(id)
	var count := int(r["count"])
	if not working:
		if cid == 0:
			_set_status(id, a, "No chest nearby")
			return
		var cost: Dictionary = r["cost"]
		if not chest_has(cid, cost):
			_set_status(id, a, "Waiting for materials")
			return
		var cost_n := 0
		for k in cost:
			cost_n += int(cost[k])
		if chest_total(cid) - cost_n + count > CHEST_CAP:
			_set_status(id, a, "Chest full")
			return
		for item in cost:
			_chest_take(cid, String(item), int(cost[item]))
		a["working"] = true
		a["elapsed"] = 0.0
		a["duration"] = Extras.craft_time(r)
		a["status"] = "Working"
		_chest_sync(cid)
		_commit_asm(id, a)
		return
	a["elapsed"] = float(a["elapsed"]) + dt
	if float(a["elapsed"]) < float(a["duration"]):
		return
	if cid == 0:
		_set_status(id, a, "No chest nearby")
		return
	if chest_total(cid) + count > CHEST_CAP:
		_set_status(id, a, "Chest full")
		return
	_chest_add(cid, Extras.output_item(r), count)
	a["working"] = false
	a["elapsed"] = 0.0
	a["produced"] = int(a["produced"]) + 1
	a["status"] = "Idle"
	_chest_sync(cid)
	_commit_asm(id, a)


func _set_status(id: int, a: Dictionary, text: String) -> void:
	if String(a["status"]) != text:
		a["status"] = text
		_commit_asm(id, a)


func _commit_asm(id: int, a: Dictionary) -> void:
	assembler_changed.emit(id)
	if _b._in_game():
		_rpc_asm.rpc(id, a["recipe"], a["enabled"], a["working"], a["elapsed"], a["duration"], a["status"], a["produced"])


func _chest_sync(cid: int) -> void:
	chest_changed.emit(cid)
	if _b._in_game():
		_rpc_chest.rpc(cid, chests.get(cid, {}))


func _chest_add(cid: int, item: String, n: int) -> void:
	var items: Dictionary = chests.get(cid, {})
	items[item] = int(items.get(item, 0)) + n
	chests[cid] = items


func _chest_take(cid: int, item: String, n: int) -> int:
	var items: Dictionary = chests.get(cid, {})
	var got := mini(n, int(items.get(item, 0)))
	if got <= 0:
		return 0
	items[item] = int(items[item]) - got
	if int(items[item]) <= 0:
		items.erase(item)
	chests[cid] = items
	return got


func _in_reach(peer: int, id: int) -> bool:
	var info = _b.pieces.get(id)
	if info == null:
		return false
	return not _b._too_far(peer, _b.key_position(info["key"]), _b.USE_REACH + USE_SLACK)


func _server_set_recipe(peer: int, id: int, recipe_id: String) -> void:
	if not asms.has(id) or not _b.pieces.has(id):
		return
	if not _in_reach(peer, id):
		_b._reject(peer, "Too far")
		return
	if recipe_id != "" and not Extras.recipe_ok(recipe_id):
		_b._reject(peer, "Unknown recipe")
		return
	var a: Dictionary = asms[id]
	if bool(a["working"]):
		_b._reject(peer, "Assembler busy")
		return
	a["recipe"] = recipe_id
	a["status"] = "Pick a recipe" if recipe_id == "" else "Waiting for materials"
	_commit_asm(id, a)


func _server_toggle(peer: int, id: int) -> void:
	if not asms.has(id) or not _b.pieces.has(id):
		return
	if not _in_reach(peer, id):
		_b._reject(peer, "Too far")
		return
	var a: Dictionary = asms[id]
	a["enabled"] = not bool(a["enabled"])
	if not bool(a["enabled"]) and not bool(a["working"]):
		a["status"] = "Paused"
	_commit_asm(id, a)


func _server_deposit(peer: int, cid: int, item: String, n: int) -> void:
	if not chests.has(cid) or not _b.pieces.has(cid):
		return
	if item != "planks" and item != "scrap":
		_b._reject(peer, "Only planks and scrap")
		return
	if not _in_reach(peer, cid):
		_b._reject(peer, "Too far")
		return
	n = mini(clampi(n, 0, MAX_MOVE), CHEST_CAP - chest_total(cid))
	if n <= 0:
		_b._reject(peer, "Chest full")
		return
	var cost := {item: n}
	if not _b._take(peer, cost, false):
		_b._reject(peer, "Not enough materials")
		return
	_b._take(peer, cost, true)
	_chest_add(cid, item, n)
	_chest_sync(cid)


func _server_withdraw(peer: int, cid: int, item: String, n: int) -> void:
	if not chests.has(cid) or not _b.pieces.has(cid):
		return
	if not _in_reach(peer, cid):
		_b._reject(peer, "Too far")
		return
	n = _chest_take(cid, item, clampi(n, 0, MAX_MOVE))
	if n <= 0:
		return
	_chest_sync(cid)
	if item == "planks" or item == "scrap":
		_b.give(item, n, peer)
	elif peer == 1:
		if not _deliver_local(item, n):
			_chest_add(cid, item, n)
			_chest_sync(cid)
			_b._reject(peer, "Inventory full")
	else:
		var key := "%d|%s" % [peer, item]
		_pending[key] = int(_pending.get(key, 0)) + n
		_rpc_deliver.rpc_id(peer, cid, item, n)


## Hands a stored item to the local player the way pickups do (weapons, ammo reserve, grid space check).
func _deliver_local(item: String, n: int) -> bool:
	var pl: Node = _net.get_local_player() if _net != null else null
	if pl == null:
		return false
	# give_to reports success for a weapon already held (pickup never duplicates), which would destroy the stored copy.
	var d: Dictionary = ItemDB.get_item(ItemDB.canonical(item))
	if str(d.get("type", "")) == "weapon":
		var wc = pl.get("weapons") if "weapons" in pl else null
		if wc != null and wc.has_method("has_weapon") and wc.has_weapon(str(d.get("weapon_id", ""))):
			return false
	return ItemDB.give_to(pl, item, n)


func _server_delivered(peer: int, cid: int, item: String, n: int, ok: bool) -> void:
	var key := "%d|%s" % [peer, item]
	var take := mini(int(_pending.get(key, 0)), n)
	if take <= 0:
		return
	_pending[key] = int(_pending[key]) - take
	if ok:
		return
	if chests.has(cid):
		_chest_add(cid, item, take)
		_chest_sync(cid)
	_b._reject(peer, "Inventory full")


# ----------------------------------------------------------------- lamp / local

func _update_light(id: int, a: Dictionary) -> void:
	var info = _b.pieces.get(id)
	if info == null or not is_instance_valid(info["node"]):
		return
	var light := (info["node"] as Node).get_node_or_null("Light") as MeshInstance3D
	if light == null:
		return
	var col := Color(0.4, 0.4, 0.4)
	if bool(a["working"]):
		col = Color(0.2, 1.0, 0.3)
	elif String(a["status"]) == "Waiting for materials" or String(a["status"]) == "Chest full" or String(a["status"]) == "No chest nearby":
		col = Color(1.0, 0.6, 0.1)
	var m := light.material_override as StandardMaterial3D
	if m != null and not m.albedo_color.is_equal_approx(col):
		m.albedo_color = col
		m.emission = col * 0.8


# ---------------------------------------------------------------------- RPCs

@rpc("any_peer", "call_remote", "reliable")
func _rpc_req_recipe(id: int, recipe_id: String) -> void:
	if _b._server():
		_server_set_recipe(multiplayer.get_remote_sender_id(), id, recipe_id)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_req_toggle(id: int) -> void:
	if _b._server():
		_server_toggle(multiplayer.get_remote_sender_id(), id)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_req_deposit(cid: int, item: String, n: int) -> void:
	if _b._server():
		_server_deposit(multiplayer.get_remote_sender_id(), cid, item, n)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_req_withdraw(cid: int, item: String, n: int) -> void:
	if _b._server():
		_server_withdraw(multiplayer.get_remote_sender_id(), cid, item, n)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_delivered(cid: int, item: String, n: int, ok: bool) -> void:
	if _b._server():
		_server_delivered(multiplayer.get_remote_sender_id(), cid, item, n, ok)


## Host -> the withdrawing peer: put this in your own inventory, then confirm.
@rpc("authority", "call_remote", "reliable")
func _rpc_deliver(cid: int, item: String, n: int) -> void:
	_rpc_delivered.rpc_id(1, cid, item, n, _deliver_local(item, n))


@rpc("authority", "call_remote", "reliable")
func _rpc_chest(cid: int, items: Dictionary) -> void:
	chests[cid] = items
	chest_changed.emit(cid)


@rpc("authority", "call_remote", "reliable")
func _rpc_asm(id: int, recipe: String, enabled: bool, working: bool, elapsed: float, duration: float, status: String, produced: int) -> void:
	asms[id] = {"recipe": recipe, "enabled": enabled, "working": working, "elapsed": elapsed,
		"duration": duration, "status": status, "produced": produced}
	assembler_changed.emit(id)


@rpc("authority", "call_remote", "reliable")
func _rpc_sync(chest_state: Dictionary, asm_state: Dictionary) -> void:
	for id in chest_state:
		chests[int(id)] = chest_state[id]
		chest_changed.emit(int(id))
	for id in asm_state:
		asms[int(id)] = asm_state[id]
		assembler_changed.emit(int(id))
