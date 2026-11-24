extends RefCounted
## Builds the hand-authored extras from hand_layout.gd: countryside cottages, the city's tower blocks, street lamps
## and abandoned street cars. One flat-shaded vertex-coloured mesh plus box collision, all under a "HandWorld" node
## at the world origin (positions are world coordinates). No randomness: the layout is data, the only RNG is a fixed
## seed used by PropFactory for car paint. Footprints are published as world meta "hand_footprints" for the map:
## [x, z, width, depth, yaw, kind ("house" | "tower"), height].

const HandLayout = preload("res://tools/worldgen/hand_layout.gd")
const PropFactory = preload("res://tools/worldgen/prop_factory.gd")
const CityKit = preload("res://tools/worldgen/city_kit.gd")
const RoadKit = preload("res://tools/worldgen/road_kit.gd")
const ModelUtil = preload("res://scripts/world/model_util.gd")

## Downloaded Kenney models that stand in for the old primitive cottages and street cars.
const HOUSE_MODELS := ["a", "b", "c", "d", "e", "f", "g", "h"]
const SUB := "res://assets/kenney/city-kit-suburban/building-type-%s.glb"
const CARS := "res://assets/kenney/cars/%s.glb"
const CAR_MODEL := {"sedan": "sedan", "pickup": "suv", "van": "van", "police": "police", "truck": "delivery"}
const CAR_H := {"sedan": 1.45, "suv": 1.75, "van": 2.1, "police": 1.5, "delivery": 2.5}

const FLOOR_H := 3.2

var world
var node: Node3D
var footprints: Array = []
var counts := {"houses": 0, "towers": 0, "lamps": 0, "cars": 0, "road_tiles": 0}
var _body: StaticBody3D


func _init(p_world) -> void:
	world = p_world


func build() -> Node3D:
	node = Node3D.new()
	node.name = "HandWorld"
	_body = StaticBody3D.new()
	_body.name = "Collision"
	node.add_child(_body)
	var i := 0
	for h in HandLayout.HOUSES:
		_house(i, float(h[0]), float(h[1]), float(h[2]))
		i += 1
	# City district: Kenney commercial / industrial / suburban buildings, storefront props, road kit tiles and street props.
	var kit := CityKit.new(world, node, _body, footprints, counts)
	kit.build()
	var roads := RoadKit.new(world, kit)
	roads.build()
	counts["road_tiles"] = int(roads.counts["tiles"])
	var info := {"buildings": kit.buildings, "props": kit.props, "models": kit.models, "tiles": roads.tile_kinds,
		"missing": kit.missing, "junctions": roads.counts["junctions"]}
	node.set_meta("citykit", info)
	world.set_meta("citykit", info)
	_street_cars()
	node.set_meta("footprints", footprints)
	world.set_meta("hand_footprints", footprints)
	return node


## Cottage: walls, gable roof (ridge along local X), door and windows on the local +Z front.
func _house(i: int, x: float, z: float, yaw: float) -> void:
	var w: float = 8.0 + float(i % 3)
	var d: float = 6.0 + float(i % 2)
	var wall_h := 2.8
	var rise := 1.9
	var y: float = world.get_height(x, z)
	var xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(x, y, z))
	var centre := Vector3(0.0, wall_h * 0.5 - 0.3, 0.0)   # sunk 0.6 m so slopes never show a gap
	PropFactory.add_collision(_body, xf, centre, Vector3(w, wall_h + 0.6, d))
	var hx: float = w * 0.5 + 0.3
	var hz: float = d * 0.5 + 0.3
	# Visual: a downloaded Kenney suburban house stretched over the same footprint and height.
	var house: Node3D = ModelUtil.fit_box(SUB % HOUSE_MODELS[i % HOUSE_MODELS.size()], Vector3(w + 0.6, wall_h + rise, d + 0.6))
	if house != null:
		house.transform = xf * Transform3D(Basis(), Vector3(0.0, (wall_h + rise) * 0.5, 0.0))
		node.add_child(house)
	var cs := CollisionShape3D.new()
	var sh := ConvexPolygonShape3D.new()
	sh.points = PackedVector3Array([Vector3(-hx, wall_h, -hz), Vector3(hx, wall_h, -hz), Vector3(hx, wall_h, hz),
		Vector3(-hx, wall_h, hz), Vector3(-hx, wall_h + rise, 0.0), Vector3(hx, wall_h + rise, 0.0)])
	cs.shape = sh
	cs.transform = xf
	_body.add_child(cs)
	footprints.append([x, z, w + 0.6, d + 0.6, yaw, "house", wall_h + rise])
	counts["houses"] = int(counts["houses"]) + 1


func _street_cars() -> void:
	for c in HandLayout.CITY_CARS:
		var x: float = float(c[0])
		var z: float = float(c[1])
		var xf := Transform3D(Basis(Vector3.UP, float(c[2])), Vector3(x, world.get_height(x, z), z))
		var kind: String = str(CAR_MODEL.get(str(c[3]), "sedan"))
		var m: Node3D = ModelUtil.load_fit(CARS % kind, float(CAR_H.get(kind, 1.6)))
		if m != null:
			var sz: Vector3 = m.get_meta("size") as Vector3
			m.transform = xf
			node.add_child(m)
			PropFactory.add_collision(_body, xf, Vector3(0, sz.y * 0.5, 0), sz)
		counts["cars"] = int(counts["cars"]) + 1
