extends SceneTree
## Kenney asset test (RAT). Run: godot --headless --path . --script res://tests/t_kenney.gd
## Phases: 1 asset import + ModelUtil.load_fit; 2 world.tscn x3 seeds (dressing, loot models, collider overlap,
## walkability with/without the Kenney colliders); 3 real solo main.tscn (camera, loot, dressing); 4 zombie arms.
## Edits nothing in the game; only reads.

const ModelUtil = preload("res://scripts/world/model_util.gd")
const ZombieScript = preload("res://scripts/zombies/zombie.gd")
const GY := "res://assets/kenney/graveyard/"
const FOOD := "res://assets/kenney/food/"
const LIFT := 0.2

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


# ---------------------------------------------------------------- helpers

func _glbs(dir: String, out: Array) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".glb"):
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		_glbs(dir.path_join(sub), out)


## Every node under n whose instanced-scene path starts with prefix and ends with one of the given file names ("" = any).
func _models(n: Node, prefix: String, out: Array) -> void:
	if n.scene_file_path.begins_with(prefix):
		out.append(n)
	for c in n.get_children():
		_models(c, prefix, out)


func _count_named(n: Node, prefix: String, needle: String) -> int:
	var arr: Array = []
	_models(n, prefix, arr)
	var k := 0
	for m in arr:
		if (m as Node).scene_file_path.contains(needle):
			k += 1
	return k


func _world_bb(n: Node3D) -> AABB:
	var boxes: Array = []
	ModelUtil._collect(n, Transform3D.IDENTITY, boxes)
	var bb: AABB = boxes[0]
	for i in range(1, boxes.size()):
		bb = bb.merge(boxes[i])
	return bb


func _free_at(space: PhysicsDirectSpaceState3D, node: Node3D, c: Vector2) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = capsule
	q.collision_mask = 1
	q.transform = Transform3D(Basis(), node.to_global(Vector3(c.x, LIFT + 0.9, c.y)))
	return space.intersect_shape(q, 1).is_empty()


func _key(c: Vector2, step: float) -> Vector2i:
	return Vector2i(int(round(c.x / step)), int(round(c.y / step)))


func _flood(space: PhysicsDirectSpaceState3D, node: Node3D, start: Vector2, lo: Vector2, hi: Vector2, step: float) -> Dictionary:
	var reach := {}
	if not _free_at(space, node, start):
		return reach
	var seen := {}
	var queue: Array[Vector2i] = [_key(start, step)]
	seen[queue[0]] = true
	var head := 0
	while head < queue.size():
		var k: Vector2i = queue[head]
		head += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nk: Vector2i = k + d
			if seen.has(nk):
				continue
			var c := Vector2(nk.x * step, nk.y * step)
			if c.x < lo.x or c.x > hi.x or c.y < lo.y or c.y > hi.y:
				continue
			seen[nk] = true
			if _free_at(space, node, c):
				queue.append(nk)
	for k in queue:
		reach[k] = true
	return reach


## Free (capsule fits) cells inside the box that the flood did NOT reach = enclosed pockets.
func _pockets(space: PhysicsDirectSpaceState3D, node: Node3D, reach: Dictionary, lo: Vector2, hi: Vector2, step: float) -> int:
	var n := 0
	var x := lo.x
	while x <= hi.x:
		var z := lo.y
		while z <= hi.y:
			var k := _key(Vector2(x, z), step)
			if not reach.has(k) and _free_at(space, node, Vector2(k.x * step, k.y * step)):
				n += 1
			z += step
		x += step
	return n


## Kenney StaticBody3D colliders: direct children of the location node sitting exactly on a Kenney model wrapper.
func _kenney_bodies(loc: Node3D) -> Array:
	var wraps: Array = []
	for c in loc.get_children():
		if c is Node3D and c.get_child_count() > 0 and c.get_child(0).scene_file_path.begins_with(GY):
			wraps.append(c)
	var bodies: Array = []
	for c in loc.get_children():
		if c is StaticBody3D:
			for w in wraps:
				if (w as Node3D).position.distance_to((c as Node3D).position) < 0.001:
					bodies.append(c)
					break
	return bodies


