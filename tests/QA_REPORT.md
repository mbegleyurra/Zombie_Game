# QA REPORT: Dead Acres (Zombie_Game), full pass by RAT, 2026-11-15

Tree under test: HEAD 3ed5daf plus uncommitted KayKit work (gun_mesh, weapon_db, item_db, world_builder, spawner, new skeleton/dungeon/forest/resources scripts). Godot 4.7.2 headless unless noted. Logs: /tmp/qa/ (not in the repo).

## 1. Summary

Two complete runs of `tests/run_kenney_all.sh` (38 scripts each). Run 1 was before my fixes, run 2 after.

| Result | Run 1 (before fixes) | Run 2 (after fixes) |
|---|---|---|
| Scripts with 0 failures | 35 of 38 | 36 of 38 |
| Failing scripts | t_forest (2), t_kenney (1), t_rifle (parse/script error, timeout exit 124) | t_forest (2), t_r5_late (2, flaky) |
| Parse errors in the existing tests | 0 (the t_rifle script error was a runtime access error, see D5) | 0 |

Per-test results (pass count / fail count), run 2 unless noted:

| Test | Result | Note |
|---|---|---|
| smoke_test | 47/0 | see section 2; 12 runs before fix: 3 failed; 20 runs after fix: 0 failed |
| t_core | 97/0 | |
| t_dressing | 33/0 | |
| t_dungeon | 30/0 | assertions not individually reviewed, see "not verified" |
| t_forest | 52/2 FAIL | D3 |
| t_kenney | 177/0 | was 176/1 before fix (D4) |
| t_kenney_dress | 32/0 | road scan seeds 20260101, 31337, 7, 424242 clean |
| t_kenney_walker | 14/0 | |
| t_kenney_walker_fit, t_kenney_walker_wind, t_kenney_wind, t_r3_polys | 0/0 | diagnostic printers, no assertions; they cannot fail |
| t_loot_r2 | 24/0 | |
| t_mp_main | 5/0 | real main.tscn host flow, single process |
| t_mp_real | 12/0 | two real processes over ENet loopback |
| t_player_model | 21/0 | |
| t_r3_adjudicate | 8/0 | |
| t_r3_guns | 30/0 | |
| t_r3_hitprobe | 2/0 | |
| t_r3_mp_main | 16/0 | two real processes |
| t_r3_zombies | 11/0 | |
| t_r4_equip | 5/0 | |
| t_r4_mp4 | 49/0 | 4 real processes |
| t_r4_pause | 24/0 | |
| t_r4_rat_equip | 19/0 | |
| t_r4_ui | 26/0 | |
| t_r4_world | 48/0 | |
| t_r4_zombies | 32/0 | |
| t_r5_dmg | 11/0 (3 extra runs also 11/0) | engine ERROR lines in log, D6 |
| t_r5_late | 10/2 FAIL in run 2; 12/0 in run 1 | flaky, D2 |
| t_r5_walk | 45/0 | |
| t_resources | 19/0 | |
| t_rifle | 44/0 | was a script error before fix (D5) |
| t_round2 | 26/0 | |
| t_skeletons | 59/0 | |
| t_solo, t_solo_r2 | 9/0, 3/0 | |
| t_world | 10/0 | |
| selftest (scripts/net) | PASS | two processes, uses a stand-in node, not the real player |
| t_qa_sens (new, mine) | 9/0 | mouse sensitivity, restores settings.cfg |

Multiplayer tests: t_mp_real, t_r3_mp_main, t_r4_mp4, t_r5_late, t_r5_dmg and selftest launch real second processes over ENet loopback. None only simulates a peer. selftest alone uses a stand-in player node.

## 2. Requested items

**Smoke test flake.** 12 runs before the fix: 3 failed (25%), always the first bullet/headshot hit on the zombie. Root cause, measured with a diagnostic script (/tmp/qa/diag_hit.gd): 100 first-shots at a frozen zombie 14 m away. With the stock pistol cone (spread_deg 1.1) 63/100 hit; with the cone zeroed 100/100 hit. The player camera ray is at y=1.62 and the zombie capsule top is at 1.7, so a random cone often passes over the crown. It is test setup (random spread), not hit timing and not a collision-shape regression. Fix: the test zeroes spread on that first shot. After the fix: 0 failures in 20 runs plus 1 in the full run, 47/47 each time. Note this also means a player aiming at centre of mass from 14 m is not affected; aiming at the head at range is genuinely random.

**t_kenney player-scene check.** Confirmed stale test, not a player_model.gd bug. PlayerModel (commit 86f33b7) intentionally loads the avatar from `res://assets/kenney/mini/`. Isolation: a copy of the project with `PlayerModel.build` forced to `return false` gave 177 pass / 0 fail. The assertion now rejects Kenney models outside the Avatar node (0 outside, 1 inside). 177/0 in both a standalone run and the full run.

