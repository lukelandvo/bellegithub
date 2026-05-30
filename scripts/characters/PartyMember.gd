# PartyMember.gd
# Resource representing one party member's full state.
# Create one .tres per character via File > New Resource > PartyMember.
#
# Base stats are stored and saved as-is.
# Always read combat stats via get_effective_*() methods —
# these add equipped item bonuses and subtract any active battle debuffs.
# This prevents stat drift from equip/unequip AND from enemy debuff moves.
#
# _temp_*_penalty fields are NOT exported and NOT serialized — they exist
# only in memory during battle and clear to 0 on next load automatically.
# Call clear_battle_penalties() at the end of every battle path.

class_name PartyMember
extends Resource

@export_group("Identity")
@export var character_name: String = "Skip"
@export var character_id: int = 0
@export var is_active: bool = false

@export_group("Progression")
@export var level: int = 1
@export var experience: int = 0
@export var experience_to_next_level: int = 100

@export_group("Health")
@export var max_hp: int = 32
@export var current_hp: int = 32:
	set(value):
		current_hp = clampi(value, 0, max_hp)

@export_group("PSI")
@export var max_pp: int = 10
@export var current_pp: int = 10:
	set(value):
		current_pp = clampi(value, 0, max_pp)

@export_group("Base Stats")
@export var offense: int = 8
@export var defense: int = 6
@export var speed: int = 8
@export var guts: int = 4
@export var luck: int = 4
@export var vitality: int = 4
@export var iq: int = 4

@export_group("Equipment")
@export var weapon: String = ""
@export var head: String = ""
@export var body: String = ""
@export var accessory: String = ""

@export_group("Moves")
@export var psi_moves: Array[Resource] = []

@export_group("Move Unlocks")
@export var move_unlocks: Dictionary = {}

# ---------------------------------------------------------------------------
# Battle-only temporary debuff penalties.
# Not exported, not serialized — zero on every fresh load.
# Accumulate via BattleManager; clear with clear_battle_penalties().
# ---------------------------------------------------------------------------

var _temp_offense_penalty: int = 0
var _temp_defense_penalty: int = 0
var _temp_speed_penalty: int = 0
var _temp_guts_penalty: int = 0

func clear_battle_penalties() -> void:
	_temp_offense_penalty = 0
	_temp_defense_penalty = 0
	_temp_speed_penalty = 0
	_temp_guts_penalty = 0

# ---------------------------------------------------------------------------
# Effective stat helpers — always use these in battle and menus.
# Includes equipment bonuses and temporary battle debuffs.
# ---------------------------------------------------------------------------

func get_effective_offense() -> int:
	return maxi(0, offense + _bonus("bonus_offense") - _temp_offense_penalty)

func get_effective_defense() -> int:
	return maxi(0, defense + _bonus("bonus_defense") - _temp_defense_penalty)

func get_effective_speed() -> int:
	return maxi(0, speed + _bonus("bonus_speed") - _temp_speed_penalty)

func get_effective_guts() -> int:
	return maxi(0, guts + _bonus("bonus_guts") - _temp_guts_penalty)

func get_effective_luck() -> int:
	return luck + _bonus("bonus_luck")

func get_effective_iq() -> int:
	return iq + _bonus("bonus_iq")

func get_effective_vitality() -> int:
	return vitality + _bonus("bonus_vitality")

func _bonus(field: String) -> int:
	var total: int = 0
	for slot in ["weapon", "head", "body", "accessory"]:
		var item_id: String = get_equipped(slot)
		if item_id == "":
			continue
		var item: ItemData = ItemRegistry.get_item(item_id)
		if item:
			total += item.get(field) as int
	return total

# ---------------------------------------------------------------------------
# Derived helpers
# ---------------------------------------------------------------------------

func is_alive() -> bool:
	return current_hp > 0

func is_ko() -> bool:
	return current_hp <= 0

func take_damage(amount: int) -> int:
	# Uses get_effective_defense() which already includes temp debuffs.
	var actual = maxi(1, amount - get_effective_defense())
	current_hp -= actual
	return actual

func heal(amount: int) -> int:
	var before = current_hp
	current_hp += amount
	return current_hp - before

func restore_pp(amount: int) -> int:
	var before = current_pp
	current_pp += amount
	return current_pp - before

func use_pp(amount: int) -> bool:
	if current_pp < amount:
		return false
	current_pp -= amount
	return true

func full_restore() -> void:
	current_hp = max_hp
	current_pp = max_pp

