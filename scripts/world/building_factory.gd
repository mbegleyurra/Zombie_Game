extends RefCounted
## Builds the enterable low-poly locations (farm, gas station, hospital) from primitive boxes/prisms.
## Each location is one flat-shaded vertex-coloured mesh plus box collision shapes, with doors/windows cut
## as real openings in the walls so interiors are walkable. Local origin = pad centre at ground level.

const LootContainer = preload("res://scripts/world/loot_container.gd")
const LootItem = preload("res://scripts/world/loot_item.gd")
const ItemDB = preload("res://scripts/world/item_db.gd")
const PropFactory = preload("res://scripts/world/prop_factory.gd")
const ModelUtil = preload("res://scripts/world/model_util.gd")
const KENNEY_FOOD := "res://assets/kenney/food/"
const SURV := "res://assets/kenney/survival/"
const GY := "res://assets/kenney/graveyard/"
const CARS := "res://assets/kenney/cars/"
const HandMapData = preload("res://scripts/world/hand_map_data.gd")
const WALL_PANEL := SURV + "metal-panel.glb"   # solid 0.5 x 0.5 m panel; structure-metal-wall.glb is an open frame
const WALL_CELL := 2.5   # target tile height (m) for wall panels
const SLAB_CELL := 2.0   # target tile edge (m) for floor and roof slabs
const CAR_MODEL := {"sedan": "sedan", "pickup": "suv", "van": "van", "police": "police", "truck": "delivery"}
const CAR_H := {"sedan": 1.45, "suv": 1.75, "van": 2.1, "police": 1.5, "delivery": 2.5, "tractor": 2.0}

const F := 0.06   # floor top height above ground (small enough to step over)
const T := 0.3    # default wall thickness

const C_FLOOR_WOOD := Color(0.5, 0.36, 0.24)
const C_FLOOR_CONCRETE := Color(0.55, 0.55, 0.56)
const C_ROOF_DARK := Color(0.28, 0.2, 0.2)
const C_FURN := Color(0.45, 0.32, 0.2)
const C_WHITE := Color(0.9, 0.9, 0.88)
const C_RED := Color(0.78, 0.18, 0.15)
const C_YELLOW := Color(0.92, 0.75, 0.2)
const C_DARK := Color(0.16, 0.16, 0.18)

const C_FENCE_WOOD := Color(0.55, 0.45, 0.32)
const C_FENCE_METAL := Color(0.5, 0.52, 0.55)
const C_FENCE_IRON := Color(0.15, 0.15, 0.17)

const FARM_WALLS := [Color(0.66, 0.3, 0.22), Color(0.82, 0.78, 0.66), Color(0.38, 0.5, 0.6), Color(0.85, 0.68, 0.4)]

var world
var material: Material
var _body: StaticBody3D
var _root: Node3D
var _loc: int = -1   # location id (root meta "loc_id"): keys the authored rows in HandMapData
var _foot: Array = []       # Rect2 (local XZ) of every solid that blocks the floor: scatter avoids these
var _scatter_q: Array = []  # deferred ground-loot requests, resolved in _finish once all solids exist

const SCATTER_MARGIN := 0.5


func _init(p_world, p_material: Material) -> void:
	world = p_world
	material = p_material


# ---------------------------------------------------------------- shared helpers

func _begin(root: Node3D) -> void:
	_root = root
	_loc = int(root.get_meta("loc_id", -1))
	_body = StaticBody3D.new()
	_body.name = "Collision"
	_foot = []
	_scatter_q = []


func _finish() -> void:
	_flush_scatter()
	_root.add_child(_body)


## Records a solid's floor footprint when it stands in the walking band (floor .. head height).
func _note_foot(pos: Vector3, size: Vector3) -> void:
	if pos.y + size.y * 0.5 > F + 0.25 and pos.y - size.y * 0.5 < F + 1.6:
		_foot.append(Rect2(pos.x - size.x * 0.5, pos.z - size.z * 0.5, size.x, size.z))


func _box(pos: Vector3, size: Vector3, col: Color, collide: bool = true) -> void:
	var model := _box_model(size)
	if model == WALL_PANEL:
		# Solid panels tiled along the segment (about 2.5 m square), never one stretched piece.
		var rot: bool = size.x < size.z
		var sz: Vector3 = Vector3(size.z, size.y, size.x) if rot else size
		var ch: float = sz.y / float(maxi(1, roundi(sz.y / WALL_CELL)))
		var xf := Transform3D(Basis(Vector3.UP, PI * 0.5) if rot else Basis(), pos)
		_tiled_at(model, xf, sz, Vector3(ch, ch, 0.0))
	elif model.ends_with("/floor.glb"):
		_tiled_at(model, Transform3D.IDENTITY, size, Vector3(SLAB_CELL, 0.0, SLAB_CELL), pos)
	elif model.ends_with("box-large.glb") and maxf(size.x, maxf(size.y, size.z)) > 2.0:
		_tiled_at(model, Transform3D.IDENTITY, size, Vector3(1.0, 1.0, 1.0), pos)
	else:
		_model_box(model, pos, size)
	if collide:
		_note_foot(pos, size)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		cs.position = pos
		_body.add_child(cs)


func _cyl(base: Vector3, r: float, h: float, segs: int, col: Color) -> void:
	_model_box(SURV + ("barrel.glb" if r >= 1.0 else "signpost.glb"), base + Vector3(0, h * 0.5, 0), Vector3(r * 2.0, h, r * 2.0))
	_note_foot(base + Vector3(0, h * 0.5, 0), Vector3(r * 2.0, h, r * 2.0))
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = r
	sh.height = h
	cs.shape = sh
	cs.position = base + Vector3(0, h * 0.5, 0)
	_body.add_child(cs)


