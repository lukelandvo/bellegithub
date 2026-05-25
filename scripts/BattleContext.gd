# BattleContext.gd
# Autoload singleton — owns all battle transition state.
# Add to Project > Project Settings > Autoload as "BattleContext".
#
# Separated from GameState so GameState can focus on
# progression flags, inventory, and save/load only.
extends Node

var return_scene: PackedScene = null
var pre_battle_position: Vector3 = Vector3.ZERO
var pre_battle_rotation: float = 0.0
var pre_battle_camera_position: Vector3 = Vector3.ZERO
var pre_battle_area: int = 0
var is_battle_return: bool = false
var pending_encounter: Encounter = null
var pending_battle_music: AudioStream = null

var _battle_scene: PackedScene = preload("res://scenes/battle.tscn")

func set_encounter(encounter: Encounter) -> void:
	pending_encounter = encounter
	pending_battle_music = encounter.battle_music if encounter else null

func start_battle(encounter: Encounter = null) -> void:
	var player = get_tree().get_first_node_in_group("player")
	if player:
		pre_battle_position = player.global_position
		pre_battle_rotation = player.rotation.y
	# save which area the player was in
	var gm = get_tree().get_first_node_in_group("game_manager")
	if gm:
		# find current active area index
		for i in gm.areas.size():
			if gm.areas[i].visible:
				pre_battle_area = i
				break
	var cam = get_tree().get_first_node_in_group("camera")
	if cam:
		pre_battle_camera_position = cam.global_position
	is_battle_return = true
	if encounter:
		pending_encounter = encounter
	var sm = get_tree().get_first_node_in_group("scene_manager")
	if sm:
		return_scene = sm.current_packed_scene
		sm.load_battle(_battle_scene)

func clear_battle_return() -> void:
	return_scene = null
	pre_battle_position = Vector3.ZERO
	pre_battle_rotation = 0.0
	pre_battle_camera_position = Vector3.ZERO
	pre_battle_area = 0
	is_battle_return = false