func _build_world(seed_value: int) -> Node3D:
	var w: Node3D = (load("res://scenes/world/world.tscn") as PackedScene).instantiate()
	root.add_child(w)
	w.build(seed_value)
	return w


# ---------------------------------------------------------------- run

func _run() -> void:
	await physics_frame
	_phase1_assets()
	await _phase2_world()
	await _phase4_zombie()
	await _phase3_main()
	print("RESULT  failures=%d" % fails)
	quit(1 if fails > 0 else 0)


func _phase1_assets() -> void:
	info("--- phase 1: import + ModelUtil.load_fit")
	var all: Array = []
	_glbs("res://assets/kenney", all)
	var bad := PackedStringArray()
	var no_mesh := PackedStringArray()
	for p in all:
		var ps := ResourceLoader.load(str(p)) as PackedScene
		if ps == null:
			bad.append(str(p))
			continue
		var inst := ps.instantiate()
		var boxes: Array = []
		if inst is Node3D:
			ModelUtil._collect(inst, Transform3D.IDENTITY, boxes)
		if boxes.is_empty():
			no_mesh.append(str(p))
		inst.free()
	check(all.size() >= 300, "found %d .glb under assets/kenney" % all.size())
	check(bad.is_empty(), "every glb loads as PackedScene (%d bad: %s)" % [bad.size(), ", ".join(bad)])
	info("glb with no mesh AABB: %d %s" % [no_mesh.size(), ", ".join(no_mesh)])
	for sub in ["graveyard", "mini", "food"]:
		var l: Array = []
		_glbs("res://assets/kenney/" + sub, l)
		check(l.size() > 0, "assets/kenney/%s has %d glb" % [sub, l.size()])

	var cases := [
		[GY + "gravestone-bevel.glb", 1.2], [GY + "crypt-small.glb", 3.4], [GY + "stone-wall.glb", 1.2],
		[GY + "lightpost-single.glb", 3.0], [GY + "pumpkin.glb", 0.45], [GY + "hay-bale.glb", 1.1],
		[FOOD + "can.glb", 0.17], [FOOD + "can-small.glb", 0.07], [FOOD + "soda-bottle.glb", 0.3],
	]
	for c in cases:
		var path: String = c[0]
		var th: float = c[1]
		var m: Node3D = ModelUtil.load_fit(path, th)
		var nm := path.get_file()
		check(m != null, "load_fit(%s) returns a node" % nm)
		if m == null:
			continue
		var sz: Vector3 = m.get_meta("size") as Vector3
		var bb := _world_bb(m)
		check(absf(sz.y - th) <= th * 0.02, "%s meta size.y %.3f == target %.2f (+-2%%)" % [nm, sz.y, th])
		check(absf(bb.size.y - th) <= th * 0.02, "%s real mesh height %.3f == target %.2f" % [nm, bb.size.y, th])
		check(absf(bb.position.y) < 0.01 * maxf(th, 0.1), "%s sits on y=0 (min y %.4f)" % [nm, bb.position.y])
		check(absf(bb.get_center().x) < 0.02 and absf(bb.get_center().z) < 0.02, "%s centred on x/z (%.3f, %.3f)" % [nm, bb.get_center().x, bb.get_center().z])
		check(bb.size.x < 8.0 and bb.size.z < 8.0 and bb.size.x > 0.005, "%s footprint plausible (%.2f x %.2f)" % [nm, bb.size.x, bb.size.z])
		info("%s size %s" % [nm, str(bb.size)])
		m.free()
	check(ModelUtil.load_fit("res://assets/kenney/food/__missing__.glb", 1.0) == null, "load_fit on a missing file returns null (no crash)")


