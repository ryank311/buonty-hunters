extends Node
## The live link's memory: what the player did over the last minute of play, and what the
## engine printed. An agent told "walking feels slow" reads this to see what was felt.
##
## Samples are taken every physics tick while the game is being played; time in the menu
## or frozen is not recorded, so "the last ten seconds" always means ten seconds of play.

const SECONDS := 60.0
const TICKS := 60
const CAPACITY := 3600
const MAX_LOG := 400
const MAX_EVENTS := 200
# One sample: play clock, position, horizontal and vertical speed, yaw and pitch
# (degrees), stance, move input (x right, y back), flag bits, shots, hits, health, slot.
enum { T, X, Y, Z, SPEED, RISE, YAW, PITCH, STANCE, INPUT_X, INPUT_Y, FLAGS, SHOTS, HITS, HEALTH, SLOT, WIDTH }
const ON_FLOOR := 1
const AIMING := 2
const DIVING := 4
const WALK_HELD := 8
const FIRE_HELD := 16
const STANCES: Array[String] = ["stand", "crouch", "prone"]
const MOVING := 0.25

## Receives everything the engine logs. It can be called from any thread.
class Capture extends Logger:
	var lock := Mutex.new()
	var entries: Array[Dictionary] = []
	var sequence: int = 0

	func _log_message(message: String, error: bool) -> void:
		_keep("error" if error else "print", message.strip_edges(), "", 0)

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, script_backtraces: Array) -> void:
		var kind: String = ["error", "warning", "script error", "shader error"][clampi(error_type, 0, 3)]
		# push_error and friends report the engine source line; the script frame is the useful one.
		if not file.begins_with("res://") and not file.begins_with("user://") and not file.begins_with("gdscript://"):
			for trace: Variant in script_backtraces:
				if trace != null and trace.get_frame_count() > 0:
					file = trace.get_frame_file(0)
					line = trace.get_frame_line(0)
					function = trace.get_frame_function(0)
					break
		_keep(kind, rationale if rationale != "" else code, file, line, function)

	func _keep(kind: String, text: String, file: String, line: int, function: String = "") -> void:
		if text == "":
			return
		lock.lock()
		sequence += 1
		var entry: Dictionary = {"seq": sequence, "at": Time.get_ticks_msec(), "kind": kind, "text": text}
		if file != "":
			entry["where"] = "%s:%d" % [file, line] if line > 0 else file
			if function != "":
				entry["in"] = function
		entries.append(entry)
		if entries.size() > MAX_LOG:
			entries = entries.slice(entries.size() - MAX_LOG)
		lock.unlock()

var capture := Capture.new()
var samples: Array[PackedFloat32Array] = []
var head: int = 0
var clock: float = 0.0
var last_sample_at: int = 0
var events: Array[Dictionary] = []
var previous := PackedFloat32Array()
var level_key: String = ""
var notice_text: String = ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# After the player has moved, so a sample is the tick that was just played.
	process_physics_priority = 1000
	OS.add_logger(capture)

func _exit_tree() -> void:
	OS.remove_logger(capture)

func session() -> Node:
	for node: Node in get_tree().root.get_children():
		if node.has_method("load_level") and node.get("player") != null:
			return node
	return null

## Adds a line to the timeline: something the agent did, to read beside what the player did.
func note(text: String) -> void:
	events.append({"t": clock, "event": text})
	if events.size() > MAX_EVENTS:
		events = events.slice(events.size() - MAX_EVENTS)

func playing() -> bool:
	var s := session()
	return s != null and not get_tree().paused and not s.get("modal") and s.player.get("controls_enabled") == true

