# EnemySlot.gd
# One entry in an EncounterRoster.
# Links an enemy's stats, scene, and victory flag together.
#
# victory_flag: when set, the NPC in the world checks FlagService for this.
# Use FlagService.make_instance_flag() for instanced enemies to avoid
# the shared-flag problem from Onett Arcade.
#
# Leave display_name blank to auto-generate from stats.enemy_name.

class_name EnemySlot
extends Resource

@export var display_name: String = ""
@export var victory_flag: String = ""   # e.g. "defeated_carpowski__camp__0"
@export var stats: EnemyStats
@export var scene: PackedScene
