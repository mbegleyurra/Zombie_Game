extends SceneTree
## QA gate (RAT): (1) the REAL Player (player.tscn, its own _physics_process, input via Input.action_press) walks up
## two chained stairs onto an upper storey and back down; (2) independent ledger checks of the chest-fed assembler.
## The Player ignores input unless the mouse is CAPTURED and headless Godot ignores that write, so run under a display:
##   xvfb-run -a godot --rendering-driver opengl3 --path . --script res://tests/t_qa_walk_build.gd

const Extras := preload("res://scripts/building/building_extras.gd")
const Recipes := preload("res://scripts/world/recipes.gd")

var fails := 0
var net: Node
var B: Node
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


## Steer the real player at a horizontal point using only input + yaw.
func _go(target: Vector3, max_frames: int = 600, tol: float = 0.35) -> bool:
	for _i in max_frames:
		await physics_frame
		var to: Vector3 = target - player.global_position
		to.y = 0.0
		if to.length() < tol:
			Input.action_release("move_forward")
			return true
		player.rotation.y = atan2(-to.x, -to.z)
		Input.action_press("move_forward")
	Input.action_release("move_forward")
	return false


func _run() -> void:
	net = root.get_node_or_null("Net")
	if net == null:
		net = _mk("res://scripts/net/network.gd", "Net")
	B = root.get_node_or_null("Building")
	if B == null:
		B = _mk("res://scripts/building/building_system.gd", "Building")
	await _frames(2)
	var fb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 1, 400)
	cs.shape = box
	fb.add_child(cs)
	fb.position = Vector3(0, -0.5, 0)
	root.add_child(fb)
	player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	player.name = "1"
	player.position = Vector3(-3.5, 0.1, 1)
	root.add_child(player)
	await _frames(5)
	check(net.host(17951, 4251) == OK, "Net.host ok")
	net.players[1] = player
	await _frames(3)
	check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "real Player has captured mouse (input is live)")
	B.give("planks", 900)
	B.give("scrap", 900)
	await _frames(2)
	var rejected := [""]
	B.build_rejected.connect(func(r: String) -> void: rejected[0] = r)

	# ---------- stairs: build two flights + upper floor via the real placement path
	player.global_position = Vector3(3.0, 0.1, 3.0)   # within build reach of every piece placed below
	await _frames(3)
	var s_a := Vector4i(0, 0, 0, Extras.SLOT_STAIR + 1)
	var s_b: Vector4i = Extras.chain_key(s_a)
	var up: Vector4i = Extras.landing_key(s_b)
	B.request_place("stairs", s_a)
	await _frames(4)
	print("  after stairs A: slots=%s pieces=%d rejected='%s'" % [str(B.slots.keys()), B.pieces.size(), rejected[0]])
	B.request_place("stairs", s_b)
	await _frames(4)
	print("  after stairs B: slots=%s pieces=%d rejected='%s'" % [str(B.slots.keys()), B.pieces.size(), rejected[0]])
	B.request_place("floor", up)
	await _frames(4)
	print("  after floor: slots=%s pieces=%d rejected='%s'" % [str(B.slots.keys()), B.pieces.size(), rejected[0]])
	check(B.slots.has(s_a) and B.slots.has(s_b) and B.slots.has(up), "two stairs and an upper floor placed (rejected='%s')" % rejected[0])
	if not (B.slots.has(s_a) and B.slots.has(s_b) and B.slots.has(up)):
		print("RESULT fails=%d (setup failed, walk results would be void)" % fails)
		quit(1)
		return
	# a floor one cell further on so there is room to stand and turn
	var up2 := Vector4i(up.x + 1, up.y, up.z, Extras.SLOT_FLOOR)
	B.request_place("floor", up2)
	await _frames(2)

	# harness sanity: forward really moves the player on flat ground
	var p0: Vector3 = player.global_position
	player.rotation.y = -PI * 0.5
	Input.action_press("move_forward")
	await _frames(20)
	Input.action_release("move_forward")
	check(player.global_position.distance_to(p0) > 0.8 and player.global_position.x > p0.x, "harness: forward input moves the real Player +X (%.2f m)" % player.global_position.distance_to(p0))

	# ---------- walk up
	player.global_position = Vector3(-1.5, 0.1, 1)
	player.velocity = Vector3.ZERO
	await _frames(6)
	var gy: float = player.global_position.y
	check(await _go(Vector3(0.9, 0, 1)), "real Player reaches the first ramp")
	check(player.global_position.y > gy + 0.2, "real Player climbs the first ramp (y %.2f -> %.2f)" % [gy, player.global_position.y])
	var ok_top := await _go(Vector3(5.0, 0, 1), 900)
	await _frames(15)
	var y_top: float = player.global_position.y
	print("  upper y=%.3f  (ground-stand y=%.3f, WALL_H=%.2f) on_floor=%s" % [y_top, gy, B.WALL_H, str(player.is_on_floor())])
	check(ok_top, "real Player walks across both flights (x=%.2f)" % player.global_position.x)
	check(absf((y_top - gy) - B.WALL_H) < 0.15 and player.is_on_floor(), "real Player stands on the upper storey (+%.2f m)" % (y_top - gy))
	# onto the second floor cell and back down the stairs
	check(await _go(Vector3(6.5, 0, 1), 300), "real Player can move on the upper floor")
	check(await _go(Vector3(-1.5, 0, 1), 1200, 0.5), "real Player walks back down the stairs (x=%.2f)" % player.global_position.x)
	await _frames(20)
	check(absf(player.global_position.y - gy) < 0.15 and player.is_on_floor(), "real Player is back on the ground (y=%.2f)" % player.global_position.y)
	# blocked ramp from the side: a stairs piece is a ramp, not a wall of treads; walking from the low end must not stall at the first tread
	Input.action_release("move_forward")

	# ---------- automation ledger, independent of tests/t_automation.gd
	var base = B.base
	var ak := Vector4i(5, 0, 5, B.SLOT_BENCH)
	var ck := Vector4i(4, 0, 5, B.SLOT_BENCH)
	player.global_position = Vector3(9, 0.1, 11)
	await _frames(3)
	B.request_place("assembler", ak)
	B.request_place("chest", ck)
	await _frames(4)
	var aid: int = B.slots.get(ak, 0)
	var cid: int = B.slots.get(ck, 0)
	check(aid != 0 and cid != 0 and base.linked_chest(aid) == cid, "assembler + chest placed and linked")
	base.request_set_recipe(aid, "gun_ar_t2")
	var r: Dictionary = Recipes.get_recipe("gun_ar_t2")
	var inv_p0: int = int(B.local_stock["planks"])
	var inv_s0: int = int(B.local_stock["scrap"])
	base.request_deposit(cid, "planks", 30)
	base.request_deposit(cid, "scrap", 60)
	await _frames(3)
	check(int(B.local_stock["planks"]) == inv_p0 - 30 and int(B.local_stock["scrap"]) == inv_s0 - 60, "deposit debits exactly the carried stock")
	# 30 planks / 60 scrap, one cycle costs 12 / 24 -> 2 cycles possible, leftover 6 / 12; real-time first cycle
	await _frames(5)
	check(bool(base.asms[aid]["working"]) and base.chest_count(cid, "planks") == 18 and base.chest_count(cid, "scrap") == 36, "cycle start takes exactly the recipe cost (p=%d s=%d)" % [base.chest_count(cid, "planks"), base.chest_count(cid, "scrap")])
	var dur: float = float(base.asms[aid]["duration"])
	check(is_equal_approx(dur, Extras.craft_time(r)), "cycle duration is craft_time (%.1f s)" % dur)
	await _frames(int(dur * 60.0 * 0.5))
	check(bool(base.asms[aid]["working"]) and base.chest_count(cid, "weapon_ar_t2") == 0, "no product before the cycle ends (halfway)")
	base.time_scale = 30.0
	await _frames(int(dur * 60.0 / 30.0) + 60)
	check(base.chest_count(cid, "weapon_ar_t2") == 2 and base.chest_count(cid, "planks") == 6 and base.chest_count(cid, "scrap") == 12 and int(base.asms[aid]["produced"]) == 2,
		"two cycles: 2 weapons, leftover 6 planks / 12 scrap (w=%d p=%d s=%d n=%d)" % [base.chest_count(cid, "weapon_ar_t2"), base.chest_count(cid, "planks"), base.chest_count(cid, "scrap"), int(base.asms[aid]["produced"])])
	check(String(base.asms[aid]["status"]) == "Waiting for materials", "starved -> '%s'" % base.asms[aid]["status"])
	# the product reaches the real player (weapons live in the weapon controller's slots, not the grid)
	var w = player.weapons
	var had0: bool = w.has_weapon("ar_t2")
	var slots0: int = w.slots.size()
	base.request_withdraw(cid, "weapon_ar_t2", 1)
	await _frames(3)
	check(not had0 and w.has_weapon("ar_t2") and w.slots.size() == slots0 + 1 and base.chest_count(cid, "weapon_ar_t2") == 1,
		"withdrawing 1 built weapon puts it in a weapon slot and leaves 1 in the chest (slots %d -> %d, chest %d)" % [slots0, w.slots.size(), base.chest_count(cid, "weapon_ar_t2")])
	# a second copy of a weapon the player already holds: it must not be destroyed
	base.request_withdraw(cid, "weapon_ar_t2", 1)
	await _frames(3)
	var chest_left: int = base.chest_count(cid, "weapon_ar_t2")
	print("  duplicate withdraw: chest now %d, weapon slots %d (a 2nd copy cannot be held: pickup_weapon never duplicates)" % [chest_left, w.slots.size()])
	check(chest_left == 1, "a duplicate weapon withdraw does not consume the stored weapon (chest %d, expected 1)" % chest_left)
	base.chests[cid] = {}

	# edge: the chest is removed mid-cycle (it is empty then): nothing may be created from nothing
	base.time_scale = 0.0001
	base.chests[cid] = {"planks": 12, "scrap": 24}
	await _frames(10)
	check(bool(base.asms[aid]["working"]) and base.chest_total(cid) == 0, "second weapon cycle started; chest empty")
	B.request_remove(cid)
	await _frames(3)
	print("  mid-cycle chest removal: chest present=%s, rejected='%s', status='%s'" % [str(B.pieces.has(cid)), rejected[0], str(base.asms[aid]["status"])])
	base.time_scale = 100.0
	await _frames(300)
	var a: Dictionary = base.asms[aid]
	print("  after: working=%s status='%s' produced=%d" % [str(a["working"]), str(a["status"]), int(a["produced"])])
	check(not B.pieces.has(cid) and bool(a["working"]) == true and String(a["status"]) == "No chest nearby", "mid-cycle chest removal leaves the cycle parked, not finished")
	base.request_place("chest", ck) if false else B.request_place("chest", ck)
	await _frames(40)
	var cid2: int = B.slots.get(ck, 0)
	check(cid2 != 0 and base.chest_count(cid2, "weapon_ar_t2") == 1 and not bool(base.asms[aid]["working"]), "a replacement chest receives the parked cycle's product (%d)" % base.chest_count(cid2, "weapon_ar_t2"))

	print("RESULT fails=%d" % fails)
	quit(1 if fails > 0 else 0)
