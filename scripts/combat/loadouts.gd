extends RefCounted
## The character classes a player can choose. Order is the order shown in the class menu.

const IDS: Array[String] = ["rifleman", "marksman", "breacher", "pointman"]
const CLASSES: Array[Resource] = [
	preload("res://resources/classes/rifleman.tres"),
	preload("res://resources/classes/marksman.tres"),
	preload("res://resources/classes/breacher.tres"),
	preload("res://resources/classes/pointman.tres"),
]

static func index_of(id: String) -> int:
	return IDS.find(id.to_lower())

static func by_id(id: String) -> Resource:
	var index := index_of(id)
	return CLASSES[index] if index >= 0 else null
