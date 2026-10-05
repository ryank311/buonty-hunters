extends SceneTree
## Grenade throwing: holding the button builds strength and range, the length of the
## hold picks the throw (lob, overhand or sidearm on the run, full), the grenade leaves
## the hand partway through the motion, and the arc shown while holding is where the
## grenade actually comes down. A pad's trigger sets the strength by how far it is
## squeezed instead. And a grenade does not know who threw it: one that comes down too
## close kills the thrower and anyone on their side.

const H = preload("res://tools/agent/harness.gd")
const Combat = preload("res://scripts/combat/combat.gd")
const THROW_ARC = preload("res://scripts/combat/throw_arc.gd")
const THROWABLE = preload("res://scripts/combat/throwable.gd")
var failures: Array[String] = []
var session: Node3D
var player: PrototypePlayer
var weapon: PracticeWeapon

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, description: String) -> void:
	print("PASS " if condition else "FAIL ", description)
	if not condition:
		failures.append(description)

func ticks(count: int) -> void:
	for index: int in range(count):
		await physics_frame

func grenades() -> Array:
	return get_nodes_in_group(Combat.SPAWNED_GROUP).filter(func(node: Node) -> bool: return node.get("fuse") != null)

## Holds the throw for `frames` (optionally running forward), lets go, and follows the
## grenade to the first thing it hits. Returns the throw and how far from the soldier
## it first came down.
func throw(frames: int, run: bool = false) -> Dictionary:
	await H.scenario(self, "lab_start", {"roster": false, "weapon": "frag", "pitch": 0.0})
	paused = false
	var start := player.global_position
	if run:
		await H.step(self, 40, {"forward": 1.0})
	var input := {"hold": ["fire"]}
	if run:
		input["forward"] = 1.0
	await H.step(self, frames, input)
	paused = false
	# The weapon sees the button come up on the next tick.
	await ticks(2)
	var style := weapon.throw_style
	var expected: Dictionary = THROW_ARC.predict(player.get_world_3d(), weapon.throw_launch(weapon.throw_strength, style).origin, weapon.throw_launch(weapon.throw_strength, style).velocity) if not run else {}
	var early := grenades().size()
	var grenade: Node3D = null
	var first := Vector3.ZERO
	for tick: int in range(240):
		await physics_frame
		if grenade == null and not grenades().is_empty():
			grenade = grenades().front()
		if grenade != null and grenade.bounces >= 1:
			first = grenade.global_position
			break
	var flat := Vector2(first.x - start.x, first.z - start.z)
	return {"style": style, "early": early, "landed": grenade != null and first != Vector3.ZERO, "distance": flat.length(), "point": first, "expected": expected}

