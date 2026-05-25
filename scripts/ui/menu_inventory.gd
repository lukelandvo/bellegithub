# menu_inventory.gd
# Attach to the root Control of menu_inventory.tscn.
# Lists all items in the player's inventory with quantities.
# Item use from the menu is stubbed — wire up when ItemData exists.

extends Control

func _ready() -> void:
	refresh()

func refresh() -> void:
	for child in get_children():
		child.free()

	var inventory = SaveManager.get_inventory()

	if inventory.is_empty():
		_add_label("Your bag is empty.")
		return

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	for item_id in inventory:
		var qty = SaveManager.get_quantity(item_id)
		vbox.add_child(_build_item_row(item_id, qty))

	# Capacity footer
	var capacity_label := Label.new()
	var used = SaveManager.inventory_count()
	var cap = SaveManager.max_inventory_size()
	capacity_label.text = "Items: %d / %d" % [used, cap]
	capacity_label.add_theme_font_size_override("font_size", 11)
	capacity_label.add_theme_color_override("font_color", Color(0.55, 0.55, 0.65))
	capacity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vbox.add_child(capacity_label)

func _build_item_row(item_id: String, quantity: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.custom_minimum_size.y = 28

	var name_label := Label.new()
	# TODO: replace item_id with ItemData.get_display_name(item_id) when ItemData exists
	name_label.text = item_id
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_color", Color(0.92, 0.92, 0.96))
	row.add_child(name_label)

	var qty_label := Label.new()
	qty_label.text = "x%d" % quantity
	qty_label.custom_minimum_size.x = 36
	qty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	qty_label.add_theme_font_size_override("font_size", 13)
	qty_label.add_theme_color_override("font_color", Color(0.55, 0.55, 0.65))
	row.add_child(qty_label)

	# Divider
	var wrapper := VBoxContainer.new()
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.add_child(row)
	var divider := ColorRect.new()
	divider.color = Color(0.18, 0.18, 0.28)
	divider.custom_minimum_size.y = 1
	wrapper.add_child(divider)

	return wrapper

func _add_label(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.65))
	add_child(lbl)
