extends RefCounted
## Enterable ground floors for the downtown (commercial) buildings, furnished with the Kenney Mini Shop / Mini Arcade
## props. Called from CityKit._lot; the kit building stays one model, only its box collider is swapped for a wall ring
## with a door gap on the street (front, local +Z) face plus a slab over the ground floor.
##
## Deterministic: every pick is arithmetic on the lot index, no RNG. Props hug the walls and keep a clear lane
## (|x| < LANE) from the door to the back wall. Everything is recorded on the "CityInteriors" node as meta:
##   "rooms"  [{lot, kind, x, z, w, d, yaw, gh, door: Vector2 (world, outside the door)}]
##   "placed" [{lot, kit, file, x, z, w, d, yaw, collide}]   (w/d are the prop's footprint in its own local axes)
## A model that fails to load is skipped (and listed in the kit's `missing`), never fatal.

const ModelUtil = preload("res://scripts/world/model_util.gd")
const PropFactory = preload("res://tools/worldgen/prop_factory.gd")

const SKYSCRAPER_FROM := 24.0  ## same cut-off as CityKit: taller lots keep their solid skyscraper model
const SCALE := 1.8             ## same fixture scale as the storefront dressing
const WALL_T := 0.5            ## wall ring thickness, inside the visible footprint
const DOOR_W := 2.8            ## door gap width
const LANE := 1.6              ## half-width of the prop-free lane from the door to the back wall
const GROUND_H := 3.4          ## ground-floor ceiling height
const LIFT := 0.03             ## props sit this far above the terrain, on the floor tile

const SHOP_BACK := ["shelf-boxes", "shelf-bags", "display-bread", "freezers-standing"]
const SHOP_LEFT := ["clothing-rack", "display-fruit"]
const SHOP_RIGHT := ["display-cans", "display-flowers"]
const ARC_BACK := ["arcade-machine", "claw-machine", "pinball", "dance-machine"]
const ARC_LEFT := ["claw-machine", "basketball-game"]
const ARC_RIGHT := ["vending-machine", "gambling-machine"]

var kit
var root: Node3D
var _rooms: Array = []
var _placed: Array = []


func _init(p_kit) -> void:
	kit = p_kit
	root = Node3D.new()
	root.name = "CityInteriors"
	kit.node.add_child(root)
	root.set_meta("rooms", _rooms)
	root.set_meta("placed", _placed)


## "shop" / "arcade" for lots that get an enterable ground floor, "" for the rest. Every 4th downtown lot is an arcade.
static func kind(district: String, h: float, idx: int) -> String:
	if district != "commercial" or h >= SKYSCRAPER_FROM:
		return ""
	return "arcade" if idx % 4 == 1 else "shop"


## Swap the building's box collider (child `box_index` of the kit body) for the wall ring and furnish the room.
## size is the visible footprint (x, height, z); the building sits at (cx, cz) turned by yaw, door on local +Z.
func furnish(k: String, box_index: int, idx: int, cx: float, cz: float, size: Vector3, yaw: float) -> void:
	var body: StaticBody3D = kit._body
	if box_index < 0 or box_index >= body.get_child_count():
		return
	var old: Node = body.get_child(box_index)
	if not (old is CollisionShape3D and (old as CollisionShape3D).shape is BoxShape3D):
		return   # not the building box: leave the solid building alone
	body.remove_child(old)
	old.free()
	var hw: float = size.x * 0.5
	var hd: float = size.z * 0.5
	var gh: float = minf(GROUND_H, size.y * 0.5)
	var y: float = kit.world.get_height(cx, cz) - 0.05
	var xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(cx, y, cz))
	var seg: float = hw - DOOR_W * 0.5
	for w in [
		[Vector3(0.0, gh * 0.5, -hd + WALL_T * 0.5), Vector3(size.x, gh, WALL_T)],
		[Vector3(-hw + WALL_T * 0.5, gh * 0.5, 0.0), Vector3(WALL_T, gh, size.z)],
		[Vector3(hw - WALL_T * 0.5, gh * 0.5, 0.0), Vector3(WALL_T, gh, size.z)],
		[Vector3(-(hw + DOOR_W * 0.5) * 0.5, gh * 0.5, hd - WALL_T * 0.5), Vector3(seg, gh, WALL_T)],
		[Vector3((hw + DOOR_W * 0.5) * 0.5, gh * 0.5, hd - WALL_T * 0.5), Vector3(seg, gh, WALL_T)],
		[Vector3(0.0, gh + (size.y - gh) * 0.5, 0.0), Vector3(size.x, size.y - gh, size.z)],
	]:
		PropFactory.add_collision(body, xf, w[0], w[1])
	var door := Basis(Vector3.UP, yaw) * Vector3(0.0, 0.0, hd + 1.0)
	_rooms.append({"lot": idx, "kind": k, "x": cx, "z": cz, "w": size.x, "d": size.z, "yaw": yaw, "gh": gh,
		"door": Vector2(cx + door.x, cz + door.z)})
	var ctx := {"lot": idx, "cx": cx, "cz": cz, "hw": hw, "hd": hd, "yaw": yaw}
	_floor(ctx)
	if k == "arcade":
		_layout(ctx, ARC_BACK, ARC_LEFT, ARC_RIGHT, "mini-arcade", "ticket-machine", "")
	else:
		_layout(ctx, SHOP_BACK, SHOP_LEFT, SHOP_RIGHT, "mini-shop", "clothing-table", "cash-register")


