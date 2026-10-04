extends SceneTree

var failures: Array[String] = []
var checks := 0
var session: Node3D
var player: PrototypePlayer

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

func place(stance: int = 0) -> void:
	player.controls_enabled = true
	player.reset_at(Transform3D(Basis.IDENTITY,Vector3(0,0.1,25)))
	await frames(20)
	player.request_stance(stance)
	await frames(60)

func box_at(point: Vector3, dimensions: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = dimensions
	collision.shape = shape
	body.add_child(collision)
	session.add_child(body)
	body.position = point
	return body

func gait_sample(speed: float) -> Dictionary:
	var soldier := player.soldier
	soldier.reset_pose()
	for i: int in range(120):
		soldier.pose(0,speed,Vector2.UP,0,0,1.0/60.0)
	var low := INF
	var high := -INF
	var lift := 0.0
	var flight := 0
	var grounded_feet := true
	for i: int in range(360):
		soldier.pose(0,speed,Vector2.UP,0,0,1.0/120.0)
		low = minf(low,soldier.pose_points.head.y)
		high = maxf(high,soldier.pose_points.head.y)
		if not soldier.foot_samples.L.contact and not soldier.foot_samples.R.contact:
			flight += 1
		for side: String in ["L","R"]:
			lift = maxf(lift,soldier.foot_samples[side].lift)
			var foot: MeshInstance3D = soldier.parts[side + "Boot"]
			var half: Vector3 = foot.mesh.size * 0.5
			var sole := foot.position.y - absf(foot.basis.x.y)*half.x - absf(foot.basis.y.y)*half.y - absf(foot.basis.z.y)*half.z
			grounded_feet = grounded_feet and sole >= -0.001 and (not soldier.foot_samples[side].contact or absf(sole) < 0.001)
	return {"bounce":high-low,"lift":lift,"flight":flight,"feet":grounded_feet}

func _run() -> void:
	session = load("res://scenes/main.tscn").instantiate()
	root.add_child(session)
	player = session.player
	session.load_level(true)
	await place()
	var rig := player.camera_rig
	var reticle: Control = session.hud.crosshair
	# Real window stretch transforms, not just project-settings string assertions.
	var center_ray := rig.camera.project_ray_normal(Vector2(320,240))
	var corner_ray := rig.camera.project_ray_normal(Vector2(0,0))
	for output: Vector2i in [Vector2i(1024,768),Vector2i(1600,900),Vector2i(1920,1080),Vector2i(2560,1080),Vector2i(800,600),Vector2i(800,1000),Vector2i(3840,2160)]:
		root.size = output
		await frames(3)
		var logical := root.get_visible_rect().size
		var transform := root.get_final_transform()
		var content := Rect2(transform.origin,logical * transform.get_scale())
		check(logical.is_equal_approx(Vector2(640,480)),"%s keeps the full frame at exactly 640x480" % output)
		check(root.get_texture().get_size().is_equal_approx(Vector2(640,480)),"%s keeps the render texture at 640x480 rather than the window resolution" % output)
		check(is_equal_approx(logical.x/logical.y,4.0/3.0) and absf(transform.x.length()-transform.y.length()) < 0.001,"%s preserves 4:3 without stretching" % output)
		var expected_scale := minf(output.x/640.0,output.y/480.0)
		check(content.position.distance_to((Vector2(output)-content.size)*0.5) < 1.0 and content.size.distance_to(Vector2(640,480)*expected_scale) < 1.0,"%s fits the whole image between equal black bars" % output)
		check((reticle.get_global_transform()*reticle.center_ring.position).is_equal_approx(logical*0.5),"%s keeps idle aim at exact viewport center" % output)
		check(center_ray.is_equal_approx(rig.camera.project_ray_normal(Vector2(320,240))) and corner_ray.is_equal_approx(rig.camera.project_ray_normal(Vector2.ZERO)),"%s shows the same world and aim direction" % output)
	root.size = Vector2i(1024,768)
	await frames(10)
	var head := rig.camera.unproject_position(player.soldier.parts.Helmet.global_position)
	check(head.y > 480*0.60 and head.y < 480*0.75 and absf(head.x-320) < 22,"Elevated centered camera frames the soldier below the reticle (%s)" % head)
	# Motion, stance, lean and camera pitch never add a cosmetic reticle offset.
	var stays_centered := true
	for stance: int in [0,1,2]:
		await place(stance)
		player.test_command = {"move":Vector2.RIGHT}
		for pitch: float in [-0.6,0.0,0.7]:
			rig.pitch = pitch
			await frames(12)
			stays_centered = stays_centered and reticle.center_ring.position.is_equal_approx(reticle.size*0.5)
	check(stays_centered,"Looking, running, crouching and prone strafing leave the neutral reticle centered")
	await place()
	player.controls_enabled = false
	player.global_position = Vector3(1000,0,0)
	var wall := box_at(Vector3(1000,10,-25),Vector3(100,100,0.1))
	await frames(3)
	var projection_agrees := true
	for pitch: float in [-0.25,0.0,0.6]:
		rig.pitch = pitch
		rig.set_recoil(Vector2(deg_to_rad(8.0),0.005))
		var projected := rig.camera.unproject_position(rig.camera.global_position + rig.aim_direction()*50)
		var indicated := reticle.get_global_transform()*(reticle.size*0.5 + rig.reticle_offset(reticle.size))
		var result := player.weapon.query_aim()
		projection_agrees = projection_agrees and projected.distance_to(indicated) < 0.01 and not result.is_empty() and rig.camera.unproject_position(result.position).distance_to(indicated) < 0.1
	check(projection_agrees,"Recoil reticle and actual muzzle hitscan agree through different look angles")
	check(rig.reticle_offset(reticle.size).y < -40 and is_zero_approx(rig.reticle_offset(reticle.size).x),"Recoil lifts the aim circle vertically without lateral HUD drift")
	var delta_angle := rig.aim_direction().angle_to(-rig.camera.global_basis.z)
	check(delta_angle > deg_to_rad(4) and delta_angle < deg_to_rad(6),"Camera follows only part of the kick while the remaining climb moves the reticle")
	player.weapon.reset()
	rig.pitch = -0.1
	player.weapon.shoot({})
	await frames(2)
	check(reticle.center_ring.position.y < reticle.size.y*0.5 and player.weapon.recoil.bloom > 0,"A real shot raises the reticle and independently adds spread")
	player.weapon.tick(2.0,false,false)
	await frames(2)
	check(reticle.center_ring.position.is_equal_approx(reticle.size*0.5),"Recoil recovery returns the circle exactly to center")
	player.camera_settings.height_offset = 1.1
	player.camera_settings.shoulder_offset = -0.1
	var config := ConfigFile.new()
	config.parse(session.settings_config().encode_to_text())
	session.reset_tuning()
	session.apply_settings_config(config)
	check(is_equal_approx(player.camera_settings.height_offset,1.1) and is_equal_approx(player.camera_settings.shoulder_offset,-0.1),"New camera framing preferences survive settings serialization")
	session.reset_tuning()
	var legacy := ConfigFile.new()
	legacy.set_value("meta","version",3)
	legacy.set_value("camera","shoulder_offset",0.2)
	legacy.set_value("camera","mouse_sensitivity",0.004)
	session.apply_settings_config(legacy)
	check(is_zero_approx(player.camera_settings.shoulder_offset) and is_equal_approx(player.camera_settings.height_offset,0.85) and is_equal_approx(player.camera_settings.mouse_sensitivity,0.004),"Older presets receive centered elevated framing while keeping look sensitivity")
	session.reset_tuning()
	wall.queue_free()
	await place(1)
	player.global_position = Vector3(-10,0.08,2)
	await frames(30)
	var ceiling := player.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(player.global_position+Vector3.UP*0.95,player.global_position+Vector3.UP*3,1))
	check(not ceiling.is_empty() and rig.global_position.y+0.15 < ceiling.position.y and rig.camera.global_position.y < ceiling.position.y,"Raised camera retracts below the crouch fixture ceiling")
	await place()
	player.controls_enabled = false
	var walk := gait_sample(player.movement.walk_speed)
	var jog := gait_sample(player.movement.run_speed)
	check(jog.bounce > 0.065 and jog.bounce > walk.bounce*1.3,"Jog has a visibly stronger body bounce than walking (%.3f m vs %.3f m)" % [jog.bounce,walk.bounce])
	check(jog.lift > 0.12 and walk.lift < 0.03,"Jog lifts the recovering foot and knee; the walk keeps a low swing")
	check(jog.flight > 0 and walk.flight == 0,"Jog includes flight between push-offs; walking keeps ground contact")
	check(jog.feet and walk.feet,"Walk and jog supporting soles stay planted without floor penetration")
	# Drive actual strafe input over three full authored cycles, not a posed screenshot.
	await place(2)
	var start := player.position
	var slow := INF
	var fast := 0.0
	var reach_hand := 0.0
	var reach_foot := 0.0
	var reach_distance := 0.0
	var limbs := true
	var floor_clear := true
	player.test_command = {"move":Vector2.RIGHT}
	for i: int in range(207):
		await frames()
		slow = minf(slow,player.velocity.x)
		fast = maxf(fast,player.velocity.x)
		if i < 15:
			reach_hand = maxf(reach_hand,player.soldier.arm_joints.R[2].x)
			reach_foot = maxf(reach_foot,player.soldier.leg_joints.R[2].x)
			reach_distance = player.position.x-start.x
		for side: String in ["L","R"]:
			var arm: Array = player.soldier.arm_joints[side]
			var leg: Array = player.soldier.leg_joints[side]
			limbs = limbs and absf(arm[0].distance_to(arm[1])-SoldierProxy.UPPER_ARM_LENGTH) < 0.001 and absf(arm[1].distance_to(arm[2])-SoldierProxy.FOREARM_LENGTH) < 0.001 and absf(leg[0].distance_to(leg[1])-SoldierProxy.THIGH_LENGTH) < 0.001 and absf(leg[1].distance_to(leg[2])-SoldierProxy.SHIN_LENGTH) < 0.001
			floor_clear = floor_clear and arm[1].y > 0.06 and leg[2].y >= 0.109
	var right_distance := player.position.x-start.x
	check(fast > slow*8 and slow < 0.06 and fast > 0.5,"Prone side movement pulses between reaching and pulling (%.3f–%.3f m/s)" % [slow,fast])
	check(reach_hand > 0.40 and reach_foot > 0.36 and reach_distance < 0.025,"Leading hand and leg reach sideways before the body follows (%.3f / %.3f / %.3f m)" % [reach_hand,reach_foot,reach_distance])
	check(absf(right_distance/3.45 - player.movement.prone_speed*0.65*0.95) < 0.015,"Pulsed strafe preserves its slow average travel speed")
	check(limbs and floor_clear,"Prone reaching preserves limb lengths, grounded feet and clear elbows")
	var stopping := player.position
	player.test_command = {}
	await frames(15)
	check(player.position.distance_to(stopping) < 0.005,"Releasing prone strafe stops body travel without a residual slide")
	await place(2)
	player.test_command = {"move":Vector2.LEFT}
	start = player.position
	await frames(207)
	check(absf((start.x-player.position.x)-right_distance) < 0.01,"Left and right strafe travel mirror each other")
	player.test_command = {"move":Vector2.RIGHT}
	var previous: Vector3 = player.soldier.arm_joints.L[2]
	var max_step := 0.0
	for i: int in range(30):
		await frames()
		var current: Vector3 = player.soldier.arm_joints.L[2]
		max_step = maxf(max_step,current.distance_to(previous))
		previous = current
	check(max_step < 0.13,"Reversing a crawl blends the reaching hand back without a pose snap (%.3f m)" % max_step)
	await place(2)
	wall = box_at(Vector3(1,0.5,25),Vector3(0.1,1,4))
	await frames(3)
	player.test_command = {"move":Vector2.RIGHT}
	await frames(240)
	check(player.position.x < 0.63,"Authored crawl movement still respects wall collision")
	wall.queue_free()
	print("\nRESULT: %d checks, %d failure(s)" % [checks,failures.size()])
	session.queue_free()
	await frames(2)
	quit(0 if failures.is_empty() else 1)
