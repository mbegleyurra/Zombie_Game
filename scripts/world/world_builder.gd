extends Node3D
## Loads the Dead Acres world from the BAKED scenes (scenes/world/world_baked.tscn and scenes/world/baked/*.tscn).
## Nothing is generated at runtime: terrain, buildings, vegetation, props, the dungeon, cars, loot and every spawn point
## are saved nodes, so the world is identical on every peer and every run, and edits made in the editor are what the
## game plays. The bake-only generator that produced the scenes lives in tools/worldgen/ (see baked/BAKE_NOTES.md).
##
## Public API:
##   build(seed)                      load everything (call once; the seed is ignored)
##   get_height(x, z) -> float        baked heightmap (bilinear), else a downward physics ray
##   get_spawn_point(i) -> Vector3    player_spawn marker slot (wraps around)
##   get_locations(type="") -> Array  [{id,type,name,pos:Vector3,pos2,rot,radius,node}] from the location markers
##   nearest_location(pos,type="")    closest location dict or {}
##   next_loot_id() / register_loot(node) / get_loot(id)
##   spawn_ground_item(item_id, count, pos, loot_id=-1) -> Node
##   apply_loot_removed(id) / apply_container_opened(id)   network-sync helpers
## Signals: built, loot_picked_up(loot_id, by), container_opened(loot_id, by)
## Nodes: day_night (day_night.gd), terrain (the baked Terrain node, read-only queries via baked_terrain.gd),
## markers (baked Markers). Groups used: "interactable", "loot_item", "loot_container".

signal built
signal loot_picked_up(loot_id: int, by)
signal container_opened(loot_id: int, by)

const BAKED_SCENE := "res://scenes/world/world_baked.tscn"
const MANIFEST := "res://scenes/world/baked/res/bake_manifest.json"
const BakedTerrain = preload("res://scripts/world/baked_terrain.gd")
const LootItem = preload("res://scripts/world/loot_item.gd")
const HALF := 256.0
const MASK_WORLD := 1
## Sub-scene roots that only hold content: their children are moved up under World so node paths stay as they were
## before the bake (World/KayKitForest, World/Props, World/KenneyDressing, World/Dungeon, World/Vehicles/Car_N,
## World/HandWorld, World/<location>_<id>, World/Roads). Terrain and Markers stay as they are.
const HOIST := ["Roads", "Buildings", "Vegetation", "Props", "Dungeon", "Vehicles"]
## World-level metadata the baked Markers root carries (the generator used to set it on the world).
const WORLD_META := ["dungeon_site", "hand_footprints", "citykit", "spawn_center", "roads", "flats"]

## Kept for API compatibility (main.gd / network pass it in); it no longer changes anything.
var world_seed: int = 0
var start_hour: float = 9.0
var terrain: Node3D
var day_night: Node3D
var markers: Node3D
var locations: Array = []
var loot_by_id: Dictionary = {}
var spawn_center := Vector2.ZERO
## Builder counts recorded by the bake (baked/res/bake_manifest.json "builder"), for tests and logs.
var dressing_counts: Dictionary = {}
var forest_counts: Dictionary = {}

var _spawns: Array = []          # player_spawn markers, ordered by meta "slot"
var _loot_counter: int = 0
var _dyn_counter: int = 1000000
var _is_built: bool = false


func build(p_seed: int = 0) -> void:
	if _is_built:
		return
	_is_built = true
	world_seed = p_seed
	var t0: int = Time.get_ticks_msec()
	var packed := load(BAKED_SCENE) as PackedScene
	if packed == null:
		push_error("[World] missing baked world %s" % BAKED_SCENE)
		return
	var baked: Node = packed.instantiate()
	_adopt(baked)
	baked.free()
	terrain = get_node_or_null("Terrain") as Node3D
	markers = get_node_or_null("Markers") as Node3D
	day_night = get_node_or_null("DayNight") as Node3D
	if markers != null:
		for k in WORLD_META:
			if markers.has_meta(k):
				set_meta(k, markers.get_meta(k))
	spawn_center = get_meta("spawn_center", Vector2.ZERO) as Vector2
	if terrain != null:
		terrain.load_data(get_meta("roads", []) as Array, get_meta("flats", []) as Array)
	_read_markers()
	_register_baked_loot()
	_read_manifest()
	print("[World] baked world loaded in %dms: loot_nodes=%d locations=%d spawns=%d" % [
		Time.get_ticks_msec() - t0, loot_by_id.size(), locations.size(), _spawns.size()])
	built.emit()


## Moves the baked scene's nodes under this World (hoisting content holders), before they enter the tree, so _ready
## runs once in place. The Terrain node gets baked_terrain.gd for its read-only height / road queries.
func _adopt(baked: Node) -> void:
	for top in baked.get_children():
		baked.remove_child(top)
		if String(top.name) in HOIST:
			for c in top.get_children():
				top.remove_child(c)
				add_child(c)
			top.free()
			continue
		if top.name == &"Terrain" and top.get_script() == null:
			top.set_script(BakedTerrain)
		if top.name == &"DayNight":
			top.set("time_hours", start_hour)
		add_child(top)


