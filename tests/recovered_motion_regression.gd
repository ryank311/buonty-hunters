extends SceneTree
## Guard the visible player against regressions that inspection-only tests miss.
const H = preload("res://tools/agent/harness.gd")
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, description: String) -> void:
	print("PASS " if ok else "FAIL ", description)
	if not ok:
		failures.append(description)

func pose_error(a: Array[Transform3D], b: Array[Transform3D]) -> float:
	var worst := 0.0
	for index: int in range(a.size()):
		worst = maxf(worst, a[index].origin.distance_to(b[index].origin))
		worst = maxf(worst, a[index].basis.get_rotation_quaternion().angle_to(b[index].basis.get_rotation_quaternion()))
	return worst

func _run() -> void:
	var session: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(session)
	await H.scenario(self, "lab_start", {"roster": false, "freeze": true})
	var player: PrototypePlayer = session.player
	var skin: SoldierSkin = player.soldier.soldier_skin
	# Camera pitch previously imposed a guessed hand-axis correction on the torso.
	var run_error := 0.0
	for pitch: float in [-35.0, 0.0, 35.0]:
		await H.apply(self, {"pitch": pitch})
		await H.step(self, 40, {"forward": 1.0})
		var expected: Array[Transform3D] = skin.motion.sample("seal_run", skin.driver.time)
		run_error = maxf(run_error, pose_error(skin.driver.last_pose, expected))
	check(skin.driver.active_clip == "seal_run" and run_error < 0.002, "Player run matches the Lab's native pose at every tested view pitch (error %.6f)" % run_error)
	# Pistol locomotion clips track only spinelo upward; the legs come from the rifle gait.
	await H.scenario(self, "lab_start", {"roster": false, "freeze": true, "weapon": "secondary"})
	await H.step(self, 40, {"forward": 1.0})
	var thigh: int = skin.motion.rig.names.find("rthigh")
	var spine: int = skin.motion.rig.names.find("spinehi")
	var stride := 0.0
	var layer_error := 0.0
	for tick: int in range(20):
		await H.step(self, 1, {"forward": 1.0})
		var legs: Array[Transform3D] = skin.motion.sample("seal_run", skin.driver.base_time)
		var arms: Array[Transform3D] = skin.motion.sample("seal_p_run", skin.driver.time)
		var pose: Array[Transform3D] = skin.driver.last_base_pose
		stride = maxf(stride, pose[thigh].basis.get_rotation_quaternion().angle_to(skin.motion.rig.locals[thigh].basis.get_rotation_quaternion()))
		layer_error = maxf(layer_error, pose_error([pose[thigh], pose[spine]] as Array[Transform3D], [legs[thigh], arms[spine]] as Array[Transform3D]))
	check(skin.driver.active_clip == "seal_p_run" and stride > 0.3 and layer_error < 0.002, "Pistol run layers the pistol upper body over the rifle leg cycle (stride %.3f rad, error %.6f)" % [stride, layer_error])
	await H.scenario(self, "lab_start", {"roster": false, "freeze": true})
	await H.step(self, 1, {"tap": ["jump"]})
	var saw_air := false
	var saw_land := false
	var jump_valid := true
	var previous_time := 0.0
	var peak := player.position.y
	var root_id: int = skin.motion.rig.names.find("skel_root")
	var ground_root: float = skin.motion.sample("seal_jump", 0)[root_id].origin.y
	for tick: int in range(75):
		await H.step(self, 1)
		peak = maxf(peak, player.position.y)
		if not player.is_on_floor():
			saw_air = true
			jump_valid = jump_valid and skin.driver.active_clip == "seal_jump" and skin.driver.time >= previous_time and skin.driver.time < 20.0 / 30.0
			previous_time = skin.driver.time
			if skin.driver.transition >= 1.0:
				jump_valid = jump_valid and absf(skin.driver.last_pose[root_id].origin.y - ground_root) < 0.001
		elif saw_air and skin.driver.active_clip == "seal_land_soft":
			saw_land = true
	check(saw_air and peak > 0.5 and jump_valid, "Jump advances through airborne frames once, without adding source root lift to physics")
	check(saw_land, "A normal jump reaches the recovered landing animation on floor contact")
	await H.step(self, 45)
	check(skin.driver.active_clip == "seal_stand", "Landing finishes and returns to idle without looping")
	await H.scenario(self, "lab_start", {"roster": false, "freeze": true})
	await H.step(self, 40, {"forward": 1.0})
	await H.step(self, 22, {"forward": 1.0, "hold": ["crouch"]})
	var dive_valid := true
	var saw_dive := false
	var saw_low_landing := false
	var dive_error := 0.0
	for tick: int in range(65):
		await H.step(self, 1)
		if skin.driver.active_clip == "seal_dive2prone":
			saw_dive = true
			dive_valid = dive_valid and skin.driver.time <= 15.0 / 30.0 + 0.001
			if skin.driver.transition >= 1.0:
				var expected: Array[Transform3D] = skin.motion.sample("seal_dive2prone", skin.driver.time)
				dive_error = maxf(dive_error, pose_error(skin.driver.last_pose, expected))
			if player.is_on_floor():
				saw_low_landing = skin.motion.native_worlds[root_id].origin.y < 0.3
	check(saw_dive and dive_valid and dive_error < 0.002, "Dive keeps the authored full-body pose and never samples the standing wrap frame (error %.6f)" % dive_error)
	check(saw_low_landing and player.stance.current == 2 and skin.driver.active_clip == "seal_prone", "Dive lands low and transitions into the recovered prone pose")
	print("RESULT: %d failure(s)" % failures.size())
	session.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