## Visual stand-in for a primitive: a downloaded model stretched over `size`, centred at `center` in frame `xf`.
func _model_at(file: String, xf: Transform3D, center: Vector3, size: Vector3) -> void:
	var m: Node3D = ModelUtil.fit_box(file, size)
	if m == null:
		return
	m.transform = xf * Transform3D(Basis(), center)
	_root.add_child(m)


## Like _model_at, but the model is repeated on a grid (cell per axis, <= 0 = one tile) so it keeps its proportions.
func _tiled_at(file: String, xf: Transform3D, size: Vector3, cell: Vector3, center: Vector3 = Vector3.ZERO) -> void:
	var m: Node3D = ModelUtil.tile_box(file, size, cell)
	if m == null:
		return
	m.transform = xf * Transform3D(Basis(), center)
	_root.add_child(m)


func _model_box(file: String, center: Vector3, size: Vector3) -> void:
	_model_at(file, Transform3D.IDENTITY, center, size)


## Which Kenney survival piece stands in for a box of this size.
func _box_model(size: Vector3) -> String:
	if size.y <= 0.6 and size.x >= 1.5 and size.z >= 1.5:
		return SURV + "floor.glb"
	if size.y >= 1.2 and minf(size.x, size.z) <= 0.5:
		return WALL_PANEL
	return SURV + "box-large.glb"


## A Kenney vehicle model (cars/<name>.glb) on xf, with a box collider of its size.
func _vehicle(model_name: String, xf: Transform3D) -> void:
	var m: Node3D = ModelUtil.load_fit(CARS + model_name + ".glb", float(CAR_H.get(model_name, 1.6)))
	if m == null:
		return
	var sz: Vector3 = m.get_meta("size") as Vector3
	m.transform = xf
	_root.add_child(m)
	PropFactory.add_collision(_body, xf, Vector3(0, sz.y * 0.5, 0), sz)


func _door(c: float, w: float = 1.6, h: float = 2.4) -> Dictionary:
	return {"c": c, "w": w, "y0": 0.0, "y1": h}


func _win(c: float, w: float = 1.4, y0: float = 1.0, y1: float = 2.1) -> Dictionary:
	return {"c": c, "w": w, "y0": y0, "y1": y1}


## Axis-aligned wall with openings. axis 0 = runs along X at z=fixed, axis 1 = runs along Z at x=fixed.
## Openings are {c, w, y0, y1} (centre along wall, width, bottom/top relative to floor). Must not overlap.
func _wall(axis: int, fixed: float, a0: float, a1: float, h: float, col: Color, openings: Array = [], thick: float = T) -> void:
	var ops: Array = openings.duplicate()
	ops.sort_custom(func(p: Dictionary, q: Dictionary) -> bool: return float(p["c"]) < float(q["c"]))
	var cursor: float = a0
	for o in ops:
		var lo: float = float(o["c"]) - float(o["w"]) * 0.5
		var hi: float = float(o["c"]) + float(o["w"]) * 0.5
		_seg(axis, fixed, cursor, lo, F, F + h, col, thick)
		_seg(axis, fixed, lo, hi, F, F + float(o["y0"]), col, thick)
		_seg(axis, fixed, lo, hi, F + float(o["y1"]), F + h, col, thick)
		cursor = hi
	_seg(axis, fixed, cursor, a1, F, F + h, col, thick)


func _seg(axis: int, fixed: float, l: float, r: float, ylo: float, yhi: float, col: Color, thick: float) -> void:
	if r - l < 0.01 or yhi - ylo < 0.01:
		return
	var mid: float = (l + r) * 0.5
	var len: float = r - l
	var cy: float = (ylo + yhi) * 0.5
	var sy: float = yhi - ylo
	if axis == 0:
		_box(Vector3(mid, cy, fixed), Vector3(len, sy, thick), col)
	else:
		_box(Vector3(fixed, cy, mid), Vector3(thick, sy, len), col)


func _floor_slab(cx: float, cz: float, w: float, d: float, col: Color) -> void:
	_box(Vector3(cx, F - 0.25, cz), Vector3(w, 0.5, d), col)


## Decorative Kenney Food Kit prop: no collision, no loot, so it never affects play. pos is location-local.
func _deco(file: String, height: float, pos: Vector3, yaw: float = 0.0) -> void:
	var m: Node3D = ModelUtil.load_fit(KENNEY_FOOD + file, height)
	if m == null:
		return
	m.position = pos
	m.rotation.y = yaw
	_root.add_child(m)


## Gable roof, ridge along X. y_eave = wall top. Solid convex collision wedge above the eaves.
func _gable_roof(cx: float, cz: float, hx: float, hz: float, y_eave: float, rise: float, roof: Color, gable: Color) -> void:
	var e_bl := Vector3(cx - hx, y_eave, cz - hz)
	var e_br := Vector3(cx + hx, y_eave, cz - hz)
	var e_fr := Vector3(cx + hx, y_eave, cz + hz)
	var e_fl := Vector3(cx - hx, y_eave, cz + hz)
	var r_l := Vector3(cx - hx, y_eave + rise, cz)
	var r_r := Vector3(cx + hx, y_eave + rise, cz)
	_model_box(SURV + "structure-roof.glb", Vector3(cx, y_eave + rise * 0.5, cz), Vector3(hx * 2.0, rise, hz * 2.0))
	var cs := CollisionShape3D.new()
	var sh := ConvexPolygonShape3D.new()
	sh.points = PackedVector3Array([e_bl, e_br, e_fr, e_fl, r_l, r_r])
	cs.shape = sh
	_body.add_child(cs)


## Spawns a searchable container. y_base = bottom height (defaults to the floor).
func _container(kind: String, table: String, x: float, z: float, rot: float, y_base: float = F) -> void:
	var c = LootContainer.new()
	var id: int = world.next_loot_id()
	c.setup(id, kind, table, world.world_seed)
	c.position = Vector3(x, y_base, z)
	c.rotation.y = rot
	_root.add_child(c)
	world.register_loot(c)
	if y_base <= F + 0.01:
		_foot.append(Rect2(x - 0.8, z - 0.8, 1.6, 1.6))


