class_name WeaponData
extends Resource
## Data-driven description of one firearm. Instances are built in WeaponDB.
## Units: metres, seconds, degrees, damage in hit points (zombie = 100 hp).

@export var id: String = ""
@export var display_name: String = ""
## Ammo item id consumed from the player inventory: 9mm, 556, 12ga, 762.
@export var caliber: String = "9mm"
@export var model: String = "pistol"      ## GunMesh model key

# --- terminal ballistics ---
@export var damage: float = 30.0          ## per projectile at the muzzle
@export var pellets: int = 1              ## projectiles per shot (shotgun)
@export var headshot_mult: float = 3.0
@export var penetration: float = 0.5      ## damage fraction kept after passing through one body
@export var max_penetrations: int = 1     ## extra bodies a projectile can pass through
@export var falloff_start: float = 30.0   ## metres where damage starts to fall
@export var falloff_end: float = 120.0    ## metres where damage hits min_damage_frac
@export var min_damage_frac: float = 0.5
@export var max_range: float = 300.0

# --- exterior ballistics ---
@export var muzzle_velocity: float = 400.0  ## m/s
@export var gravity_scale: float = 1.0      ## 1.0 = real 9.81 m/s^2 drop
@export var zero_range: float = 50.0        ## metres where the sights are zeroed (bullet crosses the aim line)

# --- handling ---
@export var mag_size: int = 15            ## rounds in the magazine (not counting chambered)
@export var fire_rate_rpm: float = 400.0
@export var automatic: bool = false
@export var reload_tactical: float = 1.8  ## round still chambered: fast mag swap
@export var reload_empty: float = 2.5     ## bolt/slide locked back: mag swap + rack
@export var per_round_reload: bool = false ## tube fed (shotgun): one shell at a time
@export var round_time: float = 0.55      ## seconds per shell when per_round_reload
@export var chamber_time: float = 0.5     ## time to rack a round after a tube reload

# --- accuracy and recoil ---
@export var spread_deg: float = 1.0       ## hip-fire cone half angle, standing still
@export var ads_spread_mult: float = 0.35
@export var move_spread_deg: float = 2.0  ## added at full sprint speed
@export var bloom_per_shot: float = 0.2   ## extra cone per consecutive shot
@export var recoil_pitch: float = 1.0     ## degrees up per shot (base)
@export var recoil_yaw: float = 0.3       ## degrees sideways random per shot
## Per-shot kick in a burst: Vector2(yaw_deg, pitch_deg). Last entry repeats.
@export var recoil_pattern: PackedVector2Array = PackedVector2Array()
@export var recoil_recovery: float = 6.0  ## degrees/second the muzzle settles back
@export var sway: float = 1.0             ## viewmodel sway multiplier
@export var ads_fov: float = 55.0
@export var ads_time: float = 0.15
@export var sight_height: float = 0.065   ## viewmodel offset so the sights line up when aiming

# --- misc ---
@export var noise_radius: float = 60.0    ## metres zombies can hear a shot
@export var weight: float = 1.0


func seconds_between_shots() -> float:
	return 60.0 / maxf(fire_rate_rpm, 1.0)


## Reload duration in seconds. Guns here never jam, so the time is deterministic.
## Magazine guns: reload_tactical (round still chambered) or reload_empty.
## Tube guns: rounds_missing * round_time, plus chamber_time when empty (-1 = full tube).
func reload_time(empty: bool = false, rounds_missing: int = -1) -> float:
	if per_round_reload:
		var n := mag_size if rounds_missing < 0 else rounds_missing
		return float(n) * round_time + (chamber_time if empty else 0.0)
	return reload_empty if empty else reload_tactical


## Bullet drop in metres at `distance` (flat shot, constant speed approximation).
func drop_at(distance: float) -> float:
	var t := distance / maxf(muzzle_velocity, 1.0)
	return 0.5 * 9.81 * gravity_scale * t * t


## Launch elevation in radians so the arc crosses the line of sight at zero_range.
func zero_angle() -> float:
	return 0.5 * 9.81 * gravity_scale * zero_range / (maxf(muzzle_velocity, 1.0) * maxf(muzzle_velocity, 1.0))


## Height of the bullet relative to the line of sight at `distance` once zeroed (negative = below).
func sight_offset_at(distance: float) -> float:
	return distance * tan(zero_angle()) - drop_at(distance)


## Read-only spec sheet used by an inspect UI and by tests.
func inspect() -> Dictionary:
	return {
		"id": id, "name": display_name, "ammo": caliber,
		"damage": damage, "pellets": pellets, "automatic": automatic,
		"rpm": fire_rate_rpm, "mag_size": mag_size,
		"muzzle_velocity": muzzle_velocity, "zero_range": zero_range,
		"drop_50m": drop_at(50.0), "drop_100m": drop_at(100.0), "drop_200m": drop_at(200.0),
		"reload_tactical": reload_time(false), "reload_empty": reload_time(true),
		"reload_full_tube": reload_time(true) if per_round_reload else 0.0,
		"per_round_reload": per_round_reload, "malfunctions": false,
		"recoil_shots": maxi(recoil_pattern.size(), 1),
	}


func kick_for_shot(index: int) -> Vector2:
	## Returns Vector2(yaw_deg, pitch_deg) for the Nth shot of a burst.
	var base: Vector2
	if recoil_pattern.size() > 0:
		base = recoil_pattern[mini(index, recoil_pattern.size() - 1)]
	else:
		base = Vector2(0.0, recoil_pitch)
	return Vector2(base.x + randf_range(-recoil_yaw, recoil_yaw) * 0.5, base.y)
