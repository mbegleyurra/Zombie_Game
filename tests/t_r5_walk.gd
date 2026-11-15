extends SceneTree
## Round 5 (RAT): walkability of police_station, warehouse and church.
## A player-sized capsule (r 0.35, h 1.8, same as player.tscn) is flood-filled (BFS, 0.25 m grid, 4-neighbour,
## physics shape queries against world layer 1) from OUTSIDE the entrance (gate/door) and must reach every
## loot container (line of sight within 3 m, like Player._hover_target) and every ground pickup (<= 1.5 m).
## Capsule bottom floats 0.2 m above the location origin, so the 0.06 m floor slab never counts as a wall.
## Run: godot --headless --path . --script res://tests/t_r5_walk.gd

const STEP := 0.25
const LIFT := 0.2
const SPECS := {
	"police_station": {"start": Vector2(0, 21), "min": Vector2(-20, -10), "max": Vector2(20, 24), "interior": Rect2(-8, -5, 16, 10)},
	"warehouse": {"start": Vector2(0, 21), "min": Vector2(-22, -10), "max": Vector2(22, 24), "interior": Rect2(-12, -8, 24, 16)},
	"church": {"start": Vector2(-15, 0), "min": Vector2(-18, -8), "max": Vector2(12, 7), "interior": Rect2(-9, -4.5, 18, 9)},
}

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


func _free(space: PhysicsDirectSpaceState3D, node: Node3D, c: Vector2) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = capsule
	q.collision_mask = 1
	q.transform = Transform3D(Basis(), node.to_global(Vector3(c.x, LIFT + 0.9, c.y)))
	return space.intersect_shape(q, 1).is_empty()


func _key(c: Vector2) -> Vector2i:
	return Vector2i(int(round(c.x / STEP)), int(round(c.y / STEP)))


func _flood(space: PhysicsDirectSpaceState3D, node: Node3D, spec: Dictionary) -> Dictionary:
	var seen := {}
	var start: Vector2 = spec["start"]
	var lo: Vector2 = spec["min"]
	var hi: Vector2 = spec["max"]
	if not _free(space, node, start):
		return seen
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
			if c.x < lo.x or c.x > hi.x or c.y < lo.y or c.y > hi.y:
				continue
			seen[n] = true
			if _free(space, node, c):
				queue.append(n)
	var reach := {}
	for k in queue:
		reach[k] = true
	return reach


## Aim at the middle of the container's own box (a register is 0.35 m tall, a locker 1.9 m).
func _box_mid(ln: Node3D) -> float:
	var kinds: Dictionary = ln.get_script().KINDS if "KINDS" in ln.get_script() else {}
	if kinds.has(ln.kind):
		return float((kinds[ln.kind] as Dictionary)["size"].y) * 0.5
	return 0.4


func _can_use(space: PhysicsDirectSpaceState3D, node: Node3D, reach: Dictionary, ln: Node3D) -> bool:
	var lp: Vector3 = node.to_local(ln.global_position)
	var is_box := ln.is_in_group("loot_container")
	var r := 2.4 if is_box else 1.5
	var ck := _key(Vector2(lp.x, lp.z))
	var span := int(ceil(r / STEP))
	for dx in range(-span, span + 1):
		for dz in range(-span, span + 1):
			var k := Vector2i(ck.x + dx, ck.y + dz)
			if not reach.has(k):
				continue
			var c := Vector2(k.x * STEP, k.y * STEP)
			if c.distance_to(Vector2(lp.x, lp.z)) > r:
				continue
			if not is_box:
				return true
			var from: Vector3 = node.to_global(Vector3(c.x, LIFT + 1.62, c.y))
			var to: Vector3 = ln.global_position + Vector3(0, _box_mid(ln), 0)
			var dir := (to - from).normalized()
			var rq := PhysicsRayQueryParameters3D.create(from, from + dir * 3.0, 0xFFFFFFFF)
			var hit := space.intersect_ray(rq)
			if not hit.is_empty():
				var n: Node = hit["collider"] as Node
				for _i in 4:
					if n == null:
						break
					if n == ln:
						return true
					n = n.get_parent()
	return false


func _walk(w: Node3D, seed_value: int, type: String) -> void:
	var spec: Dictionary = SPECS[type]
	var locs: Array = w.get_locations(type)
	check(locs.size() >= 1, "seed %d: %s exists" % [seed_value, type])
	var space := w.get_world_3d().direct_space_state
	for l in locs:
		var node: Node3D = l["node"]
		var start: Vector2 = spec["start"]
		check(_free(space, node, start), "seed %d: %s entrance start %s is free for the capsule" % [seed_value, type, str(start)])
		var reach := _flood(space, node, spec)
		var inside := 0
		var rect: Rect2 = spec["interior"]
		for k in reach:
			if rect.has_point(Vector2(k.x * STEP, k.y * STEP)):
				inside += 1
		var area := rect.size.x * rect.size.y
		var frac := float(inside) * STEP * STEP / area
		check(inside > 40, "seed %d: %s capsule gets inside (%d interior cells, %.0f%% of the footprint)" % [seed_value, type, inside, frac * 100.0])
		var lp: Vector3 = l["pos"]
		var total := 0
		var bad := PackedStringArray()
		for id in w.loot_by_id:
			var ln = w.loot_by_id[id]
			if not is_instance_valid(ln):
				continue
			var gp: Vector3 = ln.global_position
			if Vector2(gp.x - lp.x, gp.z - lp.z).length() > float(l["radius"]):
				continue
			var local: Vector3 = node.to_local(gp)
			if not Rect2(spec["min"], (spec["max"] as Vector2) - (spec["min"] as Vector2)).has_point(Vector2(local.x, local.z)):
				continue
			total += 1
			if not _can_use(space, node, reach, ln):
				var what: String = ln.kind if ln.is_in_group("loot_container") else str(ln.item_id)
				bad.append("%s#%d@(%.1f,%.1f)" % [what, int(id), local.x, local.z])
		check(total >= 5, "seed %d: %s has loot to test (%d)" % [seed_value, type, total])
		check(bad.is_empty(), "seed %d: %s every loot reachable by the capsule (%d/%d unreachable: %s)" % [seed_value, type, bad.size(), total, ", ".join(bad)])


func _run() -> void:
	await physics_frame
	for seed_value in [20260101, 31337, 7]:
		var w := _build(seed_value)
		await physics_frame
		await physics_frame
		for t in SPECS:
			_walk(w, seed_value, t)
		w.queue_free()
		await physics_frame
		await physics_frame
	print("RESULT  failures=%d" % fails)
	quit(1 if fails > 0 else 0)
