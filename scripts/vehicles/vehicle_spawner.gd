extends RefCounted
## Places drivable cars from the hand-authored VEHICLES rows of data/hand_map/placements.json
## ([kind, x, z, yaw]). No random numbers: the cars are identical on every run and peer. Everything lives under one
## "Vehicles" node so the paths match on every peer. The first cars sit on the spawn roads just outside the spawn pad.

const Vehicle = preload("res://scripts/vehicles/vehicle.gd")
const HandMapData = preload("res://scripts/world/hand_map_data.gd")

var world
var terrain
var node: Node3D
var cars: Array = []             # Vehicle nodes, in placement order


func _init(p_world) -> void:
	world = p_world
	terrain = p_world.terrain


func build() -> Node3D:
	node = Node3D.new()
	node.name = "Vehicles"
	for row in HandMapData.section("VEHICLES"):
		var r: Array = row
		var car = Vehicle.new()
		car.setup(str(r[0]))
		car.name = "Car_%d" % cars.size()
		car.position = Vector3(float(r[1]), terrain.height_at(float(r[1]), float(r[2])) + 0.7, float(r[2]))
		car.rotation.y = float(r[3])
		node.add_child(car)
		cars.append(car)
	return node
