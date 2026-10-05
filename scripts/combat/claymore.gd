extends Node3D
## A directional mine, the recovered M18. It has no trigger of its own: it waits where it
## was set until the soldier who placed it fires the claymore remote. The blast is a cone
## out of its convex face, away from where that soldier knelt, and hurts whoever stands
## in it, friend or enemy.

const Combat := preload("res://scripts/combat/combat.gd")
const BLAST_FX := preload("res://scripts/combat/blast_fx.gd")
const MODEL := preload("res://art/models/recovered_claymore.glb")
const GROUP := &"claymores"
const BLAST_DOT := 0.35
## The visible fan; the damage cone is BLAST_DOT wide and profile.effect_radius long.
const FX_LENGTH := 5.0
const FX_HALF_ANGLE := 40.0
## The recovered .M18_CLAYMORE report, three sequencer choices.
const REPORTS: Array[AudioStream] = [preload("res://audio/claymore/m18_claymore_1.wav"), preload("res://audio/claymore/m18_claymore_2.wav"), preload("res://audio/claymore/m18_claymore_3.wav")]
var profile: WeaponProfile
var placed_by: Node
var detonated: bool = false

func place(owner_actor: Node, item: WeaponProfile, where: Transform3D) -> void:
	placed_by = owner_actor
	profile = item
	global_transform = where
	add_to_group(GROUP)
	add_child(MODEL.instantiate())

## Whether `actor` placed this claymore and it is still waiting.
func belongs_to(actor: Node) -> bool:
	return placed_by == actor and not detonated

func detonate() -> void:
	if detonated:
		return
	detonated = true
	var info := {"source": placed_by, "weapon": profile.display_name}
	Combat.blast(get_tree(), global_position + Vector3.UP * 0.15, profile.effect_radius, profile.damage, info, -global_basis.z, BLAST_DOT)
	var fx := BLAST_FX.new()
	Combat.spawn(get_parent(), fx)
	# The blast leaves the convex face in a fan, away from the soldier who set it.
	fx.global_transform = Transform3D(global_basis, global_position + Vector3.UP * 0.2)
	fx.start(Color("ffcf7a"), 3.0, 0.4, 1.0, REPORTS.pick_random())
	fx.cone(FX_LENGTH, FX_HALF_ANGLE)
	queue_free()
