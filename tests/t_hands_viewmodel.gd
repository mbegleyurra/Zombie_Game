extends SceneTree
## First-person hands, rendered. Needs a real renderer (NOT --headless):
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --script res://tests/t_hands_viewmodel.gd
## For every WeaponDB weapon it asserts: both hands + forearms exist as meshes, the palms are inside the
## camera frustum at rest and stay on screen through a full reload, the hands really MOVE during the reload
## (sampled at several points of its duration), the reload takes WeaponData.reload_time, and the rendered frame
## contains skin-coloured pixels (so the hands are not hidden behind the gun). It also checks the third-person
## body shows arms. Screenshots land in tests/shots/hands_*.png.

const SHOT_DIR := "res://tests/shots/"
const MIN_SKIN_PIXELS := 600
const MIN_HAND_TRAVEL := 0.05   ## metres a hand must move during a reload
const SAMPLES := 40
const ON_GUN_DIST := 0.06       ## at every reload sample at least one palm must be this close to the gun's bounds
const MIN_PALM_GAP := 0.14      ## a palm is about 7 to 9 cm wide: palms closer than this read as one merged mass
const MIN_GAP_PX := 100         ## the two palms must stay at least this many pixels apart in the rendered 1280x720 frame
const MIN_IMG_GAP_PX := 12      ## in the rendered frame, a run of non-skin pixels this long must lie on the line between the two palms
const BACK_TOL := 0.003         ## after cancel a palm is back at its hold within this (the view-space clamp reads live sway, so not bit-exact)
const GRIP_HOLD_DIST := 0.08    ## the trigger palm stays this close to the grip for non-bolt styles throughout a reload
const REACH_DIST := 0.08        ## a hand must come this close to the part it works (mag well, port, bolt, charging handle)

## RAT's section-4 assertions, every anchor below measured from the pack meshes, not read from the viewmodel profile
const KNOB_REACH := 0.05        ## bolt gun: the trigger palm must come this close to the bolt knob
const MAG_HOLD_DIST := 0.05     ## rifle / pistol at 75 percent: the support palm is this close to the magazine's centre
const SHELL_TRAVEL := 0.03      ## shotgun: the support palm moves at least this far between the 25 and 75 percent samples
const BOLT_KNOB_MESH := Vector3(0.035, -0.005, -0.245)   ## sniper_rifle_001 bolt knob centre at rest (mesh: vertices with x > 0.02 span x 0.021-0.048, y -0.021-0.012, z -0.261--0.229)
const BOLT_RECEIVER := Vector3(-0.04, 0.03, -0.25)       ## sniper_rifle_001 receiver opening (mesh bins z -0.30 to -0.20, x -0.043 to 0.048, top y 0.044)
const SHELL_GATE := Vector3(0.0, -0.056, -0.13)   ## shotgun_001 loading gate, gun-local: underside of the receiver (mesh bins: y min -0.056, z -0.15 to -0.09)

## RAT QA_GATE_FINAL6 section A
const MIN_PART_TRAVEL := 0.01   ## A1: the bolt / slide / pump / charging handle / cylinder visibly moves at least this far (m)
const MAG_STEP_MAX := 0.03      ## A2: a handled magazine never jumps more than this between two samples (2.4 % apart)
const MAG_NEAR_75 := 0.035      ## A2: at 75 percent the new magazine's top is this close to its seat
const CUP_PHASE := 0.1          ## revolver: before / after this share of the reload the support hand cups the grip (palms touch by design)

## RAT QA_GATE_FINAL7 A1
const FOREND_BELOW_BORE := 0.04 ## at rest the support palm sits over a mesh section reaching at least this far below the bore (forend, not bare barrel / scope)

var fails := 0


func check(cond: bool, label: String) -> void:
	if cond:
		print("PASS  ", label)
	else:
		fails += 1
		print("FAIL  ", label)


func _initialize() -> void:
	_run()


func _frames(n: int) -> void:
	for _i in range(n):
		await process_frame


