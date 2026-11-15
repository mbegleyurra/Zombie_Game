# Dead Acres - Round 1 Test Report (RAT, tester)

Godot 4.7.2 headless on a software-rendered VM. No game code was edited. Tests written: `tests/t_world.gd`, `tests/t_core.gd`, `tests/t_mp_main.gd`, `tests/t_mp_real.gd`.
Not judged here: frame rate, visuals, mouse-captured input (headless cannot capture the mouse, so key-driven movement and fire-input were not exercised end to end; weapon logic was driven by calling `_try_fire` / `start_reload` directly).

## 1. Headless project check
`godot --headless --path . --quit-after 120` -> exit 0. Output has 0 ERROR and 0 WARNING lines. It printed only `[World] seed=20260101 ... total=527ms loot_nodes=125 locations=9` and `[Main] spawned Player_1 ... (player scene)`. Menu scene (`--scene res://scenes/ui/menu.tscn --quit-after 90`) also loads with no output/errors.

## 2. Existing tests
| Command | Result |
|---|---|
| `--script res://scripts/player/smoke_test.gd` | exit 0, 46 PASS, `failures=0` |
| `--script res://scripts/net/selftest.gd` | exit 0, `SELFTEST PASS` (uses a stand-in Node3D player, not player.tscn) |

## 3. My tests
| Test | Command | Result |
|---|---|---|
| World determinism | `t_world.gd -- 20260101` twice | Identical both runs: locations=9, loot_nodes=125 (57 containers + 68 ground items), same md5 over location positions, container contents and ground items (`9f50944d...`). Seed 777 gives a different hash (`a84d54af...`) with the same counts. |
| World content | same script | PASS: 6 farms, 2 gas stations, 1 hospital; terrain -11.8..12.7 m; farmhouse door gap passes a ray, adjacent wall blocks it; 6 loot items inside the house; roof present. |
| Player + weapons + zombies + building + loot | `t_core.gd` | 88 PASS, 8 FAIL (all 8 are defects below; exit 1). |
| Host flow on real `main.tscn` | `t_mp_main.gd` | 3 FAIL (seed ignored, 2 players, no spawner). |
| 2-process co-op with REAL `player.tscn` | `t_mp_real.gd` | Run twice, same result: spawn/authority/camera PASS, client->host position PASS, host->client position FAIL. |

Passing detail (t_core): player instances, falls, settles on floor, 100 hp, camera current. Each of pistol, ak, m4, shotgun, hunting: loaded to mag_size, fires and emits shot_fired, ammo drops by 1, magazine empties after exactly mag_size shots, empty trigger starts a reload instead of firing, reload consumes exactly the rounds loaded from reserve, tactical reload tops up, reload refused with no reserve. Zombie: IDLE -> INVESTIGATE (noise) -> CHASE (alert, closes distance) -> ATTACK (player 100 -> 88 hp) -> DEAD (died emitted once, later damage ignored); spawner.spawn_zombie_at works. Building: wall places and costs 4 planks, duplicate slot -> "Occupied", wrong slot -> "Bad slot", door places and toggles, floor places, remove frees slot and refunds half, over-spend -> "Not enough materials", pieces have collision. Loot: container contents deterministic per (seed,id), search gives all contents, cannot be searched twice, loot_item pickup removes the node.

## 4. Stated requirements
- Open world: met. About 380 m square with 9 locations and terrain relief. Modest in size.
- Buildings with interiors: met. Walkable farmhouse/gas station/hospital with door and window openings, roof, loot inside.
- Loot: partly. Containers and ground items work, but picked-up ammo and building materials are not usable (defects 4, 5) and no gun can be found (defect 6).
- Realistic guns: met at the data/logic level. Real calibers, mags, rpm, bullet drop, penetration, falloff, recoil, and per-round shotgun/rifle reloads all behave.
- Co-op multiplayer: partly. Host/join, seed handshake, spawn, authority, client->host sync, building sync work. The real game flow duplicates players (defect 2), ignores the host seed (defect 3), and host->client position sync is broken (defect 7).
- Low poly: met by construction. Everything is box/prism/capsule geometry with flat vertex colours (checked in code, not visually).

