# QA GATE 4 (RAT, 2026-11-16)

Scope: terrain smoothing, city interiors, hands/reload animations, ITHappy gun swap. No game code was edited. Logs are in /tmp/qa4/*.log; the runner is /tmp/qa4/run.sh.

Method: each suite ran ONE AT A TIME with `xvfb-run -a /home/kali/tools/godot/godot --path . --script res://tests/<n>.gd`, with smoke_test run last via res://scripts/player/smoke_test.gd.

## 1. terrain.gd compile
CLEAN. `godot --check-only --script res://scripts/world/terrain.gd` exited 0 with no errors. `_build_chunk` is defined at terrain.gd:321 and called at :308, so the mid-edit undefined-function report is no longer true.

## 2. Suite results
| suite | exit | PASS | FAIL | script errors | ERROR lines |
|---|---|---|---|---|---|
| t_terrain_smooth | 0 | 12 | 0 | 0 | 0 |
| t_flatroads | 0 | 19 | 0 | 0 | 1 |
| t_handworld | 0 | 34 | 0 | 0 | 1 |
| t_vehicles | 0 | 35 | 0 | 0 | 7 |
| t_resources | 0 | 19 | 0 | 0 | 3 |
| t_forest | 0 | 54 | 0 | 0 | 5 |
| t_citykit | 0 | 35 | 0 | 0 | 1 |
| t_city_interiors | 0 | 15 | 0 | 0 | 1 |
| t_hands_viewmodel | 0 | 140 | 0 | 0 | 0 |
| t_blaster_guns | 0 | 216 | 0 | 0 | 0 |
| t_viewmodel | 0 | 209 | 0 | 0 | 0 |
| t_rifle | 0 | 44 | 0 | 0 | 0 |
| smoke_test | 0 | 50 | 0 | 0 | 0 |

- 13 of 13 suites passed, with 0 failing assertions and 0 script/parse errors.
- The one "FAIL" grep hit in t_blaster_guns is the summary line `0 FAIL`, which is a false positive.
- The ERROR lines are all Godot exit-time warnings ("2 resources still in use at exit", and leaked GL textures at exit in t_vehicles, t_resources and t_forest). No assertion is involved. Minor, and not caused by this round. t_forest and t_resources also leaked textures at exit, so the leaks look pre-existing.
- t_terrain_smooth has no .uid file (tests/t_terrain_smooth.gd only). Cosmetic; Godot generates it on editor open.
- Not run (out of scope): t_map_ui, which carried 4 known pre-existing failures per note_5.

## 3. ITHappy vs Blaster Kit
- GUNS: ITHappy. gun_mesh.gd `blaster_dir` = res://assets/ithappy_weapons/Meshes/Assets/ and the BLASTERS table maps every weapon key to pistol_001, rifle_001, shotgun_001 or sniper_rifle_001, with pistol_drum_001 and rifle_magazine_001 as magazines. viewmodel.gd loads its clip from the same dir, and t_blaster_guns.gd uses the ITHappy path (KIT const). If a file is missing, gun_mesh.gd falls back to the procedural gun, not to the Kenney kit.
- Blaster Kit still referenced in-game: scripts/world/pickup_visuals.gd:15 `BL := "res://assets/kenney/blaster-kit/"`, used for AMMO pickup shapes (not guns). assets/kenney/blaster-kit still exists on disk. This is not a gun-model use, but the comment says "no longer used" and it is not fully true.
- Stale comments and names: loot_item.gd:79, pickup_visuals.gd:56 and viewmodel.gd:300 still say "Blaster Kit". Identifier names (BLASTERS, is_blaster, blaster_dir) are deliberately kept per the gun_mesh.gd header. Cosmetic.
- Limitation: the ITHappy pack has only 4 guns. Every rifle-class key (ak, m4, ar, ar_t1, ar_t2) shares rifle_001. Only length differs, so they look nearly identical in the world and in the hand.

## 4. Leftover probe files
None found. `tests/zz_probe_*` and `tests/_probe*` do not exist. tests/ holds only t_*.gd, r_kenney*.gd, run scripts and reports.

## 5. Hands screenshots (tests/shots/hands_*.png)
Screenshots are dated 21:49, after the last viewmodel/gun_mesh edit at 21:42, so they are current. I read them with an image-analysis model (I did not view the pixels directly). Treat the detail as a good read, not ground truth.
- Hands visible: YES, in the rest poses of ak, hunting and pistol (blocky tan hands, olive sleeves, bottom right).
- Reload moves them: PARTLY. Programmatically, t_hands_viewmodel asserts hands exist/visible, hands travel >= MIN_HAND_TRAVEL during the reload, and both palms stay on screen, and all of these pass across all weapons. In the reload frames, ak and pistol show a hand and gun in a changed raised pose. The reload frames do not show a magazine or drum, and the second hand is not visible in those frames (ak: support hand only; pistol: right hand only).
  - Caveat: this may just be the frame captured (start of the reload, before the mag appears), and the vision read is not certain. A mid-reload frame with a visible mag was not confirmed. MASTER CHIEF should confirm with a frame at mag-out and mag-in time.
- Confirmed MASTER CHIEF's open items:
  - White blob / blown-out gun: the AK rest frame has a bright white wedge on the barrel. The hunting rifle rest frame shows a pale capsule with a ball, and the stock and scope are not recognisable as a gun. The ak reload frame has a harsh white streak and speckles at the muzzle. Likely an unlit or over-bright material or a scale problem on the ITHappy meshes.
  - Pistol: small, mostly covered by the hand, and the fingers do not wrap the grip (the gun sits above the fist). Hard black wedges appear between finger blocks.
  - Viewmodel framing: gun and hands sit very low and far right, and the right sleeve is cropped in the ak frame.
  - Third-person arms (hands_third_person.png): the render shows NO gun in the hands, and the arms look splayed rather than in a two-handed aim hold. The hair/head block is oversized and hides the left arm. This one looks like a real defect, but it is a single frame and a vision read, so verify.

## 6. Defects by owner
MASTER CHIEF (hands and guns)
1. Blown-out white geometry on the ITHappy guns (ak barrel wedge, hunting rifle looks like a white blob, muzzle speckles on reload). Check materials and lighting on the .glb imports (Materials/Textures folder).
2. Pistol is mostly hidden by the hand, with fingers not wrapping the grip.
3. Reload frames do not show the mag/drum or the second hand (unconfirmed; could be capture timing). Add a mag-visible frame check.
4. Third-person arms: no gun visible in the hands, pose not an aim hold (unconfirmed, one frame).
5. Viewmodel sits too low and right, and the right arm is cropped.
6. All rifle-class keys share rifle_001, so they are visually identical (design limit of the pack).
7. Stale "Blaster Kit" comments in viewmodel.gd, loot_item.gd and pickup_visuals.gd (cosmetic).

PLAGUEMASTER (terrain): none found. t_terrain_smooth 12/12, terrain.gd compiles, and t_flatroads, t_handworld and t_forest pass. The only noise is the exit-time leak warnings.

GRIM REAPER (city interiors): none found. t_city_interiors 15/15 and t_citykit 35/35 pass with 0 script errors. Coverage note: the interiors suite has only 15 assertions, and I did not visually inspect interiors.

Other: pickup_visuals.gd still loads Kenney blaster-kit models for ammo, so the Kenney kit is still in use for pickups.

## 7. Limits
- Headless/xvfb only; no human playtest. Visual findings come from still screenshots read by a vision model.
- t_map_ui and the multiplayer selftest were not run (out of scope).
