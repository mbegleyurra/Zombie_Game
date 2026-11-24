extends StaticBody3D
## A pickup lying on the ground. Group "interactable" + "loot_item".
## Player interaction contract:
##   item.get_prompt() -> String
##   item.interact(player) -> bool   (calls player.add_item(id, count) if present; a bool false return = inventory full)
## Collision layer is ITEM_LAYER (bit 4, value 8) so items never block movement but ray casts can hit them.

signal picked_up(item, by)

const ItemDB = preload("res://scripts/world/item_db.gd")
const ModelUtil = preload("res://scripts/world/model_util.gd")
const PickupVisuals = preload("res://scripts/world/pickup_visuals.gd")
const SELF_PATH := "res://scripts/world/loot_item.gd"
const ITEM_LAYER := 8

@export var item_id: String = "scrap"
@export var count: int = 1
@export var loot_id: int = -1

var _visual: Node3D
var _t: float = 0.0


## Factory: LootItem.create("medkit", 1, loot_id)
static func create(p_item_id: String, p_count: int, p_loot_id: int = -1) -> StaticBody3D:
	var script: GDScript = load(SELF_PATH)
	var it = script.new()
	it.item_id = p_item_id
	it.count = p_count
	it.loot_id = p_loot_id
	it.name = "Loot_%d" % p_loot_id if p_loot_id >= 0 else "Loot"
	return it


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("loot_item")
	collision_layer = ITEM_LAYER
	collision_mask = 0
	_build_visual()
	_t = float(abs(loot_id) % 100) * 0.3


func get_prompt() -> String:
	return "Pick up %s x%d" % [ItemDB.item_name(item_id), count]


func interact(by = null) -> bool:
	if by != null and not ItemDB.give_to(by, item_id, count):
		return false
	picked_up.emit(self, by)
	queue_free()
	return true


func _process(delta: float) -> void:
	_t += delta
	if _visual:
		_visual.rotation.y = _t * 1.2
		_visual.position.y = 0.05 + (sin(_t * 2.4) * 0.5 + 0.5) * 0.05


func _build_visual() -> void:
	var info: Dictionary = ItemDB.get_item(item_id)
	var col: Color = ItemDB.item_color(item_id)
	var shape_kind: String = str(info.get("shape", "box"))
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	var model_path: String = str(info.get("model", ""))
	var model_height: float = float(info.get("model_height", 0.25))
	# Optional "models": [[path, height], ...]. The variant is chosen from loot_id, so every peer
	# (and the world seed) shows the same model for the same pickup.
	var variants: Array = info.get("models", []) as Array
	if not variants.is_empty():
		var pick: Array = variants[absi(loot_id) % variants.size()] as Array
		model_path = str(pick[0])
		model_height = float(pick[1])
	# Weapons lie on the ground as their ITHappy pack model (GunMesh); falls through to the old box gun if absent.
	if shape_kind == "gun" and model_path == "" and WeaponDB.has_weapon(str(info.get("weapon_id", ""))):
		var gm: Node3D = GunMesh.world_pickup(WeaponDB.get_weapon(str(info["weapon_id"])).model)
		if gm != null:
			_visual.add_child(gm)
			_add_box_collision(gm.get_meta("size") as Vector3)
			return
	# Every other pickup gets its own model + colour from PickupVisuals, with a coloured glow disc under it.
	if shape_kind != "gun":
		var pm: Node3D = PickupVisuals.instantiate(item_id, loot_id)
		if pm != null:
			_visual.add_child(pm)
			_add_box_collision(pm.get_meta("size") as Vector3)
			_add_glow(PickupVisuals.accent(item_id))
			return
	if model_path != "":
		var m: Node3D = ModelUtil.load_fit(model_path, model_height)
		if m != null:
			_visual.add_child(m)
			_add_box_collision(m.get_meta("size") as Vector3)
			return
	var size := Vector3(0.22, 0.12, 0.16)
	_add_box_collision(size)


func _add_box_collision(size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size + Vector3(0.12, 0.12, 0.12)
	cs.shape = bs
	cs.position = Vector3(0, size.y * 0.5, 0)
	add_child(cs)


## Flat coloured disc under the pickup so its type reads from a distance; it bobs and spins with the model.
func _add_glow(col: Color) -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = 0.26
	cm.bottom_radius = 0.26
	cm.height = 0.01
	cm.radial_segments = 20
	cm.rings = 1
	var mi := MeshInstance3D.new()
	mi.name = "Glow"
	mi.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(col.r, col.g, col.b, 0.45)
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 1.4
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	mi.position = Vector3(0, 0.005, 0)
	_visual.add_child(mi)

