extends Control
## World map. Toggle: M (action "toggle_map", registered here in code). Full-screen map of the procedural world plus a
## small always-on minimap in the bottom-left corner. Drawn from world_builder data: a baked top-down ground texture
## (terrain ground colours, roads, forest, trees/rocks, building footprints, dungeon crater; see make_height_texture),
## locations (world.locations), the dungeon (world meta "dungeon_site"), the spawn pad, other players, and the local
## player with a heading arrow. While driving, the arrow is the CAR's heading (player.vehicle), not the hidden body's
## yaw. North (-Z) is up on both maps.

## Owned by the Hud autoload. Esc closes the full map; the mouse is released while it is open.

signal opened
signal closed

const ACTION := "toggle_map"
const GROUP_OPEN := "ui_open"        ## Hud.is_ui_open() is true while any member is in this group
const GROUP_ALL := "overlay_ui"
const TEX_SIZE := 384            ## ground texture resolution (1.33 m per texel over the 512 m world), built once per world
const FOREST_CORE := 0.12        ## Terrain.forest_density at or above this is dense forest (same as KayKitForest)
const MINI_SIZE := 220.0
const MINI_HALF := 90.0
const FONT_TITLE := 48
const FONT_BODY := 22
const KEY_COL := Color(0.95, 0.8, 0.35)
const PLAYER_COL := Color(1.0, 0.92, 0.2)
const DUNGEON_COL := Color(0.9, 0.25, 0.9)
const CAR_COL := Color(1.0, 0.5, 0.1)
const TREE_COL := Color(0.13, 0.31, 0.14)
const TREE_HI := Color(0.25, 0.46, 0.2)
const BUSH_COL := Color(0.26, 0.42, 0.17)
const ROCK_COL := Color(0.5, 0.47, 0.45)
const OUTLINE_COL := Color(0.1, 0.08, 0.08)
const HOUSE_COL := Color(0.55, 0.3, 0.24)
const TOWER_COL := Color(0.5, 0.52, 0.58)
const TOWER_HI := Color(0.78, 0.8, 0.86)
## Building footprints per location type (from building_factory.gd): [local x, local z, width, depth, roof colour].
const FOOTPRINTS := {
	"farm": [[0.0, 0.0, 10.6, 8.6, Color(0.36, 0.28, 0.25)], [14.0, -2.0, 8.6, 6.6, Color(0.62, 0.2, 0.16)]],
	"gas_station": [[0.0, 0.0, 12.6, 8.6, Color(0.75, 0.2, 0.18)]],
	"hospital": [[0.0, 0.0, 24.6, 16.6, Color(0.88, 0.9, 0.9)]],
	"police_station": [[0.0, 0.0, 16.6, 10.6, Color(0.62, 0.66, 0.72)]],
	"warehouse": [[0.0, 0.0, 25.0, 17.0, Color(0.32, 0.34, 0.38)]],
	"church": [[0.0, 0.0, 18.6, 9.6, Color(0.3, 0.22, 0.2)], [-10.5, 0.0, 3.6, 6.6, Color(0.6, 0.55, 0.5)]],
}
## Location type -> [color, letter, legend name].
const TYPE_STYLE := {
	"hospital": [Color(0.95, 0.3, 0.3), "H", "Hospital"],
	"gas_station": [Color(0.95, 0.75, 0.2), "G", "Gas station"],
	"police_station": [Color(0.35, 0.55, 0.95), "P", "Police station"],
	"warehouse": [Color(0.75, 0.75, 0.8), "W", "Warehouse"],
	"church": [Color(0.9, 0.9, 1.0), "C", "Church"],
	"farm": [Color(0.55, 0.9, 0.4), "F", "Farm"],
}
## [height m, color] stops for the terrain tint.
const HEIGHT_STOPS := [
	[-14.0, Color(0.14, 0.3, 0.15)], [0.0, Color(0.3, 0.48, 0.2)], [8.0, Color(0.5, 0.58, 0.24)],
	[16.0, Color(0.58, 0.46, 0.3)], [30.0, Color(0.5, 0.46, 0.44)], [55.0, Color(0.88, 0.88, 0.9)],
]


