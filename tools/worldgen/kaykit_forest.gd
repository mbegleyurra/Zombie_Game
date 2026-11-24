extends RefCounted
## KayKit Forest Nature Pack (CC0, free tier) terrain dressing: trees, bushes, rocks and grass tufts.
## HAND-AUTHORED: every instance is one row of the FOREST section in data/hand_map/placements.json
## ([kind, model, x, z, yaw, scale]); nothing is drawn from a random generator, so the forest is identical on every
## run and peer. Every object is its OWN node so it can be selected, moved, copied or deleted in the editor:
##   KayKitForest/Trees|Bushes|Rocks|Grass/<Model>_<NNNN>  = an instance of a small prop scene
##   scenes/world/props/vegetation/<Model>.tscn (root carries meta "kind"; child "Mesh" = the model mesh, shared
##   resource; trees and big rocks also have their own StaticBody3D "Body" + CollisionShape3D, shared shape).
##   Big rocks use <Model>_Solid.tscn (box collider); small rocks, bushes and grass have no collider.
## The prop scenes are written once (when missing) and are hand-editable afterwards; the bake never overwrites them.
##
## Usage (world_builder): var f = KayKitForest.new(self); add_child(f.build()); f.counts has the totals.

const HandMapData = preload("res://tools/worldgen/hand_map_data.gd")

const DIR := "res://assets/kaykit/forest/KayKit_Forest_Nature_Pack_1.0_FREE/Assets/gltf/"
const PROP_DIR := "res://scenes/world/props/vegetation/"
const GROUPS := {"tree": "Trees", "bush": "Bushes", "rock": "Rocks", "grass": "Grass"}

const BIG_ROCK_H := 0.9       # rocks at least this tall get a box collider

var world
var terrain
var node: Node3D
var counts := {"trees": 0, "bushes": 0, "rocks": 0, "grass": 0, "shapes": 0, "prop_scenes": 0, "instances": 0}

## Every placed instance as [kind, x, z] (generator-side only; the baked scene stores no copy: the map and tests read
## the vegetation nodes via scripts/world/forest_data.gd, so a hand edit is always reflected).
var sites: Array = []

var _models: Dictionary = {}    # model name -> {mesh, off, tm, size} (empty when the file is missing)
var _props: Dictionary = {}     # prop scene name -> PackedScene
var _mean_scale: Dictionary = {} # tree model -> mean authored scale (sizes its shared trunk collider)
var _next: Dictionary = {}      # model -> next instance index


func _init(p_world) -> void:
	world = p_world
	terrain = p_world.terrain


func build() -> Node3D:
	node = Node3D.new()
	node.name = "KayKitForest"
	for kind in GROUPS:
		var g := Node3D.new()
		g.name = GROUPS[kind]
		node.add_child(g)
	var rows: Array = HandMapData.section("FOREST")
	var sums := {}
	for row in rows:
		if str(row[0]) == "tree":
			var sm: Array = sums.get(str(row[1]), [0.0, 0])
			sums[str(row[1])] = [float(sm[0]) + float(row[5]), int(sm[1]) + 1]
	for k in sums:
		_mean_scale[k] = float(sums[k][0]) / float(sums[k][1])
	for row in rows:
		_place(row as Array)
	return node


# ------------------------------------------------------------------ models

## Loads one model once: its mesh, the offset that seats it on y = 0 centred on x/z, and its native size.
func _model(mname: String) -> Dictionary:
	if _models.has(mname):
		return _models[mname]
	var out: Dictionary = {}
	var path: String = DIR + mname + "_Color1.gltf"
	var ps: PackedScene = null
	if ResourceLoader.exists(path):
		ps = load(path) as PackedScene
	if ps == null:
		push_warning("[KayKitForest] missing model %s" % path)
		_models[mname] = out
		return out
	var inst: Node = ps.instantiate()
	var found: Array = []
	_collect(inst, Transform3D.IDENTITY, found)
	if not found.is_empty():
		var tm: Transform3D = found[0][0]
		var mesh: Mesh = found[0][1]
		var bb: AABB = tm * mesh.get_aabb()
		var c: Vector3 = bb.get_center()
		out = {"mesh": mesh, "tm": tm, "size": bb.size, "off": Vector3(-c.x, -bb.position.y, -c.z)}
	inst.free()
	_models[mname] = out
	return out


func _collect(n: Node, xf: Transform3D, out: Array) -> void:
	var t: Transform3D = xf
	if n is Node3D:
		t = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append([t, (n as MeshInstance3D).mesh])
	for ch in n.get_children():
		_collect(ch, t, out)


# ------------------------------------------------------------------ prop scenes (written once, then hand-editable)

