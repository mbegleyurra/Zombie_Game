extends Node3D
## Builds the whole Dead Acres world from the HANDCRAFTED layout in hand_layout.gd:
## terrain, trees/rocks, locations (farms, gas stations, hospital, the city), loot, day/night, spawn points.
## The layout (roads, locations, houses, city blocks) is fixed data, and the relief/decoration seed is the constant
## HandLayout.HAND_SEED: build(seed) ignores its argument, so the world is identical on every peer and every run.
##
## Public API:
##   build(seed)                      build everything (call once)
##   get_height(x, z) -> float        terrain height
##   get_spawn_point(i) -> Vector3    player spawn slot (wraps around)
##   get_locations(type="") -> Array  [{id,type,name,pos:Vector3,rot,radius,node}]
##   nearest_location(pos,type="")    closest location dict or {}
##   next_loot_id() / register_loot(node) / get_loot(id)
##   spawn_ground_item(item_id, count, pos, loot_id=-1) -> Node
##   apply_loot_removed(id) / apply_container_opened(id)   network-sync helpers
## Signals: built, loot_picked_up(loot_id, by), container_opened(loot_id, by)
## Nodes: day_night (day_night.gd), terrain (terrain.gd). Groups used: "interactable", "loot_item", "loot_container".

signal built
signal loot_picked_up(loot_id: int, by)
signal container_opened(loot_id: int, by)

const MeshUtil = preload("res://scripts/world/mesh_util.gd")
const TerrainGen = preload("res://scripts/world/terrain.gd")
const BuildingFactory = preload("res://scripts/world/building_factory.gd")
const DayNight = preload("res://scripts/world/day_night.gd")
const LootItem = preload("res://scripts/world/loot_item.gd")
const PropFactory = preload("res://scripts/world/prop_factory.gd")
const ModelUtil = preload("res://scripts/world/model_util.gd")
const KenneyDressing = preload("res://scripts/world/kenney_dressing.gd")
const KayKitForest = preload("res://scripts/world/kaykit_forest.gd")
const VehicleSpawner = preload("res://scripts/vehicles/vehicle_spawner.gd")
const HandLayout = preload("res://scripts/world/hand_layout.gd")
const HandBuilder = preload("res://scripts/world/hand_builder.gd")
const HandMapData = preload("res://scripts/world/hand_map_data.gd")
const KENNEY_GY := "res://assets/kenney/graveyard/"

const ROADSIDE_MODEL := "res://assets/kenney/city-kit-roads/light-square.glb"
const ROADSIDE_H := 6.0

var world_seed: int = 1337
var start_hour: float = 9.0
var terrain: Node3D
var day_night: Node3D
var material: StandardMaterial3D
var locations: Array = []
var loot_by_id: Dictionary = {}
var spawn_center := Vector2.ZERO
## XZ of procedural trees, rocks and roadside wrecks, so the Kenney dressing can keep clear of them.
var prop_points := PackedVector2Array()
var dressing_counts: Dictionary = {}
var forest_counts: Dictionary = {}

var _loot_counter: int = 0
var _dyn_counter: int = 1000000
var _props: Node3D
var _factory
var _is_built: bool = false


func build(p_seed: int) -> void:
	if _is_built:
		return
	_is_built = true
	world_seed = HandLayout.HAND_SEED   # handcrafted world: the seed argument no longer changes anything
	var t0: int = Time.get_ticks_msec()
	material = MeshUtil.make_material()
	terrain = TerrainGen.new()
	terrain.name = "Terrain"
	add_child(terrain)
	terrain.setup(world_seed)
	_plan_locations()
	load("res://scripts/world/dungeon_builder.gd").attach(self)
	_add_dungeon_track()
	terrain.build_chunks(material)
	var t1: int = Time.get_ticks_msec()
	_build_props()
	var t2: int = Time.get_ticks_msec()
	_build_locations()
	var hand = HandBuilder.new(self)
	add_child(hand.build())
	print("[World] hand world: %s" % [str(hand.counts)])
	var t3: int = Time.get_ticks_msec()
	var dressing = KenneyDressing.new(self)
	add_child(dressing.build())
	dressing_counts = dressing.counts
	print("[World] kenney dressing: %s" % [str(dressing_counts)])
	var vehicles = VehicleSpawner.new(self)
	add_child(vehicles.build())
	print("[World] drivable vehicles: %d" % vehicles.cars.size())
	var forest = KayKitForest.new(self)
	add_child(forest.build())
	forest_counts = forest.counts
	print("[World] kaykit forest: %s" % [str(forest_counts)])
	day_night = DayNight.new()
	day_night.name = "DayNight"
	day_night.time_hours = start_hour
	add_child(day_night)
	print("[World] seed=%d terrain=%dms props=%dms locations=%dms total=%dms loot_nodes=%d locations=%d" % [
		world_seed, t1 - t0, t2 - t1, t3 - t2, Time.get_ticks_msec() - t0, loot_by_id.size(), locations.size()])
	built.emit()


