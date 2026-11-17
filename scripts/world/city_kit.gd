extends RefCounted
## The city district built from Kenney City Kit Commercial / Industrial / Suburban (CC0), with Mini Shop and Mini Arcade
## storefront dressing and the street props of City Kit Roads. It replaces the old procedural tower boxes.
##
## Deterministic: no RNG, every pick is arithmetic on the lot index. The lot rectangles come straight from
## HandLayout.CITY_BLOCKS, so the street clearances are the ones the 'roads do not cross buildings' test already
## guards; the footprints published for the map are the VISIBLE (scaled model) size, always inside the lot.
## West block column = suburban, centre column = commercial downtown, east column = industrial.
## Every placed model is recorded in `models` (path -> count) and every path that failed to load in `missing`.

const ModelUtil = preload("res://scripts/world/model_util.gd")
const HandLayout = preload("res://scripts/world/hand_layout.gd")
const PropFactory = preload("res://scripts/world/prop_factory.gd")

const DIR := {
	"commercial": "res://assets/kenney/city-kit-commercial/",
	"industrial": "res://assets/kenney/city-kit-industrial/",
	"suburban": "res://assets/kenney/city-kit-suburban/",
	"roads": "res://assets/kenney/city-kit-roads/",
	"mini-shop": "res://assets/kenney/mini-shop/",
	"mini-arcade": "res://assets/kenney/mini-arcade/",
}

const FILL := 0.92            ## the model fills at most this much of its lot, so streets keep a sidewalk gap
const MAX_STRETCH := 1.4      ## a model may be stretched this much more along its looser lot axis
const SKYSCRAPER_FROM := 24.0 ## commercial lots whose old tower was at least this tall get a skyscraper model
const STORE_SCALE := 1.8      ## mini-shop / mini-arcade pieces are about 0.8 m; this makes them shop-fixture sized

const COMM_LOW := ["building-a", "building-b", "building-c", "building-d", "building-e", "building-f", "building-g",
	"building-h", "building-i", "building-j", "building-k", "building-l", "building-m", "building-n"]
const COMM_SKY := ["building-skyscraper-a", "building-skyscraper-b", "building-skyscraper-c", "building-skyscraper-d",
	"building-skyscraper-e"]
const IND_LETTERS := "abcdefghijklmnopqrst"
const SUB_LETTERS := "abcdefghijklmnopqrstu"
const SHOP_ITEMS := ["display-fruit", "shelf-bags", "clothing-rack", "display-cans", "display-flowers", "shopping-cart"]
const ARCADE_ITEMS := ["arcade-machine", "claw-machine", "vending-machine", "pinball", "gambling-machine"]

var world
var node: Node3D
var buildings := {"commercial": 0, "industrial": 0, "suburban": 0}
var props := {"commercial": 0, "industrial": 0, "suburban": 0, "roads": 0, "mini-shop": 0, "mini-arcade": 0}
var models: Dictionary = {}
var missing: Array = []
var _body: StaticBody3D
var _footprints: Array
var _counts: Dictionary


func _init(p_world, p_node: Node3D, p_body: StaticBody3D, p_footprints: Array, p_counts: Dictionary) -> void:
	world = p_world
	node = p_node
	_body = p_body
	_footprints = p_footprints
	_counts = p_counts


func build() -> void:
	var idx := 0
	var blk_i := 0
	for blk in HandLayout.CITY_BLOCKS:
		var bx: float = float(blk[0])
		var bz: float = float(blk[1])
		var district: String = district_at(bx)
		for t in blk[2]:
			_lot(district, idx, bx + float(t[0]), bz + float(t[1]), float(t[2]), float(t[3]), float(t[4]),
				-1.0 if float(t[1]) < 0.0 else 1.0)
			idx += 1
		_block_centre(district, blk_i, bx, bz)
		blk_i += 1


## Suburban on the west edge, commercial downtown in the middle, industrial on the east edge.
static func district_at(block_x: float) -> String:
	if block_x < 68.0:
		return "suburban"
	if block_x < 112.0:
		return "commercial"
	return "industrial"


func _pick(district: String, idx: int, h: float) -> String:
	match district:
		"commercial":
			if h >= SKYSCRAPER_FROM:
				return COMM_SKY[idx % COMM_SKY.size()]
			return COMM_LOW[(idx * 3 + 1) % COMM_LOW.size()]
		"industrial":
			return "building-%s" % IND_LETTERS[(idx * 7 + 2) % IND_LETTERS.length()]
		_:
			return "building-type-%s" % SUB_LETTERS[(idx * 5 + 1) % SUB_LETTERS.length()]


func _lot(district: String, idx: int, cx: float, cz: float, w: float, d: float, h: float, front_z: float) -> void:
	var file: String = _pick(district, idx, h)
	var yaw: float = PI if front_z < 0.0 else 0.0   # door side (local +Z) faces the nearer street
	var info: Dictionary = _building(district, file, cx, cz, w, d, yaw, h if file.contains("skyscraper") else 0.0)
	if info.is_empty():
		_footprints.append([cx, cz, w, d, 0.0, "tower", h])
	else:
		var size: Vector3 = info["size"]
		_footprints.append([cx, cz, size.x, size.z, 0.0, "tower", size.y])
		buildings[district] = int(buildings[district]) + 1
		_frontage(district, idx, cx, cz, size.z, front_z, yaw)
	_counts["towers"] = int(_counts["towers"]) + 1


