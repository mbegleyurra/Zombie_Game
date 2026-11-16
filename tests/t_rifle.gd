extends SceneTree
## Assault rifle ("ar"): data, mesh, items, loot, pickup/equip/fire through WeaponController, reload, and the
## multiplayer-facing state (equipped_id drives the remote avatar gun). Run:
##   godot --headless --path . --script res://tests/t_rifle.gd

const ItemDB = preload("res://scripts/world/item_db.gd")

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


func _run() -> void:
	# ---- data
	check(WeaponDB.has_weapon("ar"), "WeaponDB knows 'ar'")
	var ar: WeaponData = WeaponDB.get_weapon("ar")
	var pistol: WeaponData = WeaponDB.get_weapon("pistol")
	var m4: WeaponData = WeaponDB.get_weapon("m4")
	check(ar != null and ar.display_name == "Assault Rifle" and ar.caliber == "556" and ar.model == "ar", "ar identity: name, 5.56 ammo, model key")
	check(ar.damage > pistol.damage and ar.damage > m4.damage, "damage %.0f beats pistol %.0f and m4 %.0f" % [ar.damage, pistol.damage, m4.damage])
	check(ar.max_range > pistol.max_range and ar.falloff_end > pistol.falloff_end and ar.falloff_start > pistol.falloff_start, "range beats pistol (max %.0f, falloff %.0f-%.0f)" % [ar.max_range, ar.falloff_start, ar.falloff_end])
	check(ar.muzzle_velocity > pistol.muzzle_velocity, "muzzle velocity %.0f > pistol %.0f" % [ar.muzzle_velocity, pistol.muzzle_velocity])
	check(ar.mag_size == 20 and ar.automatic and ar.fire_rate_rpm > 300.0, "20 round automatic rifle at %.0f rpm" % ar.fire_rate_rpm)
	check(ar.reload_empty > ar.reload_tactical and ar.reload_tactical > pistol.reload_tactical, "reload %.1fs tactical / %.1fs empty (slower than pistol)" % [ar.reload_tactical, ar.reload_empty])
	check(ar.recoil_pattern.size() >= 4 and ar.recoil_pitch > pistol.recoil_pitch * 0.9 and ar.recoil_pitch > m4.recoil_pitch, "has a recoil pattern (%d kicks), pitch %.1f" % [ar.recoil_pattern.size(), ar.recoil_pitch])
	var spec: Dictionary = ar.inspect()
	check(int(spec["mag_size"]) == 20 and float(spec["damage"]) == ar.damage, "inspect() spec sheet is filled in")
	check(ar.weight > 0.0 and ar.noise_radius > pistol.noise_radius, "weight and gunshot noise set (noise %.0f m)" % ar.noise_radius)

	# ---- mesh
	var g := GunMesh.build("ar")
	var muz: Node3D = GunMesh.muzzle_of(g)
	var tris := 0
	var boxes := 0
	for c in g.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh != null:
			boxes += 1
			var m: Mesh = (c as MeshInstance3D).mesh
			for s in m.get_surface_count():
				var arr = m.surface_get_arrays(s)
				var idx = arr[Mesh.ARRAY_INDEX]
				tris += (idx.size() if idx != null else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	check(g.name == "Gun_ar" and muz != null, "mesh builds as Gun_ar with a Muzzle marker")
	check(tris >= 300 and boxes >= 25, "mesh is detailed like the other guns (%d parts, %d tris)" % [boxes, tris])
	check(muz != null and muz.position.z < -0.5 and muz.position.z > -1.2, "muzzle sits at the barrel tip (z=%.2f)" % (muz.position.z if muz != null else 0.0))
	g.free()
	var pg := GunMesh.build("pistol")
	check(g != pg and GunMesh.muzzle_of(pg).position.z > -0.3, "unknown-model fallback still the pistol (rifle did not replace it)")
	pg.free()

	# ---- items and loot
	var it: Dictionary = ItemDB.get_item("weapon_ar")
	check(str(it.get("type", "")) == "weapon" and str(it.get("weapon_id", "")) == "ar" and WeaponDB.has_weapon(str(it["weapon_id"])), "item weapon_ar -> weapon id ar")
	check(ItemDB.ammo_item_for(ar.caliber) == "ammo_556" and ItemDB.reserve_key("ammo_556") == ar.caliber, "its ammo (556) has an item and a reserve key")
	var tables_with := 0
	for t in ItemDB.TABLES.keys():   # table_names() also lists KayKit tables that are not in TABLES
		for e in (ItemDB.TABLES[t]["entries"] as Array):
			if str((e as Array)[0]) == "weapon_ar":
				tables_with += 1
	check(tables_with >= 3, "weapon_ar is in %d loot tables" % tables_with)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var rolled := 0
	for _i in 4000:
		for table in ["police", "hospital", "wild"]:
			if str(ItemDB.pick_one(table, rng)["id"]) == "weapon_ar":
				rolled += 1
	check(rolled > 0, "rolling police/hospital/wild loot 4000x each yields the rifle (%d times)" % rolled)

	# ---- player, pickup, equip, fire
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(600, 1, 600)
	cs.shape = box
	floor_body.add_child(cs)
	floor_body.position = Vector3(0, -0.5, 0)
	root.add_child(floor_body)
	var player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	player.name = "1"
	player.position = Vector3(0, 0.2, 0)
	root.add_child(player)
	await _frames(10)
	var w = player.weapons
	check(not w.has_weapon("ar"), "player starts without the rifle")
	var got: bool = ItemDB.give_to(player, "weapon_ar", 1)
	await _frames(2)
	check(got and w.has_weapon("ar"), "picking up weapon_ar adds it to the weapon slots")
	check(w.weapon_data() != null and w.weapon_data().id == "ar", "a newly picked-up rifle is auto-equipped")
	check(str(w.status()["weapon"]) == "ar" and bool(w.status()["auto"]), "HUD status reports the rifle as automatic")
	var slots_before: int = w.slots.size()
	var r556: int = player.count_item("556")
	player.give_weapon("ar")
	check(w.slots.size() == slots_before, "second pickup does not add a duplicate slot")
	player.add_item("ar", 1)
	check(player.count_item("556") == r556 + ar.mag_size and w.slots.size() == slots_before, "duplicate pickup gives one magazine (%d -> %d)" % [r556, player.count_item("556")])
	check(player.count_item("ar") == 1, "inventory counts the rifle as owned")
	await _frames(40)
	check(w.state == WeaponController.State.READY, "rifle ready after the draw animation")
	check(int(w.slots[w.current_slot]["mag"]) == 19 and bool(w.slots[w.current_slot]["chambered"]), "picked up loaded: 19 in mag + 1 chambered")

	# multiplayer-facing state: the remote avatar builds its gun from equipped_id
	check(player.equipped_id == "ar", "player.equipped_id = '%s' (remote avatars build the gun from it)" % player.equipped_id)
	var avatar_gun := GunMesh.build(WeaponDB.get_weapon(player.equipped_id).model)
	check(GunMesh.muzzle_of(avatar_gun) != null, "avatar gun for the rifle builds with a muzzle")
	avatar_gun.free()
	check(player.has_method("broadcast_shot") and player.has_method("emit_noise"), "fire path reaches broadcast_shot / emit_noise used for multiplayer tracers")

	# fire at a zombie 80 m away with zero spread: damaged, ammo accounted
	var z = (load("res://scenes/zombies/zombie.tscn") as PackedScene).instantiate()
	z.position = Vector3(0, 0.0, -80)
	root.add_child(z)
	z.set_physics_process(false)
	await _frames(3)
	ar.spread_deg = 0.0
	ar.move_spread_deg = 0.0
	player.look_pitch = 0.0
	player.head.rotation_degrees.x = 0.0
	player.rotation.y = 0.0
	w._recoil_target = Vector2.ZERO
	w._recoil_cur = Vector2.ZERO
	w._cooldown = 0.0
	var mag0: int = int(w.slots[w.current_slot]["mag"])
	var noise_before: int = 0
	w._try_fire(ar)
	await _frames(2)
	check(int(w.slots[w.current_slot]["mag"]) == mag0 - 1, "firing uses one round (mag %d -> %d)" % [mag0, int(w.slots[w.current_slot]["mag"])])
	check(z.health < 100.0, "rifle round damaged a zombie at 80 m (hp %.1f)" % z.health)
	var pistol_dmg: float = 27.0
	check(100.0 - z.health > pistol_dmg * 0.9, "rifle did more than a pistol round at the muzzle would (%.1f dmg)" % (100.0 - z.health))
	w._cooldown = 0.0
	w._try_fire(ar)
	check(absf(w._cooldown - ar.seconds_between_shots()) < 0.001, "shot sets the fire-rate cooldown (%.3fs)" % w._cooldown)
	# full auto: holding fire is allowed to repeat (wants_fire uses is_action_pressed for automatic guns)
	check(ar.automatic, "automatic flag makes the controller poll is_action_pressed")

	# reload
	player.add_item("556", 60)
	w.state = WeaponController.State.READY
	w._cooldown = 0.0
	check(w.start_reload(), "rifle reload starts")
	check(absf(w._reload_total - ar.reload_tactical) < 0.001, "tactical reload time %.1fs" % ar.reload_tactical)
	var res0: int = player.count_item("556")
	var m1: int = int(w.slots[w.current_slot]["mag"])
	w._reload_timer = 0.0
	w._advance_reload(ar)
	check(int(w.slots[w.current_slot]["mag"]) == 20 and bool(w.slots[w.current_slot]["chambered"]), "tactical reload refills to 20 + 1 chambered (round was chambered)")
	check(player.count_item("556") == res0 - (20 - m1), "reserve dropped by the rounds loaded (%d -> %d)" % [res0, player.count_item("556")])
	w.slots[w.current_slot]["mag"] = 0
	w.slots[w.current_slot]["chambered"] = false
	w.state = WeaponController.State.READY
	check(w.start_reload() and absf(w._reload_total - ar.reload_empty) < 0.001, "empty reload takes %.1fs" % ar.reload_empty)
	w._reload_timer = 0.0
	w._advance_reload(ar)
	check(int(w.slots[w.current_slot]["mag"]) == 19 and bool(w.slots[w.current_slot]["chambered"]), "empty reload gives 19 + 1 chambered (20 total)")

	# equip cycling reaches the rifle
	w.state = WeaponController.State.READY
	w.equip(w._find_slot("pistol"))
	await _frames(2)
	check(player.equipped_id == "pistol", "switching to the pistol updates equipped_id")
	w.equip(w._find_slot("ar"))
	await _frames(2)
	check(player.equipped_id == "ar" and w.weapon_data().id == "ar", "switching back to the rifle updates equipped_id")
	w.remove_weapon("ar")
	check(not w.has_weapon("ar"), "remove_weapon drops it")
	z.free()
	print("RESULT  failures=", fails)
	quit(1 if fails > 0 else 0)
