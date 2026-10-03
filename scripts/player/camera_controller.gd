class_name PlayerCamera
extends Node3D

@onready var arm: SpringArm3D = $SpringArm3D
@onready var camera: Camera3D = $SpringArm3D/Camera3D
var profile: CameraProfile
var pitch: float = -0.10
var actual_lean: float = 0.0
var recoil_offset := Vector2.ZERO
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
	rotation.x = clampf(pitch + recoil_offset.x, deg_to_rad(-50.0), deg_to_rad(70.0))
	rotation.y = recoil_offset.y

func update_view(body: CharacterBody3D, eye_height: float, lean: float, aiming: bool, delta: float) -> void:
	var center := body.global_position + Vector3.UP * eye_height
	var space := body.get_world_3d().direct_space_state
	var lean_query := PhysicsShapeQueryParameters3D.new()
	lean_query.shape = lean_probe
	lean_query.transform = Transform3D(Basis.IDENTITY, center)
	lean_query.motion = body.global_basis.x * lean * 0.20
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
	position.y = minf(position.y, eye_height) if eye_height < position.y else lerpf(position.y, eye_height, 1.0 - exp(-18.0 * delta))
	set_recoil(recoil_offset)
	var target_length := minf(profile.distance, 2.3) if aiming else profile.distance
	arm.spring_length = lerpf(arm.spring_length, target_length, 1.0 - exp(-12.0 * delta))
	camera.fov = lerpf(camera.fov, profile.field_of_view - (10.0 if aiming else 0.0), 1.0 - exp(-12.0 * delta))
