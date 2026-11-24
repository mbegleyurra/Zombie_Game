extends Node3D
## Smooth terrain from hand-authored relief grids (data/hand_map/terrain.bin) - no runtime noise or seed. World is CHUNKS x CHUNKS chunks of CHUNK_SIZE metres,
## each chunk an indexed smooth-normal ArrayMesh (2 triangles per CELL x CELL quad) with its own trimesh collision.
## World spans [-HALF, HALF] on X and Z; a mountain ridge rises at the border to contain players.

const CHUNK_SIZE := 64.0
const CELL := 1.0
const CHUNKS := 8
const HALF := 256.0
const VIEW_RANGE := 300.0
const ROAD_WIDTH := 3.2

const COL_GRASS_A := Color(0.33, 0.5, 0.2)
const COL_GRASS_B := Color(0.56, 0.6, 0.24)
const COL_DIRT := Color(0.5, 0.36, 0.22)
const COL_ROCK := Color(0.52, 0.46, 0.42)
const COL_ROCK_DARK := Color(0.38, 0.33, 0.34)
const COL_SAND := Color(0.76, 0.64, 0.4)
const COL_HIGH := Color(0.62, 0.5, 0.38)
const COL_DIRT_DRY := Color(0.58, 0.46, 0.28)
const COL_GRASS_DARK := Color(0.22, 0.4, 0.18)
const ROAD_EDGE := 1.1  # width of the worn verge beside a road (metres)
## Level road bed: the terrain is carved to a flat strip ROAD_FLAT metres each side of every road centreline
## (wide enough that no 2 m terrain triangle under a 6.4 m tile is tilted), then blends to the natural relief over ROAD_BLEND.
const ROAD_FLAT := 6.2
const ROAD_BLEND := 9.0
const ROAD_CELL := 16.0           # spatial hash cell for the road lookup
const ROAD_JOIN_TOL := 0.3        # a segment end this close to another segment shares that segment's profile height
const ROAD_SMOOTH_RINGS := [10.0, 20.0]  # radii of the low-pass that turns raw relief into the road profile
const ROAD_SNAP_END := 2.0        # a segment end this close to another segment's END takes that end's height (no sliver of grade)

## Hand-authored relief: three 1 m grids (relief, forest density, ground-colour patch) stored in
## data/hand_map/terrain.bin, sampled bilinearly. No noise is evaluated at runtime.
const GRID_FILE := "res://data/hand_map/terrain.bin"
const GRID_PAD := 258                  # samples cover x, z = -GRID_PAD .. GRID_PAD metres
const GRID_N := 2 * GRID_PAD + 1

var world_seed: int = 0
var _g_relief := PackedFloat32Array()
var _g_forest := PackedFloat32Array()
var _g_patch := PackedFloat32Array()

var flat_pos := PackedVector2Array()
var flat_radius := PackedFloat32Array()
var flat_blend := PackedFloat32Array()
var flat_height := PackedFloat32Array()
var flat_core: Array = []              # Rect2 per pad: inside it this pad's height is exact for road profiles (zero area = none)
var flat_roads := PackedByteArray()    # 1 = the pad's blend shapes road profiles; 0 = exact inside its radius only (cottages)
var _solid_pads := PackedInt32Array()  # indices of pads that no road bed may cut into (dungeon crater / stair support)
var road_a := PackedVector2Array()
var road_b := PackedVector2Array()
var _road_dirty := true
var _road_h0 := PackedFloat32Array()   # road profile height at road_a[i]
var _road_h1 := PackedFloat32Array()   # road profile height at road_b[i]
var _road_grid := {}                   # Vector2i cell -> PackedInt32Array of road indices reaching that cell


var chunk_nodes: Dictionary = {}  # Vector2i -> MeshInstance3D

# working buffers for the chunk being built
var _v := PackedVector3Array()
var _n := PackedVector3Array()
var _c := PackedColorArray()



func setup(p_seed: int) -> void:
	world_seed = p_seed
	_load_grids()


func _load_grids() -> void:
	var f := FileAccess.open(GRID_FILE, FileAccess.READ)
	if f == null:
		push_error("[Terrain] missing hand-authored grid %s" % GRID_FILE)
		return
	var count: int = GRID_N * GRID_N
	_g_relief = f.get_buffer(count * 4).to_float32_array()
	_g_forest = f.get_buffer(count * 4).to_float32_array()
	_g_patch = f.get_buffer(count * 4).to_float32_array()
	f.close()


