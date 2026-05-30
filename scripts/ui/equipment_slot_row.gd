# equipment_slot_row.gd
# Attach to the root PanelContainer of equipment_slot_row.tscn.
# Populated by equipment_member_block.gd — do not set data here directly.

extends PanelContainer

@export_group("Colors")
@export var color_slot_label: Color = Color(0.55, 0.55, 0.65)
@export var color_equipped: Color = Color(0.92, 0.92, 0.96)
@export var color_empty: Color = Color(0.35, 0.35, 0.45)
@export var color_normal_bg: Color = Color(0.12, 0.12, 0.20)
@export var color_normal_border: Color = Color(0.25, 0.25, 0.45)
@export var color_selected_bg: Color = Color(0.18, 0.18, 0.30)
@export var color_selected_border: Color = Color(1.0, 0.85, 0.2)

@onready var slot_label: Label = %SlotLabel
@onready var equipped_label: Label = %EquippedLabel

func _ready() -> void:
	set_selected(false)

func setup(slot_name: String, equipped: String) -> void:
	slot_label.text = slot_name
	slot_label.add_theme_color_override("font_color", color_slot_label)
	if equipped == "":
		equipped_label.text = "—"
		equipped_label.add_theme_color_override("font_color", color_empty)
	else:
		var item: ItemData = ItemRegistry.get_item(equipped)
		equipped_label.text = item.display_name if item else equipped
		equipped_label.add_theme_color_override("font_color", color_equipped)

func set_selected(selected: bool) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = color_selected_bg if selected else color_normal_bg
	style.set_border_width_all(1)
	style.border_color = color_selected_border if selected else color_normal_border
	style.set_corner_radius_all(3)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	add_theme_stylebox_override("panel", style)