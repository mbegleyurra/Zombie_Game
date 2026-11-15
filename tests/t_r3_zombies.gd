extends SceneTree
## Round 3: zombies in the REAL game flow (Play Solo = Net.host_solo + scenes/main.tscn).
## Checks: one player, one spawner, zombies spawn by day, DayNight drives the spawner at night,
## a zombie chases across real terrain and damages the player.
## Run: godot --headless --path . --script res://tests/t_r3_zombies.gd
## State ids: IDLE 0, WANDER 1, INVESTIGATE 2, CHASE 3, ATTACK 4, DEAD 5.

var fails := 0


func check(cond: bool, label: String) -> void:
	if cond:
		print("PASS  ", label)
	else:
		fails += 1
		print("FAIL  ", label)


func info(s: String) -> void:
	print("INFO  ", s)


func _initialize() -> void:
	_run.call_deferred()


func _until(cond: Callable, timeout: float) -> bool:
	var t := 0.0
	while t < timeout:
		if cond.call():
			return true
		await create_timer(0.2).timeout
		t += 0.2
	return cond.call()


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _run() -> void:
	await physics_frame
	var net: Node = root.get_node_or_null("Net")
	check(net.host_solo(31337) == OK, "Net.host_solo (Play Solo path) ok")
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	for _i in 40:
		await physics_frame
	var p = net.players.get(1)
	check(p != null and get_nodes_in_group("players").size() == 1, "exactly one player in solo (%d)" % get_nodes_in_group("players").size())
	var sp = get_first_node_in_group("spawner")
	check(sp != null and get_nodes_in_group("spawner").size() == 1, "exactly one spawner in main.tscn")
	if p == null or sp == null:
		print("RESULT  failures=%d" % fails)
		quit(1)
		return
	var dn = main.world.day_night
	var in_group: bool = dn.is_in_group("daynight") or dn.is_in_group("day_night")
	check(in_group, "DayNight node is in group 'daynight'/'day_night' (the groups spawner.gd polls)")
	dn.paused = true
	dn.set_time(12.0)
	var day_ok: bool = await _until(func() -> bool: return sp.alive_count() >= 1, 20.0)
	check(day_ok, "daytime: zombies spawn in real main.tscn (alive=%d)" % sp.alive_count())
	await create_timer(6.0).timeout
	var day_alive: int = sp.alive_count()
	info("day population after ~6 s more: %d, night_factor=%.2f" % [day_alive, sp.night_factor])

	# night
	dn.set_time(0.0)
	check(dn.is_night(), "DayNight.is_night() true at 00:00")
	await create_timer(6.0).timeout
	info("spawner.night_factor after 6 s at 00:00 = %.2f" % sp.night_factor)
	check(sp.night_factor > 0.6, "spawner night_factor follows DayNight at midnight (got %.2f)" % sp.night_factor)
	var night_ok: bool = await _until(func() -> bool: return sp.alive_count() >= day_alive + 6, 15.0)
	check(night_ok, "night: population exceeds day population by 6+ (day %d -> night %d)" % [day_alive, sp.alive_count()])

	# deterministic chase + damage on real terrain
	sp.enabled = false
	sp.kill_all()
	await create_timer(0.6).timeout
	var pos: Vector3 = p.global_position + Vector3(12, 0, 0)
	pos.y = main.world.get_height(pos.x, pos.z) + 0.4
	var z = sp.spawn_zombie_at(pos, false)
	check(z != null, "spawn_zombie_at works on real terrain")
	if z != null:
		await create_timer(0.6).timeout
		z.alert_to(p)
		var d0: float = _flat(z.global_position, p.global_position)
		await create_timer(4.0).timeout
		var d1: float = _flat(z.global_position, p.global_position) if is_instance_valid(z) else 0.0
		check(d1 < d0 - 3.0, "alerted zombie chases across terrain (%.1f m -> %.1f m in 4 s, state %d)" % [d0, d1, z.state_id])
		var hit: bool = await _until(func() -> bool: return p.health < 100.0, 12.0)
		check(hit, "zombie reaches and damages the player (hp %.0f)" % p.health)
	print("RESULT  failures=%d" % fails)
	net.leave()
	quit(1 if fails > 0 else 0)
