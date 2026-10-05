extends Node
## What the live link can do to the running game. Each tool in tools.json is answered by
## the method here named `_tool_<name>`; tests/live_regression.gd keeps the two lists equal.
##
## A tool takes its arguments as a Dictionary and returns one. An "error" key marks a
## failure, and "_images" (PNG bytes) is sent as pictures rather than text.
##
## Nothing here is typed against the game's own classes, so this file still loads when a
## gameplay script does not compile, and the link can say why. Setting up and driving the
## game is left to tools/agent/harness.gd, the same code the screenshot tooling uses.

const Codec := preload("res://scripts/live/live_codec.gd")
const HARNESS := "res://tools/agent/harness.gd"
const OUTPUT := "res://.agent/live"
const DEFAULTS: Dictionary = {
	"movement": "res://resources/movement/default_movement.tres",
	"camera": "res://resources/camera/default_camera.tres",
}
const WATCHED: Array[String] = ["gd", "tres", "tscn", "gdshader"]
## Outside views of a target: degrees around it from behind, and degrees above the horizon.
const VIEWS: Dictionary = {"back": [0.0, 12.0], "front": [180.0, 8.0], "left": [-90.0, 6.0], "right": [90.0, 6.0], "top": [0.0, 89.0], "quarter": [140.0, 18.0], "orbit": [0.0, 12.0]}
const ACTOR_GROUP := &"combat_actors"
const KEPT_SHOTS := 200

var server: Node
var recorder: Node
## The speed of time the agent asked for. Stepping the game puts the engine back to
## normal speed, so it is applied again afterwards.
var time_scale: float = 1.0
var held: bool = false
var stamps: Dictionary = {}
var studio: SubViewport
var studio_camera: Camera3D
var banner: Label
var shots: int = 0
## Something to do once the current answer has been sent, such as restarting.
var after_reply := Callable()
## True from a restart until the player is back where they were.
var resuming: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	stamps = _scan()
	var layer := CanvasLayer.new()
	layer.layer = 90
	add_child(layer)
	banner = Label.new()
	banner.visible = false
	banner.add_theme_font_size_override("font_size", 14)
	banner.add_theme_color_override("font_color", Color("e8cf8a"))
	banner.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	banner.add_theme_constant_override("outline_size", 5)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	banner.position.y = 64.0
	layer.add_child(banner)

func _input(event: InputEvent) -> void:
	# A frozen game does not hear its own pause key, so the player could not get out.
	if held and get_tree().paused and InputMap.has_action("pause") and event.is_action_pressed("pause"):
		get_tree().paused = false
		held = false
		_show_banner()
		get_viewport().set_input_as_handled()

func session() -> Node:
	for node: Node in get_tree().root.get_children():
		if node.has_method("load_level") and node.get("player") != null:
			return node
	return null

func call_tool(tool: String, arguments: Dictionary) -> Dictionary:
	var method := "_tool_" + tool
	if not has_method(method):
		return _reply({"error": "Unknown tool '%s'." % tool})
	var mark: int = recorder.log_mark()
	var data: Variant = await call(method, arguments)
	if not data is Dictionary:
		data = {"error": "The tool stopped on a script error before it could answer."}
	# Errors the game raised while the tool ran belong with its answer.
	var raised: Array = recorder.logged(mark, "errors", 6)
	if not raised.is_empty():
		data["script_errors"] = raised
	return _reply(data)

## How long a call may take before the server gives up on it, in real seconds.
func seconds_allowed(tool: String, arguments: Dictionary) -> float:
	var ticks := 0.0
	match tool:
		"play":
			ticks = 900.0 * arguments.walk_to.size() if arguments.get("walk_to") is Array else float(arguments.get("frames", 60))
			ticks /= clampf(float(arguments.get("speed", 4.0 if arguments.has("walk_to") else 1.0)), 1.0, 8.0)
		"filmstrip":
			ticks = float(arguments.get("frames", 8)) * (float(arguments.get("every", 6)) + 2.0)
		"time":
			ticks = float(arguments.get("step", 0))
		"setup":
			ticks = 120.0 + float(arguments.get("settle", 8))
	return 45.0 + ticks / 60.0 / clampf(time_scale, 0.05, 1.0) * 1.5

func _reply(data: Dictionary) -> Dictionary:
	var pictures: Array = data.get("_images", [])
	data.erase("_images")
	var content: Array = [{"type": "text", "text": JSON.stringify(data)}]
	for picture: PackedByteArray in pictures:
		content.append({"type": "image", "data": Marshalls.raw_to_base64(picture), "mimeType": "image/png"})
	return {"content": content, "isError": data.has("error")}

# ---- Looking ----

func _tool_state(_arguments: Dictionary) -> Dictionary:
	var missing := _missing()
	if not missing.is_empty():
		return missing
	var data: Dictionary = _harness().state(get_tree())
	data["game"] = server.label()
	data["window_focused"] = get_window().has_focus()
	if not is_equal_approx(Engine.time_scale, 1.0):
		data["time_scale"] = snappedf(Engine.time_scale, 0.01)
	return data

