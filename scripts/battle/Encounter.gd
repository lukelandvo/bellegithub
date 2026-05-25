# Encounter.gd
# Defines all possible enemy rosters for a fight.
# Assign to an NPC's encounter export in the inspector.
# When battle starts, one roster is picked by weighted random.

class_name Encounter
extends Resource

@export var rosters: Array[EncounterRoster] = []
@export var battle_music: AudioStream
@export var battle_background: PackedScene = null   # leave blank for default

func pick_roster() -> EncounterRoster:
	if rosters.is_empty():
		return null
	var total_weight: float = 0.0
	for roster in rosters:
		total_weight += roster.weight
	var roll = randf() * total_weight
	var running: float = 0.0
	for roster in rosters:
		running += roster.weight
		if roll <= running:
			return roster
	return rosters[rosters.size() - 1]
