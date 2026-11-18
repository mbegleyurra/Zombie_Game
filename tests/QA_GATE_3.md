# QA GATE 3 (RAT) - 2026-11-16

Scope: all work not yet gated (flat roads, city/road kit, buried pickups, more ammo, Blaster gun swap, pickup visuals).
Method: every Godot suite run ONE AT A TIME with `xvfb-run -a godot --path . --script res://<file>` from the project folder.
Counts: pass = lines starting `PASS`; script errors = `SCRIPT ERROR|Parse Error`. Raw logs: /tmp/qa3/ (sweep A) and /tmp/qa3s/ (sweep B).

IMPORTANT - the tree moved under the gate. Another run edited `city_kit.gd`, `city_interiors.gd` (new), `terrain.gd`,
`world_builder.gd`, `t_citykit.gd`, `t_flatroads.gd` between 21:00 and 21:20. So there are two sweeps:
- Sweep A: tree as it was at ~21:00 (before those edits). Findings 1 and 5 were measured here.
- Sweep B: frozen copy of the tree at 21:19:06 in /tmp/qa3_snap (script md5 manifest 3df2e514a59bfe4290cdcffeee266f57). Items re-measured there.
Nothing was gated against edits made after 21:19 except the one live t_citykit re-run noted below.

## Suite results (script errors are 0 in every suite, both sweeps)

