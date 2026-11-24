extends RefCounted
## Reads the baked vegetation (Vegetation/KayKitForest MultiMeshes) straight from their instance buffers, so the map,
## tests and tools always see what is actually saved: moving or editing a batch in the editor is reflected, and there is
## no separate copy of the sites to go stale. Works under the headless renderer, which keeps a buffer that was loaded or
## assigned whole (it only drops per-instance set_instance_transform writes).
## Buffer layout per instance (TRANSFORM_3D): [x.x, y.x, z.x, o.x,  x.y, y.y, z.y, o.y,  x.z, y.z, z.z, o.z].


static func _stride(mm: MultiMesh) -> int:
	return 12 + (4 if mm.use_colors else 0) + (4 if mm.use_custom_data else 0)


static func instance_transform(mm: MultiMesh, buf: PackedFloat32Array, i: int) -> Transform3D:
	var j := i * _stride(mm)
	return Transform3D(Basis(Vector3(buf[j], buf[j + 4], buf[j + 8]), Vector3(buf[j + 1], buf[j + 5], buf[j + 9]),
		Vector3(buf[j + 2], buf[j + 6], buf[j + 10])), Vector3(buf[j + 3], buf[j + 7], buf[j + 11]))


## True when a TRANSFORM_3D MultiMesh holds a full buffer and every instance has a non-degenerate basis.
static func buffer_ok(mm: MultiMesh) -> bool:
	if mm == null or mm.transform_format != MultiMesh.TRANSFORM_3D:
		return false
	var buf: PackedFloat32Array = mm.buffer
	if buf.size() != mm.instance_count * _stride(mm):
		return false
	for i in mm.instance_count:
		if absf(instance_transform(mm, buf, i).basis.determinant()) < 1e-6:
			return false
	return true


## Every vegetation instance as [kind, x, z] in the forest node's parent space (the world). The position is the centre
## of the instance's mesh bounds, which the generator seats exactly on the authored x/z. Kind is the batch's "kind"
## meta (fallback: the node name prefix, e.g. "tree_Tree_1_..." -> "tree").
static func sites(forest: Node) -> Array:
	var out: Array = []
	if forest == null:
		return out
	var base: Transform3D = (forest as Node3D).transform if forest is Node3D else Transform3D.IDENTITY
	for ch in forest.get_children():
		if not (ch is MultiMeshInstance3D):
			continue
		var mmi := ch as MultiMeshInstance3D
		var mm: MultiMesh = mmi.multimesh
		if mm == null:
			continue
		var buf: PackedFloat32Array = mm.buffer
		if buf.size() < mm.instance_count * _stride(mm):
			continue
		var kind: String = str(mmi.get_meta("kind", String(mmi.name).get_slice("_", 0)))
		var centre: Vector3 = mm.mesh.get_aabb().get_center() if mm.mesh != null else Vector3.ZERO
		var xf: Transform3D = base * mmi.transform
		for i in mm.instance_count:
			var p: Vector3 = xf * (instance_transform(mm, buf, i) * centre)
			out.append([kind, p.x, p.z])
	return out