## Bilinear sample of one authored grid at world (x, z); exact at integer metres, clamped beyond the grid.
func _grid_at(g: PackedFloat32Array, x: float, z: float) -> float:
	if g.is_empty():
		return 0.0
	var fx: float = clampf(x + float(GRID_PAD), 0.0, float(GRID_N - 1))
	var fz: float = clampf(z + float(GRID_PAD), 0.0, float(GRID_N - 1))
	var ix: int = mini(int(fx), GRID_N - 2)
	var iz: int = mini(int(fz), GRID_N - 2)
	var tx: float = fx - float(ix)
	var tz: float = fz - float(iz)
	var i0: int = iz * GRID_N + ix
	var a: float = lerpf(g[i0], g[i0 + 1], tx)
	var b: float = lerpf(g[i0 + GRID_N], g[i0 + GRID_N + 1], tx)
	return lerpf(a, b, tz)


## Ground-colour patch value (was noise_patch): low = lush meadow, high = bare earth.
func patch_at(x: float, z: float) -> float:
	return _grid_at(_g_patch, x, z)


## Flatten terrain to `height` inside `radius`, blending to natural terrain over `blend` metres.
## `core` (optional) is a rectangle in which this pad's height is exact for road profiles, whatever other pads overlap
## (the city street grid). `shapes_roads` false keeps a small pad (a cottage) from moving the roads beside it.
## `solid` true shields the pad (radius + blend) from every road bed, strip included: a structure sits on it that a
## dead-end road's flat end disc would otherwise bury (the dungeon's stair support).
func add_flat(center: Vector2, radius: float, blend: float, height: float, core: Rect2 = Rect2(), shapes_roads: bool = true, solid: bool = false) -> void:
	if solid:
		_solid_pads.append(flat_pos.size())
	flat_pos.append(center)
	flat_radius.append(radius)
	flat_blend.append(blend)
	flat_height.append(height)
	flat_core.append(core)
	flat_roads.append(1 if shapes_roads else 0)
	_road_dirty = true


## Paint (and keep prop-free) a dirt road between two points.
func add_road(a: Vector2, b: Vector2) -> void:
	road_a.append(a)
	road_b.append(b)
	_road_dirty = true


func _raw_height(x: float, z: float) -> float:
	var h: float = _grid_at(_g_relief, x, z)
	var e: float = maxf(absf(x), absf(z))
	h += smoothstep(HALF - 45.0, HALF - 8.0, e) * 45.0
	return h


## Natural terrain plus the flat location pads, WITHOUT the road bed.
func base_height(x: float, z: float) -> float:
	var h: float = _raw_height(x, z)
	var p := Vector2(x, z)
	for i in flat_pos.size():
		var rr: float = flat_radius[i]
		var d: float = p.distance_to(flat_pos[i])
		if d < rr + flat_blend[i]:
			h = lerpf(flat_height[i], h, smoothstep(rr, rr + flat_blend[i], d))
	return h


## Final ground height: base terrain with every road's level bed carved in. Across a road the height is constant;
## along it the height follows the smooth grade of that segment (no bumps, no steps).
func height_at(x: float, z: float) -> float:
	var h: float = base_height(x, z)
	var bed: Vector2 = _bed(x, z)
	if bed.y > 0.0:
		var s: float = bed.y
		if s < 1.0:
			s *= _skirt_keep(Vector2(x, z))
		if not _solid_pads.is_empty():
			s *= _solid_keep(Vector2(x, z))
		h = lerpf(h, bed.x, s)
	return h


## 0..1 factor for a road bed over a solid pad: 0 inside the pad's radius (the pad's own height stands), rising to 1
## at the end of its blend. Unlike _skirt_keep this also cancels the bed's level strip.
func _solid_keep(p: Vector2) -> float:
	var keep := 1.0
	for i in _solid_pads:
		keep = minf(keep, smoothstep(flat_radius[i], flat_radius[i] + flat_blend[i], p.distance_to(flat_pos[i])))
	return keep