## Skin pixels: warm, low-saturation orange-tan (gun body and ground are neutral or strongly saturated).
func _skin_pixels(img: Image) -> int:
	var n := 0
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			if _is_skin(img.get_pixel(x, y)):
				n += 4
	return n


func _is_skin(c: Color) -> bool:
	var r := c.r * 255.0
	var g := c.g * 255.0
	var b := c.b * 255.0
	return r > 110.0 and r - g > 20.0 and r - g < 85.0 and g - b > 10.0 and g - b < 65.0


## Longest run of non-skin pixels on the straight line between two screen points (the visible gap between the hands).
func _gap_run(img: Image, a: Vector2, b: Vector2) -> int:
	var steps := int(a.distance_to(b))
	var best := 0
	var run := 0
	for i in range(steps + 1):
		var pt := a.lerp(b, float(i) / maxf(float(steps), 1.0))
		var x := clampi(int(pt.x), 0, img.get_width() - 1)
		var y := clampi(int(pt.y), 0, img.get_height() - 1)
		if _is_skin(img.get_pixel(x, y)):
			run = 0
		else:
			run += 1
			best = maxi(best, run)
	return best


func _palm_ok(cam: Camera3D, h: Node3D, hand: String) -> bool:
	var palm := h.get_node_or_null(hand + "/Palm") as Node3D
	if palm == null:
		return false
	var p := palm.global_position
	if cam.is_position_behind(p) or not cam.is_position_in_frustum(p):
		return false
	var s := cam.unproject_position(p)
	var vr := root.get_visible_rect().size
	return s.x > 0.0 and s.y > 0.0 and s.x < vr.x and s.y < vr.y


## Centre of the visible magazine's meshes in gun-local space; Vector3.INF when the magazine is hidden or empty.
func _mag_center(h: Node3D, gun: Node3D) -> Vector3:
	var mag := h._mag as Node3D
	if mag == null or not mag.visible:
		return Vector3.INF
	var box := AABB()
	var first := true
	for mi in mag.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null or not m.is_visible_in_tree():
			continue
		var bb := m.global_transform * m.get_aabb()
		box = bb if first else box.merge(bb)
		first = false
	return Vector3.INF if first else gun.to_local(box.get_center())


func _mesh_count(n: Node) -> int:
	return n.find_children("*", "MeshInstance3D", true, false).size() if n != null else 0


## Distance from a gun-local point to the gun's bounding box (0 when inside).
func _box_dist(p: Vector3, lo: Vector3, hi: Vector3) -> float:
	return p.distance_to(Vector3(clampf(p.x, lo.x, hi.x), clampf(p.y, lo.y, hi.y), clampf(p.z, lo.z, hi.z)))


## Flakiness fix: the controller's breathing (sin of wall-clock _time), mouse sway and kickback move the gun a
## millimetre or two by however long each frame happened to take, which flipped checks sitting at 0.079 vs 0.08.
## Pin them to zero and stop the controller so every run measures the same gun pose.
func _freeze_viewmodel(w: WeaponController, wd: WeaponData) -> void:
	w._time = 0.0
	w._sway = Vector2.ZERO
	w._mouse_rel = Vector2.ZERO
	w._kickback = 0.0
	w._update_viewmodel(0.0, wd)
	w.set_process(false)


