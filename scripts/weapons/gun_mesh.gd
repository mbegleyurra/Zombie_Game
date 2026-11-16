class_name GunMesh
extends RefCounted
## Low-poly procedural gun models built from primitives.
## Convention: gun points down -Z, origin at the rear of the receiver,
## top of the receiver at about y = +0.06. A Marker3D named "Muzzle" marks the barrel tip.

const STEEL := Color(0.13, 0.13, 0.15)
const DARK := Color(0.07, 0.07, 0.08)
const POLYMER := Color(0.17, 0.17, 0.18)
const WOOD := Color(0.42, 0.26, 0.12)
const WOOD_DARK := Color(0.3, 0.18, 0.09)
const GLASS := Color(0.2, 0.35, 0.5)

static var _mat_cache: Dictionary = {}


static func build(model: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Gun_" + model
	match model:
		"pistol":
			_pistol(root)
		"ak":
			_ak(root)
		"m4":
			_m4(root)
		"shotgun":
			_shotgun(root)
		"hunting":
			_hunting(root)
		"ar":
			_ar(root)
		"ar_t1", "ar_t2", "ar_t3":
			_ar_tier(root, int(model.substr(4)))
		_:
			_pistol(root)
	return root


static func muzzle_of(gun: Node3D) -> Node3D:
	return gun.get_node_or_null("Muzzle") as Node3D


## Returns a copy of `src` with one flat normal per triangle (faceted low-poly
## shading). Works for any single-surface triangle mesh (sphere, capsule, cylinder).
static func faceted(src: Mesh) -> ArrayMesh:
	var arrays := src.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = PackedInt32Array()
	if arrays[Mesh.ARRAY_INDEX] != null:
		idx = arrays[Mesh.ARRAY_INDEX]
	var src_n: PackedVector3Array = PackedVector3Array()
	if arrays[Mesh.ARRAY_NORMAL] != null:
		src_n = arrays[Mesh.ARRAY_NORMAL]
	var count := idx.size() if idx.size() > 0 else verts.size()
	var out_v := PackedVector3Array()
	var out_n := PackedVector3Array()
	for i in range(0, count - 2, 3):
		var ia := idx[i] if idx.size() > 0 else i
		var ib := idx[i + 1] if idx.size() > 0 else i + 1
		var ic := idx[i + 2] if idx.size() > 0 else i + 2
		var a := verts[ia]
		var b := verts[ib]
		var c := verts[ic]
		var n := (c - a).cross(b - a)
		if n.length_squared() < 1e-12:
			continue
		n = n.normalized()
		if src_n.size() > ic and n.dot(src_n[ia] + src_n[ib] + src_n[ic]) < 0.0:
			n = -n   # keep the original outward orientation
		out_v.append_array(PackedVector3Array([a, b, c]))
		out_n.append_array(PackedVector3Array([n, n, n]))
	var out_arrays := []
	out_arrays.resize(Mesh.ARRAY_MAX)
	out_arrays[Mesh.ARRAY_VERTEX] = out_v
	out_arrays[Mesh.ARRAY_NORMAL] = out_n
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out_arrays)
	return m


# ---------------------------------------------------------------- helpers

static func _mat(color: Color, metallic: float = 0.0, rough: float = 0.8) -> StandardMaterial3D:
	var key := "%s_%s_%s" % [color.to_html(), metallic, rough]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = rough
	_mat_cache[key] = m
	return m