## 0..1 factor for a road bed's BLEND skirt (never its flat strip): a nearby road's skirt fades out over a location pad
## (farm, warehouse...) so a raised bed cannot bury the floor or fence of a site it only passes by. The level strip of a
## road that really enters the pad is untouched. The city's big pad is exempt (city streets are carved by their own beds).
func _skirt_keep(p: Vector2) -> float:
	var keep := 1.0
	for i in flat_pos.size():
		var rr: float = flat_radius[i]
		if flat_roads[i] != 1 or rr > 40.0 or flat_core[i].has_area():
			continue
		keep = minf(keep, smoothstep(rr - 2.0, rr + 6.0, p.distance_to(flat_pos[i])))
	return keep


## Height of the road bed at (x, z), or NAN when no road's bed reaches it. Cottage pads use this so a house sits
## at the level of the road in front of it.
func road_bed_height(x: float, z: float) -> float:
	var bed: Vector2 = _bed(x, z)
	return bed.x if bed.y > 0.0 else NAN


## (target height, strength 0..1) of the road bed at (x, z); strength 0 means no road reaches this point.
func _bed(x: float, z: float) -> Vector2:
	if road_a.is_empty():
		return Vector2.ZERO
	if _road_dirty:
		_index_roads()
	var segs = _road_grid.get(Vector2i(floori(x / ROAD_CELL), floori(z / ROAD_CELL)))
	if segs == null:
		return Vector2.ZERO
	var p := Vector2(x, z)
	var reach: float = ROAD_FLAT + ROAD_BLEND
	var tsum := 0.0
	var wsum := 0.0
	var wmax := 0.0
	for i in (segs as PackedInt32Array):
		var a: Vector2 = road_a[i]
		var ab: Vector2 = road_b[i] - a
		var t: float = clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var d: float = p.distance_to(a + ab * t)
		if d >= reach:
			continue
		var w: float = 1.0 - smoothstep(ROAD_FLAT, reach, d)
		var w8: float = pow(w, 8.0)   # the nearest road dominates where beds overlap
		tsum += w8 * lerpf(_road_h0[i], _road_h1[i], t)
		wsum += w8
		wmax = maxf(wmax, w)
	if wsum <= 0.0:
		return Vector2.ZERO
	return Vector2(tsum / wsum, wmax)


## Heavily smoothed NATURAL height: the road profile, so roads ignore the 2.5 m surface noise and small hills.
## Inside a pad's `core` rectangle (the city street grid) the pad height is used exactly and wins over every other pad,
## so every city street is one height. Everywhere else the pads are blended over the smoothed relief in the order they
## were added, exactly like base_height, so a road end sitting in two overlapping pads (a farm gate inside the city's
## round pad) takes the height of the ground it really stands on. Cottage pads only act inside their own radius.
func _profile_height(p: Vector2) -> float:
	for i in flat_pos.size():
		var core: Rect2 = flat_core[i]
		if core.has_area() and core.has_point(p):
			return flat_height[i]
	var sum: float = _raw_height(p.x, p.y)
	var cnt := 1
	for r in ROAD_SMOOTH_RINGS:
		for k in 8:
			var ang: float = TAU * float(k) / 8.0
			sum += _raw_height(p.x + cos(ang) * float(r), p.y + sin(ang) * float(r))
			cnt += 1
	var h: float = sum / float(cnt)
	for i in flat_pos.size():
		var rr: float = flat_radius[i]
		var d: float = p.distance_to(flat_pos[i])
		if flat_roads[i] == 1:
			if d < rr + flat_blend[i]:
				h = lerpf(flat_height[i], h, smoothstep(rr, rr + flat_blend[i], d))
		elif d <= rr:
			h = flat_height[i]
	return h


## Profile height of a segment end: a point lying on an earlier segment takes THAT segment's height there
## (junctions and driveways meet without a step); otherwise the smoothed base height.
func _profile_end(p: Vector2, upto: int) -> float:
	for j in upto:
		var a: Vector2 = road_a[j]
		var ab: Vector2 = road_b[j] - a
		var t: float = clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		if p.distance_to(a + ab * t) <= ROAD_JOIN_TOL:
			if p.distance_to(road_b[j]) <= ROAD_SNAP_END:
				return _road_h1[j]
			if p.distance_to(a) <= ROAD_SNAP_END:
				return _road_h0[j]
			return lerpf(_road_h0[j], _road_h1[j], t)
	return _profile_height(p)


