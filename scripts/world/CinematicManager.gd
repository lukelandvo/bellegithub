# CinematicManager.gd
# Node in main.tscn — owns confrontation sequences and future cutscene moments.
# Freezes NPCs and world enemies, plays audio stings, waits for player input.
# Does not load scenes — tells SceneLoader when the sequence is done.
#
# Wire TransitionManager and Player via @export in the inspector.

extends Node

@export_group("References")
@export var transition_manager: Node
@export var player: CharacterBody3D

@export_group("Confrontation")
@export var confrontation_dim: float = 0.65
@export var confrontation_fade_in: float = 0.4
@export var confrontation_sound_id: String = "battle_confrontation"
@export var confrontation_sound_fade: float = 0.5

# Read by dialogueballoon.gd to block input during confrontation
var is_playing_confrontation: bool = false

var _awaiting_skip: bool = false

signal confrontation_complete

func _ready() -> void:
	add_to_group("cinematic_manager")

func _unhandled_input(event: InputEvent) -> void:
	if _awaiting_skip and event.is_action_pressed("interact"):
		_awaiting_skip = false
		get_viewport().set_input_as_handled()

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func play_confrontation() -> void:
	is_playing_confrontation = true
	_freeze_world()
	AudioManager.stop_footsteps()
	AudioManager.stop_music()
	AudioManager.play_confrontation(confrontation_sound_id)
	await transition_manager.fade_to(confrontation_dim, confrontation_fade_in)
	_awaiting_skip = true
	while _awaiting_skip:
		await get_tree().process_frame
	AudioManager.stop_confrontation(confrontation_sound_fade)
	await transition_manager.fade_out(confrontation_sound_fade)
	is_playing_confrontation = false
	emit_signal("confrontation_complete")

func resume_world() -> void:
	_unfreeze_world()

# ---------------------------------------------------------------------------
# Internal — freeze / unfreeze
# ---------------------------------------------------------------------------

func _freeze_world() -> void:
	for npc in get_tree().get_nodes_in_group("npc"):
		npc.set_process(false)
		npc.set_physics_process(false)
		if npc.get("anim_player") and npc.anim_player:
			npc.anim_player.pause()
	for enemy in get_tree().get_nodes_in_group("world_npc"):
		if enemy.has_method("freeze"):
			enemy.freeze()
		else:
			enemy.set_process(false)
			if enemy.get("anim_player") and enemy.anim_player:
				enemy.anim_player.pause()
	for flicker in get_tree().get_nodes_in_group("screen_flicker"):
		flicker.set_process(false)

func _unfreeze_world() -> void:
	for npc in get_tree().get_nodes_in_group("npc"):
		npc.set_process(true)
		npc.set_physics_process(true)
		if npc.get("anim_player") and npc.anim_player:
			npc.anim_player.advance(0)
	for enemy in get_tree().get_nodes_in_group("world_npc"):
		if enemy.has_method("unfreeze"):
			enemy.unfreeze()
		else:
			enemy.set_process(true)
			if enemy.get("anim_player") and enemy.anim_player:
				enemy.anim_player.advance(0)
	for flicker in get_tree().get_nodes_in_group("screen_flicker"):
		flicker.set_process(true)
