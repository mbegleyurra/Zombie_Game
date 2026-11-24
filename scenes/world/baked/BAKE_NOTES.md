# Baked world (Phase 1 bake + Phase 2 runtime)

The generated Dead Acres world (tools/worldgen/gen_world.gd, HandLayout.HAND_SEED) baked once into editable scenes.
Open `res://scenes/world/world_baked.tscn` in the editor: every building, model, tree, bush, rock, grass tuft, road
piece, loot node and marker is a real node you can select, move, copy or delete. There is no MultiMesh anywhere in
scenes/world (the bake aborts if one appears; tests/t_editable_world.gd checks it).

## Editing by hand

- **Vegetation**: `Vegetation/KayKitForest/{Trees,Bushes,Rocks,Grass}/<Model>_NNNN`, each an instance of
  `scenes/world/props/vegetation/<Model>.tscn` (rocks with a collider use `<Model>_Solid.tscn`). Every tree and big rock
  carries its own `Body` StaticBody3D + `Shape` inside the prop scene, so moving / scaling / deleting the node moves
  its collider too. To add one, instance a prop scene anywhere under `KayKitForest` (the root's meta `kind` makes it
  count). The map, spawn placement (`kaykit_resources.blocked_by_dressing`) and tests read the nodes through
  `scripts/world/forest_data.gd`, so they follow every edit; there is no stored copy of the positions.
  Editing a prop scene (e.g. a bigger trunk collider) changes every instance of that model.
- **Kenney dressing and roadside lights**: each model wrapper owns its collider (`Body`/`Shape` child) and is an
  editor group (`_edit_group_`), so one click selects the whole object.
- **Roads**: `Roads/Road_NNN` (one per road segment) and `Roads/Junction_NNN` (one per junction tile), each a
  MeshInstance3D at its own centre. Move or delete a piece freely. Reshaping a piece means editing its mesh in a 3D tool
  or re-baking. Roads have no collision; `road_distance` uses Markers meta `roads`, which is NOT updated by moving a
  piece.
- **Terrain**: 64 `Terrain/Chunk_X_Z` baked mesh nodes, each with its own trimesh collider. Move or delete a chunk in
  the editor. Godot has no built-in mesh sculpting, so changing the ground shape means editing
  `res/terrain_mesh_NNNN.res` in a 3D tool (or a terrain plugin) and replacing `res/terrain_shape_NNNN.res` with a
  matching trimesh (Mesh > Create Trimesh Static Body). `res/heightmap.res` does not follow such edits (see Heightmap
  format).

## Phase 2: how the game uses it

- The game never generates world content. `scripts/world/world_builder.gd` only instances `world_baked.tscn` and hoists
  the Roads/Buildings/Vegetation/Props/Dungeon/Vehicles children under `World`.
- `Terrain` gets `scripts/world/baked_terrain.gd`: `height_at` / `normal_at` (heightmap.res), `ground_color` /
  `forest_density` (groundmap.res), `road_distance` (Markers meta `roads`).
- Zombie / skeleton spawners and loot read `markers.tscn` through `scripts/world/spawn_markers.gd` (falls back to the
  markers.tscn SceneState when no world is loaded). Nothing under scripts/ reads data/hand_map/placements.json.
- The generator scripts live only in `tools/worldgen/` (bake-only; nothing under scripts/ or scenes/ loads them).

## Re-running the bake

```
cd /home/kali/Documents/Zombie_Game
rm -rf scenes/world/baked/*.tscn scenes/world/baked/res scenes/world/world_baked.tscn   # keep this file
/home/kali/tools/godot/godot --headless --path . --script res://tools/bake_world.gd     # ~17 s
/home/kali/tools/godot/godot --headless --path . --script res://tools/verify_bake.gd    # exit 0 = PASS
```

WARNING: re-baking OVERWRITES hand edits. It uses the generator kept in tools/worldgen/. The scenes are the source of
truth for the game. Clear `res/` before a re-bake: files are numbered, and stale files would otherwise remain.
Re-baking is deterministic: the only file that differs between two runs is markers.tscn.

## Files