| suite | sweep A pass/fail | sweep B pass/fail |
|---|---|---|
| t_flatroads | 15 / 0 | 19 / 0 |
| t_more_ammo | 41 / 0 | 41 / 0 |
| t_pickup_visuals | 454 / 0 | 454 / 0 |
| t_resources | 19 / 0 | 19 / 0 |
| t_handworld | 34 / 0 | 34 / 0 |
| t_citykit | 24 / 0 (old, count-only test) | 33 / 2 (see item 3) ; LIVE re-run 21:20 on newest file: 35 / 0 |
| t_vehicles | 35 / 0 | 35 / 0 |
| t_qa_world | 59 / 0 | 59 / 0 |
| t_blaster_guns | 198 / 0 | 198 / 0 |
| t_rifle | 44 / 0 | 44 / 0 |
| t_inventory_grid | 45 / 0 | 45 / 0 |
| t_crafting | 88 / 0 | 88 / 0 |
| t_workbench | 26 / 0 | 26 / 0 |
| t_forest | 54 / 0 | 54 / 0 |
| t_map_ui | 54 / 0 | 54 / 0 |
| smoke_test | 50 / 0 | 50 / 0 |
| t_qa_pavement (new, mine) | 3 pass / 1 FAIL | 4 / 0 |
| t_qa_recoil (existing) | not run | 0 / 9 FAIL (item 4) |
| t_city_interiors (other run's new test) | - | 15 / 0 |

Notes: the "fail=1" my summary script printed for t_pickup_visuals and t_blaster_guns is a grep artefact: the line `... : 0 FAIL`. Real failures 0.
The `ERROR:` lines (0-7 per suite) are Godot teardown noise ("Texture with GL ID ... leaked", "resources still in use at exit"); no script errors, exit code 0.

## Verdicts

1. Road flatness / pavement overlap - PASS now, was FAIL.
   - Flatness: t_flatroads sweep B: worst lateral deviation 0.00000 m over 3136 cross samples, worst second difference 0.00003 m, city grid one height (range 2.0000-2.0000), road mesh 0.06-0.08 m above ground, none under or floating.
   - Overlap, sweep A (measured real bounds of every strip against the baked road mesh): tile-low (scale 12) 17 of 17 strips overlapped road tiles, up to 4.34 m deep (e.g. strip rect at x 74.5, z -69.14, 12 x 12 m, 270 road triangles inside). driveway-short (scale 10): 0 of 17 overlap.
   - Sweep B (after the `STRIP_D` change in city_kit.gd): tile-low 0 of 17 overlap, driveway-short 0 of 17.
   - Regression test added: tests/t_qa_pavement.gd (fails on sweep A tree, passes on sweep B).
   - Owner of the fix was PLAGUEMASTER (city_kit.gd `_frontage`).

2. Industrial plaza water tower / chimney-large - PASS. Both plaza colliders (blocks at (134,-46) water tower, (134,-134) chimney) overlap NO other box collider in xz. Sweep A: tower box 3.83 x 3.74 m, chimney 3.46 x 3.46; sweep B: 2.9 x 2.82 and 2.8 x 2.8 after scale constants. Now enforced in t_citykit.

3. t_citykit strengthened - DONE, with a caveat. I added: every tower footprint must have its own box collider (centre + footprint match), colliders must reach the model roof, and plaza colliders must collide with nothing else. Another run then rewrote the same file (adds `_collider_problems` plus self-tests that prove the checker can fail). The newest file passes 35/0 live.
   - Sweep B (21:19 version) failed 2: (a) "collider as tall as model" for lots (99.5,-55.5), (80.5,-36.5), (80.5,-143.5), (99.5,-124.5): these are the enterable buildings, where `city_interiors.gd furnish()` replaces the single box by a wall ring + upper block (upper block 5.64 = 9.04 - 3.4 ground height). Not a missing collider; the check must compare roof line (the newest file does). (b) a new "strips placed" count was 2, fixed in the newest file.
   - Not verified: I did not review the other run's final t_citykit.gd line by line, only that it passes.

4. Gun stats / recoil vs the Blaster swap - PASS for "untouched", with one OPEN pre-existing defect.
   - Compared against /tmp/mut (the tree copy from the previous gate; the project has no .git, so this is not git HEAD): weapon_data.gd and weapon_controller.gd are byte-identical. weapon_db.gd differs only by the new `DUP_PICKUP_MAGS` / `START_RESERVE_9MM` / `dup_pickup_rounds` (more-ammo work, intended). gun_mesh.gd and viewmodel.gd differ only by the Blaster Kit skin code (visual).
   - t_blaster_guns 198/0, t_rifle 44/0, t_more_ammo 41/0.
   - OPEN DEFECT (pre-existing, identical to the earlier gate log /tmp/final_t_qa_recoil.log): t_qa_recoil 0 pass / 9 FAIL. Pistol/ak/m4/ar/ar_t1-3 kick is 0.75x old, request was ~0.5x; shotgun and hunting are 1.50x, should be 1.0x. Cause: `RECOIL_GAIN := 1.5` scripts/weapons/weapon_data.gd:8, applied at :114. Owner: MASTER CHIEF. Not caused by the Blaster swap. Decision for the Commander: t_qa_recoil encodes "halve recoil, leave shotgun/hunting"; if 1.5 is the wanted feel, the test must change instead.

5. Hartley Farm driveway drop - REPORTED (was real on sweep A), RESOLVED on sweep B by someone else's terrain.gd edit; I changed nothing.
   - Sweep A: pad -6.15 at the farm, ground 2.00 at the gate (-8,-84), driveway seg (-8,-84)->(-18,-84) dropped 7.99 m in 10 m (80% grade). Axis heights: x=-10 1.19, -12 0.37, -14 -0.45, -16 -2.61, -18 -5.99, x<=-20 -6.15.
   - Farm floor: NOT buried (pad flat at -6.15 for x<=-20, 0 of 41 meshes fully buried). Fences: YES buried - front fence colliders at (-11,-94.5) and (-11,-73.5) had top -4.89 m under ground -2.79/-2.65; a box collider at (-12.46,-87) had top -4.45 under ground 0.18 (3 buried colliders of 74).
   - Sweep B: gate ground -6.10, driveway drop 0.05 m, 0 of 74 farm colliders buried. Side effect to watch: the road this driveway joins now sits near -5.9 at (0,-84) where sweep A had 2.0; t_flatroads still passes.
   - Remaining steep driveways in sweep B (not asked for, FYI): seg 79 Olsen (-30,148) 24% grade (4.06 m / 16.8 m), seg 75 Miller 18%, seg 81 Brandt 18% (4.51 m / 25 m). t_flatroads' own limit is 35%, so no failure. Owner if the Commander wants them flatter: PLAGUEMASTER (terrain.gd / world_builder.gd driveway profile).

6. Leftover probe files
   - tests/: `_probe_a.gd` (21:12) and `_probe_b.gd` (21:18) existed DURING the gate, written by another active run. By 21:20 both were gone (their author removed them). I deleted nothing. `ls tests/_probe_*` at the end: none.
   - /tmp (not this crew's tests/ folder, NOT deleted): check_dress.gd, check_face.gd, check_variants.gd, dbg.gd, dump_arms.gd, dump_bones.gd, dump_mat.gd, dump_uvcolors.gd, dump_zombie.gd, hud_head.gd, inspect_glb.gd, measure_models.gd, pose_debug.gd, pose_test.gd, probe2.gd, probe3.gd, probe4.gd, probe_items.gd, probe.log, probe_1.txt, probe_7.txt, probe_42.txt, probe_777.txt, probe_999.txt, probe_31337.txt, r5probe/, o_t_r3_hitprobe.gd.txt, latency-view-probe.csv. Mine: /tmp/qa3_probe.gd, /tmp/qa3_probe2.gd, /tmp/qa3_run.sh, /tmp/qa3, /tmp/qa3s, /tmp/qa3_snap (239 MB copy, safe to delete).

## Defects to send back

| # | file:line | evidence | owner | status |
|---|---|---|---|---|
| D1 | scripts/weapons/weapon_data.gd:8,:114 | t_qa_recoil 0/9: ratios 0.75 (pistol/rifles), 1.50 (shotgun/hunting) | MASTER CHIEF | OPEN (pre-existing) |
| D2 | scripts/world/city_kit.gd `_frontage` tile-low strip | 17/17 strips 4.34 m into the street on sweep A | PLAGUEMASTER | fixed in sweep B |
| D3 | scripts/world/terrain.gd / world_builder.gd Hartley driveway | 7.99 m drop, fence colliders buried 2 m | PLAGUEMASTER | fixed in sweep B |
| - | GRIM REAPER (pickup visuals) | t_pickup_visuals 454/0 | - | no defects |

## Files changed by this gate
- tests/t_citykit.gd (collider/plaza assertions; later rewritten by another run), tests/t_qa_pavement.gd (new), tests/QA_GATE_3.md.
- No game code edited.
