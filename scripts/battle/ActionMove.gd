# ActionMove.gd
# Resource representing one special action a party member can take.
# Named "Action" rather than PSI to stay generic for BELLE's early design.
# Create via File > New Resource > ActionMove.
# Add to PartyMember.psi_moves array in the inspector.

class_name ActionMove
extends Resource

enum EffectType {
	DAMAGE,      # deal damage to target enemy
	HEAL,        # restore party member HP
	RESTORE_PP,  # restore party member PP
}

@export_group("Identity")
@export var move_name: String = "Action"
@export var description: String = ""

@export_group("Cost")
@export var pp_cost: int = 5

@export_group("Effect")
@export var effect_type: EffectType = EffectType.DAMAGE
@export var power: int = 30
@export var variance: int = 5

@export_group("Sound")
@export var use_sound: AudioStream = null
