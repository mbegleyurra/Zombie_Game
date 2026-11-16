extends RefCounted
## Base-building extras for Building: stairs, base core, storage chest, assembler.
## Pure data and geometry. Building merges KINDS/DEFS in _ready() and delegates mesh building, placement
## rules and stair snapping here; chest/assembler state and networking live in base_system.gd.
##
## Stairs use slots 4..7 (one per climb direction N, E, S, W = -Z, +X, +Z, -X) and occupy one cell. A piece
## climbs STAIR_STEPS * YSTEP = 1.25 m over one 2 m cell (32 degrees, under the CharacterBody3D 45 degree
## floor limit), so it is collided as a smooth ramp; the treads are visual. Two chained pieces plus a floor
## reach the next storey (STOREY_STEPS = one wall height). Aim a floor or stairs at a stairs piece and
## Building snaps it to the landing cell on top (landing_key / chain_key).
## Core, chest and assembler sit on the cell centre (SLOT_BENCH) like the workbench.

const ItemDB := preload("res://scripts/world/item_db.gd")
const Recipes := preload("res://scripts/world/recipes.gd")

const CELL := 2.0
const YSTEP := 0.25
const SLOT_FLOOR := 0
const SLOT_BENCH := 3
const SLOT_STAIR := 4
const STAIR_STEPS := 5
const STOREY_STEPS := 10

const KINDS: Array[String] = ["stairs", "base_core", "chest", "assembler"]
const DEFS := {
	"stairs": {"cost": {"planks": 6}, "hp": 180.0, "slot": "stair"},
	"base_core": {"cost": {"planks": 10, "scrap": 10}, "hp": 400.0, "slot": "bench"},
	"chest": {"cost": {"planks": 6, "scrap": 2}, "hp": 150.0, "slot": "bench"},
	"assembler": {"cost": {"planks": 10, "scrap": 16}, "hp": 220.0, "slot": "bench"},
}


# ------------------------------------------------------------------- stairs

## Climb direction of a stair as a cell offset (x, z): 0 = -Z, 1 = +X, 2 = +Z, 3 = -X.
static func stair_dir(d: int) -> Vector2i:
	match posmod(d, 4):
		0:
			return Vector2i(0, -1)
		1:
			return Vector2i(1, 0)
		2:
			return Vector2i(0, 1)
	return Vector2i(-1, 0)


## Yaw that turns the piece's local -Z (its climb direction) onto stair_dir(d).
static func stair_yaw(d: int) -> float:
	return -float(posmod(d, 4)) * PI * 0.5


static func is_stair_slot(w: int) -> bool:
	return w >= SLOT_STAIR and w < SLOT_STAIR + 4


## Stairs placed where the player looks: they climb away from the player.
static func stair_key(gx: int, yk: int, gz: int, from: Vector3, pos: Vector3) -> Vector4i:
	var v := Vector2(pos.x - from.x, pos.z - from.z)
	var d := 0
	if absf(v.x) > absf(v.y):
		d = 1 if v.x > 0.0 else 3
	else:
		d = 2 if v.y > 0.0 else 0
	return Vector4i(gx, yk, gz, SLOT_STAIR + d)


## Floor cell at the top of a stairs piece.
static func landing_key(sk: Vector4i) -> Vector4i:
	var v := stair_dir(sk.w - SLOT_STAIR)
	return Vector4i(sk.x + v.x, sk.y + STAIR_STEPS, sk.z + v.y, SLOT_FLOOR)


## Next stairs piece in the same direction, standing on the landing.
static func chain_key(sk: Vector4i) -> Vector4i:
	var v := stair_dir(sk.w - SLOT_STAIR)
	return Vector4i(sk.x + v.x, sk.y + STAIR_STEPS, sk.z + v.y, sk.w)


# ------------------------------------------------------------ placement rules

## "" when the piece may go there, else the rejection text. Server side, after the slot checks.
static func validate(b: Node, kind: String, key: Vector4i) -> String:
	match kind:
		"stairs":
			for d in 4:
				var k := Vector4i(key.x, key.y, key.z, SLOT_STAIR + d)
				if k != key and b.slots.has(k):
					return "Stairs already here"
			if b.slots.has(Vector4i(key.x, key.y + STAIR_STEPS, key.z, SLOT_FLOOR)):
				return "Floor in the way"
		"floor":
			for d in 4:
				if b.slots.has(Vector4i(key.x, key.y - STAIR_STEPS, key.z, SLOT_STAIR + d)):
					return "Stairs in the way"
		"base_core":
			var base = b.get("base")
			if base != null and int(base.core_id) != 0 and b.pieces.has(int(base.core_id)):
				return "Base already claimed"
	return ""


# ----------------------------------------------------------------- recipes

## Output item id of a workbench recipe ("weapon_ar_t1", "ammo_9mm").
static func output_item(r: Dictionary) -> String:
	var give := String(r.get("give", ""))
	if String(r.get("kind", "")) == "weapon":
		return "weapon_" + give
	return ItemDB.canonical(give)


