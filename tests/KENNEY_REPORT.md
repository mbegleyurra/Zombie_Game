# Kenney asset test (RAT), 2026-11-14

Godot 4.7.2 headless, `/home/kali/tools/godot/godot`, project `/home/kali/Documents/Zombie_Game`.
Tester only: nothing under `scripts/`, `scenes/`, `assets/` or `project.godot` was edited. Files added: `tests/t_kenney.gd`, `tests/t_kenney_wind.gd`, `tests/run_kenney_all.sh`, this report.

## Timing (PLAGUEMASTER caveat)
- Latest change to any game file I saw: `scripts/world/building_factory.gd` at 23:02:04 (`item_db.gd`, `loot_item.gd` 23:01:50, `world_builder.gd` 23:01:39, `model_util.gd` 22:55:31).
- Every run below started at 23:03:14 or later, so all results are **after the last edit I observed**. I re-checked mtimes at 23:06 and again afterwards: no further change. If PLAGUEMASTER edits `scripts/world/*` again, results for phases 2-3 and `t_r5_walk` are stale and need the second pass.
- Tree state tested (md5): building_factory f09b76f3, item_db 6de7f255, loot_item 5fbf9514, world_builder f41e1046, model_util a19d636d.

## 1. Project check and all tests
- `--quit-after 120`: exit 0, output is the version banner only. 0 ERROR / WARNING / SCRIPT / Parse lines.
- `tests/run_kenney_all.sh` ran all 24 `tests/t_*.gd` + `scripts/net/selftest.gd` + `scripts/player/smoke_test.gd`: **26 of 26 exit 0, 0 FAIL lines.**
- ERROR/WARNING/SCRIPT/Parse lines: **none anywhere except `t_r5_dmg`** (11 on the swept run, 14 on a rerun):
  `Node not found: "Main/<peer>/DamageRelay"`, `Parameter "node" is null` (scene_cache_interface.cpp:118), `Failed to get path from RPC`, `Invalid packet received. Requested node was not found.`
  The test still passes (RESULT failures=0). Not caused by Kenney: a clean `git archive HEAD` copy (no Kenney) gives **35** of the same ERROR lines.
- Kenney-specific `t_kenney.gd`: 167 PASS, 10 FAIL (all overlap checks, analysed in section 3, none block movement).

## 2. Import and ModelUtil.load_fit
- 334 `.glb` under `assets/kenney` (food 200, graveyard 91, mini 43): all load as PackedScene, all have mesh AABBs.
- `load_fit` on gravestone-bevel 1.2, crypt-small 3.4, stone-wall 1.2, lightpost-single 3.0, pumpkin 0.45, hay-bale 1.1, **can 0.17, can-small 0.07, soda-bottle 0.3**: real mesh height within 2% of target, min y 0 (sits on ground), centred on x/z, footprints plausible (can 0.16 x 0.16, soda-bottle 0.09 x 0.08, crypt-small 4.59 x 4.76). Missing file returns null without a crash.

## 3. Main scene (real solo flow: Net.host_solo -> start_game -> main.tscn, 120 frames)
| Requirement | Result |
|---|---|
| Churches have graveyard dressing | PASS. 80 graveyard models in main; each church has 20+ (gravestones, crypt, walls, urns, candles, pumpkins). |
| Farms have hay bales and pumpkins | PASS. Main: 18 hay, 15 pumpkin. In each of 3 seeds every farm has 3 hay + 2 pumpkin, plus Food Kit kitchen dressing. |
| Food and water loot use Kenney models | PASS. All food pickups use can/can-small, all water use soda-bottle.glb: 15/15 + 8/8, 11/11 + 13/13, 13/13 + 12/12 (3 seeds). No non-food pickup carries a Kenney model. |
| First-person camera | PASS. Camera is the current viewport camera, parent Head, Head parent Player, local offset (0,0,0), 1.62 m above feet, 0.000 m horizontal offset, fov 75, no SpringArm3D anywhere in main, exactly one current Camera3D, no Kenney node on the player. |
| Zombies unchanged | PASS for Kenney: `zombie.tscn` identical to HEAD, no "kenney" string in zombie.tscn or zombie.gd, no Kenney node on a zombie, triangle count 3228 / 43 meshes identical to a baseline checkout. NOTE `zombie.gd` differs from HEAD (arm fix, mtime 20:54, before the Kenney work, not a Kenney change). |
| Arms point forward (positive angle) | PASS for idle and chase: idle 0.45 / 0.05 rad, chase 1.16 / 1.54 rad, all positive; chase hand direction dot facing = 0.98 / 1.00. See D2 for the wind-up pose. |

