# Dead Acres - Round 3 Test Report (RAT, tester)

Godot 4.7.2 headless, software-rendered VM, 2026-11-14. No game code edited. New tests in `tests/`: `t_r3_adjudicate.gd`, `t_r3_zombies.gd`, `t_r3_guns.gd`, `t_r3_mp_main.gd`, `t_r3_hitprobe.gd`, `t_r3_polys.gd` (probe, prints numbers only).
Not judged: frame rate, visuals, real mouse-captured input (headless cannot capture the mouse), menu button clicks, more than 2 peers.

## 1. Full run (exact results)
Command form: `godot --headless --path . --script res://tests/<t>.gd` (exit code, PASS lines, FAIL lines).

| Test | exit | PASS | FAIL |
|---|---|---|---|
| t_world | 0 | 10 | 0 |
| t_core | 1 | 95 | 1 (planks -> Building.stock, test setup problem, see section 2) |
| t_mp_main | 0 | 5 | 0 |
| t_loot_r2 | 0 | 24 | 0 |
| t_solo_r2 | 0 | 3 | 0 |
| t_round2 | 0 | 26 | 0 |
| t_solo | 0 | 9 | 0 |
| t_mp_real | 0 | 12 | 0 |
| t_r3_adjudicate (new) | 0 | 8 | 0 |
| t_r3_zombies (new) | 1 | 8 | 3 (all night scaling, defect N1) |
| t_r3_guns (new) | 0 | 30 | 0 |
| t_r3_hitprobe (new) | 0 | 2 | 0 |
| t_r3_mp_main (new, 2 processes) | 0 | 16 | 0 |
| scripts/net/selftest.gd | 0 | SELFTEST PASS | - |
| scripts/player/smoke_test.gd | 0 | 46 | 0 (failures=0) |
| project check `--quit-after 120` | 0 | 0 ERROR, 0 WARNING lines | - |

## 2. Adjudication: t_core "picked-up planks become usable Building material" (t_core.gd:360-367, stock 3 -> 3)
Verdict: TEST SETUP PROBLEM, not a bug in LootItem or Building.give. Evidence (`t_r3_adjudicate.gd`, 8/8 pass):
- `LootItem.interact` (loot_item.gd:46-51) -> `ItemDB.give_to` (item_db.gd:154-162). For planks/scrap it adds to the inventory, then looks up the node in group `main_world` and calls `give_materials`, which calls `Building.give`. `main.gd:29` registers that group; `main.gd:76-85` is `give_materials`.
- t_core adds a player and a floor to the SceneTree root and never instantiates main.tscn, so no `main_world` node exists and the credit is skipped silently.
- A: reproduced exactly: no `main_world` node, player inventory planks=5, Building.stock 20 -> 20.
- B: `Building.give("planks",5)` called directly: stock +5. Building.give is fine.
- C: with main.tscn present, the same pickup: planks +5 and scrap +3 feed Building.stock.
- Real flow (`t_r3_guns.gd`, Net.host_solo + main.tscn): planks pickup feeds Building.stock +5.
Fix: tests/t_core.gd (tester file) should instantiate `res://scenes/main.tscn` before the loot check, as t_loot_r2 does. No game file needs to change. Design note: the ItemDB -> group-lookup coupling drops the credit silently when no main node exists; harmless in the shipped flow.

