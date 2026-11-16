# QA GATE REPORT (RAT) - 2026-11-15

Scope: working tree of /home/kali/Documents/Zombie_Game (uncommitted changes on top of 634bfb3). Tests run headless with
`/home/kali/tools/godot/godot --headless --path . --script res://<file>`. A clean `git archive HEAD` copy in /tmp/base was used as the baseline.
No file under scripts/ or scenes/ was edited. Files added/edited under tests/ are listed at the bottom.

## Verdicts

| # | Item | Verdict |
|---|------|---------|
| 1 | Recoil halved for pistols and rifles | **SENT BACK** (to the weapons engineer) |
| 2 | t_respawn 4/36 mouse-recapture failures | **PASS** - headless quirk, not a game defect (test hardened) |
| 3 | t_r4_pause "Esc again closes the overlay" | **PASS** - passes 5/5 runs; the earlier failure was not reproduced |
| 4 | Full suite + smoke_test + `--quit-after 120` | **SENT BACK** for 8 pre-existing FAILs and script errors (listed below); nothing new broke |
| 5 | Hands/reload, workbench/crafting, inventory grid, gore | **PASS** after I closed two test gaps (t_viewmodel and t_gore were partly vacuous) |

## 1. Recoil - SENT BACK

Measured pitch kick for shot 0..3 via `kick_for_shot()`, HEAD vs working tree (tests/t_qa_recoil.gd prints/asserts this):

| weapon | HEAD shot 0 | now shot 0 | ratio |
|---|---|---|---|
| pistol | 1.700 | 1.275 | **0.75** |
| ak | 1.900 | 1.425 | **0.75** |
| m4 | 1.300 | 0.975 | **0.75** |
| ar, ar_t1-t3 | 1.800 | 1.350 | **0.75** |
| shotgun | 6.200 | 9.300 | **1.50** (not requested) |
| hunting | 3.600 | 5.400 | **1.50** (not requested) |

Root cause: `weapon_db.gd` sets `recoil_scale = 0.5` on pistol/ak/m4/ar, but the same change adds
`const RECOIL_GAIN := 1.5` in `weapon_data.gd:8`, applied in `kick_for_shot` (`* (recoil_scale * RECOIL_GAIN)`, line 114).
Net 0.5 x 1.5 = 0.75, so pistols and rifles are only 25% lower, and every weapon left at scale 1.0 (shotgun, hunting rifle) became 50% stronger.
The viewmodel kickback in weapon_controller.gd:358 is likewise ~0.75x for those guns (`(0.045 + pitch*0.006) * 0.5` vs old `0.03 + pitch*0.004`).
Also: `bloom_per_shot` was removed (t_gore asserts that), which is a separate unrequested behaviour change.

Fix for the engineer: make RECOIL_GAIN 1.0 (pistol/rifles then 0.5, shotgun/hunting unchanged) or set recoil_scale to 0.333 and leave the others compensated.
Re-check with `tests/t_qa_recoil.gd` (currently 9 FAIL, as intended; it will go green when fixed).

The tests named in the item: t_rifle PASS (44/0), t_gore PASS (25/0), smoke_test PASS (50/0). They pass because none asserts the halving: t_gore even asserts `k1 > recoil_pitch` ("global gain makes it stronger than raw recoil_pitch"), which blesses the 1.5x gain. So green here does not mean the request was met.

## 2. t_respawn - headless quirk (PASS)

- `scripts/ui/death_ui.gd` is unmodified from HEAD, and t_respawn fails the identical 4 checks on the clean HEAD copy.
- Probe `tests/t_qa_mouse_probe.gd`: on the headless DisplayServer, `Input.mouse_mode = CAPTURED` reads back 0 (VISIBLE) immediately and on the next frame. Mouse mode simply cannot be set headless.
- death_ui code path is correct: `_show()` sets VISIBLE, `_hide(recapture=true)` sets CAPTURED unless paused, and `respawn()` calls `_hide()`.
- Consequence: the "mouse is freed" checks pass trivially (default is VISIBLE) and the 4 "recaptured" checks can never pass headless.
- Fix applied in the test only: `check_captured()` in tests/t_respawn.gd prints SKIP under headless and asserts for real on a windowed run; the non-mouse halves of two compound checks still run. Result: 0 FAIL, 4 SKIP.
- Limit: recapture itself is therefore unverified headless; it needs one manual windowed run.
- Same quirk explains `t_map_ui: mouse is recaptured on close`.

## 3. t_r4_pause - PASS

4 consecutive runs on the working tree: 24 PASS / 0 FAIL each (plus the full-suite run); the clean HEAD copy also passes. `Esc` flows through hud.gd:192 (`ui_cancel` toggles `open_pause`/`close_pause`); hud.gd and pause_menu.gd are unmodified. I could not reproduce the earlier failure, so I cannot name its cause. Likely suspect (unproven): interference from another test running at the same time (many tests print `Couldn't create an ENet host` when ports are taken). Run tests sequentially.