## Recipes the assembler can make: every workbench recipe whose product is a real item.
static func recipes() -> Array:
	var out: Array = []
	for r in Recipes.all():
		if ItemDB.has_item(output_item(r)):
			out.append(r)
	return out


static func recipe_ok(recipe_id: String) -> bool:
	var r := Recipes.get_recipe(recipe_id)
	return not r.is_empty() and ItemDB.has_item(output_item(r))


## Seconds for one assembler cycle: bigger recipes take longer.
static func craft_time(r: Dictionary) -> float:
	var n := 0
	var cost: Dictionary = r.get("cost", {})
	for k in cost:
		n += int(cost[k])
	return 4.0 + 0.5 * float(n)


# ------------------------------------------------------------------ meshes

## Called by Building._make_piece for the kinds above. `b` is the Building node (its _box / colours).
static func build_piece(b: Node, root: Node3D, kind: String, ghost: bool) -> void:
	var wood: Color = b.COL_WOOD
	var wood_dark: Color = b.COL_WOOD_DARK
	var wood_light: Color = b.COL_WOOD_LIGHT
	var scrap: Color = b.COL_SCRAP
	match kind:
		"stairs":
			_build_stairs(b, root, ghost)
		"base_core":
			b._box(root, Vector3(1.4, 0.2, 1.4), Vector3(0, 0.1, 0), scrap, ghost)
			b._box(root, Vector3(0.14, 2.6, 0.14), Vector3(0, 1.5, 0), wood_dark, ghost)
			b._box(root, Vector3(0.9, 0.55, 0.05), Vector3(0.45, 2.2, 0), Color(0.75, 0.15, 0.12), ghost, false)
			b._box(root, Vector3(0.3, 0.3, 0.3), Vector3(0.45, 0.35, 0.45), wood, ghost, false)
		"chest":
			b._box(root, Vector3(1.2, 0.6, 0.7), Vector3(0, 0.3, 0), wood_dark, ghost)
			b._box(root, Vector3(1.24, 0.18, 0.74), Vector3(0, 0.69, 0), wood_light, ghost)
			for sx in [-0.4, 0.4]:
				b._box(root, Vector3(0.1, 0.62, 0.76), Vector3(sx, 0.31, 0), scrap, ghost, false)
			b._box(root, Vector3(0.14, 0.16, 0.06), Vector3(0, 0.62, 0.38), scrap, ghost, false)
		"assembler":
			b._box(root, Vector3(1.5, 0.9, 1.0), Vector3(0, 0.45, 0), scrap, ghost)
			b._box(root, Vector3(0.7, 0.3, 0.7), Vector3(-0.3, 1.05, 0), wood_dark, ghost)
			b._box(root, Vector3(0.12, 0.12, 1.3), Vector3(0.55, 1.05, 0), wood_light, ghost, false)
			_make_light(b, root, Vector3(0.45, 0.78, 0.52), ghost)


static func _build_stairs(b: Node, root: Node3D, ghost: bool) -> void:
	var rise := STAIR_STEPS * YSTEP
	var a := atan2(rise, CELL)
	var slope_len := sqrt(CELL * CELL + rise * rise)
	var light: Color = b.COL_WOOD_LIGHT
	var mid: Color = b.COL_WOOD
	var dark: Color = b.COL_WOOD_DARK
	# Treads climb toward local -Z; tops sit on the ramp's centre line at each tread's middle.
	for j in STAIR_STEPS:
		var top := 0.125 + 0.25 * j
		b._box(root, Vector3(CELL - 0.3, top, 0.4), Vector3(0.0, top * 0.5, 0.8 - 0.4 * j), light if j % 2 == 0 else mid, ghost, false)
	var off := Vector3(0.0, rise * 0.5 - 0.1 * cos(a), -0.1 * sin(a))
	for sx in [-0.9, 0.9]:
		var s: MeshInstance3D = b._box(root, Vector3(0.12, 0.2, slope_len), off + Vector3(sx, 0.0, 0.0), dark, ghost, false)
		s.rotation.x = a
	if not ghost and root is CollisionObject3D:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(CELL, 0.2, slope_len)
		cs.shape = bs
		cs.position = off
		cs.rotation.x = a
		root.add_child(cs)


## The assembler's status lamp. Own material so it can change colour; BaseSystem finds it by name "Light".
static func _make_light(b: Node, root: Node3D, pos: Vector3, ghost: bool) -> void:
	if ghost:
		b._box(root, Vector3(0.18, 0.18, 0.1), pos, Color.WHITE, true, false)
		return
	var mi := MeshInstance3D.new()
	mi.name = "Light"
	var bm := BoxMesh.new()
	bm.size = Vector3(0.18, 0.18, 0.1)
	mi.mesh = bm
	mi.position = pos
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.5, 0.5, 0.5)
	m.emission_enabled = true
	m.emission = Color(0.0, 0.0, 0.0)
	mi.material_override = m
	root.add_child(mi)
