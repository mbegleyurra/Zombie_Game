extends RefCounted
## Kenney Survival Kit + Car Kit world dressing (CC0): abandoned vehicles, camps, signposts, barrels/crates,
## open-terrain trees and rocks. Built once from the world seed with its own RNG, after the locations exist,
## so it never changes loot layout or any other seeded system. Everything lives under one "KenneyDressing"
## node with ONE StaticBody3D (many box/cylinder shapes, layer 1). No per-frame cost.
##
## Usage (world_builder): var d = KenneyDressing.new(self); add_child(d.build()); d.counts has the totals.

const ModelUtil = preload("res://scripts/world/model_util.gd")
const SURV := "res://assets/kenney/survival/"
const CARS := "res://assets/kenney/cars/"
const FLOOR := 0.06   # same floor-slab lift as BuildingFactory.F

const CAR_H := {
	"sedan": 1.45, "sedan-sports": 1.35, "hatchback-sports": 1.35, "suv": 1.75, "suv-luxury": 1.75,
	"van": 2.1, "truck": 2.6, "taxi": 1.45, "police": 1.5, "ambulance": 2.3, "delivery": 2.5,
	"garbage-truck": 3.0, "firetruck": 3.1,
}
const ROAD_KINDS := ["sedan", "suv", "van", "taxi", "delivery", "truck", "sedan-sports", "hatchback-sports", "suv-luxury", "garbage-truck", "firetruck"]
const MAX_ROAD_CARS := 14
const CAMP_COUNT := 5
const TREE_COUNT := 36
const ROCK_COUNT := 40
const EDGE := 45.0   # keep clear of the border mountains
const ROAD_CLEAR := 1.0   # min distance from any road centreline to any point of a car footprint (player capsule r 0.35 + margin)
const SPAWN_CLEAR := 22.0   # trees and rocks keep this far from the player spawn centre
const GAS_CRATE_ROAD := 3.0   # gas-station crate spots closer than this to a road are skipped

var world
var terrain
var node: Node3D
var body: StaticBody3D
var rng := RandomNumberGenerator.new()
var counts := {"cars": 0, "cones": 0, "camps": 0, "camp_models": 0, "signposts": 0, "crates_barrels": 0, "trees": 0, "rocks": 0, "models": 0, "shapes": 0}
var _taken: Array = []   # Vector3(x, z, radius)


func _init(p_world) -> void:
	world = p_world
	terrain = p_world.terrain


func build() -> Node3D:
	node = Node3D.new()
	node.name = "KenneyDressing"
	body = StaticBody3D.new()
	body.name = "Collision"
	node.add_child(body)
	rng.seed = (int(world.world_seed) ^ 0x4B45) & 0x7FFFFFFF
	_location_props()
	_road_cars()
	_signposts()
	_camps()
	_terrain_breakers()
	return node


# ------------------------------------------------------------------ primitives

func _load(dir: String, file: String, height: float) -> Node3D:
	var m: Node3D = ModelUtil.load_fit(dir + file + ".glb", height)
	if m == null:
		push_warning("[KenneyDressing] missing model %s%s" % [dir, file])
	return m


## mode: 0 none, 1 box (0.9 of the model's size), 2 slim cylinder (posts, trees)
func _finish_put(m: Node3D, x: float, z: float, yaw: float, mode: int, lift: float = 0.0) -> Node3D:
	var y: float = terrain.height_at(x, z) + lift
	m.position = Vector3(x, y, z)
	m.rotation.y = yaw
	node.add_child(m)
	counts["models"] += 1
	var sz: Vector3 = m.get_meta("size") as Vector3
	if mode != 0:
		var cs := CollisionShape3D.new()
		if mode == 1:
			var bs := BoxShape3D.new()
			bs.size = sz * 0.9
			cs.shape = bs
		else:
			var cyl := CylinderShape3D.new()
			cyl.radius = clampf(minf(sz.x, sz.z) * 0.3, 0.12, 0.45)
			cyl.height = sz.y
			cs.shape = cyl
		cs.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(x, y + sz.y * 0.5, z))
		body.add_child(cs)
		counts["shapes"] += 1
	return m


func _put(dir: String, file: String, h: float, x: float, z: float, yaw: float, mode: int, lift: float = 0.0) -> Node3D:
	var m := _load(dir, file, h)
	if m == null:
		return null
	return _finish_put(m, x, z, yaw, mode, lift)


## Yaw that lays the model's long axis along `heading` (world XZ).
func _yaw_for(m: Node3D, heading: Vector2) -> float:
	var sz: Vector3 = m.get_meta("size") as Vector3
	if sz.x >= sz.z:
		return atan2(-heading.y, heading.x)
	return atan2(heading.x, heading.y)


