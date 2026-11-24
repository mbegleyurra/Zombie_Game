# QA GATE: baked world re-gate after D1-D5 fixes (BAKED2)

RAT, 2026-11-23. Branch Bad_Animations (HEAD 9fc08a5 + uncommitted working tree). Baked scenes and all 505 baked/res
files dated 21:23, a full re-bake. Same method as tests/QA_GATE_BAKED1.md.

## VERDICT: PASS

| # | Item | BAKED1 | BAKED2 |
|---|---|---|---|
| 1 | No generation at runtime | PASS | PASS |
| 2 | Editable | PASS (D4, D5) | PASS |
| 3 | Same world (vegetation renders) | FAIL (D1) | **PASS** |
| 4 | Gameplay | PASS | PASS |
| 5 | Suites | FAIL (D3, D2) | **PASS** (no failure outside the baseline) |

| Defect | Result | Evidence |
|---|---|---|
| D1 vegetation zero-basis transforms | **PASS** | see 3 |
| D2 transform test gap | **PASS** | see 5 |
| D3 t_inventory_ui / empty new crate | **PASS** | t_inventory_ui 37/0; loot_container.gd:86 setup() and :113 _ready() roll when contents are empty |
| D4 auto-named `@Type@N` nodes | **PASS** | 0 `[node name="@` lines in all 8 baked scenes (was 5783) |
| D5 stale `metadata/sites` | **PASS** | 0 `metadata/sites` in vegetation.tscn (longest line 121 chars, was 70 KB). map_ui.gd:322 and t_forest read MultiMesh buffers via scripts/world/forest_data.gd sites() |

## 1. No generation at runtime: PASS
- Outside comments, scripts/, scenes/ and project.godot have no hits for `res://tools`, `placements.json` or `hand_map`.
- world_builder.gd:62 `load(BAKED_SCENE)` = `res://scenes/world/world_baked.tscn`.
- t_mp_main log: `[World] baked world loaded in 1719ms: loot_nodes=250 locations=12 spawns=8`.

## 2. Editable: PASS
- Node counts are identical to BAKED1: terrain 192, roads 1, buildings 10553, vegetation 882, props 751, dungeon 692,
  vehicles 11, markers 1447.
- 0 nodes have a null owner in any scene. The only nodes not owned by the scene root are the internals of glb
  instances: buildings 3214, props 252, dungeon 233, markers 402, which is normal. glb instance counts are 2890 / 173
  / 233 / 115, as in BAKED1.
- None of the 8 scenes contains an inline ArrayMesh or primitive mesh sub_resource.
- Move test: `Props/light-square2_0/light-square2` was moved (0,0,0.94) -> (3,0,-1.06), saved and reloaded. The move
  was kept, the node is still a glb instance, and the file went from 137073 to 137070 bytes (no inlining). The node now
  has a readable name.

## 3. Same world: PASS (D1 fixed)
Fix: tools/worldgen/kaykit_forest.gd:116-128 assigns the whole `mm.buffer` instead of calling set_instance_transform.

Run under xvfb at 1280x720 with `--rendering-driver opengl3` (llvmpipe), with world_baked.tscn in the tree:
- 316 multimeshes and 2450 instances (tree 520, bush 260, rock 170, grass 1500). For all of them, buffer_ok fails 0,
  zero-basis instances in the buffer are 0, and zero-basis instances read back from the renderer are 0.
  Buffer-vs-renderer mismatches are 0.
- Instance 0 (`tree_Tree_4_A_2_0`) has origin (37.10, 1.63, -187.27) and scale 1.361. This matches the BAKED1
  pre-change baseline (37.1, 1.6, -187.3, scale 1.36).
- ForestData.sites() returns 2450. There are 564 colliders, so they now coincide with visible vegetation.
- Renders at the BAKED1 sites, comparing Vegetation visible vs hidden:

| site | mean px diff | px >40 |
|---|---|---|
| spawn (0,0) | 2.45 | 3.25% |
| city (46,-90) | 0.93 | 0.68% |
| farm (-28,-84) | 1.57 | 1.48% |
| dungeon (-143.3,123.5) | 2.76 | 3.46% |
| forest edge (-1.7,34.7) | 4.33 | 5.12% |

  Visual check of the forest-edge and dungeon frames: about 70-90 trees, shrubs, grass tufts and rocks are visible,
  with no black or magenta meshes and no floating trees.
  These magnitudes are the same order as the BAKED1 before/after deltas (the vegetation that was missing then).
  Camera framing differs from BAKED1, so the figures are not directly comparable. No pixel diff was made against a
  pre-change tree this time.

## 4. Gameplay: PASS
- PlayerSpawn_0..7 sit 0.80-0.81 m above terrain collision.
- t_dungeon_access 16/0, t_mp_main 5/0, selftest `SELFTEST PASS`, smoke_test 50/0.
- Loot: 109 containers in the `loot_container` group, 0 empty and unopened, md5 d78b1c84...e098. This is a different
  measure from BAKED1's 250-loot-node md5, so it is not comparable. The 250 total is confirmed by the load line and
  verify_bake.

## 5. Suites: PASS
`tools/verify_bake.gd`: `VERIFY PASS (0 failing checks)`. It now checks "forest xforms non-0" and
"mm w/o buffer" (verify_bake.gd:48-63).

Headless: t_baked_world 24/0 (was 23/0; transform check added at :83) · t_no_primitives 5/0 · t_world 10/0 ·
t_flatroads 19/0 · t_forest 54/0 · t_dungeon 30/0 · t_dungeon_access 16/0 (timeout 400) · t_mp_main 5/0 ·
t_inventory_ui 37/0 (D3 fixed; matches the baseline) · t_map_ui 50/4 · selftest PASS · smoke_test 50/0.

xvfb + opengl3: t_baked_world 24/0 · t_forest 54/0 · t_map_ui 54/0.

- The 4 t_map_ui headless failures are the same 4 lines as the BAKED1 baseline (full map canvas size 0x628, NW corner,
  north higher, mouse recaptured). They pass under opengl3, so they are headless-only and not a regression.
- D2 mutation check, run headless: ForestData.buffer_ok returns true on the real batch, false when instance 0 is
  zeroed, and false for an unset buffer. Because the check reads the saved buffer, it catches D1 without needing a
  renderer.
- selftest SCRIPT ERRORs: hud.gd:243 `float()` 131 and death_ui.gd:78 `bool()` 132, total 264 (BAKED1: 198 after /
  208 before). These are the same two pre-existing lines, and the count scales with run length.

## New defects
None blocking.
- **N1 (minor, test hygiene, owner: MASTER CHIEF)**: under opengl3, t_baked_world logs 2 and t_forest logs 4 lines of
  `ERROR: Texture with GL ID of N: leaked 349524 bytes` at exit (drivers/gles3/storage/utilities.cpp:82). This is
  shutdown noise from textures the tests do not free before quit. Exit code 0, and t_map_ui_gl is clean. Free the
  world, or wait a frame, before `quit()` so the error lines do not mask real ones in renderer runs.

Probes (tests/qa_baked2_probe.gd, qa_baked2_mut.gd, qa_baked2_edit.gd, qa_baked2_*.png) and /tmp/qb2/props_moved.tscn
were removed. Suite logs are in /tmp/qb2/.
