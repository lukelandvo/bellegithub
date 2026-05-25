# menu_load.gd
# Attach to the root Control of menu_load.tscn.
# Shows 4 save slots. Player selects one to load.
# Matches the visual style of the other menu tabs.

extends Control

const NORMAL_COLOR := Color(0.92, 0.92, 0.96, 1.0)
const DIM_COLOR := Color(0.35, 0.35, 0.45, 1.0)
const SELECTED_COLOR := Color(1.0, 0.85, 0.2, 1.0)
const SELECTOR := "► "

var _selected: int = 0
var _slot_infos: Array = []
var _rows: Array = []
var _active: bool = false
var _confirming: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	refresh()

func refresh() -> void:
	for child in get_children():
		child.free()
	_rows.clear()
	_selected = 0
	_active = false
	_confirming = false
	_slot_infos = SaveManager.get_all_slot_infos()
	_build_ui()

func _build_ui() -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	for i in range(SaveManager.SAVE_SLOT_COUNT):
		var info = _slot_infos[i]
		var row = _build_slot_row(i, info)
		vbox.add_child(row)
		_rows.append(row)

	var hint := Label.new()
	hint.text = "W/S to select   E to load   Esc to cancel"
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", DIM_COLOR)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint)

	_active = true
	_update_selection()

func _build_slot_row(index: int, info: Dictionary) -> Control:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.20, 1.0)
	style.set_border_width_all(1)
	style.border_color = Color(0.25, 0.25, 0.45, 1.0)
	style.set_corner_radius_all(3)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	panel.add_child(hbox)

	# selector label
	var sel_label := Label.new()
	sel_label.text = "  "
	sel_label.add_theme_font_size_override("font_size", 13)
	sel_label.add_theme_color_override("font_color", SELECTED_COLOR)
	sel_label.custom_minimum_size.x = 20
	sel_label.name = "Selector"
	hbox.add_child(sel_label)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 2)
	hbox.add_child(vbox)

	if info.get("empty", true):
		var empty_label := Label.new()
		empty_label.text = "Slot %d   — Empty —" % (index + 1)
		empty_label.add_theme_font_size_override("font_size", 13)
		empty_label.add_theme_color_override("font_color", DIM_COLOR)
		vbox.add_child(empty_label)
	else:
		var top_row := HBoxContainer.new()
		top_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vbox.add_child(top_row)

		var slot_label := Label.new()
		slot_label.text = "Slot %d" % (index + 1)
		slot_label.add_theme_font_size_override("font_size", 11)
		slot_label.add_theme_color_override("font_color", DIM_COLOR)
		slot_label.custom_minimum_size.x = 48
		top_row.add_child(slot_label)

		var name_label := Label.new()
		name_label.text = info.get("save_point_name", "Unknown")
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.add_theme_font_size_override("font_size", 13)
		name_label.add_theme_color_override("font_color", NORMAL_COLOR)
		top_row.add_child(name_label)

		var playtime_label := Label.new()
		playtime_label.text = info.get("playtime", "00:00:00")
		playtime_label.add_theme_font_size_override("font_size", 11)
		playtime_label.add_theme_color_override("font_color", DIM_COLOR)
		top_row.add_child(playtime_label)

		var ts_label := Label.new()
		ts_label.text = info.get("timestamp", "")
		ts_label.add_theme_font_size_override("font_size", 10)
		ts_label.add_theme_color_override("font_color", DIM_COLOR)
		vbox.add_child(ts_label)

	return panel

func _update_selection() -> void:
	for i in _rows.size():
		var sel = _rows[i].get_node_or_null("HBoxContainer/Selector")
		if sel:
			sel.text = SELECTOR if i == _selected else "  "
			sel.add_theme_color_override("font_color",
				SELECTED_COLOR if i == _selected else DIM_COLOR)
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.18, 0.18, 0.30, 1.0) if i == _selected else Color(0.12, 0.12, 0.20, 1.0)
		style.set_border_width_all(1)
		style.border_color = SELECTED_COLOR if i == _selected else Color(0.25, 0.25, 0.45, 1.0)
		style.set_corner_radius_all(3)
		style.content_margin_left = 10
		style.content_margin_right = 10
		style.content_margin_top = 8
		style.content_margin_bottom = 8
		_rows[i].add_theme_stylebox_override("panel", style)

func _unhandled_input(event: InputEvent) -> void:
	if not _active or not visible:
		return
	if _confirming:
		return
	print("menu_load: _unhandled_input fired, action=interact:%s move_forward:%s move_back:%s" % [
		event.is_action_pressed("interact"),
		event.is_action_pressed("move_forward"),
		event.is_action_pressed("move_back")
	])

	if event.is_action_pressed("move_forward"):
		_selected = wrapi(_selected - 1, 0, SaveManager.SAVE_SLOT_COUNT)
		_update_selection()
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("move_back"):
		_selected = wrapi(_selected + 1, 0, SaveManager.SAVE_SLOT_COUNT)
		_update_selection()
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("interact") and not event.is_echo():
		print("menu_load: interact pressed, selected=%d, confirming=%s" % [_selected, _confirming])
		var info = _slot_infos[_selected]
		print("menu_load: slot info = %s" % info)
		if info.get("empty", true):
			print("menu_load: slot is empty, ignoring")
			return
		_active = false
		_confirming = true
		_load_slot(_selected)
		get_viewport().set_input_as_handled()

func _load_slot(slot: int) -> void:
	print("menu_load: loading slot %d" % slot)
	var success = SaveManager.load_save(slot)
	print("menu_load: load_save returned %s" % success)
	if not success:
		_confirming = false
		return
	# store loader reference before closing menu (which frees this node)
	var loaders = get_tree().get_nodes_in_group("scene_loader")
	if loaders.is_empty():
		push_warning("menu_load: no scene_loader found")
		return
	var loader = loaders[0]
	var scene_id = SaveManager.current_scene_id
	print("menu_load: scene_id = '%s'" % scene_id)
	# close menu last — this frees the menu node including this script
	# so we hand off to SceneLoader via a deferred call before that happens
	loader.call_deferred("_load_from_save", scene_id)
	var menu_manager = get_tree().get_first_node_in_group("menu_manager")
	if menu_manager and menu_manager.has_method("close_menu"):
		menu_manager.close_menu()