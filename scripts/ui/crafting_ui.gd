extends Control
## Workbench crafting overlay. Opened by Building when the player presses E at a workbench.
## Lists every recipe in scripts/world/recipes.gd with its cost; a row is greyed out while the
## player's planks/scrap (Building.local_stock) cannot pay for it. Pressing Craft only sends a
## request: the host takes the materials and hands the result over (Building.request_craft).
## E or Esc closes it. Closing hands the mouse back to the game.

signal opened
signal closed

const Recipes := preload("res://scripts/world/recipes.gd")

const GROUP_OPEN := "ui_open"      ## Hud.is_ui_open() is true while any member is in this group
const GROUP_ALL := "overlay_ui"    ## get_tree().call_group("overlay_ui", "close", false)
const FONT_TITLE := 44
const FONT_BODY := 22
const FONT_SMALL := 18
const OK_COL := Color(0.75, 0.95, 0.6)
const BAD_COL := Color(0.95, 0.45, 0.4)
const KEY_COL := Color(0.95, 0.8, 0.35)

## Tests set this to drive the overlay without the Net/Hud autoloads.
var standalone := false
## Tests may point this at a Building instance that is not an autoload.
var building: Node = null
var rows: Array = []          ## [{id, button, name_label, cost_label}]

var _list: VBoxContainer
var _stock_label: Label
var _status_label: Label
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
	var title := Label.new()
	title.text = "WORKBENCH"
	title.add_theme_font_size_override("font_size", FONT_TITLE)
	title.add_theme_color_override("font_color", KEY_COL)
	box.add_child(title)
	_stock_label = Label.new()
	_stock_label.add_theme_font_size_override("font_size", FONT_BODY)
	box.add_child(_stock_label)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(900, 560)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)
	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", FONT_SMALL)
	box.add_child(_status_label)
	var hint := Label.new()
	hint.text = "E / Esc: close"
	hint.add_theme_font_size_override("font_size", FONT_SMALL)
	hint.add_theme_color_override("font_color", Color(0.65, 0.65, 0.6))
	box.add_child(hint)


func open() -> bool:
	if visible:
		return false
	_connect()
	_prev_mouse = Input.mouse_mode
	visible = true
	add_to_group(GROUP_OPEN)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_status_label.text = ""
	refresh()
	opened.emit()
	return true


## recapture: give the mouse back to the player (not wanted when something else takes over the mouse).
func close(recapture: bool = true) -> void:
	if not visible:
		return
	visible = false
	remove_from_group(GROUP_OPEN)
	if recapture:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()


func refresh() -> void:
	var b := _building()
	var stock: Dictionary = b.local_stock if b != null else {}
	_stock_label.text = "Planks %d    Scrap %d" % [int(stock.get("planks", 0)), int(stock.get("scrap", 0))]
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	rows.clear()
	var section := ""
	for r in Recipes.all():
		var kind: String = r["kind"]
		if kind != section:
			section = kind
			_list.add_child(_header({"weapon": "ASSAULT RIFLES", "gear": "BACKPACKS"}.get(kind, "AMMUNITION")))
		_list.add_child(_make_row(r, b))


func _make_row(r: Dictionary, b: Node) -> Control:
	var owned := _owned(r)
	var affordable: bool = b != null and bool(b.can_afford_cost(r["cost"]))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var name_label := Label.new()
	name_label.text = String(r["name"])
	name_label.add_theme_font_size_override("font_size", FONT_BODY)
	info.add_child(name_label)
	var cost_label := Label.new()
	cost_label.text = "Cost: " + Recipes.cost_text(r) + "   " + String(r["desc"])
	cost_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cost_label.custom_minimum_size = Vector2(620, 0)
	cost_label.add_theme_font_size_override("font_size", FONT_SMALL)
	cost_label.add_theme_color_override("font_color", OK_COL if affordable else BAD_COL)
	info.add_child(cost_label)
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(190, 56)
	btn.add_theme_font_size_override("font_size", FONT_BODY)
	btn.text = "Owned" if owned else ("Craft" if affordable else "Need materials")
	btn.disabled = owned or not affordable
	btn.pressed.connect(_on_craft.bind(String(r["id"])))
	row.add_child(btn)
	rows.append({"id": String(r["id"]), "button": btn, "name_label": name_label, "cost_label": cost_label})
	return row


func _header(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", FONT_BODY)
	l.add_theme_color_override("font_color", KEY_COL)
	return l


## A rifle the player already holds would only convert into a magazine, so it is not offered twice.
func _owned(r: Dictionary) -> bool:
	if r["kind"] != "weapon":
		return false
	var net := get_node_or_null("/root/Net")
	var pl: Node = net.get_local_player() if net != null else null
	return pl != null and is_instance_valid(pl) and pl.has_method("count_item") and int(pl.count_item(String(r["give"]))) > 0


func _on_craft(recipe_id: String) -> void:
	var b := _building()
	if b == null:
		return
	_status_label.text = "Crafting..."
	b.request_craft(recipe_id)


func _on_crafted(recipe_id: String) -> void:
	var r := Recipes.get_recipe(recipe_id)
	_status_label.text = "Crafted: " + String(r.get("name", recipe_id))
	if visible:
		refresh()


func _on_rejected(reason: String) -> void:
	if visible:
		_status_label.text = reason


func _building() -> Node:
	if building != null and is_instance_valid(building):
		return building
	return get_node_or_null("/root/Building")


func _connect() -> void:
	var b := _building()
	if _connected or b == null:
		return
	_connected = true
	b.stock_changed.connect(func(_s: Dictionary): if visible: refresh())
	b.crafted.connect(_on_crafted)
	b.build_rejected.connect(_on_rejected)


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
