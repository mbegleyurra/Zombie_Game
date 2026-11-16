extends SceneTree
## Grid inventory rules + UI: footprints, capacity, rejected pickups (HUD notice, item stays on the ground), stack
## splitting, rotation, deconstruct (yields, atomic, Building stock feed, owner-only) and the grid drawing.
## Run: godot --headless --path . --script res://tests/t_inventory_grid.gd

const ItemDB := preload("res://scripts/world/item_db.gd")
const InvGrid := preload("res://scripts/player/inventory_grid.gd")
const LootItem := preload("res://scripts/world/loot_item.gd")
const LootContainer := preload("res://scripts/world/loot_container.gd")
const InvUI := preload("res://scripts/ui/inventory_ui.gd")

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


func _action(name: String) -> InputEventAction:
	var ev := InputEventAction.new()
	ev.action = name
	ev.pressed = true
	return ev


## No two placed stacks overlap and all are inside cols x rows.
func _layout_valid(p) -> bool:
	var lay: Dictionary = InvGrid.layout(p)
	var seen := {}
	for it in (lay["items"] as Array):
		for yy in range(int(it["y"]), int(it["y"]) + int(it["h"])):
			for xx in range(int(it["x"]), int(it["x"]) + int(it["w"])):
				if xx < 0 or yy < 0 or xx >= int(lay["cols"]) or yy >= int(lay["rows"]) or seen.has(Vector2i(xx, yy)):
					return false
				seen[Vector2i(xx, yy)] = true
	return bool(lay["ok"])


