# EnemyStats.gd
# Resource holding all combat data for an enemy type.
# Create one .tres per enemy type via File > New Resource > EnemyStats.

class_name EnemyStats
extends Resource

@export_group("Identity")
@export var enemy_name: String = "Enemy"
@export var level: int = 1

@export_group("Health")
@export var max_hp: int = 50
var current_hp: int = max_hp:
	set(value):
		current_hp = clampi(value, 0, max_hp)

@export_group("Combat Stats")
@export var offense: int = 10
@export var defense: int = 5
@export var speed: int = 10
@export var guts: int = 5

@export_group("Moves")
@export var moves: Array[EnemyMove] = []

@export_group("Rewards")
@export var experience_reward: int = 20
@export var money_reward: int = 10

func _init() -> void:
	current_hp = max_hp

func take_damage(amount: int) -> int:
	var actual = maxi(1, amount - defense)
	current_hp -= actual
	return actual

func is_alive() -> bool:
	return current_hp > 0