## Queues ground pickups inside a rectangle (local coordinates). They are placed in _finish(), after
## every solid is known, so no item ends up inside a bed, counter, car or wall.
func _scatter(table: String, count: int, x0: float, x1: float, z0: float, z1: float) -> void:
	_scatter_q.append([table, count, x0, x1, z0, z1])


func _blocked_xz(x: float, z: float) -> bool:
	for r in _foot:
		if (r as Rect2).grow(SCATTER_MARGIN).has_point(Vector2(x, z)):
			return true
	return false


## Authored ground pickups for this location (SCATTER rows [loc, item, amount, local_x, local_z, yaw]).
## The queued requests only mark where loot belongs; the exact spots are data.
func _flush_scatter() -> void:
	for row in HandMapData.for_loc("SCATTER", _loc):
		var r: Array = row
		var px: float = float(r[3])
		var pz: float = float(r[4])
		var id: int = world.next_loot_id()
		var item = LootItem.create(str(r[1]), int(r[2]), id)
		item.position = Vector3(px, _scatter_y(px, pz), pz)
		item.rotation.y = float(r[5])
		_root.add_child(item)
		world.register_loot(item)
	_scatter_q = []


## Local y for a ground pickup at local (x, z): the floor top, or the CURRENT terrain surface when that is higher.
## Yards beside a building are not covered by its floor slab, and a road bed carved through the pad (a driveway)
## raises the ground there, so a fixed floor height would bury the item.
func _scatter_y(x: float, z: float) -> float:
	var y: float = F + 0.02
	if world != null and world.terrain != null and _root != null and _root.is_inside_tree():
		var wp: Vector3 = _root.to_global(Vector3(x, 0.0, z))
		y = maxf(y, world.terrain.height_at(wp.x, wp.z) - _root.global_position.y + 0.04)
	return y


## Collision only (no mesh), for props whose visuals are drawn separately.
func _solid(pos: Vector3, size: Vector3) -> void:
	_note_foot(pos, size)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = pos
	_body.add_child(cs)


## Parks a car (kind sedan/pickup/van/police/truck). wreck: 0 intact, 1 rusted, 2 burnt out.
func _car(pos: Vector3, yaw: float, kind: String, _wreck: int = 0) -> void:
	var xf := Transform3D(Basis(Vector3.UP, yaw), pos)
	_foot.append(Rect2(pos.x - 3.0, pos.z - 3.0, 6.0, 6.0))
	_vehicle(str(CAR_MODEL.get(kind, "sedan")), xf)


## Fence line from a to b (local XZ) with an optional gate gap (gap_w > 0) in the middle.
func _fence(a: Vector2, b: Vector2, gap_w: float, col: Color, h: float) -> void:
	var d := b - a
	var length: float = d.length()
	if length < 0.5:
		return
	var dir := d / length
	var fx := Transform3D(Basis(Vector3.UP, atan2(-dir.y, dir.x)), Vector3(a.x, F, a.y))
	var g0: float = length * 0.5 - gap_w * 0.5
	var g1: float = length * 0.5 + gap_w * 0.5
	var has_gap: bool = gap_w > 0.0
	var pieces: Array = [[0.0, length]]
	if has_gap:
		pieces = [[0.0, g0], [g1, length]]
	for pc in pieces:
		var s0: float = float(pc[0])
		var s1: float = float(pc[1])
		if s1 - s0 < 0.2:
			continue
		var mid: float = (s0 + s1) * 0.5
		var ln: float = s1 - s0
		_model_at((GY + "iron-fence.glb") if col == C_FENCE_IRON else (SURV + "fence.glb"), fx, Vector3(mid, h * 0.5, 0.0), Vector3(ln, h, 0.12))
		PropFactory.add_collision(_body, fx, Vector3(mid, h * 0.5, 0.0), Vector3(ln, h, 0.12))


func _fence_rect(x0: float, z0: float, x1: float, z1: float, gap_w: float, col: Color, h: float) -> void:
	_fence(Vector2(x0, z0), Vector2(x1, z0), gap_w, col, h)
	_fence(Vector2(x1, z0), Vector2(x1, z1), gap_w, col, h)
	_fence(Vector2(x1, z1), Vector2(x0, z1), gap_w, col, h)
	_fence(Vector2(x0, z1), Vector2(x0, z0), gap_w, col, h)


# ---------------------------------------------------------------- FARM

