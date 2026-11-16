extends RefCounted
## A KayKit Dungeon Pack dungeon sunk into a crater in the Dead Acres countryside, entered by stairs from a ruined surface gate.
## (Terrain is one heightfield, so "underground" is a crater: the whole footprint is flattened to floor level, cliffs ring it,
## the building is roofed at 4 m and the stairs run down from the rim into the yard north of the entrance.)
##
## Hook (one call from world_builder.build, right after _plan_locations and BEFORE terrain.build_chunks):
##   DungeonBuilder.attach(self)
## attach() picks a deterministic site away from roads and buildings, flattens a plateau and carves the entrance pit
## into the terrain (terrain.add_flat), and queues the build for the world's `built` signal. It also queues the
## KayKit resource scatter (kaykit_resources.gd). Everything is seeded from world.world_seed, so every peer
## builds the identical dungeon and identical loot ids.
##
## Layout (4 m grid, 9 x 9 cells, hand laid; see ROOMS / CORRIDORS / DOORS):
##   stairs (two stairs_long pieces, 8 m down) -> antechamber -> corridor -> great hall, which has corridors to the
##   armory (-> storeroom) and the library (-> barracks) and a south corridor to the vault (boss and treasure room).
## Collision: one floor slab and one ceiling slab over the footprint, box colliders per wall / doorway frame / prop,
## a ramp plus side rails over the stairs. Walls, floors and props are on collision layer 1.
## Guard spawn points: Marker3D nodes in group "dungeon_skeleton_spawn" with meta "type" (warrior / minion /
## rogue / mage), "room", and "boss" = true on the vault boss.
## Result: world has a "Dungeon" child node; its meta "stats" holds counts, meta "site" the site dictionary.

const SELF_PATH := "res://scripts/world/dungeon_builder.gd"
const KayKitRes = preload("res://scripts/world/kaykit_resources.gd")
const ModelUtil = preload("res://scripts/world/model_util.gd")
const DungeonContainer = preload("res://scripts/world/dungeon_container.gd")
const DungeonDoor = preload("res://scripts/world/dungeon_door.gd")
const DUN := KayKitRes.DUN
const RES := KayKitRes.RES

const U := 4.0               # cell size = wall width
const COLS := 9
const ROWS := 9
const WALL_H := 4.0
const FLOOR_TOP := 0.05      # walkable surface above a floor tile's origin
const DEPTH := 8.0           # dungeon floor sits this far below the surface plateau
const PLATEAU_R := 34.0
const PLATEAU_BLEND := 22.0
const CRATER_R := 27.0       # flat crater floor: covers the 36 x 36 footprint (corner distance 25.5)
const CRATER_BLEND := 5.0
const SITE_LIMIT := 150.0
const ENTRY := Vector2i(4, 0)

const FACE_S := Vector2(0, 1)    # object front points +z
const FACE_N := Vector2(0, -1)
const FACE_E := Vector2(1, 0)
const FACE_W := Vector2(-1, 0)

## Rooms as inclusive cell rectangles (col c0..c1, row r0..r1).
const ROOMS := {
	"antechamber": {"c0": 3, "c1": 5, "r0": 0, "r1": 1},
	"hall": {"c0": 3, "c1": 5, "r0": 3, "r1": 5},
	"armory": {"c0": 0, "c1": 1, "r0": 3, "r1": 4},
	"library": {"c0": 7, "c1": 8, "r0": 3, "r1": 4},
	"storeroom": {"c0": 0, "c1": 1, "r0": 6, "r1": 7},
	"barracks": {"c0": 7, "c1": 8, "r0": 6, "r1": 7},
	"vault": {"c0": 2, "c1": 6, "r0": 7, "r1": 8},
}
const CORRIDORS := [Vector2i(4, 2), Vector2i(2, 4), Vector2i(6, 4), Vector2i(4, 6), Vector2i(0, 5), Vector2i(8, 5)]
## Cell pairs joined by a doorway (every corridor touches exactly two rooms).
const DOORS := [
	[Vector2i(4, 1), Vector2i(4, 2)], [Vector2i(4, 2), Vector2i(4, 3)],
	[Vector2i(1, 4), Vector2i(2, 4)], [Vector2i(2, 4), Vector2i(3, 4)],
	[Vector2i(5, 4), Vector2i(6, 4)], [Vector2i(6, 4), Vector2i(7, 4)],
	[Vector2i(4, 5), Vector2i(4, 6)], [Vector2i(4, 6), Vector2i(4, 7)],
	[Vector2i(0, 4), Vector2i(0, 5)], [Vector2i(0, 5), Vector2i(0, 6)],
	[Vector2i(8, 4), Vector2i(8, 5)], [Vector2i(8, 5), Vector2i(8, 6)],
]
const ROOM_FLOOR := {
	"library": "floor_wood_large.gltf", "barracks": "floor_wood_large.gltf", "storeroom": "floor_dirt_large.gltf",
}
## Wall pieces replaced by another model: "H|V,col,row" of the edge's second cell.
const WALL_OVERRIDE := {"H,7,3": "wall_shelves.gltf", "H,8,3": "wall_shelves.gltf"}

