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
	if BLASTERS.has(model) and _build_blaster(root, model):
		return root
	# fallback: the procedural primitive gun (model missing / failed to load / unknown key)
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


# ---------------------------------------------------------------- ITHappy Weapons Free skin
# Visual-only skin for every WeaponDB model key (the names BLASTERS / is_blaster / blaster_dir are kept
# from the old Kenney Blaster Kit so callers did not change; the kit itself is no longer used for guns).
# The ITHappy .glb files point down +X; they are turned MODEL_YAW about Y so they match the convention of
# the procedural guns (points down -Z, right-hand grip near z = GRIP_Z, barrel axis at y = MUZZLE_Y, a
# Marker3D "Muzzle" at the barrel tip). Hand grips, magazine and charging points are derived from the
# model's own geometry and stored on the root as meta "vm_profile" for viewmodel.gd. If the file is
# missing or fails to load, build() silently returns the procedural gun instead.
# Swapping a model = editing one BLASTERS row: file, in-hand length (m), optional magazine mesh ("clip").

## Folder of the imported pack; a static var so a test can point it at nothing to exercise the fallback.
static var blaster_dir: String = "res://assets/ithappy_weapons/Meshes/Assets/"

const GRIP_Z := -0.03        ## gun-local z of the right-hand grip (same as the procedural guns)
const MUZZLE_Y := 0.02       ## gun-local height of the barrel axis
const BLASTER_MAX_SCALE := 1.3
const MODEL_YAW := PI * 0.5  ## turns the pack's +X muzzle direction onto -Z

## model key -> pack file, in-hand length (muzzle to butt, metres) and the magazine mesh shown in reloads.
## Only four guns ship in the pack: every rifle-class key shares rifle_001, the bolt gun and the heavy
## tier-3 rifle use sniper_rifle_001, the pump shotgun uses shotgun_001. Lengths tell them apart.
## "part" = the gun's moving part (built under a "MovingPart" node, meta "kind"; viewmodel.gd animates it),
## every coordinate in the pack file's own space (+X muzzle, +Y up, +Z the gun's right side):
##   cylinder / pump : a separate pack mesh ("file") whose origin goes at "at" (pistol_001 is a revolver that ships
##                     without its drum, shotgun_001 ships without its pump forend)
##   charge / bolt   : the mesh components inside the AABB "split" are cut out of the fused gun and moved; "knob" is
##                     where the hand works them (rifle_001: the small cross bar on top of the receiver; sniper: bolt)
## "well" = top of the magazine well (rifle_001 ships without a magazine; the clip is seated there).
const RIFLE_PART := {"kind": "charge", "split": AABB(Vector3(0.448, 0.3, -0.035), Vector3(0.03, 0.028, 0.07)), "knob": Vector3(0.463, 0.314, 0.029)}
const RIFLE_WELL := Vector3(0.27, 0.19, 0.0)
const SNIPER_WELL := Vector3(0.30, 0.0, 0.0)   ## ahead of sniper_rifle_001's trigger guard (x 0.047-0.214), under the stock line
const SNIPER_PART := {"kind": "bolt", "split": AABB(Vector3(0.035, 0.04, -0.02), Vector3(0.105, 0.1, 0.16)), "knob": Vector3(0.097, 0.077, 0.101)}
const BLASTERS := {
	"pistol": {"file": "pistol_001", "len": 0.28, "clip": "", "part": {"kind": "cylinder", "file": "pistol_drum_001", "at": Vector3(0.196, 0.118, 0.0), "radius": 0.046}},
	"ak": {"file": "rifle_001", "len": 0.78, "clip": "rifle_magazine_001", "part": RIFLE_PART, "well": RIFLE_WELL},
	"m4": {"file": "rifle_001", "len": 0.86, "clip": "rifle_magazine_001", "part": RIFLE_PART, "well": RIFLE_WELL},
	"shotgun": {"file": "shotgun_001", "len": 0.84, "clip": "", "part": {"kind": "pump", "file": "shotgun_handguard_001", "at": Vector3(0.68, 0.14, 0.0)}},
	"hunting": {"file": "sniper_rifle_001", "len": 1.0, "clip": "rifle_magazine_001", "part": SNIPER_PART},
	"ar": {"file": "rifle_001", "len": 0.82, "clip": "rifle_magazine_001", "part": RIFLE_PART, "well": RIFLE_WELL},
	"ar_t1": {"file": "rifle_001", "len": 0.7, "clip": "rifle_magazine_001", "part": RIFLE_PART, "well": RIFLE_WELL},
	"ar_t2": {"file": "rifle_001", "len": 0.74, "clip": "rifle_magazine_001", "part": RIFLE_PART, "well": RIFLE_WELL},
	"ar_t3": {"file": "sniper_rifle_001", "len": 0.98, "clip": "rifle_magazine_001", "part": SNIPER_PART, "well": SNIPER_WELL},
}

