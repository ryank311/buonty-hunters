extends Control
## CZActionBitmap: original 50x50 icons at (306,365), 62-pixel neighbors and the
## available blue/grey palettes. The original pulsed at five units a second; this
## breathes slower and fainter, and the icons sit more transparently over the view.
## The recovered action bitmaps decode bottom-up, so they are drawn flipped.
const SOURCE := Vector2(640, 448)
const FALLBACK = preload("res://art/ui/recovered/hud/action_x.png")
## Pulse units a second (one breath is two units) and how much of the original
## brightening it keeps; the selected and other icons' opacity.
const PULSE_RATE := 1.4
const PULSE_DEPTH := 0.4
const SELECTED_ALPHA := 0.7
const OTHER_ALPHA := 0.4
var icons: Dictionary = {}
var entries: Array[Dictionary] = []
var selected: int = 0
var pulse: float = 0.0
var caption := Label.new()
var hint: String = ""
var icon_rects: Array[Rect2] = []

func _ready() -> void:
	name = "ContextActions"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.add_theme_font_size_override("font_size", 16)
	caption.add_theme_color_override("font_color", Color("dce3d2"))
	caption.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	caption.add_theme_constant_override("outline_size", 3)
	add_child(caption)

func update_actions(actions: Node, delta: float) -> void:
	visible = actions.available() and not actions.offers.is_empty() and not actions.player.weapon.scoped
	entries = actions.offers.duplicate()
	selected = actions.selected
	pulse = fposmod(pulse + delta * PULSE_RATE, 2.0)
	icon_rects.clear()
	if visible:
		var offer: Dictionary = entries[selected]
		hint = "%s  %s" % [actions.button_hint(), offer.label if offer.enabled else offer.reason]
		if entries.size() > 1:
			hint += "  ·  TAB / ↑↓ SELECT"
		caption.text = hint
		caption.position = Vector2(146, 418) * size / SOURCE
		caption.size = Vector2(320, 22) * size / SOURCE
	queue_redraw()

func _draw() -> void:
	if not visible or entries.is_empty():
		return
	var order: Array[int] = [selected]
	for index: int in range(entries.size()):
		if index != selected:
			order.append(index)
	var scale := size / SOURCE
	for slot: int in range(mini(order.size(), 3)):
		var entry: Dictionary = entries[order[slot]]
		var path: String = "res://art/ui/recovered/hud/" + entry.icon
		if not icons.has(path):
			icons[path] = load(path) if ResourceLoader.exists(path) else FALLBACK
		var amount := smoothstep(0.0, 1.0, 1.0 - absf(pulse - 1.0)) * PULSE_DEPTH
		var base := Vector3(20, 50, 60) if entry.enabled else Vector3(42, 42, 42)
		var change := Vector3(35, 80, 80) if entry.enabled else Vector3(8, 8, 8)
		var color := (base + change * amount) / 128.0
		var tint := Color(color.x, color.y, color.z, SELECTED_ALPHA if slot == 0 else OTHER_ALPHA)
		var x: float = 306.0 + [0.0, -62.0, 62.0][slot]
		var rect := Rect2(Vector2(x - 25.0, 365.0) * scale, Vector2(50, 50) * scale)
		icon_rects.append(rect)
		# Flip about the icon's horizontal centre line.
		draw_set_transform(Vector2(0.0, rect.position.y * 2.0 + rect.size.y), 0.0, Vector2(1.0, -1.0))
		draw_texture_rect(icons[path], rect, false, tint)
		draw_set_transform(Vector2.ZERO)
