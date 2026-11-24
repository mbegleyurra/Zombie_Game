extends SceneTree
## Survival Kit + Car Kit dressing probe (RAT, 2026-11-15). Tester file, touches nothing in scripts/.
## 1 counts + spawn clearance, 2 per location: capsule flood-fill with the dressing collider ON vs OFF
##   (cells and loot that become unreachable only because of the dressing), 3 road corridor, 4 dressing collider
##   overlaps with non-dressing colliders and with other dressing shapes.
## Run: godot --headless --path . --script res://tests/t_kenney_dress.gd

const STEP := 0.3
const LIFT := 0.2
const SEEDS := [20260101, 31337, 7, 424242]

var fails := 0
var capsule := CapsuleShape3D.new()


func check(cond: bool, label: String) -> void:
	if cond:
		print("PASS  ", label)
	else:
		fails += 1
		print("FAIL  ", label)


func info(msg: String) -> void:
	print("INFO  ", msg)


func _initialize() -> void:
	capsule.radius = 0.35
	capsule.height = 1.8
	_run.call_deferred()


func _build(seed_value: int) -> Node3D:
	var w: Node3D = (load("res://scenes/world/world.tscn") as PackedScene).instantiate()
	root.add_child(w)
	w.build(seed_value)
	return w


func _is_terrain(n: Node) -> bool:
	while n != null:
		if n.name == "Terrain":
			return true
		n = n.get_parent()
	return false


func _free_world(space: PhysicsDirectSpaceState3D, p: Vector3) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = capsule
	q.collision_mask = 1
	q.transform = Transform3D(Basis(), p)
	return space.intersect_shape(q, 1).is_empty()


func _free_local(space: PhysicsDirectSpaceState3D, node: Node3D, c: Vector2) -> bool:
	return _free_world(space, node.to_global(Vector3(c.x, LIFT + 0.9, c.y)))


func _key(c: Vector2) -> Vector2i:
	return Vector2i(int(round(c.x / STEP)), int(round(c.y / STEP)))


func _flood(space: PhysicsDirectSpaceState3D, node: Node3D, start: Vector2, half: float) -> Dictionary:
	var seen := {}
	var queue: Array[Vector2i] = [_key(start)]
	seen[_key(start)] = true
	var head := 0
	while head < queue.size():
		var k: Vector2i = queue[head]
		head += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = k + d
			if seen.has(n):
				continue
			var c := Vector2(n.x * STEP, n.y * STEP)
			if absf(c.x) > half or absf(c.y) > half:
				continue
			seen[n] = true
			if _free_local(space, node, c):
				queue.append(n)
	var reach := {}
	for k in queue:
		reach[k] = true
	return reach


func _near_reach(reach: Dictionary, lp: Vector3, r: float) -> bool:
	var ck := _key(Vector2(lp.x, lp.z))
	var span := int(ceil(r / STEP))
	for dx in range(-span, span + 1):
		for dz in range(-span, span + 1):
			var k := Vector2i(ck.x + dx, ck.y + dz)
			if reach.has(k) and Vector2(k.x * STEP, k.y * STEP).distance_to(Vector2(lp.x, lp.z)) <= r:
				return true
	return false


func _model_name_at(dressing: Node3D, x: float, z: float) -> String:
	for c in dressing.get_children():
		if c is Node3D:
			var p: Vector3 = (c as Node3D).position
			if absf(p.x - x) < 0.01 and absf(p.z - z) < 0.01 and c.get_child_count() > 0:
				return str(c.get_child(0).name)
	return "?"


## Every model owns its collider (StaticBody3D "Body" child); toggles all of them.
func _set_layer(bodies: Array, layer: int) -> void:
	for b in bodies:
		(b as StaticBody3D).collision_layer = layer


