# menu_party.gd
# Attach to the root VBoxContainer of menu_party.tscn.
# Shows full stats for all active party members.
# Calls refresh() every time the tab is opened.
# Display only — no item selection needed.

extends VBoxContainer

const NORMAL_COLOR := Color(0.92, 0.92, 0.96)
const DIM_COLOR := Color(0.55, 0.55, 0.65)
const VALUE_COLOR := Color(0.75, 0.75, 0.82)

func _ready() -> void:
	refresh()

func refresh() -> void:
	for child in get_children():
		child.free()

	var members := SaveManager.get_active_members()
	if members.is_empty():
		_add_label("No party members.")
		return

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(vbox)

	for member in members:
		vbox.add_child(_build_member_row(member))

func activate_content() -> void:
	pass  # display only — nothing to activate

func deactivate_content() -> void:
	pass

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
	name_label.add_theme_color_override("font_color", NORMAL_COLOR)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(name_label)

	var level_label := Label.new()
	level_label.text = "Lv %d" % member.level
	level_label.add_theme_font_size_override("font_size", 11)
	level_label.add_theme_color_override("font_color", DIM_COLOR)
	name_row.add_child(level_label)

	# HP bar
	vbox.add_child(_build_bar_row("HP", member.current_hp, member.max_hp,
		Color(0.35, 0.80, 0.45), Color(0.75, 0.25, 0.25)))

	# PP bar
	if member.max_pp > 0:
		vbox.add_child(_build_bar_row("PP", member.current_pp, member.max_pp,
			Color(0.30, 0.55, 0.90), Color(0.90, 0.55, 0.20)))

	# Divider
	var sep := HSeparator.new()
	var sep_style := StyleBoxFlat.new()
	sep_style.bg_color = Color(0.25, 0.25, 0.45, 0.5)
	sep.add_theme_stylebox_override("separator", sep_style)
	vbox.add_child(sep)

	# Combat stats grid — shows effective stats so equipment bonuses are visible
	var stats_grid := GridContainer.new()
	stats_grid.columns = 4
	stats_grid.add_theme_constant_override("h_separation", 16)
	stats_grid.add_theme_constant_override("v_separation", 4)
	vbox.add_child(stats_grid)

	_add_stat(stats_grid, "OFF", str(member.get_effective_offense()))
	_add_stat(stats_grid, "DEF", str(member.get_effective_defense()))
	_add_stat(stats_grid, "SPD", str(member.get_effective_speed()))
	_add_stat(stats_grid, "GTS", str(member.get_effective_guts()))

	# EXP row
	var exp_row := HBoxContainer.new()
	vbox.add_child(exp_row)

	var exp_lbl := Label.new()
	exp_lbl.text = "EXP"
	exp_lbl.add_theme_font_size_override("font_size", 10)
	exp_lbl.add_theme_color_override("font_color", DIM_COLOR)
	exp_lbl.custom_minimum_size.x = 30
	exp_row.add_child(exp_lbl)

	var exp_val := Label.new()
	exp_val.text = "%d / %d" % [member.experience, member.experience_to_next_level]
	exp_val.add_theme_font_size_override("font_size", 10)
	exp_val.add_theme_color_override("font_color", VALUE_COLOR)
	exp_row.add_child(exp_val)

	return panel

func _add_stat(parent: GridContainer, label: String, value: String) -> void:
	var lbl := Label.new()
	lbl.text = label
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", DIM_COLOR)
	parent.add_child(lbl)

	var val := Label.new()
	val.text = value
	val.add_theme_font_size_override("font_size", 11)
	val.add_theme_color_override("font_color", NORMAL_COLOR)
	parent.add_child(val)

func _build_bar_row(label_text: String, current: int, maximum: int,
		color_high: Color, color_low: Color) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size.x = 24
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", DIM_COLOR)
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
	val_label.add_theme_color_override("font_color", VALUE_COLOR)
	row.add_child(val_label)

	return row

func _add_label(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", DIM_COLOR)
	add_child(lbl)
