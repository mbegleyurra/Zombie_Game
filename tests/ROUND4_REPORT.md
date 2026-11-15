# Dead Acres - Round 4 Test Report (RAT, tester)

Godot 4.7.2 headless, software-rendered VM, 2026-11-14. Only `tests/` edited. No git init, no commit.
Engineers were still editing game files while I tested (zombie.gd, world_builder.gd, building_factory.gd changed between my runs, 17:09 to 17:13). One mid-edit run of `t_r3_zombies` hit parse errors in zombie.gd; it passes on the final re-run below. All final numbers come from runs after the last game-file change I saw (17:13:42).
Not judged: frame rate, visuals/looks of new props and zombies, real mouse capture and clicks (headless cannot), 5+ peers.

## 1. Test setup fix
`tests/t_core.gd` now instantiates `res://scenes/main.tscn` and waits 10 frames before the loot section (as `t_loot_r2` does), and asserts the node is in group `main_world`. Result: t_core 97 PASS, 0 FAIL, exit 0. The Round 3 failure (planks stock 3 -> 3) is gone: PASS.

## 2. Full run (final)
Command form: `godot --headless --path . --script res://tests/<t>.gd`

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
| t_r3_zombies (N1) | 0 | 11 | 0 |
| t_r3_guns | 0 | 30 | 0 |
| t_r3_hitprobe | 0 | 2 | 0 |
| t_r3_mp_main (2 processes) | 0 | 16 | 0 |
| scripts/net/selftest.gd | 0 | SELFTEST PASS | - |
| scripts/player/smoke_test.gd | 0 | 46 | 0 |
| project check `--quit-after 120` | 0 | 0 ERROR/WARNING lines | - |
| t_r4_rat_equip (new, mine) | 0 | 19 | 0 |
| t_r4_zombies (new, mine) | 0 | 29 | 0 |
| t_r4_pause (new, mine) | 0 | 24 | 0 |
| t_r4_world (new, mine, 3 seeds) | 0 | 48 | 0 |
| t_r4_mp4 (new, mine, 4 processes + 5th) | 1 | 47 | 2 (defect D1) |
| t_r4_ui (not mine, found in tests/; menu buttons + pause) | 0 | 26 | 0 |

Note on `tests/t_r4_equip.gd`: this is no longer my file. At 17:15 it was replaced by a 1,291-byte probe from someone else (5 PASS). My 19-check version was run before the overwrite (19 PASS) and is re-saved as `t_r4_rat_equip.gd`. The foreign `t_r4_equip.gd` and `t_r4_ui.gd` were left untouched.

## 3. Round 3 items
| Item | Result | Evidence |
|---|---|---|
| N1 night reaches spawner | PASS | `day_night.gd:31` `add_to_group("daynight")`; `t_r3_zombies` exit 0, 11 PASS; `t_r4_zombies`: night_factor follows DayNight at 00:00 and returns to ~0 at noon; pick_kind by night 1,121 runners+bloaters of 2,000 vs 173 by day. |
| N2 picked-up gun auto-equipped | PASS | `item_db.gd:147-148` uses `pickup_weapon`. `t_r4_rat_equip`: ak, m4, shotgun, hunting each become current on pickup with no slot key; a second pickup of an owned gun adds no slot and does not switch; ammo pickup does not switch; auto-equipped ak fires one round. |
| t_core planks credit | PASS | section 1 |

## 4. ROUND1 defects, regression check
| # | Defect | Result |
|---|---|---|
| 1 | Zombies spawn in real game incl. night | PASS (t_r3_zombies day+night, t_r3_mp_main) |
| 2 | One player on host | PASS (t_r3_zombies, t_r3_mp_main, t_r4_mp4 host has 1 then exactly 4) |
| 3 | Host seed used | PASS (client worlds identical md5 on 3 clients) |
| 4 | Ammo ids | PASS (t_loot_r2, t_round2, t_core) |
| 5 | Loot feeds building | PASS |
| 6 | Guns lootable/equippable | PASS |
| 7 | No fire in build mode | PASS, partial dynamic (source gate confirmed; live click path not runnable headless) |
| 8 | Zombies damage built pieces | PASS (t_round2) |
| 9 | Host->client sync | PASS (t_mp_real 12/12) |
| 10 | Menu as start scene / Play Solo | PASS (project.godot; t_r4_ui 26 PASS drives button `pressed` signals; mouse clicks not run) |