func build_farm(root: Node3D) -> void:
	_begin(root)
	var farm_rows: Array = HandMapData.for_loc("FARM", _loc)
	var wall: Color = FARM_WALLS[int((farm_rows[0] as Array)[1]) if not farm_rows.is_empty() else 0]
	var veh_rows: Array = HandMapData.for_loc("FARM_VEH", _loc)
	var veh: Array = veh_rows[0] as Array if not veh_rows.is_empty() else [_loc, 0.0, 0.0]
	var trim := wall.darkened(0.2)
	# Farmhouse: x in [-5,5], z in [-4,4], walls 3 m.
	var H := 3.0
	_floor_slab(0, 0, 10.6, 8.6, C_FLOOR_WOOD)
	_wall(0, 4.0, -5.15, 5.15, H, wall, [_door(0.0), _win(-3.0), _win(3.0)])
	_wall(0, -4.0, -5.15, 5.15, H, wall, [_win(-3.0), _door(3.0, 1.4)])
	_wall(1, -5.0, -3.85, 3.85, H, wall, [_win(0.0)])
	_wall(1, 5.0, -3.85, 3.85, H, wall, [_win(0.0)])
	_wall(1, 1.5, -3.85, 3.85, H, trim, [_door(0.5, 1.4)], 0.2)
	_gable_roof(0, 0, 5.6, 4.6, F + H, 2.6, C_ROOF_DARK, wall.darkened(0.1))
	# Furniture
	_box(Vector3(-3.5, F + 0.25, -2.6), Vector3(2.0, 0.5, 1.0), Color(0.75, 0.75, 0.8))     # bed
	_box(Vector3(3.2, F + 0.45, -3.5), Vector3(2.4, 0.9, 0.7), C_FURN)                       # counter
	_box(Vector3(3.2, F + 0.4, 0.8), Vector3(1.4, 0.8, 1.2), C_FURN)                         # table
	_container("cupboard", "farm", -4.5, 1.8, PI * 0.5)
	_container("fridge", "farm", 4.3, -3.5, 0.0)
	_container("crate", "farm", -2.2, 3.0, 0.3)
	_scatter("farm", 3, -4.4, 4.4, -3.4, 3.4)
	# Food Kit dressing: dinner table (top F+0.8) and kitchen counter (top F+0.9)
	_deco("plate.glb", 0.03, Vector3(2.9, F + 0.8, 0.55), 0.0)
	_deco("plate.glb", 0.03, Vector3(3.5, F + 0.8, 1.05), 0.0)
	_deco("apple.glb", 0.08, Vector3(3.5, F + 0.83, 1.05), 0.0)
	_deco("mug.glb", 0.1, Vector3(3.2, F + 0.8, 0.8), 0.8)
	_deco("pot-stew.glb", 0.2, Vector3(2.4, F + 0.9, -3.5), 0.0)
	_deco("frying-pan.glb", 0.04, Vector3(2.9, F + 0.9, -3.5), 0.5)
	_deco("loaf.glb", 0.15, Vector3(3.4, F + 0.9, -3.45), 0.2)
	# Barn: x in [10,18], z in [-5,1]
	var bx := 14.0
	var bz := -2.0
	var BH := 3.6
	var barn := Color(0.62, 0.2, 0.16)
	_floor_slab(bx, bz, 8.6, 6.6, Color(0.42, 0.34, 0.25))
	_wall(0, bz + 3.0, bx - 4.15, bx + 4.15, BH, barn, [_door(bx, 3.4, 2.9)])
	_wall(0, bz - 3.0, bx - 4.15, bx + 4.15, BH, barn, [_win(bx + 2.0, 1.2, 1.4, 2.4)])
	_wall(1, bx - 4.0, bz - 2.85, bz + 2.85, BH, barn, [_win(bz, 1.2, 1.4, 2.4)])
	_wall(1, bx + 4.0, bz - 2.85, bz + 2.85, BH, barn)
	_gable_roof(bx, bz, 4.6, 3.6, F + BH, 2.2, Color(0.3, 0.3, 0.34), barn.darkened(0.1))
	_box(Vector3(bx - 2.8, F + 0.45, bz - 1.8), Vector3(1.4, 0.9, 1.0), C_YELLOW)  # hay
	_box(Vector3(bx - 2.8, F + 1.35, bz - 1.8), Vector3(1.2, 0.9, 0.9), C_YELLOW.darkened(0.1))
	_box(Vector3(bx + 1.5, F + 0.45, bz - 2.2), Vector3(1.4, 0.9, 1.0), C_YELLOW)
	_container("crate", "barn", bx + 3.0, bz + 1.5, 0.0)
	_container("crate", "barn", bx - 3.0, bz + 1.8, 0.2)
	_container("toolbox", "barn", bx + 3.2, bz - 0.5, -PI * 0.5)
	_scatter("barn", 3, bx - 3.4, bx + 3.4, bz - 2.4, bz + 2.4)
	# Silo and yard
	_cyl(Vector3(-15.0, 0.0, -5.0), 2.2, 8.0, 8, Color(0.7, 0.72, 0.74))
	_box(Vector3(-9.0, 0.5, 9.0), Vector3(3.0, 1.0, 1.2), Color(0.5, 0.35, 0.2))     # wagon bed
	_scatter("wild", 2, -10.0, 10.0, 6.0, 14.0)
	# Round 4 props (no loot rolls): weathered fence with gates, crop rows, tractor, pickup truck
	_fence_rect(-19.0, -15.0, 19.0, 17.0, 4.0, C_FENCE_WOOD, 1.2)
	# (crop rows were primitive boxes with no downloaded equivalent: removed)
	var tractor_xf := Transform3D(Basis(Vector3.UP, float(veh[1])), Vector3(-13.0, F, 5.0))
	_vehicle("tractor", tractor_xf)
	_foot.append(Rect2(-15.0, 3.0, 4.0, 4.0))
	_car(Vector3(3.0, F, 15.5), float(veh[2]), "pickup", 0)
	_finish()


# ---------------------------------------------------------------- GAS STATION