func _car(kind: String, x: float, z: float, heading: Vector2, jitter: float, lift: float = 0.0) -> Node3D:
	var m := _load(CARS, kind, float(CAR_H.get(kind, 1.6)))
	if m == null:
		return null
	var yaw: float = _yaw_for(m, heading.normalized())
	if jitter > 0.0:
		yaw += rng.randf_range(-jitter, jitter)
	# Fixed lot/forecourt spots can sit on a road that starts at the location centre: skip those.
	if not _footprint_off_roads(m.get_meta("size") as Vector3, Vector2(x, z), yaw):
		m.free()
		return null
	counts["cars"] += 1
	return _finish_put(m, x, z, yaw, 1, lift)


func _cone(x: float, z: float, lift: float = 0.0) -> void:
	if _put(CARS, "cone", 0.55, x, z, rng.randf() * TAU, 0, lift) != null:
		counts["cones"] += 1


func _crate(file: String, h: float, x: float, z: float, lift: float, solid: bool = true) -> void:
	if _put(SURV, file, h, x, z, rng.randf() * TAU, 1 if solid else 0, lift) != null:
		counts["crates_barrels"] += 1


func _loc_pt(loc: Dictionary, lx: float, lz: float) -> Vector2:
	var n: Node3D = loc["node"]
	var wp: Vector3 = n.transform * Vector3(lx, 0.0, lz)
	return Vector2(wp.x, wp.z)


func _loc_dir(loc: Dictionary, lx: float, lz: float) -> Vector2:
	var n: Node3D = loc["node"]
	var d: Vector3 = n.transform.basis * Vector3(lx, 0.0, lz)
	return Vector2(d.x, d.z)


func _near_location(x: float, z: float, margin: float) -> bool:
	var p := Vector2(x, z)
	for l in world.locations:
		if (l["pos2"] as Vector2).distance_to(p) < float(l["radius"]) + margin:
			return true
	return false


func _room(x: float, z: float, r: float) -> bool:
	var p := Vector2(x, z)
	for q in world.prop_points:
		if (q as Vector2).distance_to(p) < r:
			return false
	for t in _taken:
		if Vector2((t as Vector3).x, (t as Vector3).y).distance_to(p) < (t as Vector3).z + r:
			return false
	return true


## True if the whole yawed footprint (corners, edge midpoints, centre line) stays ROAD_CLEAR from every road centreline.
func _footprint_off_roads(sz: Vector3, p: Vector2, yaw: float) -> bool:
	var basis := Basis(Vector3.UP, yaw)
	for fx in [-1.0, -0.5, 0.0, 0.5, 1.0]:
		for fz in [-1.0, 0.0, 1.0]:
			var o: Vector3 = basis * Vector3(float(fx) * sz.x * 0.5, 0.0, float(fz) * sz.z * 0.5)
			if terrain.road_distance(p.x + o.x, p.y + o.z) < ROAD_CLEAR:
				return false
	return true


# ------------------------------------------------------------------ inside locations

## Fixed, hand-picked spots that keep every door, aisle and loot spot clear (checked against the factory layouts).
func _location_props() -> void:
	for loc in world.get_locations("police_station"):
		# Third marked bay in the lot (existing cars sit in bays -7.5, -4.5, 4.5; the door lane is x in [-1, 1]).
		var p := _loc_pt(loc, 7.5, 11.0)
		_car("police", p.x, p.y, _loc_dir(loc, 0.0, 1.0), 0.0, FLOOR)
	for loc in world.get_locations("hospital"):
		# Ambulance on the east side of the forecourt (the procedural wreck is on the west), cones marking a lane.
		var a := _loc_pt(loc, 9.0, 14.5)
		_car("ambulance", a.x, a.y, _loc_dir(loc, 1.0, 0.0), 0.0)
		for c in [Vector2(4.4, 12.2), Vector2(4.9, 14.0), Vector2(5.3, 15.8)]:
			var cp := _loc_pt(loc, (c as Vector2).x, (c as Vector2).y)
			_cone(cp.x, cp.y)
	for loc in world.get_locations("gas_station"):
		var s := _loc_pt(loc, 0.0, 15.0)   # forecourt apron, clear of pump islands (z <= 13.25) and canopy posts
		_car("suv", s.x, s.y, _loc_dir(loc, 1.0, 0.0), 0.12, FLOOR)
		# Behind the shop, west of the back door (x 3.5..4.9)
		for it in [["barrel-open", 0.9, -3.6, -5.7], ["barrel", 0.9, -2.7, -5.9], ["box-large", 0.7, -0.8, -5.7], ["box", 0.5, 0.2, -5.6]]:
			var bp := _loc_pt(loc, float(it[2]), float(it[3]))
			if terrain.road_distance(bp.x, bp.y) < GAS_CRATE_ROAD:
				continue
			_crate(str(it[0]), float(it[1]), bp.x, bp.y, 0.0)
	for loc in world.get_locations("warehouse"):
		var d := _loc_pt(loc, -6.5, 15.0)   # loading yard, between the west door lane (x -8) and the dock door (x 4)
		_car("delivery", d.x, d.y, _loc_dir(loc, 1.0, 0.0), 0.1, FLOOR)
		# Interior: east back corner and west wall, away from the doors, racks and loot containers
		for it in [["barrel", 0.9, 11.3, -6.8], ["barrel-open", 0.9, 10.5, -7.3], ["box-large", 0.8, -10.7, 3.4], ["box", 0.6, -10.7, 2.3]]:
			var wp := _loc_pt(loc, float(it[2]), float(it[3]))
			_crate(str(it[0]), float(it[1]), wp.x, wp.y, FLOOR)


