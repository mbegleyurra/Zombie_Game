# QA gate round 3: PLAGUEMASTER world rework re-gate

Tester: RAT. Date: 2026-11-16. Godot 4.7.2, every run under xvfb-run, sequential.
Only files under tests/ were edited (t_qa_world.gd, this report). All baselines and mutations ran on copies in /tmp/qa2; the repo was not touched.

## What was gated
Committed HEAD 21d6475 (contains PLAGUEMASTER's world_builder / kenney_dressing / kaykit_resources / t_handworld / t_mp_main changes, plus another engineer's city kit: city_kit.gd, road_kit.gd, hand_builder.gd). Original reference: 195707b.

The live tree changed twice while I tested (city kit landed in 21d6475; later uncommitted edits to terrain.gd, world_builder.gd, pickup_visuals.gd, t_flatroads.gd by someone else, 20:33-20:38). Verdicts below are for a frozen snapshot of 21d6475 plus my t_qa_world.gd edit (/tmp/qa2/snap). My first named and full runs (before the city kit commit) were discarded as stale.

## Verdicts

| # | Item | Verdict | Evidence | Owner |
|---|---|---|---|---|
| 1 | No driveway or road crosses a tower footprint | PASS | t_handworld new check: 0 crossings (0.25 m sampling, 1 m margin). t_qa_world: 0 towers crossed. With the ORIGINAL world_builder (195707b) both fail: 3 crossings (Harlan Freight driveway (158,-146)>(112,-24) through towers at (143.5,-124.5), (124.5,-55.5), (124.5,-36.5)). | PLAGUEMASTER |
| 2 | Layout byte-identical across runs | PASS | t_qa_world signature (spawn, locations, roads, footprints, vehicles, spawn slots, 21x21 heights, loot positions) md5 e82fce5cce821b545abb93656e607381 for seeds 1, 424242, 7 (snapshot) and 99, 5 (live tree), separate processes. Limit: the signature does not cover the 1738 road_kit tiles. | PLAGUEMASTER |
| 3 | Roads are not a star | PASS | Max degree outside the city 4, at (24,12); 21 countryside segments; roads in at least 3 of 4 orientation bins; at most a third of segments within 12 m of one point. | PLAGUEMASTER |
| 4 | City exists and is not the spawn | PASS | 24 towers inside the city box, all clustered; spawn (0,0) is 127 m from city centre; all 8 spawn slots outside the city and every building, capsules clear of static colliders. | PLAGUEMASTER |
| 5 | Everything reachable | PASS | 0 unreached locations; one connected road network; city streets, dungeon gate and all 9 drivable cars in the spawn component. | PLAGUEMASTER |
| 6 | Tests not vacuous | PASS with one caveat | Mutation (original world_builder + kenney_dressing + kaykit_resources, current tests): t_handworld 1 FAIL, t_dressing 3 FAIL, t_kenney_dress 4 FAIL, t_qa_world 1 FAIL, t_forest 3 FAIL. Each new check catches the old defect. t_handworld also has a self-test that a road laid through a building is flagged. Caveat: t_mp_main passes against the ORIGINAL code too, because the original already ignored the seed; I did not verify it would fail if the world used Net.world_seed. | PLAGUEMASTER |
| 7 | No regressions in t_map_ui, t_qa_recoil, t_kenney, t_r4_zombies | PASS | Against 195707b: t_map_ui 54/0 both; t_qa_recoil 9 FAIL both (RECOIL_GAIN, known); t_kenney 6 FAIL both (SpringArm x2, non-food pickup look x3, player Kenney models; not caused by the rework); t_r4_zombies "runner closes more distance than walker" is a timing flake, fails on both trees in repeated runs (original 3 of 3, HEAD 4 of 6). | RAT (baseline) |
| 8 | tests/probe_pm.gd is gone | PASS | `ls tests/probe_pm.gd`: no such file. | PLAGUEMASTER |
| 9 | Whole suite, real FAIL lines and script errors | PASS as a count, with two stale tests | Snapshot of 21d6475: 27 FAIL lines, 0 script errors outside selftest (selftest 196, known). Breakdown: t_qa_recoil 9, t_kenney 6, t_r4_mp4 6, t_r3_mp_main 2, t_r4_pause 1, t_thirdperson 1, t_r4_zombies 1 (flaky), t_skeletons 1 (flaky). Original 195707b: same set, t_r4_mp4 9. smoke_test 50/0. t_vehicles 35/0, t_dungeon_access 16/0, t_forest 54/0, t_dressing 33/0, t_kenney_dress 32/0, t_mp_main 5/0, t_handworld 34/0, t_qa_world 59/0. | RAT |

## Sent back (minor, not a blocker for the world)
- t_r3_mp_main (2 FAIL) and t_r4_mp4 ("host world built from Net seed", "client N used host seed") still assert the old contract that the world follows Net.world_seed. PLAGUEMASTER updated t_mp_main for the fixed hand seed but left these two. They fail identically at 195707b, so this is stale tests, not a regression. Owner: PLAGUEMASTER; fix is to assert HAND_SEED as t_mp_main now does. The remaining t_r4_mp4 failures (peer movement, left player freed) fail on the original too and look timing related; not diagnosed.

## Flaky, not regressions
- t_skeletons "approaching the far marker spawns its rogue": HEAD snapshot failed 1 of 4 runs, original 195707b failed 2 of 4 (1 and 3 FAIL lines). Pre-existing.
- t_r4_zombies: see item 7.

## Not gated: live tree after 20:33
In the live tree at about 20:36, with uncommitted edits to terrain.gd, world_builder.gd (cottage pads at road-bed height), pickup_visuals.gd and new tests, t_resources failed "no pickup is buried below the terrain (2)". It passes on both HEAD 21d6475 and 195707b, so it comes from that uncommitted work. I did not re-run the live tree afterwards. Whoever owns the terrain / cottage pad change should re-run t_resources before committing.

## Test change by RAT
tests/t_qa_world.gd: the road-through-tower check sampled each segment 9 times (about 16 m apart on the 130 m driveway) and found only 1 of the 3 towers the old driveway crossed. It now samples every 0.25 m. Confirmed it still flags all 3 on the original code and passes (0 crossings) on HEAD.

## Overall
PLAGUEMASTER's world rework: PASS on all requested items. SENT BACK only for the two stale seed-contract tests above.
