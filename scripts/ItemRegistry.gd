# ItemRegistry.gd
# Autoload singleton — scans res://resources/items/ at startup.

extends Node

const ITEMS_PATH: String = "res://resources/items/"

var _registry: Dictionary = {}

func _ready() -> void:
	_scan()

func _scan() -> void:
	var dir = DirAccess.open(ITEMS_PATH)
	if not dir:
		push_warning("ItemRegistry: folder not found at '%s'" % ITEMS_PATH)
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

func get_item(item_id: String) -> ItemData:
	return _registry.get(item_id, null)

func get_display_name(item_id: String) -> String:
	var item: ItemData = get_item(item_id)
	return item.display_name if item else item_id

func get_all_ids() -> Array:
	return _registry.keys()