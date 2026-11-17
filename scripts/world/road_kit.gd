extends RefCounted
## Road rendering from the Kenney City Kit Roads (CC0) for the whole map: countryside roads, the city street grid and
## the driveways / dungeon track. The tiles follow the existing HandLayout polylines (plus the extra segments the
## world builder appended to terrain.road_a/b), so every road the layout and the tests know about is drawn.
##
## All tiles are baked into ONE mesh with the road kit's own colormap material, every vertex lifted onto the terrain
## height, and given NO collision: the terrain chunks stay the drivable ground (vehicle ground contact is untouched).
## Junction tiles (end / bend / T / crossroad) come from the polyline graph; straight tiles fill the rest. City
## corners also get light poles, traffic lights and stop signs from the same kit. Deterministic, no RNG.

const HandLayout = preload("res://scripts/world/hand_layout.gd")

const ROADS_DIR := "res://assets/kenney/city-kit-roads/"
const COUNTRY_W := 6.0       ## asphalt width of countryside roads
const CITY_W := 6.4          ## city streets (matches the two 3.2 m tracks of HandLayout.STREET_HALF)
const LANE_W := 3.6          ## driveways and dirt tracks
const MAX_TILE_LEN := 1.5    ## straight tiles are cut this short so they hug the terrain
const LIFT := 0.14           ## tiles float this far above the terrain surface (clears the 2-triangle terrain cells)
const AXIS_TOL := 0.06       ## radians: a direction this close to N/E/S/W counts as axis aligned
const PROP_SCALE := 7.0
const CORNER := 3.9          ## street prop offset from the intersection centre

## Local openings of the kit tiles (tile space, +X = (1,0)): straight runs along X, bend opens -X and +Z,
## the T opens +X, -X and +Z, the end opens +X.
const BEND_OPEN := [Vector2i(-1, 0), Vector2i(0, 1)]
const T_OPEN := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1)]
const ALL_OPEN := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var world
var kit                      ## the CityKit (prop placement, node, missing list)
var tile_kinds := {}         ## tile file -> placed count
var missing: Array = []
var counts := {"tiles": 0, "junctions": 0}
var _cache := {}
var _mat: Material
var _v := PackedVector3Array()
var _n := PackedVector3Array()
var _uv := PackedVector2Array()
var _idx := PackedInt32Array()
var _verts := {}             ## vertex key -> {"p": Vector2, "dirs": [Vector2], "w": float, "city": bool}
var _segs := {}              ## "keyA|keyB" -> true (de-duplicates overlapping polylines)
var _seg_list: Array = []    ## [a, b, width, city]


func _init(p_world, p_kit) -> void:
	world = p_world
	kit = p_kit


func build() -> void:
	_collect_network()
	var trim := {}
	for k in _verts:
		var v: Dictionary = _verts[k]
		if _junction(v["p"], v["dirs"], float(v["w"]), bool(v["city"])):
			trim[k] = float(v["w"]) * 0.5
	for s in _seg_list:
		_segment(s[0], s[1], float(s[2]), bool(s[3]), float(trim.get(_key(s[0]), 0.0)), float(trim.get(_key(s[1]), 0.0)))
	var mi := MeshInstance3D.new()
	mi.name = "Roads"
	mi.mesh = _to_mesh()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	kit.node.add_child(mi)
	_city_props()
	kit.missing.append_array(missing)


# ------------------------------------------------------------------ network

func _key(p: Vector2) -> String:
	return "%d,%d" % [roundi(p.x * 2.0), roundi(p.y * 2.0)]


func _add_segment(a: Vector2, b: Vector2, w: float, city: bool) -> void:
	if a.distance_to(b) < 0.5:
		return
	var ka: String = _key(a)
	var kb: String = _key(b)
	var sk: String = ka + "|" + kb if ka < kb else kb + "|" + ka
	if _segs.has(sk):
		return
	_segs[sk] = true
	_seg_list.append([a, b, w, city])
	for pair in [[a, b, ka], [b, a, kb]]:
		var p: Vector2 = pair[0]
		var q: Vector2 = pair[1]
		var k: String = pair[2]
		if not _verts.has(k):
			_verts[k] = {"p": p, "dirs": [], "w": w, "city": city}
		var v: Dictionary = _verts[k]
		v["w"] = maxf(float(v["w"]), w)
		v["city"] = bool(v["city"]) and city
		(v["dirs"] as Array).append((q - p).normalized())