func _tool_telemetry(arguments: Dictionary) -> Dictionary:
	return recorder.summary(float(arguments.get("seconds", 10.0)), clampi(int(arguments.get("samples", 0)), 0, 600))

func _tool_logs(arguments: Dictionary) -> Dictionary:
	var lines: Array = recorder.logged(0, str(arguments.get("level", "all")), clampi(int(arguments.get("limit", 40)), 1, 200))
	if arguments.has("seconds"):
		var newest := float(arguments.seconds)
		lines = lines.filter(func(line: Dictionary) -> bool: return line.ago <= newest)
	if arguments.get("clear", false):
		recorder.clear_log()
	return {"lines": lines}

func _tool_screenshot(arguments: Dictionary) -> Dictionary:
	var frame := await _frame(arguments)
	if frame.has("error"):
		return frame
	var image: Image = frame.image
	var data: Dictionary = {"png": _save(image, "shot"), "size": [image.get_width(), image.get_height()], "view": frame.view}
	if arguments.get("inline", true):
		data["_images"] = [image.save_png_to_buffer()]
	return data

func _tool_filmstrip(arguments: Dictionary) -> Dictionary:
	var count := clampi(int(arguments.get("frames", 8)), 2, 16)
	var every := clampi(int(arguments.get("every", 6)), 1, 120)
	var input: Dictionary = arguments.get("input", {}) if arguments.get("input") is Dictionary else {}
	var driving := not input.is_empty()
	var tree := get_tree()
	var h: GDScript = _harness()
	if driving:
		var missing := _missing()
		if not missing.is_empty():
			return missing
	var frozen := tree.paused
	var menu_was_open := false
	var pressed: Array = []
	var taps: Array = input.get("tap", [])
	if driving:
		menu_was_open = _open_world()
		h._prepare(session())
		h._axis("move_forward", "move_back", float(input.get("forward", 0.0)))
		h._axis("move_right", "move_left", float(input.get("right", 0.0)))
		pressed = input.get("hold", []) + taps
		for action: String in pressed:
			h._send(action, true)
	tree.paused = false
	var turn := deg_to_rad(float(input.get("turn", 0.0))) / 60.0
	var tiles: Array[Image] = []
	var ticks: Array[int] = []
	var first := Engine.get_physics_frames()
	var failure: Dictionary = {}
	var view := ""
	for index: int in range(count):
		var frame := await _frame(arguments)
		if frame.has("error"):
			failure = frame
			break
		view = frame.view
		tiles.append(frame.image)
		ticks.append(Engine.get_physics_frames() - first)
		if index == count - 1:
			break
		for tick: int in range(every):
			await tree.physics_frame
			if index == 0 and tick == 2:
				for action: String in taps:
					h._send(action, false)
			if turn != 0.0 and session() != null:
				session().player.turn(turn)
	if driving:
		h._axis("move_forward", "move_back", 0.0)
		h._axis("move_right", "move_left", 0.0)
		for action: String in pressed:
			h._send(action, false)
		await h._settle_input(tree, frozen)
		_close_world(menu_was_open, {})
	tree.paused = frozen
	if not failure.is_empty():
		return failure
	var columns := clampi(int(arguments.get("columns", 4)), 1, count)
	var tile := Vector2i(320, roundi(320.0 * tiles[0].get_height() / tiles[0].get_width()))
	var sheet := Image.create_empty(tile.x * columns, tile.y * ceili(float(count) / columns), false, tiles[0].get_format())
	for index: int in range(count):
		tiles[index].resize(tile.x, tile.y, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(tiles[index], Rect2i(Vector2i.ZERO, tile), Vector2i(index % columns, index / columns) * tile)
	var data: Dictionary = {"png": _save(sheet, "strip"), "view": view, "frames": count, "columns": columns, "order": "left to right, then down", "tick_of_each_frame": ticks}
	if driving:
		data["player"] = h.state(tree).player
	if arguments.get("inline", true):
		data["_images"] = [sheet.save_png_to_buffer()]
	return data

func _tool_inspect(arguments: Dictionary) -> Dictionary:
	var found := _resolve(str(arguments.get("path", "session")))
	if not found[0]:
		return {"error": found[1]}
	var target: Object = found[1]
	var data := _outline(target, clampi(int(arguments.get("depth", 1)), 0, 6))
	var props: Variant = arguments.get("props")
	if props is String and props == "all":
		data["values"] = Codec.script_values(target, 1)
	elif props is Array:
		var values: Dictionary = {}
		for path: Variant in props:
			var read := Codec.read_path(target, str(path))
			values[str(path)] = Codec.encode(read[1], 1) if read[0] else "(%s)" % read[1]
		data["values"] = values
	else:
		var names: Dictionary = {}
		for property: Dictionary in target.get_property_list():
			if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
				names[property.name] = type_string(property.type) if property.type != TYPE_NIL else "any"
		if not names.is_empty():
			data["vars"] = names
	return data

# ---- Tuning ----

func _tool_tuning_get(arguments: Dictionary) -> Dictionary:
	if session() == null:
		return _no_session()
	var sections := _sections()
	var active: String = sections.weapon.key
	var wanted := str(arguments.get("section", "")).to_lower()
	var names: Array = []
	match wanted:
		"":
			names = ["movement", "camera", active]
		"all", "weapons":
			names = ["movement", "camera"] if wanted == "all" else []
			for key: String in sections:
				if key.begins_with("weapon") and key != "weapon":
					names.append(key)
		"weapon":
			names = [active]
		_:
			if not sections.has(wanted):
				return {"error": "No tuning section '%s'. Sections: %s." % [wanted, ", ".join(sections.keys())]}
			names = [wanted]
	var data: Dictionary = {}
	for key: String in names:
		data[key] = _describe(sections[key], key == active)
	if not server.qa:
		data["note"] = "This game also loads the player's saved F1-menu values (user://prototype_settings.cfg) over the defaults."
	return data

func _tool_tuning_set(arguments: Dictionary) -> Dictionary:
	var s := session()
	if s == null:
		return _no_session()
	var applied: Dictionary = {}
	var refused: Dictionary = {}
	if arguments.get("reset", false):
		s.reset_tuning()
		applied["reset"] = "every value is back to its default"
	var sections := _sections()
	var changes: Dictionary = arguments.get("changes", {}) if arguments.get("changes") is Dictionary else {}
	for key: String in changes:
		var section := key.get_slice(".", 0).to_lower()
		var property := key.substr(section.length() + 1)
		if not sections.has(section) or property == "":
			refused[key] = "name it movement.<value>, camera.<value>, weapon.<value> (the weapon in hand) or weapon<slot>.<value>"
			continue
		var entry: Dictionary = sections[section]
		var live: Resource = entry.live
		if not _tunable(live).has(property):
			refused[key] = "%s has no value '%s'; tuning_get lists them" % [section, property]
			continue
		var before: Variant = live.get(property)
		var value: Variant = changes[key]
		if value == null:
			if entry.file == "":
				refused[key] = "this weapon has no default file to return to"
				continue
			value = load(entry.file).get(property)
			if typeof(value) in Codec.LIST_TYPES:
				value = value.duplicate()
		else:
			var decoded := Codec.decode(value, before)
			if not decoded[0]:
				refused[key] = decoded[1]
				continue
			value = decoded[1]
		live.set(property, value)
		applied[key] = {"from": Codec.encode(before), "to": Codec.encode(live.get(property))}
	if not applied.is_empty():
		if s.get("hud") != null and s.hud.has_method("refresh_settings"):
			s.hud.refresh_settings()
		var told: Array = []
		for key: String in applied:
			told.append("%s %s → %s" % [key.get_slice(".", 1), str(applied[key].from), str(applied[key].to)] if applied[key] is Dictionary else "tuning reset")
		_notice(", ".join(told.slice(0, 2)) + (" +%d more" % (told.size() - 2) if told.size() > 2 else ""))
	var data: Dictionary = {"applied": applied}
	if not refused.is_empty():
		data["refused"] = refused
		if applied.is_empty():
			data["error"] = "Nothing was changed."
	return data

func _tool_tuning_save(arguments: Dictionary) -> Dictionary:
	if session() == null:
		return _no_session()
	var sections := _sections()
	var active: String = sections.weapon.key
	sections.erase("weapon")
	var wanted: Array = arguments.get("sections", []) if arguments.get("sections") is Array else []
	var dry: bool = arguments.get("dry_run", false)
	var written: Dictionary = {}
	var skipped: Dictionary = {}
	for key: String in sections:
		if not wanted.is_empty() and not key in wanted and not (key == active and "weapon" in wanted):
			continue
		var entry: Dictionary = sections[key]
		var live: Resource = entry.live
		if entry.file == "":
			if not wanted.is_empty():
				skipped[key] = "taken from a body, so it has no default file here"
			continue
		var base: Resource = load(entry.file)
		var changed: Dictionary = {}
		for property: String in _tunable(live):
			var value: Variant = live.get(property)
			if JSON.stringify(Codec.encode(base.get(property))) == JSON.stringify(Codec.encode(value)):
				continue
			changed[property] = {"from": Codec.encode(base.get(property)), "to": Codec.encode(value)}
			if not dry:
				# The loaded default is the one "restore defaults" copies, so it changes too.
				base.set(property, value.duplicate() if typeof(value) in Codec.LIST_TYPES else value)
		if changed.is_empty():
			continue
		if not dry:
			var problem := ResourceSaver.save(base, entry.file)
			if problem != OK:
				skipped[key] = "could not write %s: %s" % [entry.file, error_string(problem)]
				continue
		written[entry.file] = changed
	var data: Dictionary = {("would_write" if dry else "written"): written}
	if not skipped.is_empty():
		data["skipped"] = skipped
	if written.is_empty():
		data["note"] = "No live value differs from the defaults on disk."
	elif not dry:
		_notice("saved tuning to %d default file%s" % [written.size(), "" if written.size() == 1 else "s"])
	return data

# ---- Changing ----

func _tool_setup(arguments: Dictionary) -> Dictionary:
	var missing := _missing()
	if not missing.is_empty():
		return missing
	var spec := arguments.duplicate(true)
	var title := str(spec.get("scenario", ""))
	spec.erase("scenario")
	var h: GDScript = _harness()
	var menu_was_open := _open_world()
	var result: Dictionary
	if title != "":
		result = await h.scenario(get_tree(), title, spec)
	else:
		result = await h.apply(get_tree(), spec)
	_close_world(menu_was_open and not spec.has("menu"), result)
	return result

func _tool_play(arguments: Dictionary) -> Dictionary:
	var missing := _missing()
	if not missing.is_empty():
		return missing
	var h: GDScript = _harness()
	var menu_was_open := _open_world()
	var result: Dictionary
	if arguments.get("walk_to") is Array:
		result = await h.walk_to(get_tree(), arguments.walk_to, float(arguments.get("speed", 4.0)))
	else:
		result = await h.step(get_tree(), int(arguments.get("frames", 60)), arguments)
	_close_world(menu_was_open, result)
	return result

func _tool_time(arguments: Dictionary) -> Dictionary:
	var tree := get_tree()
	if arguments.has("scale"):
		time_scale = clampf(float(arguments.scale), 0.05, 8.0)
		Engine.time_scale = time_scale
	if arguments.has("frozen"):
		tree.paused = bool(arguments.frozen)
	if arguments.has("step"):
		tree.paused = false
		# One more wait than ticks: the signal comes at the start of each tick.
		for index: int in range(clampi(int(arguments.step), 1, 3600) + 1):
			await tree.physics_frame
		tree.paused = true
	held = tree.paused
	_show_banner()
	recorder.note("AI: time %s, x%s" % ["frozen" if tree.paused else "running", str(snappedf(Engine.time_scale, 0.01))])
	return {"frozen": tree.paused, "scale": snappedf(Engine.time_scale, 0.01), "tick": Engine.get_physics_frames()}

func _tool_set(arguments: Dictionary) -> Dictionary:
	var found := _resolve(str(arguments.get("path", "session")))
	if not found[0]:
		return {"error": found[1]}
	var values: Dictionary = arguments.get("values", {}) if arguments.get("values") is Dictionary else {}
	var changed: Dictionary = {}
	var refused: Dictionary = {}
	for key: String in values:
		var wrote := Codec.write_path(found[1], key, values[key])
		if wrote[0]:
			changed[key] = {"from": Codec.encode(wrote[1], 0), "to": Codec.encode(wrote[2], 0)}
		else:
			refused[key] = wrote[1]
	if not changed.is_empty():
		recorder.note("AI: set %s on %s" % [", ".join(changed.keys()), str(arguments.get("path", "session"))])
	var data: Dictionary = {"changed": changed}
	if not refused.is_empty():
		data["refused"] = refused
		if changed.is_empty():
			data["error"] = "Nothing was changed."
	return data

func _tool_call(arguments: Dictionary) -> Dictionary:
	var found := _resolve(str(arguments.get("path", "session")))
	if not found[0]:
		return {"error": found[1]}
	var target: Object = found[1]
	var method := str(arguments.get("method", ""))
	if not target.has_method(method):
		return {"error": "%s has no method '%s'." % [Codec.title(target), method]}
	var given: Array = Codec.whole_numbers(arguments.get("args", [])) if arguments.get("args") is Array else []
	recorder.note("AI: called %s.%s" % [str(arguments.get("path", "session")), method])
	var result: Variant = await target.callv(method, given)
	return {"result": Codec.encode(result, 2)}

func _tool_eval(arguments: Dictionary) -> Dictionary:
	var code := str(arguments.get("code", "")).strip_edges(false, true)
	if code.strip_edges() == "":
		return {"error": "No code given."}
	var s := session()
	var scope: Array = [self, s, s.player if s != null else null, s.level if s != null else null, get_tree()]
	recorder.note("AI: ran code")
	# One line is tried as an expression first: it hands back its value, and it reports a
	# mistake as text instead of an engine error. Anything else is compiled as statements.
	if not "\n" in code.strip_edges():
		var expression := Expression.new()
		if expression.parse(code.strip_edges(), ["live", "session", "player", "level", "tree"]) == OK:
			var value: Variant = expression.execute(scope, self, false)
			if expression.has_execute_failed():
				return {"error": expression.get_error_text()}
			if value is Object and value.get_class() == "GDScriptFunctionState":
				value = await value
			return {"result": Codec.encode(value, 2)}
	var source := "extends RefCounted\n\nfunc run(live: Node, session: Node, player: Node, level: Node, tree: SceneTree) -> Variant:\n"
	for line: String in code.split("\n"):
		source += "\t" + line + "\n"
	source += "\treturn null\n"
	var mark: int = recorder.log_mark()
	var script := GDScript.new()
	script.source_code = source
	if script.reload() != OK:
		var problems: Array = []
		for entry: Dictionary in recorder.logged(mark, "errors", 4):
			# The snippet starts three lines into the script built around it.
			var where := str(entry.get("where", ":0"))
			problems.append("line %d: %s" % [maxi(where.get_slice(":", where.get_slice_count(":") - 1).to_int() - 3, 1), entry.text])
		return {"error": "The code did not compile.", "problems": problems}
	var runner: RefCounted = script.new()
	var result: Variant = await runner.run(scope[0], scope[1], scope[2], scope[3], scope[4])
	return {"result": Codec.encode(result, 2)}

func _tool_reload(arguments: Dictionary) -> Dictionary:
	var now := _scan()
	var targets: Array[String] = []
	if arguments.get("paths") is Array and not arguments.paths.is_empty():
		for item: Variant in arguments.paths:
			var path := str(item)
			targets.append(path if "://" in path else "res://" + path.trim_prefix("/"))
	else:
		for path: String in now:
			if now[path] != stamps.get(path, -1):
				targets.append(path)
	if targets.is_empty():
		return {"reloaded": [], "note": "Nothing on disk is newer than what the game loaded."}
	var reloaded: Array[String] = []
	var failed: Dictionary = {}
	var others: Dictionary = {}
	var seeded: Dictionary = {}
	var pending: Array[String] = []
	for path: String in targets:
		if path.get_extension() == "gd":
			pending.append(path)
	# A script can fail only because one it leans on was not reloaded yet, so go round again.
	for attempt: int in range(3):
		var again: Array[String] = []
		for path: String in pending:
			var outcome := _reload_script(path)
			if outcome.has("error"):
				again.append(path)
				failed[path] = outcome.error
				continue
			failed.erase(path)
			stamps[path] = now.get(path, 0)
			if outcome.status == "reloaded":
				reloaded.append(path)
			else:
				others[path] = outcome.status
			if not outcome.get("new_vars", []).is_empty():
				seeded[path] = outcome.new_vars
		if again.is_empty() or again.size() == pending.size():
			break
		pending = again
	for path: String in targets:
		if path.get_extension() == "gd":
			continue
		if not FileAccess.file_exists(path):
			others[path] = "no such file"
		elif not ResourceLoader.has_cached(path):
			others[path] = "not loaded yet; its next load reads the new file"
		elif ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) != null:
			others[path] = "refreshed"
		else:
			failed[path] = "did not load"
		stamps[path] = now.get(path, 0)
	var data: Dictionary = {"reloaded": reloaded}
	if not failed.is_empty():
		data["failed"] = failed
	if not others.is_empty():
		data["others"] = others
	var notes: Array[String] = []
	if not seeded.is_empty():
		data["new_variables"] = seeded
		notes.append("New variables were given their declared default where the engine knows it; code in _ready that sets them up has not run. restart if something depends on that.")
	if others.values().has("refreshed"):
		notes.append("A refreshed scene or resource is used the next time it is instanced or copied: setup {\"level\": ..., \"reload\": true} rebuilds the level, and tuning_set {\"reset\": true} re-reads tuning defaults.")
	if not notes.is_empty():
		data["notes"] = notes
	if not reloaded.is_empty():
		var names: Array[String] = []
		for path: String in reloaded.slice(0, 3):
			names.append(path.get_file())
		_notice("reloaded %s" % ", ".join(names))
	if reloaded.is_empty() and not failed.is_empty():
		data["error"] = "Nothing was reloaded."
	return data

