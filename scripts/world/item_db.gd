extends RefCounted
## Static item database and loot tables for Dead Acres.
## Usage: const ItemDB = preload("res://scripts/world/item_db.gd")
##        ItemDB.get_item("medkit"), ItemDB.roll_table("hospital", rng)

const KayKitRes = preload("res://scripts/world/kaykit_resources.gd")

const ITEMS := {
	"weapon_pistol": {
		"name": "9mm Pistol", "type": "weapon", "weapon_id": "pistol", "stack": 1, "weight": 1.0,
		"color": Color(0.2, 0.2, 0.22), "shape": "gun", "desc": "Semi-auto sidearm.",
	},
	"weapon_ak": {
		"name": "AK Rifle", "type": "weapon", "weapon_id": "ak", "stack": 1, "weight": 3.5,
		"color": Color(0.38, 0.27, 0.16), "shape": "gun", "desc": "Rugged 7.62 assault rifle.",
	},
	"weapon_m4": {
		"name": "M4 Carbine", "type": "weapon", "weapon_id": "m4", "stack": 1, "weight": 3.2,
		"color": Color(0.16, 0.17, 0.18), "shape": "gun", "desc": "5.56 carbine.",
	},
	"weapon_shotgun": {
		"name": "Pump Shotgun", "type": "weapon", "weapon_id": "shotgun", "stack": 1, "weight": 3.4,
		"color": Color(0.3, 0.22, 0.14), "shape": "gun", "desc": "12 gauge pump action.",
	},
	"weapon_hunting": {
		"name": "Hunting Rifle", "type": "weapon", "weapon_id": "hunting", "stack": 1, "weight": 3.6,
		"color": Color(0.45, 0.32, 0.18), "shape": "gun", "desc": "Bolt-action 7.62 rifle.",
	},
	"weapon_ar": {
		"name": "Assault Rifle", "type": "weapon", "weapon_id": "ar", "stack": 1, "weight": 3.8,
		"color": Color(0.15, 0.16, 0.17), "shape": "gun", "desc": "Heavy-hitting 5.56 assault rifle, 20 round magazine.",
	},
	"ammo_9mm": {
		"name": "9mm Rounds", "type": "ammo", "caliber": "9mm", "stack": 120, "weight": 0.012,
		"color": Color(0.86, 0.68, 0.25), "shape": "box", "desc": "Pistol and SMG cartridges.",
	},
	"ammo_556": {
		"name": "5.56x45mm Rounds", "type": "ammo", "caliber": "5.56", "stack": 120, "weight": 0.012,
		"color": Color(0.55, 0.62, 0.3), "shape": "box", "desc": "Rifle cartridges for carbines and assault rifles.",
	},
	"ammo_12ga": {
		"name": "12 Gauge Shells", "type": "ammo", "caliber": "12ga", "stack": 40, "weight": 0.045,
		"color": Color(0.8, 0.2, 0.18), "shape": "box", "desc": "Shotgun shells.",
	},
	"ammo_762": {
		"name": "7.62x51mm Rounds", "type": "ammo", "caliber": "7.62", "stack": 80, "weight": 0.025,
		"color": Color(0.35, 0.4, 0.55), "shape": "box", "desc": "Heavy rifle cartridges for battle and hunting rifles.",
	},
	"medkit": {
		"name": "Medkit", "type": "medical", "stack": 3, "weight": 0.8, "heal": 60.0,
		"color": Color(0.92, 0.92, 0.92), "shape": "medkit", "desc": "Restores health.",
	},
	"food": {
		"name": "Canned Food", "type": "consumable", "stack": 8, "weight": 0.4, "hunger": 35.0,
		"color": Color(0.8, 0.55, 0.2), "shape": "can", "desc": "Restores hunger.",
		"model": "res://assets/kenney/food/can.glb", "model_height": 0.17,
		"models": [["res://assets/kenney/food/can.glb", 0.17], ["res://assets/kenney/food/can-small.glb", 0.07]],
	},
	"water": {
		"name": "Water Bottle", "type": "consumable", "stack": 8, "weight": 0.5, "thirst": 40.0,
		"color": Color(0.35, 0.65, 0.9), "shape": "bottle", "desc": "Restores thirst.",
		"model": "res://assets/kenney/food/soda-bottle.glb", "model_height": 0.3,
	},
	"scrap": {
		"name": "Scrap Metal", "type": "material", "stack": 30, "weight": 0.3,
		"color": Color(0.55, 0.55, 0.6), "shape": "scrap", "desc": "Crafting and building material.",
	},
	"planks": {
		"name": "Wood Planks", "type": "material", "stack": 30, "weight": 0.6,
		"color": Color(0.65, 0.47, 0.28), "shape": "long", "desc": "Used for building barricades.",
	},
	# Workbench rifles and their own ammo types (crafted at the workbench).
	"weapon_ar_t1": {
		"name": "Scrapper AR (Mk1)", "type": "weapon", "weapon_id": "ar_t1", "stack": 1, "weight": 3.6,
		"color": Color(0.85, 0.5, 0.15), "shape": "gun", "desc": "Workbench-built assault rifle, 5.45 rounds, 24 round magazine.",
	},
	"weapon_ar_t2": {
		"name": "Marauder AR (Mk2)", "type": "weapon", "weapon_id": "ar_t2", "stack": 1, "weight": 3.9,
		"color": Color(0.2, 0.5, 0.85), "shape": "gun", "desc": "Workbench-built assault rifle, 6.8 rounds, 30 round magazine.",
	},
	"weapon_ar_t3": {
		"name": "Reaper AR (Mk3)", "type": "weapon", "weapon_id": "ar_t3", "stack": 1, "weight": 4.2,
		"color": Color(0.8, 0.12, 0.12), "shape": "gun", "desc": "Workbench-built assault rifle, .300 rounds, 40 round magazine.",
	},
	"ammo_545": {
		"name": "5.45x39mm Rounds", "type": "ammo", "caliber": "545", "stack": 120, "weight": 0.011,
		"color": Color(0.85, 0.5, 0.15), "shape": "box", "desc": "Ammo for the Scrapper AR.",
	},
	"ammo_68": {
		"name": "6.8mm Rounds", "type": "ammo", "caliber": "68", "stack": 120, "weight": 0.013,
		"color": Color(0.2, 0.5, 0.85), "shape": "box", "desc": "Ammo for the Marauder AR.",
	},
	"ammo_300": {
		"name": ".300 Rounds", "type": "ammo", "caliber": "300", "stack": 120, "weight": 0.015,
		"color": Color(0.8, 0.12, 0.12), "shape": "box", "desc": "Ammo for the Reaper AR.",
	},
}