## One drawable map view. The full map shows the whole world; the minimap a window around the player.
class MapCanvas extends Control:
	var world: Node = null
	var player: Node = null
	var texture: Texture2D = null
	var view_center := Vector2.ZERO
	var view_half := 256.0
	var detailed := true
	var draw_count := 0

	## Unit vector on the map (x right, y down = world XZ) the body faces for a yaw in radians.
	static func heading_vec(yaw: float) -> Vector2:
		return Vector2(-sin(yaw), -cos(yaw))

	## The car this player is driving (player.vehicle, set by vehicle.gd while seated), or null on foot.
	## While seated the player body is hidden and parked on the seat, so its own yaw is NOT the travel direction.
	static func vehicle_of(who: Node) -> Node3D:
		if who == null or not is_instance_valid(who):
			return null
		var v = who.get("vehicle")
		if v != null and is_instance_valid(v) and v is Node3D:
			return v as Node3D
		return null

	## Map-space unit vector of the car's front (vehicle.gd drives toward local -Z).
	static func car_heading(car: Node3D) -> Vector2:
		var f: Vector3 = car.global_transform.basis * Vector3(0.0, 0.0, -1.0)
		var v := Vector2(f.x, f.z)
		return v.normalized() if v.length() > 0.001 else Vector2(0.0, -1.0)

	## Direction the player is going: the car's heading while driving, else the body's facing.
	static func player_heading(who: Node3D) -> Vector2:
		var car := vehicle_of(who)
		return car_heading(car) if car != null else heading_vec(who.global_rotation.y)

	func half_world() -> float:
		return float(world.terrain.HALF) if world != null and world.get("terrain") != null else 256.0

	func px_per_m() -> float:
		return minf(size.x, size.y) * 0.5 / view_half

	## World XZ (Vector2) -> pixel position inside this control.
	func world_to_map(p: Vector2) -> Vector2:
		return size * 0.5 + (p - view_center) * px_per_m()

	func _draw() -> void:
		draw_count += 1
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.06, 0.04))
		if world == null or not is_instance_valid(world) or world.get("terrain") == null:
			return
		var ppm := px_per_m()
		var h := half_world()
		var corner := world_to_map(Vector2(-h, -h))
		var span := Vector2(h * 2.0, h * 2.0) * ppm
		if texture != null:
			draw_texture_rect(texture, Rect2(corner, span), false)
		draw_rect(Rect2(corner, span), Color(0.9, 0.85, 0.7, 0.8), false, 2.0)
		var font := ThemeDB.fallback_font
		var spawn := world_to_map(world.spawn_center)
		draw_rect(Rect2(spawn - Vector2(5, 5), Vector2(10, 10)), Color.WHITE)
		if detailed:
			_label(font, spawn + Vector2(10, 5), "SPAWN", 20, Color.WHITE)
		for l in world.locations:
			var st: Array = TYPE_STYLE.get(str(l["type"]), [Color.WHITE, "?", str(l["type"])])
			var pt := world_to_map(l["pos2"])
			if detailed:
				draw_circle(pt, 13.0, Color(0, 0, 0, 0.75))
				draw_circle(pt, 11.0, st[0])
				draw_string(font, pt + Vector2(-6, 7), str(st[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.BLACK)
				_label(font, pt + Vector2(-60, 30), str(l["name"]), 20, Color.WHITE, 120.0)
			else:
				draw_circle(pt, 5.0, Color.BLACK)
				draw_circle(pt, 4.0, st[0])
		var site: Dictionary = world.get_meta("dungeon_site", {}) as Dictionary
		if site.has("origin"):
			var dp := world_to_map(site["origin"])
			var r := 14.0 if detailed else 6.0
			var dia := PackedVector2Array([dp + Vector2(0, -r), dp + Vector2(r, 0), dp + Vector2(0, r), dp + Vector2(-r, 0)])
			draw_colored_polygon(dia, DUNGEON_COL)
			draw_polyline(PackedVector2Array([dia[0], dia[1], dia[2], dia[3], dia[0]]), Color.BLACK, 2.0)
			if detailed:
				_label(font, dp + Vector2(-60, r + 22), "DUNGEON", 20, Color(1.0, 0.7, 1.0), 120.0)
		for n in get_tree().get_nodes_in_group("players"):
			if n != player and n is Node3D:
				var q := (n as Node3D).global_position
				draw_circle(world_to_map(Vector2(q.x, q.z)), 6.0 if detailed else 4.0, Color(0.3, 0.7, 1.0))
		if player != null and is_instance_valid(player) and player is Node3D:
			var car := vehicle_of(player)
			var pp := (car if car != null else (player as Node3D)).global_position
			var pos := world_to_map(Vector2(pp.x, pp.z))
			var f: Vector2 = player_heading(player as Node3D)
			var side := Vector2(-f.y, f.x)
			var s := 1.0 if detailed else 0.75
			if car != null:
				# Car outline (1.8 x 4 m, at least marker-sized) with a big arrow out of its nose.
				var len_px := maxf(4.0 * ppm, 28.0 * s)
				var half_l := len_px * 0.5
				var half_w := half_l * 0.45
				var body := PackedVector2Array([pos + f * half_l + side * half_w, pos + f * half_l - side * half_w,
					pos - f * half_l - side * half_w, pos - f * half_l + side * half_w])
				draw_colored_polygon(body, CAR_COL)
				draw_polyline(PackedVector2Array([body[0], body[1], body[2], body[3], body[0]]), Color.BLACK, 2.0)
				var nose := pos + f * (half_l + 6.0 * s)
				var arrow := PackedVector2Array([nose + f * 14.0 * s, nose - f * 2.0 * s + side * 10.0 * s, nose - f * 2.0 * s - side * 10.0 * s])
				draw_colored_polygon(arrow, PLAYER_COL)
				draw_polyline(PackedVector2Array([arrow[0], arrow[1], arrow[2], arrow[0]]), Color.BLACK, 2.0)
			else:
				var tri := PackedVector2Array([pos + f * 16.0 * s, pos - f * 9.0 * s + side * 9.0 * s, pos - f * 9.0 * s - side * 9.0 * s])
				draw_colored_polygon(tri, PLAYER_COL)
				draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]), Color.BLACK, 2.0)

		if not detailed:
			draw_rect(Rect2(Vector2.ZERO, size), Color(0.9, 0.85, 0.7, 0.9), false, 3.0)
			draw_string(ThemeDB.fallback_font, Vector2(size.x * 0.5 - 6, 22), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)

	func _label(font: Font, at: Vector2, text: String, fs: int, col: Color, width: float = -1.0) -> void:
		var align := HORIZONTAL_ALIGNMENT_CENTER if width > 0.0 else HORIZONTAL_ALIGNMENT_LEFT
		draw_string_outline(font, at, text, align, width, fs, 6, Color.BLACK)
		draw_string(font, at, text, align, width, fs, col)