func _tool_restart(arguments: Dictionary) -> Dictionary:
	var keep: Dictionary = {}
	if arguments.get("restore", true) and _missing().is_empty():
		keep = _snapshot()
	var path := ProjectSettings.globalize_path(OUTPUT.path_join("restore-%d.json" % server.port))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"error": "Could not write %s." % path}
	file.store_string(JSON.stringify(keep))
	file.close()
	after_reply = _relaunch.bind(path)
	return {"restarting": true, "port": server.port, "restores": keep.keys()}

# ---- Restarting in place ----

func _snapshot() -> Dictionary:
	var state: Dictionary = _harness().state(get_tree())
	var keep: Dictionary = {"level": state.level, "pos": state.player.pos, "yaw": state.player.yaw, "pitch": state.player.pitch, "stance": state.player.stance, "class": state["class"], "weapon": state.weapon.slot}
	var tuning: Dictionary = {}
	var sections := _sections()
	for key: String in ["movement", "camera", "weapon"]:
		var entry: Dictionary = sections[key]
		if entry.file == "":
			continue
		var base: Resource = load(entry.file)
		for property: String in _tunable(entry.live):
			var value: Variant = Codec.encode(entry.live.get(property))
			if JSON.stringify(value) != JSON.stringify(Codec.encode(base.get(property))) and not value is Array:
				tuning.get_or_add(key, {})[property] = value
	if not tuning.is_empty():
		keep["tuning"] = tuning
	return keep

