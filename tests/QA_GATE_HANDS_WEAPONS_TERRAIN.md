# QA gate: hands + reload, ITHappy weapons, smooth terrain (RAT, 2026-11-16)

Source was not edited. Only files under tests/ were touched (this report, plus screenshots written by the existing
t_hands_viewmodel run). Two probe scripts (tests/_probe_guns.gd, tests/_probe_world.gd) were created and deleted.
Godot 4.7.2 at /home/kali/tools/godot/godot. Rendering under xvfb-run (llvmpipe, Compatibility renderer); logic tests with --headless, run one at a time.

Note on method: the image_analyze answers contradicted each other on several frames, so the verdicts below come from
looking at the PNGs directly. Pixel-count asserts in t_hands_viewmodel do not prove the hands look right.

## Verdicts

| Item | Owner | Verdict |
|---|---|---|
| 1. Hands and reload | MASTER CHIEF (engineer-2) | FAIL (test green, visuals not acceptable) |
| 2. ITHappy weapons | MASTER CHIEF | PASS, with notes |
| 3. Smooth terrain | PLAGUEMASTER | PASS, with a cost note |

## 1. Hands and reload: FAIL

Run: `xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --script res://tests/t_hands_viewmodel.gd`
Result: rc=0, 139 PASS, 0 FAIL, RESULT PASS. Weapons covered: pistol, ak, m4, shotgun, hunting, ar, ar_t1, ar_t2, ar_t3.
Reload hand travel (left/right, metres): pistol 0.138/0.000, ak 0.392/0, m4 0.419/0, shotgun 0.477/0, hunting 0.507/0.113,
ar 0.405/0, ar_t1 0.364/0, ar_t2 0.378/0, ar_t3 0.536/0. Off-frame samples 0/10 for all. Skin pixels at rest 12.8k-17.4k, mid-reload 20.9k-29.7k.

What the pixels show:
- Both forearms and tan block hands are visible at rest on every weapon. The AK rest frame reads best: rear hand on the grip, front hand on the handguard.
- Pistol at rest: the gun is small next to chunky hands and the finger blocks are clumped beneath it; it does not read as a held pistol.
- Pistol reload (tests/shots/hands_pistol_reload.png): the hands merge into one tan mass with only one sleeve visible, the revolver cylinder is large and near the camera while the rest of the gun is small and far up the screen, so it does not read as one object.
- Sniper (hunting) reload (tests/shots/hands_hunting_reload.png): the gun is low and nearly edge-on, both hands are bunched above it near the horizon and neither touches it. Black faces on the sleeve cuffs, a large flat skin-coloured slab behind the hands, and cuffs detached from their hands are visible. This is the clearest defect.
- Reload does visibly move the hands (the AK mid-reload frame shows a loose magazine in the lower hand and the gun tilted), so animation exists; the problem is hand-to-gun alignment on some weapons.
- Right hand never moves in 8 of 9 reloads (travel 0.000): only the off-hand animates, which is plausible for rifles but makes the pistol reload read as one hand.
- Third person (hands_third_person.png, from behind): body with arms and blue mitten hands is visible; no gun is visible from that angle. A side view with the probe (AK, avatar gun at (0, 0.64, -0.7), scale 1.5, visible) shows the gun held in front of the body. So the third-person model does show hands and a gun; it is only hidden from directly behind.

Test gap: the skin-pixel and palm-in-frustum asserts pass while the sniper reload leaves the hands off the gun. A distance assert between each palm and its grab point (gun-local from vm_profile: grip_l, mag_pos, bolt_hand) at reload mid-point would catch it. I did not add it, since it would fail today until the owner fixes the pose.

## 2. ITHappy weapons: PASS

