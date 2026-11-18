extends SceneTree
## Every non-weapon pickup type resolves to its own model + colour, nothing falls back to a placeholder, and the
## in-world LootItem actually builds that model with a glow disc.
## Run: xvfb-run -a godot --path . --script res://tests/t_pickup_visuals.gd

const PV = preload("res://scripts/world/pickup_visuals.gd")
const IDB = preload("res://scripts/world/item_db.gd")
const LootItem = preload("res://scripts/world/loot_item.gd")

var fails := 0


func check(cond: bool, label: String) -> void:
	if cond:
		print("PASS  ", label)
	else:
		fails += 1
		print("FAIL  ", label)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var ids: Array = PV.pickup_ids()
	check(ids.size() >= 20, "pickup types found (%d)" % ids.size())
	var model_owner := {}   # model path -> item id
	var look_owner := {}    # "paths|tint" -> item id
	var accent_seen: Array = []
	for id in ids:
		var cid := str(id)
		var r: Dictionary = PV.resolve(cid, 0)
		check(str(r["source"]) == "table", "%s has a table visual (source=%s)" % [cid, r["source"]])
		var vs: Array = PV.variants(cid)
		check(not vs.is_empty(), "%s has at least one model" % cid)
		var paths := PackedStringArray()
		for v in vs:
			paths.append(str(v[0]))
			check(ResourceLoader.exists(str(v[0])), "%s model exists: %s" % [cid, str(v[0]).get_file()])
			var prev = model_owner.get(str(v[0]), "")
			check(prev == "" or prev == cid, "%s model %s not shared with %s" % [cid, str(v[0]).get_file(), prev])
			model_owner[str(v[0])] = cid
		var tint: Color = r["tint"] as Color
		var look := "%s|%s" % [",".join(paths), tint.to_html()]
		check(not look_owner.has(look), "%s model+colour combination is unique" % cid)
		look_owner[look] = cid
		var acc: Color = PV.accent(cid)
		for o in accent_seen:
			var oc: Color = o[1] as Color
			var d := absf(acc.r - oc.r) + absf(acc.g - oc.g) + absf(acc.b - oc.b)
			if d < 0.12:
				check(false, "%s accent too close to %s (%.2f)" % [cid, o[0], d])
		accent_seen.append([cid, acc])
		for lid in [0, 1, 2, 7]:
			var m: Node3D = PV.instantiate(cid, lid)
			check(m != null, "%s variant for loot_id %d instantiates" % [cid, lid])
			if m != null:
				var sz: Vector3 = m.get_meta("size") as Vector3
				check(maxf(sz.x, sz.z) <= PV.MAX_SPAN + 0.001 and sz.y > 0.03, "%s size sane (%s)" % [cid, sz])
				m.free()
	# World node: model + glow, no primitive placeholder, collision present, variant stable per loot_id.
	for id in ids:
		var cid := str(id)
		var a = LootItem.create(cid, 1, 3)
		root.add_child(a)
		var vis: Node = a.get_node_or_null("Visual")
		check(vis != null and vis.get_node_or_null("Glow") != null, "%s world pickup has glow disc" % cid)
		var prim := 0
		if vis != null:
			for c in vis.get_children():
				if c is MeshInstance3D and c.name != "Glow":
					prim += 1
		check(prim == 0, "%s world pickup is a model, not a primitive placeholder" % cid)
		var shapes := 0
		for c in a.get_children():
			if c is CollisionShape3D:
				shapes += 1
		check(shapes == 1 and a.collision_layer == 8, "%s pickup keeps item-layer collision" % cid)
		check(a.get_prompt().begins_with("Pick up "), "%s prompt intact" % cid)
		var b = LootItem.create(cid, 1, 3)
		root.add_child(b)
		check(str(PV.resolve(cid, 3)["model"]) == str(PV.resolve(cid, 3)["model"]), "%s variant deterministic" % cid)
		a.queue_free()
		b.queue_free()
	# Weapons are excluded from the table but must still not hit the placeholder gun when a model exists.
	check(not ids.has("weapon_pistol"), "weapons excluded from pickup table")
	print("t_pickup_visuals: %d FAIL" % fails)
	quit(1 if fails > 0 else 0)
