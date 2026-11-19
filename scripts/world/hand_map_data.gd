extends RefCounted
## Reader for the HAND-AUTHORED world placements in data/hand_map/placements.json.
## Every tree, rock, prop, gravestone, hay bale, pickup, loot container, zombie spawn and dungeon choice is one
## explicit row in that file (position, rotation, scale), so the world is identical on every run and every peer.
## Nothing here (or in the builders that use it) draws random numbers.
##
## Sections (row layout):
##   FOREST          [kind, model, x, z, yaw, scale]
##   DRESSING        [category, dir, file, height, x, z, yaw, collider_mode, lift]
##   VEHICLES        [kind, x, z, yaw]
##   PICKUPS         [item, amount, x, z]
##   CONTAINERS      [loot_id, kind, table, [[item, count], ...]]
##   SCATTER         [location_id, item, amount, local_x, local_z, yaw]
##   LOCAL           [location_id, file, height, local_x, local_z, yaw, solid, post_radius, local_y]
##   CH_STONE        [location_id, local_x, local_z, yaw]
##   FARM            [location_id, wall_colour_index]
##   FARM_VEH        [location_id, tractor_yaw, pickup_yaw]
##   RACK            [location_id, x, y, z, width, height, shade]
##   WH_COL          [location_id, c0, c1, c2]
##   DUN_SITE        [x, z]            DUN_BROKEN [pillar_index]      DUN_WALL [wall_key, cracked]
##   ZOMBIE_SPAWNS   [x, z, yaw, kind_roll, variant_seed]
##   SKELETON_SPAWNS [x, z, yaw, type_roll, variant_seed]

const FILE := "res://data/hand_map/placements.json"

static var _data: Dictionary = {}
static var _loaded := false


static func section(sec: String) -> Array:
	if not _loaded:
		_load()
	return _data.get(sec, []) as Array


## Rows of `sec` whose first column (the location id) equals `loc_id`, in file order.
static func for_loc(sec: String, loc_id: int) -> Array:
	var out: Array = []
	for row in section(sec):
		if int((row as Array)[0]) == loc_id:
			out.append(row)
	return out


## Container row by loot id, or an empty array.
static func container(loot_id: int) -> Array:
	if not _loaded:
		_load()
	return _by_loot.get(loot_id, []) as Array


static var _by_loot: Dictionary = {}


static func _load() -> void:
	_loaded = true
	var f := FileAccess.open(FILE, FileAccess.READ)
	if f == null:
		push_error("[HandMapData] missing %s" % FILE)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		push_error("[HandMapData] %s is not a JSON object" % FILE)
		return
	_data = parsed as Dictionary
	for row in (_data.get("CONTAINERS", []) as Array):
		_by_loot[int((row as Array)[0])] = row


## Dungeon: authored entrance site [x, z], or Vector2(120, 120) when the row is missing.
static func dungeon_site() -> Vector2:
	var rows: Array = section("DUN_SITE")
	if rows.is_empty():
		return Vector2(120.0, 120.0)
	return Vector2(float((rows[0] as Array)[0]), float((rows[0] as Array)[1]))


## Dungeon: index (0-3) of the one broken pillar in the entrance hall.
static func dungeon_broken() -> int:
	var rows: Array = section("DUN_BROKEN")
	return int((rows[0] as Array)[0]) if not rows.is_empty() else 0


static var _cracked: Dictionary = {}
static var _cracked_ready := false


## Dungeon: true when the plain wall at `key` ("H,x,y" / "V,x,y") is authored as the cracked variant.
static func dungeon_wall_cracked(key: String) -> bool:
	if not _cracked_ready:
		_cracked_ready = true
		for row in section("DUN_WALL"):
			_cracked[str((row as Array)[0])] = bool((row as Array)[1])
	return bool(_cracked.get(key, false))