var full: MapCanvas
var mini: MapCanvas
var overlay: Control
var pos_label: Label
## Tests: skip the Net/Hud gating so the map can be driven without a running game.
var standalone := false

var _world: Node = null
var _player: Node = null
var _tex_world: Node = null
var _texture: Texture2D = null
var _prev_mouse := Input.MOUSE_MODE_CAPTURED


## Unit vector on the map (x right, y down = world XZ) the body faces for a yaw in radians.
static func heading_vec(yaw: float) -> Vector2:
	return MapCanvas.heading_vec(yaw)


static func height_color(h: float) -> Color:
	var stops: Array = HEIGHT_STOPS
	if h <= float(stops[0][0]):
		return stops[0][1]
	for i in range(1, stops.size()):
		if h <= float(stops[i][0]):
			var a: Array = stops[i - 1]
			var b: Array = stops[i]
			return (a[1] as Color).lerp(b[1], (h - float(a[0])) / (float(b[0]) - float(a[0])))
	return stops[stops.size() - 1][1]


## Top-down "render" of the whole world, built once per world (cached by the owner) and fully deterministic from
## the seed: the terrain's own ground colours (grass/dirt/rock/sand/road, via Terrain._tri_color) with a light
## hillshade, a dark forest floor, the dungeon crater, building footprints and tree/rock/bush stamps.
static func make_height_texture(world: Node, n: int = TEX_SIZE) -> ImageTexture:
	var t = world.terrain
	var half: float = float(t.HALF)
	var cell: float = half * 2.0 / float(n)
	var hts := PackedFloat32Array()
	hts.resize(n * n)
	for y in n:
		for x in n:
			hts[y * n + x] = t.height_at(-half + (float(x) + 0.5) * cell, -half + (float(y) + 0.5) * cell)
	var rd := _road_distances(t, n, cell, half)
	var real: bool = t.has_method("_tri_color") and t.has_method("_hash2")
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		var ym: int = maxi(y - 1, 0)
		var yp: int = mini(y + 1, n - 1)
		for x in n:
			var xm: int = maxi(x - 1, 0)
			var xp: int = mini(x + 1, n - 1)
			var h: float = hts[y * n + x]
			var hx: float = hts[y * n + xp] - hts[y * n + xm]
			var hz: float = hts[yp * n + x] - hts[ym * n + x]
			var col: Color
			if real:
				var wx: float = -half + (float(x) + 0.5) * cell
				var wz: float = -half + (float(y) + 0.5) * cell
				var ny: float = 2.0 * cell / Vector3(-hx, 2.0 * cell, -hz).length()
				col = t._tri_color(ny, h, rd[y * n + x], t._hash2(x, y), wx, wz)
				if t.forest_density(wx, wz) >= FOREST_CORE:
					col = col.lerp(TREE_COL, 0.3)
			else:
				col = height_color(h)
			var shade: float = 1.0 + clampf((hx + hz) * 0.5 / (2.0 * cell) * 0.8, -0.25, 0.25)
			img.set_pixel(x, y, Color(col.r * shade, col.g * shade, col.b * shade, 1.0))
	_stamp_dungeon(img, world, n, half, cell)
	_stamp_buildings(img, world, n, half, cell)
	_stamp_vegetation(img, world, n, half, cell)
	return ImageTexture.create_from_image(img)


