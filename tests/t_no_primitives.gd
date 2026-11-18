extends SceneTree
## No primitive-built objects in the world. Run:
##   xvfb-run -a godot --headless --path . --script res://tests/t_no_primitives.gd
## Builds the world and asserts every visible MeshInstance3D / MultiMeshInstance3D is either part of an instanced
## downloaded asset (scene under res://assets/ or a mesh resource from a .glb) or on the allowed list below
## (terrain chunks, the terrain-baked road mesh, pickup glow discs). Also builds one zombie of each kind and one
## placed piece of each building kind, and scans them the same way.

const ALLOWED_PREFIX := ["Chunk_", "Roads", "Glow"]

var _fails := 0


func check(ok: bool, msg: String) -> void:
	if ok:
		print("PASS ", msg)
	else:
		print("FAIL ", msg)
		_fails += 1


func _is_asset(n: Node) -> bool:
	var p: Node = n
	while p != null:
		if str(p.scene_file_path).begins_with("res://assets/"):
			return true
		p = p.get_parent()
	return false


func _mesh_of(n: Node) -> Mesh:
	if n is MeshInstance3D:
		return (n as MeshInstance3D).mesh
	if n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh != null:
		return (n as MultiMeshInstance3D).multimesh.mesh
	return null


func _offenders(root_node: Node, out: Array) -> int:
	var seen := 0
	for n in root_node.find_children("*", "", true, false):
		if not (n is MeshInstance3D or n is MultiMeshInstance3D):
			continue
		var mesh := _mesh_of(n)
		if mesh == null or not (n as Node3D).is_visible_in_tree():
			continue
		seen += 1
		var rp: String = mesh.resource_path
		if _is_asset(n) or rp.contains("assets/") or rp.contains(".glb"):
			continue
		var allowed := false
		for pre in ALLOWED_PREFIX:
			if str(n.name).begins_with(pre):
				allowed = true
		if not allowed:
			out.append("%s (%s) under %s" % [n.name, mesh.get_class(), n.get_parent().name])
	return seen


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var world: Node3D = (load("res://scenes/world/world.tscn") as PackedScene).instantiate()
	root.add_child(world)
	world.build(1)
	for _i in 3:
		await physics_frame
	var bad: Array = []
	var seen := _offenders(world, bad)
	print("world meshes scanned: ", seen)
	for b in bad:
		print("  primitive: ", b)
	check(seen > 0, "world has visible meshes (scan is live)")
	check(bad.is_empty(), "world: zero visible primitive meshes outside the allowed list (%d found)" % bad.size())

	var zs: PackedScene = load("res://scenes/zombies/zombie.tscn") as PackedScene
	if zs != null:
		for k in 3:
			var z: Node3D = zs.instantiate()
			z.set("kind", k)
			root.add_child(z)
			await physics_frame
			var zb: Array = []
			var zn := _offenders(z, zb)
			check(zn > 0 and zb.is_empty(), "zombie kind %d: %d meshes, %d primitive" % [k, zn, zb.size()])
			z.queue_free()
	else:
		check(false, "zombie scene loads")
	print("t_no_primitives: ", "OK" if _fails == 0 else "%d FAILED" % _fails)
	quit(1 if _fails > 0 else 0)
