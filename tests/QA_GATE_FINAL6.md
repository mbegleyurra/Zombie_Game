# QA GATE FINAL 6 (RAT) - 2026-11-18

Scope: (A) reload animations (MASTER CHIEF), (B) backpacks (GRIM REAPER), (C) handcrafted map (PLAGUEMASTER), plus t_no_primitives and smoke_test.
Source untouched; only tests/ edited. Godot 4.7.2, every suite run alone: `timeout 280 xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 --path . --script <suite>`.

Precondition note: no completion report from PLAGUEMASTER or MASTER CHIEF was found (no new tests/*.md, PROGRESS.md last edited 11-14). Gate was run against the tree as of 17:45: scripts/weapons/viewmodel.gd last modified 17:36:34, scripts/world/hand_layout.gd 17:32:25, both unchanged for the whole gate run. If either engineer lands changes after that, A/C must be re-gated.

| Area | Verdict |
|---|---|
| A Reload | **FAIL** (4 defects) |
| B Backpacks | **FAIL** (3 defects; all 5 suites pass) |
| C Handcrafted map | **PASS** (1 stale test fixed) |
| t_no_primitives, smoke_test | PASS |

---

## A. Reload - FAIL

Rendered: 9 weapons (pistol, ak, m4, shotgun, hunting, ar, ar_t1, ar_t2, ar_t3) at rest and at 25/50/75 % of an empty reload, 1280x720, clock advanced deterministically with `advance()`. Numeric probe sampled palm/mag/slide positions at 10-95 %.
t_hands_viewmodel: 236 PASS / 0 FAIL (it re-saves tests/shots/hands_*.png as usual).

Per weapon (from the images):
- All 9 at rest: trigger hand on grip, support hand on handguard/forend, stock visible, no floating fists. OK.
- Trigger hand stays on the grip (<= 0.04 m) through every mag reload. OK.
- shotgun: 25/50 % support hand carries a red shell to the loading gate, 75 % back on the forend. PASS.
- hunting: 25 % support hand fetches a round ~15 cm under the gun (by design, `_pose_bolt` pouch), 50 % round at the port, 75 % both hands at the receiver. Readable except bolt motion (A1).
- ak, m4, ar, ar_t1, ar_t2, ar_t3: fail A2, A3, A1.
- pistol: fails A2, A4, A1.

Defects (owner MASTER CHIEF):
1. **A1 No moving bolt / slide / pump / charging handle on any weapon.** `h._slide == null` and `_bolt_proxy == null` for all 9 guns. `_slide_z` animates (hunting 0.05 m from 40-60 %, shotgun pump 0.017 m at 85 %) but the measured slide movement is 0.000 m, so no bolt or slide motion is visible in any frame. File: scripts/weapons/viewmodel.gd (pivot capture in attach / profile setup; `_slide` never built).
2. **A2 New magazine never approaches the well, then teleports in.** Rifles and pistol: held mag sits 0.087-0.105 m from its seated position at 40, 50, 60 and 75 %, then 0.000 at 85 % (one-step pop of ~10 cm). The code comment intends the hand to be at `under` = grab + 4 cm before seating. At 75 % every rifle frame shows the mag well below the receiver. File: scripts/weapons/viewmodel.gd `_pose_mag` (lines ~775-813: `hold` offset 0.06 m and the `t_new..t_seat` segment).
3. **A3 Floating empty fist at 25 % on all six rifles.** The old mag has already fallen away (mag offset 0.21-0.24 m) and the support fist hangs 10-15 cm under/left of the receiver holding nothing. File: scripts/weapons/viewmodel.gd `_pose_mag` timing `ts` (t_gone vs pouch/new-mag phase).
4. **A4 Pistol model / reload mismatch.** pistol_001 renders as a revolver (cylinder, no mag well) while the animation does a box-magazine swap: a black box mag is held ~10 cm below the grip at 50/75 %. Files: scripts/weapons/gun_mesh.gd:69 (pistol model/clip) and scripts/weapons/viewmodel.gd (pistol style). Either a cylinder/speedloader reload or a magazine pistol model.

Limitation, not a defect: ak, m4, ar, ar_t1, ar_t2 all render rifle_001 and ar_t3 shares sniper_rifle_001 with hunting; documented as a pack limit in gun_mesh.gd:66-67.

## B. Backpacks - FAIL

Suites: t_backpacks 66/0, t_inventory_grid 45/0, t_inventory_ui 37/0, t_crafting 94/0, t_workbench 26/0 (exit 0, no script errors).
Logic OK: backpack_large equips, grid becomes 16x6 (+6 columns as specified).

Renders: worn backpack_large in game third-person camera, side, front and rear; inventory open with the large pack at 1280x720.

Defects (owner GRIM REAPER):
1. **B1 Worn Expedition Backpack reads as a small box at the hips.** Measured world AABB of the pack: y 0.29-0.90 m on a 1.8 m character, z 0.18-0.41 m behind the torso. It hangs from hip to mid-torso, its bottom is on the thighs, and its top half is hidden by the hair from side and rear. In the default third-person camera only a small block at belt level is visible; it does not read as a "huge frame pack". Files: scripts/world/item_db.gd:117 (`worn_size` 0.19x0.26x0.10) and scripts/player/player_model.gd (`BACK_OFFSET`, set_backpack line ~145).
2. **B2 Large-pack inventory overflows 1280x720.** With 16 columns (~84 px cells, ~1352 px needed) the 16th column is cut off at the right edge; the footer "Space x / 96 cells" and the DECONSTRUCT (Del) / UNEQUIP EXPEDITION PACK buttons are clipped at the bottom/right. File: scripts/ui/inventory_ui.gd (cell size / layout not scaled to the grid width).
3. **B3 Slot item names overlap stack counts** ("5.56x45mm Rounds" over "x3", "9mm Rounds" over "x93", "Canned Food" over its count). File: scripts/ui/inventory_ui.gd `_slot_label` / slot layout.

## C. Handcrafted map - PASS

- Grep: no layout RNG left. `world_builder.gd:65` forces `world_seed = HandLayout.HAND_SEED`; terrain reads data/hand_map/terrain.bin with no runtime noise. Remaining RNG is only weapon spread, muzzle flash, zombie behaviour, player shirt colour (seeded by peer id) and loot rolls.
- Object-for-object: world built with seed 1 and seed 987654321, every node dumped (class, path, global transform to 1 mm, mesh, loot_id/contents/table). Both builds: 15,075 nodes, 12 locations. Raw diff 1,700 lines, all of them animated transforms: car Y only (physics settling, X/Z/rotation identical), pickup `/Visual` spin/bob, Sun/Moon angle. With those transforms masked: **0 differences**, including all container contents.
- Suites: t_handmap 15/0, t_handworld 34/0, t_dungeon_access 16/0, t_map_ui 54/0 after fix (below).
- Renders (top-down full map, town and farm close-ups; ground frames at spawn, town, Hartley Farm): roads, town grid, tall buildings, farms, trees, vehicles all placed sensibly; no buildings on roads, nothing floating seen. Observation only: in the orthographic top-down frames from 400-600 m the terrain surface is not drawn (buildings and roads are), probably distance culling; does not affect play or the in-game map texture. Cause not verified.

Test fix (RAT, tests/ only):
- **t_map_ui "player marker follows movement" was a stale test, not a map bug.** It teleported the player with y kept at 0.0003 to (12, -9) where the handcrafted relief is ~0.59 m; depenetration slid the body to (8.66, -8.23). The marker equalled the real player position exactly. The test now places the player on `terrain.height_at()` at the target. tests/t_map_ui.gd: 53/1 before, 54/0 after.

## Other

- t_no_primitives 5/0, smoke_test 50/0 (`RESULT failures=0`).
- Every suite prints "2 resources still in use at exit" at quit: benign, pre-existing.
- Probe files deleted: tests/r_qa6_pack.gd, r_qa6_reload.gd, r_qa6_reload_num.gd, r_qa6_worlddiff.gd, r_qa6_map.gd, r_qa6_mapui_dbg.gd (+ any .uid). Frames and logs remain in /tmp/qa6/ (shots/sheet_*.png, shots/reload/, shots/map/, world_0.txt, world_1.txt).