## 4. Full run

Runner: `tests/run_qa_all.sh` (logs in /tmp/qa/all; exit code captured directly from godot, FAIL and SCRIPT ERROR counted from the logs, no pipeline exit codes).
49 test scripts + selftest + smoke_test + boot check. Results from the full run (before the t_respawn edit):

- smoke_test: 50 PASS / 0 FAIL. `--quit-after 120` boot: exit 0, 0 script errors.
- Real FAIL lines: 12 total, all pre-existing at HEAD (identical on the clean copy):
  - t_respawn x4 (headless quirk; now SKIP, see item 2)
  - t_map_ui x4: `full map canvas has a size (0x628)`, `north-west corner is top-left`, `a point north (-Z) is drawn higher`, `mouse is recaptured on close`. map_ui.gd is modified in the tree and belongs to the pending map job (GRIM REAPER); the first three are real, not the mouse one. **SENT BACK to the map owner.**
  - t_kenney x2: `no SpringArm3D under the player` / `in main scene`. player.gd:650 builds a SpringArm3D for third person (also at HEAD); t_thirdperson (32/0) expects it. Stale assertion in t_kenney, fix is in the test (test owner), not the game.
  - t_forest x2: seed 20260101 `no loot item inside a forest collider (1)`; seed 31337 `forest colliders overlap no other collider (1)` (BoxShape3D@(-99.5,202.6) vs Props/PropCollision). Real world-gen defects, pre-existing. **SENT BACK to the world engineer.**
- Script errors (`SCRIPT ERROR`): only selftest.gd, 180 (164 on HEAD): `Nonexistent 'float' constructor` at hud.gd:243 and `Nonexistent 'bool' constructor` at death_ui.gd:78, i.e. `float()/bool()` applied to a null Variant. Pre-existing, selftest still exits 0.
- Engine noise (not counted as test failures): `Condition "!v.is_finite()"` thousands of times in the multiplayer tests (t_r3_mp_main 3251, t_r4_mp4 204932, t_r5_dmg 41663, t_r5_late 130093; 9719 on HEAD for t_r3_mp_main, others not baselined) - a NaN Vector3 reaches a transform somewhere in the MP path; t_r5_dmg also logs `"spawner" is null` and `ID N not found in cache` (8 each, known from notes). `Couldn't create an ENet host` in many tests (host_solo fallback).
- t_kenney_walker_fit, t_kenney_walker_wind, t_kenney_wind, t_r3_polys report 0 PASS (they are render/diagnostic scripts, not assertions) - they prove nothing.
- Not run: tests/r_kenney_*render.gd (image render scripts).

## 5. Hands, workbench, crafting, inventory grid, gore

Re-run: t_viewmodel 209/0, t_workbench 26/0, t_crafting 88/0, t_inventory_grid 45/0, t_gore 25/0.
To check they assert behaviour, I mutated a copy (/tmp/mut) one behaviour at a time and ran the matching test:

| mutation | test | outcome |
|---|---|---|
| workbench proximity check removed | t_workbench | killed (6 FAIL) |
| same mutation | t_crafting | **survived** (t_crafting does not cover it; t_workbench does) |
| crafting does not consume materials | t_crafting | killed (10 FAIL) |
| deconstruct yields nothing | t_inventory_grid | killed (8 FAIL) |
| grid never rotates items | t_inventory_grid | killed (1 FAIL) |
| blood amount flat for headshots | t_gore | killed (1 FAIL) |
| reload animation frozen at progress 0 | t_viewmodel | **survived** - all 209 checks only test finiteness, duration, state |
| severed parts never hidden | t_gore | **survived** - only checks stump count, reach, gib |

New test `tests/t_qa_motion.gd` closes both surviving gaps: every weapon's hands/gun must travel >0.03 m mid-reload (0.36-0.59 m on real code), and a severed arm/head node must be invisible while the intact arm stays visible.
On the real tree: 13 PASS / 0 FAIL. On the mutated copies it fails (reload frozen: 8 FAIL; hide removed: 2 FAIL). So the behaviour is covered now, and the game code for item 5 is sound.
Remaining limit: t_gore/t_viewmodel are headless; they say nothing about how the hands look on screen.

## Files touched (tests/ only)

- added `tests/run_qa_all.sh` (full runner with honest counts)
- added `tests/t_qa_recoil.gd` (recoil regression, currently FAILS 9: this is the item 1 defect)
- added `tests/t_qa_motion.gd` (reload motion + severed-part visibility, passes)
- added `tests/t_qa_mouse_probe.gd` (headless mouse-mode probe, prints only)
- edited `tests/t_respawn.gd` (`check_captured` SKIP under headless)
- Note: `tests/t_qa_recoil.gd` will make `run_qa_all.sh` show 9 FAIL until item 1 is fixed. That is intended.
