# menu_equipment.gd
# Attach to the root Control of menu_equipment.tscn.
# Shows weapon/head/body/accessory slots for each active party member.
# Equipping from inventory is stubbed — wire up when ItemData exists.

extends Control

const SLOT_LABELS := {
	"weapon": "Weapon",
	"head": "Head",
	"body": "Body",
	"accessory": "Accessory",
}

func _ready() -> void:
	refresh()

func refresh() -> void:
	for child in get_children():
		child.free()

	var members = SaveManager.get_active_members()
	if members.is_empty():
		_add_label("No party members.")
		return

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	for member in members:
		vbox.add_child(_build_member_block(member))

func _build_member_block(member) -> Control:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Member name header
	var name_label := Label.new()
	name_label.text = member.character_name.to_upper()
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.add_theme_color_override("font_color", Color(0.40, 0.75, 0.55))
	vbox.add_child(name_label)

	var divider := ColorRect.new()
	divider.color = Color(0.25, 0.25, 0.45)
	divider.custom_minimum_size.y = 1
	vbox.add_child(divider)

	# Equipment slots
	for slot_key in ["weapon", "head", "body", "accessory"]:
		var equipped: String = member.get_equipped(slot_key)
		vbox.add_child(_build_slot_row(SLOT_LABELS[slot_key], equipped))

	return vbox

func _build_slot_row(slot_label: String, equipped: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.custom_minimum_size.y = 24

	var lbl := Label.new()
	lbl.text = slot_label
	lbl.custom_minimum_size.x = 80
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.65))
	row.add_child(lbl)

	var equipped_label := Label.new()
	if equipped == "":
		equipped_label.text = "—"
		equipped_label.add_theme_color_override("font_color", Color(0.35, 0.35, 0.45))
	else:
		# TODO: replace with ItemData.get_display_name(equipped) when ItemData exists
		equipped_label.text = equipped
		equipped_label.add_theme_color_override("font_color", Color(0.92, 0.92, 0.96))
	equipped_label.add_theme_font_size_override("font_size", 12)
	equipped_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(equipped_label)

	return row

func _add_label(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.65))
	add_child(lbl)
