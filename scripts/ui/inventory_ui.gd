extends Control
## Grid inventory overlay. Toggle: I (action "toggle_inventory", registered here in code like Player.register_inputs).
## One slot per item kind: owned weapons first (they live in player.weapons, not player.inventory), then every
## Player.inventory entry (id -> count, ammo under its reserve key) sorted by ItemDB display name. Full description
## under the grid while a slot is hovered or focused. The grid refreshes live on inventory_changed and on the weapon
## controller's ammo_changed / weapon_changed signals, so anything picked up from the ground or a container shows at once.
## Click / Enter: a weapon slot equips it, medkit / food / water are used (Player.use_item). The player has no drop
## function, so every other item is display only.
## Owned by the Hud autoload. Esc closes it and the mouse is released while it is open.

signal opened
signal closed

const ItemDB := preload("res://scripts/world/item_db.gd")

const ACTION := "toggle_inventory"
const GROUP_OPEN := "ui_open"        ## Hud.is_ui_open() is true while any member is in this group
const GROUP_ALL := "overlay_ui"      ## close everything: get_tree().call_group("overlay_ui", "close", false)
const COLUMNS := 6
const MIN_SLOTS := 24
const SLOT_SIZE := Vector2(140, 100)
const GAP := 8
const FONT_TITLE := 48
const FONT_SLOT := 20
const FONT_COUNT := 28
const FONT_BODY := 22
const KEY_COL := Color(0.95, 0.8, 0.35)
## Items Player.use_item can consume.
const USABLE := ["medkit", "food", "water"]
const IDLE_DETAIL := "Hover a slot for details."
const WEAPON_PREFIX := "weapon:"

var slots: Array[Button] = []
var detail_label: Label
var status_label: Label
## Tests: skip the Net/Hud gating so the overlay can be driven without a running game.
var standalone := false

var _player: Node = null
var _grid: GridContainer
var _scroll: ScrollContainer
var _entries: Array = []
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
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box(Color(0.06, 0.07, 0.06, 0.97), Color(0.4, 0.38, 0.3), 2, 12))
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	var title := Label.new()
	title.text = "INVENTORY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", FONT_TITLE)
	box.add_child(title)

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size = Vector2(COLUMNS * (SLOT_SIZE.x + GAP) + 24, 4 * (SLOT_SIZE.y + GAP) + 4)
	box.add_child(_scroll)
	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", GAP)
	_grid.add_theme_constant_override("v_separation", GAP)
	_scroll.add_child(_grid)
	_ensure_slots(MIN_SLOTS)

	detail_label = Label.new()
	detail_label.text = IDLE_DETAIL
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_label.custom_minimum_size = Vector2(0, 64)
	detail_label.add_theme_font_size_override("font_size", FONT_BODY)
	box.add_child(detail_label)
	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", FONT_BODY)
	status_label.add_theme_color_override("font_color", KEY_COL)
	status_label.custom_minimum_size = Vector2(0, 30)
	box.add_child(status_label)
	var hint := Label.new()
	hint.text = "Click a weapon to equip, medkit / food / water to use     I or Esc - Close"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 20)
	hint.modulate = Color(1, 1, 1, 0.85)
	box.add_child(hint)
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


## Filled slots in display order: Array of {key, name, count, tag, color}. Weapons first (tag EQUIPPED on the one in
## hand, count 0), then inventory items sorted by display name.
func entries() -> Array:
	var out: Array = []
	var p := _player if _player != null and is_instance_valid(_player) else null
	var wc = p.get("weapons") if p != null else null
	if wc != null and is_instance_valid(wc):
		var cur: String = str(wc.slots[wc.current_slot]["id"]) if wc.current_slot >= 0 and wc.current_slot < wc.slots.size() else ""
		for wid in wc.weapon_ids():
			var iid := _weapon_item_id(str(wid))
			out.append({"key": WEAPON_PREFIX + str(wid), "name": _weapon_name(str(wid)), "count": 0,
				"tag": "EQUIPPED" if str(wid) == cur else "", "color": ItemDB.item_color(iid)})
	var items: Array = []
	var inv = p.get("inventory") if p != null else null
	if inv is Dictionary:
		for k in inv:
			var n := int(inv[k])
			if n > 0:
				items.append({"key": str(k), "name": ItemDB.item_name(str(k)), "count": n, "tag": "", "color": ItemDB.item_color(str(k))})
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["name"]) < str(b["name"]))
	return out + items


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
	_entries = entries()
	_ensure_slots(_entries.size())
	for i in slots.size():
		var filled := i < _entries.size()
		var b := slots[i]
		b.disabled = not filled
		if filled:
			var e: Dictionary = _entries[i]
			_name_labels[i].text = str(e["name"])
			_count_labels[i].text = str(e["tag"]) if str(e["tag"]) != "" else "x%d" % int(e["count"])
			b.tooltip_text = describe(i)
			_style_slot(b, e["color"] as Color, true)
		else:
			_name_labels[i].text = ""
			_count_labels[i].text = ""
			b.tooltip_text = ""
			_style_slot(b, Color.BLACK, false)


