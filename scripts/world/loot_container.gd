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
const ModelFit = preload("res://scripts/world/model_util.gd")

## kind -> [downloaded model]. All Kenney (mini-shop, mini-arcade, survival, graveyard).
const K := "res://assets/kenney/"
const MODELS := {
	"cupboard": [K + "mini-shop/shelf-boxes.glb"],
	"fridge": [K + "mini-arcade/vending-machine.glb"],
	"crate": [K + "survival/box-large.glb"],
	"shelf": [K + "mini-shop/shelf-bags.glb"],
	"locker": [K + "mini-arcade/vending-machine.glb"],
	"med_cabinet": [K + "mini-shop/shelf-boxes.glb"],
	"register": [K + "mini-shop/cash-register.glb"],
	"toolbox": [K + "survival/chest.glb"],
	"weapon_rack": [K + "mini-shop/shelf-bags.glb"],
	"evidence_locker": [K + "mini-arcade/vending-machine.glb"],
	"altar_chest": [K + "graveyard/altar-stone.glb"],
	"donation_box": [K + "graveyard/pillar-square.glb"],
	"pallet_crate": [K + "survival/box-large.glb"],
}

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

var _body_model: Node3D
var _base_color: Color = Color(0.7, 0.55, 0.3)
static var _overlay: StandardMaterial3D


static func _open_overlay() -> StandardMaterial3D:
	if _overlay == null:
		_overlay = StandardMaterial3D.new()
		_overlay.albedo_color = Color(0, 0, 0, 0.45)
		_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return _overlay


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

	# Visual is a downloaded Kenney model fitted to the container's footprint (no primitive meshes).
	var spec: Array = MODELS.get(kind, MODELS["crate"]) as Array
	var model: Node3D = ModelFit.load_fit(str(spec[0]), size.y)
	if model != null:
		var msz: Vector3 = model.get_meta("size") as Vector3
		model.scale = Vector3(clampf(size.x / maxf(msz.x, 0.01), 0.6, 1.8), 1.0, clampf(size.z / maxf(msz.z, 0.01), 0.6, 1.8))
		model.name = "Body"
		add_child(model)
		_body_model = model
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
	if _body_model == null:
		return
	# Opened containers are darkened with a translucent overlay so the model keeps its own textures.
	for mi in _body_model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_overlay = _open_overlay() if open else null


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
