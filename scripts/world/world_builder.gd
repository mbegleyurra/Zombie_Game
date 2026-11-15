extends Node3D
## Builds the whole Dead Acres world deterministically from a seed:
## terrain, trees/rocks, locations (farms, gas stations, hospital), loot, day/night, spawn points.
## Same seed => identical world on every peer (all randomness comes from seeded RandomNumberGenerators).
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

const MAX_TREES := 900
const MAX_ROCKS := 300
const MAX_BUSHES := 380
const MAX_GRASS := 2400
const LINK_MAX_DIST := 150.0
const PLACE_LIMIT := 190.0
const MIN_LOCATION_GAP := 68.0

const FARM_NAMES := ["Hartley Farm", "Miller Homestead", "Cedar Ridge Farm", "Olsen Acres", "Brandt Farm", "Willow Creek Farm", "Dunmore Farm", "Pike Orchard"]
const GAS_NAMES := ["Route 9 Gas & Go", "Sunrise Fuel Stop"]
const HOSPITAL_NAME := "St. Agnes Regional Hospital"

var world_seed: int = 1337
var start_hour: float = 9.0
var terrain: Node3D
var day_night: Node3D
var material: StandardMaterial3D
var locations: Array = []
var loot_by_id: Dictionary = {}
var spawn_center := Vector2.ZERO

var _loot_counter: int = 0
var _dyn_counter: int = 1000000
var _props: Node3D
var _factory
var _is_built: bool = false


func build(p_seed: int) -> void:
	if _is_built:
		return
	_is_built = true
	world_seed = p_seed
	var t0: int = Time.get_ticks_msec()
	material = MeshUtil.make_material()
	terrain = TerrainGen.new()
	terrain.name = "Terrain"
	add_child(terrain)
	terrain.setup(world_seed)
	_plan_locations()
	terrain.build_chunks(material)
	var t1: int = Time.get_ticks_msec()
	_build_props()
	var t2: int = Time.get_ticks_msec()
	_build_locations()
	var t3: int = Time.get_ticks_msec()
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

func _plan_locations() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed & 0x7FFFFFFF
	var plan: Array = [["hospital", 26.0], ["gas_station", 22.0], ["gas_station", 22.0],
		["police_station", 22.0], ["warehouse", 24.0], ["church", 22.0]]
	for _i in 6:
		plan.append(["farm", 26.0])
	var farm_i := 0
	var gas_i := 0
	for entry in plan:
		var type: String = entry[0]
		var radius: float = entry[1]
		var placed := false
		for _attempt in 300:
			var p := Vector2(rng.randf_range(-PLACE_LIMIT, PLACE_LIMIT), rng.randf_range(-PLACE_LIMIT, PLACE_LIMIT))
			if p.length() < 55.0:
				continue
			var ok := true
			for l in locations:
				if (l["pos2"] as Vector2).distance_to(p) < MIN_LOCATION_GAP:
					ok = false
					break
			if not ok:
				continue
			var nm: String
			match type:
				"hospital":
					nm = HOSPITAL_NAME
				"gas_station":
					nm = GAS_NAMES[gas_i % GAS_NAMES.size()]
					gas_i += 1
				"police_station":
					nm = "Millbrook Police Station"
				"warehouse":
					nm = "Harlan Freight Warehouse"
				"church":
					nm = "Saint Brigid Chapel"
				_:
					nm = FARM_NAMES[farm_i % FARM_NAMES.size()]
					farm_i += 1
			var loc := {
				"id": locations.size(), "type": type, "name": nm, "pos2": p,
				"pos": Vector3.ZERO, "rot": float(rng.randi_range(0, 3)) * PI * 0.5,
				"radius": radius, "node": null,
			}
			locations.append(loc)
			placed = true
			break
		if not placed:
			push_warning("[World] could not place location type %s" % type)
	# Flatten pads and paint roads (must happen before the terrain mesh is built).
	terrain.add_flat(spawn_center, 14.0, 24.0, terrain.height_at(spawn_center.x, spawn_center.y))
	for l in locations:
		var p2: Vector2 = l["pos2"]
		terrain.add_flat(p2, float(l["radius"]), 18.0, terrain.height_at(p2.x, p2.y))
		terrain.add_road(spawn_center, p2)
	# Dirt tracks between neighbouring locations (each location links to its nearest other one)
	var linked := {}
	for l in locations:
		var best_j: int = -1
		var best_d := LINK_MAX_DIST
		var pa: Vector2 = l["pos2"]
		for m in locations:
			if m == l:
				continue
			var d: float = pa.distance_to(m["pos2"])
			if d < best_d:
				best_d = d
				best_j = int(m["id"])
		if best_j < 0:
			continue
		var key: int = mini(int(l["id"]), best_j) * 1000 + maxi(int(l["id"]), best_j)
		if linked.has(key):
			continue
		linked[key] = true
		terrain.add_road(pa, locations[best_j]["pos2"])


