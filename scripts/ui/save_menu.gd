# save_menu.gd
# Attach to a CanvasLayer node in save_menu.tscn.
# Called by the save NPC after dialogue ends.
# Shows 4 save slots with metadata. E to select, Escape to cancel.
#
# Scene structure:
#   CanvasLayer (layer 10) — save_menu.gd
#     PanelContainer
#       VBoxContainer
#         Label (title)
#         [slot rows built in code]

extends CanvasLayer

signal save_completed(slot: int)
signal save_cancelled

@export var title_text: String = "Save your progress?"
@export var empty_slot_text: String = "--- Empty ---"
@export var font_size: int = 16
@export var selector: String = "►"
@export var normal_color: Color = Color.WHITE
@export var selected_color: Color = Color.YELLOW
@export var panel_color: Color = Color(0.0, 0.0, 0.0, 0.88)

var _selected: int = 0
var _slot_buttons: Array[Button] = []
var _slot_infos: Array = []
var _active: bool = false
var _panel: PanelContainer
var _vbox: VBoxContainer


func _ready() -> void:
	layer = 10
	_build_ui()
	hide()


func _build_ui() -> void:
	_panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = panel_color
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	_panel.add_theme_stylebox_override("panel", style)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(420, 0)
	add_child(_panel)

	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", 8)
	_panel.add_child(_vbox)

	var title = Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", font_size + 2)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_vbox.add_child(title)

	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	_vbox.add_child(spacer)


func open() -> void:
	_slot_infos = SaveManager.get_all_slot_infos()
	_rebuild_slots()
	_selected = 0
	_update_selection()
	show()
	_active = true
	FlagService.set_flag("save_menu_open")
	for npc in get_tree().get_nodes_in_group("npc"):
		if npc.get("interaction_area") and npc.interaction_area:
			npc.interaction_area.lock()
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_method("disable_movement"):
		player.disable_movement()


func _rebuild_slots() -> void:
	for btn in _slot_buttons:
		btn.queue_free()
	_slot_buttons.clear()

	var font = load("res://fonts/Apple_Kid.ttf") if ResourceLoader.exists("res://fonts/Apple_Kid.ttf") else null

	for i in range(SaveManager.SAVE_SLOT_COUNT):
		var info = _slot_infos[i]
		var btn = Button.new()
		btn.flat = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(370, 52)
		if font:
			btn.add_theme_font_override("font", font)
		btn.add_theme_font_size_override("font_size", font_size)
		btn.add_theme_color_override("font_color", normal_color)
		btn.add_theme_color_override("font_hover_color", normal_color)
		btn.add_theme_color_override("font_pressed_color", normal_color)
		btn.add_theme_color_override("font_focus_color", normal_color)
		btn.text = _format_slot(i, info)
		_vbox.add_child(btn)
		_slot_buttons.append(btn)


func _format_slot(index: int, info: Dictionary) -> String:
	var prefix = "  "
	if info.get("empty", true):
		return "%sSlot %d   %s" % [prefix, index + 1, empty_slot_text]
	return "%sSlot %d   %s\n         %s   %s" % [
		prefix,
		index + 1,
		info.get("save_point_name", "Unknown"),
		info.get("timestamp", ""),
		info.get("playtime", "00:00:00")
	]


func _update_selection() -> void:
	for i in _slot_buttons.size():
		var is_selected = i == _selected
		var prefix = selector + " " if is_selected else "  "
		var info = _slot_infos[i]
		_slot_buttons[i].text = prefix + _format_slot(i, info).lstrip(" ")
		_slot_buttons[i].add_theme_color_override("font_color",
			selected_color if is_selected else normal_color)


func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return

	if event.is_action_pressed("move_forward"):
		_selected = wrapi(_selected - 1, 0, SaveManager.SAVE_SLOT_COUNT)
		_update_selection()
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("move_back"):
		_selected = wrapi(_selected + 1, 0, SaveManager.SAVE_SLOT_COUNT)
		_update_selection()
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("interact"):
		_confirm_save()
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_cancel"):
		_cancel()
		get_viewport().set_input_as_handled()


func _confirm_save() -> void:
	_active = false
	SaveManager.save(_selected)
	hide()
	# don't restore player here — npc handles it after save_confirm dialogue ends
	FlagService.clear_flag("save_menu_open")
	emit_signal("save_completed", _selected)


func _cancel() -> void:
	_active = false
	hide()
	await get_tree().create_timer(0.25).timeout
	FlagService.clear_flag("save_menu_open")
	for npc in get_tree().get_nodes_in_group("npc"):
		if npc.get("interaction_area") and npc.interaction_area:
			npc.interaction_area.unlock()
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_method("enable_movement"):
		player.enable_movement()
	emit_signal("save_cancelled")

func _restore_player() -> void:
	# delay restoring so the E press that closed the menu doesn't immediately trigger interaction
	await get_tree().create_timer(0.25).timeout
	FlagService.clear_flag("save_menu_open")
	for npc in get_tree().get_nodes_in_group("npc"):
		if npc.get("interaction_area") and npc.interaction_area:
			npc.interaction_area.unlock()
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_method("enable_movement"):
		player.enable_movement()
