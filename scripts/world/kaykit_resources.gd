extends RefCounted
## KayKit Resource Bits (CC0) wired into Dead Acres: item definitions, loot tables, building-stock feed and
## deterministic ground pickups around locations and in the wild.
##
## ItemDB merges this file in (has_item / get_item / all_ids / roll_table), so nothing else has to know about it:
##   ITEMS    new item ids (ingots, nuggets, fuel can, parts, logs, coin)
##   VISUALS  KayKit model overrides for existing items (planks, scrap)
##   FEED     item -> [building stock item, units per item]; ItemDB.give_to credits Building with it
##   TABLES   new loot tables (the dungeon_* ones)
##   EXTRA    extra [id, weight, min, max] entries appended to existing tables
## Entries whose item id does not exist in ItemDB (for example a rifle that has not been added yet) are skipped
## when the table is read, so a table can name future items safely.

const RES := "res://assets/kaykit/resources/KayKit_ResourceBits_1.0_FREE/Assets/gltf/"
const DUN := "res://assets/kaykit/dungeon/KayKit_Dungeon_Pack_1.1_FREE/Assets/gltf/"

const ITEMS := {
	"iron_ingot": {
		"name": "Iron Ingot", "type": "material", "stack": 30, "weight": 0.5,
		"color": Color(0.55, 0.57, 0.62), "shape": "box", "desc": "Refined iron. Counts as 3 scrap for building.",
		"model": RES + "Iron_Bar.gltf", "model_height": 0.13,
	},
	"copper_ingot": {
		"name": "Copper Ingot", "type": "material", "stack": 30, "weight": 0.5,
		"color": Color(0.78, 0.45, 0.25), "shape": "box", "desc": "Refined copper. Counts as 2 scrap for building.",
		"model": RES + "Copper_Bar.gltf", "model_height": 0.13,
	},
	"silver_ingot": {
		"name": "Silver Ingot", "type": "valuable", "stack": 30, "weight": 0.5,
		"color": Color(0.8, 0.82, 0.88), "shape": "box", "desc": "A heavy bar of silver.",
		"model": RES + "Silver_Bar.gltf", "model_height": 0.13,
	},
	"gold_ingot": {
		"name": "Gold Ingot", "type": "valuable", "stack": 30, "weight": 0.7,
		"color": Color(0.95, 0.78, 0.2), "shape": "box", "desc": "A bar of solid gold.",
		"model": RES + "Gold_Bar.gltf", "model_height": 0.13,
	},
	"iron_nuggets": {
		"name": "Iron Nuggets", "type": "material", "stack": 40, "weight": 0.2,
		"color": Color(0.5, 0.52, 0.56), "shape": "box", "desc": "Raw iron ore. Counts as 1 scrap for building.",
		"model": RES + "Iron_Nuggets.gltf", "model_height": 0.16,
	},
	"copper_nuggets": {
		"name": "Copper Nuggets", "type": "material", "stack": 40, "weight": 0.2,
		"color": Color(0.75, 0.42, 0.22), "shape": "box", "desc": "Raw copper ore. Counts as 1 scrap for building.",
		"model": RES + "Copper_Nuggets.gltf", "model_height": 0.16,
	},
	"silver_nuggets": {
		"name": "Silver Nuggets", "type": "valuable", "stack": 40, "weight": 0.2,
		"color": Color(0.78, 0.8, 0.86), "shape": "box", "desc": "Raw silver.",
		"model": RES + "Silver_Nuggets.gltf", "model_height": 0.16,
	},
	"gold_nuggets": {
		"name": "Gold Nuggets", "type": "valuable", "stack": 40, "weight": 0.2,
		"color": Color(0.92, 0.75, 0.18), "shape": "box", "desc": "Raw gold.",
		"model": RES + "Gold_Nuggets.gltf", "model_height": 0.16,
	},
	"fuel_can": {
		"name": "Fuel Can", "type": "material", "stack": 6, "weight": 4.0,
		"color": Color(0.8, 0.2, 0.15), "shape": "can", "desc": "A jerrycan of fuel.",
		"model": RES + "Fuel_A_Jerrycan.gltf", "model_height": 0.36,
		"models": [[RES + "Fuel_A_Jerrycan.gltf", 0.36], [RES + "Fuel_B_Jerrycan.gltf", 0.36], [RES + "Fuel_C_Jerrycan.gltf", 0.36]],
	},
	"parts": {
		"name": "Machine Parts", "type": "material", "stack": 30, "weight": 0.6,
		"color": Color(0.5, 0.5, 0.55), "shape": "scrap", "desc": "Cogs and spare parts. Counts as 2 scrap for building.",
		"model": RES + "Parts_Pile_Small.gltf", "model_height": 0.24,
	},
	"wood_logs": {
		"name": "Wood Logs", "type": "material", "stack": 20, "weight": 1.2,
		"color": Color(0.5, 0.34, 0.2), "shape": "long", "desc": "Cut logs. Counts as 3 planks for building.",
		"model": RES + "Wood_Log_A.gltf", "model_height": 0.22,
		"models": [[RES + "Wood_Log_A.gltf", 0.22], [RES + "Wood_Log_B.gltf", 0.22]],
	},
	"coin": {
		"name": "Gold Coin", "type": "valuable", "stack": 200, "weight": 0.01,
		"color": Color(0.95, 0.8, 0.25), "shape": "box", "desc": "Old dungeon coin.",
		"model": DUN + "coin_stack_small.gltf", "model_height": 0.14,
	},
}