# ------------------------------------------------------------------ props

func _build_props() -> void:
	_props = Node3D.new()
	_props.name = "Props"
	add_child(_props)
	var rng := RandomNumberGenerator.new()
	rng.seed = (world_seed ^ 0x51ED) & 0x7FFFFFFF
	var body := StaticBody3D.new()
	body.name = "PropCollision"
	_props.add_child(body)
	var limit: float = TerrainGen.HALF - 20.0

	var tree_xf: Array = []
	var canopy_cols: Array = []
	var trunk_shape := CylinderShape3D.new()
	trunk_shape.radius = 0.4
	trunk_shape.height = 3.0
	var palette: Array = [Color(0.3, 0.55, 0.22), Color(0.38, 0.6, 0.25), Color(0.25, 0.46, 0.3), Color(0.7, 0.55, 0.2), Color(0.75, 0.4, 0.18)]
	for _a in 4000:
		if tree_xf.size() >= MAX_TREES:
			break
		var x: float = rng.randf_range(-limit, limit)
		var z: float = rng.randf_range(-limit, limit)
		var gate: float = rng.randf()
		var s: float = rng.randf_range(0.8, 1.6)
		var rot: float = rng.randf() * TAU
		var pal_i: int = rng.randi_range(0, palette.size() - 1)
		if not terrain.is_clear(x, z, 5.0):
			continue
		if terrain.forest_density(x, z) < -0.15 and gate > 0.06:
			continue
		if terrain.normal_at(x, z).y < 0.8:
			continue
		var y: float = terrain.height_at(x, z)
		tree_xf.append(Transform3D(Basis(Vector3.UP, rot).scaled(Vector3(s, s, s)), Vector3(x, y, z)))
		canopy_cols.append(palette[pal_i] if gate < 0.8 else palette[(pal_i + 2) % palette.size()])
		var cs := CollisionShape3D.new()
		cs.shape = trunk_shape
		cs.position = Vector3(x, y + 1.5 * s, z)
		body.add_child(cs)
	var trunk_mu = MeshUtil.new()
	trunk_mu.add_frustum(Vector3.ZERO, 0.38, 0.2, 2.6, 8, Color(0.4, 0.28, 0.18))
	trunk_mu.add_beam(Vector3(0, 1.4, 0), Vector3(0.7, 2.0, 0.2), 0.1, Color(0.36, 0.25, 0.16))
	trunk_mu.add_beam(Vector3(0, 1.1, 0), Vector3(-0.6, 1.7, -0.3), 0.1, Color(0.36, 0.25, 0.16))
	var canopy_mu = MeshUtil.new()
	canopy_mu.add_frustum(Vector3(0, 1.2, 0), 1.9, 0.0, 2.2, 9, Color.WHITE)
	canopy_mu.add_frustum(Vector3(0, 2.4, 0), 1.5, 0.0, 2.2, 9, Color.WHITE, 0.35)
	canopy_mu.add_frustum(Vector3(0, 3.6, 0), 1.0, 0.0, 2.0, 9, Color.WHITE, 0.7)
	var white: Array = []
	for _t in tree_xf.size():
		white.append(Color.WHITE)
	_add_multimesh("Trunks", trunk_mu.to_mesh(), tree_xf, white)
	_add_multimesh("Canopies", canopy_mu.to_mesh(), tree_xf, canopy_cols)

	_build_rocks(rng, body, limit)
	_build_bushes(body, limit)
	_build_grass(limit)
	_build_roadside(body)