func build_gas_station(root: Node3D) -> void:
	_begin(root)
	var H := 3.2
	var wall := Color(0.9, 0.88, 0.8)
	_floor_slab(0, 0, 12.6, 8.6, C_FLOOR_CONCRETE)
	_wall(0, 4.0, -6.15, 6.15, H, wall, [_win(-2.2, 5.0, 0.9, 2.6), _door(3.0)])
	_wall(0, -4.0, -6.15, 6.15, H, wall, [_door(4.2, 1.4)])
	_wall(1, -6.0, -3.85, 3.85, H, wall, [_win(0.0, 2.0, 1.0, 2.2)])
	_wall(1, 6.0, -3.85, 3.85, H, wall, [_win(0.0, 2.0, 1.0, 2.2)])
	_box(Vector3(0, F + H + 0.2, 0), Vector3(13.2, 0.4, 9.2), C_RED)    # roof slab
	_box(Vector3(0, F + H + 0.45, 4.5), Vector3(13.2, 0.6, 0.2), C_WHITE)  # fascia
	# Interior
	_box(Vector3(3.0, F + 0.55, -0.5), Vector3(3.6, 1.1, 0.8), C_FURN)  # counter
	_container("register", "gas_station", 3.0, -0.5, 0.0, F + 1.1)
	_container("shelf", "gas_station", -4.5, -3.55, 0.0)
	_container("shelf", "gas_station", -2.0, -3.55, 0.0)
	_container("shelf", "gas_station", 0.6, -3.55, 0.0)
	_container("fridge", "gas_station", -5.5, -2.6, PI * 0.5)
	_container("fridge", "gas_station", -5.5, 2.6, PI * 0.5)
	_scatter("gas_station", 4, -5.0, 5.0, -3.2, 3.2)
	# Food Kit dressing: counter clutter (counter top F+1.1) and litter on the floor
	_deco("soda-can.glb", 0.13, Vector3(1.7, F + 1.1, -0.35), 0.4)
	_deco("soda-can.glb", 0.13, Vector3(1.95, F + 1.1, -0.55), 1.2)
	_deco("plate.glb", 0.03, Vector3(2.2, F + 1.1, -0.3), 0.0)
	_deco("candy-bar.glb", 0.02, Vector3(2.2, F + 1.13, -0.3), 0.3)
	_deco("bottle-ketchup.glb", 0.2, Vector3(4.1, F + 1.1, -0.4), 0.0)
	_deco("mug.glb", 0.1, Vector3(4.45, F + 1.1, -0.6), 2.0)
	_deco("soda-can-crushed.glb", 0.1, Vector3(-1.2, F, 2.2), 0.7)
	_deco("can-open.glb", 0.11, Vector3(-3.4, F, 0.8), 1.9)
	_deco("plate-broken.glb", 0.025, Vector3(1.6, F, 2.6), 0.3)
	# Forecourt: slab, canopy, pumps
	_box(Vector3(0, F - 0.25, 11.0), Vector3(16.0, 0.5, 10.0), C_FLOOR_CONCRETE)
	for px in [-6.0, 6.0]:
		for pz in [8.0, 14.0]:
			_box(Vector3(px, F + 2.3, pz), Vector3(0.4, 4.6, 0.4), C_WHITE)
	_box(Vector3(0, F + 4.5, 11.0), Vector3(14.0, 0.25, 9.0), C_WHITE)
	_box(Vector3(0, F + 4.75, 11.0), Vector3(14.3, 0.25, 9.3), C_RED)
	for pxx in [-2.5, 2.5]:
		_box(Vector3(pxx, F + 0.1, 11.0), Vector3(1.2, 0.2, 4.5), Color(0.4, 0.4, 0.42))
		_box(Vector3(pxx, F + 0.95, 10.0), Vector3(0.6, 1.5, 0.5), C_RED)
		_box(Vector3(pxx, F + 0.95, 12.0), Vector3(0.6, 1.5, 0.5), C_WHITE)
	# Car wreck
	var rust := Color(0.5, 0.28, 0.18)
	_box(Vector3(-10.0, F + 0.7, 9.0), Vector3(4.2, 0.8, 1.8), rust)
	_box(Vector3(-10.4, F + 1.4, 9.0), Vector3(2.2, 0.7, 1.6), rust.darkened(0.2))
	for wx in [-11.5, -8.5]:
		for wz in [8.0, 10.0]:
			_box(Vector3(wx, F + 0.35, wz), Vector3(0.8, 0.7, 0.3), C_DARK)
	_container("toolbox", "gas_station", -7.0, 9.0, 0.0)
	_scatter("wild", 2, -12.0, 12.0, 6.0, 14.0)
	# Roadside sign
	_box(Vector3(9.5, F + 3.5, 6.0), Vector3(0.3, 7.0, 0.3), C_DARK)
	_box(Vector3(9.5, F + 6.6, 6.0), Vector3(3.0, 1.6, 0.3), C_YELLOW)
	_finish()


# ---------------------------------------------------------------- HOSPITAL

func build_hospital(root: Node3D) -> void:
	_begin(root)
	var H := 3.6
	var wall := Color(0.88, 0.9, 0.9)
	var accent := Color(0.3, 0.62, 0.65)
	_floor_slab(0, 0, 24.6, 16.6, Color(0.7, 0.78, 0.78))
	_wall(0, 8.0, -12.15, 12.15, H, wall, [
		_door(0.0, 3.2, 2.8), _win(-8.5, 1.8, 1.0, 2.4), _win(-5.0, 1.8, 1.0, 2.4),
		_win(5.0, 1.8, 1.0, 2.4), _win(8.5, 1.8, 1.0, 2.4)])
	_wall(0, -8.0, -12.15, 12.15, H, wall, [
		_win(-9.0, 1.8, 1.0, 2.4), _win(-3.0, 1.8, 1.0, 2.4), _win(3.0, 1.8, 1.0, 2.4), _win(9.0, 1.8, 1.0, 2.4)])
	_wall(1, -12.0, -7.85, 7.85, H, wall, [_win(-4.0, 1.8, 1.0, 2.4), _win(4.0, 1.8, 1.0, 2.4)])
	_wall(1, 12.0, -7.85, 7.85, H, wall, [_win(-4.0, 1.8, 1.0, 2.4), _win(4.0, 1.8, 1.0, 2.4)])
	# Partition between hall (z>0) and the four patient rooms (z<0)
	_wall(0, 0.0, -11.85, 11.85, H, accent, [_door(-9.0, 1.4), _door(-3.0, 1.4), _door(3.0, 1.4), _door(9.0, 1.4)], 0.25)
	for dx in [-6.0, 0.0, 6.0]:
		_wall(1, dx, -7.85, -0.125, H, accent, [], 0.25)
	_box(Vector3(0, F + H + 0.2, 0), Vector3(25.2, 0.4, 17.2), Color(0.5, 0.52, 0.55))
	# Rooftop red cross sign
	_box(Vector3(0, F + H + 2.2, 7.6), Vector3(3.0, 3.0, 0.3), C_WHITE)
	_box(Vector3(0, F + H + 2.2, 7.8), Vector3(0.8, 2.4, 0.2), C_RED)
	_box(Vector3(0, F + H + 2.2, 7.8), Vector3(2.4, 0.8, 0.2), C_RED)
	# Rooms: bed + medical cabinet
	for rx in [-9.0, -3.0, 3.0, 9.0]:
		_box(Vector3(rx + 1.8, F + 0.3, -3.5), Vector3(1.0, 0.6, 2.0), Color(0.85, 0.9, 0.92))
		_container("med_cabinet", "hospital", rx, -7.55, 0.0)
	_container("locker", "hospital", -11.55, -5.0, PI * 0.5)
	_container("med_cabinet", "hospital", 11.55, -5.0, -PI * 0.5)
	# Hall: reception desk, benches, locker
	_box(Vector3(-6.0, F + 0.55, 3.0), Vector3(4.0, 1.1, 0.9), C_FURN)
	for bx2 in [4.0, 8.0]:
		_box(Vector3(bx2, F + 0.25, 3.5), Vector3(2.2, 0.5, 0.6), C_DARK.lightened(0.2))
	_container("locker", "hospital", -2.8, 7.5, PI)
	_scatter("hospital", 4, -11.0, 11.0, 1.0, 7.0)
	_scatter("hospital", 4, -11.0, 11.0, -7.0, -1.0)
	# Ambulance out front
	_box(Vector3(-8.0, F + 1.0, 14.0), Vector3(5.0, 1.5, 2.2), C_WHITE)
	_box(Vector3(-5.0, F + 0.9, 14.0), Vector3(1.6, 1.2, 2.0), C_WHITE.darkened(0.1))
	_box(Vector3(-8.0, F + 1.3, 14.0), Vector3(5.02, 0.35, 2.22), C_RED)
	for wx in [-9.5, -6.0]:
		for wz in [13.0, 15.0]:
			_box(Vector3(wx, F + 0.35, wz), Vector3(0.8, 0.7, 0.3), C_DARK)
	_finish()


