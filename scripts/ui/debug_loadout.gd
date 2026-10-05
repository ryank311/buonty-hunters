extends VBoxContainer
## Select the playable character, gun records and equipment from the debug menu.
const Guns := preload("res://scripts/combat/recovered_weapons.gd")
const EQUIPMENT: Array[WeaponProfile] = [
	preload("res://resources/weapons/frag.tres"),
	preload("res://resources/weapons/smoke.tres"),
	preload("res://resources/weapons/flash.tres"),
	preload("res://resources/weapons/claymore.tres"),
]
var hud: Node
var pickers: Array[OptionButton] = []
var choices: Array[Array] = []
var character_search: LineEdit
var character_picker: OptionButton

func initialize(owner_hud: Node) -> void:
	hud = owner_hud
	add_theme_constant_override("separation", 9)
	var guns: Array[Array] = [[], []]
	for entry: Dictionary in Guns.catalogue():
		# The Lab retains archive geometry variants; the loadout lists each design.
		if not entry.playable or entry.id != entry.source_name.to_lower():
			continue
		for record: Dictionary in Guns.records_for(entry.id):
			# The Gyurza record aliases SIG geometry on disc; use its own recovered mesh.
			if int(record.id) == 13 and entry.id != "sp10_gyuraz":
				continue
			var slot := 1 if entry.hold == "pistol" else 0
			guns[slot].append({"model": entry.id, "record": int(record.id), "title": record.name, "category": entry.category})
	for list: Array in guns:
		list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.title).naturalnocasecmp_to(b.title) < 0)
	var equipment: Array = []
	for profile: WeaponProfile in EQUIPMENT:
		equipment.append({"kind": profile.kind, "title": "%s × %d" % [profile.display_name.capitalize(), profile.magazine_size]})
	choices = [guns[0], guns[1], equipment, equipment]
	for slot: int in range(4):
		var row := HBoxContainer.new()
		add_child(row)
		var label := Label.new()
		row.add_child(label)
		label.text = ["Primary · 1", "Pistol · 2", "Equipment · 3", "Equipment · 4"][slot]
		label.custom_minimum_size.x = 142
		var picker := OptionButton.new()
		row.add_child(picker)
		picker.name = ["Primary", "Pistol", "Equipment1", "Equipment2"][slot]
		picker.fit_to_longest_item = false
		picker.custom_minimum_size = Vector2(380, 34)
		picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		picker.get_popup().max_size.y = 300
		for choice: Dictionary in choices[slot]:
			picker.add_item(choice.title)
			picker.set_item_tooltip(picker.item_count - 1, choice.get("category", choice.title))
		picker.item_selected.connect(_choose.bind(slot))
		hud._bind_focus(picker)
		hud.page_controls.back().append(picker)
		pickers.append(picker)
	var character_row := HBoxContainer.new()
	add_child(character_row)
	var character_label := Label.new()
	character_row.add_child(character_label)
	character_label.text = "Character"
	character_label.custom_minimum_size.x = 142
	character_picker = OptionButton.new()
	character_row.add_child(character_picker)
	character_picker.name = "Character"
	character_picker.fit_to_longest_item = false
	character_picker.custom_minimum_size = Vector2(380, 34)
	character_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	character_picker.get_popup().max_size.y = 300
	character_picker.item_selected.connect(func(index: int) -> void:
		hud.session.set_player_character(character_picker.get_item_id(index))
	)
	hud._bind_focus(character_picker)
	hud.page_controls.back().append(character_picker)
	character_search = LineEdit.new()
	add_child(character_search)
	character_search.placeholder_text = "Find character… (%d full-detail models)" % hud.session.recovered_characters.size()
	character_search.custom_minimum_size.y = 30
	character_search.text_changed.connect(func(_text: String) -> void: _filter_characters())
	hud._bind_focus(character_search)
	hud.page_controls.back().append(character_search)
	var note := Label.new()
	add_child(note)
	note.text = "Weapons refill their slot; characters swap immediately. Kept for this run.\nClass/defaults restore equipment. Your character stays selected."
	note.add_theme_font_size_override("font_size", 13)
	note.add_theme_color_override("font_color", hud.MUTED)
	refresh()

func refresh() -> void:
	var weapon: PracticeWeapon = hud.session.player.weapon
	for slot: int in range(pickers.size()):
		var picker := pickers[slot]
		# A non-catalogue pickup can be displayed without silently replacing it.
		while picker.item_count > choices[slot].size():
			picker.remove_item(picker.item_count - 1)
		picker.disabled = slot >= weapon.profiles.size()
		if picker.disabled:
			continue
		var carried := weapon.profiles[slot]
		var selected := -1
		for index: int in range(choices[slot].size()):
			var choice: Dictionary = choices[slot][index]
			if slot < 2:
				if int(carried.recovered_stats.get("id", -1)) == choice.record:
					selected = index
			elif carried.kind == choice.kind:
				selected = index
		if selected < 0:
			selected = picker.item_count
			picker.add_item(carried.display_name + " (current)")
		picker.select(selected)
	_filter_characters()

func _filter_characters() -> void:
	if character_picker == null:
		return
	character_picker.clear()
	var path: String = hud.session.player.soldier.soldier_skin.model_path
	var query := character_search.text.strip_edges().to_lower()
	var selected := -1
	var entries: Array = hud.session.recovered_characters
	for index: int in range(entries.size()):
		var entry: Dictionary = entries[index]
		if not query.is_empty() and not query in String(entry.name).to_lower():
			continue
		character_picker.add_item(entry.name, index)
		if entry.path == path:
			selected = character_picker.item_count - 1
	character_picker.disabled = character_picker.item_count == 0
	if character_picker.disabled:
		character_picker.add_item("No matching characters")
	else:
		# Filtering is read-only: do not imply its first result is the current model.
		character_picker.select(selected)
		if selected < 0:
			character_picker.text = "Choose a matching character…"

func _choose(index: int, slot: int) -> void:
	if index < 0 or index >= choices[slot].size():
		return
	var weapon: PracticeWeapon = hud.session.player.weapon
	if slot >= weapon.profiles.size():
		return
	var choice: Dictionary = choices[slot][index]
	var selected: WeaponProfile
	if slot < 2:
		selected = Guns.profile_for(choice.model, choice.record)
	else:
		for defaults: WeaponProfile in EQUIPMENT:
			if defaults.kind == choice.kind:
				selected = defaults.duplicate()
	if selected == null:
		return
	preload("res://scripts/combat/weapon_tuning.gd").apply(selected)
	weapon.receive(slot, selected, selected.magazine_size, selected.starting_reserve)
	hud.refresh_settings()