## The mesh copied out of the model file (materials duplicated in, textures stay the pack's png), tagged with the
## asset it came from (tests/t_no_primitives.gd). Shared by every instance of the model.
func _mesh_res(mname: String) -> Mesh:
	var p: String = PROP_DIR + "res/" + mname + ".res"
	if ResourceLoader.exists(p):
		return load(p) as Mesh
	var src: Mesh = _model(mname)["mesh"]
	var c: Mesh = src.duplicate()
	for s in c.get_surface_count():
		var sm: Material = c.surface_get_material(s)
		if sm != null and (sm.resource_path == "" or sm.resource_path.contains("::")):
			c.surface_set_material(s, sm.duplicate())
	c.set_meta("source_asset", DIR + mname + "_Color1.gltf")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PROP_DIR + "res/"))
	ResourceSaver.save(c, p, ResourceSaver.FLAG_COMPRESS)
	return load(p) as Mesh


## <Model>.tscn (no collider) or <Model>_Solid.tscn (rock with a box) / trees (always a trunk cylinder). Sizes are for
## scale 1; each placed instance is scaled uniformly, which scales its collider with it.
func _prop(kind: String, mname: String, solid: bool) -> PackedScene:
	var pname: String = mname + ("_Solid" if solid and kind == "rock" else "")
	if _props.has(pname):
		return _props[pname]
	var path: String = PROP_DIR + pname + ".tscn"
	if not ResourceLoader.exists(path):
		var m: Dictionary = _model(mname)
		var sz: Vector3 = m["size"]
		var root := Node3D.new()
		root.name = pname
		root.set_meta("kind", kind)
		var mi := MeshInstance3D.new()
		mi.name = "Mesh"
		mi.mesh = _mesh_res(mname)
		mi.transform = Transform3D(Basis.IDENTITY, m["off"] as Vector3) * (m["tm"] as Transform3D)
		match kind:
			"tree", "rock":
				mi.visibility_range_end = 260.0
			"bush":
				mi.visibility_range_end = 150.0
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_:
				mi.visibility_range_end = 110.0
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end_margin = 15.0
		root.add_child(mi)
		mi.owner = root
		if solid:
			var body := StaticBody3D.new()
			body.name = "Body"
			root.add_child(body)
			body.owner = root
			var cs := CollisionShape3D.new()
			cs.name = "Shape"
			if kind == "tree":
				# Trunk cylinder sized at this model's mean authored scale (the old per-tree clamp, expressed at s = 1).
				var ms: float = float(_mean_scale.get(mname, 1.0))
				var cyl := CylinderShape3D.new()
				cyl.radius = clampf(minf(sz.x, sz.z) * ms * 0.08, 0.25, 0.55) / ms
				cyl.height = minf(sz.y * ms, 3.5) / ms
				cs.shape = cyl
				cs.position = Vector3(0.0, cyl.height * 0.5, 0.0)
			else:
				var bs := BoxShape3D.new()
				bs.size = sz * 0.8
				cs.shape = bs
				cs.position = Vector3(0.0, bs.size.y * 0.5, 0.0)
			body.add_child(cs)
			cs.owner = root
		var ps := PackedScene.new()
		ps.pack(root)
		ResourceSaver.save(ps, path)
		root.free()
		counts["prop_scenes"] += 1
	_props[pname] = load(path) as PackedScene
	return _props[pname]


# ------------------------------------------------------------------ placement (read from data)

## One authored row: [kind, model, x, z, yaw, scale]. Colliders are derived from the model size and the row's scale.
func _place(row: Array) -> void:
	var kind: String = str(row[0])
	var mname: String = str(row[1])
	var x: float = float(row[2])
	var z: float = float(row[3])
	var yaw: float = float(row[4])
	var s: float = float(row[5])
	var m: Dictionary = _model(mname)
	if m.is_empty():
		return
	var sz: Vector3 = m["size"]
	var solid: bool = kind == "tree" or (kind == "rock" and sz.y * s >= BIG_ROCK_H)
	var inst: Node3D = _prop(kind, mname, solid).instantiate() as Node3D
	var i: int = int(_next.get(mname, 0)) + 1
	_next[mname] = i
	inst.name = "%s_%04d" % [mname, i]
	var y: float = terrain.height_at(x, z) - 0.04 * s
	inst.transform = Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(s, s, s)), Vector3(x, y, z))
	node.get_node(GROUPS.get(kind, "Grass")).add_child(inst)
	counts["instances"] += 1
	sites.append([kind, x, z])
	if solid:
		counts["shapes"] += 1
	match kind:
		"tree":
			counts["trees"] += 1
		"rock":
			counts["rocks"] += 1
		"bush":
			counts["bushes"] += 1
		_:
			counts["grass"] += 1
