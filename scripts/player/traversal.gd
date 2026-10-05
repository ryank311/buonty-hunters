class_name Traversal
extends RefCounted
## Stepping onto low ledges and climbing higher ones, with the original game's limits
## (dynamics.rdr) and its climb clips (animset.rdr "Climb crate", "Climb medium",
## "Stand -> Hang", "Hang -> Climb").
##
## A climb moves the body along the clip's own root track: its rise is scaled to the
## ledge's height and its forward travel to the distance onto the ledge, so the hands
## meet the edge whatever its height inside the clip's band. The capsule is placed, not
## swept, while climbing; the destination is checked for room before the climb starts.

## Ledge kinds: the clips that play, in order, and the stance the climb ends in.
const CLIMBS := {
	"low": ["climbcrate"],
	"medium": ["climb_medium"],
	"high": ["stand2hang", "hang2climbup"],
}
const REACH := 0.95
const RADIUS := 0.32

var active := false
var kind := ""
var clips: Array[String] = []
var lengths: Array[float] = []
var elapsed := 0.0
var total := 0.0
var start := Vector3.ZERO
var forward := Vector3.FORWARD
var rise := 0.0
var travel := 0.0
var end_stance := 0
## Authored root rise and forward travel of the whole sequence, and the root's height
## at its start, read from the clips.
var authored_rise := 1.0
var authored_travel := 1.0
var root_start := 0.0
## What the skin plays now: the clip, its time, and the root height to show.
var clip := ""
var clip_time := 0.0
var root_height := 0.0

## Lifts the body onto a ledge no higher than step_height that blocks `motion`, and
## returns how far it rose (0 when there was nothing to step onto).
static func step_up(body: CharacterBody3D, motion: Vector3, step_height: float, max_slope: float) -> float:
	motion.y = 0.0
	if motion.length() < 0.0005 or not body.test_move(body.global_transform, motion):
		return 0.0
	var direction := motion.normalized()
	var space := body.get_world_3d().direct_space_state
	var side := direction.cross(Vector3.UP)
	var best := 0.0
	# The ledge's top just ahead of the capsule, under its middle and both sides.
	for offset: float in [0.0, -0.2, 0.2]:
		var top := body.global_position + direction * (RADIUS + 0.12) + side * offset + Vector3.UP * (step_height + 0.05)
		var query := PhysicsRayQueryParameters3D.create(top, top + Vector3.DOWN * (step_height + 0.1), body.collision_mask, [body.get_rid()])
		var hit := space.intersect_ray(query)
		if hit.is_empty() or hit.normal.y < cos(deg_to_rad(max_slope)):
			continue
		var height: float = hit.position.y - body.global_position.y
		if height > 0.01 and height <= step_height:
			best = maxf(best, height)
	if best <= 0.0:
		return 0.0
	var lift := Vector3.UP * (best + 0.01)
	if body.test_move(body.global_transform, lift):
		return 0.0
	var raised := body.global_transform.translated(lift)
	if body.test_move(raised, motion):
		return 0.0
	body.global_position = raised.origin
	return best + 0.01

## The ledge in front of the body that a climb could reach: {height, wall, kind}, or {}.
static func find_ledge(body: CharacterBody3D, movement: MovementProfile) -> Dictionary:
	var space := body.get_world_3d().direct_space_state
	var ahead := -body.global_basis.z
	ahead.y = 0.0
	ahead = ahead.normalized()
	var feet := body.global_position
	# A wall in front, at knee height, within reach.
	var knee := feet + Vector3.UP * (movement.step_height * 0.5 + 0.1)
	var wall := space.intersect_ray(PhysicsRayQueryParameters3D.create(knee, knee + ahead * REACH, body.collision_mask, [body.get_rid()]))
	if wall.is_empty() or absf(wall.normal.y) > 0.5:
		return {}
	var distance: float = (wall.position - knee).dot(ahead)
	# Up the face to its first opening, so a roof or overhang above the ledge is never
	# taken for the ledge itself.
	var opening := -1.0
	var height := movement.step_height * 0.5 + 0.2
	while height <= movement.high_climb_height + 0.2:
		var at := feet + Vector3.UP * height
		if space.intersect_ray(PhysicsRayQueryParameters3D.create(at, at + ahead * (distance + 0.35), body.collision_mask, [body.get_rid()])).is_empty():
			opening = height
			break
		height += 0.1
	if opening < 0.0:
		return {}
	# The ledge's top, a little past the face, just under the opening.
	var over := feet + ahead * (distance + 0.18) + Vector3.UP * (opening + 0.05)
	var top := space.intersect_ray(PhysicsRayQueryParameters3D.create(over, Vector3(over.x, feet.y + movement.step_height * 0.5, over.z), body.collision_mask, [body.get_rid()]))
	if top.is_empty() or top.normal.y < cos(deg_to_rad(movement.max_slope_degrees)):
		return {}
	height = top.position.y - feet.y
	if height <= movement.step_height or height > movement.high_climb_height:
		return {}
	var kind := "low" if height <= movement.low_climb_height else "medium" if height <= movement.medium_climb_height else "high"
	return {"height": height, "distance": distance, "forward": ahead, "kind": kind}

