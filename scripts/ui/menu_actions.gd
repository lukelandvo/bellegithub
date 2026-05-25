# menu_actions.gd
# Attach to the root Control of menu_actions.tscn.
# Lists PSI/action moves available to each active party member.
# Move use outside of battle is stubbed — wire up when PSI system is ready.

extends Control

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

	if member.psi_moves.is_empty():
		var none_label := Label.new()
		none_label.text = "No actions learned."
		none_label.add_theme_font_size_override("font_size", 12)
		none_label.add_theme_color_override("font_color", Color(0.35, 0.35, 0.45))
		vbox.add_child(none_label)
	else:
		for move in member.psi_moves:
			if move:
				vbox.add_child(_build_move_row(move, member))

	return vbox

func _build_move_row(move: Resource, member) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.custom_minimum_size.y = 24

	var name_label := Label.new()
	# Uses move.move_name — matches ActionMove resource field
	name_label.text = move.get("move_name") if move.get("move_name") else "???"
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_color", Color(0.92, 0.92, 0.96))
	row.add_child(name_label)

	# PP cost
	var pp_cost = move.get("pp_cost") if move.get("pp_cost") != null else 0
	var pp_label := Label.new()
	pp_label.text = "%d PP" % pp_cost
	pp_label.custom_minimum_size.x = 48
	pp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var can_afford = member.current_pp >= pp_cost
	pp_label.add_theme_color_override("font_color",
		Color(0.55, 0.55, 0.65) if can_afford else Color(0.65, 0.30, 0.30))
	pp_label.add_theme_font_size_override("font_size", 12)
	row.add_child(pp_label)

	return row

func _add_label(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.65))
	add_child(lbl)
