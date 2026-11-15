class_name WeaponDB
extends RefCounted
## Static registry of every firearm. Real-world references in comments;
## numbers are tuned for a 100 hp zombie, not copied from energy tables.

static var _cache: Dictionary = {}


static func ids() -> Array:
	_ensure()
	return _cache.keys()


static func has_weapon(id: String) -> bool:
	_ensure()
	return _cache.has(id)


static func get_weapon(id: String) -> WeaponData:
	_ensure()
	return _cache.get(id, null)


## Spec sheet for every gun: {id: WeaponData.inspect() dictionary}.
static func inspect_all() -> Dictionary:
	_ensure()
	var out: Dictionary = {}
	for k in _cache.keys():
		out[k] = (_cache[k] as WeaponData).inspect()
	return out


static func _ensure() -> void:
	if not _cache.is_empty():
		return
	_cache["pistol"] = _pistol()
	_cache["ak"] = _ak()
	_cache["m4"] = _m4()
	_cache["shotgun"] = _shotgun()
	_cache["hunting"] = _hunting()


static func _pistol() -> WeaponData:
	# 9x19mm, Glock-style: 15 round mag, ~370 m/s, semi-auto.
	var w := WeaponData.new()
	w.id = "pistol"
	w.display_name = "9mm Pistol"
	w.caliber = "9mm"
	w.model = "pistol"
	w.damage = 27.0
	w.headshot_mult = 3.0
	w.penetration = 0.5
	w.max_penetrations = 1
	w.falloff_start = 20.0
	w.falloff_end = 90.0
	w.min_damage_frac = 0.45
	w.muzzle_velocity = 370.0
	w.mag_size = 15
	w.fire_rate_rpm = 380.0
	w.automatic = false
	w.reload_tactical = 1.6
	w.reload_empty = 2.1
	w.spread_deg = 1.1
	w.move_spread_deg = 2.2
	w.bloom_per_shot = 0.35
	w.recoil_pitch = 1.3
	w.recoil_yaw = 0.5
	# snappy muzzle flip that stacks a little, with slight alternating yaw
	w.recoil_pattern = PackedVector2Array([
		Vector2(0.0, 1.7), Vector2(0.25, 1.5), Vector2(-0.3, 1.4), Vector2(0.2, 1.3),
	])
	w.zero_range = 25.0
	w.recoil_recovery = 9.0
	w.sway = 0.8
	w.ads_fov = 62.0
	w.ads_time = 0.12
	w.sight_height = 0.07
	w.noise_radius = 45.0
	w.weight = 0.9
	return w


static func _ak() -> WeaponData:
	# 7.62x39mm AK-style: 30 rd mag, ~715 m/s, full auto, hard climbing recoil.
	var w := WeaponData.new()
	w.id = "ak"
	w.display_name = "AK-47"
	w.caliber = "762"
	w.model = "ak"
	w.damage = 42.0
	w.headshot_mult = 3.5
	w.penetration = 0.65
	w.max_penetrations = 2
	w.falloff_start = 60.0
	w.falloff_end = 220.0
	w.min_damage_frac = 0.6
	w.muzzle_velocity = 715.0
	w.mag_size = 30
	w.fire_rate_rpm = 600.0
	w.automatic = true
	w.reload_tactical = 2.3
	w.reload_empty = 3.0
	w.spread_deg = 1.6
	w.move_spread_deg = 3.0
	w.bloom_per_shot = 0.22
	w.recoil_pitch = 1.1
	w.recoil_yaw = 0.8
	w.recoil_pattern = PackedVector2Array([
		Vector2(0.0, 1.9), Vector2(0.1, 1.6), Vector2(-0.1, 1.4), Vector2(0.3, 1.2),
		Vector2(0.5, 1.0), Vector2(0.6, 0.9), Vector2(0.3, 0.8), Vector2(-0.4, 0.8),
		Vector2(-0.7, 0.7), Vector2(-0.5, 0.7), Vector2(0.2, 0.6),
	])
	w.zero_range = 100.0
	w.recoil_recovery = 7.0
	w.sway = 1.2
	w.ads_fov = 56.0
	w.ads_time = 0.2
	w.sight_height = 0.085
	w.noise_radius = 90.0
	w.weight = 3.6
	return w