# ---------------------------------------------------------------- POLICE STATION

func build_police_station(root: Node3D) -> void:
	_begin(root)
	var H := 3.4
	var wall := Color(0.62, 0.66, 0.72)
	var inner := Color(0.78, 0.8, 0.82)
	var blue := Color(0.12, 0.2, 0.45)
	_floor_slab(0, 0, 16.6, 10.6, C_FLOOR_CONCRETE)
	_wall(0, 5.0, -8.15, 8.15, H, wall, [_door(0.0, 2.0, 2.6), _win(-4.5), _win(4.5)])
	_wall(0, -5.0, -8.15, 8.15, H, wall, [_win(-4.5, 1.0, 2.0, 2.6), _win(4.5, 1.0, 2.0, 2.6)])
	_wall(1, -8.0, -4.85, 4.85, H, wall, [_win(3.0)])
	_wall(1, 8.0, -4.85, 4.85, H, wall, [_door(2.5, 1.4), _win(-3.0, 1.0, 2.0, 2.6)])
	# Partition: lobby (z > -1) in front, two cells and a central armory behind
	_wall(0, -1.0, -7.85, 7.85, H, inner, [_door(-4.5, 1.4), _door(0.0, 1.2), _door(4.5, 1.4)], 0.2)
	_wall(1, -2.0, -4.85, -1.1, H, inner, [], 0.2)
	_wall(1, 2.0, -4.85, -1.1, H, inner, [], 0.2)
	_box(Vector3(0, F + H + 0.2, 0), Vector3(16.8, 0.4, 10.8), Color(0.3, 0.32, 0.36))
	_box(Vector3(0, F + H + 0.95, 5.2), Vector3(6.0, 1.1, 0.2), blue)
	_box(Vector3(0, F + H + 0.95, 5.32), Vector3(5.4, 0.3, 0.05), C_WHITE, false)
	# Lobby
	_box(Vector3(0, F + 0.55, 2.0), Vector3(5.0, 1.1, 0.9), C_FURN)
	_container("register", "police", -1.0, 2.0, 0.0, F + 1.1)
	_container("locker", "police", -7.55, 0.5, PI * 0.5)
	_container("locker", "police", -7.55, 4.3, PI * 0.5)
	_container("shelf", "police", -2.4, -0.55, 0.0)
	_container("shelf", "police", 2.4, -0.55, 0.0)
	for bx in [-6.0, 6.0]:
		_box(Vector3(bx, F + 0.25, 4.4), Vector3(2.4, 0.5, 0.6), C_DARK.lightened(0.2))
	_scatter("police", 3, -6.5, 6.5, 2.7, 3.4)
	# Armory
	_container("weapon_rack", "police", -0.95, -4.6, 0.0)
	_container("weapon_rack", "police", 0.95, -4.6, 0.0)
	_container("evidence_locker", "police", -1.65, -2.5, PI * 0.5)
	_container("evidence_locker", "police", 1.65, -2.5, -PI * 0.5)
	# Cells
	_box(Vector3(-6.8, F + 0.25, -3.8), Vector3(1.8, 0.5, 0.8), Color(0.6, 0.6, 0.62))
	_box(Vector3(6.8, F + 0.25, -3.8), Vector3(1.8, 0.5, 0.8), Color(0.6, 0.6, 0.62))
	_container("crate", "police", -3.2, -4.2, 0.4)
	_container("locker", "police", 7.45, -2.2, -PI * 0.5)
	_scatter("police", 1, -7.4, -2.6, -4.4, -1.6)
	_scatter("police", 1, 2.6, 7.4, -4.4, -1.6)
	# Parking lot, cars, flag, dumpster, chain-link fence
	_box(Vector3(0, F - 0.25, 10.5), Vector3(22.0, 0.5, 11.0), Color(0.25, 0.25, 0.27))
	for i in 7:
		_box(Vector3(-9.0 + float(i) * 3.0, F + 0.01, 11.0), Vector3(0.12, 0.02, 4.0), C_WHITE, false)
	_car(Vector3(-7.5, F, 11.0), PI * 0.5, "police", 0)
	_car(Vector3(-4.5, F, 11.0), PI * 0.5, "police", 1)
	_car(Vector3(4.5, F, 11.0), PI * 0.5, "sedan", 2)
	_cyl(Vector3(10.0, F, 7.0), 0.08, 9.0, 6, C_WHITE)
	_box(Vector3(10.7, F + 8.2, 7.0), Vector3(1.4, 0.9, 0.03), Color(0.7, 0.1, 0.12), false)
	_box(Vector3(12.0, F + 0.6, -8.0), Vector3(2.2, 1.2, 1.2), Color(0.18, 0.32, 0.2))
	_fence_rect(-16.0, -12.0, 16.0, 18.0, 6.0, C_FENCE_METAL, 2.0)
	_finish()


