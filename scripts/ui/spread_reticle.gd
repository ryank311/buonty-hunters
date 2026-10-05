class_name SpreadReticle
extends Control
## Original HUD2 bitmaps in their 640x448 coordinate space. Gameplay still supplies
## the prototype's real cone/recoil; see tools/recovery/HUD.md for fidelity limits.

const Combat := preload("res://scripts/combat/combat.gd")
const SOURCE_SIZE := Vector2(640, 448)
const DIRECTIONS := [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]
const REST := Color8(200, 200, 24)
const FRIEND := Color8(24, 200, 44)
const ENEMY := Color8(200, 24, 44)
const SETS := {
	"rifle": [preload("res://art/ui/recovered/hud2/ret_rifle_01.png"), preload("res://art/ui/recovered/hud2/ret_rifle_02.png")],
	"sidearm": [preload("res://art/ui/recovered/hud2/ret_sidearm_01.png"), preload("res://art/ui/recovered/hud2/ret_sidearm_02.png")],
	"shotgun": [preload("res://art/ui/recovered/hud2/ret_shotgun_01.png"), preload("res://art/ui/recovered/hud2/ret_shotgun_02.png")],
	"grenade": [preload("res://art/ui/recovered/hud2/ret_grenade_02.png"), preload("res://art/ui/recovered/hud2/ret_grenade_01.png")],
}
const ACCURACY := preload("res://art/ui/recovered/hud2/ret_accuracy.png")
var center_ring := Control.new()
var spread_marks: Array[Control] = []
var feedback := Control.new()
var family: String = "rifle"
var center_texture: Texture2D = SETS.rifle[0]
var arm_texture: Texture2D = SETS.rifle[1]
var circle_radius: float = 32.0
var pixel_scale := Vector2.ONE
# Distances below are in original HUD pixels, before presentation scaling.
var displayed_spread: float = 0.0
var target_spread: float = 0.0
var mark_distance: float = 0.0
var ink: Color = REST
var blocked: bool = false
var pip_alpha: float = 0.0
var charge: float = 0.0
var pip_offset := Vector2.ZERO
var _pip_target: bool = false

func _ready() -> void:
	name = "Reticle"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	center_ring.name = "CenterRing"
	center_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center_ring)
	center_ring.draw.connect(_draw_center)
	for index: int in range(4):
		var mark := Control.new()
		mark.name = ["North", "East", "South", "West"][index]
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(mark)
		spread_marks.append(mark)
		mark.draw.connect(_draw_arm.bind(mark, index))
	feedback.name = "MuzzleAccuracy"
	feedback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(feedback)
	feedback.draw.connect(func() -> void:
		feedback.draw_texture(ACCURACY, -ACCURACY.get_size() * 0.5, Color(1, 1, 1, pip_alpha))
	)

func select_family(next: String) -> void:
	if next == family:
		return
	family = next
	center_texture = SETS[family][0]
	arm_texture = SETS[family][1]
	pip_alpha = 0.0
	_pip_target = false

func update_weapon(weapon: PracticeWeapon, delta: float, paused: bool) -> void:
	var profile := weapon.profile
	select_family("grenade" if profile.kind != "firearm" else "sidearm" if profile.hold == "pistol" else "shotgun" if profile.pellets > 1 else "rifle")
	var player := weapon.player
	var camera := player.camera_rig.camera
	var hidden: bool = paused or weapon.scoped or weapon.director.dead or weapon.director.class_open or weapon.director.loot_open
	var recoil_pixels := player.camera_rig.reticle_offset(size)
	ink = REST
	charge = clampf(weapon.throw_charge, 0.0, 1.0) if weapon.ammo > 0 else 0.0
	_pip_target = false
	if not hidden:
		# Query without random spread so the tint/pip do not flicker between pellets.
		var result := weapon.query_aim()
		var target: Node3D = result.get("collider") as Node3D
		if not weapon.blocked and is_instance_valid(target) and target.is_in_group(Combat.ACTOR_GROUP) and Combat.is_alive(target) and player.global_position.distance_to(target.global_position) <= 32.0:
			ink = FRIEND if Combat.team_of(target) == Combat.team_of(player) else ENEMY
		if profile.kind == "firearm" and weapon.blocked and not camera.is_position_behind(weapon.hit_point):
			var viewport_size := get_viewport().get_visible_rect().size
			pip_offset = (camera.unproject_position(weapon.hit_point) * size / viewport_size - size * 0.5 - recoil_pixels) / (size / SOURCE_SIZE)
			pip_offset = pip_offset.clamp(Vector2(-200, -200), Vector2(200, 200))
			_pip_target = pip_offset.length() > center_texture.get_width() * 0.5
	# Include the shotgun pellet cone, which the previous reticle omitted.
	update_reticle(weapon.spread_degrees() + profile.pellet_spread, camera.fov, delta, weapon.blocked, false, hidden, recoil_pixels)

