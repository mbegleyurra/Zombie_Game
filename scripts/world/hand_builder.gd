extends RefCounted
## Builds the hand-authored extras from hand_layout.gd: countryside cottages, the city's tower blocks, street lamps
## and abandoned street cars. One flat-shaded vertex-coloured mesh plus box collision, all under a "HandWorld" node
## at the world origin (positions are world coordinates). No randomness: the layout is data, the only RNG is a fixed
## seed used by PropFactory for car paint. Footprints are published as world meta "hand_footprints" for the map:
## [x, z, width, depth, yaw, kind ("house" | "tower"), height].

const MeshUtil = preload("res://scripts/world/mesh_util.gd")
const HandLayout = preload("res://scripts/world/hand_layout.gd")
const PropFactory = preload("res://scripts/world/prop_factory.gd")
const CityKit = preload("res://scripts/world/city_kit.gd")
const RoadKit = preload("res://scripts/world/road_kit.gd")

const WALLS := [Color(0.82, 0.78, 0.66), Color(0.66, 0.3, 0.22), Color(0.38, 0.5, 0.6), Color(0.85, 0.68, 0.4), Color(0.7, 0.72, 0.68)]
const ROOFS := [Color(0.3, 0.22, 0.2), Color(0.36, 0.2, 0.18), Color(0.25, 0.27, 0.3)]
const TOWERS := [Color(0.55, 0.56, 0.6), Color(0.62, 0.5, 0.42), Color(0.45, 0.5, 0.56), Color(0.7, 0.68, 0.62)]
const GLASS := Color(0.12, 0.17, 0.22)
const DARK := Color(0.16, 0.16, 0.18)
const LAMP_LIGHT := Color(0.95, 0.88, 0.6)
const FLOOR_H := 3.2

var world
var node: Node3D
var footprints: Array = []
var counts := {"houses": 0, "towers": 0, "lamps": 0, "cars": 0, "road_tiles": 0}
var _mu
var _body: StaticBody3D


func _init(p_world) -> void:
	world = p_world


func build() -> Node3D:
	node = Node3D.new()
	node.name = "HandWorld"
	_mu = MeshUtil.new()
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
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = _mu.to_mesh()
	mi.material_override = world.material
	node.add_child(mi)
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
	var wall_col: Color = WALLS[i % WALLS.size()]
	var roof_col: Color = ROOFS[i % ROOFS.size()]
	var centre := Vector3(0.0, wall_h * 0.5 - 0.3, 0.0)   # sunk 0.6 m so slopes never show a gap
	_mu.add_box_xf(xf, centre, Vector3(w, wall_h + 0.6, d), wall_col)
	PropFactory.add_collision(_body, xf, centre, Vector3(w, wall_h + 0.6, d))
	var hx: float = w * 0.5 + 0.3
	var hz: float = d * 0.5 + 0.3
	var e_bl: Vector3 = xf * Vector3(-hx, wall_h, -hz)
	var e_br: Vector3 = xf * Vector3(hx, wall_h, -hz)
	var e_fr: Vector3 = xf * Vector3(hx, wall_h, hz)
	var e_fl: Vector3 = xf * Vector3(-hx, wall_h, hz)
	var r_l: Vector3 = xf * Vector3(-hx, wall_h + rise, 0.0)
	var r_r: Vector3 = xf * Vector3(hx, wall_h + rise, 0.0)
	var b: Basis = xf.basis
	_mu.add_quad(e_bl, e_br, r_r, r_l, roof_col, b * Vector3(0, 1, -1))
	_mu.add_quad(e_fl, e_fr, r_r, r_l, roof_col, b * Vector3(0, 1, 1))
	_mu.add_tri(e_bl, e_fl, r_l, wall_col, b * Vector3(-1, 0, 0))
	_mu.add_tri(e_br, e_fr, r_r, wall_col, b * Vector3(1, 0, 0))
	var cs := CollisionShape3D.new()
	var sh := ConvexPolygonShape3D.new()
	sh.points = PackedVector3Array([Vector3(-hx, wall_h, -hz), Vector3(hx, wall_h, -hz), Vector3(hx, wall_h, hz),
		Vector3(-hx, wall_h, hz), Vector3(-hx, wall_h + rise, 0.0), Vector3(hx, wall_h + rise, 0.0)])
	cs.shape = sh
	cs.transform = xf
	_body.add_child(cs)
	# front: door and two windows; back: one window; chimney
	_mu.add_box_xf(xf, Vector3(0.0, 1.0, d * 0.5 + 0.03), Vector3(1.1, 2.0, 0.08), DARK.lightened(0.25))
	for wx in [-w * 0.3, w * 0.3]:
		_mu.add_box_xf(xf, Vector3(wx, 1.6, d * 0.5 + 0.03), Vector3(1.1, 0.9, 0.08), GLASS)
	_mu.add_box_xf(xf, Vector3(0.0, 1.6, -d * 0.5 - 0.03), Vector3(1.1, 0.9, 0.08), GLASS)
	_mu.add_box_xf(xf, Vector3(w * 0.28, wall_h + rise * 0.75, -d * 0.18), Vector3(0.7, rise * 1.2, 0.7), Color(0.45, 0.3, 0.25))
	footprints.append([x, z, w + 0.6, d + 0.6, yaw, "house", wall_h + rise])
	counts["houses"] = int(counts["houses"]) + 1


func _street_cars() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77001   # fixed: only picks car paint colours, never the layout
	for c in HandLayout.CITY_CARS:
		var x: float = float(c[0])
		var z: float = float(c[1])
		var xf := Transform3D(Basis(Vector3.UP, float(c[2])), Vector3(x, world.get_height(x, z), z))
		PropFactory.add_car(_mu, _body, xf, str(c[3]), PropFactory.random_car_color(rng), int(c[4]), rng)
		counts["cars"] = int(counts["cars"]) + 1
