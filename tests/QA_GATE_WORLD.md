# QA gate round 2: handcrafted world

Tester: RAT. Date: 2026-11-16. Godot 4.7.2. Only files under tests/ were written (t_qa_hud_build.gd, t_qa_world.gd, this report, the round 2 section of QA_GATE_DUNGEON_BUILD.md).

## (1) GRIM REAPER re-test
Both fixes verified; see the Round 2 section of tests/QA_GATE_DUNGEON_BUILD.md. t_qa_walk_build (xvfb): 0 FAIL over 5 runs after the fix. t_qa_hud_build: 36/0.

## (2) PLAGUEMASTER handcrafted world
Own probe `tests/t_qa_world.gd` (separate from t_handworld, recomputes geometry from layout data and the built world). `t_handworld.gd` itself: 0 FAIL, 0 script errors.

| Check | Result |
|---|---|
| Layout identical across runs | PASS. Separate processes with seeds 1, 424242 and 7: signature files (spawn, locations, every road segment, footprints, vehicles, spawn slots, 21x21 height samples, loot positions; 855 lines) are byte-identical, md5 576cbe2d31931946679b3109e2b1e12a. No RNG in hand_layout.gd; car paint uses fixed seed 77001. |
| Roads not a star | PASS. Max degree outside the city is 4 (vertex 24,12). 3 of 21 countryside segments lie within 12 m of that vertex. Roads run in 3 of 4 orientation bins, plus a closed Orchard Loop. |
| City district exists | PASS. 24 towers, all inside the city box, each with a neighbour within 25 m, tallest 38 m. |
| Player does not spawn in the city | PASS. Spawn (0,0) is 127 m from the city centre. All 8 spawn slots are outside the city and every hand building, and their capsule volumes hit no static collider. |
| Roads and city reachable | PASS. All roads form one connected component. Every location, the city streets and the dungeon gate touch the spawn component (counting the driveways world_builder adds). Without those driveways 5 farms would be unreached; that is expected. |
| Vehicles on roads | PASS. 9 drivable cars, all within 1.1 m of a road, connected to the spawn component, none inside a building, all near terrain height. 8 city wrecks sit on streets. |
| Roads do not run through buildings | FAIL. The driveway from Harlan Freight Warehouse, (158,-146) to (112,-24), crosses city towers [124.5,-55.5,13x14,h20] and [124.5,-36.5,14x12,h16]. A road, and the terrain painted as one, cuts through two solid towers. Cause: `_plan_locations` in world_builder.gd snaps the gate to the nearest country-road point, which is the City Link end at (112,-24) on the far side of the city. |
| t_handworld asserts real behaviour | Mostly. It checks real world state and passes 0 FAIL. Gaps: it does not detect the road-through-tower defect; its determinism check compares two worlds in ONE process (my cross-process check agrees); `lamps` check is only a child count. |

New failures versus the known list (t_forest, t_map_ui):
- t_dressing: 3 FAIL (every seed, "nothing within 20 m of the spawn centre"). Not failing at HEAD. Likely cause: spawn moved to a plain flat pad with no dressing. Not confirmed.
- t_kenney_dress: 4 FAIL (every seed, road centreline blocked by signpost2 at (70,-64), road#32, nearest location hospital 33.1 m). Not failing at HEAD.
- t_mp_main: 1 FAIL, "world built from Net.world_seed (main world seed=20260101, Net seed=424242)". Expected consequence of the world ignoring the seed; the test needs updating or the contract needs a decision.
- t_qa_recoil 9 FAIL and t_kenney 2 FAIL: pre-existing at HEAD (recoil 0.75 vs 0.5 from RECOIL_GAIN; stale SpringArm check). Not new.
- t_r3_mp_main, t_r4_mp4, t_r5_late failed last round and pass now.
- t_r4_zombies: 1 FAIL ("runner closes more distance than walker", 6.2 vs 9.0 in the suite). Over 3 reruns: 1 fail (3.6 vs 9.0), 2 passes with no FAIL lines, plus the in-suite failure. Flaky timing test. Not compared against HEAD; unrelated to the world as far as I can tell.
- t_forest: 3 FAIL (one per seed, "no loot item inside a forest collider (1)"). This is the known failure; I did not capture the item name, so I could not confirm it is Loot_206 in every seed.
- t_map_ui: 4 FAIL, the known four (canvas size 0x628, NW corner, north drawn higher, mouse recapture).

## (3) Leftover probes
tests/probe_entrance.gd and tests/probe_models.gd do not exist (`ls tests/probe_*` finds nothing). Nothing to delete.

## (4) Full run (sequential, headless, counts from log greps)
All tests/t_*.gd except the display-only t_qa_walk_*, my t_qa_world.gd (needs args) and t_qa_mouse_probe.gd, plus scripts/net/selftest.gd and scripts/player/smoke_test.gd.
- Real FAIL lines: 27 (dressing 3, forest 3, kenney 2, kenney_dress 4, map_ui 4, mp_main 1, qa_recoil 9, r4_zombies 1).
- Script errors: 198, all in selftest (known); 0 elsewhere.
- smoke_test: 50 PASS, 0 FAIL.
- t_qa_world run separately: 1 FAIL (road through towers), all other checks pass.

## Incident
During this run I executed `git stash -q` in the repo by mistake after the suite finished. It stashed the engineers' tracked edits for a few seconds. I ran `git stash pop` straight away: the stash dropped cleanly and `git status` shows the same 6 modified files and the same untracked files as before. Any run that read those files in that window could have seen the old versions, and file mtimes changed. No tracked file content was lost, as far as git diff --stat shows.

## Verdicts
- (1) GRIM REAPER fixes (duplicate withdraw, HUD build bar): PASS. Owner: GRIM REAPER (engineer-3).
- (2) Handcrafted world: SENT BACK. Reasons: the Harlan Freight driveway runs through two city towers; t_dressing (3), t_kenney_dress (4) and t_mp_main (1) fail new versus HEAD; t_handworld does not catch the road-through-tower defect. Owner: PLAGUEMASTER.
- (3) Leftover probes: PASS. None present. Owner: RAT.
- (4) Full suite: PASS as a count (27 FAIL lines, 198 selftest script errors, smoke 50/0), but 9 of the 27 FAIL lines are new from the world work; see (2). Owner: RAT for the run, PLAGUEMASTER for the new failures.
