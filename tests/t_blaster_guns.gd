extends SceneTree
## Kenney Blaster Kit gun skin: every WeaponDB weapon resolves to a Blaster Kit model with a valid muzzle,
## hands/reload still work on it, dropped pickups use it, and a missing kit falls back to the procedural gun. Run:
##   godot --headless --path . --script res://tests/t_blaster_guns.gd

const ItemDB = preload("res://scripts/world/item_db.gd")
const KIT := "res://assets/kenney/blaster-kit/"

var fails := 0


func check(cond: bool, label: String) -> void:
	if cond:
		print("PASS  ", label)
	else:
		fails += 1
		print("FAIL  ", label)


func _has_mesh(n: Node) -> bool:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		return true
	for c in n.get_children():
		if _has_mesh(c):
			return true
	return false


func _initialize() -> void:
	_run()


func _run() -> void:
	var ids: Array = WeaponDB.ids()
	check(ids.size() >= 9, "WeaponDB lists %d weapons" % ids.size())
	var used := {}
	for id in ids:
		var wd: WeaponData = WeaponDB.get_weapon(id)
		var tag := "%s (%s)" % [id, wd.model]
		check(GunMesh.has_blaster(wd.model), tag + " is mapped to a Blaster Kit model")
		var g: Node3D = GunMesh.build(wd.model)
		check(GunMesh.is_blaster(g), tag + " builds the Blaster Kit mesh, not the procedural fallback")
		if not GunMesh.is_blaster(g):
			g.free()
			continue
		var file: String = str(g.get_meta("blaster"))
		used[file] = true
		check(file.begins_with("blaster-") and ResourceLoader.exists(KIT + file + ".glb"), tag + " uses " + file + ".glb")
		var model := g.get_node_or_null("Model") as Node3D
		check(model != null and _has_mesh(model), tag + " has a real mesh under Model")
		var mz := GunMesh.muzzle_of(g)
		check(mz != null and mz is Marker3D, tag + " has a Muzzle Marker3D")
		if mz != null:
			var vp: Dictionary = g.get_meta("vm_profile")
			var ext: Dictionary = vp["extent"]
			var lo: Vector3 = ext["lo"]
			var hi: Vector3 = ext["hi"]
			check(mz.position.z < -0.1 and absf(mz.position.z - lo.z) < 0.001, tag + " muzzle sits at the forward (-Z) tip (z %.2f)" % mz.position.z)
			check(mz.position.y > lo.y and mz.position.y < hi.y, tag + " muzzle height is inside the model")
			check(hi.z > GunMesh.GRIP_Z, tag + " stock/receiver extends behind the grip")
			for k in ["grip_r", "grip_l", "mag_pos", "grab_off", "slide_pos", "charge_pos", "bolt_hand", "port"]:
				check(vp.has(k) and (vp[k] as Vector3).is_finite(), tag + " profile " + k)
		# hands + reload animation on the fused model
		var vm: Node3D = load("res://scripts/weapons/viewmodel.gd").attach(g, wd)
		check(vm != null and vm.name == "Hands", tag + " hands attach")
		var played: float = vm.play_reload(wd, true, 3 if wd.per_round_reload else 0)
		check(played > 0.0 and vm.is_playing(), tag + " reload starts (%.2fs, %s)" % [played, vm.style()])
		var steps := 0
		while vm.is_playing() and steps < 2000:
			vm.advance(0.05)
			steps += 1
		check(not vm.is_playing(), tag + " reload finishes")
		check(g.position.is_equal_approx(Vector3.ZERO) and g.rotation.is_equal_approx(Vector3.ZERO), tag + " gun returns to rest after reload")
		# pickup
		var pk := GunMesh.world_pickup(wd.model)
		check(pk != null and (pk.get_meta("size") as Vector3).x > (pk.get_meta("size") as Vector3).z, tag + " world pickup lies lengthwise along X")
		if pk != null:
			pk.free()
		g.free()
	check(used.size() >= 8, "the roster uses %d distinct Blaster Kit models" % used.size())

	# ---- loot item uses the blaster model
	var li: Node = load("res://scripts/world/loot_item.gd").create("weapon_ak", 1, 5)
	get_root().add_child(li)
	await process_frame   # _ready (which builds the visual) runs once the tree has started
	var vis := li.get_node_or_null("Visual")
	check(vis != null and vis.get_node_or_null("Pickup_ak") != null, "dropped AK pickup shows the Blaster Kit model")
	li.queue_free()

	# ---- graceful fallback when the kit is missing
	var old_dir: String = GunMesh.blaster_dir
	GunMesh.blaster_dir = "res://assets/__no_such_kit__/"
	GunMesh.reset_blaster_cache()
	for key in ["pistol", "ak", "shotgun", "hunting"]:
		var fg: Node3D = GunMesh.build(key)
		check(not GunMesh.is_blaster(fg) and GunMesh.muzzle_of(fg) != null, "fallback: %s builds the procedural gun with a muzzle" % key)
		fg.free()
	check(GunMesh.world_pickup("ak") == null, "fallback: no blaster pickup when the kit is missing")
	GunMesh.blaster_dir = old_dir
	GunMesh.reset_blaster_cache()
	var back: Node3D = GunMesh.build("ak")
	check(GunMesh.is_blaster(back), "kit restored: ak is a blaster again")
	back.free()

	print("---- t_blaster_guns: %d FAIL" % fails)
	quit(1 if fails > 0 else 0)