func _phase2_world() -> void:
	info("--- phase 2: world.tscn dressing, overlap, walkability")
	for seed_value in [20260101, 31337, 7]:
		var w := _build_world(seed_value)
		await physics_frame
		await physics_frame
		var space := w.get_world_3d().direct_space_state
		# ----- churches
		for l in w.get_locations("church"):
			var node: Node3D = l["node"]
			var gy: Array = []
			_models(node, GY, gy)
			check(gy.size() >= 20, "seed %d: church has %d Kenney graveyard models" % [seed_value, gy.size()])
			check(_count_named(node, GY, "gravestone") >= 4, "seed %d: church has gravestones (%d)" % [seed_value, _count_named(node, GY, "gravestone")])
			var kb := _kenney_bodies(node)
			# overlap with existing (non-Kenney) structure
			var overl := PackedStringArray()
			for b in kb:
				var body: StaticBody3D = b
				var cs: CollisionShape3D = body.get_child(0) as CollisionShape3D
				var q := PhysicsShapeQueryParameters3D.new()
				q.shape = cs.shape
				q.collision_mask = 1
				q.transform = cs.global_transform
				for hit in space.intersect_shape(q, 8):
					var col: Node = hit["collider"] as Node
					if col != null and col != body and not kb.has(col) and col.get_parent() == node:
						overl.append("%s@(%.1f,%.1f) hits %s/%s" % [(body.get_child(0) as CollisionShape3D).shape.get_class(), body.position.x, body.position.z, col.get_parent().name, col.name])
						break
			check(overl.is_empty(), "seed %d: no Kenney collider overlaps the church's own colliders (%d: %s)" % [seed_value, overl.size(), ", ".join(overl)])
			# walkability with / without Kenney colliders
			var lo := Vector2(-18, -8)
			var hi := Vector2(18, 25)
			var step := 0.3
			var start := Vector2(-15, 0)
			var with_k := _flood(space, node, start, lo, hi, step)
			var yard_lo := Vector2(-14.5, 7.0)
			var yard_hi := Vector2(14.5, 18.0)
			var p_with := _pockets(space, node, with_k, yard_lo, yard_hi, step)
			for b in kb:
				(b as CollisionObject3D).collision_layer = 0
			await physics_frame
			await physics_frame
			var without_k := _flood(space, node, start, lo, hi, step)
			var p_without := _pockets(space, node, without_k, yard_lo, yard_hi, step)
			var lost := 0
			for k in without_k:
				if not with_k.has(k):
					lost += 1
			info("seed %d church: %d Kenney colliders; reach with=%d without=%d lost=%d; yard pockets with=%d without=%d" % [seed_value, kb.size(), with_k.size(), without_k.size(), lost, p_with, p_without])
			check(p_with <= p_without + 3, "seed %d: Kenney colliders create no new enclosed yard pockets (%d vs %d baseline)" % [seed_value, p_with, p_without])
			var gate := _key(Vector2(0, 6.9), step)
			check(with_k.has(gate), "seed %d: church gate cell (0,6.9) reachable from the church door side" % seed_value)
			var yard_cells := 0
			for k in with_k:
				if k.y * step >= 8.0 and k.y * step <= 18.0 and absf(k.x * step) <= 14.0:
					yard_cells += 1
			check(yard_cells > 300, "seed %d: capsule reaches into the churchyard (%d cells)" % [seed_value, yard_cells])
			for b in kb:
				(b as CollisionObject3D).collision_layer = 1
		# ----- farms
		var hay := 0
		var pump := 0
		var farms: Array = w.get_locations("farm")
		for l in farms:
			var node: Node3D = l["node"]
			var h := _count_named(node, GY, "hay-bale")
			var pk := _count_named(node, GY, "pumpkin")
			hay += h
			pump += pk
			check(_count_named(node, FOOD, "plate") + _count_named(node, FOOD, "pot-stew") >= 2, "seed %d: farm kitchen has Food Kit dressing" % seed_value)
			var kb := _kenney_bodies(node)
			var overl := PackedStringArray()
			for b in kb:
				var body: StaticBody3D = b
				var cs: CollisionShape3D = body.get_child(0) as CollisionShape3D
				var q := PhysicsShapeQueryParameters3D.new()
				q.shape = cs.shape
				q.collision_mask = 1
				q.transform = cs.global_transform
				for hit in space.intersect_shape(q, 8):
					var col: Node = hit["collider"] as Node
					if col != null and col != body and not kb.has(col) and col.get_parent() == node:
						overl.append("(%.1f,%.1f) hits %s/%s" % [body.position.x, body.position.z, col.get_parent().name, col.name])
						break
			check(overl.is_empty(), "seed %d: farm hay bales do not overlap barn/house colliders (%d: %s)" % [seed_value, overl.size(), ", ".join(overl)])
			info("seed %d farm: hay=%d pumpkin=%d kenney colliders=%d" % [seed_value, h, pk, kb.size()])
			# farmhouse walkability with the Kenney colliders on: door is at z=+4, start south of it
			var lo := Vector2(-26, -12)
			var hi := Vector2(26, 26)
			var reach := _flood(space, node, Vector2(0, 9), lo, hi, 0.4)
			var inside := 0
			for k in reach:
				if Rect2(-4.5, -3.5, 9.0, 7.0).has_point(Vector2(k.x * 0.4, k.y * 0.4)):
					inside += 1
			check(inside > 20, "seed %d: capsule gets into the farmhouse (%d cells) with Kenney colliders" % [seed_value, inside])
		check(farms.size() == 0 or hay >= 1, "seed %d: farms have hay bales (%d total over %d farms)" % [seed_value, hay, farms.size()])
		check(farms.size() == 0 or pump >= 1, "seed %d: farms have pumpkins (%d total)" % [seed_value, pump])
		# ----- loot models
		var food_n := 0
		var food_k := 0
		var water_n := 0
		var water_k := 0
		var other_k := 0
		for id in w.loot_by_id:
			var ln: Node = w.loot_by_id[id] as Node
			if not is_instance_valid(ln):
				continue
			var iid: String = str(ln.get("item_id"))
			var ks: Array = []
			_models(ln, "res://assets/kenney/", ks)
			if iid == "food":
				food_n += 1
				if ks.size() > 0:
					food_k += 1
			elif iid == "water":
				water_n += 1
				if ks.size() == 1 and (ks[0] as Node).scene_file_path.ends_with("soda-bottle.glb"):
					water_k += 1
			elif ks.size() > 0:
				other_k += 1
		info("seed %d loot: food %d/%d Kenney, water %d/%d Kenney, other items with Kenney model %d" % [seed_value, food_k, food_n, water_k, water_n, other_k])
		check(food_n > 0 and food_k == food_n, "seed %d: all %d food pickups use Kenney can models" % [seed_value, food_n])
		check(water_n > 0 and water_k == water_n, "seed %d: all %d water pickups use soda-bottle.glb" % [seed_value, water_n])
		check(other_k == 0, "seed %d: non-food pickups keep their original look" % seed_value)
		w.queue_free()
		await physics_frame
		await physics_frame