func _physics_process(delta: float) -> void:
	if not playing():
		return
	var s := session()
	var p: Node3D = s.player
	var stance: Variant = p.get("stance")
	var rig: Variant = p.get("camera_rig")
	var weapon: Variant = p.get("weapon")
	if stance == null or rig == null or weapon == null:
		return
	clock += delta
	last_sample_at = Time.get_ticks_msec()
	var velocity: Vector3 = p.velocity
	var move: Vector2 = p.get("move_input") if p.get("move_input") is Vector2 else Vector2.ZERO
	var flags := 0
	if p.is_on_floor():
		flags |= ON_FLOOR
	if p.get("aiming") == true:
		flags |= AIMING
	if p.get("diving") == true:
		flags |= DIVING
	if InputMap.has_action("walk") and Input.is_action_pressed("walk"):
		flags |= WALK_HELD
	if InputMap.has_action("fire") and Input.is_action_pressed("fire"):
		flags |= FIRE_HELD
	var sample := PackedFloat32Array()
	sample.resize(WIDTH)
	sample[T] = clock
	sample[X] = p.global_position.x
	sample[Y] = p.global_position.y
	sample[Z] = p.global_position.z
	sample[SPEED] = Vector2(velocity.x, velocity.z).length()
	sample[RISE] = velocity.y
	sample[YAW] = rad_to_deg(p.rotation.y)
	sample[PITCH] = rad_to_deg(_value(rig, "pitch"))
	sample[STANCE] = _value(stance, "current")
	sample[INPUT_X] = move.x
	sample[INPUT_Y] = move.y
	sample[FLAGS] = flags
	sample[SHOTS] = _value(weapon, "shots_fired")
	sample[HITS] = _value(weapon, "hits")
	sample[HEALTH] = _value(p, "health")
	sample[SLOT] = _value(weapon, "active_slot")
	_spot_events(s, sample)
	if samples.size() < CAPACITY:
		samples.append(sample)
	else:
		samples[head] = sample
		head = (head + 1) % CAPACITY
	previous = sample

# A number from the game by name, so a renamed member costs a zero, not an error every tick.
static func _value(object: Object, key: String) -> float:
	var found: Variant = object.get(key)
	return float(found) if found is float or found is int else 0.0

func _spot_events(s: Node, now: PackedFloat32Array) -> void:
	var level := str(s.get("current_level"))
	if level != level_key:
		if level_key != "":
			note("level: %s" % level)
		level_key = level
	var notice: Variant = s.hud.get("notice_label") if s.get("hud") != null else null
	if notice is Label and notice.text != notice_text:
		notice_text = notice.text
		if notice_text != "" and not notice_text.begins_with("AI"):
			note("notice: %s" % notice_text)
	if previous.is_empty():
		return
	var was := previous
	if now[STANCE] != was[STANCE]:
		note(STANCES[clampi(int(now[STANCE]), 0, 2)])
	var flags := int(now[FLAGS])
	var before := int(was[FLAGS])
	if flags & DIVING and not before & DIVING:
		note("dive at %.1f m/s" % was[SPEED])
	elif before & ON_FLOOR and not flags & ON_FLOOR and now[RISE] > 0.5:
		note("jump")
	if flags & ON_FLOOR and not before & ON_FLOOR:
		note("land at %.1f m/s down" % -was[RISE])
	if now[SLOT] != was[SLOT]:
		note("weapon slot %d" % int(now[SLOT]))
	if now[HEALTH] < was[HEALTH]:
		note("hurt %.0f, health %.0f" % [was[HEALTH] - now[HEALTH], now[HEALTH]])
	if Vector3(now[X] - was[X], now[Y] - was[Y], now[Z] - was[Z]).length() > 2.0:
		note("moved to %.1f, %.1f, %.1f" % [now[X], now[Y], now[Z]])
	if flags & FIRE_HELD and not before & FIRE_HELD:
		note("trigger down")

## The samples of the last `seconds` of play, oldest first.
func window(seconds: float) -> Array[PackedFloat32Array]:
	var ordered: Array[PackedFloat32Array] = []
	for index: int in range(samples.size()):
		var sample := samples[(head + index) % samples.size()]
		if sample[T] > clock - seconds:
			ordered.append(sample)
	return ordered