**KENNEY_REPORT D8/D9/D10** (details appended to KENNEY_REPORT.md):
- D9 (road car, seed 7): not reproduced. Road scan seed 7: 0 of 2956 samples blocked; seeds 20260101 (2516), 31337 (2497), 424242 (2814) also 0.
- D10 (barrel on road, seed 7): not reproduced, same scan. World generation has changed since the report (forest and dungeon change placement), so it may have moved rather than been fixed. Closed for these four seeds only.
- D8 (walker head wider than capsule): still open, Low. Capsule r=0.34, h=1.70; head vertex extents up to radius 0.51 and torso/arm z up to 0.67. Ray grid at y=1.5 and 1.7 only lands within +-0.2 m, so roughly 0.1-0.3 m of head and 0.3 m of arms at the sides cannot be hit.

**t_r5_dmg clean pass count:** 11 PASS / 0 FAIL, "RESULT failures=0", in 3 runs on the working tree and 2 runs on a clean `git archive HEAD` copy, plus the two full runs. The log is not clean: it carries engine RPC ERROR lines (working tree 17-41 lines per run, HEAD 8). The "Node not found" DamageRelay errors are pre-existing (HEAD reproduces them) but the count is higher on the working tree. See D6.

**settings.cfg cleanup.** Could not reproduce a leak from the tests: the real file (`~/.local/share/godot/app_userdata/Dead Acres/settings.cfg`, contents `[controls] sens_pct=100.0`) kept the same mtime and md5 across t_r4_ui, t_r4_pause and my t_qa_sens. The file's mtime (04:03) predates this run. Risk that remains: `PauseMenu.set_sens_pct` writes to the real user:// path, so any future test that moves the slider overwrites the player's setting. t_qa_sens backs the file up and restores it; the existing tests do not touch the slider.

**Doorway margin (0.9 / 1.0 / 1.2 m gaps, centred and +-5 cm off-centre, rotation 0 and 45 degrees), real colliders, test_move over 6 m:**
- walker (lateral half-extent 0.36), runner (0.32), warrior, minion, rogue, mage (0.36 each): pass every case at 0.9, 1.0 and 1.2 m.
- bloater (half-extent 0.50, full width 1.00): BLOCKED at 0.9 and 1.0 m, passes 1.2 m. That is expected from its width; the bloater cannot use 0.9 or 1.0 m doors. Whether that is intended is a design call.
- I did not find or isolate a 4 mm margin on the HeadCollision sphere. I measured only each body's overall lateral extent, so the specific 4 mm claim is neither confirmed nor refuted.

## 3. New features

- Skeletons (t_skeletons 59/0): warrior, minion, rogue, mage, spawner and spawn markers covered by the test; all five kinds pass the doorway check. Render check below.
- KayKit forest: t_forest 52/2 (D3). Instances on roads: 0, in locations: 0 on all seeds tested.
- Resource Bits: t_resources 19/0.
- Dungeon: t_dungeon 30/0. Rendered and looked at, see section 5.
- Rifle: t_rifle 44/0 after the test fix (D5). Covers weapon_db, gun_mesh (59 parts, 912 tris, muzzle z=-0.85), item_db, ammo, loot tables.
- Mouse sensitivity: t_qa_sens 9/0 (clamp 25..300, persists, Hud applies it to the local player and follows later changes).
- Day/night brightness (measured mean luma of the player view, llvmpipe, 1280x720): 6:00 0.347, 9:00 0.541, 12:00 0.560, 18:00 0.341, 21:00 0.108, 00:00 0.117, 03:00 0.099. Night is dark but readable: terrain, buildings and HUD visible in the midnight screenshot. The pistol view model is near black at night.
- Player model arms not aiming: known, not retested.

## 4. Defects

