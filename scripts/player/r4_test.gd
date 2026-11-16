extends SceneTree
## Round 4 headless test: loot pickup equip, weapon spec/ballistics, zombie variants,
## hit reaction, death animation, night scaling through the "daynight" group.
## Run: godot --headless --path . --script res://scripts/player/r4_test.gd

var fails: int = 0


class FakeDayNight:
	extends Node
	var factor: float = 0.0

	func get_night_factor() -> float:
		return factor


func _initialize() -> void:
	_run()


func check(cond: bool, label: String) -> void:
	if cond:
		print("PASS  ", label)
	else:
		fails += 1
		print("FAIL  ", label)


func _frames(n: int) -> void:
	for _i in range(n):
		await physics_frame


func _tris(node: Node) -> int:
	var t := 0
	for n in node.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh != null:
			t += mi.mesh.get_faces().size() / 3
	return t


func _run() -> void:
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
	var w: WeaponController = player.weapons

	# ---- (1) loot pickup: equips, never duplicates, returns cleanly
	check(w.weapon_data().id == "pistol", "start: pistol equipped")
	var slot: int = w.pickup_weapon("ak")
	check(slot >= 0 and w.weapon_data().id == "ak", "pickup_weapon(ak) equips the new gun")
	var n_before := w.slots.size()
	var again: int = w.pickup_weapon("ak")
	check(again == slot and w.slots.size() == n_before, "second pickup of ak returns the same slot, no duplicate")
	w.equip(0)
	w.pickup_weapon("ak")
	check(w.weapon_data().id == "pistol" and w.slots.size() == n_before, "re-pickup of an owned gun does not steal the equip or duplicate")
	check(w.pickup_weapon("rocket_launcher") == -1 and w.slots.size() == n_before, "unknown id returns -1 and changes nothing")
	var gslot: int = player.give_weapon("shotgun")
	check(gslot >= 0 and w.weapon_data().id == "shotgun", "Player.give_weapon equips a newly obtained gun")
	check(player.give_weapon("shotgun") == gslot and w.slots.size() == n_before + 1, "Player.give_weapon twice: still one shotgun")
	player.add_item("m4")
	check(w.weapon_data().id == "m4" and w.has_weapon("m4"), "add_item(gun) equips via the same path")

	# ---- (3) weapon spec sheet, reload times, bullet drop, recoil patterns
	var all: Dictionary = WeaponDB.inspect_all()
	check(all.size() >= 5 and all.has("pistol") and all.has("ak") and all.has("m4") and all.has("shotgun") and all.has("hunting"), "inspect_all covers the 5 original guns (and any crafted rifles)")
	var reloads: Array = []
	var patterns: Array = []
	for id in all.keys():
		var d: Dictionary = all[id]
		var wd: WeaponData = WeaponDB.get_weapon(id)
		check(float(d["reload_empty"]) > 0.0 and float(d["reload_tactical"]) > 0.0 and not bool(d["malfunctions"]), "%s reload %.2f/%.2f s, no malfunctions, ammo %s" % [id, d["reload_tactical"], d["reload_empty"], d["ammo"]])
		check(float(d["drop_200m"]) > float(d["drop_100m"]) and float(d["drop_100m"]) > float(d["drop_50m"]) and float(d["drop_50m"]) > 0.0, "%s drop grows with range (50/100/200 m = %.2f/%.2f/%.2f)" % [id, d["drop_50m"], d["drop_100m"], d["drop_200m"]])
		check(absf(wd.sight_offset_at(wd.zero_range)) < 0.001, "%s sights are zeroed at %d m" % [id, int(wd.zero_range)])
		reloads.append(snappedf(float(d["reload_empty"]), 0.01))
		patterns.append(str(wd.recoil_pattern))
	var uniq_p: Dictionary = {}
	for p in patterns:
		uniq_p[p] = true
	check(uniq_p.size() >= 5, "the original five guns have distinct recoil patterns (rifle tiers may share one)")
	var uniq_r: Dictionary = {}
	for r in reloads:
		uniq_r[r] = true
	check(uniq_r.size() >= 4, "reload times differ per gun: %s" % str(reloads))
	var sg: WeaponData = WeaponDB.get_weapon("shotgun")
	check(is_equal_approx(sg.reload_time(true, 6), 6.0 * sg.round_time + sg.chamber_time), "shotgun empty reload = 6 shells + rack")
	w.equip(w._find_slot("ak"))
	await _frames(40)
	var insp: Dictionary = w.inspect_current()
	check(insp.get("id", "") == "ak" and float(insp["reload_now"]) == WeaponDB.get_weapon("ak").reload_tactical, "inspect_current(ak): live reload time is the tactical one when a round is chambered")

	# zeroed AK, 100 m shot, no spread: lands on target (drop compensated)
	var ak: WeaponData = WeaponDB.get_weapon("ak")
	ak.spread_deg = 0.0
	ak.move_spread_deg = 0.0
	ak.ads_spread_mult = 0.0
	player.look_pitch = 0.0
	var zt = (load("res://scenes/zombies/zombie.tscn") as PackedScene).instantiate()
	zt.position = Vector3(0, 0.05, -100)
	root.add_child(zt)
	zt.set_physics_process(false)
	await _frames(5)
	w._cooldown = 0.0
	w._try_fire(ak)
	await _frames(2)
	check(zt.health < 100.0, "zeroed AK hits a zombie at 100 m (hp %.1f)" % zt.health)
	zt.queue_free()

	# gun viewmodels: more detail than before
	for id in WeaponDB.ids():
		var g := GunMesh.build(WeaponDB.get_weapon(id).model)
		var t := _tris(g)
		print("INFO  viewmodel %s: %d triangles, %d meshes" % [id, t, g.find_children("*", "MeshInstance3D", true, false).size()])
		check(t >= 300 and GunMesh.muzzle_of(g) != null, "viewmodel %s detailed (%d tris) and has a muzzle" % [id, t])
		g.free()

	# ---- (2) zombie variants
	var sp = ZombieSpawner.new()
	root.add_child(sp)
	await _frames(3)
	player.respawn(Vector3(0, 0.2, 0))
	var kinds: Array = []
	var tri_by_kind: Dictionary = {}
	for k in [0, 1, 2]:
		var z = sp.spawn_zombie_at(Vector3(40 + k * 4, 0.1, 40), false, k)
		z.set_physics_process(false)
		await _frames(3)
		kinds.append(z)
		tri_by_kind[k] = _tris(z)
		print("INFO  kind %d: hp %.0f runner=%s triangles=%d" % [k, z.max_health, str(z.runner), tri_by_kind[k]])
	check(kinds[0].max_health == 100.0 and kinds[1].max_health < 100.0 and kinds[2].max_health > 200.0, "walker 100 / runner < 100 / bloater > 200 hp")
	check(kinds[1].runner and not kinds[0].runner and not kinds[2].runner, "runner flag only on the runner")
	check(kinds[2].chase_speed < kinds[0].chase_speed and kinds[1].runner_speed > kinds[0].chase_speed, "bloater slower, runner faster than walker")
	check(tri_by_kind[0] > 600 and tri_by_kind[1] > 1560 and tri_by_kind[2] > 1560, "runner/bloater above the old 1560-triangle zombie; Kenney walker (low-poly model) above 600")
	check(tri_by_kind[0] != tri_by_kind[1] and tri_by_kind[1] != tri_by_kind[2] and tri_by_kind[0] != tri_by_kind[2], "variant meshes differ")
	var legacy = sp.spawn_zombie_at(Vector3(60, 0.1, 40), true)
	check(legacy.kind == Zombie.KIND_RUNNER and legacy.runner, "legacy spawn_zombie_at(pos, true) is a runner")
	var plain = sp.spawn_zombie_at(Vector3(64, 0.1, 40))
	check(plain.kind == Zombie.KIND_WALKER and plain.max_health == 100.0, "legacy spawn_zombie_at(pos) is a 100 hp walker")
	check(not sp.pick_kind() < 0, "pick_kind returns a valid kind")
	sp.set_night_factor(1.0)
	var counts := [0, 0, 0]
	for _i in range(600):
		counts[sp.pick_kind()] += 1
	sp.set_night_factor(0.0)
	var dcounts := [0, 0, 0]
	for _i in range(600):
		dcounts[sp.pick_kind()] += 1
	check(counts[1] > dcounts[1] and counts[2] > dcounts[2], "night mix has more runners and bloaters (night %s vs day %s)" % [str(counts), str(dcounts)])

	# hit reaction (no death) and death animation
	var bz = kinds[2]
	bz.request_damage(20.0, false, 1)
	await _frames(3)
	check(bz.health < bz.max_health and bz._flinch > 0.0 and bz.state_id != Zombie.State.DEAD, "damage plays a flinch without killing (flinch %.2f)" % bz._flinch)
	var wz = kinds[0]
	wz.request_damage(500.0, true, 1)
	var rx0: float = wz._body.rotation.x
	await _frames(15)
	var mid: float = absf(wz._body.rotation.x)
	await _frames(90)
	var end: float = absf(wz._body.rotation.x)
	check(wz.state_id == Zombie.State.DEAD and mid < end and end > 1.3, "death animation topples the body over time (%.2f -> %.2f -> %.2f rad)" % [rx0, mid, end])

	# ---- night scaling through the daynight group
	var dn := FakeDayNight.new()
	dn.add_to_group("daynight")
	root.add_child(dn)
	sp.set_night_factor(0.0)
	sp._night_poll = 0.0
	dn.factor = 0.8
	await _frames(70)
	check(absf(sp.night_factor - 0.8) < 0.01, "spawner follows the daynight group (night_factor=%.2f)" % sp.night_factor)
	dn.factor = 0.0
	await _frames(70)
	check(sp.night_factor < 0.01, "spawner returns to day when the group says so (night_factor=%.2f)" % sp.night_factor)

	print("RESULT  failures=", fails)
	quit(1 if fails > 0 else 0)
