# ItemData.gd
# Resource representing one usable or equippable item.
# Create via File > New Resource > ItemData.
# Save instances to res://resources/items/.
#
# item_id must match the string key used in SaveManager's inventory.
# equipment_slot: leave blank for consumable/key items.
# Valid equipment_slot values: "weapon", "head", "body", "accessory"
# Stat bonuses only apply when the item is equipped — ignored for consumables.
#
# is_usable_outside_battle() returns true for consumables (HEAL_HP, RESTORE_PP)
# and for key items. Equipment is never usable from the item menu directly.

class_name ItemData
extends Resource

enum EffectType {
	HEAL_HP,     # restore HP to one party member
	RESTORE_PP,  # restore PP to one party member
	NONE,        # equipment or items with no direct use effect
}

@export_group("Identity")
@export var item_id: String = ""
@export var display_name: String = "Item"
@export var description: String = ""

@export_group("Type")
@export var is_key_item: bool = false

@export_group("Equipment")
@export var equipment_slot: String = ""

@export_group("Stat Bonuses")
@export var bonus_offense: int = 0
@export var bonus_defense: int = 0
@export var bonus_speed: int = 0
@export var bonus_guts: int = 0
@export var bonus_luck: int = 0
@export var bonus_iq: int = 0
@export var bonus_vitality: int = 0

@export_group("Effect")
@export var effect_type: EffectType = EffectType.NONE
@export var power: int = 0

@export_group("Sound")
@export var use_sound: AudioStream = null

func is_equipment() -> bool:
	return equipment_slot != ""

func is_usable_outside_battle() -> bool:
	if is_equipment():
		return false
	match effect_type:
		EffectType.HEAL_HP, EffectType.RESTORE_PP:
			return true
	# Key items with NONE effect are "usable" but their logic is handled externally.
	# Return true so the menu allows selecting them; stub handling is fine for now.
	if is_key_item:
		return true
	return false
