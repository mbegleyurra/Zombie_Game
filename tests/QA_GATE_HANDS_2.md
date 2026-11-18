# QA GATE: first-person hands + reload, round 2 (RAT, 2026-11-16)

Scope: scripts/weapons/viewmodel.gd and tests/t_hands_viewmodel.gd (PLAGUEMASTER). Source was read-only; only tests/ touched.

## Verdict: FAIL (all 9 weapons)

The test suite is green, but the rendered frames do not meet the bar. Judged from the images, not the test counts.

## Tests (run one at a time, each under xvfb-run -a, 1280x720, llvmpipe)

| Test | Result |
|---|---|
| tests/t_hands_viewmodel.gd | rc=0, 175 PASS, 0 FAIL, "RESULT PASS" |
| tests/t_blaster_guns.gd | rc=0, 216 PASS, summary line "0 FAIL" |
| tests/t_viewmodel.gd | rc=0, 209 PASS, 0 FAIL |
| tests/t_rifle.gd | rc=0, 44 PASS, 0 FAIL |
| scripts/player/smoke_test.gd | rc=0, 50 PASS, "failures=0" |

No SCRIPT ERROR or Parse Error in any log.

## Screenshots

Rendered by a probe (deleted afterwards). 37 frames, every weapon in WeaponDB.ids() at rest and at 25/50/75% of a reload with an empty chamber (reload frames driven by `advance()`):

    tests/shots/qa2/<id>_0rest.png, <id>_25.png, <id>_50.png, <id>_75.png
    ids: pistol ak m4 shotgun hunting ar ar_t1 ar_t2 ar_t3
    tests/shots/qa2/third_person.png

## Per-weapon verdict

| Weapon | Rest | 25 / 50 / 75 % reload | Verdict |
|---|---|---|---|
| pistol | FAIL: hands flat and wedge-like, not gripping; gun small, floating above them; two hands read as one peach mass | FAIL: fists stacked and touching, only one sleeve clearly visible; a cylinder-like part looks detached and oversized next to the lower hand | **FAIL** |
| ak | Two hands present (forward fist, rear hand), gun tiny and mostly hidden | FAIL: hands stacked along the gun axis, one forearm visible, they read as one column | **FAIL** |
| m4 | Two hands present, gun tiny | FAIL: stacked at 25/50/75; magazine appears as a gray slab across the fingers, not seated | **FAIL** |
| shotgun | Two hands present | FAIL: stacked and nearly merged at all three samples; gun mostly covered; no shell or pump readable | **FAIL** |
| hunting | Two hands present | FAIL: stacked column again; only weapon where the right hand moves (0.106 m), but the frames still read as merged | **FAIL** |
| ar | Two hands present | FAIL: stacked, gun body hidden | **FAIL** |
| ar_t1 | Two hands present | FAIL: same stacked column | **FAIL** |
| ar_t2 | Two hands present | FAIL: same stacked column | **FAIL** |
| ar_t3 | Two hands present | Closest to acceptable: at 50% a small gap shows between hands, magazine visible in the lower hand; still crowded, gun mostly hidden | **FAIL (marginal)** |

Common to all: hands are large relative to the gun, the gun shows as a thin sliver pointing steeply up and away, and the receiver and magazine well are hidden behind the fingers. The "no_depth_test" hands cover the gun entirely during a reload.

Coverage note: pistol, ak and m4 also got per-frame image_analyze reads, which agreed. Pistol and hunting were judged from my own view of their montages; I did not re-view them after the later frames. ar, ar_t1, ar_t2 (rest and 50% only), shotgun, m4, ar_t3 were judged from the final contact sheets.

## Third person

PASS. tests/shots/qa2/third_person.png shows the character from behind with raised arms and a small light-blue mitten hand at the end of each. Hands are present. No gun is visible in that pose; not part of this gate.

## Stats and recoil versus git

- scripts/weapons/weapon_data.gd: no diff against HEAD.
- scripts/weapons/weapon_db.gd diff adds only `DUP_PICKUP_MAGS := 2`, `START_RESERVE_9MM := 90` and `dup_pickup_rounds()`. No existing weapon stat line changed. I did not diff per-weapon values programmatically; this is from the diff text.
- Recoil constants unchanged (no recoil lines in any diff).
- weapon_controller.gd: HIP_POS changed from (0.2,-0.21,-0.4) to (0.1,-0.12,-0.42), and the lowering dip is reduced when hands exist. These are viewmodel placement changes, not stats.

Unrelated behavior change (not hands work): picking up a duplicate gun now gives 2 magazines of ammo (was 1), and the starting 9mm reserve is 90 (was 45). Used in inventory_grid.gd:176, player.gd:181 and :453. Confirm this is intended.

## Defects

1. **Hands merge during every reload** (all 9). Owner: PLAGUEMASTER, viewmodel.gd `_pose_mag`/`_pose_shell`/`_pose_bolt`. The support hand works a point only about 9 cm from the trigger hand, and a palm is 8.8 cm wide, so they touch. Needs the support hand pulled clearly away from the trigger hand (to the side or forward of it, at least about 14 cm between palm centres).
2. **Test cannot see this defect.** Owner: PLAGUEMASTER, tests/t_hands_viewmodel.gd. `MIN_PALM_GAP = 0.085` is smaller than the palm width, and the check measures palm centres, so two touching hands pass. The skin-pixel count also passes with merged hands. Raise the gap threshold to match the visible hand width plus margin, and add an image-based separation check.
3. **Gun hidden during reload** (all rifles, shotgun, hunting). Owner: PLAGUEMASTER. Hands and forearms always draw over the gun and cover its receiver and mag well, so the mag swap is hard to read. Hands should hold the gun, not cover it.
4. **One forearm is missing or hidden in most reload frames.** Owner: PLAGUEMASTER. The left sleeve drops out of frame at 25-75%, leaving two hands on one arm.
5. **Pistol rest pose does not grip.** Owner: PLAGUEMASTER. Hands look flat, the gun floats, and a loose cylinder-like part sits beside the lower hand.
6. **Trigger hand never moves** in rifle, pistol and shell reloads (right travel 0.000 m). Owner: PLAGUEMASTER. Only the left hand animates. Minor; acceptable if intended.
7. **Unrelated ammo changes in weapon_db.gd.** Owner: lead to confirm. See above.

## Cleanup

Probe script tests/r_probe_hands2.gd deleted. Screenshots in tests/shots/qa2/ kept as the evidence referenced above.
