class_name StanceController
extends RefCounted

enum Stance { STAND, CROUCH, PRONE }
const HEIGHTS: Array[float] = [1.8, 1.15, 0.55]
const EYE_HEIGHTS: Array[float] = [1.45, 0.95, 0.45]
const NAMES: Array[String] = ["STANDING", "CROUCHED", "PRONE"]
## A body lying down rests on its ground, so ground is no obstacle to lying on it. This
## much of it may rise into the body's space: a slope's own rise, a kerb, a stair's edge.
const GROUND_ALLOWANCE := 0.2
## Where the ground is sampled along a lying body, from its feet (+z) to its head (-z),
## and how far either side of its middle.
const LYING_SAMPLES: Array[float] = [0.8, 0.4, 0.0, -0.4, -0.8]
const LYING_HALF_WIDTH := 0.25
const STEEPEST_LIE := 40.0
## Upright, the feet find their own footing. The room test starts this far up, so that a
## slope or a kerb under the soldier is not taken for something in the way.
const FOOTING := 0.3
var current: int = Stance.STAND
var shapes: Array[Shape3D] = []
## The room a lying body needs above the ground allowance, and a standing or crouching
## one above its footing.
var lying := BoxShape3D.new()
var upright: Array[CapsuleShape3D] = []

func _init() -> void:
	for height: float in [1.8, 1.15]:
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.32
		capsule.height = height
		shapes.append(capsule)
		var room := CapsuleShape3D.new()
		room.radius = capsule.radius
		room.height = height - FOOTING
		upright.append(room)
	var prone_shape := BoxShape3D.new()
	prone_shape.size = Vector3(0.65, 0.55, 1.8)
	shapes.append(prone_shape)
	lying.size = Vector3(prone_shape.size.x, prone_shape.size.y - GROUND_ALLOWANCE, prone_shape.size.z)

## How a body lying at `yaw` rests on its ground, in the body's own frame: tilted to the
## slope along and across it, and lifted to the line of the ground. The ground is sampled
## from feet to head and a line fitted through it. Ground that keeps to that line within
## the allowance is something to lie on, whether level, sloped, or stepped. Ground that
## does not (a crate at the head, a drop at the feet) is taken as level, and whatever
## stands up from it is left for the room test to find.
func lie(body: CharacterBody3D, yaw: float) -> Transform3D:
	var space := body.get_world_3d().direct_space_state
	var facing := Basis(Vector3.UP, yaw)
	var origin := body.global_position
	# Heights along the body relative to its origin. The origin itself is not taken as
	# ground: a level box propped on a slope holds the body's middle off the surface.
	var along: Array[float] = []
	var heights: Array[float] = []
	for offset: float in LYING_SAMPLES:
		var height: float = _ground(space, body, origin + facing * Vector3(0.0, 0.0, offset))
		if not is_nan(height):
			along.append(offset)
			heights.append(height - origin.y)
	if along.size() < 3:
		return Transform3D.IDENTITY
	# Least squares: height = lift + slope x offset.
	var count := float(along.size())
	var sum_along := 0.0
	var sum_height := 0.0
	var sum_square := 0.0
	var sum_product := 0.0
	for index: int in range(along.size()):
		sum_along += along[index]
		sum_height += heights[index]
		sum_square += along[index] * along[index]
		sum_product += along[index] * heights[index]
	var spread := count * sum_square - sum_along * sum_along
	var slope := (count * sum_product - sum_along * sum_height) / spread if spread > 0.01 else 0.0
	var lift := (sum_height - slope * sum_along) / count
	var fits := absf(rad_to_deg(atan(slope))) <= STEEPEST_LIE
	for index: int in range(along.size()):
		fits = fits and absf(heights[index] - (lift + slope * along[index])) <= GROUND_ALLOWANCE
	if not fits:
		return Transform3D.IDENTITY
	# Level ground is exactly level: a floor's contact margin is not a slope or a lift.
	if absf(slope) < 0.005:
		slope = 0.0
	if absf(lift) < 0.01:
		lift = 0.0
	# Across the body, from a hand's breadth either side of its middle.
	var left: float = _ground(space, body, origin + facing * Vector3(-LYING_HALF_WIDTH, 0.0, 0.0))
	var right: float = _ground(space, body, origin + facing * Vector3(LYING_HALF_WIDTH, 0.0, 0.0))
	var lean := 0.0
	if not is_nan(left) and not is_nan(right) and absf(left - origin.y - lift) <= GROUND_ALLOWANCE and absf(right - origin.y - lift) <= GROUND_ALLOWANCE:
		lean = atan((right - left) / (LYING_HALF_WIDTH * 2.0))
		if absf(lean) < 0.005:
			lean = 0.0
	# The head is at -z, so ground that rises toward the head pitches the body up; ground
	# that rises to the right rolls it up on that side.
	return Transform3D(Basis(Vector3.RIGHT, atan(-slope)) * Basis(Vector3.BACK, lean), Vector3.UP * lift)

# Height of the ground under a point near the body, or NAN where there is none in reach.
func _ground(space: PhysicsDirectSpaceState3D, body: CharacterBody3D, point: Vector3) -> float:
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.9, point + Vector3.DOWN * 1.0, 1, [body.get_rid()]))
	return NAN if hit.is_empty() else float(hit.position.y)

## Tilts the prone box to the ground the body rests on. `resting` is lie(), eased. Only
## the tilt is taken: the box then meets the surface along its whole length, and the
## body comes down onto it by its own weight.
func rest(collider: CollisionShape3D, resting: Transform3D) -> void:
	if current == Stance.PRONE:
		collider.transform = Transform3D(resting.basis, resting.basis * Vector3.UP * HEIGHTS[current] * 0.5)

func has_clearance(body: CharacterBody3D, stance: int, yaw: float) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	if stance != Stance.PRONE:
		query.shape = upright[stance]
		query.transform = Transform3D(Basis(Vector3.UP, yaw), body.global_position + Vector3.UP * (FOOTING + upright[stance].height * 0.5 + 0.025))
	else:
		# The room above the allowance, along the ground the body would rest on.
		query.shape = lying
		query.transform = Transform3D(Basis(Vector3.UP, yaw), body.global_position) * lie(body, yaw) * Transform3D(Basis.IDENTITY, Vector3.UP * (GROUND_ALLOWANCE + lying.size.y * 0.5 + 0.025))
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
	collider.transform = Transform3D(Basis.IDENTITY, Vector3.UP * HEIGHTS[current] * 0.5)