static var _blaster_cache: Dictionary = {}


static func has_blaster(model: String) -> bool:
	return BLASTERS.has(model)


## True when `gun` (from build) is an ITHappy pack model rather than the procedural fallback.
static func is_blaster(gun: Node3D) -> bool:
	return gun != null and gun.has_meta("blaster")


static func reset_blaster_cache() -> void:
	_blaster_cache.clear()


## A lying-down copy for a dropped pickup: length along X, resting on y = 0, centred on x/z.
## meta "size" = bounding size. Returns null when the model is not a blaster (caller keeps its own mesh).
static func world_pickup(model: String) -> Node3D:
	var g := build(model)
	if not is_blaster(g):
		g.free()
		return null
	var vp: Dictionary = g.get_meta("vm_profile")
	var ext: Dictionary = vp["extent"]
	var lo: Vector3 = ext["lo"]
	var hi: Vector3 = ext["hi"]
	var zc := (lo.z + hi.z) * 0.5
	var basis := Basis(Vector3.UP, PI * 0.5)
	g.rotation.y = PI * 0.5
	g.position = -(basis * Vector3(0.0, lo.y, zc))
	var wrap := Node3D.new()
	wrap.name = "Pickup_" + model
	wrap.add_child(g)
	wrap.set_meta("size", Vector3(hi.z - lo.z, hi.y - lo.y, hi.x - lo.x))
	return wrap


