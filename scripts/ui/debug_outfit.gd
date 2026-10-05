extends VBoxContainer
## Per-slot visual overrides; Auto restores the character.rdr default for this body.
const Outfit = preload("res://scripts/actors/recovered_outfit.gd")
const SLOTS := {"headwear": "Hat / helmet", "eyewear": "Goggles", "vest": "Vest gear", "belt": "Belt / pouches", "holster": "Holster", "pack": "Backpack", "knife": "Knife"}
var hud: Node
var pickers: Dictionary = {}
var stowed: CheckButton
var grenades: CheckButton

func initialize(owner_hud: Node) -> void:
	hud = owner_hud
	add_theme_constant_override("separation", 5)
	for slot: String in SLOTS:
		var row := HBoxContainer.new()
		add_child(row)
		var label := Label.new()
		label.text = SLOTS[slot]
		label.custom_minimum_size.x = 150
		row.add_child(label)
		var picker := OptionButton.new()
		picker.name = slot
		picker.fit_to_longest_item = false
		picker.custom_minimum_size = Vector2(360, 30)
		picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		picker.get_popup().max_size.y = 270
		row.add_child(picker)
		picker.add_item("Auto · character's original gear")
		picker.set_item_metadata(0, "auto")
		picker.add_item("None")
		picker.set_item_metadata(1, "none")
		for id: String in Outfit.catalogue().gear:
			if Outfit.catalogue().gear[id].group != slot:
				continue
			picker.add_item(id.replace("_", " ").capitalize())
			picker.set_item_metadata(picker.item_count - 1, id)
		picker.item_selected.connect(func(index: int) -> void: _outfit().choose(slot, picker.get_item_metadata(index)))
		_bind(picker)
		pickers[slot] = picker
	var toggles := HBoxContainer.new()
	add_child(toggles)
	stowed = CheckButton.new()
	stowed.text = "Stowed guns"
	toggles.add_child(stowed)
	stowed.toggled.connect(func(value: bool) -> void: _outfit().show_stowed = value; _update_equipment())
	_bind(stowed)
	grenades = CheckButton.new()
	grenades.text = "Carried grenades"
	toggles.add_child(grenades)
	grenades.toggled.connect(func(value: bool) -> void: _outfit().show_grenades = value; _update_equipment())
	_bind(grenades)
	var restore := Button.new()
	restore.text = "Restore character's original outfit"
	restore.pressed.connect(func() -> void: _outfit().reset(); _update_equipment(); refresh())
	add_child(restore)
	_bind(restore)
	var note := Label.new()
	note.text = "Visual fitting only. Loadout controls weapons and grenade supply.\nAuto follows the selected character; overrides stay for this run."
	note.add_theme_font_size_override("font_size", 13)
	note.add_theme_color_override("font_color", hud.MUTED)
	add_child(note)
	refresh()

func _outfit() -> Node3D:
	return hud.session.player.soldier.soldier_skin.outfit

func _update_equipment() -> void:
	_outfit().update_equipment(hud.session.player.soldier, hud.session.player.weapon)

func _bind(control: Control) -> void:
	hud._bind_focus(control)
	hud.page_controls.back().append(control)

func refresh() -> void:
	for slot: String in pickers:
		var picker: OptionButton = pickers[slot]
		var id: String = _outfit().overrides.get(slot, "auto")
		for index: int in range(picker.item_count):
			if picker.get_item_metadata(index) == id:
				picker.select(index)
	stowed.set_pressed_no_signal(_outfit().show_stowed)
	grenades.set_pressed_no_signal(_outfit().show_grenades)