## Distance from every texel centre to the nearest road centreline (1e9 beyond the verge), walking each road once.
static func _road_distances(t, n: int, cell: float, half: float) -> PackedFloat32Array:
	var rd := PackedFloat32Array()
	rd.resize(n * n)
	rd.fill(1.0e9)
	var reach: float = float(t.ROAD_WIDTH) * 0.5 + float(t.ROAD_EDGE)
	var r_px: int = int(ceil(reach / cell))
	for i in t.road_a.size():
		var a: Vector2 = t.road_a[i]
		var b: Vector2 = t.road_b[i]
		var steps: int = maxi(int(ceil(a.distance_to(b) / cell)), 1)
		var last := Vector2i(-99999, -99999)
		for s in steps + 1:
			var p: Vector2 = a.lerp(b, float(s) / float(steps))
			var cx: int = int(floor((p.x + half) / cell))
			var cy: int = int(floor((p.y + half) / cell))
			if cx == last.x and cy == last.y:
				continue
			last = Vector2i(cx, cy)
			for y in range(maxi(cy - r_px, 0), mini(cy + r_px + 1, n)):
				for x in range(maxi(cx - r_px, 0), mini(cx + r_px + 1, n)):
					var c := Vector2(-half + (float(x) + 0.5) * cell, -half + (float(y) + 0.5) * cell)
					var d: float = c.distance_to(Geometry2D.get_closest_point_to_segment(c, a, b))
					if d < rd[y * n + x]:
						rd[y * n + x] = d
	return rd


