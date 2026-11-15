extends RefCounted
## KayKit Forest Nature Pack (CC0, free tier) terrain dressing: trees, bushes, rocks and grass tufts.
## Built once from the world seed with its own RNG, after locations and the Kenney dressing exist, so it never
## changes loot layout or any other seeded system. Everything lives under one "KayKitForest" node:
##   - one MultiMeshInstance3D per (model, 128 m cell), with a visibility range, so the cost stays low;
##   - ONE StaticBody3D "Collision" (layer 1) holding a cylinder per tree and a box per big rock.
##     Bushes, grass and small rocks have no collider.
## Layout: dense forest where Terrain.forest_density is high, sparse in open ground, and thinned out in a band
## beside roads and location pads. Nothing is placed on a road, inside a location radius or on the spawn ring.
##
## Usage (world_builder): var f = KayKitForest.new(self); add_child(f.build()); f.counts has the totals.

const DIR := "res://assets/kaykit/forest/KayKit_Forest_Nature_Pack_1.0_FREE/Assets/gltf/"
const TREES := ["Tree_1_A", "Tree_1_B", "Tree_2_A", "Tree_2_B", "Tree_3_A", "Tree_4_A", "Tree_4_B", "Tree_Bare_1_A"]
const BUSHES := ["Bush_1_A", "Bush_2_A", "Bush_3_A", "Bush_3_B", "Bush_4_A", "Bush_4_B"]
const ROCKS := ["Rock_1_A", "Rock_1_E", "Rock_1_K", "Rock_2_A", "Rock_2_C", "Rock_3_A", "Rock_3_C", "Rock_3_E"]
const GRASS := ["Grass_1_A", "Grass_1_B", "Grass_2_A", "Grass_2_B"]

const TREE_COUNT := 520
const BUSH_COUNT := 260
const ROCK_COUNT := 170
const GRASS_COUNT := 1500

const EDGE := 50.0            # keep clear of the border mountains
const CELL := 128.0           # MultiMesh cell size (frustum culling + visibility range work per cell)
const GRID := 8.0             # spacing grid for the overlap check
const SPAWN_CLEAR := 22.0     # nothing within this of the spawn centre
const FOREST_CORE := 0.12     # forest_density at or above this is a dense forest zone
const OPEN_BELOW := -0.15     # forest_density below this is open ground (matches the procedural trees)
const ROAD_HALF := 1.6        # Terrain.ROAD_WIDTH / 2
const TREE_ROAD_HARD := 5.0   # tree trunks never closer than this to a road centreline
const ROAD_SOFT := 12.0       # inside this band (beyond the hard limit) trees are sparse
const ROAD_SPARSE := 0.3
const LOC_HARD := 3.0         # metres beyond a location radius that trees keep clear
const LOC_SOFT := 14.0
const LOC_SPARSE := 0.35
const TREE_SPACING := 1.3     # trunk-to-trunk spacing is 2 x this
const BIG_ROCK_H := 0.9       # rocks at least this tall get a box collider

var world
var terrain
var node: Node3D
var body: StaticBody3D
var rng := RandomNumberGenerator.new()
var counts := {"trees": 0, "bushes": 0, "rocks": 0, "grass": 0, "shapes": 0, "multimeshes": 0, "instances": 0}

## Every queued instance as [kind, x, z]; also exposed as node meta "sites" (the headless renderer cannot read
## MultiMesh transforms back, so tests and tools use this).
var sites: Array = []

var _models: Dictionary = {}    # model name -> {mesh, off, tm, size} (empty when the file is missing)
var _buckets: Dictionary = {}   # "kind|model|cx|cz" -> Array of Transform3D
var _grid: Dictionary = {}      # Vector2i -> Array of Vector3(x, z, radius)


func _init(p_world) -> void:
	world = p_world
	terrain = p_world.terrain


func build() -> Node3D:
	node = Node3D.new()
	node.name = "KayKitForest"
	body = StaticBody3D.new()
	body.name = "Collision"
	node.add_child(body)
	rng.seed = (int(world.world_seed) ^ 0x4B4B) & 0x7FFFFFFF
	_seed_grid()
	_place_trees()
	_place_rocks()
	_place_bushes()
	_place_grass()
	_flush()
	node.set_meta("sites", sites)
	return node


