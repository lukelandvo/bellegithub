# menu_inventory.gd
# Attach to the root VBoxContainer of menu_inventory.tscn.
# Populates inventory_row.tscn instances from SaveManager inventory.
# activate_content() / deactivate_content() called by menu.gd zone system.
#
# Scene structure (menu_inventory.tscn):
#   VBoxContainer  ← root, this script
#     VBoxContainer  (unique name: RowContainer)  size_flags: Expand+Fill both axes
#     Label          (unique name: CapacityLabel)
#     Label          (unique name: EmptyLabel)     text: "Your bag is empty."
#
# Item use flow:
#   Browse (W/S) → E on usable item → party target picker → E confirms → effect applied
#   Non-usable items (equipment, key items with no effect) are greyed out and E does nothing.
#   Esc / cancel while picking target returns to browse.

extends VBoxContainer

const ROW_SCENE := preload("res://scenes/ui/menu/inventory_row.tscn")

@onready var row_container: VBoxContainer = %RowContainer
@onready var capacity_label: Label = %CapacityLabel
@onready var empty_label: Label = %EmptyLabel

var _rows: Array = []
var _selected: int = 0
var _active: bool = false
var _state: String = "browsing"  # "browsing" | "picking_target"

# Target picker state
var _pending_item: ItemData = null
var _pending_item_id: String = ""
var _picker_panel: PanelContainer = null
var _picker_rows: Array = []
var _picker_selected: int = 0
var _picker_interact_was_held: bool = false

func _ready() -> void:
	refresh()

func refresh() -> void:
	for row in _rows:
		row.queue_free()
	_rows.clear()
	_selected = 0
	_active = false
	_state = "browsing"
	_close_picker()

	var inventory := SaveManager.get_inventory()
	empty_label.visible = inventory.is_empty()
	capacity_label.visible = not inventory.is_empty()
	row_container.visible = not inventory.is_empty()

	if inventory.is_empty():
		return

	for item_id in inventory:
		var qty := SaveManager.get_quantity(item_id)
		var item_data: ItemData = ItemRegistry.get_item(item_id)
		var display_name: String = item_data.display_name if item_data else item_id
		var description: String = item_data.description if item_data else ""
		var usable: bool = item_data != null and item_data.is_usable_outside_battle()

		var row := ROW_SCENE.instantiate()
		row_container.add_child(row)
		row.setup(display_name, qty, description, usable)
		_rows.append(row)

	var used := SaveManager.inventory_count()
	var cap := SaveManager.max_inventory_size()
	capacity_label.text = "Items: %d / %d" % [used, cap]

func activate_content() -> void:
	if _rows.is_empty():
		_notify_at_top()
		return
	_selected = 0
	_active = true
	_update_selection()

func deactivate_content() -> void:
	_active = false
	_state = "browsing"
	_close_picker()
	for row in _rows:
		row.set_selected(false)

# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not _active or not visible:
		return
	match _state:
		"browsing":      _handle_browse_input(event)
		"picking_target": _handle_picker_input(event)

func _handle_browse_input(event: InputEvent) -> void:
	if event.is_action_pressed("move_forward"):
		if _selected == 0:
			_notify_at_top()
		else:
			_selected = wrapi(_selected - 1, 0, _rows.size())
			_update_selection()
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("move_back"):
		_selected = wrapi(_selected + 1, 0, _rows.size())
		_update_selection()
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("interact") and not event.is_echo():
		_try_use_item()
		get_viewport().set_input_as_handled()

func _handle_picker_input(event: InputEvent) -> void:
	# Block the same E press that opened the picker from immediately confirming.
	if _picker_interact_was_held:
		if event.is_action_released("interact"):
			_picker_interact_was_held = false
		return

	if event.is_action_pressed("move_forward"):
		_picker_selected = wrapi(_picker_selected - 1, 0, _picker_rows.size())
		_update_picker_selection()
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("move_back"):
		_picker_selected = wrapi(_picker_selected + 1, 0, _picker_rows.size())
		_update_picker_selection()
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("interact") and not event.is_echo():
		_confirm_target()
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_cancel"):
		_close_picker()
		_state = "browsing"
		get_viewport().set_input_as_handled()

