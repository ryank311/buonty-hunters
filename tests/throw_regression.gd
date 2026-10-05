extends SceneTree
## Grenade throwing: holding the button builds strength and range, the length of the
## hold picks the throw (lob, overhand or sidearm on the run, full), the grenade leaves
## the hand partway through the motion, and the arc shown while holding is where the
## grenade actually comes down.

const H = preload("res://tools/agent/harness.gd")
const Combat = preload("res://scripts/combat/combat.gd")
const THROW_ARC = preload("res://scripts/combat/throw_arc.gd")
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
	check(player.soldier.throw_hold_style == SoldierProxy.Throw.OVERHAND and player.soldier.throw_pose.w > 0.5, "The soldier draws back into the throw while it is held")
	# Held actions are let go by the next apply().
	await H.apply(self, {"settle": 0})
	paused = false
	await ticks(2)
	check(not weapon.throw_arc.visible and weapon.ammo == 1 and player.soldier.throwing() and grenades().is_empty(), "Letting go starts the throwing motion; the grenade is still in the hand (arc %s, ammo %d, throwing %s, live %d, charge %.2f, release %.2f)" % [weapon.throw_arc.visible, weapon.ammo, player.soldier.throwing(), grenades().size(), weapon.throw_charge, weapon.throw_release])
	await ticks(20)
	check(grenades().size() == 1, "The grenade leaves the hand partway through the motion")
	# The hold picks the throw, and a longer hold throws further.
	var lob := await throw(2)
	var overhand := await throw(36)
	var full := await throw(72)
	var sidearm := await throw(36, true)
	check(lob.style == SoldierProxy.Throw.LOB and lob.early == 0 and lob.landed and lob.distance > 3.0 and lob.distance < 9.0, "A tap is an underhand lob a few metres out (%.1f m)" % lob.distance)
	check(overhand.style == SoldierProxy.Throw.OVERHAND and overhand.distance > lob.distance + 4.0, "A medium hold standing is an overhand throw, well past the lob (%.1f m)" % overhand.distance)
	check(full.style == SoldierProxy.Throw.FULL and full.distance > 20.0 and full.distance > overhand.distance + 4.0, "A full hold is the full-body throw and reaches past 20 m on level aim (%.1f m)" % full.distance)
	check(sidearm.style == SoldierProxy.Throw.SIDEARM and sidearm.landed, "A medium hold on the run is a sidearm sling")
	for result: Dictionary in [lob, overhand, full]:
		var expected: Dictionary = result.expected
		check(expected.hit and expected.landing.distance_to(result.point) < 0.4, "The arc shown predicts where the %s comes down (%.2f m off)" % [["lob", "sidearm", "overhand", "full throw"][result.style], expected.landing.distance_to(result.point)])
	print("\nRESULT: %d failure(s)" % failures.size())
	session.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
