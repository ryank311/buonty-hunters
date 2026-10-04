extends RefCounted
## Scenario setup, input stepping, and state digests for agents driving the running game.
##
## Nothing in the game references this file. It is reached from MCP `run_script`
## snippets and from tools/agent/capture.gd:
##
##   extends RefCounted
##   const H = preload("res://tools/agent/harness.gd")
##   func execute(scene_tree: SceneTree) -> Variant:
##       return await H.scenario(scene_tree, "lab_range")
##
## Units: positions are metres [x, y, z]; yaw and pitch are degrees (yaw 0 faces -Z and
## positive turns left; positive pitch looks up); frames are physics ticks of 1/60 s.
## Setup is by fiat: teleports, stances, and yaw skip the clearance checks a player is
## held to, and the returned "notes" say when the result is not a reachable state.

const STANCES: Array[String] = ["stand", "crouch", "prone"]
const WEAPONS: Array[String] = ["rifle", "pistol"]
const HELD_META := &"agent_held_actions"
const PLACED_GROUP := &"agent_placed"
const READY_META := &"agent_ready"
const MAX_STEP_FRAMES := 3600  # one simulated minute
const BASE_TICKS := 60

## Named starting points. Add one whenever a state is worth revisiting; prefer markers
## ("spawn", "at") over raw coordinates so level edits do not strand a scenario.
const SCENARIOS: Dictionary = {
	"town_spawn": {"level": "town", "spawn": "West1"},
	"town_east_spawn": {"level": "town", "spawn": "East1"},
	"town_market": {"level": "town", "pos": [-17.0, 0.1, -13.0], "look_at": [-17.0, 1.4, -1.0]},
	"town_courtyard": {"level": "town", "pos": [18.0, 0.1, -36.0], "look_at": [33.0, 1.4, -36.0]},
	"town_passage": {"level": "town", "pos": [7.0, 0.1, 38.0], "look_at": [7.0, 1.4, 17.0]},
	"town_west_stair": {"level": "town", "pos": [-5.0, 0.1, -26.0], "yaw": 180.0},
	"lab_start": {"level": "lab", "spawn": "Start"},
	"lab_range": {"level": "lab", "pos": [23.0, 0.1, 5.0], "look_at": "Targets/Target10"},
	"lab_range_moving": {"level": "lab", "pos": [25.0, 0.1, 5.0], "look_at": "Targets/MovingTarget"},
	"lab_low_ceiling": {"level": "lab", "pos": [-10.0, 0.08, 2.0], "stance": "crouch"},
	"lab_prone_tunnel": {"level": "lab", "pos": [-10.0, 0.08, -7.0], "stance": "prone"},
	"lab_stairs": {"level": "lab", "spawn": "Stairs"},
	"lab_wall_camera": {"level": "lab", "pos": [9.0, 0.1, 21.8]},
	"menu": {"level": "lab", "spawn": "Start", "menu": 0},
	"rifle_empty": {"level": "lab", "pos": [23.0, 0.1, 5.0], "look_at": "Targets/Target10", "ammo": 0, "reserve": 0},
	"pistol_ready": {"level": "lab", "pos": [23.0, 0.1, 5.0], "look_at": "Targets/Target10", "weapon": "pistol"},
	"crouch_aim": {"level": "lab", "pos": [23.0, 0.1, 5.0], "look_at": "Targets/Target10", "stance": "crouch", "hold": ["aim"]},
}

static func session(tree: SceneTree) -> Node:
	for node: Node in tree.root.get_children():
		if node.has_method("load_level") and node.get("player") != null:
			return node
	return null

static func scenarios() -> Dictionary:
	return SCENARIOS

## Applies a named scenario from a clean respawn. `overrides` takes the same keys as apply().
static func scenario(tree: SceneTree, title: String, overrides: Dictionary = {}) -> Dictionary:
	if not SCENARIOS.has(title):
		return {"error": "Unknown scenario '%s'" % title, "scenarios": SCENARIOS.keys()}
	var spec: Dictionary = {"reset": true}
	spec.merge(SCENARIOS[title], true)
	spec.merge(overrides, true)
	return await apply(tree, spec)