func _run() -> void:
	await physics_frame
	var player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	player.name = "1"
	player.position = Vector3(0, 0.2, 0)
	root.add_child(player)
	await _frames(5)
	player.notice.connect(func(t: String) -> void: notices.append(t))

	# ---- footprints
	check(ItemDB.footprint("weapon_pistol") == Vector2i(2, 1), "pistol is 2x1")
	check(ItemDB.footprint("weapon_ak") == Vector2i(4, 2) and ItemDB.footprint("weapon_m4") == Vector2i(4, 2), "ak / m4 are 4x2")
	check(ItemDB.footprint("weapon_shotgun") == Vector2i(4, 2) and ItemDB.footprint("weapon_hunting") == Vector2i(4, 2), "shotgun / hunting rifle are 4x2")
	check(ItemDB.footprint("weapon_ar_t1") == Vector2i(4, 2), "crafted rifles default to 4x2")
	var all_one := true
	for id in ["ammo_9mm", "ammo_556", "ammo_12ga", "ammo_762", "planks", "scrap", "medkit", "food", "water", "9mm", "556"]:
		all_one = all_one and ItemDB.footprint(id) == Vector2i(1, 1)
	check(all_one, "ammo, planks, scrap and consumables are 1x1 (ammo reserve keys resolve too)")

	# ---- starting loadout: pistol 2 + 9mm, medkit, food, water = 6 cells
	var lay: Dictionary = InvGrid.layout(player)
	check(int(lay["cols"]) == 10 and int(lay["rows"]) == 6, "default grid is 10 x 6")
	check(int(lay["used"]) == 6 and bool(lay["ok"]) and _layout_valid(player), "starting loadout uses 6 cells without overlap (used %d)" % int(lay["used"]))

	# ---- stack splitting: 9mm stack is 120 rounds
	player.add_item("9mm", 130)   # 175 total -> 2 stacks
	var n9 := 0
	for it in (InvGrid.layout(player)["items"] as Array):
		n9 += 1 if str(it["key"]) == "9mm" else 0
	check(n9 == 2 and _layout_valid(player), "175 rounds of 9mm occupy 2 stacks (%d)" % n9)
	player.remove_item("9mm", 130)

	# ---- pack(): rotation and capacity, pure
	var rifle := InvGrid._stack("weapon", "ak", 1)
	var r1 := InvGrid.pack([rifle], 2, 4)
	check(bool(r1["ok"]) and bool(rifle["rotated"]) and int(rifle["w"]) == 2 and int(rifle["h"]) == 4, "a 4x2 rifle rotates to fit a 2x4 grid")
	var r2 := InvGrid.pack([InvGrid._stack("weapon", "ak", 1), InvGrid._stack("weapon", "m4", 1)], 4, 3)
	check(not bool(r2["ok"]), "two 4x2 rifles do not fit a 4x3 grid")
	var r3 := InvGrid.pack([InvGrid._stack("weapon", "ak", 1), InvGrid._stack("weapon", "m4", 1), InvGrid._stack("weapon", "shotgun", 1)], 4, 6)
	check(bool(r3["ok"]), "three 4x2 rifles fit a 4x6 grid")

	# ---- rejected pickup: grid 6 x 3 = 18 cells, 6 used
	player.inv_cols = 6
	player.inv_rows = 3
	check(player.can_fit_item("weapon_ak", 1), "ak fits an 18-cell grid with 6 used")
	var ak_item = LootItem.create("weapon_ak", 1, 11)
	root.add_child(ak_item)
	var ok1: bool = ak_item.interact(player)
	check(ok1 and player.weapons.has_weapon("ak") and int(InvGrid.layout(player)["used"]) == 14, "ak picked up (8 cells, 14 used)")
	notices.clear()
	var m4_item = LootItem.create("weapon_m4", 1, 12)
	root.add_child(m4_item)
	var ok2: bool = m4_item.interact(player)
	check(not ok2 and not player.weapons.has_weapon("m4"), "m4 pickup rejected when it does not fit")
	check(is_instance_valid(m4_item) and not m4_item.is_queued_for_deletion(), "the rejected item stays on the ground")
	check(notices.size() == 1 and "full" in str(notices[0]).to_lower(), "rejection shows a HUD message: %s" % str(notices))
	var full_sig := [false]
	player.inventory_full.connect(func(_id: String) -> void: full_sig[0] = true)
	check(not player.add_item("m4", 1) and full_sig[0], "add_item returns false and emits inventory_full")
	check(not player.try_add("weapon_shotgun", 1) and not player.weapons.has_weapon("shotgun"), "try_add returns false for a rifle that does not fit")
	check(player.try_add("scrap", 4) and player.count_item("scrap") == 4, "try_add accepts a 1x1 stack that fits")
	player.remove_item("scrap", 4)
	check(_layout_valid(player), "layout stays valid after rejections")

	# ---- containers: leftovers that do not fit drop on the ground
	player.inv_cols = 3
	player.inv_rows = 2   # 6 cells, exactly the loadout (pistol 2 + 4 items) is 6 and ak is still owned -> already over
	player.weapons.remove_weapon("ak")
	var c = LootContainer.new()
	c.setup(900, "crate", "wild", 1)
	root.add_child(c)
	c.contents = [{"id": "iron_ingot", "count": 2}, {"id": "weapon_m4", "count": 1}]
	await _frames(2)   # earlier pickups are freed by now
	var loot_before := get_nodes_in_group("loot_item").size()
	c.interact(player)
	await _frames(2)
	check(player.count_item("iron_ingot") == 0 and not player.weapons.has_weapon("m4") and get_nodes_in_group("loot_item").size() == loot_before + 2,
		"a full grid takes nothing from a container; both items drop as ground loot")

	# ---- deconstruct (fresh roomy grid)
	player.inv_cols = 10
	player.inv_rows = 6
	var feed := Node.new()
	var gs := GDScript.new()
	gs.source_code = "extends Node\nvar got := {}\nfunc give_materials(i, n):\n\tgot[i] = int(got.get(i, 0)) + n\n"
	gs.reload()
	feed.set_script(gs)
	root.add_child(feed)
	feed.add_to_group("main_world")

	player.add_item("ak")
	var sc0: int = player.count_item("scrap")
	var pl0: int = player.count_item("planks")
	var r: Dictionary = player.deconstruct_item("weapon_ak")
	check(bool(r["ok"]) and not player.weapons.has_weapon("ak"), "deconstruct ak removes the weapon")
	check(int((r["yield"] as Dictionary).get("scrap", 0)) == 5 and int((r["yield"] as Dictionary).get("planks", 0)) == 2, "ak yields 5 scrap + 2 planks")
	check(player.count_item("scrap") == sc0 + 5 and player.count_item("planks") == pl0 + 2, "materials land in the inventory")
	check(int(feed.got.get("scrap", 0)) == 5 and int(feed.got.get("planks", 0)) == 2, "materials feed the Building stock like a pickup (%s)" % str(feed.got))

	var a0: int = player.count_item("9mm")
	var r_am: Dictionary = player.deconstruct_item("ammo_9mm")
	check(bool(r_am["ok"]) and int(r_am["removed"]) == 10 and player.count_item("9mm") == a0 - 10 and int((r_am["yield"] as Dictionary).get("scrap", 0)) == 1,
		"one unit of ammo = 10 rounds -> 1 scrap")
	var r_pl: Dictionary = player.deconstruct_item("planks")
	check(not bool(r_pl["ok"]) and "cannot" in str(r_pl["reason"]).to_lower(), "base materials cannot be deconstructed")
	var r_none: Dictionary = player.deconstruct_item("weapon_hunting")
	check(not bool(r_none["ok"]) and not player.weapons.has_weapon("hunting"), "cannot deconstruct what you do not own")
	player.add_item("iron_ingot", 1)
	check(not ItemDB.deconstruct_yield("iron_ingot").is_empty() or true, "kaykit yield lookup does not crash")

	# ---- atomic: no room for the materials -> nothing changes
	var p2 = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	p2.name = "1"
	root.add_child(p2)
	await _frames(3)
	p2.inventory.clear()
	p2.inv_cols = 4
	p2.inv_rows = 2   # 8 cells: pistol 2 + six 1x1 kinds, no scrap
	for id in ["9mm", "medkit", "food", "water", "12ga", "762"]:
		p2.add_item(id, 15 if id == "9mm" else 1)
	check(int(InvGrid.layout(p2)["used"]) == 8, "setup: grid completely full (%d / 8)" % int(InvGrid.layout(p2)["used"]))
	var snap: Dictionary = p2.inventory.duplicate()
	notices.clear()
	p2.notice.connect(func(t: String) -> void: notices.append(t))
	var r_full: Dictionary = p2.deconstruct_item("9mm")   # 10 of 15 rounds go, 5 stay, scrap needs a new cell
	check(not bool(r_full["ok"]) and p2.inventory == snap and "room" in str(r_full["reason"]).to_lower(), "deconstruct with no room for materials changes nothing")
	check(notices.size() == 1, "and tells the player: %s" % str(notices))
	var r_fit: Dictionary = p2.deconstruct_item("medkit")  # frees its cell, scrap takes it
	check(bool(r_fit["ok"]) and p2.count_item("medkit") == 0 and p2.count_item("scrap") == 1, "deconstruct that frees the room it needs succeeds")

	# ---- multiplayer: only the owning peer changes its inventory
	var p3 = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	p3.name = "1"
	root.add_child(p3)
	await _frames(3)
	p3.add_item("ak")
	p3.set_multiplayer_authority(777)
	var r_mp: Dictionary = InvGrid.deconstruct(p3, "ak", 1)
	check(not bool(r_mp["ok"]) and "owning" in str(r_mp["reason"]).to_lower() and p3.weapons.has_weapon("ak"), "a non-owner cannot deconstruct someone else's inventory")
	p3.queue_free()
	p2.queue_free()

	# ---- UI
	var ui: Control = InvUI.new()
	ui.standalone = true
	root.add_child(ui)
	ui.bind_player(player)
	await _frames()
	player.add_item("m4")
	player.add_item("planks", 3)
	player.add_item("scrap", 2)
	ui.open()
	await _frames(2)
	var mi := _find(ui, "weapon:m4")
	var pi := _find(ui, "planks")
	var pst := _find(ui, "weapon:pistol")
	check(mi >= 0 and int(ui._entries[mi]["w"]) == 4 and int(ui._entries[mi]["h"]) == 2, "m4 is drawn 4x2")
	check(pst >= 0 and int(ui._entries[pst]["w"]) == 2 and int(ui._entries[pst]["h"]) == 1, "pistol is drawn 2x1")
	check(pi >= 0 and int(ui._entries[pi]["w"]) == 1 and int(ui._entries[pi]["h"]) == 1, "planks are drawn 1x1")
	var geo_ok := true
	for i in ui._entries.size():
		var e: Dictionary = ui._entries[i]
		var b: Button = ui.slots[i]
		geo_ok = geo_ok and b.visible and is_equal_approx(b.size.x, int(e["w"]) * InvUI.CELL - InvUI.GAP) and is_equal_approx(b.size.y, int(e["h"]) * InvUI.CELL - InvUI.GAP) \
			and is_equal_approx(b.position.x, int(e["x"]) * InvUI.CELL + InvUI.GAP) and is_equal_approx(b.position.y, int(e["y"]) * InvUI.CELL + InvUI.GAP)
	check(geo_ok, "every item button sits at its footprint on the cell grid")
	check(ui._bg.size() == 60 and "Space" in ui.space_label.text, "60 background cells and a space readout (%s)" % ui.space_label.text)
	ui._show_detail(mi)
	check("4x2" in ui.detail_label.text and "Deconstruct" in ui.detail_label.text, "detail names the footprint and the deconstruct yield")
	check(not ui.deconstruct_button.disabled, "DECONSTRUCT is enabled for a rifle")
	ui._show_detail(pi)
	check(ui.deconstruct_button.disabled, "DECONSTRUCT is disabled for planks")
	ui._show_detail(_find(ui, "weapon:m4"))
	var sc1: int = player.count_item("scrap")
	ui._input(_action("inventory_deconstruct"))
	check(not player.weapons.has_weapon("m4") and player.count_item("scrap") == sc1 + 6 and _find(ui, "weapon:m4") < 0, "Delete key deconstructs the selected m4 (+6 scrap) and the grid updates live")
	check("Deconstructed" in ui.status_label.text, "status reports it: %s" % ui.status_label.text)
	ui._selected_key = ""
	ui.deconstruct_selected()
	check("Select" in ui.status_label.text, "deconstruct with nothing selected asks for a selection")
	ui.close()

	ui.queue_free()
	player.queue_free()
	await _frames(3)
	print("RESULT  failures=%d" % fails)
	quit(1 if fails > 0 else 0)


func _find(ui: Node, key: String) -> int:
	for i in ui._entries.size():
		if str(ui._entries[i]["key"]) == key:
			return i
	return -1
