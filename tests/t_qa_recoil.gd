extends SceneTree
## QA gate regression (RAT): "recoil halved for pistols and rifles". OLD_* are the shot-0 pitch kicks measured on git HEAD
## (b2f39f0..634bfb3, before the recoil change). Pistol/rifles must be ~50% of that (45-55%); shotgun and hunting rifle
## were not part of the request and must be unchanged (95-105%).
## Run: godot --headless --path . --script res://tests/t_qa_recoil.gd
const OLD := {"pistol": 1.7, "ak": 1.9, "m4": 1.3, "ar": 1.8, "ar_t1": 1.8, "ar_t2": 1.8, "ar_t3": 1.8, "shotgun": 6.2, "hunting": 3.6}
const HALVED := ["pistol", "ak", "m4", "ar", "ar_t1", "ar_t2", "ar_t3"]
var fails := 0

func check(cond: bool, label: String) -> void:
	if cond:
		print("PASS  ", label)
	else:
		fails += 1
		print("FAIL  ", label)

func _init() -> void:
	for id in OLD.keys():
		var wd: WeaponData = WeaponDB.get_weapon(id)
		if wd == null:
			check(false, "%s exists" % id)
			continue
		var ratio: float = wd.kick_for_shot(0).y / float(OLD[id])
		if HALVED.has(id):
			check(ratio >= 0.45 and ratio <= 0.55, "%s kick is ~50%% of the old value (ratio %.2f)" % [id, ratio])
		else:
			check(ratio >= 0.95 and ratio <= 1.05, "%s kick unchanged (ratio %.2f)" % [id, ratio])
	quit(1 if fails > 0 else 0)
