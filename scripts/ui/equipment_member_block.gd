# equipment_member_block.gd
# Attach to the root VBoxContainer of equipment_member_block.tscn.
# Populated by menu_equipment.gd — do not set data here directly.

extends VBoxContainer

const SLOT_SCENE := preload("res://scenes/ui/menu/equipment_slot_row.tscn")

const SLOT_KEYS := ["weapon", "head", "body", "accessory"]
const SLOT_LABELS := {
	"weapon": "Weapon",
	"head": "Head",
	"body": "Body",
	"accessory": "Accessory",
}

@export_group("Colors")
@export var color_member_name: Color = Color(0.40, 0.75, 0.55)
@export var color_divider: Color = Color(0.25, 0.25, 0.45)

@onready var name_label: Label = %MemberNameLabel
@onready var divider: ColorRect = %Divider
@onready var slot_container: VBoxContainer = %SlotContainer

var _member = null
var _slot_rows: Array = []
var _selected_slot: int = 0
var _active: bool = false

signal slot_selected(member, slot_key: String)

func _ready() -> void:
	divider.color = color_divider
	name_label.add_theme_color_override("font_color", color_member_name)

func setup(member) -> void:
	_member = member
	name_label.text = member.character_name.to_upper()
	for slot_key in SLOT_KEYS:
		var equipped: String = member.get_equipped(slot_key)
		var row := SLOT_SCENE.instantiate()
		slot_container.add_child(row)
		row.setup(SLOT_LABELS[slot_key], equipped)
		_slot_rows.append(row)

func activate() -> void:
	_active = true
	_selected_slot = 0
	_update_selection()

func activate_at_bottom() -> void:
	_active = true
	_selected_slot = _slot_rows.size() - 1
	_update_selection()

func deactivate() -> void:
	_active = false
	for row in _slot_rows:
		row.set_selected(false)

func is_at_top() -> bool:
	return _selected_slot == 0

func is_at_bottom() -> bool:
	return _selected_slot == _slot_rows.size() - 1

func navigate(direction: int) -> void:
	if not _active:
		return
	_selected_slot = wrapi(_selected_slot + direction, 0, _slot_rows.size())
	_update_selection()

func confirm() -> void:
	if not _active:
		return
	emit_signal("slot_selected", _member, SLOT_KEYS[_selected_slot])

func refresh_slots() -> void:
	for i in _slot_rows.size():
		var slot_key = SLOT_KEYS[i]
		var equipped: String = _member.get_equipped(slot_key)
		_slot_rows[i].setup(SLOT_LABELS[slot_key], equipped)

func _update_selection() -> void:
	for i in _slot_rows.size():
		_slot_rows[i].set_selected(i == _selected_slot)