func _run() -> void:
	await physics_frame
	for seed_value in SEEDS:
		var w := _build(seed_value)
		await physics_frame
		await physics_frame
		var space := w.get_world_3d().direct_space_state
		var dressing: Node3D = w.get_node_or_null("KenneyDressing")
		check(dressing != null, "seed %d: KenneyDressing node exists" % seed_value)
		if dressing == null:
			w.queue_free()
			continue
		var bodies: Array = dressing.find_children("*", "StaticBody3D", true, false)
		var shapes: Array = dressing.find_children("*", "CollisionShape3D", true, false)
		info("seed %d counts %s" % [seed_value, str(w.dressing_counts)])
		check(int(w.dressing_counts["cars"]) >= 3, "seed %d: cars placed (%d)" % [seed_value, int(w.dressing_counts["cars"])])
		var off_layer := 0
		for b in bodies:
			if (b as StaticBody3D).collision_layer != 1:
				off_layer += 1
		check(bodies.size() > 0 and off_layer == 0, "seed %d: all %d dressing colliders on layer 1 only (%d not)" % [seed_value, bodies.size(), off_layer])

		# 1 spawn clearance: capsule at each spawn slot, plus nearest dressing shape to spawn centre
		var spawn_bad := 0
		for i in 8:
			var sp: Vector3 = w.get_spawn_point(i)
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = capsule
			q.collision_mask = 1
			q.transform = Transform3D(Basis(), sp + Vector3(0, 0.3, 0))
			for h in space.intersect_shape(q, 8):
				if dressing.is_ancestor_of(h["collider"]):
					spawn_bad += 1
		check(spawn_bad == 0, "seed %d: no dressing collider on any of the 8 spawn slots (%d hits)" % [seed_value, spawn_bad])
		var near_spawn := 9999.0
		for cs in shapes:
			var o: Vector3 = (cs as CollisionShape3D).global_position
			near_spawn = minf(near_spawn, Vector2(o.x, o.z).distance_to(w.spawn_center))
		info("seed %d: nearest dressing collider to spawn centre %.1f m" % [seed_value, near_spawn])
		check(near_spawn > 8.0, "seed %d: dressing keeps >8 m from spawn centre (%.1f)" % [seed_value, near_spawn])

		# 2 per location: dressing ON vs OFF flood
		var lost_total := 0
		var loot_lost := PackedStringArray()
		var skipped := 0
		for l in w.locations:
			var node: Node3D = l["node"]
			var r: float = float(l["radius"])
			var half := r + 2.0
			var start := Vector2.ZERO
			var found := false
			for ang in 16:
				var a := TAU * float(ang) / 16.0
				var cand := Vector2(cos(a), sin(a)) * (r + 1.0)
				_set_layer(bodies, 0)
				await physics_frame
				if _free_local(space, node, cand):
					start = cand
					found = true
					break
			_set_layer(bodies, 0)
			await physics_frame
			if not found:
				skipped += 1
				continue
			var base := _flood(space, node, start, half)
			_set_layer(bodies, 1)
			await physics_frame
			var with := {}
			if _free_local(space, node, start):
				with = _flood(space, node, start, half)
			var lost := 0
			for k in base:
				if not with.has(k):
					lost += 1
			lost_total += lost
			var lp3: Vector3 = l["pos"]
			var lost_loot := 0
			var tested := 0
			for id in w.loot_by_id:
				var ln = w.loot_by_id[id]
				if not is_instance_valid(ln):
					continue
				var gp: Vector3 = ln.global_position
				if Vector2(gp.x - lp3.x, gp.z - lp3.z).length() > r:
					continue
				var loc: Vector3 = node.to_local(gp)
				var reach_r := 2.4 if ln.is_in_group("loot_container") else 1.5
				if not _near_reach(base, loc, reach_r):
					continue
				tested += 1
				if not _near_reach(with, loc, reach_r):
					lost_loot += 1
					var what: String = ln.kind if ln.is_in_group("loot_container") else str(ln.item_id)
					loot_lost.append("%s:%s#%d@(%.1f,%.1f)" % [str(l["type"]), what, int(id), loc.x, loc.z])
			info("seed %d %s: cells reachable off %d on %d (lost %d), loot reachable-off %d, lost by dressing %d" % [seed_value, str(l["type"]), base.size(), with.size(), lost, tested, lost_loot])
		check(loot_lost.is_empty(), "seed %d: dressing makes no loot unreachable (%d lost: %s)" % [seed_value, loot_lost.size(), ", ".join(loot_lost)])
		info("seed %d: floor cells lost to dressing across locations: %d (locations with no free entry ring cell, skipped: %d)" % [seed_value, lost_total, skipped])
		_set_layer(bodies, 1)
		await physics_frame

		# 3 road corridor: centreline capsule free along every road
		var t: Node = w.terrain
		var road_blocked := 0
		var road_total := 0
		var road_where := PackedStringArray()
		for i in t.road_a.size():
			var a: Vector2 = t.road_a[i]
			var b: Vector2 = t.road_b[i]
			var len: float = a.distance_to(b)
			var d: int = int(len / 1.0)
			for s in d:
				var p: Vector2 = a.lerp(b, float(s) / float(maxi(d, 1)))
				var y: float = t.height_at(p.x, p.y)
				var cp := Vector3(p.x, y + LIFT + 0.9, p.y)
				var q := PhysicsShapeQueryParameters3D.new()
				q.shape = capsule
				q.collision_mask = 1
				q.transform = Transform3D(Basis(), cp)
				var blocked := false
				var who := ""
				for h in space.intersect_shape(q, 8):
					if dressing.is_ancestor_of(h["collider"]):
						blocked = true
						var hc: Vector3 = (h["collider"] as Node3D).global_position
						who = _model_name_at(dressing, hc.x, hc.z)
				road_total += 1
				if blocked:
					road_blocked += 1
					if road_where.size() < 6:
						var near_loc := "none"
						var near_d := 9999.0
						for l2 in w.locations:
							var dd: float = (l2["pos2"] as Vector2).distance_to(p)
							if dd < near_d:
								near_d = dd
								near_loc = str(l2["type"])
						var other_road := 9999.0
						for j in t.road_a.size():
							if j != i:
								var cpj: Vector2 = Geometry2D.get_closest_point_to_segment(p, t.road_a[j], t.road_b[j])
								other_road = minf(other_road, cpj.distance_to(p))
						road_where.append("(%.0f,%.0f)=%s road#%d nearest-loc %s %.1fm other-road %.1fm" % [p.x, p.y, who, i, near_loc, near_d, other_road])
		check(road_blocked == 0, "seed %d: road centrelines free of dressing (%d/%d samples blocked %s)" % [seed_value, road_blocked, road_total, ", ".join(road_where)])

		# 4 overlaps: each dressing shape vs everything else
		var idx := 0
		var vs_world := PackedStringArray()
		var vs_self := PackedStringArray()
		for cs in shapes:
			var c3 := cs as CollisionShape3D
			var own: Node = c3.get_parent()
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = c3.shape
			q.collision_mask = 1
			var xf: Transform3D = c3.global_transform
			if c3.shape is BoxShape3D:
				var sh := BoxShape3D.new()
				sh.size = (c3.shape as BoxShape3D).size - Vector3(0.1, 0.1, 0.1)
				q.shape = sh
				xf = xf.translated_local(Vector3(0, 0.12, 0))   # ignore terrain skimming the base
			q.transform = xf
			var nm := _model_name_at(dressing, c3.global_position.x, c3.global_position.z)
			var where := "%s@(%.1f,%.1f)" % [nm, c3.global_position.x, c3.global_position.z]
			var hit_world := false
			var hit_self := false
			for h in space.intersect_shape(q, 16):
				var col: Node = h["collider"] as Node
				if dressing.is_ancestor_of(col):
					if col != own:
						hit_self = true
				elif not _is_terrain(col):
					hit_world = true
					where += " vs " + str(col.get_parent().name if col.get_parent() != null else col.name)
			if hit_world:
				vs_world.append(where)
			if hit_self:
				vs_self.append(where)
			idx += 1
		info("seed %d: %d dressing shapes; overlap other (non-terrain) colliders: %d; overlap each other: %d" % [seed_value, idx, vs_world.size(), vs_self.size()])
		for s in vs_world:
			info("   world-overlap " + s)
		for s in vs_self:
			info("   self-overlap " + s)
		check(vs_world.is_empty(), "seed %d: no dressing collider overlaps a building/prop/tree collider (%d)" % [seed_value, vs_world.size()])
		w.queue_free()
		await physics_frame
		await physics_frame
	print("RESULT  failures=%d" % fails)
	quit(1 if fails > 0 else 0)