## 3. ROUND1 defects, re-verified
| # | Defect | Result | Evidence |
|---|---|---|---|
| 1 | Zombies spawn in the real game, incl. night | PARTIAL: day PASS, night FAIL | Day: alive=1+ within 20 s in main.tscn (t_r3_zombies), zombies spawn in the 2-player game and replicate to the client (t_r3_mp_main). Alerted zombie closes distance across real terrain and damages the player (t_r3_zombies). Night: FAIL, see N1. |
| 2 | One player on host | PASS | 1 player node on solo host (t_r3_zombies) and on the 2-process host before the client joins (t_r3_mp_main); client sees exactly 2. |
| 3 | Host seed used by clients | PASS | Host seed 424242: host world seed 424242, client reports seed 424242 and the md5 of locations + all loot + terrain heights is identical on both processes. |
| 4 | Ammo ids | PASS | t_loot_r2 and t_round2: ammo_9mm/556/762/12ga raise the matching reserve. |
| 5 | Loot feeds building | PASS | t_loot_r2, t_r3_adjudicate C, t_r3_guns real flow. |
| 6 | Guns lootable and equippable | PASS (one minor gap, N2) | weapon_ak/m4/shotgun/hunting pickup gives the weapon; slot_N input action equips it; fires exactly one round each. Guns exist in loot of every world tested (seeds 31337, 1, 2, 3, 20260101; main world has 4). An AK shot at a zombie 9 m ahead took it 100 -> 58 hp (t_r3_hitprobe). |
| 7 | No fire in build mode | PASS (partial dynamic) | With `Building.build_mode` true the weapon controller reports gated and slot keys are ignored; works again when off. The click-to-fire gate (weapon_controller.gd:269 `if not captured or building: return`) is confirmed by source only: headless cannot capture the mouse, so the live fire path was not run. |
| 8 | Zombies damage built pieces | PASS | t_round2: wall hp dropped under a zombie; zombie.gd:446 calls Building.damage_piece. |
| 9 | Host sync | PASS | t_mp_real 12/12; t_r3_mp_main: client sees host move 15 m, host sees client move, authority and cameras correct on both peers. |
| 10 | Menu is the start scene | PASS | project.godot:6 `run/main_scene="res://scenes/ui/menu.tscn"`. |
| 10b | Play Solo works | PASS (button not clicked) | Play Solo = `Net.host_solo` + main.tscn; that path ran in t_r3_zombies and t_r3_guns (one player, one spawner, building stock works). The Play Solo button itself was not clicked. |

## 4. New defects
- **N1 (HIGH) Night never reaches the zombie spawner. Owner: PLAGUEMASTER (world).** `scripts/world/day_night.gd:30` (`_ready` never calls `add_to_group`) and `scripts/world/world_builder.gd:71-74` (creates DayNight, adds no group). `spawner.gd:116` polls groups `daynight`/`day_night`, finds nothing, so `night_factor` stays 0.00. Test: DayNight set to 00:00 (`is_night()` true), after 6 s `spawner.night_factor=0.00`; population day 2 -> night 7, below the required day+6 (t_r3_zombies, 3 FAIL). Effect: no night horde (`spawner.gd:128-132`), no night cap/interval scaling, no `night_mult` for zombies; night is only visually dark. Fix: `add_to_group("daynight")` in day_night.gd `_ready` (the spawner then uses `is_night()`; optionally add `get_night_factor()` returning `get_darkness()` for smooth scaling).
- **N2 (LOW) Picked-up gun is not auto-equipped. Owner: PLAGUEMASTER (item_db.gd:145-146), with MASTER CHIEF (player.gd:486-487).** `ItemDB.give_to` calls `player.give_weapon`, which only equips when no weapon is held (weapon_controller.gd:98-110). `pickup_weapon` (weapon_controller.gd:115, auto-equips) exists but `LootItem` does not use it, whereas `player.add_item("ak")` does equip (t_round2). Player must press the slot key. Observed in t_r3_guns for all four guns. Fix: call `player.weapons.pickup_weapon(id)` from `give_to`, or make `Player.give_weapon` call it.
- Not a defect: after 4 shots of several guns the view pitch rose about 5 degrees (permanent recoil, weapon_controller.gd:26/332); my first hit test missed because of it, so the test now aims exactly. The weapon path itself hits.

## 5. Requirements
- Low poly, higher polygon count: MET as measured, no earlier baseline to compare against. Real mesh data: world 139,592 triangles in 290 mesh instances; zombie 1,560 triangles in 15 meshes; vertex-colour materials (mesh_util.gd:13). Gun viewmodel triangle count not measured. Look not judged.
- Open world: MET, modest. 9 locations spanning about x -156..121, z -171..178 m; terrain relief -11.8..12.7 m.
- Buildings to loot: MET. Walkable interiors with door gap, solid walls, loot inside (t_world 10/10); 125 loot nodes per world.
- Realistic guns: MET at logic level. Five guns with real calibers/mags/reload behaviour, lootable, equippable, fire, and hit zombies.
- Co-op multiplayer: MET for 2 peers. Two real processes on real main.tscn and real player.tscn: identical world, host seed, movement visible both ways, zombies replicate. 3-4 peers not tested.

## 6. Unverified
Frame rate and visuals; real mouse/keyboard input and the live click-to-fire path; menu buttons; 3-4 player sessions; night behaviour after N1 is fixed.

VERDICT: NOT WORKING