func update_reticle(spread_degrees: float, vertical_fov: float, delta: float, obstructed: bool, _hit_flash: bool, paused: bool, recoil_pixels: Vector2 = Vector2.ZERO) -> void:
	visible = not paused
	blocked = obstructed
	pixel_scale = size / SOURCE_SIZE
	circle_radius = center_texture.get_width() * 0.5 * pixel_scale.x
	# Original third-person draw halves the accuracy displacement. Use the real
	# weapon cone instead of adding unrelated cosmetic bloom.
	target_spread = tan(deg_to_rad(spread_degrees)) * SOURCE_SIZE.y * 0.5 / tan(deg_to_rad(vertical_fov * 0.5)) * 0.5
	var rate := 35.0 if target_spread > displayed_spread else 9.0
	displayed_spread = lerpf(displayed_spread, target_spread, 1.0 - exp(-rate * delta))
	mark_distance = displayed_spread
	var center := size * 0.5 + recoil_pixels
	center_ring.position = center
	center_ring.scale = pixel_scale
	feedback.position = center + pip_offset * pixel_scale
	feedback.scale = pixel_scale
	pip_alpha = move_toward(pip_alpha, 1.0 if _pip_target and blocked and not paused else 0.0, delta * 15.0)
	for index: int in range(spread_marks.size()):
		var mark := spread_marks[index]
		var direction: Vector2 = Vector2(-1, 1).rotated(index * PI * 0.5) if family == "shotgun" else DIRECTIONS[index]
		mark.position = center + direction * mark_distance * pixel_scale
		mark.scale = pixel_scale
		mark.visible = family != "grenade"
		mark.queue_redraw()
	center_ring.queue_redraw()
	feedback.queue_redraw()

func _draw_center() -> void:
	# The grenade aiming cross sits at the top of its texture; the meter hangs below.
	var origin := Vector2(-center_texture.get_width() * 0.5, 0) if family == "grenade" else -center_texture.get_size() * 0.5
	center_ring.draw_texture(center_texture, origin)
	if family == "grenade" and charge > 0.0:
		# Reveal the recovered meter from its base up as the existing throw charges.
		var extent := arm_texture.get_size()
		var height := extent.y * charge
		var source := Rect2(0, extent.y - height, extent.x, height)
		center_ring.draw_texture_rect_region(arm_texture, Rect2(source.position + origin, source.size), source, ink)

func _draw_arm(mark: Control, index: int) -> void:
	var extent := arm_texture.get_size()
	if family == "shotgun":
		# A recovered quarter-circle, repeated around the four corners.
		mark.draw_set_transform(Vector2.ZERO, index * PI * 0.5)
		mark.draw_texture(arm_texture, Vector2(-extent.x, 0), ink)
	else:
		# Centre the visible stripe, which lies along the texture's right edge.
		# The rifle stripe is centred 1.5px in; the pistol stripe is 1px in.
		mark.draw_set_transform(Vector2.ZERO, DIRECTIONS[index].angle() - PI * 0.5)
		mark.draw_texture(arm_texture, Vector2(-extent.x + (1.0 if family == "sidearm" else 1.5), 0), ink)
	mark.draw_set_transform(Vector2.ZERO)