## Four rock silhouettes (boulder, tall spire, flat slab, jagged chunk), each its own MultiMesh.
## Some rocks get one or two smaller companions so they read as outcrops. Rocks collide (sphere per rock).
func _build_rocks(rng: RandomNumberGenerator, body: StaticBody3D, limit: float) -> void:
	var rock_rng := RandomNumberGenerator.new()
	rock_rng.seed = (world_seed ^ 0x0C0C) & 0x7FFFFFFF
	# per shape: radius vector, segs, rings, jitter, collision radius factor, collision centre height factor
	var defs: Array = [
		[Vector3(1.0, 0.8, 1.0), 6, 3, 0.25, 0.85, 0.3],
		[Vector3(0.7, 1.35, 0.8), 5, 3, 0.3, 0.7, 0.6],
		[Vector3(1.35, 0.5, 1.1), 7, 2, 0.2, 0.95, 0.15],
		[Vector3(0.9, 1.0, 0.9), 5, 4, 0.4, 0.8, 0.35],
	]
	var xfs: Array = [[], [], [], []]
	var cols: Array = [[], [], [], []]
	var count := 0
	for _b in 3000:
		if count >= MAX_ROCKS:
			break
		var rx: float = rng.randf_range(-limit, limit)
		var rz: float = rng.randf_range(-limit, limit)
		var shape_i: int = rng.randi_range(0, 3)
		var rs: float = rng.randf_range(0.6, 2.2)
		var cluster: int = 0
		if rng.randf() < 0.3:
			cluster = rng.randi_range(1, 2)
		var base_rot: float = rng.randf() * TAU
		if not terrain.is_clear(rx, rz, 4.0):
			continue
		for k in cluster + 1:
			var px: float = rx
			var pz: float = rz
			var ps: float = rs
			var si: int = shape_i
			if k > 0:
				var ang: float = rng.randf() * TAU
				var dist: float = rs * rng.randf_range(1.1, 1.8)
				px += cos(ang) * dist
				pz += sin(ang) * dist
				ps = rs * rng.randf_range(0.35, 0.65)
				si = rng.randi_range(0, 3)
				if not terrain.is_clear(px, pz, 4.0):
					continue
			var shade: float = rng.randf_range(0.7, 1.1)
			var warm: float = rng.randf_range(-0.05, 0.05)
			var tilt: float = rng.randf_range(-0.15, 0.15)
			var py: float = terrain.height_at(px, pz)
			var d: Array = defs[si]
			var basis := Basis(Vector3.UP, base_rot + float(k) * 1.3) * Basis(Vector3.RIGHT, tilt) * Basis.from_scale(Vector3(ps, ps * rng.randf_range(0.8, 1.15), ps))
			(xfs[si] as Array).append(Transform3D(basis, Vector3(px, py, pz)))
			(cols[si] as Array).append(Color(0.55 * shade + warm, 0.5 * shade, 0.46 * shade - warm))
			var rcs := CollisionShape3D.new()
			var sph := SphereShape3D.new()
			sph.radius = ps * float(d[4])
			rcs.shape = sph
			rcs.position = Vector3(px, py + float(d[5]) * ps, pz)
			body.add_child(rcs)
			count += 1
	for si in 4:
		var d: Array = defs[si]
		var mu = MeshUtil.new()
		mu.add_blob(Vector3(0, 0.3, 0), d[0] as Vector3, int(d[1]), int(d[2]), Color.WHITE, rock_rng, float(d[3]))
		_add_multimesh("Rocks%d" % si, mu.to_mesh(), xfs[si], cols[si])