## 4. Walkability (t_r5_walk style, capsule r 0.35 h 1.8)
- `t_r5_walk.gd` (police, warehouse, church, 3 seeds): 45 PASS, 0 FAIL.
- Church yard, with vs without the Kenney colliders (new in `t_kenney.gd`): the gate cell (0, 6.9) and 300+ yard cells are reachable on every seed. Enclosed pockets in the yard: 0 with Kenney, 0 without. The Kenney colliders remove 992 / 1066 / 1105 grid cells (0.3 m grid) of floor, which is the footprint of the stones themselves. **No new unreachable pockets.**
- Farmhouse reachable with the Kenney hay colliders on, every farm, every seed.

## Defects
| # | Severity | Where | Owner | What |
|---|---|---|---|---|
| D1 | Requirement gap | whole project | Lead / MASTER CHIEF decision | **Mini Characters are imported (43 glb) but used nowhere.** `grep kenney/mini` in scripts/ and scenes/ finds 0 references. Commander asked for all three kits to be used. Lead says zombies were evaluated and left alone for proportions; no other use exists (no props, NPCs, weapons, pickups). |
| D2 | Cosmetic, pre-existing arm fix | `scripts/zombies/zombie.gd:634-635` | whoever made the arm fix (not Kenney work) | Wind-up pose still lerps arms to `-2.75`, but the sign was flipped for `arm_base`/`punch` (+ is forward now). Measured: `_wind_pose` 0 -> arm hangs 0.30 forward; 0.5 -> hand direction dot facing **-0.99** (arm swept straight backward); 1.0 -> arm straight up. So the wind-up passes the arm through the back instead of the front. Suggested fix: `+2.75`. Rotation values measured; the animation was not seen. |
| D3 | Cosmetic | `world_builder.gd:578` | PLAGUEMASTER | `crypt-small` at (-13, 0, 15) is 4.59 x 4.76 m rotated 90 deg, so it spans x -15.4..-10.6: pokes 0.4 m through the iron fence on x = -15 (`building_factory.gd:642`) and sits on the procedural headstone row (`building_factory.gd:634-641`, z 8.5..14.9). Collider overlap confirmed on all 3 seeds. |
| D4 | Cosmetic | `world_builder.gd:579` | PLAGUEMASTER | `pine-crooked` at (11.5, 0, 19) overlaps the fence line z = 18.5; collider overlap on all 3 seeds. |
| D5 | Cosmetic | `building_factory.gd:634-641` vs `world_builder.gd:570-577` | PLAGUEMASTER | Church now has two overlapping headstone sets: the old procedural 3x7 rows and the new Kenney 2x6 rows (z 12.5 and 15.7 against procedural z 8.5..14.9). Seed 31337: Kenney stone at (7.3, 12.2) intersects a procedural stone. Consider dropping the procedural boxes or the Kenney rows. |
| D6 | Cosmetic | `world_builder.gd:646-652` | PLAGUEMASTER | Hay bales (radius 19-23 from farm centre, up to 1.9 m long) intersect existing farm colliders (barn / fence): seed 20260101 (19.0,1.1); 31337 (18.3,-7.7), (11.0,17.0); 7 (19.3,2.5), (-18.7,-4.1), (18.9,-8.6), (19.3,-10.3), (19.0,-6.3), (-11.1,17.3), (-14.0,16.7). 12 of ~45 bales over 3 seeds. They do not block movement (pockets 0). Suggested: reject a candidate whose box overlaps, or move to radius 24+. |
| D7 | Pre-existing, not Kenney | `scripts/player/damage_relay.gd` / `t_r5_dmg.gd` | netcode owner | DamageRelay RPC "Node not found" errors during the late-join step; 35 lines on a clean HEAD copy. Test passes; hits are still delivered. |

