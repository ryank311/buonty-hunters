extends Node
## Screen-space feedback for combat that the main HUD does not own: the scope view, the
## flashbang whiteout, damage numbers, the elimination banner, and the two small menus
## (searching a body, choosing a class). The scope mask sits under the HUD; everything
## else sits over it.

const LAYOUT_SIZE := Vector2(1024, 768) # same authored size as the HUD, scaled to the viewport
const INK := Color("dce3d2")
const GOLD := Color("d5bd7f")
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

## Whites the screen out, fading over `seconds`.
func flash(seconds: float) -> void:
	flash_left = maxf(flash_left, seconds)
	flash_total = maxf(flash_left, 0.01)

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
	# Hold near white, then clear quickly at the end.
	whiteout.color.a = pow(flash_left / flash_total, 0.6) if flash_left > 0.0 else 0.0
	damage_left = maxf(0.0, damage_left - delta)
	damage.visible = damage_left > 0.0
	damage.modulate.a = clampf(damage_left / 0.3, 0.0, 1.0)
	if menu.visible:
		menu.position = (LAYOUT_SIZE - menu.size) * Vector2(0.5, 0.42)

func _draw_scope() -> void:
	var size := scope.size
	var centre := size * 0.5
	var radius := minf(size.x, size.y) * 0.46
	var reach := size.length()
	# Black everywhere outside the lens: a ring of quads from the lens edge outward.
	var steps := 64
	for index: int in range(steps):
		var a := Vector2.from_angle(TAU * index / steps)
		var b := Vector2.from_angle(TAU * (index + 1) / steps)
		scope.draw_colored_polygon(PackedVector2Array([centre + a * radius, centre + b * radius, centre + b * reach, centre + a * reach]), Color.BLACK)
	scope.draw_arc(centre, radius, 0.0, TAU, 96, Color.BLACK, 3.0)
	var ink := Color(0.03, 0.03, 0.03, 0.95)
	var gap := radius * 0.06
	for direction: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		scope.draw_line(centre + direction * gap, centre + direction * radius * 0.32, ink, 1.0)
		scope.draw_line(centre + direction * radius * 0.32, centre + direction * radius, ink, 3.0)
	# Hold-over ticks below the centre for judging bullet drop.
	for tick: int in range(1, 5):
		var y := radius * 0.07 * tick
		scope.draw_line(centre + Vector2(-6, y), centre + Vector2(6, y), ink, 1.0)
	scope.draw_circle(centre, 1.2, Color(0.75, 0.1, 0.08))
	if scope_caption != "":
		scope.draw_string(ThemeDB.fallback_font, centre + Vector2(radius * 0.42, radius * 0.86), scope_caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, INK)