## Low bushes: two overlapping jittered blobs, tinted per instance. Visual only (no collision).
func _build_bushes(_body: StaticBody3D, limit: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = (world_seed ^ 0x0B05) & 0x7FFFFFFF
	var mesh_rng := RandomNumberGenerator.new()
	mesh_rng.seed = (world_seed ^ 0x0B06) & 0x7FFFFFFF
	var mu = MeshUtil.new()
	mu.add_blob(Vector3(0, 0.3, 0), Vector3(0.7, 0.5, 0.7), 5, 3, Color.WHITE, mesh_rng, 0.2)
	mu.add_blob(Vector3(0.45, 0.2, 0.2), Vector3(0.5, 0.4, 0.5), 5, 3, Color.WHITE.darkened(0.08), mesh_rng, 0.2)
	var pal: Array = [Color(0.24, 0.42, 0.16), Color(0.3, 0.5, 0.2), Color(0.34, 0.46, 0.14), Color(0.45, 0.4, 0.15), Color(0.2, 0.36, 0.2)]
	var xf: Array = []
	var cols: Array = []
	for _a in 4000:
		if xf.size() >= MAX_BUSHES:
			break
		var x: float = rng.randf_range(-limit, limit)
		var z: float = rng.randf_range(-limit, limit)
		var gate: float = rng.randf()
		var s: float = rng.randf_range(0.8, 1.7)
		var rot: float = rng.randf() * TAU
		var pi_: int = rng.randi_range(0, pal.size() - 1)
		if not terrain.is_clear(x, z, 2.5):
			continue
		if terrain.forest_density(x, z) < -0.3 and gate > 0.15:
			continue
		if terrain.normal_at(x, z).y < 0.85:
			continue
		xf.append(Transform3D(Basis(Vector3.UP, rot).scaled(Vector3(s, s * rng.randf_range(0.8, 1.2), s)), Vector3(x, terrain.height_at(x, z), z)))
		cols.append(pal[pi_])
	_add_multimesh("Bushes", mu.to_mesh(), xf, cols)


## Grass tufts: four crossed blades (4 triangles) per tuft. Visual only.
func _build_grass(limit: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = (world_seed ^ 0x6A55) & 0x7FFFFFFF
	var mu = MeshUtil.new()
	for k in 4:
		var a: float = float(k) * PI * 0.5 + 0.4
		var dir := Vector3(cos(a), 0.0, sin(a))
		var side := Vector3(-dir.z, 0.0, dir.x)
		var base: Vector3 = dir * 0.06
		var tip: Vector3 = base + dir * (0.1 + 0.04 * float(k % 2)) + Vector3(0, 0.55 + 0.12 * float(k % 3), 0)
		mu.add_tri(base - side * 0.07, base + side * 0.07, tip, Color.WHITE, side.cross(Vector3.UP) + Vector3(0, 0.1, 0))
	var pal: Array = [Color(0.34, 0.52, 0.2), Color(0.45, 0.58, 0.22), Color(0.58, 0.58, 0.26), Color(0.28, 0.46, 0.18), Color(0.62, 0.52, 0.28)]
	var xf: Array = []
	var cols: Array = []
	for _a in 8000:
		if xf.size() >= MAX_GRASS:
			break
		var x: float = rng.randf_range(-limit, limit)
		var z: float = rng.randf_range(-limit, limit)
		var s: float = rng.randf_range(0.7, 1.6)
		var rot: float = rng.randf() * TAU
		var pi_: int = rng.randi_range(0, pal.size() - 1)
		if not terrain.is_clear(x, z, 1.0):
			continue
		var y: float = terrain.height_at(x, z)
		if y > 16.0 or y < -2.5 or terrain.normal_at(x, z).y < 0.88:
			continue
		xf.append(Transform3D(Basis(Vector3.UP, rot).scaled(Vector3(s, s, s)), Vector3(x, y, z)))
		cols.append(pal[pi_])
	_add_multimesh("Grass", mu.to_mesh(), xf, cols)


## Wooden power poles and sagging wires along each road, plus a few wrecked cars on the verges.
## Deterministic: its own rng seeded from the world seed.
func _build_roadside(body: StaticBody3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = (world_seed ^ 0x7013) & 0x7FFFFFFF
	var mu = MeshUtil.new()
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
		var prev: Array = []
		var s: float = 30.0
		while s < length - 30.0:
			var p: Vector2 = a + dir * s + side * 4.5
			var y: float = terrain.height_at(p.x, p.y)
			var xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, y, p.y))
			var pts: Array = PropFactory.add_pole(mu, body, xf)
			if not prev.is_empty():
				for k in 3:
					PropFactory.add_wire(mu, prev[k], pts[k], 0.8)
			prev = pts
			s += 36.0
		# Wrecked car on the verge of long roads
		if length > 90.0:
			var cs: float = rng.randf_range(0.3, 0.7) * length
			var cp: Vector2 = a + dir * cs + side * rng.randf_range(-3.5, 3.5)
			if terrain.normal_at(cp.x, cp.y).y > 0.9:
				var kinds: Array = ["sedan", "pickup", "van"]
				var cxf := Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU)), Vector3(cp.x, terrain.height_at(cp.x, cp.y), cp.y))
				PropFactory.add_car(mu, body, cxf, str(kinds[rng.randi_range(0, 2)]), PropFactory.random_car_color(rng), rng.randi_range(1, 2), rng)
	if mu.is_empty():
		return
	var mi := MeshInstance3D.new()
	mi.name = "Roadside"
	mi.mesh = mu.to_mesh()
	mi.material_override = material
	_props.add_child(mi)


func _add_multimesh(node_name: String, mesh: Mesh, xforms: Array, colors: Array) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.material_override = material
	_props.add_child(mmi)


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
		var rng := RandomNumberGenerator.new()
		rng.seed = (world_seed * 31 + int(l["id"]) * 7919 + 11) & 0x7FFFFFFF
		match str(l["type"]):
			"hospital":
				_factory.build_hospital(root, rng)
			"gas_station":
				_factory.build_gas_station(root, rng)
			"police_station":
				_factory.build_police_station(root, rng)
			"warehouse":
				_factory.build_warehouse(root, rng)
			"church":
				_factory.build_church(root, rng)
			_:
				_factory.build_farm(root, rng)
