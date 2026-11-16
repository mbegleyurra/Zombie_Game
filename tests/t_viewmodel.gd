extends SceneTree
## First-person hands + reload animation (scripts/weapons/viewmodel.gd). Iterates WeaponDB at runtime, so
## every weapon added later is covered. Rendering is not checked (headless); this checks structure,
## timing, state and cancellation. Run:
##   godot --headless --path . --script res://tests/t_viewmodel.gd

var fails := 0


func check(cond: bool, label: String) -> void:
	if cond:
		print("PASS  ", label)
	else:
		fails += 1
		print("FAIL  ", label)


func _initialize() -> void:
	_run()


func _frames(n: int) -> void:
	for _i in range(n):
		await physics_frame


func _finite(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)


## Steps the animation in fixed slices; returns the simulated seconds it took to finish (-1 = never).
func _run_to_end(h: Node3D, dt: float, limit: float) -> float:
	var t := 0.0
	while h.is_playing() and t < limit:
		h.advance(dt)
		t += dt
	return t if not h.is_playing() else -1.0


func _arm_ok(h: Node3D) -> bool:
	for n in ["Hand_R", "Hand_L", "Arm_R", "Arm_L"]:
		var node := h.get_node_or_null(n) as Node3D
		if node == null or not _finite(node.position):
			return false
	return true


