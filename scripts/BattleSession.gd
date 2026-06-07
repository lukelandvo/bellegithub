# BattleSession.gd
# Autoload singleton — owns battle setup state.
# Add to Project > Project Settings > Autoload as "BattleSession".

extends Node

var pending_encounter: Resource = null
var pending_music: AudioStream = null
var confirmed_encounter: Resource = null
var active_party: Array = []

func set_encounter(encounter: Resource) -> void:
	pending_encounter = encounter
	if encounter and encounter.get("battle_music"):
		pending_music = encounter.battle_music
	else:
		pending_music = null
	_populate_active_party()

func confirm_encounter() -> void:
	confirmed_encounter = pending_encounter
	pending_encounter = null

func consume() -> Resource:
	var encounter = confirmed_encounter
	confirmed_encounter = null
	return encounter

func _populate_active_party() -> void:
	active_party.clear()
	for member in SaveManager.party:
		if member and member.is_active and member.is_alive():
			active_party.append(member)