## Loot tables: "rolls" = [min, max] number of weighted picks, "entries" = [item_id, weight, min_count, max_count].
## Maps ammo item ids and caliber strings (both forms) to the canonical item id.
const ALIASES := {
	"9mm": "ammo_9mm", "556": "ammo_556", "5.56": "ammo_556",
	"762": "ammo_762", "7.62": "ammo_762", "12ga": "ammo_12ga",
	"545": "ammo_545", "68": "ammo_68", "300": "ammo_300",
}
## Ammo item id -> the reserve key weapons read via player.count_item(caliber).
const RESERVE_KEYS := {
	"ammo_9mm": "9mm", "ammo_556": "556", "ammo_762": "762", "ammo_12ga": "12ga",
	"ammo_545": "545", "ammo_68": "68", "ammo_300": "300",
}

## Every ammo entry in a loot table (and so every ground pile, container and dungeon drop) is multiplied by this.
const AMMO_LOOT_MULT := 2

const TABLES := {
	"farm": {
		"rolls": [1, 3],
		"entries": [
			["food", 20, 1, 2], ["water", 18, 1, 2], ["ammo_12ga", 14, 2, 6], ["scrap", 10, 1, 3],
			["planks", 12, 2, 4], ["ammo_762", 6, 3, 8], ["ammo_9mm", 8, 5, 15], ["medkit", 5, 1, 1],
			["ammo_556", 3, 5, 10], ["weapon_shotgun", 1.5, 1, 1], ["weapon_hunting", 1.5, 1, 1], ["ammo_545", 3, 4, 8],
		],
	},
	"barn": {
		"rolls": [1, 3],
		"entries": [
			["planks", 24, 2, 6], ["scrap", 22, 2, 5], ["ammo_12ga", 12, 2, 5], ["water", 8, 1, 1],
			["food", 6, 1, 1], ["ammo_762", 5, 3, 6], ["medkit", 2, 1, 1],
			["weapon_shotgun", 1.5, 1, 1],
			],
	},
	"gas_station": {
		"rolls": [1, 3],
		"entries": [
			["food", 26, 1, 3], ["water", 26, 1, 3], ["scrap", 10, 1, 3], ["ammo_9mm", 12, 6, 18],
			["medkit", 5, 1, 1], ["ammo_12ga", 5, 2, 4], ["ammo_556", 3, 5, 10], ["planks", 4, 1, 2],
			["weapon_pistol", 2, 1, 1], ["weapon_ak", 1, 1, 1], ["ammo_545", 2, 4, 8],
			],
	},
	"hospital": {
		"rolls": [2, 4],
		"entries": [
			["medkit", 34, 1, 2], ["water", 14, 1, 2], ["food", 10, 1, 2], ["ammo_9mm", 8, 6, 15],
			["scrap", 6, 1, 2], ["ammo_556", 3, 5, 10], ["ammo_762", 2, 3, 6],
			["weapon_pistol", 1.5, 1, 1], ["weapon_m4", 1, 1, 1], ["weapon_ar", 0.8, 1, 1], ["ammo_68", 2, 4, 8],
			],
	},
	"police": {
		"rolls": [2, 4],
		"entries": [
			["ammo_9mm", 20, 8, 20], ["ammo_12ga", 12, 3, 8], ["ammo_556", 8, 6, 15], ["medkit", 8, 1, 1],
			["weapon_pistol", 8, 1, 1], ["weapon_shotgun", 6, 1, 1], ["weapon_m4", 3, 1, 1], ["weapon_ar", 3, 1, 1],
			["water", 6, 1, 2], ["food", 4, 1, 2], ["scrap", 4, 1, 3],
			["ammo_545", 4, 5, 10], ["ammo_68", 3, 4, 8], ["ammo_300", 2, 3, 6],
		],
	},
	"warehouse": {
		"rolls": [1, 3],
		"entries": [
			["planks", 22, 3, 8], ["scrap", 24, 2, 6], ["food", 10, 1, 3], ["water", 8, 1, 2],
			["ammo_12ga", 6, 2, 5], ["ammo_9mm", 6, 5, 12], ["medkit", 3, 1, 1],
			["weapon_hunting", 1, 1, 1], ["weapon_pistol", 1, 1, 1],
		],
	},
	"church": {
		"rolls": [1, 3],
		"entries": [
			["medkit", 20, 1, 2], ["water", 18, 1, 3], ["food", 14, 1, 3], ["planks", 12, 2, 5],
			["scrap", 6, 1, 3], ["ammo_9mm", 6, 4, 10], ["ammo_12ga", 6, 2, 5], ["ammo_762", 4, 3, 6],
			["weapon_hunting", 2, 1, 1], ["weapon_pistol", 1, 1, 1],
		],
	},
	"wild": {
		"rolls": [1, 2],
		"entries": [
			["scrap", 25, 1, 2], ["planks", 20, 1, 3], ["food", 12, 1, 1], ["water", 12, 1, 1],
			["ammo_9mm", 10, 4, 10], ["ammo_12ga", 8, 1, 3], ["medkit", 3, 1, 1], ["ammo_556", 4, 4, 8],
			["ammo_762", 3, 3, 6],
			["weapon_pistol", 1, 1, 1], ["weapon_hunting", 1, 1, 1], ["weapon_m4", 0.5, 1, 1], ["weapon_ar", 0.7, 1, 1],
			["ammo_545", 2, 4, 8], ["ammo_300", 1, 3, 6],
			],
	},
}


