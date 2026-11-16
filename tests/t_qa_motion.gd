extends SceneTree
## QA gate (RAT): closes two gaps that mutation testing found in the shipped tests.
##  (a) t_viewmodel never proved the reload animation MOVES anything (freezing progress at 0 still passed 209 checks):
##      here every weapon's hands/gun/mag must travel a real distance away from the rest pose mid-reload.
##  (b) t_gore never proved a severed part is hidden (replacing _hide_part with `pass` still passed): here the
##      severed limb/head node must be invisible and the intact one visible.
## Run: godot --headless --path . --script res://tests/t_qa_motion.gd

var fails := 0


func check(cond: bool, label: String) -> void:
	if cond:
		print("PASS  ", label)
	else:
		fails += 1
		print("FAIL  ", label)


func _frames(n: int) -> void:
	for _i in range(n):
		await physics_frame


func _initialize() -> void:
	_run.call_deferred()


func _snap(h: Node3D, gun: Node3D) -> Array:
	return [(h.get_node("Hand_L") as Node3D).position, (h.get_node("Hand_R") as Node3D).position, gun.position, gun.rotation]


func _dist(a: Array, b: Array) -> float:
	return maxf(maxf(a[0].distance_to(b[0]), a[1].distance_to(b[1])), maxf(a[2].distance_to(b[2]), a[3].distance_to(b[3]) * 0.1))


func _run() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 1, 400)
	cs.shape = box
	floor_body.add_child(cs)
	floor_body.position = Vector3(0, -0.5, 0)
	root.add_child(floor_body)
	var player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	player.name = "1"
	player.position = Vector3(0, 0.2, 0)
	root.add_child(player)
	await _frames(10)
	var w: WeaponController = player.weapons
	var ids := WeaponDB.ids()
	for id in ids:
		w.give_weapon(str(id))

	# ---- (a) reload animation really moves hands / gun
	for id in ids:
		var sid := str(id)
		var wd: WeaponData = WeaponDB.get_weapon(sid)
		var idx := w.weapon_ids().find(sid)
		if idx < 0:
			check(false, "[%s] in slots" % sid)
			continue
		if w.current_slot != idx:
			w.equip(idx)
		await _frames(40)
		var h: Node3D = w._hands
		if h == null:
			check(false, "[%s] hands exist" % sid)
			continue
		var s: Dictionary = w.slots[idx]
		s["mag"] = maxi(wd.mag_size - 3, 0)
		s["chambered"] = true
		player.inventory[wd.caliber] = 999
		var rest := _snap(h, w._gun)
		if not w.start_reload():
			check(false, "[%s] reload starts" % sid)
			continue
		var best := 0.0
		for _k in range(9):
			h.advance(h.duration() * 0.1)
			if h.is_playing():
				best = maxf(best, _dist(rest, _snap(h, w._gun)))
		check(best > 0.03, "[%s] reload moves hands/gun away from rest (max travel %.3f m)" % [sid, best])
		h.cancel()
		w.cancel_reload()
		await _frames(2)

	# ---- (b) severed parts are hidden
	var zsp := ZombieSpawner.new()
	root.add_child(zsp)
	zsp.enabled = false
	await _frames(3)
	var za: Zombie = zsp.spawn_zombie_at(Vector3(40, 0.1, 20), false, Zombie.KIND_WALKER)
	za.rotation.y = 0.0
	await _frames(3)
	check(za._arms.size() > 1, "walker has two arm nodes to hide (%d)" % za._arms.size())
	za._take_damage(35.0, false, 0, za.global_position + Vector3(0.4, 1.0, 0), Vector3(0, 0, -1))
	if za._arms.size() > 1:
		check(not (za._arms[1] as Node3D).visible, "severed right arm node is hidden")
		check((za._arms[0] as Node3D).visible, "intact left arm node stays visible")
	var zh: Zombie = zsp.spawn_zombie_at(Vector3(60, 0.1, 20), false, Zombie.KIND_WALKER)
	zh.rotation.y = 0.0
	await _frames(3)
	zh._take_damage(150.0, true, 0, zh.global_position + Vector3(0, 1.7, 0), Vector3(0, 0, -1))
	check(zh._head != null and not (zh._head as Node3D).visible, "decapitated head node is hidden")

	print("RESULT failures=", fails)
	quit(1 if fails > 0 else 0)
