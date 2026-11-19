# QA GATE FINAL 7 (RAT) - 2026-11-18

Scope: re-gate of (A) reload animations (MASTER CHIEF) and (B) backpacks (GRIM REAPER) against the QA_GATE_FINAL6 defect list.
Source untouched; only tests/ edited (temporary probes, deleted). Godot 4.7.2, xvfb-run 1280x720x24, opengl3 (Mesa llvmpipe).
No written report from either engineer was found. Gating started after the tree was quiet: no source edit after 18:40:17 for more than 2 minutes, and no other agent's test godot running. Source fingerprint frozen in /tmp/qa7/frozen.sha1 and re-checked before the suite run.

## Verdict

| Area | Result |
|---|---|
| A reload animations | **FAIL** (2 defects) |
| B backpacks | **PASS** (2 non-blocking notes) |
| Suites | 12 of 13 PASS; **t_no_primitives FAIL** (defect A2) |

## A - Reload animations: FAIL

Method: probe renders all nine weapons at rest and at 25/50/75 % of an empty reload, driven by `play_reload` + `set_process(false)` + `advance()`. It logs moving-part travel, magazine distance from its seat, and support-palm-to-magazine distance every 5 %. A second probe measures the rest-pose support palm against the gun's own mesh sections, and the revolver palm against the drum. Frames are in /tmp/qa7/shots/reload/.

Gate-6 defects, re-checked:
- **A1 (gate 6) slide/bolt motion: FIXED.** Every gun's moving part travels 0.027-0.116 m: cylinder swing on the pistol, pump on the shotgun, bolt on hunting/ar_t3, charging handle on the AR pattern. Bolt and pump read clearly in the frames.
- **A2 (gate 6) magazine pop: FIXED.** The largest per-step magazine move is 0.021 m (gate 6 had about 0.10 m). The magazine travels to the well and seats without a jump.
- **A3 (gate 6) empty floating fist at 25 % on rifles: FIXED.** From 10 % to 83 % the support palm stays about 0.04 m from the magazine centre. AK/M4 frames at 25/50/75 % show the fist holding the magazine, closing to the well.
- **A4 (gate 6) pistol model vs reload: FIXED.** pistol_001 is now treated as a revolver: cylinder swing-out, muzzle-up eject, speedloader at 50/75 %. At 20-32 % the support palm is 0.060-0.066 m from the drum centre, on the open cylinder (about one palm width), not floating. It closes to 0.022 m at 83 % while pushing the drum shut.
- Shotgun: shell to the loading gate at 25/50 %, hand back on the forend at 75 %. Correct.
- Hunting: the round is carried to the port at 25/50 %, hands on the receiver at 75 %. Correct.

New / open defects:

1. **A1 - Bolt-model support hand rests on the barrel, not the forend (hunting, ar_t3).** At rest the support fist sits forward of the scope at barrel/scope height instead of wrapping the forend from below. Cause: `grip_l.z` is clamped to at least `GUN_GRIP_Z - 0.31` (z -0.34). On the sniper_rifle_001 model the wooden forend ends before that point: sections from z -0.06 to -0.30 reach down to y -0.08, while z -0.34 only meets barrel/scope vertices (lo +0.008), so the palm lands at y +0.022. This is not a gate-7 regression; the gate-6 frames show the same position, and gate 6 missed it. AK/M4/AR/ar_t1/ar_t2 are fine: the palm sits at 54-55 % of the grip-to-muzzle length on the handguard section, 1.6 cm off its left face, rolled 70°. Fix: limit `grip_l.z` to the last z where the section still reaches below the bore, or tune the forend per model. **Owner: MASTER CHIEF. File: scripts/weapons/viewmodel.gd** (`_profile_for`, grip_l clamp).
2. **A2 - New primitive mesh: `ChargingHandle` BoxMesh under `MovingPart`.** `gun_mesh.gd:239-244` (`"charge"` part) builds the AR-pattern charging handle with `_box()`, a procedural BoxMesh. t_no_primitives now fails ("1 found: ChargingHandle (BoxMesh) under MovingPart"); gate 6 found 0. Fix: split the handle out of the blaster .glb as done for "bolt" (`_split_out`), or use an asset mesh. **Owner: MASTER CHIEF. File: scripts/weapons/gun_mesh.gd.**

