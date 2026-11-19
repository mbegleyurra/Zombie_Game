extends SceneTree
## Backpacks: three tiers in ItemDB, found as loot, crafted at the workbench, worn to add grid columns (never losing
## an item: a take-off that would not fit is refused), shown on the player's back (local and remote peers) and
## operated from the inventory overlay.
## Run: xvfb-run -a godot --headless --path . --script res://tests/t_backpacks.gd

const ItemDB := preload("res://scripts/world/item_db.gd")
const InvGrid := preload("res://scripts/player/inventory_grid.gd")
const Recipes := preload("res://scripts/world/recipes.gd")
const ModelUtil := preload("res://scripts/world/model_util.gd")
const InvUI := preload("res://scripts/ui/inventory_ui.gd")

const PACKS := ["backpack_small", "backpack_medium", "backpack_large"]

var fails := 0
var notices: Array = []


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


func _spawn(peer: String, pos: Vector3) -> Player:
	var p := (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as Player
	p.name = peer
	p.position = pos
	root.add_child(p)
	return p


func _rolled_id(it) -> String:
	if it is Dictionary:
		return str(it.get("id", it.get("item", "")))
	if it is Array and (it as Array).size() > 0:
		return str(it[0])
	return str(it)


func _run() -> void:
	await physics_frame
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	cs.shape = box
	floor_body.add_child(cs)
	floor_body.position = Vector3(0, -0.5, 0)
	root.add_child(floor_body)

	# ---- item data
	var cols: Array = []
	for id in PACKS:
		var d: Dictionary = ItemDB.get_item(id)
		check(not d.is_empty() and str(d["type"]) == "backpack" and ItemDB.is_backpack(id), "%s is a backpack item" % id)
		cols.append(ItemDB.backpack_cols(id))
		check(int(d["stack"]) == 1, "%s does not stack" % id)
		var fp: Vector2i = ItemDB.footprint(id)
		check(fp.x >= 2 and fp.y >= 2, "%s has a multi-cell footprint (%dx%d)" % [id, fp.x, fp.y])
		check(ResourceLoader.exists(str(d["worn_model"])) and ResourceLoader.exists(str(d["model"])), "%s worn and pickup models exist in assets" % id)
		var m: Node3D = ModelUtil.fit_box(str(d["worn_model"]), d["worn_size"] as Vector3)
		check(m != null and m.find_children("*", "MeshInstance3D", true, false).size() > 0, "%s worn model loads with meshes (downloaded asset)" % id)
		if m != null:
			m.free()
	check(cols[0] > 0 and cols[0] < cols[1] and cols[1] < cols[2], "tiers add 2 < 4 < 6 columns (%s)" % str(cols))
	check(ItemDB.backpack_cols("") == 0 and ItemDB.backpack_cols("medkit") == 0 and not ItemDB.is_backpack("medkit"), "non-packs add no columns")

	# ---- loot: every tier is rollable from at least one table
	var seen := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for t in ItemDB.table_names():
		for _i in 400:
			for it in ItemDB.roll_table(t, rng):
				var iid := _rolled_id(it)
				if PACKS.has(iid):
					seen[iid] = int(seen.get(iid, 0)) + 1
	for id in PACKS:
		check(int(seen.get(id, 0)) > 0, "%s drops from loot tables (%d rolls)" % [id, int(seen.get(id, 0))])

	# ---- workbench recipes (the crafting flow itself is exercised for every recipe by t_crafting.gd)
	var last_cost := 0
	for id in PACKS:
		var rc: Dictionary = Recipes.get_recipe(id)
		check(not rc.is_empty() and rc["kind"] == "gear" and rc["give"] == id and int(rc["count"]) == 1, "%s has a workbench recipe" % id)
		var total := int(rc["cost"].get("planks", 0)) + int(rc["cost"].get("scrap", 0))
		check(total > last_cost, "%s costs more than the tier below (%d)" % [id, total])
		last_cost = total

	# ---- wearing
	var local := _spawn("1", Vector3(0, 0.2, 0))
	var remote := _spawn("2", Vector3(6, 0.0, 0))
	await _frames(8)
	local.notice.connect(func(t: String) -> void: notices.append(t))
	var changed := [0]
	local.inventory_changed.connect(func() -> void: changed[0] += 1)
	check(local.inv_cols == 10 and local.backpack_id == "", "no backpack: 10 columns")
	check(not bool(local.equip_backpack("backpack_small")["ok"]), "cannot wear a pack you are not carrying")
	check(not bool(local.equip_backpack("medkit")["ok"]), "cannot wear a non-backpack")
	check(local.inv_cols == 10 and local.backpack_id == "", "refused equips change nothing")

	local.add_item("backpack_medium", 1)
	check(local.count_item("backpack_medium") == 1, "a found backpack lands in the inventory")
	var c0: int = changed[0]
	check(bool(local.equip_backpack("backpack_medium")["ok"]), "equip medium")
	check(local.inv_cols == 10 + ItemDB.backpack_cols("backpack_medium") and local.backpack_id == "backpack_medium", "medium adds its columns (%d)" % local.inv_cols)
	check(local.count_item("backpack_medium") == 0, "the worn pack leaves the grid")
	check(changed[0] > c0, "inventory_changed fires")
	check(int(InvGrid.layout(local)["cols"]) == local.inv_cols, "grid layout uses the new width")

	local.add_item("backpack_small", 1)
	check(bool(local.use_item("backpack_small")), "use_item wears a backpack")
	check(local.backpack_id == "backpack_small" and local.inv_cols == 10 + ItemDB.backpack_cols("backpack_small"), "swap resizes to the new tier (%d)" % local.inv_cols)
	check(local.count_item("backpack_medium") == 1 and local.count_item("backpack_small") == 0, "swapping returns the old pack to the inventory")

	# ---- take-off safety: fill the wide grid, then try to shrink it
	check(bool(local.equip_backpack("backpack_medium")["ok"]), "re-equip medium")
	var guard := 0
	while InvGrid.can_add(local, "scrap", 1) and guard < 3000:
		local.add_item("scrap", 1)
		guard += 1
	var scrap_before: int = local.count_item("scrap")
	var small_before: int = local.count_item("backpack_small")
	check(not InvGrid.can_add(local, "scrap", 1), "grid is full (%d scrap)" % scrap_before)
	notices.clear()
	var r: Dictionary = local.unequip_backpack()
	check(not bool(r["ok"]) and str(r["reason"]) != "", "take-off refused while it would not fit (%s)" % str(r["reason"]))
	check(local.backpack_id == "backpack_medium" and local.inv_cols == 14, "refused take-off keeps pack and width")
	check(local.count_item("scrap") == scrap_before and local.count_item("backpack_small") == small_before, "refused take-off loses nothing")
	check(notices.size() > 0, "refusal shows a HUD notice")
	check(bool(InvGrid.layout(local)["ok"]), "layout still packs after the refusal")
	var swap: Dictionary = local.equip_backpack("backpack_small")
	check(not bool(swap["ok"]) and local.backpack_id == "backpack_medium", "downgrading swap is refused too")
	local.inventory["scrap"] = 5
	local.inventory_changed.emit()
	check(bool(local.unequip_backpack()["ok"]), "take-off succeeds once there is room")
	check(local.backpack_id == "" and local.inv_cols == 10 and local.count_item("backpack_medium") == 1, "take-off restores 10 columns and returns the pack")
	check(bool(InvGrid.layout(local)["ok"]), "layout packs after take-off")

	# ---- visible on the player (local third person / remote peer)
	local.add_item("backpack_large", 1)
	check(bool(local.equip_backpack("backpack_large")["ok"]), "equip large for the visual checks")
	remote.backpack_id = "backpack_medium"   # the replicated var the remote peer receives
	await _frames(4)
	var rm: PlayerModel = remote._model
	check(rm != null and rm._pack_att != null and rm._pack_meshes.size() > 0, "remote peer draws the replicated backpack")
	if rm != null and rm._pack_att != null:
		check(rm._pack_att.get_parent() == rm._skel and rm._pack_att.bone_name == "torso", "pack is attached to the torso bone")
		var torso := rm._skel.global_transform * rm._skel.get_bone_global_pose(rm._skel.find_bone("torso"))
		var node := rm._pack_att.get_child(0) as Node3D
		var off: Vector3 = node.global_position - torso.origin
		check(off.dot(torso.basis * Vector3(0, 0, 1)) < 0.0, "pack sits behind the torso (%.2f)" % off.dot(torso.basis * Vector3(0, 0, 1)))
		check(off.length() < 0.9, "pack is on the body (%.2f m from the hip joint)" % off.length())
		var on := true
		for mi in rm._pack_meshes:
			on = on and mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON and rm._meshes.has(mi)
		check(on, "remote pack meshes are visible and tracked with the body")
	var lm: PlayerModel = local._model
	check(lm != null and lm._pack_att != null, "local player has its pack on the model")
	if lm != null and lm._pack_att != null:
		var hidden := true
		for mi in lm._pack_meshes:
			hidden = hidden and (mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY) == lm.local_view
		check(hidden, "first-person: the pack only casts a shadow (never blocks the camera)")
		lm.set_local_view(false)
		var shown := true
		for mi in lm._pack_meshes:
			shown = shown and mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		check(shown, "third person: the local pack is drawn")
		# the large pack rides between the shoulders and up behind the head, not at the hips
		var bb := AABB()
		for k in lm._pack_meshes.size():
			var mb: AABB = lm._pack_meshes[k].global_transform * lm._pack_meshes[k].mesh.get_aabb()
			bb = mb if k == 0 else bb.merge(mb)
		var shoulder_y: float = (lm._skel.global_transform * lm._skel.get_bone_global_pose(lm._skel.find_bone("arm-left"))).origin.y
		var hips_y: float = (lm._skel.global_transform * lm._skel.get_bone_global_pose(lm._skel.find_bone("torso"))).origin.y
		check(bb.end.y > shoulder_y + 0.3 and bb.position.y > hips_y - 0.01, "large pack spans the back from above the hips (%.2f) to well above the shoulders (%.2f)" % [bb.position.y, bb.end.y])
	var hs: Array = []
	for id in PACKS:
		hs.append((ItemDB.get_item(id)["worn_size"] as Vector3).y)
	check(hs[0] < hs[1] and hs[1] < hs[2], "worn size grows with the tier %s" % str(hs))
	remote.backpack_id = "backpack_small"
	await _frames(3)
	check(rm._pack_id == "backpack_small" and rm._pack_att != null, "remote swaps to another tier")
	var old_att := rm._pack_att
	remote.backpack_id = ""
	await _frames(3)
	check(rm._pack_att == null and rm._pack_meshes.is_empty() and not is_instance_valid(old_att), "remote pack removed when taken off")

	# ---- inventory overlay
	var ui: Control = InvUI.new()
	ui.standalone = true
	root.add_child(ui)
	ui.bind_player(local)
	await _frames(2)
	check(ui.unequip_button != null and not ui.unequip_button.disabled and "EXPEDITION" in ui.unequip_button.text, "unequip button names the worn pack (%s)" % ui.unequip_button.text)
	ui.open()
	await _frames(3)
	var vr := ui.get_viewport_rect()
	check(vr.encloses(ui._panel.get_global_rect()), "16-column inventory panel fits the viewport (%s in %s, cell %d)" % [ui._panel.get_global_rect(), vr.size, ui.cell])
	var apart := true
	for i in ui._entries.size():
		var nr: Rect2 = ui._name_labels[i].get_global_rect()
		var cr: Rect2 = ui._count_labels[i].get_global_rect()
		apart = apart and (ui._count_labels[i].text == "" or not nr.intersects(cr))
	check(apart, "slot names never overlap stack counts")
	ui.close(false)
	var idx := -1
	for i in ui._entries.size():
		if str(ui._entries[i]["key"]) == "backpack_medium":
			idx = i
	check(idx >= 0, "a carried backpack is listed in the grid")
	ui.use_slot(idx)
	check(local.backpack_id == "backpack_medium", "clicking a carried backpack wears it")
	check(ui._grid_dims().x == local.inv_cols, "overlay grid follows the wider inventory (%d columns)" % ui._grid_dims().x)
	ui.unequip_backpack()
	check(local.backpack_id == "" and ui.unequip_button.disabled, "overlay take-off works and disables the button")

	print("RESULT  failures=", fails)
	quit(1 if fails > 0 else 0)
