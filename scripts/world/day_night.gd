extends Node3D
## Day/night cycle: sun + moon DirectionalLight3D, procedural sky, ambient and fog.
## time_hours is 0..24 (6 = sunrise, 12 = noon, 18 = sunset). Call set_time(h) to sync clients to the host.

signal hour_changed(hour: int)
signal became_night
signal became_day

@export var day_length_seconds: float = 600.0
@export var time_hours: float = 9.0
var paused: bool = false

var sun: DirectionalLight3D
var moon: DirectionalLight3D
var env: Environment
var sky_mat: ProceduralSkyMaterial
var world_env: WorldEnvironment

var _last_hour: int = -1
var _was_night: bool = false

const NIGHT_TOP := Color(0.02, 0.03, 0.09)
const NIGHT_HORIZON := Color(0.05, 0.07, 0.14)
const DAY_TOP := Color(0.18, 0.36, 0.64)
const DAY_HORIZON := Color(0.5, 0.58, 0.66)
const DUSK_TOP := Color(0.35, 0.3, 0.5)
const DUSK_HORIZON := Color(0.95, 0.55, 0.3)


func _ready() -> void:
	add_to_group("daynight")
	_build()
	_apply()


func _process(delta: float) -> void:
	if paused or day_length_seconds <= 0.0:
		return
	time_hours = fposmod(time_hours + delta * 24.0 / day_length_seconds, 24.0)
	_apply()


func set_time(hours: float) -> void:
	time_hours = fposmod(hours, 24.0)
	if sun:
		_apply()


func is_night() -> bool:
	return sin((time_hours - 6.0) / 24.0 * TAU) < -0.05


## 0.0 = full day, 1.0 = full night.
func get_darkness() -> float:
	return 1.0 - clampf(sin((time_hours - 6.0) / 24.0 * TAU) * 3.0 + 0.6, 0.0, 1.0)


## Smooth 0..1 night value for the zombie spawner (same curve as get_darkness).
func get_night_factor() -> float:
	return get_darkness()


func get_time_string() -> String:
	var h: int = int(time_hours)
	var m: int = int((time_hours - float(h)) * 60.0)
	return "%02d:%02d" % [h, m]


func _build() -> void:
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	add_child(sun)
	moon = DirectionalLight3D.new()
	moon.name = "Moon"
	moon.light_color = Color(0.55, 0.65, 1.0)
	moon.shadow_enabled = false
	add_child(moon)
	sky_mat = ProceduralSkyMaterial.new()
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.7
	env.glow_enabled = false
	env.fog_enabled = true
	env.fog_density = 0.0015
	world_env = WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	add_child(world_env)


func _apply() -> void:
	var sh: float = sin((time_hours - 6.0) / 24.0 * TAU)
	var day: float = clampf(sh * 3.0 + 0.6, 0.0, 1.0)
	var dusk: float = clampf(1.0 - absf(sh) * 3.5, 0.0, 1.0)
	var sun_pitch: float = -(time_hours - 6.0) / 24.0 * 360.0
	sun.rotation_degrees = Vector3(sun_pitch, 35.0, 0.0)
	sun.light_energy = day * 0.55
	sun.visible = day > 0.01
	sun.light_color = Color(1.0, 0.97, 0.88).lerp(Color(1.0, 0.55, 0.25), dusk)
	moon.rotation_degrees = Vector3(sun_pitch + 180.0, 35.0, 0.0)
	moon.light_energy = (1.0 - day) * 0.3
	moon.visible = day < 0.99
	var top: Color = NIGHT_TOP.lerp(DAY_TOP, day).lerp(DUSK_TOP, dusk * 0.6)
	var horizon: Color = NIGHT_HORIZON.lerp(DAY_HORIZON, day).lerp(DUSK_HORIZON, dusk * 0.7)
	sky_mat.sky_top_color = top
	sky_mat.sky_horizon_color = horizon
	sky_mat.ground_horizon_color = horizon
	sky_mat.ground_bottom_color = horizon.darkened(0.5)
	env.ambient_light_energy = lerpf(0.2, 0.3, day)
	env.fog_light_color = horizon
	env.fog_density = lerpf(0.003, 0.0015, day)
	var hr: int = int(time_hours)
	if hr != _last_hour:
		_last_hour = hr
		hour_changed.emit(hr)
	var night_now: bool = is_night()
	if night_now != _was_night:
		_was_night = night_now
		if night_now:
			became_night.emit()
		else:
			became_day.emit()