func _phase4_zombie() -> void:
	info("--- phase 4: zombie")
	# Design change (Commander approved): only the walker uses a Kenney model (mini/character-zombie.glb).
	check(not FileAccess.get_file_as_string("res://scenes/zombies/zombie.tscn").to_lower().contains("kenney"), "zombie.tscn has no Kenney reference")
	var zsrc := FileAccess.get_file_as_string("res://scripts/zombies/zombie.gd").to_lower()
	check(zsrc.count("kenney/") == zsrc.count("kenney/mini/character-zombie.glb"), "zombie.gd references only mini/character-zombie.glb")
	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100, 1, 100)
	cs.shape = box
	floor_body.add_child(cs)
	floor_body.position = Vector3(0, -0.5, 0)
	root.add_child(floor_body)
	var z = (load("res://scenes/zombies/zombie.tscn") as PackedScene).instantiate()
	root.add_child(z)
	z.position = Vector3(30, 0.1, 30)
	await physics_frame
	await physics_frame
	var arms: Array = z._arms
	check(arms.size() == 2, "zombie has 2 arms (%d)" % arms.size())
	var kenney_nodes: Array = []
	_models(z, "res://assets/kenney/", kenney_nodes)
	check(kenney_nodes.size() <= 1, "default (walker) zombie contains at most the one Kenney walker model (%d)" % kenney_nodes.size())
	if arms.size() == 2:
		for st in [ZombieScript.State.IDLE, ZombieScript.State.CHASE]:
			z.state_id = st
			z._process(0.016)
			var fwd: Vector3 = -(z as Node3D).global_transform.basis.z
			for a in arms:
				var arm: Node3D = a
				var hang: Vector3 = -arm.global_transform.basis.y
				check(arm.rotation.x > 0.0, "zombie state %d arm angle positive (%.2f)" % [st, arm.rotation.x])
				check(hang.dot(fwd) > 0.0, "zombie state %d arm swings toward facing direction (dot %.2f)" % [st, hang.dot(fwd)])
	z.queue_free()
	floor_body.queue_free()
	await physics_frame


