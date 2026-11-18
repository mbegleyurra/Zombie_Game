# QA GATE FINAL (RAT, 2026-11-17)

Scope: Part A hands/reload, Part B primitive replacement, Part C weapons_free duplicate. Source was read-only; only tests/ was written.
All tests ran one at a time under `xvfb-run -a` (Godot at /home/kali/tools/godot/godot, real renderer, not --headless).

## Verdicts

| Item | Verdict |
|---|---|
| A1 Test suite (t_hands_viewmodel, t_blaster_guns, t_viewmodel, t_rifle, smoke_test) | PASS |
| A2 First-person hands, rendered and viewed (9 weapons x rest/25/50/75 % reload) | FAIL |
| A3 Third-person model shows hands | PASS (test-asserted only, not viewed) |
| A4 Weapon stats and recoil unchanged versus git | PASS |
| B1 t_no_primitives and the world suites | FAIL (t_dungeon_access regression) |
| B2 Remaining primitive-built objects | INFO, list below |
| B3 World screenshots | PASS with notes |
| C weapons_free duplicate gone or unreferenced | PASS |

## A1 Test counts (PASS lines / FAIL lines)
- t_hands_viewmodel: exit 0, 202 / 0
- t_blaster_guns: exit 0, 216 / 0 (the one grep hit was the summary line "0 FAIL")
- t_viewmodel: exit 0, 209 / 0
- t_rifle: exit 0, 44 / 0
- smoke_test: exit 0, 50 / 0
- No SCRIPT ERROR or Parse Error in any of them.
These tests pass, but their checks do not catch what the images show (see A2).

## A2 Images (judged with image_analyze; one 2x2 montage per weapon)
Screenshots: tests/shots/qf/<weapon>_rest.png, _r25.png, _r50.png, _r75.png and montages tests/shots/qf/m_<weapon>.png.
Weapons: pistol, ak, m4, shotgun, hunting, ar, ar_t1, ar_t2, ar_t3.

Good in all nine: two separate arms in every frame, no merged hands, no missing hand, gun always visible and muzzle-forward, right hand stays on the grip.

Defects seen in the images (vision judgement from low-resolution montages; some contact and clipping calls are best guesses):
1. The left hand hovers off the gun at 25 % and 50 % of reload on the pistol, AK-type rifles (ak, ar, ar_t1, ar_t2), shotgun and hunting rifle. At 25 % it drops away from the gun and at 50 % it stays low or beside it, not at a mag well or the shell port.
2. At 75 % the left hand jumps abruptly up to the front of the gun (above or at the front sight on the rifles). The forearm is near-vertical and crosses the handguard or barrel, so it appears to clip or occlude the gun. It is flagged on the pistol, AK, shotgun, hunting rifle, ar, ar_t1 and ar_t2.
3. No magazine is visibly removed, held or inserted on the rifles. A grey plate appears next to the right hand at 50 % and is ambiguous.
4. On the AK-type rifles the right forearm hides the stock in frames 2 to 4 and the right fist looks partly buried in the receiver.
5. On the hunting rifle (bolt) the right hand floats off the receiver at 25 % and 50 % (no bolt motion visible) and the left forearm cuts through the barrel at 50 % and 75 %.
6. The left arm is long and thin and the right arm blocky, so the pair looks mismatched. The pistol is small and steeply pitched.
7. Shotgun: the gun's scale and angle differ between the rest frame and the reload frames (looks like a jump cut).
8. m4: the montage returned no text, so I did not judge it separately. Only the ak_r75 full frame was viewed, so m4 is NOT judged.
Overall: the hands are two separate hands and the guns are correctly oriented, but the reload hand movement does not read as a reload. Judged by images, FAIL. Owner: GRIM REAPER (scripts/weapons/viewmodel.gd, weapon_controller.gd).

## A3 Third person
t_hands_viewmodel asserts the third-person body shows arms and passed. I did not view a third-person image.

## A4 Stats and recoil
- scripts/weapons/weapon_data.gd: unmodified versus HEAD.
- git diff of weapon_controller.gd: no added or removed line touching recoil, damage, mag_size, fire_rate, spread or reload_time.
- weapon_db.gd adds only DUP_PICKUP_MAGS = 2, START_RESERVE_9MM = 90 and dup_pickup_rounds(). These change ammo granted on duplicate pickup and the starting 9mm reserve, not weapon stats. dungeon_builder.gd also doubles some ammo pickups (12 to 24 9mm, 60 to 120 5.56, 30 to 60 7.62). These are intended-looking behaviour changes outside the reframe; flagging them for the lead.
- Reload durations are unchanged by the test: reload_time assertions pass (pistol 2.1 s, ak 3.0, m4 2.7, shotgun 2.35, hunting 3.4, ar 3.1, ar_t1 3.1, ar_t2 2.9, ar_t3 2.8).

