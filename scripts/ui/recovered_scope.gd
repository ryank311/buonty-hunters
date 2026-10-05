extends RefCounted
## Each source texture is the bottom-left quadrant of the original scope.
const TUBE := preload("res://art/ui/recovered/hud2/ret_scope_01.png")
const SHADE := preload("res://art/ui/recovered/hud2/ret_scope_02.png")

static func draw(canvas: CanvasItem, size: Vector2) -> void:
	var scale := size / Vector2(640, 448)
	for texture: Texture2D in [TUBE, SHADE]:
		for flip: Vector2 in [Vector2.ONE, Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			canvas.draw_set_transform(size * 0.5, 0.0, scale * flip)
			# Original mirrored UVs stop just inside the edge (0.01..0.99).
			canvas.draw_texture_rect_region(texture, Rect2(-320, 0, 320, 320), Rect2(texture.get_size() * 0.01, texture.get_size() * 0.98))
	canvas.draw_set_transform(Vector2.ZERO)
