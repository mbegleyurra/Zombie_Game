# QA GATE FINAL3 (RAT, 2026-11-17)

Scope: re-gate after GRIM REAPER's hands fix. Source read-only; only tests/ touched.

## Verdict: FAIL (visual). Scripted tests: PASS.

## 1. Scripted tests
Each run alone, `xvfb-run -a ... godot --path . --rendering-driver opengl3 --script res://<file>`, `timeout 250`.

| test | exit | PASS lines | FAIL lines | script errors |
|---|---|---|---|---|
| t_hands_viewmodel | 0 | 211 | 0 | 0 |
| t_blaster_guns | 0 | 216 | 0 (the only grep hit is the summary text "0 FAIL") | 0 |
| t_viewmodel | 0 | 209 | 0 | 0 |
| t_rifle | 0 | 44 | 0 | 0 |
| t_dungeon_access | 0 | 16 | 0 | 0 |
| t_no_primitives | 0 | 5 | 0 | 0 |
| smoke_test | 0 | 50 | 0 | 0 |

Logs: /tmp/qa3/<name>.log. Dungeon exit confirmed fixed (16/16).

## 2. Rendered first-person frames
Probe rendered all nine WeaponDB weapons (pistol, ak, m4, shotgun, hunting, ar, ar_t1, ar_t2, ar_t3) at 1280x720 under xvfb opengl3.
Frame index: 0 = rest, 1 = 25% of reload, 2 = 50%, 3 = 75%. Files: /tmp/qa3/frames/<weapon>_<n>.png and sheet_<weapon>.png (2x2: rest, 25, 50, 75).
Reload driven by the hands' own clock (play_reload, empty magazine; per-round weapons use 3 missing), viewmodel frozen as in t_hands_viewmodel.

Evidence grade:
- DIRECT = I looked at the sheet myself: pistol, ak, m4, shotgun.
- VISION = read through image_analyze (low-res blocky render, contact calls are less certain): hunting, ar, ar_t1, ar_t2, ar_t3. Re-check these by eye before closing.

## 3. Defects

D1 pistol, frames 1, 2, 3 (DIRECT). The trigger hand lets go of the gun for the whole reload and floats about 100+ px to the right of the grip, never returning. The pistol is held only by the left fist at the grip base. At rest (frame 0) the hold is fine. Frames 2 and 3 are almost identical to frame 1.

D2 ak, frames 1, 2, 3 (DIRECT). The trigger hand leaves the pistol grip and sits as a large block on top of the stock/forearm wood; the grip is left empty. Hand overlaps the wood. Frames 1, 2, 3 are near-identical, so progression through the reload is barely visible.

D3 m4, frames 1, 2, 3 (DIRECT). Same pose as D2 (trigger hand parked on the wood, empty grip, near-static 25/50/75).

D4 ar, ar_t1, ar_t2, frames 1, 2, 3 (VISION). Same pattern as D2: right hand off the grip, fixed on the stock, possible clipping into wood, 25% and 75% near-identical.

D5 hunting, frame 2 (VISION). Left hand rises to the front tip of the gun, at or past the muzzle end, and neither hand clearly grips the rifle; right fist lifted off the stock. Frame 3 left hand still beyond the front end. Expected: left hand works the bolt/port.

D6 ar_t3, frames 1, 2, 3 (VISION). Trigger hand floats off the stock with a visible gap in all three reload frames; the gun is held by the left fist at the receiver only. No bolt/mag progress visible between frames.

D7 all rifles and the shotgun, frame 0 (DIRECT). The support arm at rest is a thin, long, almost vertical green-sleeve pole with a tiny fist, a different look from the bare-forearm arm used during reload (pop in scale/appearance between frames 0 and 1). Cosmetic, lower severity.

D8 shotgun, frames 1 to 3 (DIRECT). Both hands stay close to their rest pose; no shell, no visible hand at the loading gate underside, so the per-round reload reads as almost no motion. Not a hand-detached defect; animation legibility only. Medium-low severity.

## 4. Test gap (why scripted PASS coexists with D1 to D6)
t_hands_viewmodel only requires that at least one palm be within 0.06 m of the gun at each sample (the left hand on the mag satisfies it). It does not require the trigger hand to stay on the grip, so a released trigger hand passes. Suggest an added assertion: trigger-hand palm within ~0.08 m of the grip for non-bolt styles throughout reload (not changed here; source and existing tests untouched).

## 5. Not covered / limits
- Judged from still frames at four points only, no video.
- Pistol assumption from the brief ("held with both hands at rest") holds at frame 0 for DIRECT weapons I viewed.
- M4 and AK share rifle_001 by design (only length differs per gun_mesh.gd); not counted as a defect. Their rest frames differ byte-wise (md5 differs).
- VISION-graded defects (D4 to D6) are not confirmed by my own eyes.

## 6. Cleanup
tests/_probe_final3.gd removed. Frames left in /tmp/qa3 only.
