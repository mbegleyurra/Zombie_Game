# Dead Acres - Progress Log

Godot: /home/kali/tools/godot/godot (4.7.2). Language: GDScript. No git, no commits.
Setting: modern rural region (farms, gas station, hospital). Co-op 2-4 players, host-based. PVP later.
Style: low poly (Deep Rock Galactic look) with a higher polygon count than before.
Note: this VM uses software rendering, so Rat tests logic, scripts and networking, not frame rate.

Check command (headless): /home/kali/tools/godot/godot --headless --path /home/kali/Documents/ZombieGame --quit-after 120

## Ownership
- PLAGUEMASTER (engineer): world, terrain, buildings, loot, day/night
- MASTER CHIEF (engineer-2): player, weapons (realistic ballistics, ammo, reload, recoil), zombie AI
- GRIM REAPER (engineer-3): multiplayer (ENet host/join), player building, networked state sync
- RAT (engineer-4): tests only

## Rounds

### MASTER CHIEF: player, weapons, zombies (done)
- Files: scenes/player/player.tscn, scenes/zombies/zombie.tscn, scripts/player/{player,smoke_test}.gd,
  scripts/weapons/{weapon_data,weapon_db,gun_mesh,weapon_controller}.gd, scripts/zombies/{zombie,spawner}.gd
- Player scene node name = peer id. Player owns a "PlayerSync" MultiplayerSynchronizer; do not add a second one for the same props.
- World must contain ONE node with scripts/zombies/spawner.gd (class ZombieSpawner, group "spawner") at the same path on all peers.
  Day/night: put a node in group "daynight" with get_night_factor() -> 0..1, or call spawner.set_night_factor(f).
- Weapon ids: pistol(9mm) ak(762) m4(556) shotgun(12ga) hunting(762). player.give_weapon(id), player.add_item("556", n).
- Bullet collision masks: world=layer 1, players=layer 2, zombies=layer 3 (value 4). Anything bullets should stop on must be on layer 1.
- Interact: any collider (or a parent up to 3 levels) with interact(player) and optional get_prompt() -> String; E key.
- Smoke test: godot --headless --path . --script res://scripts/player/smoke_test.gd  (46 checks)

### Round 1 - RAT verdict: NOT WORKING
Passing: world determinism, interiors, 5 guns fire/reload, zombie states, building place/remove, headless check 0 errors.
Defects (see tests/ROUND1_REPORT.md): no zombies in main, two local players when hosting, host seed ignored, loot ammo ids mismatch, loot never feeds building, no guns lootable, host-to-client sync broken, weapons fire in build mode, zombies ignore built pieces, main scene skips menu.

### Round 2 - dispatched to engineers with all 10 defects split by ownership

### Round 2 (engineers done, lead verified)
- Fixed: spawner in main.gd, one local player, host seed used, loot feeds Building, weapons lootable, ammo id mapping, no firing in build mode, zombies attack built pieces, host sync (t_mp_real 12/12), menu as main scene with Play Solo, faceted meshes.
- Lead re-run: t_world, t_mp_main, t_loot_r2, t_solo_r2, t_round2, t_solo, t_mp_real, selftest, smoke_test all pass; project and main scene load with no errors.
- Open: t_core fails 1 check ("picked-up planks become usable Building material": stock 3 -> 3). Passes in t_loot_r2, so either the t_core setup or a real bug in the t_core path. RAT to adjudicate in round 3.
- Not yet verified: visuals, frame rate, real mouse input, two-process co-op with real player, zombie spawning in live play.

### Round 5 - MASTER CHIEF (D2 fix + zombie feel)
- D2: Player.request_damage now sends through scripts/player/damage_relay.gd (child node "DamageRelay" on every Player, no synchronizer, so the "peer cannot see this node" check never blocks it). Hits are retried every 0.4 s until acked, deduplicated by (sender, seq). Health stays owned/replicated by PlayerSync.
- Zombie: replicated `winding` flag = planted wind-up (arms overhead, no step cycle), 0.55 s walker / 0.35 runner / 0.8 bloater; strike plays on every peer on the falling edge. Hits interrupt a wind-up and shove the zombie back (existing flinch/stagger kept). Footsteps: zombies make none.
- Reload times per gun already differ (WeaponDB reload_tactical/reload_empty; shotgun per shell); unchanged.
- New test: tests/t_r5_dmg.gd (host + early client + late joiner, 13 PASS).
- smoke_test.gd zombie-hit window widened 14 s -> 20 s (wind-up is longer).
