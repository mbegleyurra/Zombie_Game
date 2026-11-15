extends SceneTree
## Round 4: zombie variants (walker / runner / bloater) in the real game flow, plus a regression
## on night scaling (N1). Run: godot --headless --path . --script res://tests/t_r4_zombies.gd

var fails := 0


func check(cond: bool, label: String) -> void:
	if cond:
		print("PASS  ", label)
	else:
		fails += 1
		print("FAIL  ", label)


func info(msg: String) -> void:
	print("INFO  ", msg)


func _initialize() -> void:
	_run.call_deferred()


func _ground(main: Node, v: Vector3) -> Vector3:
	return Vector3(v.x, main.world.get_height(v.x, v.z) + 0.6, v.z)


func _run() -> void:
	await physics_frame
	var net: Node = root.get_node_or_null("Net")
	check(net.host_solo(31337) == OK, "Net.host_solo ok")
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	for _i in 40:
		await physics_frame
	var p = net.players.get(1)
	var sp = get_first_node_in_group("spawner")
	check(p != null and sp != null, "player and spawner exist")
	if p == null or sp == null:
		print("RESULT  failures=%d" % fails)
		quit(1)
		return
	sp.enabled = false
	sp.kill_all()
	await physics_frame
	var base: Vector3 = p.global_position
	# ---- three kinds spawn with the right identity
	var zs := {}
	for k in [Zombie.KIND_WALKER, Zombie.KIND_RUNNER, Zombie.KIND_BLOATER]:
		var z = sp.spawn_zombie_at(_ground(main, base + Vector3(30 + 4 * k, 0, 30)), false, k)
		check(z != null and z.kind == k, "spawn_zombie_at(kind=%d) returns a zombie of that kind" % k)
		zs[k] = z
	for _i in 10:
		await physics_frame
	var w = zs[Zombie.KIND_WALKER]
	var r = zs[Zombie.KIND_RUNNER]
	var b = zs[Zombie.KIND_BLOATER]
	check(r.runner and not w.runner and not b.runner, "only the runner has runner=true")
	check(w.is_in_group("zombies") and r.is_in_group("zombies") and b.is_in_group("zombies"), "all kinds are in group zombies")
	check(is_equal_approx(b.max_health, b.max_health) and b.health > 0.0, "bloater starts alive (hp %.0f, walker %.0f, runner %.0f)" % [b.health, w.health, r.health])
	info("max_health walker=%.0f runner=%.0f bloater=%.0f" % [w.max_health, r.max_health, b.max_health])
	check(b.health != w.health or b.max_health != w.max_health or b._body.scale != w._body.scale, "bloater differs from a walker (health or build)")
	# ---- appearance differs per variant seed and per kind
	var a1 = sp.spawn_zombie_at(_ground(main, base + Vector3(40, 0, 40)), false, Zombie.KIND_WALKER)
	var a2 = sp.spawn_zombie_at(_ground(main, base + Vector3(44, 0, 40)), false, Zombie.KIND_WALKER)
	for _i in 5:
		await physics_frame
	a1.variant_seed = 1111
	a2.variant_seed = 2222
	var c1: Color = a1._mat_shirt.albedo_color
	var c2: Color = a2._mat_shirt.albedo_color
	check(c1 != c2, "different variant_seed -> different shirt colour (%s vs %s)" % [c1, c2])
	a2.variant_seed = 1111
	check(a2._mat_shirt.albedo_color == a1._mat_shirt.albedo_color, "same variant_seed -> same look (deterministic)")
	check(b._mat_skin.albedo_color != w._mat_skin.albedo_color or b._body.scale != w._body.scale, "bloater looks different from a walker")
	# ---- speeds: runner outruns walker when both chase
	check(r.runner_speed > r.chase_speed, "runner_speed %.1f > chase_speed %.1f" % [r.runner_speed, r.chase_speed])
	# ---- all kinds still take damage, die once, and emit died once
	for k in zs:
		var z = zs[k]
		var died := [0]
		z.died.connect(func(_zz) -> void: died[0] += 1)
		z.request_damage(10000.0, false, 1)
		z.request_damage(10000.0, false, 1)
		await physics_frame
		check(z.state_id == Zombie.State.DEAD and died[0] == 1, "kind %d: lethal damage -> DEAD, died emitted once" % k)
	# ---- alert -> chase works for every kind
	var chasers := {}
	for k in [Zombie.KIND_WALKER, Zombie.KIND_RUNNER, Zombie.KIND_BLOATER]:
		var z = sp.spawn_zombie_at(_ground(main, base + Vector3(-25, 0, -25 - 3 * k)), false, k)
		chasers[k] = z
	for _i in 10:
		await physics_frame
	var starts := {}
	for k in chasers:
		chasers[k].alert_to(p)
		starts[k] = chasers[k].global_position.distance_to(p.global_position)
		check(chasers[k].state_id == Zombie.State.CHASE, "kind %d: alert -> CHASE" % k)
	await create_timer(3.0).timeout
	var closed := {}
	for k in chasers:
		if is_instance_valid(chasers[k]):
			closed[k] = starts[k] - chasers[k].global_position.distance_to(p.global_position)
	info("distance closed in 3 s: %s" % str(closed))
	for k in chasers:
		check(closed.has(k) and closed[k] > 1.0, "kind %d closes distance while chasing (%.1f m)" % [k, closed.get(k, 0.0)])
	check(closed.get(Zombie.KIND_RUNNER, 0.0) > closed.get(Zombie.KIND_WALKER, 99.0), "runner closes more distance than walker (%.1f vs %.1f)" % [closed.get(Zombie.KIND_RUNNER, 0.0), closed.get(Zombie.KIND_WALKER, 0.0)])
	# ---- mix by night vs day
	sp.set_night_factor(0.0)
	var day := {0: 0, 1: 0, 2: 0}
	for _i in 2000:
		day[sp.pick_kind()] += 1
	sp.set_night_factor(1.0)
	var night := {0: 0, 1: 0, 2: 0}
	for _i in 2000:
		night[sp.pick_kind()] += 1
	info("pick_kind x2000 day=%s night=%s" % [str(day), str(night)])
	check(day[0] > 1500, "by day mostly walkers (%d/2000)" % day[0])
	check(night[1] + night[2] > day[1] + day[2] + 300, "by night many more runners/bloaters (%d vs %d)" % [night[1] + night[2], day[1] + day[2]])
	check(day[2] > 0 and night[2] > 0, "bloaters occur day and night (%d / %d)" % [day[2], night[2]])
	# ---- N1 regression: DayNight is wired to the spawner
	var dn = main.world.day_night
	check(dn.is_in_group("daynight") or dn.is_in_group("day_night"), "N1: DayNight node is in the group the spawner polls")
	sp.enabled = true
	dn.paused = true
	dn.set_time(0.0)
	await create_timer(4.0).timeout
	check(sp.night_factor > 0.5, "N1: spawner.night_factor follows DayNight at 00:00 (%.2f)" % sp.night_factor)
	dn.set_time(12.0)
	await create_timer(4.0).timeout
	check(sp.night_factor < 0.2, "N1: spawner.night_factor returns to ~0 at noon (%.2f)" % sp.night_factor)
	print("RESULT  failures=%d" % fails)
	quit(1 if fails > 0 else 0)
