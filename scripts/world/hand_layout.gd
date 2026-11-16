extends RefCounted
## The HANDCRAFTED Dead Acres layout: every road, location, house, city block and street prop is authored here as
## fixed data. Nothing in this file (or in how world_builder uses it) depends on the world seed, so the map is
## identical on every peer, every run. Coordinates are world metres on XZ; +Z is south on the map, -Z is north.
##
## Countryside: Route 9 runs west-east with a crossroads at County Road (24, 12), a small loop around the south-east
## farmland, a big loop (Route 9 - Ridge Lane - North Road - County Road), side lanes, farms and houses along them.
## City (Millbrook): a 3 x 3 grid of 44 m blocks between x 24..156 and z -156..-24: hospital, police station and church
## in the middle row, tall towers everywhere else. The player spawn (0, 0) is in the countryside, about 34 m from the nearest city corner (24, -24) and outside its flat pad.

const HAND_SEED := 20260101          ## terrain relief + decoration seed, always used regardless of the seed passed to build()
const SPAWN := Vector2(0.0, 0.0)

const CITY_CENTER := Vector2(90.0, -90.0)
const CITY_FLAT_R := 100.0
const CITY_FLAT_BLEND := 24.0
const CITY_HEIGHT := 2.0
const CITY_MIN := Vector2(24.0, -156.0)   ## street grid bounding box (x, z)
const CITY_MAX := Vector2(156.0, -24.0)
const CITY_X := [24.0, 68.0, 112.0, 156.0]
const CITY_Z := [-156.0, -112.0, -68.0, -24.0]
const STREET_HALF := 1.5                  ## city streets are two parallel 3.2 m tracks, 3 m apart (about 6.4 m wide)

const GATE_DIST := 20.0                   ## driveway starts this far in front of a countryside location (local +Z)
const HOUSE_PAD := 7.0

## [name, [points]] polylines of the countryside roads.
const COUNTRY_ROADS := [
	["Route 9", [Vector2(-195, 40), Vector2(-120, 28), Vector2(-45, 14), Vector2(24, 12), Vector2(95, 6), Vector2(165, -6), Vector2(205, -10)]],
	["Spawn Lane", [Vector2(0, 12.6), Vector2(0, 0), Vector2(0, -84)]],
	["County Road", [Vector2(24, -24), Vector2(24, 12), Vector2(24, 175)]],
	["Orchard Loop", [Vector2(70, 55), Vector2(160, 55), Vector2(160, 125), Vector2(70, 125), Vector2(70, 55)]],
	["Orchard Lane", [Vector2(95, 6), Vector2(95, 55)]],
	["Mill Lane", [Vector2(24, 92), Vector2(70, 92)]],
	["South Lane", [Vector2(24, 126), Vector2(-60, 134)]],
	["Ridge Lane", [Vector2(-90, 22.4), Vector2(-90, -96)]],
	["North Road", [Vector2(-90, -96), Vector2(-30, -112), Vector2(24, -112)]],
	["City Link", [Vector2(112, 3.1), Vector2(112, -24)]],
]

## [type, name, x, z, yaw, radius]. yaw turns the building like Basis(UP, yaw); the front gate / door side is local +Z.
const LOCATIONS := [
	["hospital", "St. Agnes Regional Hospital", 90.0, -90.0, 0.0, 26.0],
	["police_station", "Millbrook Police Station", 46.0, -90.0, 0.0, 22.0],
	["church", "Saint Brigid Chapel", 134.0, -96.0, 0.0, 22.0],
	["gas_station", "Route 9 Gas & Go", 60.0, -12.0, 0.0, 22.0],
	["gas_station", "Sunrise Fuel Stop", 165.0, -30.0, 0.0, 22.0],
	["warehouse", "Harlan Freight Warehouse", 178.0, -146.0, -PI * 0.5, 24.0],
	["farm", "Hartley Farm", -28.0, -84.0, PI * 0.5, 26.0],
	["farm", "Miller Homestead", -50.0, -150.0, 0.0, 26.0],
	["farm", "Cedar Ridge Farm", -128.0, -30.0, PI * 0.5, 26.0],
	["farm", "Olsen Acres", -30.0, 168.0, PI, 26.0],
	["farm", "Brandt Farm", 115.0, 90.0, -PI * 0.5, 26.0],
	["farm", "Willow Creek Farm", 130.0, 160.0, PI, 26.0],
]