## Model overrides merged over existing item definitions.
const VISUALS := {
	"planks": {
		"model": RES + "Wood_Planks_Stack_Small.gltf", "model_height": 0.2,
		"models": [[RES + "Wood_Planks_Stack_Small.gltf", 0.2], [RES + "Wood_Plank_A.gltf", 0.1], [RES + "Wood_Planks_Stack_Medium.gltf", 0.3]],
	},
	"scrap": {
		"model": RES + "Parts_Pile_Small.gltf", "model_height": 0.24,
		"models": [[RES + "Parts_Pile_Small.gltf", 0.24], [RES + "Parts_Pile_Medium.gltf", 0.32], [RES + "Parts_Cog.gltf", 0.16]],
	},
}

## Items that also feed the building stock (which only knows planks and scrap): item -> [stock item, units each].
const FEED := {
	"iron_ingot": ["scrap", 3], "copper_ingot": ["scrap", 2], "iron_nuggets": ["scrap", 1],
	"copper_nuggets": ["scrap", 1], "parts": ["scrap", 2], "wood_logs": ["planks", 3],
}

## New tables. "rolls" = [min, max], entries = [item_id, weight, min_count, max_count].
const TABLES := {
	"dungeon_chest": {
		"rolls": [3, 5],
		"entries": [
			["ammo_762", 14, 6, 14], ["ammo_556", 14, 8, 20], ["ammo_9mm", 10, 10, 24], ["ammo_12ga", 10, 4, 10],
			["medkit", 16, 1, 2], ["iron_ingot", 10, 1, 3], ["copper_ingot", 9, 1, 3], ["silver_ingot", 6, 1, 2],
			["gold_nuggets", 8, 1, 4], ["coin", 14, 6, 20], ["parts", 7, 1, 3], ["fuel_can", 3, 1, 1],
			["weapon_hunting", 3, 1, 1], ["weapon_shotgun", 3, 1, 1], ["weapon_m4", 3, 1, 1], ["weapon_ak", 3, 1, 1],
			["weapon_ar", 4, 1, 1],
		],
	},
	"dungeon_gold": {
		"rolls": [4, 6],
		"entries": [
			["ammo_762", 16, 20, 40], ["ammo_556", 16, 20, 40], ["ammo_12ga", 8, 8, 16], ["ammo_9mm", 6, 20, 40],
			["medkit", 16, 2, 3], ["gold_ingot", 14, 1, 3], ["silver_ingot", 10, 1, 3], ["gold_nuggets", 10, 2, 6],
			["coin", 16, 15, 40], ["weapon_hunting", 8, 1, 1], ["weapon_m4", 8, 1, 1], ["weapon_ak", 8, 1, 1],
			["weapon_shotgun", 6, 1, 1], ["weapon_ar", 10, 1, 1],
		],
	},
	"dungeon_barrel": {
		"rolls": [1, 2],
		"entries": [
			["fuel_can", 8, 1, 1], ["water", 14, 1, 2], ["food", 10, 1, 2], ["scrap", 10, 1, 3], ["parts", 10, 1, 2],
			["planks", 8, 1, 3], ["coin", 8, 2, 8], ["ammo_9mm", 8, 6, 14], ["medkit", 4, 1, 1], ["wood_logs", 5, 1, 2],
		],
	},
	"dungeon_crate": {
		"rolls": [1, 3],
		"entries": [
			["planks", 12, 2, 5], ["scrap", 12, 2, 4], ["iron_ingot", 8, 1, 2], ["copper_ingot", 7, 1, 2], ["parts", 8, 1, 2],
			["iron_nuggets", 7, 2, 4], ["ammo_9mm", 6, 6, 14], ["ammo_12ga", 5, 2, 6], ["food", 6, 1, 2], ["coin", 6, 3, 10],
		],
	},
	"dungeon_bottles": {
		"rolls": [1, 2],
		"entries": [["water", 20, 1, 2], ["medkit", 8, 1, 1], ["food", 8, 1, 1], ["coin", 6, 2, 6]],
	},
}

