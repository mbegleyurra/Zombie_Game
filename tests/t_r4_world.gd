extends SceneTree
## Round 4 (RAT): new locations (police_station, warehouse, church) and new props (cars, tractor, power poles).
## Checks per seed: every new type present, node valid with collision, loot inside its radius, location
## nodes not overlapping each other, props have collision, two builds of one seed are identical.
## Run: godot --headless --path . --script res://tests/t_r4_world.gd

var fails := 0
const NEW_TYPES := ["police_station", "warehouse", "church"]


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


func _build(seed_value: int) -> Node3D:
	var w: Node3D = (load("res://scenes/world/world.tscn") as PackedScene).instantiate()
	root.add_child(w)
	w.build(seed_value)
	return w


func _hash(w) -> String:
	var sig := PackedStringArray()
	for l in w.get_locations():
		var pp: Vector3 = l["pos"]
		sig.append("%s|%s|%.2f,%.2f,%.2f|%.3f" % [l["type"], l["name"], pp.x, pp.y, pp.z, float(l["rot"])])
	var ids: Array = w.loot_by_id.keys()
	ids.sort()
	for id in ids:
		var n = w.loot_by_id[id]
		if n.is_in_group("loot_container"):
			sig.append("C%d|%s|%s|%s" % [id, n.kind, n.table, str(n.contents)])
		else:
			var gp: Vector3 = n.global_position
			sig.append("I%d|%s|%d|%.2f,%.2f,%.2f" % [id, n.item_id, n.count, gp.x, gp.y, gp.z])
	return "\n".join(sig).md5_text()


func _shapes(n: Node) -> int:
	return n.find_children("*", "CollisionShape3D", true, false).size()


func _meshes(n: Node) -> int:
	return n.find_children("*", "MeshInstance3D", true, false).size()


func _run() -> void:
	await physics_frame
	for seed_value in [20260101, 31337, 7]:
		var w := _build(seed_value)
		await physics_frame
		var types := {}
		for l in w.get_locations():
			types[l["type"]] = int(types.get(l["type"], 0)) + 1
		info("seed %d types %s" % [seed_value, str(types)])
		for t in NEW_TYPES:
			var locs: Array = w.get_locations(t)
			check(locs.size() >= 1, "seed %d: %s present (%d)" % [seed_value, t, locs.size()])
			for l in locs:
				var node = l.get("node")
				check(node != null and is_instance_valid(node), "seed %d: %s node valid" % [seed_value, t])
				if node != null and is_instance_valid(node):
					check(_shapes(node) > 0 and _meshes(node) > 0, "seed %d: %s has meshes (%d) and collision (%d)" % [seed_value, t, _meshes(node), _shapes(node)])
				var inside := 0
				var lp: Vector3 = l["pos"]
				for id in w.loot_by_id:
					var ln = w.loot_by_id[id]
					if is_instance_valid(ln) and Vector2(ln.global_position.x - lp.x, ln.global_position.z - lp.z).length() <= float(l["radius"]):
						inside += 1
				check(inside >= 2, "seed %d: %s holds loot (%d within radius %.0f m)" % [seed_value, t, inside, float(l["radius"])])
		# no two locations overlap
		var locs_all: Array = w.get_locations()
		var overlap := 0
		for i in locs_all.size():
			for j in range(i + 1, locs_all.size()):
				var a: Vector3 = locs_all[i]["pos"]
				var b: Vector3 = locs_all[j]["pos"]
				if Vector2(a.x - b.x, a.z - b.z).length() < float(locs_all[i]["radius"]) * 0.9 + float(locs_all[j]["radius"]) * 0.9:
					overlap += 1
		check(overlap == 0, "seed %d: no overlapping locations (%d pairs)" % [seed_value, overlap])
		# props
		var props: Node = w.get_node_or_null("Props")
		check(props != null and _shapes(props) > 0, "seed %d: world Props node has collision (%d shapes)" % [seed_value, _shapes(props) if props != null else -1])
		# spawn points are not inside a building collider: ray down from above must hit within 2 m of spawn y
		var space := w.get_world_3d().direct_space_state
		var blocked := 0
		for s in 4:
			var sp: Vector3 = w.get_spawn_point(s)
			var q := PhysicsRayQueryParameters3D.create(sp + Vector3(0, 40, 0), sp + Vector3(0, -5, 0))
			var hit: Dictionary = space.intersect_ray(q)
			if not hit.is_empty() and (hit["position"] as Vector3).y > sp.y + 2.0:
				blocked += 1
		check(blocked == 0, "seed %d: no spawn point sits under a roof/prop (%d blocked)" % [seed_value, blocked])
		var h1 := _hash(w)
		w.queue_free()
		await physics_frame
		await physics_frame
		var w2 := _build(seed_value)
		await physics_frame
		check(_hash(w2) == h1, "seed %d: rebuild is identical (%s)" % [seed_value, h1.substr(0, 8)])
		w2.queue_free()
		await physics_frame
		await physics_frame
	print("RESULT  failures=%d" % fails)
	quit(1 if fails > 0 else 0)