# ---------------------------------------------------------------- WAREHOUSE

## Steel shelving run along X at depth z: uprights, planks, seeded crates. One collision box for the run.
func _rack_run(x0: float, x1: float, z: float, levels: int = 4) -> void:
	var steel := Color(0.25, 0.35, 0.6)
	var plank := Color(0.85, 0.55, 0.15)
	var n: int = maxi(int(round((x1 - x0) / 2.0)), 1)
	var step: float = (x1 - x0) / float(n)
	for i in n + 1:
		var x: float = x0 + step * float(i)
		_box(Vector3(x, F + 2.2, z - 0.4), Vector3(0.1, 4.4, 0.1), steel, false)
		_box(Vector3(x, F + 2.2, z + 0.4), Vector3(0.1, 4.4, 0.1), steel, false)
	for l in levels:
		var y: float = F + 0.15 + float(l) * 1.4
		_box(Vector3((x0 + x1) * 0.5, y, z), Vector3(x1 - x0, 0.08, 0.9), plank, false)
		for row in HandMapData.for_loc("RACK", _loc):
			var r: Array = row
			if absf(float(r[3]) - z) > 0.002 or absf(float(r[2]) - y) > 0.002 or float(r[1]) < x0 or float(r[1]) > x1:
				continue
			var shade: float = float(r[6])
			_box(Vector3(float(r[1]), y + 0.04 + float(r[5]) * 0.5, z), Vector3(float(r[4]), float(r[5]), 0.7), Color(0.6 * shade, 0.45 * shade, 0.25 * shade), false)
	_solid(Vector3((x0 + x1) * 0.5, F + 2.2, z), Vector3(x1 - x0, 4.4, 0.9))


func build_warehouse(root: Node3D) -> void:
	_begin(root)
	var H := 7.0
	var wall := Color(0.6, 0.62, 0.64)
	_floor_slab(0, 0, 25.0, 17.0, C_FLOOR_CONCRETE)
	_wall(0, 8.0, -12.15, 12.15, H, wall, [_door(-8.0, 1.6, 2.6), _door(4.0, 5.0, 4.2)])
	_wall(0, -8.0, -12.15, 12.15, H, wall, [_win(-6.0, 3.0, 4.5, 5.8), _win(0.0, 3.0, 4.5, 5.8), _door(9.0, 1.6, 2.6)])
	_wall(1, -12.0, -7.85, 7.85, H, wall, [_win(-3.0, 3.0, 4.5, 5.8), _win(3.0, 3.0, 4.5, 5.8)])
	_wall(1, 12.0, -7.85, 7.85, H, wall, [_win(-3.0, 3.0, 4.5, 5.8), _win(3.0, 3.0, 4.5, 5.8)])
	_gable_roof(0, 0, 12.6, 8.6, F + H, 2.4, Color(0.32, 0.34, 0.38), wall.darkened(0.1))
	# Shelving along the back wall and two rack runs
	for i in 6:
		_container("shelf", "warehouse", -10.0 + float(i) * 2.0, -7.55, 0.0)
	_rack_run(-9.0, 5.0, -3.5)
	_rack_run(-9.0, 5.0, 1.0)
	_container("pallet_crate", "warehouse", 8.5, -3.0, 0.3)
	_container("pallet_crate", "warehouse", 10.2, -2.0, -0.2)
	_container("crate", "warehouse", -10.5, 5.5, 0.6)
	_container("toolbox", "warehouse", 10.5, 5.5, PI)
	_box(Vector3(10.5, F + 0.6, 6.5), Vector3(1.2, 1.2, 1.2), Color(0.6, 0.45, 0.25))
	_box(Vector3(10.5, F + 1.8, 6.5), Vector3(1.0, 1.2, 1.0), Color(0.55, 0.42, 0.22))
	_scatter("warehouse", 3, -8.5, 5.5, -2.8, 0.3)
	_scatter("warehouse", 2, 6.5, 11.0, 0.0, 2.5)
	# Loading yard: slab, box truck at the dock, wrecks, shipping containers, chain-link fence
	_box(Vector3(0, F - 0.25, 13.0), Vector3(30.0, 0.5, 10.0), Color(0.3, 0.3, 0.32))
	_car(Vector3(4.0, F, 13.5), -PI * 0.5, "truck", 0)
	_car(Vector3(-14.0, F, 13.0), 0.3, "van", 2)
	_car(Vector3(10.0, F, 15.5), PI, "pickup", 1)
	var cont_cols: Array = [Color(0.65, 0.2, 0.15), Color(0.2, 0.35, 0.6), Color(0.25, 0.5, 0.35), Color(0.75, 0.55, 0.15)]
	var wh_rows: Array = HandMapData.for_loc("WH_COL", _loc)
	var wh: Array = wh_rows[0] as Array if not wh_rows.is_empty() else [_loc, 0, 1, 2]
	var c0: Color = cont_cols[int(wh[1])]
	var c1: Color = cont_cols[int(wh[2])]
	var c2: Color = cont_cols[int(wh[3])]
	_box(Vector3(-16.5, F + 1.3, -4.0), Vector3(2.4, 2.6, 6.0), c0)
	_box(Vector3(-16.5, F + 3.9, -4.0), Vector3(2.4, 2.6, 6.0), c1)
	_box(Vector3(-16.5, F + 1.3, 3.0), Vector3(2.4, 2.6, 6.0), c2)
	_fence_rect(-19.0, -14.0, 19.0, 18.0, 6.0, C_FENCE_METAL, 2.0)
	_finish()