func _index_roads() -> void:
	_road_dirty = false
	var n: int = road_a.size()
	_road_h0.resize(n)
	_road_h1.resize(n)
	_road_grid.clear()
	for i in n:
		_road_h0[i] = _profile_end(road_a[i], i)
		_road_h1[i] = _profile_end(road_b[i], i)
	var reach: float = ROAD_FLAT + ROAD_BLEND
	for i in n:
		var a: Vector2 = road_a[i]
		var b: Vector2 = road_b[i]
		var cx0: int = floori((minf(a.x, b.x) - reach) / ROAD_CELL)
		var cx1: int = floori((maxf(a.x, b.x) + reach) / ROAD_CELL)
		var cz0: int = floori((minf(a.y, b.y) - reach) / ROAD_CELL)
		var cz1: int = floori((maxf(a.y, b.y) + reach) / ROAD_CELL)
		for cz in range(cz0, cz1 + 1):
			for cx in range(cx0, cx1 + 1):
				var key := Vector2i(cx, cz)
				var list: PackedInt32Array = _road_grid.get(key, PackedInt32Array())
				list.append(i)
				_road_grid[key] = list


func normal_at(x: float, z: float) -> Vector3:
	var e := 1.0
	var hx: float = height_at(x + e, z) - height_at(x - e, z)
	var hz: float = height_at(x, z + e) - height_at(x, z - e)
	return Vector3(-hx, 2.0 * e, -hz).normalized()


func forest_density(x: float, z: float) -> float:
	return _grid_at(_g_forest, x, z)


## Indices of the roads whose segment passes within `pad` metres of the rectangle.
func _roads_near(x0: float, z0: float, x1: float, z1: float, pad: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in road_a.size():
		var a: Vector2 = road_a[i]
		var b: Vector2 = road_b[i]
		if maxf(a.x, b.x) < x0 - pad or minf(a.x, b.x) > x1 + pad:
			continue
		if maxf(a.y, b.y) < z0 - pad or minf(a.y, b.y) > z1 + pad:
			continue
		out.append(i)
	return out


func road_distance(x: float, z: float) -> float:
	var best := 1.0e9
	var p := Vector2(x, z)
	for i in road_a.size():
		var q: Vector2 = Geometry2D.get_closest_point_to_segment(p, road_a[i], road_b[i])
		best = minf(best, p.distance_to(q))
	return best


## True if (x,z) is outside every location pad and road by at least `margin`.
func is_clear(x: float, z: float, margin: float) -> bool:
	var p := Vector2(x, z)
	for i in flat_pos.size():
		if p.distance_to(flat_pos[i]) < flat_radius[i] + margin:
			return false
	if road_distance(x, z) < ROAD_WIDTH + margin:
		return false
	return true


func build_chunks(mat: Material) -> void:
	for cz in CHUNKS:
		for cx in CHUNKS:
			_build_chunk(cx, cz, mat)


func _hash2(i: int, j: int) -> float:
	var h: int = i * 374761393 + j * 668265263
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xFFFF) / 65535.0