# ------------------------------------------------------------------ models

## Loads one model once: its mesh, the offset that seats it on y = 0 centred on x/z, and its native size.
func _model(mname: String) -> Dictionary:
	if _models.has(mname):
		return _models[mname]
	var out: Dictionary = {}
	var path: String = DIR + mname + "_Color1.gltf"
	var ps: PackedScene = null
	if ResourceLoader.exists(path):
		ps = load(path) as PackedScene
	if ps == null:
		push_warning("[KayKitForest] missing model %s" % path)
		_models[mname] = out
		return out
	var inst: Node = ps.instantiate()
	var found: Array = []
	_collect(inst, Transform3D.IDENTITY, found)
	if not found.is_empty():
		var tm: Transform3D = found[0][0]
		var mesh: Mesh = found[0][1]
		var bb: AABB = tm * mesh.get_aabb()
		var c: Vector3 = bb.get_center()
		out = {"mesh": mesh, "tm": tm, "size": bb.size, "off": Vector3(-c.x, -bb.position.y, -c.z)}
	inst.free()
	_models[mname] = out
	return out


func _collect(n: Node, xf: Transform3D, out: Array) -> void:
	var t: Transform3D = xf
	if n is Node3D:
		t = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append([t, (n as MeshInstance3D).mesh])
	for ch in n.get_children():
		_collect(ch, t, out)


## Queues one instance, scaled uniformly by s, seated on the terrain.
func _queue(kind: String, mname: String, x: float, z: float, yaw: float, s: float) -> float:
	var m: Dictionary = _model(mname)
	var y: float = terrain.height_at(x, z) - 0.04 * s
	var place := Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(s, s, s)), Vector3(x, y, z))
	var xf: Transform3D = place * Transform3D(Basis.IDENTITY, m["off"] as Vector3) * (m["tm"] as Transform3D)
	var cx: int = clampi(floori((x + terrain.HALF) / CELL), 0, int(ceil(2.0 * terrain.HALF / CELL)) - 1)
	var cz: int = clampi(floori((z + terrain.HALF) / CELL), 0, int(ceil(2.0 * terrain.HALF / CELL)) - 1)
	var key := "%s|%s|%d|%d" % [kind, mname, cx, cz]
	if not _buckets.has(key):
		_buckets[key] = []
	(_buckets[key] as Array).append(xf)
	counts["instances"] += 1
	sites.append([kind, x, z])
	return y


func _flush() -> void:
	for key in _buckets:
		var arr: Array = _buckets[key]
		var parts: PackedStringArray = String(key).split("|")
		var kind: String = parts[0]
		var m: Dictionary = _model(parts[1])
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = m["mesh"] as Mesh
		mm.instance_count = arr.size()
		for i in arr.size():
			mm.set_instance_transform(i, arr[i] as Transform3D)
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "%s_%s_%s_%s" % [kind, parts[1], parts[2], parts[3]]
		mmi.multimesh = mm
		match kind:
			"tree", "rock":
				mmi.visibility_range_end = 260.0
			"bush":
				mmi.visibility_range_end = 150.0
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_:
				mmi.visibility_range_end = 110.0
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end_margin = 15.0
		node.add_child(mmi)
		counts["multimeshes"] += 1


# ------------------------------------------------------------------ spacing grid

func _gkey(x: float, z: float) -> Vector2i:
	return Vector2i(floori(x / GRID), floori(z / GRID))


func _gadd(x: float, z: float, r: float) -> void:
	var k := _gkey(x, z)
	if not _grid.has(k):
		_grid[k] = []
	(_grid[k] as Array).append(Vector3(x, z, r))


## True if a disc of radius r at (x, z) overlaps none of the recorded discs.
func _room(x: float, z: float, r: float) -> bool:
	var k := _gkey(x, z)
	var p := Vector2(x, z)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var cell := Vector2i(k.x + dx, k.y + dz)
			if not _grid.has(cell):
				continue
			for q in (_grid[cell] as Array):
				var v: Vector3 = q
				if Vector2(v.x, v.y).distance_to(p) < v.z + r:
					return false
	return true


