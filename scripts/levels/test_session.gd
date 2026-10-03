extends Node3D

const TOWN := preload("res://scenes/levels/old_quarter.tscn")
const LAB := preload("res://scenes/levels/movement_lab.tscn")
const SETTINGS_PATH := "user://prototype_settings.cfg"
@onready var player: PrototypePlayer = $Player
@onready var hud: PrototypeHUD = $HUD
var level: Node3D
var in_lab: bool = false
var spawn_index: int = 0
var modal: bool = false
var elapsed: float = 0.0
var lap_time: float = 0.0
var lap_running: bool = false
var last_lap: float = 0.0
var lap_start := Vector3.ZERO
var debug_visible: bool = false
var retro_enabled: bool = false
var qa_mode: bool = "--qa" in OS.get_cmdline_user_args() or "--capture" in OS.get_cmdline_user_args()

func _enter_tree() -> void:
	PlayerInput.setup()

func _ready() -> void:
	_load_settings()
	hud.initialize(self)
	player.message.connect(hud.notify)
	load_level(false)
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if not qa_mode:
		get_window().focus_exited.connect(func() -> void: set_modal(true))
	Input.joy_connection_changed.connect(_controller_connection_changed)
	if "--capture" in OS.get_cmdline_user_args():
		_capture_preview()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("tuning"):
		set_modal(not modal)
		get_viewport().set_input_as_handled()
	elif modal:
		if event.is_action_pressed("ui_cancel"):
			set_modal(false)
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("menu_previous") or event.is_action_pressed("menu_next"):
			hud.change_page(-1 if event.is_action_pressed("menu_previous") else 1)
			get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if modal:
		return
	if event.is_action_pressed("switch_level"):
		load_level(not in_lab)
	elif event.is_action_pressed("reset_player"):
		reset_player()
	elif event.is_action_pressed("next_spawn"):
		next_spawn()
	elif event.is_action_pressed("debug_view"):
		debug_visible = not debug_visible
	elif event.is_action_pressed("start_lap"):
		toggle_lap()

func next_spawn() -> void:
	spawn_index = (spawn_index + 1) % level.get_node("Spawns").get_child_count()
	reset_player()

func toggle_lap() -> void:
	if lap_running:
		last_lap = lap_time
		lap_running = false
		hud.notify("Lap recorded: %.2f seconds" % last_lap)
	else:
		lap_time = 0.0
		lap_start = player.global_position
		lap_running = true
		hud.notify("Lap started • Y / T to stop")

func _controller_connection_changed(_device: int, connected: bool) -> void:
	if not connected:
		set_modal(true)
		hud.notify("Controller disconnected • reconnect or use mouse and keyboard")
	else:
		hud.notify("Controller connected • Start opens tuning")

func load_level(lab: bool) -> void:
	if is_instance_valid(level):
		remove_child(level)
		level.queue_free()
	in_lab = lab
	spawn_index = 0
	level = (LAB if lab else TOWN).instantiate()
	add_child(level)
	level.process_mode = Node.PROCESS_MODE_DISABLED if modal else Node.PROCESS_MODE_INHERIT
	reset_player()
	hud.notify("Movement Lab • measured fixtures and practice targets" if lab else "Old Quarter • explore the three routes")

func reset_player() -> void:
	var spawn: Marker3D = level.get_node("Spawns").get_child(spawn_index)
	player.reset_at(spawn.global_transform)
	lap_time = 0.0
	lap_running = false
	last_lap = 0.0
	elapsed = 0.0
	for target: Node in get_tree().get_nodes_in_group("range_targets"):
		if level.is_ancestor_of(target):
			target.reset_target()

func set_modal(value: bool) -> void:
	modal = value
	player.controls_enabled = not value
	player.input_armed = false
	player.pending_mouse = Vector2.ZERO
	player.pad_stance_time = 0.0
	player.pad_hold_consumed = true
	player.stance_was_down = false
	PlayerInput.stop_vibration()
	level.process_mode = Node.PROCESS_MODE_DISABLED if value else Node.PROCESS_MODE_INHERIT
	hud.set_menu(value)
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if value else Input.MOUSE_MODE_CAPTURED
	if not value:
		_save_settings()

