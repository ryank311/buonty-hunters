extends Node
## The live link: an MCP server inside the running game, so an agent can inspect and
## change the game while someone plays it. scripts/live/live_boot.gd decides when it runs.
##
## It speaks MCP (JSON-RPC 2.0) over HTTP on this machine only:
##   GET  /health   who this game is: port, process, role, level
##   POST /mcp      initialize, tools/list, tools/call. Each request is answered with one
##                  JSON body; there is no session to keep, so a restarted game picks up
##                  where the last one left off.
## Agents reach it through tools/agent/live-mcp.mjs, which finds running games and stays
## up between them. Any MCP client can also be pointed at http://127.0.0.1:<port>/mcp.
##
## Three things keep other software out: the socket listens on 127.0.0.1 only; a request
## must carry the token written to .agent/live/<port>.json, which only this user can
## read; and a request from a web page (one with an Origin header) is refused.

const Tools := preload("res://scripts/live/live_tools.gd")
const Recorder := preload("res://scripts/live/live_recorder.gd")
const Codec := preload("res://scripts/live/live_codec.gd")
const MANIFEST := "res://scripts/live/tools.json"
const REGISTRY := "res://.agent/live"
const DEFAULT_PORT := 47200
const PORT_SPAN := 10
const MAX_HEAD := 16 * 1024
const MAX_BODY := 4 * 1024 * 1024
const IDLE_MS := 15000
const PROTOCOLS: Array[String] = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]
const REASONS: Dictionary = {200: "OK", 202: "Accepted", 400: "Bad Request", 401: "Unauthorized", 403: "Forbidden", 404: "Not Found", 405: "Method Not Allowed", 413: "Payload Too Large"}

class Peer extends RefCounted:
	var stream: StreamPeerTCP
	var data := PackedByteArray()
	var seen: int = Time.get_ticks_msec()
	var busy: bool = false

## Set before the node enters the tree to choose the port (0 takes any free one) or to
## keep the game out of the registry. Tests use both.
var requested_port: int = -1
var announce: bool = true

var port: int = 0
var token: String = ""
## "player" for a game someone is playing, "sandbox" for a hidden or QA game an agent
## started for itself.
var role: String = "player"
var launched_by: String = ""
var qa: bool = false
var hidden: bool = false
var started: int = 0
var tools: Node
var recorder: Node
var listener: TCPServer
var peers: Array[Peer] = []
## The tool call now running, and a counter to tell calls apart. One runs at a time.
var running: int = 0
var calls: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var arguments := OS.get_cmdline_user_args()
	qa = "--qa" in arguments or "--capture" in arguments
	hidden = OS.get_environment("SOCOM_LIVE_HIDDEN") == "1" or OS.get_environment("MCP_BACKGROUND") == "1"
	launched_by = OS.get_environment("SOCOM_LIVE_OWNER")
	role = "sandbox" if hidden or qa else "player"
	started = int(Time.get_unix_time_from_system())
	token = OS.get_environment("SOCOM_LIVE_TOKEN")
	if token == "":
		token = Crypto.new().generate_random_bytes(16).hex_encode()
	if OS.get_environment("SOCOM_LIVE_HIDDEN") == "1" and DisplayServer.get_name() != "headless":
		# An agent's own game: no focus, no mouse, off screen.
		for flag: int in [DisplayServer.WINDOW_FLAG_NO_FOCUS, DisplayServer.WINDOW_FLAG_MOUSE_PASSTHROUGH, DisplayServer.WINDOW_FLAG_BORDERLESS]:
			DisplayServer.window_set_flag(flag, true)
		DisplayServer.window_set_position(Vector2i(-9999, -9999))
	recorder = Recorder.new()
	recorder.name = "Recorder"
	add_child(recorder)
	tools = Tools.new()
	tools.name = "Tools"
	tools.server = self
	tools.recorder = recorder
	add_child(tools)
	if not await _listen():
		push_warning("Live link: no free port from %d; this game runs without it." % DEFAULT_PORT)
		return
	if announce:
		_announce()
		print("Live link: http://127.0.0.1:%d/mcp (%s)" % [port, role])
	var restore := OS.get_environment("SOCOM_LIVE_RESTORE")
	if restore != "":
		OS.unset_environment("SOCOM_LIVE_RESTORE")
		tools.resume(restore)

func _exit_tree() -> void:
	close()

## Stops listening and leaves the registry. The port is free as soon as this returns.
func close() -> void:
	if listener != null:
		listener.stop()
		listener = null
	for peer: Peer in peers:
		peer.stream.disconnect_from_host()
	peers.clear()
	if announce and port > 0:
		DirAccess.remove_absolute(_registry_file())

func label() -> String:
	return "%s @%d" % [role, port]

func info() -> Dictionary:
	var s: Node = tools.session()
	return {
		"name": "socom-live",
		"project": ProjectSettings.globalize_path("res://"),
		"port": port,
		"pid": OS.get_process_id(),
		"role": role,
		"launched_by": launched_by,
		"qa": qa,
		"hidden": hidden,
		"started": started,
		"level": str(s.get("current_level")) if s != null else "",
		"focused": get_window().has_focus(),
		"restoring": tools.resuming,
	}