## Entries appended to existing tables so resources also turn up in ordinary containers.
const EXTRA := {
	"warehouse": [["iron_ingot", 8, 1, 3], ["copper_ingot", 6, 1, 3], ["parts", 10, 1, 3], ["fuel_can", 4, 1, 1], ["wood_logs", 6, 1, 2]],
	"barn": [["wood_logs", 8, 1, 2], ["parts", 6, 1, 2], ["iron_nuggets", 5, 1, 3]],
	"farm": [["wood_logs", 6, 1, 2], ["parts", 4, 1, 2], ["fuel_can", 3, 1, 1]],
	"gas_station": [["fuel_can", 14, 1, 2], ["parts", 5, 1, 2]],
	"police": [["iron_ingot", 3, 1, 2]],
	"church": [["silver_ingot", 2, 1, 1], ["coin", 4, 2, 8]],
	"wild": [["iron_nuggets", 6, 1, 3], ["copper_nuggets", 5, 1, 3], ["wood_logs", 5, 1, 2], ["parts", 4, 1, 2],
		["silver_nuggets", 1.5, 1, 2], ["gold_nuggets", 1, 1, 2]],
}

## Ground pickups per location type: [item, min, max] each placed once just outside the pad ring.
const LOCATION_SPAWNS := {
	"gas_station": [["fuel_can", 1, 2], ["fuel_can", 1, 1], ["parts", 1, 2]],
	"warehouse": [["planks", 3, 6], ["planks", 2, 5], ["iron_ingot", 1, 2], ["copper_ingot", 1, 2], ["parts", 1, 3]],
	"farm": [["wood_logs", 1, 2], ["planks", 2, 4], ["parts", 1, 1]],
	"police_station": [["iron_ingot", 1, 1], ["parts", 1, 2]],
	"church": [["silver_ingot", 1, 1], ["wood_logs", 1, 1]],
	"hospital": [["parts", 1, 1]],
}
const WILD_DEPOSITS := 18
const WILD_ITEMS := [["iron_nuggets", 3, 7], ["copper_nuggets", 3, 7], ["wood_logs", 1, 3], ["parts", 1, 2],
	["iron_ingot", 1, 1], ["silver_nuggets", 1, 3], ["planks", 2, 5], ["gold_nuggets", 1, 2]]


static func feed_for(item_id: String) -> Array:
	return FEED.get(item_id, []) as Array


## Wires the ground-pickup scatter to the world's `built` signal (called from DungeonBuilder.attach).
static func attach(world: Node) -> void:
	world.built.connect(func(): scatter(world))


