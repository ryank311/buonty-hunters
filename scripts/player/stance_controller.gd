class_name StanceController
extends RefCounted

enum Stance { STAND, CROUCH, PRONE }
const HEIGHTS: Array[float] = [1.8, 1.15, 0.55]
const EYE_HEIGHTS: Array[float] = [1.45, 0.95, 0.45]
const NAMES: Array[String] = ["STANDING", "CROUCHED", "PRONE"]
var current: int = Stance.STAND
var shapes: Array[Shape3D] = []

func _init() -> void:
	for height: float in [1.8, 1.15]:
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.32
		capsule.height = height
		shapes.append(capsule)
	var prone_shape := BoxShape3D.new()
	prone_shape.size = Vector3(0.65, 0.55, 1.8)
	shapes.append(prone_shape)

func shape_transform(body: CharacterBody3D, stance: int, yaw: float) -> Transform3D:
	# A small floor clearance keeps resting contact out of overlap queries.
	return Transform3D(Basis(Vector3.UP, yaw), body.global_position + Vector3.UP * (HEIGHTS[stance] * 0.5 + 0.025))

func has_clearance(body: CharacterBody3D, stance: int, yaw: float) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shapes[stance]
	query.transform = shape_transform(body, stance, yaw)
	query.collision_mask = 1
	query.exclude = [body.get_rid()]
	return body.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func request(body: CharacterBody3D, collider: CollisionShape3D, stance: int) -> bool:
	if stance == current:
		return true
	if not has_clearance(body, stance, body.rotation.y):
		return false
	current = stance
	apply(collider)
	return true

func apply(collider: CollisionShape3D) -> void:
	collider.shape = shapes[current]
	collider.position.y = HEIGHTS[current] * 0.5
