extends RefCounted
## Deterministic low-poly props shared by the world builder and the building factory:
## cars (sedan, pickup, van, police, box truck), a tractor, wooden power poles and sagging wires.
## Every function draws into a caller-owned MeshUtil + StaticBody3D, placed by a Transform3D whose
## origin sits on the ground. Cars and the tractor run along local +X (+X = front).
## Randomness only ever comes from the RandomNumberGenerator the caller passes in.

const MeshUtil = preload("res://scripts/world/mesh_util.gd")

const CAR_COLORS := [
	Color(0.62, 0.14, 0.12), Color(0.15, 0.3, 0.55), Color(0.78, 0.74, 0.62), Color(0.22, 0.4, 0.28),
	Color(0.85, 0.55, 0.15), Color(0.5, 0.52, 0.55), Color(0.9, 0.9, 0.9),
]
const C_GLASS := Color(0.16, 0.2, 0.26)
const C_TYRE := Color(0.1, 0.1, 0.11)
const C_HUB := Color(0.55, 0.55, 0.58)
const C_RUST := Color(0.45, 0.26, 0.16)
const C_BUMPER := Color(0.22, 0.22, 0.24)
const C_POLE := Color(0.36, 0.25, 0.16)
const C_WIRE := Color(0.08, 0.08, 0.09)

const POLE_HEIGHT := 9.0
const WIRE_Y := 8.9


static func random_car_color(rng: RandomNumberGenerator) -> Color:
	return CAR_COLORS[rng.randi_range(0, CAR_COLORS.size() - 1)] as Color