## Places the deterministic ground pickups. Uses next_loot_id() so every peer builds identical ids.
## Returns the number of pickups placed.
static func scatter(world: Node) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = (world.world_seed ^ 0x4B41) & 0x7FFFFFFF
	var terrain = world.terrain
	var placed: Array = []   # Vector2
	var count := 0
	for l in world.locations:
		var spawns: Array = LOCATION_SPAWNS.get(str(l["type"]), []) as Array
		for sp in spawns:
			var p := _find_spot(world, terrain, rng, l["pos2"], float(l["radius"]) + 1.5, float(l["radius"]) + 4.5, placed)
			if p.x > 1.0e8:
				continue
			placed.append(p)
			_drop(world, str(sp[0]), rng.randi_range(int(sp[1]), int(sp[2])), p)
			count += 1
	var limit: float = 200.0
	var tries := 0
	var deposits := 0
	while deposits < WILD_DEPOSITS and tries < 600:
		tries += 1
		var p := Vector2(rng.randf_range(-limit, limit), rng.randf_range(-limit, limit))
		var pick: Array = WILD_ITEMS[rng.randi_range(0, WILD_ITEMS.size() - 1)]
		var amt: int = rng.randi_range(int(pick[1]), int(pick[2]))
		if not _spot_ok(world, terrain, p, 8.0, placed):
			continue
		var h: float = terrain.height_at(p.x, p.y)
		if h < -1.0 or h > 14.0:
			continue
		placed.append(p)
		_drop(world, str(pick[0]), amt, p)
		deposits += 1
		count += 1
	return count


static func _drop(world: Node, item: String, amount: int, p: Vector2) -> void:
	var y: float = world.terrain.height_at(p.x, p.y) + 0.06
	world.spawn_ground_item(item, amount, Vector3(p.x, y, p.y), world.next_loot_id())


static func _find_spot(world: Node, terrain, rng: RandomNumberGenerator, center: Vector2, r0: float, r1: float, placed: Array) -> Vector2:
	for _i in 24:
		var a: float = rng.randf() * TAU
		var r: float = rng.randf_range(r0, r1)
		var p: Vector2 = center + Vector2(cos(a), sin(a)) * r
		if _spot_ok(world, terrain, p, 0.0, placed):
			return p
	return Vector2(1.0e9, 1.0e9)


## Flat enough, off every placed pickup, off the procedural props, off the Kenney dressing colliders.
## clear_margin > 0 additionally demands terrain.is_clear(x, z, margin) (wild deposits stay off pads and roads).
static func _spot_ok(world: Node, terrain, p: Vector2, clear_margin: float, placed: Array) -> bool:
	if absf(p.x) > 215.0 or absf(p.y) > 215.0:
		return false
	if clear_margin > 0.0 and not terrain.is_clear(p.x, p.y, clear_margin):
		return false
	if terrain.normal_at(p.x, p.y).y < 0.93:
		return false
	for q in placed:
		if (q as Vector2).distance_to(p) < 2.5:
			return false
	for q in world.prop_points:
		if (q as Vector2).distance_to(p) < 2.6:
			return false
	return not blocked_by_dressing(world, p, 0.7)


## True if (x, z) lies inside (or within `pad` of) any Kenney-dressing or KayKit-forest collider. The scatter runs on
## `built`, after both exist, so deposits are rejected here instead of the forest having to dodge them.
static func blocked_by_dressing(world: Node, p: Vector2, pad: float) -> bool:
	for path in ["KenneyDressing/Collision", "KayKitForest/Collision"]:
		if _blocked_by_body(world.get_node_or_null(path), p, pad):
			return true
	return false


static func _blocked_by_body(body: Node, p: Vector2, pad: float) -> bool:
	if body == null:
		return false
	for c in body.get_children():
		var cs := c as CollisionShape3D
		if cs == null or cs.shape == null:
			continue
		var lp: Vector3 = cs.global_transform.affine_inverse() * Vector3(p.x, cs.global_position.y, p.y)
		if cs.shape is BoxShape3D:
			var h: Vector3 = (cs.shape as BoxShape3D).size * 0.5
			if absf(lp.x) <= h.x + pad and absf(lp.z) <= h.z + pad:
				return true
		elif cs.shape is CylinderShape3D:
			if Vector2(lp.x, lp.z).length() <= (cs.shape as CylinderShape3D).radius + pad:
				return true
		elif cs.shape is SphereShape3D:
			if Vector2(lp.x, lp.z).length() <= (cs.shape as SphereShape3D).radius + pad:
				return true
		elif cs.shape is CapsuleShape3D:
			if Vector2(lp.x, lp.z).length() <= (cs.shape as CapsuleShape3D).radius + pad:
				return true
	return false