The church fence-corner columns (`world_builder.gd:607`) and gate piers (`:610`) also overlap the fence segments they sit on: intended, listed only because the overlap check reports them.

## Performance numbers that are measurable
`t_r3_polys` world triangles: 168,438 (HEAD) -> 199,916 (+18.7%), mesh instances 374 -> 533 (+42%). Zombie unchanged.

## NOT measured
- Rendering, materials, lighting, scale as seen by eye, colours, "does it match the current style": this VM is software-rendered and headless; nothing was looked at.
- Frame rate or GPU cost: only triangle and mesh-instance counts were measured, not time per frame.
- Wind-up and attack animation as animation (only joint angles).
- Whether PLAGUEMASTER edits after 23:06 change any result above; a second pass is needed after he finishes.
- Mouse-look input and keyboard movement (headless cannot capture the mouse); camera checks are structural.
- Farm interior loot reachability (only that the farmhouse is entered); police/warehouse/church loot reachability comes from `t_r5_walk`.
- Multiplayer behaviour of the Kenney visuals on a remote peer (selected by `loot_id`, same on every peer by design; not checked on a client).

## VERDICT: NOT WORKING
Functionally the game is sound: 26 of 26 scripts exit 0, no new errors, first person intact, zombies unchanged, Kenney models load, scale correctly and block nothing. The verdict is NOT WORKING for one reason: D1, the Mini Characters kit is not used anywhere, which misses the Commander's requirement. Everything else (D2-D6) is cosmetic and can ship, and D7 predates this work.


---

# Pass 2: Kenney WALKER (zombie.gd), RAT, 2026-11-14 23:20-23:50

**Supersedes** the "Zombies unchanged" and "Arms point forward" rows and defect D2 above: they describe `zombie.gd` before the walker change. Everything else in pass 1 still stands.

Tested tree: `scripts/zombies/zombie.gd` md5 f689f578 (last modified 23:15:16, unchanged for the full test period; checked again after the suite finished). `scripts/world/*` unchanged since pass 1 (mtimes 22:55-23:02). Godot 4.7.2 headless, plus a real render under xvfb (Mesa llvmpipe, OpenGL 4.6).

Tester only. Added/edited tests: `t_kenney_walker.gd`, `t_kenney_walker_fit.gd`, `t_kenney_walker_wind.gd`, `r_kenney_render.gd`, `t_kenney.gd` (2 stale zombie assertions rewritten for the new design). Frames: `tests/kenney_render/*.png`.

