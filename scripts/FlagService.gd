# FlagService.gd
# Autoload singleton — owns all flag state for BELLE.
# Add to Project > Project Settings > Autoload as "FlagService".
#
# Flags can be bool, int, or string values.
# Use the typed getters to keep call sites clean and safe.
#
# Enemy instance flags:
# Generate via FlagService.make_instance_flag("crow", "forest_area", 0)
# Returns a stable string key like "crow__forest_area__0"

extends Node

const SAVE_VERSION: int = 1
# Flags are saved/loaded via SaveManager — no separate file needed

var _flags: Dictionary = {}
var _debug_mode: bool = false

# ---------------------------------------------------------------------------
# Debug
# ---------------------------------------------------------------------------

func set_debug(enabled: bool) -> void:
	_debug_mode = enabled
	if enabled:
		_flags.clear()

func is_debug() -> bool:
	return _debug_mode

# ---------------------------------------------------------------------------
# Core set / get
# ---------------------------------------------------------------------------

func set_flag(key: String, value: Variant = true) -> void:
	_flags[key] = value

func has_flag(key: String) -> bool:
	return _flags.has(key)

func clear_flag(key: String) -> void:
	_flags.erase(key)

# ---------------------------------------------------------------------------
# Typed getters
# ---------------------------------------------------------------------------

func get_bool(key: String, default: bool = false) -> bool:
	var value = _flags.get(key, default)
	if value is bool:
		return value
	if value is int:
		return value != 0
	return default

func get_int(key: String, default: int = 0) -> int:
	var value = _flags.get(key, default)
	if value is int:
		return value
	if value is bool:
		return 1 if value else 0
	return default

func get_string(key: String, default: String = "") -> String:
	var value = _flags.get(key, default)
	if value is String:
		return value
	return default

# ---------------------------------------------------------------------------
# Integer convenience helpers
# ---------------------------------------------------------------------------

func increment(key: String, amount: int = 1) -> int:
	var current = get_int(key, 0)
	var next = current + amount
	set_flag(key, next)
	return next

# ---------------------------------------------------------------------------
# Enemy instance flag helpers
# ---------------------------------------------------------------------------

func make_instance_flag(enemy_type: String, scene_id: String, index: int) -> String:
	return "%s__%s__%d" % [enemy_type, scene_id, index]

# ---------------------------------------------------------------------------
# Serialization — used by SaveManager only
# ---------------------------------------------------------------------------

func get_flags_for_save() -> Dictionary:
	return _flags.duplicate(true)

func restore_from_save(flags: Dictionary) -> void:
	# Duplicate to prevent external mutation of the restored data
	_flags = flags.duplicate(true)

# ---------------------------------------------------------------------------
# Save / Load
# ---------------------------------------------------------------------------
