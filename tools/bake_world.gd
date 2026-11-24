extends SceneTree
## Bakes the generated world into hand-editable scenes under res://scenes/world/baked/.
## Run:  godot --headless --path . --script res://tools/bake_world.gd
## Runs the bake-only generator (tools/worldgen/gen_world.gd) once, then splits the result into sub-scenes, saves big
## meshes / shapes as .res files in baked/res/, imported models as instances of their source .glb/.gltf, vegetation as
## one prop-scene instance per object (scenes/world/props/vegetation/), roads as one mesh node per segment / junction,
## data as Marker3D nodes, and a heightmap. Writes baked/res/bake_manifest.json with the counts tools/verify_bake.gd
## checks. A MultiMesh anywhere in the output aborts the bake: every world object must be its own editable node.

const OUT := "res://scenes/world/baked/"
const RES := OUT + "res/"
const HandMapData = preload("res://tools/worldgen/hand_map_data.gd")
const ForestData = preload("res://scripts/world/forest_data.gd")
const SCENES := ["terrain", "roads", "buildings", "vegetation", "props", "dungeon", "vehicles", "markers"]
## Scripts that build their children in _ready(): their children are not saved (they would be built twice).
const RUNTIME_BUILT := ["res://scripts/world/loot_item.gd", "res://scripts/vehicles/vehicle.gd"]

