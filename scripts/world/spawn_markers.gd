extends RefCounted
## Reads the baked spawn markers (scenes/world/baked/markers.tscn) as the row layout the spawners have always used:
## [x, z, yaw, roll, variant_seed], ordered by the marker's meta "index" (the original authored order).
##   "ZOMBIE_SPAWNS"   -> group "zombie_spawn"
##   "SKELETON_SPAWNS" -> group "skeleton_spawn"
## Live markers in the tree win (so editor edits to a loaded world apply). With no world loaded (headless tests on a
## test floor) the same markers are read from the packed scene's SceneState, without instancing it. Either way every
## peer reads the same baked data. Zombies themselves still spawn at runtime.

const MARKERS_SCENE := "res://scenes/world/baked/markers.tscn"
const GROUPS := {"ZOMBIE_SPAWNS": "zombie_spawn", "SKELETON_SPAWNS": "skeleton_spawn"}

static var _file_rows: Dictionary = {}   # section -> rows read from MARKERS_SCENE (cached)


static func rows(tree: SceneTree, section: String) -> Array:
	if not GROUPS.has(section):
		return []
	var live := _live_rows(tree, str(GROUPS[section]))
	return live if not live.is_empty() else file_rows(section)


static func _live_rows(tree: SceneTree, group: String) -> Array:
	var ms: Array = []
	if tree != null:
		for n in tree.get_nodes_in_group(group):
			if n is Node3D and (n as Node3D).is_inside_tree():
				ms.append(n)
	ms.sort_custom(func(a, b): return int(a.get_meta("index", 0)) < int(b.get_meta("index", 0)))
	var out: Array = []
	for m in ms:
		var mk := m as Node3D
		var p := mk.global_position
		out.append([p.x, p.z, mk.global_rotation.y, float(mk.get_meta("roll", 0.5)), int(mk.get_meta("variant_seed", 1))])
	return out


## Rows straight from the baked markers scene file (transforms composed down the saved hierarchy).
static func file_rows(section: String) -> Array:
	if _file_rows.has(section):
		return _file_rows[section]
	var out: Array = []
	var packed := load(MARKERS_SCENE) as PackedScene
	if packed == null:
		return out
	var st := packed.get_state()
	var group := StringName(str(GROUPS[section]))
	var xf := {}   # node path -> global transform (scene root at the origin, as in world_baked.tscn)
	var found: Array = []   # [index, Transform3D, meta]
	for i in st.get_node_count():
		var local := Transform3D.IDENTITY
		var meta := {}
		for k in st.get_node_property_count(i):
			var pn: String = st.get_node_property_name(i, k)
			if pn == "transform":
				local = st.get_node_property_value(i, k)
			elif pn.begins_with("metadata/"):
				meta[pn.substr(9)] = st.get_node_property_value(i, k)
		var path := st.get_node_path(i)
		var parent := st.get_node_path(i, true)
		var g: Transform3D = (xf.get(parent, Transform3D.IDENTITY) as Transform3D) * local if i > 0 else local
		xf[path] = g
		if group in st.get_node_groups(i):
			found.append([int(meta.get("index", found.size())), g, meta])
	found.sort_custom(func(a, b): return int(a[0]) < int(b[0]))
	for f in found:
		var g: Transform3D = f[1]
		var meta: Dictionary = f[2]
		out.append([g.origin.x, g.origin.z, g.basis.get_euler().y, float(meta.get("roll", 0.5)), int(meta.get("variant_seed", 1))])
	_file_rows[section] = out
	return out
