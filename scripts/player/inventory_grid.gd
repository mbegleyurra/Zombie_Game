extends RefCounted
## Grid inventory rules (pure logic, no UI). Usage: const InventoryGrid := preload("res://scripts/player/inventory_grid.gd")
##
## The player's grid is inv_cols x inv_rows cells (default 10 x 6). Every item stack occupies the footprint
## ItemDB.footprint(id) (w x h cells); a stack holds at most the item's "stack" count, so 45 rounds of 9mm is one 1x1
## stack but 130 rounds is two. Weapons (they live in player.weapons, not player.inventory) take their footprint too.
## Placement is an automatic first-fit pack (largest footprints first, rotated 90 degrees when that is the only way
## in), recomputed from the real state, so the grid can never disagree with the inventory dictionary.
##
## Public API (Player wraps these as player.try_add / can_fit_item / deconstruct_item):
##   can_add(player, id, n) -> bool          would the item fit right now (nothing is changed)
##   deconstruct(player, id, units) -> Dictionary
##       {ok, reason, item, removed, yield: {material: n}}  breaks an item down to planks / scrap
##   layout(player) -> {ok, used, cols, rows, items: [{key, item, name, count, w, h, x, y, rotated, weapon}]}
## Multiplayer: the inventory belongs to the owning peer (multiplayer authority); deconstruct refuses on any other
## peer. Materials go through ItemDB.give_to, which also credits the host-side Building stock exactly like a pickup.

const ItemDB := preload("res://scripts/world/item_db.gd")

const DEFAULT_COLS := 10
const DEFAULT_ROWS := 6
const WEAPON_PREFIX := "weapon:"


## Where an id lands: {"kind": "weapon", "key": weapon_id} or {"kind": "inv", "key": reserve/item key}.
## Accepts ItemDB ids ("weapon_ak", "ammo_9mm"), caliber strings and Player-normalised ids ("ak", "9mm").
static func resolve(id: String) -> Dictionary:
	var cid: String = ItemDB.canonical(id)
	var d: Dictionary = ItemDB.get_item(cid)
	match str(d.get("type", "")):
		"weapon":
			return {"kind": "weapon", "key": str(d.get("weapon_id", cid.trim_prefix("weapon_")))}
		"ammo":
			return {"kind": "inv", "key": ItemDB.reserve_key(cid)}
	if d.is_empty() and WeaponDB.has_weapon(id):
		return {"kind": "weapon", "key": id}
	return {"kind": "inv", "key": id}


## ItemDB id for a grid key (weapon id "ak" -> "weapon_ak", reserve key "9mm" -> "ammo_9mm").
static func item_id_of(kind: String, key: String) -> String:
	return "weapon_" + key if kind == "weapon" else ItemDB.canonical(key)


## Stacks to place, in display order: owned weapons first, then inventory keys sorted by display name, each split
## into stacks of at most the item's stack size.
static func build_items(inv: Dictionary, weapon_ids: Array) -> Array:
	var out: Array = []
	for wid in weapon_ids:
		out.append(_stack("weapon", str(wid), 1))
	var keys: Array = []
	for k in inv:
		if int(inv[k]) > 0:
			keys.append(str(k))
	keys.sort_custom(func(a: String, b: String) -> bool:
		var na: String = ItemDB.item_name(a)
		var nb: String = ItemDB.item_name(b)
		return na < nb if na != nb else a < b)
	for k in keys:
		var cap: int = maxi(1, int(ItemDB.get_item(k).get("stack", 99)))
		var left := int(inv[k])
		while left > 0:
			var take := mini(left, cap)
			out.append(_stack("inv", k, take))
			left -= take
	return out


static func _stack(kind: String, key: String, count: int) -> Dictionary:
	var iid := item_id_of(kind, key)
	var fp: Vector2i = ItemDB.footprint(iid)
	return {
		"key": WEAPON_PREFIX + key if kind == "weapon" else key, "item": iid, "name": ItemDB.item_name(iid),
		"count": 0 if kind == "weapon" else count, "w": fp.x, "h": fp.y, "x": -1, "y": -1,
		"rotated": false, "weapon": kind == "weapon",
	}


## First-fit pack of `items` (from build_items) into cols x rows. Fills x / y / w / h / rotated on every item.
## Returns {"ok": bool, "used": cells occupied, "items": items}; ok is false when something did not fit.
static func pack(items: Array, cols: int, rows: int) -> Dictionary:
	var occ := PackedByteArray()
	occ.resize(maxi(0, cols * rows))
	var order: Array = range(items.size())
	order.sort_custom(func(a: int, b: int) -> bool:
		var aa: int = int(items[a]["w"]) * int(items[a]["h"])
		var ab: int = int(items[b]["w"]) * int(items[b]["h"])
		return a < b if aa == ab else aa > ab)
	var used := 0
	var ok := true
	for idx in order:
		var it: Dictionary = items[idx]
		var w: int = it["w"]
		var h: int = it["h"]
		var spot := _find_spot(occ, cols, rows, w, h)
		if spot.x < 0 and w != h:
			spot = _find_spot(occ, cols, rows, h, w)
			if spot.x >= 0:
				it["rotated"] = true
				it["w"] = h
				it["h"] = w
		if spot.x < 0:
			ok = false
			continue
		w = it["w"]
		h = it["h"]
		for yy in range(spot.y, spot.y + h):
			for xx in range(spot.x, spot.x + w):
				occ[yy * cols + xx] = 1
		it["x"] = spot.x
		it["y"] = spot.y
		used += w * h
	return {"ok": ok, "used": used, "items": items}