func _collect_network() -> void:
	for r in HandLayout.COUNTRY_ROADS:
		var pts: Array = r[1]
		for i in range(pts.size() - 1):
			_add_segment(pts[i], pts[i + 1], COUNTRY_W, false)
	for x in HandLayout.CITY_X:
		for k in range(HandLayout.CITY_Z.size() - 1):
			_add_segment(Vector2(float(x), float(HandLayout.CITY_Z[k])), Vector2(float(x), float(HandLayout.CITY_Z[k + 1])), CITY_W, true)
	for z in HandLayout.CITY_Z:
		for k in range(HandLayout.CITY_X.size() - 1):
			_add_segment(Vector2(float(HandLayout.CITY_X[k]), float(z)), Vector2(float(HandLayout.CITY_X[k + 1]), float(z)), CITY_W, true)
	# driveways and the dungeon track: everything the world builder appended after the layout's own segments
	var base: int = HandLayout.road_segments().size()
	var t = world.terrain
	for i in range(base, t.road_a.size()):
		_add_segment(t.road_a[i], t.road_b[i], LANE_W, false)


## The whole road tile placement for one graph vertex. Returns true when a tile was placed (the segments then stop
## half a tile short of the vertex).
func _junction(p: Vector2, dirs: Array, w: float, city: bool) -> bool:
	var kind := dirs.size()
	if kind == 2 and (dirs[0] as Vector2).dot(dirs[1]) < -0.9999:
		return false   # straight through: the two segments simply meet
	var card: Array = []
	var all_axis := true
	for d in dirs:
		var c: Vector2i = _cardinal(d)
		if c == Vector2i.ZERO:
			all_axis = false
		card.append(c)
	var file := "road-crossroad"
	var yaw := 0.0
	if kind == 1:
		file = "road-end"
		yaw = atan2(-(dirs[0] as Vector2).y, (dirs[0] as Vector2).x)   # opens +X in tile space
	elif kind == 2:
		if all_axis and card[0] != card[1]:
			var y1: float = _fit_yaw(BEND_OPEN, card)
			if not is_nan(y1):
				file = "road-bend"
				yaw = y1
		else:
			file = "road-straight"   # oblique bend: a straight patch along the bisector covers the wedge
			var bis: Vector2 = (dirs[1] as Vector2) - (dirs[0] as Vector2)
			if bis.length() < 0.01:
				return false
			yaw = atan2(-bis.y, bis.x)
		if file == "road-crossroad":
			yaw = atan2(-(dirs[0] as Vector2).y, (dirs[0] as Vector2).x)
			file = "road-straight"
	elif kind == 3 and all_axis:
		var y3: float = _fit_yaw(T_OPEN, card)
		if not is_nan(y3):
			file = "road-intersection"
			yaw = y3
	elif kind >= 3 and not all_axis:
		yaw = atan2(-(dirs[0] as Vector2).y, (dirs[0] as Vector2).x)
	_add_tile(file, p, yaw, w, w)
	counts["junctions"] = int(counts["junctions"]) + 1
	return true


func _cardinal(d: Vector2) -> Vector2i:
	for c in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if absf(d.angle_to(Vector2(c))) < AXIS_TOL:
			return c
	return Vector2i.ZERO


## The 90-degree yaw (Basis(UP, yaw), matching Godot's rotation) that turns the tile's local openings into `want`.
func _fit_yaw(open_local: Array, want: Array) -> float:
	for k in 4:
		var yaw: float = float(k) * PI * 0.5
		var c: int = roundi(cos(yaw))
		var s: int = roundi(sin(yaw))
		var got := {}
		for o in open_local:
			got[Vector2i(c * o.x + s * o.y, -s * o.x + c * o.y)] = true
		var ok: bool = got.size() == want.size()
		for q in want:
			if not got.has(q):
				ok = false
		if ok:
			return yaw
	return NAN