## Results
| Item | Result |
|---|---|
| Walker uses Kenney rig | PASS. `_skel` present, bones root/leg-left/leg-right/torso/arm-left/arm-right/head, stock AnimationPlayer removed, 2 mesh instances (runner and bloater have 47 each). |
| Runner and bloater stay procedural | PASS. No skeleton on either. |
| Scale / height | PASS. Mesh height 1.82 m (target about 1.75), feet 0.04 m from the origin. Capsule h 1.80 covers it (top 1.80 vs 1.82). |
| Head hit line | PASS mechanically. `is_head_hit`: walker false at +1.36, true at +1.40 and above; runner and bloater keep 1.48. Head spans 0.89 (neck) to 1.78 m, line 1.36 is inside it. See K2. |
| Arms forward | PASS. Measured from the bones: idle fwd 0.27/0.33 with arms hanging; chase fwd 0.98/0.99 and about level (up -0.14/-0.03). Render frame `4_chase_front`/`5_chase_side` shows the arms reaching forward. |
| Walk animation | PASS. Leg bone pose changed in 11 of 11 samples while chasing. |
| Death | PASS. Dies once; dead mesh height 0.88 m (body rot x -90 deg). |
| Hit flash | PASS. Private skin material per walker; flash on one did not light another. |
| Regression suite | 29 scripts run. 26 exit 0. Failures: `t_kenney` (10 pre-existing overlaps D3-D6, 2 stale zombie assertions, now fixed, 167 PASS / 10 FAIL after the fix), `t_r4_mp4`, `t_r5_late` (K5). |
| Frame cost | 60 physics frames with 30 walkers plus other nodes: 15.0 ms avg, headless, CPU only. **No baseline measured**, so no claim that the walker is cheaper or dearer than the procedural body. |

## Defects
| # | Severity | Owner | What |
|---|---|---|---|
| K1 | Medium (gameplay) | MASTER CHIEF (`zombie.tscn` Collision / `_build_kenney_walker`) | **Collision capsule r 0.32 is narrower than the scaled model.** Rest-pose vertex extents: head about 0.93 m wide (x -0.51..0.42, z -0.38..0.56), legs about 0.8 m, capsule 0.64 m. Side raycasts at 0.3-1.7 m hit only at z-offsets of 0, +-0.2 (7 rays from -0.6 to +0.6 in 0.2 steps: `. . X X X . .`); +-0.4 misses although the head mesh reaches +-0.45. About a third of the head's width cannot be hit, so shots at the head edge pass through visible mesh. Not fixed (tester). Suggested: a second shape for the head or walker capsule radius about 0.4; tradeoff is doorway clearance. Rest-pose numbers: the arm T-pose inflates the torso band (x +-1.0), which I did not count. |
| K2 | Low (design call) | Commander / MASTER CHIEF | Head line 1.36 sits in the middle of an 0.89 m tall head: only the upper 47% of the head counts as a headshot; the face's lower half is body damage. The code comment ties the line to the 300 m rifle drop (about 1.32 m), so it looks deliberate; flagging the tradeoff, not a bug. |
| K3 | Low (cosmetic, shared with runner/bloater) | MASTER CHIEF (`zombie.gd:643-644`) | Wind-up target is `-2.75`, the old sign. Walker and runner behave the same: wind-up pose has the arms straight up (fwd -0.04), which matches "cocked overhead", but while the pose unwinds into the strike the arms pass behind the body (fwd -0.49 at wind 0.89, one frame after release). The earlier D2 measured -0.99 at wind 0.5. Fix: lerp target `+2.75` or accept the overhead swing. Joint angles measured only; animation not watched. |
| K4 | Low (visual) | Commander (accepted tradeoff) | In the render the walker reads as a chibi figure: oversized head, short legs, flat teal/blue palette, next to the olive procedural runner and bloater. All walkers look identical by design (`_apply_variant` returns early), so the per-zombie colour variety is gone for walkers. |
| K5 | Pre-existing, not Kenney | netcode owner | `t_r5_late` fails 2 checks reproducibly ("early joiner sees 4 zombies (0)"). **Same 2 failures with the Kenney walker disabled** (copy of the project with `WALKER_MODEL` pointed at a missing file, procedural fallback): matches open defect D1 from round 4. `t_r4_mp4` failed once during the parallel suite run (client node not freed) and passed on a solo rerun: flaky when ports are contended, not reproduced. |
| K6 | Low, unrelated | UI owner | At 1280x720 the HUD labels overlap (FOOD / WATER / THIRST / STAMINA text stacked on the bars). Seen in the frames only. |