## Puts the game into the described state and returns state(). Every key is optional:
##   level "town"|"lab", reload bool      spawn index|name (respawns)
##   reset bool (respawn, refill, default tuning)
##   at "Locations/Market" (level node)   pos [x,y,z]
##   yaw deg, pitch deg                   look_at [x,y,z] | level node path
##   stance "stand"|"crouch"|"prone"      weapon "rifle"|"pistol", ammo int, reserve int
##   health float                         hold ["aim", ...] (kept down until the next call)
##   tuning {"movement"|"camera"|"weapon": {property: value}}
##   place [{"scene": "res://art/models/crate.glb", "pos": [x,y,z], "yaw": deg, "scale": n}]
##   menu bool|page index, debug bool     settle frames (default 8), freeze bool
static func apply(tree: SceneTree, spec: Dictionary) -> Dictionary:
	var s := session(tree)
	if s == null:
		return {"error": "No running session: scenes/main.tscn is not loaded."}
	var notes: Array[String] = []
	var p: CharacterBody3D = s.player
	var w: Node = p.weapon
	var freeze: bool = spec.get("freeze", tree.paused)
	tree.paused = false
	_prepare(s)
	_release_held(s)
	# The menu disables the level and the player, so world setup happens with it closed.
	if s.modal:
		s.set_modal(false)
	var reset: bool = spec.get("reset", false)
	if reset:
		# A clean slate includes tuning, or one experiment would skew the next.
		s.reset_tuning()
		for placed: Node in tree.get_nodes_in_group(PLACED_GROUP):
			placed.queue_free()
	if spec.has("level"):
		var wanted := str(spec.level)
		if wanted not in ["town", "lab"]:
			notes.append("unknown level '%s' (town or lab)" % wanted)
		elif (wanted == "lab") != s.in_lab or spec.get("reload", false):
			s.load_level(wanted == "lab")
			await _ticks(tree, 2)
	if spec.has("spawn"):
		var index := _child_index(s.level.get_node("Spawns"), spec.spawn)
		if index < 0:
			notes.append("no spawn '%s'" % str(spec.spawn))
		else:
			s.spawn_index = index
			s.reset_player()
	elif reset:
		s.reset_player()
	# Scenes dropped into the level for a look: a model fresh out of Blender, a prop in
	# context. They last until the next reset or level change and are never saved.
	for item: Dictionary in spec.get("place", []):
		var packed := load(str(item.get("scene", ""))) as PackedScene
		if packed == null:
			notes.append("cannot load scene '%s' (exported and imported? tools/dev import)" % str(item.get("scene", "")))
			continue
		var placed := packed.instantiate()
		placed.add_to_group(PLACED_GROUP)
		s.level.add_child(placed)
		if placed is Node3D:
			placed.global_position = _vec(item.get("pos", [0.0, 0.0, 0.0]))
			placed.rotation.y = deg_to_rad(float(item.get("yaw", 0.0)))
			placed.scale = Vector3.ONE * float(item.get("scale", 1.0))
	if spec.has("at"):
		var marker := s.level.get_node_or_null(str(spec.at)) as Node3D
		if marker == null:
			notes.append("no level node '%s'" % str(spec.at))
		else:
			_teleport(p, marker.global_position + Vector3.UP * 0.1, marker.global_rotation.y)
	if spec.has("pos"):
		_teleport(p, _vec(spec.pos), p.rotation.y)
	if spec.has("yaw"):
		p.rotation.y = deg_to_rad(float(spec.yaw))
	if spec.has("pitch"):
		_set_pitch(p, float(spec.pitch))
	if spec.has("stance"):
		var stance := STANCES.find(str(spec.stance))
		if stance < 0:
			notes.append("unknown stance '%s'" % str(spec.stance))
		else:
			p.stance.current = stance
			p.stance.apply(p.collider)
	await _ticks(tree, 6)
	if not p.stance.has_clearance(p, p.stance.current, p.rotation.y):
		notes.append("%s has no clearance here; a player could not hold this stance" % STANCES[p.stance.current])
	if spec.has("weapon"):
		var slot := WEAPONS.find(str(spec.weapon))
		if slot < 0:
			notes.append("unknown weapon '%s'" % str(spec.weapon))
		else:
			w.equip(slot)
			# Ready at once; drive the equip action through step() to test the draw itself.
			w.draw_remaining = 0.0
			w.cooldown = 0.0
			w.require_trigger_release = false
	if spec.has("ammo"):
		w.ammo = int(spec.ammo)
	if spec.has("reserve"):
		w.reserve = int(spec.reserve)
	if spec.has("health"):
		p.health = float(spec.health)
	var tuning: Dictionary = spec.get("tuning", {})
	for section: String in tuning:
		var target: Resource = {"movement": p.movement, "camera": p.camera_settings, "weapon": w.profile}.get(section)
		if target == null:
			notes.append("unknown tuning section '%s' (movement, camera, weapon)" % section)
			continue
		for key: String in tuning[section]:
			if key in target:
				target.set(key, tuning[section][key])
			else:
				notes.append("no %s property '%s'" % [section, key])
	if spec.has("look_at"):
		var point: Variant = _point(s, spec.look_at)
		if point == null:
			notes.append("cannot resolve look_at '%s'" % str(spec.look_at))
		else:
			await _aim(tree, p, point)
	for action: String in spec.get("hold", []):
		_hold(s, action)
	if spec.has("debug"):
		s.debug_visible = bool(spec.debug)
	await _ticks(tree, int(spec.get("settle", 8)))
	var menu: Variant = spec.get("menu", false)
	if not (menu is bool and not menu):
		s.set_modal(true)
		if not menu is bool:
			s.hud.show_page(int(menu))
		await _ticks(tree, 3)
	tree.paused = freeze
	var result := state(tree)
	if not notes.is_empty():
		result["notes"] = notes
	return result