# ---------------------------------------------------------------- CHURCH

func build_church(root: Node3D) -> void:
	_begin(root)
	var H := 5.0
	var wall := Color(0.86, 0.84, 0.78)
	var stone := Color(0.55, 0.55, 0.57)
	var roof := Color(0.3, 0.22, 0.2)
	var tile := Color(0.6, 0.55, 0.5)
	_floor_slab(0, 0, 18.6, 9.6, tile)
	_floor_slab(-10.5, 0, 3.6, 6.6, tile)
	var glass: Array = [Color(0.2, 0.35, 0.8), Color(0.75, 0.2, 0.25), Color(0.85, 0.7, 0.2), Color(0.25, 0.6, 0.4)]
	var win_c: Array = [-6.0, -2.0, 2.0, 6.0]
	var wins: Array = []
	for c in win_c:
		wins.append(_win(float(c), 1.2, 1.5, 3.8))
	_wall(0, -4.5, -9.15, 9.15, H, wall, wins)
	_wall(0, 4.5, -9.15, 9.15, H, wall, wins)
	_wall(1, 9.0, -4.35, 4.35, H, wall, [_win(0.0, 1.4, 2.0, 4.2)])
	_wall(1, -9.0, -4.35, 4.35, H, wall, [_door(0.0, 2.2, 2.8)])
	_gable_roof(0, 0, 9.4, 4.8, F + H, 2.8, roof, wall)
	for i in win_c.size():
		for zs in [-4.5, 4.5]:
			_box(Vector3(float(win_c[i]), F + 2.65, float(zs)), Vector3(1.2, 2.3, 0.06), glass[i] as Color, false)
	# Vestibule with a bell tower and spire above it
	_wall(0, -3.0, -12.15, -8.85, H, stone)
	_wall(0, 3.0, -12.15, -8.85, H, stone)
	_wall(1, -12.0, -2.85, 2.85, H, stone, [_door(0.0, 2.0, 2.6)])
	_box(Vector3(-10.5, F + H + 0.2, 0.0), Vector3(3.6, 0.4, 6.6), roof)
	_box(Vector3(-10.5, F + H + 3.2, 0.0), Vector3(2.4, 5.6, 2.4), stone)
	for lv in [Vector3(-10.5, 0, 1.22), Vector3(-10.5, 0, -1.22), Vector3(-9.28, 0, 0), Vector3(-11.72, 0, 0)]:
		var sz: Vector3 = Vector3(0.9, 1.4, 0.04) if absf(lv.z) > 0.5 else Vector3(0.04, 1.4, 0.9)
		_box(Vector3(lv.x, F + H + 4.6, lv.z), sz, C_DARK, false)
	_box(Vector3(-10.5, F + H + 11.1, 0.0), Vector3(0.14, 1.2, 0.14), C_WHITE, false)
	_box(Vector3(-10.5, F + H + 11.3, 0.0), Vector3(0.14, 0.14, 0.7), C_WHITE, false)
	# Pews either side of the aisle
	for i in 5:
		var px: float = -6.5 + float(i) * 2.0
		for sz in [-1.0, 1.0]:
			_box(Vector3(px, F + 0.25, 2.4 * sz), Vector3(0.6, 0.5, 2.8), C_FURN)
			_box(Vector3(px - 0.3, F + 0.85, 2.4 * sz), Vector3(0.1, 0.9, 2.8), C_FURN.darkened(0.2))
	# Altar end
	_box(Vector3(7.0, F + 0.075, 0.0), Vector3(4.0, 0.15, 7.0), Color(0.5, 0.4, 0.3), false)
	_box(Vector3(8.3, F + 0.7, 0.0), Vector3(0.9, 1.1, 2.4), C_WHITE)
	_box(Vector3(8.8, F + 3.6, 0.0), Vector3(0.1, 1.6, 0.2), Color(0.45, 0.3, 0.15), false)
	_box(Vector3(8.8, F + 3.9, 0.0), Vector3(0.1, 0.2, 0.9), Color(0.45, 0.3, 0.15), false)
	_container("altar_chest", "church", 7.2, 0.0, -PI * 0.5, F + 0.15)
	_container("donation_box", "church", -10.5, -2.6, 0.0)
	_container("cupboard", "church", 3.6, -4.1, 0.0)
	_container("cupboard", "church", 4.6, -4.1, 0.0)
	_container("locker", "church", -6.5, 4.05, PI)
	_scatter("church", 3, -8.0, 4.0, -0.7, 0.7)
	_scatter("church", 1, -11.5, -9.5, -2.0, 2.0)
	# Graveyard: seeded headstones with earth mounds, iron fence, a wrecked sedan outside
	for row in HandMapData.for_loc("CH_STONE", _loc):
		var r: Array = row
		var gxf := Transform3D(Basis(Vector3.UP, float(r[3])), Vector3(float(r[1]), F, float(r[2])))
		_model_at(GY + "gravestone-bevel.glb", gxf, Vector3(0, 0.45, 0), Vector3(0.7, 0.9, 0.3))
		PropFactory.add_collision(_body, gxf, Vector3(0, 0.45, 0), Vector3(0.7, 0.9, 0.16))
	_fence_rect(-15.0, 6.5, 15.0, 18.5, 4.0, C_FENCE_IRON, 1.4)
	_car(Vector3(14.0, F, -9.0), 0.4, "sedan", 1)
	_finish()