static var _cell_region: Dictionary = {}

var stats: Dictionary = {"walls": 0, "doors": 0, "props": 0, "lights": 0, "containers": 0, "chests": 0,
	"gold_chests": 0, "markers": 0, "pickups": 0, "missing": 0}
var containers: Array = []
var markers: Array = []
var doors: Array = []

var _world: Node
var _site: Dictionary
var _root: Node3D
var _body: StaticBody3D
var _rng := RandomNumberGenerator.new()
var _aabbs: Dictionary = {}
var _room: String = ""
var F: float = 0.0
var gx: float = 0.0
var gz: float = 0.0
var ox: float = 0.0
var h0: float = 0.0


# ------------------------------------------------------------------ layout (static, no world needed)

static func cells() -> Dictionary:
	if _cell_region.is_empty():
		for rid in ROOMS:
			var rm: Dictionary = ROOMS[rid]
			for r in range(int(rm["r0"]), int(rm["r1"]) + 1):
				for c in range(int(rm["c0"]), int(rm["c1"]) + 1):
					_cell_region[Vector2i(c, r)] = str(rid)
		var i := 0
		for cc in CORRIDORS:
			_cell_region[cc] = "corridor_%d" % i
			i += 1
	return _cell_region


static func region_of(v: Vector2i) -> String:
	return str(cells().get(v, ""))


static func has_door(a: Vector2i, b: Vector2i) -> bool:
	for d in DOORS:
		if (d[0] == a and d[1] == b) or (d[0] == b and d[1] == a):
			return true
	return false


## "none" (both empty), "open" (same region, or the stair entrance), "door" or "wall".
static func edge_kind(a: Vector2i, b: Vector2i) -> String:
	var above := Vector2i(ENTRY.x, ENTRY.y - 1)
	if (a == above and b == ENTRY) or (b == above and a == ENTRY):
		return "open"
	var ra: String = region_of(a)
	var rb: String = region_of(b)
	if ra == "" and rb == "":
		return "none"
	if ra == rb:
		return "open"
	if ra != "" and rb != "" and has_door(a, b):
		return "door"
	return "wall"


## Cells reachable on foot from the entrance cell (through open edges and doorways).
static func reachable_cells() -> Array:
	var seen := {ENTRY: true}
	var queue: Array = [ENTRY]
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: Vector2i = cur + d
			if seen.has(nx) or not cells().has(nx):
				continue
			var k: String = edge_kind(cur, nx)
			if k == "open" or k == "door":
				seen[nx] = true
				queue.append(nx)
	return seen.keys()


## World position (floor level) of a cell-unit coordinate for a site: c, r are in cells (4.5, 4.5 = hall centre).
static func cell_pos(site: Dictionary, c: float, r: float) -> Vector3:
	return Vector3(float(site["gx"]) + c * U, float(site["floor_y"]) + FLOOR_TOP, float(site["gz"]) + r * U)


# ------------------------------------------------------------------ site planning and hook

static func attach(world: Node) -> void:
	var site: Dictionary = plan_site(world)
	world.set_meta("dungeon_site", site)
	KayKitRes.attach(world)
	var script: GDScript = load(SELF_PATH)
	world.built.connect(func(): script.new(world, site).build())