static func _m4() -> WeaponData:
	# 5.56x45mm M4-style: 30 rd mag, ~880 m/s (carbine), full auto, flatter recoil.
	var w := WeaponData.new()
	w.id = "m4"
	w.display_name = "M4 Carbine"
	w.caliber = "556"
	w.model = "m4"
	w.damage = 34.0
	w.headshot_mult = 3.5
	w.penetration = 0.6
	w.max_penetrations = 2
	w.falloff_start = 70.0
	w.falloff_end = 250.0
	w.min_damage_frac = 0.6
	w.muzzle_velocity = 880.0
	w.mag_size = 30
	w.fire_rate_rpm = 750.0
	w.automatic = true
	w.reload_tactical = 2.0
	w.reload_empty = 2.7
	w.spread_deg = 1.2
	w.move_spread_deg = 2.6
	w.bloom_per_shot = 0.15
	w.recoil_pitch = 0.9
	w.recoil_yaw = 0.45
	w.recoil_pattern = PackedVector2Array([
		Vector2(0.0, 1.3), Vector2(0.05, 1.1), Vector2(-0.1, 0.95), Vector2(0.2, 0.85),
		Vector2(0.3, 0.75), Vector2(0.25, 0.7), Vector2(-0.2, 0.65), Vector2(-0.35, 0.6),
	])
	w.zero_range = 100.0
	w.recoil_recovery = 9.0
	w.sway = 1.0
	w.ads_fov = 54.0
	w.ads_time = 0.17
	w.sight_height = 0.09
	w.noise_radius = 85.0
	w.weight = 3.2
	return w


static func _shotgun() -> WeaponData:
	# 12 gauge pump, 00 buckshot: 8 pellets, ~400 m/s, tube of 6 + 1 chambered.
	var w := WeaponData.new()
	w.id = "shotgun"
	w.display_name = "Pump Shotgun"
	w.caliber = "12ga"
	w.model = "shotgun"
	w.damage = 13.0           # per pellet
	w.pellets = 8
	w.headshot_mult = 2.0
	w.penetration = 0.25
	w.max_penetrations = 1
	w.falloff_start = 8.0
	w.falloff_end = 40.0
	w.min_damage_frac = 0.1
	w.max_range = 80.0
	w.muzzle_velocity = 400.0
	w.mag_size = 6
	w.fire_rate_rpm = 72.0    # pump cycle
	w.automatic = false
	w.per_round_reload = true
	w.round_time = 0.6
	w.chamber_time = 0.55
	w.reload_tactical = 0.6
	w.reload_empty = 0.6
	w.spread_deg = 3.8
	w.ads_spread_mult = 0.75
	w.move_spread_deg = 1.5
	w.bloom_per_shot = 0.0
	w.recoil_pitch = 6.0
	w.recoil_yaw = 1.2
	# one heavy kick per pump cycle, drifting right
	w.recoil_pattern = PackedVector2Array([Vector2(0.45, 6.2)])
	w.zero_range = 30.0
	w.recoil_recovery = 8.0
	w.sway = 1.1
	w.ads_fov = 64.0
	w.ads_time = 0.2
	w.sight_height = 0.075
	w.noise_radius = 100.0
	w.weight = 3.4
	return w


static func _hunting() -> WeaponData:
	# 7.62x51mm bolt-action hunting rifle with scope: 5 rd, ~850 m/s.
	var w := WeaponData.new()
	w.id = "hunting"
	w.display_name = "Hunting Rifle"
	w.caliber = "762"
	w.model = "hunting"
	w.damage = 95.0
	w.headshot_mult = 4.0
	w.penetration = 0.8
	w.max_penetrations = 3
	w.falloff_start = 200.0
	w.falloff_end = 600.0
	w.min_damage_frac = 0.7
	w.max_range = 600.0
	w.muzzle_velocity = 850.0
	w.mag_size = 5
	w.fire_rate_rpm = 48.0    # bolt cycle
	w.automatic = false
	w.reload_tactical = 3.0
	w.reload_empty = 3.4
	w.spread_deg = 0.9
	w.ads_spread_mult = 0.08
	w.move_spread_deg = 3.5
	w.bloom_per_shot = 0.0
	w.recoil_pitch = 3.4
	w.recoil_yaw = 0.5
	# bolt gun: one big, slow kick with a rolling yaw
	w.recoil_pattern = PackedVector2Array([Vector2(-0.3, 3.6)])
	w.zero_range = 150.0
	w.recoil_recovery = 5.0
	w.sway = 1.5
	w.ads_fov = 22.0
	w.ads_time = 0.28
	w.sight_height = 0.115
	w.noise_radius = 130.0
	w.weight = 4.0
	return w