func _run() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
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

	var ids: Array = WeaponDB.ids()
	check(ids.size() >= 5, "WeaponDB lists %d weapons: %s" % [ids.size(), str(ids)])
	for id in ids:
		w.give_weapon(str(id))
	var styles := {}

	for id in ids:
		var sid := str(id)
		var wd: WeaponData = WeaponDB.get_weapon(sid)
		var idx := w.weapon_ids().find(sid)
		check(idx >= 0, "[%s] weapon is in the slots" % sid)
		if idx < 0:
			continue
		if w.current_slot != idx:
			w.equip(idx)
		await _frames(40)
		check(w.state == WeaponController.State.READY, "[%s] ready after the draw" % sid)
		var h: Node3D = w._hands
		check(h != null and is_instance_valid(h), "[%s] hands exist on the local viewmodel" % sid)
		if h == null:
			continue
		check(_arm_ok(h), "[%s] both hands and forearms exist with finite positions" % sid)
		check(h.get_parent() == w._gun, "[%s] hands ride on the gun mesh" % sid)
		var style: String = h.style()
		styles[style] = true
		check(style in ["pistol", "rifle", "bolt", "shell"], "[%s] reload style '%s'" % [sid, style])
		check(style == "shell" if wd.per_round_reload else style != "shell", "[%s] style matches per_round_reload=%s" % [sid, str(wd.per_round_reload)])
		check(w._gun.get_child_count() > 0 and GunMesh.muzzle_of(w._gun) != null, "[%s] gun keeps its muzzle after the hands re-parent parts" % sid)

		# ---- tactical reload (round chambered, mag one short)
		var s: Dictionary = w.slots[idx]
		s["mag"] = maxi(wd.mag_size - 3, 0)
		s["chambered"] = true
		player.inventory[wd.caliber] = 999
		var missing: int = wd.mag_size - int(s["mag"])
		check(w.start_reload(), "[%s] tactical reload starts" % sid)
		check(h.is_playing(), "[%s] reload animation plays" % sid)
		var want := wd.reload_time(false, missing if wd.per_round_reload else -1)
		check(absf(h.duration() - maxf(want, 0.05)) < 0.001, "[%s] animation length %.2fs equals reload_time %.2fs" % [sid, h.duration(), want])
		var done := {"n": 0}
		h.reload_finished.connect(func() -> void: done["n"] += 1)
		var mid_ok := true
		for _k in range(3):
			h.advance(h.duration() * 0.2)
			mid_ok = mid_ok and _arm_ok(h) and _finite(w._gun.position) and _finite(w._gun.rotation)
		check(mid_ok and h.is_playing(), "[%s] mid-reload poses are finite (progress %.2f)" % [sid, h.progress()])
		var took := _run_to_end(h, 0.04, h.duration() + 1.0)
		check(took > 0.0 and not h.is_playing(), "[%s] animation finishes (%.2fs simulated)" % [sid, took])
		check(done["n"] == 1, "[%s] reload_finished emitted exactly once" % sid)
		check(w._gun.position.is_zero_approx() and w._gun.rotation.is_zero_approx(), "[%s] gun back at rest after the animation" % sid)
		check(w.state == WeaponController.State.RELOADING, "[%s] animation never changed controller state (still RELOADING)" % sid)
		w.cancel_reload()
		check(not h.is_playing() and w.state == WeaponController.State.READY, "[%s] cancel_reload stops it and frees the controller" % sid)

		# ---- empty reload (nothing chambered: adds the rack / charge)
		s["mag"] = 0
		s["chambered"] = false
		missing = wd.mag_size
		w.state = WeaponController.State.READY
		check(w.start_reload() and h.is_playing(), "[%s] empty reload starts and animates" % sid)
		want = wd.reload_time(true, missing if wd.per_round_reload else -1)
		check(absf(h.duration() - maxf(want, 0.05)) < 0.001, "[%s] empty animation length %.2fs equals reload_time %.2fs" % [sid, h.duration(), want])
		took = _run_to_end(h, 0.033, h.duration() + 1.0)
		check(took > 0.0 and _arm_ok(h) and w._gun.position.is_zero_approx(), "[%s] empty reload animation finishes cleanly (%.2fs)" % [sid, took])
		w.cancel_reload()

		# ---- cancel mid-way snaps back
		w.state = WeaponController.State.READY
		w.start_reload()
		h.advance(h.duration() * 0.45)
		check(h.is_playing(), "[%s] mid-reload still playing at 45%%" % sid)
		w.cancel_reload()
		check(not h.is_playing() and w._gun.position.is_zero_approx() and w._gun.rotation.is_zero_approx(), "[%s] cancel mid-reload snaps the gun to rest" % sid)

	check(styles.has("pistol") and styles.has("shell") and (styles.has("rifle") or styles.has("bolt")), "every reload family is exercised: %s" % str(styles.keys()))

	# ---- weapon switch cancels and the new gun gets fresh hands
	if ids.size() >= 2:
		var a: String = str(w.weapon_ids()[0])
		var b: String = str(w.weapon_ids()[1])
		w.equip(w.weapon_ids().find(a))
		await _frames(40)
		var wa: WeaponData = WeaponDB.get_weapon(a)
		w.slots[w.current_slot]["mag"] = 0
		player.inventory[wa.caliber] = 999
		w.state = WeaponController.State.READY
		var old_h: Node3D = w._hands
		check(w.start_reload() and old_h.is_playing(), "switch test: reload running on '%s'" % a)
		w.equip(w.weapon_ids().find(b))
		check(w._hands != old_h, "switch test: a new hands node replaces the old one")
		check(w._hands != null and not w._hands.is_playing(), "switch test: new weapon starts with no reload animation")
		check(w.state == WeaponController.State.SWITCHING, "switch test: controller is switching (reload dropped)")
		await _frames(3)
		check(not is_instance_valid(old_h), "switch test: old hands freed with the old gun")

	# ---- death cancels
	await _frames(40)
	var wd2 := w.weapon_data()
	w.slots[w.current_slot]["mag"] = 0
	player.inventory[wd2.caliber] = 999
	w.state = WeaponController.State.READY
	var h2: Node3D = w._hands
	check(w.start_reload() and h2.is_playing(), "death test: reload running")
	player._die()
	check(not h2.is_playing() and w.state == WeaponController.State.READY, "death test: reload animation cancelled, controller released")

	# ---- remote peers get no hands
	var remote = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	remote.name = "2"
	remote.position = Vector3(5, 0.2, 0)
	root.add_child(remote)
	await _frames(10)
	remote.weapons.give_weapon("pistol")
	remote.weapons.equip(0)
	await _frames(5)
	check(not remote.is_multiplayer_authority(), "remote player is not locally owned")
	check(remote.weapons._hands == null, "remote player's weapon controller builds no first-person hands")

	print("")
	print("t_viewmodel: %d failures" % fails)
	quit(1 if fails > 0 else 0)