static func _clearance(terrain, p: Vector2) -> float:
	var best: float = terrain.road_distance(p.x, p.y) - 3.2
	for i in terrain.flat_pos.size():
		best = minf(best, p.distance_to(terrain.flat_pos[i]) - float(terrain.flat_radius[i]))
	return best


## Picks the site (flat, far from roads, pads and the spawn) and carves the plateau and entrance pit.
## Must run before terrain.build_chunks.
static func plan_site(world: Node) -> Dictionary:
	var terrain = world.terrain
	var rng := RandomNumberGenerator.new()
	rng.seed = (int(world.world_seed) ^ 0xD06E) & 0x7FFFFFFF
	var best := Vector2(120.0, 120.0)
	var best_score := -1.0e9
	var best_clear := 0.0
	for _i in 3000:
		var p := Vector2(rng.randf_range(-SITE_LIMIT, SITE_LIMIT), rng.randf_range(-SITE_LIMIT, SITE_LIMIT))
		if p.length() < 80.0:
			continue
		var clear: float = _clearance(terrain, p)
		var hc: float = terrain.height_at(p.x, p.y)
		var dev := 0.0
		for k in 12:
			var a: float = TAU * float(k) / 12.0
			var rr: float = 30.0 if k % 2 == 0 else 15.0
			dev = maxf(dev, absf(terrain.height_at(p.x + cos(a) * rr, p.y + sin(a) * rr) - hc))
		var score: float = minf(clear, 60.0) - 3.0 * dev
		if score > best_score:
			best_score = score
			best = p
			best_clear = clear
	var h: float = terrain.height_at(best.x, best.y)
	var site := {
		"origin": best, "h0": h, "floor_y": h - DEPTH, "gx": best.x - 18.0, "gz": best.y - 8.0, "clearance": best_clear,
	}
	terrain.add_flat(best, PLATEAU_R, PLATEAU_BLEND, h)
	# crater: flat at dungeon-floor level around the whole footprint (centre = footprint centre)
	terrain.add_flat(Vector2(best.x, float(site["gz"]) + 18.0), CRATER_R, CRATER_BLEND, h - DEPTH)
	# support under the upper stair piece (its base sits 4 m below the rim)
	terrain.add_flat(Vector2(best.x, float(site["gz"]) - 12.5), 3.6, 2.0, h - 4.0)
	return site


# ------------------------------------------------------------------ build

func _init(world: Node, site: Dictionary) -> void:
	_world = world
	_site = site
	F = float(site["floor_y"])
	gx = float(site["gx"])
	gz = float(site["gz"])
	h0 = float(site["h0"])
	ox = (site["origin"] as Vector2).x
	_rng.seed = (int(world.world_seed) * 7919 + 0xD0) & 0x7FFFFFFF


func build() -> Node3D:
	_root = Node3D.new()
	_root.name = "Dungeon"
	_world.add_child(_root)
	_body = StaticBody3D.new()
	_body.name = "Collision"
	_root.add_child(_body)
	_build_shell()
	_build_stairs()
	_build_surface()
	_decorate()
	_root.set_meta("stats", stats)
	_root.set_meta("site", _site)
	print("[Dungeon] site=(%.0f, %.0f) h0=%.1f floor=%.1f clearance=%.0f %s" % [
		ox, gz + 8.0, h0, F, float(_site.get("clearance", 0.0)), str(stats)])
	return _root


func _cp(c: float, r: float, y: float = 0.0) -> Vector3:
	return Vector3(gx + c * U, F + FLOOR_TOP + y, gz + r * U)


func _aabb(path: String) -> AABB:
	if _aabbs.has(path):
		return _aabbs[path]
	var out := AABB()
	var ps := load(path) as PackedScene
	if ps != null:
		var inst := ps.instantiate()
		var boxes: Array = []
		ModelUtil._collect(inst, Transform3D.IDENTITY, boxes)
		if not boxes.is_empty():
			out = boxes[0]
			for i in range(1, boxes.size()):
				out = out.merge(boxes[i])
		inst.free()
	_aabbs[path] = out
	return out


func _count(key: String, n: int = 1) -> void:
	stats[key] = int(stats[key]) + n