## A digest of the last `seconds` of play. `rows` above zero adds that many evenly spaced
## raw samples.
func summary(seconds: float, rows: int = 0) -> Dictionary:
	seconds = clampf(seconds, 1.0, SECONDS)
	var recent := window(seconds)
	var idle := (Time.get_ticks_msec() - last_sample_at) / 1000.0
	if recent.size() < 2:
		return {"note": "No play has been recorded yet. The recorder runs while the game is being played, not in the menu or frozen.", "playing_now": playing()}
	var states: Dictionary = {}
	var distance := 0.0
	var top := 0.0
	var turn := 0.0
	var aimed := 0.0
	var shots := 0.0
	var hits := 0.0
	var lowest_health: float = recent[0][HEALTH]
	var starts: Array = []
	var stops: Array = []
	var jumps: Array = []
	var start_at := -1
	var stop_at := -1
	var air_at := -1
	for index: int in range(recent.size()):
		var now := recent[index]
		var flags := int(now[FLAGS])
		var label := _state(now)
		var state: Dictionary = states.get_or_add(label, {"ticks": 0, "sum": 0.0, "max": 0.0})
		state.ticks += 1
		state.sum += now[SPEED]
		state.max = maxf(state.max, now[SPEED])
		top = maxf(top, now[SPEED])
		lowest_health = minf(lowest_health, now[HEALTH])
		if flags & AIMING:
			aimed += 1.0 / TICKS
		if index == 0:
			continue
		var was := recent[index - 1]
		var before := int(was[FLAGS])
		var stride := Vector2(now[X] - was[X], now[Z] - was[Z]).length()
		if stride < 2.0:
			distance += stride
		turn = maxf(turn, absf(wrapf(now[YAW] - was[YAW], -180.0, 180.0)) * TICKS)
		shots += maxf(0.0, now[SHOTS] - was[SHOTS])
		hits += maxf(0.0, now[HITS] - was[HITS])
		var pushing := Vector2(now[INPUT_X], now[INPUT_Y]).length() > 0.1
		var pushed := Vector2(was[INPUT_X], was[INPUT_Y]).length() > 0.1
		# A start: input goes down from rest. It ends when speed stops climbing.
		if pushing and not pushed and was[SPEED] < MOVING and flags & ON_FLOOR:
			start_at = index
		elif start_at >= 0 and (not pushing or now[SPEED] <= was[SPEED] + 0.0005):
			if was[SPEED] > MOVING:
				starts.append({"to_speed": snappedf(was[SPEED], 0.01), "seconds": snappedf(was[T] - recent[start_at - 1][T], 0.01), "as": _state(was)})
			start_at = -1
		# A stop: input is let go at speed. It ends at rest.
		if pushed and not pushing and was[SPEED] > 1.0 and flags & ON_FLOOR:
			stop_at = index - 1
		elif stop_at >= 0 and pushing:
			stop_at = -1
		elif stop_at >= 0 and now[SPEED] < 0.05:
			var from := recent[stop_at]
			stops.append({"from_speed": snappedf(from[SPEED], 0.01), "seconds": snappedf(now[T] - from[T], 0.01), "metres": snappedf(Vector2(now[X] - from[X], now[Z] - from[Z]).length(), 0.01)})
			stop_at = -1
		# A jump: off the floor going up, until the floor again.
		if before & ON_FLOOR and not flags & ON_FLOOR and now[RISE] > 0.5 and not flags & DIVING:
			air_at = index - 1
		elif air_at >= 0 and flags & ON_FLOOR:
			var peak: float = recent[air_at][Y]
			for airborne: int in range(air_at, index + 1):
				peak = maxf(peak, recent[airborne][Y])
			jumps.append({"height": snappedf(peak - recent[air_at][Y], 0.01), "air_seconds": snappedf(now[T] - recent[air_at][T], 0.01), "metres": snappedf(Vector2(now[X] - recent[air_at][X], now[Z] - recent[air_at][Z]).length(), 0.01)})
			air_at = -1
	var by_state: Dictionary = {}
	for label: String in states:
		var state: Dictionary = states[label]
		by_state[label] = {"seconds": snappedf(float(state.ticks) / TICKS, 0.1)}
		if state.max > MOVING:
			by_state[label]["avg_speed"] = snappedf(state.sum / state.ticks, 0.01)
			by_state[label]["max_speed"] = snappedf(state.max, 0.01)
	var timeline: Array = []
	for event: Dictionary in events:
		if event.t > clock - seconds:
			timeline.append({"t": snappedf(event.t - clock, 0.1), "event": event.event})
	var result: Dictionary = {
		"seconds_of_play": snappedf(recent.back()[T] - recent[0][T], 0.1),
		"playing_now": playing(),
		"last_played_seconds_ago": snappedf(idle, 0.1),
		"metres": snappedf(distance, 0.01),
		"max_speed": snappedf(top, 0.01),
		"by_state": by_state,
		"max_turn_deg_per_s": snappedf(turn, 1.0),
	}
	if not starts.is_empty():
		result["starts"] = starts.slice(maxi(0, starts.size() - 4))
	if not stops.is_empty():
		result["stops"] = stops.slice(maxi(0, stops.size() - 4))
	if not jumps.is_empty():
		result["jumps"] = jumps.slice(maxi(0, jumps.size() - 4))
	if aimed > 0.0:
		result["aim_seconds"] = snappedf(aimed, 0.1)
	if shots > 0.0:
		result["shots"] = int(shots)
		result["hits"] = int(hits)
	if lowest_health < recent[0][HEALTH]:
		result["lowest_health"] = snappedf(lowest_health, 0.1)
	if not timeline.is_empty():
		result["timeline"] = timeline
	if rows > 0:
		result["columns"] = ["t", "x", "y", "z", "speed", "rise", "yaw", "pitch", "stance", "input_right", "input_back"]
		var picked: Array = []
		var count := mini(rows, recent.size())
		for row: int in range(count):
			var sample := recent[int(round(float(row) * (recent.size() - 1) / maxf(1.0, count - 1.0)))]
			picked.append([snappedf(sample[T] - clock, 0.01), snappedf(sample[X], 0.01), snappedf(sample[Y], 0.01), snappedf(sample[Z], 0.01), snappedf(sample[SPEED], 0.01), snappedf(sample[RISE], 0.01), snappedf(sample[YAW], 0.1), snappedf(sample[PITCH], 0.1), STANCES[clampi(int(sample[STANCE]), 0, 2)], snappedf(sample[INPUT_X], 0.01), snappedf(sample[INPUT_Y], 0.01)])
		result["samples"] = picked
	return result