## Runs the game for exactly `frames` physics ticks with the given input held, then
## releases it:
##   forward, right  -1..1 analogue movement      hold ["fire", "aim", "walk", ...]
##   tap ["jump", "reload", "switch_level", ...]  turn, look_up  degrees per second
##   trace N  sample [frame, x, y, z, speed] every N frames
##   speed N  run up to 8 times faster than real time; ticks stay 1/60 s, so the
##            outcome is identical to running at normal speed
## A frozen game is thawed for the window and frozen again afterwards.
static func step(tree: SceneTree, frames: int, input: Dictionary = {}) -> Dictionary:
	var s := session(tree)
	if s == null:
		return {"error": "No running session: scenes/main.tscn is not loaded."}
	var p: CharacterBody3D = s.player
	var freeze := tree.paused
	tree.paused = false
	_prepare(s)
	_fast_forward(float(input.get("speed", 1.0)))
	_axis("move_forward", "move_back", float(input.get("forward", 0.0)))
	_axis("move_right", "move_left", float(input.get("right", 0.0)))
	var held: Array = input.get("hold", [])
	var taps: Array = input.get("tap", [])
	for action: String in held + taps:
		_send(action, true)
	var turn := deg_to_rad(float(input.get("turn", 0.0))) / BASE_TICKS
	var look_up := float(input.get("look_up", 0.0)) / BASE_TICKS
	var every := int(input.get("trace", 0))
	var trace: Array = []
	for index: int in range(clampi(frames, 1, MAX_STEP_FRAMES)):
		await tree.physics_frame
		if index == 2:
			for action: String in taps:
				_send(action, false)
		if turn != 0.0:
			p.turn(turn)
		if look_up != 0.0:
			_set_pitch(p, rad_to_deg(p.camera_rig.pitch) + look_up)
		if every > 0 and index % every == 0:
			var speed := Vector2(p.velocity.x, p.velocity.z).length()
			trace.append([index, snappedf(p.global_position.x, 0.001), snappedf(p.global_position.y, 0.001), snappedf(p.global_position.z, 0.001), snappedf(speed, 0.001)])
	await tree.physics_frame
	_axis("move_forward", "move_back", 0.0)
	_axis("move_right", "move_left", 0.0)
	for action: String in held + taps:
		_send(action, false)
	await _settle_input(tree, freeze)
	var result := state(tree)
	if not trace.is_empty():
		result["trace"] = trace
	return result