func _layout(c: Dictionary, back: Array, left: Array, right: Array, kit_name: String, counter: String,
		register: String) -> void:
	var i: int = int(c["lot"])
	var hd: float = c["hd"]
	# back wall: two fixtures either side of the lane
	_put(c, kit_name, str(back[i % back.size()]), "back", -3.4)
	_put(c, kit_name, str(back[(i + 1) % back.size()]), "back", 3.4)
	# side walls, back half only so they never meet the counter or the door
	for n in 2:
		_put(c, kit_name, str(left[(i + n) % left.size()]), "left", -hd + 3.4 + 1.7 * n)
		_put(c, kit_name, str(right[(i + n) % right.size()]), "right", -hd + 3.4 + 1.7 * n)
	# counter just inside the door on the right, register on top (shops)
	var cs: Vector3 = _put(c, kit_name, counter, "free", 3.3, hd - 2.6)
	if register != "" and cs != Vector3.ZERO:
		_put(c, kit_name, register, "free", 3.3, hd - 2.6, cs.y, false)


## One prop in the room. side "back" / "left" / "right": against that wall, `a` = position along it (x for back,
## z for left / right), facing into the room. side "free": at local (a, b). Returns its scaled size (zero when the
## model is missing).
func _put(c: Dictionary, kit_name: String, file: String, side: String, a: float, b: float = 0.0,
		extra_lift: float = 0.0, collide: bool = true) -> Vector3:
	var inst: Node3D = kit._instance(kit_name, file)
	if inst == null:
		return Vector3.ZERO
	var bb: AABB = ModelUtil.bounds(inst)
	var size: Vector3 = bb.size * SCALE
	var hw: float = c["hw"]
	var hd: float = c["hd"]
	var inset: float = WALL_T + 0.1 + size.z * 0.5
	var lx: float = a
	var lz: float = b
	var local_yaw := 0.0
	match side:
		"back":
			lz = -hd + inset
		"left":
			lx = -hw + inset
			lz = a
			local_yaw = PI * 0.5
		"right":
			lx = hw - inset
			lz = a
			local_yaw = -PI * 0.5
	var yaw: float = float(c["yaw"])
	var off: Vector3 = Basis(Vector3.UP, yaw) * Vector3(lx, 0.0, lz)
	var x: float = float(c["cx"]) + off.x
	var z: float = float(c["cz"]) + off.z
	var wrap := Node3D.new()
	wrap.name = "%s_%s" % [kit_name, file]
	wrap.position = Vector3(x, kit.world.get_height(x, z) + LIFT + extra_lift, z)
	wrap.rotation.y = yaw + local_yaw
	inst.scale = Vector3(SCALE, SCALE, SCALE)
	var ctr: Vector3 = bb.get_center()
	inst.position = Vector3(-ctr.x * SCALE, -bb.position.y * SCALE, -ctr.z * SCALE)
	wrap.add_child(inst)
	root.add_child(wrap)
	var solid: bool = collide and size.y > 0.3
	if solid:
		var xf := Transform3D(Basis(Vector3.UP, yaw + local_yaw), wrap.position)
		PropFactory.add_collision(kit._body, xf, Vector3(0.0, size.y * 0.5, 0.0),
			Vector3(maxf(size.x, 0.2), size.y, maxf(size.z, 0.2)))
	kit.props[kit_name] = int(kit.props[kit_name]) + 1
	_placed.append({"lot": c["lot"], "kit": kit_name, "file": file, "x": x, "z": z, "w": size.x, "d": size.z,
		"yaw": yaw + local_yaw, "collide": solid})
	return size


## Wood floor tile stretched over the room so the interior reads as a floor (no collision: terrain is the ground).
func _floor(c: Dictionary) -> void:
	var inst: Node3D = kit._instance("mini-shop", "floor-wood")
	if inst == null:
		return
	var bb: AABB = ModelUtil.bounds(inst)
	var sx: float = (float(c["hw"]) * 2.0 - WALL_T * 2.0) / maxf(bb.size.x, 0.01)
	var sz: float = (float(c["hd"]) * 2.0 - WALL_T * 2.0) / maxf(bb.size.z, 0.01)
	var wrap := Node3D.new()
	wrap.name = "floor_%d" % int(c["lot"])
	wrap.position = Vector3(float(c["cx"]), kit.world.get_height(float(c["cx"]), float(c["cz"])) + 0.01, float(c["cz"]))
	wrap.rotation.y = float(c["yaw"])
	inst.scale = Vector3(sx, 1.0, sz)
	var ctr: Vector3 = bb.get_center()
	inst.position = Vector3(-ctr.x * sx, -bb.position.y, -ctr.z * sz)
	wrap.add_child(inst)
	root.add_child(wrap)
