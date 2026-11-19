extends Control
## Grid inventory overlay. Toggle: I (action "toggle_inventory", registered here in code like Player.register_inputs).
## A real cell grid (player.inv_cols x player.inv_rows, 10 x 6 by default). Every item stack is drawn at its footprint
## (ItemDB.footprint: pistol 2x1, rifles and shotguns 4x2, ammo / planks / scrap / consumables 1x1) at the position
## the auto-packer in scripts/player/inventory_grid.gd gave it. Owned weapons come first (they live in player.weapons,
## not player.inventory), then every Player.inventory entry (id -> count, ammo under its reserve key) split into stacks.
## Full description under the grid while an item is hovered or focused. The grid refreshes live on inventory_changed and
## on the weapon controller's ammo_changed / weapon_changed signals, so anything picked up shows at once.
## Click / Enter: a weapon equips, medkit / food / water are used (Player.use_item), the rest only select.
## DECONSTRUCT: the last hovered / focused / clicked item is selected; the DECONSTRUCT button or the Delete key breaks
## one unit of it into planks and scrap (yields come from ItemDB.deconstruct_yield).
## Owned by the Hud autoload. Esc closes it and the mouse is released while it is open.

signal opened
signal closed

const ItemDB := preload("res://scripts/world/item_db.gd")
const InvGrid := preload("res://scripts/player/inventory_grid.gd")
const PickupVisuals := preload("res://scripts/world/pickup_visuals.gd")

const ACTION := "toggle_inventory"
const DECON_ACTION := "inventory_deconstruct"
const GROUP_OPEN := "ui_open"        ## Hud.is_ui_open() is true while any member is in this group
const GROUP_ALL := "overlay_ui"      ## close everything: get_tree().call_group("overlay_ui", "close", false)
const CELL := 84             ## largest cell size (px); `cell` shrinks below it so the panel fits the viewport
const CELL_MIN := 32
const SCREEN_MARGIN := 16    ## free space kept around the panel (px)
const GAP := 3
const FONT_TITLE := 48
const FONT_SLOT := 20        ## readability floor: slot text never shrinks below 20 px, even when the cells do
const FONT_COUNT := 28
const FONT_COUNT_MIN := 20
const FONT_BODY := 22
const DETAIL_LINES := 3
const KEY_COL := Color(0.95, 0.8, 0.35)
## Items Player.use_item can consume.
const USABLE := ["medkit", "food", "water"]
const IDLE_DETAIL := "Hover an item for details."
const WEAPON_PREFIX := "weapon:"

var slots: Array[Button] = []          ## pooled item buttons; the first _entries.size() are visible
var detail_label: Label
var status_label: Label
var space_label: Label
var deconstruct_button: Button
var unequip_button: Button   ## takes the worn backpack off (refused when the items would not fit the smaller grid)
## Current cell size (px): CELL, or less when the grid (a 16-column large-pack grid, a small window) would not fit.
var cell := CELL
## Tests: skip the Net/Hud gating so the overlay can be driven without a running game.
var standalone := false

var _player: Node = null
var _panel: PanelContainer
var _grid: Control
var _bg: Array[Panel] = []
var _bg_dims := Vector2i.ZERO
var _bg_cell := 0
var _entries: Array = []
var _used := 0
var _selected_key := ""
var _name_labels: Array[Label] = []
var _count_labels: Array[Label] = []
var _prev_mouse := Input.MOUSE_MODE_CAPTURED