| File | Contents |
|---|---|
| `scenes/world/world_baked.tscn` | Root `World` (Node3D): instances the 8 sub-scenes below + `DayNight` (day_night.gd, time_hours = 9). Written as plain text, no overrides. |
| `baked/terrain.tscn` | `Terrain`: 64 `Chunk_X_Z` MeshInstance3D (64 m each, mesh = `res/terrain_mesh_NNNN.res`, material `res/mat_*.tres`, visibility_range_end 300), each with child `Collision` StaticBody3D + CollisionShape3D (trimesh `res/terrain_shape_NNNN.res`). No terrain.gd script. |
| `baked/roads.tscn` | `Roads`: 123 terrain-hugging road pieces (62 `Road_NNN` + 61 `Junction_NNN`, meshes `res/roads_mesh_NNNN.res`), no collision (as before). The bake raises any road vertex below heightmap height + 0.041 m onto it (120 vertices, mostly the dungeon approach cut the 1 m grid cannot follow; `road_vertices_raised` in the manifest). |
| `baked/buildings.tscn` | `Buildings`: the 12 location roots (`hospital_0` ... `farm_11`, meta loc_id/location_type/location_name) with all factory geometry and authored graveyard/farm models, plus `HandWorld` (23 cottages, 24 city towers, CityInteriors, street lamps, street cars, storefront props, `Collision` body). Loot containers were moved OUT to markers.tscn. 2890 model instances. |
| `baked/vegetation.tscn` | `KayKitForest`: 2450 prop-scene instances in `Trees` (520), `Bushes` (260), `Rocks` (170), `Grass` (1500); 564 per-object colliders (trees + big rocks). |
| `scenes/world/props/vegetation/` | 34 prop scenes (one per model, `_Solid` = with collider) + `res/` with the 26 shared model meshes (meta `source_asset`). Written once by the bake when missing, never overwritten: hand edits survive a re-bake. |
| `baked/props.tscn` | `Props` (roadside street lights, each with its own collider) and `KenneyDressing` (155 models, 131 of them with their own collider). |
| `baked/dungeon.tscn` | `Dungeon`: walls, floors, stairs, surface gate, torches/lights, 12 `Door_N` (dungeon_door.gd) and its `Collision`. Containers, pickups and guard markers were moved to markers.tscn. |
| `baked/vehicles.tscn` | `Vehicles`: 10 drivable `Car_N` (vehicle.gd, exported `kind`) at the authored spawn (height + 0.7), zero velocity. |
| `baked/markers.tscn` | `Markers`: all gameplay data (see below). |
| `baked/res/heightmap.res` | Height sampling without generation (see below). |
| `baked/res/groundmap.res` | Map tint image; alpha channel = forest density. Read by baked_terrain.gd and the map UI. |
| `baked/res/*.res, *.tres` | 64 terrain meshes, 64 terrain trimesh shapes, 123 road piece meshes, 2 dungeon meshes, 29 materials. |
| `baked/res/bake_manifest.json` | Builder counts + per-scene node/semantic counts, used by verify_bake.gd. |

Total size: about 16 MB under baked/ plus 0.44 MB of vegetation prop scenes (vegetation.tscn 0.66 MB).

## markers.tscn

| Child group node | Node type | Godot group | Data |
|---|---|---|---|
| `PlayerSpawns/PlayerSpawn_0..7` | Marker3D | `player_spawn` | meta `slot` (int). Position = old get_spawn_point(i) (includes the +0.8 m lift). |
| `Locations/<type>_<id>` | Marker3D | `location` | meta `id` (int), `type`, `name` (String), `radius` (float); rotation.y = old `rot`; position = old `pos`. |
| `ZombieSpawns/Zombie_000..252` | Marker3D | `zombie_spawn` | meta `index`, `roll` (kind roll 0..1), `variant_seed`; rotation.y = yaw; y = ground height. Same order as ZOMBIE_SPAWNS rows. |
| `SkeletonSpawns/Skeleton_000..157` | Marker3D | `skeleton_spawn` | meta `index`, `roll` (type roll), `variant_seed`. Same order as SKELETON_SPAWNS rows. |
| `DungeonSkeletonSpawns/Guard_NN` | Marker3D | `dungeon_skeleton_spawn` | the dungeon builder's own guard markers, unchanged (13). |
| `VehicleSpawns/Car_N` | Marker3D | `vehicle_spawn` | meta `kind`. Same transform as the baked car. |
| `LootContainers/Container_N` | StaticBody3D, loot_container.gd or dungeon_container.gd | `interactable`, `loot_container` | exported `loot_id`, `kind`, `table`, `is_open`, `contents` ([{id,count}], baked from placements.json); dungeon ones also exported `dkind`, `model_size`. 109 nodes. |
| `GroundLoot/Loot_N` | StaticBody3D, loot_item.gd | `interactable`, `loot_item` | exported `item_id`, `count`, `loot_id`. 141 nodes (52 building pickups, dungeon pickups, resource scatter). |