func _listen() -> bool:
	var fixed := requested_port
	var asked := OS.get_environment("SOCOM_LIVE_PORT")
	if fixed < 0 and asked.is_valid_int():
		fixed = asked.to_int()
	listener = TCPServer.new()
	if fixed >= 0:
		# A game restarting in place asks for the port its predecessor is still letting go of.
		for attempt: int in range(25):
			if listener.listen(fixed, "127.0.0.1") == OK:
				port = listener.get_local_port()
				return true
			await get_tree().create_timer(0.2, true, false, true).timeout
		return false
	for candidate: int in range(DEFAULT_PORT, DEFAULT_PORT + PORT_SPAN):
		if not _taken(candidate) and listener.listen(candidate, "127.0.0.1") == OK:
			port = candidate
			return true
	return false

# Whether another game already answers on a port, asked quietly: a failed listen() logs
# an engine error, which would greet every second game with red text.
func _taken(candidate: int) -> bool:
	var probe := StreamPeerTCP.new()
	if probe.connect_to_host("127.0.0.1", candidate) != OK:
		return false
	for attempt: int in range(40):
		probe.poll()
		if probe.get_status() != StreamPeerTCP.STATUS_CONNECTING:
			break
		OS.delay_msec(5)
	var answered := probe.get_status() == StreamPeerTCP.STATUS_CONNECTED
	probe.disconnect_from_host()
	return answered

func _registry_file() -> String:
	return ProjectSettings.globalize_path(REGISTRY.path_join("%d.json" % port))

func _announce() -> void:
	var directory := ProjectSettings.globalize_path(REGISTRY)
	DirAccess.make_dir_recursive_absolute(directory)
	# Keeps Godot from importing the screenshots saved under here.
	var marker := ProjectSettings.globalize_path("res://.agent/.gdignore")
	if not FileAccess.file_exists(marker):
		FileAccess.open(marker, FileAccess.WRITE)
	var entry := info()
	entry["token"] = token
	entry["url"] = "http://127.0.0.1:%d/mcp" % port
	var file := FileAccess.open(_registry_file(), FileAccess.WRITE)
	if file == null:
		push_warning("Live link: could not write %s; agents will not find this game." % _registry_file())
		return
	file.store_string(JSON.stringify(entry, "  "))
	file.close()
	FileAccess.set_unix_permissions(_registry_file(), FileAccess.UNIX_READ_OWNER | FileAccess.UNIX_WRITE_OWNER)

func _process(_delta: float) -> void:
	if listener == null:
		return
	while listener.is_connection_available():
		var peer := Peer.new()
		peer.stream = listener.take_connection()
		peers.append(peer)
	for peer: Peer in peers.duplicate():
		if peer.busy:
			continue
		peer.stream.poll()
		if peer.stream.get_status() != StreamPeerTCP.STATUS_CONNECTED or Time.get_ticks_msec() - peer.seen > IDLE_MS:
			_drop(peer)
			continue
		var waiting := peer.stream.get_available_bytes()
		if waiting > 0:
			peer.data.append_array(peer.stream.get_data(waiting)[1])
			peer.seen = Time.get_ticks_msec()
		var request := _parse(peer.data)
		if not request.is_empty():
			peer.busy = true
			_serve(peer, request)

## A whole HTTP request from the bytes so far, {} while it is still arriving, or
## {"refuse": status} when it is not one this server takes.
func _parse(data: PackedByteArray) -> Dictionary:
	var text := data.slice(0, mini(data.size(), MAX_HEAD)).get_string_from_ascii()
	var split := text.find("\r\n\r\n")
	if split < 0:
		return {"refuse": 400} if data.size() >= MAX_HEAD else {}
	var lines := text.substr(0, split).split("\r\n")
	var opening := lines[0].split(" ")
	if opening.size() < 2:
		return {"refuse": 400}
	var headers: Dictionary = {}
	for index: int in range(1, lines.size()):
		var colon := lines[index].find(":")
		if colon > 0:
			headers[lines[index].substr(0, colon).strip_edges().to_lower()] = lines[index].substr(colon + 1).strip_edges()
	var length := str(headers.get("content-length", "0")).to_int()
	if length > MAX_BODY:
		return {"refuse": 413}
	if data.size() < split + 4 + length:
		return {}
	return {"method": opening[0], "path": opening[1].get_slice("?", 0), "headers": headers, "body": data.slice(split + 4, split + 4 + length).get_string_from_utf8()}

