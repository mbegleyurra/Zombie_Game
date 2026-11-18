extends RefCounted
## One distinct, recognisable in-world look for every non-weapon pickup. LootItem builds its model from resolve(), the
## inventory grid tints its slots with accent(), and tests/t_pickup_visuals.gd asserts no two items look alike.
##
## An entry is {"models": [[path, height], ...], "tint": Color (optional multiply), "accent": Color (glow + inventory)}.
## Variants are picked from loot_id so every peer shows the same model. The model sets of different items never overlap.
## Anything missing here falls back to the ItemDB "model" (source "item") or a primitive placeholder (source "placeholder");
## the test fails on both for every pickup type.

const ItemDB = preload("res://scripts/world/item_db.gd")
const ModelUtil = preload("res://scripts/world/model_util.gd")

const RES := "res://assets/kaykit/resources/KayKit_ResourceBits_1.0_FREE/Assets/gltf/"
const DUN := "res://assets/kaykit/dungeon/KayKit_Dungeon_Pack_1.1_FREE/Assets/gltf/"
const ITH := "res://assets/ithappy_weapons/Meshes/Assets/"
const CAR := "res://assets/kenney/cars/"
const FOOD := "res://assets/kenney/food/"
const SURV := "res://assets/kenney/survival/"

## No pickup is wider than this (flat plates would otherwise blow up when fitted by height).
const MAX_SPAN := 0.55

const VISUALS := {
	# Ammo: a distinct shape per calibre, tinted with the calibre colour. Magazines come from the ITHappy pack
	# (pistol drum, rifle magazine); the pack has no shells or crates, so the rest are Kenney survival-kit boxes.
	"ammo_9mm": {"models": [[ITH + "pistol_drum_001.glb", 0.2]], "tint": Color(0.95, 0.75, 0.2), "accent": Color(0.95, 0.75, 0.2)},
	"ammo_556": {"models": [[ITH + "rifle_magazine_001.glb", 0.26]], "tint": Color(0.5, 0.75, 0.3), "accent": Color(0.5, 0.8, 0.3)},
	"ammo_12ga": {"models": [[SURV + "bottle.glb", 0.2]], "tint": Color(0.9, 0.2, 0.15), "accent": Color(0.95, 0.2, 0.15)},
	"ammo_762": {"models": [[SURV + "box.glb", 0.2]], "tint": Color(0.4, 0.5, 0.85), "accent": Color(0.4, 0.5, 0.9)},
	"ammo_545": {"models": [[SURV + "box-large.glb", 0.22]], "tint": Color(1.0, 0.55, 0.1), "accent": Color(1.0, 0.55, 0.1)},
	"ammo_68": {"models": [[SURV + "bucket.glb", 0.18]], "tint": Color(0.15, 0.6, 1.0), "accent": Color(0.15, 0.6, 1.0)},
	"ammo_300": {"models": [[SURV + "box-large-open.glb", 0.24]], "tint": Color(1.0, 0.1, 0.1), "accent": Color(1.0, 0.1, 0.1)},
	"medkit": {"models": [[SURV + "box-open.glb", 0.22]], "accent": Color(0.95, 0.95, 0.95)},
	"food": {"models": [[FOOD + "can.glb", 0.17], [FOOD + "can-small.glb", 0.1]], "accent": Color(0.85, 0.55, 0.15)},
	"water": {"models": [[FOOD + "soda-bottle.glb", 0.3]], "accent": Color(0.35, 0.7, 1.0)},
	"scrap": {"models": [[CAR + "debris-plate-small-a.glb", 0.12], [CAR + "debris-plate-small-b.glb", 0.12], [CAR + "debris-bolt.glb", 0.12]],
		"accent": Color(0.6, 0.65, 0.7)},
	"parts": {"models": [[RES + "Parts_Pile_Small.gltf", 0.24], [RES + "Parts_Pile_Medium.gltf", 0.32], [RES + "Parts_Cog.gltf", 0.16]],
		"accent": Color(0.8, 0.6, 0.25)},
	"planks": {"models": [[RES + "Wood_Planks_Stack_Small.gltf", 0.2], [RES + "Wood_Plank_A.gltf", 0.1], [RES + "Wood_Planks_Stack_Medium.gltf", 0.3]],
		"accent": Color(0.85, 0.65, 0.35)},
	"wood_logs": {"models": [[RES + "Wood_Log_A.gltf", 0.22], [RES + "Wood_Log_B.gltf", 0.22]], "accent": Color(0.5, 0.3, 0.12)},
	"iron_ingot": {"models": [[RES + "Iron_Bar.gltf", 0.13]], "accent": Color(0.45, 0.48, 0.55)},
	"copper_ingot": {"models": [[RES + "Copper_Bar.gltf", 0.13]], "accent": Color(0.85, 0.4, 0.2)},
	"silver_ingot": {"models": [[RES + "Silver_Bar.gltf", 0.13]], "accent": Color(0.85, 0.92, 1.0)},
	"gold_ingot": {"models": [[RES + "Gold_Bar.gltf", 0.13]], "accent": Color(1.0, 0.82, 0.1)},
	"iron_nuggets": {"models": [[RES + "Iron_Nuggets.gltf", 0.16]], "accent": Color(0.3, 0.33, 0.4)},
	"copper_nuggets": {"models": [[RES + "Copper_Nuggets.gltf", 0.16]], "accent": Color(0.7, 0.3, 0.1)},
	"silver_nuggets": {"models": [[RES + "Silver_Nuggets.gltf", 0.16]], "accent": Color(0.7, 0.78, 0.9)},
	"gold_nuggets": {"models": [[RES + "Gold_Nuggets.gltf", 0.16]], "accent": Color(1.0, 0.65, 0.05)},
	"fuel_can": {"models": [[RES + "Fuel_A_Jerrycan.gltf", 0.36], [RES + "Fuel_B_Jerrycan.gltf", 0.36], [RES + "Fuel_C_Jerrycan.gltf", 0.36]],
		"accent": Color(0.15, 0.85, 0.6)},
	"coin": {"models": [[DUN + "coin_stack_small.gltf", 0.14]], "accent": Color(1.0, 0.95, 0.55)},
}


