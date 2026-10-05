extends CanvasLayer
## An inspection dock: the player stops, while both comparison figures animate.

var lab: Node3D
var panel: PanelContainer
var model_picker: OptionButton
var motion_picker: OptionButton
var category_picker: OptionButton
var model_search: LineEdit
var motion_search: LineEdit
var details: Label
var pause_button: Button
var timeline: HSlider
var opened: bool = false
var categories: Array[String] = ["All motions"]
var visible_motions: Array[String] = []
var inspection_camera: Camera3D
var player_was_visible: bool = true

func _ready() -> void:
	layer = 2
	inspection_camera = Camera3D.new()
	lab.add_child(inspection_camera)
	inspection_camera.position = Vector3(9.25, 1.55, 13.6)
	inspection_camera.look_at(lab.to_global(Vector3(9.25, 1.0, 8.0)))
	inspection_camera.fov = 50.0
	inspection_camera.h_offset = -1.0
	var root := Control.new()
	add_child(root)
	root.size = Vector2(1024, 768)
	root.scale = get_viewport().get_visible_rect().size / root.size
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel = PanelContainer.new()
	root.add_child(panel)
	panel.position = Vector2(24, 70)
	panel.custom_minimum_size = Vector2(370, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.1, 0.08, 0.96)
	style.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	panel.add_child(box)
	box.add_theme_constant_override("separation", 9)
	_label(box, "RECOVERED CHARACTERS", 21)
	_label(box, "%d models · %d motions" % [lab.data.characters.size(), lab.data.motions.size()], 16)
	model_search = LineEdit.new()
	box.add_child(model_search)
	model_search.placeholder_text = "Find character…"
	model_search.text_changed.connect(func(_text: String) -> void: _filter_models())
	model_picker = OptionButton.new()
	box.add_child(model_picker)
	model_picker.fit_to_longest_item = false
	model_picker.custom_minimum_size.y = 34
	model_picker.item_selected.connect(func(index: int) -> void: lab.set_character(model_picker.get_item_id(index)))
	_label(box, "Compare with your playable character →", 14)
	category_picker = OptionButton.new()
	box.add_child(category_picker)
	for motion: Dictionary in lab.data.motions:
		if not categories.has(motion.category):
			categories.append(motion.category)
	for category: String in categories:
		category_picker.add_item(category)
	category_picker.item_selected.connect(func(_index: int) -> void: _filter_motions())
	motion_search = LineEdit.new()
	box.add_child(motion_search)
	motion_search.placeholder_text = "Find animation…"
	motion_search.text_changed.connect(func(_text: String) -> void: _filter_motions())
	motion_picker = OptionButton.new()
	box.add_child(motion_picker)
	motion_picker.fit_to_longest_item = false
	motion_picker.custom_minimum_size.y = 34
	motion_picker.item_selected.connect(func(index: int) -> void: lab.set_clip(lab.animation_names.find(visible_motions[index])))
	var playback := HBoxContainer.new()
	box.add_child(playback)
	_button(playback, "Previous", func() -> void: _cycle(-1))
	pause_button = _button(playback, "Pause", func() -> void: lab.set_playback_paused(not lab.playback_paused))
	_button(playback, "Next", func() -> void: _cycle(1))
	_button(playback, "+1 frame", func() -> void: lab.step_animation())
	timeline = HSlider.new()
	box.add_child(timeline)
	timeline.step = 1.0 / 30.0
	timeline.value_changed.connect(func(value: float) -> void: lab.set_playback_paused(true); lab.seek_animation(value))
	details = _label(box, "", 14)
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.custom_minimum_size = Vector2(338, 82)
	_label(box, "Turn models", 14)
	var angle := HSlider.new()
	box.add_child(angle)
	angle.max_value = 360
	angle.value = 180
	angle.value_changed.connect(func(value: float) -> void:
		lab.character.rotation.y = deg_to_rad(value)
		lab.retargeted.rotation.y = deg_to_rad(value)
	)
	_button(box, "Use selected character for player", func() -> void: lab.get_parent().set_player_character(lab.character_index))
	_label(box, "Close to play. [ / ] switches characters.", 13)
	var extras := HBoxContainer.new()
	box.add_child(extras)
	_button(extras, "Collision", func() -> void: lab.set_collision_visible(not lab.collision_visible))
	_button(extras, "Close / Tab", func() -> void: set_open(false))
	_filter_models()
	_filter_motions()
	panel.hide()

