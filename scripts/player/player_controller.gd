class_name PrototypePlayer
extends CharacterBody3D

signal message(text: String)
@export var max_health: float = 100.0
var health: float = 100.0:
	set(value): health = clampf(value, 0.0, max_health)
@export var movement: MovementProfile = preload("res://resources/movement/default_movement.tres")
@export var camera_settings: CameraProfile = preload("res://resources/camera/default_camera.tres")
@onready var collider: CollisionShape3D = $BodyCollision
@onready var camera_rig: PlayerCamera = $CameraRig
@onready var soldier: SoldierProxy = $Soldier
@onready var weapon: PracticeWeapon = $Weapon
@onready var footsteps: AudioStreamPlayer3D = $Footsteps
var stance := StanceController.new()
var controls_enabled: bool = true
var aiming: bool = false
var move_input := Vector2.ZERO
var jump_cooldown: float = 0.0
var step_distance: float = 0.0
var pad_stance_time: float = 0.0
var pad_hold_consumed: bool = false
var stance_was_down: bool = false
var diving: bool = false
var dive_time: float = 0.0
var dive_recovery: float = 0.0
var dive_direction := Vector3.FORWARD
var prone_strafe_phase: float = 0.0
var prone_strafe_amount: float = 0.0
var test_command: Dictionary = {}
var pending_mouse := Vector2.ZERO
var input_armed: bool = true
var local_acceleration := Vector3.ZERO

func _ready() -> void:
	movement = movement.duplicate()
	camera_settings = camera_settings.duplicate()
	stance.apply(collider)
	camera_rig.initialize(self, camera_settings)
	footsteps.stream = preload("res://audio/step.wav")
	weapon.initialize(self)

func _unhandled_input(event: InputEvent) -> void:
	if not controls_enabled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		pending_mouse += event.screen_relative

func turn(amount: float) -> bool:
	if diving:
		return false
	if stance.current == StanceController.Stance.PRONE:
		# Sample the swept angular change so a large mouse event cannot tunnel the long body.
		var steps := maxi(1, ceili(absf(amount) / deg_to_rad(3.0)))
		for index: int in range(1, steps + 1):
			if not stance.has_clearance(self, stance.current, rotation.y + amount * float(index) / steps):
				return false
	rotation.y += amount
	return true

func request_stance(value: int) -> bool:
	if not is_on_floor() or diving or dive_recovery > 0.0:
		return false
	if stance.request(self, collider, value):
		if value == StanceController.Stance.PRONE:
			var slow := Vector2(velocity.x,velocity.z).limit_length(movement.prone_speed)
			velocity.x = slow.x
			velocity.z = slow.y
		return true
	message.emit("Not enough room to change stance")
	return false

func can_fire() -> bool:
	return not diving and dive_recovery <= 0.0

func begin_dive() -> bool:
	if not is_on_floor() or diving or dive_recovery > 0 or stance.current != StanceController.Stance.STAND:
		return false
	if not stance.request(self,collider,StanceController.Stance.PRONE):
		message.emit("Not enough room to dive")
		return false
	diving = true
	dive_time = 0.0
	dive_direction = -global_basis.z
	velocity = dive_direction * movement.dive_speed + Vector3.UP * movement.dive_lift
	# Let gravity and swept CharacterBody motion finish the dive, without floor snap
	# pulling the airborne body down early or a teleport passing through nearby cover.
	floor_snap_length = 0.0
	weapon.reload_remaining = 0.0
	weapon.muzzle_timer = 0.0
	soldier.flash.visible = false
	return true

func _hold_prone() -> void:
	var forward_speed := Vector3(velocity.x,0,velocity.z).dot(-global_basis.z)
	if stance.current == StanceController.Stance.STAND and forward_speed >= movement.run_speed * 0.78:
		begin_dive()
	else:
		request_stance(0 if stance.current == 2 else 2)