## Sets the pad's right trigger to `travel`, from 0 (at rest) to 1 (fully squeezed).
func trigger(travel: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = 0
	event.axis = JOY_AXIS_TRIGGER_RIGHT
	event.axis_value = travel
	Input.parse_input_event(event)
	Input.flush_buffered_events()

## Lets the trigger go from `travel` the way a finger does: up through every lighter
## squeeze over a few ticks.
func let_go(travel: float) -> void:
	for part: float in [0.7, 0.4, 0.1, 0.0]:
		trigger(travel * part)
		await ticks(1)
	await ticks(2)

## Squeezes the trigger to `travel` and holds it, optionally eases off to `ease_to` and
## rests there, lets go, and follows the grenade to the first thing it hits.
func squeeze_throw(travel: float, ease_to: float = -1.0, pitch: float = 0.0) -> Dictionary:
	await H.scenario(self, "lab_start", {"roster": false, "weapon": "frag", "pitch": pitch})
	paused = false
	var start := player.global_position
	for step: int in range(1, 5):
		trigger(travel * step / 4.0)
		await ticks(1)
	await ticks(30)
	var early := weapon.throw_charge
	await ticks(30)
	var held := weapon.throw_charge
	var shown := weapon.throw_arc.visible
	if ease_to >= 0.0:
		for step: int in range(1, 5):
			trigger(lerpf(travel, ease_to, step / 4.0))
			await ticks(1)
		await ticks(12)
		travel = ease_to
	var asked := Input.get_action_strength("fire")
	var expected: Dictionary = THROW_ARC.predict(player.get_world_3d(), weapon.throw_launch(weapon.throw_charge, player.soldier.throw_hold_style).origin, weapon.throw_launch(weapon.throw_charge, player.soldier.throw_hold_style).velocity)
	await let_go(travel)
	var grenade: Node3D = null
	var first := Vector3.ZERO
	for tick: int in range(240):
		await physics_frame
		if grenade == null and not grenades().is_empty():
			grenade = grenades().front()
		if grenade != null and grenade.bounces >= 1:
			first = grenade.global_position
			break
	return {"early": early, "held": held, "asked": asked, "thrown": weapon.throw_strength, "shown": shown, "style": weapon.throw_style, "landed": grenade != null and first != Vector3.ZERO, "distance": Vector2(first.x - start.x, first.z - start.z).length(), "point": first, "expected": expected, "grenade": grenade}

func _run() -> void:
	session = load("res://scenes/main.tscn").instantiate()
	root.add_child(session)
	player = session.player
	weapon = player.weapon
	await ticks(30)
	# Holding shows the arc; nothing leaves the hand until the button is let go.
	await H.scenario(self, "lab_start", {"roster": false, "weapon": "frag", "pitch": 0.0})
	paused = false
	await H.apply(self, {"hold": ["fire"]})
	paused = false
	await ticks(40)
	check(weapon.throw_charge > 0.5 and weapon.throw_arc.visible and weapon.throw_arc.ring.visible and grenades().is_empty() and weapon.ammo == 2, "Holding builds strength and shows the arc and landing ring, without throwing yet (%.2f)" % weapon.throw_charge)
	# Held actions are let go by the next apply().
	await H.apply(self, {"settle": 0})
	paused = false
	await ticks(2)
	check(not weapon.throw_arc.visible and weapon.ammo == 1 and player.soldier.throwing(), "Releasing spends one grenade and hides the arc during the native follow-through")
	await ticks(20)
	check(grenades().size() == 1, "The grenade leaves the hand partway through the motion")
	await H.scenario(self, "lab_start", {"roster": false, "weapon": "frag", "freeze": true})
	weapon.throw_charge = 0.5
	weapon._commit_throw()
	session.set_player_character(0)
	check(weapon.ammo == 2 and weapon.throw_release < 0.0 and not player.soldier.throwing(), "Changing character cancels and refunds a grenade still in hand")
	weapon.throw_charge = 0.5
	weapon._commit_throw()
	weapon._throw()
	session.set_player_character(0)
	check(weapon.ammo == 1 and grenades().size() == 1, "Changing character after release neither refunds nor duplicates the grenade")
	# The hold picks the throw, and a longer hold throws further.
	var lob := await throw(2)
	var overhand := await throw(36)
	var full := await throw(72)
	var moving := await throw(36, true)
	check(lob.style == SoldierProxy.Throw.LOB and lob.early == 0 and lob.landed and lob.distance > 3.0 and lob.distance < 9.0, "A tap is an underhand lob a few metres out (%.1f m)" % lob.distance)
	check(overhand.style == SoldierProxy.Throw.OVERHAND and overhand.distance > lob.distance + 4.0, "A medium hold standing is an overhand throw, well past the lob (%.1f m)" % overhand.distance)
	check(full.style == SoldierProxy.Throw.FULL and full.distance > 20.0 and full.distance > overhand.distance + 4.0, "A full hold is the full-body throw and reaches past 20 m on level aim (%.1f m)" % full.distance)
	check(moving.landed, "A medium hold while moving releases and lands")
	for result: Dictionary in [lob, overhand, full]:
		var expected: Dictionary = result.expected
		check(expected.hit and expected.landing.distance_to(result.point) < 0.4, "The arc shown predicts where the %s comes down (%.2f m off)" % [["lob", "sidearm", "overhand", "full throw"][result.style], expected.landing.distance_to(result.point)])
	# A pad's trigger: the squeeze is the strength.
	var light := await squeeze_throw(0.3)
	var half := await squeeze_throw(0.6)
	var hard := await squeeze_throw(1.0)
	check(weapon.fire_analog and light.shown and is_equal_approx(light.early, light.held) and is_equal_approx(light.held, light.asked) and light.held > 0.1 and light.held < 0.25, "A trigger held at a light squeeze holds that strength; it does not build with time (%.2f after half a second, %.2f after a second)" % [light.early, light.held])
	check(is_equal_approx(light.thrown, light.held) and is_equal_approx(half.thrown, half.held) and is_equal_approx(hard.thrown, 1.0), "Letting go throws at the squeeze that was held, not at what the trigger read on its way up (%.2f, %.2f, %.2f)" % [light.thrown, half.thrown, hard.thrown])
	check(light.landed and half.landed and hard.landed and half.distance > light.distance + 4.0 and hard.distance > half.distance + 8.0, "The harder the squeeze, the further the grenade goes (%.1f m, %.1f m, %.1f m)" % [light.distance, half.distance, hard.distance])
	check(light.style == SoldierProxy.Throw.LOB and half.style == SoldierProxy.Throw.OVERHAND and hard.style == SoldierProxy.Throw.FULL, "The squeeze picks the throw as a hold does: lob, overhand, full")
	for result: Dictionary in [light, half, hard]:
		check(result.expected.hit and result.expected.landing.distance_to(result.point) < 0.4, "The arc shown under a squeeze of %.2f is where the grenade comes down (%.2f m off)" % [result.held, result.expected.landing.distance_to(result.point)])
	var eased := await squeeze_throw(1.0, 0.45)
	check(is_equal_approx(eased.held, 1.0) and eased.thrown < 0.4 and eased.thrown > 0.3 and eased.distance < hard.distance - 10.0, "Easing off and resting at a lighter squeeze throws the lighter throw (%.2f, %.1f m)" % [eased.thrown, eased.distance])
	# A trigger twitching at rest must not take a held button's throw away from it.
	await H.scenario(self, "lab_start", {"roster": false, "weapon": "frag", "pitch": 0.0})
	paused = false
	await H.apply(self, {"hold": ["fire"]})
	paused = false
	await ticks(10)
	trigger(0.06)
	await ticks(10)
	check(not weapon.fire_analog and weapon.throw_charge > 0.25 and weapon.throw_charge < 0.5, "A button still builds strength by time, whatever a resting trigger reports (%.2f after a third of a second)" % weapon.throw_charge)
	trigger(0.0)
	await H.apply(self, {"settle": 0})
	paused = false
	# Friendly fire. The lightest toss, aimed at the ground ahead, comes down close
	# enough to all but kill the thrower.
	await H.scenario(self, "lab_start", {"roster": false, "weapon": "frag", "pitch": -50.0})
	paused = false
	trigger(0.2)
	await ticks(20)
	await let_go(0.2)
	var tossed: Node3D = null
	var rested := Vector3.ZERO
	for tick: int in range(300):
		await physics_frame
		if tossed == null and not grenades().is_empty():
			tossed = grenades().front()
		if is_instance_valid(tossed):
			rested = tossed.global_position
	var away := Vector2(rested.x - player.global_position.x, rested.z - player.global_position.z).length()
	check(away < 4.5 and player.health < 25.0, "The lightest toss at the ground ahead comes down close enough to maim the thrower (%.1f m away, %.0f health left)" % [away, player.health])
	# One lying two metres off kills the soldier who threw it and the teammate beside
	# them, and spares a teammate out of its reach.
	await H.scenario(self, "lab_start", {"roster": false, "weapon": "frag", "actors": [{"team": 0, "pos": [1.2, 0.0, 25.0], "name": "MATE"}, {"team": 0, "pos": [0.0, 0.0, 13.0], "name": "DISTANT"}]})
	paused = false
	var frag := THROWABLE.new()
	Combat.spawn(session.level, frag)
	frag.launch(player, weapon.profile, player.global_position + Vector3(0.0, 0.3, -2.0), Vector3.ZERO)
	await ticks(roundi(weapon.profile.fuse_seconds * 60.0) + 20)
	var mate: Node = null
	var distant: Node = null
	for actor: Node in get_nodes_in_group(Combat.ACTOR_GROUP):
		if Combat.name_of(actor) == "MATE":
			mate = actor
		elif Combat.name_of(actor) == "DISTANT":
			distant = actor
	check(player.health <= 0.0 and not Combat.is_alive(player) and weapon.director.dead, "A soldier's own grenade two metres away kills them (%.0f health left)" % player.health)
	check(mate != null and not Combat.is_alive(mate) and distant != null and Combat.is_alive(distant) and is_equal_approx(distant.health, 100.0), "It kills a teammate beside them too, and spares one out of its reach")
	print("\nRESULT: %d failure(s)" % failures.size())
	session.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