# ------------------------------------------------------------------ API

func get_height(x: float, z: float) -> float:
	return terrain.height_at(x, z)


func get_spawn_point(i: int = 0) -> Vector3:
	var a: float = TAU * float(posmod(i, 8)) / 8.0
	var p := spawn_center + Vector2(cos(a), sin(a)) * 5.0
	return Vector3(p.x, terrain.height_at(p.x, p.y) + 0.8, p.y)


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
	if n.has_signal("picked_up"):
		n.picked_up.connect(_on_item_picked)
	if n.has_signal("opened"):
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
	add_child(item)
	item.global_position = pos
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


# ------------------------------------------------------------------ planning

## Builds the location list, ground pads and roads from HandLayout (fixed data, no RNG).
func _plan_locations() -> void:
	spawn_center = HandLayout.SPAWN
	for e in HandLayout.LOCATIONS:
		locations.append({
			"id": locations.size(), "type": str(e[0]), "name": str(e[1]),
			"pos2": Vector2(float(e[2]), float(e[3])), "pos": Vector3.ZERO, "rot": float(e[4]),
			"radius": float(e[5]), "node": null,
		})
	# Flat pads first (spawn, the city, every location); cottage pads follow the roads (below); the mesh is built after this.
	terrain.add_flat(spawn_center, 14.0, 24.0, terrain.height_at(spawn_center.x, spawn_center.y))
	# The street grid (plus a margin for the verge) is the city pad's exact-height core: the round pad also reaches
	# countryside such as the Hartley Farm gate, which must keep its own height.
	var city_core := Rect2(HandLayout.CITY_MIN - Vector2(8.0, 8.0), (HandLayout.CITY_MAX - HandLayout.CITY_MIN) + Vector2(16.0, 16.0))
	terrain.add_flat(HandLayout.CITY_CENTER, HandLayout.CITY_FLAT_R, HandLayout.CITY_FLAT_BLEND, HandLayout.CITY_HEIGHT, city_core)
	for l in locations:
		var p2: Vector2 = l["pos2"]
		terrain.add_flat(p2, float(l["radius"]), 18.0, terrain.height_at(p2.x, p2.y))
	# Roads: countryside polylines, the city street grid, then a driveway for every countryside location.
	for s in HandLayout.road_segments():
		terrain.add_road(s[0], s[1])
	# Driveways snap to the nearest road of ANY kind. Country roads alone sent the Harlan Freight driveway across the
	# whole city (through three towers) to City Link; its gate stands 0.5 m from the city's east street instead.
	var country: Array = HandLayout.road_segments()
	for l in locations:
		var p2: Vector2 = l["pos2"]
		if HandLayout.in_city(p2):
			continue
		var dir := Vector2(sin(float(l["rot"])), cos(float(l["rot"])))   # Basis(UP, rot) * +Z, the gate side
		var gate: Vector2 = p2 + dir * HandLayout.GATE_DIST
		var best: Vector2 = gate
		var best_d := INF
		for s in country:
			var q: Vector2 = Geometry2D.get_closest_point_to_segment(gate, s[0], s[1])
			if gate.distance_to(q) < best_d:
				best_d = gate.distance_to(q)
				best = q
		if best_d > 1.0:
			terrain.add_road(gate, best)
		terrain.add_road(gate, p2 + dir * 10.0)
	# Cottage pads last, at the level of the road bed in front of the house (natural height when no road reaches it):
	# the pad and the road then agree, so the footprint stays level and the road stays level beside it.
	for h in HandLayout.HOUSES:
		var hp := Vector2(float(h[0]), float(h[1]))
		var hh: float = terrain.road_bed_height(hp.x, hp.y)
		if is_nan(hh):
			hh = terrain.height_at(hp.x, hp.y)
		terrain.add_flat(hp, HandLayout.HOUSE_PAD, 6.0, hh, Rect2(), false)


## Dirt track from the nearest road to the dungeon's ruined surface gate, so the entrance is always reachable.
## Runs after the dungeon site is picked (the site search avoids roads, so it can land far from them).
func _add_dungeon_track() -> void:
	var site: Dictionary = get_meta("dungeon_site", {}) as Dictionary
	if not site.has("origin"):
		return
	var gate := Vector2(float((site["origin"] as Vector2).x), float(site["gz"]) - 18.0)
	var best: Vector2 = gate
	var best_d := INF
	for i in terrain.road_a.size():
		var q: Vector2 = Geometry2D.get_closest_point_to_segment(gate, terrain.road_a[i], terrain.road_b[i])
		if gate.distance_to(q) < best_d:
			best_d = gate.distance_to(q)
			best = q
	if best_d > 1.0:
		terrain.add_road(best, gate)



# ------------------------------------------------------------------ props

