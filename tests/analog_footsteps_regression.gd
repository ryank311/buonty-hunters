extends SceneTree

const H = preload("res://tools/agent/harness.gd")
var failures: Array[String] = []
var session: Node
var player: PrototypePlayer

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, description: String) -> void:
	print("PASS " if ok else "FAIL ", description)
	if not ok:
		failures.append(description)

func frames(count: int) -> void:
	for tick: int in range(count):
		await physics_frame
		await process_frame

func axis(which: JoyAxis, amount: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = 0
	event.axis = which
	event.axis_value = amount
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func stick_click(down: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.device = 0
	event.button_index = JOY_BUTTON_LEFT_STICK
	event.pressed = down
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func place(stance: String = "stand", weapon: String = "primary") -> void:
	axis(JOY_AXIS_LEFT_X, 0.0)
	axis(JOY_AXIS_LEFT_Y, 0.0)
	await H.scenario(self, "lab_start", {"roster": false, "freeze": false, "stance": stance, "weapon": weapon})

func _run() -> void:
	session = load("res://scenes/main.tscn").instantiate()
	root.add_child(session)
	player = session.player
	await place()
	axis(JOY_AXIS_LEFT_Y, -0.1)
	await frames(30)
	check(player.move_input == Vector2.ZERO and player.velocity.length() < 0.01, "Stick drift stays inside the stop deadzone")
	var counts: Array[int] = []
	var volumes: Array[float] = []
	var speeds: Array[float] = []
	for index: int in range(3):
		await place()
		var gait: String = ["walk", "jog", "sprint"][index]
		axis(JOY_AXIS_LEFT_Y, -[0.4, 0.68, 0.9][index])
		await frames(45)
		var speed := Vector2(player.velocity.x, player.velocity.z).length()
		speeds.append(speed)
		var start: int = player.step_audio.steps_played
		var contacts_low := true
		var clips: Dictionary = {}
		for tick: int in range(150):
			var previous: int = player.step_audio.steps_played
			await frames(1)
			if player.step_audio.steps_played != previous:
				var motion: Node = player.soldier.soldier_skin.motion
				var foot: int = motion.rig.names.find(player.step_audio.last_foot)
				contacts_low = contacts_low and motion.native_worlds[foot].origin.y < 0.13
				clips[player.step_audio.last_sound.resource_path] = true
		counts.append(player.step_audio.steps_played - start)
		volumes.append(player.step_audio.last_volume)
		var expected: String = ["seal_walk_alert", "seal_jog_alert", "seal_run"][index]
		check(player.soldier.soldier_skin.driver.active_clip == expected, "%s stick selects recovered %s at %.2f m/s" % [gait, expected, speed])
		check(player.step_audio.last_gait == gait and counts[-1] >= 3 and clips.size() > 1, "%s plays varying %s footfalls (%d contacts)" % [gait, gait, counts[-1]])
		check(contacts_low, "%s sounds occur when the visible boot is close to the floor" % gait)
	check(speeds[0] < speeds[1] and speeds[1] < speeds[2] and absf(speeds[2] - player.movement.run_speed) < 0.02, "Stop → walk → jog → full sprint needs only stick travel")
	check(counts[0] < counts[1] and counts[1] < counts[2], "Footstep cadence rises with each gait: %s" % str(counts))
	check(volumes[0] + 4.0 < volumes[1] and volumes[1] + 4.0 < volumes[2], "Walk, jog and sprint become distinctly louder: %s dB" % str(volumes))
	await place()
	axis(JOY_AXIS_LEFT_Y, -0.9)
	stick_click(true)
	await frames(40)
	check(not Input.is_action_pressed("walk") and absf(player.velocity.length() - player.movement.run_speed) < 0.02, "Holding L3 cannot change or gate full sprint")
	stick_click(false)
	await frames(10)
	check(absf(player.velocity.length() - player.movement.run_speed) < 0.02, "Releasing L3 keeps full sprint")
	axis(JOY_AXIS_LEFT_X, 0.64)
	axis(JOY_AXIS_LEFT_Y, -0.64)
	await frames(40)
	check(absf(player.velocity.length() - player.movement.run_speed) < 0.02, "Diagonal outer stick reaches the same speed cap")
	axis(JOY_AXIS_LEFT_X, 0.0)
	axis(JOY_AXIS_LEFT_Y, -1.0)
	Input.action_press("walk")
	await frames(40)
	check(absf(player.velocity.length() - player.movement.walk_speed) < 0.02, "Keyboard walk action retains its speed limit")
	Input.action_release("walk")
	await place()
	var steps: int = player.step_audio.steps_played
	await frames(60)
	check(player.step_audio.steps_played == steps, "Standing still is silent")
	await place("crouch")
	axis(JOY_AXIS_LEFT_Y, -0.9)
	await frames(120)
	check(player.step_audio.last_gait == "walk" and player.step_audio.last_volume < volumes[0] - 4.0, "Crouch uses quieter walking footfalls")
	await place("prone")
	steps = player.step_audio.steps_played
	axis(JOY_AXIS_LEFT_X, 0.9)
	await frames(60)
	check(player.step_audio.steps_played == steps, "Prone crawling does not emit standing footfalls")
	await place("stand", "secondary")
	axis(JOY_AXIS_LEFT_Y, -0.9)
	await frames(60)
	steps = player.step_audio.steps_played
	await frames(60)
	check(player.step_audio.steps_played > steps and player.step_audio.last_gait == "sprint", "Pistol gait uses its recovered leg contacts too")
	Input.action_press("jump")
	await frames(2)
	Input.action_release("jump")
	steps = player.step_audio.steps_played
	await frames(10)
	check(not player.is_on_floor() and player.step_audio.steps_played == steps, "Airborne motion is silent between takeoff and landing")
	axis(JOY_AXIS_LEFT_X, 0.0)
	axis(JOY_AXIS_LEFT_Y, 0.0)
	print("RESULT: %d failure(s)" % failures.size())
	session.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
