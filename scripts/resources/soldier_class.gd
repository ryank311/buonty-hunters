extends Resource
## A character class: the loadout a soldier spawns with. Players choose a class, never
## individual weapons. Slot 0 is the primary, slot 1 the pistol, then the equipment.

@export var display_name: String = "RIFLEMAN"
@export var summary: String = ""
@export var primary: WeaponProfile
@export var secondary: WeaponProfile
@export var equipment: Array[Resource] = []

func weapons() -> Array[WeaponProfile]:
	var carried: Array[WeaponProfile] = [primary, secondary]
	for item: WeaponProfile in equipment:
		carried.append(item)
	return carried