## Puts a model in the dungeon. file is a Dungeon Pack gltf name or a full res:// path. solid adds a box collider
## fitted to the model's bounding box.
func _place(file: String, pos: Vector3, yaw: float = 0.0, sc: float = 1.0, solid: bool = true) -> Node3D:
	var path: String = file if file.begins_with("res://") else DUN + file
	var ps := load(path) as PackedScene
	if ps == null:
		_count("missing")
		push_warning("[Dungeon] missing model %s" % path)
		return null
	var inst := ps.instantiate() as Node3D
	inst.position = pos
	inst.rotation.y = yaw
	inst.scale = Vector3(sc, sc, sc)
	_root.add_child(inst)
	if solid:
		var bb: AABB = _aabb(path)
		_box(bb.size * sc, pos + Basis(Vector3.UP, yaw) * (bb.get_center() * sc), yaw)
	_count("props")
	return inst


func _box(size: Vector3, center: Vector3, yaw: float) -> void:
	_box_xf(size, Transform3D(Basis(Vector3.UP, yaw), center))


func _box_xf(size: Vector3, xf: Transform3D) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.transform = xf
	_body.add_child(cs)


## Box collider given in a model's local frame (x along the wall, y up).
func _box_local(size: Vector3, local: Vector3, origin: Vector3, yaw: float) -> void:
	_box(size, origin + Basis(Vector3.UP, yaw) * local, yaw)


# ------------------------------------------------------------------ shell: floor, ceiling, walls

func _floor_file(room: String) -> String:
	var f: String = str(ROOM_FLOOR.get(room, "floor_tile_large.gltf"))
	var bb: AABB = _aabb(DUN + f)
	if absf(bb.size.x - U) > 0.1 or absf(bb.size.z - U) > 0.1:
		return "floor_tile_large.gltf"
	return f


func _build_shell() -> void:
	var span: float = U * float(COLS)
	_box(Vector3(span, 0.5, span), Vector3(gx + span * 0.5, F + FLOOR_TOP - 0.25, gz + span * 0.5), 0.0)
	# roof collider only over occupied cells (merged per row), so the open yard has no invisible ceiling
	for r in ROWS:
		var c := 0
		while c < COLS:
			if not cells().has(Vector2i(c, r)):
				c += 1
				continue
			var c1 := c
			while c1 + 1 < COLS and cells().has(Vector2i(c1 + 1, r)):
				c1 += 1
			var w: float = float(c1 - c + 1) * U
			_box(Vector3(w, 0.5, U), Vector3(gx + float(c) * U + w * 0.5, F + WALL_H + 0.25, gz + (float(r) + 0.5) * U), 0.0)
			c = c1 + 1
	for k in cells().keys():
		var cv: Vector2i = k
		var file: String = _floor_file(region_of(cv))
		var bb: AABB = _aabb(DUN + file)
		var cx: float = gx + (float(cv.x) + 0.5) * U
		var cz: float = gz + (float(cv.y) + 0.5) * U
		_place(file, Vector3(cx - bb.get_center().x, F + FLOOR_TOP - (bb.position.y + bb.size.y), cz - bb.get_center().z), 0.0, 1.0, false)
		_place("ceiling_tile.gltf", Vector3(cx, F + WALL_H + 0.25, cz), 0.0, 1.0, false)
	for r in range(0, ROWS + 1):
		for c in COLS:
			_edge(Vector2i(c, r - 1), Vector2i(c, r), true)
	for c in range(0, COLS + 1):
		for r in ROWS:
			_edge(Vector2i(c - 1, r), Vector2i(c, r), false)