static func _find_spot(occ: PackedByteArray, cols: int, rows: int, w: int, h: int) -> Vector2i:
	if w > cols or h > rows or w <= 0 or h <= 0:
		return Vector2i(-1, -1)
	for y in range(0, rows - h + 1):
		for x in range(0, cols - w + 1):
			var free := true
			for yy in range(y, y + h):
				for xx in range(x, x + w):
					if occ[yy * cols + xx] != 0:
						free = false
						break
				if not free:
					break
			if free:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


static func _weapon_ids(p) -> Array:
	var wc = p.get("weapons")
	return (wc.weapon_ids() as Array).duplicate() if wc != null and is_instance_valid(wc) else []


static func _cols(p) -> int:
	return int(p.get("inv_cols")) if p.get("inv_cols") != null else DEFAULT_COLS


static func _rows(p) -> int:
	return int(p.get("inv_rows")) if p.get("inv_rows") != null else DEFAULT_ROWS


## Current packed layout of a player (see header).
static func layout(p) -> Dictionary:
	if p == null or not is_instance_valid(p):
		return {"ok": true, "used": 0, "cols": DEFAULT_COLS, "rows": DEFAULT_ROWS, "items": []}
	var inv: Dictionary = p.get("inventory") if p.get("inventory") is Dictionary else {}
	var r := pack(build_items(inv, _weapon_ids(p)), _cols(p), _rows(p))
	r["cols"] = _cols(p)
	r["rows"] = _rows(p)
	return r


static func _fits(p, inv: Dictionary, wids: Array) -> bool:
	return bool(pack(build_items(inv, wids), _cols(p), _rows(p))["ok"])


## Would `n` of item `id` fit? Mirrors Player.add_item: a weapon you do not own takes its footprint, a weapon you
## already own turns into one magazine of its ammo, everything else adds n to its key.
static func can_add(p, id: String, n: int = 1) -> bool:
	if n <= 0:
		return true
	var r := resolve(id)
	var inv: Dictionary = (p.get("inventory") as Dictionary).duplicate()
	var wids := _weapon_ids(p)
	var key: String = r["key"]
	if r["kind"] == "weapon":
		if wids.has(key):
			var wd = WeaponDB.get_weapon(key)
			if wd == null:
				return true
			inv[wd.caliber] = int(inv.get(wd.caliber, 0)) + int(wd.mag_size)
		else:
			wids.append(key)
	else:
		inv[key] = int(inv.get(key, 0)) + n
	return _fits(p, inv, wids)


## Breaks `units` of an item down into planks / scrap. Weapons: one per call; ammo: one unit = ItemDB.deconstruct_unit
## rounds. Atomic: nothing changes unless the materials also fit in the grid after the item is gone.
static func deconstruct(p, id: String, units: int = 1) -> Dictionary:
	var res := {"ok": false, "reason": "", "item": id, "removed": 0, "yield": {}}
	if p == null or not is_instance_valid(p):
		res["reason"] = "No player."
		return res
	if p.has_method("is_multiplayer_authority") and p.is_inside_tree() and not p.is_multiplayer_authority():
		res["reason"] = "Only the owning peer can deconstruct its inventory."
		return res
	var nid: String = p.normalize_id(id) if p.has_method("normalize_id") else id
	var r := resolve(nid)
	var kind: String = r["kind"]
	var key: String = r["key"]
	var iid := item_id_of(kind, key)
	res["item"] = iid
	var per: Dictionary = ItemDB.deconstruct_yield(iid)
	if per.is_empty():
		res["reason"] = "%s cannot be deconstructed." % ItemDB.item_name(iid)
		return res
	var inv: Dictionary = (p.get("inventory") as Dictionary).duplicate()
	var wids := _weapon_ids(p)
	var have := 0
	if kind == "weapon":
		have = 1 if wids.has(key) else 0
		units = 1
	else:
		have = int(inv.get(key, 0))
	if have <= 0 or units <= 0:
		res["reason"] = "You do not have %s." % ItemDB.item_name(iid)
		return res
	var unit: int = 1 if kind == "weapon" else ItemDB.deconstruct_unit(iid)
	var removed := mini(have, unit * units)
	var batches := int(ceil(float(removed) / float(unit)))
	var gain := {}
	for m in per:
		gain[str(m)] = int(per[m]) * batches
	# Simulate: item gone, materials in. Refuse the whole thing if it would not fit.
	if kind == "weapon":
		wids.erase(key)
	else:
		inv[key] = have - removed
	for m in gain:
		inv[m] = int(inv.get(m, 0)) + int(gain[m])
	if not _fits(p, inv, wids):
		res["reason"] = "Not enough room for the materials. Free some space first."
		return res
	var got: int = int(p.remove_item(key, removed))
	if got <= 0:
		res["reason"] = "Could not remove %s." % ItemDB.item_name(iid)
		return res
	for m in gain:
		ItemDB.give_to(p, str(m), int(gain[m]))
	res["ok"] = true
	res["removed"] = got
	res["yield"] = gain
	return res