func _relaunch(restore: String) -> void:
	server.close()
	OS.set_environment("SOCOM_LIVE", "1")
	OS.set_environment("SOCOM_LIVE_PORT", str(server.port))
	OS.set_environment("SOCOM_LIVE_RESTORE", restore)
	OS.set_environment("SOCOM_AGENT_QA", "1" if server.qa else "0")
	# Come back in front only if the player was looking at the game when it went away.
	OS.set_environment("SOCOM_AGENT_SHOW", "1" if get_window().has_focus() else "0")
	var launcher := ProjectSettings.globalize_path("res://tools/agent/godot")
	var passed: Array[String] = ["--path", ProjectSettings.globalize_path("res://")]
	var given := OS.get_cmdline_args()
	for index: int in range(given.size() - 1):
		if given[index] == "--log-file":
			passed.append_array([given[index], given[index + 1]])
	if FileAccess.file_exists(launcher) and OS.get_name() != "Windows":
		OS.create_process(launcher, passed)
	else:
		if server.qa:
			passed.append_array(["--", "--qa"])
		OS.set_restart_on_exit(true, passed)
	get_tree().quit()

## Puts the game back the way a restart left it. Called by the server when it starts
## with a restore file.
func resume(path: String) -> void:
	resuming = true
	var text := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
	DirAccess.remove_absolute(path)
	var keep: Variant = JSON.parse_string(text) if text != "" else null
	if keep is Dictionary and not keep.is_empty():
		for index: int in range(240):
			await get_tree().physics_frame
			if index >= 30 and _missing().is_empty():
				break
		if _missing().is_empty():
			var menu_was_open := _open_world()
			var result: Dictionary = await _harness().apply(get_tree(), keep)
			_close_world(menu_was_open, result)
			_notice("restarted on the new code")
	resuming = false

