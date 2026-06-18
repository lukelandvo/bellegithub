# SaveManager.gd
# Autoload singleton — owns party state, inventory, and save/load.

extends Node

const SAVE_VERSION: int = 1
const SAVE_SLOT_COUNT: int = 4
const SAVE_PATH_TEMPLATE: String = "user://belle_save_%d.dat"

const BASE_INVENTORY_SIZE: int = 16
const INVENTORY_PER_MEMBER: int = 8
const MAX_PARTY_SIZE: int = 4

const PARTY_MEMBER_PATHS: Array = [
	"res://resources/players/skip.tres",
	"res://resources/players/dad.tres",
	"",
	"",
]

var party: Array = []

var current_save_point_id: String = ""
var current_save_point_name: String = ""
var current_scene_id: String = ""
var saved_player_position: Vector3 = Vector3.ZERO
var saved_player_rotation: float = 0.0
var _pending_follower_paths: Array = []

var _playtime_seconds: float = 0.0
var _playtime_active: bool = false

var _inventory: Array = []
var _quantities: Dictionary = {}

func _ready() -> void:
	party.resize(MAX_PARTY_SIZE)
	for i in range(MAX_PARTY_SIZE):
		var path = PARTY_MEMBER_PATHS[i] if i < PARTY_MEMBER_PATHS.size() else ""
		if path != "" and ResourceLoader.exists(path):
			party[i] = load(path)
		else:
			party[i] = null

func _process(delta: float) -> void:
	if _playtime_active:
		_playtime_seconds += delta

func start_playtime() -> void:
	_playtime_active = true

func stop_playtime() -> void:
	_playtime_active = false

func get_playtime_string() -> String:
	var total = int(_playtime_seconds)
	@warning_ignore("integer_division")
	var hours = total / 3600
	@warning_ignore("integer_division")
	var minutes = (total % 3600) / 60
	var seconds = total % 60
	return "%02d:%02d:%02d" % [hours, minutes, seconds]

func _slot_path(slot: int) -> String:
	return SAVE_PATH_TEMPLATE % slot

func get_slot_info(slot: int) -> Dictionary:
	var path = _slot_path(slot)
	if not FileAccess.file_exists(path):
		return { "empty": true, "slot": slot }
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return { "empty": true, "slot": slot }
	var data = file.get_var()
	file.close()
	if not data is Dictionary:
		return { "empty": true, "slot": slot }
	return {
		"empty": false,
		"slot": slot,
		"save_point_name": data.get("save_point_name", "Unknown"),
		"scene_id": data.get("scene_id", ""),
		"timestamp": data.get("timestamp", ""),
		"playtime": data.get("playtime", "00:00:00"),
	}

func get_all_slot_infos() -> Array:
	var result = []
	for i in range(SAVE_SLOT_COUNT):
		result.append(get_slot_info(i))
	return result

func get_member(slot: int):
	if slot < 0 or slot >= party.size():
		push_error("SaveManager: party slot %d out of range" % slot)
		return null
	return party[slot]

func get_active_members() -> Array:
	var result: Array = []
	for member in party:
		if member and member.is_active:
			result.append(member)
	return result

func get_active_count() -> int:
	return get_active_members().size()

func add_member(member, slot: int) -> void:
	if slot < 0 or slot >= MAX_PARTY_SIZE:
		push_error("SaveManager: invalid party slot %d" % slot)
		return
	party[slot] = member
	member.is_active = true

func remove_member(slot: int) -> void:
	if slot < 0 or slot >= party.size():
		return
	if party[slot]:
		party[slot].is_active = false
	party[slot] = null

func is_slot_active(slot: int) -> bool:
	return party[slot] != null and party[slot].is_active

func recruit_party_member(character_id: int) -> void:
	for i in range(MAX_PARTY_SIZE):
		if party[i] and party[i].character_id == character_id:
			party[i].is_active = true
			return
	push_warning("SaveManager: no PartyMember found with character_id %d" % character_id)

func max_inventory_size() -> int:
	var extras = max(0, get_active_count() - 1)
	return BASE_INVENTORY_SIZE + (INVENTORY_PER_MEMBER * extras)

func inventory_count() -> int:
	return _inventory.size()

func is_inventory_full() -> bool:
	return _inventory.size() >= max_inventory_size()

func has_item(item_id: String) -> bool:
	return _quantities.get(item_id, 0) > 0

func get_quantity(item_id: String) -> int:
	return _quantities.get(item_id, 0)

func add_item(item_id: String, quantity: int = 1) -> bool:
	if not has_item(item_id) and is_inventory_full():
		return false
	if not _inventory.has(item_id):
		_inventory.append(item_id)
	_quantities[item_id] = _quantities.get(item_id, 0) + quantity
	return true

