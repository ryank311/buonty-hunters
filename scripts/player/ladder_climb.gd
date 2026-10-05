extends RefCounted
## Climbing a ladder with the original game's clips (animset.rdr "Stand -> Ladder",
## "Climb ladder", "Climb off ladder", "Ladder -> slide", "Ladderslide", "Ladderslide
## land") and its rules, from the local research note 86-traversal.md:
##
##   - At the foot the soldier steps onto the ladder; at the head they back down onto it
##     (the climb-off played in reverse).
##   - On the ladder the stick climbs and descends. The climb cycle is driven by the
##     height covered, never by time, so hands and feet stay on the rungs at any speed
##     and hold still when the stick is let go. There is no turning and no firing.
##   - Climbing off starts where the clip was authored to start: hips 0.88 m under the
##     top floor. The climb between foot and head is divided into whole cycles, each
##     stretched a little from its authored metre, so the last one ends exactly there.
##   - The action button slides down: gravity x 0.8, landing on the ground below.
##
## As in scripts/player/traversal.gd the body is placed, not swept, and follows the
## clips' own root travel. `hips` is the root's world height throughout; the body's
## origin hangs under it, and `root_height` is what the skin shows between the two.

enum Phase { OFF, MOUNT, CLIMB, TOP_OFF, TOP_ON, FOOT_OFF, SLIDE_IN, SLIDE, SLIDE_LAND }

## The hips stand this far in front of the rungs, and start the climb-off this far under
## the top floor: the "refPt" of the climb-off and slide clips, (0.265, 8.824, -5.565)
## source units.
const STANDOFF := 0.5565
const HEAD_BELOW := 0.8824
## The slide clips' root z when the hips are STANDOFF from the rungs.
const SLIDE_PLANE := 0.4985
## How far past the rungs the body is set down on the top floor: the nearest of these
## with room to stand. The original climb-off's 0.86 m of travel ends 0.3 m past them,
## inside the ladder's own collision, and some decks have a lip or a rail post there.
const DECK_STEPS: Array[float] = [0.45, 0.6, 0.8, 1.0]
## Authored rise of one climb cycle, and the stick below which nothing moves.
const CYCLE := 1.0
const DEADZONE := 0.03
const SLIDE_GRAVITY := 0.8
## Seconds over which a soldier is drawn from where they stood onto the clip's path.
const BLEND := 0.25
const TURN_BLEND := 0.45
const FRAME := 1.0 / 30.0

var phase: Phase = Phase.OFF
var active: bool:
	get:
		return phase != Phase.OFF
var ladder: Node3D
## What the skin plays now: the clip, its time, and the root height to show.
var clip := ""
var clip_time := 0.0
var root_height := 0.0
var end_stance := 0
## Rungs passed since the last update, for the sound of them.
var rungs := 0

var clips: Dictionary = {}
var base := Vector3.ZERO
var out := Vector3.BACK
var ground := 0.0
var deck := 0.0
var deck_step := 0.45
## Hip heights between which the climb cycle runs, and the cycles that fit.
var low := 0.0
var high := 0.0
var cycles := 0
var progress := 0.0
var hips := 0.0
var feet := 0.0
var away := 0.0
var time := 0.0
var elapsed := 0.0
var fall := 0.0
var stand_root := 1.178
## Root height of the landing's first pose: the slide ends with the hips this high.
var land_root := 1.144
var from_position := Vector3.ZERO
var from_yaw := 0.0
var blend := BLEND
## Where the top-off began, so a short ladder's climb-off still ends on the floor.
var off_from := 0.0

