extends SceneTree
## Climbs every ladder of the recovered maps the way a player does: takes the offer at
## the foot and climbs to the top floor, takes the offer at the head and backs down to
## the ground, then climbs part-way, lets go of the stick, and slides. Run it after a map
## is re-exported or resources/recovered/ladders.json is rebuilt; it takes a few minutes,
## so it is a tool, not a regression suite.
##
##   tools/dev godot --headless --path . --fixed-fps 60 --script res://tools/recovery/verify_ladders.gd -- --qa [MP2 MP81 ...]
##
## With no map named it visits every map that has a ladder.
const H = preload("res://tools/agent/harness.gd")
var session: Node
var player: PrototypePlayer

func _initialize() -> void:
	_run.call_deferred()

func ticks(count: int) -> void:
	for index: int in range(count):
		await physics_frame

func offer(kind: String) -> Dictionary:
	player.interactions.refresh()
	for entry: Dictionary in player.interactions.offers:
		if entry.kind == kind:
			return entry
	return {}

func hold(forward: float) -> void:
	H._axis("move_forward", "move_back", forward)

## Runs until the ladder lets go or `limit` ticks pass; returns ticks taken and clips seen.
func ride(limit: int) -> Dictionary:
	var seen: Array[String] = []
	var count := 0
	var lowest := INF
	var highest := -INF
	while player.ladder.active and count < limit:
		await physics_frame
		count += 1
		lowest = minf(lowest, player.global_position.y)
		highest = maxf(highest, player.global_position.y)
		var clip: String = player.soldier.traversal_clip
		if clip != "" and (seen.is_empty() or seen.back() != clip):
			seen.append(clip)
	return {"ticks": count, "clips": seen, "low": lowest, "high": highest, "done": not player.ladder.active}

func _run() -> void:
	session = load("res://scenes/main.tscn").instantiate()
	root.add_child(session)
	await H.scenario(self, "lab_start", {"roster": false})
	player = session.player
	var maps: Array = Array(OS.get_cmdline_user_args()).filter(func(a: String) -> bool: return a.begins_with("MP"))
	if maps.is_empty():
		maps = JSON.parse_string(FileAccess.get_file_as_string("res://resources/recovered/ladders.json")).maps.keys()
	var problems := 0
	for map: String in maps:
		await H.apply(self, {"level": "map:" + map, "roster": false})
		var holder: Node = session.level.get_node_or_null("Ladders")
		if holder == null:
			print(map, ": no ladders installed")
			problems += 1
			continue
		for ladder: Node3D in holder.get_children():
			var out: Vector3 = ladder.out()
			var yaw := rad_to_deg(atan2(out.x, out.z))
			var foot: Vector3 = ladder.global_position + out * 1.0
			# The ground in front of the ladder, which can lie above the bottom of its rungs.
			var probe: Vector3 = foot + Vector3.UP * (ladder.height - 2.6)
			var below := player.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(probe, probe + Vector3.DOWN * (ladder.height + 2.0), player.collision_mask, [player.get_rid()]))
			if not below.is_empty():
				foot.y = below.position.y
			await H.apply(self, {"pos": [foot.x, foot.y + 0.1, foot.z], "yaw": yaw, "stance": "stand", "settle": 20})
			var line := "%s %s h=%.2f: " % [map, ladder.name, ladder.height]
			var standing := player.global_position
			var up := offer("ladder")
			if up.is_empty() or up.label != "CLIMB LADDER":
				print(line, "NO FOOT OFFER at ", standing, " floor ", player.is_on_floor(), " local ", ladder.to_local(standing))
				problems += 1
				continue
			player.interactions.activate()
			hold(1.0)
			var climb: Dictionary = await ride(1800)
			hold(0.0)
			await ticks(12)
			var top := player.global_position
			var local: Vector3 = ladder.to_local(top)
			var ok: bool = climb.done and absf(local.y - ladder.height) < 0.3 and local.z < -0.3 and player.is_on_floor()
			line += "up %.1fs %s -> y %.2f (deck %.2f) behind %.2f floor %s cycles %d" % [climb.ticks / 60.0, "ok" if ok else "FAILED " + str(climb.clips), local.y, ladder.height, -local.z, player.is_on_floor(), player.ladder.cycles]
			if not ok:
				problems += 1
				print(line)
				continue
			# Back down from the head: face the ladder and take the offer.
			await H.apply(self, {"yaw": yaw + 180.0, "settle": 4})
			var down := offer("ladder")
			if down.is_empty() or down.label != "CLIMB DOWN":
				print(line, " | NO HEAD OFFER local ", ladder.to_local(player.global_position))
				problems += 1
				continue
			player.interactions.activate()
			hold(-1.0)
			var descent: Dictionary = await ride(1800)
			hold(0.0)
			await ticks(12)
			var back: Vector3 = ladder.to_local(player.global_position)
			ok = descent.done and absf(player.global_position.y - standing.y) < 0.15 and back.z > 0.8 and player.is_on_floor()
			line += " | down %.1fs %s y %.2f out %.2f" % [descent.ticks / 60.0, "ok" if ok else "FAILED " + str(descent.clips), back.y, back.z]
			if not ok:
				problems += 1
				print(line)
				continue
			# Up again half way, then the slide.
			await H.apply(self, {"pos": [foot.x, foot.y + 0.1, foot.z], "yaw": yaw, "settle": 20})
			player.interactions.activate()
			hold(1.0)
			var waited := 0
			while player.ladder.active and player.ladder.progress < maxf(1.0, player.ladder.cycles * 0.6) and waited < 900:
				await physics_frame
				waited += 1
			hold(0.0)
			await ticks(3)
			var held := player.global_position.y
			await ticks(20)
			var still := absf(player.global_position.y - held) < 0.001
			var slide := offer("slide")
			var from := player.global_position.y - standing.y
			var slid := false
			if not slide.is_empty():
				slid = player.interactions.activate()
			var fallen: Dictionary = await ride(600)
			await ticks(12)
			var landed: Vector3 = ladder.to_local(player.global_position)
			ok = still and slid and fallen.done and absf(player.global_position.y - standing.y) < 0.15 and player.is_on_floor()
			line += " | holds %s, slide from %.2f m %.1fs %s out %.2f" % [still, from, fallen.ticks / 60.0, "ok" if ok else "FAILED " + str(fallen.clips), landed.z]
			if not ok:
				problems += 1
			print(line)
	print("LADDERS: %s" % ("ok" if problems == 0 else "%d problem(s)" % problems))
	session.queue_free()
	await process_frame
	quit(0 if problems == 0 else 1)
