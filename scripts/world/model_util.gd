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


## A downloaded model stretched per axis to fill `size`, its bounds centred on the returned wrapper's origin.
## Used where a primitive box used to stand: the same footprint, the model as the visual. Null when the model is missing.
static func fit_box(path: String, size: Vector3) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	var ps := load(path) as PackedScene
	if ps == null:
		return null
	var inst := ps.instantiate() as Node3D
	if inst == null:
		return null
	var bb: AABB = bounds(inst)
	if bb.size.x + bb.size.y + bb.size.z < 0.0001:
		inst.queue_free()
		return null
	var s := Vector3(size.x / maxf(bb.size.x, 0.001), size.y / maxf(bb.size.y, 0.001), size.z / maxf(bb.size.z, 0.001))
	inst.scale = s
	inst.position = -bb.get_center() * s
	var wrap := Node3D.new()
	wrap.add_child(inst)
	wrap.set_meta("size", size)
	return wrap


## A model repeated on a grid to fill `size`, centred on the wrapper's origin. Each axis gets round(size / cell) tiles
## (at least 1), so a long wall is many panels near the model's natural proportions instead of one stretched piece.
## A cell component <= 0 means "one tile along that axis". Null when the model is missing.
static func tile_box(path: String, size: Vector3, cell: Vector3) -> Node3D:
	var n := Vector3i(1, 1, 1)
	for a in 3:
		if cell[a] > 0.0:
			n[a] = maxi(1, roundi(size[a] / cell[a]))
	var tile := Vector3(size.x / n.x, size.y / n.y, size.z / n.z)
	var wrap := Node3D.new()
	for ix in n.x:
		for iy in n.y:
			for iz in n.z:
				var t: Node3D = fit_box(path, tile)
				if t == null:
					wrap.queue_free()
					return null
				t.position = Vector3(
					-size.x * 0.5 + (ix + 0.5) * tile.x,
					-size.y * 0.5 + (iy + 0.5) * tile.y,
					-size.z * 0.5 + (iz + 0.5) * tile.z)
				wrap.add_child(t)
	wrap.set_meta("size", size)
	return wrap


## Merged bounding box of every mesh under `n`, in n's own space (zero-size AABB when it has no mesh).
static func bounds(n: Node3D) -> AABB:
	var boxes: Array = []
	_collect(n, Transform3D.IDENTITY, boxes)
	if boxes.is_empty():
		return AABB()
	var bb: AABB = boxes[0]
	for i in range(1, boxes.size()):
		bb = bb.merge(boxes[i])
	return bb


static func _collect(n: Node, xf: Transform3D, out: Array) -> void:
	var t := xf
	if n is Node3D:
		t = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append(t * (n as MeshInstance3D).mesh.get_aabb())
	for c in n.get_children():
		_collect(c, t, out)