# ------------------------------------------------------------------ roads

func _road_cars() -> void:
	var placed := 0
	for i in terrain.road_a.size():
		if placed >= MAX_ROAD_CARS:
			break
		var a: Vector2 = terrain.road_a[i]
		var b: Vector2 = terrain.road_b[i]
		var d: Vector2 = b - a
		var length: float = d.length()
		if length < 70.0:
			continue
		var dir: Vector2 = d / length
		var side := Vector2(-dir.y, dir.x)
		var n: int = 1 if length < 150.0 else 2
		for _k in n:
			if placed >= MAX_ROAD_CARS:
				break
			var cs: float = rng.randf_range(0.2, 0.8) * length
			var off: float = -rng.randf_range(2.2, 3.6)   # pylons stand on the +side at 4.5
			var kind: String = ROAD_KINDS[rng.randi_range(0, ROAD_KINDS.size() - 1)]
			if placed == 0:
				kind = "ambulance"
			elif placed == 1:
				kind = "police"
			var jit: float = rng.randf_range(-0.2, 0.2)   # yaw jitter, capped: a 5 m car swings its corner ~0.5 m at 0.2 rad
			var m := _load(CARS, kind, float(CAR_H.get(kind, 1.6)))
			if m == null:
				continue
			var yaw: float = _yaw_for(m, dir.rotated(jit))
			# Try the drawn spot, then nudge away from the own road (negative side) in 0.5 m steps.
			var p := Vector2.ZERO
			var fits := false
			for t in 4:
				p = a + dir * cs + side * (off - 0.5 * float(t))
				if p.length() < 30.0 or _near_location(p.x, p.y, 5.0):
					continue
				if absf(p.x) > terrain.HALF - EDGE or absf(p.y) > terrain.HALF - EDGE:
					continue
				if terrain.normal_at(p.x, p.y).y < 0.92 or not _room(p.x, p.y, 5.0):
					continue
				if _footprint_off_roads(m.get_meta("size") as Vector3, p, yaw):
					fits = true
					break
			if not fits:
				m.free()
				continue
			counts["cars"] += 1
			_finish_put(m, p.x, p.y, yaw, 1)
			_taken.append(Vector3(p.x, p.y, 3.0))
			placed += 1
			if kind == "ambulance" or kind == "police":
				for k in 3:
					var cp: Vector2 = p + dir * (4.2 + float(k) * 1.6) + side * (0.6 - float(k) * 0.7)
					_cone(cp.x, cp.y)


## One signpost per location on the road in from the spawn, beside the track, outside the pad.
func _signposts() -> void:
	for l in world.locations:
		var lp: Vector2 = l["pos2"]
		var to_spawn: Vector2 = world.spawn_center - lp
		if to_spawn.length() < 60.0:
			continue
		var dir: Vector2 = to_spawn.normalized()
		var side := Vector2(-dir.y, dir.x)
		var p: Vector2 = lp + dir * (float(l["radius"]) + 7.0) - side * 4.0
		if terrain.normal_at(p.x, p.y).y < 0.88:
			continue
		if terrain.road_distance(p.x, p.y) < 3.5:
			continue   # city streets can pass the usual spot (hospital): never stand a sign on a road
		var yaw: float = atan2(dir.x, dir.y)   # board faces the traveller coming from the spawn
		if _put(SURV, "signpost", 2.2, p.x, p.y, yaw, 2) != null:
			counts["signposts"] += 1
			_taken.append(Vector3(p.x, p.y, 1.0))


# ------------------------------------------------------------------ camps