## Starts climbing `target` from whichever end the body stands at. Returns whether it started.
func begin(body: CharacterBody3D, target: Node3D, motion: Node, pistol: bool) -> bool:
	var end: String = target.end_near(body.global_position, -body.global_basis.z)
	if end == "":
		return false
	ladder = target
	for title: String in ["stand2ladder", "climbladder", "climboffladder", "ladder2slide", "ladderslide", "ladderslide_land"]:
		var full := ("seal_p_" if pistol else "seal_") + title
		clips[title] = full if motion.has_animation(full) else "seal_" + title
	out = ladder.out()
	base = ladder.global_position
	stand_root = _root(motion, "stand2ladder", 0.0).y
	land_root = _root(motion, "ladderslide_land", 0.0).y
	var space := body.get_world_3d().direct_space_state
	# From the head, the ground is the first floor under the rungs' open side. It can lie
	# well above their bottom, which some maps bury in a slope.
	var drop: float = maxf(1.0, ladder.height - ladder.HEAD_ROOM)
	ground = body.global_position.y if end == "foot" else _floor(space, body, base + out * (STANDOFF + 0.5) + Vector3.UP * drop, drop + 1.5, base.y)
	deck_step = DECK_STEPS[0]
	deck = body.global_position.y if end == "head" else _floor(space, body, base - out * deck_step + Vector3.UP * (ladder.height + 1.0), 1.8, base.y + ladder.height)
	low = ground + stand_root + _travel(motion, "stand2ladder").y
	high = deck - HEAD_BELOW
	cycles = roundi((high - low) / CYCLE) if high - low >= 0.3 else 0
	if cycles == 0:
		high = low
	from_position = body.global_position
	from_yaw = body.rotation.y
	elapsed = 0.0
	rungs = 0
	fall = 0.0
	end_stance = 0
	body.velocity = Vector3.ZERO
	if end == "foot":
		phase = Phase.MOUNT
		time = 0.0
		blend = BLEND
	else:
		phase = Phase.TOP_ON
		time = _length(motion, "climboffladder")
		off_from = high
		# Backing onto the ladder means turning round first when the soldier faces it.
		blend = TURN_BLEND if absf(angle_difference(from_yaw, _yaw())) > PI * 0.5 else BLEND
	update(body, motion, 0.0, 0.0)
	return true

func cancel() -> void:
	phase = Phase.OFF
	clip = ""
	ladder = null

func can_slide() -> bool:
	return phase == Phase.CLIMB and hips - ground > land_root + 0.3

## Lets go into the slide. Returns whether it started.
func slide() -> bool:
	if not can_slide():
		return false
	phase = Phase.SLIDE_IN
	time = 0.0
	off_from = hips
	return true

## Finds where on the top floor the soldier can be set down, and returns the stance
## there is room for (stand, else crouch), or -1 when the head of the ladder is blocked.
func room_above(body: CharacterBody3D, stance: StanceController) -> int:
	var space := body.get_world_3d().direct_space_state
	var top: float = base.y + ladder.height
	for step: float in DECK_STEPS:
		var spot := base - out * step
		var floor_height := _floor(space, body, Vector3(spot.x, top + 1.0, spot.z), 1.8, NAN)
		if is_nan(floor_height):
			continue
		for which: int in [0, 1]:
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = stance.shapes[which]
			query.transform = Transform3D(Basis.IDENTITY, Vector3(spot.x, floor_height + 0.05 + StanceController.HEIGHTS[which] * 0.5, spot.z))
			query.collision_mask = body.collision_mask
			query.exclude = [body.get_rid()]
			if space.intersect_shape(query, 1).is_empty():
				deck_step = step
				deck = floor_height
				return which
	return -1