static func has_item(id: String) -> bool:
	return _items().has(canonical(id))


static var _items_cache: Dictionary = {}
static var _tables_cache: Dictionary = {}


## ITEMS plus the KayKit resource items, with KayKit model overrides applied to existing items.
static func _items() -> Dictionary:
	if _items_cache.is_empty():
		var m: Dictionary = ITEMS.duplicate(true)
		for id in KayKitRes.ITEMS:
			m[id] = KayKitRes.ITEMS[id]
		for id in KayKitRes.VISUALS:
			if m.has(id):
				var d: Dictionary = (m[id] as Dictionary).duplicate()
				for k in (KayKitRes.VISUALS[id] as Dictionary):
					d[k] = KayKitRes.VISUALS[id][k]
				m[id] = d
		_items_cache = m
	return _items_cache


## TABLES plus the KayKit tables and extra entries; entries naming an unknown item id are dropped.
static func _tables() -> Dictionary:
	if _tables_cache.is_empty():
		var items: Dictionary = _items()
		var m: Dictionary = TABLES.duplicate(true)
		for name in KayKitRes.TABLES:
			m[name] = (KayKitRes.TABLES[name] as Dictionary).duplicate(true)
		for name in KayKitRes.EXTRA:
			if m.has(name):
				(m[name]["entries"] as Array).append_array((KayKitRes.EXTRA[name] as Array).duplicate(true))
		for name in m:
			var kept: Array = []
			for e in (m[name]["entries"] as Array):
				if items.has(str((e as Array)[0])):
					kept.append(e)
			m[name]["entries"] = kept
		_tables_cache = m
	return _tables_cache


