extends SceneTree
## Assembler automation: a chest-fed assembler turns planks/scrap into recipe outputs over time.
## Run: godot --headless --path . --script res://tests/t_automation.gd

const Extras := preload("res://scripts/building/building_extras.gd")
const Recipes := preload("res://scripts/world/recipes.gd")
const ItemDB := preload("res://scripts/world/item_db.gd")

var fails := 0
var net: Node
var building: Node
var player


func check(cond: bool, label: String) -> void:
	if cond:
		print("PASS  ", label)
	else:
		fails += 1
		print("FAIL  ", label)


func _initialize() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for _i in n:
		await physics_frame


func _mk(path: String, node_name: String) -> Node:
	var n: Node = (load(path) as GDScript).new()
	n.name = node_name
	root.add_child(n)
	return n


func _run() -> void:
	net = root.get_node_or_null("Net")
	if net == null:
		net = _mk("res://scripts/net/network.gd", "Net")
	building = root.get_node_or_null("Building")
	if building == null:
		building = _mk("res://scripts/building/building_system.gd", "Building")
	await _frames(2)
	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 1, 400)
	cs.shape = box
	floor_body.add_child(cs)
	floor_body.position = Vector3(0, -0.5, 0)
	root.add_child(floor_body)
	player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	player.name = "1"
	player.position = Vector3(0, 0.1, 5)
	root.add_child(player)
	await _frames(5)
	check(net.host(17934, 4245) == OK, "Net.host ok")
	net.players[1] = player
	await _frames(3)
	var B = building
	var base = B.base
	B.give("planks", 500)
	B.give("scrap", 500)
	await _frames(2)
	var rejected := [""]
	B.build_rejected.connect(func(r: String) -> void: rejected[0] = r)

	# ---- recipe catalogue
	var recs: Array = Extras.recipes()
	check(not recs.is_empty() and recs.all(func(r): return ItemDB.has_item(Extras.output_item(r))), "every assembler recipe yields a real item (%d recipes)" % recs.size())
	check(Extras.output_item(Recipes.get_recipe("ammo_9mm")) == "ammo_9mm", "ammo recipe output is the canonical ammo item")
	check(Extras.output_item(Recipes.get_recipe("gun_ar_t1")) == "weapon_ar_t1", "weapon recipe output is the weapon item")
	check(Extras.craft_time(Recipes.get_recipe("gun_ar_t3")) > Extras.craft_time(Recipes.get_recipe("ammo_9mm")), "bigger recipes take longer")

	# ---- assembler alone: no chest
	var asm_key := Vector4i(1, 0, 3, B.SLOT_BENCH)
	B.request_place("assembler", asm_key)
	await _frames(3)
	var aid: int = B.slots.get(asm_key, 0)
	check(aid != 0 and base.asms.has(aid), "assembler placed and registered")
	var node: Node3D = B.pieces[aid]["node"]
	check(node is StaticBody3D and node.is_in_group("building") and node.get_node_or_null("Light") != null, "assembler has a collider, model and status lamp")
	check(String(base.asms[aid]["recipe"]) == "" and String(base.asms[aid]["status"]) == "Pick a recipe", "new assembler waits for a recipe")
	rejected[0] = ""
	base.request_set_recipe(aid, "no_such_recipe")
	await _frames(2)
	check(rejected[0] == "Unknown recipe" and String(base.asms[aid]["recipe"]) == "", "unknown recipe rejected (%s)" % rejected[0])
	base.request_set_recipe(aid, "ammo_9mm")
	await _frames(4)
	check(String(base.asms[aid]["recipe"]) == "ammo_9mm" and String(base.asms[aid]["status"]) == "No chest nearby", "no chest -> status '%s'" % base.asms[aid]["status"])

	# ---- chest feeds it
	var chest_key := Vector4i(0, 0, 3, B.SLOT_BENCH)
	B.request_place("chest", chest_key)
	await _frames(3)
	var cid: int = B.slots.get(chest_key, 0)
	check(cid != 0 and base.linked_chest(aid) == cid, "assembler links to the nearby chest")
	await _frames(3)
	check(String(base.asms[aid]["status"]) == "Waiting for materials", "empty chest -> status '%s'" % base.asms[aid]["status"])
	base.time_scale = 200.0
	base.request_deposit(cid, "planks", 1)
	base.request_deposit(cid, "scrap", 2)
	await _frames(40)
	var r9: Dictionary = Recipes.get_recipe("ammo_9mm")
	check(base.chest_count(cid, "ammo_9mm") == int(r9["count"]), "one cycle produced %d x 9mm (%d)" % [int(r9["count"]), base.chest_count(cid, "ammo_9mm")])
	check(base.chest_count(cid, "planks") == 0 and base.chest_count(cid, "scrap") == 0, "inputs were consumed exactly")
	check(int(base.asms[aid]["produced"]) == 1 and not bool(base.asms[aid]["working"]), "cycle counter 1, assembler idle again")
	check(String(base.asms[aid]["status"]) == "Waiting for materials", "starved again -> '%s'" % base.asms[aid]["status"])

	# ---- keeps running while the chest is stocked
	base.request_deposit(cid, "planks", 3)
	base.request_deposit(cid, "scrap", 6)
	await _frames(80)
	check(base.chest_count(cid, "ammo_9mm") == 4 * int(r9["count"]) and int(base.asms[aid]["produced"]) == 4,
		"three more cycles ran unattended (ammo %d, cycles %d)" % [base.chest_count(cid, "ammo_9mm"), int(base.asms[aid]["produced"])])

	# ---- pause / resume
	base.request_toggle(aid)
	await _frames(2)
	check(not bool(base.asms[aid]["enabled"]) and String(base.asms[aid]["status"]) == "Paused", "pause -> '%s'" % base.asms[aid]["status"])
	base.request_deposit(cid, "planks", 1)
	base.request_deposit(cid, "scrap", 2)
	await _frames(30)
	check(base.chest_count(cid, "ammo_9mm") == 4 * int(r9["count"]) and base.chest_count(cid, "planks") == 1, "paused assembler does not touch the chest")
	base.request_toggle(aid)
	await _frames(40)
	check(base.chest_count(cid, "ammo_9mm") == 5 * int(r9["count"]), "resume continues the work")

	# ---- full chest: nothing is lost or created
	base.chests[cid] = {"planks": 1, "scrap": 398}
	await _frames(20)
	check(String(base.asms[aid]["status"]) == "Chest full" and base.chest_count(cid, "scrap") == 398 and base.chest_count(cid, "planks") == 1,
		"full chest blocks the cycle without eating inputs (%s)" % base.asms[aid]["status"])
	base.chests[cid] = {}

	# ---- a weapon recipe
	base.request_set_recipe(aid, "gun_ar_t1")
	await _frames(3)
	base.chests[cid] = {"planks": 6, "scrap": 10}
	await _frames(60)
	check(base.chest_count(cid, "weapon_ar_t1") == 1 and base.chest_total(cid) == 1, "assembler built a Scrapper AR from planks and scrap")
	base.chests[cid] = {}

	# ---- recipe-picker UI
	var ui = (load("res://scripts/building/base_ui.gd") as GDScript).new()
	ui.base = base
	ui.building = B
	root.add_child(ui)
	await _frames(2)
	ui.open_for(aid, "assembler")
	check(ui.visible and ui.recipe_buttons.has("ammo_9mm") and ui.recipe_buttons.has("gun_ar_t1") and ui.recipe_buttons.size() == recs.size(),
		"UI lists every recipe (%d buttons)" % ui.recipe_buttons.size())
	check(ui.recipe_buttons["gun_ar_t1"].disabled and not ui.recipe_buttons["ammo_556"].disabled, "UI marks the current recipe as selected")
	ui.recipe_buttons["ammo_556"].pressed.emit()
	await _frames(3)
	check(String(base.asms[aid]["recipe"]) == "ammo_556", "picking a recipe in the UI selects it on the host (%s)" % base.asms[aid]["recipe"])
	check(ui.recipe_buttons["ammo_556"].disabled and not ui.recipe_buttons["gun_ar_t1"].disabled, "UI refreshed after the change")
	ui.toggle_button.pressed.emit()
	await _frames(2)
	check(not bool(base.asms[aid]["enabled"]), "UI pause button pauses the assembler")
	ui.toggle_button.pressed.emit()
	await _frames(2)
	check(bool(base.asms[aid]["enabled"]) and ui.progress != null, "UI resume button resumes; progress bar present")
	ui.close(false)
	base.request_set_recipe(aid, "ammo_9mm")
	await _frames(3)

	# ---- busy assembler: locked and cannot be taken down; lamp and summary show it
	base.time_scale = 0.0001
	base.chests[cid] = {"planks": 1, "scrap": 2}
	await _frames(15)
	check(bool(base.asms[aid]["working"]), "assembler is mid-cycle")
	var lamp := node.get_node("Light") as MeshInstance3D
	check((lamp.material_override as StandardMaterial3D).albedo_color.g > 0.9, "status lamp is green while working")
	B.request_place("base_core", Vector4i(2, 0, 3, B.SLOT_BENCH))
	await _frames(3)
	check(int(base.summary()["working"]) == 1 and int(base.summary()["assemblers"]) == 1, "base summary counts the working assembler")
	check(base.chest_total(cid) == 0, "inputs are taken when the cycle starts")
	rejected[0] = ""
	base.request_set_recipe(aid, "ammo_556")
	await _frames(2)
	check(rejected[0] == "Assembler busy" and String(base.asms[aid]["recipe"]) == "ammo_9mm", "recipe cannot change mid-cycle (%s)" % rejected[0])
	rejected[0] = ""
	B.request_remove(aid)
	await _frames(2)
	check(B.pieces.has(aid) and rejected[0] == "Assembler busy", "busy assembler cannot be removed (%s)" % rejected[0])

	# ---- client sync handlers rebuild the same state (host -> client RPC bodies run locally)
	var chests_snap: Dictionary = base.chests.duplicate(true)
	var asms_snap: Dictionary = base.asms.duplicate(true)
	base._rpc_asm(aid, "ammo_68", true, true, 1.5, 9.0, "Working", 7)
	check(String(base.asms[aid]["recipe"]) == "ammo_68" and int(base.asms[aid]["produced"]) == 7 and is_equal_approx(float(base.asms[aid]["elapsed"]), 1.5), "client applies an assembler update")
	base._rpc_chest(cid, {"planks": 5})
	check(base.chest_count(cid, "planks") == 5, "client applies a chest update")
	base.chests.clear()
	base.asms.clear()
	base._rpc_sync(chests_snap, asms_snap)
	check(base.chests.has(cid) and base.asms.has(aid) and String(base.asms[aid]["recipe"]) == "ammo_9mm" and bool(base.asms[aid]["working"]),
		"late-join snapshot restores chests and assemblers")

	# ---- finish the cycle, then it can be removed
	base.time_scale = 200.0
	await _frames(30)
	check(not bool(base.asms[aid]["working"]) and base.chest_count(cid, "ammo_9mm") == int(r9["count"]), "cycle finished and delivered to the chest")
	base.chests[cid] = {}
	B.request_remove(aid)
	await _frames(3)
	check(not B.pieces.has(aid) and not base.asms.has(aid), "idle assembler removed and unregistered")

	print("t_automation fails=", fails)
	quit(1 if fails > 0 else 0)
