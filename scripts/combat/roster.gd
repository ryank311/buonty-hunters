extends RefCounted
## The stand-in soldiers each level starts with, so the round rules can be tried by hand:
## teammates to watch after being eliminated, enemies to shoot and search, and one enemy
## on patrol to walk into a claymore. They live in a "Roster" node under the level, are
## reset with it, and are kept out of the level scenes because tools/build_graybox.py
## regenerates those.
##
## Each entry: name, team (0 is the player's), class, pos, yaw in degrees (0 faces -Z,
## 90 faces -X), and optionally travel, the metres patrolled either side of pos.

const DUMMY := preload("res://scenes/actors/combat_dummy.tscn")
const NODE_NAME := "Roster"

const LAB: Array[Dictionary] = [
	{"name": "ALPHA", "team": 0, "class": "pointman", "pos": Vector3(-3.5, 0, 23.5), "yaw": 0.0},
	{"name": "BRAVO", "team": 0, "class": "marksman", "pos": Vector3(3.5, 0, 22.5), "yaw": 0.0},
	{"name": "TANGO 1", "team": 1, "class": "rifleman", "pos": Vector3(14, 0, 12), "yaw": 135.0},
	{"name": "TANGO 2", "team": 1, "class": "breacher", "pos": Vector3(18, 0, 18), "yaw": 114.0},
	{"name": "TANGO 3", "team": 1, "class": "marksman", "pos": Vector3(8, 0, -30), "yaw": 180.0},
	{"name": "PATROL", "team": 1, "class": "pointman", "pos": Vector3(-15, 0, 18), "yaw": 0.0, "travel": 5.0},
]

const TOWN: Array[Dictionary] = [
	{"name": "ALPHA", "team": 0, "class": "pointman", "pos": Vector3(-41.5, 0, 6.5), "yaw": -90.0},
	{"name": "BRAVO", "team": 0, "class": "marksman", "pos": Vector3(-41.5, 0, 13), "yaw": -90.0},
	{"name": "TANGO 1", "team": 1, "class": "rifleman", "pos": Vector3(-1, 0, 1), "yaw": 90.0},
	{"name": "TANGO 2", "team": 1, "class": "breacher", "pos": Vector3(9, 0, 8), "yaw": 90.0},
	{"name": "TANGO 3", "team": 1, "class": "marksman", "pos": Vector3(40, 0, 10), "yaw": 90.0},
	{"name": "PATROL", "team": 1, "class": "pointman", "pos": Vector3(-14, 0, 9), "yaw": 90.0, "travel": 4.0},
]

static func entries(lab: bool) -> Array[Dictionary]:
	return LAB if lab else TOWN

## Gives a freshly loaded level its soldiers. Does nothing once the level has a roster,
## including one that was emptied on purpose.
static func ensure(level: Node, lab: bool) -> void:
	if level.has_node(NODE_NAME):
		return
	var holder := Node3D.new()
	holder.name = NODE_NAME
	level.add_child(holder)
	_fill(holder, lab)

## Removes the level's soldiers, or puts them back.
static func set_present(level: Node, lab: bool, present: bool) -> void:
	ensure(level, lab)
	var holder := level.get_node(NODE_NAME)
	if present == (holder.get_child_count() > 0):
		return
	if present:
		_fill(holder, lab)
		return
	for dummy: Node in holder.get_children():
		# Out of the tree now, so group queries stop seeing it this frame.
		holder.remove_child(dummy)
		dummy.queue_free()

static func _fill(holder: Node, lab: bool) -> void:
	for entry: Dictionary in entries(lab):
		var dummy := DUMMY.instantiate()
		dummy.name = str(entry.name).replace(" ", "")
		dummy.display_name = entry.name
		dummy.team = entry.team
		dummy.soldier_class = entry["class"]
		dummy.travel = entry.get("travel", 0.0)
		dummy.position = entry.pos
		dummy.rotation.y = deg_to_rad(entry.yaw)
		holder.add_child(dummy)
