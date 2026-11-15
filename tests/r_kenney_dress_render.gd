extends SceneTree
## Renders the Survival/Car Kit dressing (RAT). Needs a real renderer: run under xvfb-run, NOT --headless.
## xvfb-run -a godot --path . --script res://tests/r_kenney_dress_render.gd -- /abs/out_dir

var out_dir := "/tmp/kenney_dress_render"
var cam: Camera3D


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _shot(name: String, pos: Vector3, look: Vector3) -> void:
	cam.global_position = pos
	cam.look_at(look, Vector3.UP)
	for _i in 8:
		await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [out_dir, name])
	print("SAVED ", name, " ", img.get_size())


func _run() -> void:
	await physics_frame
	var w: Node3D = (load("res://scenes/world/world.tscn") as PackedScene).instantiate()
	root.add_child(w)
	w.build(31337)
	cam = Camera3D.new()
	cam.fov = 70.0
	cam.far = 400.0
	root.add_child(cam)
	cam.current = true
	await process_frame
	var d: Node3D = w.get_node("KenneyDressing")
	for t in ["police_station", "hospital", "gas_station", "warehouse"]:
		var ls: Array = w.get_locations(t)
		if ls.is_empty():
			continue
		var p: Vector3 = ls[0]["pos"]
		var n: Node3D = ls[0]["node"]
		var back: Vector3 = n.global_transform.basis * Vector3(0, 0, 30)
		await _shot(t, Vector3(p.x + back.x, w.get_height(p.x, p.z) + 6.0, p.z + back.z), Vector3(p.x, w.get_height(p.x, p.z) + 1.0, p.z))
	# a camp: tent is the 1st child of a camp part list; find any model named tent*
	for c in d.get_children():
		if c is Node3D and c.name != "Collision" and c.get_child_count() > 0 and "tent" in str(c.get_child(0).name).to_lower():
			var p: Vector3 = (c as Node3D).global_position
			await _shot("camp", p + Vector3(7, 4, 7), p + Vector3(0, 0.8, 0))
			break
	# a road car
	var shown := 0
	for c in d.get_children():
		if shown >= 2:
			break
		if c is Node3D and c.name != "Collision" and c.get_child_count() > 0:
			var nm := str(c.get_child(0).name).to_lower()
			if nm in ["ambulance", "police", "taxi", "sedan", "van", "truck", "suv", "firetruck", "delivery"]:
				var p: Vector3 = (c as Node3D).global_position
				if p.length() < 35.0:
					continue
				shown += 1
				await _shot("roadcar_%d_%s" % [shown, nm], p + Vector3(8, 3.5, 8), p + Vector3(0, 1.0, 0))
	var sp: Vector3 = w.get_spawn_point(0)
	await _shot("spawn_eye", sp + Vector3(0, 1.0, 0), sp + Vector3(0, 1.0, -20))
	print("DONE")
	quit(0)
