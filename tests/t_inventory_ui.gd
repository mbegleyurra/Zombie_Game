extends SceneTree
## Grid inventory (scripts/ui/inventory_ui.gd): loot -> grid for EVERY ItemDB item (incl. KayKit resources, ammo and
## weapons), loot containers from every loot table, live refresh, click to use / equip, I and Esc, mouse mode, readable
## fonts, and the real Hud hook (host_solo + main.tscn).
## Run: godot --headless --path . --script res://tests/t_inventory_ui.gd

const ItemDB := preload("res://scripts/world/item_db.gd")
const LootItem := preload("res://scripts/world/loot_item.gd")
const LootContainer := preload("res://scripts/world/loot_container.gd")
const InvUI := preload("res://scripts/ui/inventory_ui.gd")

var fails := 0


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


## Slot index holding `key` in the UI's current entries, or -1.
func _find(ui: Node, key: String) -> int:
	for i in ui._entries.size():
		if str(ui._entries[i]["key"]) == key:
			return i
	return -1


## The grid key an item id should land under: weapon slot, reserve key for ammo, else the item id itself.
## Total count of `key` over all its stacks in the grid.
func _total(ui: Node, key: String) -> int:
	var t := 0
	for e in ui._entries:
		if str(e["key"]) == key:
			t += int(e["count"])
	return t


func _grid_key(item_id: String) -> String:
	var cid: String = ItemDB.canonical(item_id)
	var d: Dictionary = ItemDB.get_item(cid)
	match str(d.get("type", "")):
		"weapon":
			return InvUI.WEAPON_PREFIX + str(d["weapon_id"])
		"ammo":
			return ItemDB.reserve_key(cid)
	return cid


func _pick_up(player: Node, id: String, n: int, loot_id: int = 1) -> bool:
	var it = LootItem.create(id, n, loot_id)
	root.add_child(it)
	var ok: bool = it.interact(player)
	return ok