var world
var subs := {}            # scene name -> Node3D root
var flatten := {}         # instance roots whose internals were edited (a child moved out): saved as plain nodes
var res_count := {}       # file prefix -> counter
var dup_map := {}         # original resource instance id -> saved copy
var stats := {"meshes": 0, "materials": 0, "shapes": 0, "imported_copies": 0, "meta_node_refs": 0}
var scripts_seen := {}
var road_segments: Array = []   # [ax, az, bx, bz] per terrain road segment
var flat_pads: Array = []       # [x, z, radius, blend, height] per terrain flat pad


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(RES))
	world = Node3D.new()
	world.set_script(load("res://tools/worldgen/gen_world.gd"))
	world.name = "World"
	root.add_child(world)
	world.build(1)
	await process_frame
	await process_frame
	for i in world.terrain.road_a.size():
		var a: Vector2 = world.terrain.road_a[i]
		var b: Vector2 = world.terrain.road_b[i]
		road_segments.append([a.x, a.y, b.x, b.y])
	for i in world.terrain.flat_pos.size():
		var fp: Vector2 = world.terrain.flat_pos[i]
		flat_pads.append([fp.x, fp.y, world.terrain.flat_radius[i], world.terrain.flat_blend[i], world.terrain.flat_height[i]])
	var builder := {
		"dressing": world.dressing_counts, "forest": world.forest_counts, "loot_nodes": world.loot_by_id.size(),
		"locations": world.locations.size(), "vehicles": world.get_node("Vehicles").get_child_count(),
	}
	_reset_vehicles()
	_find_edited_instances(world)
	# Sub-scene roots live under their own holder: the generated world already has children called Terrain, Props,
	# Dungeon and Vehicles, and a sibling with the same name would be renamed by Godot.
	var holder := Node3D.new()
	holder.name = "BakeOut"
	root.add_child(holder)
	for s in SCENES:
		var n := Node3D.new()
		n.name = String(s).capitalize().replace(" ", "")
		holder.add_child(n)
		subs[s] = n
	_split()
	_bake_heightmap()
	_seat_roads()
	for s in SCENES:
		_name_auto(subs[s])
	var manifest := {"builder": builder, "scenes": {}, "files": []}
	for s in SCENES:
		var sub: Node3D = subs[s]
		_strip_runtime(sub)
		_own(sub, sub)
		_externalize(sub, s)
		if stats.has("multimeshes_found"):
			push_error("[Bake] %d MultiMeshInstance3D node(s) in the output; aborting" % int(stats["multimeshes_found"]))
			quit(1)
			return
		manifest["scenes"][s] = {"nodes": _count(sub), "semantic": semantic_counts(sub)}
		var ps := PackedScene.new()
		var err := ps.pack(sub)
		if err != OK:
			push_error("[Bake] pack %s failed: %d" % [s, err])
			quit(1)
			return
		err = ResourceSaver.save(ps, OUT + s + ".tscn")
		print("[Bake] %s.tscn nodes=%d save=%d" % [s, manifest["scenes"][s]["nodes"], err])
	_save_world_scene()
	stats["flattened_instances"] = flatten.size()
	manifest["stats"] = stats
	manifest["scripts"] = scripts_seen.keys()
	var f := FileAccess.open(RES + "bake_manifest.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(manifest, "  "))
	f.close()
	print("[Bake] builder=%s" % JSON.stringify(builder))
	print("[Bake] stats=%s scripts=%s" % [JSON.stringify(stats), str(scripts_seen.keys())])
	quit(0)


# ------------------------------------------------------------------ splitting

func _move(n: Node, to: String, parent: Node = null) -> void:
	var dest: Node = parent if parent != null else subs[to]
	n.reparent(dest, true)


func _group_node(sub: String, gname: String) -> Node3D:
	var s: Node3D = subs[sub]
	var g := s.get_node_or_null(gname) as Node3D
	if g == null:
		g = Node3D.new()
		g.name = gname
		s.add_child(g)
	return g


func _split() -> void:
	# Loot first (containers sit inside buildings and the dungeon; ground loot at the world root): data -> markers.
	var ids: Array = world.loot_by_id.keys()
	ids.sort()
	for id in ids:
		var n = world.get_loot(id)
		if n == null:
			continue
		var grp: String = "LootContainers" if n.is_in_group("loot_container") else "GroundLoot"
		_move(n, "markers", _group_node("markers", grp))
	# Dungeon skeleton guards -> markers.
	for m in get_nodes_in_group("dungeon_skeleton_spawn"):
		_move(m, "markers", _group_node("markers", "DungeonSkeletonSpawns"))
	# Terrain: chunks move to a plain node (the terrain.gd generator script is not baked).
	var terr: Node = world.get_node("Terrain")
	for ch in terr.get_children():
		_move(ch, "terrain")
	# Roads mesh out of the hand world.
	var hand: Node = world.get_node("HandWorld")
	_move(hand.get_node("Roads"), "roads")
	for ch in world.get_children():
		if ch == terr:
			continue
		var nm := String(ch.name)
		if nm == "HandWorld" or ch.has_meta("loc_id"):
			_move(ch, "buildings")
		elif nm == "KayKitForest":
			_move(ch, "vegetation")
		elif nm == "Props" or nm == "KenneyDressing":
			_move(ch, "props")
		elif nm == "Dungeon":
			_move(ch, "dungeon")
		elif nm == "Vehicles":
			_move(ch, "vehicles")
		elif nm == "DayNight":
			pass   # rebuilt fresh in world_baked.tscn
		else:
			push_warning("[Bake] unassigned top-level node %s" % nm)
	_markers()


func _marker(parent: Node3D, nm: String, pos: Vector3, yaw: float, group: String, meta: Dictionary) -> Marker3D:
	var m := Marker3D.new()
	m.name = nm
	parent.add_child(m)
	m.position = pos
	m.rotation.y = yaw
	m.add_to_group(group, true)
	for k in meta:
		m.set_meta(k, meta[k])
	return m


func _markers() -> void:
	var mk: Node3D = subs["markers"]
	var g := _group_node("markers", "PlayerSpawns")
	for i in 8:
		_marker(g, "PlayerSpawn_%d" % i, world.get_spawn_point(i), 0.0, "player_spawn", {"slot": i})
	g = _group_node("markers", "Locations")
	for l in world.locations:
		_marker(g, "%s_%d" % [l["type"], l["id"]], l["pos"], float(l["rot"]), "location",
			{"id": int(l["id"]), "type": str(l["type"]), "name": str(l["name"]), "radius": float(l["radius"])})
	for sec in [["ZOMBIE_SPAWNS", "ZombieSpawns", "zombie_spawn", "Zombie"], ["SKELETON_SPAWNS", "SkeletonSpawns", "skeleton_spawn", "Skeleton"]]:
		g = _group_node("markers", sec[1])
		var i := 0
		for row in HandMapData.section(sec[0]):
			var r: Array = row
			var x: float = float(r[0])
			var z: float = float(r[1])
			_marker(g, "%s_%03d" % [sec[3], i], Vector3(x, world.get_height(x, z), z), float(r[2]), sec[2],
				{"index": i, "roll": float(r[3]), "variant_seed": int(r[4])})
			i += 1
	g = _group_node("markers", "VehicleSpawns")
	for car in subs["vehicles"].get_node("Vehicles").get_children():
		_marker(g, String(car.name), car.global_position, car.rotation.y, "vehicle_spawn", {"kind": str(car.kind)})
	# World-level data the map / dungeon code reads from world meta.
	for k in ["dungeon_site", "hand_footprints", "citykit"]:
		if world.has_meta(k):
			mk.set_meta(k, world.get_meta(k))
	mk.set_meta("spawn_center", world.spawn_center)
	# Road centrelines [ax, az, bx, bz] (generator data, captured before the split) for the map and road queries.
	mk.set_meta("roads", road_segments)
	# Flat pads [x, z, radius, blend, height] the generator carved (locations, camps, crater, city), same order.
	mk.set_meta("flats", flat_pads)


## Physics has run for a couple of frames, so cars have settled/fallen: put each back on its authored placement
## (exactly what vehicle_spawner.gd does) with no velocity, so the baked state is the spawn state.
func _reset_vehicles() -> void:
	var rows: Array = HandMapData.section("VEHICLES")
	var cars: Array = world.get_node("Vehicles").get_children()
	for i in mini(rows.size(), cars.size()):
		var r: Array = rows[i]
		var car: VehicleBody3D = cars[i]
		car.linear_velocity = Vector3.ZERO
		car.angular_velocity = Vector3.ZERO
		car.transform = Transform3D(Basis(Vector3.UP, float(r[3])),
			Vector3(float(r[1]), world.get_height(float(r[1]), float(r[2])) + 0.7, float(r[2])))


# ------------------------------------------------------------------ ownership

## Godot auto-names unnamed nodes "@Type@N" (N is a global counter, so it changes from bake to bake and is hard to find
## in the editor). Give each one a stable readable name: <hint>_<index among siblings with that hint>, where the hint
## is the source model of an instance, the first child of a plain wrapper, "Col<Shape>" for a collision shape, or the
## class. The generator is deterministic, so the same node gets the same name on every re-bake.
func _name_auto(n: Node) -> void:
	var used := {}
	for ch in n.get_children():
		used[String(ch.name)] = true
	var next := {}
	for ch in n.get_children():
		if String(ch.name).begins_with("@"):
			var hint := ch.get_class()
			if ch.scene_file_path != "":
				hint = ch.scene_file_path.get_slice("::", 0).get_file().get_basename()
			elif ch is CollisionShape3D and (ch as CollisionShape3D).shape != null:
				hint = "Col" + (ch as CollisionShape3D).shape.get_class().replace("Shape3D", "")
			elif ch.get_child_count() > 0 and ch.get_script() == null and not String(ch.get_child(0).name).begins_with("@"):
				hint = String(ch.get_child(0).name)
			hint = hint.validate_node_name().replace("@", "")
			var i: int = int(next.get(hint, 0))
			while used.has("%s_%d" % [hint, i]):
				i += 1
			next[hint] = i + 1
			var nm := "%s_%d" % [hint, i]
			used.erase(String(ch.name))
			used[nm] = true
			ch.name = nm
			stats["renamed_auto"] = int(stats.get("renamed_auto", 0)) + 1
		var inst: bool = ch.scene_file_path != "" and ch.scene_file_path.find("::") < 0
		if not inst or flatten.has(ch):
			_name_auto(ch)


## A node whose owner is not one of its ancestors was moved out of an imported model (a dungeon door leaf): that
## model can no longer be saved as a plain instance, so it and the moved node are saved as ordinary nodes.
## (Godot clears the owner of a node moved out of its owner's subtree, so it is detected by comparing each instance
## with a fresh instantiation of its source scene: a different node count means its internals were edited.)
var _fresh_counts := {}


func _find_edited_instances(n: Node) -> void:
	for ch in n.get_children():
		var sp: String = ch.scene_file_path
		if sp != "" and sp.find("::") < 0:
			if not _fresh_counts.has(sp):
				var fresh: Node = (load(sp) as PackedScene).instantiate()
				_fresh_counts[sp] = _count(fresh)
				fresh.free()
			if _count(ch) != int(_fresh_counts[sp]):
				flatten[ch] = true
		_find_edited_instances(ch)


func _strip_runtime(n: Node) -> void:
	for ch in n.get_children():
		var sc = ch.get_script()
		if sc != null and RUNTIME_BUILT.has(sc.resource_path):
			for gc in ch.get_children():
				ch.remove_child(gc)
				gc.free()
		else:
			_strip_runtime(ch)


func _own(n: Node, sub: Node) -> void:
	for ch in n.get_children():
		ch.owner = sub
		var sc = ch.get_script()
		if sc != null:
			scripts_seen[sc.resource_path] = true
		for gname in ch.get_groups():
			var gs := String(gname)
			if gs.begins_with("_"):
				continue
			ch.remove_from_group(gname)
			ch.add_to_group(gname, true)
		for mk in ch.get_meta_list():
			ch.set_meta(mk, _clean_meta(ch.get_meta(mk), sub))
		var inst := ch.scene_file_path != "" and ch.scene_file_path.find("::") < 0
		if inst and not flatten.has(ch):
			continue   # saved as an instance of its source scene; its internals come from the model file
		if inst:
			ch.scene_file_path = ""
		_own(ch, sub)


## Metadata cannot hold node references in a saved scene: they become NodePaths relative to the sub-scene root.
func _clean_meta(v, sub: Node):
	if v is Node:
		stats["meta_node_refs"] += 1
		return sub.get_path_to(v) if sub.is_ancestor_of(v) else NodePath()
	if v is Array:
		var a: Array = []
		for e in v:
			a.append(_clean_meta(e, sub))
		return a
	if v is Dictionary:
		var d := {}
		for k in v:
			d[k] = _clean_meta(v[k], sub)
		return d
	return v


# ------------------------------------------------------------------ resources

func _res_path(prefix: String, ext: String) -> String:
	var i: int = int(res_count.get(prefix, 0))
	res_count[prefix] = i + 1
	return RES + "%s_%04d.%s" % [prefix, i, ext]


func _needs_copy(r: Resource) -> bool:
	return r != null and (r.resource_path == "" or r.resource_path.find("::") >= 0)


## Saved (or reused) copy of a material; imported-model sub-resources are copied so the bake never points into
## .godot/imported.
func _material(m: Material, scene: String) -> Material:
	if not _needs_copy(m):
		return m
	var key := m.get_instance_id()
	if dup_map.has(key):
		return dup_map[key]
	var c: Material = m if m.resource_path == "" else m.duplicate()
	if m.resource_path != "":
		stats["imported_copies"] += 1
	var p := _res_path("mat", "tres")
	ResourceSaver.save(c, p)
	c.take_over_path(p)
	dup_map[key] = c
	stats["materials"] += 1
	return c


func _mesh(m: Mesh, scene: String) -> Mesh:
	if not _needs_copy(m):
		return m
	var key := m.get_instance_id()
	if dup_map.has(key):
		return dup_map[key]
	var c: Mesh = m if m.resource_path == "" else m.duplicate()
	if m.resource_path != "":
		stats["imported_copies"] += 1
		# Imported-model sub-resource: record which downloaded asset file it came from (tests/t_no_primitives.gd).
		c.set_meta("source_asset", m.resource_path.get_slice("::", 0))
	for s in c.get_surface_count():
		var sm: Material = c.surface_get_material(s)
		if sm != null:
			c.surface_set_material(s, _material(sm, scene))
	var p := _res_path("%s_mesh" % scene, "res")
	ResourceSaver.save(c, p, ResourceSaver.FLAG_COMPRESS)
	c.take_over_path(p)
	dup_map[key] = c
	stats["meshes"] += 1
	return c


func _externalize(n: Node, scene: String) -> void:
	for ch in n.get_children():
		if ch.scene_file_path != "":
			continue   # instance of an imported model: its resources live in the model file
		if ch is GeometryInstance3D:
			var gi := ch as GeometryInstance3D
			if gi.material_override != null:
				gi.material_override = _material(gi.material_override, scene)
			if gi.material_overlay != null:
				gi.material_overlay = _material(gi.material_overlay, scene)
		if ch is MeshInstance3D and (ch as MeshInstance3D).mesh != null:
			var mi := ch as MeshInstance3D
			mi.mesh = _mesh(mi.mesh, scene)
			for s in mi.get_surface_override_material_count():
				var om: Material = mi.get_surface_override_material(s)
				if om != null:
					mi.set_surface_override_material(s, _material(om, scene))
		elif ch is MultiMeshInstance3D:
			push_error("[Bake] %s is a MultiMeshInstance3D (not editable per object)" % ch.get_path())
			stats["multimeshes_found"] = int(stats.get("multimeshes_found", 0)) + 1
		elif ch is CollisionShape3D and (ch as CollisionShape3D).shape != null:
			var sh: Shape3D = (ch as CollisionShape3D).shape
			if sh.resource_path == "" and (sh is ConcavePolygonShape3D or (sh is ConvexPolygonShape3D and (sh as ConvexPolygonShape3D).points.size() > 64)):
				var p := _res_path("%s_shape" % scene, "res")
				ResourceSaver.save(sh, p, ResourceSaver.FLAG_COMPRESS)
				sh.take_over_path(p)
				stats["shapes"] += 1
		if ch.owner == subs[scene] and (ch.scene_file_path == "" or flatten.has(ch)):
			_externalize(ch, scene)


# ------------------------------------------------------------------ heightmap

## Bilinear height on the 1 m heightmap grid, exactly as scripts/world/baked_terrain.gd samples it at runtime.
func _grid_height(x: float, z: float) -> float:
	var terr = world.terrain
	var x0 := floorf(x)
	var z0 := floorf(z)
	var fx := x - x0
	var fz := z - z0
	var h00: float = terr.height_at(x0, z0)
	var h10: float = terr.height_at(x0 + 1.0, z0)
	var h01: float = terr.height_at(x0, z0 + 1.0)
	var h11: float = terr.height_at(x0 + 1.0, z0 + 1.0)
	return lerpf(lerpf(h00, h10, fx), lerpf(h01, h11, fx), fz)


## The generator lifted the road tiles 0.04 m above its analytic height. The baked ground is the 1 m grid, which cannot
## follow the steepest carved cuts (the dungeon approach drops ~1 m per 0.5 m), so a few road vertices ended up inside
## the visible ground. Raise any vertex below grid height + 0.04 m to that height; vertices above it are untouched.
func _seat_roads() -> void:
	var holder: Node = subs["roads"].get_node_or_null("Roads")
	if holder == null or holder.get_child_count() == 0:
		push_error("[Bake] Roads pieces missing")
		return
	var raised := 0
	for piece in holder.get_children():
		if piece is MeshInstance3D and (piece as MeshInstance3D).mesh is ArrayMesh:
			raised += _seat_road_piece(piece as MeshInstance3D)
	stats["road_vertices_raised"] = raised
	stats["road_pieces"] = holder.get_child_count()
	print("[Bake] roads: %d pieces, raised %d vertices onto the baked ground" % [holder.get_child_count(), raised])


func _seat_road_piece(roads: MeshInstance3D) -> int:
	var src := roads.mesh as ArrayMesh
	var xf: Transform3D = roads.global_transform
	var inv: Transform3D = xf.affine_inverse()
	var out := ArrayMesh.new()
	var raised := 0
	for s in src.get_surface_count():
		var arrays: Array = src.surface_get_arrays(s)
		var vs: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for i in vs.size():
			var g: Vector3 = xf * vs[i]
			var want: float = _grid_height(g.x, g.z) + 0.041
			if g.y < want:
				vs[i] = inv * Vector3(g.x, want, g.z)
				raised += 1
		arrays[Mesh.ARRAY_VERTEX] = vs
		out.add_surface_from_arrays(src.surface_get_primitive_type(s), arrays)
		out.surface_set_material(s, src.surface_get_material(s))
	out.resource_name = src.resource_name
	roads.mesh = out
	return raised


func _bake_heightmap() -> void:
	var terr = world.terrain
	var pad: int = int(terr.HALF) + 2
	var n: int = 2 * pad + 1
	var img := Image.create(n, n, false, Image.FORMAT_RF)
	for j in n:
		for i in n:
			img.set_pixel(i, j, Color(terr.height_at(float(i - pad), float(j - pad)), 0, 0))
	img.set_meta("origin", Vector2(-pad, -pad))
	img.set_meta("cell", 1.0)
	img.set_meta("size", n)
	ResourceSaver.save(img, RES + "heightmap.res", ResourceSaver.FLAG_COMPRESS)
	# exactness check against the generator at every grid point, read back from disk
	var back := ResourceLoader.load(RES + "heightmap.res", "", ResourceLoader.CACHE_MODE_IGNORE) as Image
	var max_err := 0.0
	for j in n:
		for i in n:
			max_err = maxf(max_err, absf(back.get_pixel(i, j).r - terr.height_at(float(i - pad), float(j - pad))))
	print("[Bake] heightmap %dx%d origin=%s max_err=%.6f" % [n, n, str(back.get_meta("origin")), max_err])
	_bake_groundmap(pad, n)


## Ground colours for the world map, on the heightmap grid: RGB = the generator's own terrain tint (_tri_color: grass,
## dirt, rock, sand, road) and A = forest density mapped from [-1, 1] to [0, 1] (a = (d + 1) / 2). The runtime map samples this instead of the noise.
func _bake_groundmap(pad: int, n: int) -> void:
	var terr = world.terrain
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for j in n:
		for i in n:
			var x := float(i - pad)
			var z := float(j - pad)
			var c: Color = terr._tri_color(terr.normal_at(x, z).y, terr.height_at(x, z), terr.road_distance(x, z),
				terr._hash2(i, j), x, z)
			c.a = clampf((terr.forest_density(x, z) + 1.0) * 0.5, 0.0, 1.0)
			img.set_pixel(i, j, c)
	img.set_meta("origin", Vector2(-pad, -pad))
	img.set_meta("cell", 1.0)
	ResourceSaver.save(img, RES + "groundmap.res", ResourceSaver.FLAG_COMPRESS)
	print("[Bake] groundmap %dx%d" % [n, n])


# ------------------------------------------------------------------ world scene + counts

## Written as text: packing live instances would store copies of their metadata as overrides, which would then hide
## later edits made inside the sub-scenes.
func _save_world_scene() -> void:
	var t := "[gd_scene format=3]\n\n"
	var i := 1
	for s in SCENES:
		t += "[ext_resource type=\"PackedScene\" path=\"%s%s.tscn\" id=\"%d\"]\n" % [OUT, s, i]
		i += 1
	t += "[ext_resource type=\"Script\" path=\"res://scripts/world/day_night.gd\" id=\"%d\"]\n\n" % i
	t += "[node name=\"World\" type=\"Node3D\"]\n\n"
	i = 1
	for s in SCENES:
		t += "[node name=\"%s\" parent=\".\" instance=ExtResource(\"%d\")]\n\n" % [String(s).capitalize().replace(" ", ""), i]
		i += 1
	t += "[node name=\"DayNight\" type=\"Node3D\" parent=\".\"]\nscript = ExtResource(\"%d\")\ntime_hours = %s\n" % [i, str(world.start_hour)]
	var f := FileAccess.open("res://scenes/world/world_baked.tscn", FileAccess.WRITE)
	f.store_string(t)
	f.close()
	print("[Bake] world_baked.tscn written (%d bytes)" % t.length())


func _count(n: Node) -> int:
	var c := 0
	for ch in n.get_children():
		c += 1 + _count(ch)
	return c


## Counts shared with verify_bake.gd: computed the same way on the live tree and on the loaded scene.
static func semantic_counts(sub: Node) -> Dictionary:
	var out := {"loot_containers": 0, "ground_loot": 0, "vehicles": 0, "multimeshes": 0, "veg_nodes": 0,
		"collision_shapes": 0, "glb_instances": 0, "markers": 0}
	var stack: Array = [sub]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for ch in n.get_children():
			stack.append(ch)
		var sc = n.get_script()
		var sp: String = sc.resource_path if sc != null else ""
		if sp.ends_with("loot_container.gd") or sp.ends_with("dungeon_container.gd"):
			out["loot_containers"] += 1
		elif sp.ends_with("loot_item.gd"):
			out["ground_loot"] += 1
		elif sp.ends_with("vehicle.gd"):
			out["vehicles"] += 1
		if n is MultiMeshInstance3D:
			out["multimeshes"] += 1
		if n != sub and ForestData.KINDS.has(str(n.get_meta("kind", ""))) and n.scene_file_path.begins_with("res://scenes/world/props/vegetation/"):
			out["veg_nodes"] += 1
		if n is CollisionShape3D:
			out["collision_shapes"] += 1
		if n is Marker3D:
			out["markers"] += 1
		if n != sub and n.scene_file_path != "":
			out["glb_instances"] += 1
	return out
