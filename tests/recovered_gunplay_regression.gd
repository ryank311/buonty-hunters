extends SceneTree
const H = preload("res://tools/agent/harness.gd")
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, description: String) -> void:
	print("PASS " if ok else "FAIL ", description)
	if not ok:
		failures.append(description)

func direction(skin: SoldierSkin) -> Vector3:
	var hand: Transform3D = skin.motion.native_worlds[skin.motion.rig.names.find("rhand")]
	return (hand * skin.driver.gunplay.socket).basis.x.normalized()

func _run() -> void:
	var session: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(session)
	await H.scenario(self, "lab_start", {"roster": false, "freeze": true, "pitch": 0.0})
	var player: PrototypePlayer = session.player
	var skin: SoldierSkin = player.soldier.soldier_skin
	var driver: RefCounted = skin.driver
	var gun: RefCounted = driver.gunplay
	await H.step(self, 60) # Let the spawn's brief floor-contact landing finish.
	var length: float = skin.motion.get_animation("seal_stand").length
	var start: float = driver.time
	await H.step(self, 60)
	var advanced: float = fposmod(driver.time - start, length)
	check(absf(advanced - length / 6.0) < 0.002, "Rifle idle uses the source six-second cycle, not the half-second key duration (%.3f s of keys per second)" % advanced)
	await H.step(self, 20, {"hold": ["aim"]})
	check(gun.fire_clip == "seal_fp_stand" and gun.fire_blend > 0.99 and direction(skin).z < -0.98, "Standing aim raises the original fire pose and points the rifle forward")
	var neutral_direction := direction(skin)
	await H.apply(self, {"pitch": 30.0})
	await H.step(self, 15, {"hold": ["aim"]})
	check(direction(skin).y > neutral_direction.y + 0.35 and absf(direction(skin).x) < 0.08, "Aimed pitch lifts the rifle through the native aim node without yawing the torso")
	await H.scenario(self, "lab_start", {"roster": false, "freeze": true, "pitch": 0.0})
	await H.step(self, 5, {"tap": ["fire"]})
	check(player.weapon.shots_fired == 1 and gun.fire_blend > 0.4 and gun.recoil_clip == "seal_recoil" and gun.recoil_weight > 0.05, "An actual unscoped shot raises the rifle and plays its recovered recoil")
	await H.step(self, 15)
	check(gun.recoil_weight == 0.0 and gun.fire_blend > 0.99, "Recoil settles while the weapon remains ready after shooting")
	await H.step(self, 330)
	check(gun.fire_blend == 0.0 and gun.fire_hold == 0.0, "The weapon returns to relaxed idle after the ready hold")
	await H.scenario(self, "lab_start", {"roster": false, "freeze": true, "ammo": 0})
	await H.step(self, 20, {"hold": ["fire"]})
	check(player.weapon.shots_fired == 0 and gun.recoil_weight == 0.0 and gun.fire_hold == 0.0, "A dry trigger does not invent a shot or recoil")
	await H.scenario(self, "lab_start", {"roster": false, "freeze": true, "ammo": 12})
	await H.step(self, 15, {"tap": ["reload"]})
	check(gun.reload_clip == "seal_reload" and gun.reload_blend > 0.99 and player.weapon.ammo == 12, "Standing reload uses the recovered clip without awarding ammo early")
	var progress: float = gun.reload_progress
	await H.step(self, 25, {"forward": 1.0})
	var thigh: int = skin.motion.rig.names.find("rthigh")
	var difference: float = driver.last_pose[thigh].basis.get_rotation_quaternion().angle_to(driver.last_base_pose[thigh].basis.get_rotation_quaternion())
	check(gun.reload_clip == "seal_mv_reload" and gun.reload_progress > progress and difference < 0.002, "Moving mid-reload preserves timer progress and the running legs")
	await H.step(self, 160)
	check(player.weapon.ammo == player.weapon.profile.magazine_size and gun.reload_blend == 0.0, "Reload completion follows the combat timer and blends out")
	await H.scenario(self, "lab_start", {"roster": false, "freeze": true, "weapon": "secondary", "pitch": 0.0})
	await H.step(self, 35, {"forward": 1.0, "hold": ["aim"]})
	difference = driver.last_pose[thigh].basis.get_rotation_quaternion().angle_to(driver.last_base_pose[thigh].basis.get_rotation_quaternion())
	check(gun.fire_clip == "seal_pfp_run" and difference < 0.002, "Partial pistol fire poses retain the native leg cycle")
	await H.step(self, 5, {"tap": ["fire"], "hold": ["aim"]})
	check(gun.recoil_clip == "seal_p_recoil" and gun.recoil_weight > 0.05, "Pistol fire uses the original pistol recoil")
	await H.scenario(self, "lab_start", {"roster": false, "freeze": true, "stance": "prone", "pitch": 0.0})
	await H.step(self, 20, {"hold": ["aim"]})
	await H.step(self, 5, {"tap": ["fire"], "hold": ["aim"]})
	check(gun.fire_clip == "seal_fp_prone" and gun.recoil_clip == "seal_prone_recoil" and skin.motion.native_worlds[0].origin.y < 0.35, "Prone aim and recoil keep the original low body pose")
	await H.scenario(self, "lab_start", {"roster": false, "freeze": true, "ammo": 12})
	await H.step(self, 15, {"tap": ["reload"]})
	await H.step(self, 20, {"tap": ["equip_pistol"]})
	check(gun.reload_blend == 0.0 and gun.recoil_weight == 0.0 and player.weapon.magazines[0] == 12, "Weapon switching cancels the old action layer without transferring ammo")
	print("RESULT: %d failure(s)" % failures.size())
	session.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
