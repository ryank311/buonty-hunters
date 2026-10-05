extends SceneTree
## Death ragdolls: a killing blow throws the limp body along its direction, a head shot
## whips the head, a blast throws the body away, every body comes to rest on the ground,
## and a reset brings the soldier back standing.

const H = preload("res://tools/agent/harness.gd")
const Combat = preload("res://scripts/combat/combat.gd")
var failures: Array[String] = []
var session: Node3D

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, description: String) -> void:
	print("PASS " if condition else "FAIL ", description)
	if not condition:
		failures.append(description)

func ticks(count: int) -> void:
	for index: int in range(count):
		await physics_frame

func actor(title: String) -> Node3D:
	for candidate: Node in get_nodes_in_group(Combat.ACTOR_GROUP):
		if candidate != session.player and Combat.name_of(candidate) == title:
			return candidate
	return null

## Kills `target` with a shot that left `from` and struck `height` metres up its body.
func shoot(target: Node3D, from: Vector3, height: float) -> void:
	var shooter := Marker3D.new()
	session.level.add_child(shooter)
	shooter.global_position = from - Vector3.UP * 1.4
	Combat.hurt(target, 500.0, {"position": target.global_position + Vector3.UP * height, "source": shooter, "weapon": "TEST"})
	shooter.queue_free()

func _run() -> void:
	session = load("res://scenes/main.tscn").instantiate()
	root.add_child(session)
	await ticks(30)
	# Every soldier faces -Z (yaw 0), so "in front" is toward -Z.
	await H.scenario(self, "lab_start", {"roster": false, "actors": [
		{"team": 1, "pos": [-9.0, 0.0, 10.0], "name": "FRONT"},
		{"team": 1, "pos": [-3.0, 0.0, 10.0], "name": "SIDE"},
		{"team": 1, "pos": [3.0, 0.0, 10.0], "name": "HEAD"},
		{"team": 1, "pos": [9.0, 0.0, 10.0], "name": "BLAST"},
	]})
	paused = false
	var front := actor("FRONT")
	var side := actor("SIDE")
	var head := actor("HEAD")
	var blast := actor("BLAST")
	var start := {}
	for dummy: Node3D in [front, side, head, blast]:
		start[dummy] = dummy.global_position
	shoot(front, front.global_position + Vector3(0, 1.3, -8.0), 1.2)
	shoot(side, side.global_position + Vector3(8.0, 1.3, 0), 1.2)
	shoot(head, head.global_position + Vector3(0, 1.6, -8.0), 1.62)
	var blast_origin: Vector3 = blast.global_position + Vector3(-1.0, 0.2, 1.5)
	Combat.blast(self, blast_origin, 6.0, 400.0, {"weapon": "TEST"})
	check(not front.alive and front.ragdoll != null and not front.soldier.visible, "A killed soldier is replaced by a limp ragdoll")
	await ticks(2)
	var whip: float = head.ragdoll.bodies.Head.linear_velocity.length()
	var trunk: float = head.ragdoll.bodies.Torso.linear_velocity.length()
	check(whip > trunk * 2.0, "A head shot snaps the head harder than the body (%.2f vs %.2f m/s)" % [whip, trunk])
	await ticks(260)
	var rested := true
	var grounded := true
	for dummy: Node3D in [front, side, head, blast]:
		rested = rested and dummy.ragdoll.settled
		grounded = grounded and dummy.ragdoll.rest_position().y < 0.45
	check(rested and grounded, "Every body comes to rest lying on the ground within four seconds")
	var front_fall: Vector3 = front.ragdoll.rest_position() - start[front]
	check(front_fall.z > 0.25, "Shot from the front, the body falls backward (%.2f m)" % front_fall.z)
	var side_fall: Vector3 = side.ragdoll.rest_position() - start[side]
	check(side_fall.x < -0.25, "Shot from the right, the body falls to its left (%.2f m)" % side_fall.x)
	var head_fall: Vector3 = head.ragdoll.rest_position() - start[head]
	check(head_fall.z > 0.15, "A head shot from the front drops the body backward (%.2f m)" % head_fall.z)
	var thrown: float = Vector2(blast.ragdoll.rest_position().x - blast_origin.x, blast.ragdoll.rest_position().z - blast_origin.z).length() - Vector2(start[blast].x - blast_origin.x, start[blast].z - blast_origin.z).length()
	check(thrown > 0.8, "A blast throws the body away from the explosion (%.2f m)" % thrown)
	var bodies: Node3D = front.ragdoll
	session.reset_player()
	await ticks(2)
	check(front.alive and front.soldier.visible and not is_instance_valid(bodies), "A reset clears the ragdoll and stands the soldier back up")
	print("\nRESULT: %d failure(s)" % failures.size())
	session.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