## [x, z, yaw]: cottages along the roads, front door (local +Z) toward the road.
const HOUSES := [
	[-160.0, 24.5, 0.0], [-110.0, 35.0, PI], [-70.0, 9.5, 0.0], [-22.0, 22.0, PI],
	[125.0, 10.0, PI], [150.0, 7.0, PI],
	[14.0, 35.0, PI * 0.5], [14.0, 75.0, PI * 0.5], [14.0, 150.0, PI * 0.5],
	[34.0, 40.0, -PI * 0.5], [34.0, 110.0, -PI * 0.5], [34.0, 150.0, -PI * 0.5],
	[110.0, 46.0, 0.0], [145.0, 46.0, 0.0], [169.0, 75.0, -PI * 0.5], [169.0, 105.0, -PI * 0.5], [61.0, 72.0, PI * 0.5],
	[-81.0, -10.0, -PI * 0.5], [-81.0, -55.0, -PI * 0.5],
	[-62.0, -93.0, PI], [-10.0, -122.0, 0.0],
	[-9.0, -35.0, PI * 0.5], [9.0, -60.0, -PI * 0.5],
]

## City tower blocks: [block centre x, z, [[dx, dz, w, d, height, colour index] x4]].
const CITY_BLOCKS := [
	[46.0, -46.0, [[-9.5, -9.5, 13.0, 13.0, 22.0, 0], [9.5, -9.5, 14.0, 12.0, 14.0, 1], [-9.5, 9.5, 12.0, 14.0, 30.0, 2], [9.5, 9.5, 13.0, 13.0, 18.0, 3]]],
	[90.0, -46.0, [[-9.5, -9.5, 14.0, 14.0, 34.0, 2], [9.5, -9.5, 13.0, 12.0, 16.0, 0], [-9.5, 9.5, 13.0, 13.0, 12.0, 1], [9.5, 9.5, 14.0, 13.0, 26.0, 3]]],
	[134.0, -46.0, [[-9.5, -9.5, 13.0, 14.0, 20.0, 1], [9.5, -9.5, 14.0, 13.0, 28.0, 3], [-9.5, 9.5, 14.0, 12.0, 16.0, 0], [9.5, 9.5, 13.0, 14.0, 36.0, 2]]],
	[46.0, -134.0, [[-9.5, -9.5, 14.0, 13.0, 26.0, 3], [9.5, -9.5, 12.0, 14.0, 12.0, 2], [-9.5, 9.5, 13.0, 13.0, 32.0, 0], [9.5, 9.5, 14.0, 14.0, 20.0, 1]]],
	[90.0, -134.0, [[-9.5, -9.5, 13.0, 13.0, 16.0, 1], [9.5, -9.5, 14.0, 14.0, 38.0, 3], [-9.5, 9.5, 14.0, 13.0, 24.0, 2], [9.5, 9.5, 13.0, 12.0, 14.0, 0]]],
	[134.0, -134.0, [[-9.5, -9.5, 14.0, 12.0, 18.0, 2], [9.5, -9.5, 13.0, 13.0, 30.0, 0], [-9.5, 9.5, 12.0, 14.0, 22.0, 3], [9.5, 9.5, 14.0, 14.0, 15.0, 1]]],
]

## Parked / abandoned cars on the city streets: [x, z, yaw, kind, wreck (0 intact, 1 rusted, 2 burnt)].
const CITY_CARS := [
	[68.5, -40.0, 1.6, "sedan", 1], [112.5, -50.0, 1.5, "pickup", 2], [25.0, -60.0, 1.5, "van", 1],
	[80.0, -68.2, 0.1, "sedan", 2], [100.0, -111.5, 3.0, "pickup", 1], [60.0, -155.5, 0.2, "van", 2],
	[156.5, -120.0, 1.5, "sedan", 1], [37.0, -24.3, 3.1, "pickup", 2],
]


## Every road segment [a, b] of the world: countryside polylines plus the doubled city street grid.
static func road_segments() -> Array:
	var out: Array = []
	for r in COUNTRY_ROADS:
		var pts: Array = r[1]
		for i in range(pts.size() - 1):
			out.append([pts[i], pts[i + 1]])
	for x in CITY_X:
		for k in range(CITY_Z.size() - 1):
			for off in [-STREET_HALF, STREET_HALF]:
				out.append([Vector2(float(x) + off, float(CITY_Z[k])), Vector2(float(x) + off, float(CITY_Z[k + 1]))])
	for z in CITY_Z:
		for k in range(CITY_X.size() - 1):
			for off in [-STREET_HALF, STREET_HALF]:
				out.append([Vector2(float(CITY_X[k]), float(z) + off), Vector2(float(CITY_X[k + 1]), float(z) + off)])
	return out


static func in_city(p: Vector2, margin: float = 0.0) -> bool:
	return p.x >= CITY_MIN.x - margin and p.x <= CITY_MAX.x + margin and p.y >= CITY_MIN.y - margin and p.y <= CITY_MAX.y + margin