# ---- Helpers ----

func _harness() -> GDScript:
	var script := load(HARNESS) as GDScript
	return script if script != null and script.can_instantiate() else null

func _no_session() -> Dictionary:
	return {"error": "The game's main scene (scenes/main.tscn) is not running here. `logs` shows why if it failed to load."}

func _missing() -> Dictionary:
	if session() == null:
		return _no_session()
	if _harness() == null:
		return {"error": "tools/agent/harness.gd did not load, so state, setup and play are unavailable; `logs` has the reason. inspect, set, call and eval still work."}
	return {}

## Makes the world run for a tool that has to move things in it, and says whether the
## menu was open so it can be put back.
func _open_world() -> bool:
	var s := session()
	# The harness mutes the game and caps its frame rate the first time it is used. That
	# suits an agent's own hidden game, not one a person is playing.
	if server.role == "player":
		s.set_meta(&"agent_ready", true)
	var menu_was_open: bool = s.get("modal") == true
	if menu_was_open:
		s.set_modal(false)
	return menu_was_open

func _close_world(reopen_menu: bool, result: Dictionary) -> void:
	Engine.time_scale = time_scale
	var s := session()
	if reopen_menu and s != null and s.get("modal") == false:
		s.set_modal(true)
		if result.has("menu"):
			result["menu"] = true

