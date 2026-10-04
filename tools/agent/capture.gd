extends SceneTree
## Renders harness scenarios to PNG in a hidden window, without the MCP server.
## Run it through `tools/dev shot`. User arguments (after `--`):
##   <scenario>...        names from harness.gd SCENARIOS
##   --all                every scenario
##   key=value            an apply() key, e.g. level=lab pos=0,0.1,20 stance=prone ammo=0.
##                        With scenarios it overrides them; alone it is saved as custom.png
##   step.key=value       a step() key run after each state is applied, e.g.
##                        step.frames=45 step.forward=1 step.hold=fire
##   --model=<name>       place art/models/<name>.glb in the level (repeatable); with no
##                        level chosen it is shown on the Movement Lab start line
##   --at=x,y,z --yaw=n   where the first model goes (default 1.5,0,20) and its heading
##   --spec=<json>        a whole apply() spec as JSON, for nested keys such as tuning
##   --step=<json>        a whole step() input as JSON, including "frames"
##   --out=<dir>          output directory (default .agent/shots)
##   --sheet              also save sheet-N.png contact sheets, six scenarios each
##   --full               keep the native frame instead of fitting within 960x720
##   --state              include the state digest with each result
##   --show               leave the window visible and focusable

const H = preload("res://tools/agent/harness.gd")
const TILE := Vector2i(640, 480)
const SHEET_TILES := 6

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var names: Array[String] = []
	var flags: Dictionary = {}
	var out := ProjectSettings.globalize_path("res://.agent/shots")
	var spec_json := ""
	var step_json := ""
	var overrides: Dictionary = {}
	var step_keys: Dictionary = {}
	var models: Array[String] = []
	var model_at := Vector3(1.5, 0.0, 20.0)
	var model_yaw := 0.0
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		elif arg.begins_with("--spec="):
			spec_json = arg.trim_prefix("--spec=")
		elif arg.begins_with("--step="):
			step_json = arg.trim_prefix("--step=")
		elif arg.begins_with("--model="):
			models.append(arg.trim_prefix("--model="))
		elif arg.begins_with("--at="):
			model_at = H._vec(_value(arg.trim_prefix("--at=")))
		elif arg.begins_with("--yaw="):
			model_yaw = arg.trim_prefix("--yaw=").to_float()
		elif arg.begins_with("--"):
			flags[arg.trim_prefix("--")] = true
		elif arg.begins_with("step.") and "=" in arg:
			var step_key := arg.get_slice("=", 0).trim_prefix("step.")
			step_keys[step_key] = _value(arg.get_slice("=", 1), step_key in ["hold", "tap"])
		elif "=" in arg:
			overrides[arg.get_slice("=", 0)] = _value(arg.get_slice("=", 1), arg.get_slice("=", 0) == "hold")
		else:
			names.append(arg)
	if flags.has("all"):
		names.assign(H.SCENARIOS.keys())
	var spec: Variant = JSON.parse_string(spec_json) if spec_json != "" else null
	var step: Variant = JSON.parse_string(step_json) if step_json != "" else null
	if (spec_json != "" and not spec is Dictionary) or (step_json != "" and not step is Dictionary):
		printerr("capture: --spec and --step take a JSON object")
		quit(2)
		return
	if not step_keys.is_empty():
		step = step_keys.merged(step if step != null else {})
	if not models.is_empty():
		var placed: Array = []
		for index: int in range(models.size()):
			var scene := models[index] if models[index].begins_with("res://") else "res://art/models/%s.glb" % models[index].trim_suffix(".glb")
			# Several models stand in a row, 2.5 m apart.
			placed.append({"scene": scene, "pos": [model_at.x + 2.5 * index, model_at.y, model_at.z], "yaw": model_yaw})
		overrides["place"] = placed
		if names.is_empty() and spec == null and not overrides.has("level"):
			overrides.merge({"level": "lab", "spawn": "Start"})
	if not overrides.is_empty() and names.is_empty():
		spec = overrides.merged(spec if spec != null else {})
	for title: String in names:
		if not H.SCENARIOS.has(title):
			printerr("capture: unknown scenario '%s'. Known: %s" % [title, ", ".join(H.SCENARIOS.keys())])
			quit(2)
			return
	if names.is_empty() and spec == null:
		print("Scenarios: ", ", ".join(H.SCENARIOS.keys()))
		quit(0)
		return
	if not flags.has("show"):
		for flag: int in [DisplayServer.WINDOW_FLAG_NO_FOCUS, DisplayServer.WINDOW_FLAG_MOUSE_PASSTHROUGH, DisplayServer.WINDOW_FLAG_BORDERLESS]:
			DisplayServer.window_set_flag(flag, true)
		DisplayServer.window_set_position(Vector2i(-9999, -9999))
	DirAccess.make_dir_recursive_absolute(out)
	root.add_child(load("res://scenes/main.tscn").instantiate())
	for index: int in range(20):
		await process_frame
	var jobs: Array = names.map(func(title: String) -> Array: return [title, null])
	if spec != null:
		jobs.append(["custom", spec])
	var tiles: Array[Image] = []
	for job: Array in jobs:
		var result: Dictionary
		if job[1] != null:
			result = await H.apply(self, job[1])
		else:
			result = await H.scenario(self, job[0], overrides)
		if step != null and not result.has("error"):
			var stepped: Dictionary = await H.step(self, int(step.get("frames", 60)), step)
			if result.has("notes"):
				stepped["notes"] = result.notes
			result = stepped
		var image := await _grab()
		if not flags.has("full"):
			var ratio := minf(960.0 / image.get_width(), 720.0 / image.get_height())
			image.resize(roundi(image.get_width() * ratio), roundi(image.get_height() * ratio), Image.INTERPOLATE_LANCZOS)
		var path := out.path_join("%s.png" % job[0])
		image.save_png(path)
		var line: Dictionary = {"scenario": job[0], "png": path}
		for key: String in ["error", "notes"]:
			if result.has(key):
				line[key] = result[key]
		if flags.has("state"):
			line["state"] = result
		print("SHOT ", JSON.stringify(line))
		if flags.has("sheet"):
			var ratio := minf(float(TILE.x) / image.get_width(), float(TILE.y) / image.get_height())
			image.resize(roundi(image.get_width() * ratio), roundi(image.get_height() * ratio), Image.INTERPOLATE_LANCZOS)
			var tile := Image.create_empty(TILE.x,TILE.y,false,image.get_format())
			tile.fill(Color.BLACK)
			tile.blit_rect(image,Rect2i(Vector2i.ZERO,image.get_size()),(TILE - image.get_size()) / 2)
			tiles.append(tile)
	# Six tiles a sheet keeps each one legible when an agent views the image.
	for first: int in range(0, tiles.size(), SHEET_TILES):
		var count := mini(SHEET_TILES, tiles.size() - first)
		var sheet := Image.create_empty(TILE.x * 2, TILE.y * ceili(count / 2.0), false, tiles[0].get_format())
		for index: int in range(count):
			sheet.blit_rect(tiles[first + index], Rect2i(Vector2i.ZERO, TILE), Vector2i(index % 2, index / 2) * TILE)
		var sheet_path := out.path_join("sheet-%d.png" % (first / SHEET_TILES + 1))
		sheet.save_png(sheet_path)
		var order: Array = jobs.slice(first, first + count).map(func(job: Array) -> String: return job[0])
		print("SHEET ", JSON.stringify({"png": sheet_path, "left_to_right_top_to_bottom": order}))
	quit(0)

# Reads a command-line value: true/false, a number, text, or a comma-separated list.
func _value(text: String, as_list: bool = false) -> Variant:
	if "," in text or as_list:
		var items: Array = []
		for part: String in text.split(","):
			items.append(_value(part))
		return items if items.size() > 1 or as_list else items[0]
	if text in ["true", "false"]:
		return text == "true"
	if text.is_valid_int():
		return text.to_int()
	if text.is_valid_float():
		return text.to_float()
	return text

func _grab() -> Image:
	# A hidden macOS window is occluded, so the engine stops drawing it; render one
	# frame by hand instead of waiting for a draw that never comes.
	if DisplayServer.window_can_draw():
		await RenderingServer.frame_post_draw
	else:
		RenderingServer.force_draw(false, 0.0)
	return root.get_texture().get_image()