- gun_mesh.gd BLASTERS maps all 9 WeaponDB models (pistol, ak, m4, shotgun, hunting, ar, ar_t1, ar_t2, ar_t3) to assets/ithappy_weapons/Meshes/Assets files: pistol_001, rifle_001 (ak, m4, ar, ar_t1, ar_t2), shotgun_001, sniper_rifle_001 (hunting, ar_t3). Probe confirmed `blaster=<file>` meta, a Muzzle marker, and a vm_profile for every weapon.
- No reference to assets/kenney/blaster-kit remains in scripts/ or scenes/ (grep empty). The folder assets/kenney/blaster-kit still exists on disk, unused. The names BLASTERS / is_blaster / blaster_dir and tests/t_blaster_guns.gd are stale Kenney-era names.
- Textures: every gun carries one material override from WeaponsMaterial.tres with albedo_texture set (tex=true, colour 0.82 grey tint). Side renders show steel and wood tones on the AK, sniper and shotgun.
- Sniper white blob: not reproduced. The code darkens near-white atlas UVs and a matte material override is applied; the hunting side render and ground pickup show a dark barrel with a brown stock and no white. Pickup render of the revolver-style pistol also correct.
- Scale/orientation: barrel level and pointing down -Z in side view; in-hand lengths 0.28 m pistol to 1.0 m sniper; ground pickups lie flat on y=0 (sizes e.g. ak 0.78x0.19x0.06, hunting 1.0x0.16x0.10).
- Tests: t_blaster_guns 216 PASS, 0 FAIL, rc=0; t_pickup_visuals 454 PASS, 0 FAIL, rc=0. (The raw grep counted one "0 FAIL" summary line each; it is not a failure.)
- Stats vs git HEAD: weapon_data.gd unchanged (RECOIL_GAIN 1.5 intact). weapon_db.gd differs by +10 lines only: DUP_PICKUP_MAGS=2, START_RESERVE_9MM=90, dup_pickup_rounds(). Those are ammo-economy changes from earlier work, not damage or recoil. weapon_controller.gd changed HIP_POS (0.2,-0.21,-0.4 to 0.1,-0.12,-0.42) and reduced the lowering dip when hands are attached; no recoil values touched.
- Notes: the pistol is a revolver model whose reload shows the cylinder as the magazine (see item 1). Sniper and ar_t3 share one model, and four rifle keys share rifle_001; only length distinguishes them.

## 3. Smooth terrain: PASS

Run one at a time, --headless: t_terrain_smooth rc=0 12 PASS 0 FAIL (2 s); t_flatroads rc=0 19 PASS 0 FAIL (10 s); t_handworld rc=0 34 PASS 0 FAIL (11 s); t_vehicles rc=0 35 PASS 0 FAIL (41 s); t_resources rc=0 19 PASS 0 FAIL (10 s); t_forest rc=0 54 PASS 0 FAIL (29 s); smoke_test rc=0 50 PASS 0 FAIL (27 s). No SCRIPT ERROR or Parse Error in any log.
Ground screenshot (seed 1234, player eye height, tests/shots/qa_terrain_ground.png) and overview look smoothly shaded with no visible facets or seams.
Cost: world instantiate 173 ms, world.build 4866 ms (llvmpipe/CPU, headless of GPU cost), 64 chunks, 524,288 terrain triangles, 15,073 scene nodes. About 5 s of build is a loading-screen cost, not a runtime frame cost; I did not measure frame time on real GPU hardware.

## Defect list

1. MASTER CHIEF: sniper (and ar_t3, same model) reload leaves both hands off the gun, with black cuff faces, a stray large skin slab and detached cuffs (hands_hunting_reload.png). High.
2. MASTER CHIEF: pistol reload merges both hands into one mass and detaches the cylinder drum from the gun; pistol at rest is undersized and clumped in the hands (hands_pistol_*.png). Medium.
3. MASTER CHIEF: tests/t_hands_viewmodel.gd cannot catch (1) or (2); add a palm-to-grab-point distance check once poses are fixed. Low.
4. MASTER CHIEF: stale Kenney-era names and unused assets/kenney/blaster-kit folder. Cosmetic.
5. PLAGUEMASTER: none blocking. World build is about 5 s; consider chunked or async generation if load time matters.

Screenshots: tests/shots/hands_<weapon>_{rest,reload}.png, tests/shots/hands_third_person.png, tests/shots/qa_*.png (copies of probe renders).