static func _build_blaster(root: Node3D, model: String) -> bool:
	var spec: Dictionary = BLASTERS[model]
	var file: String = spec["file"]
	var info := _blaster_info(file)
	if info.is_empty():
		return false
	var ps := load(blaster_dir + file + ".glb") as PackedScene
	if ps == null:
		return false
	var inst := ps.instantiate() as Node3D
	if inst == null:
		return false
	inst.rotation.y = MODEL_YAW
	var lo: Vector3 = info["lo"]
	var hi: Vector3 = info["hi"]
	var size: Vector3 = hi - lo
	var s := minf(float(spec["len"]) / maxf(size.z, 0.01), BLASTER_MAX_SCALE)
	var off := Vector3(-float(info["cx"]) * s, MUZZLE_Y - float(info["muzzle_y"]) * s, GRIP_Z - float(info["grip_z"]) * s)
	inst.name = "Model"
	inst.scale = Vector3.ONE * s
	inst.position = off
	_no_shadow(inst)
	apply_pack_material(inst)
	root.add_child(inst)
	var mk := Marker3D.new()
	mk.name = "Muzzle"
	mk.position = Vector3(0.0, MUZZLE_Y, lo.z * s + off.z)
	root.add_child(mk)
	root.set_meta("blaster", file)

	# ---- viewmodel profile, in final gun-local metres
	var f_lo_y := lo.y * s + off.y
	var f_hi_y := hi.y * s + off.y
	var palm_y := minf(float(info["grip_ymin"]) * s + off.y + 0.06, MUZZLE_Y - 0.03)
	var xr := clampf(float(info["halfw"]) * s * 0.85, 0.0, 0.06)
	var pistol := model == "pistol"
	var p: Dictionary = {}
	p["grip_r"] = Vector3(xr, palm_y, GRIP_Z)
	if pistol:
		# Palm behind and below the slide so the slide stays visible and the fingers curl round the grip front.
		p["grip_r"] = Vector3(0.0, MUZZLE_Y - 0.085, GRIP_Z + 0.035)
		p["grip_l"] = Vector3(-0.02, MUZZLE_Y - 0.1, GRIP_Z + 0.01)
	else:
		var fz := float(info["fore_z"]) * s + off.z
		p["grip_l"] = Vector3(0.0, float(info["fore_under"]) * s + off.y - 0.012, fz)
	var mag_top := lerpf(f_lo_y, MUZZLE_Y, 0.55)
	var hang := maxf(mag_top - (float(info["mag_ymin"]) * s + off.y), 0.05)
	p["mag_pos"] = Vector3(0.0, mag_top, float(info["mag_z"]) * s + off.z)
	if spec.has("well"):
		p["mag_pos"] = inst.transform * (spec["well"] as Vector3)
		p["clip_seated"] = true   ## the clip IS the gun's magazine: shown in the well at rest, not only while handled
	p["grab_off"] = Vector3(0.0, -hang * 0.7, 0.0)
	var clip_file: String = str(spec.get("clip", ""))
	var cinfo := _blaster_info(clip_file) if clip_file != "" else {}
	if not cinfo.is_empty():
		var clo: Vector3 = cinfo["lo"]
		var chi: Vector3 = cinfo["hi"]
		p["clip_file"] = clip_file
		p["clip_h"] = chi.y                  ## top of the clip above its origin: the proxy hangs from it
		p["clip_yaw"] = MODEL_YAW
		p["clip_scale"] = hang / maxf(chi.y - clo.y, 0.01)
	p["slide_pos"] = Vector3(0.0, MUZZLE_Y + 0.035, GRIP_Z - 0.02)
	p["charge_pos"] = Vector3(0.0, f_hi_y + 0.02, GRIP_Z - 0.03)
	p["port"] = Vector3(0.0, lerpf(f_lo_y, MUZZLE_Y, 0.45), GRIP_Z - 0.06)
	p["bolt_hand"] = Vector3(xr + 0.05, MUZZLE_Y + 0.02, GRIP_Z - 0.03)
	if model == "hunting":
		p["port"] = Vector3(0.0, MUZZLE_Y + 0.05, GRIP_Z - 0.1)
	var part: Dictionary = spec.get("part", {})
	if not part.is_empty():
		var handle := _build_moving_part(root, inst, part, s)
		if handle != Vector3.INF:
			p["handle"] = handle   ## gun-local point the support hand works (charging handle, bolt knob, cylinder, pump)
			if part["kind"] == "cylinder":
				p["revolver"] = true
				p["cyl_radius"] = float(part["radius"]) * s
	p["extent"] = {
		"lo": Vector3(-size.x * s * 0.5, f_lo_y, lo.z * s + off.z),
		"hi": Vector3(size.x * s * 0.5, f_hi_y, hi.z * s + off.z),
	}
	root.set_meta("vm_profile", p)
	return true


## Builds the gun's moving part under a "MovingPart" node of `root` (gun-local) and returns the gun-local point a
## hand works it at (Vector3.INF when nothing was built). A cylinder's node sits on the crane axis below the drum,
## so rotating it about Z swings the drum out to the left; every other part slides along Z.
static func _build_moving_part(root: Node3D, inst: Node3D, part: Dictionary, s: float) -> Vector3:
	var kind: String = part["kind"]
	var ixf := inst.transform   ## pack-file space -> gun-local (yaw, scale, offset)
	var pivot := Node3D.new()
	pivot.name = "MovingPart"
	pivot.set_meta("kind", kind)
	var handle := Vector3.INF
	match kind:
		"cylinder", "pump":
			var path := blaster_dir + str(part["file"]) + ".glb"
			var ps := load(path) as PackedScene if ResourceLoader.exists(path) else null
			var mesh := ps.instantiate() as Node3D if ps != null else null
			if mesh == null:
				pivot.free()
				return Vector3.INF
			var at_g := ixf * (part["at"] as Vector3)
			if kind == "cylinder":
				pivot.position = at_g - Vector3(0.0, float(part["radius"]) * s, 0.0)
			mesh.name = "Drum" if kind == "cylinder" else "Pump"
			mesh.transform = Transform3D(ixf.basis, at_g - pivot.position)
			_no_shadow(mesh)
			apply_pack_material(mesh)
			pivot.add_child(mesh)
			handle = at_g
		"charge", "bolt":
			var moved := _split_out(inst, part["split"])
			if moved == null:
				pivot.free()
				return Vector3.INF
			moved.name = "Bolt" if kind == "bolt" else "ChargingHandle"
			moved.transform = ixf * moved.transform
			pivot.add_child(moved)
			handle = ixf * (part["knob"] as Vector3)
	root.add_child(pivot)
	return handle