func _ready() -> void:
	add_to_group(GROUP_ALL)
	if not InputMap.has_action(ACTION):
		InputMap.add_action(ACTION, 0.2)
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_I
		InputMap.action_add_event(ACTION, ev)
	if not InputMap.has_action(DECON_ACTION):
		InputMap.add_action(DECON_ACTION, 0.2)
		var dv := InputEventKey.new()
		dv.physical_keycode = KEY_DELETE
		InputMap.action_add_event(DECON_ACTION, dv)
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", _box(Color(0.06, 0.07, 0.06, 0.97), Color(0.4, 0.38, 0.3), 2, 12))
	center.add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_panel.add_child(box)

	var title := Label.new()
	title.text = "INVENTORY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", FONT_TITLE)
	box.add_child(title)

	var grid_center := CenterContainer.new()
	box.add_child(grid_center)
	_grid = Control.new()
	_grid.mouse_filter = Control.MOUSE_FILTER_PASS
	grid_center.add_child(_grid)

	detail_label = Label.new()
	detail_label.text = IDLE_DETAIL
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_label.max_lines_visible = DETAIL_LINES   # a long description never grows the panel past the screen
	detail_label.add_theme_font_size_override("font_size", FONT_BODY)
	detail_label.custom_minimum_size = Vector2(0, DETAIL_LINES * detail_label.get_line_height())
	box.add_child(detail_label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	box.add_child(row)
	space_label = Label.new()
	space_label.add_theme_font_size_override("font_size", FONT_BODY)
	space_label.custom_minimum_size = Vector2(230, 0)
	row.add_child(space_label)
	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", FONT_BODY)
	status_label.add_theme_color_override("font_color", KEY_COL)
	status_label.custom_minimum_size = Vector2(0, 30)
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS   # a long reason never widens the panel
	row.add_child(status_label)
	deconstruct_button = Button.new()
	deconstruct_button.text = "DECONSTRUCT (Del)"
	deconstruct_button.focus_mode = Control.FOCUS_NONE
	deconstruct_button.add_theme_font_size_override("font_size", FONT_BODY)
	deconstruct_button.pressed.connect(deconstruct_selected)
	row.add_child(deconstruct_button)
	unequip_button = Button.new()
	unequip_button.focus_mode = Control.FOCUS_NONE
	unequip_button.add_theme_font_size_override("font_size", FONT_BODY)
	unequip_button.pressed.connect(unequip_backpack)
	row.add_child(unequip_button)
	var hint := Label.new()
	hint.text = "Click a weapon to equip, medkit / food / water to use. Select an item, then DECONSTRUCT for planks and scrap.     I or Esc - Close"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(700, 0)
	hint.add_theme_font_size_override("font_size", 20)
	hint.modulate = Color(1, 1, 1, 0.85)
	box.add_child(hint)
	get_viewport().size_changed.connect(refresh)
	refresh()


# ---------------------------------------------------------------- public API

func is_open() -> bool:
	return visible


## Points the grid at a player (the Hud finds the local one automatically when this is never called).
func bind_player(p: Node) -> void:
	if _player == p:
		return
	_link(_player, false)
	_player = p
	_link(p, true)
	refresh()


## Placed stacks in display order: Array of {key, name, count, tag, color, item, x, y, w, h, rotated}. Weapons first
## (tag EQUIPPED on the one in hand, count 0), then inventory stacks sorted by display name. Updates _used.
func entries() -> Array:
	var p := _player if _player != null and is_instance_valid(_player) else null
	_used = 0
	if p == null:
		return []
	var lay: Dictionary = InvGrid.layout(p)
	_used = int(lay["used"])
	var wc = p.get("weapons")
	var cur := ""
	if wc != null and is_instance_valid(wc) and wc.current_slot >= 0 and wc.current_slot < wc.slots.size():
		cur = str(wc.slots[wc.current_slot]["id"])
	var out: Array = []
	for it in (lay["items"] as Array):
		var e: Dictionary = (it as Dictionary).duplicate()
		var key := str(e["key"])
		e["color"] = PickupVisuals.accent(str(e["item"]))
		e["tag"] = "EQUIPPED" if key == WEAPON_PREFIX + cur else ""
		if bool(e["weapon"]):
			e["name"] = _weapon_name(key.trim_prefix(WEAPON_PREFIX))
		out.append(e)
	return out


func open() -> bool:
	if visible or _blocked():
		return false
	if _player == null or not is_instance_valid(_player):
		var net := get_node_or_null("/root/Net")
		bind_player(net.get_local_player() if net != null else null)
	if _player != null and bool(_player.get("is_dead")):
		return false
	_prev_mouse = Input.mouse_mode
	visible = true
	add_to_group(GROUP_OPEN)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	status_label.text = ""
	refresh()
	if not _entries.is_empty():
		slots[0].grab_focus.call_deferred()
	opened.emit()
	return true


## recapture: give the mouse back to the player (not wanted when something else takes over the mouse).
func close(recapture: bool = true) -> void:
	if not visible:
		return
	visible = false
	remove_from_group(GROUP_OPEN)
	if recapture and not _blocked(true):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()


func refresh() -> void:
	if _grid == null or space_label == null:
		return
	_entries = entries()
	_sync_background()
	while slots.size() < _entries.size():
		_add_slot()
	for i in slots.size():
		var b := slots[i]
		if i >= _entries.size():
			b.visible = false
			b.disabled = true
			_name_labels[i].text = ""
			_count_labels[i].text = ""
			b.tooltip_text = ""
			continue
		var e: Dictionary = _entries[i]
		b.visible = true
		b.disabled = false
		b.position = Vector2(int(e["x"]) * cell + GAP, int(e["y"]) * cell + GAP)
		b.size = Vector2(int(e["w"]) * cell - GAP, int(e["h"]) * cell - GAP)
		_name_labels[i].text = str(e["name"])
		_count_labels[i].text = str(e["tag"]) if str(e["tag"]) != "" else ("x%d" % int(e["count"]) if int(e["count"]) > 0 else "")
		_layout_slot(i)
		b.tooltip_text = describe(i)
		_style_slot(b, e["color"] as Color, true, str(e["key"]) == _selected_key)
	var total := _grid_dims().x * _grid_dims().y
	space_label.text = "Space %d / %d cells" % [_used, total]
	if unequip_button != null:
		var worn := str(_player.get("backpack_id")) if _player != null and is_instance_valid(_player) and _player.get("backpack_id") != null else ""
		unequip_button.text = "UNEQUIP " + ItemDB.item_name(worn).to_upper() if worn != "" else "NO BACKPACK WORN"
		unequip_button.disabled = worn == ""
	if deconstruct_button != null:
		var sel := _selected_index()
		deconstruct_button.disabled = sel < 0 or ItemDB.deconstruct_yield(str(_entries[sel]["item"])).is_empty()


## Hover text for item i: name, count, footprint, description, type, weight and what it deconstructs into
## ("" for an invalid index).
func describe(i: int) -> String:
	if i < 0 or i >= _entries.size():
		return ""
	var e: Dictionary = _entries[i]
	var key := str(e["key"])
	var iid := str(e["item"])
	var fp: Vector2i = ItemDB.footprint(iid)
	var s: String
	var d: Dictionary = ItemDB.get_item(iid)
	if key.begins_with(WEAPON_PREFIX):
		s = "%s  (weapon%s, %dx%d cells)" % [str(e["name"]), ", equipped" if str(e["tag"]) != "" else "", fp.x, fp.y]
		if not d.is_empty():
			s += "\n%s   (%.2f kg)" % [str(d.get("desc", "")), float(d.get("weight", 0.0))]
	else:
		s = "%s  x%d  (%dx%d cells)" % [str(e["name"]), int(e["count"]), fp.x, fp.y]
		if not d.is_empty():
			s += "\n%s   (%s, %.2f kg each)" % [str(d.get("desc", "")), str(d.get("type", "item")), float(d.get("weight", 0.0))]
	var y: Dictionary = ItemDB.deconstruct_yield(iid)
	if not y.is_empty():
		var parts: Array = []
		for m in y:
			parts.append("%d %s" % [int(y[m]), ItemDB.item_name(str(m))])
		var unit := ItemDB.deconstruct_unit(iid)
		s += "\nDeconstruct%s: %s" % [" %d rounds" % unit if unit > 1 else "", ", ".join(parts)]
	return s


## Clicking item i: weapons are equipped, medkit / food / water used, everything else just selects.
func use_slot(i: int) -> void:
	if i < 0 or i >= _entries.size():
		return
	var key: String = str(_entries[i]["key"])
	var nm: String = str(_entries[i]["name"])
	_selected_key = key
	var wc = _player.get("weapons") if _player != null and is_instance_valid(_player) else null
	if key.begins_with(WEAPON_PREFIX):
		var idx: int = wc.weapon_ids().find(key.trim_prefix(WEAPON_PREFIX)) if wc != null else -1
		if idx >= 0:
			wc.equip(idx)
			status_label.text = "Equipped %s." % nm
		else:
			status_label.text = "Cannot equip %s." % nm
	elif ItemDB.is_backpack(key):
		var r: Dictionary = _player.equip_backpack(key) if _player != null and is_instance_valid(_player) and _player.has_method("equip_backpack") else {"ok": false, "reason": "No player."}
		status_label.text = ("Wearing %s." % nm) if bool(r["ok"]) else str(r["reason"])
	elif not USABLE.has(key):
		status_label.text = "%s: selected (display only, no use action)." % nm
	elif _player != null and is_instance_valid(_player) and _player.has_method("use_item") and bool(_player.use_item(key)):
		status_label.text = "Used 1 %s." % nm
	else:
		status_label.text = "Cannot use %s right now." % nm
	refresh()


## Breaks one unit of stack i (a weapon, a bundle of ammo, a single item) into planks and scrap.
## Returns Player.deconstruct_item's result ({} when i is not a valid item).
func deconstruct_slot(i: int) -> Dictionary:
	if i < 0 or i >= _entries.size():
		status_label.text = "Select an item first."
		return {}
	var key: String = str(_entries[i]["key"])
	var id := key.trim_prefix(WEAPON_PREFIX) if key.begins_with(WEAPON_PREFIX) else key
	var nm: String = str(_entries[i]["name"])
	var r: Dictionary
	if _player != null and is_instance_valid(_player) and _player.has_method("deconstruct_item"):
		r = _player.deconstruct_item(id, 1)
	else:
		r = InvGrid.deconstruct(_player, id, 1)
	if bool(r.get("ok", false)):
		var parts: Array = []
		for m in (r["yield"] as Dictionary):
			parts.append("%d %s" % [int(r["yield"][m]), ItemDB.item_name(str(m))])
		status_label.text = "Deconstructed %s into %s." % [nm, ", ".join(parts)]
	else:
		status_label.text = str(r.get("reason", "Cannot deconstruct."))
	refresh()
	return r


## Takes the worn backpack off. Refused with the reason in the status line when the grid would no longer hold everything.
func unequip_backpack() -> Dictionary:
	var r := {"ok": false, "reason": "No backpack worn."}
	if _player != null and is_instance_valid(_player) and _player.has_method("unequip_backpack"):
		r = _player.unequip_backpack()
	status_label.text = "Backpack taken off." if bool(r["ok"]) else str(r["reason"])
	refresh()
	return r


func deconstruct_selected() -> Dictionary:
	return deconstruct_slot(_selected_index())


# ------------------------------------------------------------------ internals

func _selected_index() -> int:
	if _selected_key == "":
		return -1
	for i in _entries.size():
		if str(_entries[i]["key"]) == _selected_key:
			return i
	return -1


func _grid_dims() -> Vector2i:
	var cols: int = int(_player.get("inv_cols")) if _player != null and is_instance_valid(_player) and _player.get("inv_cols") != null else InvGrid.DEFAULT_COLS
	var rows: int = int(_player.get("inv_rows")) if _player != null and is_instance_valid(_player) and _player.get("inv_rows") != null else InvGrid.DEFAULT_ROWS
	return Vector2i(cols, rows)


## Largest cell (CELL_MIN..CELL) at which the panel, grid plus its fixed title / detail / buttons, fits the viewport.
func _fit_cell(dims: Vector2i) -> int:
	var vp := get_viewport_rect().size if is_inside_tree() else Vector2(1280, 720)
	var chrome_w := _panel.get_theme_stylebox("panel").get_minimum_size().x
	var chrome_h := _panel.get_combined_minimum_size().y - _grid.get_combined_minimum_size().y
	var avail := vp - Vector2(2 * SCREEN_MARGIN + chrome_w + GAP, 2 * SCREEN_MARGIN + chrome_h + GAP)
	var c := floori(minf(avail.x / maxi(dims.x, 1), avail.y / maxi(dims.y, 1)))
	return clampi(c, CELL_MIN, CELL)


## Background cells, rebuilt only when the player's grid size or the fitted cell size changes.
func _sync_background() -> void:
	var dims := _grid_dims()
	var fit := _fit_cell(dims)
	if dims == _bg_dims and fit == _bg_cell:
		return
	for old in _bg:
		old.queue_free()
	_bg.clear()
	_bg_dims = dims
	_bg_cell = fit
	cell = fit
	_grid.custom_minimum_size = Vector2(dims.x * cell + GAP, dims.y * cell + GAP)
	var sb := _box(Color(0.12, 0.13, 0.12, 0.85), Color(0.25, 0.26, 0.24), 1, 3)
	for y in dims.y:
		for x in dims.x:
			var bgc := Panel.new()
			bgc.mouse_filter = Control.MOUSE_FILTER_IGNORE
			bgc.add_theme_stylebox_override("panel", sb)
			bgc.position = Vector2(x * cell + GAP, y * cell + GAP)
			bgc.size = Vector2(cell - GAP, cell - GAP)
			_grid.add_child(bgc)
			_grid.move_child(bgc, 0)
			_bg.append(bgc)


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed(DECON_ACTION):
		deconstruct_selected()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(ACTION):
		if visible:
			close()
			get_viewport().set_input_as_handled()
		elif open():
			get_viewport().set_input_as_handled()


func _link(p: Node, on: bool) -> void:
	if p == null or not is_instance_valid(p):
		return
	var sources: Array = [[p, "inventory_changed"]]
	var wc = p.get("weapons")
	if wc != null:
		sources.append([wc, "ammo_changed"])
		sources.append([wc, "weapon_changed"])
	for s in sources:
		var o: Object = s[0]
		var sig: String = s[1]
		if not o.has_signal(sig):
			continue
		var c := Callable(self, "_on_inventory_changed")
		if on and not o.is_connected(sig, c):
			o.connect(sig, c)
		elif not on and o.is_connected(sig, c):
			o.disconnect(sig, c)


func _on_inventory_changed(_a = null) -> void:
	if visible:
		refresh()


## ItemDB id of a weapon id ("ak" -> "weapon_ak").
static func _weapon_item_id(wid: String) -> String:
	return "weapon_" + wid


static func _weapon_name(wid: String) -> String:
	var d: Dictionary = ItemDB.get_item(_weapon_item_id(wid))
	if not d.is_empty():
		return str(d["name"])
	var wd = WeaponDB.get_weapon(wid)
	return str(wd.display_name) if wd != null else wid


## True while the game should not open an overlay (menu, pause, loot panel, not in a game).
## closing: only the pause / loot panels count (they own the mouse), not "not in game".
func _blocked(closing: bool = false) -> bool:
	if standalone:
		return false
	var net := get_node_or_null("/root/Net")
	if not closing and (net == null or not bool(net.active)):
		return true
	var hud := get_node_or_null("/root/Hud")
	return hud != null and (bool(hud.is_paused()) or bool(hud.is_loot_open()))


func _add_slot() -> void:
	var i := slots.size()
	var b := Button.new()
	b.focus_mode = Control.FOCUS_ALL
	b.clip_contents = true
	var nl := _slot_label(b, FONT_SLOT, HORIZONTAL_ALIGNMENT_LEFT, VERTICAL_ALIGNMENT_TOP)
	nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var cl := _slot_label(b, FONT_COUNT, HORIZONTAL_ALIGNMENT_RIGHT, VERTICAL_ALIGNMENT_BOTTOM)
	b.pressed.connect(use_slot.bind(i))
	b.mouse_entered.connect(_show_detail.bind(i))
	b.focus_entered.connect(_show_detail.bind(i))
	b.mouse_exited.connect(_show_detail.bind(-1))
	_grid.add_child(b)
	slots.append(b)
	_name_labels.append(nl)
	_count_labels.append(cl)
	_style_slot(b, Color.BLACK, false, false)


func _slot_label(parent: Button, font_size: int, h: int, v: int) -> Label:
	var l := Label.new()
	l.horizontal_alignment = h as HorizontalAlignment
	l.vertical_alignment = v as VerticalAlignment
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	return l


## Slot i's labels at the current cell size: the count gets a strip along the bottom, the name the space above it
## (as many whole lines as fit, ellipsis after), so a long name can never run over the count.
func _layout_slot(i: int) -> void:
	var b := slots[i]
	var nl := _name_labels[i]
	var cl := _count_labels[i]
	var cfs := clampi(int(cell * 0.27), FONT_COUNT_MIN, FONT_COUNT)
	cl.add_theme_font_size_override("font_size", cfs)
	var pad := 3.0
	var count_h: float = float(cl.get_line_height()) if cl.text != "" else 0.0
	cl.anchor_top = 1.0   # a strip of count_h along the bottom edge
	cl.offset_left = pad
	cl.offset_right = -pad
	cl.offset_bottom = -1.0
	cl.offset_top = -1.0 - count_h
	var name_h := maxf(b.size.y - 2.0 * pad - count_h, 0.0)
	nl.offset_left = pad
	nl.offset_right = -pad
	nl.offset_top = pad
	nl.offset_bottom = -(pad + count_h)
	nl.max_lines_visible = maxi(1, floori(name_h / maxf(nl.get_line_height(), 1.0)))


## Hovering / focusing an item shows its detail and selects it for DECONSTRUCT (i = -1 clears only the detail text).
func _show_detail(i: int) -> void:
	var t := describe(i)
	detail_label.text = t if t != "" else IDLE_DETAIL
	if i >= 0 and i < _entries.size() and str(_entries[i]["key"]) != _selected_key:
		_selected_key = str(_entries[i]["key"])
		refresh()


func _style_slot(b: Button, col: Color, filled: bool, selected: bool) -> void:
	var base := col.darkened(0.45) if filled else Color(0.12, 0.13, 0.12, 0.85)
	var edge := KEY_COL if selected else (Color(0.45, 0.45, 0.4) if filled else Color(0.25, 0.26, 0.24))
	var bw := 3 if selected else 2
	b.add_theme_stylebox_override("normal", _box(base, edge, bw, 6))
	b.add_theme_stylebox_override("disabled", _box(base, edge, bw, 6))
	b.add_theme_stylebox_override("hover", _box(base.lightened(0.25), KEY_COL, 3, 6))
	b.add_theme_stylebox_override("pressed", _box(base.lightened(0.4), KEY_COL, 3, 6))
	b.add_theme_stylebox_override("focus", _box(base.lightened(0.15), KEY_COL, 3, 6))


static func _box(bg: Color, border: Color, bw: int, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb
