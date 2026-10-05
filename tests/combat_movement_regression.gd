extends SceneTree

var failures: Array[String] = []
var checks := 0
var session: Node3D
var player: PrototypePlayer
var weapon: PracticeWeapon

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, description: String) -> void:
	checks += 1
	print("PASS " if condition else "FAIL ",description)
	if not condition:
		failures.append(description)

func frames(count: int = 1) -> void:
	for i: int in range(count):
		await physics_frame
		await process_frame

func key(code: Key, down: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = down
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func button(code: JoyButton, down: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.device = 0
	event.button_index = code
	event.pressed = down
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func place() -> void:
	player.controls_enabled = true
	player.reset_at(Transform3D(Basis.IDENTITY,Vector3(0,0.1,25)))
	await frames(15)

func box_at(point: Vector3, dimensions: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = dimensions
	body.add_child(shape)
	session.add_child(body)
	body.global_position = point
	return body

func pattern(speed: float, bloom: float, center: Vector3) -> Dictionary:
	player.velocity = Vector3(0,0,-speed)
	weapon.accuracy.knock = Vector2.ZERO
	for i: int in range(120):
		weapon.accuracy.tick(1.0 / 60.0, player.velocity, Vector2.ZERO, false, false, 0)
	weapon.accuracy.size = minf(weapon.accuracy.size + bloom, weapon.accuracy.table().TargetMax)
	weapon.rng.seed = 73483
	player.camera_rig.camera.look_at(center,Vector3.UP)
	var hits := 0
	var square_sum := 0.0
	for shot: int in range(800):
		var result := weapon.query_aim(true)
		if result.is_empty():
			return {"hits": -1,"rms": -1.0}
		var offset: Vector3 = result.position - center
		square_sum += Vector2(offset.x,offset.y).length_squared()
		if absf(offset.x) < 0.25 and absf(offset.y) < 0.55:
			hits += 1
	return {"hits": hits,"rms": sqrt(square_sum / 800.0)}

func _run() -> void:
	session = load("res://scenes/main.tscn").instantiate()
	root.add_child(session)
	session.load_level(true)
	player = session.player
	weapon = player.weapon
	await frames(20)
	player.controls_enabled = false
	player.aiming = false
	player.stance.current = 0
	weapon.reset()
	player.velocity = Vector3.ZERO
	var standing := weapon.spread_degrees()
	player.velocity.z = -player.movement.walk_speed
	weapon.tick(2.0, false, false)
	var walking := weapon.spread_degrees()
	player.velocity.z = -player.movement.run_speed
	weapon.tick(2.0, false, false)
	var running := weapon.spread_degrees()
	for i: int in range(4):
		weapon.cooldown = 0
		weapon.shoot({})
	var burst := weapon.spread_degrees()
	check(standing < walking and walking < running and is_equal_approx(running, burst),"Movement widens the native spread; running fire respects the same source cap")
	check(is_equal_approx(weapon.accuracy.size, 26),"Full-speed running reaches the recovered M4 26px maximum")
	player.velocity = Vector3.ZERO
	var standing_burst := weapon.spread_degrees()
	player.stance.current = 1
	var crouching := weapon.spread_degrees()
	player.stance.current = 2
	var prone := weapon.spread_degrees()
	check(prone < crouching and crouching < standing_burst,"Crouching and prone reduce the entire shot cone, including existing shot bloom")
	var kicks: Array[float] = []
	for stance: int in [0,1,2]:
		weapon.reset()
		player.stance.current = stance
		weapon.shoot({})
		kicks.append(-weapon.accuracy.knock.y)
	check(kicks[2] < kicks[1] and kicks[1] < kicks[0],"Stance progressively reduces upward aim kick")
	weapon.reset()
	player.stance.current = 0
	var before: Vector3 = -player.camera_rig.camera.global_basis.z
	weapon.shoot({})
	check((-player.camera_rig.camera.global_basis.z).is_equal_approx(before),"Unscoped recovered recoil leaves the camera still")
	check(weapon.accuracy.size > weapon.accuracy.table().TargetMin,"A shot adds native spread independently of reticle climb")
	weapon.tick(2.0,false,false)
	check(weapon.accuracy.size == weapon.accuracy.table().TargetMin and weapon.accuracy.knock.is_zero_approx(),"Releasing fire recovers both spread and recoil")
	# Real Jolt camera/muzzle rays against a large wall, aimed at a human-sized rectangle.
	player.reset_at(Transform3D(Basis.IDENTITY,Vector3(1000,0.05,0)))
	player.soldier.pose(0,0,Vector2.ZERO,0,0,1.0)
	var center := Vector3(1000,1.3,-25)
	var wall := box_at(center,Vector3(60,60,0.1))
	await frames(2)
	var idle_pattern := pattern(0,0,center)
	var walk_pattern := pattern(player.movement.walk_speed,0,center)
	var run_pattern := pattern(player.movement.run_speed,0,center)
	var burst_pattern := pattern(0,25,center)
	check(idle_pattern.rms > 0 and idle_pattern.rms < walk_pattern.rms and walk_pattern.rms < run_pattern.rms and is_equal_approx(run_pattern.rms, burst_pattern.rms),"Actual native impact patterns widen with motion and bloom up to the same cap")
	check(idle_pattern.hits > 720 and run_pattern.hits < idle_pattern.hits * 0.65,"At 25 m the native running square reduces hits on a 0.5 × 1.1 m target (%d / 800 vs idle %d)" % [run_pattern.hits,idle_pattern.hits])
	wall.queue_free()
	# Reticle components use independent transforms. Recoil never scales the center disc.
	var reticle: Control = session.hud.crosshair
	for i: int in range(90):
		reticle.update_reticle(0.25,60,1.0/60.0,false,false,false)
	var radius: float = reticle.circle_radius
	var resting_distance: float = reticle.mark_distance
	var ring_center: Vector2 = reticle.center_ring.position
	reticle.update_reticle(9.0,60,1.0/60.0,false,false,false)
	check(reticle.spread_marks.size() == 4 and reticle.center_ring.get_parent() == reticle,"Center disc and four cardinal marks are separate UI nodes")
	check(reticle.center_texture.get_size() == Vector2(64, 64) and reticle.arm_texture.get_size() == Vector2(32, 32),"Rifle reticle uses the recovered 64px disc and 32px arm sprites")
	check(reticle.mark_distance > resting_distance + 10 and reticle.circle_radius == radius and reticle.center_ring.position == ring_center,"Spread pushes the four marks outward while the circle stays fixed")
	var symmetric := true
	for index: int in range(4):
		symmetric = symmetric and reticle.spread_marks[index].position.is_equal_approx(ring_center + reticle.DIRECTIONS[index] * reticle.mark_distance * reticle.pixel_scale)
	check(symmetric,"All four spread marks remain symmetric on the cardinal axes")
	var expanded: float = reticle.mark_distance
	reticle.update_reticle(0.25,60,1.0/60.0,false,false,false)
	check(reticle.mark_distance < expanded and reticle.mark_distance > resting_distance,"Marks animate inward without snapping back")
	for i: int in range(90):
		reticle.update_reticle(0.25,60,1.0/60.0,false,false,false)
	check(absf(reticle.mark_distance-resting_distance) < 0.01,"Reticle settles back around the same center circle")
	reticle.update_reticle(1.0,60,0.1,false,false,true)
	check(not reticle.visible,"Reticle hides while tuning is open")
	# Keyboard and gamepad share tap/hold semantics; a walk does not accidentally dive.
	await place()
	key(KEY_C,true)
	await frames(5)
	check(player.stance.current == 0,"C press waits to distinguish tap from hold")
	key(KEY_C,false)
	await frames(2)
	check(player.stance.current == 1,"C tap crouches once on release")
	await place()
	key(KEY_C,true)
	await frames(25)
	check(player.stance.current == 2 and not player.diving,"Holding C at rest enters prone")
	key(KEY_C,false)
	await frames(3)
	check(player.stance.current == 2,"Releasing a completed hold does not toggle out of prone")
	player.test_command = {"move":Vector2.UP}
	await frames(30)
	var start := player.position
	var min_ankle: float = player.soldier.leg_joints.L[2].z
	var max_ankle := min_ankle
	for i: int in range(60):
		await frames(1)
		min_ankle = minf(min_ankle,player.soldier.leg_joints.L[2].z)
		max_ankle = maxf(max_ankle,player.soldier.leg_joints.L[2].z)
	var crawled := player.position.distance_to(start)
	check(crawled > player.movement.prone_speed * 0.9 and crawled < player.movement.prone_speed * 1.05,"Prone movement is a crawl at its set speed (%.2f m in a second at %.2f m/s)" % [crawled, player.movement.prone_speed])
	check(max_ankle-min_ankle > 0.09 and player.soldier.parts.Head.position.y < 0.5,"Crawl visibly shimmies the legs with the body lying flat")
	player.test_command = {}
	await place()
	key(KEY_SHIFT,true)
	player.test_command = {"move":Vector2.UP}
	await frames(30)
	button(JOY_BUTTON_B,true)
	await frames(25)
	check(player.stance.current == 2 and not player.diving,"Walking plus a controller hold lowers into prone without a dive")
	button(JOY_BUTTON_B,false)
	key(KEY_SHIFT,false)
	player.test_command = {}
	await frames(3)
	# Run + hold through launch, flight, landing and recovery, with real collision motion.
	await place()
	player.test_command = {"move":Vector2.UP}
	await frames(40)
	button(JOY_BUTTON_B,true)
	var saw_flight := false
	var saw_landing := false
	var locked_fire := true
	var launch := Vector3.ZERO
	var landing := Vector3.ZERO
	var peak := 0.0
	var extended := false
	for i: int in range(100):
		await frames(1)
		if player.diving:
			if not saw_flight:
				launch = player.position
			saw_flight = true
			peak = maxf(peak,player.position.y)
			var ammo := weapon.ammo
			weapon.cooldown = 0
			weapon.shoot({})
			locked_fire = locked_fire and weapon.ammo == ammo
			extended = extended or (player.soldier.dive_blend > 0.8 and player.soldier.arm_joints.R[2].z < -0.7)
		if saw_flight and not player.diving and not saw_landing:
			landing = player.position
			saw_landing = true
			check(player.is_on_floor() and player.stance.current == 2 and player.dive_recovery > 0,"Dive lands in prone with a short recovery")
			locked_fire = locked_fire and not player.can_fire()
			player.test_command = {}
	button(JOY_BUTTON_B,false)
	await frames(3)
	check(saw_flight and saw_landing and peak > 0.15,"Running plus controller hold launches an airborne forward dive")
	# The recovered dive clip itself travels 2.98 m.
	check(landing.distance_to(launch) > 2.4 and landing.distance_to(launch) < 3.8,"Dive travels forward under physics before landing (%.2f m)" % landing.distance_to(launch))
	check(extended,"Dive stretches the arms forward into the airborne pose")
	check(locked_fire and player.can_fire(),"Firing is blocked in flight/recovery and restored after settling")
	check(player.stance.current == 2 and not player.diving,"Holding through landing never retriggers a dive or stands the player up")
	# A strafe dive leaves sideways with the carried momentum, pushes faster, and keeps the aim.
	await place()
	player.test_command = {"move":Vector2.RIGHT}
	await frames(40)
	var carried := Vector2(player.velocity.x,player.velocity.z).length()
	button(JOY_BUTTON_B,true)
	var side_launch := Vector3.ZERO
	var side_landing := Vector3.ZERO
	var fastest := 0.0
	var banked := false
	for i: int in range(100):
		await frames(1)
		if player.diving:
			if side_launch == Vector3.ZERO:
				side_launch = player.position
			fastest = maxf(fastest,Vector2(player.velocity.x,player.velocity.z).length())
			banked = banked or player.soldier.basis.x.y < -0.3
		elif side_launch != Vector3.ZERO and side_landing == Vector3.ZERO:
			side_landing = player.position
			player.test_command = {}
	button(JOY_BUTTON_B,false)
	await frames(3)
	var side_travel := side_landing - side_launch
	check(side_landing != Vector3.ZERO and side_travel.x > 1.3 and absf(side_travel.z) < 0.15 and absf(player.rotation.y) < 0.001,"Strafing plus a hold dives sideways while the body keeps facing the aim (%.2f m)" % side_travel.x)
	check(fastest > carried * 1.2,"The dive pushes past the strafe speed it carried in (%.2f -> %.2f m/s)" % [carried,fastest])
	check(banked and player.stance.current == 2,"A side dive banks the body into its travel and lands prone")
	await place()
	player.test_command = {"move":Vector2.DOWN}
	await frames(40)
	button(JOY_BUTTON_B,true)
	await frames(25)
	button(JOY_BUTTON_B,false)
	player.test_command = {}
	check(player.stance.current == 2 and not player.diving and player.dive_recovery == 0,"Backpedaling plus a hold lowers into prone instead of diving backward")
	await frames(3)
	# A thin wall must stop the dive; nearby space must be checked before committing.
	await place()
	var blocker := box_at(Vector3(0,1.5,23.5),Vector3(5,3,0.2))
	await frames(2)
	check(player.begin_dive(),"Dive begins with clear prone space beside a wall")
	await frames(65)
	check(player.position.z >= 24.48 and player.is_on_floor() and not player.diving,"Swept dive collision stops at a thin wall without tunnelling")
	blocker.queue_free()
	await frames(2)
	await place()
	blocker = box_at(Vector3(0,0.25,24.35),Vector3(2,0.5,0.1))
	await frames(2)
	check(not player.begin_dive() and player.stance.current == 0,"Insufficient body clearance rejects a dive before changing stance")
	blocker.queue_free()
	await frames(2)
	await place()
	player.begin_dive()
	await frames(3)
	session.reset_player()
	check(not player.diving and player.dive_recovery == 0 and player.floor_snap_length > 0 and player.soldier.dive_blend == 0,"Reset cancels flight/recovery and restores a standing pose")
	# Different walking and running contact timing, with anatomical dive limbs.
	player.controls_enabled = false
	var soldier := player.soldier
	for i: int in range(120):
		soldier.pose(0,1.6,Vector2.UP,0,0,1.0/60.0)
	var walk_cycle := soldier.cycle
	for i: int in range(60):
		soldier.pose(0,1.6,Vector2.UP,0,0,1.0/60.0)
	var walk_cadence := soldier.cycle - walk_cycle
	check(soldier.stride_contact > 0.5,"Walking keeps at least one boot planted through the step cycle")
	for i: int in range(120):
		soldier.pose(0,4.5,Vector2.UP,0,0,1.0/60.0)
	var run_cycle := soldier.cycle
	for i: int in range(60):
		soldier.pose(0,4.5,Vector2.UP,0,0,1.0/60.0)
	check(soldier.cycle - run_cycle > walk_cadence * 1.2 and soldier.stride_contact < 0.4,"Running has a distinct quicker cadence and shorter ground contact")
	var limbs := true
	for i: int in range(60):
		soldier.pose(2,5.6,Vector2.UP,0,0,1.0/60.0,1.0,Vector3.ZERO,false,0,0,false,1.0)
		for joints: Array in soldier.arm_joints.values():
			limbs = limbs and absf(joints[0].distance_to(joints[1])-SoldierProxy.UPPER_ARM_LENGTH) < 0.001 and absf(joints[1].distance_to(joints[2])-SoldierProxy.FOREARM_LENGTH) < 0.001
	check(limbs,"Dive extension preserves arm lengths instead of stretching the mesh")
	print("\nRESULT: %d checks, %d failure(s)" % [checks,failures.size()])
	session.queue_free()
	await frames(2)
	quit(0 if failures.is_empty() else 1)