func _run() -> void:
	await physics_frame
	var player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	player.name = "1"
	player.position = Vector3(0, 0.2, 0)
	root.add_child(player)
	await _frames(5)
	player.inv_cols = 24   # the sweep below loots EVERY ItemDB item (all weapons are 4x2), far more than the default 10x6 grid
	player.inv_rows = 24
	var ui: Control = InvUI.new()
	ui.standalone = true
	root.add_child(ui)
	ui.bind_player(player)
	await _frames()

	# ---- input + layout
	var has_i := false
	for ev in InputMap.action_get_events("toggle_inventory"):
		has_i = has_i or (ev is InputEventKey and (ev as InputEventKey).physical_keycode == KEY_I)
	check(has_i, "action toggle_inventory is bound to I")
	check(ui._bg.size() == 24 * 24, "grid draws %d background cells (player.inv_cols x inv_rows)" % ui._bg.size())
	check(not ui.visible, "closed by default")
	check(_find(ui, InvUI.WEAPON_PREFIX + "pistol") >= 0 and _find(ui, "9mm") >= 0, "starting pistol and 9mm are in the grid")

	# ---- open with I: visible, mouse freed, joins ui_open
	ui._input(_action("toggle_inventory"))
	check(ui.visible and ui.is_in_group("ui_open"), "I opens the grid and joins group ui_open")
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "mouse is freed while the grid is open")

	# ---- loot every ItemDB item, check each shows up with the right count (grid already open: live refresh)
	var ids: Array = ItemDB.all_ids()
	var n_kaykit := 0
	var bad: Array = []
	for id in ids:
		var key := _grid_key(str(id))
		var before: int = player.count_item(key) if not key.begins_with(InvUI.WEAPON_PREFIX) else 0
		var ok := _pick_up(player, str(id), 3)
		var idx := _find(ui, key)
		var good := ok and idx >= 0
		if good and not key.begins_with(InvUI.WEAPON_PREFIX):
			good = _total(ui, key) == before + 3 and str(ui._name_labels[idx].text) == str(ui._entries[idx]["name"])
		if not good:
			bad.append("%s (key %s ok=%s idx=%d)" % [id, key, ok, idx])
		if str(id) in ["iron_ingot", "gold_nuggets", "fuel_can", "wood_logs", "coin", "parts"]:
			n_kaykit += 1
	check(bad.is_empty(), "all %d ItemDB items picked up appear in the open grid with correct counts %s" % [ids.size(), str(bad)])
	check(n_kaykit == 6, "KayKit resource items were part of the sweep (%d/6 sampled ids exist)" % n_kaykit)
	check(ui.slots.size() >= ui._entries.size(), "button pool grew to hold %d stacks (%d buttons)" % [ui._entries.size(), ui.slots.size()])
	var weapons_in_grid := 0
	for e in ui._entries:
		if str(e["key"]).begins_with(InvUI.WEAPON_PREFIX):
			weapons_in_grid += 1
	check(weapons_in_grid == player.weapons.weapon_ids().size() and weapons_in_grid >= 6,
		"every owned weapon is a slot (%d in grid, %d owned)" % [weapons_in_grid, player.weapons.weapon_ids().size()])
	check(ui._entries.size() > 0 and str(ui._entries[0]["key"]).begins_with(InvUI.WEAPON_PREFIX), "weapons are listed first")
	var tagged := 0
	for e in ui._entries:
		tagged += 1 if str(e["tag"]) == "EQUIPPED" else 0
	check(tagged == 1, "exactly one weapon slot is tagged EQUIPPED")

	# ---- live refresh without reopening
	var si := _find(ui, "scrap")
	var c0: int = _total(ui, "scrap")
	_pick_up(player, "scrap", 4)
	check(_total(ui, "scrap") == c0 + 4 and ui._count_labels[_find(ui, "scrap")].text.begins_with("x"),
		"stack counts update live on inventory_changed (x%d -> x%d)" % [c0, c0 + 4])
	player.remove_item("scrap", c0 + 4)
	check(_find(ui, "scrap") < 0, "slot disappears live when the stack is used up")
	player.weapons.remove_weapon("hunting")
	check(_find(ui, InvUI.WEAPON_PREFIX + "hunting") < 0, "weapon slot disappears live when the weapon is removed")
	_pick_up(player, "weapon_hunting", 1)
	check(_find(ui, InvUI.WEAPON_PREFIX + "hunting") >= 0, "weapon slot appears live on pickup")
	player.weapons.equip(player.weapons.weapon_ids().find("pistol"))
	var pi := _find(ui, InvUI.WEAPON_PREFIX + "pistol")
	check(str(ui._count_labels[pi].text) == "EQUIPPED", "EQUIPPED tag follows weapon_changed live")

	# ---- containers: every loot table
	var net_seed := 4242
	var tables: Array = ItemDB.table_names()
	var cbad: Array = []
	var cid := 100
	var total_contents := 0
	for t in tables:
		cid += 1
		var c = LootContainer.new()
		c.setup(cid, "crate", str(t), net_seed)
		root.add_child(c)
		var contents: Array = c.contents.duplicate(true)
		c.interact(player)
		for d in contents:
			total_contents += 1
			if _find(ui, _grid_key(str(d["id"]))) < 0:
				cbad.append("%s/%s" % [t, d["id"]])
	check(cbad.is_empty() and total_contents > 0, "items taken from containers of all %d loot tables show in the grid (%d items) %s" % [tables.size(), total_contents, str(cbad)])

	# ---- click to use / equip / display only
	player.health = 40.0
	_pick_up(player, "medkit", 1)
	var mi := _find(ui, "medkit")
	var mk: int = player.count_item("medkit")
	ui.use_slot(mi)
	check(player.count_item("medkit") == mk - 1 and player.health > 40.0, "clicking Medkit uses one (hp 40 -> %.0f)" % player.health)
	ui.use_slot(_find(ui, InvUI.WEAPON_PREFIX + "ak"))
	check(player.weapons.weapon_data().id == "ak", "clicking a weapon slot equips it")
	_pick_up(player, "scrap", 1)
	ui.use_slot(_find(ui, "scrap"))
	check("display only" in ui.status_label.text, "non-usable item reports display only")
	ui._show_detail(_find(ui, "iron_ingot"))
	check("Iron Ingot" in ui.detail_label.text and "kg" in ui.detail_label.text, "hover detail shows name, description and weight")

	# ---- readable fonts
	var small := 999
	var stack: Array = [ui]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if (n is Label and (n as Label).text != "" and n != ui.status_label) or (n is Button and (n as Button).text != ""):
			small = mini(small, (n as Control).get_theme_font_size("font_size"))
		stack.append_array(n.get_children())
	check(small >= 20, "all inventory text is >= 20 px (smallest %d)" % small)

	# ---- Esc closes, mouse recaptured; I toggles
	ui._input(_action("ui_cancel"))
	check(not ui.visible and not ui.is_in_group("ui_open"), "Esc closes the grid and leaves ui_open")
	var recaptured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	# Some headless builds (Godot 4.7.2 here) never store MOUSE_MODE_CAPTURED; probe that before asserting on it.
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var can_capture := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	check(recaptured or not can_capture,
		"mouse is recaptured on close" + ("" if can_capture else " (skipped: this headless build cannot hold CAPTURED)"))
	ui._input(_action("toggle_inventory"))
	ui._input(_action("toggle_inventory"))
	check(not ui.visible, "I toggles it closed again")
	player.health = 0.0
	player._hurt(1.0)
	check(player.is_dead and not ui.open(), "cannot open the grid while dead")

	ui.queue_free()
	player.queue_free()
	await _frames(3)
	await _hud_flow()
	print("RESULT  failures=%d" % fails)
	quit(1 if fails > 0 else 0)