static func _state(sample: PackedFloat32Array) -> String:
	var flags := int(sample[FLAGS])
	if flags & DIVING:
		return "dive"
	if not flags & ON_FLOOR:
		return "air"
	var stance := clampi(int(sample[STANCE]), 0, 2)
	if sample[SPEED] < MOVING:
		return STANCES[stance] + " still"
	if stance == 0:
		return "walk" if flags & WALK_HELD else "run"
	return "crouch move" if stance == 1 else "crawl"

## A position in the log, to ask later what was logged after it.
func log_mark() -> int:
	capture.lock.lock()
	var mark := capture.sequence
	capture.lock.unlock()
	return mark

## Logged lines newer than `mark`, newest last. `level` is "all", "warnings" (warnings and
## errors), or "errors".
func logged(mark: int = 0, level: String = "all", limit: int = 50) -> Array:
	capture.lock.lock()
	var copy := capture.entries.duplicate()
	capture.lock.unlock()
	var now := Time.get_ticks_msec()
	var found: Array = []
	for entry: Dictionary in copy:
		if entry.seq <= mark:
			continue
		if level == "errors" and entry.kind in ["print", "warning"]:
			continue
		if level == "warnings" and entry.kind == "print":
			continue
		var line: Dictionary = {"ago": snappedf((now - entry.at) / 1000.0, 0.1), "kind": entry.kind, "text": entry.text}
		for key: String in ["where", "in"]:
			if entry.has(key):
				line[key] = entry[key]
		found.append(line)
	return found.slice(maxi(0, found.size() - limit))

func clear_log() -> void:
	capture.lock.lock()
	capture.entries.clear()
	capture.lock.unlock()
