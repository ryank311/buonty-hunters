extends SceneTree
## Keeps the live link (scripts/live) working against the real game: the HTTP endpoint and
## who it lets in, every tool in tools.json, and script reload. If a gameplay change
## breaks a check here, the tools agents use on a running game have drifted from it.
## This runs headless, so pictures are covered by `tools/dev live smoke` instead.

const SERVER := preload("res://scripts/live/live_server.gd")
const PROBE_DIR := "res://.agent/live/test"

var failures: Array[String] = []
var session: Node
var server: Node

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, description: String) -> void:
	print("PASS " if condition else "FAIL ", description)
	if not condition:
		failures.append(description)

func frames(count: int) -> void:
	for index: int in range(count):
		await physics_frame
		await process_frame

## Calls a tool the way a client does and returns its answer, with "is_error" added.
func tool(title: String, arguments: Dictionary = {}) -> Dictionary:
	var reply: Dictionary = await server.handle({"jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": {"name": title, "arguments": arguments}})
	var data: Dictionary = JSON.parse_string(reply.result.content[0].text)
	data["is_error"] = reply.result.isError
	return data

## One HTTP request to the server over a real socket: {"status", "body", "json"}.
func http(method: String, path: String, body: String = "", headers: Dictionary = {}) -> Dictionary:
	var stream := StreamPeerTCP.new()
	stream.connect_to_host("127.0.0.1", server.port)
	for index: int in range(600):
		stream.poll()
		if stream.get_status() != StreamPeerTCP.STATUS_CONNECTING:
			break
		await process_frame
	var head := "%s %s HTTP/1.1\r\nHost: 127.0.0.1:%d\r\nContent-Length: %d\r\n" % [method, path, server.port, body.to_utf8_buffer().size()]
	for key: String in headers:
		head += "%s: %s\r\n" % [key, headers[key]]
	stream.put_data((head + "\r\n" + body).to_utf8_buffer())
	var received := PackedByteArray()
	for index: int in range(6000):
		await process_frame
		stream.poll()
		if stream.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			break
		if stream.get_available_bytes() > 0:
			received.append_array(stream.get_data(stream.get_available_bytes())[1])
	var text := received.get_string_from_utf8()
	var split := text.find("\r\n\r\n")
	var answer: Dictionary = {"status": text.get_slice(" ", 1).to_int(), "body": text.substr(split + 4) if split >= 0 else ""}
	answer["json"] = JSON.parse_string(answer.body) if answer.body != "" else null
	return answer

