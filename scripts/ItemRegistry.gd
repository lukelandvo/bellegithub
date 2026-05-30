# ItemRegistry.gd
# Autoload singleton — scans res://resources/items/ at startup and builds
# a lookup table of item_id -> ItemData.
#
# Add to Project > Project Settings > Autoload as "ItemRegistry".
#
# Usage:
#   ItemRegistry.get_item("herb")         -> ItemData or null
#   ItemRegistry.get_display_name("herb") -> "Herb" (falls back to raw id if not found)

extends Node

const ITEMS_PATH: String = "res://resources/items/"

var _registry: Dictionary = {}

func _ready() -> void:
	_scan()

func _scan() -> void:
	var dir = DirAccess.open(ITEMS_PATH)
	if not dir:
		push_warning("ItemRegistry: folder not found at '%s' — create res://resources/items/ and add .tres files" % ITEMS_PATH)
		return

	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			var path = ITEMS_PATH + file_name
			var resource = load(path)
			if resource is ItemData:
				if resource.item_id == "":
					push_warning("ItemRegistry: item at '%s' has no item_id set — skipping" % path)
				elif _registry.has(resource.item_id):
					push_warning("ItemRegistry: duplicate item_id '%s' found at '%s' — skipping" % [resource.item_id, path])
				else:
					_registry[resource.item_id] = resource
		file_name = dir.get_next()
	dir.list_dir_end()

	if OS.is_debug_build():
		print("ItemRegistry: loaded %d items — %s" % [_registry.size(), _registry.keys()])

# Returns the ItemData resource for the given id, or null if not found.
func get_item(item_id: String) -> ItemData:
	return _registry.get(item_id, null)

# Returns the display name for an item id.
# Falls back to the raw item_id string if no resource is registered.
func get_display_name(item_id: String) -> String:
	var item: ItemData = get_item(item_id)
	return item.display_name if item else item_id

# Returns all registered item ids. Useful for debugging.
func get_all_ids() -> Array:
	return _registry.keys()
