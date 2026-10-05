extends Node3D
## The view of an eliminated player. It orbits one subject at a time: a living teammate,
## or the player's own body, which stays where it fell. Enemies are never offered
## (docs/DESIGN.md, "Spectating and round reset").

const Combat := preload("res://scripts/combat/combat.gd")
const DISTANCE := 3.2
var camera := Camera3D.new()
var body: Node3D
var subjects: Array[Node3D] = []
var index: int = 0
var yaw: float = 0.0
var pitch: float = -0.3
var active: bool = false

func _ready() -> void:
	top_level = true
	camera.near = 0.05
	camera.fov = 60.0
	add_child(camera)

## Starts watching: a living teammate if there is one, otherwise the player's own body.
func begin(own_body: Node3D) -> void:
	body = own_body
	yaw = own_body.rotation.y
	pitch = -0.3
	active = true
	_gather()
	index = 0
	camera.make_current()
	update(0.0)

func end() -> void:
	active = false
	subjects.clear()

func _gather() -> void:
	var watched: Node3D = subject()
	subjects.clear()
	for actor: Node in get_tree().get_nodes_in_group(Combat.ACTOR_GROUP):
		if actor != body and actor is Node3D and Combat.is_alive(actor) and Combat.team_of(actor) == Combat.team_of(body):
			subjects.append(actor)
	subjects.append(body)
	index = maxi(0, subjects.find(watched)) if watched != null else 0

func subject() -> Node3D:
	return subjects[index] if index < subjects.size() and is_instance_valid(subjects[index]) else null

func cycle(direction: int) -> void:
	_gather()
	index = posmod(index + direction, subjects.size())

func watching_own_body() -> bool:
	return subject() == body

func caption() -> String:
	return "your body" if watching_own_body() else Combat.name_of(subject())

## Turns the view; `amount` is in radians.
func look(amount: Vector2) -> void:
	yaw -= amount.x
	pitch = clampf(pitch - amount.y, deg_to_rad(-70.0), deg_to_rad(35.0))

func update(_delta: float) -> void:
	if not active:
		return
	var watched := subject()
	# A teammate who falls is no longer a view; move on rather than linger on an enemy's kill.
	if watched == null or (watched != body and not Combat.is_alive(watched)):
		_gather()
		watched = subject()
	var anchor := watched.global_position + Vector3.UP * (0.45 if watched == body else 1.5)
	var offset := Basis.from_euler(Vector3(pitch, yaw, 0.0)) * Vector3(0.0, 0.0, DISTANCE)
	var query := PhysicsRayQueryParameters3D.create(anchor, anchor + offset, Combat.WORLD_MASK)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var eye: Vector3 = anchor + offset if hit.is_empty() else hit.position - offset.normalized() * 0.2
	camera.global_transform = Transform3D(Basis.from_euler(Vector3(pitch, yaw, 0.0)), eye)
