extends SceneTree
## Kenney walker: rest-pose vertex extents per body band vs the collision capsule (RAT).
## Run: godot --headless --path . --script res://tests/t_kenney_walker_fit.gd


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await physics_frame
	var net: Node = root.get_node_or_null("Net")
	net.host_solo(31337)
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	for _i in 40:
		await physics_frame
	var p = net.players.get(1)
	var sp = get_first_node_in_group("spawner")
	sp.enabled = false
	sp.kill_all()
	var base: Vector3 = p.global_position
	var pos := Vector3(base.x + 30, main.world.get_height(base.x + 30, base.z + 30) + 0.6, base.z + 30)
	var w = sp.spawn_zombie_at(pos, false, Zombie.KIND_WALKER)
	for _i in 20:
		await physics_frame
	var gy: float = w.global_position.y
	var org: Vector3 = w.global_position
	var bands := [[0.0, 0.5, "legs"], [0.5, 0.89, "torso"], [0.89, 1.36, "head lower (body hit)"], [1.36, 1.9, "head upper (head hit)"]]
	for band in bands:
		var maxr := 0.0
		var minz := 99.0
		var maxz := -99.0
		var minx := 99.0
		var maxx := -99.0
		var n := 0
		for m in w.find_children("*", "MeshInstance3D", true, false):
			var mi := m as MeshInstance3D
			var arr: Array = mi.mesh.surface_get_arrays(0)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			for v in verts:
				var wv: Vector3 = mi.global_transform * v
				var rel: Vector3 = wv - org
				if rel.y >= band[0] and rel.y < band[1]:
					n += 1
					maxr = maxf(maxr, Vector2(rel.x, rel.z).length())
					minx = minf(minx, rel.x)
					maxx = maxf(maxx, rel.x)
					minz = minf(minz, rel.z)
					maxz = maxf(maxz, rel.z)
		print("BAND %-24s verts=%d  x %.2f..%.2f  z %.2f..%.2f  max horizontal radius from origin %.2f" % [band[2], n, minx, maxx, minz, maxz, maxr])
	var cs := w.get_node("Collision") as CollisionShape3D
	var cap := cs.shape as CapsuleShape3D
	print("CAPSULE r=%.2f h=%.2f centre offset (%.2f, %.2f, %.2f)" % [cap.radius, cap.height, cs.position.x, cs.position.y, cs.position.z])
	# clean side rays from the -X side (nothing else spawned there)
	var space: PhysicsDirectSpaceState3D = w.get_world_3d().direct_space_state
	for y in [0.3, 0.9, 1.3, 1.5, 1.7, 1.85]:
		var row := []
		for dz in [-0.6, -0.4, -0.2, 0.0, 0.2, 0.4, 0.6]:
			var from := Vector3(org.x - 5.0, gy + y, org.z + dz)
			var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(10, 0, 0))
			q.exclude = [p.get_rid()]
			var res: Dictionary = space.intersect_ray(q)
			row.append("X" if (res.size() > 0 and res.collider == w) else ".")
		print("RAYROW y=+%.2f z-offset -0.6..+0.6: %s" % [y, " ".join(row)])
	quit(0)