func _physics_process(delta: float) -> void:
	if not controls_enabled:
		pending_mouse = Vector2.ZERO
		return
	dive_recovery = maxf(0.0,dive_recovery - delta)
	var yaw_input := -pending_mouse.x * camera_settings.mouse_sensitivity
	camera_rig.add_pitch(pending_mouse.y * camera_settings.mouse_sensitivity)
	pending_mouse = Vector2.ZERO
	var look := PlayerInput.look_vector(camera_settings.pad_deadzone)
	if aiming:
		look *= camera_settings.pad_aim_multiplier
	yaw_input -= look.x * camera_settings.pad_sensitivity * delta
	if stance.current == StanceController.Stance.PRONE:
		yaw_input = clampf(yaw_input,-movement.prone_turn_speed * delta,movement.prone_turn_speed * delta)
	turn(yaw_input)
	camera_rig.add_pitch(look.y * camera_settings.pad_sensitivity * delta)
	move_input = Input.get_vector("move_left", "move_right", "move_forward", "move_back", camera_settings.pad_deadzone)
	if not test_command.is_empty():
		move_input = test_command.get("move", Vector2.ZERO)
	if not input_armed:
		input_armed = true
		for action: String in ["fire", "jump", "crouch", "prone", "pad_stance", "reload", "equip_rifle", "equip_pistol"]:
			input_armed = input_armed and not Input.is_action_pressed(action)
		return
	if Input.is_action_just_pressed("equip_rifle"):
		weapon.equip(0)
	elif Input.is_action_just_pressed("equip_pistol"):
		weapon.equip(1)
	if Input.is_action_just_pressed("prone"):
		request_stance(StanceController.Stance.STAND if stance.current == StanceController.Stance.PRONE else StanceController.Stance.PRONE)
	_stance_input(delta)
	aiming = Input.is_action_pressed("aim")
	var speed := movement.run_speed
	if stance.current == StanceController.Stance.CROUCH:
		speed = movement.crouch_speed
	elif stance.current == StanceController.Stance.PRONE:
		speed = movement.prone_speed
	elif Input.is_action_pressed("walk"):
		speed = movement.walk_speed
	var local_input := move_input.limit_length()
	local_input.x *= movement.strafe_multiplier
	if local_input.y > 0.0:
		local_input.y *= movement.backward_multiplier
	if stance.current == StanceController.Stance.PRONE:
		local_input.x *= 0.65
		if local_input.y > 0:
			local_input.y *= 0.75
	var previous_strafe := prone_strafe_amount
	prone_strafe_amount = move_input.limit_length().x if stance.current == StanceController.Stance.PRONE and is_on_floor() and not diving and dive_recovery <= 0 else 0.0
	if signf(previous_strafe) != signf(prone_strafe_amount):
		prone_strafe_phase = 0.0
	if absf(prone_strafe_amount) > 0.05:
		# An authored reach/pull/settle clock drives both displacement and the pose.
		# This is kinematic movement, not forces, limb simulation, or root-motion drift.
		prone_strafe_phase = fposmod(prone_strafe_phase + delta * absf(prone_strafe_amount) / movement.prone_strafe_seconds, 1.0)
		local_input.x *= SoldierProxy.sample_prone_strafe(prone_strafe_phase).speed
	else:
		prone_strafe_phase = 0.0
	var desired := basis * Vector3(local_input.x, 0, local_input.y) * speed
	var rate := movement.braking if local_input.is_zero_approx() else movement.acceleration
	var before_horizontal := Vector3(velocity.x, 0, velocity.z)
	var horizontal := before_horizontal.move_toward(desired, rate * delta)
	if stance.current == StanceController.Stance.PRONE:
		horizontal = desired
	if diving:
		dive_time += delta
		horizontal = dive_direction * maxf(0.0,movement.dive_speed - dive_time * 0.6)
	elif dive_recovery > 0:
		horizontal = before_horizontal.move_toward(Vector3.ZERO,movement.braking * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	local_acceleration = basis.inverse() * (horizontal - before_horizontal) / delta
	if diving or not is_on_floor():
		velocity.y -= movement.gravity * delta
	else:
		velocity.y = 0.0
	jump_cooldown = maxf(0.0, jump_cooldown - delta)
	if (Input.is_action_just_pressed("jump") or test_command.get("jump", false)) and is_on_floor() and jump_cooldown <= 0.0 and not diving and dive_recovery <= 0:
		if stance.current != StanceController.Stance.STAND:
			request_stance(StanceController.Stance.STAND)
		elif stance.has_clearance(self, 0, rotation.y):
			velocity.y = sqrt(2.0 * movement.gravity * movement.jump_height)
			jump_cooldown = 0.25
	var was_grounded := is_on_floor()
	var impact_speed := -velocity.y
	move_and_slide()
	if not was_grounded and is_on_floor():
		soldier.land(impact_speed, movement.body_weight)
		if diving:
			diving = false
			dive_recovery = movement.dive_recovery_seconds
			velocity.x *= 0.15
			velocity.z *= 0.15
			floor_snap_length = 0.25
		if impact_speed > 3.0:
			PlayerInput.vibrate(camera_settings.vibration * 0.45, 0.10)
	var lean := Input.get_axis("lean_left", "lean_right") if stance.current != StanceController.Stance.PRONE else 0.0
	camera_rig.update_view(self, StanceController.EYE_HEIGHTS[stance.current], lean, aiming, delta)
	var speed_now := Vector2(velocity.x, velocity.z).length()
	var local_velocity := basis.inverse() * Vector3(velocity.x, 0, velocity.z)
	soldier.pose(stance.current, speed_now, Vector2(local_velocity.x, local_velocity.z), camera_rig.aim_pitch(), camera_rig.actual_lean, delta, movement.body_weight, local_acceleration, is_on_floor(), weapon.recoil.visual_kick, weapon.draw_remaining / weapon.profile.draw_seconds, aiming, 1.0 if diving else 0.0, prone_strafe_phase, prone_strafe_amount)
	soldier.set_close_fade(camera_rig.arm.get_hit_length() < 0.70)
	weapon.tick(delta, Input.is_action_pressed("fire"), Input.is_action_just_pressed("reload"))
	if is_on_floor() and speed_now > 0.25 and stance.current != StanceController.Stance.PRONE:
		step_distance += speed_now * delta
		if step_distance > (1.65 if stance.current == 0 else 1.2):
			step_distance = 0.0
			footsteps.pitch_scale = 0.95 + randf() * 0.1
			footsteps.volume_db = -16.0 if stance.current == 0 else -24.0
			if DisplayServer.get_name() != "headless":
				footsteps.play()

func _stance_input(delta: float) -> void:
	var down := Input.is_action_pressed("crouch") or Input.is_action_pressed("pad_stance")
	if down and not stance_was_down:
		pad_stance_time = 0.0
		pad_hold_consumed = false
	if down:
		pad_stance_time += delta
		if pad_stance_time >= 0.35 and not pad_hold_consumed:
			pad_hold_consumed = true
			_hold_prone()
	if not down and stance_was_down and not pad_hold_consumed:
		request_stance(0 if stance.current == 1 else 1)
	stance_was_down = down

func reset_at(spawn_transform: Transform3D) -> void:
	global_transform = spawn_transform
	health = max_health
	velocity = Vector3.ZERO
	stance.current = 0
	stance.apply(collider)
	camera_rig.reset_view()
	weapon.reset()
	jump_cooldown = 0.0
	step_distance = 0.0
	pad_stance_time = 0.0
	pad_hold_consumed = false
	stance_was_down = false
	diving = false
	dive_time = 0.0
	dive_recovery = 0.0
	prone_strafe_phase = 0.0
	prone_strafe_amount = 0.0
	floor_snap_length = 0.25
	input_armed = true
	local_acceleration = Vector3.ZERO
	soldier.reset_pose()
	move_input = Vector2.ZERO
	pending_mouse = Vector2.ZERO
	test_command.clear()