## Real session: the Hud autoload owns the grid; I opens it, Esc closes it WITHOUT opening the pause menu.
func _hud_flow() -> void:
	var net: Node = root.get_node_or_null("Net")
	var hud: Node = root.get_node_or_null("Hud")
	check(net != null and hud != null, "Net and Hud autoloads present")
	if net == null or hud == null:
		return
	check(net.host_solo(31351) == OK, "Net.host_solo ok")
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	for _i in 30:
		await physics_frame
	var p = net.get_local_player()
	check(p != null, "local player spawned")
	if p == null:
		return
	var ui: Node = null
	for c in hud.get_children():
		if c.get_script() != null and str(c.get_script().resource_path).ends_with("inventory_ui.gd"):
			ui = c
	check(ui != null, "Hud owns an inventory_ui child")
	if ui == null:
		return
	await _frames()
	ui._input(_action("toggle_inventory"))
	check(ui.visible and hud.is_ui_open() and not hud.is_paused(), "I opens it in a real session; Hud.is_ui_open() is true")
	await _frames(2)
	check(ui.size.is_equal_approx(root.get_visible_rect().size), "inventory overlay fills the screen (%s)" % str(ui.size))
	check(ui._player == p and _find(ui, InvUI.WEAPON_PREFIX + "pistol") >= 0, "bound to the local player automatically")
	var it = LootItem.create("iron_ingot", 2, 7)
	main.add_child(it)
	it.interact(p)
	check(_find(ui, "iron_ingot") >= 0, "ground pickup in the real session shows in the open grid")
	ui._input(_action("ui_cancel"))
	check(not ui.visible and not hud.is_ui_open() and not hud.is_paused(), "Esc closes it and does not open the pause menu")
	hud.open_pause()
	ui._input(_action("toggle_inventory"))
	check(not ui.visible, "I does nothing while paused")
	hud.close_pause(true)
