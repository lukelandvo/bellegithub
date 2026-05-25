# EnemyPhase.gd
# Defines an alternate animation pool that activates when enemy HP
# drops to or below hp_threshold (0.0–1.0, as fraction of max HP).
# Create via File > New Resource > EnemyPhase.
# Add to enemy_battle.gd's phases array.

class_name EnemyPhase
extends Resource

@export_group("Trigger")
@export_range(0.0, 1.0, 0.01) var hp_threshold: float = 0.5

@export_group("Attack Animations")
@export var attack_anims: Array[EnemyAttackAnim] = []
