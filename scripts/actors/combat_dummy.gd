extends StaticBody3D
## A stand-in soldier for the practice build: a teammate or an enemy with a class,
## health, and a body that stays where it falls. It does not think. With a fire_interval
## it fires harmless bursts that land beside the player (muzzle flash, tracers, the
## sound the HUD's gunfire marks report); its rounds never hurt anyone. Real
## players and bots will replace it; the combat code relies only on what is declared
## here (team, alive, display_name, apply_damage, the loot and view helpers).

const Combat := preload("res://scripts/combat/combat.gd")
const Loadouts := preload("res://scripts/combat/loadouts.gd")
const PROXY := preload("res://scripts/player/soldier_proxy.gd")
const RAGDOLL := preload("res://scripts/actors/soldier_ragdoll.gd")
const STAND_HEIGHT := 1.8
const TEAM_TINT := {0: Color("5f7f96"), 1: Color("9a5a44")}

@export var display_name: String = "SOLDIER"
## 0 is the player's team; any other number is an enemy team.
@export var team: int = 1
@export_enum("rifleman", "marksman", "breacher", "pointman") var soldier_class: String = "rifleman"
## Metres walked either side of the start, along the dummy's own left-right axis.
@export var travel: float = 0.0
@export var walk_speed: float = 1.4
## Seconds between harmless three-round bursts fired near the player; 0 never fires.
@export var fire_interval: float = 0.0
const BURST := 3
const BURST_GAP := 0.11
var fire_clock: float = 0.0
var burst_left: int = 0
var rounds_fired: int = 0
var max_health: float = 100.0
var health: float = 100.0
var alive: bool = true
var flashed: float = 0.0
var last_damage: float = 0.0
var last_hit: Dictionary = {}
var drift := Vector3.ZERO
var ragdoll: Node3D
## What a searcher can take: slot 0 the primary, slot 1 the pistol, each {profile, ammo, reserve}.
var carried: Array[Dictionary] = []
var soldier: Node3D
var shape_node := CollisionShape3D.new()
var label := Label3D.new()
var start: Transform3D
var elapsed: float = 0.0
var standing := CapsuleShape3D.new()
var fallen := BoxShape3D.new()

func _ready() -> void:
	collision_layer = 4
	collision_mask = 0
	add_to_group(Combat.ACTOR_GROUP)
	# The session resets everything in this group when the player respawns.
	add_to_group(&"range_targets")
	standing.radius = 0.32
	standing.height = STAND_HEIGHT
	fallen.size = Vector3(0.65, 0.4, 1.8)
	add_child(shape_node)
	soldier = Node3D.new()
	soldier.set_script(PROXY)
	add_child(soldier)
	_tint()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = 0.0045
	label.font_size = 48
	label.outline_size = 10
	label.position.y = 2.1
	add_child(label)
	start = transform
	reset_target()

func _physics_process(delta: float) -> void:
	flashed = maxf(0.0, flashed - delta)
	soldier.flash.advance(delta)
	if not alive:
		return
	if fire_interval > 0.0:
		_fire_bursts(delta)
	var sideways := 0.0
	if travel > 0.0:
		elapsed += delta
		var phase := elapsed * walk_speed / travel
		position = start.origin + start.basis.x * sin(phase) * travel
		sideways = cos(phase) * walk_speed
		drift = start.basis.x * sideways
	soldier.pose(0, absf(sideways), Vector2(sideways, 0.0), 0.0, 0.0, delta)

## One harmless round toward `point`: flash, gunfire report and sometimes a tracer
## (always the first after a pause; see Gunfire).
func fire_at(point: Vector3) -> void:
	if not alive or carried.is_empty():
		return
	var profile: WeaponProfile = carried[0].profile
	rounds_fired += 1
	soldier.flash.fire(profile.recovered_model)
	Gunfire.fired(self, soldier.muzzle.global_position, point, profile.recovered_model, team)

