# QA GATE FINAL 2 (RAT, 2026-11-17)

Source read-only; only tests/ written. Every suite ran one at a time under `xvfb-run -a` (real renderer, Godot 4.7.2 at /home/kali/tools/godot/godot).
Earlier gate: tests/QA_GATE_FINAL.md (kept). viewmodel.gd was last modified 01:34, after that gate (01:08), so this run covers GRIM REAPER's hands fix.

## Verdicts

| Item | Verdict |
|---|---|
| t_blaster_guns | PASS 216 / 0 |
| t_viewmodel | PASS 209 / 0 |
| t_rifle | PASS 44 / 0 |
| t_dungeon_access | PASS 16 / 0 (the dungeon exit fix holds) |
| t_no_primitives | PASS 5 / 0 |
| smoke_test | PASS 50 / 0 |
| t_hands_viewmodel | UNSTABLE: 207 PASS / 3 FAIL, then 210 / 0 and 210 / 0 on two re-runs. A stray run from another loop gave 206 / 4 |
| First-person hands judged from images (9 weapons x rest/25/50/75 %) | FAIL |

No SCRIPT ERROR or Parse Error in any log.

### t_hands_viewmodel flake
Failing checks in the 207 / 3 run:
- `[m4] rendered reload frames show a gap between the hands (11 px non-skin >= 12)`
- `[m4] hands return to the hold after cancel (left off 0.0000 m, right off 0.0015 m)`
- `[ar_t1] rendered reload frames show a gap between the hands (9 px non-skin >= 12)`

The gap check fails by 1 to 3 pixels, so the margin is thin and the result varies from run to run. I did not find the cause of the variance. A gate cannot call this green: it passed 2 of 4 runs.

## Hands, judged from images
Evidence: 45 renders at 1280x720 in tests/shots/qf2/ (`<weapon>_p00/p25/p50/p75.png`, plus `sheet_<weapon>.png`). I viewed these at full resolution myself:
- ak: p00, p50, p75
- m4: p50
- pistol: p00, p50
- shotgun: p50
- hunting: p50, p75
- ar_t3: p50

ar, ar_t1 and ar_t2 were checked only through the 2x2 sheets, and the other frames were not individually viewed. Judgements from the sheets came from a vision model and disagreed with each other, so I treat them as weak.

What passes in the frames I viewed:
- Two separate hands in every frame, no merged fists.
- The gun is visible and muzzle-forward in every frame.
- The right hand holds the grip on the pistol and the AK-type guns.

What fails:
1. **The left hand is not at the mag well during reload.** On the AK-type rifles and the pistol at 50 %, the left hand holds the magazine below and left of the gun, with a clear gap short of the well. At 75 % on the AK the left fist is still low and empty while the grey magazine sits against the right fist. The viewed frames show no left hand seating a magazine.
2. **Hunting rifle (bolt).**
   - At 75 % the left hand is out at the muzzle end of the barrel, with its forearm running vertically up the left side of the frame.
   - The right hand floats off the receiver.
   - Measured left-palm distance to the port is 0.11 m at 75 %.
3. **Shotgun at 50 %.** The left fist sits below the receiver, not at the port (measured 0.054 m).
4. **Right forearm hides the AK-type stock** in the viewed AK, m4 and ar_t3 frames. I could not separate hiding from real clipping at this view.
5. **Pistol at rest.** The left fist floats well left of and below the gun and does not touch it. If the pistol is meant to be two-handed at rest, this fails. If it is one-handed, it is a design question for the lead.
6. **Left forearm is long and thin; right forearm is blocky.** The pair reads as mismatched.

### Probe measurements disagree with the images
The probe's left-palm-to-target distances (`REACH` lines) were 0.017 to 0.036 m for ak, m4, ar, ar_t1 and ar_t2 at all three stages, which passes the numeric reach checks. The images show a visible gap on the same frames. So the target point (mag_pos + grab_off) is probably not where the model's magazine well really is, or the palm origin is a poor proxy for the fist. This is the reason the tests pass while the animation reads wrong. Larger distances elsewhere:
- shotgun 0.048 to 0.058 m
- hunting 0.033, 0.056 and 0.110 m at 50, 25 and 75 %
- ar_t3 0.047 m at 25 %

## Defect list
1. GRIM REAPER, viewmodel.gd: the left hand does not reach the mag well or shell port in reload, and the hunting-rifle 75 % pose throws the left hand to the muzzle. High.
2. GRIM REAPER or test owner: t_hands_viewmodel is unstable (see above). Medium.
3. Test gap, tests/: the reach check measures to a point that does not match the visible well, so it passes with a visible gap. Medium.
4. Lead decision: pistol left hand at rest.

## Not verified
- ar, ar_t1, ar_t2 and the remaining frames of the other weapons were not each viewed at full resolution.
- Third-person arms were not viewed.
- The cause of the t_hands_viewmodel variance was not found.

## Cleanup
Deleted tests/rat_probe_f2.gd and its .uid file. Kept the screenshots in tests/shots/qf2/ as evidence. tests/r_probe_hands.gd existed before this run and was left alone.
