# EnemyAttackAnim.gd
# One entry in an enemy's weighted attack animation pool.
# Create via File > New Resource > EnemyAttackAnim.
# Add to enemy_battle.gd's attack_anims array, or to an EnemyPhase's array.

class_name EnemyAttackAnim
extends Resource

@export var animation_name: String = "attack"
@export var weight: float = 1.0