## Not verified
- Replication of the walker to a late-joining or second peer: `t_r5_late` cannot reach it because of K5.
- Real shots on the walker with the actual weapons (only `is_head_hit` heights and raycasts).
- Animation as motion; the render is still frames. Software renderer only, so no GPU timing.
- Hit flash visually (emission flag checked, not seen).
- Rest-pose extents ignore skinning, so arm and leg widths during animation were not measured.
- 3 of the 5 frames show the walker partly hidden behind the other zombies; my vision summaries disagreed with each other and I used the pixels only for the claims above.


---

# Pass 3: Survival Kit + Car Kit dressing, K1 / D2 / D3-D6, RAT, 2026-11-15 00:18-00:26

Tested tree (md5 identical before the run, during, and after, last write 00:13:08, tree quiet 5+ min before the pass started):
`kenney_dressing.gd` 278b4a56, `world_builder.gd` 552034fd, `building_factory.gd` 2ec35de3, `zombie.gd` fa1c39e1.
Godot 4.7.2, `/home/kali/tools/godot/godot`. Headless for logic, xvfb (software GL) for frames. Tester only: nothing under `scripts/`, `scenes/`, `assets/`, `project.godot` was edited.
Added: `tests/t_kenney_dress.gd` (new probe), `tests/r_kenney_dress_render.gd`, frames in `tests/kenney_dress_render/`.
An earlier suite run (pass 2, started 00:13) was discarded: `kenney_dressing.gd`, `world_builder.gd`, `building_factory.gd` and `zombie.gd` changed while it ran.

## Integration facts
- New file `scripts/world/kenney_dressing.gd` (339 lines), called from `world_builder.gd:81-84`. One `KenneyDressing` node, one StaticBody3D (layer 1, 139-143 box/cylinder shapes).
- Per seed: 17-19 cars, 9 cones, 5 camps (40 camp models), 9-11 signposts, 12 crates/barrels, 36 trees, 40 rocks, 163-167 models.
- `grep` finds both kit paths (`kenney/survival/`, `kenney/cars/`) only in `kenney_dressing.gd`. Mini Characters is used by the walker (`zombie.gd:26`), so D1 is closed.

## Results
| Item | Result |
|---|---|
| Project load (`--quit-after 120`) | exit 0 (from pass 1, tree differs now; not rerun separately). Every script in the suite loads the world, so a parse error would have shown. |
| Full suite `run_kenney_all.sh` (32 scripts incl. `t_dressing`, added by another engineer; my `t_kenney_dress.gd` was written after the sweep started and is not in it) | 31 of 32 exit 0. Failure: `t_r5_late` only (K5, below). `t_kenney` now **177 PASS, 0 FAIL**. |
| ERROR / SCRIPT ERROR / Parse lines | None from game code. Only: `Couldn't create an ENet host` (the live game process, pid 413194, holds the port; harmless to the logic) and the known `t_r5_dmg` / `t_r5_late` DamageRelay / spawner RPC errors (11 and 27 lines). No `SCRIPT ERROR`, no `Parse Error`, no "missing model" warning. |
| D2 / K3 wind-up sign | **FIXED.** `zombie.gd:644-645` is now `+2.75`. Measured: wind-up fwd +0.67 (up +0.72), strike fwd +0.76, never negative (walker and runner). |
| D3 crypt overlaps fence and headstones | Not reproduced: `t_kenney` overlap checks all pass on 3 seeds. |
| D4 pine on fence line | Not reproduced, same. |
| D5 two headstone sets | Not reproduced, same (`world_builder.gd:591-592` positions have moved). |
| D6 hay bales overlap barn/fence | Not reproduced, same. |
| K1 walker capsule too narrow | **PARTLY fixed.** `zombie.gd:29` `WALKER_RADIUS` 0.32 -> 0.40 (applied `:801`). Re-measured: hit zone is now z-offsets -0.2..+0.2 in a 0.2 m ray grid, and my +-0.4 rays still miss (tangent, so inconclusive). Head vertex bands still reach z +0.54..0.56 and x +0.65 (`t_kenney_walker_fit`), i.e. up to about 0.15-0.25 m of visible head sits outside the 0.40 capsule. Not closed; see D8. |
| Spawn | PASS: 4 seeds, no dressing collider touches any of the 8 spawn slots; nearest dressing collider to spawn centre 31.1-42.8 m. |
| Dressing collider vs any non-terrain collider | PASS: 0 overlaps on 4 seeds (140-143 shapes each); 0 dressing-vs-dressing overlaps. |
| Loot reachable | PASS: at hospital, gas_station, police, warehouse, church and all 6 farms, on 4 seeds, **0 loot containers or pickups became unreachable** because of the dressing (capsule flood fill, dressing collider on vs off, 0.3 m grid, entry ring found for every location). |
| Doors | PASS in the sense above: the entry-ring flood still reaches every loot item, which require going through the door. Dressing removes 21-338 floor cells per location (gas station 173-338, warehouse 214-221, hospital 120-123, police 91), which are the vehicle and crate footprints. |
| Roads | **FAIL, see D9 and D10**: 3 seeds clean, 2 seeds have dressing standing on a road centreline. |