static var _split_cache: Dictionary = {}


## Cuts the connected mesh components of `inst` whose bounds lie inside `box` (pack-file space) out of the fused
## model and returns them as a new MeshInstance3D (transform relative to `inst`), or null when none match.
static func _split_out(inst: Node3D, box: AABB) -> MeshInstance3D:
	for c in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if mi.mesh == null or mi.mesh.get_surface_count() != 1:
			continue
		var key := "%d_%s" % [mi.mesh.get_instance_id(), str(box)]
		if not _split_cache.has(key):
			var pr := _split_mesh(mi.mesh, _rel_xf(inst, mi), box)
			# both halves are the pack's own geometry (the source mesh may be a runtime UV-fixed copy without a path):
			# record the .glb as their provenance on a unique sub-path, so asset scans tell them from procedural meshes
			var src_path := inst.scene_file_path
			if not pr.is_empty() and src_path.ends_with(".glb"):
				for half in pr:
					(half as Mesh).resource_path = "%s::split_%d" % [src_path, (half as Mesh).get_instance_id()]
			_split_cache[key] = pr
		var pair: Array = _split_cache[key]
		if pair.is_empty():
			continue
		mi.mesh = pair[0]
		var out := MeshInstance3D.new()
		out.mesh = pair[1]
		out.material_override = mi.material_override
		out.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		out.transform = _rel_xf(inst, mi)
		return out
	return null


static func _rel_xf(top: Node3D, n: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != top:
		xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


## [kept mesh, cut mesh] split by connected component (vertices joined by position), [] when nothing is in `box`.
static func _split_mesh(src: Mesh, xf: Transform3D, box: AABB) -> Array:
	var arr := src.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if idx.is_empty():
		for i in range(v.size()):
			idx.append(i)
	var ids := {}
	var par := PackedInt32Array()
	var vid := PackedInt32Array()
	for p in v:
		var k := (p * 10000.0).round()
		if not ids.has(k):
			ids[k] = par.size()
			par.append(par.size())
		vid.append(ids[k])
	for t in range(idx.size() / 3):
		var a := _uf_root(par, vid[idx[t * 3]])
		for j in range(1, 3):
			var b := _uf_root(par, vid[idx[t * 3 + j]])
			if a != b:
				par[b] = a
	var bounds := {}
	for i in range(v.size()):
		var r := _uf_root(par, vid[i])
		var w := xf * v[i]
		bounds[r] = (bounds[r] as AABB).expand(w) if bounds.has(r) else AABB(w, Vector3.ZERO)
	var keep := PackedInt32Array()
	var cut := PackedInt32Array()
	for t in range(idx.size() / 3):
		var inside := box.encloses(bounds[_uf_root(par, vid[idx[t * 3]])])
		for j in range(3):
			if inside:
				cut.append(idx[t * 3 + j])
			else:
				keep.append(idx[t * 3 + j])
	if cut.is_empty():
		return []
	var a_keep := arr.duplicate()
	a_keep[Mesh.ARRAY_INDEX] = keep
	var a_cut := arr.duplicate()
	a_cut[Mesh.ARRAY_INDEX] = cut
	var m_keep := ArrayMesh.new()
	m_keep.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a_keep)
	var m_cut := ArrayMesh.new()
	m_cut.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a_cut)
	return [m_keep, m_cut]


static func _uf_root(par: PackedInt32Array, x: int) -> int:
	while par[x] != x:
		x = par[x]
	return x


## The pack's .glb files embed a plain untextured grey material (it renders as white blobs); the real colours
## live in the atlas that WeaponsMaterial.tres wraps. Every pack mesh (gun and magazine) gets that material.
const PACK_MATERIAL := "res://assets/ithappy_weapons/Materials/WeaponsMaterial.tres"
static var _pack_mat: Material