func _phase3_main() -> void:
	info("--- phase 3: real solo main.tscn")
	var net: Node = root.get_node("Net")
	check(net.host_solo() == OK, "host_solo() ok")
	check(net.start_game() == OK, "start_game() ok")
	for i in 120:
		await process_frame
	var main := current_scene
	check(main != null and main.scene_file_path == "res://scenes/main.tscn", "main.tscn loaded")
	if main == null:
		return
	var gy: Array = []
	_models(main, GY, gy)
	check(gy.size() >= 20, "main scene: %d Kenney graveyard models (churches)" % gy.size())
	check(_count_named(main, GY, "hay-bale") + _count_named(main, GY, "pumpkin") >= 1, "main scene: hay bales/pumpkins present (%d hay, %d pumpkin)" % [_count_named(main, GY, "hay-bale"), _count_named(main, GY, "pumpkin")])
	var fk: Array = []
	_models(main, FOOD, fk)
	info("main scene: %d Kenney Food Kit models (loot + dressing)" % fk.size())
	check(_count_named(main, FOOD, "soda-bottle") >= 1, "main scene: soda-bottle.glb in use (%d)" % _count_named(main, FOOD, "soda-bottle"))
	check(_count_named(main, FOOD, "/can.glb") + _count_named(main, FOOD, "can-small") >= 1, "main scene: can models in use")
	var players := get_nodes_in_group("players")
	check(players.size() == 1, "one player (%d)" % players.size())
	if players.size() != 1:
		return
	var p = players[0]
	var cam: Camera3D = p.camera
	var head: Node3D = p.head
	check(cam.current, "player camera is current")
	check(root.get_viewport().get_camera_3d() == cam, "viewport renders through the player camera")
	check(cam.get_parent() == head and head.get_parent() == p, "camera is under Head under Player (no rig)")
	check(cam.position.length() < 0.001, "camera local offset zero (%s)" % str(cam.position))
	var dy: float = cam.global_position.y - (p as Node3D).global_position.y
	check(absf(dy - 1.62) < 0.1, "camera at eye height %.2f m above feet" % dy)
	var dh := Vector2(cam.global_position.x - p.global_position.x, cam.global_position.z - p.global_position.z).length()
	check(dh < 0.01, "no third-person horizontal offset (%.3f m)" % dh)
	check((p as Node).find_children("*", "SpringArm3D", true, false).is_empty(), "no SpringArm3D under the player")
	check(not main.find_children("*", "SpringArm3D", true, false).size() > 0, "no SpringArm3D in main scene")
	var cur := 0
	for c in main.find_children("*", "Camera3D", true, false):
		if (c as Camera3D).current:
			cur += 1
	check(cur == 1, "exactly one current Camera3D in main (%d)" % cur)
	var pk: Array = []
	_models(p, "res://assets/kenney/", pk)
	# QA: PlayerModel (commit 86f33b7) deliberately builds the Avatar from res://assets/kenney/mini/ (shadow-only for the
	# local player). The old assertion "no Kenney models at all" predates it; still reject Kenney models outside the Avatar.
	var pk_other: Array = []
	for m in pk:
		var under_avatar := false
		var a: Node = m as Node
		while a != null and a != p:
			if a.name == "Avatar":
				under_avatar = true
			a = a.get_parent()
		if not under_avatar:
			pk_other.append(m)
	check(pk_other.is_empty(), "player scene has no Kenney models outside the Avatar (%d; %d inside the Avatar)" % [pk_other.size(), pk.size() - pk_other.size()])
	info("camera fov %.0f, head y %.2f" % [cam.fov, head.position.y])
