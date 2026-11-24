extends Node3D
## Runtime face of the BAKED terrain (scenes/world/baked/terrain.tscn). world_builder.gd attaches this script to the
## baked "Terrain" node on load, so `world.terrain` keeps the read-only queries the rest of the game used:
##   height_at(x, z) / normal_at(x, z)   bilinear samples of scenes/world/baked/res/heightmap.res (NAN off the map)
##   ground_color(x, z)                  baked map tint (scenes/world/baked/res/groundmap.res; A = encoded forest density)
##   forest_density(x, z)                baked forest density, -1..1 (8-bit, about 0.008 resolution)
##   road_a / road_b / road_distance()   road centrelines from the Markers "roads" meta (baked data)
##   flat_pos / flat_radius / flat_blend / flat_height   carved flat pads from the Markers "flats" meta
## Nothing here generates meshes or collision; those are the baked Chunk_X_Z nodes.

const HEIGHTMAP_PATH := "res://scenes/world/baked/res/heightmap.res"
const GROUNDMAP_PATH := "res://scenes/world/baked/res/groundmap.res"
const HALF := 256.0
const ROAD_WIDTH := 3.2
const ROAD_EDGE := 1.1
## Half-width of the level road bed and the blend beyond it that the bake carved (generator values).
const ROAD_FLAT := 6.2
const ROAD_BLEND := 9.0

var heightmap: Image
var origin := Vector2(-258.0, -258.0)
var cell := 1.0
var size := 0
var road_a := PackedVector2Array()
var road_b := PackedVector2Array()
var flat_pos := PackedVector2Array()
var flat_radius := PackedFloat32Array()
var flat_blend := PackedFloat32Array()
var flat_height := PackedFloat32Array()

var _h := PackedFloat32Array()
var _ground: Image


## Loads the heightmap (once per node), the road list ([ax, az, bx, bz] rows) and the flat pads ([x, z, r, blend, h]).
func load_data(roads: Array = [], flats: Array = []) -> void:
	if heightmap == null:
		heightmap = load(HEIGHTMAP_PATH) as Image
		if heightmap != null:
			origin = heightmap.get_meta("origin", origin) as Vector2
			cell = float(heightmap.get_meta("cell", cell))
			size = heightmap.get_width()
			_h = heightmap.get_data().to_float32_array()
		else:
			push_error("[BakedTerrain] missing %s" % HEIGHTMAP_PATH)
	road_a.clear()
	road_b.clear()
	for r in roads:
		road_a.append(Vector2(float(r[0]), float(r[1])))
		road_b.append(Vector2(float(r[2]), float(r[3])))
	flat_pos.clear()
	flat_radius.clear()
	flat_blend.clear()
	flat_height.clear()
	for f in flats:
		flat_pos.append(Vector2(float(f[0]), float(f[1])))
		flat_radius.append(float(f[2]))
		flat_blend.append(float(f[3]))
		flat_height.append(float(f[4]))


func has_height(x: float, z: float) -> bool:
	if size < 2:
		return false
	var fx: float = (x - origin.x) / cell
	var fz: float = (z - origin.y) / cell
	return fx >= 0.0 and fz >= 0.0 and fx <= float(size - 1) and fz <= float(size - 1)


## Bilinear heightmap sample; NAN outside the baked grid.
func height_at(x: float, z: float) -> float:
	if not has_height(x, z):
		return NAN
	var fx: float = (x - origin.x) / cell
	var fz: float = (z - origin.y) / cell
	var i: int = mini(int(floor(fx)), size - 2)
	var j: int = mini(int(floor(fz)), size - 2)
	var tx: float = fx - float(i)
	var tz: float = fz - float(j)
	var h00: float = _h[j * size + i]
	var h10: float = _h[j * size + i + 1]
	var h01: float = _h[(j + 1) * size + i]
	var h11: float = _h[(j + 1) * size + i + 1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


func normal_at(x: float, z: float) -> Vector3:
	var e: float = cell * 0.5
	var hx: float = height_at(x + e, z) - height_at(x - e, z)
	var hz: float = height_at(x, z + e) - height_at(x, z - e)
	if is_nan(hx) or is_nan(hz):
		return Vector3.UP
	return Vector3(-hx, 2.0 * e, -hz).normalized()


## Nearest-cell baked ground tint; A carries forest density. Transparent black when the groundmap is missing or off-map.
func ground_color(x: float, z: float) -> Color:
	if _ground == null:
		if not ResourceLoader.exists(GROUNDMAP_PATH):
			return Color(0, 0, 0, 0)
		_ground = load(GROUNDMAP_PATH) as Image
		if _ground == null:
			return Color(0, 0, 0, 0)
	var i: int = int(round((x - origin.x) / cell))
	var j: int = int(round((z - origin.y) / cell))
	if i < 0 or j < 0 or i >= _ground.get_width() or j >= _ground.get_height():
		return Color(0, 0, 0, 0)
	return _ground.get_pixel(i, j)


## Forest density decoded from the groundmap alpha (a = (d + 1) / 2); -1 (open ground) when unavailable.
func forest_density(x: float, z: float) -> float:
	var c := ground_color(x, z)
	if c.r + c.g + c.b + c.a <= 0.0:
		return -1.0
	return c.a * 2.0 - 1.0


## Distance from (x, z) to the nearest road centreline (INF when there are no roads).
func road_distance(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var best := INF
	for i in road_a.size():
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, road_a[i], road_b[i])))
	return best