func _process(delta: float) -> void:
	if not modal:
		elapsed += delta
		if lap_running:
			lap_time += delta
		if player.global_position.y < -8:
			reset_player()
			hud.notify("Returned to spawn")
	hud.update_display(delta)

func location_name() -> String:
	var result := "OLD QUARTER" if not in_lab else "MOVEMENT LAB"
	var best: float = INF
	for marker: Marker3D in level.get_node("Locations").get_children():
		var distance := player.global_position.distance_to(marker.global_position)
		if distance < float(marker.get_meta("radius")) and distance < best:
			result = marker.get_meta("title")
			best = distance
	return result

func set_retro(enabled: bool) -> void:
	retro_enabled = enabled
	get_viewport().scaling_3d_scale = 0.5 if enabled else 1.0

func reset_tuning() -> void:
	player.movement = load("res://resources/movement/default_movement.tres").duplicate()
	player.camera_settings = load("res://resources/camera/default_camera.tres").duplicate()
	player.camera_rig.profile = player.camera_settings
	player.weapon.reset_profiles()
	set_retro(false)
	hud.refresh_settings()

func _save_settings() -> void:
	if qa_mode:
		return
	var error := settings_config().save(SETTINGS_PATH)
	if error != OK:
		push_warning("Could not save prototype tuning: %s" % error_string(error))

func settings_config() -> ConfigFile:
	var config := ConfigFile.new()
	config.set_value("meta", "version", 4)
	for key: String in ["run_speed", "acceleration", "braking", "body_weight", "prone_speed"]:
		config.set_value("movement", key, player.movement.get(key))
	for key: String in ["field_of_view", "distance", "shoulder_offset", "height_offset", "mouse_sensitivity", "pad_sensitivity", "pad_deadzone", "pad_aim_multiplier", "vibration", "invert_y", "hud_opacity"]:
		config.set_value("camera", key, player.camera_settings.get(key))
	for slot: int in range(2):
		for key: String in WeaponProfile.TUNING_KEYS:
			config.set_value("weapon_%d" % slot, key, player.weapon.profiles[slot].get(key))
	config.set_value("display", "retro", retro_enabled)
	return config

func _load_settings() -> void:
	if qa_mode:
		return
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	apply_settings_config(config)

func apply_settings_config(config: ConfigFile) -> void:
	for key: String in ["run_speed", "acceleration", "braking", "body_weight", "prone_speed"]:
		# Earlier saved acceleration/braking values predate the heavier baseline.
		if config.get_value("meta", "version", 1) < 2 and key in ["acceleration", "braking"]:
			continue
		player.movement.set(key, config.get_value("movement", key, player.movement.get(key)))
	for key: String in ["field_of_view", "distance", "shoulder_offset", "height_offset", "mouse_sensitivity", "pad_sensitivity", "pad_deadzone", "pad_aim_multiplier", "vibration", "invert_y", "hud_opacity"]:
		if config.get_value("meta", "version", 1) < 4 and key == "shoulder_offset":
			continue
		player.camera_settings.set(key, config.get_value("camera", key, player.camera_settings.get(key)))
	for slot: int in range(2):
		for key: String in WeaponProfile.TUNING_KEYS:
			var settings: WeaponProfile = player.weapon.profiles[slot]
			# Migrate the earlier low-spread prototype preset once; preserve later tuning.
			if config.get_value("meta", "version", 1) < 3 and key in ["spread_per_shot", "max_climb", "max_bloom", "vertical_kick"]:
				continue
			settings.set(key, config.get_value("weapon_%d" % slot, key, settings.get(key)))
	set_retro(config.get_value("display", "retro", false))

func _capture_preview() -> void:
	# Engine-rendered screenshots for visual QA; invoked explicitly by CLI only.
	for index: int in range(12):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/private/tmp/socom-town.png")
	load_level(true)
	for index: int in range(12):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/private/tmp/socom-lab.png")
	set_modal(true)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/private/tmp/socom-tuning.png")
	get_tree().quit()
