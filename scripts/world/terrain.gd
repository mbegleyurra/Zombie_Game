extends Node3D
## Procedural, seed-deterministic faceted terrain. World is CHUNKS x CHUNKS chunks of CHUNK_SIZE metres,
## each chunk a flat-shaded ArrayMesh (2 triangles per CELL x CELL quad) with its own trimesh collision.
## World spans [-HALF, HALF] on X and Z; a mountain ridge rises at the border to contain players.

const CHUNK_SIZE := 64.0
const CELL := 2.0
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

var world_seed: int = 0
var noise_hills: FastNoiseLite
var noise_detail: FastNoiseLite
var noise_forest: FastNoiseLite
var noise_patch: FastNoiseLite

var flat_pos := PackedVector2Array()
var flat_radius := PackedFloat32Array()
var flat_blend := PackedFloat32Array()
var flat_height := PackedFloat32Array()
var road_a := PackedVector2Array()
var road_b := PackedVector2Array()

var chunk_nodes: Dictionary = {}  # Vector2i -> MeshInstance3D

# working buffers for the chunk being built
var _v := PackedVector3Array()
var _n := PackedVector3Array()
var _c := PackedColorArray()
var _k: int = 0


func setup(p_seed: int) -> void:
	world_seed = p_seed
	var s: int = p_seed & 0x7FFFFFFF
	noise_hills = FastNoiseLite.new()
	noise_hills.seed = s
	noise_hills.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_hills.frequency = 0.005
	noise_hills.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise_hills.fractal_octaves = 4
	noise_detail = FastNoiseLite.new()
	noise_detail.seed = (s + 101) & 0x7FFFFFFF
	noise_detail.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_detail.frequency = 0.035
	noise_detail.fractal_octaves = 2
	noise_forest = FastNoiseLite.new()
	noise_forest.seed = (s + 202) & 0x7FFFFFFF
	noise_forest.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_forest.frequency = 0.012
	noise_forest.fractal_octaves = 2
	noise_patch = FastNoiseLite.new()
	noise_patch.seed = (s + 303) & 0x7FFFFFFF
	noise_patch.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_patch.frequency = 0.045
	noise_patch.fractal_octaves = 2


## Flatten terrain to `height` inside `radius`, blending to natural terrain over `blend` metres.
func add_flat(center: Vector2, radius: float, blend: float, height: float) -> void:
	flat_pos.append(center)
	flat_radius.append(radius)
	flat_blend.append(blend)
	flat_height.append(height)


## Paint (and keep prop-free) a dirt road between two points.
func add_road(a: Vector2, b: Vector2) -> void:
	road_a.append(a)
	road_b.append(b)


func _raw_height(x: float, z: float) -> float:
	var h: float = noise_hills.get_noise_2d(x, z) * 16.0 + noise_detail.get_noise_2d(x, z) * 2.5
	var e: float = maxf(absf(x), absf(z))
	h += smoothstep(HALF - 45.0, HALF - 8.0, e) * 45.0
	return h


func height_at(x: float, z: float) -> float:
	var h: float = _raw_height(x, z)
	var p := Vector2(x, z)
	for i in flat_pos.size():
		var rr: float = flat_radius[i]
		var d: float = p.distance_to(flat_pos[i])
		if d < rr + flat_blend[i]:
			h = lerpf(flat_height[i], h, smoothstep(rr, rr + flat_blend[i], d))
	return h


func normal_at(x: float, z: float) -> Vector3:
	var e := 1.0
	var hx: float = height_at(x + e, z) - height_at(x - e, z)
	var hz: float = height_at(x, z + e) - height_at(x, z - e)
	return Vector3(-hx, 2.0 * e, -hz).normalized()


func forest_density(x: float, z: float) -> float:
	return noise_forest.get_noise_2d(x, z)


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


