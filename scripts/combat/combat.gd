extends RefCounted
## Shared combat rules: who counts as an actor, which team they are on, and how bullets,
## blasts, and flashes hurt them. The player and the practice dummies both go through
## these helpers, so real players and bots can replace the dummies without new rules.
##
## An actor is any Node3D in ACTOR_GROUP. It exposes a team and an alive flag, either as
## members (dummies) or as metadata (the player), and takes damage through apply_damage()
## or, for the player, its health property.

const ACTOR_GROUP := &"combat_actors"
const SPAWNED_GROUP := &"combat_spawned"
const WORLD_MASK := 1
const SHOT_MASK := 1 | 4
# docs/DESIGN.md: 34 torso, 100 head, 25 limb for the rifle; other weapons keep the ratios.
const HEAD_MULTIPLIER := 100.0 / 34.0
const LIMB_MULTIPLIER := 25.0 / 34.0

static func team_of(actor: Object) -> int:
	if actor.has_meta(&"team"):
		return int(actor.get_meta(&"team"))
	var team: Variant = actor.get("team")
	return int(team) if team != null else -1

static func is_alive(actor: Object) -> bool:
	if actor.has_meta(&"alive"):
		return bool(actor.get_meta(&"alive"))
	var alive: Variant = actor.get("alive")
	return bool(alive) if alive != null else true

static func name_of(actor: Object) -> String:
	if actor.has_meta(&"display_name"):
		return str(actor.get_meta(&"display_name"))
	var title: Variant = actor.get("display_name")
	return str(title) if title != null else str(actor.name)

static func height_of(actor: Node3D) -> float:
	if actor.has_method("body_height"):
		return actor.body_height()
	var stance: Variant = actor.get("stance")
	return StanceController.HEIGHTS[stance.current] if stance != null else 1.8

static func centre_of(actor: Node3D) -> Vector3:
	return actor.global_position + Vector3.UP * height_of(actor) * 0.6

## Head, torso, or limb, judged by how high on a standing or crouched body the hit landed.
static func region_multiplier(actor: Node3D, hit_position: Vector3) -> float:
	var height := height_of(actor)
	if height < 1.0:
		return 1.0
	var fraction := (hit_position.y - actor.global_position.y) / height
	if fraction >= 0.82:
		return HEAD_MULTIPLIER
	return LIMB_MULTIPLIER if fraction < 0.45 else 1.0

static func damage_at(profile: WeaponProfile, distance: float) -> float:
	var faded := smoothstep(profile.falloff_start, maxf(profile.falloff_start + 0.01, profile.falloff_end), distance)
	return profile.damage * lerpf(1.0, profile.minimum_damage, faded)

## Returns the damage actually dealt. `info` may carry "position", "source", "weapon",
## and "regional" (false for blasts, which ignore hit regions).
static func hurt(target: Object, amount: float, info: Dictionary = {}) -> float:
	if amount <= 0.0 or not is_instance_valid(target):
		return 0.0
	if target.has_method("apply_damage"):
		return target.apply_damage(amount, info)
	if target is Node and target.is_in_group(ACTOR_GROUP) and target.get("health") != null:
		if not is_alive(target):
			return 0.0
		if info.get("regional", true) and info.has("position"):
			amount *= region_multiplier(target, info.position)
		target.health -= amount
		target.set_meta(&"last_hit", info.get("weapon", ""))
		# Kept so a killing blow can throw the body (SoldierRagdoll.impact).
		target.set_meta(&"last_hit_info", info.merged({"damage": amount}))
		return amount
	if target.has_method("register_hit"):
		target.register_hit()
	return 0.0

static func clear_line(world: World3D, from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to, WORLD_MASK)
	return world.direct_space_state.intersect_ray(query).is_empty()

## Everything a blast can hurt: actors, plus practice targets that take damage.
static func _blast_targets(tree: SceneTree) -> Array[Node3D]:
	var found: Array[Node3D] = []
	for group: StringName in [ACTOR_GROUP, &"range_targets"]:
		for node: Node in tree.get_nodes_in_group(group):
			if node is Node3D and node.is_inside_tree() and not found.has(node):
				found.append(node)
	return found

## Line-of-sight-aware blast damage, strongest at the centre. With `direction` set the
## blast is a cone (the claymore): only targets within `cone_dot` of that direction.
## Returns [{target, damage}] for whatever was hurt.
static func blast(tree: SceneTree, origin: Vector3, radius: float, peak: float, info: Dictionary = {}, direction := Vector3.ZERO, cone_dot: float = -1.0) -> Array:
	var world := tree.root.get_world_3d()
	var hurt_list: Array = []
	for target: Node3D in _blast_targets(tree):
		var centre := centre_of(target) if target.is_in_group(ACTOR_GROUP) else target.global_position
		var offset := centre - origin
		var distance := offset.length()
		if distance > radius:
			continue
		if direction != Vector3.ZERO and distance > 0.3 and direction.dot(offset / distance) < cone_dot:
			continue
		# Cover between the blast and the body stops it; a slight lift keeps the floor out of the way.
		if not clear_line(world, origin + Vector3.UP * 0.15, centre):
			continue
		var details := info.duplicate()
		details["regional"] = false
		details["position"] = centre
		details["origin"] = origin
		var dealt := hurt(target, peak * (1.0 - distance / radius), details)
		if dealt > 0.0:
			hurt_list.append({"target": target, "damage": dealt})
	return hurt_list

## Blinds actors who can see the flash: longer the closer they are and the more directly
## they face it. Returns [{target, seconds}].
static func flash(tree: SceneTree, origin: Vector3, radius: float, seconds: float) -> Array:
	var world := tree.root.get_world_3d()
	var blinded: Array = []
	for actor: Node in tree.get_nodes_in_group(ACTOR_GROUP):
		if not actor is Node3D or not is_alive(actor):
			continue
		var eye: Vector3 = actor.eye_position() if actor.has_method("eye_position") else centre_of(actor)
		var view: Vector3 = actor.view_direction() if actor.has_method("view_direction") else -actor.global_basis.z
		# The player is blinded at the soldier's eyes, not at the camera behind them.
		var camera_rig: Variant = actor.get("camera_rig")
		if camera_rig != null:
			eye = actor.global_position + Vector3.UP * StanceController.EYE_HEIGHTS[actor.stance.current]
			view = camera_rig.aim_direction()
		var offset := origin - eye
		var distance := offset.length()
		if distance > radius or not clear_line(world, origin + Vector3.UP * 0.1, eye):
			continue
		var facing := clampf(view.dot(offset / maxf(distance, 0.01)), 0.0, 1.0)
		var strength := (1.0 - distance / radius) * lerpf(0.3, 1.0, facing)
		var duration := seconds * strength
		if duration < 0.3:
			continue
		if actor.has_method("apply_flash"):
			actor.apply_flash(duration)
		else:
			actor.set_meta(&"flashed", duration)
		blinded.append({"target": actor, "seconds": duration})
	return blinded

## Adds a spawned combat object (bullet, grenade, mine, smoke) and tags it so a reset
## can clear it. Pass the level as `parent` so a level change removes it too.
static func spawn(parent: Node, node: Node) -> void:
	node.add_to_group(SPAWNED_GROUP)
	parent.add_child(node)

static func clear_spawned(tree: SceneTree) -> void:
	for node: Node in tree.get_nodes_in_group(SPAWNED_GROUP):
		node.queue_free()