# ---------------------------------------------------------------------------
# Equipment helpers
# ---------------------------------------------------------------------------

func equip(slot: String, item_id: String) -> String:
	var previous: String = ""
	match slot:
		"weapon":
			previous = weapon
			weapon = item_id
		"head":
			previous = head
			head = item_id
		"body":
			previous = body
			body = item_id
		"accessory":
			previous = accessory
			accessory = item_id
		_:
			push_error("PartyMember: unknown equipment slot '%s'" % slot)
	return previous

func unequip(slot: String) -> String:
	return equip(slot, "")

func get_equipped(slot: String) -> String:
	match slot:
		"weapon": return weapon
		"head": return head
		"body": return body
		"accessory": return accessory
		_:
			push_error("PartyMember: unknown equipment slot '%s'" % slot)
			return ""

func get_all_equipment() -> Dictionary:
	return { "weapon": weapon, "head": head, "body": body, "accessory": accessory }

# ---------------------------------------------------------------------------
# Experience
# ---------------------------------------------------------------------------

var newly_unlocked_moves: Array = []

func add_experience(amount: int) -> int:
	experience += amount
	newly_unlocked_moves.clear()
	var levels_gained: int = 0
	while experience >= experience_to_next_level:
		_level_up()
		levels_gained += 1
	return levels_gained

func _level_up() -> void:
	level += 1
	experience -= experience_to_next_level
	experience_to_next_level = int(experience_to_next_level * 1.5)
	max_hp += 10
	if max_pp > 0:
		max_pp += 5
	offense += 2
	defense += 1
	speed += 1
	guts += 1
	current_hp = max_hp
	current_pp = max_pp
	_check_move_unlocks()

func _check_move_unlocks() -> void:
	if OS.is_debug_build(): print("PartyMember: checking move unlocks at level %d, keys=%s" % [level, move_unlocks.keys()])
	if not move_unlocks.has(level):
		return
	var path = move_unlocks[level]
	if not ResourceLoader.exists(path):
		push_warning("PartyMember: move unlock path not found: %s" % path)
		return
	var move = load(path)
	if not move:
		push_warning("PartyMember: failed to load move at: %s" % path)
		return
	for existing in psi_moves:
		if existing.resource_path == path:
			return
	psi_moves.append(move)
	newly_unlocked_moves.append(move.move_name)

# ---------------------------------------------------------------------------
# Serialization — temp penalties are intentionally excluded.
# ---------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var move_paths: Array = []
	for move in psi_moves:
		if move and move.resource_path != "":
			move_paths.append(move.resource_path)
	return {
		"resource_path": resource_path,
		"character_id": character_id,
		"character_name": character_name,
		"is_active": is_active,
		"level": level,
		"experience": experience,
		"experience_to_next_level": experience_to_next_level,
		"max_hp": max_hp,
		"current_hp": current_hp,
		"max_pp": max_pp,
		"current_pp": current_pp,
		"offense": offense,
		"defense": defense,
		"speed": speed,
		"guts": guts,
		"luck": luck,
		"vitality": vitality,
		"iq": iq,
		"weapon": weapon,
		"head": head,
		"body": body,
		"accessory": accessory,
		"psi_moves": move_paths,
	}

func from_dict(data: Dictionary) -> void:
	character_id = data.get("character_id", character_id)
	character_name = data.get("character_name", character_name)
	is_active = data.get("is_active", is_active)
	level = data.get("level", level)
	experience = data.get("experience", experience)
	experience_to_next_level = data.get("experience_to_next_level", experience_to_next_level)
	max_hp = data.get("max_hp", max_hp)
	current_hp = data.get("current_hp", current_hp)
	max_pp = data.get("max_pp", max_pp)
	current_pp = data.get("current_pp", current_pp)
	offense = data.get("offense", offense)
	defense = data.get("defense", defense)
	speed = data.get("speed", speed)
	guts = data.get("guts", guts)
	luck = data.get("luck", luck)
	vitality = data.get("vitality", vitality)
	iq = data.get("iq", iq)
	weapon = data.get("weapon", "")
	head = data.get("head", "")
	body = data.get("body", "")
	accessory = data.get("accessory", "")
	var move_paths: Array = data.get("psi_moves", [])
	if not move_paths.is_empty():
		psi_moves.clear()
		for path in move_paths:
			if ResourceLoader.exists(path):
				var move = load(path)
				if move:
					psi_moves.append(move)