| ID | Sev | Defect | Repro | Evidence | Suspect |
|---|---|---|---|---|---|
| D1 | Medium | HUD vitals text drawn twice: old "HP/STA/FOOD/WATER" label overlaps the new HEALTH/HUNGER/THIRST bars | run the game, look top-left | I zoomed the screenshot myself: "HP 100 ST" over "HEALTH", "FOOD 100 WATER 100" over "HUNGER", cut by the bars; only THIRST row is clean | `scripts/player/player.gd:696-729` (`_lbl_stats`) duplicates `scripts/ui/hud.gd:247-249`. Not fixed (removing the old label is a design choice; 2 files) |
| D2 | Medium | Late-join test flaky: early client sees 0 zombies | `sh tests/run_r5_late.sh` | working tree: 12/0, 10/2, 10/2, then 10/2 in full run 2; clean HEAD: 1 of 3 runs failed. Fails: "client 1 (early) sees the 3 pre-existing zombies (0 visible)", "early joiner sees 4 zombies (0)". Log: `Node not found: "Main/Spawner/ZombieMP"`, `ID 3 not found in cache of peer 1`, `Parameter "spawner" is null` | spawn-packet race (spawner path not ready when host sends); the old D1 from ROUND4 is not fully fixed. Not fixed |
| D3 | Low-Med | Forest colliders conflict with other content | `t_forest` | seed 31337: forest box at (-99.5, -1.16, 202.6) overlaps `Props/PropCollision`; seed 20260101: loot 213 (silver_nuggets) at about (-99.4, -0.08, ...) sits inside a forest collider, so it may be unreachable | `scripts/world/kaykit_forest.gd` placement filter ignores props and loot. Not fixed |
| D4 | Low | t_kenney assertion stale | `t_kenney` | 176/1 before | fixed in the test (see below) |
| D5 | Low | t_rifle crashed and hung to timeout | `t_rifle` before fix | `SCRIPT ERROR: Invalid access to property or key 'dungeon_chest' on a base object of type 'Dictionary'`, exit 124, only 16 PASS | `ItemDB.table_names()` now also lists KayKit tables that are not in `ItemDB.TABLES`; the test indexed TABLES by that list. Fixed in the test; the mismatch itself may still bite other callers |
| D6 | Low | RPC errors in t_r5_dmg log | `t_r5_dmg` | 17-41 error lines per run on the tree vs 8 on HEAD ("Node not found", "Failed to get path") although all 11 assertions pass | RPC to a node that does not exist yet on a joining peer; pre-existing but worse on the tree. Not fixed |
| D7 | Low | Light leak at the top of the dungeon hall wall (green/orange slivers between wall top and ceiling beams) | screenshot 3_dungeon_hall | vision-model description only, not independently checked by pixel | `scripts/world/dungeon_builder.gd`. Unconfirmed |
| D8 | Low | walker head/arms wider than hit capsule | see section 2 | see KENNEY_REPORT | `scripts/zombies/zombie.gd` collision shapes. Not fixed |
| D9 | Info | Bloater cannot pass 0.9 or 1.0 m doorways | section 2 | test_move BLOCKED | design |

## 5. Runtime and rendering

- `godot --headless --quit-after 300` on the project: exit 0, 0 ERROR/WARNING lines.
- Fresh import of a copy without `.godot/`: finished, 0 ERROR/WARNING/Parse Error lines (the log was filtered on those words).
- Display: X server on :0.0 is up, renderer was llvmpipe (software), gl_compatibility. Screenshots were actually captured at 1280x720 by `/tmp/qa/render_qa.gd`: player view, dungeon approach, dungeon hall, three skeletons, midnight view. Saved under /tmp/qa/shots/ (not in the repo).
- What I saw (descriptions of images 2-4 and the midnight view come from the vision tool, not from my own eyes; I looked at the HUD crop myself): hilly low-poly terrain with pines, farm buildings, utility poles and fog; a stone dungeon sunk into a crater, with pillars, hex floor, banner and a door; dungeon hall with torches and wooden ceiling beams, no chest in that frame; warrior, rogue and mage skeletons upright in idle pose, feet on the floor, weapons attached. The skeleton shot was taken at about 3 m, so fine weapon and clipping detail is not verified.
- Dungeon entrance as a staircase was not clearly visible from the approach shot; I did not walk it in the render. The reachability tests in t_dungeon pass.

## 6. Assets

- License.txt exists for all 5 Kenney packs and all 4 KayKit packs.
- 875 model files (`.glb`/`.gltf`) and 919 `.import` files.
- res:// path scan over `.gd/.tscn/.tres/.cfg` (203 references): 1 missing, `res://assets/kenney/food/__missing__.glb`, referenced only in `tests/t_kenney.gd`, which is a deliberate fallback test. No broken res:// paths in game code.
- No uid or orphan warnings in the fresh import log.

## 7. What I changed

1. `tests/t_rifle.gd`: iterate `ItemDB.TABLES.keys()` instead of `ItemDB.table_names()` (D5). t_rifle 44/0.
2. `scripts/player/smoke_test.gd`: zero spread/move spread/bloom before the first shot (smoke flake). 0 failures in 20 runs plus the full run.
3. `tests/t_kenney.gd`: player-scene assertion allows the Avatar's Kenney mini model (D4). 177/0.
4. `tests/t_qa_sens.gd`: new test, mouse sensitivity (9/0).
5. `tests/KENNEY_REPORT.md`: appended the 2026-11-15 update. `tests/QA_REPORT.md`: this file.
No game code was changed. The `.godot/` cache files show as modified in git because of the imports; I did not touch them deliberately.

## 8. Not verified

- Any play-through by a human: aiming, feel, rifle recoil, reload animation on screen, zombie/skeleton behaviour in motion, mage bolt visuals, chest opening, skeleton fights in the dungeon. Tests assert logic; screenshots are static.
- Individual assertions in t_dungeon, t_resources, t_skeletons: I read the pass counts, not each assertion (chests, loot tables, guard markers, entrance reachability are presumed covered by those tests).
- Rendering was software (llvmpipe) only; no GPU check.
- Whether D2 and D6 are the same root cause; I did not trace the spawner code.
- HeadCollision 4 mm margin (see section 2).
- No fix was verified under repeated runs other than smoke_test (20 runs); t_kenney and t_rifle were verified once standalone and once in the full run.