## Item ids the table must cover: everything in ItemDB except weapons (guns show their own ITHappy model).
static func pickup_ids() -> Array:
	var out: Array = []
	for id in ItemDB.all_ids():
		if str(ItemDB.get_item(str(id)).get("type", "")) != "weapon":
			out.append(str(id))
	out.sort()
	return out


static func has_visual(id: String) -> bool:
	return VISUALS.has(ItemDB.canonical(id))


## [[path, height], ...] for an item (table first, then the ItemDB model), [] when it only has a placeholder.
static func variants(id: String) -> Array:
	var cid := ItemDB.canonical(id)
	if VISUALS.has(cid):
		return (VISUALS[cid]["models"] as Array)
	var d: Dictionary = ItemDB.get_item(cid)
	if d.has("models"):
		return d["models"] as Array
	if str(d.get("model", "")) != "":
		return [[str(d["model"]), float(d.get("model_height", 0.25))]]
	return []


## Glow / inventory colour for an item (the table, else the ItemDB colour).
static func accent(id: String) -> Color:
	var cid := ItemDB.canonical(id)
	if VISUALS.has(cid):
		return (VISUALS[cid]["accent"] as Color)
	return ItemDB.item_color(cid)


## {model, height, tint (Color, alpha 0 = none), accent, source: "table" | "item" | "placeholder"} for one pickup.
static func resolve(id: String, loot_id: int = 0) -> Dictionary:
	var cid := ItemDB.canonical(id)
	var v: Array = variants(cid)
	var src := "placeholder"
	if not v.is_empty():
		src = "table" if VISUALS.has(cid) else "item"
	var out := {"model": "", "height": 0.25, "tint": Color(1, 1, 1, 0), "accent": accent(cid), "source": src}
	if v.is_empty():
		return out
	var pick: Array = v[absi(loot_id) % v.size()] as Array
	out["model"] = str(pick[0])
	out["height"] = float(pick[1])
	if VISUALS.has(cid) and (VISUALS[cid] as Dictionary).has("tint"):
		out["tint"] = (VISUALS[cid]["tint"] as Color)
	return out


## Loads the resolved model fitted to its height and span, tinted; null when the item has no loadable model.
## The wrapper carries meta "size" like ModelUtil.load_fit.
static func instantiate(id: String, loot_id: int = 0) -> Node3D:
	var r: Dictionary = resolve(id, loot_id)
	if str(r["model"]) == "":
		return null
	var m: Node3D = ModelUtil.load_fit(str(r["model"]), float(r["height"]))
	if m == null:
		return null
	var size: Vector3 = m.get_meta("size") as Vector3
	var span: float = maxf(size.x, size.z)
	if span > MAX_SPAN:
		var k: float = MAX_SPAN / span
		m.scale = Vector3(k, k, k)
		m.set_meta("size", size * k)
	var tint: Color = r["tint"] as Color
	if tint.a > 0.0:
		_tint(m, tint)
	return m


static func _tint(n: Node, tint: Color) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh != null:
			for s in mi.mesh.get_surface_count():
				var base := mi.get_active_material(s) as StandardMaterial3D
				var mat: StandardMaterial3D = base.duplicate() as StandardMaterial3D if base != null else StandardMaterial3D.new()
				mat.albedo_color = Color(mat.albedo_color.r * tint.r, mat.albedo_color.g * tint.g, mat.albedo_color.b * tint.b, mat.albedo_color.a)
				mi.set_surface_override_material(s, mat)
	for c in n.get_children():
		_tint(c, tint)
