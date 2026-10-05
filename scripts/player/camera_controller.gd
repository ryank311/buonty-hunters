class_name PlayerCamera
extends Node3D

@onready var arm: SpringArm3D = $SpringArm3D
@onready var camera: Camera3D = $SpringArm3D/Camera3D
var profile: CameraProfile
var pitch: float = -0.10
var actual_lean: float = 0.0
var recoil_offset := Vector2.ZERO
# Most of the kick lifts the weapon/reticle within the view; a smaller part lifts
# the camera. The total firing angle stays equal to the weapon's tuned recoil.
const RECOIL_CAMERA_FOLLOW := 0.35
var probe := SphereShape3D.new()
var lean_probe := SphereShape3D.new()

func initialize(body: CharacterBody3D, settings: CameraProfile) -> void:
	profile = settings
	probe.radius = 0.16
	lean_probe.radius = 0.32
	arm.add_excluded_object(body.get_rid())
	arm.spring_length = profile.distance
	reset_view()

func reset_view() -> void:
	pitch = -0.10
	recoil_offset = Vector2.ZERO
	actual_lean = 0.0
	# Start at the eye; update_view safely raises the framing pivot below ceilings.
	position = Vector3(0.0, 1.45, 0.0)
	rotation = Vector3(pitch, 0.0, 0.0)
	camera.rotation = Vector3.ZERO
	if profile:
		arm.spring_length = profile.distance
		camera.fov = profile.field_of_view

func add_pitch(amount: float) -> void:
	pitch = clampf(pitch - amount * (-1.0 if profile.invert_y else 1.0), deg_to_rad(-50.0), deg_to_rad(65.0))

func set_recoil(value: Vector2) -> void:
	recoil_offset = value
	rotation.x = clampf(pitch + recoil_offset.x * RECOIL_CAMERA_FOLLOW, deg_to_rad(-50.0), deg_to_rad(70.0))
	rotation.y = recoil_offset.y

func aim_pitch() -> float:
	return clampf(pitch + recoil_offset.x, deg_to_rad(-50.0), deg_to_rad(70.0))

func aim_basis() -> Basis:
	return camera.global_basis * Basis(Vector3.RIGHT, aim_pitch() - rotation.x)

func aim_direction() -> Vector3:
	return -aim_basis().z

func reticle_offset(view_size: Vector2) -> Vector2:
	# The same projection as the real firing ray, in HUD coordinates. No movement
	# bob or stance animation can displace the neutral screen-center aim point.
	var angle := aim_pitch() - rotation.x
	return Vector2(0.0, -tan(angle) * view_size.y * 0.5 / tan(deg_to_rad(camera.fov * 0.5)))

func update_view(body: CharacterBody3D, eye_height: float, lean: float, aiming: bool, delta: float) -> void:
	var center := body.global_position + Vector3.UP * eye_height
	var space := body.get_world_3d().direct_space_state
	# Sweep upward from the stance eye so the elevated camera cannot start above
	# a low ceiling or see through its underside before the spring arm is cast.
	var height_query := PhysicsShapeQueryParameters3D.new()
	height_query.shape = probe
	height_query.transform = Transform3D(Basis.IDENTITY, center)
	height_query.motion = Vector3.UP * profile.height_offset
	height_query.collision_mask = 1
	height_query.exclude = [body.get_rid()]
	var height_fraction: float = 0.0 if not space.intersect_shape(height_query, 1).is_empty() else space.cast_motion(height_query)[0]
	var safe_height := eye_height + maxf(0.0, profile.height_offset * height_fraction - (0.02 if height_fraction < 1.0 else 0.0))
	center.y = body.global_position.y + safe_height
	var lean_query := PhysicsShapeQueryParameters3D.new()
	lean_query.shape = lean_probe
	lean_query.transform = Transform3D(Basis.IDENTITY, body.global_position + Vector3.UP * eye_height)
	# The recovered step-and-lean reaches farther than the old proxy tilt.
	lean_query.motion = body.global_basis.x * lean * 0.75
	lean_query.collision_mask = 1
	lean_query.exclude = [body.get_rid()]
	var lean_fraction: float = 0.0 if not space.intersect_shape(lean_query, 1).is_empty() else space.cast_motion(lean_query)[0]
	actual_lean = lean * lean_fraction
	var desired := profile.shoulder_offset + actual_lean * 0.25
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = probe
	query.transform = Transform3D(Basis.IDENTITY, center)
	query.motion = body.global_basis.x * desired
	query.collision_mask = 1
	query.exclude = [body.get_rid()]
	var fraction: float = 0.0 if not space.intersect_shape(query, 1).is_empty() else space.cast_motion(query)[0]
	var safe_offset := desired * fraction
	# Retract immediately; ease only when extending into known-clear space.
	if absf(safe_offset) < absf(position.x) or signf(safe_offset) != signf(position.x):
		position.x = safe_offset
	else:
		position.x = lerpf(position.x, safe_offset, 1.0 - exp(-18.0 * delta))
	position.y = minf(position.y, safe_height) if safe_height < position.y else lerpf(position.y, safe_height, 1.0 - exp(-18.0 * delta))
	set_recoil(recoil_offset)
	var target_length := minf(profile.distance, 2.3) if aiming else profile.distance
	arm.spring_length = lerpf(arm.spring_length, target_length, 1.0 - exp(-12.0 * delta))
	camera.fov = lerpf(camera.fov, profile.field_of_view - (10.0 if aiming else 0.0), 1.0 - exp(-12.0 * delta))