static func apply_pack_material(n: Node) -> void:
	if _pack_mat == null and ResourceLoader.exists(PACK_MATERIAL):
		var base := load(PACK_MATERIAL) as StandardMaterial3D
		if base != null:
			# Runtime copy so the pack's .tres stays untouched: matte, low specular, so the flat-shaded
			# pack meshes do not blow out to white under a directional light.
			_pack_mat = base.duplicate() as StandardMaterial3D
			(_pack_mat as StandardMaterial3D).roughness = 0.85
			(_pack_mat as StandardMaterial3D).metallic_specular = 0.2
			(_pack_mat as StandardMaterial3D).albedo_color = Color(0.82, 0.82, 0.82)
	if _pack_mat == null:
		return
	var mi := n as MeshInstance3D
	if mi != null:
		_darken_bright_uvs(mi)
		mi.material_override = _pack_mat
	for c in n.get_children():
		apply_pack_material(c)


const PACK_TEX := "res://assets/ithappy_weapons/Textures/Demonstration_Texture_1.png"
static var _atlas: Image
static var _fixed_meshes: Dictionary = {}


static func _atlas_image() -> Image:
	if _atlas == null:
		var t := load(PACK_TEX) as Texture2D
		if t != null:
			_atlas = t.get_image()
			if _atlas != null and _atlas.is_compressed():
				_atlas.decompress()
	return _atlas


static func _atlas_px(img: Image, uv: Vector2) -> Color:
	return img.get_pixel(clampi(int(uv.x * img.get_width()), 0, img.get_width() - 1), clampi(int(uv.y * img.get_height()), 0, img.get_height() - 1))


## Some pack surfaces (AK top cover, sniper bolt and rail, shotgun trim) are UV-mapped to the atlas' white
## cells and render as blown-out white. Vertices that sample near-white are moved to the darkest cell the same
## mesh already uses, so the shape keeps its detail and the colour matches the rest of the gun.
static func _darken_bright_uvs(mi: MeshInstance3D) -> void:
	var src := mi.mesh
	if src == null:
		return
	var key := src.get_instance_id()
	if _fixed_meshes.has(key):
		mi.mesh = _fixed_meshes[key]
		return
	var img := _atlas_image()
	if img == null:
		return
	var out := ArrayMesh.new()
	var changed := false
	for si in range(src.get_surface_count()):
		var arr := src.surface_get_arrays(si)
		if arr[Mesh.ARRAY_TEX_UV] != null:
			var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
			var dark_uv := Vector2(0.88, 0.3)   # mid-grey steel cell, used when the mesh has nothing darker
			var best := 0.5
			for u in uv:
				var c := _atlas_px(img, u)
				var lum := (c.r + c.g + c.b) / 3.0
				if lum < best:
					best = lum
					dark_uv = u
			for i in range(uv.size()):
				var c2 := _atlas_px(img, uv[i])
				if c2.r > 0.8 and c2.g > 0.8 and c2.b > 0.75:
					uv[i] = dark_uv
					changed = true
			arr[Mesh.ARRAY_TEX_UV] = uv
		out.add_surface_from_arrays(src.surface_get_primitive_type(si), arr)
	var result: Mesh = out if changed else src
	_fixed_meshes[key] = result
	mi.mesh = result


static func _no_shadow(n: Node) -> void:
	var gi := n as GeometryInstance3D
	if gi != null:
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in n.get_children():
		_no_shadow(c)


static func _collect_verts(n: Node, xf: Transform3D, out: PackedVector3Array) -> void:
	var t := xf
	if n is Node3D:
		t = xf * (n as Node3D).transform
	var mi := n as MeshInstance3D
	if mi != null and mi.mesh != null:
		for si in range(mi.mesh.get_surface_count()):
			var arr := mi.mesh.surface_get_arrays(si)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			for v in vs:
				out.append(t * v)
	for c in n.get_children():
		_collect_verts(c, t, out)


## Cached geometry analysis of one kit .glb in its native units ({} when it cannot be loaded).
static func _blaster_info(file: String) -> Dictionary:
	var key := blaster_dir + file
	if _blaster_cache.has(key):
		return _blaster_cache[key]
	var info: Dictionary = {}
	var path := blaster_dir + file + ".glb"
	if ResourceLoader.exists(path):
		var ps := load(path) as PackedScene
		if ps != null:
			var inst := ps.instantiate() as Node3D
			if inst != null:
				var vs := PackedVector3Array()
				_collect_verts(inst, Transform3D(Basis(Vector3.UP, MODEL_YAW), Vector3.ZERO), vs)
				inst.free()
				if vs.size() >= 12:
					info = _analyze(vs)
	_blaster_cache[key] = info
	return info