## Resolves caliber strings ("9mm", "5.56", "556") to the ammo item id; other ids pass through.
static func canonical(id: String) -> String:
	return str(ALIASES.get(id, id))


## The reserve key a player's inventory uses for this ammo item ("" if not ammo).
static func reserve_key(id: String) -> String:
	return str(RESERVE_KEYS.get(canonical(id), ""))


## Hands an item to a player the way the rest of the game expects:
## weapons -> player.give_weapon(weapon_id), ammo -> reserve key (9mm/556/762/12ga),
## planks/scrap -> inventory plus Building stock. Returns false if nothing was accepted.
static func give_to(player, id: String, count: int) -> bool:
	var cid: String = canonical(id)
	var d: Dictionary = get_item(cid)
	if player == null:
		return false
	# Grid inventory: an item that does not fit is refused (it stays on the ground) and the player is told.
	if player.has_method("can_fit_item") and not player.can_fit_item(cid, count):
		if player.has_method("inventory_rejected"):
			player.inventory_rejected(cid)
		return false
	match str(d.get("type", "")):
		"weapon":
			var wid: String = str(d.get("weapon_id", ""))
			var wc = player.get("weapons") if "weapons" in player else null
			if wc != null and wc.has_method("pickup_weapon"):
				return int(wc.pickup_weapon(wid)) >= 0
			if player.has_method("give_weapon"):
				return int(player.give_weapon(wid)) >= 0
			if player.has_method("add_item"):
				player.add_item(cid, count)
			return true
		"ammo":
			if player.has_method("add_item"):
				player.add_item(reserve_key(cid), count)
			return true
	if player.has_method("add_item"):
		var r = player.add_item(cid, count)
		if r is bool and not r:
			return false
	var feed: Array = KayKitRes.feed_for(cid)
	if cid == "planks" or cid == "scrap" or not feed.is_empty():
		var tree := Engine.get_main_loop() as SceneTree
		var m: Node = tree.get_first_node_in_group("main_world") if tree != null else null
		if m != null and m.has_method("give_materials"):
			if feed.is_empty():
				m.give_materials(cid, count)
			else:
				m.give_materials(str(feed[0]), count * int(feed[1]))
	return true


static func get_item(id: String) -> Dictionary:
	id = canonical(id)
	if _items().has(id):
		return _items()[id] as Dictionary
	return {}


static func item_name(id: String) -> String:
	var d: Dictionary = get_item(id)
	return str(d.get("name", id))


static func item_color(id: String) -> Color:
	var d: Dictionary = get_item(id)
	return d.get("color", Color(0.7, 0.7, 0.7)) as Color


static func all_ids() -> Array:
	return _items().keys()


static func table_names() -> Array:
	return _tables().keys()


## Returns the ammo item id for a caliber string like "9mm", "5.56", "12ga", "7.62" (or "" if none).
static func ammo_item_for(caliber: String) -> String:
	if ALIASES.has(caliber):
		return str(ALIASES[caliber])
	for id in ITEMS:
		var d: Dictionary = ITEMS[id]
		if d.get("type", "") == "ammo" and d.get("caliber", "") == caliber:
			return str(id)
	return ""


static func make_stack(id: String, count: int) -> Dictionary:
	return {"id": id, "count": count}


## Rolls a loot table. Returns Array of {"id": String, "count": int}, duplicates merged.
## rolls_override >= 0 forces the number of picks.
static func roll_table(table: String, rng: RandomNumberGenerator, rolls_override: int = -1) -> Array:
	var t: Dictionary = _tables().get(table, _tables()["wild"]) as Dictionary
	var rr: Array = t["rolls"]
	var rolls: int = rolls_override if rolls_override >= 0 else rng.randi_range(int(rr[0]), int(rr[1]))
	var merged := {}
	var order: Array = []
	for _i in rolls:
		var pick: Dictionary = pick_one(table, rng)
		var id: String = pick["id"]
		if merged.has(id):
			merged[id] = int(merged[id]) + int(pick["count"])
		else:
			merged[id] = int(pick["count"])
			order.append(id)
	var out: Array = []
	for id in order:
		out.append({"id": id, "count": int(merged[id])})
	return out