func _edge(a: Vector2i, b: Vector2i, horiz: bool) -> void:
	var kind: String = edge_kind(a, b)
	if kind == "none" or kind == "open":
		return
	var center: Vector3
	var yaw: float
	if horiz:
		center = Vector3(gx + (float(b.x) + 0.5) * U, F, gz + float(b.y) * U)
		yaw = 0.0
	else:
		center = Vector3(gx + float(b.x) * U, F, gz + (float(b.y) + 0.5) * U)
		yaw = PI * 0.5
	if kind == "door":
		var frame := _place("wall_doorway.gltf", center, yaw, 1.0, false)
		_door(frame, center, yaw)
		# frame: two side pillars and a lintel; the opening is 2.0 m wide and 2.8 m high (the model's arch is 2.86 m)
		_box_local(Vector3(1.0, WALL_H, 1.0), Vector3(-1.5, WALL_H * 0.5, 0), center, yaw)
		_box_local(Vector3(1.0, WALL_H, 1.0), Vector3(1.5, WALL_H * 0.5, 0), center, yaw)
		_box_local(Vector3(2.0, WALL_H - 2.8, 1.0), Vector3(0, 2.8 + (WALL_H - 2.8) * 0.5, 0), center, yaw)
		_count("doors")
		return
	var key: String = "%s,%d,%d" % ["H" if horiz else "V", b.x, b.y]
	var file: String = str(WALL_OVERRIDE.get(key, ""))
	if file == "":
		file = "wall_cracked.gltf" if _rng.randf() < 0.2 else "wall.gltf"
	_place(file, center, yaw, 1.0, true)
	_count("walls")


## An openable door in a doorway: takes the leaf mesh out of the placed doorway model and adds the collider.
## Named Door_N in build order, so the node path is the same on every peer (the RPCs need that).
func _door(frame: Node3D, center: Vector3, yaw: float) -> void:
	var d := DungeonDoor.new()
	d.name = "Door_%d" % int(stats["doors"])
	d.position = center
	d.rotation.y = yaw
	_root.add_child(d)
	var leaf: Node3D = null
	if frame != null:
		leaf = frame.find_child("wall_doorway_door", true, false) as Node3D
	d.setup(leaf)
	doors.append(d)


# ------------------------------------------------------------------ stairs and surface ruin

func _build_stairs() -> void:
	_place("stairs_long.gltf", Vector3(ox, F + 4.0, gz - 16.0), 0.0, 1.0, false)
	_place("stairs_long.gltf", Vector3(ox, F, gz - 8.0), 0.0, 1.0, false)
	# one continuous ramp through the tread centres (0.5 m rise per 1 m run) from the landing to the antechamber floor
	var za: float = gz - 15.6
	var ya: float = F + FLOOR_TOP + 8.0
	var zb: float = gz + 0.4
	var yb: float = F + FLOOR_TOP
	var v := Vector3(0.0, yb - ya, zb - za)
	var slope_len: float = v.length()
	var t: Vector3 = v / slope_len
	var n := Vector3(0.0, t.z, -t.y)
	var basis := Basis(Vector3.RIGHT, n, t)
	var mid := Vector3(ox, (ya + yb) * 0.5, (za + zb) * 0.5)
	_box_xf(Vector3(4.0, 0.5, slope_len), Transform3D(basis, mid - n * 0.25))
	for side in [-1.0, 1.0]:
		_box_xf(Vector3(0.5, 3.0, slope_len), Transform3D(basis, mid + n * 1.5 + Vector3(side * 2.25, 0.0, 0.0)))
	# a lamp on the way down
	_light(Vector3(ox, F + 3.4, gz - 3.0), 1.2, 10.0)


func _build_surface() -> void:
	var y: float = h0
	var tile: AABB = _aabb(DUN + "floor_tile_large.gltf")
	for i in 3:
		var cx: float = ox + (float(i) - 1.0) * U
		_place("floor_tile_large.gltf", Vector3(cx - tile.get_center().x, y + FLOOR_TOP - (tile.position.y + tile.size.y), gz - 18.0 - tile.get_center().z), 0.0, 1.0, false)
	_box(Vector3(12.0, 0.3, 4.4), Vector3(ox, y + FLOOR_TOP - 0.15, gz - 17.8), 0.0)
	var broken: int = _rng.randi_range(0, 3)
	var corners: Array = [Vector2(-6.0, -20.0), Vector2(6.0, -20.0), Vector2(-6.0, -16.0), Vector2(6.0, -16.0)]
	for i in corners.size():
		var cp: Vector2 = corners[i]
		_place("column.gltf" if i == broken else "pillar.gltf", Vector3(ox + cp.x, y, gz + cp.y), 0.0, 1.0, true)
	_place("wall_broken.gltf", Vector3(ox - 6.0, y, gz - 18.0), PI * 0.5, 1.0, true)
	_place("wall_broken.gltf", Vector3(ox + 6.0, y, gz - 18.0), PI * 0.5, 1.0, true)
	_place("wall_broken.gltf", Vector3(ox - 4.0, y, gz - 16.0), 0.0, 1.0, true)
	_place("wall_broken.gltf", Vector3(ox + 4.0, y, gz - 16.0), 0.0, 1.0, true)
	# gate pillars on the approach side with torches
	for sx in [-2.5, 2.5]:
		_place("pillar_decorated.gltf", Vector3(ox + sx, y, gz - 20.0), 0.0, 1.0, true)
		_place("torch_mounted.gltf", Vector3(ox + sx, y + 2.0, gz - 20.75), PI, 1.0, false)
	_place("rubble_large.gltf", Vector3(ox - 10.0, y, gz - 18.0), 0.6, 0.45, false)
	_place("rubble_large.gltf", Vector3(ox + 10.0, y, gz - 17.0), -0.8, 0.4, false)
	_place("banner_red.gltf", Vector3(ox - 6.0, y + 0.4, gz - 18.0 + 0.0), PI * 0.5, 1.0, false)


