extends RefCounted
## Kenney Survival Kit + Car Kit world dressing (CC0): abandoned vehicles, camps, signposts, barrels/crates,
## open-terrain trees and rocks. HAND-AUTHORED: every model is one row of the DRESSING section in
## data/hand_map/placements.json ([category, dir, file, height, x, z, yaw, collider_mode, lift]); nothing is drawn
## from a random generator or re-validated at runtime, so the dressing is identical on every run and peer.
## Everything lives under one "KenneyDressing" node with ONE StaticBody3D (many box/cylinder shapes, layer 1).
##
## Usage (world_builder): var d = KenneyDressing.new(self); add_child(d.build()); d.counts has the totals.

const ModelUtil = preload("res://scripts/world/model_util.gd")
const HandMapData = preload("res://tools/worldgen/hand_map_data.gd")

## The Car Kit folder and heights live in vehicle.gd (runtime); the dressing reuses them.
const CARS: String = preload("res://scripts/vehicles/vehicle.gd").CARS
const CAR_H: Dictionary = preload("res://scripts/vehicles/vehicle.gd").CAR_H

var world
var terrain
var node: Node3D
var counts := {"cars": 0, "cones": 0, "camps": 0, "camp_models": 0, "signposts": 0, "crates_barrels": 0, "trees": 0, "rocks": 0, "models": 0, "shapes": 0}


func _init(p_world) -> void:
	world = p_world
	terrain = p_world.terrain


func build() -> Node3D:
	node = Node3D.new()
	node.name = "KenneyDressing"
	for row in HandMapData.section("DRESSING"):
		_place(row as Array)
	return node


## mode: 0 none, 1 box (0.9 of the model's size), 2 slim cylinder (posts, trees). The collider is the model's OWN child
## (StaticBody3D "Body"), and the wrapper is an editor group, so clicking the model selects it and moving it moves both.
func _finish_put(m: Node3D, x: float, z: float, yaw: float, mode: int, lift: float = 0.0) -> Node3D:
	var y: float = terrain.height_at(x, z) + lift
	m.position = Vector3(x, y, z)
	m.rotation.y = yaw
	m.set_meta("_edit_group_", true)
	node.add_child(m)
	counts["models"] += 1
	var sz: Vector3 = m.get_meta("size") as Vector3
	if mode != 0:
		var body := StaticBody3D.new()
		body.name = "Body"
		m.add_child(body)
		var cs := CollisionShape3D.new()
		cs.name = "Shape"
		if mode == 1:
			var bs := BoxShape3D.new()
			bs.size = sz * 0.9
			cs.shape = bs
		else:
			var cyl := CylinderShape3D.new()
			cyl.radius = clampf(minf(sz.x, sz.z) * 0.3, 0.12, 0.45)
			cyl.height = sz.y
			cs.shape = cyl
		cs.position = Vector3(0.0, sz.y * 0.5, 0.0)
		body.add_child(cs)
		counts["shapes"] += 1
	return m


## One authored row: [category, dir, file, height, x, z, yaw, mode, lift].
func _place(row: Array) -> void:
	var cat: String = str(row[0])
	var dir: String = str(row[1])
	var file: String = str(row[2])
	var m: Node3D = ModelUtil.load_fit(dir + file + ".glb", float(row[3]))
	if m == null:
		push_warning("[KenneyDressing] missing model %s%s" % [dir, file])
		return
	_finish_put(m, float(row[4]), float(row[5]), float(row[6]), int(row[7]), float(row[8]))
	if counts.has(cat):
		counts[cat] += 1
	if cat == "camp_models" and file == "tent":
		counts["camps"] += 1
