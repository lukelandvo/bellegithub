# menu_equipment.gd
# Attach to the root VBoxContainer of menu_equipment.tscn.
# Populates equipment_member_block.tscn instances from active party members.
# activate_content() / deactivate_content() called by menu.gd zone system.
# W/S scrolls through all slots across all members in sequence.
#
# v4.6: _confirm_picker now removes the new item from inventory BEFORE
# adding the old item back, preventing item loss on full-inventory swaps.
# Unequip with full bag is blocked (item is not lost).

extends VBoxContainer

const BLOCK_SCENE := preload("res://scenes/ui/menu/equipment_member_block.tscn")

@onready var block_container: VBoxContainer = %BlockContainer
@onready var empty_label: Label = %EmptyLabel

var _blocks: Array = []
var _current_block: int = 0
var _active: bool = false
var _state: String = "browsing"

var _picker_member = null
var _picker_slot: String = ""
var _picker_items: Array = []
var _picker_rows: Array = []
var _picker_selected: int = 0
var _picker_container: VBoxContainer = null
var _picker_panel: PanelContainer = null
var _picker_interact_was_held: bool = false

func _ready() -> void:
	refresh()

func refresh() -> void:
	for block in _blocks:
		block.queue_free()
	_blocks.clear()
	_current_block = 0
	_active = false
	_state = "browsing"
	_picker_interact_was_held = false
	_close_picker()

	var members := SaveManager.get_active_members()

	empty_label.visible = members.is_empty()
	block_container.visible = not members.is_empty()

	if members.is_empty():
		return

	for member in members:
		var block := BLOCK_SCENE.instantiate()
		block_container.add_child(block)
		block.setup(member)
		block.slot_selected.connect(_on_slot_selected)
		_blocks.append(block)

func activate_content() -> void:
	if _blocks.is_empty():
		_notify_at_top()
		return
	_active = true
	_current_block = 0
	_state = "browsing"
	_blocks[0].activate()

func deactivate_content() -> void:
	_active = false
	_state = "browsing"
	_close_picker()
	for block in _blocks:
		block.deactivate()

func _notify_at_top() -> void:
	var menu = _find_menu()
	if menu and menu.has_method("at_top_of_content"):
		menu.at_top_of_content()

func _find_menu() -> Node:
	var parent = get_parent()
	while parent:
		if parent.has_method("at_top_of_content"):
			return parent
		parent = parent.get_parent()
	return null

func _unhandled_input(event: InputEvent) -> void:
	if not _active or not visible:
		return
	if _state == "browsing":
		_handle_browse_input(event)
	elif _state == "picking":
		_handle_picker_input(event)

func _handle_browse_input(event: InputEvent) -> void:
	if _blocks.is_empty():
		return

	if event.is_action_pressed("move_forward"):
		if _blocks[_current_block].is_at_top() and _current_block == 0:
			_notify_at_top()
		elif _blocks[_current_block].is_at_top() and _current_block > 0:
			_blocks[_current_block].deactivate()
			_current_block -= 1
			_blocks[_current_block].activate_at_bottom()
		else:
			_blocks[_current_block].navigate(-1)
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("move_back"):
		if _blocks[_current_block].is_at_bottom():
			if _current_block < _blocks.size() - 1:
				_blocks[_current_block].deactivate()
				_current_block += 1
				_blocks[_current_block].activate()
		else:
			_blocks[_current_block].navigate(1)
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("interact") and not event.is_echo():
		_blocks[_current_block].confirm()
		get_viewport().set_input_as_handled()

func _handle_picker_input(event: InputEvent) -> void:
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
		_confirm_picker()
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_cancel"):
		_close_picker()
		_state = "browsing"
		get_viewport().set_input_as_handled()

func _on_slot_selected(member, slot_key: String) -> void:
	_picker_member = member
	_picker_slot = slot_key
	_picker_interact_was_held = true
	_open_picker()
	get_tree().create_timer(0.15).timeout.connect(func(): _picker_interact_was_held = false, CONNECT_ONE_SHOT)

func _open_picker() -> void:
	_state = "picking"
	_picker_selected = 0
	_picker_items.clear()
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

	_picker_container = VBoxContainer.new()
	_picker_container.add_theme_constant_override("separation", 4)
	_picker_panel.add_child(_picker_container)

	var header := Label.new()
	header.text = "Equip %s:" % _picker_slot.capitalize()
	header.add_theme_font_size_override("font_size", 11)
	header.add_theme_color_override("font_color", Color(0.40, 0.75, 0.55))
	_picker_container.add_child(header)

	_add_picker_row("— Remove —", "")

	for item_id in SaveManager.get_inventory():
		var item: ItemData = ItemRegistry.get_item(item_id)
		if item and item.equipment_slot == _picker_slot:
			_picker_items.append(item_id)
			_add_picker_row(item.display_name, item_id)

	if _picker_items.is_empty():
		var none := Label.new()
		none.text = "No items available."
		none.add_theme_font_size_override("font_size", 11)
		none.add_theme_color_override("font_color", Color(0.35, 0.35, 0.45))
		_picker_container.add_child(none)

	_update_picker_selection()

func _add_picker_row(label_text: String, _item_id: String) -> void:
	var lbl := Label.new()
	lbl.text = "  " + label_text
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color(0.92, 0.92, 0.96))
	_picker_container.add_child(lbl)
	_picker_rows.append(lbl)

func _update_picker_selection() -> void:
	for i in _picker_rows.size():
		var is_sel = i == _picker_selected
		var item_name: String
		if i == 0:
			item_name = "— Remove —"
		else:
			var item: ItemData = ItemRegistry.get_item(_picker_items[i - 1])
			item_name = item.display_name if item else _picker_items[i - 1]
		_picker_rows[i].text = ("> " if is_sel else "  ") + item_name
		_picker_rows[i].add_theme_color_override("font_color",
			Color(1.0, 0.85, 0.2) if is_sel else Color(0.92, 0.92, 0.96))

func _confirm_picker() -> void:
	if _picker_selected == 0:
		# "— Remove —": return equipped item to inventory, clear slot.
		var currently_equipped: String = _picker_member.get_equipped(_picker_slot)
		if currently_equipped != "":
			if not SaveManager.add_item(currently_equipped):
				# Bag is full — silently close without unequipping.
				# TODO: show "Bag is full!" when UI supports feedback messages.
				_close_picker()
				_state = "browsing"
				return
			_picker_member.equip(_picker_slot, "")
	else:
		# Equip new item.
		# Remove new item from inventory FIRST to free a slot,
		# then add the old equipped item into that freed slot.
		var item_id: String = _picker_items[_picker_selected - 1]
		var currently_equipped: String = _picker_member.get_equipped(_picker_slot)
		SaveManager.remove_item(item_id)
		if currently_equipped != "":
			SaveManager.add_item(currently_equipped)
		_picker_member.equip(_picker_slot, item_id)

	_blocks[_current_block].refresh_slots()
	_close_picker()
	_state = "browsing"

func _close_picker() -> void:
	if _picker_panel and is_instance_valid(_picker_panel):
		_picker_panel.queue_free()
	_picker_panel = null
	_picker_container = null
	_picker_items.clear()
	_picker_rows.clear()
	_picker_selected = 0
	_picker_member = null
	_picker_slot = ""