func remove_item(item_id: String, quantity: int = 1) -> bool:
	if not has_item(item_id):
		return false
	var current = _quantities.get(item_id, 0)
	if current < quantity:
		return false
	var remaining = current - quantity
	if remaining <= 0:
		_quantities.erase(item_id)
		_inventory.erase(item_id)
	else:
		_quantities[item_id] = remaining
	return true

func get_inventory() -> Array:
	return _inventory.duplicate()

func activate_save_point(save_point_id: String, save_point_name: String, scene_id: String, player_position: Vector3 = Vector3.ZERO, player_rotation: float = 0.0) -> void:
	current_save_point_id = save_point_id
	current_save_point_name = save_point_name
	current_scene_id = scene_id
	saved_player_position = player_position
	saved_player_rotation = player_rotation

func save(slot: int) -> void:
	if FlagService.is_debug():
		return

	var party_data: Array = []
	for member in party:
		if member:
			party_data.append(member.to_dict())
		else:
			party_data.append(null)

	var inventory_data: Dictionary = {
		"items": _inventory.duplicate(),
		"quantities": _quantities.duplicate()
	}

	var timestamp = Time.get_datetime_string_from_system()

	var save_data: Dictionary = {
		"version": SAVE_VERSION,
		"save_point_id": current_save_point_id,
		"save_point_name": current_save_point_name,
		"scene_id": current_scene_id,
		"player_position": { "x": saved_player_position.x, "y": saved_player_position.y, "z": saved_player_position.z },
		"player_rotation": saved_player_rotation,
		"timestamp": timestamp,
		"playtime": get_playtime_string(),
		"playtime_seconds": _playtime_seconds,
		"party": party_data,
		"inventory": inventory_data,
		"flags": FlagService.get_flags_for_save(),
		"followers": FollowerManager.get_follower_paths()
	}

	var file = FileAccess.open(_slot_path(slot), FileAccess.WRITE)
	if not file:
		push_error("SaveManager: failed to open save file for writing (slot %d)" % slot)
		return
	file.store_var(save_data)
	file.close()

func load_save(slot: int) -> bool:
	var path = _slot_path(slot)
	if not FileAccess.file_exists(path):
		return false

	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("SaveManager: failed to open save file for reading (slot %d)" % slot)
		return false

	var save_data = file.get_var()
	file.close()

	if not save_data is Dictionary:
		push_error("SaveManager: save data is corrupted (slot %d)" % slot)
		return false

	var version = save_data.get("version", 0)
	if version != SAVE_VERSION:
		push_error("SaveManager: save version mismatch in slot %d" % slot)
		return false

	current_save_point_id = save_data.get("save_point_id", "")
	current_save_point_name = save_data.get("save_point_name", "")
	current_scene_id = save_data.get("scene_id", "")
	_playtime_seconds = save_data.get("playtime_seconds", 0.0)
	var pos_data = save_data.get("player_position", {})
	saved_player_position = Vector3(pos_data.get("x", 0.0), pos_data.get("y", 0.0), pos_data.get("z", 0.0))
	saved_player_rotation = save_data.get("player_rotation", 0.0)

	var party_data: Array = save_data.get("party", [])
	for i in range(min(party_data.size(), MAX_PARTY_SIZE)):
		var member_data = party_data[i]
		if member_data == null:
			party[i] = null
			continue
		if party[i] == null:
			push_error("SaveManager: no PartyMember resource in slot %d" % i)
			continue
		party[i].from_dict(member_data)

	# Inventory loading with validation against ItemRegistry
	var inv_data: Dictionary = save_data.get("inventory", {})
	var saved_items: Array = inv_data.get("items", [])
	var saved_quantities: Dictionary = inv_data.get("quantities", {})

	_inventory.clear()
	_quantities.clear()

	for item_id in saved_items:
		var item: ItemData = ItemRegistry.get_item(item_id)
		if item:
			_inventory.append(item_id)
			_quantities[item_id] = saved_quantities.get(item_id, 1)
		else:
			push_warning("SaveManager: unknown item_id '%s' skipped during load" % item_id)

	FlagService.restore_from_save(save_data.get("flags", {}))
	FlagService.clear_flag("save_menu_open")
	FlagService.clear_flag("save_confirming")
	FlagService.clear_flag("wants_save")
	_pending_follower_paths = save_data.get("followers", [])

	return true

func delete_save(slot: int) -> void:
	var path = _slot_path(slot)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

func save_exists(slot: int = -1) -> bool:
	if slot >= 0:
		return FileAccess.file_exists(_slot_path(slot))
	for i in range(SAVE_SLOT_COUNT):
		if FileAccess.file_exists(_slot_path(i)):
			return true
	return false
