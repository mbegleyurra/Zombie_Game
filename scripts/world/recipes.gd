extends RefCounted
## Workbench recipes. Everything is paid for in planks and scrap (the Building stock).
## Usage: const Recipes = preload("res://scripts/world/recipes.gd")
##        Recipes.all(), Recipes.get_recipe("ammo_556"), Recipes.can_afford(recipe, {"planks": 9, "scrap": 4})
##
## A recipe is {id, name, kind ("weapon" | "ammo" | "gear"), give, count, cost, desc}.
##   give  = id passed to Player.add_item: a weapon id, or the caliber reserve key for ammo.
##   count = how many of `give` one craft yields.

const ItemDB := preload("res://scripts/world/item_db.gd")

const MATERIALS: Array[String] = ["planks", "scrap"]

## Backpacks (ItemDB items), smallest first. "give" is the ItemDB id, so the assembler can make them too.
const BACKPACKS := [
	{"item": "backpack_small", "cost": {"planks": 4, "scrap": 6}},
	{"item": "backpack_medium", "cost": {"planks": 8, "scrap": 14}},
	{"item": "backpack_large", "cost": {"planks": 14, "scrap": 26}},
]

## Tiered assault rifles, cheapest first. Stats live in WeaponDB.
const RIFLES := [
	{"weapon": "ar_t1", "cost": {"planks": 6, "scrap": 10}},
	{"weapon": "ar_t2", "cost": {"planks": 12, "scrap": 24}},
	{"weapon": "ar_t3", "cost": {"planks": 20, "scrap": 40}},
]

## caliber -> {count, cost} for one batch of ammo.
const AMMO := {
	"9mm": {"count": 60, "cost": {"planks": 1, "scrap": 2}},
	"556": {"count": 60, "cost": {"planks": 1, "scrap": 3}},
	"762": {"count": 40, "cost": {"planks": 1, "scrap": 4}},
	"12ga": {"count": 24, "cost": {"planks": 2, "scrap": 2}},
	"545": {"count": 60, "cost": {"planks": 1, "scrap": 3}},
	"68": {"count": 60, "cost": {"planks": 2, "scrap": 4}},
	"300": {"count": 60, "cost": {"planks": 2, "scrap": 6}},
}
## Used for a caliber that has no AMMO row, so a new gun is never left without ammo.
const AMMO_DEFAULT := {"count": 40, "cost": {"planks": 2, "scrap": 4}}

static var _cache: Array = []


static func all() -> Array:
	if _cache.is_empty():
		_cache = _build()
	return _cache


static func get_recipe(id: String) -> Dictionary:
	for r in all():
		if r["id"] == id:
			return r
	return {}


## Ammo recipe id for a caliber reserve key ("" never: every caliber resolves).
static func ammo_id(caliber: String) -> String:
	return "ammo_" + caliber


static func can_afford(recipe: Dictionary, stock: Dictionary) -> bool:
	var cost: Dictionary = recipe.get("cost", {})
	for item in cost:
		if int(stock.get(item, 0)) < int(cost[item]):
			return false
	return true


static func cost_text(recipe: Dictionary) -> String:
	var parts: PackedStringArray = []
	var cost: Dictionary = recipe.get("cost", {})
	for item in MATERIALS:
		if cost.has(item):
			parts.append("%d %s" % [int(cost[item]), item])
	return ", ".join(parts)


static func _build() -> Array:
	var out: Array = []
	for rf in RIFLES:
		var wid: String = rf["weapon"]
		var wd := WeaponDB.get_weapon(wid)
		if wd == null:
			continue
		out.append({
			"id": "gun_" + wid, "name": wd.display_name, "kind": "weapon", "give": wid, "count": 1,
			"cost": (rf["cost"] as Dictionary).duplicate(),
			"desc": "%.0f dmg, %.0f rpm, %d round mag, uses %s ammo." % [wd.damage, wd.fire_rate_rpm, wd.mag_size, wd.caliber],
		})
	# one ammo recipe per caliber, covering every weapon in WeaponDB
	var seen := {}
	for wid in WeaponDB.ids():
		var wd := WeaponDB.get_weapon(wid)
		if wd == null:
			continue
		var cal := wd.caliber
		if seen.has(cal):
			(seen[cal]["users"] as Array).append(wd.display_name)
			continue
		seen[cal] = {"users": [wd.display_name]}
	for cal in seen:
		var row: Dictionary = AMMO.get(cal, AMMO_DEFAULT)
		out.append({
			"id": ammo_id(cal), "name": "%s ammo x%d" % [cal, int(row["count"])], "kind": "ammo", "give": cal,
			"count": int(row["count"]), "cost": (row["cost"] as Dictionary).duplicate(),
			"desc": "For: " + ", ".join(PackedStringArray(seen[cal]["users"])),
		})
	for bp in BACKPACKS:
		var iid: String = bp["item"]
		out.append({
			"id": iid, "name": ItemDB.item_name(iid), "kind": "gear", "give": iid, "count": 1,
			"cost": (bp["cost"] as Dictionary).duplicate(),
			"desc": "Worn on your back: +%d grid columns." % ItemDB.backpack_cols(iid),
		})
	return out