# ------------------------------------------------------------------ decoration helpers

func _yaw(face: Vector2) -> float:
	return atan2(face.x, face.y)


func _light(pos: Vector3, energy: float, rng_m: float) -> void:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = Color(1.0, 0.62, 0.3)
	l.light_energy = energy
	l.omni_range = rng_m
	l.shadow_enabled = false
	_root.add_child(l)
	_count("lights")


## Wall torch (c, r on the wall line, face = direction into the room) with an optional light.
func _torch(c: float, r: float, face: Vector2, light: bool) -> void:
	var base: Vector3 = _cp(c, r) + Vector3(face.x, 0.0, face.y) * 0.5
	_place("torch_mounted.gltf", base + Vector3(0, 1.9, 0), _yaw(face), 1.0, false)
	if light:
		_light(base + Vector3(face.x, 0.0, face.y) * 0.5 + Vector3(0, 2.4, 0), 1.4, 11.0)


## Wall decoration: banners sit on the wall centre line, shields and signs on the wall face.
func _hang(file: String, c: float, r: float, face: Vector2, y: float, sc: float, on_face: bool) -> void:
	var off: float = 0.5 if on_face else 0.0
	_place(file, _cp(c, r, y) + Vector3(face.x, 0.0, face.y) * off, _yaw(face), sc, false)


func _container(dkind: String, c: float, r: float, face: Vector2, table: String, fixed: Array = []) -> Node:
	var id: int = _world.next_loot_id()
	var ct = DungeonContainer.new()
	ct.setup_dungeon(id, dkind, table, int(_world.world_seed))
	if not fixed.is_empty():
		ct.contents = fixed
	ct.position = _cp(c, r)
	ct.rotation.y = _yaw(face)
	ct.set_meta("room", _room)
	_root.add_child(ct)
	_world.register_loot(ct)
	containers.append(ct)
	_count("containers")
	if dkind == "chest":
		_count("chests")
	elif dkind == "gold_chest":
		_count("gold_chests")
	return ct


func _guard(type: String, c: float, r: float, boss: bool = false) -> void:
	var m := Marker3D.new()
	m.name = "Guard_%02d" % markers.size()
	m.position = _cp(c, r)
	m.add_to_group("dungeon_skeleton_spawn")
	m.set_meta("type", type)
	m.set_meta("room", _room)
	if boss:
		m.set_meta("boss", true)
	_root.add_child(m)
	markers.append(m)
	_count("markers")


func _pickup(item: String, count: int, c: float, r: float) -> void:
	_world.spawn_ground_item(item, count, _cp(c, r, 0.06), _world.next_loot_id())
	_count("pickups")


# ------------------------------------------------------------------ rooms

func _decorate() -> void:
	_room_antechamber()
	_room_corridors()
	_room_hall()
	_room_armory()
	_room_library()
	_room_storeroom()
	_room_barracks()
	_room_vault()