func _label(parent: Node, text: String, size: int) -> Label:
	var label := Label.new()
	parent.add_child(label)
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	return label

func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	parent.add_child(button)
	button.text = text
	button.custom_minimum_size.y = 34
	button.pressed.connect(callback)
	return button

func _filter_models() -> void:
	model_picker.clear()
	for index: int in range(lab.data.characters.size()):
		var entry: Dictionary = lab.data.characters[index]
		if not model_search.text.is_empty() and not entry.name.to_lower().contains(model_search.text.to_lower()):
			continue
		model_picker.add_item(entry.name, index)
		if index == lab.character_index:
			model_picker.select(model_picker.item_count - 1)
	model_picker.disabled = model_picker.item_count == 0

func _filter_motions() -> void:
	motion_picker.clear()
	visible_motions.clear()
	for entry: Dictionary in lab.data.motions:
		if category_picker.selected > 0 and entry.category != categories[category_picker.selected]:
			continue
		if not motion_search.text.is_empty() and not entry.name.contains(motion_search.text.to_lower()):
			continue
		visible_motions.append(entry.name)
		motion_picker.add_item(entry.name + (" [partial]" if entry.partial else ""))
		if entry.name == lab.animation_names[lab.clip_index]:
			motion_picker.select(motion_picker.item_count - 1)
	motion_picker.disabled = motion_picker.item_count == 0

func _cycle(direction: int) -> void:
	if visible_motions.is_empty():
		return
	var index := visible_motions.find(lab.animation_names[lab.clip_index])
	index = posmod(index + direction, visible_motions.size())
	lab.set_clip(lab.animation_names.find(visible_motions[index]))
	motion_picker.select(index)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("recovery_browser") or (opened and (event.is_action_pressed("pause") or event.is_action_pressed("tuning"))):
		set_open(not opened)
		get_viewport().set_input_as_handled()

func set_open(value: bool) -> void:
	opened = value
	panel.visible = value
	lab._update_caption()
	var session := lab.get_parent()
	if value:
		player_was_visible = session.player.soldier.visible
		session.player.soldier.hide()
		inspection_camera.make_current()
	else:
		session.player.soldier.visible = player_was_visible
		session.player.camera_rig.camera.make_current()
	session.player.controls_enabled = not value
	session.player.input_armed = false
	session.player.pending_mouse = Vector2.ZERO
	session.hud.root.visible = not value
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if value else Input.MOUSE_MODE_CAPTURED
	if not value:
		get_viewport().gui_release_focus()

func _exit_tree() -> void:
	if opened and is_instance_valid(lab.get_parent()):
		set_open(false)

func _process(_delta: float) -> void:
	if not opened:
		return
	pause_button.text = "Play" if lab.playback_paused else "Pause"
	timeline.set_block_signals(true)
	timeline.max_value = lab.animation.current_animation_length
	timeline.set_value_no_signal(lab.animation.current_animation_position)
	timeline.set_block_signals(false)
	var name: String = lab.animation_names[lab.clip_index]
	var selected := visible_motions.find(name)
	if selected >= 0 and motion_picker.selected != selected:
		motion_picker.select(selected)
	for entry: Dictionary in lab.data.motions:
		if entry.name == name:
			details.text = "%s\n%.2f / %.2f s · %d frames\n%s" % [name, timeline.value, entry.duration, entry.frames, "Partial-body clip: missing tracks use its original bind pose." if entry.partial else "Original rig and motion. Gameplay events need review."]
			break