func _build_chunk(cx: int, cz: int, mat: Material) -> void:
	var n: int = int(CHUNK_SIZE / CELL)
	var x0: float = -HALF + float(cx) * CHUNK_SIZE
	var z0: float = -HALF + float(cz) * CHUNK_SIZE
	var stride: int = n + 1
	var hts := PackedFloat32Array()
	hts.resize(stride * stride)
	for j in stride:
		for i in stride:
			hts[j * stride + i] = height_at(x0 + float(i) * CELL, z0 + float(j) * CELL)
	_v.resize(n * n * 6)
	_n.resize(n * n * 6)
	_c.resize(n * n * 6)
	_k = 0
	var near: PackedInt32Array = _roads_near(x0, z0, x0 + CHUNK_SIZE, z0 + CHUNK_SIZE, ROAD_WIDTH + ROAD_EDGE + 2.0)
	for j in n:
		for i in n:
			var xa: float = x0 + float(i) * CELL
			var za: float = z0 + float(j) * CELL
			var p00 := Vector3(xa, hts[j * stride + i], za)
			var p10 := Vector3(xa + CELL, hts[j * stride + i + 1], za)
			var p01 := Vector3(xa, hts[(j + 1) * stride + i], za + CELL)
			var p11 := Vector3(xa + CELL, hts[(j + 1) * stride + i + 1], za + CELL)
			var rd: float = 1.0e9
			if near.size() > 0:
				var cp := Vector2(xa + CELL * 0.5, za + CELL * 0.5)
				for ri in near:
					rd = minf(rd, cp.distance_to(Geometry2D.get_closest_point_to_segment(cp, road_a[ri], road_b[ri])))
			var hsh: float = _hash2(cx * n + i, cz * n + j)
			if (i + j) % 2 == 0:
				_emit(p00, p10, p11, rd, hsh)
				_emit(p00, p11, p01, rd, _hash2(cx * n + i + 7, cz * n + j + 3))
			else:
				_emit(p00, p10, p01, rd, hsh)
				_emit(p10, p11, p01, rd, _hash2(cx * n + i + 7, cz * n + j + 3))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _v
	arrays[Mesh.ARRAY_NORMAL] = _n
	arrays[Mesh.ARRAY_COLOR] = _c
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


func _emit(a: Vector3, b: Vector3, c: Vector3, road_d: float, jitter: float) -> void:
	var nrm := (b - a).cross(c - a)
	if nrm.length_squared() < 0.0000001:
		nrm = Vector3.UP
	nrm = nrm.normalized()
	var cx3: float = (a.x + b.x + c.x) / 3.0
	var cz3: float = (a.z + b.z + c.z) / 3.0
	var col: Color = _tri_color(absf(nrm.y), (a.y + b.y + c.y) / 3.0, road_d, jitter, cx3, cz3)
	if nrm.y < 0.0:
		_put(a, b, c, -nrm, col)
	else:
		_put(a, c, b, nrm, col)


func _put(a: Vector3, b: Vector3, c: Vector3, nrm: Vector3, col: Color) -> void:
	_v[_k] = a
	_v[_k + 1] = b
	_v[_k + 2] = c
	_n[_k] = nrm
	_n[_k + 1] = nrm
	_n[_k + 2] = nrm
	_c[_k] = col
	_c[_k + 1] = col
	_c[_k + 2] = col
	_k += 3


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
		var pn: float = noise_patch.get_noise_2d(x, z)
		if pn < -0.25:
			c = c.lerp(COL_GRASS_DARK, clampf((-0.25 - pn) * 2.5, 0.0, 0.6))
		elif pn > 0.3:
			c = c.lerp(COL_DIRT_DRY, clampf((pn - 0.3) * 2.5, 0.0, 0.55))
		if road_d < half_w + ROAD_EDGE:
			c = c.lerp(COL_DIRT, 0.5 * (1.0 - (road_d - half_w) / ROAD_EDGE))
	var k: float = 0.93 + jitter * 0.14
	return Color(c.r * k, c.g * k, c.b * k, 1.0)
