extends SceneTree
## Kenney test (RAT): zombie arm direction during the wind-up pose (_wind_pose=1). Reads only.
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var fb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(100, 1, 100)
	cs.shape = bx
	fb.add_child(cs)
	fb.position = Vector3(0, -0.5, 0)
	root.add_child(fb)
	var z = (load("res://scenes/zombies/zombie.tscn") as PackedScene).instantiate()
	root.add_child(z)
	z.position = Vector3(30, 0.1, 30)
	await physics_frame
	await physics_frame
	for wp in [0.0, 0.5, 1.0]:
		z._wind_pose = wp
		z._process(0.0)
		var fwd: Vector3 = -(z as Node3D).global_transform.basis.z
		var a: Node3D = z._arms[0]
		print("INFO  wind_pose %.1f arm0 rot.x %.2f hang.dot(fwd) %.2f hang.y %.2f" % [wp, a.rotation.x, (-a.global_transform.basis.y).dot(fwd), (-a.global_transform.basis.y).y])
	quit(0)