The `Markers` root also holds metadata that the world used to publish: `dungeon_site`, `hand_footprints`, `citykit`, `spawn_center`, `roads` (road segments for road_distance).

Loot ids are 1..250, unique, and unchanged from the generated run, so container contents and pickup model variants stay identical.

## Heightmap format

`res/heightmap.res` is an `Image`, FORMAT_RF (one float32 per pixel), 517 x 517.
- Pixel (i, j) = terrain.height_at(origin.x + i * cell, origin.y + j * cell)
- meta `origin` = Vector2(-258, -258), meta `cell` = 1.0, meta `size` = 517
- Covers x, z in [-258, 258]; the world spans [-256, 256].
- Values are exact to height_at at grid points (max error read back from disk: 2e-6).
- Between grid points, sample bilinearly (as terrain.gd did for its relief grid). The baked terrain mesh uses the same 1 m vertices, so bilinear sampling follows the visible mesh triangles closely, but not exactly (bilinear vs. triangle split).
- If the terrain is hand-edited later, the heightmap is NOT updated automatically.

## Script changes this phase made (needed so baked state survives save/load)

- loot_container.gd: `loot_id, kind, table, is_open, contents` are `@export`. `_ready` re-finds the `Body` child when setup() did not run.
- dungeon_container.gd: `dkind, model_size` are `@export`. `_ready` re-finds the `Model` child.
- loot_item.gd: `item_id, count, loot_id` are `@export`.
- vehicle.gd: `kind` is `@export`.
- dungeon_door.gd: `is_open, hinge_x` are `@export`. `_ready` re-finds the `Hinge` and `Leaf` children.

Behaviour of the generated path is unchanged: t_handmap, t_dungeon_access and t_vehicles pass.

## Not baked / limitations (read before Phase 2)

1. **Ground loot and vehicle visuals are not in the files.** loot_item.gd and vehicle.gd build their model, collision and wheels in `_ready()`, so the bake strips those children (otherwise they would be built twice). In the editor, the 141 ground pickups and 10 cars appear as bare bodies at the right transform. At runtime they look and work as before. To see them in the editor, those scripts would need `@tool` or a placeholder.
2. **Signal wiring is runtime only.** register_loot() connections (picked_up / opened -> world) and `loot_by_id` are not serialised. The Phase 2 world script must walk groups `loot_item` / `loot_container` and register each node.
3. **DayNight** is a fresh day_night.gd node (sun, moon and environment are built in `_ready`), not baked.
4. **Terrain generator data** (flat pads, road beds) is not saved. Only its results are: meshes, collision, heightmap, groundmap and the road list (Markers meta `roads`). `road_distance` and `forest_density` are served from those by baked_terrain.gd; `is_clear` / `patch_at` have no baked equivalent.
5. **12 dungeon doorway models are saved as plain nodes**, not as glb instances, because their door leaf was moved into the door's Hinge. All other imported models are instances of their .glb/.gltf (2890 + 173 + 233 + 115).
6. **Imported sub-resources** (meshes and materials that the builders pulled out of models, e.g. the forest meshes in `scenes/world/props/vegetation/res/`) are copied out of the model files. Swapping the source glb does not update those copies. Each copied mesh carries meta `source_asset` = the .glb/.gltf it came from; tests/t_no_primitives.gd uses it to tell asset meshes from code-generated ones.
7. **Copied metadata**: HandWorld meta `footprints` / `citykit`, CityInteriors meta `rooms` / `placed` and Markers meta `roads` are derived lists. They do not follow nodes you move in the editor. (Vegetation has no copied list: it is read from the nodes.)
8. Zombie and skeleton spawners read the `zombie_spawn` / `skeleton_spawn` markers (same rows, same order as the old placements.json sections) via spawn_markers.gd.
9. Inline arrays left in .tscn: only 6-point roof hulls (ConvexPolygonShape3D) and the metadata lists above. No mesh or terrain arrays.
