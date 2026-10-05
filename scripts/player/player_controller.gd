class_name PrototypePlayer
extends CharacterBody3D

const RecoveredProne = preload("res://scripts/actors/recovered_prone.gd")
const FootstepAudio = preload("res://scripts/player/footstep_audio.gd")

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
## How the body rests on its ground: tilted to the slope when lying prone, eased over time.
var resting := Transform3D.IDENTITY
var controls_enabled: bool = true
var aiming: bool = false
var move_input := Vector2.ZERO
var jump_cooldown: float = 0.0
var step_audio: RefCounted
var pad_stance_time: float = 0.0
var pad_hold_consumed: bool = false
var stance_was_down: bool = false
var diving: bool = false
var dive_time: float = 0.0
var dive_recovery: float = 0.0
var dive_direction := Vector3.FORWARD
var dive_carry: float = 0.0
var dive_launch: float = 0.0
var prone_strafe_phase: float = 0.0
var prone_strafe_amount: float = 0.0
var test_command: Dictionary = {}
var pending_mouse := Vector2.ZERO
var input_armed: bool = true
var local_acceleration := Vector3.ZERO
var look_scale: float = 1.0 # Below one while a scope is zoomed in, so aim speed tracks the magnification.
var traversal := Traversal.new()
var interactions: Node
## Height still to ease out of the soldier after stepping onto a ledge.
var step_offset: float = 0.0

func _ready() -> void:
	movement = movement.duplicate()
	camera_settings = camera_settings.duplicate()
	stance.apply(collider)
	camera_rig.initialize(self, camera_settings)
	weapon.initialize(self)
	interactions = preload("res://scripts/player/context_actions.gd").new()
	interactions.player = self
	add_child(interactions)

func try_climb() -> bool:
	if not controls_enabled or not is_on_floor() or traversal.active or diving or dive_recovery > 0.0 or stance.current == StanceController.Stance.PRONE:
		return false
	var ledge := Traversal.find_ledge(self, movement)
	if ledge.is_empty() or not traversal.begin(self, stance, soldier.soldier_skin.motion, ledge, soldier.weapon_slot == 1):
		return false
	_climb(0.0)
	return true

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
	# Dive along the travel direction (forward, sideways or diagonal), keeping the
	# speed carried into it and pushing past it off the planted foot.
	var travel := Vector3(velocity.x,0,velocity.z)
	dive_direction = travel.normalized() if travel.length() > 0.5 else -global_basis.z
	dive_carry = travel.length()
	dive_launch = maxf(movement.dive_speed,dive_carry * movement.dive_boost)
	velocity = dive_direction * dive_carry + Vector3.UP * movement.dive_lift
	# Let gravity and swept CharacterBody motion finish the dive, without floor snap
	# pulling the airborne body down early or a teleport passing through nearby cover.
	floor_snap_length = 0.0
	weapon.reload_remaining = 0.0
	weapon.muzzle_timer = 0.0
	soldier.flash.visible = false
	return true

func _hold_prone() -> void:
	var travel := Vector3(velocity.x,0,velocity.z)
	var backward := travel.dot(global_basis.z)
	# Running or strafing dives; backpedaling and walking lower into prone instead.
	if stance.current == StanceController.Stance.STAND and travel.length() >= movement.run_speed * 0.78 and backward < travel.length() * 0.3:
		begin_dive()
	else:
		request_stance(0 if stance.current == 2 else 2)