func _room_antechamber() -> void:
	_room = "antechamber"
	_torch(3.0, 0.5, FACE_E, true)
	_hang("banner_red.gltf", 3.0, 1.5, FACE_E, 0.4, 1.0, false)
	_hang("banner_red.gltf", 6.0, 0.5, FACE_W, 0.4, 1.0, false)
	_torch(6.0, 1.5, FACE_W, true)
	_container("barrel", 3.4, 1.7, FACE_E, "dungeon_barrel")
	_container("barrel_small", 5.6, 1.7, FACE_W, "dungeon_barrel")
	_guard("minion", 3.8, 1.4)
	_pickup("ammo_9mm", 12, 4.1, 1.3)


func _room_corridors() -> void:
	_room = "corridor"
	_torch(4.0, 2.5, FACE_E, false)
	_torch(2.5, 4.0, FACE_S, false)
	_torch(6.5, 5.0, FACE_N, false)
	_torch(4.0, 6.5, FACE_E, false)
	_torch(8.5, 5.0, FACE_N, false)


func _room_hall() -> void:
	_room = "hall"
	for p in [Vector2(3.75, 3.75), Vector2(5.25, 3.75), Vector2(3.75, 5.25), Vector2(5.25, 5.25)]:
		_place("pillar.gltf", _cp(p.x, p.y), 0.0, 1.0, true)
	_hang("banner_red.gltf", 3.5, 3.0, FACE_S, 0.4, 1.0, false)
	_hang("banner_red.gltf", 5.5, 3.0, FACE_S, 0.4, 1.0, false)
	_hang("banner_blue.gltf", 3.5, 6.0, FACE_N, 0.4, 1.0, false)
	_hang("banner_blue.gltf", 5.5, 6.0, FACE_N, 0.4, 1.0, false)
	_torch(3.0, 3.5, FACE_E, true)
	_torch(3.0, 5.5, FACE_E, false)
	_torch(6.0, 3.5, FACE_W, false)
	_torch(6.0, 5.5, FACE_W, true)
	_container("chest", 5.5, 3.35, FACE_S, "dungeon_chest")
	_container("chest", 3.5, 5.65, FACE_N, "dungeon_chest")
	_container("barrel", 3.4, 3.4, FACE_S, "dungeon_barrel")
	_container("crates", 5.65, 5.65, FACE_N, "dungeon_crate")
	_guard("warrior", 3.9, 3.9)
	_guard("minion", 5.1, 3.9)
	_guard("rogue", 4.5, 4.5)


func _room_armory() -> void:
	_room = "armory"
	_torch(0.0, 3.5, FACE_E, true)
	_hang("sword_shield.gltf", 0.5, 3.0, FACE_S, 2.0, 0.6, true)
	_hang("sword_shield.gltf", 1.5, 3.0, FACE_S, 2.0, 0.6, true)
	_hang("sword_shield_broken.gltf", 0.0, 4.5, FACE_E, 2.0, 0.6, true)
	_container("chest", 0.5, 3.35, FACE_S, "dungeon_chest")
	_container("chest", 1.55, 3.35, FACE_S, "dungeon_chest")
	_container("keg", 1.75, 3.75, FACE_W, "dungeon_barrel")
	_guard("warrior", 1.0, 4.0)


func _room_library() -> void:
	_room = "library"
	_torch(9.0, 4.5, FACE_W, true)
	_torch(9.0, 3.5, FACE_W, false)
	_container("bottle_table", 7.5, 3.55, FACE_S, "dungeon_bottles")
	_container("bottle_table", 8.5, 3.55, FACE_S, "dungeon_bottles")
	_container("chest", 8.74, 4.1, FACE_W, "dungeon_chest")
	_place("chair.gltf", _cp(7.8, 4.1), 0.7, 0.5, false)
	_place("stool.gltf", _cp(8.2, 4.0), 0.2, 0.5, false)
	_place("candle_lit.gltf", _cp(7.35, 4.2), 0.0, 0.4, false)
	_guard("mage", 7.9, 3.95)