## Starts climbing the ledge if there is room on top; returns whether it started.
func begin(body: CharacterBody3D, stance: StanceController, motion: Node, ledge: Dictionary, pistol: bool) -> bool:
	var destination: Vector3 = body.global_position + ledge.forward * (ledge.distance + RADIUS + 0.2) + Vector3.UP * (ledge.height + 0.02)
	var stand_room := _room(body, stance, 0, destination)
	if not stand_room and not _room(body, stance, 1, destination):
		return false
	kind = ledge.kind
	clips.clear()
	lengths.clear()
	for name: String in CLIMBS[kind]:
		var full := ("seal_p_" if pistol else "seal_") + name
		clips.append(full if motion.has_animation(full) else "seal_" + name)
		# The decoder appends the first frame at the end; stop on the last authored one.
		lengths.append(motion.get_animation(clips.back()).length - 1.0 / 30.0)
	total = 0.0
	for length: float in lengths:
		total += length
	var first := _root(motion, 0, 0.0)
	var last := _root(motion, clips.size() - 1, lengths.back())
	root_start = first.y
	authored_rise = _offset(motion, clips.size() - 1, lengths.back()).y
	authored_travel = maxf(0.1, _offset(motion, clips.size() - 1, lengths.back()).z)
	start = body.global_position
	forward = ledge.forward as Vector3
	rise = destination.y - start.y
	travel = Vector2(destination.x - start.x, destination.z - start.z).length()
	end_stance = 0 if stand_room else 1
	body.velocity = Vector3.ZERO
	body.look_at(body.global_position + forward, Vector3.UP)
	elapsed = 0.0
	active = true
	_pose(motion)
	return true

## Advances the climb, placing the body; returns false once it has finished.
func update(body: CharacterBody3D, motion: Node, delta: float) -> bool:
	elapsed = minf(elapsed + delta, total)
	var offset := _pose(motion)
	var up := offset.y / authored_rise * rise
	# The body never sinks below the floor it climbs from; the dip stays in the pose.
	body.global_position = start + forward * (offset.z / authored_travel * travel) + Vector3.UP * maxf(0.0, up)
	root_height = root_start + minf(0.0, up)
	if elapsed >= total:
		active = false
		clip = ""
	return active

## Sets the clip and time the skin shows and returns the sequence's root offset so far:
## y up from the start, z forward.
func _pose(motion: Node) -> Vector3:
	var remaining := elapsed
	var index := 0
	while index < clips.size() - 1 and remaining > lengths[index]:
		remaining -= lengths[index]
		index += 1
	clip = clips[index]
	clip_time = minf(remaining, lengths[index])
	return _offset(motion, index, clip_time)

func _offset(motion: Node, index: int, seconds: float) -> Vector3:
	# Each clip's root continues from where the previous clip's ended.
	var result := Vector3.ZERO
	for previous: int in range(index):
		var a := _root(motion, previous, 0.0)
		var b := _root(motion, previous, lengths[previous])
		result += Vector3(0, b.y - a.y, a.z - b.z)
	var from := _root(motion, index, 0.0)
	var to := _root(motion, index, seconds)
	return result + Vector3(0, to.y - from.y, from.z - to.z)

func _root(motion: Node, index: int, seconds: float) -> Vector3:
	return motion.local_track(clips[index], seconds, "skel_root", Transform3D.IDENTITY).origin

func _room(body: CharacterBody3D, stance: StanceController, which: int, position: Vector3) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = stance.shapes[which]
	query.transform = Transform3D(Basis.IDENTITY, position + Vector3.UP * (StanceController.HEIGHTS[which] * 0.5 + 0.03))
	query.collision_mask = body.collision_mask
	query.exclude = [body.get_rid()]
	return body.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()
