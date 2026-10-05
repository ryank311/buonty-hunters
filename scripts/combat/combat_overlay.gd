extends Node
## Screen-space feedback for combat that the main HUD does not own: the scope view, the
## flashbang whiteout and ringing ears, damage numbers, the elimination banner, and the two small menus
## (searching a body, choosing a class). The scope mask sits under the HUD; everything
## else sits over it.

const LAYOUT_SIZE := Vector2(1024, 768) # same authored size as the HUD, scaled to the viewport
const INK := Color("dce3d2")
const GOLD := Color("d5bd7f")
## The recovered .RINGING_EARS loop. It plays on Master, past the World bus it deafens.
const RINGING := preload("res://audio/flashbang/ringing_ears.wav")
## Fraction of a flash the screen stays solid white before the after-image fades.
const WHITEOUT_HOLD := 0.45
## The ears ring this many times as long as the eyes stay white.
const RING_STRETCH := 2.0
## The world goes quiet just after the bang, so the bang itself still lands.
const DEAF_ATTACK := 0.15
const DEAF_FLOOR_DB := -36.0
const DEAF_CUTOFF_HZ := 300.0
const RING_DB := -6.0
var back := CanvasLayer.new()
var front := CanvasLayer.new()
var scope := Control.new()
var whiteout := ColorRect.new()
var root := Control.new()
var status := Label.new()
var prompt := Label.new()
var damage := Label.new()
var menu := PanelContainer.new()
var menu_text := Label.new()
var scope_on: bool = false
var scope_caption: String = ""
var flash_left: float = 0.0
var flash_total: float = 1.0
var ringing := AudioStreamPlayer.new()
var deaf_left: float = 0.0
var deaf_total: float = 1.0
var deaf_age: float = 0.0
var muffle: float = 0.0
var damage_left: float = 0.0

func _ready() -> void:
	back.layer = 0
	front.layer = 10
	add_child(back)
	add_child(front)
	scope.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scope.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scope.visible = false
	scope.draw.connect(_draw_scope)
	back.add_child(scope)
	whiteout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	whiteout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	whiteout.color = Color(1, 1, 1, 0)
	front.add_child(whiteout)
	ringing.stream = RINGING
	ringing.bus = &"Master"
	add_child(ringing)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	front.add_child(root)
	_label(status, 20, GOLD, Vector2(0, 96))
	_label(prompt, 18, INK, Vector2(0, 520))
	_label(damage, 22, GOLD, Vector2(0, 318))
	var backing := StyleBoxFlat.new()
	backing.bg_color = Color(0.07, 0.09, 0.08, 0.86)
	backing.set_content_margin_all(18)
	backing.set_corner_radius_all(3)
	menu.add_theme_stylebox_override("panel", backing)
	menu.visible = false
	root.add_child(menu)
	menu_text.add_theme_font_size_override("font_size", 18)
	menu_text.add_theme_color_override("font_color", INK)
	menu.add_child(menu_text)
	get_viewport().size_changed.connect(_layout)
	_layout()

func _label(label: Label, font_size: int, colour: Color, where: Vector2) -> void:
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", colour)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("outline_size", 6)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = where
	label.size = Vector2(LAYOUT_SIZE.x, 30)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(label)

func _layout() -> void:
	root.size = LAYOUT_SIZE
	root.scale = get_viewport().get_visible_rect().size / LAYOUT_SIZE

func set_scope(on: bool, caption: String = "") -> void:
	scope_on = on
	scope_caption = caption
	scope.visible = on
	scope.queue_redraw()

## Whites the screen out for `seconds`, and deafens for longer under ringing ears.
func flash(seconds: float) -> void:
	flash_left = maxf(flash_left, seconds)
	flash_total = maxf(flash_left, 0.01)
	if deaf_left <= 0.0:
		deaf_age = 0.0
	deaf_left = maxf(deaf_left, seconds * RING_STRETCH)
	deaf_total = maxf(deaf_left, 0.01)

func clear_flash() -> void:
	flash_left = 0.0
	deaf_left = 0.0
	_hear(0.0)

func show_status(text: String) -> void:
	status.text = text

func show_prompt(text: String) -> void:
	prompt.text = text

func show_damage(amount: float, dropped: bool) -> void:
	damage.text = ("DOWN  -%d" if dropped else "-%d") % roundi(amount)
	damage_left = 0.8

func show_menu(title: String, lines: Array, choice: int, footer: String) -> void:
	var text := title + "\n"
	for index: int in range(lines.size()):
		text += "\n%s %s" % ["▶" if index == choice else "   ", lines[index]]
	menu_text.text = text + "\n\n" + footer
	menu.visible = true
	menu.reset_size()
	menu.position = (LAYOUT_SIZE - menu.size) * Vector2(0.5, 0.42)

func hide_menu() -> void:
	menu.visible = false

func _process(delta: float) -> void:
	flash_left = maxf(0.0, flash_left - delta)
	# Solid white at first, then the after-image fades.
	whiteout.color.a = smoothstep(0.0, 1.0 - WHITEOUT_HOLD, flash_left / flash_total) if flash_left > 0.0 else 0.0
	_hear(delta)
	damage_left = maxf(0.0, damage_left - delta)
	damage.visible = damage_left > 0.0
	damage.modulate.a = clampf(damage_left / 0.3, 0.0, 1.0)
	if menu.visible:
		menu.position = (LAYOUT_SIZE - menu.size) * Vector2(0.5, 0.42)

## Rings the ears and muffles everything on the World bus, loudest just after the bang.
func _hear(delta: float) -> void:
	deaf_left = maxf(0.0, deaf_left - delta)
	deaf_age += delta
	var left := deaf_left / deaf_total
	var amount := smoothstep(0.0, 0.6, left) * clampf(deaf_age / DEAF_ATTACK, 0.0, 1.0) if deaf_left > 0.0 else 0.0
	if amount != muffle:
		muffle = amount
		var bus := AudioServer.get_bus_index(&"World")
		if bus >= 0:
			AudioServer.set_bus_volume_db(bus, DEAF_FLOOR_DB * muffle)
			var filter := AudioServer.get_bus_effect(bus, 0) as AudioEffectLowPassFilter
			if filter != null:
				filter.cutoff_hz = 20000.0 * pow(DEAF_CUTOFF_HZ / 20000.0, muffle)
	if deaf_left > 0.0:
		ringing.volume_db = RING_DB + linear_to_db(maxf(smoothstep(0.0, 0.4, left), 0.001))
		if not ringing.playing and DisplayServer.get_name() != "headless":
			ringing.play()
	elif ringing.playing:
		ringing.stop()

func _exit_tree() -> void:
	clear_flash()

func _draw_scope() -> void:
	preload("res://scripts/ui/recovered_scope.gd").draw(scope, scope.size)
	if scope_caption != "":
		# Our weapon strip occupies the original bottom-left caption location.
		scope.draw_string(ThemeDB.fallback_font, Vector2(scope.size.x * 0.5 - 38, scope.size.y * 0.93), "ZOOM: " + scope_caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, INK)