## One weighted pick from a table: {"id", "count"}.
static func pick_one(table: String, rng: RandomNumberGenerator) -> Dictionary:
	var t: Dictionary = _tables().get(table, _tables()["wild"]) as Dictionary
	var entries: Array = t["entries"]
	var total := 0.0
	for e in entries:
		total += float((e as Array)[1])
	var r: float = rng.randf() * total
	var chosen: Array = entries[entries.size() - 1]
	for e in entries:
		r -= float((e as Array)[1])
		if r <= 0.0:
			chosen = e
			break
	var lo: int = int(chosen[2])
	var hi: int = int(chosen[3])
	if str(get_item(str(chosen[0])).get("type", "")) == "ammo":
		lo *= AMMO_LOOT_MULT
		hi *= AMMO_LOOT_MULT
	return {"id": str(chosen[0]), "count": rng.randi_range(lo, hi)}


# ---------------------------------------------------------------- grid inventory (footprints + deconstruct)

## Cells an item occupies in the player's grid, [w, h]. An item entry may carry its own "cells": [w, h] and wins over
## this table; anything not listed takes the type default in footprint() (weapons 4x2, everything else 1x1).
const FOOTPRINTS := {
	"weapon_pistol": [2, 1], "weapon_ak": [4, 2], "weapon_m4": [4, 2], "weapon_shotgun": [4, 2],
	"weapon_hunting": [4, 2], "weapon_ar": [4, 2],
}

## Base materials an item breaks down into, per unit (see deconstruct_unit): item id -> {planks / scrap: n}.
## An item entry may carry its own "deconstruct" dict. Weapons not listed fall back to a type default in
## deconstruct_yield(); materials, food and water give nothing.
const DECONSTRUCT := {
	"weapon_pistol": {"scrap": 3},
	"weapon_ak": {"scrap": 5, "planks": 2},
	"weapon_m4": {"scrap": 6},
	"weapon_shotgun": {"scrap": 5, "planks": 2},
	"weapon_hunting": {"scrap": 3, "planks": 3},
	"weapon_ar": {"scrap": 7, "planks": 1},
	"medkit": {"scrap": 1},
}
## Ammo is broken down in bundles of this many rounds per unit of yield (default 10, yield scrap 1).
const DECONSTRUCT_UNIT := {"ammo_12ga": 4}


static func footprint(id: String) -> Vector2i:
	var cid: String = canonical(id)
	var d: Dictionary = get_item(cid)
	var c = d.get("cells", FOOTPRINTS.get(cid, null))
	if c is Array and (c as Array).size() == 2:
		return Vector2i(maxi(1, int(c[0])), maxi(1, int(c[1])))
	return Vector2i(4, 2) if str(d.get("type", "")) == "weapon" else Vector2i(1, 1)


## {material: n} per unit, empty when the item cannot be deconstructed. Items that feed the building stock
## (KayKit wood / metal) break down into what they feed.
static func deconstruct_yield(id: String) -> Dictionary:
	var cid: String = canonical(id)
	var d: Dictionary = get_item(cid)
	if d.is_empty() or cid == "planks" or cid == "scrap":
		return {}
	if d.has("deconstruct"):
		return (d["deconstruct"] as Dictionary).duplicate()
	if DECONSTRUCT.has(cid):
		return (DECONSTRUCT[cid] as Dictionary).duplicate()
	var feed: Array = KayKitRes.feed_for(cid)
	if not feed.is_empty():
		return {str(feed[0]): int(feed[1])}
	match str(d.get("type", "")):
		"weapon":
			return {"scrap": 5, "planks": 1}
		"ammo":
			return {"scrap": 1}
	return {}


## Items consumed per unit of deconstruct_yield (ammo comes in bundles, everything else is 1).
static func deconstruct_unit(id: String) -> int:
	var cid: String = canonical(id)
	var d: Dictionary = get_item(cid)
	if str(d.get("type", "")) != "ammo":
		return 1
	return int(DECONSTRUCT_UNIT.get(cid, 10))