Note (non-blocking): in the AK/M4 reload frames the magazine in the fist reads as a thin, short slab, mostly hidden by the hand. It is present and travels correctly; it just does not read as a full curved magazine.

## B - Backpacks: PASS

Method: probe equips each tier, renders third person (game camera, rear, side, front), measures the worn-pack world AABB against the body bones, then opens the large-pack inventory at 1280x720 and checks every visible Control rect, button text width and slot label rect. Frames are in /tmp/qa7/shots/pack/.

Gate-6 defects, re-checked:
- **B1 (gate 6) pack at the hips: FIXED.** The pack is attached to the torso bone and its bottom sits at y 0.46 on a 1.80 m character (torso bone 0.41, shoulder 0.67). Small y 0.46-0.88, medium 0.46-1.08, large 0.46-1.36. Width 0.40/0.54/0.74 m, depth 0.42/0.48/0.58 m: scale grows with the tier. All three read as a pack on the back from the game camera, with nothing hidden behind the hair.
- **B2 (gate 6) 16-column inventory overflows 1280x720: FIXED.** Cell 63 px; panel (128,17) 1023x685 inside the viewport; 0 Controls outside it. Buttons: "DECONSTRUCT (Del)" 221 px for 213 px of text, "UNEQUIP EXPEDITION BACKPACK" 361 px for 353 px of text. Both fit.
- **B3 (gate 6) label overlap: FIXED.** 0 name/count overlaps across 13 slots.

Notes (non-blocking, no defect number):
- The large pack is the Kenney `item-luggage-upright` stand-in. From the side it reads as an upright wheeled suitcase with its handle beside the hair. ItemDB already notes that no real backpack model exists in the asset library.
- 1x1 slot names are ellipsised at cell 63, so the two 9mm stacks both show "9m..." and are told apart only by count. The full name shows in the detail line on hover.

## Suites (one at a time, xvfb-run opengl3, timeout 280 s each)

| Suite | Exit | PASS | FAIL | Script errors |
|---|---|---|---|---|
| t_hands_viewmodel | 0 | 287 | 0 | 0 |
| t_blaster_guns | 0 | 216 | 0 | 0 |
| t_viewmodel | 0 | 209 | 0 | 0 |
| t_rifle | 0 | 44 | 0 | 0 |
| t_backpacks | 0 | 70 | 0 | 0 |
| t_inventory_grid | 0 | 45 | 0 | 0 |
| t_inventory_ui | 0 | 37 | 0 | 0 |
| t_crafting | 0 | 94 | 0 | 0 |
| t_workbench | 0 | 26 | 0 | 0 |
| t_handmap | 0 | 15 | 0 | 0 |
| t_map_ui | 0 | 54 | 0 | 0 |
| t_no_primitives | 1 | 4 | **1** | 0 |
| smoke_test (res://scripts/player/smoke_test.gd) | 0 | 50 | 0 | 0 |

smoke_test lives in scripts/player/, not tests/. It was run from that path.
Logs: /tmp/qa7/suites/*.log. Probe logs: /tmp/qa7/reload.log, rest.log, pack.log.

## Defect list

| # | Area | Defect | Owner | File |
|---|---|---|---|---|
| A1 | Reload | Bolt-model (hunting, ar_t3) support fist rests on the barrel/scope forward of the forend; grip_l.z clamp overshoots the forend | MASTER CHIEF | scripts/weapons/viewmodel.gd |
| A2 | Reload | `ChargingHandle` is a BoxMesh primitive; t_no_primitives FAIL (regression from gate 6) | MASTER CHIEF | scripts/weapons/gun_mesh.gd |

Probe files deleted: tests/r_qa7_reload.gd, tests/r_qa7_rest.gd, tests/r_qa7_pack.gd (and any .uid).