static func _box(parent: Node3D, size: Vector3, pos: Vector3, color: Color, rot_deg: Vector3 = Vector3.ZERO, metallic: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = _mat(color, metallic, 0.55 if metallic > 0.0 else 0.85)
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## Cylinder lying along the Z axis, centred at pos, `length` long.
static func _barrel(parent: Node3D, radius: float, length: float, pos: Vector3, color: Color, metallic: float = 0.6, segments: int = 12) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = segments
	mesh.rings = 1
	mi.mesh = faceted(mesh)
	mi.material_override = _mat(color, metallic, 0.5)
	mi.position = pos
	mi.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## Upright (Y axis) cylinder: knobs, turrets, screws, cartridge heads.
static func _post(parent: Node3D, radius: float, height: float, pos: Vector3, color: Color, metallic: float = 0.5, segments: int = 10) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = segments
	mesh.rings = 1
	mi.mesh = faceted(mesh)
	mi.material_override = _mat(color, metallic, 0.5)
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## A row of small teeth/ribs along Z (serrations, rail slots, magazine ribs).
static func _ribs(parent: Node3D, count: int, size: Vector3, start: Vector3, step: Vector3, color: Color, metallic: float = 0.0) -> void:
	for i in range(count):
		_box(parent, size, start + step * float(i), color, Vector3.ZERO, metallic)


static func _muzzle(parent: Node3D, z: float, y: float = 0.0) -> void:
	var m := Marker3D.new()
	m.name = "Muzzle"
	m.position = Vector3(0.0, y, z)
	parent.add_child(m)


# ---------------------------------------------------------------- models

static func _pistol(r: Node3D) -> void:
	_box(r, Vector3(0.034, 0.04, 0.2), Vector3(0, 0.04, -0.1), STEEL, Vector3.ZERO, 0.6)   # slide
	_box(r, Vector3(0.03, 0.025, 0.16), Vector3(0, 0.005, -0.09), POLYMER)                 # frame
	_box(r, Vector3(0.032, 0.095, 0.05), Vector3(0, -0.05, -0.02), POLYMER, Vector3(-12, 0, 0)) # grip
	_box(r, Vector3(0.02, 0.012, 0.03), Vector3(0, -0.005, -0.065), DARK)                  # trigger guard bar
	_box(r, Vector3(0.006, 0.01, 0.012), Vector3(0, 0.066, -0.01), DARK)                   # rear sight
	_box(r, Vector3(0.005, 0.01, 0.01), Vector3(0, 0.066, -0.19), DARK)                    # front sight
	_ribs(r, 5, Vector3(0.037, 0.03, 0.006), Vector3(0, 0.044, -0.015), Vector3(0, 0, -0.011), DARK)  # slide serrations (rear)
	_box(r, Vector3(0.036, 0.016, 0.04), Vector3(0, 0.055, -0.1), DARK, Vector3.ZERO, 0.4)     # ejection port
	_box(r, Vector3(0.026, 0.012, 0.06), Vector3(0, -0.012, -0.15), POLYMER)               # accessory rail
	_box(r, Vector3(0.008, 0.03, 0.012), Vector3(0, -0.018, -0.07), DARK, Vector3(-10, 0, 0)) # trigger
	_box(r, Vector3(0.026, 0.012, 0.03), Vector3(0, -0.012, -0.04), POLYMER)               # trigger guard front
	_box(r, Vector3(0.012, 0.018, 0.02), Vector3(0, 0.062, 0.005), DARK, Vector3(25, 0, 0)) # hammer
	_box(r, Vector3(0.036, 0.016, 0.052), Vector3(0, -0.103, -0.012), DARK, Vector3(-12, 0, 0))  # magazine baseplate
	_box(r, Vector3(0.008, 0.012, 0.02), Vector3(0.019, 0.01, -0.12), DARK)                # slide stop lever
	_ribs(r, 4, Vector3(0.036, 0.006, 0.04), Vector3(0, -0.03, -0.02), Vector3(0, -0.017, 0.002), DARK)  # grip texture
	_barrel(r, 0.008, 0.02, Vector3(0, 0.04, -0.205), STEEL, 0.7, 8)                       # barrel crown
	_muzzle(r, -0.205, 0.04)


static func _ak(r: Node3D) -> void:
	_box(r, Vector3(0.05, 0.075, 0.3), Vector3(0, 0.0, -0.15), STEEL, Vector3.ZERO, 0.5)   # receiver
	_box(r, Vector3(0.048, 0.02, 0.3), Vector3(0, 0.044, -0.15), STEEL, Vector3.ZERO, 0.5) # dust cover
	_barrel(r, 0.012, 0.42, Vector3(0, 0.02, -0.51), STEEL)                                # barrel
	_barrel(r, 0.014, 0.26, Vector3(0, 0.045, -0.43), DARK)                                # gas tube
	_box(r, Vector3(0.056, 0.05, 0.22), Vector3(0, 0.0, -0.4), WOOD)                       # handguard
	_box(r, Vector3(0.04, 0.03, 0.2), Vector3(0, 0.045, -0.4), WOOD_DARK)                  # upper handguard
	_box(r, Vector3(0.046, 0.15, 0.065), Vector3(0, -0.11, -0.2), POLYMER, Vector3(18, 0, 0)) # curved magazine
	_box(r, Vector3(0.036, 0.1, 0.05), Vector3(0, -0.075, -0.04), WOOD, Vector3(-16, 0, 0)) # pistol grip
	_box(r, Vector3(0.045, 0.085, 0.26), Vector3(0, -0.01, 0.13), WOOD, Vector3(-4, 0, 0))  # stock
	_box(r, Vector3(0.008, 0.035, 0.012), Vector3(0, 0.075, -0.02), DARK)                  # rear sight
	_box(r, Vector3(0.006, 0.04, 0.01), Vector3(0, 0.055, -0.7), DARK)                     # front sight post
	_box(r, Vector3(0.03, 0.045, 0.04), Vector3(0, 0.04, -0.64), STEEL, Vector3.ZERO, 0.5) # front sight base / gas block
	_barrel(r, 0.008, 0.28, Vector3(0, 0.06, -0.42), STEEL, 0.6, 8)                        # cleaning rod
	_barrel(r, 0.017, 0.05, Vector3(0, 0.02, -0.72), DARK, 0.6, 12)                        # slant muzzle brake
	_box(r, Vector3(0.032, 0.012, 0.04), Vector3(0, 0.05, -0.04), STEEL, Vector3.ZERO, 0.5)  # rear sight leaf
	_box(r, Vector3(0.056, 0.012, 0.02), Vector3(0, -0.03, -0.31), STEEL, Vector3.ZERO, 0.5) # handguard retainer
	_box(r, Vector3(0.008, 0.012, 0.07), Vector3(0.027, 0.0, -0.12), STEEL, Vector3.ZERO, 0.6)  # selector lever
	_box(r, Vector3(0.008, 0.02, 0.012), Vector3(0.027, -0.01, -0.02), DARK)               # charging handle
	_box(r, Vector3(0.012, 0.03, 0.01), Vector3(0, -0.055, -0.1), DARK, Vector3(-10, 0, 0))   # trigger
	_box(r, Vector3(0.03, 0.01, 0.1), Vector3(0, -0.07, -0.09), STEEL, Vector3.ZERO, 0.5)  # trigger guard
	_ribs(r, 5, Vector3(0.048, 0.008, 0.05), Vector3(0, -0.07, -0.19), Vector3(0, -0.026, 0.004), POLYMER)  # magazine ribs
	_box(r, Vector3(0.05, 0.09, 0.02), Vector3(0, -0.01, 0.26), DARK)                      # buttplate
	_ribs(r, 4, Vector3(0.058, 0.004, 0.012), Vector3(0, 0.0, -0.3), Vector3(0, 0, -0.045), WOOD_DARK)  # handguard grooves
	_post(r, 0.006, 0.014, Vector3(0.03, 0.02, -0.28), STEEL, 0.6, 8)                      # sling swivel
	_muzzle(r, -0.73, 0.02)


static func _m4(r: Node3D) -> void:
	_box(r, Vector3(0.05, 0.08, 0.26), Vector3(0, 0.0, -0.13), POLYMER)                    # receiver
	_box(r, Vector3(0.04, 0.03, 0.13), Vector3(0, 0.07, -0.1), DARK)                       # carry handle base
	_box(r, Vector3(0.012, 0.025, 0.012), Vector3(0, 0.1, -0.05), DARK)                    # rear aperture
	_box(r, Vector3(0.054, 0.058, 0.3), Vector3(0, 0.0, -0.4), DARK)                       # handguard
	_barrel(r, 0.01, 0.2, Vector3(0, 0.0, -0.65), STEEL)                                   # barrel
	_box(r, Vector3(0.008, 0.05, 0.01), Vector3(0, 0.05, -0.62), DARK)                     # front sight post
	_box(r, Vector3(0.042, 0.13, 0.06), Vector3(0, -0.1, -0.17), POLYMER, Vector3(6, 0, 0)) # STANAG mag
	_box(r, Vector3(0.036, 0.1, 0.05), Vector3(0, -0.08, -0.03), POLYMER, Vector3(-18, 0, 0)) # grip
	_box(r, Vector3(0.04, 0.07, 0.24), Vector3(0, -0.005, 0.2), POLYMER)                   # collapsible stock
	_box(r, Vector3(0.044, 0.09, 0.02), Vector3(0, -0.005, 0.33), DARK)                    # butt pad
	_ribs(r, 8, Vector3(0.02, 0.012, 0.01), Vector3(0, 0.088, -0.18), Vector3(0, 0, -0.035), DARK)  # top rail teeth
	_box(r, Vector3(0.012, 0.012, 0.03), Vector3(0.028, 0.015, -0.12), DARK)               # ejection port cover
	_box(r, Vector3(0.016, 0.02, 0.016), Vector3(0.03, 0.0, -0.04), DARK)                  # forward assist
	_box(r, Vector3(0.025, 0.012, 0.03), Vector3(0, 0.1, -0.025), DARK)                    # charging handle
	_box(r, Vector3(0.012, 0.012, 0.02), Vector3(-0.028, -0.04, -0.13), DARK)              # magazine release
	_box(r, Vector3(0.012, 0.03, 0.01), Vector3(0, -0.055, -0.09), DARK, Vector3(-10, 0, 0))  # trigger
	_box(r, Vector3(0.03, 0.01, 0.09), Vector3(0, -0.07, -0.085), POLYMER)                 # trigger guard
	_ribs(r, 6, Vector3(0.058, 0.01, 0.02), Vector3(0, 0.02, -0.28), Vector3(0, 0, -0.045), STEEL, 0.5)  # handguard heat-shield slots
	_box(r, Vector3(0.03, 0.04, 0.03), Vector3(0, 0.03, -0.57), STEEL, Vector3.ZERO, 0.5)  # gas block
	_barrel(r, 0.014, 0.08, Vector3(0, 0.0, -0.74), DARK, 0.6, 8)                          # flash hider
	_barrel(r, 0.022, 0.2, Vector3(0, 0.02, 0.18), STEEL, 0.5, 8)                          # buffer tube
	_box(r, Vector3(0.036, 0.03, 0.12), Vector3(0, 0.05, 0.12), POLYMER)                   # cheek riser
	_muzzle(r, -0.76, 0.0)


static func _shotgun(r: Node3D) -> void:
	_box(r, Vector3(0.05, 0.075, 0.25), Vector3(0, 0.0, -0.125), STEEL, Vector3.ZERO, 0.5) # receiver
	_barrel(r, 0.014, 0.62, Vector3(0, 0.02, -0.56), STEEL)                                # barrel
	_barrel(r, 0.016, 0.45, Vector3(0, -0.012, -0.47), DARK)                               # magazine tube
	_box(r, Vector3(0.052, 0.05, 0.2), Vector3(0, -0.012, -0.42), WOOD)                    # pump forend
	_box(r, Vector3(0.036, 0.1, 0.05), Vector3(0, -0.075, -0.03), WOOD, Vector3(-16, 0, 0)) # grip
	_box(r, Vector3(0.048, 0.1, 0.32), Vector3(0, -0.015, 0.2), WOOD, Vector3(-6, 0, 0))   # stock
	_box(r, Vector3(0.006, 0.01, 0.01), Vector3(0, 0.048, -0.85), DARK)                    # bead sight
	_box(r, Vector3(0.03, 0.01, 0.1), Vector3(0, -0.07, -0.09), STEEL, Vector3.ZERO, 0.5)  # trigger guard
	_box(r, Vector3(0.012, 0.03, 0.01), Vector3(0, -0.055, -0.08), DARK, Vector3(-10, 0, 0))  # trigger
	_box(r, Vector3(0.012, 0.03, 0.07), Vector3(0.026, 0.01, -0.12), DARK)                 # ejection port
	_box(r, Vector3(0.05, 0.015, 0.06), Vector3(0, -0.044, -0.05), STEEL, Vector3.ZERO, 0.5) # loading port / carrier
	_post(r, 0.019, 0.02, Vector3(0, -0.012, -0.69), DARK, 0.6, 10)                        # magazine tube cap
	_barrel(r, 0.019, 0.03, Vector3(0, 0.02, -0.5), STEEL, 0.6, 10)                        # barrel band
	_ribs(r, 5, Vector3(0.054, 0.006, 0.012), Vector3(0, -0.012, -0.34), Vector3(0, 0, -0.035), WOOD_DARK)  # forend grip grooves
	_ribs(r, 4, Vector3(0.012, 0.03, 0.012), Vector3(-0.03, -0.01, 0.1), Vector3(0, 0, 0.03), DARK)  # side-saddle shells
	_box(r, Vector3(0.05, 0.11, 0.02), Vector3(0, -0.02, 0.37), DARK)                      # recoil pad
	_post(r, 0.006, 0.014, Vector3(0.03, -0.02, -0.7), STEEL, 0.6, 8)                      # sling stud
	_muzzle(r, -0.88, 0.02)


static func _hunting(r: Node3D) -> void:
	_box(r, Vector3(0.045, 0.07, 0.28), Vector3(0, 0.0, -0.14), STEEL, Vector3.ZERO, 0.5)  # receiver
	_barrel(r, 0.013, 0.7, Vector3(0, 0.015, -0.63), STEEL)                                # barrel
	_box(r, Vector3(0.05, 0.06, 0.4), Vector3(0, -0.012, -0.35), WOOD)                     # fore-stock
	_box(r, Vector3(0.04, 0.12, 0.34), Vector3(0, -0.03, 0.18), WOOD, Vector3(-8, 0, 0))   # stock
	_box(r, Vector3(0.036, 0.09, 0.05), Vector3(0, -0.065, -0.02), WOOD, Vector3(-16, 0, 0)) # grip
	_box(r, Vector3(0.02, 0.012, 0.05), Vector3(0.04, 0.02, -0.05), STEEL, Vector3.ZERO, 0.6) # bolt handle
	# scope: tube, objective, ocular, mount rings
	_barrel(r, 0.02, 0.3, Vector3(0, 0.1, -0.15), DARK)
	_barrel(r, 0.028, 0.06, Vector3(0, 0.1, -0.33), DARK)
	_barrel(r, 0.026, 0.05, Vector3(0, 0.1, 0.02), DARK)
	_box(r, Vector3(0.02, 0.03, 0.02), Vector3(0, 0.065, -0.06), STEEL)
	_box(r, Vector3(0.02, 0.03, 0.02), Vector3(0, 0.065, -0.24), STEEL)
	_post(r, 0.011, 0.02, Vector3(0.0, 0.132, -0.18), STEEL, 0.6, 10)                      # elevation turret
	_post(r, 0.011, 0.02, Vector3(0.032, 0.1, -0.18), STEEL, 0.6, 10)                      # windage turret
	var lens := _barrel(r, 0.025, 0.004, Vector3(0, 0.1, -0.362), GLASS, 0.9, 12)          # objective lens
	lens.material_override = _mat(GLASS, 0.9, 0.1)
	_barrel(r, 0.012, 0.012, Vector3(0.05, 0.026, -0.05), DARK, 0.6, 10).rotation_degrees = Vector3(0, 0, 90)  # bolt knob stem
	_post(r, 0.014, 0.014, Vector3(0.062, 0.026, -0.05), DARK, 0.6, 10)                    # bolt knob
	_box(r, Vector3(0.03, 0.012, 0.1), Vector3(0, -0.044, -0.09), STEEL, Vector3.ZERO, 0.5) # floor plate
	_box(r, Vector3(0.012, 0.03, 0.01), Vector3(0, -0.055, -0.1), DARK, Vector3(-10, 0, 0))  # trigger
	_box(r, Vector3(0.03, 0.01, 0.1), Vector3(0, -0.07, -0.1), STEEL, Vector3.ZERO, 0.5)   # trigger guard
	_barrel(r, 0.016, 0.03, Vector3(0, 0.015, -0.99), DARK, 0.6, 10)                       # muzzle crown / thread protector
	_ribs(r, 6, Vector3(0.052, 0.004, 0.012), Vector3(0, -0.012, -0.2), Vector3(0, 0, -0.045), WOOD_DARK)  # fore-stock checkering
	_box(r, Vector3(0.042, 0.13, 0.025), Vector3(0, -0.035, 0.36), DARK, Vector3(-8, 0, 0))  # recoil pad
	_box(r, Vector3(0.034, 0.03, 0.1), Vector3(0, 0.03, 0.08), WOOD, Vector3(-8, 0, 0))    # cheek rest
	_post(r, 0.006, 0.014, Vector3(0.03, -0.02, -0.5), STEEL, 0.6, 8)                      # sling stud
	_muzzle(r, -0.99, 0.015)


static func _ar(r: Node3D) -> void:
	# modern assault rifle: polymer receiver, free-float rail handguard, folding-style stock, red-dot optic
	_box(r, Vector3(0.05, 0.08, 0.28), Vector3(0, 0.0, -0.14), POLYMER)                    # upper/lower receiver
	_box(r, Vector3(0.048, 0.018, 0.28), Vector3(0, 0.049, -0.14), DARK)                   # top rail base
	_ribs(r, 9, Vector3(0.022, 0.01, 0.012), Vector3(0, 0.063, -0.03), Vector3(0, 0, -0.03), DARK)  # top rail teeth
	_box(r, Vector3(0.056, 0.062, 0.34), Vector3(0, 0.0, -0.45), DARK)                     # free-float handguard
	_ribs(r, 7, Vector3(0.06, 0.012, 0.02), Vector3(0, 0.015, -0.3), Vector3(0, 0, -0.045), STEEL, 0.5)  # handguard vent slots
	_ribs(r, 6, Vector3(0.02, 0.012, 0.012), Vector3(0, 0.043, -0.31), Vector3(0, 0, -0.045), DARK)  # handguard top rail
	_barrel(r, 0.011, 0.16, Vector3(0, 0.005, -0.7), STEEL)                                # barrel
	_barrel(r, 0.016, 0.09, Vector3(0, 0.005, -0.8), DARK, 0.6, 8)                         # flash hider
	_barrel(r, 0.018, 0.02, Vector3(0, 0.005, -0.835), STEEL, 0.6, 8)                      # hider crown
	_box(r, Vector3(0.03, 0.04, 0.03), Vector3(0, 0.025, -0.62), STEEL, Vector3.ZERO, 0.5) # gas block
	_box(r, Vector3(0.008, 0.05, 0.01), Vector3(0, 0.07, -0.64), DARK)                     # folding front sight
	_box(r, Vector3(0.042, 0.14, 0.06), Vector3(0, -0.105, -0.17), POLYMER, Vector3(5, 0, 0))  # curved 20 rd magazine
	_ribs(r, 5, Vector3(0.044, 0.008, 0.062), Vector3(0, -0.06, -0.17), Vector3(0, -0.022, 0.003), DARK)  # magazine ribs
	_box(r, Vector3(0.04, 0.012, 0.07), Vector3(0, -0.178, -0.165), DARK, Vector3(5, 0, 0))  # magazine floor plate
	_box(r, Vector3(0.036, 0.1, 0.05), Vector3(0, -0.08, -0.03), POLYMER, Vector3(-18, 0, 0))  # pistol grip
	_ribs(r, 4, Vector3(0.038, 0.006, 0.04), Vector3(0, -0.05, -0.04), Vector3(0, -0.02, 0.003), DARK)  # grip texture
	_box(r, Vector3(0.012, 0.03, 0.01), Vector3(0, -0.055, -0.09), DARK, Vector3(-10, 0, 0))  # trigger
	_box(r, Vector3(0.03, 0.01, 0.09), Vector3(0, -0.07, -0.085), POLYMER)                 # trigger guard
	_box(r, Vector3(0.012, 0.012, 0.03), Vector3(0.028, 0.015, -0.12), DARK)               # ejection port cover
	_box(r, Vector3(0.012, 0.016, 0.014), Vector3(0.028, 0.0, -0.05), DARK)                # forward assist
	_box(r, Vector3(0.026, 0.012, 0.03), Vector3(0, 0.062, -0.01), DARK)                   # charging handle
	_box(r, Vector3(0.012, 0.012, 0.02), Vector3(-0.028, -0.04, -0.13), DARK)              # magazine release
	_box(r, Vector3(0.008, 0.01, 0.03), Vector3(-0.027, 0.01, -0.03), STEEL, Vector3.ZERO, 0.6)  # selector lever
	_box(r, Vector3(0.042, 0.075, 0.22), Vector3(0, -0.005, 0.2), POLYMER, Vector3(-3, 0, 0))   # stock body
	_box(r, Vector3(0.034, 0.03, 0.14), Vector3(0, 0.05, 0.17), POLYMER)                   # cheek riser
	_barrel(r, 0.02, 0.12, Vector3(0, 0.02, 0.1), STEEL, 0.5, 8)                           # buffer tube
	_box(r, Vector3(0.046, 0.09, 0.022), Vector3(0, -0.005, 0.32), DARK)                   # butt pad
	_box(r, Vector3(0.012, 0.022, 0.06), Vector3(0.027, 0.0, 0.15), DARK)                  # stock latch/adjuster
	# red-dot optic on the top rail
	_box(r, Vector3(0.034, 0.012, 0.07), Vector3(0, 0.077, -0.12), DARK)                   # optic mount
	_box(r, Vector3(0.036, 0.04, 0.07), Vector3(0, 0.1, -0.12), DARK)                      # optic body
	var lens := _box(r, Vector3(0.026, 0.026, 0.004), Vector3(0, 0.1, -0.157), GLASS, Vector3.ZERO, 0.9)  # front lens
	lens.material_override = _mat(GLASS, 0.9, 0.1)
	_box(r, Vector3(0.004, 0.004, 0.003), Vector3(0, 0.1, -0.1575), Color(1.0, 0.1, 0.1))  # reticle dot
	_post(r, 0.006, 0.014, Vector3(0.03, -0.02, -0.28), STEEL, 0.6, 8)                     # sling swivel
	_muzzle(r, -0.845, 0.005)


static func _ar_tier(r: Node3D, tier: int) -> void:
	# workbench rifles: the base AR plus bolt-on parts that grow with the tier
	_ar(r)
	var accents: Array[Color] = [Color(0.85, 0.5, 0.15), Color(0.2, 0.5, 0.85), Color(0.8, 0.12, 0.12)]
	var accent: Color = accents[clampi(tier, 1, 3) - 1]
	_box(r, Vector3(0.052, 0.012, 0.3), Vector3(0, 0.03, -0.45), accent)                   # handguard accent stripe
	_box(r, Vector3(0.012, 0.03, 0.05), Vector3(-0.03, 0.0, -0.05), accent)                # receiver tag
	if tier >= 2:
		_box(r, Vector3(0.03, 0.1, 0.035), Vector3(0, -0.07, -0.5), POLYMER, Vector3(8, 0, 0))  # vertical foregrip
		_box(r, Vector3(0.042, 0.07, 0.06), Vector3(0, -0.205, -0.175), POLYMER, Vector3(5, 0, 0))  # extended magazine
	if tier >= 3:
		_box(r, Vector3(0.05, 0.05, 0.1), Vector3(0, -0.19, -0.2), accent)                 # magazine collar
		_barrel(r, 0.014, 0.1, Vector3(0, 0.005, -0.89), DARK, 0.6, 8)                     # long muzzle brake
		_box(r, Vector3(0.012, 0.02, 0.2), Vector3(0.032, 0.02, -0.45), STEEL, Vector3.ZERO, 0.6)  # heat shield
		var m := muzzle_of(r)
		if m != null:
			m.position.z = -0.94
