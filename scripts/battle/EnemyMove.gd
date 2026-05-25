# EnemyMove.gd
# Resource representing one action an enemy can take.
# Create via File > New Resource > EnemyMove.
# Add to EnemyStats.moves array in the inspector.

class_name EnemyMove
extends Resource

enum EffectType {
	ATTACK,        # physical hit, uses enemy offense vs party member defense
	DAMAGE_FLAT,   # ignores defense, deals power damage directly
	HEAL_SELF,     # restores this enemy's HP by power amount
	HEAL_ALLY,     # restores a random living ally's HP
	TAUNT,         # no damage — message only
	LOWER_OFFENSE,
	LOWER_DEFENSE,
	LOWER_SPEED,
	LOWER_GUTS,
}

@export_group("Identity")
@export var move_name: String = "Attack"
@export var use_message: String = "{enemy} attacks!"
# Tokens: {enemy}, {player}, {amount}
@export var result_message: String = ""   # leave blank for default message

@export_group("Effect")
@export var effect_type: EffectType = EffectType.ATTACK
@export var power: int = 0
@export var variance: int = 0

@export_group("Selection")
@export var weight: float = 1.0
@export var cooldown_turns: int = 0

@export_group("Animation")
@export var prepare_animation_name: String = ""
@export var attack_animation_name: String = ""
@export var miss_animation_name: String = ""
@export var anim_override: int = -1
@export var animation_speed: float = 1.0
@export var prepare_speed: float = 1.0
@export var miss_speed: float = 1.0

@export_group("Sounds")
@export var attack_sound: AudioStream
@export var hit_sound: AudioStream