## Hover text for slot i: name, count, description, type and weight ("" for an empty slot).
func describe(i: int) -> String:
	if i < 0 or i >= _entries.size():
		return ""
	var e: Dictionary = _entries[i]
	var key := str(e["key"])
	if key.begins_with(WEAPON_PREFIX):
		var wid := key.trim_prefix(WEAPON_PREFIX)
		var d: Dictionary = ItemDB.get_item(_weapon_item_id(wid))
		var s := "%s  (weapon%s)" % [str(e["name"]), ", equipped" if str(e["tag"]) != "" else ""]
		if not d.is_empty():
			s += "\n%s   (%.2f kg)" % [str(d.get("desc", "")), float(d.get("weight", 0.0))]
		return s
	var d2: Dictionary = ItemDB.get_item(key)
	var s2 := "%s  x%d" % [str(e["name"]), int(e["count"])]
	if not d2.is_empty():
		s2 += "\n%s   (%s, %.2f kg each)" % [str(d2.get("desc", "")), str(d2.get("type", "item")), float(d2.get("weight", 0.0))]
	return s2


## Clicking slot i: weapons are equipped, medkit / food / water used, everything else reports display only.
func use_slot(i: int) -> void:
	if i < 0 or i >= _entries.size():
		return
	var key: String = str(_entries[i]["key"])
	var nm: String = str(_entries[i]["name"])
	var wc = _player.get("weapons") if _player != null and is_instance_valid(_player) else null
	if key.begins_with(WEAPON_PREFIX):
		var idx: int = wc.weapon_ids().find(key.trim_prefix(WEAPON_PREFIX)) if wc != null else -1
		if idx >= 0:
			wc.equip(idx)
			status_label.text = "Equipped %s." % nm
		else:
			status_label.text = "Cannot equip %s." % nm
	elif not USABLE.has(key):
		status_label.text = "%s: display only (no use or drop action exists for it)." % nm
	elif _player != null and is_instance_valid(_player) and _player.has_method("use_item") and bool(_player.use_item(key)):
		status_label.text = "Used 1 %s." % nm
	else:
		status_label.text = "Cannot use %s right now." % nm
	refresh()


# ------------------------------------------------------------------ internals

func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
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


func _ensure_slots(n: int) -> void:
	var want := maxi(MIN_SLOTS, int(ceil(float(n) / COLUMNS)) * COLUMNS)
	while slots.size() < want:
		_add_slot()


func _add_slot() -> void:
	var i := slots.size()
	var b := Button.new()
	b.custom_minimum_size = SLOT_SIZE
	b.focus_mode = Control.FOCUS_ALL
	b.clip_contents = true
	var nl := _slot_label(b, FONT_SLOT, HORIZONTAL_ALIGNMENT_LEFT, VERTICAL_ALIGNMENT_TOP)
	nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var cl := _slot_label(b, FONT_COUNT, HORIZONTAL_ALIGNMENT_RIGHT, VERTICAL_ALIGNMENT_BOTTOM)
	b.pressed.connect(use_slot.bind(i))
	b.mouse_entered.connect(_show_detail.bind(i))
	b.focus_entered.connect(_show_detail.bind(i))
	b.mouse_exited.connect(_show_detail.bind(-1))
	_grid.add_child(b)
	slots.append(b)
	_name_labels.append(nl)
	_count_labels.append(cl)
	_style_slot(b, Color.BLACK, false)


func _slot_label(parent: Button, font_size: int, h: int, v: int) -> Label:
	var l := Label.new()
	l.horizontal_alignment = h as HorizontalAlignment
	l.vertical_alignment = v as VerticalAlignment
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 6)
	return l


func _show_detail(i: int) -> void:
	var t := describe(i)
	detail_label.text = t if t != "" else IDLE_DETAIL


func _style_slot(b: Button, col: Color, filled: bool) -> void:
	var base := col.darkened(0.45) if filled else Color(0.12, 0.13, 0.12, 0.85)
	var edge := Color(0.45, 0.45, 0.4) if filled else Color(0.25, 0.26, 0.24)
	b.add_theme_stylebox_override("normal", _box(base, edge, 2, 6))
	b.add_theme_stylebox_override("disabled", _box(base, edge, 2, 6))
	b.add_theme_stylebox_override("hover", _box(base.lightened(0.25), KEY_COL, 3, 6))
	b.add_theme_stylebox_override("pressed", _box(base.lightened(0.4), KEY_COL, 3, 6))
	b.add_theme_stylebox_override("focus", _box(base.lightened(0.15), KEY_COL, 3, 6))


static func _box(bg: Color, border: Color, bw: int, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb
