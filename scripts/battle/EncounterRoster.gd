# EncounterRoster.gd
# One possible enemy lineup for an encounter.
# Add multiple rosters to an Encounter with different weights
# to create varied fights from the same NPC.

class_name EncounterRoster
extends Resource

@export var weight: float = 1.0
@export var enemies: Array[EnemySlot] = []
