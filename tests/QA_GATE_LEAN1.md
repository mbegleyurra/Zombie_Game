# QA GATE LEAN1 — lean + third-person gun direction + body animations

Run by RAT, 2026-11-18 19:31-19:45 EST. Source read-only; nothing under scripts/ was edited.

## Verdict: BLOCKED (FAIL). The lean change has not landed.

The gate was meant to run after PLAGUEMASTER reported. His change is not in the tree.

Pre-check: scripts/player/player.gd was last modified 12:01 and player_model.gd at 18:22. Both were quiet for more than 1 hour at 19:31, so the 2-minute quiet window held.

Evidence that lean does not exist:
- `grep -rni lean` over every .gd, .tscn and project.godot: the only hits are two comments in scripts/zombies/zombie.gd. There is no lean code and no lean input action. Q/E are not mapped to lean.
- `git diff` of player.gd (+44/-1) and player_model.gd (+50): the changes are backpack work only (`backpack_id` sync). There is no lean code and no change to how pitch drives the gun or arms.
- tests/t_lean.gd does not exist.

## Items

| Item | Result | Notes |
|---|---|---|
| (a) FP lean L/R: camera roll and shift, gun follows the crosshair, no wall clip | FAIL (not implemented) | Nothing to render. Owner: scripts/player/player.gd (lean input, camera roll/offset, wall-probe). |
| (b) TP (V) and remote peer at pitch -30/0/+30: barrel on aim, gun in hands, body leans | FAIL (not implemented) | Lean is absent from the body and is not replicated. The lean property must also be added to the sync list in player.gd. Gun-direction fix also not landed. Owner: scripts/player/player_model.gd (`animate()` has no lean parameter). Not rendered: there is no post-fix state to judge, and the original defect report already covers pre-fix behaviour. |
| (c) Armed idle/walk/sprint/crouch clips, arms hold the gun | FAIL (no change landed) | player_model.gd diff touches no animation code. Owner: scripts/player/player_model.gd. |

Frame paths: none. No frames were rendered because no lean or gun-direction change exists to evaluate.

## Suites (baseline, xvfb opengl3, timeout 280s each, runner /tmp/qa7/run_lean1.sh)

| Suite | Result |
|---|---|
| t_lean | MISSING (tests/t_lean.gd not present). FAIL. |
| t_backpacks | PASS 70/70 |
| t_map_ui | PASS 54/54 |
| t_no_primitives | FAIL 4/5. See defect D1. |
| t_hands_viewmodel | PASS 295/295 |
| smoke_test (res://scripts/player/smoke_test.gd) | PASS 50/50 |

Logs: /tmp/qa7/lean1/*.log

## Defects

- **L1** (scripts/player/player.gd): no lean. Required:
  - Q/E hold-to-lean input actions in project.godot.
  - Camera roll and lateral shift.
  - A wall probe so leaning into a wall cannot push the camera through it.
  - `lean` added to the replicated property list.
- **L2** (scripts/player/player_model.gd): `animate()` takes no lean value. The torso and spine do not lean, and the third-person and remote gun direction is unchanged.
- **L3** (tests/t_lean.gd): suite does not exist. It should be written alongside L1 and L2.
- **D1** (scripts/weapons/gun_mesh.gd `_build_moving_part`, or the tests/t_no_primitives.gd allow rule): t_no_primitives flags `ChargingHandle (ArrayMesh) under MovingPart`.
  - Gate 7's A2 fix landed: the handle is now cut from the .glb via `_split_out` and is no longer a BoxMesh.
  - The split ArrayMesh has an empty resource_path and is not under a res://assets/ scene, so the test's asset check misses it.
  - This is a classification miss, not a primitive. Fix either side:
    - gun_mesh.gd tags split parts (for example a meta flag the test honours), or
    - the test treats MovingPart children of a pack gun as asset-derived.
  - Owner: MASTER CHIEF (gun_mesh.gd). The test change needs the lead's sign-off; it was not made here to avoid weakening a gate.

## Probe files

None were created under the project. The runner lives at /tmp/qa7/run_lean1.sh, outside the repo.

## Re-run

Re-run this gate once PLAGUEMASTER's lean, gun-direction and animation changes land:

```
sh /tmp/qa7/run_lean1.sh
```

Then render items (a), (b) and (c) with the /tmp/qa7 xvfb method.
