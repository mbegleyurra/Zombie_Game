extends "res://scripts/world/loot_container.gd"
## A loot container dressed with a KayKit Dungeon Pack model (chest, gold chest, barrel, crates, bottle table).
## Same contract as loot_container.gd: groups "interactable" + "loot_container", interact(player), get_prompt(),
## apply_open_state(bool), signal opened. Contents are rolled deterministically from (world_seed, loot_id, table).
## Build it with setup_dungeon(loot_id, dkind, table, world_seed) BEFORE adding it to the tree.

const ModelUtil = preload("res://scripts/world/model_util.gd")
const DUN := "res://assets/kaykit/dungeon/KayKit_Dungeon_Pack_1.1_FREE/Assets/gltf/"

## model file, uniform scale (the pack is chunky next to a 1.8 m player), label and verb for the prompt
const DKINDS := {
	"chest": {"model": "chest.gltf", "scale": 0.6, "label": "Chest", "verb": "Open"},
	"gold_chest": {"model": "chest_gold.gltf", "scale": 0.65, "label": "Gold Chest", "verb": "Open"},
	"barrel": {"model": "barrel_large.gltf", "scale": 0.5, "label": "Barrel", "verb": "Search"},
	"barrel_small": {"model": "barrel_small.gltf", "scale": 0.7, "label": "Small Barrel", "verb": "Search"},
	"keg": {"model": "keg.gltf", "scale": 0.5, "label": "Keg", "verb": "Search"},
	"crates": {"model": "crates_stacked.gltf", "scale": 0.55, "label": "Stacked Crates", "verb": "Search"},
	"box": {"model": "box_large.gltf", "scale": 0.55, "label": "Large Box", "verb": "Search"},
	"bottle_table": {"model": "table_medium.gltf", "scale": 0.6, "label": "Bottle Table", "verb": "Search"},
}

var dkind: String = "box"
var model_size: Vector3 = Vector3.ONE
var _model: Node3D


func setup_dungeon(p_loot_id: int, p_dkind: String, p_table: String, world_seed: int) -> void:
	dkind = p_dkind if DKINDS.has(p_dkind) else "box"
	setup(p_loot_id, "crate", p_table, world_seed)
	# drop the plain box body and handle that loot_container builds; keep its collision shape
	for ch in get_children():
		if ch is MeshInstance3D:
			remove_child(ch)
			ch.free()
	var def: Dictionary = DKINDS[dkind]
	var sc: float = float(def["scale"])
	var ps := load(DUN + str(def["model"])) as PackedScene
	if ps == null:
		return
	var inst := ps.instantiate() as Node3D
	var boxes: Array = []
	ModelUtil._collect(inst, Transform3D.IDENTITY, boxes)
	if boxes.is_empty():
		inst.free()
		return
	var bb: AABB = boxes[0]
	for i in range(1, boxes.size()):
		bb = bb.merge(boxes[i])
	var c: Vector3 = bb.get_center()
	inst.scale = Vector3(sc, sc, sc)
	inst.position = Vector3(-c.x * sc, -bb.position.y * sc, -c.z * sc)
	_model = Node3D.new()
	_model.name = "Model"
	_model.add_child(inst)
	add_child(_model)
	model_size = bb.size * sc
	for ch in get_children():
		if ch is CollisionShape3D:
			(ch.shape as BoxShape3D).size = model_size
			ch.position = Vector3(0, model_size.y * 0.5, 0)
	if dkind == "bottle_table":
		_add_bottles()


func _add_bottles() -> void:
	var files: Array = ["bottle_A_brown.gltf", "bottle_B_green.gltf", "bottle_C_brown.gltf"]
	for i in files.size():
		var ps := load(DUN + str(files[i])) as PackedScene
		if ps == null:
			continue
		var b := ps.instantiate() as Node3D
		b.scale = Vector3(0.3, 0.3, 0.3)
		b.position = Vector3((float(i) - 1.0) * 0.3, model_size.y, (float(i % 2) - 0.5) * 0.3)
		b.rotation.y = float(i) * 1.7
		_model.add_child(b)


func get_prompt() -> String:
	var def: Dictionary = DKINDS[dkind]
	if is_open:
		return "%s (empty)" % str(def["label"])
	return "%s %s" % [str(def["verb"]), str(def["label"])]


func _set_open(open: bool) -> void:
	super._set_open(open)
	if _model == null:
		return
	var stack: Array = [_model]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for ch in n.get_children():
			stack.append(ch)
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.mesh == null:
				continue
			for s in mi.mesh.get_surface_count():
				if open:
					var m := mi.mesh.surface_get_material(s) as StandardMaterial3D
					if m != null:
						var dup := m.duplicate() as StandardMaterial3D
						dup.albedo_color = Color(0.45, 0.45, 0.48)
						mi.set_surface_override_material(s, dup)
				else:
					mi.set_surface_override_material(s, null)