## Filled circle with a lit upper-left highlight; (x, z) in world metres.
static func _dot(img: Image, n: int, half: float, cell: float, p: Vector2, r: float, col: Color, hi: Color) -> void:
	var cx: float = (p.x + half) / cell - 0.5
	var cy: float = (p.y + half) / cell - 0.5
	var rp: float = maxf(r / cell, 0.9)
	for y in range(maxi(int(floor(cy - rp)), 0), mini(int(ceil(cy + rp)) + 1, n)):
		for x in range(maxi(int(floor(cx - rp)), 0), mini(int(ceil(cx + rp)) + 1, n)):
			var d := Vector2(float(x) - cx, float(y) - cy)
			if d.length() <= rp:
				img.set_pixel(x, y, hi if (d + Vector2(0.3, 0.3) * rp).length() < rp * 0.45 else col)


## Filled rectangle (size w x d metres, centre in world XZ, yaw `rot` like a location root) with a thin outline.
static func _fill_rect(img: Image, n: int, half: float, cell: float, centre: Vector2, rot: float, size: Vector2, col: Color, edge: Color) -> void:
	var rim: float = cell * 0.6
	var c: float = cos(rot)
	var s: float = sin(rot)
	var reach: float = size.length() * 0.5 + rim
	var x0: int = maxi(int(floor((centre.x - reach + half) / cell)), 0)
	var x1: int = mini(int(ceil((centre.x + reach + half) / cell)), n - 1)
	var y0: int = maxi(int(floor((centre.y - reach + half) / cell)), 0)
	var y1: int = mini(int(ceil((centre.y + reach + half) / cell)), n - 1)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var dx: float = -half + (float(x) + 0.5) * cell - centre.x
			var dz: float = -half + (float(y) + 0.5) * cell - centre.y
			var lx: float = absf(dx * c - dz * s)   # inverse of the Y rotation Basis(UP, rot)
			var lz: float = absf(dx * s + dz * c)
			if lx <= size.x * 0.5 and lz <= size.y * 0.5:
				img.set_pixel(x, y, col)
			elif lx <= size.x * 0.5 + rim and lz <= size.y * 0.5 + rim:
				img.set_pixel(x, y, edge)


static func _stamp_dungeon(img: Image, world: Node, n: int, half: float, cell: float) -> void:
	var site: Dictionary = world.get_meta("dungeon_site", {}) as Dictionary
	if site.has("gx") and site.has("gz"):   # the 36 x 36 m crater footprint
		_fill_rect(img, n, half, cell, Vector2(float(site["gx"]) + 18.0, float(site["gz"]) + 18.0), 0.0, Vector2(36.0, 36.0), Color(0.17, 0.14, 0.19), Color(0.32, 0.27, 0.34))


static func _stamp_buildings(img: Image, world: Node, n: int, half: float, cell: float) -> void:
	for l in world.locations:
		var rects: Array = FOOTPRINTS.get(str(l["type"]), [])
		var rot: float = float(l["rot"])
		var c: float = cos(rot)
		var s: float = sin(rot)
		var origin: Vector2 = l["pos2"]
		for r in rects:
			var lx: float = float(r[0])
			var lz: float = float(r[1])
			var centre := origin + Vector2(lx * c + lz * s, -lx * s + lz * c)   # Basis(UP, rot) * (lx, 0, lz)
			_fill_rect(img, n, half, cell, centre, rot, Vector2(float(r[2]), float(r[3])), r[4], OUTLINE_COL)
	# Hand-built cottages and city towers (world meta "hand_footprints": [x, z, w, d, yaw, kind, height])
	var hand: Array = world.get_meta("hand_footprints", []) as Array
	for f in hand:
		var is_tower: bool = str(f[5]) == "tower"
		var col: Color = HOUSE_COL
		if is_tower:
			var tint: float = clampf(float(f[6]) / 40.0, 0.0, 1.0)
			col = TOWER_COL.lerp(TOWER_HI, tint)
		_fill_rect(img, n, half, cell, Vector2(float(f[0]), float(f[1])), float(f[4]), Vector2(float(f[2]), float(f[3])), col, OUTLINE_COL)


