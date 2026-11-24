## VERDICT: PASS. The baked world is hand-editable per object in the Godot editor, with no generation.

# QA GATE: hand-editable baked world (EDIT1)

RAT, 2026-11-23. Branch Bad_Animations, working tree on HEAD 27dcd9e. HEAD still holds the 316-MultiMesh vegetation,
so it is the pre-change baseline. Every HEAD comparison below uses a `git worktree` of 27dcd9e in /tmp.

| # | Item | Result |
|---|---|---|
| 1 | No MultiMesh; every object is its own named node | **PASS** |
| 2 | Edit, save a copy, load the game from it; collision, map and spawning follow | **PASS** |
| 3 | No runtime world generation | **PASS** |
| 4 | Render under xvfb vs BAKED2 baseline | **PASS** |
| 5 | Suites + boot; t_handmap is pre-existing | **PASS** (no failure outside the HEAD baseline) |

## 1. Individual nodes: PASS
- `grep MultiMesh` over scenes/world/** finds 0 hits in any .tscn. It appears only in BAKE_NOTES.md.
- vegetation.tscn has 2456 nodes: 2450 `instance=ExtResource` objects plus root, KayKitForest and 4 groups.
  - Trees 520, Bushes 260, Rocks 170, Grass 1500. This equals BAKED2's 2450 instances exactly.
  - Names are readable and unique (`Tree_4_A_0001`, `Grass_1_B_0373`). There are 0 duplicate names per parent, 0
    `@` auto-names and 0 inline sub_resources.
- Each object instances one of 35 prop scenes in scenes/world/props/vegetation/. Each prop scene has a Mesh
  (external .res), plus a Body/Shape collider for trees and *_Solid rocks.
  - Instance 0 is `Tree_4_A_0001` at origin (37.04, 1.17, -187.25), scale 1.361. The BAKED2 instance 0 was
    (37.10, 1.63, -187.27), scale 1.361. The offset is the prop scene's mesh pivot (Mesh child at +0.34 y), so it is
    the same site.
- Other scenes: roads 124 per-piece MeshInstance3D (`Junction_000` ...). Props has 173, buildings 2890 and dungeon
  233 glb instances, unchanged from BAKED2. All 8 scenes have 0 auto-names. world_baked.tscn has 0
  MultiMeshInstance3D when loaded (render probe: `veg children=2450 mm=0`; HEAD: `children=0 mm=316`).

## 2. Edit test: PASS
Probe method:
1. Instance vegetation.tscn with `GEN_EDIT_STATE_INSTANCE`, as the editor does.
2. Move `Tree_2_B_0001` to zombie-spawn marker M (-205.6, -209.2).
3. Delete `Tree_4_A_0002`.
4. Instance `Tree_1_A.tscn` as `QA_Added_Tree` at spawn marker A (211.9, -35.1).
5. `PackedScene.pack` + `ResourceSaver.save` to a copy.
6. Point a world_baked copy at it, `take_over_path` it onto `BAKED_SCENE`, and call the real `world.build()`.

Results:
- The saved copy has 2450 `instance=` refs and 0 sub_resources, and contains the moved and added nodes. No inlining.
  It is 92 KB smaller because the editor drops the redundant `metadata/kind` overrides; the prop roots carry `kind`.
- After the build: 2450 sites, the moved tree at M (< 0.01 m), the deleted tree gone, the added tree present.
- **Collision / spawning:** I used the spawner's own ground ray (spawner.gd:242-245, mask 1).
  - Before the edit, it hits T at T's spot, D at D's spot, and ground at M and A.
  - After the edit, it hits ground at T-old and D-old, `Tree_2_B_0001` at M, and `QA_Added_Tree` at A.
  - Zombie spawning at those markers therefore lands on top of the edited trees.
  - The spawn markers themselves are separate nodes in markers.tscn and are unaffected, as designed.
- **Map:** `MapUI._stamp_vegetation` dots moved to M and A, and are gone at T-old and D.
- `RESULT PASS (0 failing)`. The only log noise is the pre-existing `_adopt` owner warnings (see minor M3).

## 3. No runtime world generation: PASS
`grep -rnE 'SurfaceTool|ArrayMesh|MultiMesh|Noise|ImmediateMesh|randf|randi|RandomNumberGenerator|shuffle|pick_random' scripts/`
finds nothing that places world content:
- gun_mesh.gd:337-605 `ArrayMesh`: cuts and facets weapon viewmodels, not world content.
- loot_item.gd:115 `CylinderMesh`: the per-pickup glow disc.
- item_db.gd:364-403, loot_container.gd:119-120: the loot-contents roll, seeded by hash(loot_id, table). It is
  deterministic and does not place anything.
- network.gd:93 `randi()`: a session seed. world_builder.gd:37 says the seed "no longer changes anything".
- zombie.gd / player.gd / weapon_*: AI, recoil and spread.
- `noise` hits are gameplay noise (`emit_noise`, `noise_radius`), not procedural noise.
- No script references `res://tools`, `worldgen`, `placements.json` or `hand_map`. world_builder.gd:62 only
  `load(BAKED_SCENE)`.
- All of the files above are unchanged vs HEAD.

## 4. Render: PASS
xvfb, opengl3, 1280x720, same camera per site. Current tree vs the HEAD worktree (BAKED2 multimesh state):

| site | cur veg on-vs-off | HEAD veg on-vs-off | cur vs HEAD, veg on | cur vs HEAD, veg off |
|---|---|---|---|---|
| spawn | 0.75 / 1.39% | 0.74 / 1.35% | 0.08 / 0.14% | 0 / 0% |
| city | 0.39 / 0.76% | 0.38 / 0.75% | 0.01 / 0.02% | 0 / 0% |
| farm | 1.09 / 2.07% | 1.09 / 2.06% | 0.02 / 0.03% | 0 / 0% |
| dungeon | 1.29 / 2.15% | 1.29 / 2.14% | 0.03 / 0.05% | 0 / 0% |
| forest | 2.45 / 3.70% | 2.47 / 3.73% | 0.12 / 0.23% | 0 / 0% |

Values are mean px diff / share of pixels with diff > 40.
- With vegetation hidden the frames are identical, so the rest of the world is unchanged.
- With vegetation shown they differ on at most 0.23% of pixels. Vegetation contributes the same amount as before.
- Visual check of the forest frame: about 80-120 trees, plus bushes, rocks and grass tufts. Nothing is black,
  magenta, floating or sideways.

## 5. Suites: PASS
| suite | current | HEAD | note |
|---|---|---|---|
| verify_bake | VERIFY PASS (0 failing) | PASS | |
| t_editable_world | 18/0 | n/a | new |
| t_baked_world | 26/0 | 24/0 | |
| t_no_primitives | 5/0 | | |
| t_world | 10/0 | | |
| t_flatroads | 19/0 | | |
| t_forest | 51/0 | 54 in BAKED2 | 4 MultiMesh checks replaced by 3 node checks, per seed (git diff) |
| t_dungeon | 30/0 | | |
| t_dungeon_access | 16/0 | | |
| t_mp_main | 5/0 | | |
| t_inventory_ui | 37/0 | | |
| t_map_ui (headless) | 50/4 | 50/4 | same 4 lines (`diff` empty); headless-only |
| t_handmap | 17/1 | 17/1 | same failure at HEAD, see below |
| selftest | SELFTEST PASS | | |
| smoke_test | 50/0 | | |
| gl t_baked_world | 26/0 | | |
| gl t_forest | 51/0 | | |
| gl t_map_ui | 54/0 | | |
| boot `--quit-after 120` | exit 0, 0 ERROR/WARNING | | |

Error lines:
- selftest: 123 `float()` at hud.gd:243 and 123 `bool()` at death_ui.gd:78, 246 in total. These are the same two
  pre-existing lines as BAKED2 (264), and the count scales with run length.
- gl runs: only the N1 `Texture ... leaked 349524 bytes` shutdown lines (2 and 4), which are known from BAKED2.

**t_handmap predates this work.** The same check fails at HEAD 27dcd9e with the same 3 hits:
"no RNG / noise in world placement code" -> `loot_container.gd:119-120` (`RandomNumberGenerator.new()`,
`rng.seed = hash(...)`). This is the deterministic loot-contents roll. It places no world content, so it is a false
positive in the test, not a generation defect.

## Minor findings (non-blocking, owner MASTER CHIEF)
- **M1** tests/t_editable_world.gd:150-151 asserts that "spawn placement (blocked_by_dressing) follows the moved tree".
  `KR.blocked_by_dressing` (kaykit_resources.gd:176) has no caller in scripts/; only t_resources and t_editable_world
  call it. Runtime zombie spawning uses baked markers plus a physics ray (spawner.gd:240-256). That real path does
  follow the edit (item 2), but the test checks a function the game does not use. It should check the spawner ray.
- **M2** tests/t_editable_world.gd:93-161 edits the live world in memory. It never saves and reloads, so it does not
  cover the save round-trip. Item 2 of this gate covers that.
- **M3** tests/t_handmap.gd:142-155: whitelist the seeded loot roll (loot_container.gd:119-120) via SCAN_SKIP or a
  per-line allowance, so the suite goes green and a real placement RNG would stand out.
- **M4** world_builder.gd:95/102 `_adopt` reparents without clearing `owner`, which logs "will make owner ...
  inconsistent" warnings on every build. This is unchanged vs HEAD. Clearing `owner` before `add_child` would
  silence it.
- N1 from BAKED2 (GL texture leak lines at quit) is still open.

Cleanup: tests/qa_edit1_probe.gd, qa_edit1_render.gd, qa_edit1_veg.tscn, qa_edit1_world.tscn (and .uid), the
/tmp/qe1/head worktree and /tmp/qe1 were all removed after this run.
