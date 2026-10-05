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
var character_box: VBoxContainer
var gun_box: VBoxContainer
var mode_picker: OptionButton
var gun_search: LineEdit
var gun_category: OptionButton
var gun_picker: OptionButton
var gun_details: Label
var gun_record: OptionButton
var equip_button: Button

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
	panel.position = Vector2(24, 28)
	panel.custom_minimum_size = Vector2(370, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.1, 0.08, 0.96)
	style.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", style)
	var outer := VBoxContainer.new()
	panel.add_child(outer)
	mode_picker = OptionButton.new()
	outer.add_child(mode_picker)
	mode_picker.add_item("Characters & animations")
	mode_picker.add_item("Guns")
	mode_picker.custom_minimum_size.y = 34
	mode_picker.item_selected.connect(set_mode)
	var box := VBoxContainer.new()
	outer.add_child(box)
	character_box = box
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
	_build_guns(outer)
	panel.hide()

func _build_guns(outer: VBoxContainer) -> void:
	gun_box = VBoxContainer.new()
	outer.add_child(gun_box)
	gun_box.add_theme_constant_override("separation", 9)
	_label(gun_box, "RECOVERED GUNS", 21)
	_label(gun_box, "%d models and source variants" % lab.guns.size(), 16)
	gun_category = OptionButton.new()
	gun_box.add_child(gun_category)
	gun_category.add_item("All guns")
	var categories: Array[String] = []
	for entry: Dictionary in lab.guns:
		if not categories.has(entry.category):
			categories.append(entry.category)
	for category: String in categories:
		gun_category.add_item(category)
	gun_category.item_selected.connect(func(_index: int) -> void: _filter_guns())
	gun_search = LineEdit.new()
	gun_box.add_child(gun_search)
	gun_search.placeholder_text = "Find gun…"
	gun_search.text_changed.connect(func(_text: String) -> void: _filter_guns())
	gun_picker = OptionButton.new()
	gun_box.add_child(gun_picker)
	gun_picker.fit_to_longest_item = false
	gun_picker.custom_minimum_size.y = 34
	gun_picker.item_selected.connect(func(index: int) -> void: lab.set_gun(gun_picker.get_item_id(index)); _gun_details())
	var row := HBoxContainer.new()
	gun_box.add_child(row)
	_button(row, "Previous", func() -> void: _cycle_gun(-1))
	_button(row, "Next", func() -> void: _cycle_gun(1))
	gun_details = _label(gun_box, "", 14)
	gun_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gun_details.custom_minimum_size = Vector2(338, 100)
	gun_record = OptionButton.new()
	gun_box.add_child(gun_record)
	gun_record.fit_to_longest_item = false
	gun_record.item_selected.connect(func(_index: int) -> void: _gun_stats())
	_label(gun_box, "Turn gun", 14)
	var angle := HSlider.new()
	gun_box.add_child(angle)
	angle.max_value = 360
	angle.value = 90
	angle.value_changed.connect(func(value: float) -> void: lab.weapon.rotation.y = deg_to_rad(value))
	equip_button = _button(gun_box, "Equip selected gun", func() -> void: lab.equip_gun(gun_record.get_selected_id()); set_open(false))
	_button(gun_box, "Close / Tab", func() -> void: set_open(false))
	_filter_guns()
	_gun_details()
	gun_box.hide()

func set_mode(index: int) -> void:
	mode_picker.select(index)
	character_box.visible = index == 0
	gun_box.visible = index == 1
	panel.size.y = 0
	if index == 1:
		inspection_camera.position = Vector3(5, 1.4, 10.5)
		inspection_camera.look_at(lab.to_global(Vector3(5, 1.1, 8)))
		inspection_camera.h_offset = -0.65
	else:
		inspection_camera.position = Vector3(9.25, 1.55, 13.6)
		inspection_camera.look_at(lab.to_global(Vector3(9.25, 1, 8)))
		inspection_camera.h_offset = -1.0

func _filter_guns() -> void:
	gun_picker.clear()
	for index: int in range(lab.guns.size()):
		var entry: Dictionary = lab.guns[index]
		if gun_category.selected > 0 and entry.category != gun_category.get_item_text(gun_category.selected):
			continue
		if not gun_search.text.is_empty() and not (entry.name + " " + entry.source_name).to_lower().contains(gun_search.text.to_lower()):
			continue
		gun_picker.add_item(entry.name, index)
		if index == lab.weapon_index:
			gun_picker.select(gun_picker.item_count - 1)
	gun_picker.disabled = gun_picker.item_count == 0
	if gun_picker.item_count > 0 and gun_picker.get_item_id(gun_picker.selected) != lab.weapon_index:
		lab.set_gun(gun_picker.get_item_id(gun_picker.selected))
	if gun_details != null:
		_gun_details()

func _cycle_gun(direction: int) -> void:
	if gun_picker.item_count == 0:
		return
	var index := posmod(gun_picker.selected + direction, gun_picker.item_count)
	gun_picker.select(index)
	lab.set_gun(gun_picker.get_item_id(index))
	_gun_details()

func _gun_details() -> void:
	var entry: Dictionary = lab.guns[lab.weapon_index]
	gun_record.clear()
	for record: Dictionary in lab.Guns.records_for(entry.id):
		gun_record.add_item(record.name, int(record.id))
	gun_record.visible = gun_record.item_count > 1
	_gun_stats()
	equip_button.disabled = not entry.playable or gun_picker.item_count == 0

func _gun_stats() -> void:
	var entry: Dictionary = lab.guns[lab.weapon_index]
	var size: Vector3 = lab.Guns.vector(entry.bounds_max) - lab.Guns.vector(entry.bounds_min)
	var info := "Launcher model preview. Firing is not yet implemented."
	if entry.playable:
		var profile: WeaponProfile = lab.Guns.profile_for(entry.id, gun_record.get_selected_id())
		var modes: Array[String] = []
		for mode: float in profile.recovered_stats.modes:
			modes.append(["SAFE", "SEMI", "BURST", "AUTO"][int(mode)])
		info = "%s · %s\nRecovered recoil / spread · B / L3 changes mode\nDamage and ammunition use prototype tuning." % [profile.recovered_stats.name, " / ".join(modes)]
	gun_details.text = "%s\n%s · %.2f m long\n%s" % [entry.name, entry.category, size.z, info]

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
	session.update_mouse_capture()
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
