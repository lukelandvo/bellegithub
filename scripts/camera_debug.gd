# camera_debug.gd
# Attach to a CanvasLayer node in your scene (layer 100).
# Debug-builds only — safe to leave in shipped scenes, does nothing in release.
#
# F1          — toggle debug panel. Camera continues naturally when off.
# Backspace   — reset to snapshot (values captured when F1 was pressed)
# P           — print all current values to Godot output for copy/paste
#
# Controls (when active):
#   Q / E         — offset_z (zoom in/out)
#   R / F         — offset_y (up/down)
#   T / G         — offset_x (left/right)
#   Z / X         — rotation_x (tilt up/down)
#   Arrow Up/Dn   — follow_speed
#   Arrow Lt/Rt   — rotation_follow_speed
#   [ / ]         — field of view
#   Numpad +/-    — step size
#
# Note: Camera Y rotation is driven by _camera_angle_rad (follow logic).
# It cannot be overridden in follow mode without fighting the camera system.

extends CanvasLayer

@export var enabled: bool = true
@export var step: float = 0.1

var _cam: Node = null
var _panel: PanelContainer
var _label: Label
var _indicator: Label
var _active: bool = false
var _f1_was_pressed: bool = false

# Snapshot — captured from live camera values when F1 opens debug.
# Backspace always resets to this, not to hardcoded defaults.
var _snap_offset_x: float = 0.0
var _snap_offset_y: float = 1.647
var _snap_offset_z: float = 9.0
var _snap_rotation_x: float = -15.4
var _snap_follow_speed: float = 4.0
var _snap_rotation_follow_speed: float = 8.0
var _snap_fov: float = 75.0


func _ready() -> void:
	if not OS.is_debug_build():
		queue_free()
		return
	layer = 100
	_build_ui()
	visible = false


func _build_ui() -> void:
	_indicator = Label.new()
	_indicator.text = "[ CAMERA DEBUG — F1 ]"
	_indicator.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3, 1.0))
	_indicator.add_theme_font_size_override("font_size", 13)
	_indicator.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_indicator.offset_left = -220
	_indicator.offset_top = 10
	_indicator.offset_right = -10
	_indicator.offset_bottom = 30
	_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_indicator)
	_indicator.visible = false

	_panel = PanelContainer.new()
	add_child(_panel)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.82)
	style.set_corner_radius_all(4)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	_panel.add_theme_stylebox_override("panel", style)
	_panel.position = Vector2(12, 12)

	_label = Label.new()
	_label.add_theme_color_override("font_color", Color(1, 1, 0.4, 1))
	_label.add_theme_font_size_override("font_size", 14)
	_panel.add_child(_label)


func _unhandled_input(event: InputEvent) -> void:
	if not enabled or not _active:
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.physical_keycode:
		KEY_UP:
			if _cam: _cam.follow_speed = maxf(0.1, _cam.follow_speed + 0.5)
		KEY_DOWN:
			if _cam: _cam.follow_speed = maxf(0.1, _cam.follow_speed - 0.5)
		KEY_LEFT:
			if _cam: _cam.rotation_follow_speed = maxf(0.5, _cam.rotation_follow_speed - 0.5)
		KEY_RIGHT:
			if _cam: _cam.rotation_follow_speed += 0.5
		KEY_BRACKETLEFT:
			if _cam: _cam.fov = clampf(_cam.fov - 1.0, 20.0, 150.0)
		KEY_BRACKETRIGHT:
			if _cam: _cam.fov = clampf(_cam.fov + 1.0, 20.0, 150.0)
		KEY_BACKSPACE:
			_reset_to_snapshot()
		KEY_P:
			_print_values()


