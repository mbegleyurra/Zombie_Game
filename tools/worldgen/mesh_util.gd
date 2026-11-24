extends RefCounted
## Flat-shaded, vertex-coloured mesh accumulator.
## Every triangle is emitted un-indexed with its own face normal (faceted low-poly look).
## Winding is fixed automatically from an "outward" hint vector (Godot front faces are clockwise).

var verts := PackedVector3Array()
var norms := PackedVector3Array()
var cols := PackedColorArray()


static func make_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.95
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func is_empty() -> bool:
	return verts.is_empty()


func add_tri(a: Vector3, b: Vector3, c: Vector3, col: Color, hint: Vector3) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 0.000001:
		return
	n = n.normalized()
	if n.dot(hint) >= 0.0:
		_push(a, c, b, n, col)
	else:
		_push(a, b, c, -n, col)


func add_quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, hint: Vector3) -> void:
	add_tri(a, b, c, col, hint)
	add_tri(a, c, d, col, hint)


func add_box(center: Vector3, size: Vector3, col: Color) -> void:
	var h := size * 0.5
	var x0 := center.x - h.x
	var x1 := center.x + h.x
	var y0 := center.y - h.y
	var y1 := center.y + h.y
	var z0 := center.z - h.z
	var z1 := center.z + h.z
	var p000 := Vector3(x0, y0, z0)
	var p100 := Vector3(x1, y0, z0)
	var p110 := Vector3(x1, y1, z0)
	var p010 := Vector3(x0, y1, z0)
	var p001 := Vector3(x0, y0, z1)
	var p101 := Vector3(x1, y0, z1)
	var p111 := Vector3(x1, y1, z1)
	var p011 := Vector3(x0, y1, z1)
	add_quad(p001, p101, p111, p011, col, Vector3(0, 0, 1))
	add_quad(p100, p000, p010, p110, col, Vector3(0, 0, -1))
	add_quad(p101, p100, p110, p111, col, Vector3(1, 0, 0))
	add_quad(p000, p001, p011, p010, col, Vector3(-1, 0, 0))
	add_quad(p010, p011, p111, p110, col, Vector3(0, 1, 0))
	add_quad(p000, p100, p101, p001, col, Vector3(0, -1, 0))


## Faceted cylinder / cone (rt <= 0.001 makes a cone). base = bottom centre.
func add_frustum(base: Vector3, rb: float, rt: float, height: float, segs: int, col: Color, twist: float = 0.0) -> void:
	var apex := base + Vector3(0, height, 0)
	for i in segs:
		var a0 := TAU * float(i) / float(segs) + twist
		var a1 := TAU * float(i + 1) / float(segs) + twist
		var am := (a0 + a1) * 0.5
		var mid := Vector3(cos(am), 0, sin(am))
		var b0 := base + Vector3(cos(a0) * rb, 0, sin(a0) * rb)
		var b1 := base + Vector3(cos(a1) * rb, 0, sin(a1) * rb)
		if rt <= 0.001:
			add_tri(b0, b1, apex, col, mid + Vector3(0, 0.3, 0))
		else:
			var t0 := apex + Vector3(cos(a0) * rt, 0, sin(a0) * rt)
			var t1 := apex + Vector3(cos(a1) * rt, 0, sin(a1) * rt)
			add_quad(b0, b1, t1, t0, col, mid)
			add_tri(apex, t0, t1, col, Vector3.UP)


## Oriented box. centre/size are in the local frame of xf, which carries yaw, tilt and position.
func add_box_xf(xf: Transform3D, center: Vector3, size: Vector3, col: Color) -> void:
	var h := size * 0.5
	var c: Array = []
	for i in 8:
		var sx: float = 1.0 if (i & 1) != 0 else -1.0
		var sy: float = 1.0 if (i & 2) != 0 else -1.0
		var sz: float = 1.0 if (i & 4) != 0 else -1.0
		c.append(xf * (center + Vector3(h.x * sx, h.y * sy, h.z * sz)))
	var b := xf.basis
	add_quad(c[4], c[5], c[7], c[6], col, b * Vector3(0, 0, 1))
	add_quad(c[1], c[0], c[2], c[3], col, b * Vector3(0, 0, -1))
	add_quad(c[5], c[1], c[3], c[7], col, b * Vector3(1, 0, 0))
	add_quad(c[0], c[4], c[6], c[2], col, b * Vector3(-1, 0, 0))
	add_quad(c[2], c[6], c[7], c[3], col, b * Vector3(0, 1, 0))
	add_quad(c[0], c[1], c[5], c[4], col, b * Vector3(0, -1, 0))


## Square-section beam from a to b (branches, wires, struts).
func add_beam(a: Vector3, b: Vector3, thick: float, col: Color) -> void:
	var d := b - a
	var blen := d.length()
	if blen < 0.001:
		return
	var x := d / blen
	var ref := Vector3.UP if absf(x.y) < 0.95 else Vector3.RIGHT
	var z := x.cross(ref).normalized()
	var y := z.cross(x)
	add_box_xf(Transform3D(Basis(x, y, z), (a + b) * 0.5), Vector3.ZERO, Vector3(blen, thick, thick), col)


func to_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if verts.is_empty():
		return mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _tri_out(a: Vector3, b: Vector3, c: Vector3, center: Vector3, col: Color) -> void:
	add_tri(a, b, c, col, (a + b + c) / 3.0 - center)


func _push(a: Vector3, b: Vector3, c: Vector3, n: Vector3, col: Color) -> void:
	verts.append(a)
	verts.append(b)
	verts.append(c)
	norms.append(n)
	norms.append(n)
	norms.append(n)
	cols.append(col)
	cols.append(col)
	cols.append(col)
