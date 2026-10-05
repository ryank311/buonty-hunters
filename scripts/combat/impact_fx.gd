class_name ImpactFX
extends Node3D
## The original bullet impacts (resources/recovered/impacts.json, from
## tools/recovery/prepare_impacts.py): each surface's bullet_hit_* effect, its
## emitter layers rebuilt as one-shot particle bursts with the recovered textures,
## counts, spread, gravity, speed, life, size and colour keys.
##
## Layers leave along the surface normal turned partly toward the bullet's ricochet,
## so ground dust leans the way the round was travelling and walls puff outward.
## Flash layers (the muzzle-flash and fire-puff glows) decode with a speed and size
## that are not a moving particle's; they play as a brief stationary glow instead.

const DATA := "res://resources/recovered/impacts.json"
## Physics layer 10: recovered water surfaces. Off every movement and bullet mask, so
## shots pass into the water; play_shot looks for it separately to splash.
const WATER_LAYER := 1 << 9
const TEXTURES := "res://art/effects/impacts/"
const GLOWS := ["effect_muzzle01", "explosion2", "effect_spark01", "effect_spark02"]
const FLASHES := ["effect_muzzle01", "explosion2"]
## The PS2 spawned 45-120 particles a layer; a fraction keeps the look at a lower cost.
const COUNT_SCALE := 0.25
## How far the emission turns from the normal toward the ricochet (0 none, 1 all).
const RICOCHET_LEAN := 0.45
static var data: Dictionary = {}
static var quad: QuadMesh
static var materials: Dictionary = {}
var life := 0.0
## The recovered effect this impact plays.
var effect := ""

static func library() -> Dictionary:
	if data.is_empty():
		data = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	return data

## The recovered effect a surface plays, or "" for none (bullets pass through it).
static func effect_for(surface: String) -> String:
	var entry: Dictionary = library().surfaces.get(surface, library().surfaces.stone)
	return entry.effect if entry.effect != null else ""

## The surface a collider presents: recovered map collision carries it as "surface"
## metadata; soldiers are people; anything else is treated as stone (concrete).
static func surface_of(collider: Object) -> String:
	if collider is Node:
		if collider.has_meta(&"surface"):
			return collider.get_meta(&"surface")
		if collider.is_in_group(&"combat_actors") or collider.is_in_group(&"players"):
			return "person"
	return "stone"

## Plays a round's impact from `from` to what it struck: a splash where it enters water
## first, otherwise the struck surface's own effect.
static func play_shot(parent: Node3D, from: Vector3, hit: Dictionary) -> void:
	if hit.is_empty() or not parent.is_inside_tree():
		return
	var to: Vector3 = hit.position
	var water := parent.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, WATER_LAYER))
	if not water.is_empty():
		play(parent, water, to - from, "water")
		return
	play(parent, hit, to - from)

## Plays the impact of a round travelling along `direction` that struck `hit`.
static func play(parent: Node, hit: Dictionary, direction: Vector3, surface: String = "") -> ImpactFX:
	if hit.is_empty() or parent == null or not parent.is_inside_tree():
		return null
	if surface == "":
		surface = surface_of(hit.get("collider"))
	var effect := effect_for(surface)
	var layers: Array = library().effects.get(effect, [])
	if layers.is_empty():
		return null
	var fx := ImpactFX.new()
	fx.effect = effect
	var tree := parent.get_tree()
	(tree.current_scene if tree.current_scene != null else tree.root).add_child(fx)
	var normal: Vector3 = hit.get("normal", Vector3.UP)
	var bounce := direction.normalized().bounce(normal) if direction.length() > 0.001 else normal
	var out := normal.lerp(bounce, RICOCHET_LEAN).normalized()
	var up := Vector3.UP if absf(out.dot(Vector3.UP)) < 0.98 else Vector3.FORWARD
	fx.global_transform = Transform3D(Basis.looking_at(out, up) * Basis(Vector3.RIGHT, -PI * 0.5), hit.position + normal * 0.02)
	for layer: Dictionary in layers:
		fx._add_layer(layer)
	return fx

func _process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		queue_free()

func _add_layer(layer: Dictionary) -> void:
	var texture: String = layer.get("texture", "") if layer.get("texture") != null else ""
	if texture == "" or not ResourceLoader.exists(TEXTURES + texture + ".png"):
		return
	var flash: bool = texture in FLASHES
	var burst := CPUParticles3D.new()
	burst.one_shot = true
	burst.explosiveness = 0.92
	burst.local_coords = false
	burst.amount = 1 if flash else clampi(int(round(maxf(float(layer.count), 12.0) * COUNT_SCALE)), 2, 30)
	var life_range: Array = layer.life
	burst.lifetime = 0.09 if flash else maxf(float(life_range[1]), 0.05)
	burst.lifetime_randomness = 0.0 if flash else clampf(1.0 - float(life_range[0]) / maxf(float(life_range[1]), 0.001), 0.0, 1.0)
	# Emission leaves along local +Y (the effect's out direction), jittered per axis.
	var spread: Array = layer.spread_deg
	burst.direction = Vector3.UP
	burst.spread = clampf(maxf(absf(float(spread[1])), maxf(absf(float(spread[0])), absf(float(spread[4])))), 4.0, 75.0)
	var speed := 0.0 if flash else float(layer.speed)
	burst.initial_velocity_min = speed * 0.6
	burst.initial_velocity_max = speed * 1.3
	var accel: Array = layer.acceleration
	burst.gravity = Vector3.ZERO if flash else Vector3(float(accel[0]), float(accel[1]), float(accel[2]))
	burst.damping_min = float(layer.drag) * 20.0
	burst.damping_max = burst.damping_min
	var size_range: Array = layer.size
	burst.scale_amount_min = 0.16 if flash else maxf(float(size_range[0]), 0.04)
	burst.scale_amount_max = 0.22 if flash else maxf(float(size_range[1]), 0.05)
	burst.angle_min = 0.0
	burst.angle_max = 360.0
	burst.color_ramp = _ramp(layer.colors)
	burst.mesh = _quad()
	burst.material_override = _material(texture)
	burst.emitting = true
	add_child(burst)
	life = maxf(life, burst.lifetime + 0.1)

static func _ramp(keys: Array) -> Gradient:
	var ramp := Gradient.new()
	if keys.size() < 2:
		keys = [[0.0, 1.0, 1.0, 1.0, 1.0], [1.0, 1.0, 1.0, 1.0, 0.0]]
	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	for key: Array in keys:
		offsets.append(clampf(float(key[0]), 0.0, 1.0))
		colors.append(Color(float(key[1]), float(key[2]), float(key[3]), float(key[4])))
	ramp.offsets = offsets
	ramp.colors = colors
	return ramp

static func _quad() -> QuadMesh:
	if quad == null:
		quad = QuadMesh.new()
		quad.size = Vector2.ONE
	return quad

static func _material(texture: String) -> StandardMaterial3D:
	if not materials.has(texture):
		var look := StandardMaterial3D.new()
		look.albedo_texture = load(TEXTURES + texture + ".png")
		look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		look.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		look.vertex_color_use_as_albedo = true
		look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		look.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		look.cull_mode = BaseMaterial3D.CULL_DISABLED
		if texture in GLOWS:
			look.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		materials[texture] = look
	return materials[texture]
