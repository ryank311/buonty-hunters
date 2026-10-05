class_name Gunfire
extends RefCounted
## Who heard a shot, and which rounds are tracers. Both read each gun's original record
## (resources/recovered/muzzle_flashes.json): its Sound_Radius in metres and whether it
## is suppressed (no muzzle flash in its fire sequence). Every shot is reported to the
## "gunfire_listeners" group as heard_gunfire(origin, model, shooter, team, radius).

const LISTENERS := &"gunfire_listeners"
## The first round after a pause is a tracer, whether the gun is automatic or tapped;
## after it each round is one by chance, and never more than TRACER_GAP go by without.
const TRACER_CHANCE := 0.25
const TRACER_GAP := 6
## Physics ticks without a shot that make the next round a first round (0.6 s).
const PAUSE_TICKS := 36
## How far a tracer flies when the shot hits nothing.
const TRACER_REACH := 150.0
const TRACER := preload("res://scripts/combat/tracer.gd")

static func entry(model: String) -> Dictionary:
	RecoveredMuzzleFlash.flash_for(model)
	var entries: Array = RecoveredMuzzleFlash.data.weapons.get(model.to_lower(), [])
	return entries[0] if not entries.is_empty() else {}

static func suppressed(model: String) -> bool:
	return entry(model).get("suppressed", false)

## Metres within which the shot is heard; a gun with no record is heard at 60 m.
static func sound_radius(model: String) -> float:
	return float(entry(model).get("sound_radius_m", 60.0))

## Whether this round is a tracer: `first` after a pause, `since` the rounds fired
## since the shooter's last tracer, `roll` a random 0-1.
static func tracer_due(model: String, first: bool, since: int, roll: float) -> bool:
	if suppressed(model):
		return false
	return first or since >= TRACER_GAP or roll < TRACER_CHANCE

## Reports a shot fired from `origin` by `shooter` on `team`, and sends a tracer toward
## `aim_end` when the round is one.
static func fired(shooter: Node3D, origin: Vector3, aim_end: Vector3, model: String, team: int) -> void:
	shooter.get_tree().call_group(LISTENERS, "heard_gunfire", origin, model, shooter, team, sound_radius(model))
	var now := Engine.get_physics_frames()
	var first: bool = now - int(shooter.get_meta(&"last_shot_tick", -PAUSE_TICKS - 1)) > PAUSE_TICKS
	shooter.set_meta(&"last_shot_tick", now)
	var since: int = shooter.get_meta(&"rounds_since_tracer", TRACER_GAP) + 1
	if tracer_due(model, first, since - 1, randf()):
		since = 0
		var streak: Node3D = TRACER.new()
		streak.from = origin
		streak.to = aim_end
		streak.ally = team == 0
		var tree := shooter.get_tree()
		(tree.current_scene if tree.current_scene != null else tree.root).add_child(streak)
	shooter.set_meta(&"rounds_since_tracer", since)
