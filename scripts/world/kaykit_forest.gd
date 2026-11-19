extends RefCounted
## KayKit Forest Nature Pack (CC0, free tier) terrain dressing: trees, bushes, rocks and grass tufts.
## HAND-AUTHORED: every instance is one row of the FOREST section in data/hand_map/placements.json
## ([kind, model, x, z, yaw, scale]); nothing is drawn from a random generator, so the forest is identical on every
## run and peer. Everything lives under one "KayKitForest" node:
##   - one MultiMeshInstance3D per (model, 128 m cell), with a visibility range, so the cost stays low;
##   - ONE StaticBody3D "Collision" (layer 1) holding a cylinder per tree and a box per big rock.
##     Bushes, grass and small rocks have no collider.
##
## Usage (world_builder): var f = KayKitForest.new(self); add_child(f.build()); f.counts has the totals.

const HandMapData = preload("res://scripts/world/hand_map_data.gd")

const DIR := "res://assets/kaykit/forest/KayKit_Forest_Nature_Pack_1.0_FREE/Assets/gltf/"

const CELL := 128.0           # MultiMesh cell size (frustum culling + visibility range work per cell)
const BIG_ROCK_H := 0.9       # rocks at least this tall get a box collider

var world
var terrain
var node: Node3D
var body: StaticBody3D
var counts := {"trees": 0, "bushes": 0, "rocks": 0, "grass": 0, "shapes": 0, "multimeshes": 0, "instances": 0}

## Every queued instance as [kind, x, z]; also exposed as node meta "sites" (the headless renderer cannot read
## MultiMesh transforms back, so tests and tools use this).
var sites: Array = []

var _models: Dictionary = {}    # model name -> {mesh, off, tm, size} (empty when the file is missing)
var _buckets: Dictionary = {}   # "kind|model|cx|cz" -> Array of Transform3D


func _init(p_world) -> void:
	world = p_world
	terrain = p_world.terrain


func build() -> Node3D:
	node = Node3D.new()
	node.name = "KayKitForest"
	body = StaticBody3D.new()
	body.name = "Collision"
	node.add_child(body)
	for row in HandMapData.section("FOREST"):
		_place(row as Array)
	_flush()
	node.set_meta("sites", sites)
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


## Queues one instance, scaled uniformly by s, seated on the terrain.
func _queue(kind: String, mname: String, x: float, z: float, yaw: float, s: float) -> float:
	var m: Dictionary = _model(mname)
	var y: float = terrain.height_at(x, z) - 0.04 * s
	var place := Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(s, s, s)), Vector3(x, y, z))
	var xf: Transform3D = place * Transform3D(Basis.IDENTITY, m["off"] as Vector3) * (m["tm"] as Transform3D)
	var cx: int = clampi(floori((x + terrain.HALF) / CELL), 0, int(ceil(2.0 * terrain.HALF / CELL)) - 1)
	var cz: int = clampi(floori((z + terrain.HALF) / CELL), 0, int(ceil(2.0 * terrain.HALF / CELL)) - 1)
	var key := "%s|%s|%d|%d" % [kind, mname, cx, cz]
	if not _buckets.has(key):
		_buckets[key] = []
	(_buckets[key] as Array).append(xf)
	counts["instances"] += 1
	sites.append([kind, x, z])
	return y


func _flush() -> void:
	for key in _buckets:
		var arr: Array = _buckets[key]
		var parts: PackedStringArray = String(key).split("|")
		var kind: String = parts[0]
		var m: Dictionary = _model(parts[1])
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = m["mesh"] as Mesh
		mm.instance_count = arr.size()
		for i in arr.size():
			mm.set_instance_transform(i, arr[i] as Transform3D)
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "%s_%s_%s_%s" % [kind, parts[1], parts[2], parts[3]]
		mmi.multimesh = mm
		match kind:
			"tree", "rock":
				mmi.visibility_range_end = 260.0
			"bush":
				mmi.visibility_range_end = 150.0
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_:
				mmi.visibility_range_end = 110.0
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end_margin = 15.0
		node.add_child(mmi)
		counts["multimeshes"] += 1


func _cyl(x: float, y: float, z: float, r: float, h: float) -> void:
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = r
	sh.height = h
	cs.shape = sh
	cs.position = Vector3(x, y + h * 0.5, z)
	body.add_child(cs)
	counts["shapes"] += 1


func _box(x: float, y: float, z: float, yaw: float, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	cs.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(x, y + size.y * 0.5, z))
	body.add_child(cs)
	counts["shapes"] += 1


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
	var y: float = _queue(kind, mname, x, z, yaw, s)
	match kind:
		"tree":
			_cyl(x, y, z, clampf(minf(sz.x, sz.z) * s * 0.08, 0.25, 0.55), minf(sz.y * s, 3.5))
			counts["trees"] += 1
		"rock":
			if sz.y * s >= BIG_ROCK_H:
				_box(x, y, z, yaw, Vector3(sz.x, sz.y, sz.z) * s * 0.8)
			counts["rocks"] += 1
		"bush":
			counts["bushes"] += 1
		_:
			counts["grass"] += 1