func _physics_process(delta: float) -> void:
	if not controls_enabled:
		pending_mouse = Vector2.ZERO
		return
	dive_recovery = maxf(0.0,dive_recovery - delta)
	var yaw_input := -pending_mouse.x * camera_settings.mouse_sensitivity * look_scale
	camera_rig.add_pitch(pending_mouse.y * camera_settings.mouse_sensitivity * look_scale)
	pending_mouse = Vector2.ZERO
	var look := PlayerInput.look_vector(camera_settings.pad_deadzone) * look_scale
	if aiming:
		look *= camera_settings.pad_aim_multiplier
	yaw_input -= look.x * camera_settings.pad_sensitivity * delta
	if stance.current == StanceController.Stance.PRONE:
		yaw_input = clampf(yaw_input,-movement.prone_turn_speed * delta,movement.prone_turn_speed * delta)
	turn(yaw_input)
	camera_rig.add_pitch(look.y * camera_settings.pad_sensitivity * delta)
	move_input = PlayerInput.move_vector(camera_settings.pad_deadzone)
	if not test_command.is_empty():
		move_input = test_command.get("move", Vector2.ZERO)
	if not input_armed:
		input_armed = true
		for action: String in ["fire", "fire_mode", "jump", "crouch", "prone", "pad_stance", "reload", "equip_rifle", "equip_pistol"]:
			input_armed = input_armed and not Input.is_action_pressed(action)
		return
	if traversal.active:
		_climb(delta)
		return
	# Modified number shortcuts must not also change the equipped weapon.
	if Input.is_action_just_pressed("equip_rifle", true):
		weapon.equip(0)
	elif Input.is_action_just_pressed("equip_pistol", true):
		weapon.equip(1)
	if Input.is_action_just_pressed("prone"):
		request_stance(StanceController.Stance.STAND if stance.current == StanceController.Stance.PRONE else StanceController.Stance.PRONE)
	_stance_input(delta)
	aiming = Input.is_action_pressed("aim")
	var speed := movement.run_speed
	var strafe := movement.strafe_multiplier
	var backward := movement.backward_multiplier
	if stance.current == StanceController.Stance.CROUCH:
		speed = movement.crouch_speed
		strafe = movement.crouch_strafe_multiplier
		backward = movement.crouch_backward_multiplier
	elif stance.current == StanceController.Stance.PRONE:
		speed = movement.prone_speed
		strafe = movement.prone_strafe_multiplier
		backward = movement.prone_backward_multiplier
	elif Input.is_action_pressed("walk"):
		speed = movement.walk_speed
	var local_input := move_input.limit_length()
	local_input.x *= strafe
	if local_input.y > 0.0:
		local_input.y *= backward
	var previous_strafe := prone_strafe_amount
	var sideways := absf(move_input.x) > absf(move_input.y) * 1.4
	prone_strafe_amount = move_input.limit_length().x if sideways and stance.current == StanceController.Stance.PRONE and is_on_floor() and not diving and dive_recovery <= 0 else 0.0
	if signf(previous_strafe) != signf(prone_strafe_amount):
		prone_strafe_phase = 0.0
	if absf(prone_strafe_amount) > 0.05:
		# Travel per authored cycle sets the cadence, just as for the other native
		# gaits. The pull curve distributes that travel without feeding pulsed
		# velocity back into the clock that produced it.
		var distance := RecoveredProne.cycle_distance(soldier.soldier_skin.motion, prone_strafe_amount)
		var next_phase := prone_strafe_phase + delta * absf(local_input.x) * speed / distance
		local_input.x *= RecoveredProne.speed_scale(soldier.soldier_skin.motion, prone_strafe_amount, prone_strafe_phase, next_phase)
		prone_strafe_phase = fposmod(next_phase, 1.0)
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
		var push := lerpf(dive_carry,dive_launch,smoothstep(0.0,0.12,dive_time))
		horizontal = dive_direction * maxf(0.0,push - dive_time * 0.6)
	elif dive_recovery > 0:
		# A short belly skid bleeds off the landing speed.
		horizontal = before_horizontal.move_toward(Vector3.ZERO,9.0 * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	local_acceleration = basis.inverse() * (horizontal - before_horizontal) / delta
	if diving or not is_on_floor():
		velocity.y -= movement.gravity * delta
	else:
		velocity.y = 0.0
	jump_cooldown = maxf(0.0, jump_cooldown - delta)
	if (Input.is_action_just_pressed("jump") or test_command.get("jump", false)) and is_on_floor() and jump_cooldown <= 0.0 and not diving and dive_recovery <= 0:
		# The jump button climbs the ledge in front, unless standing and the jump
		# itself clears it: then a hop is quicker than the crate climb.
		var ledge := Traversal.find_ledge(self, movement) if stance.current == StanceController.Stance.STAND else {}
		var hop: bool = not ledge.is_empty() and ledge.height <= movement.jump_height - 0.1
		if not hop and try_climb():
			return
		if stance.current != StanceController.Stance.STAND:
			request_stance(StanceController.Stance.STAND)
		elif stance.has_clearance(self, 0, rotation.y):
			# Launch speed for the apex under per-tick integration, which adds half a
			# tick of rise to the continuous v²/2g.
			var half_step := movement.gravity * delta * 0.5
			velocity.y = sqrt(half_step * half_step + 2.0 * movement.gravity * movement.jump_height) - half_step
			soldier.begin_jump(velocity.y)
			jump_cooldown = 0.25
	var was_grounded := is_on_floor()
	var impact_speed := -velocity.y
	floor_max_angle = deg_to_rad(movement.max_slope_degrees)
	if was_grounded and not diving and stance.current != StanceController.Stance.PRONE:
		# Walk up kerbs, steps and low ledges; the soldier and camera ease up after the body.
		var lifted := Traversal.step_up(self, Vector3(velocity.x, 0.0, velocity.z) * delta, movement.step_height, movement.max_slope_degrees)
		if lifted > 0.0:
			step_offset += lifted
			camera_rig.position.y -= lifted
	step_offset *= exp(-14.0 * delta)
	soldier.position.y = -step_offset
	move_and_slide()
	if not was_grounded and is_on_floor():
		soldier.land(impact_speed, movement.body_weight)
		if diving:
			diving = false
			dive_recovery = movement.dive_recovery_seconds
			velocity.x *= 0.35
			velocity.z *= 0.35
			floor_snap_length = 0.25
		if impact_speed > 3.0:
			PlayerInput.vibrate(camera_settings.vibration * 0.45, 0.10)
	var lean := Input.get_axis("lean_left", "lean_right")
	camera_rig.update_view(self, StanceController.EYE_HEIGHTS[stance.current], lean, aiming, delta)
	# Lying down, the soldier and the prone box lie along the surface under them, at its
	# angle. A dive stays level until it lands.
	var lying := stance.current == StanceController.Stance.PRONE and not diving
	resting = resting.interpolate_with(stance.lie(self, rotation.y) if lying else Transform3D.IDENTITY, 1.0 - exp(-10.0 * delta))
	stance.rest(collider, resting)
	soldier.ground = resting
	var speed_now := Vector2(velocity.x, velocity.z).length()
	var local_velocity := basis.inverse() * Vector3(velocity.x, 0, velocity.z)
	# The weapon stays on aim: a body tilted up a slope raises it that much less.
	soldier.pose(stance.current, speed_now, Vector2(local_velocity.x, local_velocity.z), camera_rig.aim_pitch() - asin(clampf((resting.basis * Vector3.FORWARD).y, -1.0, 1.0)), camera_rig.actual_lean, delta, movement.body_weight, local_acceleration, is_on_floor(), weapon.recoil.visual_kick, weapon.draw_remaining / weapon.profile.draw_seconds, aiming, 1.0 if diving else 0.0, prone_strafe_phase, prone_strafe_amount, clampf((movement.dive_lift - velocity.y) / (2.0 * movement.dive_lift),0.0,1.0), velocity.y)
	soldier.set_close_fade(camera_rig.arm.get_hit_length() < 0.70)
	weapon.tick(delta, Input.is_action_pressed("fire"), Input.is_action_just_pressed("reload"))
	if step_audio == null:
		step_audio = FootstepAudio.new()
	step_audio.update(soldier.soldier_skin, footsteps, speed_now, movement.run_speed, stance.current, is_on_floor(), delta)

## One tick of a climb: the body follows the clip's root and the skin plays it.
func _climb(delta: float) -> void:
	var going := traversal.update(self, soldier.soldier_skin.motion, delta)
	soldier.traversal_clip = traversal.clip if going else ""
	soldier.traversal_time = traversal.clip_time
	soldier.traversal_root = traversal.root_height
	velocity = Vector3.ZERO
	if not going:
		if stance.current != traversal.end_stance:
			stance.current = traversal.end_stance
			stance.apply(collider)
		apply_floor_snap()
	camera_rig.update_view(self, StanceController.EYE_HEIGHTS[stance.current], 0.0, false, delta)
	soldier.pose(stance.current, 0.0, Vector2.ZERO, camera_rig.aim_pitch(), 0.0, delta, movement.body_weight, Vector3.ZERO, true)
	weapon.tick(delta, false, false)

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
	resting = Transform3D.IDENTITY
	soldier.ground = resting
	health = max_health
	velocity = Vector3.ZERO
	stance.current = 0
	stance.apply(collider)
	camera_rig.reset_view()
	weapon.reset()
	jump_cooldown = 0.0
	if step_audio != null:
		step_audio.reset()
	pad_stance_time = 0.0
	pad_hold_consumed = false
	stance_was_down = false
	diving = false
	dive_time = 0.0
	dive_recovery = 0.0
	dive_carry = 0.0
	dive_launch = 0.0
	prone_strafe_phase = 0.0
	prone_strafe_amount = 0.0
	floor_snap_length = 0.25
	traversal.active = false
	soldier.traversal_clip = ""
	step_offset = 0.0
	soldier.position.y = 0.0
	input_armed = true
	local_acceleration = Vector3.ZERO
	soldier.reset_pose()
	move_input = Vector2.ZERO
	pending_mouse = Vector2.ZERO
	test_command.clear()