## Seeds the grid with everything already in the world: procedural trees, rocks and wrecks (prop_points) and
## every Kenney model (cars, camps, signposts, crates).
func _seed_grid() -> void:
	for q in world.prop_points:
		_gadd((q as Vector2).x, (q as Vector2).y, 0.9)
	var d: Node = world.get_node_or_null("KenneyDressing")
	if d == null:
		return
	for ch in d.get_children():
		if ch is Node3D and ch.has_meta("size"):
			var sz: Vector3 = ch.get_meta("size")
			var p3: Vector3 = (ch as Node3D).position
			_gadd(p3.x, p3.z, 0.5 * maxf(sz.x, sz.z) + 0.3)


# ------------------------------------------------------------------ site rules

## 0 = blocked, otherwise the share of candidate sites kept (1 = full density, less beside roads and locations).
func _density_factor(x: float, z: float, road_hard: float, loc_hard: float, road_soft: float, loc_soft: float) -> float:
	var f := 1.0
	var p := Vector2(x, z)
	if p.distance_to(world.spawn_center) < SPAWN_CLEAR:
		return 0.0
	var rd: float = terrain.road_distance(x, z)
	if rd < road_hard:
		return 0.0
	if rd < road_soft:
		f *= ROAD_SPARSE
	for l in world.locations:
		var gap: float = p.distance_to(l["pos2"] as Vector2) - float(l["radius"])
		if gap < loc_hard:
			return 0.0
		if gap < loc_soft:
			f *= LOC_SPARSE
	# any other flattened pad (spawn, and any pad added later) is off limits too
	for i in terrain.flat_pos.size():
		if p.distance_to(terrain.flat_pos[i]) - terrain.flat_radius[i] < loc_hard:
			return 0.0
	return f


func _ground_ok(x: float, z: float, min_ny: float) -> bool:
	var y: float = terrain.height_at(x, z)
	return y > -2.5 and y < 16.0 and terrain.normal_at(x, z).y >= min_ny


func _zone_p(fd: float, core: float, mid: float, open: float) -> float:
	if fd >= FOREST_CORE:
		return core
	if fd >= OPEN_BELOW:
		return mid
	return open


func _cyl(x: float, y: float, z: float, r: float, h: float) -> void:
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = r
	sh.height = h
	cs.shape = sh
	cs.position = Vector3(x, y + h * 0.5, z)
	body.add_child(cs)
	counts["shapes"] += 1


func _box(x: float, y: float, z: float, yaw: float, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	cs.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(x, y + size.y * 0.5, z))
	body.add_child(cs)
	counts["shapes"] += 1


# ------------------------------------------------------------------ placement

func _place_trees() -> void:
	var limit: float = terrain.HALF - EDGE
	var placed := 0
	for _a in 12000:
		if placed >= TREE_COUNT:
			break
		var x: float = rng.randf_range(-limit, limit)
		var z: float = rng.randf_range(-limit, limit)
		var mname: String = TREES[rng.randi_range(0, TREES.size() - 1)]
		var s: float = rng.randf_range(1.1, 1.8)
		var yaw: float = rng.randf() * TAU
		var gate: float = rng.randf()
		var p: float = _zone_p(terrain.forest_density(x, z), 0.95, 0.4, 0.05)
		var f: float = _density_factor(x, z, TREE_ROAD_HARD, LOC_HARD, ROAD_SOFT, LOC_SOFT)
		if f <= 0.0 or gate > p * f:
			continue
		if not _ground_ok(x, z, 0.88) or not _room(x, z, TREE_SPACING):
			continue
		var m: Dictionary = _model(mname)
		if m.is_empty():
			continue
		var sz: Vector3 = m["size"]
		var y: float = _queue("tree", mname, x, z, yaw, s)
		_cyl(x, y, z, clampf(minf(sz.x, sz.z) * s * 0.08, 0.25, 0.55), minf(sz.y * s, 3.5))
		_gadd(x, z, TREE_SPACING)
		placed += 1
	counts["trees"] = placed