## Everything in the wild (trees, rocks, bushes, grass) comes from the KayKit forest; the only thing built here is the
## roadside: downloaded Kenney street lights along each long road, each with a thin collider.
func _build_props() -> void:
	_props = Node3D.new()
	_props.name = "Props"
	add_child(_props)
	var body := StaticBody3D.new()
	body.name = "PropCollision"
	_props.add_child(body)
	_build_roadside(body)


func _build_roadside(body: StaticBody3D) -> void:
	for i in terrain.road_a.size():
		var a: Vector2 = terrain.road_a[i]
		var b: Vector2 = terrain.road_b[i]
		var d: Vector2 = b - a
		var length: float = d.length()
		if length < 60.0:
			continue
		var dir: Vector2 = d / length
		var side := Vector2(-dir.y, dir.x)
		var yaw: float = atan2(-dir.y, dir.x)
		var s: float = 30.0
		while s < length - 30.0:
			var p: Vector2 = a + dir * s + side * 4.5
			s += 36.0
			var m: Node3D = ModelUtil.load_fit(ROADSIDE_MODEL, ROADSIDE_H)
			if m == null:
				continue
			var y: float = terrain.height_at(p.x, p.y)
			m.position = Vector3(p.x, y, p.y)
			m.rotation.y = yaw
			_props.add_child(m)
			var cs := CollisionShape3D.new()
			var sh := CylinderShape3D.new()
			sh.radius = 0.2
			sh.height = ROADSIDE_H
			cs.shape = sh
			cs.position = Vector3(p.x, y + ROADSIDE_H * 0.5, p.y)
			body.add_child(cs)


# ------------------------------------------------------------------ locations

func _build_locations() -> void:
	_factory = BuildingFactory.new(self, material)
	for l in locations:
		var p2: Vector2 = l["pos2"]
		var pos := Vector3(p2.x, terrain.height_at(p2.x, p2.y), p2.y)
		l["pos"] = pos
		var root := Node3D.new()
		root.name = "%s_%d" % [str(l["type"]), int(l["id"])]
		root.position = pos
		root.rotation.y = float(l["rot"])
		root.set_meta("location_name", l["name"])
		root.set_meta("location_type", l["type"])
		add_child(root)
		l["node"] = root
		var lid: int = int(l["id"])
		root.set_meta("loc_id", lid)
		match str(l["type"]):
			"hospital":
				_factory.build_hospital(root)
			"gas_station":
				_factory.build_gas_station(root)
			"police_station":
				_factory.build_police_station(root)
			"warehouse":
				_factory.build_warehouse(root)
			"church":
				_factory.build_church(root)
				_build_authored_models(root, lid)
			_:
				_factory.build_farm(root)
				_build_authored_models(root, lid)


# ------------------------------------------------------------------ Kenney graveyard / farm dressing

## Puts one Kenney model on the ground at a location-local offset, with a box collider on layer 1.
func _place_model(root: Node3D, file: String, height: float, local: Vector3, yaw: float, solid: bool = true) -> Node3D:
	var m: Node3D = ModelUtil.load_fit(KENNEY_GY + file, height)
	if m == null:
		return null
	var wp: Vector3 = root.transform * local
	m.position = Vector3(local.x, terrain.height_at(wp.x, wp.z) - root.position.y, local.z)
	m.rotation.y = yaw
	root.add_child(m)
	if solid:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		var sz: Vector3 = m.get_meta("size") as Vector3
		bs.size = Vector3(sz.x, sz.y, sz.z) * 0.9
		cs.shape = bs
		cs.position = Vector3(0, sz.y * 0.5, 0)
		body.position = m.position
		body.rotation.y = yaw
		body.add_child(cs)
		root.add_child(body)
	return m


## Graveyard stones, crypt, pines, wall, urns, pumpkins (church) and hay bales / pumpkins (farm): every model is one
## authored LOCAL row [location_id, file, height, local_x, local_z, yaw, solid, post_radius, local_y]; no random draws.
func _build_authored_models(root: Node3D, loc_id: int) -> void:
	for row in HandMapData.for_loc("LOCAL", loc_id):
		var r: Array = row
		var m: Node3D = _place_model(root, str(r[1]), float(r[2]), Vector3(float(r[3]), float(r[8]), float(r[4])), float(r[5]), bool(r[6]))
		if float(r[7]) > 0.0:
			_add_post_collision(root, m, float(r[7]))


## Thin cylinder collider for a slim model (lightpost) whose full bounding box would be too wide.
func _add_post_collision(root: Node3D, m: Node3D, radius: float) -> void:
	if m == null:
		return
	var sz: Vector3 = m.get_meta("size") as Vector3
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = radius
	sh.height = sz.y
	cs.shape = sh
	cs.position = Vector3(0, sz.y * 0.5, 0)
	body.position = m.position
	body.add_child(cs)
	root.add_child(body)