func _notice(text: String) -> void:
	recorder.note("AI: " + text)
	var s := session()
	if server.role == "player" and s != null and s.get("hud") != null and s.hud.has_method("notify"):
		s.hud.notify("AI · " + text)

func _show_banner() -> void:
	if held and get_tree().paused:
		banner.text = "HELD BY AI  ·  ESC RESUMES"
	elif not is_equal_approx(Engine.time_scale, 1.0):
		banner.text = "AI  ·  TIME ×%s" % str(snappedf(Engine.time_scale, 0.01))
	else:
		banner.text = ""
	banner.visible = banner.text != ""

## Finds what a tool's `path` names. Returns [true, object] or [false, reason].
func _resolve(path: String) -> Array:
	var text := path.strip_edges()
	if text == "":
		text = "session"
	var where := text
	var chain := ""
	var dot := text.find(".")
	if dot >= 0:
		where = text.substr(0, dot)
		chain = text.substr(dot + 1)
	var s := session()
	var p: Node = s.player if s != null else null
	var base: Object = null
	if where.begins_with("/"):
		base = get_tree().root.get_node_or_null(where)
	else:
		var head := where.get_slice("/", 0)
		var rest := where.substr(head.length() + 1)
		match head.to_lower():
			"session":
				base = s
			"player":
				base = p
			"weapon":
				base = p.get("weapon") if p != null else null
			"camera":
				base = p.get("camera_rig") if p != null else null
			"soldier":
				base = p.get("soldier") if p != null else null
			"hud":
				base = s.get("hud") if s != null else null
			"level":
				base = s.get("level") if s != null else null
			"root":
				base = get_tree().root
			"live":
				base = self
			_:
				rest = ""
				if head.to_lower().begins_with("actor:"):
					base = _actor(where.substr(6))
				else:
					for origin: Variant in [s, s.get("level") if s != null else null, get_tree().root]:
						if base == null and origin is Node:
							base = origin.get_node_or_null(where)
					if base == null and not "/" in where:
						base = get_tree().root.find_child(where, true, false)
		if base is Node and rest != "":
			base = base.get_node_or_null(rest)
	if base == null or not is_instance_valid(base):
		return [false, "Nothing at '%s'. Use session, player, weapon, camera, soldier, hud, level, actor:<NAME>, root, a node path such as level/Targets/Target10, or a node's name; add .property to reach an object a variable holds." % path]
	if chain != "":
		var read := Codec.read_path(base, chain)
		if not read[0]:
			return read
		if not read[1] is Object or not is_instance_valid(read[1]):
			return [false, "'%s' is a %s, not an object. Name the object that owns it and ask for the value in props or values." % [path, type_string(typeof(read[1]))]]
		base = read[1]
	return [true, base]