## 5. This round's engineer work
| Feature | Result | Evidence |
|---|---|---|
| 3-4 peer multiplayer | PARTIAL | `t_r4_mp4`: host + 3 clients on real main.tscn. PASS: 4 player nodes on host and every client, identical world md5 on all 3 clients, one spawner each, own authority/camera only, each client's move visible on host, 5th peer refused (roster stays 4; `network.gd:276`), leaving client frees its player (host back to 3) and building intact. FAIL: late joiner sees no zombies (D1). |
| Late-join building | PASS | Client 3 joined after 3 pieces existed: received all 3, door open state correct, own 20 planks, host stock unchanged (`building_system.gd:493-501`). |
| Zombie variants (walker/runner/bloater) | PASS | `t_r4_zombies`: kinds spawn as requested, max_health 100/70/260, all die once and emit `died` once, all chase on alert, runner closed 15.7 m vs walker 9.9 m in 3 s, bloater 7.0 m, look differs per variant_seed (deterministic), kinds 0,1,2 replicate to clients 1 and 2 (`kind` is in the sync config, `zombie.gd:131`). |
| New locations (police_station, warehouse, church) | PASS | `t_r4_world`, seeds 20260101/31337/7: all three present each seed, meshes and collision, >=2 loot nodes within radius, no overlapping locations, rebuild hash identical. |
| New props (cars, tractor, poles) | PASS (logic only) | Props node has collision on all 3 seeds; no spawn point under a prop/roof. Looks not judged. |
| Pause menu | PASS | `t_r4_pause` 24 PASS: refused when Net inactive, Esc (`ui_cancel`) toggles, Resume/Disconnect/Quit present and wired, SceneTree not paused (physics keeps running, damage still applies), Disconnect clears Net and emits `left`. |

## 6. New defects
- **D1 (HIGH) Late joiner never sees any zombies. Owner: GRIM REAPER (join/scene flow, `main.gd:42-48`, `network.gd:273-285`) with MASTER CHIEF (`scripts/zombies/spawner.gd:60-63`, MultiplayerSpawner "ZombieMP").** Reproduced in `t_r4_mp4` twice: client 3 joined while zombies existed; it reports 0 zombie nodes, and also 0 for a zombie spawned later, while clients 1 and 2 (joined before any zombie) see all kinds and the later zombie (3 visible). Host log at the join: `Node not found: "Main/Spawner/ZombieMP"` then repeated `ID 3 not found in cache of peer 1` / `Parameter "spawner" is null` (scene_replication_interface.cpp:577). Likely cause (not verified by a fix): the client only builds main.tscn after the seed arrives, so the host's spawn packets for existing zombies reach a client that has no `Main/Spawner/ZombieMP` yet, and the spawner never recovers. Effect: a player who joins mid-game sees an empty world while zombies attack them. Possible fix: have the client create the spawner path before the host starts replicating (e.g. host sends spawns only after the client reports its main scene ready, as players already do with `_rpc_spawned`).
- **D2 (MEDIUM, observed, effect not measured) Zombie hits on the late joiner log RPC errors. Owner: MASTER CHIEF (`zombie.gd:427` -> `player.gd:362`).** Host log: `Attempt to call an RPC to a peer that cannot see this node. Peer ID: <client 3>`, repeated. `Player.request_damage` calls `rpc_id(authority, "_rpc_hurt")` on a player node that peer cannot see yet, so damage to that client probably does not apply. Did not verify the resulting health value.

## 7. Requirements
- Low poly / higher polygon count: MET as before (not re-measured this round, looks not judged).
- Open world: MET; 12 locations now (6 farms, 2 gas stations, hospital, police station, warehouse, church), terrain -12.05..12.73 m.
- Buildings to loot: MET, new locations hold loot.
- Realistic guns: MET at logic level; N2 fixed.
- Co-op multiplayer: MET for 2 to 4 peers joining before zombies exist; NOT MET for a mid-game joiner (D1).

## 8. Unverified
Frame rate and visuals; real mouse/keyboard input and the live click-to-fire path; mouse capture/release on pause; menu mouse clicks; behaviour of D1 after a fix; effect of D2 on health.

VERDICT: NOT WORKING
