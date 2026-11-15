# Dead Acres - Round 5 Test Report (RAT, tester)

Godot 4.7.2 headless, software-rendered VM, 2026-11-14. Only `tests/` edited. No git init, no commit.
Command form: `godot --headless --path . --script res://tests/<t>.gd` (mp tests under `timeout 280`).

## 0. Run validity
Engineers were still editing while I tested (damage_relay.gd, player.gd, zombie.gd, spawner.gd, network.gd, main.gd, building_factory.gd, terrain.gd, world_builder.gd; last game-file edit 17:26:50 zombie.gd, then smoke_test.gd 17:28:53 and PROGRESS.md 17:29:22).
My first full run (17:23-17:31) overlapped the 17:26 edits (Zombie/DamageRelay parse errors, ENet port clashes, killed processes). I DISCARDED it entirely. All numbers below come from a second full run started 17:31:31 after 129 s of no game-file changes; nothing outside tests/ changed during it (checked afterwards).
Not judged: frame rate, visuals, real mouse/keyboard and the live click-to-fire path, mouse capture, 5+ peers, real-network latency (loopback only).

## 1. Full run (final)
| Test | exit | PASS | FAIL |
|---|---|---|---|
| t_core | 0 | 97 | 0 |
| t_world | 0 | 10 | 0 |
| t_mp_main | 0 | 5 | 0 |
| t_loot_r2 | 0 | 24 | 0 |
| t_solo_r2 | 0 | 3 | 0 |
| t_round2 | 0 | 26 | 0 |
| t_solo | 0 | 9 | 0 |
| t_mp_real | 0 | 12 | 0 |
| t_r3_adjudicate | 0 | 8 | 0 |
| t_r3_zombies | 0 | 11 | 0 |
| t_r3_guns | 0 | 30 | 0 |
| t_r3_hitprobe | 0 | 2 | 0 |
| t_r3_mp_main (2 procs) | 0 | 16 | 0 |
| t_r4_rat_equip | 0 | 19 | 0 |
| t_r4_equip (foreign probe) | 0 | 5 | 0 |
| t_r4_zombies | 0 | 29 | 0 |
| t_r4_pause | 0 | 24 | 0 |
| t_r4_world (3 seeds) | 0 | 48 | 0 |
| t_r4_ui (foreign) | 0 | 26 | 0 |
| t_r4_mp4 (4 procs + 5th) | 0 | 49 | 0 |
| t_r5_walk (new, mine, 3 seeds) | 0 | 45 | 0 |
| t_r5_late via tests/run_r5_late.sh (new, mine, 2 procs) | 0 | 12 | 0 |
| scripts/net/selftest.gd | 0 | SELFTEST PASS | - |
| scripts/player/smoke_test.gd | 0 | 46 | 0 |
| scripts/player/r4_test.gd | 0 | 47 | 0 |
| project check `--quit-after 120` | 0 | 0 ERROR/WARNING lines | - |

## 2. Round 4 defects
| Item | Result | Evidence |
|---|---|---|
| D1 late joiner sees zombies | PASS | `t_r4_mp4` exit 0, 49/49 (was 47/2 FAIL). `t_r5_late`: host+client 1, 3 zombies (kinds 0,1,2) exist, client 2 joins late: it sees 3 (kinds 0,1,2) and 4 after one more spawns; early joiner also 4. Fix: `main.gd:50` `notify_scene_ready`, `network.gd` `peer_scene_ready`, `spawner.gd:72-88` gate zombie visibility per ready peer. |
| D2 late joiner takes damage, no RPC error | PASS | `t_r5_late`: late joiner starts at 100, a zombie placed beside it brings its own reported health to 88.23 (client-side value, so the hit applied on the owner). New `scripts/player/damage_relay.gd` carries the hit. `grep` of host/combined logs for "cannot see this node / Node not found / not found in cache / spawner is null / Attempt to call an RPC": 0 in t_r5_late, t_r4_mp4, t_r3_mp_main, t_mp_real. Note: drop was 11.77, slightly under 12 x night scale; sampled once per second, cause not investigated (possible regen or rounding of the reported sample). |

## 3. New locations walkability (`t_r5_walk`)
Method: player-sized capsule (r 0.35, h 1.8 as player.tscn) flood-filled on a 0.25 m grid with physics shape queries against layer 1, from outside the entrance (police/warehouse: 21 m in front of the door; church: 15 m west, in front of the vestibule door). Every loot container must be usable from a reachable cell (within 2.4 m, ray hits it like `Player._hover_target`); every ground pickup within 1.5 m of a reachable cell. No jumping, 4-neighbour moves.
| Location | seeds 20260101, 31337, 7 | Result |
|---|---|---|
| police_station | entrance free; 56-57% of the footprint reachable; 16/16 loot reachable each seed | PASS |
| warehouse | entrance free; 70% reachable; 15/15 loot reachable each seed | PASS |
| church | entrance free; 53% reachable; 9/9 loot reachable each seed | PASS |
Test fix disclosed: an earlier run (invalid run, see section 0) reported police `register` unreachable. That was my test aiming the ray 0.5 m above the container origin, over the 0.35 m register. I changed the test to aim at the middle of each container's own box. The game was not at fault.
Limits: this proves a path exists for the capsule; it does not prove a door is easy to find visually.

## 4. Regression: all earlier defects
| Item | Result | Evidence |
|---|---|---|
| ROUND1 #1-#10 | PASS | t_r3_zombies, t_r3_mp_main, t_mp_real, t_loot_r2, t_round2, t_solo*, t_r4_ui, t_core all green |
| R3 N1 night reaches spawner | PASS | t_r3_zombies 11, t_r4_zombies 29 |
| R3 N2 gun auto-equip | PASS | t_r4_rat_equip 19 |
| t_core planks credit | PASS | t_core 97 |
| R4 4-peer co-op, late-join building, 5th peer refused | PASS | t_r4_mp4 49 |
| R4 zombie variants, new locations/props, pause menu | PASS | t_r4_zombies, t_r4_world, t_r4_pause |
Engineer changes this round (damage_relay, scene-ready gating, terrain/building_factory/world_builder edits) caused no regression in any test above.

## 5. New defects
None found. No owner/file:line to report.

## 6. Requirements
Low poly (looks not judged); open world with 12 locations; lootable buildings (all three new interiors enterable and loot reachable); realistic guns (logic level); co-op 2-4 peers including a mid-game joiner: MET at logic level on loopback.

## 7. Unverified
Frame rate and visuals; real input; mid-game join over a real network; zombie hit damage amount exactness (11.77 vs 12, see D2); behaviour with 5+ peers beyond the refusal check.

VERDICT: WORKING