static func add_collision(body: StaticBody3D, xf: Transform3D, center: Vector3, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.transform = xf * Transform3D(Basis(), center)
	body.add_child(cs)


## Faceted wheel with its axle along local Z: two crossed squares make an eight-point disc.
static func add_wheel(mu, xf: Transform3D, center: Vector3, radius: float, width: float, tyre: Color = C_TYRE) -> void:
	var s: float = radius * 1.4
	mu.add_box_xf(xf, center, Vector3(s, s, width), tyre)
	var rot := xf * Transform3D(Basis(Vector3(0, 0, 1), PI * 0.25), center)
	mu.add_box_xf(rot, Vector3.ZERO, Vector3(s, s, width), tyre)
	mu.add_box_xf(xf, center, Vector3(radius * 0.7, radius * 0.7, width + 0.04), C_HUB)


## kind: "sedan" | "pickup" | "van" | "police" | "truck".
## wreck: 0 intact, 1 rusted and sagging on a flat tyre, 2 burnt out.
static func add_car(mu, body: StaticBody3D, xf: Transform3D, kind: String, col: Color, wreck: int, rng: RandomNumberGenerator) -> void:
	var paint: Color = col
	if kind == "police":
		paint = Color(0.12, 0.13, 0.16)
	if wreck == 1:
		paint = paint.lerp(C_RUST, 0.45)
	elif wreck == 2:
		paint = Color(0.07, 0.065, 0.06)
	var glass: Color = C_GLASS if wreck != 2 else Color(0.03, 0.03, 0.03)
	var trim: Color = C_BUMPER if wreck != 2 else Color(0.05, 0.05, 0.05)
	var f := xf
	if wreck == 1:
		f = xf * Transform3D(Basis(Vector3(1, 0, 0), rng.randf_range(0.03, 0.07)), Vector3.ZERO)
	var wheel_x: Array = [1.4, -1.4]
	var half_w := 0.9
	var hull := Vector3(4.4, 1.5, 1.9)
	var tail_x := -2.25
	var front_x := 2.25
	match kind:
		"pickup":
			wheel_x = [1.6, -1.5]
			half_w = 0.95
			hull = Vector3(5.0, 1.6, 1.95)
			tail_x = -2.5
			front_x = 2.5
			mu.add_box_xf(f, Vector3(0, 0.62, 0), Vector3(5.0, 0.62, 1.9), paint)
			mu.add_box_xf(f, Vector3(0.7, 1.25, 0), Vector3(1.9, 0.65, 1.7), glass)
			mu.add_box_xf(f, Vector3(0.7, 1.62, 0), Vector3(1.7, 0.1, 1.7), paint)
			mu.add_box_xf(f, Vector3(-1.4, 1.05, 0.92), Vector3(2.2, 0.45, 0.1), paint)
			mu.add_box_xf(f, Vector3(-1.4, 1.05, -0.92), Vector3(2.2, 0.45, 0.1), paint)
			mu.add_box_xf(f, Vector3(-2.45, 1.05, 0), Vector3(0.1, 0.45, 1.9), paint)
		"van":
			wheel_x = [1.7, -1.6]
			half_w = 1.0
			hull = Vector3(5.2, 2.2, 2.05)
			tail_x = -2.6
			front_x = 2.6
			mu.add_box_xf(f, Vector3(0, 0.5, 0), Vector3(5.2, 0.5, 1.9), trim)
			mu.add_box_xf(f, Vector3(0, 1.3, 0), Vector3(5.0, 1.7, 2.0), paint)
			mu.add_box_xf(f, Vector3(2.45, 1.55, 0), Vector3(0.1, 0.6, 1.8), glass)
			mu.add_box_xf(f, Vector3(1.8, 1.75, 1.01), Vector3(1.2, 0.5, 0.04), glass)
			mu.add_box_xf(f, Vector3(1.8, 1.75, -1.01), Vector3(1.2, 0.5, 0.04), glass)
		"truck":
			wheel_x = [2.5, -0.6, -2.0]
			half_w = 1.0
			hull = Vector3(7.2, 2.8, 2.4)
			tail_x = -3.6
			front_x = 3.6
			mu.add_box_xf(f, Vector3(0, 0.55, 0), Vector3(7.2, 0.4, 2.0), trim)
			mu.add_box_xf(f, Vector3(2.55, 1.3, 0), Vector3(1.6, 1.6, 2.2), paint)
			mu.add_box_xf(f, Vector3(3.3, 1.7, 0), Vector3(0.1, 0.7, 1.9), glass)
			var cargo: Color = Color(0.86, 0.86, 0.84) if wreck != 2 else Color(0.09, 0.085, 0.08)
			mu.add_box_xf(f, Vector3(-0.8, 1.85, 0), Vector3(4.6, 2.5, 2.4), cargo)
		_:
			mu.add_box_xf(f, Vector3(0, 0.62, 0), Vector3(4.4, 0.62, 1.8), paint)
			mu.add_box_xf(f, Vector3(-0.2, 1.2, 0), Vector3(2.3, 0.6, 1.62), glass)
			mu.add_box_xf(f, Vector3(-0.2, 1.52, 0), Vector3(1.9, 0.1, 1.55), paint)
			if kind == "police":
				mu.add_box_xf(f, Vector3(0, 0.66, 0.91), Vector3(2.2, 0.35, 0.03), Color(0.9, 0.9, 0.92))
				mu.add_box_xf(f, Vector3(0, 0.66, -0.91), Vector3(2.2, 0.35, 0.03), Color(0.9, 0.9, 0.92))
				mu.add_box_xf(f, Vector3(-0.2, 1.64, -0.25), Vector3(0.5, 0.14, 0.5), Color(0.8, 0.12, 0.1))
				mu.add_box_xf(f, Vector3(-0.2, 1.64, 0.25), Vector3(0.5, 0.14, 0.5), Color(0.15, 0.25, 0.85))
	# bumpers and lights
	mu.add_box_xf(f, Vector3(front_x, 0.45, 0), Vector3(0.18, 0.3, half_w * 1.9), trim)
	mu.add_box_xf(f, Vector3(tail_x, 0.45, 0), Vector3(0.18, 0.3, half_w * 1.9), trim)
	if wreck != 2:
		var lamp := Color(0.95, 0.85, 0.5)
		var tail := Color(0.75, 0.1, 0.08)
		for sz in [-1.0, 1.0]:
			mu.add_box_xf(f, Vector3(front_x + 0.01, 0.78, half_w * 0.7 * sz), Vector3(0.05, 0.15, 0.3), lamp)
			mu.add_box_xf(f, Vector3(tail_x - 0.01, 0.78, half_w * 0.7 * sz), Vector3(0.05, 0.15, 0.3), tail)
	# wheels (one sits lower and is skipped on a burnt hull)
	var flat_i: int = rng.randi_range(0, wheel_x.size() * 2 - 1) if wreck == 1 else -1
	var wi := 0
	for wx in wheel_x:
		for sz in [-1.0, 1.0]:
			var r := 0.36
			var cy := 0.37
			if wi == flat_i:
				r = 0.3
				cy = 0.3
			add_wheel(mu, f, Vector3(float(wx), cy, (half_w - 0.05) * float(sz)), r, 0.28)
			wi += 1
	add_collision(body, f, Vector3(0, hull.y * 0.5, 0), hull)


## Small farm tractor (green, big rear wheels, glass cab). Runs along +X.
static func add_tractor(mu, body: StaticBody3D, xf: Transform3D, paint: Color) -> void:
	mu.add_box_xf(xf, Vector3(0.7, 0.95, 0), Vector3(1.9, 0.9, 1.1), paint)
	mu.add_box_xf(xf, Vector3(1.55, 0.95, 0), Vector3(0.3, 0.7, 1.0), Color(0.2, 0.2, 0.22))
	mu.add_box_xf(xf, Vector3(-0.6, 1.0, 0), Vector3(1.6, 0.6, 1.1), paint.darkened(0.15))
	mu.add_box_xf(xf, Vector3(-0.7, 1.9, 0), Vector3(1.1, 1.0, 1.2), C_GLASS)
	mu.add_box_xf(xf, Vector3(-0.7, 2.45, 0), Vector3(1.3, 0.1, 1.4), paint)
	mu.add_box_xf(xf, Vector3(1.1, 1.55, 0.35), Vector3(0.1, 0.5, 0.1), Color(0.15, 0.15, 0.15))
	for sz in [-1.0, 1.0]:
		add_wheel(mu, xf, Vector3(-0.9, 0.8, 0.85 * float(sz)), 0.8, 0.4)
		add_wheel(mu, xf, Vector3(1.25, 0.45, 0.7 * float(sz)), 0.45, 0.25)
	add_collision(body, xf, Vector3(0.1, 1.0, 0), Vector3(3.2, 2.0, 1.9))


## Wooden pole with crossarm and three insulators. The crossarm runs along local Z, so yaw the
## transform with Basis(UP, atan2(-dir.y, dir.x)) to put a pole beside a road with direction dir.
## Returns the three wire attachment points in the same space as xf's parent.
static func add_pole(mu, body: StaticBody3D, xf: Transform3D) -> Array:
	var insul := Color(0.55, 0.7, 0.68)
	mu.add_box_xf(xf, Vector3(0, POLE_HEIGHT * 0.5, 0), Vector3(0.28, POLE_HEIGHT, 0.28), C_POLE)
	mu.add_box_xf(xf, Vector3(0, 8.5, 0), Vector3(0.18, 0.18, 2.6), C_POLE.darkened(0.2))
	mu.add_box_xf(xf, Vector3(0, 7.6, 0), Vector3(0.15, 0.15, 1.6), C_POLE.darkened(0.2))
	mu.add_beam(xf * Vector3(0, 7.8, 0), xf * Vector3(0, 8.45, 0.9), 0.08, C_POLE.darkened(0.1))
	mu.add_beam(xf * Vector3(0, 7.8, 0), xf * Vector3(0, 8.45, -0.9), 0.08, C_POLE.darkened(0.1))
	for z in [-1.1, 1.1]:
		mu.add_box_xf(xf, Vector3(0, 8.7, z), Vector3(0.12, 0.2, 0.12), insul)
	mu.add_box_xf(xf, Vector3(0, 9.1, 0), Vector3(0.12, 0.2, 0.12), insul)
	add_collision(body, xf, Vector3(0, POLE_HEIGHT * 0.5, 0), Vector3(0.28, POLE_HEIGHT, 0.28))
	return [xf * Vector3(0, WIRE_Y, -1.1), xf * Vector3(0, WIRE_Y, 1.1), xf * Vector3(0, 9.3, 0)]


## Sagging wire between two attachment points (four beam segments on a parabola).
static func add_wire(mu, p0: Vector3, p1: Vector3, sag: float) -> void:
	var prev := p0
	for k in range(1, 5):
		var t: float = float(k) / 4.0
		var p: Vector3 = p0.lerp(p1, t)
		p.y -= sag * 4.0 * t * (1.0 - t)
		mu.add_beam(prev, p, 0.05, C_WIRE)
		prev = p