func _place_rocks() -> void:
	var limit: float = terrain.HALF - EDGE
	var placed := 0
	for _a in 8000:
		if placed >= ROCK_COUNT:
			break
		var x: float = rng.randf_range(-limit, limit)
		var z: float = rng.randf_range(-limit, limit)
		var mname: String = ROCKS[rng.randi_range(0, ROCKS.size() - 1)]
		var cls: float = rng.randf()
		var h: float = rng.randf_range(0.3, 0.8)
		if cls > 0.95:
			h = rng.randf_range(2.2, 3.2)
		elif cls > 0.7:
			h = rng.randf_range(1.0, 1.8)
		var yaw: float = rng.randf() * TAU
		var gate: float = rng.randf()
		var m: Dictionary = _model(mname)
		if m.is_empty():
			continue
		var sz: Vector3 = m["size"]
		var s: float = h / maxf(sz.y, 0.01)
		var rr: float = 0.5 * Vector2(sz.x, sz.z).length() * s   # footprint circumradius
		var p: float = _zone_p(terrain.forest_density(x, z), 0.8, 0.6, 0.5)
		var f: float = _density_factor(x, z, ROAD_HALF + 1.0 + rr, LOC_HARD, ROAD_SOFT * 0.5, LOC_SOFT * 0.5)
		if f <= 0.0 or gate > p * f:
			continue
		if not _ground_ok(x, z, 0.85) or not _room(x, z, rr):
			continue
		var y: float = _queue("rock", mname, x, z, yaw, s)
		if h >= BIG_ROCK_H:
			_box(x, y, z, yaw, Vector3(sz.x, sz.y, sz.z) * s * 0.8)
		_gadd(x, z, rr)
		placed += 1
	counts["rocks"] = placed


func _place_bushes() -> void:
	var limit: float = terrain.HALF - EDGE
	var placed := 0
	for _a in 8000:
		if placed >= BUSH_COUNT:
			break
		var x: float = rng.randf_range(-limit, limit)
		var z: float = rng.randf_range(-limit, limit)
		var mname: String = BUSHES[rng.randi_range(0, BUSHES.size() - 1)]
		var h: float = rng.randf_range(0.6, 1.3)
		var yaw: float = rng.randf() * TAU
		var gate: float = rng.randf()
		var m: Dictionary = _model(mname)
		if m.is_empty():
			continue
		var s: float = h / maxf((m["size"] as Vector3).y, 0.01)
		var p: float = _zone_p(terrain.forest_density(x, z), 0.9, 0.35, 0.1)
		var f: float = _density_factor(x, z, ROAD_HALF + 1.2, 1.0, 8.0, 8.0)
		if f <= 0.0 or gate > p * f:
			continue
		if not _ground_ok(x, z, 0.85) or not _room(x, z, 0.5):
			continue
		_queue("bush", mname, x, z, yaw, s)
		_gadd(x, z, 0.5)
		placed += 1
	counts["bushes"] = placed


func _place_grass() -> void:
	var limit: float = terrain.HALF - EDGE
	var placed := 0
	for _a in 9000:
		if placed >= GRASS_COUNT:
			break
		var x: float = rng.randf_range(-limit, limit)
		var z: float = rng.randf_range(-limit, limit)
		var mname: String = GRASS[rng.randi_range(0, GRASS.size() - 1)]
		var h: float = rng.randf_range(0.45, 0.9)
		var yaw: float = rng.randf() * TAU
		var gate: float = rng.randf()
		var m: Dictionary = _model(mname)
		if m.is_empty():
			continue
		var s: float = h / maxf((m["size"] as Vector3).y, 0.01)
		var p: float = _zone_p(terrain.forest_density(x, z), 1.0, 0.8, 0.45)
		var f: float = _density_factor(x, z, ROAD_HALF + 1.2, 1.0, 5.0, 5.0)
		if f <= 0.0 or gate > p * f:
			continue
		if not _ground_ok(x, z, 0.88):
			continue
		_queue("grass", mname, x, z, yaw, s)
		placed += 1
	counts["grass"] = placed
