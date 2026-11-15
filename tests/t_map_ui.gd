extends SceneTree
## Map (scripts/ui/map_ui.gd): data comes from the real procedural world (terrain size, roads, locations, dungeon,
## spawn, player position + heading), coordinate mapping with north up, M / Esc / mouse mode, minimap follow,
## pause interplay and readable text. Real flow: host_solo + main.tscn through the Hud autoload.
## Not covered: how it LOOKS (headless uses a dummy renderer); only that drawing runs.
## Run: godot --headless --path . --script res://tests/t_map_ui.gd

const MapUI := preload("res://scripts/ui/map_ui.gd")

var fails := 0


func check(cond: bool, label: String) -> void:
	if cond:
		print("PASS  ", label)
	else:
		fails += 1
		print("FAIL  ", label)


func _initialize() -> void:
	_run.call_deferred()


func _frames(n: int = 2) -> void:
	for _i in n:
		await process_frame


func _action(name: String) -> InputEventAction:
	var ev := InputEventAction.new()
	ev.action = name
	ev.pressed = true
	return ev


func _run() -> void:
	await physics_frame
	# ---- pure helpers
	var h0 := MapUI.heading_vec(0.0)
	var h90 := MapUI.heading_vec(PI * 0.5)
	check(h0.distance_to(Vector2(0, -1)) < 0.001, "yaw 0 faces north (-Z, up on the map)")
	check(h90.distance_to(Vector2(-1, 0)) < 0.001, "yaw +90 deg (turn left) faces west (-X)")
	var lo := MapUI.height_color(-100.0)
	var hi := MapUI.height_color(500.0)
	check(lo == MapUI.HEIGHT_STOPS[0][1] and hi == MapUI.HEIGHT_STOPS[MapUI.HEIGHT_STOPS.size() - 1][1], "height_color clamps at both ends")
	check(MapUI.height_color(4.0) != MapUI.height_color(20.0), "height_color varies with height")
	var has_m := false
	var net: Node = root.get_node_or_null("Net")
	var hud: Node = root.get_node_or_null("Hud")
	check(net != null and hud != null, "Net and Hud autoloads present")
	if net == null or hud == null:
		print("RESULT  failures=%d" % fails)
		quit(1)
		return
	check(net.host_solo(31352) == OK, "Net.host_solo ok")
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	for _i in 30:
		await physics_frame
	var p = net.get_local_player()
	var world = main.get("world")
	check(p != null and world != null, "player and world exist")
	if p == null or world == null:
		print("RESULT  failures=%d" % fails)
		quit(1)
		return
	await _frames(3)
	var map: Node = null
	for c in hud.get_children():
		if c.get_script() != null and str(c.get_script().resource_path).ends_with("map_ui.gd"):
			map = c
	check(map != null, "Hud owns a map_ui child")
	if map == null:
		print("RESULT  failures=%d" % fails)
		quit(1)
		return
	for ev in InputMap.action_get_events("toggle_map"):
		has_m = has_m or (ev is InputEventKey and (ev as InputEventKey).physical_keycode == KEY_M)
	check(has_m, "action toggle_map is bound to M")

	# ---- data straight from world_builder
	var d: Dictionary = map.data()
	var t = world.terrain
	check(is_equal_approx(float(d.get("half", 0.0)), float(t.HALF)), "map terrain size = terrain.HALF (%.0f)" % float(t.HALF))
	check(int(d.get("roads", 0)) == t.road_a.size() and t.road_a.size() > 0, "map roads = terrain roads (%d)" % t.road_a.size())
	check(int(d.get("locations", 0)) == world.locations.size() and world.locations.size() > 0, "map locations = world.locations (%d)" % world.locations.size())
	var site: Dictionary = world.get_meta("dungeon_site", {}) as Dictionary
	check(site.has("origin") and d.has("dungeon") and (d["dungeon"] as Vector2) == (site["origin"] as Vector2), "dungeon marker position = dungeon_site origin")
	check((d["spawn"] as Vector2) == world.spawn_center, "spawn marker = world.spawn_center")
	var pp: Vector3 = p.global_position
	check((d["player"] as Vector2).distance_to(Vector2(pp.x, pp.z)) < 0.01, "player marker = player position")
	check((d["heading"] as Vector2).distance_to(MapUI.heading_vec(p.global_rotation.y)) < 0.001, "heading marker = player yaw")
	var types := {}
	var in_bounds := true
	for l in world.locations:
		types[str(l["type"])] = true
		var q: Vector2 = l["pos2"]
		in_bounds = in_bounds and absf(q.x) <= t.HALF and absf(q.y) <= t.HALF
	var unstyled: Array = []
	for ty in types:
		if not MapUI.TYPE_STYLE.has(ty):
			unstyled.append(ty)
	check(in_bounds, "every location lies inside the map bounds")
	check(unstyled.is_empty(), "every location type has a map style/legend entry %s" % str(unstyled))
	var tex: ImageTexture = MapUI.make_height_texture(world, 32)
	var img := tex.get_image()
	var distinct := {}
	for y in 32:
		for x in 32:
			distinct[img.get_pixel(x, y).to_html()] = true
	check(img.get_width() == 32 and distinct.size() > 3, "terrain texture is built from heights (%d distinct tints)" % distinct.size())

	# ---- minimap is on and follows the player while the full map is closed
	await _frames(3)
	check(map.mini.visible and not map.is_open(), "minimap shows during play, full map closed")
	check(map.mini.view_center.distance_to(Vector2(pp.x, pp.z)) < 0.5, "minimap is centred on the player")
	map.mini.size = Vector2(MapUI.MINI_SIZE, MapUI.MINI_SIZE)
	check(map.mini.world_to_map(map.mini.view_center).distance_to(map.mini.size * 0.5) < 0.01, "minimap centres the view point")

	# ---- open with M
	map._input(_action("toggle_map"))
	await _frames(3)
	check(map.is_open() and hud.is_ui_open() and not hud.is_paused(), "M opens the full map; Hud.is_ui_open() is true")
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "mouse is freed while the map is open")
	check(map.size.is_equal_approx(root.get_visible_rect().size) and map.overlay.size.is_equal_approx(map.size), "map overlay fills the screen (%s)" % str(map.overlay.size))
	var f = map.full
	check(f.size.x > 200.0 and f.size.y > 200.0, "full map canvas has a size (%dx%d)" % [int(f.size.x), int(f.size.y)])
	check(f.world_to_map(Vector2.ZERO).distance_to(f.size * 0.5) < 0.01, "world origin maps to the canvas centre")
	var nw: Vector2 = f.world_to_map(Vector2(-t.HALF, -t.HALF))
	var se: Vector2 = f.world_to_map(Vector2(t.HALF, t.HALF))
	check(nw.x < se.x and nw.y < se.y, "north-west corner is top-left (north up, east right)")
	var north: Vector2 = f.world_to_map(Vector2(0.0, -50.0))
	check(north.y < f.world_to_map(Vector2.ZERO).y, "a point north (-Z) is drawn higher")
	check(f.draw_count > 0, "full map drew (%d draws)" % f.draw_count)
	check(("X %d" % roundi(pp.x)) in map.pos_label.text, "legend shows the player coordinates")
	var small := 999
	var stack: Array = [map.overlay]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Label and (n as Label).text != "":
			small = mini(small, (n as Control).get_theme_font_size("font_size"))
		stack.append_array(n.get_children())
	check(small >= 20, "all map legend text is >= 20 px (smallest %d)" % small)

	# ---- player moves: marker follows
	p.global_position += Vector3(7, 0, -9)
	await _frames(2)
	var d2: Dictionary = map.data()
	check((d2["player"] as Vector2).distance_to(Vector2(pp.x + 7.0, pp.z - 9.0)) < 0.5, "player marker follows movement")

	# ---- Esc closes without opening the pause menu; M toggles
	map._input(_action("ui_cancel"))
	check(not map.is_open() and not hud.is_ui_open() and not hud.is_paused(), "Esc closes the map and does not open the pause menu")
	check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "mouse is recaptured on close")
	map._input(_action("toggle_map"))
	check(map.is_open(), "M reopens")
	map._input(_action("toggle_map"))
	check(not map.is_open(), "M closes")
	hud.open_pause()
	map._input(_action("toggle_map"))
	check(not map.is_open(), "M does nothing while paused")
	hud.close_pause(true)
	print("RESULT  failures=%d" % fails)
	quit(1 if fails > 0 else 0)