## One kit building scaled to fit the lot (w x d), optionally stretched in height toward target_h, with a box collider.
func _building(kit: String, file: String, cx: float, cz: float, w: float, d: float, yaw: float, target_h: float) -> Dictionary:
	var inst: Node3D = _instance(kit, file)
	if inst == null:
		return {}
	var bb: AABB = ModelUtil.bounds(inst)
	var sx: float = w * FILL / maxf(bb.size.x, 0.01)
	var sz: float = d * FILL / maxf(bb.size.z, 0.01)
	var s: float = minf(sx, sz)
	var scl := Vector3(minf(sx, s * MAX_STRETCH), s, minf(sz, s * MAX_STRETCH))
	if target_h > 0.0:
		scl.y = clampf(target_h / maxf(bb.size.y, 0.01), s * 0.7, s * 1.5)
	var y: float = world.get_height(cx, cz) - 0.05
	var size := Vector3(bb.size.x * scl.x, bb.size.y * scl.y, bb.size.z * scl.z)
	var wrap := Node3D.new()
	wrap.name = "%s_%s" % [kit, file]
	wrap.position = Vector3(cx, y, cz)
	wrap.rotation.y = yaw
	inst.scale = scl
	var c: Vector3 = bb.get_center()
	inst.position = Vector3(-c.x * scl.x, -bb.position.y * scl.y, -c.z * scl.z)
	wrap.add_child(inst)
	node.add_child(wrap)
	var xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(cx, y, cz))
	PropFactory.add_collision(_body, xf, Vector3(0.0, size.y * 0.5, 0.0), size)
	return {"size": size}


## Street-front dressing on the sidewalk side of a lot: mini-shop / mini-arcade fixtures downtown, a driveway in the suburbs.
func _frontage(district: String, idx: int, cx: float, cz: float, depth: float, front_z: float, yaw: float) -> void:
	var face_z: float = cz + front_z * (depth * 0.5)
	if district == "commercial":
		# pavement strip under the storefront fixtures (road kit tile-low, no collision)
		prop("roads", "tile-low", cx, face_z + front_z * 1.2, 12.0, yaw, false, 0.08)
		var slots := [-3.5, 0.0, 3.5]
		for s in 3:
			var arcade: bool = s == 1
			var list: Array = ARCADE_ITEMS if arcade else SHOP_ITEMS
			prop("mini-arcade" if arcade else "mini-shop", str(list[(idx + s) % list.size()]),
				cx + float(slots[s]), face_z + front_z * 0.9, STORE_SCALE, yaw)
	elif district == "suburban":
		prop("suburban", "driveway-short", cx, face_z + front_z * 1.0, 10.0, yaw, false, 0.03)


## Block-centre plaza (the cross-shaped gap between the four lots): water tower / chimney, trees, or parasols.
func _block_centre(district: String, blk_i: int, bx: float, bz: float) -> void:
	match district:
		"industrial":
			if blk_i % 2 == 0:
				prop("industrial", "water-tower", bx, bz, 4.5, 0.0)
			else:
				prop("industrial", "chimney-large", bx, bz, 3.2, 0.0)
		"suburban":
			prop("suburban", "tree-large", bx, bz - 1.5, 7.0, 0.0)
			prop("suburban", "tree-small", bx, bz + 1.5, 7.0, 0.0)
		_:
			prop("commercial", "detail-parasol-a", bx - 1.4, bz, 6.0, 0.0)
			prop("commercial", "detail-parasol-b", bx + 1.4, bz, 6.0, 0.0)


## A single uniformly scaled kit model, centred on x/z and sitting on the ground (+lift). Returns its scaled size.
func prop(kit: String, file: String, x: float, z: float, scale: float, yaw: float, collide: bool = true, lift: float = 0.0) -> Vector3:
	var inst: Node3D = _instance(kit, file)
	if inst == null:
		return Vector3.ZERO
	var bb: AABB = ModelUtil.bounds(inst)
	var size: Vector3 = bb.size * scale
	var y: float = world.get_height(x, z) + lift
	var wrap := Node3D.new()
	wrap.name = "%s_%s" % [kit, file]
	wrap.position = Vector3(x, y, z)
	wrap.rotation.y = yaw
	inst.scale = Vector3(scale, scale, scale)
	var c: Vector3 = bb.get_center()
	inst.position = Vector3(-c.x * scale, -bb.position.y * scale, -c.z * scale)
	wrap.add_child(inst)
	node.add_child(wrap)
	if collide and size.y > 0.3:
		var xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(x, y, z))
		PropFactory.add_collision(_body, xf, Vector3(0.0, size.y * 0.5, 0.0), Vector3(maxf(size.x, 0.2), size.y, maxf(size.z, 0.2)))
	props[kit] = int(props[kit]) + 1
	return size


func _instance(kit: String, file: String) -> Node3D:
	var path: String = str(DIR[kit]) + file + ".glb"
	var ps: PackedScene = null
	if ResourceLoader.exists(path):
		ps = load(path) as PackedScene
	var inst: Node3D = ps.instantiate() as Node3D if ps != null else null
	if inst == null:
		missing.append(path)
		return null
	models[path] = int(models.get(path, 0)) + 1
	return inst
