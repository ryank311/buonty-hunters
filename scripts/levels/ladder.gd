extends Node3D
## A ladder a soldier can climb. The node sits at the middle of the ladder's foot, on the
## plane of its rungs; its -Z points into the ladder, the way a climber faces, so +Z is
## the side it is climbed from and the floor at its head lies toward -Z.
##
## The recovered maps mark ladders on their collision polygons (m_appflags 2), found by
## tools/recovery/prepare_ladders.py and listed in resources/recovered/ladders.json. A
## ladder made by hand needs only this script, a transform, and a height.
const GROUP := &"ladders"
const SOURCE := "res://resources/recovered/ladders.json"
## How near the foot or the head a soldier must stand to be offered the climb.
const FOOT_REACH := 1.9
const HEAD_REACH := 1.7
const SIDE_REACH := 0.5
## A soldier this far under the head or nearer is past the foot: stepping on and climbing
## off take 2.4 m between them.
const HEAD_ROOM := 2.4

## From the floor the ladder stands on to the floor it reaches.
@export var height: float = 4.0
@export var half_width: float = 0.4
static var catalogue: Dictionary = {}

func _ready() -> void:
	add_to_group(GROUP)

## Adds the ladders of a recovered map to its level.
static func install(level: Node3D, map_id: String) -> void:
	if catalogue.is_empty() and FileAccess.file_exists(SOURCE):
		catalogue = JSON.parse_string(FileAccess.get_file_as_string(SOURCE))
	var entries: Array = catalogue.get("maps", {}).get(map_id.to_upper(), [])
	if entries.is_empty():
		return
	var holder := Node3D.new()
	holder.name = "Ladders"
	level.add_child(holder)
	var script: GDScript = load("res://scripts/levels/ladder.gd")
	for entry: Dictionary in entries:
		var ladder: Node3D = script.new()
		ladder.name = "Ladder%d" % (holder.get_child_count() + 1)
		ladder.height = entry.top - entry.bottom
		ladder.half_width = entry.half_width
		var out := Vector3(entry.normal[0], 0.0, entry.normal[1]).normalized()
		ladder.transform = Transform3D(Basis(Vector3.UP.cross(out), Vector3.UP, out), Vector3(entry.centre[0], entry.bottom, entry.centre[1]))
		ladder.set_meta("source", entry.path)
		holder.add_child(ladder)

## The side the ladder is climbed from, and the way a climber faces.
func out() -> Vector3:
	return global_basis.z.normalized()

func into() -> Vector3:
	return -out()

## What the ladder offers a soldier standing at `point` and facing `facing`: "foot" to
## climb up, "head" to climb down, or "" when they are not at either end.
func end_near(point: Vector3, facing: Vector3) -> String:
	var local := to_local(point)
	if absf(local.x) > half_width + SIDE_REACH:
		return ""
	# The ground at the foot can lie well above the bottom of the rungs, which some maps
	# bury in a slope: anywhere the climb still has rungs to cover counts as the foot.
	if local.y > -0.6 and local.y < height - HEAD_ROOM and local.z > 0.05 and local.z < FOOT_REACH and facing.dot(into()) > 0.35:
		return "foot"
	if absf(local.y - height) < 0.6 and local.z < 0.35 and local.z > -HEAD_REACH and facing.dot(out()) > 0.2:
		return "head"
	return ""
