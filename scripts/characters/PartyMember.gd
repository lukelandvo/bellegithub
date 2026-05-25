# PartyMember.gd
# Resource representing one party member's full state.
# Create one .tres per character via File > New Resource > PartyMember.
# Assign to SaveManager.party slots in the inspector.
#
# Equipment slots: weapon, head, body, accessory.
# All characters share the same slot layout.
#
# current_hp and current_pp persist in the .tres file.
# Call SaveManager.save() after any battle or save point to write state.

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
@export var max_hp: int = 100
@export var current_hp: int = 100:
	set(value):
		current_hp = clampi(value, 0, max_hp)

@export_group("PSI")
@export var max_pp: int = 0
@export var current_pp: int = 0:
	set(value):
		current_pp = clampi(value, 0, max_pp)

@export_group("Combat Stats")
@export var offense: int = 10
@export var defense: int = 5
@export var speed: int = 10
@export var guts: int = 5
@export var luck: int = 5
@export var vitality: int = 5
@export var iq: int = 5

@export_group("Equipment")
@export var weapon: String = ""
@export var head: String = ""
@export var body: String = ""
@export var accessory: String = ""

@export_group("Moves")
@export var psi_moves: Array[Resource] = []

# ---------------------------------------------------------------------------
# Derived helpers
# ---------------------------------------------------------------------------

func is_alive() -> bool:
	return current_hp > 0

func is_ko() -> bool:
	return current_hp <= 0

func take_damage(amount: int) -> int:
	var actual = maxi(1, amount - defense)
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
# Experience — loops until XP settles below threshold
# Returns number of levels gained (0 if none).
# ---------------------------------------------------------------------------

func add_experience(amount: int) -> int:
	experience += amount
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

# ---------------------------------------------------------------------------
# Serialization
# ---------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		# FIX: store resource_path so SaveManager.load_save() can reconstruct
		# this member if its slot was null at boot (e.g. Yabo before his path
		# is added to PARTY_MEMBER_PATHS).
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
	}

func from_dict(data: Dictionary) -> void:
	character_id = data.get("character_id", character_id)
	character_name = data.get("character_name", character_name)
	is_active = data.get("is_active", is_active)
	level = data.get("level", level)
	experience = data.get("experience", experience)
	experience_to_next_level = data.get("experience_to_next_level", experience_to_next_level)
	max_hp = data.get("max_hp", max_hp)
	# FIX: fall back to current_hp (not max_hp) if the key is missing,
	# so a partial/corrupted dict doesn't silently full-heal the character.
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