# ---------------------------------------------------------------------------
# Item use
# ---------------------------------------------------------------------------

func _try_use_item() -> void:
	if _rows.is_empty():
		return
	var inventory := SaveManager.get_inventory()
	if _selected >= inventory.size():
		return
	var item_id: String = inventory[_selected]
	var item: ItemData = ItemRegistry.get_item(item_id)
	if not item or not item.is_usable_outside_battle():
		return

	_pending_item = item
	_pending_item_id = item_id
	_picker_interact_was_held = true
	_open_target_picker()
	get_tree().create_timer(0.15).timeout.connect(
		func(): _picker_interact_was_held = false, CONNECT_ONE_SHOT)

func _open_target_picker() -> void:
	_state = "picking_target"
	_picker_selected = 0
	_picker_rows.clear()

	_picker_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.14)
	style.set_border_width_all(1)
	style.border_color = Color(0.25, 0.25, 0.45)
	style.set_corner_radius_all(3)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	_picker_panel.add_theme_stylebox_override("panel", style)
	_picker_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_picker_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	_picker_panel.add_child(vbox)

	var header := Label.new()
	header.text = "Use on who?"
	header.add_theme_font_size_override("font_size", 11)
	header.add_theme_color_override("font_color", Color(0.40, 0.75, 0.55))
	vbox.add_child(header)

	for member in SaveManager.get_active_members():
		var lbl := Label.new()
		lbl.add_theme_font_size_override("font_size", 13)
		lbl.add_theme_color_override("font_color", Color(0.92, 0.92, 0.96))
		vbox.add_child(lbl)
		_picker_rows.append(lbl)

	_update_picker_selection()

func _update_picker_selection() -> void:
	var members := SaveManager.get_active_members()
	for i in _picker_rows.size():
		var is_sel := i == _picker_selected
		var member = members[i]
		var stat_text: String
		if _pending_item and _pending_item.effect_type == ItemData.EffectType.RESTORE_PP:
			stat_text = "PP %d/%d" % [member.current_pp, member.max_pp]
		else:
			stat_text = "HP %d/%d" % [member.current_hp, member.max_hp]
		_picker_rows[i].text = ("%s " % ("> " if is_sel else "  ")) + \
			"%s  %s" % [member.character_name, stat_text]
		_picker_rows[i].add_theme_color_override("font_color",
			Color(1.0, 0.85, 0.2) if is_sel else Color(0.92, 0.92, 0.96))

func _confirm_target() -> void:
	var members := SaveManager.get_active_members()
	if _picker_selected >= members.size():
		return
	var target = members[_picker_selected]

	match _pending_item.effect_type:
		ItemData.EffectType.HEAL_HP:
			target.heal(_pending_item.power)
		ItemData.EffectType.RESTORE_PP:
			target.restore_pp(_pending_item.power)
		ItemData.EffectType.NONE:
			# Key items: stub — future scripted use goes here.
			pass

	SaveManager.remove_item(_pending_item_id)
	_close_picker()

	# Refresh rows, clamp cursor, re-activate at same position.
	var previous_selected := _selected
	refresh()

	if _rows.is_empty():
		# Bag became empty — return to tabs.
		_notify_at_top()
		return

	_selected = mini(previous_selected, _rows.size() - 1)
	_active = true
	_state = "browsing"
	_update_selection()

func _close_picker() -> void:
	if _picker_panel and is_instance_valid(_picker_panel):
		_picker_panel.queue_free()
	_picker_panel = null
	_picker_rows.clear()
	_picker_selected = 0
	_pending_item = null
	_pending_item_id = ""

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _notify_at_top() -> void:
	var menu := _find_menu()
	if menu and menu.has_method("at_top_of_content"):
		menu.at_top_of_content()

func _find_menu() -> Node:
	var parent := get_parent()
	while parent:
		if parent.has_method("at_top_of_content"):
			return parent
		parent = parent.get_parent()
	return null

func _update_selection() -> void:
	for i in _rows.size():
		_rows[i].set_selected(i == _selected)