## B1 World suites
- t_no_primitives: exit 0, 5 PASS / 0 FAIL
- t_handworld 34/0, t_citykit 35/0, t_vehicles 35/0, t_resources 19/0, t_forest 54/0, t_dressing 33/0: all PASS
- t_dungeon_access: exit 1, 14 PASS / 2 FAIL:
  - "the same body walks back up the stairs and out of the gate" stalled at (-143.33, -4.39, 103.72) heading for (-143.33, 0.0, 98.52)
  - "and back from the vault to the surface" stalled at the same point
- Cause, measured: with the same tests/ a copy with scripts/ reset to HEAD gives fails=0. Reverting only scripts/world/terrain.gd to HEAD gives fails=0. Reverting dungeon_container.gd or world_builder.gd alone still gives fails=2. The bisect was stopped before the other candidates finished (dungeon_builder.gd, player.gd, model_util.gd, loot_container.gd, zombie.gd were not tested). Revert terrain.gd and the test passes.
- terrain.gd diff (+200/-54) is the smooth-terrain and level-road-bed rewrite (CELL 2.0 to 1.0, road bed carving, new height_at). I have not pinned the exact line. Likely the terrain height or collision over the dungeon stair exit is changed so the player body stalls on the way out. Not confirmed.
- Owner: GRIM REAPER (terrain.gd) with whoever owns the dungeon exit. FAIL.

## B2 Primitive meshes still in scripts/ (fs_search count, then read)
Counts: player.gd 6, gun_mesh.gd 3, viewmodel.gd 4, weapon_controller.gd 3, loot_item.gd 1, skeleton_bolt.gd 1, zombie.gd 7.
What is visible in play:
- player.gd:720-745 remote-player avatar built from BoxMesh and SphereMesh (box torso, legs, arms, sphere head). Visible to other players. Primitive-built.
- viewmodel.gd:457-495 hands and forearms are cylinder and box meshes. First-person hands are primitive-built, which is the intended design here.
- gun_mesh.gd:466-498 box and cylinder helpers for gun parts (fallback or attachments).
- zombie.gd: sphere stumps (line 429), blood particle sphere (590), resource cylinders (618), and box, capsule and sphere helper functions (1315-1332) for zombie limbs and gore.
- weapon_controller.gd: muzzle flash sphere (597), tracer box (655), impact sphere (683). Effects, not objects.
- loot_item.gd:115 glow disc cylinder (on the t_no_primitives allowed list).
- skeleton_bolt.gd:24 sphere projectile.
t_no_primitives passes, which means the world and one of each zombie kind and building kind have no non-asset meshes outside its allowed list. It does not cover the remote-player avatar, first-person hands, or effects.

## B3 World screenshots
tests/shots/qf/world_0.png, world_1.png, world_2.png (three camera spots in a built world, seed 1).
Buildings, vehicles, street lamps, traffic lights, trees and roads read as modelled low-poly assets. Nothing looked like a grey untextured debug box. Weak spots the viewer named: orange and blue banded tanks and one blue-grey tower slab look plain, the ground is smooth with little texture, the road surface has pale patches. These are style calls, and t_no_primitives passes for the world, so I count them as assets and not failures.

## C weapons_free
- assets/ contains kaykit, kenney and ithappy_weapons only. No weapons_free path anywhere (find -iname '*weapons_free*' empty, git ls-files empty).
- grep for weapons_free in scripts/ returned nothing. The game loads assets/ithappy_weapons (6.2 MB), which is referenced by gun_mesh.gd and pickup_visuals.gd.
- The original zip is still at /home/kali/Downloads/Godot_4.7_Weapons_Free_v1.1.zip (not touched).
PASS.

## Defect list
1. GRIM REAPER, viewmodel.gd / weapon_controller.gd: left-hand reload path hovers at 25 % and 50 %, snaps to the muzzle end at 75 %, forearm clips the gun; no visible magazine; hunting-rifle right hand floats; right forearm hides the AK stock. High.
2. GRIM REAPER, terrain.gd: t_dungeon_access 2 FAIL (stairs exit stall near (-143.3, -4.4, 103.7)). Passes at HEAD and with terrain.gd reverted. High.
3. Test gap, tests/: t_hands_viewmodel passes 202 checks while the reload motion is visibly wrong. The "on the gun" and "reach" checks need to check the left hand at the mag well at 50 % of reload. Medium.
4. Lead decision: ammo and starting-reserve changes (weapon_db.gd, dungeon_builder.gd) are outside the hands reframe. Low.

## Not verified
- m4 montage not judged; third-person arms not viewed; the other bisect candidates for t_dungeon_access not run; the remote avatar and zombie gore were not rendered.

## Cleanup
Deleted tests/probe_qf_shots.gd and tests/probe_qf_world.gd (and their .uid files), /tmp copies and the bisect script. Kept tests/shots/qf/ (screenshots and montages) as evidence.