## Advances the climb by one tick with the stick's forward push (-1 to 1), placing the
## body. Returns false once the soldier is off the ladder.
func update(body: CharacterBody3D, motion: Node, stick: float, delta: float, speed: float = 0.759, gravity: float = 23.5, stance: StanceController = null) -> bool:
	elapsed += delta
	rungs = 0
	match phase:
		Phase.MOUNT, Phase.FOOT_OFF:
			var length := _length(motion, "stand2ladder")
			time = minf(time + delta, length) if phase == Phase.MOUNT else maxf(time - delta, 0.0)
			var moved := _moved(motion, "stand2ladder", time)
			away = STANDOFF + _travel(motion, "stand2ladder").z - moved.z
			# The body never sinks under the floor it stands on; the dip stays in the pose.
			feet = ground + maxf(0.0, moved.y)
			root_height = stand_root + minf(0.0, moved.y)
			hips = feet + root_height
			_show("stand2ladder", time)
			if phase == Phase.MOUNT and time >= length:
				phase = Phase.CLIMB
				progress = 0.0
				hips = low
			elif phase == Phase.FOOT_OFF and time <= 0.0:
				phase = Phase.OFF
		Phase.CLIMB:
			var push := stick if absf(stick) >= DEADZONE else 0.0
			if cycles > 0:
				var rise := (high - low) / cycles
				var before := progress
				progress = clampf(progress + push * speed / rise * delta, 0.0, float(cycles))
				# Two rungs a cycle, as the clip's "ladder_rung" callbacks mark them.
				rungs = absi(floori(progress * 2.0) - floori(before * 2.0))
				hips = low + progress * rise
			away = STANDOFF
			root_height = stand_root
			feet = hips - root_height
			# A whole number of cycles shows the cycle's first pose, where the climb-off starts.
			_show("climbladder", fposmod(progress, 1.0) * CYCLE * 16.0 * FRAME)
			if push > 0.0 and progress >= float(cycles):
				var landing := room_above(body, stance) if stance != null else 0
				if landing >= 0:
					end_stance = landing
					phase = Phase.TOP_OFF
					time = 0.0
					off_from = hips
			elif push < 0.0 and progress <= 0.0:
				phase = Phase.FOOT_OFF
				time = _length(motion, "stand2ladder")
		Phase.TOP_OFF, Phase.TOP_ON:
			var length := _length(motion, "climboffladder")
			time = minf(time + delta, length) if phase == Phase.TOP_OFF else maxf(time - delta, 0.0)
			var moved := _moved(motion, "climboffladder", time)
			var whole := _travel(motion, "climboffladder")
			var share := time / length
			away = lerpf(STANDOFF, -deck_step, moved.z / whole.z)
			# The clip's own rise, ending where it was authored to: its last root height
			# over the floor. The body's origin eases from under the hips onto the floor.
			var last := _root(motion, "climboffladder", length).y - _root(motion, "climboffladder", 0.0).y - HEAD_BELOW
			hips = off_from + moved.y / whole.y * (deck + last - off_from)
			feet = lerpf(off_from - stand_root, deck, share)
			root_height = hips - feet
			_show("climboffladder", time)
			if phase == Phase.TOP_OFF and time >= length:
				phase = Phase.OFF
			elif phase == Phase.TOP_ON and time <= 0.0:
				phase = Phase.CLIMB
				progress = float(cycles)
				hips = high
		Phase.SLIDE_IN:
			var length := _length(motion, "ladder2slide")
			time = minf(time + delta, length)
			var root := _root(motion, "ladder2slide", time)
			away = root.z - SLIDE_PLANE
			hips = off_from + root.y - _root(motion, "ladder2slide", 0.0).y
			root_height = stand_root
			feet = hips - root_height
			_show("ladder2slide", time)
			if time >= length:
				phase = Phase.SLIDE
				fall = 0.0
		Phase.SLIDE:
			fall += gravity * SLIDE_GRAVITY * delta
			hips -= fall * delta
			away = move_toward(away, _root(motion, "ladderslide", 0.0).z - SLIDE_PLANE, 1.5 * delta)
			root_height = stand_root
			feet = hips - root_height
			_show("ladderslide", 0.0)
			if hips <= ground + land_root:
				hips = ground + land_root
				feet = hips - root_height
				phase = Phase.SLIDE_LAND
				time = 0.0
		Phase.SLIDE_LAND:
			var length := _length(motion, "ladderslide_land")
			time = minf(time + delta, length)
			var root := _root(motion, "ladderslide_land", time)
			away = move_toward(away, root.z - SLIDE_PLANE, 3.0 * delta)
			feet = move_toward(feet, ground, 2.0 * delta)
			hips = ground + root.y
			root_height = hips - feet
			_show("ladderslide_land", time)
			if time >= length:
				phase = Phase.OFF
	# Drawn from where the soldier stood onto the clip's path, turning to face the rungs.
	var weight := smoothstep(0.0, blend, elapsed)
	var spot := Vector3(base.x + out.x * away, feet, base.z + out.z * away)
	body.global_position = from_position.lerp(spot, weight)
	body.rotation.y = lerp_angle(from_yaw, _yaw(), weight)
	if phase == Phase.OFF:
		clip = ""
	return active

func _show(title: String, seconds: float) -> void:
	clip = clips[title]
	clip_time = seconds

## The yaw that faces into the ladder.
func _yaw() -> float:
	return atan2(out.x, out.z)

## A one-shot's length to its last authored key: the decoder appends the first again.
func _length(motion: Node, title: String) -> float:
	return motion.get_animation(clips[title]).length - FRAME

func _root(motion: Node, title: String, seconds: float) -> Vector3:
	return motion.local_track(clips[title], seconds, "skel_root", Transform3D.IDENTITY).origin

## How far the clip's root has risen (y) and gone forward (z) by `seconds`.
func _moved(motion: Node, title: String, seconds: float) -> Vector3:
	var from := _root(motion, title, 0.0)
	var to := _root(motion, title, seconds)
	return Vector3(0.0, to.y - from.y, from.z - to.z)

func _travel(motion: Node, title: String) -> Vector3:
	return _moved(motion, title, _length(motion, title))

## Height of the floor under `from`, within `reach` below it, or `fallback`.
func _floor(space: PhysicsDirectSpaceState3D, body: CharacterBody3D, from: Vector3, reach: float, fallback: float) -> float:
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * reach, body.collision_mask, [body.get_rid()]))
	return fallback if hit.is_empty() else float(hit.position.y)
