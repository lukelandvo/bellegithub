# BattleSession.gd
# Autoload singleton — owns battle setup state.
# Add to Project > Project Settings > Autoload as "BattleSession".
#
# confirmed_encounter is set by SceneLoader.load_battle() and is never
# cleared until BattleManager.consume() reads it. This survives the
# confrontation sequence await safely.
#
# pending_encounter is the handoff from NPC to SceneLoader — it gets
# cleared by SceneLoader before the confrontation starts.

extends Node

# Set by NPC interact() — read and cleared by SceneLoader.load_battle()
var pending_encounter: Resource = null
var pending_music: AudioStream = null

# Set by SceneLoader.load_battle() — survives confrontation await
# Read and cleared by BattleManager._ready() via consume()
var confirmed_encounter: Resource = null

# Active party for this battle — populated from SaveManager.party
var active_party: Array = []

# ---------------------------------------------------------------------------
# Set encounter — called by NPC before dialogue ends
# ---------------------------------------------------------------------------

func set_encounter(encounter: Resource) -> void:
	pending_encounter = encounter
	if encounter and encounter.get("battle_music"):
		pending_music = encounter.battle_music
	else:
		pending_music = null
	_populate_active_party()

# ---------------------------------------------------------------------------
# Confirm encounter — called by SceneLoader.load_battle()
# Moves from pending to confirmed so it survives the confrontation await
# ---------------------------------------------------------------------------

func confirm_encounter() -> void:
	confirmed_encounter = pending_encounter
	pending_encounter = null

# ---------------------------------------------------------------------------
# Consume — called by BattleManager._ready()
# Returns and clears confirmed_encounter
# ---------------------------------------------------------------------------

func consume() -> Resource:
	var encounter = confirmed_encounter
	confirmed_encounter = null
	return encounter

# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

func _populate_active_party() -> void:
	active_party.clear()
	for member in SaveManager.party:
		if member and member.is_active and member.is_alive():
			active_party.append(member)