func _serve(peer: Peer, request: Dictionary) -> void:
	if request.has("refuse"):
		_send(peer, request.refuse, {"error": REASONS[request.refuse]})
		return
	if request.path == "/health" and request.method == "GET":
		_send(peer, 200, info())
		return
	if request.path != "/mcp":
		_send(peer, 404, {"error": "This is the SOCOM live link. POST MCP requests to /mcp; GET /health describes the game."})
		return
	if request.method != "POST":
		_send(peer, 405, {"error": "POST one JSON-RPC message per request."}, {"Allow": "POST"})
		return
	var refusal := _refusal(request.headers)
	if refusal != 0:
		_send(peer, refusal, {"error": "Send 'Authorization: Bearer <token>' with the token in .agent/live/%d.json, from this machine, and not from a web page." % port})
		return
	var message: Variant = JSON.parse_string(request.body)
	if not message is Dictionary:
		_send(peer, 400, {"jsonrpc": "2.0", "id": null, "error": {"code": -32700, "message": "The body is not a JSON object."}})
		return
	var job: Dictionary = {"done": false, "reply": null, "call": 0}
	_answer(message, job)
	var deadline := Time.get_ticks_msec() + int(_seconds_allowed(message) * 1000.0)
	while not job.done and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if not job.done:
		# Let the next call through; whatever this one was waiting for is not coming.
		if job.call == running:
			running = 0
		job.reply = _result(message.get("id"), {"content": [{"type": "text", "text": JSON.stringify({"error": "The game did not finish this call in time. `logs` may show a script error that stopped it."})}], "isError": true})
	if job.reply == null:
		_send(peer, 202, null)
	else:
		_send(peer, 200, job.reply)
	if tools.after_reply.is_valid():
		var next: Callable = tools.after_reply
		tools.after_reply = Callable()
		next.call()

func _answer(message: Dictionary, job: Dictionary) -> void:
	job.reply = await handle(message, job)
	job.done = true

## Answers one JSON-RPC message. A notification (no id) gets null.
func handle(message: Dictionary, job: Dictionary = {}) -> Variant:
	var id: Variant = Codec.whole_numbers(message.get("id"))
	var method := str(message.get("method", ""))
	var params: Dictionary = message.get("params") if message.get("params") is Dictionary else {}
	if id == null:
		return null
	match method:
		"initialize":
			var wanted := str(params.get("protocolVersion", ""))
			return _result(id, {
				"protocolVersion": wanted if wanted in PROTOCOLS else PROTOCOLS[1],
				"capabilities": {"tools": {}},
				"serverInfo": {"name": "socom-live", "title": "SOCOM live game", "version": "1.0.0"},
				"instructions": "The running SOCOM game (%s). state and telemetry read it; tuning_set, setup, play, time, set, call and eval change it; reload and restart bring in edited code. Positions are metres [x, y, z], angles degrees, frames 1/60 s ticks." % label(),
			})
		"ping":
			return _result(id, {})
		"tools/list":
			return _result(id, {"tools": manifest()})
		"tools/call":
			var arguments: Dictionary = params.get("arguments") if params.get("arguments") is Dictionary else {}
			while running != 0:
				await get_tree().process_frame
			calls += 1
			var mine := calls
			running = mine
			job["call"] = mine
			var answer: Dictionary = await tools.call_tool(str(params.get("name", "")), arguments)
			if running == mine:
				running = 0
			return _result(id, answer)
	return {"jsonrpc": "2.0", "id": id, "error": {"code": -32601, "message": "Method not found: %s" % method}}

## The tool list from tools.json, read each time so an edit shows without a restart.
func manifest() -> Array:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if not parsed is Dictionary or not parsed.get("tools") is Array:
		push_warning("Live link: %s is not valid JSON with a \"tools\" list." % MANIFEST)
		return []
	return parsed.tools

func _seconds_allowed(message: Dictionary) -> float:
	var params: Variant = message.get("params")
	if message.get("method") != "tools/call" or not params is Dictionary:
		return 15.0
	return tools.seconds_allowed(str(params.get("name", "")), params.get("arguments") if params.get("arguments") is Dictionary else {})

func _refusal(headers: Dictionary) -> int:
	# A browser always names the page a cross-site request came from; nothing else does.
	if headers.has("origin"):
		return 403
	if not str(headers.get("host", "")).get_slice(":", 0) in ["127.0.0.1", "localhost"]:
		return 403
	if str(headers.get("authorization", "")) != "Bearer " + token:
		return 401
	return 0

func _result(id: Variant, result: Dictionary) -> Dictionary:
	return {"jsonrpc": "2.0", "id": Codec.whole_numbers(id), "result": result}

func _send(peer: Peer, status: int, body: Variant, extra: Dictionary = {}) -> void:
	var payload := PackedByteArray() if body == null else JSON.stringify(body).to_utf8_buffer()
	var head := "HTTP/1.1 %d %s\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n" % [status, REASONS.get(status, "OK"), payload.size()]
	for key: String in extra:
		head += "%s: %s\r\n" % [key, extra[key]]
	peer.stream.put_data((head + "\r\n").to_utf8_buffer())
	if not payload.is_empty():
		peer.stream.put_data(payload)
	_drop(peer)

func _drop(peer: Peer) -> void:
	peer.stream.disconnect_from_host()
	peers.erase(peer)
