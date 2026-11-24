# QA GATE: baked, hand-editable world (BAKED1)

RAT, 2026-11-23 ~21:40. Branch Bad_Animations (HEAD 9fc08a5 + uncommitted Phase 1/2 working tree; bake files dated 20:18).
Baseline is a `git worktree add /tmp/zg_before HEAD` checkout (removed after the gate).

## VERDICT: FAIL

The world loads only from the baked scenes and the scenes are editable. However, **every tree, bush, rock and grass
tuft is invisible** (D1), so this is not the same world.

| # | Item | Result |
|---|---|---|
| 1 | No generation at runtime | PASS |
| 2 | Editable | PASS (minor: D4, D5) |
| 3 | Same world (renders vs pre-change) | **FAIL** (D1) |
| 4 | Gameplay | PASS |
| 5 | Suites re-run | **FAIL** (1 new failure vs baseline: D3; detection gap D2) |

## 1. No generation at runtime: PASS
- grep scripts/ and scenes/: every `tools/worldgen` hit is a comment. Nothing under scenes/, scripts/ or project.godot
  references `res://tools`, and no script reads `placements.json` / `hand_map`.
- world_builder.gd:62 `load(BAKED_SCENE)` = `res://scenes/world/world_baked.tscn`, then `_adopt()` instances it.
  It contains no builder calls.
- Headless main.tscn run: `[World] baked world loaded in 1241ms: loot_nodes=250 locations=12 spawns=8`. No tools/
  script is in the resource cache after load. The world has baked Terrain and Markers. Its 22 children match the
  pre-bake node paths.
  (`ResourceLoader.has_cached(world_baked.tscn)` returns false because world_builder drops the PackedScene after
  instancing. This is a probe artifact, not a defect.)

## 2. Editable: PASS
| scene | nodes | no owner | glb instances | inline meshes |
|---|---|---|---|---|
| terrain | 192 | 0 | 0 | 0 |
| roads | 1 | 0 | 0 | 0 |
| buildings | 10553 | 0 | 2890 | 0 |
| vegetation | 882 | 0 | 0 (multimeshes) | 0 |
| props | 751 | 0 | 173 | 0 |
| dungeon | 692 | 0 | 233 | 0 |
| vehicles | 11 | 0 | 0 | 0 |
| markers | 1447 | 0 | 115 | 0 |
- None of the baked .tscn files contain inline ArrayMesh or primitive sub_resources. All meshes and multimeshes are
  external `res/` files. The only packed arrays are small convex-shape point lists (each line is 135 characters or less).
- Move test: `Props/@Node3D@264/light-square2` was moved (0,0,0.94) -> (3,0,-1.06) in a temp copy, then saved and
  reloaded. The move survived, the node is still a glb instance, and the file size went from 138917 to 138914 bytes
  (no inlining).

## 3. Same world: FAIL
xvfb, 1280x720, `--rendering-driver opengl3`. Fixed cameras were computed from the world API and were identical in
both trees. In both trees, a 9x9 ray grid over 48 m at each site gave 0/81 misses and 0 hits below the heightmap.

| site | target | mean px diff | px >40 | judgement |
|---|---|---|---|---|
| spawn | (0,0) | 1.76 | 1.84% | vegetation missing; buildings, road, lamp, cars identical |
| city | police_station_1 (46,-90) | 1.73 | 1.17% | forest belt on horizon missing; everything else identical |
| farm | farm_6 (-28,-84) | 2.38 | 2.29% | silo, barns, tractor, car, fences identical; tree line missing |
| dungeon | origin (-143.3,123.5) | 2.48 | 2.72% | walls, stairs, gate, torches identical; surrounding trees missing |
| forest edge | nearest tree >30 m from spawn (-1.7,34.7) | 7.66 | 9.24% | the forest is gone: bare grass |

No missing buildings, no floating or sunken props, and no terrain holes were found. Only vegetation differs (D1).

## 4. Gameplay: PASS
- Player spawn: PlayerSpawn_1..7 sit 0.80 m above terrain collision. The ray at PlayerSpawn_0 hit `Player_1`, who was
  standing on it, so that is correct too.
- Dungeon exit: t_dungeon_access 16/0. A body walks in from 4 of 4 approaches, back up and out of the gate, and the
  gate-to-vault path is open. (t_qa_walk_dungeon fails 6/6 identically in the baseline because its harness input is
  dead.)
- Loot parity: two separate processes with session seeds 424242 and 1 produced 250 loot nodes each with identical
  md5 7813e0f5...4382, and 0 empty containers. t_mp_main 5/0, t_mp_real 12/0, selftest `SELFTEST PASS`.
