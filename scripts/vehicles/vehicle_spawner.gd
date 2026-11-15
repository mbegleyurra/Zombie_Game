extends RefCounted
## Places drivable cars on the roads, deterministically from the world seed (own RNG, built after KenneyDressing,
## so no other seeded system moves). Everything lives under one "Vehicles" node so the paths match on every peer.
## The first cars sit on the spawn roads just outside the spawn pad so a new player finds one quickly.

const Vehicle = preload("res://scripts/vehicles/vehicle.gd")

const KINDS := ["sedan", "suv", "hatchback-sports", "sedan-sports", "taxi", "van", "truck", "suv-luxury", "police", "delivery"]
const MAX_CARS := 10
const NEAR_SPAWN_CARS := 3
const EDGE := 45.0               # keep clear of the border mountains
const CLEAR_DRESSING := 5.5      # min distance from any Kenney dressing collider centre
const CLEAR_CAR := 9.0           # min distance between two drivable cars
const LANE := 1.6                # lateral wobble across the road

var world
var terrain
var node: Node3D
var rng := RandomNumberGenerator.new()
var cars: Array = []             # Vehicle nodes, in placement order
var _taken: Array = []           # Vector2 centres
var _dressing_pts: Array = []    # Vector2 centres of KenneyDressing collider shapes


func _init(p_world) -> void:
	world = p_world
	terrain = p_world.terrain


func build() -> Node3D:
	node = Node3D.new()
	node.name = "Vehicles"
	rng.seed = (int(world.world_seed) ^ 0x7C4A) & 0x7FFFFFFF
	var body: Node = world.get_node_or_null("KenneyDressing/Collision")
	if body != null:
		for c in body.get_children():
			if c is CollisionShape3D:
				var o: Vector3 = (c as CollisionShape3D).transform.origin
				_dressing_pts.append(Vector2(o.x, o.z))
	_place_all()
	return node


func _place_all() -> void:
	var near_spawn := 0
	for i in terrain.road_a.size():
		if cars.size() >= MAX_CARS:
			break
		var a: Vector2 = terrain.road_a[i]
		var b: Vector2 = terrain.road_b[i]
		var d: Vector2 = b - a
		var length: float = d.length()
		if length < 40.0:
			continue
		var dir: Vector2 = d / length
		var s: float
		if a.distance_to(world.spawn_center) < 1.0 and near_spawn < NEAR_SPAWN_CARS:
			s = rng.randf_range(20.0, 32.0)
			near_spawn += 1
		elif length >= 70.0:
			s = rng.randf_range(0.25, 0.75) * length
		else:
			continue
		_try_place(a + dir * s, dir)


func _try_place(base: Vector2, dir: Vector2) -> void:
	var kind: String = KINDS[rng.randi_range(0, KINDS.size() - 1)]
	var lane: float = rng.randf_range(-LANE, LANE)
	var flip: bool = rng.randf() < 0.5
	var side := Vector2(-dir.y, dir.x)
	var heading: Vector2 = -dir if flip else dir
	# Try the drawn spot, then slide along the road in 5 m steps (+5, -5, +10, -10).
	for t in 5:
		var shift: float = 0.0 if t == 0 else 5.0 * float((t + 1) / 2) * (1.0 if t % 2 == 1 else -1.0)
		var p: Vector2 = base + dir * shift + side * lane
		if not _ok(p):
			continue
		var v := Vector3(p.x, terrain.height_at(p.x, p.y) + 0.7, p.y)
		var car = Vehicle.new()
		car.setup(kind)
		car.name = "Car_%d" % cars.size()
		car.position = v
		car.rotation.y = atan2(-heading.x, -heading.y)   # local -Z (travel direction) along the road heading
		node.add_child(car)
		cars.append(car)
		_taken.append(p)
		return


func _ok(p: Vector2) -> bool:
	if p.length() < 30.0:
		return false
	if absf(p.x) > terrain.HALF - EDGE or absf(p.y) > terrain.HALF - EDGE:
		return false
	if terrain.normal_at(p.x, p.y).y < 0.93:
		return false
	for l in world.locations:
		if (l["pos2"] as Vector2).distance_to(p) < float(l["radius"]) + 4.0:
			return false
	for q in world.prop_points:
		if (q as Vector2).distance_to(p) < 3.5:
			return false
	for q in _dressing_pts:
		if (q as Vector2).distance_to(p) < CLEAR_DRESSING:
			return false
	for q in _taken:
		if (q as Vector2).distance_to(p) < CLEAR_CAR:
			return false
	return true
