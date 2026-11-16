extends Control
## Base overlay: storage chest, assembler recipe picker and base-core overview.
## Opened by BaseSystem when the player presses E on one of those pieces. Same conventions as
## crafting_ui.gd: joins ui_open while visible (Hud.is_ui_open), E / Esc closes, closing hands the mouse
## back to the game. Every button only sends a request to the host (BaseSystem.request_*); the panel
## redraws when the host's state change arrives.

signal opened
signal closed

const Recipes := preload("res://scripts/world/recipes.gd")
const ItemDB := preload("res://scripts/world/item_db.gd")
const Extras := preload("res://scripts/building/building_extras.gd")

const GROUP_OPEN := "ui_open"
const GROUP_ALL := "overlay_ui"
const FONT_TITLE := 44
const FONT_BODY := 22
const FONT_SMALL := 18
const OK_COL := Color(0.75, 0.95, 0.6)
const BAD_COL := Color(0.95, 0.45, 0.4)
const KEY_COL := Color(0.95, 0.8, 0.35)
const DIM_COL := Color(0.65, 0.65, 0.6)

## Tests set these when BaseSystem / Building are not at their autoload paths.
var base: Node = null
var building: Node = null
var mode := ""                 ## "chest" | "assembler" | "core"
var piece_id := 0
var recipe_buttons := {}       ## assembler: recipe id -> Button
var take_buttons := {}         ## chest: "item:n" (n = 1, 10, all) -> Button
var put_buttons := {}          ## chest: "planks:10", "planks:all", "scrap:10", "scrap:all" -> Button
var toggle_button: Button = null
var progress: ProgressBar = null

var _title: Label
var _stock_label: Label
var _list: VBoxContainer
var _status: Label
var _prev_mouse := Input.MOUSE_MODE_CAPTURED
var _connected := false


func _ready() -> void:
	add_to_group(GROUP_ALL)
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
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", FONT_TITLE)
	_title.add_theme_color_override("font_color", KEY_COL)
	box.add_child(_title)
	_stock_label = Label.new()
	_stock_label.add_theme_font_size_override("font_size", FONT_BODY)
	box.add_child(_stock_label)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(900, 520)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", FONT_SMALL)
	box.add_child(_status)
	var hint := Label.new()
	hint.text = "E / Esc: close"
	hint.add_theme_font_size_override("font_size", FONT_SMALL)
	hint.add_theme_color_override("font_color", DIM_COL)
	box.add_child(hint)


func open_for(id: int, p_mode: String) -> bool:
	if visible:
		return false
	piece_id = id
	mode = p_mode
	_connect()
	_prev_mouse = Input.mouse_mode
	visible = true
	add_to_group(GROUP_OPEN)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_status.text = ""
	refresh()
	opened.emit()
	return true


func close(recapture: bool = true) -> void:
	if not visible:
		return
	visible = false
	remove_from_group(GROUP_OPEN)
	if recapture:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()


func refresh() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	recipe_buttons.clear()
	take_buttons.clear()
	put_buttons.clear()
	toggle_button = null
	progress = null
	var b := _building()
	var stock: Dictionary = b.local_stock if b != null else {}
	_stock_label.text = "You carry: Planks %d    Scrap %d" % [int(stock.get("planks", 0)), int(stock.get("scrap", 0))]
	var bs := _base()
	if bs == null:
		return
	match mode:
		"chest":
			_build_chest(bs, stock)
		"assembler":
			_build_assembler(bs)
		"core":
			_build_core(bs)


func _process(_delta: float) -> void:
	if not visible or progress == null:
		return
	var bs := _base()
	if bs == null or not bs.asms.has(piece_id):
		return
	var a: Dictionary = bs.asms[piece_id]
	var dur := float(a["duration"])
	progress.value = clampf(float(a["elapsed"]) / dur, 0.0, 1.0) if bool(a["working"]) and dur > 0.0 else 0.0


# ------------------------------------------------------------------- panels

