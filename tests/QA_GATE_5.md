# QA Gate 5: from-scratch object removal (PLAGUEMASTER)

Date 2026-11-16. Read tests/PRIMITIVE_AUDIT.md first. No game code edited. Run sequentially from the project folder under `xvfb-run` (opengl3, 1280x720), `timeout 280` each. Logs: /tmp/qa5/logs.

## Verdict: FAIL (1 blocking visual defect, tests are green)

All 13 requested scripts pass, but the Location shells (audit row 2) look broken on screen. The tests cannot see it.

## Test results

| Script | exit | PASS | FAIL | SCRIPT ERROR |
|---|---|---|---|---|
| t_no_primitives | 0 | 5 | 0 | 0 |
| t_workbench | 0 | 26 | 0 | 0 |
| t_kenney_walker | 0 | 14 | 0 | 0 |
| t_handworld | 0 | 34 | 0 | 0 |
| t_citykit | 0 | 35 | 0 | 0 |
| t_city_interiors | 0 | 15 | 0 | 0 |
| t_resources | 0 | 19 | 0 | 0 |
| t_vehicles | 0 | 35 | 0 | 0 |
| t_forest | 0 | 54 | 0 | 0 |
| t_flatroads | 0 | 19 | 0 | 0 |
| t_inventory_ui | 0 | 37 | 0 | 0 |
| t_crafting | 0 | 88 | 0 | 0 |
| smoke_test | 0 | 50 | 0 | 0 |

Total 431 PASS, 0 FAIL, 0 script errors, 0 parse errors. The only `ERROR` lines are exit-teardown noise ("2 resources still in use at exit", GL texture leaks in t_forest/t_resources/t_vehicles). I did not compare them to a pre-change baseline.

## Behaviour checks

- Loot containers still lootable: PASS. My own probe (/tmp/qa5/p_loot.gd, outside the repo) built one container of each of the 13 kinds. Each has a Kenney `Body` with meshes, a box collider of the original size, and an "interactable" prompt. `interact()` opens it, and a second interact is refused. 12 of 12 sampled world containers opened and rolled contents (66 checks passed). The one FAIL line was my probe's mistake: the 26 dungeon containers use a `Model` child (KayKit) instead of `Body`. They all have meshes (0 missing).
- Workbench crafts: PASS (t_workbench: bench required, cost taken, craft signal, refund, craft closes after removal; t_crafting 88/88).
- Zombies render with the Kenney model: PASS. t_kenney_walker says all three kinds have the Kenney skeleton. The screenshots show textured Kenney characters, with no boxes or capsules and no missing textures.
- Probe files in tests/: none new. `t_qa_mouse_probe.gd` and `t_r3_hitprobe.gd` are tracked, pre-existing tests. My probes and logs are in /tmp/qa5 only. I added tests/shots/qa5/ (5 PNGs) and this report.

## Defects

### D1 (BLOCKING): hospital, church and other location shells have no walls
- Evidence: tests/shots/qa5/hospital_a.png, tests/shots/qa5/church.png. I viewed the raw pixels. Walls render as a lattice of thin blue-grey posts and crossbars, with no wall faces, windows or doors visible. Roofs are thin, flat salmon planks that fan out, leave gaps and overhang unevenly. The interior is visible from outside.
- Cause (code read plus screenshot; I did not open the .glb): `building_factory.gd` `_box_model()` (line 116) maps every tall, thin box to `survival/structure-metal-wall.glb`, and `_box()`/`fit_box()` stretch it non-uniformly over the full wall segment (up to 12-24 m long). That model looks like an open metal frame, so it renders as posts and bars. Roofs and floor slabs get `survival/floor.glb` stretched into long planks. Colliders are kept, so the walls are solid but invisible.
- Owner: `scripts/world/building_factory.gd` (`_box_model`, `_box`, `_model_at`; wall/roof callers at lines ~324-572). Engineer: PLAGUEMASTER.
- Suggested fix: use a solid wall model, or tile a fixed-size wall panel along the segment instead of stretching one piece, and tile roofs and floors the same way.
- Why the gate missed it: `t_no_primitives` only checks that no visible mesh is a Box/Cylinder/etc. A stretched model passes. Suggest it also assert that wall segments render a solid face (for example, the mesh AABB fills the segment) or compare a screenshot.

### D2 (minor, from the vision read of containers_row.png; I did not view this one's raw pixels): container models are a loose match
- Fridge, locker and evidence locker all use `mini-arcade/vending-machine.glb`, so they read as vending machines. Cupboard and med cabinet share `shelf-boxes`; shelf and weapon rack share `shelf-bags`. X/Z scale is clamped to 0.6-1.8 and can look squashed.
- Owner: `scripts/world/loot_container.gd` (`MODELS`, `setup`). Engineer: PLAGUEMASTER. Cosmetic; lootable and collidable.

### D3 (minor, from the vision read of 1_front_idle.png): zombie variants barely differ
- Runner and bloater are only slightly different from the walker in tint and proportion. The bloater may look squashed.
- Owner: `scripts/zombies/zombie.gd`. Engineer: PLAGUEMASTER. Cosmetic.

## Not checked
- Cottage and building-prop screenshot beyond hospital/church: the HandWorld children are anonymous nodes, so I did not capture a cottage or the city kit buildings. Hospital and church were captured; police station, gas stations, warehouse and farms were not. They share `_wall`/`_box`, so D1 likely applies.
- Player-built pieces (audit row 9) were covered by t_workbench and t_base_build-style asserts only, not by screenshots.
- Zombie arm/leg animation was judged from stills only.