func write(path: String, source: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(source)
	file.close()

func _run() -> void:
	session = load("res://scenes/main.tscn").instantiate()
	root.add_child(session)
	server = SERVER.new()
	server.requested_port = 0
	server.announce = false
	root.add_child(server)
	await frames(30)
	check(server.port > 0 and server.role == "sandbox", "The live link listens on a free local port (%d, %s)" % [server.port, server.role])

	# The transport, and who it lets in.
	var health := await http("GET", "/health")
	check(health.status == 200 and health.json.port == server.port and health.json.level == "town", "GET /health describes the game (%s)" % health.body.left(80))
	var listing := JSON.stringify({"jsonrpc": "2.0", "id": 7, "method": "tools/list"})
	var allowed: Dictionary = {"Authorization": "Bearer " + server.token, "Content-Type": "application/json"}
	var bare := await http("POST", "/mcp", listing)
	check(bare.status == 401, "A request without the token is refused (%d)" % bare.status)
	var page := await http("POST", "/mcp", listing, allowed.merged({"Origin": "https://example.com"}))
	check(page.status == 403, "A request from a web page is refused (%d)" % page.status)
	var listed := await http("POST", "/mcp", listing, allowed)
	check(listed.status == 200 and "\"id\":7," in listed.body, "tools/list answers over HTTP with the request's own id")
	var offered: Array = listed.json.result.tools
	var names: Array = offered.map(func(entry: Dictionary) -> String: return entry.name)
	var unanswered: Array = names.filter(func(title: String) -> bool: return not server.tools.has_method("_tool_" + title))
	var unlisted: Array = []
	for method: Dictionary in server.tools.get_method_list():
		if method.name.begins_with("_tool_") and not method.name.trim_prefix("_tool_") in names:
			unlisted.append(method.name)
	var malformed: Array = offered.filter(func(entry: Dictionary) -> bool: return str(entry.get("description", "")).length() < 20 or not entry.get("inputSchema") is Dictionary or entry.inputSchema.get("type") != "object")
	check(names.size() >= 15 and unanswered.is_empty() and unlisted.is_empty() and malformed.is_empty(), "Every tool in tools.json is described and answered, and every handler is listed (%d tools%s)" % [names.size(), "" if unanswered.is_empty() and unlisted.is_empty() else "; unanswered %s, unlisted %s" % [str(unanswered), str(unlisted)]])
	var hello := await http("POST", "/mcp", JSON.stringify({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "live_regression", "version": "1"}}}), allowed)
	check(hello.json.result.protocolVersion == "2025-06-18" and hello.json.result.serverInfo.name == "socom-live" and hello.json.result.capabilities.has("tools"), "initialize agrees the protocol version and offers tools")
	var notified := await http("POST", "/mcp", JSON.stringify({"jsonrpc": "2.0", "method": "notifications/initialized"}), allowed)
	check(notified.status == 202 and notified.body == "", "A notification is accepted without an answer (%d)" % notified.status)
	var called := await http("POST", "/mcp", JSON.stringify({"jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": {"name": "state", "arguments": {}}}), allowed)
	var digest: Variant = JSON.parse_string(called.json.result.content[0].text)
	check(digest is Dictionary and digest.level == "town" and digest.game == server.label() and not called.json.result.isError, "tools/call state returns the game's digest over HTTP")
	var lost := await http("GET", "/nowhere")
	var unknown := await tool("nope")
	check(lost.status == 404 and unknown.is_error, "An unknown path and an unknown tool are refused plainly")

	# Tuning is felt at once, reported against the defaults, and put back.
	var defaults: Resource = load("res://resources/movement/default_movement.tres")
	var start := await tool("setup", {"scenario": "lab_start"})
	var run := await tool("play", {"frames": 60, "forward": 1.0})
	var baseline: float = start.player.pos[2] - run.player.pos[2]
	# Let the player coast to rest, so the recorder sees a whole stop.
	await frames(30)
	var faster: float = defaults.run_speed + 1.5
	var tuned := await tool("tuning_set", {"changes": {"movement.run_speed": faster, "weapon.vertical_kick": 0.2, "movement.nope": 1}})
	check(not tuned.is_error and tuned.applied["movement.run_speed"].from == defaults.run_speed and tuned.refused.has("movement.nope") and session.player.movement.run_speed == faster and is_equal_approx(session.player.weapon.profile.vertical_kick, 0.2), "tuning_set changes live values and names the ones it cannot")
	await tool("setup", {"spawn": "Start"})
	var quick := await tool("play", {"frames": 60, "forward": 1.0})
	var covered: float = start.player.pos[2] - quick.player.pos[2]
	await frames(30)
	check(covered > baseline + 0.7, "A raised run speed is felt on the next run (%.2f m against %.2f m)" % [covered, baseline])
	var listed_tuning := await tool("tuning_get", {"section": "movement"})
	var movement: Dictionary = listed_tuning.movement
	check(movement.changed.run_speed.default == defaults.run_speed and movement.changed.run_speed.live == faster and movement.ranges.run_speed == [2.0, 8.0] and movement.default_file == defaults.resource_path and movement.values.has("walk_speed"), "tuning_get shows values, ranges, and what differs from the default file")
	var weapons := await tool("tuning_get", {"section": "weapons"})
	check(weapons.has("weapon0") and weapons.weapon0.in_hand and weapons.weapon0.changed.has("vertical_kick") and weapons.has("weapon1") and not weapons.weapon1.has("changed"), "tuning_get lists every carried weapon by slot")
	var planned := await tool("tuning_save", {"dry_run": true})
	check(planned.would_write.get(defaults.resource_path, {}).has("run_speed") and load(defaults.resource_path).run_speed == defaults.run_speed, "tuning_save can report what it would write without writing")
	var restored := await tool("tuning_set", {"changes": {"movement.run_speed": null, "weapon.vertical_kick": null}})
	check(not restored.is_error and session.player.movement.run_speed == defaults.run_speed, "null puts a value back to its default")

	# What the player did, in numbers.
	var felt := await tool("telemetry", {"seconds": 8, "samples": 5})
	var events: Array = felt.get("timeline", []).map(func(entry: Dictionary) -> String: return entry.event)
	check(felt.by_state.has("run") and is_equal_approx(felt.by_state.run.max_speed, faster) and felt.samples.size() == 5 and felt.starts.size() >= 2 and felt.stops.size() >= 2, "telemetry reports speed by state, starts, and stops (run max %.2f m/s, start %.2f s)" % [felt.by_state.run.max_speed, felt.starts[0].seconds])
	check(events.any(func(event: String) -> bool: return "run_speed" in event), "The timeline shows what the agent changed beside what the player did")

	# Reading and changing anything by path.
	var seen := await tool("inspect", {"path": "player", "props": ["velocity", "stance.current", "weapon.profile.display_name", "nope"]})
	check(seen["class"] == "CharacterBody3D" and seen.values["stance.current"] == 0 and seen.values["weapon.profile.display_name"] == session.player.weapon.profile.display_name and str(seen.values.nope).begins_with("(") and seen.children.size() >= 4, "inspect reads dotted properties and lists children")
	var target := await tool("inspect", {"path": "level/Targets/Target10", "depth": 0})
	var recoil := await tool("inspect", {"path": "weapon.recoil", "props": "all"})
	check(target.path.ends_with("Targets/Target10") and target.has("vars") and recoil.values.has("bloom"), "inspect reaches level nodes and objects held in variables")
	var wrote := await tool("set", {"path": "player", "values": {"health": 40, "velocity.y": 3.0, "movement.jump_height": 1.5, "nope": 1}})
	check(session.player.health == 40.0 and is_equal_approx(session.player.movement.jump_height, 1.5) and wrote.changed["velocity.y"].to == 3.0 and wrote.refused.has("nope"), "set writes values, parts of vectors, and nested objects")
	var where := await tool("call", {"path": "session", "method": "location_name"})
	await tool("call", {"path": "actor:ALPHA", "method": "die"})
	var fallen := await tool("inspect", {"path": "actor:ALPHA", "props": ["alive"], "depth": 0})
	check(where.result == session.location_name() and fallen.values.alive == false, "call runs methods on the session and on a soldier named by actor:<NAME>")
	var sum := await tool("eval", {"code": "player.health + 2"})
	var engine := await tool("eval", {"code": "Engine.get_physics_ticks_per_second()"})
	var assigned := await tool("eval", {"code": "player.health = 77"})
	var block := await tool("eval", {"code": "var before: int = Engine.get_physics_frames()\nfor index: int in range(5):\n\tawait tree.physics_frame\nreturn [player.health, Engine.get_physics_frames() - before]"})
	check(sum.result == 42.0 and engine.result == 60 and not assigned.is_error and block.result[0] == 77.0 and block.result[1] >= 4, "eval returns an expression's value, reaches engine classes, assigns, and runs statements that await")
	var broken := await tool("eval", {"code": "player.health +"})
	var missing := await tool("eval", {"code": "player.nope()"})
	check(broken.is_error and "line 1" in str(broken.get("problems")) and missing.is_error, "eval reports code that does not compile or cannot run")
	await tool("eval", {"code": "push_warning(\"live link test warning\")"})
	var logged := await tool("logs", {"level": "warnings", "seconds": 30})
	check(logged.lines.any(func(line: Dictionary) -> bool: return line.text == "live link test warning" and line.kind == "warning"), "logs returns what the game printed, with its kind")

	# Holding and stepping time.
	await tool("setup", {"scenario": "lab_range_moving"})
	var moving: Node3D = session.level.get_node("Targets/MovingTarget")
	var frozen := await tool("time", {"frozen": true})
	var held: Vector3 = moving.global_position
	await frames(20)
	check(frozen.frozen and paused and moving.global_position == held and server.tools.banner.visible, "time freezes the game and says so on screen")
	await tool("time", {"step": 30})
	check(paused and moving.global_position != held, "A step advances a frozen game and freezes it again")
	await tool("time", {"frozen": false, "scale": 0.5})
	await tool("play", {"frames": 6})
	check(not paused and is_equal_approx(Engine.time_scale, 0.5), "Slow motion outlasts a played step")
	await tool("time", {"scale": 1})
	check(is_equal_approx(Engine.time_scale, 1.0) and not server.tools.banner.visible, "Time goes back to normal")

	# An open menu stays open across a change to the world.
	session.set_modal(true)
	var placed := await tool("setup", {"pos": [0.0, 0.1, 20.0]})
	var walked := await tool("play", {"frames": 30, "forward": 1.0})
	check(session.modal and placed.menu and walked.player.pos[2] < 19.5, "setup and play work under an open menu and leave it open (z %.2f)" % walked.player.pos[2])
	session.set_modal(false)

	# Reloading a script under a live object.
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PROBE_DIR))
	var path := PROBE_DIR.path_join("reload_probe_%d.gd" % OS.get_process_id())
	write(path, "extends Node\nconst STEP := 1\nvar kept: int = 1\nfunc answer() -> int:\n\treturn STEP\n")
	var probe: Node = load(path).new()
	root.add_child(probe)
	probe.kept = 9
	write(path, "extends Node\nconst STEP := 2\nvar kept: int = 1\nvar added: int = 5\nfunc answer() -> int:\n\treturn STEP + added\n")
	var reloaded := await tool("reload", {"paths": [path]})
	check(reloaded.reloaded == [path] and probe.answer() == 7 and probe.kept == 9, "reload swaps a changed script under a live object, keeps its state, and starts new variables at their declared value (answer %s)" % str(probe.answer()))
	write(path, "extends Node\nvar kept: int = 1\nfunc answer() -> int:\n\treturn 3 +\n")
	var refused := await tool("reload", {"paths": [path]})
	check(refused.is_error and refused.failed.has(path) and probe.answer() == 7, "A script that does not compile is refused and the game keeps the one it had")
	probe.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	var picture := await tool("screenshot")
	check(picture.is_error and "headless" in picture.error, "A headless game says it cannot draw rather than hanging")

	print("\nRESULT: %d failure(s)" % failures.size())
	server.queue_free()
	session.queue_free()
	await frames(2)
	quit(0 if failures.is_empty() else 1)