func _read_markers() -> void:
	locations.clear()
	_spawns.clear()
	if markers == null:
		return
	var locs: Array = []
	var loc_root: Node = markers.get_node_or_null("Locations")
	if loc_root != null:
		for m in loc_root.get_children():
			if m is Node3D and m.is_in_group("location"):
				locs.append(m)
	locs.sort_custom(func(a, b): return int(a.get_meta("id", 0)) < int(b.get_meta("id", 0)))
	for m in locs:
		var mk := m as Node3D
		var p: Vector3 = local_xf(mk).origin
		var type: String = str(mk.get_meta("type", ""))
		var id: int = int(mk.get_meta("id", locations.size()))
		locations.append({
			"id": id, "type": type, "name": str(mk.get_meta("name", "")),
			"pos": p, "pos2": Vector2(p.x, p.z), "rot": local_xf(mk).basis.get_euler().y,
			"radius": float(mk.get_meta("radius", 20.0)),
			"node": get_node_or_null("%s_%d" % [type, id]),
		})
	var sp: Node = markers.get_node_or_null("PlayerSpawns")
	if sp != null:
		for m in sp.get_children():
			if m is Node3D and m.is_in_group("player_spawn"):
				_spawns.append(m)
	_spawns.sort_custom(func(a, b): return int(a.get_meta("slot", 0)) < int(b.get_meta("slot", 0)))


## Every baked pickup and container is registered by its saved loot_id (stable, identical on every peer).
func _register_baked_loot() -> void:
	# Walk the whole world (not only Markers), so a crate or pickup placed anywhere in the editor is registered too.
	for n in find_children("*", "", true, false):
		if not (n.is_in_group("loot_container") or n.is_in_group("loot_item")) or not ("loot_id" in n):
			continue
		if int(n.loot_id) < 0:
			continue
		if loot_by_id.has(int(n.loot_id)):
			push_error("[World] duplicate baked loot_id %d (%s)" % [int(n.loot_id), n.name])
		register_loot(n)
		_loot_counter = maxi(_loot_counter, int(n.loot_id))


func _read_manifest() -> void:
	if not FileAccess.file_exists(MANIFEST):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if parsed is Dictionary and (parsed as Dictionary).get("builder") is Dictionary:
		var b: Dictionary = parsed["builder"]
		dressing_counts = b.get("dressing", {}) as Dictionary
		forest_counts = b.get("forest", {}) as Dictionary


## Transform of `n` relative to this World, composed from local transforms (valid before the world is in the tree).
func local_xf(n: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	while n != null and n != self:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


# ------------------------------------------------------------------ API

func get_height(x: float, z: float) -> float:
	if terrain != null and terrain.has_method("has_height") and terrain.has_height(x, z):
		return terrain.height_at(x, z)
	return _ray_height(x, z)


## Highest world-collision hit straight down at (x, z), or 0 when nothing is there (or physics is not ready).
func _ray_height(x: float, z: float) -> float:
	if not is_inside_tree():
		return 0.0
	var space := get_world_3d().direct_space_state
	if space == null:
		return 0.0
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 500.0, z), Vector3(x, -500.0, z), MASK_WORLD)
	var hit := space.intersect_ray(q)
	return float((hit["position"] as Vector3).y) if not hit.is_empty() else 0.0


func get_spawn_point(i: int = 0) -> Vector3:
	if _spawns.is_empty():
		return Vector3(spawn_center.x, get_height(spawn_center.x, spawn_center.y) + 0.8, spawn_center.y)
	return local_xf(_spawns[posmod(i, _spawns.size())] as Node3D).origin


func get_locations(type: String = "") -> Array:
	if type == "":
		return locations
	var out: Array = []
	for l in locations:
		if l["type"] == type:
			out.append(l)
	return out


func nearest_location(pos: Vector3, type: String = "") -> Dictionary:
	var best: Dictionary = {}
	var best_d := INF
	for l in get_locations(type):
		var d: float = (l["pos"] as Vector3).distance_to(pos)
		if d < best_d:
			best_d = d
			best = l
	return best


func next_loot_id() -> int:
	_loot_counter += 1
	return _loot_counter


func register_loot(n) -> void:
	loot_by_id[n.loot_id] = n
	if n.has_signal("picked_up") and not n.picked_up.is_connected(_on_item_picked):
		n.picked_up.connect(_on_item_picked)
	if n.has_signal("opened") and not n.opened.is_connected(_on_container_opened):
		n.opened.connect(_on_container_opened)


func get_loot(id: int):
	var n = loot_by_id.get(id)
	if n != null and is_instance_valid(n):
		return n
	return null


## Drops a pickup into the world. Pass an explicit loot_id when mirroring the host's drop on a client.
func spawn_ground_item(item_id: String, count: int, pos: Vector3, loot_id: int = -1) -> Node:
	if loot_id < 0:
		_dyn_counter += 1
		loot_id = _dyn_counter
	var item = LootItem.create(item_id, count, loot_id)
	item.position = pos   # World sits at the origin; works before the world enters the tree
	add_child(item)
	register_loot(item)
	return item


func apply_loot_removed(id: int) -> void:
	var n = get_loot(id)
	if n != null and n.has_method("interact") and n.is_in_group("loot_item"):
		loot_by_id.erase(id)
		n.queue_free()


func apply_container_opened(id: int) -> void:
	var n = get_loot(id)
	if n != null and n.has_method("apply_open_state"):
		n.apply_open_state(true)


func _on_item_picked(item, by) -> void:
	loot_by_id.erase(item.loot_id)
	loot_picked_up.emit(item.loot_id, by)


func _on_container_opened(c, by) -> void:
	container_opened.emit(c.loot_id, by)