## Defects
| # | Sev | Where | Owner | What |
|---|---|---|---|---|
| D8 | Low-Medium | `zombie.gd:29` (`WALKER_RADIUS`), `:801` | MASTER CHIEF | K1 follow-up: 0.40 is closer but the head still extends past the capsule by up to ~0.2 m on the +z/+x side (rest pose). Not a blocker; confirm with a real shot test or raise the head shape. Doorway clearance tradeoff stands (a 0.8 m capsule vs 0.9-1.0 m doors). |
| D9 | Low-Medium (gameplay) | `kenney_dressing.gd:207-225` (`_road_cars`) | PLAGUEMASTER (assumed: file has no author line) | A road car can stand on the centreline of a *different* road. Seed 7, taxi at (-41, 112) blocks road#17 at 3 samples while another road runs 2.9 m away. Cause: placement checks `prop_points` and `_taken` only (`:219`), never `terrain.road_distance`, and the yaw jitter `jit` up to 0.35 rad (`:214`) swings a 5 m car's corner ~0.9 m. Seed 31337: a police car at (-113, 32) (12 m from the police station) blocks road#15 at 2 samples, from the same jitter (offset 2.2 m is the minimum, car half width ~1 m, capsule 0.35). Fix: reject candidates where `terrain.road_distance(p.x, p.y)` (excluding own road) is under ~4 m, and cap the jitter at about 0.2. Blocks a player capsule on the road only partially; the road is 3.2 m wide with open verge, so it is a nuisance, not a wall. |
| D10 | Low | `kenney_dressing.gd:171-176` (gas_station crates) | PLAGUEMASTER | Seed 7: `barrel-open2` at (92, -168) stands on road#14 centreline (2 samples), 6-7 m from the gas station and 2.8 m from a second road. The fixed local crate spots (`-3.6,-5.7` etc.) were checked against the building layout only, not against roads. Fix: skip crate spots whose world position is within ~3 m of a road. |
| K5 | Pre-existing | netcode owner | netcode owner | `t_r5_late` is flaky and fails the same 2 checks ("early joiner sees 4 zombies (0)") on **clean HEAD** (2 of 4 runs failed) and on the working tree (3 of 6 failed). Dressing is not the cause. Same as round 4 D1. |
| K6 | Low | HUD | UI owner | Not rechecked this pass. |

