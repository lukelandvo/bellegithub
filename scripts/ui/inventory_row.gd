# inventory_row.gd
# Attach to the root PanelContainer of inventory_row.tscn.
# Populated by menu_inventory.gd — do not set data here directly.
#
# Scene structure (inventory_row.tscn):
#   PanelContainer  ← root, this script
#     MarginContainer
#       VBoxContainer
#         HBoxContainer
#           Label  (unique name: NameLabel)  size_flags_horizontal: EXPAND_FILL, font_size: 13
#           Label  (unique name: QtyLabel)   custom_minimum_size.x: 36, horizontal_alignment: RIGHT, font_size: 13
#         Label  (unique name: DescLabel)    font_size: 10, autowrap_mode: WORD_SMART
#
# Mark NameLabel, QtyLabel, DescLabel as unique names (right-click > Access as Unique Name).
# Set a StyleBoxFlat on the PanelContainer via Theme Overrides > Styles > Panel.

extends PanelContainer

@export_group("Colors")
@export var color_normal: Color = Color(0.92, 0.92, 0.96)
@export var color_dimmed: Color = Color(0.45, 0.45, 0.50)
@export var color_selected_text: Color = Color(1.0, 0.85, 0.2)
@export var color_normal_bg: Color = Color(0.12, 0.12, 0.20)
@export var color_selected_bg: Color = Color(0.18, 0.18, 0.30)
@export var color_normal_border: Color = Color(0.25, 0.25, 0.45)
@export var color_selected_border: Color = Color(1.0, 0.85, 0.2)

@onready var name_label: Label = %NameLabel
@onready var qty_label: Label = %QtyLabel
@onready var desc_label: Label = %DescLabel

var _is_selected: bool = false
var _is_usable: bool = true

func _ready() -> void:
	set_selected(false)

func setup(display_name: String, quantity: int, description: String, usable: bool = true) -> void:
	name_label.text = display_name
	qty_label.text = "x%d" % quantity
	desc_label.text = description
	desc_label.visible = description != ""
	_is_usable = usable
	_refresh_colors()

func set_selected(selected: bool) -> void:
	_is_selected = selected
	_refresh_style()
	_refresh_colors()

# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

func _refresh_style() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = color_selected_bg if _is_selected else color_normal_bg
	style.set_border_width_all(1)
	style.border_color = color_selected_border if _is_selected else color_normal_border
	style.set_corner_radius_all(3)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	add_theme_stylebox_override("panel", style)

func _refresh_colors() -> void:
	var text_color: Color
	if _is_selected:
		# Selected always uses highlight — usability doesn't dim a selected row.
		text_color = color_selected_text
	elif _is_usable:
		text_color = color_normal
	else:
		text_color = color_dimmed
	name_label.add_theme_color_override("font_color", text_color)
	qty_label.add_theme_color_override("font_color", text_color)
	# Description always stays dim regardless of selection/usability.
	desc_label.add_theme_color_override("font_color", color_dimmed)
