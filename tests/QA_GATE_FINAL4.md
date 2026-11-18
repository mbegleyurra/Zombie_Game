# QA GATE FINAL4 (RAT, 2026-11-17)

Scope: re-gate after GRIM REAPER's hands fix (scripts/weapons/viewmodel.gd modified 15:26, after FINAL3 at 15:18). Source read-only; only tests/ touched.

## Verdict: FAIL (visual, strict). Scripted tests: PASS.

The trigger-hand defects D1 to D4 and D6 are fixed. D5 (hunting) is NOT fixed. A new defect N1 appears on all six rifle-style guns at 75% of the reload. D7 and D8 persist.

## 1. Scripted tests
One at a time, `timeout 250 xvfb-run -a -s "-screen 0 1280x720x24" /home/kali/tools/godot/godot --path . --rendering-driver opengl3 --script res://<file>`. Counts are lines starting with PASS / FAIL.

| test | exit | PASS | FAIL | script errors |
|---|---|---|---|---|
| t_hands_viewmodel | 0 | 210 | 0 | 0 (RESULT PASS) |
| t_blaster_guns | 0 | 216 | 0 | 0 |
| t_viewmodel | 0 | 209 | 0 | 0 |
| t_rifle | 0 | 44 | 0 | 0 |
| t_dungeon_access | 0 | 16 | 0 | 0 |
| t_no_primitives | 0 | 5 | 0 | 0 |
| smoke_test | 0 | 50 | 0 | 0 |

Logs: /tmp/qa4/<name>.log. No Godot process was running at the start, so nothing overlapped this run.

## 2. Rendered frames
All nine WeaponDB weapons (pistol, ak, m4, shotgun, hunting, ar, ar_t1, ar_t2, ar_t3) at 1280x720, xvfb opengl3. Frame 0 = rest, 1 = 25%, 2 = 50%, 3 = 75% of reload. Reload driven by the hands' own clock (empty magazine; per-round weapons use 3 missing), viewmodel frozen as in t_hands_viewmodel.
Files: /tmp/qa4/frames/sheet_<weapon>.png (2x2 full frames) and crop_<weapon>.png (2x2 of the lower-right 800x460 of each frame, 1600x920). I judged the crops by eye, at full resolution.

## 3. Status of FINAL3 defects

| id | weapon, frames | FINAL4 status |
|---|---|---|
| D1 | pistol 1-3 | FIXED. Trigger hand stays on the grip in all four frames. |
| D2 | ak 1-3 | FIXED. Trigger fist sits on the pistol grip, grip visible under it. |
| D3 | m4 1-3 | FIXED. Same as ak. |
| D4 | ar, ar_t1, ar_t2 1-3 | FIXED. Trigger hand on the grip in every frame. |
| D5 | hunting 1-3 | NOT FIXED, see below. |
| D6 | ar_t3 1-3 | FIXED. Trigger hand on the grip in every frame. |
| D7 | rifles, shotgun, hunting, frame 0 | PERSISTS (cosmetic). |
| D8 | shotgun 1-3 | PERSISTS (medium-low). |

## 4. Open defects

D5 hunting, frames 1, 2, 3 (DIRECT, medium-high). The left fist rides up to the front end of the gun, at the scope/muzzle end, in all three reload frames. At 50% and 75% it is at or past the front tip. The right fist sits on top of the stock about 150 px from the bolt knob rather than on it, so neither hand is clearly working the bolt or the port. The poses at 50% and 75% are near-identical, so progress through the reload is barely visible.

N1 ak, m4, ar, ar_t1, ar_t2, ar_t3, frame 3 (75%) (DIRECT, medium). The magazine sits beside the left fist rather than in it, with a visible offset, and overlaps the trigger hand and pistol-grip area. It reads as floating next to the fist and clipping the grip. Frames 1 and 2 are fine: the fist holds the mag. The same pose recurs on every weapon that shares the rifle style.

D7 ak, m4, ar, ar_t1, ar_t2, ar_t3, shotgun, hunting, frame 0 (DIRECT, low). The support arm at rest is a thin, near-vertical green-sleeve pole with a small fist that hovers at the front of the gun. It does not wrap the handguard. In reload frames the same arm is a thick bare forearm, so there is a visible pop in scale and look between frames 0 and 1.

D8 shotgun, frames 1, 2, 3 (DIRECT, medium-low). Both hands stay near their rest pose and no shell or loading-gate motion is visible, so the per-round reload reads as almost no motion. The trigger hand is on the grip in all frames. This is animation legibility only.

Minor, rifles, frames 1 to 3 (DIRECT, low). The right forearm and sleeve lie flush over the stock wood and read as overlapping it. The hands are drawn with no_depth_test by design, so this is cosmetic.

## 5. Test gap (still open)
t_hands_viewmodel passes while D5 and N1 exist. Suggested assertions, not added here because existing tests were left untouched:
- Hunting: left palm within 0.08 m of the port and right palm within 0.08 m of the bolt knob at the 50% sample (the existing reach checks pass on a minimum over all samples, not on the pose at 50%).
- Rifle style: at 75% the left palm is within ~0.05 m of the magazine's centre.
- Non-bolt styles: trigger palm within ~0.08 m of the grip at every sample.

## 6. Limits
- Four frames per weapon, no video; motion between frames is not judged.
- The image tool returned the crops without filenames. I matched each image to a weapon by the order I requested them. The rifle-style guns share a model, so ak, m4, ar, ar_t1, ar_t2 and ar_t3 look alike, and I told them apart by request order and the small differences in length.
- I did not re-inspect the pistol at rest at full resolution beyond the first pass. A low-resolution vision read described the left fist as floating beside the muzzle there. That is unconfirmed.

## 7. Cleanup
tests/_probe_final4.gd removed (see below). Frames and logs left in /tmp/qa4 only.