## Finds the barrel axis, the rear grip and the magazine from the shape: the magazine is the lowest-hanging
## lump, the grip is the rearmost low lump behind it (the stock end is ignored). Native units, muzzle at -Z.
static func _analyze(vs: PackedVector3Array) -> Dictionary:
	var lo := vs[0]
	var hi := vs[0]
	for v in vs:
		lo = Vector3(minf(lo.x, v.x), minf(lo.y, v.y), minf(lo.z, v.z))
		hi = Vector3(maxf(hi.x, v.x), maxf(hi.y, v.y), maxf(hi.z, v.z))
	var size := hi - lo
	var my_lo := 1e9
	var my_hi := -1e9
	for v in vs:
		if v.z < lo.z + size.z * 0.05:
			my_lo = minf(my_lo, v.y)
			my_hi = maxf(my_hi, v.y)
	var muzzle_y := (my_lo + my_hi) * 0.5 if my_lo < 1e8 else lo.y + size.y * 0.6
	# bin the low-hanging vertices along z
	var bin := 0.02
	var nb := int(size.z / bin) + 1
	var bmin := PackedFloat32Array()
	bmin.resize(nb)
	bmin.fill(1e9)
	var bcnt := PackedInt32Array()
	bcnt.resize(nb)
	var low_y := lo.y + size.y * 0.4
	for v in vs:
		if v.y < low_y:
			var bi := clampi(int((v.z - lo.z) / bin), 0, nb - 1)
			bmin[bi] = minf(bmin[bi], v.y)
			bcnt[bi] += 1
	for b in range(nb):
		var bz := lo.z + (float(b) + 0.5) * bin
		if bz < lo.z + size.z * 0.06 or bz > lo.z + size.z * 0.88:
			bcnt[b] = 0
	var clusters: Array = []
	var i := 0
	while i < nb:
		if bcnt[i] == 0:
			i += 1
			continue
		var last := i
		var j := i
		while j < nb and j - last <= 2:
			if bcnt[j] > 0:
				last = j
			j += 1
		var cn := 0
		var zsum := 0.0
		var ymin := 1e9
		for b in range(i, last + 1):
			cn += bcnt[b]
			zsum += (lo.z + (float(b) + 0.5) * bin) * float(bcnt[b])
			ymin = minf(ymin, bmin[b])
		clusters.append({"z": zsum / float(cn), "ymin": ymin})
		i = last + 1
	var mag_z := lo.z + size.z * 0.5
	var mag_ymin := lo.y
	var grip_z := lo.z + size.z * 0.6
	var grip_ymin := lo.y
	if not clusters.is_empty():
		var mc: Dictionary = clusters[0]
		for c in clusters:
			if float((c as Dictionary)["ymin"]) < float(mc["ymin"]) - 0.005:
				mc = c
		mag_z = float(mc["z"])
		mag_ymin = float(mc["ymin"])
		grip_z = mag_z
		grip_ymin = mag_ymin
		for c in clusters:
			var cd := c as Dictionary
			if float(cd["z"]) > mag_z + 0.04 and float(cd["ymin"]) < lo.y + size.y * 0.3:
				grip_z = float(cd["z"])
				grip_ymin = float(cd["ymin"])
	var cx := (lo.x + hi.x) * 0.5
	var halfw := 0.0
	# front hand: ahead of the magazine (not on its bottom), but not past the muzzle end
	var fore_z := minf(lerpf(grip_z, lo.z, 0.55), mag_z - 0.07)
	fore_z = maxf(fore_z, lo.z + size.z * 0.12)
	var fore_under := 1e9
	for v in vs:
		if absf(v.z - grip_z) < 0.04:
			halfw = maxf(halfw, absf(v.x - cx))
		if absf(v.z - fore_z) < 0.03:
			fore_under = minf(fore_under, v.y)
	if fore_under > 1e8:
		fore_under = muzzle_y - 0.06
	return {
		"lo": lo, "hi": hi, "cx": cx, "muzzle_y": muzzle_y,
		"mag_z": mag_z, "mag_ymin": mag_ymin, "grip_z": grip_z, "grip_ymin": grip_ymin,
		"halfw": halfw, "fore_z": fore_z, "fore_under": fore_under,
	}


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