func _process(delta: float) -> void:
	if not enabled:
		return

	var f1_pressed = Input.is_physical_key_pressed(KEY_F1)
	if f1_pressed and not _f1_was_pressed:
		_active = not _active
		visible = _active
		_indicator.visible = _active
		if _active:
			_cam = get_tree().get_first_node_in_group("camera")
			if _cam:
				_capture_snapshot()
	_f1_was_pressed = f1_pressed

	if Input.is_physical_key_pressed(KEY_KP_ADD) and _active:
		step = snappedf(step * 2.0, 0.001)
	if Input.is_physical_key_pressed(KEY_KP_SUBTRACT) and _active:
		step = snappedf(step * 0.5, 0.001)

	if not _active:
		return

	if not _cam or not is_instance_valid(_cam):
		_cam = get_tree().get_first_node_in_group("camera")
	if not _cam:
		_label.text = "No node found in group 'camera'"
		return

	var adj = step * delta * 60.0

	if Input.is_physical_key_pressed(KEY_Q): _cam.offset_z -= adj
	if Input.is_physical_key_pressed(KEY_E): _cam.offset_z += adj
	if Input.is_physical_key_pressed(KEY_R): _cam.offset_y += adj
	if Input.is_physical_key_pressed(KEY_F): _cam.offset_y -= adj
	if Input.is_physical_key_pressed(KEY_T): _cam.offset_x -= adj
	if Input.is_physical_key_pressed(KEY_G): _cam.offset_x += adj

	if Input.is_physical_key_pressed(KEY_Z):
		_cam.rotation_x -= adj
		_cam.rotation_degrees = Vector3(_cam.rotation_x, _cam.rotation_degrees.y, 0.0)
	if Input.is_physical_key_pressed(KEY_X):
		_cam.rotation_x += adj
		_cam.rotation_degrees = Vector3(_cam.rotation_x, _cam.rotation_degrees.y, 0.0)

	# Area info.
	var area_text := "unknown"
	var gm = get_tree().get_first_node_in_group("game_manager")
	if gm:
		var idx = gm.current_area_index
		var area_name := "area_%d" % idx
		if idx < gm.areas.size() and gm.areas[idx]:
			area_name = gm.areas[idx].name
		area_text = "%s (index %d)" % [area_name, idx]

	var is_fixed: bool = _cam.get("_is_fixed") == true

	var player = get_tree().get_first_node_in_group("player")
	var player_pos = player.global_position.snapped(Vector3(0.01, 0.01, 0.01)) if player else Vector3.ZERO

	_label.text = """CAMERA DEBUG  [F1 off]  [Backspace reset]  [P print]
area:       %s%s
─────────────────────────────
offset      x:%+.3f  y:%+.3f  z:%+.3f
            [T/G]    [R/F]    [Q/E]
rotation_x  %+.3f    [Z/X]
follow_spd  %.1f     [UP/DN]
rot_follow  %.1f     [LT/RT]
fov         %.1f     [[ / ]]
step        %.3f     [KP+/-]
─────────────────────────────
cam pos     x:%.2f  y:%.2f  z:%.2f
player pos  x:%.2f  y:%.2f  z:%.2f""" % [
		area_text,
		"  (FIXED)" if is_fixed else "",
		_cam.offset_x, _cam.offset_y, _cam.offset_z,
		_cam.rotation_x,
		_cam.follow_speed,
		_cam.rotation_follow_speed,
		_cam.fov,
		step,
		_cam.global_position.x, _cam.global_position.y, _cam.global_position.z,
		player_pos.x, player_pos.y, player_pos.z
	]


func _capture_snapshot() -> void:
	_snap_offset_x = _cam.offset_x
	_snap_offset_y = _cam.offset_y
	_snap_offset_z = _cam.offset_z
	_snap_rotation_x = _cam.rotation_x
	_snap_follow_speed = _cam.follow_speed
	_snap_rotation_follow_speed = _cam.rotation_follow_speed
	_snap_fov = _cam.fov


func _reset_to_snapshot() -> void:
	if not _cam or not is_instance_valid(_cam):
		return
	_cam.offset_x = _snap_offset_x
	_cam.offset_y = _snap_offset_y
	_cam.offset_z = _snap_offset_z
	_cam.rotation_x = _snap_rotation_x
	_cam.follow_speed = _snap_follow_speed
	_cam.rotation_follow_speed = _snap_rotation_follow_speed
	_cam.fov = _snap_fov
	_cam.rotation_degrees = Vector3(_snap_rotation_x, _cam.rotation_degrees.y, 0.0)


func _print_values() -> void:
	if not _cam:
		return
	print("=== CAMERA VALUES ===")
	print("offset_x: ", _cam.offset_x)
	print("offset_y: ", _cam.offset_y)
	print("offset_z: ", _cam.offset_z)
	print("rotation_x: ", _cam.rotation_x)
	print("follow_speed: ", _cam.follow_speed)
	print("rotation_follow_speed: ", _cam.rotation_follow_speed)
	print("fov: ", _cam.fov)
	print("cam position: ", _cam.global_position)
	print("=====================")