## Frames (`tests/kenney_dress_render/`, 1280x720, seed 31337, xvfb software GL)
Looked at through the vision tool, so these are descriptions, not pixel measurements:
- police_station: 4 vehicles on the pad, grounded with contact shadows, door lane clear, scale plausible. Two cruisers parked very close together: check for body overlap up close (the probe's collider check found none, the meshes may still touch).
- hospital: ambulance and a second car on the forecourt, door clear, 3 cones. Ambulance front corner near the wall; a dark green shape behind the right car could not be identified.
- camp: reads as a believable camp; the "tent" looks like a bare A-frame with no canvas (may be the model); two barrels close together.
- spawn view: clear, nothing near the spawn.
- `roadcar_1_police` is a bad frame (flat colour, camera apparently under or inside terrain: my camera placement, not a game defect). `roadcar_2_ambulance`, `gas_station`, `warehouse` were rendered but not analysed.

## NOT measured
- Frame time or GPU cost of the dressing (software renderer, headless; only counts).
- Whether vehicles look right in motion or at night, collision with *moving* zombies, zombie pathing around vehicles, or AI navigation: not tested.
- Zombie vs dressing collision on the walker (`MASK_WORLD`), i.e. whether zombies get stuck on crates: not tested.
- Multiplayer peers seeing the same dressing (built from the world seed, deterministic by design; not run on a client).
- Interior props in the warehouse (crates at local -10.7, 2.3..3.4 and 10.5..11.3, -6.8..-7.3): covered by the loot reach test only; rack and aisle widths not measured.
- Farms, church and hospital interiors beyond the loot reach test.
- Whether any seed other than 20260101, 31337, 7, 424242 produces a blocked door; a road scan covered 4 seeds only.
- The road corridor test uses a 1 m sampling step; shorter obstacles could be missed.
- K1's true hit coverage: only ray rows, not real bullets.

## VERDICT
Dressing integration is sound for doors, loot paths and spawn on 4 seeds. Two seeds show vehicles/crates on road centrelines (D9, D10), cosmetic to low gameplay impact. D1, D2/K3 and D3-D6 are closed; K1 is partly closed (D8). `t_r5_late` flake is pre-existing.


## UPDATE 2026-11-15 (RAT, full QA pass; see tests/QA_REPORT.md)

Tree tested: HEAD 3ed5daf plus the uncommitted KayKit work (gun_mesh, weapon_db, item_db, world_builder, spawner). Godot 4.7.2 headless.

| Item | Status now | Evidence |
|---|---|---|
| D9 road car on a different road's centreline (seed 7) | NOT REPRODUCED | `t_kenney_dress`: `seed 7: road centrelines free of dressing (0/2956 samples blocked)`; also seed 20260101 0/2516, seed 31337 0/2497, seed 424242 0/2814. The road-corridor scan is the test's phase 3 (centreline capsule free along every road). |
| D10 gas-station barrel on road#14 (seed 7) | NOT REPRODUCED | same scan, same 0 blocked samples. The world builds differently now (KayKit forest and dungeon change RNG-dependent placement), so this may have moved rather than been fixed: it is closed for these 4 seeds only. |
| D8 walker head wider than the capsule | STILL OPEN (Low) | `t_kenney_walker_fit` (seed 31337): capsule r=0.34 h=1.70. Rest-pose vertex extents: head upper x -0.36..0.47, z -0.34..0.49 (max radius 0.51); head lower z -0.43..0.50; torso z -0.65..0.67. Ray grid at y=1.5 and 1.7 hits only z-offsets -0.2..+0.2 (rows `. . X X X . .`), so ~0.1-0.3 m of head and ~0.3 m of torso (arms) at the sides cannot be hit. Doorway clearance is fine (see QA_REPORT section 2), so there is room to widen the head sphere. |
| `t_kenney` player-scene check | RESOLVED (test was stale) | `player scene contains no Kenney models` failed because `PlayerModel` (commit 86f33b7) deliberately builds the avatar from `res://assets/kenney/mini/`. Isolation: a copy of the project with `PlayerModel.build` forced to `return false` gives t_kenney 177 PASS / 0 FAIL. Assertion changed to reject Kenney models outside the Avatar node (1 inside, 0 outside); t_kenney now 177 PASS / 0 FAIL. |
