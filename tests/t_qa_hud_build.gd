extends SceneTree
## QA gate (RAT): the HUD build bar lists every building kind (incl. stairs, base core, chest, assembler),
## highlights the selected one, and every kind is reachable by a real key (1-9, then 0 for the 10th).
##   godot --headless --path . --script res://tests/t_qa_hud_build.gd

var fails := 0


func check(cond: bool, label: String) -> void:
	if cond:
		print("PASS  ", label)
	else:
		fails += 1
		print("FAIL  ", label)


func _initialize() -> void:
	_run.call_deferred()


func _mk(path: String, node_name: String) -> Node:
	var n: Node = (load(path) as GDScript).new()
	n.name = node_name
	root.add_child(n)
	return n


func _key(code: int) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = true
	root.push_input(e)


func _run() -> void:
	var net: Node = root.get_node_or_null("Net")
	if net == null:
		net = _mk("res://scripts/net/network.gd", "Net")
	var B: Node = root.get_node_or_null("Building")
	if B == null:
		B = _mk("res://scripts/building/building_system.gd", "Building")
	await physics_frame
	check(net.host(17952, 4252) == OK, "Net.host ok")
	await physics_frame
	var hud: CanvasLayer = _mk("res://scripts/ui/hud.gd", "HUD")
	await physics_frame
	var label: Label = hud.get("_build_label")
	check(label != null, "HUD has a build label")
	B.set_build_mode(true)
	await physics_frame
	check(B.build_mode, "build mode on")
	var text: String = label.text
	print("  build bar:\n", text)
	var kinds: Array = B.KINDS
	check(kinds.size() == 10, "10 build kinds (%d)" % kinds.size())
	for k in kinds:
		var nm: String = str(k).replace("_", " ")
		check(text.to_lower().contains(nm), "bar lists '%s'" % nm)
	check(text.contains("[%s]" % str(kinds[B.selected]).replace("_", " ").to_upper()), "selected kind is bracketed")
	# every kind reachable by a real key event: 1..9 then 0
	var codes: Array = [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_0]
	for i in kinds.size():
		_key(codes[i])
		await physics_frame
		check(B.current_kind() == kinds[i], "key #%d selects '%s' (got '%s')" % [i + 1, kinds[i], B.current_kind()])
		check(label.text.contains("[%s]" % str(kinds[i]).replace("_", " ").to_upper()), "bar highlights '%s' after key" % kinds[i])
	check(text.contains("0"), "bar text mentions the 0 key")
	print("RESULT fails=%d" % fails)
	quit(1 if fails > 0 else 0)