func _build_chest(bs: Node, stock: Dictionary) -> void:
	_title.text = "STORAGE CHEST"
	_list.add_child(_label("%d / %d items stored" % [int(bs.chest_total(piece_id)), int(bs.CHEST_CAP)], FONT_BODY, KEY_COL))
	for item in ["planks", "scrap"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.add_child(_label("Deposit %s (carrying %d)" % [item, int(stock.get(item, 0))], FONT_BODY, Color.WHITE, 360))
		var ten := _btn("+10", func() -> void: bs.request_deposit(piece_id, item, 10))
		var all := _btn("+ all", func() -> void: bs.request_deposit(piece_id, item, int(stock.get(item, 0))))
		ten.disabled = int(stock.get(item, 0)) <= 0
		all.disabled = ten.disabled
		row.add_child(ten)
		row.add_child(all)
		_list.add_child(row)
		put_buttons[item + ":10"] = ten
		put_buttons[item + ":all"] = all
	_list.add_child(_label("Contents", FONT_BODY, KEY_COL))
	var items: Dictionary = bs.chests.get(piece_id, {})
	var ids: Array = items.keys()
	ids.sort_custom(func(x: String, y: String) -> bool: return ItemDB.item_name(x) < ItemDB.item_name(y))
	if ids.is_empty():
		_list.add_child(_label("Empty. Deposit materials, or build an assembler within %d m." % int(bs.LINK_RANGE), FONT_SMALL, DIM_COL))
	for item in ids:
		var have := int(items[item])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.add_child(_label("%s  x%d" % [ItemDB.item_name(String(item)), have], FONT_BODY, Color.WHITE, 360))
		for amount in [1, 10, have]:
			var n: int = amount
			var text := "Take all" if n == have and have > 10 else "Take %d" % n
			if n == have and have <= 10 and n != 1 and n != 10:
				text = "Take all"
			var btn := _btn(text, func() -> void: bs.request_withdraw(piece_id, String(item), n))
			row.add_child(btn)
			var key := "%s:%s" % [item, "all" if n == have else str(n)]
			take_buttons[key] = btn
		_list.add_child(row)


func _build_assembler(bs: Node) -> void:
	_title.text = "ASSEMBLER"
	var a: Dictionary = bs.asms.get(piece_id, {})
	if a.is_empty():
		return
	var cid: int = bs.linked_chest(piece_id)
	var cur := Recipes.get_recipe(String(a["recipe"]))
	_list.add_child(_label("Status: %s    Cycles done: %d" % [String(a["status"]), int(a["produced"])], FONT_BODY, OK_COL if bool(a["working"]) else Color.WHITE))
	_list.add_child(_label("Making: " + (String(cur["name"]) if not cur.is_empty() else "nothing selected"), FONT_BODY, Color.WHITE))
	progress = ProgressBar.new()
	progress.min_value = 0.0
	progress.max_value = 1.0
	progress.show_percentage = false
	progress.custom_minimum_size = Vector2(600, 22)
	_list.add_child(progress)
	if cid == 0:
		_list.add_child(_label("No chest within %d m. Build a storage chest next to it." % int(bs.LINK_RANGE), FONT_SMALL, BAD_COL))
	else:
		_list.add_child(_label("Feeds from the chest %d m away (%d items)." % [int(bs.LINK_RANGE), int(bs.chest_total(cid))], FONT_SMALL, DIM_COL))
	toggle_button = _btn("Pause" if bool(a["enabled"]) else "Resume", func() -> void: bs.request_toggle(piece_id))
	_list.add_child(toggle_button)
	_list.add_child(_label("Recipes", FONT_BODY, KEY_COL))
	for r in Extras.recipes():
		var rid := String(r["id"])
		var stocked: bool = cid != 0 and bs.chest_has(cid, r["cost"])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(_label(String(r["name"]), FONT_BODY, Color.WHITE))
		var cost := _label("Cost: %s    %s" % [Recipes.cost_text(r), String(r["desc"])], FONT_SMALL, OK_COL if stocked else BAD_COL)
		cost.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cost.custom_minimum_size = Vector2(620, 0)
		info.add_child(cost)
		row.add_child(info)
		var selected := rid == String(a["recipe"])
		var btn := _btn("Selected" if selected else "Select", func() -> void: bs.request_set_recipe(piece_id, rid))
		btn.disabled = selected
		row.add_child(btn)
		_list.add_child(row)
		recipe_buttons[rid] = btn


func _build_core(bs: Node) -> void:
	_title.text = "BASE CORE"
	var s: Dictionary = bs.summary()
	if not bool(s["claimed"]):
		_list.add_child(_label("No base claimed.", FONT_BODY, BAD_COL))
		return
	_list.add_child(_label("Claimed area: %d m around this core." % int(s["radius"]), FONT_BODY, KEY_COL))
	_list.add_child(_label("Pieces owned: %d" % int(s["total"]), FONT_BODY, Color.WHITE))
	var by_kind: Dictionary = s["pieces"]
	var kinds: Array = by_kind.keys()
	kinds.sort()
	for k in kinds:
		_list.add_child(_label("   %s  x%d" % [String(k), int(by_kind[k])], FONT_SMALL, DIM_COL))
	_list.add_child(_label("Chests: %d    Assemblers: %d (%d working)" % [int(s["chests"]), int(s["assemblers"]), int(s["working"])], FONT_BODY, Color.WHITE))
	_list.add_child(_label("Stored", FONT_BODY, KEY_COL))
	var storage: Dictionary = s["storage"]
	var ids: Array = storage.keys()
	ids.sort()
	if ids.is_empty():
		_list.add_child(_label("   nothing yet", FONT_SMALL, DIM_COL))
	for k in ids:
		_list.add_child(_label("   %s  x%d" % [ItemDB.item_name(String(k)), int(storage[k])], FONT_SMALL, DIM_COL))


# ------------------------------------------------------------------ helpers

func _label(text: String, size: int, col: Color, min_w: int = 0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if min_w > 0:
		l.custom_minimum_size = Vector2(min_w, 0)
	return l


func _btn(text: String, cb: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(130, 48)
	btn.add_theme_font_size_override("font_size", FONT_BODY)
	btn.pressed.connect(cb)
	return btn


func _base() -> Node:
	if base != null and is_instance_valid(base):
		return base
	var b := get_node_or_null("/root/Building")
	return b.get("base") if b != null else null


func _building() -> Node:
	if building != null and is_instance_valid(building):
		return building
	return get_node_or_null("/root/Building")


func _connect() -> void:
	var bs := _base()
	var b := _building()
	if _connected or bs == null:
		return
	_connected = true
	bs.chest_changed.connect(func(id: int) -> void: if visible and id == piece_id: refresh())
	bs.assembler_changed.connect(func(id: int) -> void: if visible and id == piece_id: refresh())
	bs.base_changed.connect(func() -> void: if visible and mode == "core": refresh())
	if b != null:
		b.stock_changed.connect(func(_s: Dictionary) -> void: if visible and mode == "chest": refresh())
		b.build_rejected.connect(func(reason: String) -> void: if visible: _status.text = reason)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	var leave := event.is_action_pressed("ui_cancel")
	if event is InputEventKey:
		var ke := event as InputEventKey
		leave = leave or (ke.pressed and not ke.echo and ke.physical_keycode == KEY_E)
	if leave:
		close()
		get_viewport().set_input_as_handled()


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
