# QA gate: dungeon access (MASTER CHIEF) and base building (GRIM REAPER)

Tester: RAT. Date: 2026-11-16. Godot 4.7.2, seed 20260101 unless noted. No file under scripts/ or scenes/ was edited.

## Verdicts

| Item | Verdict | Owner |
|---|---|---|
| (1) Dungeon access | PASS (test gaps noted, not blocking) | MASTER CHIEF (engineer-2) |
| (2) Base building | SENT BACK | GRIM REAPER (engineer-3) |

## How the probes were run

The real Player (scenes/player/player.tscn, its own `_physics_process`) ignores input unless `Input.mouse_mode` is CAPTURED, and headless Godot ignores that write. The shipped tests therefore use a bare CharacterBody3D. My probes run under `xvfb-run -a godot --rendering-driver opengl3` and steer the real Player with `Input.action_press("move_forward")` plus yaw. Each probe first proves the harness is live (forward input moves the Player; mouse_mode == 2).

- `tests/t_qa_walk_dungeon.gd` (new): 9 PASS, 0 FAIL.
- `tests/t_qa_walk_build.gd` (new): 22 PASS, 1 FAIL (the defect below, intentional).

These two are display-only. Under `--headless` they stall, so `run_qa_all.sh` should skip `t_qa_walk_*`. I excluded them from the suite run.

## (1) Dungeon: PASS

Verified:
- Guard markers 25 to 13 (diff removes 12 `_guard` calls). The boss and all 4 skeleton types remain; loot containers are untouched.
- Real Player walks in through the gate and down the stairs from 6 different approaches and ends at y=-4.47 (floor -4.52). It walks back up and out to the surface (y=2.75). No invisible wall at the entrance.
- 12 of 12 closed doors block the real Player. 12 of 12 open doors let it through. With every door open it walks gate to vault.
- Door contract holds: group interactable, `interact()` toggles state and prompt, RPC handlers exist, and the collider follows the state (`_shape_xf`). The open leaf stays aimable.
- The scratch files `probe_entrance.gd` and `probe_models.gd` do not exist. `probe_heights.gd` (untracked TEMP probe) was also gone by the end of the run.

Test-quality gaps (copy of the tree in /tmp, one mutation at a time):
- Lintel reverted 2.8 m to 2.3 m: `t_dungeon_access` still passes (0 FAIL). The test cannot detect the entrance collider fix it is meant to guard. With a 1.8 m capsule, 2.3 m would not block either, so I could not reproduce the original wall; the 2.8 m change is harmless. Suggested fix: assert a ray or shape query at 2.5 m height through each doorway is clear.
- Door collider never moves on open (`_shape.transform` line replaced by `pass`): `t_dungeon_access` HUNG until the 250 s timeout instead of printing a FAIL. A broken door is caught only by timeout, so the test needs a bounded failure.
- Guards 14 instead of 13: caught (1 FAIL).

## (2) Base building: SENT BACK

Verified OK:
- The real Player climbs both chained stairs (ground y 0.00 to 0.43 on the first ramp, then +2.50 m = WALL_H on the upper floor, `is_on_floor` true), moves on the upper floor, and walks back down to y=0.00.
- Automation ledger, independent of `t_automation.gd`, recipe gun_ar_t2 (12 planks + 24 scrap):
  - deposit debits the carried stock exactly
  - a cycle start takes exactly the recipe cost (30/60 to 18/36)
  - duration equals `craft_time` (22.0 s)
  - no product before the cycle ends
  - two cycles give 2 weapons with leftover 6/12
  - status goes to "Waiting for materials"
  - a withdrawn weapon lands in a weapon slot
- Every listed recipe (10) is feedable from planks and scrap only.
- Mid-cycle chest removal parks the cycle ("No chest nearby", nothing created). A replacement chest receives the product.
- Mutation results: consumption removed gives 11 FAIL in `t_automation`; ramp collider removed gives 3 FAIL in `t_base_build`. Neither suite is vacuous.

Defects (reasons for SENT BACK):

1. **Duplicate weapon withdraw destroys the item.** `base_system.gd` `_server_withdraw` takes the item out of the chest, then `_deliver_local` calls `ItemDB.give_to`. For weapons that calls `WeaponController.pickup_weapon`, which never duplicates and returns the existing slot (`>= 0`), so it reports success. Evidence: with the chest holding 2 `weapon_ar_t2`, withdraw 1 gives slots 1 to 2 and chest 1 (correct). Withdraw 1 more gives chest 0 and weapon slots still 2, so the weapon vanished. Failing check in `t_qa_walk_build.gd`: "a duplicate weapon withdraw does not consume the stored weapon (chest 0, expected 1)". The assembler's output is weapons, so this is a mainline path. Fix: refuse and return the item when the player already holds that weapon (or hand over the ammo or materials value).
2. **HUD build bar does not list the new pieces.** `hud.gd` `_refresh_build` prints only the current kind name and the fixed text "1-5 / Wheel - Select". `building_system.gd` has 10 kinds, bound to keys 1 to 9 and then the 10th kind (assembler) at `KEY_1 + 9` = KEY_COLON (':'), which is not a number key. Stairs, base core, chest and assembler have no visible hint and the assembler has no usable key. Owner decision: add the kinds to the bar and fix the key for the 10th kind.
3. Test gap: `t_automation.gd` and `t_base_build.gd` check weapons only as items in the chest. Neither covers a withdraw of a weapon the player already holds, which is why defect 1 passed.

