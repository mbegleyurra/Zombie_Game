extends StaticBody3D
## A searchable container (cupboard, fridge, crate, shelf, locker, ...). Group "interactable" + "loot_container".
## Contents are rolled in setup() from (world_seed, loot_id), so every peer gets identical contents.
## Player interaction contract:
##   c.get_prompt() -> String
##   c.interact(player) -> bool   (gives contents via player.add_item(id, count) if present; leftovers drop on the ground)
## Network hooks: signal opened(container, by); c.apply_open_state(true) marks it opened without giving items.

signal opened(container, by)

const ItemDB = preload("res://scripts/world/item_db.gd")
const LootItem = preload("res://scripts/world/loot_item.gd")

const KINDS := {
	"cupboard": {"size": Vector3(0.9, 1.8, 0.5), "color": Color(0.5, 0.33, 0.2), "label": "Cupboard"},
	"fridge": {"size": Vector3(0.8, 1.8, 0.7), "color": Color(0.85, 0.88, 0.9), "label": "Fridge"},
	"crate": {"size": Vector3(0.9, 0.7, 0.9), "color": Color(0.72, 0.55, 0.3), "label": "Crate"},
	"shelf": {"size": Vector3(1.6, 1.9, 0.5), "color": Color(0.45, 0.45, 0.52), "label": "Shelf"},
	"locker": {"size": Vector3(0.6, 1.9, 0.6), "color": Color(0.3, 0.42, 0.55), "label": "Locker"},
	"med_cabinet": {"size": Vector3(1.0, 1.8, 0.5), "color": Color(0.82, 0.92, 0.93), "label": "Medical Cabinet"},
	"register": {"size": Vector3(0.6, 0.35, 0.5), "color": Color(0.2, 0.2, 0.24), "label": "Cash Register"},
	"toolbox": {"size": Vector3(0.7, 0.4, 0.35), "color": Color(0.8, 0.2, 0.15), "label": "Toolbox"},
	"weapon_rack": {"size": Vector3(1.4, 1.6, 0.4), "color": Color(0.2, 0.22, 0.25), "label": "Weapon Rack"},
	"evidence_locker": {"size": Vector3(0.8, 1.2, 0.5), "color": Color(0.35, 0.38, 0.42), "label": "Evidence Locker"},
	"altar_chest": {"size": Vector3(1.0, 0.8, 0.55), "color": Color(0.42, 0.18, 0.16), "label": "Altar Chest"},
	"donation_box": {"size": Vector3(0.4, 1.1, 0.4), "color": Color(0.55, 0.5, 0.4), "label": "Donation Box"},
	"pallet_crate": {"size": Vector3(1.2, 1.1, 1.2), "color": Color(0.6, 0.45, 0.25), "label": "Pallet Crate"},
}

var loot_id: int = -1
var kind: String = "crate"
var table: String = "wild"
var is_open: bool = false
var contents: Array = []   # [{"id": String, "count": int}]

var _mesh: MeshInstance3D
var _mat: StandardMaterial3D
var _base_color: Color = Color(0.7, 0.55, 0.3)


## Call BEFORE adding to the tree. Builds visuals/collision and rolls contents deterministically.
func setup(p_loot_id: int, p_kind: String, p_table: String, world_seed: int) -> void:
	loot_id = p_loot_id
	kind = p_kind if KINDS.has(p_kind) else "crate"
	table = p_table
	name = "Container_%d" % loot_id
	var def: Dictionary = KINDS[kind]
	var size: Vector3 = def["size"]
	_base_color = def["color"]
	var rng := RandomNumberGenerator.new()
	rng.seed = (world_seed * 1000003 + loot_id * 7919 + 17) & 0x7FFFFFFF
	contents = ItemDB.roll_table(table, rng)

	_mat = StandardMaterial3D.new()
	_mat.albedo_color = _base_color
	_mat.roughness = 0.85
	var bm := BoxMesh.new()
	bm.size = size
	_mesh = MeshInstance3D.new()
	_mesh.name = "Body"
	_mesh.mesh = bm
	_mesh.material_override = _mat
	_mesh.position = Vector3(0, size.y * 0.5, 0)
	add_child(_mesh)
	# Handle on the +Z (front) face so the opening side is readable.
	var hm := BoxMesh.new()
	hm.size = Vector3(0.06, minf(0.4, size.y * 0.5), 0.05)
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = Color(0.12, 0.12, 0.13)
	var handle := MeshInstance3D.new()
	handle.mesh = hm
	handle.material_override = hmat
	handle.position = Vector3(size.x * 0.28, size.y * 0.55, size.z * 0.5 + 0.02)
	add_child(handle)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = Vector3(0, size.y * 0.5, 0)
	add_child(cs)


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("loot_container")


func get_prompt() -> String:
	var label: String = str((KINDS[kind] as Dictionary)["label"])
	return ("%s (empty)" % label) if is_open else ("Search %s" % label)


func interact(by = null) -> bool:
	if is_open:
		return false
	_set_open(true)
	var leftover: Array = []
	for it in contents:
		var d: Dictionary = it
		if by != null:
			if not ItemDB.give_to(by, str(d["id"]), int(d["count"])):
				leftover.append(d)
		else:
			leftover.append(d)
	_drop(leftover)
	opened.emit(self, by)
	return true


## Network/state sync: mark opened (or closed) without handing out any items.
func apply_open_state(open: bool) -> void:
	_set_open(open)


func _set_open(open: bool) -> void:
	is_open = open
	if _mat:
		_mat.albedo_color = _base_color.darkened(0.45) if open else _base_color


func _drop(items: Array) -> void:
	var parent: Node = get_parent()
	if parent == null:
		return
	var i := 0
	for it in items:
		var d: Dictionary = it
		var item = LootItem.create(str(d["id"]), int(d["count"]), -1)
		parent.add_child(item)
		var a := float(i) * 1.9
		item.global_position = global_position + global_transform.basis.z * 0.9 + Vector3(cos(a) * 0.35, 0.05, sin(a) * 0.35)
		if parent.has_method("register_loot"):
			parent.register_loot(item)
		i += 1