- Markers: 10/10 cars at their VehicleSpawns marker (<0.1 m). 253 zombie, 158 skeleton and 13 guard markers.
  t_skeletons `poll_markers spawns for markers within 40 m only` PASS. t_vehicles 35/0.
- Map UI: t_map_ui terrain texture checks all PASS (420 tints, deterministic, 384 px, minimap shares texture). Its 4
  failures are identical in the baseline.

## 5. Suites (exact counts, pass/fail)
World suites: t_baked_world 23/0 · t_no_primitives 5/0 · smoke_test 50/0 · t_world 10/0 · t_qa_world 59/0 ·
t_r4_world 48/0 · t_forest 54/0 · t_handworld 34/0 · t_handmap 18/0 · t_citykit 35/0 · t_city_interiors 15/0 ·
t_dressing 33/0 · t_kenney_dress 32/0 · t_dungeon 30/0 · t_dungeon_access 16/0 · t_flatroads 19/0 ·
t_terrain_smooth 13/0 · t_vehicles 35/0 · t_skeletons 59/0 · t_map_ui 50/4 · selftest PASS · boot120 exit 0, 0 errors.

Failing suites, re-run in the baseline tree:

| suite | after | before | new? |
|---|---|---|---|
| t_backpacks | 68/2 | 68/2 | no |
| t_core | 96/1 | 96/1 | no |
| t_inventory_ui | 36/1 | 37/0 | **YES (D3)** |
| t_kenney | 172/5 | 172/5 | no |
| t_map_ui | 50/4 | 50/4 | no |
| t_qa_recoil | 0/9 | 0/9 | no |
| t_qa_walk_build | 16/7 | 16/7 | no |
| t_qa_walk_dungeon | 0/6 (timeout) | 0/6 (timeout) | no |
| t_r4_zombies | 30/2 | 30/2 | no |
| t_r5_late | 10/2 | 10/2 | no |
| t_r5_walk | 36/9 | 36/9 | no |

The failure lines are identical in both trees except the one t_inventory_ui line.
- selftest SCRIPT ERRORs (hud.gd:243 `float()`, death_ui.gd:78 `bool()`): 198 after vs 208 before. These are
  pre-existing.
- t_hands_viewmodel 0/1 is expected because it needs xvfb.

## Defects (owner: MASTER CHIEF)
- **D1 (blocker)**: `tools/bake_world.gd:354-360` saves each MultiMesh with `ResourceSaver.save` while the bake runs
  `--headless` (line 3). The dummy renderer holds no instance buffer, so all 316 `res/vegetation_multimesh_*.res` have
  zero-basis transforms. Under a real renderer, instance 0 is all zeros, where the baseline has
  origin (37.1, 1.6, -187.3) and scale 1.36. As a result, all 2450 vegetation instances are invisible, and their 564
  collision shapes in vegetation.tscn now act as invisible walls.
  Fix direction: copy `transform_array` / `set_instance_transform` from the source data before saving, or bake under a
  real renderer (xvfb + opengl3). Then re-verify with a renderer.
- **D2 (test gap)**: `tools/verify_bake.gd:52` and `tests/t_baked_world.gd:81` check only multimesh and instance
  counts, and t_forest also passes. Add an assertion that instance transforms are non-zero, run under xvfb, so D1
  cannot pass again.
- **D3 (regression, minor)**: `tests/t_inventory_ui.gd:160` builds containers with `setup()` and expects contents.
  `scripts/world/loot_container.gd:72-75` no longer rolls contents, so the test sees 0 items. The baked containers
  are fine (250 nodes, 0 empty). Either update the test to use baked containers, or give containers created at runtime
  or placed in the editor a default roll. Today a newly placed crate is empty.
- **D4 (editability, minor)**: 5783 auto-named `@Type@N` nodes (buildings 4360, vegetation 564, dungeon 364,
  props 322, markers 109, terrain 64). They are hard to find in the editor, and the names are not stable across
  re-bakes.
- **D5 (editability, minor)**: `scenes/world/baked/vegetation.tscn:2535` holds `metadata/sites` (a 70 KB line), which
  the map UI reads (`scripts/ui/map_ui.gd:319`). Moving a tree in the editor does not update it, so the map goes stale.

Probes (tests/qa_baked1_probe.gd, qa_baked1_render.gd, qa_baked1_veg.gd, qa_baked1_loot.gd) and /tmp/zg_before were
removed after the gate.
