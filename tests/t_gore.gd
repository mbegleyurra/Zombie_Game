extends SceneTree
## Gun feel + gore: per-weapon recoil, no bloom, zombie knockback, blood scaling and dismemberment.
## Run: godot --headless --path . --script res://tests/t_gore.gd

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


func _has_prop(obj: Object, pname: String) -> bool:
	for p in obj.get_property_list():
		if str(p["name"]) == pname:
			return true
	return false


func _spawn(sp: ZombieSpawner, pos: Vector3) -> Zombie:
	var z: Zombie = sp.spawn_zombie_at(pos, false, Zombie.KIND_WALKER)
	z.rotation.y = 0.0   # faces -Z, so zombie-local == world offset
	return z


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
	var zsp := ZombieSpawner.new()
	root.add_child(zsp)
	zsp.enabled = false
	await _frames(3)

	# ---- no bloom anywhere
	var wc := WeaponController.new()
	check(not _has_prop(WeaponData.new(), "bloom_per_shot"), "WeaponData has no bloom_per_shot")
	check(not _has_prop(wc, "_bloom"), "WeaponController has no _bloom")
	wc.free()
	var src := FileAccess.get_file_as_string("res://scripts/weapons/weapon_controller.gd")
	check(src.find("bloom") == -1, "weapon_controller.gd no longer mentions bloom")

	# ---- recoil: every weapon kicks up, and recoil_scale tunes it
	var all_kick := true
	for id in WeaponDB.ids():
		var wd: WeaponData = WeaponDB.get_weapon(id)
		if wd.kick_for_shot(0).y <= 0.0:
			all_kick = false
	check(all_kick, "every weapon has a positive pitch kick")
	var pistol: WeaponData = WeaponDB.get_weapon("pistol")
	var s0 := pistol.recoil_scale
	pistol.recoil_scale = 1.0
	var k1 := pistol.kick_for_shot(0).y
	pistol.recoil_scale = 2.0
	var k2 := pistol.kick_for_shot(0).y
	pistol.recoil_scale = s0
	check(absf(k2 - 2.0 * k1) < 0.001 and k1 > pistol.recoil_pitch, "recoil_scale doubles the kick; global gain makes it stronger than raw recoil_pitch (%.2f vs %.2f)" % [k1, pistol.recoil_pitch])

	# ---- knockback
	var z := _spawn(zsp, Vector3(20, 0.1, 20))
	await _frames(3)
	z.velocity = Vector3.ZERO
	var hp0 := z.health
	var fx := Vector3(0, 1.0, 0)   # torso, centre line
	z._take_damage(20.0, false, 0, z.global_position + fx, Vector3(0, 0, -1))
	check(z.health < hp0, "hit reduces health (%.0f -> %.0f)" % [hp0, z.health])
	check(z.velocity.z < -5.0, "torso hit knocks the zombie back along the shot (vz=%.2f)" % z.velocity.z)
	var z_h := _spawn(zsp, Vector3(30, 0.1, 20))
	await _frames(3)
	z_h.velocity = Vector3.ZERO
	z_h._take_damage(20.0, true, 0, z_h.global_position + Vector3(0, 1.7, 0), Vector3(0, 0, -1))
	check(z_h.velocity.z < z.velocity.z, "headshot knocks back harder than a body shot (%.2f vs %.2f)" % [z_h.velocity.z, z.velocity.z])

	# ---- blood scales with damage and headshots
	check(Zombie.blood_amount(60.0, false) > Zombie.blood_amount(20.0, false), "more damage = more blood particles")
	check(Zombie.blood_amount(20.0, true) > Zombie.blood_amount(20.0, false), "headshot = more blood")
	check(Zombie.blood_amount(5.0, false) >= 10, "even a light hit bleeds at least 10 particles")
	var decals0 := Zombie._decals.size()
	var ps: CPUParticles3D = z._hit_fx(z.global_position + Vector3(0, 1.0, 0), Vector3(0, 0, -1), 40.0, false)
	check(ps != null and ps.amount == Zombie.blood_amount(40.0, false), "hit spawns a particle burst sized by damage")
	check(Zombie._decals.size() > decals0, "hit leaves blood decals on the floor")

	# ---- dismemberment: arm
	var za := _spawn(zsp, Vector3(40, 0.1, 20))
	await _frames(3)
	var range0 := za.attack_range
	var dmg0 := za.attack_damage
	za._take_damage(35.0, false, 0, za.global_position + Vector3(0.4, 1.0, 0), Vector3(0, 0, -1))
	check((za.severed & Zombie.PART_ARM_R) != 0 and (za.severed & Zombie.PART_ARM_L) == 0, "arm shot severs the right arm only (severed=%d)" % za.severed)
	check(za.attack_range < range0 and za.attack_damage < dmg0, "arm loss reduces reach and damage (%.2f -> %.2f)" % [range0, za.attack_range])
	check(is_instance_valid(za.last_gib), "severed arm spawns a flying gib")
	check(za.health > 0.0 and za.state_id != Zombie.State.DEAD, "arm loss does not kill")

	# ---- dismemberment: legs -> crawl
	var zl := _spawn(zsp, Vector3(50, 0.1, 20))
	await _frames(3)
	var base_speed := zl._speed_mult()
	zl._take_damage(45.0, false, 0, zl.global_position + Vector3(-0.1, 0.3, 0), Vector3(0, 0, -1))
	check((zl.severed & Zombie.PART_LEG_L) != 0 and zl._speed_mult() < base_speed, "one leg gone slows the zombie")
	zl._take_damage(45.0, false, 0, zl.global_position + Vector3(0.1, 0.3, 0), Vector3(0, 0, -1))
	check((zl.severed & Zombie.PART_LEG_R) != 0 and zl._crawling and zl._speed_mult() < base_speed * 0.3, "both legs gone = crawling, very slow")
	check(zl.state_id != Zombie.State.DEAD, "crawler is still alive")

	# ---- dismemberment: head
	var zh := _spawn(zsp, Vector3(60, 0.1, 20))
	await _frames(3)
	zh._take_damage(150.0, true, 0, zh.global_position + Vector3(0, 1.7, 0), Vector3(0, 0, -1))
	check((zh.severed & Zombie.PART_HEAD) != 0 and zh.state_id == Zombie.State.DEAD, "killing headshot decapitates")
	check(is_instance_valid(zh.last_gib), "head gib spawned")

	# ---- sync: `severed` replicates, and a peer that receives it reproduces the effects
	var synced := false
	for n in za.get_children():
		if n is MultiplayerSynchronizer and n.replication_config != null:
			for p in n.replication_config.get_properties():
				if str(p).ends_with(":severed"):
					synced = true
	check(synced, "severed is in the zombie's MultiplayerSynchronizer")
	var peer := _spawn(zsp, Vector3(70, 0.1, 20))
	await _frames(3)
	peer.severed = za.severed   # what the replicated property does on a client
	check(peer.attack_range < range0 and peer._stumps.size() == 1, "peer receiving severed hides the part and applies reach loss")

	# ---- hit without a position still works (old request_damage path)
	var zo := _spawn(zsp, Vector3(80, 0.1, 20))
	await _frames(3)
	zo._take_damage(10.0, false, 0)
	check(zo.health == 90.0 and zo.severed == 0, "legacy damage call (no hit position) still works")

	print("RESULT failures=", fails)
	quit(fails)
