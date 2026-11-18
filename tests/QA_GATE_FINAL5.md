# QA GATE FINAL5 (RAT, 2026-11-17)

Scope: re-gate after GRIM REAPER's fix. scripts/weapons/viewmodel.gd was last modified 15:33:38, before this run started (FINAL4 judged the 15:26 version, so a change did land between gates). Source read-only; only tests/ touched.

## Verdict: FAIL (visual, strict). Scripted tests: PASS.

D5, N1, D7 and D8 are all still present. Nothing in the frames shows any of the four improved. One new low-medium item (N2, pistol) is added.

## 1. Scripted tests
One at a time: `timeout 250 xvfb-run -a -s "-screen 0 1280x720x24" /home/kali/tools/godot/godot --path . --rendering-driver opengl3 --script res://<file>`. PASS/FAIL are counts of lines starting with those words. Runner: /tmp/qa5/run.sh, logs /tmp/qa5/<name>.log. No other Godot process was running at the start.

| test | exit | PASS | FAIL | script errors |
|---|---|---|---|---|
| t_hands_viewmodel | 0 | 218 | 0 | 0 |
| t_blaster_guns | 0 | 216 | 0 | 0 |
| t_viewmodel | 0 | 209 | 0 | 0 |
| t_rifle | 0 | 44 | 0 | 0 |
| t_dungeon_access | 0 | 16 | 0 | 0 |
| t_no_primitives | 0 | 5 | 0 | 0 |
| smoke_test (scripts/player/smoke_test.gd) | 0 | 50 | 0 | 0 |

t_hands_viewmodel went from 210 to 218 PASS, so the test file or the hands code gained 8 checks since FINAL4. I did not diff them.

## 2. Rendered frames
All nine WeaponDB weapons (pistol, ak, m4, shotgun, hunting, ar, ar_t1, ar_t2, ar_t3), 1280x720, xvfb opengl3. Frame 0 = rest, then 25 / 50 / 75 percent of reload, driven by the hands' own clock with the viewmodel frozen (same method as t_hands_viewmodel). Files: /tmp/qa5/frames/crop_<weapon>.png (2x2 of the lower-right 800x460 of each frame) and /tmp/qa5/q/<weapon>_f<k>.png (single quadrants).

How each weapon was judged, because the image path was unreliable:
- Judged by me directly from pixels: ak (all four frames) and shotgun (all four frames).
- Judged from an image-analysis tool on single-quadrant crops, with literal questions: hunting f2/f3, m4 f3, ar f3, ar_t1 f3, ar_t2 f3, ar_t3 f3, pistol f3. Earlier whole-sheet analysis calls contradicted each other (it called ar_t3 a bolt rifle and the pistol a revolver), so those were discarded. The pistol model does read like a revolver-style body in the pixels I saw.
- Hunting was also judged by me from pixels in an earlier read (left fist at the front end of the scope at 50% and 75%, right fist on top of the stock about 150 px from the knob). The tool's single-quadrant read agrees.
- The direct image reads were cut off by a tool guard partway through, so several weapons rest on tool reads, not my own eye. Treat those findings as medium confidence.

## 3. Status of the four focus defects

| id | weapon, frames | FINAL5 status |
|---|---|---|
| D5 | hunting 1-3 | NOT FIXED |
| N1 | ak, m4, ar, ar_t1, ar_t2, frame 3 | NOT FIXED. ar_t3 reads as the same problem, less certain |
| D7 | all rifles, shotgun, hunting, frame 0 | PERSISTS |
| D8 | shotgun 1-3 | PERSISTS |

### D5 hunting (medium-high)
- 50%: left fist is at the far front of the gun by the scope/barrel front, one fist-width left of the bolt knob. The right fist is on the stock, 2 to 3 fist widths from the knob. Neither hand works the bolt or port.
- 75%: left fist still at the front end, well forward of the receiver and about 100+ px from the knob. Right fist on the stock about 100 px from the knob. Poses at 50% and 75% are close to identical.
- Numbers from the probe (gun-local, metres): at 50% the left palm is (-0.110, 0.063, -0.210) and the right palm (0.030, 0.015, 0.030), against bolt_hand (0.030, 0.000, -0.060). The right palm is about 0.09 m from the bolt hand, above the test's 0.08 REACH_DIST. At 75% it is about 0.056 m.
- The profile `port` is (-0.11, 0.03, -0.21). The left palm is within 0.05 m of it at 50% and 75%, which is why the existing reach checks pass. But z = -0.21 is at the scope/muzzle end in the render, so the animation is hitting a target that is in the wrong place on the model. This is the cause; the fix owner should move the port anchor, not the hand.

### N1 rifle style, frame 3 (medium)
- ak (my own read): the gray magazine sits beside the left fist, to its right and pointing up to the mag well, and overlaps the pistol grip and the front edge of the trigger hand. Frames 1 and 2 are fine: the fist holds the mag.
- m4, ar, ar_t1, ar_t2: the tool reads agree: magazine about 25 to 30 px right of the fist, not held, with the right hand's fingers touching or occluding its right edge and the grip partly hidden.
- ar_t3: magazine hangs below the gun, clearly separate from the left fist, and passes under the right fist and wrist. The grip is not clearly visible. Same defect class.
- Probe: at 75% the left palm for ak is (-0.072, -0.047, -0.071) against the mag well (0.0, -0.053, -0.03) plus grab offset. It is roughly 0.07 m off in x, which matches the visible offset.

### D7 rest pose (low)
At rest the support arm is a thin, nearly vertical green-sleeve pole with a small fist hovering at the front of the receiver. It does not wrap the handguard or hold the forend. Confirmed by me on ak and shotgun, and by the tool on hunting and ar_t3. In reload frames the same arm is a thick bare forearm, so it visibly pops in thickness and colour between frame 0 and frame 1.

### D8 shotgun (medium-low)
Confirmed from pixels. The left fist sits under the receiver at the loading gate in frames 1 to 3, with only a small shift between them. No shell is visible in any frame. The trigger fist stays on the grip in all four frames. The reload has no legible per-round motion.

### N2 pistol, frame 3 (low-medium, new, tool read plus my own read)
At 75% the magazine is at the base of the grip, beside the left fist rather than held in it, and it overlaps the trigger hand's fingers and the grip. The trigger fist stays on the grip in every frame, so D1 stays fixed. At rest the left fist floats off the muzzle side with nothing in it; I did not re-verify that at full resolution.

## 4. Test gap (still open)
t_hands_viewmodel passes 218/218 while D5, N1, D8 and D7 exist. Suggested assertions, not added, because existing tests were left untouched:
- Hunting: at the 50% sample, right palm within 0.05 m of bolt_hand, and left palm within 0.08 m of a port position measured from the mesh (as the shotgun test does with SHELL_GATE), not read from the profile.
- Rifle and pistol styles: at 75%, left palm within 0.05 m of the magazine's centre.
- Shotgun: left palm travel between the 25% and 75% samples of at least 0.03 m, so the animation has to show motion.

## 5. Limits
- Four frames per weapon, no video; motion between frames is not judged.
- Several weapons rest on tool reads, as described in section 2. The m4, ar, ar_t1 and ar_t2 N1 findings come from those reads plus the matching probe numbers and my own read of ak, which shares the model.
- I did not check frames 1 and 2 of m4, ar, ar_t1, ar_t2 or ar_t3 beyond the probe numbers.

## 6. Cleanup
tests/_probe_final5.gd removed. Frames, crops and logs are left in /tmp/qa5 only.
