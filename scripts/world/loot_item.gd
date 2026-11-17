extends StaticBody3D
## A pickup lying on the ground. Group "interactable" + "loot_item".
## Player interaction contract:
##   item.get_prompt() -> String
##   item.interact(player) -> bool   (calls player.add_item(id, count) if present; a bool false return = inventory full)
## Collision layer is ITEM_LAYER (bit 4, value 8) so items never block movement but ray casts can hit them.

signal picked_up(item, by)

const ItemDB = preload("res://scripts/world/item_db.gd")
const ModelUtil = preload("res://scripts/world/model_util.gd")
const SELF_PATH := "res://scripts/world/loot_item.gd"
const ITEM_LAYER := 8

var item_id: String = "scrap"
var count: int = 1
var loot_id: int = -1

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
	# Weapons lie on the ground as their Blaster Kit model (GunMesh); falls through to the old box gun if absent.
	if shape_kind == "gun" and model_path == "" and WeaponDB.has_weapon(str(info.get("weapon_id", ""))):
		var gm: Node3D = GunMesh.world_pickup(WeaponDB.get_weapon(str(info["weapon_id"])).model)
		if gm != null:
			_visual.add_child(gm)
			_add_box_collision(gm.get_meta("size") as Vector3)
			return
	if model_path != "":
		var m: Node3D = ModelUtil.load_fit(model_path, model_height)
		if m != null:
			_visual.add_child(m)
			_add_box_collision(m.get_meta("size") as Vector3)
			return
	var size := Vector3(0.22, 0.12, 0.16)
	match shape_kind:
		"gun":
			size = Vector3(0.8, 0.12, 0.14)
			var gb := BoxMesh.new()
			gb.size = Vector3(0.8, 0.07, 0.07)
			_add_mesh(gb, col, Vector3(0, 0.06, 0))
			var gg := BoxMesh.new()
			gg.size = Vector3(0.08, 0.14, 0.06)
			_add_mesh(gg, col.darkened(0.3), Vector3(-0.22, 0.08, 0))
		"can":
			size = Vector3(0.14, 0.14, 0.14)
			var cm := CylinderMesh.new()
			cm.top_radius = 0.07
			cm.bottom_radius = 0.07
			cm.height = 0.14
			cm.radial_segments = 6
			cm.rings = 1
			_add_mesh(cm, col, Vector3(0, 0.07, 0))
		"bottle":
			size = Vector3(0.1, 0.26, 0.1)
			var bm := CylinderMesh.new()
			bm.top_radius = 0.03
			bm.bottom_radius = 0.05
			bm.height = 0.26
			bm.radial_segments = 6
			bm.rings = 1
			_add_mesh(bm, col, Vector3(0, 0.13, 0))
		"long":
			size = Vector3(0.9, 0.08, 0.2)
			var pm := BoxMesh.new()
			pm.size = Vector3(0.9, 0.05, 0.18)
			_add_mesh(pm, col, Vector3(0, 0.04, 0))
			var pm2 := BoxMesh.new()
			pm2.size = Vector3(0.8, 0.05, 0.16)
			_add_mesh(pm2, col.darkened(0.12), Vector3(0.04, 0.09, 0.02))
		"medkit":
			size = Vector3(0.34, 0.18, 0.24)
			var mm := BoxMesh.new()
			mm.size = Vector3(0.34, 0.16, 0.24)
			_add_mesh(mm, col, Vector3(0, 0.08, 0))
			var c1 := BoxMesh.new()
			c1.size = Vector3(0.18, 0.02, 0.05)
			_add_mesh(c1, Color(0.85, 0.12, 0.1), Vector3(0, 0.171, 0))
			var c2 := BoxMesh.new()
			c2.size = Vector3(0.05, 0.02, 0.18)
			_add_mesh(c2, Color(0.85, 0.12, 0.1), Vector3(0, 0.171, 0))
		"scrap":
			size = Vector3(0.3, 0.14, 0.26)
			var s1 := BoxMesh.new()
			s1.size = Vector3(0.26, 0.05, 0.18)
			_add_mesh(s1, col, Vector3(0, 0.03, 0), 0.4)
			var s2 := BoxMesh.new()
			s2.size = Vector3(0.18, 0.06, 0.12)
			_add_mesh(s2, col.darkened(0.2), Vector3(0.04, 0.08, 0.02), -0.7)
		_:
			var bm2 := BoxMesh.new()
			bm2.size = size
			_add_mesh(bm2, col, Vector3(0, size.y * 0.5, 0))
	_add_box_collision(size)


func _add_box_collision(size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size + Vector3(0.12, 0.12, 0.12)
	cs.shape = bs
	cs.position = Vector3(0, size.y * 0.5, 0)
	add_child(cs)


func _add_mesh(mesh: Mesh, col: Color, pos: Vector3, yaw: float = 0.0) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 0.8
	mi.material_override = mat
	mi.position = pos
	mi.rotation.y = yaw
	_visual.add_child(mi)