func _room_storeroom() -> void:
	_room = "storeroom"
	_torch(0.0, 7.5, FACE_E, true)
	_container("crates", 1.7, 6.3, FACE_W, "dungeon_crate")
	_container("crates", 1.7, 7.5, FACE_W, "dungeon_crate")
	_container("barrel", 0.38, 7.55, FACE_E, "dungeon_barrel")
	_container("barrel", 0.38, 7.25, FACE_E, "dungeon_barrel")
	_container("barrel", 1.05, 7.75, FACE_N, "dungeon_barrel")
	_container("box", 1.1, 6.4, FACE_S, "dungeon_crate")
	_container("box", 1.15, 6.85, FACE_S, "dungeon_crate")
	_place(RES + "Parts_Pile_Medium.gltf", _cp(1.45, 7.05), 0.4, 0.8, false)
	_place(RES + "Wood_Planks_Stack_Small.gltf", _cp(0.95, 7.0), 1.2, 1.0, false)
	_place(RES + "Iron_Bars_Stack_Medium.gltf", _cp(0.6, 6.45), 0.3, 0.9, false)
	_place(RES + "Copper_Bars_Stack_Small.gltf", _cp(1.4, 6.6), 0.0, 0.9, false)
	_pickup("iron_ingot", 2, 0.9, 6.55)
	_pickup("copper_ingot", 2, 1.3, 6.65)
	_pickup("parts", 2, 0.75, 7.05)
	_guard("rogue", 1.0, 6.9)


func _room_barracks() -> void:
	_room = "barracks"
	_torch(9.0, 7.5, FACE_W, true)
	_torch(7.0, 6.5, FACE_E, false)
	for cx in [7.45, 7.9, 8.35]:
		_place("bed_floor.gltf", _cp(cx, 7.4), 0.0, 0.7, true)
	_container("chest", 8.74, 6.4, FACE_W, "dungeon_chest")
	_container("barrel", 7.4, 6.4, FACE_E, "dungeon_barrel")
	_guard("warrior", 8.0, 6.6)
	_guard("minion", 7.7, 6.7)


func _room_vault() -> void:
	_room = "vault"
	for sx in [3.4, 5.6]:
		_place("pillar_decorated.gltf", _cp(sx, 7.45), 0.0, 1.0, true)
	_hang("banner_yellow.gltf", 2.5, 7.0, FACE_S, 0.4, 1.0, false)
	_hang("banner_yellow.gltf", 6.5, 7.0, FACE_S, 0.4, 1.0, false)
	_torch(3.5, 7.0, FACE_S, true)
	_torch(5.5, 7.0, FACE_S, true)
	_torch(2.5, 9.0, FACE_N, true)
	_torch(6.5, 9.0, FACE_N, false)
	_hang("sword_shield_gold.gltf", 4.5, 9.0, FACE_N, 2.4, 0.8, true)
	# the first gold chest always holds the rifle and a serious haul; the rest roll dungeon_gold
	var prize: Array = [
		{"id": "weapon_ar", "count": 1}, {"id": "ammo_556", "count": 60}, {"id": "ammo_762", "count": 30},
		{"id": "medkit", "count": 3}, {"id": "gold_ingot", "count": 3}, {"id": "coin", "count": 40},
	]
	_container("gold_chest", 4.5, 8.7, FACE_N, "dungeon_gold", prize)
	_container("gold_chest", 3.2, 8.7, FACE_N, "dungeon_gold")
	_container("gold_chest", 5.8, 8.7, FACE_N, "dungeon_gold")
	_container("chest", 2.45, 7.5, FACE_E, "dungeon_chest")
	_container("chest", 6.55, 7.5, FACE_W, "dungeon_chest")
	_place(RES + "Gold_Bars_Stack_Large.gltf", _cp(2.55, 8.55), 0.3, 1.0, false)
	_place(RES + "Gold_Bars_Stack_Medium.gltf", _cp(6.45, 8.55), -0.4, 1.0, false)
	_place("coin_stack_large.gltf", _cp(3.85, 8.6), 0.0, 0.4, false)
	_place("coin_stack_large.gltf", _cp(5.15, 8.6), 1.0, 0.4, false)
	_place(RES + "Silver_Nuggets.gltf", _cp(6.1, 8.35), 0.0, 1.0, false)
	_pickup("gold_ingot", 2, 4.15, 8.3)
	_pickup("silver_ingot", 1, 4.85, 8.3)
	_pickup("coin", 25, 4.5, 8.35)
	_guard("warrior", 4.5, 8.0, true)
	_guard("warrior", 3.5, 7.9)
	_guard("mage", 2.9, 7.95)
	_guard("rogue", 3.9, 7.35)
