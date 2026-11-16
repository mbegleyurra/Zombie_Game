extends SceneTree
## Stairs, multi-storey bases, base core (claim marker) and storage chests.
## Run: godot --headless --path . --script res://tests/t_base_build.gd

const Extras := preload("res://scripts/building/building_extras.gd")

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


## Walks a bare CharacterBody3D (default floor angle) along `dir`; the real player reads Input, so a proxy is used.
func _walk(body: CharacterBody3D, dir: Vector3, frames: int) -> void:
	for _i in frames:
		body.velocity.x = dir.x * 3.0
		body.velocity.z = dir.z * 3.0
		body.velocity.y -= 24.0 / 60.0
		body.move_and_slide()
		await physics_frame


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
	check(net.host(17933, 4244) == OK, "Net.host ok")
	net.players[1] = player
	await _frames(3)
	var B = building
	B.give("planks", 500)
	B.give("scrap", 500)
	await _frames(2)
	var rejected := [""]
	B.build_rejected.connect(func(r: String) -> void: rejected[0] = r)

	# ---- kinds and costs
	for k in ["stairs", "base_core", "chest", "assembler"]:
		check(B.KINDS.has(k) and B.DEFS.has(k), "%s is a build kind" % k)
		var cost: Dictionary = B.DEFS[k]["cost"]
		check(cost.keys().all(func(m): return m == "planks" or m == "scrap"), "%s costs planks/scrap only" % k)
	check(B.base != null and B.base.name == "BaseSystem", "Building owns a BaseSystem")

	# ---- stair geometry helpers
	for d in 4:
		var yaw := Extras.stair_yaw(d)
		var fwd := Basis(Vector3.UP, yaw) * Vector3(0, 0, -1)
		var v := Extras.stair_dir(d)
		check(absf(fwd.x - v.x) < 0.001 and absf(fwd.z - v.y) < 0.001, "stair yaw %d faces its climb direction" % d)
	var s_a := Vector4i(0, 0, 0, Extras.SLOT_STAIR + 1)
	check(Extras.landing_key(s_a) == Vector4i(1, 5, 0, B.SLOT_FLOOR), "landing key is one cell on, STAIR_STEPS up")
	check(Extras.chain_key(s_a) == Vector4i(1, 5, 0, s_a.w), "chain key continues the same direction")
	check(Extras.STAIR_STEPS * 2 == Extras.STOREY_STEPS and Extras.STOREY_STEPS * B.YSTEP == B.WALL_H, "two stairs climb exactly one wall height")

	# ---- stairs: placement and slot rules
	var before_planks: int = int(B.local_stock["planks"])
	B.request_place("stairs", s_a)
	await _frames(3)
	check(B.pieces.size() == 1 and B.slots.has(s_a), "stairs placed (%d pieces)" % B.pieces.size())
	check(int(B.local_stock["planks"]) == before_planks - int(B.DEFS["stairs"]["cost"]["planks"]), "stairs cost taken")
	var a_id: int = B.slots[s_a]
	var a_node: Node3D = B.pieces[a_id]["node"]
	check(a_node is StaticBody3D and a_node.find_children("*", "CollisionShape3D", true, false).size() >= 1, "stairs have a collider")
	check(a_node.position.is_equal_approx(Vector3(1, 0, 1)), "stairs sit on the cell centre %s" % str(a_node.position))
	var climb := a_node.global_transform.basis * Vector3(0, 0, -1)
	check(climb.is_equal_approx(Vector3(1, 0, 0)), "placed stairs climb toward +X (%s)" % str(climb))
	rejected[0] = ""
	B.request_place("stairs", Vector4i(0, 0, 0, Extras.SLOT_STAIR + 2))
	await _frames(2)
	check(rejected[0] == "Stairs already here", "second stairs direction in the cell rejected (%s)" % rejected[0])
	rejected[0] = ""
	B.request_place("stairs", Vector4i(4, 0, 4, B.SLOT_FLOOR))
	await _frames(2)
	check(rejected[0] == "Bad slot", "stairs in the floor slot rejected (%s)" % rejected[0])
	rejected[0] = ""
	B.request_place("floor", Vector4i(0, 5, 0, B.SLOT_FLOOR))
	await _frames(2)
	check(rejected[0] == "Stairs in the way", "floor blocking the ramp rejected (%s)" % rejected[0])
	B.request_place("floor", Vector4i(-1, 5, 2, B.SLOT_FLOOR))
	await _frames(3)
	rejected[0] = ""
	B.request_place("stairs", Vector4i(-1, 0, 2, Extras.SLOT_STAIR))
	await _frames(2)
	check(rejected[0] == "Floor in the way", "stairs under an existing floor rejected (%s)" % rejected[0])

	# ---- aiming snaps floor/stairs onto the top of a stairs piece
	var hit := {"position": Vector3(1.5, 0.6, 1), "normal": Vector3(0, 1, 0), "collider": a_node, "from": Vector3(-3, 1.5, 1)}
	check(B._compute_key(hit, "floor") == Extras.landing_key(s_a), "aiming a floor at stairs snaps to the landing")
	check(B._compute_key(hit, "stairs") == Extras.chain_key(s_a), "aiming stairs at stairs chains them")
	var open_hit := {"position": Vector3(0.5, 0.0, 9), "normal": Vector3(0, 1, 0), "collider": floor_body, "from": Vector3(-3, 1.5, 9)}
	check(B._compute_key(open_hit, "stairs").w == Extras.SLOT_STAIR + 1, "stairs on open ground climb away from the player")

	# ---- two storeys: stairs, chained stairs, upper floor
	var s_b: Vector4i = Extras.chain_key(s_a)
	var up_floor: Vector4i = Extras.landing_key(s_b)
	B.request_place("stairs", s_b)
	await _frames(3)
	check(B.slots.has(s_b), "chained stairs placed")
	B.request_place("floor", up_floor)
	await _frames(3)
	check(B.slots.has(up_floor), "upper-storey floor placed at %s" % str(up_floor))
	check(is_equal_approx(B.key_position(up_floor).y, B.WALL_H), "upper floor sits one wall height up")

	# a character can really walk up both flights and stand on the upper floor
	var body := CharacterBody3D.new()
	var bcs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.8
	bcs.shape = cap
	body.add_child(bcs)
	body.position = Vector3(-1.5, 0.95, 1)
	root.add_child(body)
	await _walk(body, Vector3.ZERO, 8)
	check(body.is_on_floor() and absf(body.position.y - 0.9) < 0.1, "walker stands on the ground (y=%.2f)" % body.position.y)
	await _walk(body, Vector3(1, 0, 0), 40)
	var feet := body.position.y - 0.9
	check(feet > 0.1 and body.position.x > -0.5, "walker climbs the first ramp (feet y=%.2f x=%.2f)" % [feet, body.position.x])
	var guard := 0
	while body.position.x < 5.2 and guard < 400:
		await _walk(body, Vector3(1, 0, 0), 1)
		guard += 1
	await _walk(body, Vector3.ZERO, 10)
	feet = body.position.y - 0.9
	check(body.position.x > 4.3 and body.position.x < 6.0, "walker crossed both flights (x=%.2f)" % body.position.x)
	check(absf(feet - B.WALL_H) < 0.12 and body.is_on_floor(), "walker stands on the upper storey (feet y=%.2f)" % feet)
	body.queue_free()

	# stairs under an upper floor must be removable from the ground
	check(a_id != 0 and B.pieces.has(a_id), "first stairs still present")

	# ---- base core (claim marker)
	check(not bool(B.base.summary()["claimed"]), "no base before a core is placed")
	var core_key := Vector4i(0, 0, 3, B.SLOT_BENCH)
	B.request_place("base_core", core_key)
	await _frames(3)
	check(B.base.core_id != 0 and B.pieces[B.base.core_id]["kind"] == "base_core", "base core placed")
	rejected[0] = ""
	B.request_place("base_core", Vector4i(2, 0, 3, B.SLOT_BENCH))
	await _frames(2)
	check(rejected[0] == "Base already claimed", "second core rejected (%s)" % rejected[0])
	var s0: Dictionary = B.base.summary()
	check(bool(s0["claimed"]) and (s0["core_pos"] as Vector3).is_equal_approx(Vector3(1, 0, 7)), "summary claims around the core")
	check(int(s0["pieces"].get("stairs", 0)) == 2 and int(s0["pieces"].get("floor", 0)) == 2 and int(s0["pieces"].get("base_core", 0)) == 1,
		"summary counts what the base owns (%s)" % str(s0["pieces"]))

	# ---- storage chest
	var chest_key := Vector4i(1, 0, 3, B.SLOT_BENCH)
	B.request_place("chest", chest_key)
	await _frames(3)
	var cid: int = B.slots.get(chest_key, 0)
	check(cid != 0 and B.base.chests.has(cid), "chest placed and registered")
	var p0: int = int(B.local_stock["planks"])
	B.base.request_deposit(cid, "planks", 10)
	await _frames(2)
	check(B.base.chest_count(cid, "planks") == 10 and int(B.local_stock["planks"]) == p0 - 10, "deposit moves planks into the chest")
	rejected[0] = ""
	B.base.request_deposit(cid, "ammo_9mm", 5)
	await _frames(2)
	check(rejected[0] == "Only planks and scrap" and B.base.chest_count(cid, "ammo_9mm") == 0, "only materials can be deposited (%s)" % rejected[0])
	var scrap_before: int = int(B.local_stock["scrap"])
	B.base.request_deposit(cid, "scrap", 100000)
	await _frames(2)
	check(B.base.chest_count(cid, "scrap") == mini(scrap_before, B.base.MAX_MOVE), "deposit is clamped to MAX_MOVE / what is carried (%d)" % B.base.chest_count(cid, "scrap"))
	var carried_scrap: int = int(B.local_stock["scrap"])
	check(carried_scrap >= 0 and B.base.chest_count(cid, "scrap") + carried_scrap == scrap_before, "scrap is conserved (chest %d + carried %d)" % [B.base.chest_count(cid, "scrap"), carried_scrap])
	rejected[0] = ""
	B.request_remove(cid)
	await _frames(2)
	check(B.pieces.has(cid) and rejected[0] == "Empty the chest first", "full chest cannot be removed (%s)" % rejected[0])
	var s1: Dictionary = B.base.summary()
	check(int(s1["chests"]) == 1 and int(s1["storage"].get("planks", 0)) == 10, "summary lists chest contents")
	var p1: int = int(B.local_stock["planks"])
	B.base.request_withdraw(cid, "planks", 4)
	await _frames(2)
	check(B.base.chest_count(cid, "planks") == 6 and int(B.local_stock["planks"]) == p1 + 4, "withdraw returns planks")
	# a stored product (ammo) goes to the inventory
	B.base._chest_add(cid, "ammo_9mm", 30)
	var nine0: int = player.count_item("9mm")
	B.base.request_withdraw(cid, "ammo_9mm", 12)
	await _frames(2)
	check(B.base.chest_count(cid, "ammo_9mm") == 18 and player.count_item("9mm") == nine0 + 12, "withdraw hands ammo to the player (+12)")
	B.base.request_withdraw(cid, "no_such_item", 5)
	await _frames(2)
	check(B.base.chest_total(cid) == 6 + 18 + B.base.chest_count(cid, "scrap"), "withdrawing an absent item changes nothing")
	# empty it, then it can be removed and refunds half
	B.base.chests[cid] = {}
	rejected[0] = ""
	B.request_remove(cid)
	await _frames(3)
	check(not B.pieces.has(cid) and not B.base.chests.has(cid), "empty chest removed and unregistered")

	# ---- overlay builds for the core and a chest
	var ui = (load("res://scripts/building/base_ui.gd") as GDScript).new()
	ui.base = B.base
	ui.building = B
	root.add_child(ui)
	await _frames(2)
	ui.open_for(B.base.core_id, "core")
	check(ui.visible and ui.is_in_group("ui_open"), "core overlay opens and joins ui_open")
	ui.close(false)
	check(not ui.visible and not ui.is_in_group("ui_open"), "overlay closes and leaves ui_open")

	# ---- clear_all drops base state
	B.clear_all()
	await _frames(2)
	check(B.base.core_id == 0 and B.base.chests.is_empty() and B.base.asms.is_empty(), "clear_all resets the base")

	print("t_base_build fails=", fails)
	quit(1 if fails > 0 else 0)