## Walks through [x, z] waypoints the way tests/prototype_smoke.gd does: face the next
## point and hold forward. Reports where it stopped if a leg cannot be completed.
## `speed` fast-forwards as in step(); "seconds" in the result is simulated time.
static func walk_to(tree: SceneTree, points: Array, speed: float = 4.0, leg_frames: int = 900) -> Dictionary:
	var s := session(tree)
	if s == null:
		return {"error": "No running session: scenes/main.tscn is not loaded."}
	var p: CharacterBody3D = s.player
	var freeze := tree.paused
	tree.paused = false
	_prepare(s)
	_fast_forward(speed)
	var ticks := 0
	var blocked_at: Variant = null
	_axis("move_forward", "move_back", 1.0)
	for point: Variant in points:
		var goal := Vector2(float(point[0]), float(point[1]))
		var arrived := false
		for index: int in range(leg_frames):
			await tree.physics_frame
			var offset := Vector3(goal.x, p.position.y, goal.y) - p.position
			if offset.length() < 0.35:
				arrived = true
				break
			p.rotation.y = atan2(-offset.x, -offset.z)
			ticks += 1
		if not arrived:
			blocked_at = [goal.x, goal.y]
			break
	_axis("move_forward", "move_back", 0.0)
	await _settle_input(tree, false)
	await _ticks(tree, 12)
	tree.paused = freeze
	var result := state(tree)
	result["walk"] = {"arrived": blocked_at == null, "seconds": snappedf(ticks / float(BASE_TICKS), 0.01)}
	if blocked_at != null:
		result["walk"]["blocked_before"] = blocked_at
	return result

## Compact digest of what the game is doing right now. Cheaper than a screenshot.
static func state(tree: SceneTree) -> Dictionary:
	var s := session(tree)
	if s == null:
		return {"error": "No running session: scenes/main.tscn is not loaded."}
	var p: CharacterBody3D = s.player
	var w: Node = p.weapon
	var rig: Node3D = p.camera_rig
	var hit: Dictionary = w.query_aim()
	var collider: Variant = hit.get("collider")
	var targets: Dictionary = {}
	for target: Node in tree.get_nodes_in_group("range_targets"):
		if s.level.is_ancestor_of(target):
			targets[str(target.name)] = {"pos": _round(target.global_position), "lit": target.flash_remaining > 0.0}
	var result: Dictionary = {
		"level": "lab" if s.in_lab else "town",
		"location": s.location_name(),
		"spawn": str(s.level.get_node("Spawns").get_child(s.spawn_index).name),
		"menu": s.modal,
		"frozen": tree.paused,
		"tick": Engine.get_physics_frames(),
		"player": {
			"pos": _round(p.global_position),
			"yaw": snappedf(rad_to_deg(p.rotation.y), 0.1),
			"pitch": snappedf(rad_to_deg(rig.pitch), 0.1),
			"speed": snappedf(Vector2(p.velocity.x, p.velocity.z).length(), 0.001),
			"vertical_speed": snappedf(p.velocity.y, 0.001),
			"stance": STANCES[p.stance.current],
			"on_floor": p.is_on_floor(),
			"health": p.health,
			"aiming": p.aiming,
			"diving": p.get("diving") == true,
		},
		"weapon": {
			"name": w.profile.display_name,
			"ammo": w.ammo,
			"reserve": w.reserve,
			"reloading": w.reload_remaining > 0.0,
			"shots": w.shots_fired,
			"hits": w.hits,
			"spread": snappedf(w.spread_degrees(), 0.01),
		},
		"aim": {
			"hit": str(collider.name) if collider is Node else "",
			"point": _round(w.aim_point),
			"distance": snappedf(rig.camera.global_position.distance_to(w.aim_point), 0.01),
			"muzzle_blocked": w.blocked,
		},
		"camera": {"arm": snappedf(rig.arm.get_hit_length(), 0.01), "fov": snappedf(rig.camera.fov, 0.1)},
	}
	if not targets.is_empty():
		result["targets"] = targets
	var placed: Array = tree.get_nodes_in_group(PLACED_GROUP).filter(func(node: Node) -> bool: return not node.is_queued_for_deletion())
	if not placed.is_empty():
		result["placed"] = placed.map(func(node: Node) -> String: return str(node.name))
	var notice: Variant = s.hud.get("notice_label")
	if notice is Label and notice.visible and notice.text != "":
		result["notice"] = notice.text
	return result