Minor, not blocking: `t_base_build.gd` walks a bare capsule (it works, my real-Player probe agrees).

## Full suite

All `tests/t_*.gd`, `scripts/net/selftest.gd` and `scripts/player/smoke_test.gd` were run sequentially headless (the `t_qa_walk_*` probes excluded). Counts come from log greps, not exit codes.

- Real FAIL lines: 35, in 11 suites.
- Script errors: 196, all in `selftest` (known); 0 in every other suite.
- smoke_test: 50 PASS, 0 FAIL.
- Dungeon and base suites: t_dungeon 30/0, t_dungeon_access 16/0, t_base_build 56/0, t_automation 39/0 (PASS/FAIL).

| Suite | FAIL | Status |
|---|---|---|
| t_map_ui | 4 | known (same at HEAD) |
| t_kenney | 2 | known (same at HEAD) |
| t_forest | 3 | known 2 at HEAD; in a copy without the world work it shows 2 (different seeds), so the third is seed-dependent |
| selftest | 0 FAIL, 196 script errors | known |
| t_qa_recoil | 9 | not in the known list, but fails identically at HEAD (ratio 0.75 vs expected ~0.5, shotgun/hunting 1.5). Pre-existing, not new |
| t_r5_late | 2 | not in the known list, but identical at HEAD. Pre-existing, not new |
| t_dressing | 3 | NEW vs HEAD (0 at HEAD): "nothing within 20 m of the spawn centre" |
| t_kenney_dress | 4 | NEW vs HEAD (0): road centreline blocked by signpost2 at (70,-64) |
| t_mp_main | 1 | NEW vs HEAD (0): world seed 20260101 instead of Net seed 424242 |
| t_r3_mp_main | 2 | NEW vs HEAD (0): host/client seed mismatches |
| t_r4_mp4 | 4 | NEW vs HEAD (0): host/client seed mismatches |
| t_r4_zombies | 1 | NEW vs HEAD (0): runner closes less distance than walker |

Attribution of the new failures: they come from the concurrent world-generation work, not from the dungeon or base-building changes. The working tree also modifies `scripts/world/world_builder.gd` (+65/-80) and adds `hand_builder.gd`, `hand_layout.gd` and `tests/t_handworld.gd` (plus a `map_ui.gd` edit), and none of that is in the two items under review. In a copy of the tree with only the dungeon and base-building changes (world_builder.gd and map_ui.gd reverted to HEAD, the hand_* files removed), every one of those suites went back to HEAD results: t_dressing 0, t_kenney_dress 0, t_mp_main 0, t_r3_mp_main 0, t_r4_mp4 0, t_r4_zombies 0. The dungeon and base suites still pass 30/16/56/39 there. Owner of the world work is unassigned in this gate; flag to the lead.

Baseline method: copy of the tree with `git stash -u` (HEAD), same suites re-run.

## Final lines

1. DUNGEON: PASS. Real Player walks in and out of the entrance, doors block and open correctly, guards 25 to 13; harden the test (lintel assertion, bounded door-collider failure).
2. BASE BUILDING: SENT BACK (GRIM REAPER). A duplicate weapon withdraw destroys the weapon (chest 1 to 0), and the HUD build bar does not list stairs/core/chest/assembler (assembler sits on ':' key).

## Round 2 re-test (RAT, 2026-11-16): GRIM REAPER fixes

Verdict for item (2) Base building: **PASS** (both defects fixed).

- Defect 1, duplicate weapon withdraw: fixed in `base_system.gd` `_deliver_local` (refuses a weapon the player already holds, so the stored copy is returned to the chest and "Inventory full" is shown). `tests/t_qa_walk_build.gd` under xvfb opengl3: the check "a duplicate weapon withdraw does not consume the stored weapon" passes (chest 1, expected 1). Five consecutive runs after the fix: 0 FAIL. My first run in this round still failed that check; the source files carry mtime 14:39:00, so that run most likely started before the fix landed. I did not re-verify that ordering.
- Defect 2, HUD build bar: fixed in `hud.gd` `_refresh_build` (lists all 10 kinds, brackets the selected one, text "1-9, 0 / Wheel"). New `tests/t_qa_hud_build.gd` (headless, builds the real HUD, pushes real key events): 36 PASS, 0 FAIL. It covers every kind in the bar, the highlight, and keys 1-9 then 0 selecting all 10 kinds including the assembler.
- Still open, test gap only: `t_automation.gd` / `t_base_build.gd` do not cover the duplicate-withdraw case; only `t_qa_walk_build.gd` does. Not blocking.