## One chunk as an INDEXED mesh with shared vertices: (n+1)^2 vertices, smooth per-vertex normals taken from the height
## field by central differences (a one-vertex margin of heights beyond the chunk makes the normals match across chunk
## seams), and a per-vertex colour (the old per-triangle flat colour, now blended across the surface).
func _build_chunk(cx: int, cz: int, mat: Material) -> void:
	var n: int = int(CHUNK_SIZE / CELL)
	var x0: float = -HALF + float(cx) * CHUNK_SIZE
	var z0: float = -HALF + float(cz) * CHUNK_SIZE
	var stride: int = n + 1
	var hs: int = n + 3   # height grid with a 1-vertex margin on every side
	var hts := PackedFloat32Array()
	hts.resize(hs * hs)
	for j in hs:
		for i in hs:
			hts[j * hs + i] = height_at(x0 + float(i - 1) * CELL, z0 + float(j - 1) * CELL)
	var vcount: int = stride * stride
	_v.resize(vcount)
	_n.resize(vcount)
	_c.resize(vcount)
	var near: PackedInt32Array = _roads_near(x0, z0, x0 + CHUNK_SIZE, z0 + CHUNK_SIZE, ROAD_WIDTH + ROAD_EDGE + 2.0)
	for j in stride:
		for i in stride:
			var gi: int = (j + 1) * hs + (i + 1)
			var x: float = x0 + float(i) * CELL
			var z: float = z0 + float(j) * CELL
			var h: float = hts[gi]
			var nrm := Vector3(hts[gi - 1] - hts[gi + 1], 2.0 * CELL, hts[gi - hs] - hts[gi + hs]).normalized()
			var rd: float = 1.0e9
			if near.size() > 0:
				var cp := Vector2(x, z)
				for ri in near:
					rd = minf(rd, cp.distance_to(Geometry2D.get_closest_point_to_segment(cp, road_a[ri], road_b[ri])))
			var k: int = j * stride + i
			_v[k] = Vector3(x, h, z)
			_n[k] = nrm
			_c[k] = _tri_color(nrm.y, h, rd, _hash2(cx * n + i, cz * n + j), x, z)
	var idx := PackedInt32Array()
	idx.resize(n * n * 6)
	var q: int = 0
	for j in n:
		for i in n:
			var a: int = j * stride + i          # (x, z)
			var b: int = a + 1                   # (x + CELL, z)
			var c: int = a + stride              # (x, z + CELL)
			var d: int = c + 1                   # (x + CELL, z + CELL)
			if (i + j) % 2 == 0:
				idx[q] = a; idx[q + 1] = b; idx[q + 2] = d
				idx[q + 3] = a; idx[q + 4] = d; idx[q + 5] = c
			else:
				idx[q] = a; idx[q + 1] = b; idx[q + 2] = c
				idx[q + 3] = b; idx[q + 4] = d; idx[q + 5] = c
			q += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _v
	arrays[Mesh.ARRAY_NORMAL] = _n
	arrays[Mesh.ARRAY_COLOR] = _c
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.name = "Chunk_%d_%d" % [cx, cz]
	mi.mesh = mesh
	mi.material_override = mat
	mi.visibility_range_end = VIEW_RANGE
	mi.visibility_range_end_margin = 20.0
	add_child(mi)
	var body := StaticBody3D.new()
	body.name = "Collision"
	var cs := CollisionShape3D.new()
	cs.shape = mesh.create_trimesh_shape()
	body.add_child(cs)
	mi.add_child(body)
	chunk_nodes[Vector2i(cx, cz)] = mi


func _tri_color(slope_y: float, avg_h: float, road_d: float, jitter: float, x: float, z: float) -> Color:
	var c: Color
	var half_w: float = ROAD_WIDTH * 0.5
	if road_d < half_w:
		# worn track: dry dirt in the middle band, darker ruts toward the edges
		c = COL_DIRT_DRY.lerp(COL_DIRT, clampf(road_d / half_w, 0.0, 1.0) * 0.8)
	elif slope_y < 0.74:
		c = COL_ROCK.lerp(COL_ROCK_DARK, clampf((0.74 - slope_y) * 3.0 + (jitter - 0.5) * 0.4, 0.0, 1.0))
	elif avg_h > 17.0:
		c = COL_HIGH
	elif avg_h < -2.5:
		c = COL_SAND
	else:
		c = COL_GRASS_A.lerp(COL_GRASS_B, clampf((avg_h + 4.0) / 20.0 + (jitter - 0.5) * 0.8, 0.0, 1.0))
		# lush dark meadow where the patch noise is low, bare dry earth where it is high
		var pn: float = patch_at(x, z)
		if pn < -0.25:
			c = c.lerp(COL_GRASS_DARK, clampf((-0.25 - pn) * 2.5, 0.0, 0.6))
		elif pn > 0.3:
			c = c.lerp(COL_DIRT_DRY, clampf((pn - 0.3) * 2.5, 0.0, 0.55))
		if road_d < half_w + ROAD_EDGE:
			c = c.lerp(COL_DIRT, 0.5 * (1.0 - (road_d - half_w) / ROAD_EDGE))
	var k: float = 0.93 + jitter * 0.14
	return Color(c.r * k, c.g * k, c.b * k, 1.0)