func _actor(title: String) -> Node:
	for actor: Node in get_tree().get_nodes_in_group(ACTOR_GROUP):
		var known: Variant = actor.get_meta(&"display_name") if actor.has_meta(&"display_name") else actor.get("display_name")
		if str(known if known != null else actor.name).to_lower() == title.strip_edges().to_lower():
			return actor
	return null

func _outline(target: Object, depth: int) -> Dictionary:
	var data: Dictionary = {"class": target.get_class()}
	var script: Variant = target.get_script()
	if script is Script and script.resource_path != "":
		data["script"] = script.resource_path
	if target is Resource and target.resource_path != "":
		data["resource_path"] = target.resource_path
	if target is Node:
		data["path"] = str(target.get_path())
		if target is Node3D:
			data["position"] = Codec.encode(target.global_position)
			data["rotation_deg"] = Codec.encode(target.global_rotation_degrees)
			data["visible"] = target.visible
		elif target is CanvasItem:
			data["visible"] = target.visible
		if target.get_child_count() > 0:
			if depth > 0:
				data["children"] = _children(target, depth)
			else:
				data["child_count"] = target.get_child_count()
	return data

func _children(parent: Node, depth: int) -> Array:
	var listed: Array = []
	for child: Node in parent.get_children():
		if listed.size() >= 80:
			listed.append("... %d more" % (parent.get_child_count() - 80))
			break
		var entry: Dictionary = {"name": str(child.name), "class": Codec.title(child)}
		if child.get_child_count() > 0:
			if depth > 1:
				entry["children"] = _children(child, depth - 1)
			else:
				entry["child_count"] = child.get_child_count()
		listed.append(entry)
	return listed

## The tuning profiles the game is running with: the live copy, the default file it was
## copied from, and for weapons the slot. "weapon" is the one in hand.
func _sections() -> Dictionary:
	var p: Node = session().player
	var weapon: Node = p.weapon
	var found: Dictionary = {
		"movement": {"key": "movement", "live": p.movement, "file": DEFAULTS.movement},
		"camera": {"key": "camera", "live": p.camera_settings, "file": DEFAULTS.camera},
	}
	var issued: Array = weapon.soldier_class.weapons()
	for slot: int in range(weapon.profiles.size()):
		var live: Resource = weapon.profiles[slot]
		# A weapon taken from a body is not the one this class was issued.
		var file: String = issued[slot].resource_path if slot < issued.size() and issued[slot].display_name == live.display_name else ""
		found["weapon%d" % slot] = {"key": "weapon%d" % slot, "live": live, "file": file, "name": live.display_name}
	found["weapon"] = found["weapon%d" % weapon.active_slot]
	return found

## The exported variables of a tuning profile, by name.
func _tunable(profile: Resource) -> Dictionary:
	var found: Dictionary = {}
	for property: Dictionary in profile.get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and property.usage & PROPERTY_USAGE_STORAGE:
			found[property.name] = property
	return found

func _describe(entry: Dictionary, in_hand: bool) -> Dictionary:
	var live: Resource = entry.live
	var base: Resource = load(entry.file) if entry.file != "" else null
	var values: Dictionary = {}
	var changed: Dictionary = {}
	var ranges: Dictionary = {}
	var listed := _tunable(live)
	for property: String in listed:
		var value: Variant = Codec.encode(live.get(property))
		values[property] = value
		if base != null:
			var original: Variant = Codec.encode(base.get(property))
			if JSON.stringify(original) != JSON.stringify(value):
				changed[property] = {"default": original, "live": value}
		if listed[property].hint == PROPERTY_HINT_RANGE:
			var limits: PackedStringArray = listed[property].hint_string.split(",")
			if limits.size() >= 2:
				ranges[property] = [limits[0].to_float(), limits[1].to_float()]
	var data: Dictionary = {}
	if entry.has("name"):
		data["name"] = entry.name
		data["in_hand"] = in_hand
	data["default_file"] = entry.file if entry.file != "" else null
	data["values"] = values
	if not changed.is_empty():
		data["changed"] = changed
	if not ranges.is_empty():
		data["ranges"] = ranges
	return data

