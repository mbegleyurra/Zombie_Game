extends RefCounted
## Reads the baked vegetation straight from its nodes: every tree, bush, rock and grass tuft under
## Vegetation/KayKitForest is its own node (an instance of scenes/world/props/vegetation/<Model>.tscn whose root carries
## meta "kind"). Moving, adding (instancing a prop scene anywhere under KayKitForest) or deleting one in the editor is
## reflected by the map, tests and tools, and there is no separate copy of the sites to go stale. Each blocking object
## carries its own collider inside its prop scene, so collision follows the node too.

const KINDS := ["tree", "bush", "rock", "grass"]


## Every vegetation node under `forest` (any depth) as an Array of Node3D. A node counts when it has meta "kind" with
## one of KINDS; its own children are not searched further (they are the prop's mesh / collider).
static func nodes(forest: Node) -> Array:
	var out: Array = []
	if forest == null:
		return out
	var stack: Array = [forest]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for ch in n.get_children():
			if ch is Node3D and KINDS.has(str(ch.get_meta("kind", ""))):
				out.append(ch)
			else:
				stack.append(ch)
	return out


## Transform of `n` in the space of `forest`'s parent (the world), computed from local transforms so it also works on a
## scene that is not inside the tree yet.
static func _xf_in(forest: Node, n: Node3D) -> Transform3D:
	var xf: Transform3D = n.transform
	var p: Node = n.get_parent()
	while p != null and p != forest:
		if p is Node3D:
			xf = (p as Node3D).transform * xf
		p = p.get_parent()
	if forest is Node3D:
		xf = (forest as Node3D).transform * xf
	return xf


## Every vegetation object as [kind, x, z] in the forest node's parent space (the world). x/z is the node origin, which
## the prop scene seats at the centre of the model's footprint.
static func sites(forest: Node) -> Array:
	var out: Array = []
	for n in nodes(forest):
		var p: Vector3 = _xf_in(forest, n).origin
		out.append([str(n.get_meta("kind")), p.x, p.z])
	return out
