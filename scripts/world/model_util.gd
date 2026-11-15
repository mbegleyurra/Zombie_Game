extends RefCounted
## Loads a Kenney .glb, scales it to a target height and sits it on the ground (y = 0),
## centred on x/z. Returns a Node3D wrapper (meta "size" = scaled bounding size) or null.


static func load_fit(path: String, target_height: float) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	var ps := load(path) as PackedScene
	if ps == null:
		return null
	var inst := ps.instantiate() as Node3D
	if inst == null:
		return null
	var boxes: Array = []
	_collect(inst, Transform3D.IDENTITY, boxes)
	if boxes.is_empty():
		inst.queue_free()
		return null
	var bb: AABB = boxes[0]
	for i in range(1, boxes.size()):
		bb = bb.merge(boxes[i])
	var s: float = target_height / maxf(bb.size.y, 0.001)
	var center := bb.get_center()
	inst.scale = Vector3(s, s, s)
	inst.position = Vector3(-center.x * s, -bb.position.y * s, -center.z * s)
	var wrap := Node3D.new()
	wrap.add_child(inst)
	wrap.set_meta("size", bb.size * s)
	return wrap


static func _collect(n: Node, xf: Transform3D, out: Array) -> void:
	var t := xf
	if n is Node3D:
		t = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append(t * (n as MeshInstance3D).mesh.get_aabb())
	for c in n.get_children():
		_collect(c, t, out)