## KayKitForest keeps every placed instance in its "sites" meta; the procedural trees (first Trunks-count entries of
## world.prop_points) then the procedural rocks and wrecks (the rest) come from the world builder.
static func _stamp_vegetation(img: Image, world: Node, n: int, half: float, cell: float) -> void:
	var sites: Array = []
	var forest: Node = world.get_node_or_null("KayKitForest")
	if forest != null and forest.has_meta("sites"):
		sites = forest.get_meta("sites") as Array
	for s in sites:
		if s[0] == "bush":
			_dot(img, n, half, cell, Vector2(s[1], s[2]), 1.0, BUSH_COL, BUSH_COL)
	for s in sites:
		if s[0] == "rock":
			_dot(img, n, half, cell, Vector2(s[1], s[2]), 1.1, ROCK_COL, ROCK_COL.lightened(0.15))
	var trunks: Node = world.get_node_or_null("Props/Trunks")
	var tree_n: int = (trunks as MultiMeshInstance3D).multimesh.instance_count if trunks is MultiMeshInstance3D else world.prop_points.size()
	for i in world.prop_points.size():
		if i < tree_n:
			continue
		_dot(img, n, half, cell, world.prop_points[i], 1.2, ROCK_COL, ROCK_COL.lightened(0.15))
	for i in mini(tree_n, world.prop_points.size()):
		_dot(img, n, half, cell, world.prop_points[i], 1.7, TREE_COL, TREE_HI)
	for s in sites:
		if s[0] == "tree":
			_dot(img, n, half, cell, Vector2(s[1], s[2]), 2.0, TREE_COL, TREE_HI)


func _ready() -> void:
	add_to_group(GROUP_ALL)
	if not InputMap.has_action(ACTION):
		InputMap.add_action(ACTION, 0.2)
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_M
		InputMap.action_add_event(ACTION, ev)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	mini = MapCanvas.new()
	mini.detailed = false
	mini.view_half = MINI_HALF
	mini.clip_contents = true
	mini.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mini.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	mini.offset_left = 16.0
	mini.offset_right = 16.0 + MINI_SIZE
	mini.offset_top = -16.0 - MINI_SIZE
	mini.offset_bottom = -16.0
	mini.visible = false
	add_child(mini)

	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.visible = false
	add_child(overlay)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.04, 0.03, 0.94)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(dim)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	overlay.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	margin.add_child(row)
	full = MapCanvas.new()
	full.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	full.size_flags_vertical = Control.SIZE_EXPAND_FILL
	full.mouse_filter = Control.MOUSE_FILTER_IGNORE
	full.clip_contents = true
	row.add_child(full)
	row.add_child(_build_legend())


func _build_legend() -> Control:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(300, 0)
	box.add_theme_constant_override("separation", 6)
	var title := Label.new()
	title.text = "MAP"
	title.add_theme_font_size_override("font_size", FONT_TITLE)
	box.add_child(title)
	pos_label = _legend_row(box, "", Color.WHITE)
	_legend_row(box, "Yellow arrow: you (facing)", PLAYER_COL)
	_legend_row(box, "Orange car: arrow = car heading", CAR_COL)

	for t in TYPE_STYLE:
		var st: Array = TYPE_STYLE[t]
		_legend_row(box, "%s  %s" % [st[1], st[2]], st[0])
	_legend_row(box, "Diamond  Dungeon", DUNGEON_COL)
	_legend_row(box, "Brown track  Road", Color(0.58, 0.46, 0.28))
	_legend_row(box, "Dark green dots  Trees", TREE_HI)
	_legend_row(box, "Roofs  Buildings", Color(0.85, 0.85, 0.88))

	_legend_row(box, "North is up", Color(1, 1, 1, 0.85))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)
	_legend_row(box, "M or Esc - Close", KEY_COL)
	return box