func _fire_bursts(delta: float) -> void:
	fire_clock -= delta
	if fire_clock > 0.0:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	if burst_left <= 0:
		burst_left = BURST
	# Wide of the player's view point, so the rounds pass close and land beside them.
	var target := camera.global_position + camera.global_basis.x * (2.0 if rounds_fired % 2 == 0 else -2.0) + Vector3.DOWN * 1.2
	fire_at(target)
	burst_left -= 1
	fire_clock = BURST_GAP if burst_left > 0 else fire_interval

func apply_damage(amount: float, info: Dictionary = {}) -> float:
	if not alive:
		return 0.0
	if info.get("regional", true) and info.has("position"):
		amount *= Combat.region_multiplier(self, info.position)
	last_damage = amount
	last_hit = info
	health = maxf(0.0, health - amount)
	if health <= 0.0:
		die()
	return amount

func apply_flash(seconds: float) -> void:
	flashed = maxf(flashed, seconds)

func die() -> void:
	alive = false
	health = 0.0
	# The body stays where it fell, low to the ground, and can be searched.
	shape_node.shape = fallen
	shape_node.position.y = 0.2
	# The animated soldier goes limp: a physics body takes over from the last pose,
	# thrown by the killing blow. Without one (a body placed dead) it folds in place.
	ragdoll = RAGDOLL.new()
	Combat.spawn(get_parent(), ragdoll)
	ragdoll.build(soldier, RAGDOLL.impact(self, last_hit, last_damage) if not last_hit.is_empty() else {}, drift)
	soldier.visible = false
	label.text = "%s · down" % display_name
	label.modulate = Color(0.75, 0.75, 0.72)

func reset_target() -> void:
	transform = start
	elapsed = 0.0
	health = max_health
	alive = true
	flashed = 0.0
	last_damage = 0.0
	last_hit = {}
	drift = Vector3.ZERO
	if is_instance_valid(ragdoll):
		ragdoll.queue_free()
	soldier.visible = true
	shape_node.shape = standing
	shape_node.position.y = STAND_HEIGHT * 0.5
	label.text = display_name
	label.modulate = TEAM_TINT.get(team, Color.GRAY).lightened(0.35)
	carried.clear()
	var loadout: Resource = Loadouts.by_id(soldier_class)
	for profile: WeaponProfile in [loadout.primary, loadout.secondary]:
		carried.append({"profile": profile.duplicate(), "ammo": profile.magazine_size, "reserve": profile.starting_reserve})
	soldier.reset_pose()
	_show_weapon()
	soldier.pose(0, 0.0, Vector2.ZERO, 0.0, 0.0, 2.0)

func body_height() -> float:
	return STAND_HEIGHT if alive else 0.4

func eye_position() -> Vector3:
	return global_position + Vector3.UP * (1.6 if alive else 0.3)

func view_direction() -> Vector3:
	return -global_basis.z

## Hands over the weapon in `slot` and keeps `incoming` in its place.
func swap_weapon(slot: int, incoming: Dictionary) -> Dictionary:
	var taken := carried[slot]
	carried[slot] = incoming
	_show_weapon()
	return taken

func _show_weapon() -> void:
	var primary: WeaponProfile = carried[0].profile
	soldier.set_weapon(0 if primary.hold == "long" else 1)
	if soldier.soldier_skin == null:
		soldier.rifle_mesh.scale = primary.visual_scale if primary.hold == "long" else Vector3.ONE
		soldier.pistol_mesh.scale = primary.visual_scale if primary.hold == "pistol" else Vector3.ONE

func _tint() -> void:
	var tint: Color = TEAM_TINT.get(team, Color.GRAY)
	var swapped: Dictionary = {}
	for part: MeshInstance3D in soldier.parts.values():
		var original := part.material_override as StandardMaterial3D
		if original == null:
			continue
		if not swapped.has(original):
			var copy := original.duplicate() as StandardMaterial3D
			copy.albedo_color = original.albedo_color.lerp(tint, 0.55)
			swapped[original] = copy
		part.material_override = swapped[original]
	if soldier.soldier_skin != null:
		soldier.soldier_skin.tint(tint, 0.55)