func _shot(name: String) -> Image:
	var img := root.get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))
	img.save_png(ProjectSettings.globalize_path(SHOT_DIR + name + ".png"))
	return img


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("FAIL  this test renders: run it under xvfb-run, not --headless")
		quit(1)
		return
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	cs.shape = box
	floor_body.add_child(cs)
	floor_body.position = Vector3(0, -0.5, 0)
	root.add_child(floor_body)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(100, 100)
	ground.mesh = pm
	root.add_child(ground)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, 30, 0)
	root.add_child(light)
	# the real world has ambient light; without it every face turned away from the sun renders pure black
	var env := Environment.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.62, 0.66)
	env.ambient_light_energy = 0.9
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	player.name = "1"
	player.position = Vector3(0, 0.2, 0)
	root.add_child(player)
	await _frames(20)
	var w: WeaponController = player.weapons
	var cam: Camera3D = player.camera
	var ids: Array = WeaponDB.ids()
	check(ids.size() >= 5, "WeaponDB lists %d weapons" % ids.size())
	for id in ids:
		w.give_weapon(str(id))

	for id in ids:
		var sid := str(id)
		var wd: WeaponData = WeaponDB.get_weapon(sid)
		w.equip(w.weapon_ids().find(sid))
		await _frames(10)
		var guard := 0
		while w.state != WeaponController.State.READY and guard < 600:   ## the switch-in lowering runs on real frame time
			await process_frame
			guard += 1
		_freeze_viewmodel(w, wd)
		await _frames(3)
		var h: Node3D = w._hands
		var gun_file := str(w._gun.get_meta("blaster", "")) if w._gun != null else ""
		check(gun_file.ends_with("_001"), "[%s] held gun is an ITHappy pack model (%s), not a Kenney or primitive gun" % [sid, gun_file])
		check(h != null and is_instance_valid(h) and h.visible, "[%s] hands exist and are visible" % sid)
		if h == null:
			continue
		for part in ["Hand_R", "Hand_L", "Arm_R", "Arm_L"]:
			check(_mesh_count(h.get_node_or_null(part)) >= 3, "[%s] %s is built from meshes" % [sid, part])
		check(_palm_ok(cam, h, "Hand_R"), "[%s] right palm inside the camera frustum at rest" % sid)
		check(_palm_ok(cam, h, "Hand_L"), "[%s] left palm inside the camera frustum at rest" % sid)
		var palm := h.get_node("Hand_R/Palm") as MeshInstance3D
		check((palm.material_override as StandardMaterial3D).no_depth_test, "[%s] hands draw over the gun body" % sid)
		var img := _shot("hands_%s_rest" % sid)
		var skin := _skin_pixels(img)
		print("INFO  [%s] skin-coloured pixels at rest: %d" % [sid, skin])
		check(skin >= MIN_SKIN_PIXELS, "[%s] rendered frame shows hands (%d skin px >= %d)" % [sid, skin, MIN_SKIN_PIXELS])
		var cup: bool = h.style() == "pistol"   ## two-handed pistol cup: the support palm wraps the grip under the trigger hand
		if cup:
			var cup_d := (h.get_node("Hand_L") as Node3D).position.distance_to((h.get_node("Hand_R") as Node3D).position)
			check(cup_d <= 0.1, "[%s] support hand cups the grip at rest (palms %.3f m apart <= 0.10)" % [sid, cup_d])
		else:
			var rest_run := _gap_run(img, cam.unproject_position((h.get_node("Hand_L/Palm") as Node3D).global_position), cam.unproject_position((h.get_node("Hand_R/Palm") as Node3D).global_position))
			check(rest_run >= MIN_IMG_GAP_PX, "[%s] rendered rest frame shows a gap between the hands (%d px non-skin >= %d)" % [sid, rest_run, MIN_IMG_GAP_PX])
			# gate 7 A1: the support fist wraps the forend, not the barrel / scope ahead of it
			var lp := w._gun.to_local((h.get_node("Hand_L/Palm") as Node3D).global_position)
			var lo_y := _mesh_lo_at(w._gun, h, lp.z)
			check(lo_y <= GunMesh.MUZZLE_Y - FOREND_BELOW_BORE, "[%s] A1 rest support palm (z %.3f) sits on a section reaching below the bore (mesh low %.3f <= %.3f)" % [sid, lp.z, lo_y, GunMesh.MUZZLE_Y - FOREND_BELOW_BORE])
		# A1: the gun has a moving part to animate
		var part := h._slide as Node3D
		var part_mesh: Node3D = null
		if part != null:
			var pms := part.find_children("*", "MeshInstance3D", true, false)
			part_mesh = pms[0] as Node3D if not pms.is_empty() else null
		check(part_mesh != null, "[%s] A1 gun has a moving bolt / slide / pump / handle / cylinder mesh (%s)" % [sid, str(h._slide_kind)])
		var part_rest := gun_local(w._gun, part_mesh)

		# ---- reload: deterministic sampling through the hands' own clock
		var hl := h.get_node("Hand_L") as Node3D
		var hr := h.get_node("Hand_R") as Node3D
		var rest_l := hl.position
		var rest_r := hr.position
		var missing := mini(3, wd.mag_size) if wd.per_round_reload else wd.mag_size
		var dur: float = h.play_reload(wd, true, missing)
		h.set_process(false)   ## flakiness fix: _process advances the clock by real frame time during the screenshot awaits; only advance() below may move it
		var expect := wd.reload_time(true, missing if wd.per_round_reload else -1)
		check(absf(dur - expect) < 0.001, "[%s] reload animation lasts reload_time (%.2f s)" % [sid, dur])
		var gun: Node3D = w._gun
		var vp: Dictionary = h._p   ## the anchors the hands really use (model profile plus reload clearances)
		var ext: Dictionary = vp.get("extent", {"lo": Vector3(-0.05, -0.12, -0.5), "hi": Vector3(0.05, 0.06, 0.1)})
		var ext_lo: Vector3 = ext["lo"]
		var ext_hi: Vector3 = ext["hi"]
		# the part each hand has to reach, from the model's own anchors (gun-local metres)
		var style: String = h.style()
		var target_l: Vector3 = vp["port"] if style == "bolt" else (vp["mag_pos"] as Vector3) + (vp["grab_off"] as Vector3)
		if style == "shell":
			target_l = SHELL_GATE   ## measured from the shotgun_001 mesh, not from the profile the animation itself uses
		var target_r := Vector3.INF
		if style == "bolt":
			target_r = vp["bolt_hand"]
		var target_c := Vector3.INF   ## where the support hand works the slide / charging handle
		if style == "rifle":
			target_c = vp["charge_pos"]
		elif style == "pistol":
			target_c = vp["slide_pos"]
		var reach_c := 99.0
		var max_l := 0.0
		var max_r := 0.0
		var off_frame := 0
		var both_off := 0
		var min_gap := 99.0
		var min_px := 99999.0
		var min_img_run := 99999
		var reach_l := 99.0
		var reach_mid := 99.0   ## left palm to its target at 50 percent of the reload
		var reach_r := 99.0
		var grip_ref: Vector3 = vp["grip_r"]
		var grip_far := 0.0   ## farthest the trigger palm strays from the grip (gun-local) during the reload
		var l_q1 := Vector3.INF   ## support palm (gun-local) at about 25, 50 and 75 percent
		var l_q2 := Vector3.INF
		var l_q3 := Vector3.INF
		var mag_c := Vector3.INF  ## magazine centre (gun-local) at about 75 percent, from its meshes
		var knob_reach := 99.0    ## bolt gun: closest the trigger palm gets to the (moving) bolt knob
		var part_travel := 0.0    ## A1: farthest the moving part's mesh gets from its rest spot
		var mag_d := {}           ## A2: sample index -> distance of the visible magazine pivot from its seat
		var mag_jump := 0.0
		var last_mag := Vector3.INF
		var q1_mag := Vector3.INF ## A3: magazine centre at 25 percent
		for i in range(1, SAMPLES + 1):
			h.advance(dur / float(SAMPLES + 1))
			var prog := float(i) / float(SAMPLES + 1)
			var cup_now := cup and (prog < CUP_PHASE or prog > 1.0 - CUP_PHASE)
			if part_mesh != null:
				part_travel = maxf(part_travel, gun_local(gun, part_mesh).distance_to(part_rest))
			var mag := h._mag as Node3D
			if mag != null and mag.visible and h._mag_off != Vector3.ZERO:
				mag_d[i] = mag.position.distance_to(h._mag_rest)
				if last_mag != Vector3.INF:
					mag_jump = maxf(mag_jump, mag.position.distance_to(last_mag))
				last_mag = mag.position
			elif mag != null and mag.visible and last_mag != Vector3.INF:
				mag_jump = maxf(mag_jump, mag.position.distance_to(last_mag))   ## the seat step itself
				last_mag = Vector3.INF
			else:
				last_mag = Vector3.INF
			grip_far = maxf(grip_far, gun.to_local((h.get_node("Hand_R/Palm") as Node3D).global_position).distance_to(grip_ref))
			max_l = maxf(max_l, hl.position.distance_to(rest_l))
			max_r = maxf(max_r, hr.position.distance_to(rest_r))
			var pal := (h.get_node("Hand_L/Palm") as Node3D).global_position
			var par := (h.get_node("Hand_R/Palm") as Node3D).global_position
			var gl := gun.to_local(pal)
			var gr := gun.to_local(par)
			if i == SAMPLES / 4:
				l_q1 = gl
				q1_mag = _mag_center(h, gun)
			elif i == SAMPLES / 2:
				l_q2 = gl
			elif i == SAMPLES * 3 / 4:
				l_q3 = gl
				mag_c = _mag_center(h, gun)
			if style == "bolt":
				knob_reach = minf(knob_reach, gr.distance_to(BOLT_KNOB_MESH + Vector3(0.0, 0.0, float(h._slide_z))))
			if minf(_box_dist(gl, ext_lo, ext_hi), _box_dist(gr, ext_lo, ext_hi)) > ON_GUN_DIST:
				both_off += 1
				print("INFO  [%s] sample %d/%d: both hands off the gun (left %.3f m, right %.3f m from its bounds)" % [sid, i, SAMPLES, _box_dist(gl, ext_lo, ext_hi), _box_dist(gr, ext_lo, ext_hi)])
			if pal.distance_to(par) < MIN_PALM_GAP and not cup_now:
				print("INFO  [%s] sample %d/%d: palms %.3f m apart, left (gun-local) %s, right %s" % [sid, i, SAMPLES, pal.distance_to(par), str(gl), str(gr)])
			if not cup_now:
				min_gap = minf(min_gap, pal.distance_to(par))
				min_px = minf(min_px, cam.unproject_position(pal).distance_to(cam.unproject_position(par)))
			reach_l = minf(reach_l, gl.distance_to(target_l))
			if i == SAMPLES / 2:
				reach_mid = gl.distance_to(target_l)
			if target_r != Vector3.INF:
				reach_r = minf(reach_r, gr.distance_to(target_r))
			if target_c != Vector3.INF:
				reach_c = minf(reach_c, gl.distance_to(target_c))
			if not (_palm_ok(cam, h, "Hand_L") and _palm_ok(cam, h, "Hand_R")):
				off_frame += 1
				print("INFO  [%s] sample %d/%d off-frame: left palm px %s, right palm px %s" % [sid, i, SAMPLES, str(cam.unproject_position(pal)), str(cam.unproject_position(par))])
			if i == SAMPLES / 3 or i == SAMPLES / 2 or i == SAMPLES / 4 or i == SAMPLES * 3 / 4:
				await process_frame
				await process_frame
				var tag: String = {SAMPLES / 4: "25", SAMPLES / 3: "grab", SAMPLES / 2: "reload", SAMPLES * 3 / 4: "75"}[i]
				var rimg := _shot("hands_%s_%s" % [sid, tag])
				min_img_run = mini(min_img_run, _gap_run(rimg, cam.unproject_position(pal), cam.unproject_position(par)))
				if i == SAMPLES / 2:
					print("INFO  [%s] skin-coloured pixels mid-reload: %d" % [sid, _skin_pixels(rimg)])
		print("INFO  [%s] reload (%s): left travel %.3f m, right travel %.3f m, off-frame %d/%d, both-off-gun %d, min palm gap %.3f m, reach left %.3f m, reach right %s" % [sid, style, max_l, max_r, off_frame, SAMPLES, both_off, min_gap, reach_l, ("%.3f m" % reach_r) if target_r != Vector3.INF else "n/a"])
		check(max_l >= MIN_HAND_TRAVEL or max_r >= MIN_HAND_TRAVEL, "[%s] hands move during the reload" % sid)
		check(max_l >= MIN_HAND_TRAVEL, "[%s] off-hand goes to the magazine / shell / pump (%.3f m)" % [sid, max_l])
		check(off_frame == 0, "[%s] both palms stay on screen through the whole reload" % sid)
		check(both_off == 0, "[%s] at every reload sample a hand is on the gun (both off: %d/%d)" % [sid, both_off, SAMPLES])
		check(min_gap >= MIN_PALM_GAP, "[%s] the two hands never merge (closest palms %.3f m >= %.2f)" % [sid, min_gap, MIN_PALM_GAP])
		check(min_px >= MIN_GAP_PX, "[%s] rendered palms stay apart on screen (closest %.0f px >= %d)" % [sid, min_px, MIN_GAP_PX])
		check(min_img_run >= MIN_IMG_GAP_PX, "[%s] rendered reload frames show a gap between the hands (%d px non-skin >= %d)" % [sid, min_img_run, MIN_IMG_GAP_PX])
		if style != "bolt":
			check(grip_far <= GRIP_HOLD_DIST, "[%s] trigger hand stays on the grip through the whole reload (farthest %.3f m <= %.2f)" % [sid, grip_far, GRIP_HOLD_DIST])
		check(reach_l <= REACH_DIST, "[%s] off-hand reaches the part it works (%.3f m <= %.2f)" % [sid, reach_l, REACH_DIST])
		check(reach_mid <= REACH_DIST, "[%s] off-hand is at the mag well / port at 50 percent of the reload (%.3f m <= %.2f)" % [sid, reach_mid, REACH_DIST])
		if target_r != Vector3.INF:
			check(reach_r <= REACH_DIST, "[%s] trigger hand reaches the bolt / charging handle (%.3f m <= %.2f)" % [sid, reach_r, REACH_DIST])
		if target_c != Vector3.INF:
			check(reach_c <= REACH_DIST, "[%s] support hand reaches the slide / charging handle (%.3f m <= %.2f)" % [sid, reach_c, REACH_DIST])
		if style == "bolt":
			check(knob_reach <= KNOB_REACH, "[%s] trigger palm works the bolt knob measured from the mesh (%.3f m <= %.2f)" % [sid, knob_reach, KNOB_REACH])
			check(l_q2.distance_to(BOLT_RECEIVER) <= REACH_DIST, "[%s] support palm is at the receiver opening at 50 percent (%.3f m <= %.2f)" % [sid, l_q2.distance_to(BOLT_RECEIVER), REACH_DIST])
		if style == "rifle" or style == "pistol":
			check(mag_c != Vector3.INF, "[%s] a magazine is visible at 75 percent of the reload" % sid)
			if mag_c != Vector3.INF:
				print("INFO  [%s] 75 percent: left palm %s, magazine centre %s, right palm %s" % [sid, str(l_q3), str(mag_c), str(gun.to_local((h.get_node("Hand_R/Palm") as Node3D).global_position))])
				check(l_q3.distance_to(mag_c) <= MAG_HOLD_DIST, "[%s] support fist holds the magazine at 75 percent (%.3f m <= %.2f)" % [sid, l_q3.distance_to(mag_c), MAG_HOLD_DIST])
		if style == "shell":
			check(l_q1.distance_to(l_q3) >= SHELL_TRAVEL, "[%s] support palm travels between the 25 and 75 percent samples (%.3f m >= %.2f)" % [sid, l_q1.distance_to(l_q3), SHELL_TRAVEL])
		# ---- RAT section A
		print("INFO  [%s] A1 moving part travel %.3f m; A2 mag-from-seat %s, largest step %.3f m" % [sid, part_travel, str(_round_vals(mag_d)), mag_jump])
		check(part_travel >= MIN_PART_TRAVEL, "[%s] A1 the moving part visibly moves during the empty reload (%.3f m >= %.2f)" % [sid, part_travel, MIN_PART_TRAVEL])
		if style == "rifle" or style == "pistol":
			var i40 := int(round(0.4 * (SAMPLES + 1)))
			var i75 := SAMPLES * 3 / 4
			check(mag_d.has(i40) and mag_d.has(i75), "[%s] A2 the new magazine is in the hand from 40 to 75 percent" % sid)
			if mag_d.has(i40) and mag_d.has(i75):
				check(float(mag_d[i75]) <= MAG_NEAR_75, "[%s] A2 at 75 percent the magazine is at the well (%.3f m <= %.3f)" % [sid, mag_d[i75], MAG_NEAR_75])
				var closing := true
				for k in range(i40 + 1, i75 + 1):
					closing = closing and mag_d.has(k) and float(mag_d[k]) <= float(mag_d[k - 1]) + 0.002
				check(closing, "[%s] A2 the magazine closes on the well steadily from 40 to 75 percent" % sid)
			check(mag_jump <= MAG_STEP_MAX, "[%s] A2 the magazine never pops (largest step between samples %.3f m <= %.2f)" % [sid, mag_jump, MAG_STEP_MAX])
		if style == "rifle" or (style == "pistol" and not bool(h._revolver)):
			check(q1_mag != Vector3.INF and l_q1.distance_to(q1_mag) <= MAG_HOLD_DIST, "[%s] A3 at 25 percent the support fist is carrying a magazine (%s)" % [sid, ("%.3f m" % l_q1.distance_to(q1_mag)) if q1_mag != Vector3.INF else "no magazine"])
		h.cancel()
		var back_l := hl.position.distance_to(rest_l)
		var back_r := hr.position.distance_to(rest_r)
		check(back_l < BACK_TOL and back_r < BACK_TOL, "[%s] hands return to the hold after cancel (left off %.4f m, right off %.4f m)" % [sid, back_l, back_r])

	# ---- third person: the body is drawn and has arms
	player.set_third_person(true)
	await _frames(15)
	var model = player._model
	check(model != null, "third person: Kenney body exists")
	if model != null:
		var drawn := 0
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			if (mi as MeshInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON:
				drawn += 1
		check(drawn > 0, "third person: body meshes are drawn (%d)" % drawn)
		var skel := model.find_child("Skeleton3D", true, false) as Skeleton3D
		var arm_bones := 0
		for b in range(skel.get_bone_count()):
			var bn := skel.get_bone_name(b).to_lower()
			if "arm" in bn or "hand" in bn:
				arm_bones += 1
		check(arm_bones >= 2, "third person: skeleton has arm/hand bones (%d)" % arm_bones)
	_shot("hands_third_person")
	player.set_third_person(false)
	await _frames(5)

	print("RESULT %s (%d fails)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(1 if fails > 0 else 0)


func gun_local(gun: Node3D, n: Node3D) -> Vector3:
	return gun.to_local(n.global_position) if n != null else Vector3.ZERO


## Lowest gun-local y where the gun's own mesh surface (hands excluded) crosses the plane at `z`, from its triangles,
## so a long face with no vertex near `z` (the pump tube) still counts (INF when nothing crosses).
func _mesh_lo_at(gun: Node3D, hands: Node, z: float) -> float:
	var lo := INF
	for c in gun.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if mi.mesh == null or hands.is_ancestor_of(mi) or not mi.is_visible_in_tree():
			continue
		var xf := gun.global_transform.affine_inverse() * mi.global_transform
		var f := mi.mesh.get_faces()
		for t in range(f.size() / 3):
			for j in range(3):
				var a := xf * f[t * 3 + j]
				var b := xf * f[t * 3 + (j + 1) % 3]
				if (a.z - z) * (b.z - z) > 0.0 or is_equal_approx(a.z, b.z):
					continue
				var p := a.lerp(b, (z - a.z) / (b.z - a.z))
				if absf(p.x) < 0.06:
					lo = minf(lo, p.y)
	return lo


func _round_vals(d: Dictionary) -> Array:
	var out := []
	for k in [16, 20, 24, 30]:
		out.append(("%d:%.3f" % [k, d[k]]) if d.has(k) else "%d:-" % k)
	return out
