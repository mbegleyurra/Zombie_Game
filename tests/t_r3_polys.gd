extends SceneTree
## Round 3 requirements probe: triangle counts of world / zombie / guns, world extent, flat-colour check.
## Run: godot --headless --path . --script res://tests/t_r3_polys.gd

func _tris(node: Node) -> Array:
	var tris := 0
	var meshes := 0
	for n in node.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		meshes += 1
		tris += mi.mesh.get_faces().size() / 3
	return [tris, meshes]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await physics_frame
	var world: Node3D = (load("res://scenes/world/world.tscn") as PackedScene).instantiate()
	root.add_child(world)
	world.build(20260101)
	await physics_frame
	var t: Array = _tris(world)
	print("POLY  world: %d triangles in %d mesh instances" % [t[0], t[1]])
	var minp := Vector2(1e9, 1e9)
	var maxp := Vector2(-1e9, -1e9)
	for l in world.get_locations():
		var pp: Vector3 = l["pos"]
		minp = Vector2(minf(minp.x, pp.x), minf(minp.y, pp.z))
		maxp = Vector2(maxf(maxp.x, pp.x), maxf(maxp.y, pp.z))
	print("POLY  location span: x %.0f..%.0f z %.0f..%.0f (%d locations)" % [minp.x, maxp.x, minp.y, maxp.y, world.get_locations().size()])
	var hmin := 1e9
	var hmax := -1e9
	for xi in range(-190, 191, 10):
		for zi in range(-190, 191, 10):
			var h: float = world.get_height(float(xi), float(zi))
			hmin = minf(hmin, h)
			hmax = maxf(hmax, h)
	print("POLY  terrain height range over +-190 m: %.1f .. %.1f" % [hmin, hmax])
	var z: Node = (load("res://scenes/zombies/zombie.tscn") as PackedScene).instantiate()
	root.add_child(z)
	await physics_frame
	t = _tris(z)
	print("POLY  zombie: %d triangles in %d mesh instances" % [t[0], t[1]])
	var p: Node = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	p.name = "1"
	root.add_child(p)
	await physics_frame
	for wid in ["pistol", "ak", "m4", "shotgun", "hunting"]:
		p.weapons.give_weapon(wid)
		p.weapons.equip(p.weapons._find_slot(wid))
		await physics_frame
		var vm = p.weapons.get("_viewmodel")
		if vm != null and vm is Node:
			var tt: Array = _tris(vm)
			print("POLY  viewmodel %s: %d triangles in %d meshes" % [wid, tt[0], tt[1]])
	quit(0)