func _segment(a: Vector2, b: Vector2, w: float, city: bool, trim_a: float, trim_b: float) -> void:
	var dir: Vector2 = (b - a).normalized()
	var length: float = a.distance_to(b) - trim_a - trim_b
	if length < 0.05:
		return
	var n: int = maxi(1, ceili(length / MAX_TILE_LEN))
	var piece: float = length / float(n)
	var yaw: float = atan2(-dir.y, dir.x)   # tile +X along the segment
	for i in n:
		var centre: Vector2 = a + dir * (trim_a + piece * (float(i) + 0.5))
		var file := "road-straight"
		if city and n >= 6 and i == n / 2:
			file = "road-crossing"   # zebra mid-block on the city streets
		_add_tile(file, centre, yaw, piece, w)


# ------------------------------------------------------------------ tile baking

## Loads (once) the first mesh of a kit tile: its arrays and the transform of its node relative to the glb root.
func _tile(file: String) -> Dictionary:
	if _cache.has(file):
		return _cache[file]
	var path: String = ROADS_DIR + file + ".glb"
	var out := {}
	var ps: PackedScene = load(path) as PackedScene if ResourceLoader.exists(path) else null
	var inst: Node3D = ps.instantiate() as Node3D if ps != null else null
	if inst == null:
		missing.append(path)
	else:
		var found: Array = []
		_find_mesh(inst, Transform3D.IDENTITY, found)
		if found.is_empty():
			missing.append(path)
		else:
			var mi: MeshInstance3D = found[0][0]
			out = {"arrays": mi.mesh.surface_get_arrays(0), "xf": found[0][1]}
			if _mat == null:
				_mat = mi.mesh.surface_get_material(0)
		inst.free()
	_cache[file] = out
	return out


func _find_mesh(n: Node, xf: Transform3D, out: Array) -> void:
	var t := xf
	if n is Node3D:
		t = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null and out.is_empty():
		out.append([n, t])
	for c in n.get_children():
		_find_mesh(c, t, out)


## One tile at world (x, z), turned by yaw, scaled sx along its local X and sz along its local Z (heights stay 1:1).
func _add_tile(file: String, pos: Vector2, yaw: float, sx: float, sz: float) -> void:
	var tile: Dictionary = _tile(file)
	if tile.is_empty():
		return
	var arrays: Array = tile["arrays"]
	var xf: Transform3D = tile["xf"]
	var vs: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var ns: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var ids: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var basis := Basis(Vector3.UP, yaw)
	var base: int = _v.size()
	for i in vs.size():
		var lv: Vector3 = xf * vs[i]
		var w: Vector3 = basis * Vector3(lv.x * sx, 0.0, lv.z * sz)
		var wx: float = pos.x + w.x
		var wz: float = pos.y + w.z
		_v.append(Vector3(wx, world.get_height(wx, wz) + LIFT + lv.y, wz))
		_n.append((basis * (xf.basis * ns[i])).normalized())
		_uv.append(uvs[i])
	for i in ids:
		_idx.append(base + i)
	counts["tiles"] = int(counts["tiles"]) + 1
	tile_kinds[file] = int(tile_kinds.get(file, 0)) + 1


func _to_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if _v.is_empty():
		return mesh
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = _v
	arr[Mesh.ARRAY_NORMAL] = _n
	arr[Mesh.ARRAY_TEX_UV] = _uv
	arr[Mesh.ARRAY_INDEX] = _idx
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	if _mat != null:
		mesh.surface_set_material(0, _mat)
	return mesh


# ------------------------------------------------------------------ city street props

## Light pole, two traffic lights and a stop sign on the four corners of every grid intersection (replaces the old box lamps).
func _city_props() -> void:
	for x in HandLayout.CITY_X:
		for z in HandLayout.CITY_Z:
			var corners := [[1.0, 1.0, "light-curved"], [-1.0, 1.0, "traffic-light"], [1.0, -1.0, "traffic-light"], [-1.0, -1.0, "road-sign-stop"]]
			for c in corners:
				var sx: float = float(c[0])
				var sz: float = float(c[1])
				var yaw: float = atan2(sx, sz)   # the model's -Z side (light arm / sign face) turns toward the junction
				kit.prop("roads", str(c[2]), float(x) + sx * CORNER, float(z) + sz * CORNER, PROP_SCALE, yaw)
				if str(c[2]) == "light-curved":
					kit._counts["lamps"] = int(kit._counts["lamps"]) + 1
