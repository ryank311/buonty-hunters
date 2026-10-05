extends SceneTree

var failures: Array[String] = []
var session: Node3D
var player: PrototypePlayer
var weapon: PracticeWeapon

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, description: String) -> void:
	print("PASS " if condition else "FAIL ", description)
	if not condition:
		failures.append(description)

func frames(count: int = 1) -> void:
	for i: int in range(count):
		await physics_frame
		await process_frame

func button(value: JoyButton, down: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.device = 0
	event.button_index = value
	event.pressed = down
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func tap(value: JoyButton) -> void:
	button(value, true)
	await frames(2)
	button(value, false)
	await frames(2)

func axis(value: JoyAxis, amount: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = 0
	event.axis = value
	event.axis_value = amount
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _run() -> void:
	session = load("res://scenes/main.tscn").instantiate()
	root.add_child(session)
	player = session.player
	weapon = player.weapon
	session.load_level(true)
	await frames(20)
	player.controls_enabled = false
	# Full strides, including sideways travel and backpedaling, never reverse knee bend.
	var knees_valid := true
	var lengths_valid := true
	for stance: int in [0, 1]:
		for direction: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT, Vector2(1,-1).normalized(), Vector2(-1,1).normalized()]:
			for tick: int in range(180):
				player.soldier.pose(stance, 4.5 if stance == 0 else 2.5, direction, 0, 0, 1.0/60.0)
				for joints: Array in player.soldier.leg_joints.values():
					var bend: Vector3 = joints[1] - (joints[0] + joints[2]) * 0.5
					var forward := Basis(Vector3.UP, player.soldier.locomotion_yaw) * Vector3.FORWARD
					knees_valid = knees_valid and bend.dot(forward) >= -0.0001
					lengths_valid = lengths_valid and absf(joints[0].distance_to(joints[1]) - SoldierProxy.THIGH_LENGTH) < 0.001 and absf(joints[1].distance_to(joints[2]) - SoldierProxy.SHIN_LENGTH) < 0.001
	check(knees_valid, "Knees bend toward the feet through all standing/crouched travel directions")
	check(lengths_valid, "Thigh and shin lengths stay constant throughout strides")
	for tick: int in range(180):
		player.soldier.pose(0, 4.5, Vector2.RIGHT, 0, 0, 1.0/60.0)
	check(player.soldier.locomotion_yaw < -1.5 and player.soldier.torso_yaw < -0.9, "Right strafe turns feet, hips and torso toward travel")
	check(absf(player.soldier.weapon_pivot.rotation.y) < 0.001, "Locomotion twist keeps the weapon aligned to aim")
	for tick: int in range(180):
		player.soldier.pose(0, 4.5, Vector2.LEFT, 0, 0, 1.0/60.0)
	check(player.soldier.locomotion_yaw > 1.5 and player.soldier.torso_yaw > 0.9, "Left strafe mirrors the directional turn")
	player.soldier.land(5.0, 1.0)
	player.soldier.pose(0, 0, Vector2.ZERO, 0, 0, 1.0/60.0)
	check(player.soldier.body_drop > 0.005, "Landing loads the body visibly")
	for tick: int in range(180):
		player.soldier.pose(0, 0, Vector2.ZERO, 0, 0, 1.0/60.0)
	check(player.soldier.body_drop < 0.001, "Body settles after landing")
	var neutral_straight := true
	var neutral_flat := true
	for side: String in ["L", "R"]:
		var joints: Array = player.soldier.leg_joints[side]
		var flex := 180.0 - rad_to_deg((joints[0] - joints[1]).angle_to(joints[2] - joints[1]))
		neutral_straight = neutral_straight and flex < 18.0 and flex > 3.0
		neutral_flat = neutral_flat and absf(player.soldier.foot_samples[side].pitch) < 0.001 and absf(player.soldier.foot_samples[side].ankle.y - 0.11) < 0.002
	check(neutral_straight, "Standing knees rest nearly straight instead of in a permanent crouch")
	check(neutral_flat, "Idle boots rest flat with grounded ankles")
	var planted := true
	var low_swing := true
	var controlled_roll := true
	for tick: int in range(240):
		player.soldier.pose(0,1.6,Vector2.UP,0,0,1.0/120.0)
		for side: String in ["L", "R"]:
			var step: Dictionary = player.soldier.foot_samples[side]
			var boot: MeshInstance3D = player.soldier.parts[side + "Boot"]
			var half: Vector3 = boot.mesh.size * 0.5
			var lowest := boot.position.y - absf(boot.basis.x.y)*half.x - absf(boot.basis.y.y)*half.y - absf(boot.basis.z.y)*half.z
			if step.contact:
				planted = planted and absf(lowest) < 0.001
			low_swing = low_swing and step.lift <= 0.046 and lowest >= -0.001
			controlled_roll = controlled_roll and absf(step.pitch) <= deg_to_rad(10.01)
	check(planted, "Supporting boot stays on the floor throughout the planted part of a stride")
	check(low_swing, "Swing clears the floor without high bird-like ankle lift")
	check(controlled_roll, "Heel-to-toe roll stays within a restrained ten degrees")
	# Real controller events pass through InputMap and the gameplay/menu handlers.
	player.reset_at(Transform3D(Basis.IDENTITY, Vector3(0,0.1,25)))
	player.controls_enabled = true
	await frames(15)
	axis(JOY_AXIS_LEFT_Y, -1.0)
	await frames(6)
	check(player.velocity.length() > player.movement.run_speed * 0.3 and player.velocity.length() < player.movement.run_speed * 0.7, "Movement accelerates with weight through the left stick (%.2f m/s after six ticks)" % player.velocity.length())
	await frames(30)
	check(absf(player.velocity.length() - player.movement.run_speed) < 0.02, "Full stick reaches run speed (%.2f m/s)" % player.velocity.length())
	axis(JOY_AXIS_LEFT_Y, 0.0)
	await frames(3)
	check(player.velocity.length() > 1.0, "Releasing movement has a brief controlled stop")
	await frames(20)
	var yaw_before := player.rotation.y
	axis(JOY_AXIS_RIGHT_X, 0.10)
	await frames(10)
	check(is_equal_approx(yaw_before, player.rotation.y), "Right-stick dead zone rejects drift")
	axis(JOY_AXIS_RIGHT_X, 0.7)
	await frames(10)
	check(player.rotation.y < yaw_before - 0.05, "Right stick turns the aim direction")
	axis(JOY_AXIS_RIGHT_X, 0.0)
	axis(JOY_AXIS_TRIGGER_LEFT, 0.8)
	await frames(3)
	check(player.aiming, "Left trigger engages focus aim")
	axis(JOY_AXIS_TRIGGER_LEFT, 0.0)
	await tap(JOY_BUTTON_B)
	check(player.stance.current == 1, "B tap crouches exactly once")
	button(JOY_BUTTON_B, true)
	await frames(25)
	button(JOY_BUTTON_B, false)
	await frames(3)
	check(player.stance.current == 2, "B hold enters prone without a crouch on release")
	await tap(JOY_BUTTON_A)
	check(player.stance.current == 0, "A rises from prone")
	await tap(JOY_BUTTON_A)
	check(not player.is_on_floor(), "A jumps from standing")
	check(player.soldier.jump_active, "A jump drives the airborne animation")
	var highest_boot := 0.0
	var touchdown_boot := 1.0
	var impact_load := 0.0
	for tick: int in range(60):
		await frames()
		if not player.is_on_floor():
			highest_boot = maxf(highest_boot,player.soldier.parts.LBoot.position.y)
			touchdown_boot = player.soldier.parts.LBoot.position.y
		else:
			impact_load = maxf(impact_load,player.soldier.body_drop)
	check(highest_boot > 0.30 and touchdown_boot < 0.13, "Live jump folds the legs then reaches down before ground contact")
	check(impact_load > 0.07 and player.soldier.body_drop < 0.01, "Live touchdown absorbs impact and settles back to ready")
	button(JOY_BUTTON_RIGHT_SHOULDER, true)
	await frames(10)
	check(player.camera_rig.actual_lean > 0.9, "Shoulder button leans")
	button(JOY_BUTTON_RIGHT_SHOULDER, false)
	await tap(JOY_BUTTON_DPAD_RIGHT)
	await frames(20)
	check(weapon.active_slot == 1 and player.soldier.pistol_mesh.visible and not player.soldier.rifle_mesh.visible, "D-pad right equips the visible pistol")
	axis(JOY_AXIS_TRIGGER_RIGHT, 0.8)
	await frames(50)
	check(weapon.ammo == 11, "Held trigger fires the semi-auto pistol only once")
	axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	await frames(3)
	axis(JOY_AXIS_TRIGGER_RIGHT, 0.8)
	await frames(3)
	check(weapon.ammo == 10, "Releasing and pulling the trigger fires the next pistol round")
	axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	await tap(JOY_BUTTON_DPAD_LEFT)
	await frames(25)
	check(weapon.active_slot == 0 and weapon.ammo == 30, "D-pad left restores the rifle and its own magazine")
	await tap(JOY_BUTTON_LEFT_STICK)
	check(weapon.fire_mode() == 3, "L3 changes the recovered rifle from burst to automatic")
	axis(JOY_AXIS_TRIGGER_RIGHT, 0.8)
	await frames(65)
	check(weapon.ammo < 22 and weapon.ammo > 17, "Rifle fires automatically through the right trigger")
	axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	await tap(JOY_BUTTON_X)
	check(weapon.reload_remaining > 0, "X starts the rifle reload")
	var rifle_ammo := weapon.ammo
	var rifle_reserve := weapon.reserve
	await tap(JOY_BUTTON_DPAD_RIGHT)
	check(weapon.reload_remaining == 0 and weapon.ammo == 10, "Swapping cancels reload and preserves pistol ammunition")
	await tap(JOY_BUTTON_DPAD_LEFT)
	check(weapon.ammo == rifle_ammo and weapon.reserve == rifle_reserve, "Interrupted reload transfers no ammunition")
	await frames(25)
	await tap(JOY_BUTTON_X)
	await frames(150)
	check(weapon.ammo == 30 and weapon.reserve == rifle_reserve - (30-rifle_ammo), "Reload transfers only missing rounds from finite reserve")
	await tap(JOY_BUTTON_Y)
	check(not session.lap_running, "Context action button never starts the route timer")
	for down: bool in [true, false, true, false]:
		var timer_key := InputEventKey.new()
		timer_key.physical_keycode = KEY_T
		timer_key.pressed = down
		Input.parse_input_event(timer_key)
		Input.flush_buffered_events()
		await frames(2)
	check(not session.lap_running and session.last_lap > 0, "T still starts and stops the route timer")
	await tap(JOY_BUTTON_RIGHT_STICK)
	check(session.debug_visible, "Right stick click toggles diagnostics")
	var spawn_before: int = session.spawn_index
	await tap(JOY_BUTTON_DPAD_UP)
	check(session.spawn_index != spawn_before, "D-pad up cycles spawn positions")
	weapon.ammo = 0
	await tap(JOY_BUTTON_DPAD_DOWN)
	check(weapon.ammo == 30 and weapon.reserve == 90, "D-pad down resets and refills both weapons")
	# Controller menus must not leak D-pad actions into gameplay.
	await tap(JOY_BUTTON_START)
	check(session.modal and root.gui_get_focus_owner() != null, "Start opens tuning with controller focus")
	spawn_before = session.spawn_index
	await tap(JOY_BUTTON_DPAD_UP)
	await tap(JOY_BUTTON_DPAD_RIGHT)
	check(session.spawn_index == spawn_before and weapon.active_slot == 0, "Menu D-pad does not change spawn or weapon")
	for tick: int in range(3):
		await tap(JOY_BUTTON_RIGHT_SHOULDER)
	check(session.hud.current_page == 3, "RB reaches the rifle recoil page")
	var kick_before: float = weapon.profiles[0].recovered_recoil_scale
	await tap(JOY_BUTTON_DPAD_RIGHT)
	check(weapon.profiles[0].recovered_recoil_scale > kick_before, "D-pad adjusts recovered recoil without a mouse")
	var all_pages_fit := true
	for page: int in range(session.hud.pages.size()):
		session.hud.show_page(page)
		await frames(2)
		all_pages_fit = all_pages_fit and root.get_visible_rect().encloses(session.hud.menu_box.get_global_rect())
	check(all_pages_fit, "All tuning pages fit the viewport")
	# Focus the level button and activate with the pad; no accidental jump on resume.
	session.hud.common_controls[1].grab_focus()
	await tap(JOY_BUTTON_A)
	check(not session.modal and not session.in_lab, "Controller A selects Old Quarter from the menu")
	await frames(20)
	check(player.is_on_floor() and player.velocity.y == 0, "Menu confirm does not leak into a gameplay jump")
	await tap(JOY_BUTTON_START)
	await tap(JOY_BUTTON_B)
	check(not session.modal, "B closes the menu without changing stance")
	# Inventory exhaustion, partial reserve, and recoil math independent of render rate.
	player.controls_enabled = false
	weapon.reset()
	weapon.ammo = 0
	weapon.reserve = 0
	weapon.tick(1, true, true)
	check(weapon.ammo == 0 and weapon.shots_fired == 0 and weapon.reload_remaining == 0, "Exhausted rifle cannot shoot or invent reload ammunition")
	weapon.equip(1)
	weapon.tick(1, false, false)
	weapon.tick(0.02, true, false)
	check(weapon.ammo == 11 and weapon.shots_fired == 1, "Pistol remains available when the rifle is exhausted")
	weapon.ammo = 3
	weapon.reserve = 2
	weapon.tick(0.01, false, true)
	weapon.tick(2.0, false, false)
	check(weapon.ammo == 5 and weapon.reserve == 0, "Partial reserve reload conserves ammunition")
	var profile: WeaponProfile = weapon.profiles[0]
	var state := RecoilState.new()
	state.kick(profile, 1.0)
	check(state.offset.x > 0 and state.bloom > 0 and state.visual_kick > 0, "Shot produces aim climb, spread and visual kick")
	var first_kick := state.offset.x
	state.tick(0.10, profile)
	state.kick(profile, 1.0)
	check(state.offset.x > first_kick * 1.9, "Continuous fire accumulates recoil before recovery")
	for shot: int in range(100):
		state.kick(profile, 1.0)
	check(state.offset.x <= deg_to_rad(profile.max_climb) + 0.00001 and state.bloom <= profile.max_bloom, "Sustained recoil and bloom stay bounded")
	state.tick(3.0, profile)
	check(state.offset.is_zero_approx() and state.bloom == 0, "Releasing fire fully recovers recoil and spread")
	var offsets: Array[Vector2] = []
	for fps: int in [30,60,120]:
		state.reset()
		for shot: int in range(10):
			state.kick(profile, 1.0)
		for tick: int in range(int(fps * 0.3)):
			state.tick(1.0/fps, profile)
		offsets.append(state.offset)
	check(offsets[0].distance_to(offsets[1]) < 0.00001 and offsets[1].distance_to(offsets[2]) < 0.00001, "Recoil recovery agrees at 30, 60 and 120 updates per second")
	weapon.reset()
	var base_pitch := player.camera_rig.pitch
	weapon.shoot({})
	check(is_equal_approx(player.camera_rig.pitch, base_pitch) and is_equal_approx(player.camera_rig.rotation.x, base_pitch) and weapon.accuracy.knock.y < 0, "Recovered recoil lifts the reticle without overwriting look or camera pitch")
	weapon.tick(2.0, false, false)
	check(is_equal_approx(player.camera_rig.rotation.x, base_pitch), "Recoil recovery returns to the player's aim")
	player.stance.current = 0
	player.aiming = false
	var standing := weapon.stability()
	player.stance.current = 2
	player.aiming = true
	check(weapon.stability() < standing * 0.5, "Prone focused fire receives a stability benefit")
	# Settings round-trip through ConfigFile's real serialized representation.
	weapon.profiles[0].vertical_kick = 0.85
	weapon.profiles[1].recovery_speed = 14.0
	player.movement.body_weight = 1.4
	weapon.profiles[0].run_spread = 7.4
	weapon.profiles[1].walk_spread = 1.4
	weapon.profiles[0].recovered_recoil_scale = 1.35
	weapon.profiles[1].recovered_spread_scale = 0.75
	player.movement.prone_speed = 0.3
	var saved: String = session.settings_config().encode_to_text()
	session.reset_tuning()
	var config := ConfigFile.new()
	var parse_error := config.parse(saved)
	session.apply_settings_config(config)
	check(parse_error == OK and is_equal_approx(weapon.profiles[0].vertical_kick, 0.85) and is_equal_approx(weapon.profiles[1].recovery_speed, 14.0) and is_equal_approx(player.movement.body_weight, 1.4), "Per-weapon recoil and body weight survive settings serialization")
	check(is_equal_approx(weapon.profiles[0].run_spread,7.4) and is_equal_approx(weapon.profiles[1].walk_spread,1.4) and is_equal_approx(player.movement.prone_speed,0.3),"Accuracy and crawl tuning survive settings serialization")
	check(is_equal_approx(weapon.profiles[0].recovered_recoil_scale, 1.35) and is_equal_approx(weapon.profiles[1].recovered_spread_scale, 0.75), "Recovered recoil and spread multipliers survive settings serialization")
	session.reset_tuning()
	var legacy := ConfigFile.new()
	legacy.set_value("meta","version",2)
	legacy.set_value("weapon_0","vertical_kick",0.42)
	legacy.set_value("weapon_0","spread_per_shot",0.13)
	legacy.set_value("camera","distance",2.9)
	session.apply_settings_config(legacy)
	check(is_equal_approx(weapon.profiles[0].vertical_kick,0.65) and is_equal_approx(weapon.profiles[0].spread_per_shot,0.35) and is_equal_approx(player.camera_settings.distance,2.9),"Earlier saved presets receive the new firing baseline while preserving camera preferences")
	session.reset_tuning()
	var baseline: MovementProfile = load("res://resources/movement/default_movement.tres")
	check(is_equal_approx(weapon.profiles[0].vertical_kick, 0.65) and is_equal_approx(player.movement.acceleration, baseline.acceleration) and is_equal_approx(player.movement.run_speed, baseline.run_speed), "Restore defaults returns the baseline preset")
	# Speeds saved before the original game's values became the baseline would put the
	# old pace back, so they are not taken; the saved body weight still is.
	var slower := ConfigFile.new()
	slower.set_value("meta","version",5)
	slower.set_value("movement","run_speed",4.5)
	slower.set_value("movement","prone_speed",0.38)
	slower.set_value("movement","body_weight",1.4)
	session.apply_settings_config(slower)
	check(is_equal_approx(player.movement.run_speed, baseline.run_speed) and is_equal_approx(player.movement.prone_speed, baseline.prone_speed) and is_equal_approx(player.movement.body_weight, 1.4), "Speeds saved under the old baseline are dropped (run %.1f m/s)" % player.movement.run_speed)
	session.reset_tuning()
	print("\nRESULT: %d failure(s)" % failures.size())
	session.queue_free()
	await frames(2)
	quit(0 if failures.is_empty() else 1)
