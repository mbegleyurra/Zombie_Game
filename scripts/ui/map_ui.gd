extends Control
## World map. Toggle: M (action "toggle_map", registered here in code). Full-screen map of the procedural world plus a
## small always-on minimap in the bottom-left corner. Drawn from world_builder data: terrain size (terrain.HALF) and
## height, roads (terrain.road_a/road_b), locations (world.locations), the dungeon (world meta "dungeon_site"),
## the spawn pad, other players, and the local player with a heading arrow. North (-Z) is up.
## Owned by the Hud autoload. Esc closes the full map; the mouse is released while it is open.

signal opened
signal closed

const ACTION := "toggle_map"
const GROUP_OPEN := "ui_open"        ## Hud.is_ui_open() is true while any member is in this group
const GROUP_ALL := "overlay_ui"
const HEIGHT_TEX := 96
const MINI_SIZE := 220.0
const MINI_HALF := 90.0
const FONT_TITLE := 48
const FONT_BODY := 22
const KEY_COL := Color(0.95, 0.8, 0.35)
const PLAYER_COL := Color(1.0, 0.92, 0.2)
const DUNGEON_COL := Color(0.9, 0.25, 0.9)
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
		var t = world.terrain
		var road_w := maxf(3.0, 3.2 * ppm * 1.8)
		for i in t.road_a.size():
			var a := world_to_map(t.road_a[i])
			var b := world_to_map(t.road_b[i])
			draw_line(a, b, Color(0.2, 0.14, 0.08), road_w + 2.0)
			draw_line(a, b, Color(0.76, 0.62, 0.4), road_w)
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
			var pp := (player as Node3D).global_position
			var pos := world_to_map(Vector2(pp.x, pp.z))
			var f: Vector2 = heading_vec((player as Node3D).global_rotation.y)
			var side := Vector2(-f.y, f.x)
			var s := 1.0 if detailed else 0.75
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


## Coarse top-down tint of the whole terrain (cached by the owner, one height_at call per texel).
static func make_height_texture(world: Node, n: int = HEIGHT_TEX) -> ImageTexture:
	var half: float = float(world.terrain.HALF)
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var wx := (float(x) + 0.5) / n * half * 2.0 - half
			var wz := (float(y) + 0.5) / n * half * 2.0 - half
			img.set_pixel(x, y, height_color(world.get_height(wx, wz)))
	return ImageTexture.create_from_image(img)


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
	for t in TYPE_STYLE:
		var st: Array = TYPE_STYLE[t]
		_legend_row(box, "%s  %s" % [st[1], st[2]], st[0])
	_legend_row(box, "Diamond  Dungeon", DUNGEON_COL)
	_legend_row(box, "Tan line  Road / track", Color(0.76, 0.62, 0.4))
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
		d["heading"] = heading_vec((_player as Node3D).global_rotation.y)
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
	if _tex_world != _world or _texture == null:
		_tex_world = _world
		_texture = make_height_texture(_world)
	for c in [full, mini]:
		c.world = _world
		c.player = _player
		c.texture = _texture
		c.view_half = float(_world.terrain.HALF) if c == full else MINI_HALF
	full.view_center = Vector2.ZERO
	_sync_mini()
	if _player != null and is_instance_valid(_player) and _player is Node3D:
		var p := (_player as Node3D).global_position
		pos_label.text = "You: X %d   Z %d" % [roundi(p.x), roundi(p.z)]
	full.queue_redraw()


func _sync_mini() -> void:
	mini.world = _world
	mini.player = _player
	mini.texture = _texture
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