func _camps() -> void:
	var camps: Array = []
	var limit: float = terrain.HALF - EDGE - 20.0
	for _a in 800:
		if camps.size() >= CAMP_COUNT:
			break
		var x: float = rng.randf_range(-limit, limit)
		var z: float = rng.randf_range(-limit, limit)
		var yaw: float = rng.randf() * TAU
		var c := Vector2(x, z)
		if c.length() < 45.0 or not terrain.is_clear(x, z, 10.0) or terrain.normal_at(x, z).y < 0.96:
			continue
		var ok := true
		for o in camps:
			if (o as Vector2).distance_to(c) < 50.0:
				ok = false
				break
		if not ok or not _room(x, z, 7.0):
			continue
		var h0: float = terrain.height_at(x, z)
		if h0 < -1.0 or h0 > 14.0:
			continue
		camps.append(c)
		var basis := Basis(Vector3.UP, yaw)
		# [dir, file, height, local x, local z, extra yaw, mode]
		var parts: Array = [
			[SURV, "tent", 1.7, 0.0, 0.0, 0.0, 1],
			[SURV, "campfire-pit", 0.35, 3.2, 0.4, 0.0, 0],
			[SURV, "bedroll", 0.25, -2.6, 2.0, 0.6, 0],
			[SURV, "barrel", 0.9, 2.4, -2.5, 0.0, 1],
			[SURV, "barrel-open", 0.9, 3.2, -2.9, 0.0, 1],
			[SURV, "box-large", 0.7, -2.4, -2.6, 0.4, 1],
			[SURV, "bucket", 0.35, 1.3, 2.7, 0.0, 0],
			[SURV, "tree-log-small", 0.5, -3.4, -0.6, 1.2, 1],
		]
		for pt in parts:
			var o: Vector3 = basis * Vector3(float(pt[3]), 0.0, float(pt[4]))
			if _put(str(pt[0]), str(pt[1]), float(pt[2]), x + o.x, z + o.z, yaw + float(pt[5]) + rng.randf_range(-0.1, 0.1), int(pt[6])) != null:
				counts["camp_models"] += 1
		_taken.append(Vector3(x, z, 5.5))
		counts["camps"] += 1


# ------------------------------------------------------------------ trees and rocks

func _terrain_breakers() -> void:
	var limit: float = terrain.HALF - EDGE
	var tree_files := ["tree", "tree-tall", "tree-autumn", "tree-autumn-tall"]
	var rock_files := ["rock-a", "rock-b", "rock-c"]   # rock-flat-grass is a wide grass patch: its box collider would be ~10 m
	var trees := 0
	for _a in 4000:
		if trees >= TREE_COUNT:
			break
		var x: float = rng.randf_range(-limit, limit)
		var z: float = rng.randf_range(-limit, limit)
		var f: String = tree_files[rng.randi_range(0, tree_files.size() - 1)]
		var h: float = rng.randf_range(4.5, 7.0)
		var yaw: float = rng.randf() * TAU
		if terrain.forest_density(x, z) >= -0.15:
			continue   # only open ground: the procedural trees already fill the forests
		if Vector2(x, z).distance_to(world.spawn_center) < SPAWN_CLEAR:
			continue   # draws above stay unconditional so the RNG stream (and every later pick) is unchanged
		if not terrain.is_clear(x, z, 6.0) or terrain.normal_at(x, z).y < 0.9 or not _room(x, z, 3.5):
			continue
		var y: float = terrain.height_at(x, z)
		if y < -1.5 or y > 16.0:
			continue
		if _put(SURV, f, h, x, z, yaw, 2) != null:
			_taken.append(Vector3(x, z, 1.2))
			trees += 1
	counts["trees"] = trees
	var rocks := 0
	for _b in 4000:
		if rocks >= ROCK_COUNT:
			break
		var x2: float = rng.randf_range(-limit, limit)
		var z2: float = rng.randf_range(-limit, limit)
		var f2: String = rock_files[rng.randi_range(0, rock_files.size() - 1)]
		var h2: float = rng.randf_range(0.7, 1.7)
		var yaw2: float = rng.randf() * TAU
		if not terrain.is_clear(x2, z2, 5.0) or terrain.normal_at(x2, z2).y < 0.85 or not _room(x2, z2, 3.0):
			continue
		if Vector2(x2, z2).distance_to(world.spawn_center) < SPAWN_CLEAR:
			continue
		var y2: float = terrain.height_at(x2, z2)
		if y2 < -1.5 or y2 > 16.0:
			continue
		if _put(SURV, f2, h2, x2, z2, yaw2, 1) != null:
			_taken.append(Vector3(x2, z2, 1.0))
			rocks += 1
	counts["rocks"] = rocks
