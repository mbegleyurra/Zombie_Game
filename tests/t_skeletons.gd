extends SceneTree
## KayKit skeleton enemies: spawn, rig/animation/accessories, damage, headshot, death, bullet
## ray hit, mage bolt, dungeon-marker group API and the open-world spawner.
## Run: godot --headless --path . --script res://tests/t_skeletons.gd

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
	var sp = zsp.skeletons
	check(sp != null and sp is SkeletonSpawner and sp.get_parent() == zsp, "ZombieSpawner creates a SkeletonSpawner child")

	# ---- four types spawn with the right identity, size and gear
	var types := ["warrior", "minion", "rogue", "mage"]
	var made := {}
	for i in range(types.size()):
		var s: SkeletonEnemy = sp.spawn_skeleton_at(Vector3(30 + 4 * i, 0.1, 30), types[i])
		check(s != null and SkeletonEnemy.type_of_kind(s.kind) == types[i], "spawn %s returns a skeleton of that type (kind %d)" % [types[i], s.kind if s != null else -1])
		made[types[i]] = s
	await _frames(10)
	for t in types:
		var s: SkeletonEnemy = made[t]
		check(s.is_in_group("zombies") and s.is_in_group("skeletons") and s is Zombie, "%s is in groups zombies+skeletons and is a Zombie" % t)
		check(s._sk != null and s._ap != null and s._ap.has_animation("Walking_A") and s._ap.has_animation("Idle_A") and s._ap.has_animation("Death_A") and s._ap.has_animation("Hit_A"), "%s has the KayKit rig and Rig_Medium idle/walk/hit/death clips" % t)
		check(s.collision_layer == 4, "%s is on the bullet layer" % t)
		var top := _top_y(s)
		check(top > 1.4 and top < 2.0, "%s stands human height (%.2f m)" % [t, top])
	check(made["warrior"]._accessories.has("right") and made["warrior"]._accessories.has("left"), "warrior holds sword + shield (hand-bone attachments)")
	check(made["mage"]._accessories.has("right") and made["minion"]._accessories.has("right") and made["rogue"]._accessories.has("right"), "mage staff, minion axe, rogue blade attached")
	var ba := made["warrior"]._accessories["right"] as Node3D
	check(ba.get_parent() is BoneAttachment3D and (ba.get_parent() as BoneAttachment3D).bone_name == "handslot.r", "weapon sits on a BoneAttachment3D at handslot.r")
	check(made["minion"].max_health < made["rogue"].max_health and made["rogue"].max_health < made["warrior"].max_health, "hp ordering minion < rogue < warrior (%.0f/%.0f/%.0f)" % [made["minion"].max_health, made["rogue"].max_health, made["warrior"].max_health])
	check(made["minion"].chase_speed > made["warrior"].chase_speed and made["rogue"].chase_speed > made["minion"].chase_speed, "minion and rogue are faster than the warrior")
	check(made["mage"].attack_range > 8.0 and made["warrior"].attack_range < 3.0, "mage is ranged, warrior melee")
	var w: SkeletonEnemy = made["warrior"]
	check(not w._flash_mats.is_empty() and w._flash_mats[0][0] != made["minion"]._flash_mats[0][0], "each skeleton has private material copies (hit flash stays local)")

	# ---- animation actually changes the pose
	var hips := w._sk.find_bone("hips")
	w._cur_clip = ""
	var p0: Vector3 = w._sk.get_bone_pose_position(hips)
	var q0: Quaternion = w._sk.get_bone_pose_rotation(w._sk.find_bone("upperleg.l"))
	await create_timer(0.5).timeout
	var q1: Quaternion = w._sk.get_bone_pose_rotation(w._sk.find_bone("upperleg.l"))
	check(w._cur_clip == "Idle_A" or w._cur_clip == "Idle_B", "standing skeleton plays an idle clip (%s)" % w._cur_clip)
	check(not q0.is_equal_approx(q1) or not p0.is_equal_approx(w._sk.get_bone_pose_position(hips)), "idle clip animates the rig")

	# ---- hit detection: a ray on the bullet layer hits the skeleton; head vs body
	var space := root.get_world_3d().direct_space_state
	var tgt: SkeletonEnemy = made["rogue"]
	tgt.set_physics_process(false)
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(tgt.global_position + Vector3(0, 1.0, 6), tgt.global_position + Vector3(0, 1.0, 0), 4))
	check(not hit.is_empty() and hit["collider"] == tgt and (hit["collider"] as Object).has_method("request_damage"), "bullet ray (layer 4) hits the skeleton body")
	var head_y: float = tgt._head_line + 0.2
	var head_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(tgt.global_position + Vector3(0, head_y, 6), tgt.global_position + Vector3(0, head_y, 0), 4))
	check(not head_hit.is_empty() and head_hit["collider"] == tgt, "bullet ray at head height hits the skeleton (y=%.2f)" % head_y)
	check(tgt.is_head_hit(tgt.global_position + Vector3(0, head_y, 0)) and not tgt.is_head_hit(tgt.global_position + Vector3(0, 0.8, 0)), "is_head_hit: head true, chest false (line %.2f m)" % tgt._head_line)
	check(w.is_head_hit(w.global_position + Vector3(0, 1.6, 0)) and not w.is_head_hit(w.global_position + Vector3(0, 0.5, 0)), "warrior head test: 1.6 m head, 0.5 m legs")

	# ---- damage, flinch, headshot, death
	var h0: float = w.health
	w.set_physics_process(false)
	w.request_damage(20.0, false, 1)
	check(is_equal_approx(w.health, h0 - 20.0) and w.state_id != Zombie.State.DEAD, "damage lowers health (%.0f -> %.0f)" % [h0, w.health])
	await _frames(2)
	check(w._hit_anim > 0.0 and w._hit_flash >= 0.0, "hit plays the flinch/hit clip")
	check(w._cur_clip.begins_with("Hit_"), "hit clip selected (%s)" % w._cur_clip)
	var hs: SkeletonEnemy = made["minion"]
	hs.set_physics_process(false)
	hs.request_damage(10.0, true, 1)
	check(hs._stagger >= 0.35, "headshot staggers harder (%.2f)" % hs._stagger)
	var died := [0]
	hs.died.connect(func(_z) -> void: died[0] += 1)
	hs.request_damage(10000.0, true, 1)
	hs.request_damage(10000.0, true, 1)
	await _frames(2)
	check(hs.state_id == Zombie.State.DEAD and hs.health == 0.0 and died[0] == 1, "lethal headshot -> DEAD, died emitted once")
	check(hs.collision_layer == 0, "corpse no longer blocks bullets")
	await create_timer(3.0).timeout   # Death_B is 2.6 s long
	check(hs._cur_clip.begins_with("Death_"), "death clip plays (%s)" % hs._cur_clip)
	var rest_y: float = hs._sk.get_bone_global_pose(hs._sk.find_bone("head")).origin.y
	check(rest_y < 1.0, "head drops during the death clip (head bone y %.2f vs 1.24 standing)" % rest_y)

	# ---- AI: melee skeleton chases and wounds the player
	for k in made:
		if is_instance_valid(made[k]) and made[k].state_id != Zombie.State.DEAD and made[k] != made["mage"]:
			made[k].queue_free()
	await _frames(2)
	var melee: SkeletonEnemy = sp.spawn_skeleton_at(Vector3(0, 0.1, -8), "minion")
	await _frames(5)
	var hp_before: float = player.health
	melee.alert_to(player)
	check(melee.state_id == Zombie.State.CHASE, "alert -> CHASE")
	var saw_attack := false
	var saw_wind := false
	for _i in range(60 * 8):
		await physics_frame
		saw_attack = saw_attack or melee.state_id == Zombie.State.ATTACK
		saw_wind = saw_wind or melee.winding
		if player.health < hp_before:
			break
	check(saw_attack and saw_wind, "melee skeleton reaches ATTACK with a wind-up")
	check(player.health < hp_before, "melee skeleton damaged the player (%.0f -> %.0f)" % [hp_before, player.health])
	melee.request_damage(10000.0, true, 1)

	# ---- mage fires a slow bolt that damages the player
	var mage: SkeletonEnemy = made["mage"]
	mage.global_position = Vector3(0, 0.1, -10)
	mage.set_physics_process(true)
	mage.health = mage.max_health
	player.respawn(Vector3(0, 0.2, 0))
	await _frames(5)
	hp_before = player.health
	mage.alert_to(player)
	var bolt_seen := false
	var bolt_speed := 0.0
	for _i in range(60 * 10):
		await physics_frame
		if mage.last_bolt != null and is_instance_valid(mage.last_bolt):
			bolt_seen = true
			bolt_speed = mage.last_bolt.velocity.length()
		if player.health < hp_before:
			break
	check(mage.bolts_fired >= 1 and bolt_seen, "mage fires a bolt (%d fired)" % mage.bolts_fired)
	check(bolt_speed > 0.0 and bolt_speed < 20.0, "bolt is slow enough to dodge (%.1f m/s)" % bolt_speed)
	check(player.health < hp_before, "bolt damaged the player (%.0f -> %.0f)" % [hp_before, player.health])
	mage.request_damage(10000.0, false, 1)
	check(mage.state_id == Zombie.State.DEAD, "mage dies from lethal damage")

	# ---- dungeon marker API (group 'dungeon_skeleton_spawn', meta 'type')
	sp.kill_all()
	await _frames(3)
	player.respawn(Vector3(0, 0.2, 0))
	var near_marker := Marker3D.new()
	near_marker.add_to_group("dungeon_skeleton_spawn")
	near_marker.set_meta("type", "mage")
	near_marker.position = Vector3(25, 0.0, 0)
	root.add_child(near_marker)
	var far_marker := Marker3D.new()
	far_marker.add_to_group("dungeon_skeleton_spawn")
	far_marker.set_meta("type", "rogue")
	far_marker.position = Vector3(150, 0.0, 0)
	root.add_child(far_marker)
	var odd_marker := Marker3D.new()
	odd_marker.add_to_group("dungeon_skeleton_spawn")
	odd_marker.set_meta("type", "minion")
	odd_marker.position = Vector3(-30, 0.0, 10)
	root.add_child(odd_marker)
	sp.enabled = true
	var n_spawn: int = sp.poll_markers()
	check(n_spawn == 2, "poll_markers spawns for markers within 40 m only (%d)" % n_spawn)
	var ms = near_marker.get_meta("skeleton", null)
	check(ms is SkeletonEnemy and ms.kind == SkeletonEnemy.KIND_MAGE, "marker type=mage spawned a mage")
	check(ms != null and ms.global_position.distance_to(near_marker.global_position) < 0.5 and ms.guard, "skeleton spawned at the marker position as a guard")
	var mo = odd_marker.get_meta("skeleton", null)
	check(mo is SkeletonEnemy and mo.kind == SkeletonEnemy.KIND_MINION, "marker type=minion spawned a minion")
	check(not far_marker.has_meta("skeleton_spawned"), "marker 150 m away does not spawn yet")
	check(sp.poll_markers() == 0, "a marker spawns only once")
	player.respawn(Vector3(130, 0.2, 0))
	await _frames(3)
	check(sp.poll_markers() == 1 and far_marker.get_meta("skeleton") is SkeletonEnemy and far_marker.get_meta("skeleton").kind == SkeletonEnemy.KIND_ROGUE, "approaching the far marker spawns its rogue")
	sp._prune_far()
	await _frames(2)
	check(is_instance_valid(ms) and not ms.is_queued_for_deletion(), "guards are not pruned by distance")

	# ---- open-world spawner: bounded, mixed into the zombie world
	sp.kill_all()
	await _frames(3)
	zsp.enabled = true
	zsp.set_night_factor(1.0)
	player.respawn(Vector3(0, 0.2, 0))
	sp._timer = 0.0
	var seen := {}
	var peak := 0
	for _i in range(60 * 25):
		await physics_frame
		sp._timer = minf(sp._timer, 0.05) if _i % 30 == 0 else sp._timer
		peak = maxi(peak, sp.alive_count(false))
		for c in sp.container.get_children():
			seen[SkeletonEnemy.type_of_kind((c as SkeletonEnemy).kind)] = true
	check(peak >= 1, "open-world spawner produces skeletons at night (peak %d, types %s)" % [peak, str(seen.keys())])
	check(peak <= sp.hard_cap and peak <= sp.night_cap_per_player, "open-world skeletons stay in small numbers (peak %d <= %d)" % [peak, sp.night_cap_per_player])

	print("RESULT  failures=%d" % fails)
	quit(1 if fails > 0 else 0)


## Highest world y of any visible mesh under the skeleton enemy (its rendered height).
func _top_y(s: SkeletonEnemy) -> float:
	var top := -INF
	for n in s._model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var bb := mi.global_transform * mi.get_aabb()
		top = maxf(top, bb.end.y - s.global_position.y)
	return minf(top, 99.0)