func _legend_row(parent: Control, text: String, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", FONT_BODY)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	parent.add_child(l)
	return l


# ---------------------------------------------------------------- public API

func is_open() -> bool:
	return overlay != null and overlay.visible


## Gives the map its data source; the Hud resolves both automatically when this is never called.
func bind(world: Node, player: Node) -> void:
	_world = world
	_player = player
	_sync()


func open() -> bool:
	if is_open() or _blocked():
		return false
	_resolve()
	_prev_mouse = Input.mouse_mode
	overlay.visible = true
	add_to_group(GROUP_OPEN)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_sync()
	opened.emit()
	return true


func close(recapture: bool = true) -> void:
	if not is_open():
		return
	overlay.visible = false
	remove_from_group(GROUP_OPEN)
	if recapture and not _blocked(true):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()


## What the map is about to draw, for tests: {half, roads, locations, dungeon, spawn, player, heading}.
func data() -> Dictionary:
	var d := {}
	if _world == null or not is_instance_valid(_world) or _world.get("terrain") == null:
		return d
	d["half"] = float(_world.terrain.HALF)
	d["roads"] = _world.terrain.road_a.size()
	d["locations"] = _world.locations.size()
	var site: Dictionary = _world.get_meta("dungeon_site", {}) as Dictionary
	if site.has("origin"):
		d["dungeon"] = site["origin"]
	d["spawn"] = _world.spawn_center
	if _player != null and is_instance_valid(_player) and _player is Node3D:
		var p := (_player as Node3D).global_position
		d["player"] = Vector2(p.x, p.z)
		d["heading"] = MapCanvas.player_heading(_player as Node3D)
		d["in_vehicle"] = MapCanvas.vehicle_of(_player) != null
	return d



# ------------------------------------------------------------------ internals

func _process(_delta: float) -> void:
	if not standalone:
		var net := get_node_or_null("/root/Net")
		if net == null or not bool(net.active):
			return
	_resolve()
	if _world == null:
		return
	if is_open():
		_sync()
	elif mini != null:
		mini.visible = true
		_sync_mini()


func _input(event: InputEvent) -> void:
	if is_open() and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(ACTION):
		if is_open():
			close()
			get_viewport().set_input_as_handled()
		elif open():
			get_viewport().set_input_as_handled()


func _resolve() -> void:
	if _world == null or not is_instance_valid(_world):
		_world = null
		var main := get_tree().get_first_node_in_group("main_world") if get_tree() != null else null
		if main != null and main.get("world") != null and is_instance_valid(main.get("world")):
			_world = main.get("world")
	if _player == null or not is_instance_valid(_player):
		var net := get_node_or_null("/root/Net")
		_player = net.get_local_player() if net != null and net.has_method("get_local_player") else null


func _sync() -> void:
	if _world == null:
		return
	_ensure_texture()
	for c in [full, mini]:
		c.world = _world
		c.player = _player
		c.view_half = float(_world.terrain.HALF) if c == full else MINI_HALF
	full.view_center = Vector2.ZERO
	_sync_mini()
	if _player != null and is_instance_valid(_player) and _player is Node3D:
		var p := (_player as Node3D).global_position
		pos_label.text = "You: X %d   Z %d" % [roundi(p.x), roundi(p.z)]
	full.queue_redraw()


## Builds the ground texture once per world and hands it to both canvases, so the minimap has it before the full map is ever opened.
func _ensure_texture() -> void:
	if _world == null:
		return
	if _tex_world != _world or _texture == null:
		_tex_world = _world
		_texture = make_height_texture(_world)
	full.texture = _texture
	mini.texture = _texture


func _sync_mini() -> void:
	_ensure_texture()
	mini.world = _world
	mini.player = _player
	if _player != null and is_instance_valid(_player) and _player is Node3D:
		var p := (_player as Node3D).global_position
		mini.view_center = Vector2(p.x, p.z)
	mini.queue_redraw()


func _blocked(closing: bool = false) -> bool:
	if standalone:
		return false
	var net := get_node_or_null("/root/Net")
	if not closing and (net == null or not bool(net.active)):
		return true
	var hud := get_node_or_null("/root/Hud")
	return hud != null and (bool(hud.is_paused()) or bool(hud.is_loot_open()))