## 5. Known gaps from the lead
- `run/main_scene` is `main.tscn`, not the menu: CONFIRMED (`project.godot:6`). Also, launching main directly means `Net.active` is false, so `Building._in_game()` is false and building is disabled (from code, `building_system.gd:132-137, 275`; not run).
- `main.gd` ignores `Net.world_seed`: CONFIRMED dynamically (host seed 424242, world built with 20260101).
- Weapons fire while `Building.build_mode` is true: CONFIRMED by code (no reference to `build_mode`/`Building` in `weapon_controller.gd` or `player.gd`; `_handle_actions` at weapon_controller.gd:243-262 only checks mouse capture). Dynamic probe was inconclusive (no mouse capture headless).
- Loot does not call `Building.give`: CONFIRMED dynamically (planks picked up: inventory 5, Building.stock 3 -> 3).

## VERDICT: NOT WORKING

Defects (most severe first):
1. No zombies in the real game. Nothing instantiates `scripts/zombies/spawner.gd`: `scenes/main.tscn` has only the Main node, `scenes/world/world.tscn` only the world script, and `world_builder.gd` never adds one. `t_mp_main.gd`: 0 spawner nodes, 0 zombies after 30 frames. Zombie AI works in isolation but never appears. Fix: add a spawner node (group "spawner") to main.tscn or build it in `world_builder.gd`/`main.gd`.
2. Two local players are spawned when hosting. `main.gd:35-36` (`spawn_player(0, 1)`) plus `network.gd:162-211` (`_process`/`_spawn` into the current scene) produce `Player_1` and `1` (`t_mp_main.gd`: 2 found). Two cameras, HUDs and weapon sets for one human. On a client, `main.gd` also creates a stray `Player_1` whose authority is peer 1. Fix: main.gd should skip its own spawn when `Net.active`.
3. `main.gd:17,34` ignores `Net.world_seed`. The host's random seed (`network.gd` host()) is never used; every game builds 20260101. Peers happen to agree only because all ignore the seed. Fix: use `Net.world_seed` when `Net.active` and nonzero.
4. Loot ammo is unusable. Loot/ItemDB ids are `ammo_9mm`, `ammo_556`, `ammo_762`, `ammo_12ga` (`item_db.gd:7-20`) but weapons read reserve via `player.count_item(wd.caliber)` with calibers `9mm`, `556`, `762`, `12ga` (`weapon_db.gd:39,74,114,153,194`). `t_core.gd`: picking up 10 of each leaves reserve unchanged. Players can only use the 45 starting 9mm rounds.
5. Loot does not feed building. `loot_item.gd:46-53` / `loot_container.gd:88-` call only `player.add_item`; nothing calls `Building.give` (`building_system.gd:169`). Picked-up planks/scrap never reach `Building.stock`, which holds a fixed 20 planks / 10 scrap. Also `Building.give_hook` / `take_hook` are never set.
6. No gun can be found. `item_db.gd` has no weapon items and no table drops one; `player.gd:151-156` gives only a pistol. AK, M4, shotgun and hunting rifle exist only through `give_weapon` calls in tests.
7. Host->client replication of players fails with the real player scene. `t_mp_real.gd` (2 runs): client logs `ERROR: Node not found: "World/1/PlayerSync"` and the host player stays at its spawn point (2,3,0) on the client; client->host sync works. Cause: the host's `MultiplayerSynchronizer` (`player.gd:160-170`, created in `_ready`) starts sending to the new peer before the client has spawned the node via the manual RPC in `network.gd`. The shipped `selftest.gd` uses a stand-in node and cannot catch this. Fix: delay sync visibility per peer until the client confirms the spawn, or spawn with a MultiplayerSpawner.
8. Weapons fire in build mode. `weapon_controller.gd:243-262` (and `player.gd`) never check `Building.build_mode`, so left click both places a piece and fires (`building_system.gd:201-` header states players should not fire in build mode).
9. Zombies never damage building pieces. No reference to `Building.damage_piece` (`building_system.gd:160`) anywhere in `scripts/zombies/`; barricades only act as static walls.
10. `project.godot:6` `run/main_scene` is `scenes/main.tscn`, not the menu. Launching the game skips host/join; Net is inactive so building is disabled in that mode (`building_system.gd:132,275`) and nothing can start multiplayer. Fix: point main_scene to `scenes/ui/menu.tscn`.
