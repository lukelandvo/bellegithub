# menu_party.gd
# Attach to the root Control of menu_party.tscn.
# Shows HP and PP bars for all active party members.
# Calls refresh() every time the tab is opened.

extends Control

func _ready() -> void:
	refresh()

func refresh() -> void:
	# Clear previous children
	for child in get_children():
		child.free()

	var members = SaveManager.get_active_members()
	if members.is_empty():
		_add_label("No party members.")
		return

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(vbox)

	for member in members:
		vbox.add_child(_build_member_row(member))

func _build_member_row(member) -> Control:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.20, 1.0)
	style.set_border_width_all(1)
	style.border_color = Color(0.25, 0.25, 0.45, 1.0)
	style.set_corner_radius_all(3)
	panel.add_theme_stylebox_override("panel", style)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	# Name + level
	var name_row := HBoxContainer.new()
	vbox.add_child(name_row)

	var name_label := Label.new()
	name_label.text = member.character_name
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.add_theme_color_override("font_color", Color(0.92, 0.92, 0.96))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(name_label)

	var level_label := Label.new()
	level_label.text = "Lv %d" % member.level
	level_label.add_theme_font_size_override("font_size", 11)
	level_label.add_theme_color_override("font_color", Color(0.55, 0.55, 0.65))
	name_row.add_child(level_label)

	# HP bar
	vbox.add_child(_build_bar_row("HP", member.current_hp, member.max_hp,
		Color(0.35, 0.80, 0.45), Color(0.75, 0.25, 0.25)))

	# PP bar (only if character has PP)
	if member.max_pp > 0:
		vbox.add_child(_build_bar_row("PP", member.current_pp, member.max_pp,
			Color(0.30, 0.55, 0.90), Color(0.90, 0.55, 0.20)))

	return panel

func _build_bar_row(label_text: String, current: int, maximum: int,
		color_high: Color, color_low: Color) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size.x = 24
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.65))
	row.add_child(lbl)

	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = maximum
	bar.value = current
	bar.show_percentage = false
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.custom_minimum_size.y = 10
	var ratio = float(current) / float(maximum) if maximum > 0 else 0.0
	var bar_color = color_high.lerp(color_low, 1.0 - ratio)
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = bar_color
	fill_style.set_corner_radius_all(2)
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.08, 0.08, 0.14)
	bg_style.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("fill", fill_style)
	bar.add_theme_stylebox_override("background", bg_style)
	row.add_child(bar)

	var val_label := Label.new()
	val_label.text = "%d / %d" % [current, maximum]
	val_label.custom_minimum_size.x = 72
	val_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_label.add_theme_font_size_override("font_size", 11)
	val_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.82))
	row.add_child(val_label)

	return row

func _add_label(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.65))
	add_child(lbl)