static func _prepare(s: Node) -> void:
	if s.has_meta(READY_META):
		return
	s.set_meta(READY_META, true)
	# Agent sessions stay quiet.
	if OS.get_environment("SOCOM_AGENT_AUDIO") != "1":
		AudioServer.set_bus_mute(0, true)
	# One rendered frame per physics tick, so "frames" means the same thing everywhere.
	Engine.max_fps = BASE_TICKS

static func _fast_forward(speed: float) -> void:
	# More ticks per second at a matching time scale keeps every tick at 1/60 s.
	var factor := clampi(roundi(speed), 1, 8)
	Engine.physics_ticks_per_second = BASE_TICKS * factor
	Engine.max_physics_steps_per_frame = 8 * factor
	Engine.time_scale = float(factor)

# Resumes at the start of the next physics tick once `count` whole ticks have run.
static func _ticks(tree: SceneTree, count: int) -> void:
	for index: int in range(count + 1):
		await tree.physics_frame

# Holds the world still while buffered input releases land, so a stepped window is
# exactly as long as it was asked to be.
static func _settle_input(tree: SceneTree, freeze: bool) -> void:
	tree.paused = true
	await tree.process_frame
	await tree.process_frame
	_fast_forward(1.0)
	tree.paused = freeze

static func _send(action: String, pressed: bool, strength: float = 1.0) -> void:
	if not InputMap.has_action(action):
		push_warning("agent harness: unknown input action '%s'" % action)
		return
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	event.strength = strength if pressed else 0.0
	Input.parse_input_event(event)

static func _axis(positive: String, negative: String, value: float) -> void:
	value = clampf(value, -1.0, 1.0)
	_send(positive, value > 0.0, absf(value))
	_send(negative, value < 0.0, absf(value))

static func _hold(s: Node, action: String) -> void:
	var held: Array = s.get_meta(HELD_META, [])
	if action not in held:
		held.append(action)
	s.set_meta(HELD_META, held)
	_send(action, true)

static func _release_held(s: Node) -> void:
	for action: String in s.get_meta(HELD_META, []):
		_send(action, false)
	s.set_meta(HELD_META, [])

static func _teleport(p: CharacterBody3D, position: Vector3, yaw: float) -> void:
	p.global_position = position
	p.rotation.y = yaw
	p.velocity = Vector3.ZERO

static func _set_pitch(p: CharacterBody3D, degrees: float) -> void:
	var rig: Node3D = p.camera_rig
	rig.pitch = clampf(deg_to_rad(degrees), deg_to_rad(-50.0), deg_to_rad(65.0))
	rig.set_recoil(rig.recoil_offset)

static func _aim(tree: SceneTree, p: CharacterBody3D, point: Vector3) -> void:
	# The camera sits off the shoulder, so its position shifts as the body turns; a few
	# passes converge the view ray onto the point.
	for index: int in range(6):
		var direction: Vector3 = p.camera_rig.camera.global_position.direction_to(point)
		p.rotation.y = atan2(-direction.x, -direction.z)
		_set_pitch(p, rad_to_deg(asin(direction.y)))
		await _ticks(tree, 1)

static func _point(s: Node, value: Variant) -> Variant:
	if value is String:
		var node := s.level.get_node_or_null(value) as Node3D
		return node.global_position if node else null
	return _vec(value)

static func _vec(value: Variant) -> Vector3:
	if value is Vector3:
		return value
	if value is Dictionary:
		return Vector3(float(value.get("x", 0.0)), float(value.get("y", 0.0)), float(value.get("z", 0.0)))
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

static func _round(value: Vector3) -> Array:
	return [snappedf(value.x, 0.001), snappedf(value.y, 0.001), snappedf(value.z, 0.001)]

static func _child_index(parent: Node, key: Variant) -> int:
	if key is String:
		for child: Node in parent.get_children():
			if str(child.name).to_lower() == key.to_lower():
				return child.get_index()
		return -1
	var index := int(key)
	return index if index >= 0 and index < parent.get_child_count() else -1
