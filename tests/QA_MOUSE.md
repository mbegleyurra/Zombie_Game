# QA: MouseGuard mouse-capture change (RAT, 2026-11-16)

Verdict: no regression from MouseGuard in the suites run. Two failures exist, both reproduce identically with the autoload removed. The actual VM fix (cursor staying in the window) cannot be proven without a real pointer grab.

## 1. What MouseGuard does
- Script: scripts/ui/mouse_guard.gd. Autoload: project.godot line 14, `MouseGuard="*res://scripts/ui/mouse_guard.gd"` (only change in the project.godot diff).
- process_mode ALWAYS. `_process` polls `Input.mouse_mode`: CAPTURED sets `_want_captured = true`, VISIBLE sets it false. Other modes change nothing.
- Focus: window `focus_entered`, window `mouse_entered` and NOTIFICATION_APPLICATION_FOCUS_IN call `_reapply()`, which sets CAPTURED only if `_want_captured` and the mode is not already CAPTURED.
- Edge fallback (`_input`): while CAPTURED, a MouseMotion within 40 px of any window edge triggers `Input.warp_mouse(window centre)`. The next motion event within 4 px of centre is swallowed (set_input_as_handled) so the warp does not jerk the camera.
- Click re-capture is NOT in MouseGuard. It is player.gd:218 (any mouse button while VISIBLE sets CAPTURED, in `_unhandled_input`). Esc releases at player.gd:216 and hud.gd `open_pause`.
- Release on pause/menu/inventory/map/death/workbench is done by each UI's own script, not by MouseGuard. MouseGuard only follows the mode.

## 2. Release / recapture audit (static)
| Screen | Release | Recapture | File |
|---|---|---|---|
| Main menu | VISIBLE in _ready | player sets CAPTURED on spawn (player.gd:173) | menu.gd:22 |
| Pause | VISIBLE (hud.gd:163) | close_pause(recapture) sets CAPTURED (hud.gd:174) | hud.gd |
| Loot panel | VISIBLE, saves _prev_mouse | restores _prev_mouse | hud.gd:132-141 |
| Inventory | VISIBLE, saves _prev_mouse | close() sets CAPTURED unless _blocked | inventory_ui.gd:184-203 |
| Map | VISIBLE | CAPTURED unless _blocked | map_ui.gd:477-492 |
| Crafting | VISIBLE | CAPTURED | crafting_ui.gd:84-101 |
| Workbench / base UI | VISIBLE | CAPTURED | base_ui.gd:94-110 |
| Death / respawn | VISIBLE in _show and re-forced each frame (death_ui.gd:83) | _hide sets CAPTURED unless paused | death_ui.gd:136-146 |

Conflicts: no script fights MouseGuard. All writers set CAPTURED or VISIBLE, and MouseGuard only re-applies CAPTURED when the last observed mode was CAPTURED. Because it polls, there is a one-frame lag between a game change and MouseGuard noticing.

Observations (not verified at runtime):
- player.gd:218 recaptures on ANY unhandled click while VISIBLE. If an overlay leaves empty areas with mouse_filter pass/ignore, a click there could recapture the mouse while the UI is open. Owner: player.gd (gameplay/player engineer). Suggest also checking `Hud.is_ui_open()` there. Unproven: t_inventory_ui and t_r4_ui pass, but they send no real click.
- fallback_camera.gd:17 captures on any click unconditionally. Only relevant in the fallback camera, pre-existing.
- death_ui re-forces VISIBLE each frame, so a click while dead can flicker CAPTURED for one frame (cosmetic).

## 3. Test results (xvfb 1280x720, opengl3, run one at a time, project folder)
| Test | exit | PASS | FAIL | SCRIPT ERROR |
|---|---|---|---|---|
| smoke_test | 0 | 50 | 0 | 0 |
| t_r4_pause | 1 | 23 | 1 | 0 |
| t_r4_ui | 0 | 26 | 0 | 0 |
| t_inventory_ui | 0 | 37 | 0 | 0 |
| t_map_ui | 1 | 53 | 1 | 0 |
| t_respawn | 0 | 38 | 0 | 0 |
| t_workbench | 0 | 26 | 0 | 0 |
| t_crafting | 0 | 88 | 0 | 0 |
| t_ui_readable | 0 | 99 | 0 | 0 |
| t_qa_mouse_probe | 0 | n/a (prints only) | 0 | 0 |

- Failures: t_r4_pause "Esc again closes the overlay"; t_map_ui "player marker follows movement".
- Baseline: copy of the tree in /tmp/qa/base with the MouseGuard line removed gives the same two failures with the same counts (23/1 and 53/1). Not caused by MouseGuard. Owners not determined; the Esc one touches hud.gd/pause_menu.gd, the marker one map_ui.gd (see QA_GATE_MAP.md note about bind()).
- Non-fatal ERROR lines: "2 resources still in use at exit" (all suites), `Condition "!is_inside_tree()"` in t_r4_ui. Not mouse related.
- Probe under xvfb (X11): `Input.mouse_mode` set to CAPTURED reads back 2 on the next frame, so CAPTURED assertions are meaningful under xvfb (unlike --headless, where writes are ignored).
- No test exercises MouseGuard itself: no focus-in, no edge warp, no scripted mouse motion. Its code path is covered only by it loading without script errors.

## 4. Cannot be verified here
- Whether the VM actually keeps the cursor inside the window. xvfb has no absolute-pointer/tablet integration or real pointer grab.
- Whether Godot delivers MouseMotion with absolute positions while CAPTURED in that VM, which the edge warp depends on, and whether warp_mouse works there.
- Real focus_entered / mouse_entered ordering on window focus change.
- Camera jitter from warp events with a real device.
- The click-recapture-over-open-UI risk above.
Needs a hands-on check by the Commander in the VM: click into the window, move to the edges, Alt-Tab away and back, open inventory/map and click empty space.

No game code was edited.