## One picture: {"image", "view"} or {"error"}.
func _frame(arguments: Dictionary) -> Dictionary:
	if DisplayServer.get_name() == "headless":
		return {"error": "This game is running headless and draws nothing. Use one with a window: game_launch, or the player's own."}
	var view := str(arguments.get("view", "player")).to_lower()
	var image: Image
	if view == "player":
		banner.visible = false
		await _drawn()
		image = get_tree().root.get_texture().get_image()
		_show_banner()
	elif VIEWS.has(view):
		var focus: Vector3
		var heading := 0.0
		if arguments.get("at") is Array and arguments.at.size() >= 3:
			focus = Vector3(arguments.at[0], arguments.at[1], arguments.at[2])
		else:
			var found := _resolve(str(arguments.get("target", "player")))
			if not found[0]:
				return {"error": found[1]}
			if not found[1] is Node3D:
				return {"error": "The target of an outside view has to be a 3D node; '%s' is a %s." % [str(arguments.get("target")), found[1].get_class()]}
			focus = found[1].global_position + Vector3.UP * float(arguments.get("height", 1.0))
			heading = found[1].global_rotation.y
		var turn := heading + deg_to_rad(float(arguments.get("yaw", VIEWS[view][0])))
		var rise := deg_to_rad(clampf(float(arguments.get("pitch", VIEWS[view][1])), -89.0, 89.0))
		var away := Vector3(sin(turn), 0.0, cos(turn)) * cos(rise) + Vector3.UP * sin(rise)
		_build_studio()
		studio_camera.fov = clampf(float(arguments.get("fov", 45.0)), 5.0, 120.0)
		studio_camera.global_position = focus + away * clampf(float(arguments.get("distance", 3.5)), 0.3, 300.0)
		# Looking straight down, "up" on the picture is the way the target faces.
		studio_camera.look_at(focus, Vector3.UP if absf(rise) < deg_to_rad(75.0) else Vector3(-sin(heading), 0.0, -cos(heading)))
		studio.render_target_update_mode = SubViewport.UPDATE_ONCE
		await _drawn()
		image = studio.get_texture().get_image()
	else:
		return {"error": "Unknown view '%s'. Views: player, %s." % [view, ", ".join(VIEWS.keys())]}
	if image == null or image.is_empty():
		return {"error": "The engine returned no picture for this frame."}
	var scale := clampf(float(arguments.get("scale", 1.0)), 0.25, 2.0)
	if not is_equal_approx(scale, 1.0):
		image.resize(roundi(image.get_width() * scale), roundi(image.get_height() * scale), Image.INTERPOLATE_LANCZOS)
	return {"image": image, "view": view}

func _drawn() -> void:
	# A hidden or covered window is not drawn, so draw one frame by hand instead of
	# waiting for a draw that never comes.
	if DisplayServer.window_can_draw():
		await RenderingServer.frame_post_draw
	else:
		RenderingServer.force_draw(false, 0.0)

func _build_studio() -> void:
	if studio != null:
		return
	# A second viewport on the same world: its camera sees the game without touching
	# the player's.
	studio = SubViewport.new()
	studio.size = Vector2i(ProjectSettings.get_setting("display/window/size/viewport_width"), ProjectSettings.get_setting("display/window/size/viewport_height"))
	studio.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(studio)
	studio_camera = Camera3D.new()
	studio.add_child(studio_camera)
	studio_camera.current = true

func _save(image: Image, stem: String) -> String:
	var directory := ProjectSettings.globalize_path(OUTPUT.path_join("shots"))
	DirAccess.make_dir_recursive_absolute(directory)
	shots = (shots + 1) % KEPT_SHOTS
	var path := directory.path_join("%s-%d-%03d.png" % [stem, server.port, shots])
	image.save_png(path)
	return path

## Every script, scene, resource, and shader in the project with the time it was last
## written, to tell what has changed on disk since.
func _scan(directory: String = "res://", found: Dictionary = {}) -> Dictionary:
	var access := DirAccess.open(directory)
	if access == null or access.file_exists(".gdignore"):
		return found
	for child: String in access.get_directories():
		if not child.begins_with("."):
			_scan(directory.path_join(child), found)
	for file: String in access.get_files():
		if file.get_extension() in WATCHED:
			found[directory.path_join(file)] = FileAccess.get_modified_time(directory.path_join(file))
	return found

func _reload_script(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"error": "no such file"}
	var script := load(path) as GDScript
	if script == null:
		return {"error": "did not load"}
	var fresh := FileAccess.get_file_as_string(path)
	var previous := script.source_code
	if fresh == previous:
		return {"status": "already current"}
	var known := _members(script)
	var mark: int = recorder.log_mark()
	script.source_code = fresh
	if script.reload(true) != OK:
		# A script that failed to compile leaves its objects without methods. Put the
		# version that worked back before another tick runs.
		var raised: Array = recorder.logged(mark, "errors", 3)
		script.source_code = previous
		script.reload(true)
		var why := "did not compile"
		if not raised.is_empty():
			why = "%s (%s)" % [raised[0].text, raised[0].get("where", path)]
		return {"error": why + "; the game kept the version it had"}
	var added: Array = _members(script).filter(func(member: String) -> bool: return not member in known)
	if not added.is_empty():
		_seed(script, added)
	return {"status": "reloaded", "new_vars": added}

static func _members(script: Script) -> Array:
	return script.get_script_property_list().map(func(property: Dictionary) -> String: return property.name)

# A reload leaves variables added by the edit empty on objects that already exist.
func _seed(script: Script, added: Array) -> void:
	var waiting: Array[Node] = [get_tree().root]
	while not waiting.is_empty():
		var node: Node = waiting.pop_back()
		waiting.append_array(node.get_children())
		var attached: Variant = node.get_script()
		while attached is Script and attached != script:
			attached = attached.get_base_script()
		if attached != script:
			continue
		for member: String in added:
			var initial: Variant = script.get_property_default_value(member)
			if node.get(member) == null and initial != null:
				node.set(member, initial)
