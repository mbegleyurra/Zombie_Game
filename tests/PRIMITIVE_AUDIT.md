# Primitive audit (non-asset-pack visible objects)

Method: built the world (`world.build(1)`) in a probe, walked every MeshInstance3D / MultiMeshInstance3D that is visible and not under an instanced `res://assets/` scene, plus grep of scripts for Box/Cylinder/Sphere/Capsule/Plane/Prism/Quad/ArrayMesh/MeshUtil.
Allowed (not objects): terrain chunks (terrain.gd), road mesh (road_kit.gd, terrain-baked), sky, collision shapes, UI, particles/hit effects, pickup glow disc, projectile tracer.

## World (counts from the probe on the built world)

| # | Object | Source | Count | Action |
|---|--------|--------|-------|--------|
| 1 | Loot container body + handle (cupboard, fridge, crate, shelf, locker, med cabinet, register, toolbox, weapon rack, evidence locker, altar chest, donation box, pallet crate) | scripts/world/loot_container.gd BoxMesh | 83 + 83 | replace with Kenney/KayKit models per kind; box collision kept |
| 2 | Location shells: hospital, police station, church, gas station x2, warehouse, farm x6 (walls, roofs, fences, counters, beds, cells...) | scripts/world/building_factory.gd (MeshUtil ArrayMesh) | 12 meshes | replace with kit-model walls/roofs/props; colliders kept |
| 3 | Countryside cottages (walls, gable roof, door, windows, chimney) | hand_builder.gd `_house` (MeshUtil) | 23 | replace with Kenney suburban house model |
| 4 | Street cars in the city | hand_builder.gd `_street_cars` -> PropFactory.add_car | 8 | replace with Kenney cars/ models |
| 5 | Roadside wooden poles, wires, wrecked cars | world_builder.gd `_build_roadside`, prop_factory.gd | 1 mesh | poles/cars -> Kenney models; wires removed |
| 6 | Procedural trees (trunk + canopy MultiMesh) | world_builder.gd `_build_props` | 2 multimeshes | removed (KayKit forest already supplies trees) |
| 7 | Procedural rocks (4 blob MultiMeshes) | world_builder.gd `_build_rocks` | 4 | removed visuals (KayKit rocks supply rocks); colliders removed with them |
| 8 | Procedural bushes, grass tufts | world_builder.gd | 2 | removed (KayKit bushes/grass supply them) |
| 9 | Player-built pieces: wall, floor, window, door, barricade, workbench, stairs, base core, chest, assembler | scripts/building/building_system.gd, building_extras.gd (BoxMesh) | per placement | replace with Kenney survival-kit models; colliders kept |
| 10 | Drivable vehicle details | scripts/vehicles/vehicle.gd:73 | per vehicle | check; Kenney body kept |
| 11 | Pickup fallback shapes (gun, can, bottle, long, medkit, scrap, box) | loot_item.gd fallback | fallback only | removed; item without a model is not drawn |
| 12 | Zombie variants (runner, bloater, others) built from box/capsule/sphere | scripts/zombies/zombie.gd | per zombie | replace with Kenney mini characters |
| 13 | Zombie dismember stump spheres, gore cylinders | zombie.gd:427, 588, 616 | on hit | hit effects, kept |
| 14 | Skeleton bolt sphere | skeleton_bolt.gd | projectile | effect, kept |

## Files not touched
scripts/player/*, scripts/weapons/* (MASTER CHIEF), terrain.gd.

## Resolution (final)

| # | Outcome |
|---|---------|
| 1 | Loot containers: Kenney mini-shop / mini-arcade / survival / graveyard models per kind, box collider and loot logic unchanged; opened state is a dark overlay. |
| 2 | Location shells: every box/prism/cylinder is now a stretched Kenney survival/graveyard model (wall, floor, roof, fence, barrel, gravestone); colliders kept. Crop rows removed (no model). |
| 3 | Cottages: Kenney suburban house models over the same footprint; chimney, door and window boxes removed; collider kept. |
| 4 | Street cars, farm tractor, location cars: Kenney cars/ models with box colliders. |
| 5 | Roadside poles: Kenney light-square model with cylinder collider; wires removed. |
| 6-8 | Procedural trees, rocks, bushes, grass removed; KayKit forest supplies them. |
| 9 | Player-built pieces (wall, floor, window, door, barricade, workbench, stairs, base core, chest, assembler): Kenney survival / mini-shop models, colliders kept, workbench/chest/assembler still functional. |
| 10 | Vehicle missing-model fallback box visual removed (collider only). |
| 11 | Pickup fallback shapes removed; pickups without a model are not drawn (glow disc kept as effect). |
| 12 | All zombie kinds use the Kenney zombie rig; runner and bloater differ by proportions and tint. Primitive head/arm/leg/body builders deleted. |
| 13-14 | Gore gibs, stumps, skeleton bolt: hit effects, kept. |

Allowed leftovers: terrain chunks, terrain-baked road mesh, pickup glow discs. Enforced by tests/t_no_primitives.gd.
