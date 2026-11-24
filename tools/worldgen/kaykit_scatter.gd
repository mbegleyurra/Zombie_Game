extends RefCounted
## BAKE-ONLY. Places the hand-authored KayKit ground pickups (PICKUPS rows of data/hand_map/placements.json) into the
## generated world. Used only by tools/bake_world.gd through tools/worldgen/gen_world.gd; the game loads the result
## from scenes/world/baked/markers.tscn.

const HandMapData = preload("res://tools/worldgen/hand_map_data.gd")


## Wires the ground-pickup scatter to the world's `built` signal (called from DungeonBuilder.attach).
static func attach(world: Node) -> void:
	world.built.connect(func(): scatter(world))


## One PICKUPS row [item, amount, x, z] each. Uses next_loot_id() so ids are stable. Returns the number placed.
static func scatter(world: Node) -> int:
	var count := 0
	for row in HandMapData.section("PICKUPS"):
		var r: Array = row
		var p := Vector2(float(r[2]), float(r[3]))
		var y: float = world.terrain.height_at(p.x, p.y) + 0.06
		world.spawn_ground_item(str(r[0]), int(r[1]), Vector3(p.x, y, p.y), world.next_loot_id())
		count += 1
	return count