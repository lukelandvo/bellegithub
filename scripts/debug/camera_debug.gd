# camera_debug.gd
# Attach to a CanvasLayer node in your scene (layer 100).
# Debug-builds only — safe to leave in shipped scenes, does nothing in release.
#
# F1 — toggle debug on/off. Turning off resets camera to defaults.
#
# Controls (when active):
#   Q / E       — offset_z (zoom in/out)
#   R / F       — offset_y (up/down)
#   T / G       — offset_x (left/right)
#   Z / X       — rotation_x (angle up/down)
#   C / V       — rotation_y (rotate left/right)
#   Arrow Up/Dn — follow_speed
#   Numpad +/-  — step size

extends CanvasLayer

@export var enabled: bool = true
@export var step: float = 0.1

@export_group("Default Values")
@export var default_offset_x: float = 0.0
@export var default_offset_y: float = 1.647
@export var default_offset_z: float = 9.0
@export var default_rotation_x: float = -15.4
@export var default_rotation_y: float = 0.0
@export var default_follow_speed: float = 4.0

var _cam: Node = null
var _panel: PanelContainer
var _label: Label
var _active: bool = false
var _f1_was_pressed: bool = false


func _ready() -> void:
	if not OS.is_debug_build():
		queue_free()
		return
	layer = 100
	_build_ui()
	visible = false


func _build_ui() -> void:
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
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_UP:
				if _cam:
					_cam.follow_speed += 0.5
			KEY_DOWN:
				if _cam:
					_cam.follow_speed = maxf(0.5, _cam.follow_speed - 0.5)


func _process(delta: float) -> void:
	if not enabled:
		return

	# F1 toggle — polled in _process so it can't be swallowed by other handlers.
	var f1_pressed = Input.is_physical_key_pressed(KEY_F1)
	if f1_pressed and not _f1_was_pressed:
		_active = not _active
		visible = _active
		if _active:
			_cam = get_tree().get_first_node_in_group("camera")
		else:
			_reset_camera()
	_f1_was_pressed = f1_pressed

	# Step size.
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
		_cam.rotation_degrees = Vector3(_cam.rotation_x, _cam.rotation_y, 0.0)
	if Input.is_physical_key_pressed(KEY_X):
		_cam.rotation_x += adj
		_cam.rotation_degrees = Vector3(_cam.rotation_x, _cam.rotation_y, 0.0)
	if Input.is_physical_key_pressed(KEY_C):
		_cam.rotation_y -= adj
		_cam.rotation_degrees = Vector3(_cam.rotation_x, _cam.rotation_y, 0.0)
	if Input.is_physical_key_pressed(KEY_V):
		_cam.rotation_y += adj
		_cam.rotation_degrees = Vector3(_cam.rotation_x, _cam.rotation_y, 0.0)

	# Area info from GameManager.
	var area_text := "unknown"
	var gm = get_tree().get_first_node_in_group("game_manager")
	if gm:
		var idx = gm.current_area_index
		var area_name := "area_%d" % idx
		if idx < gm.areas.size() and gm.areas[idx]:
			area_name = gm.areas[idx].name
		area_text = "%s (index %d)" % [area_name, idx]

	var player = get_tree().get_first_node_in_group("player")
	var player_pos = player.global_position.snapped(Vector3(0.01, 0.01, 0.01)) if player else Vector3.ZERO

	_label.text = """CAMERA DEBUG  [F1 to disable + reset]
area:       %s
─────────────────────────────
offset      x:%+.3f  y:%+.3f  z:%+.3f
            [T/G]    [R/F]    [Q/E]
rotation    x:%+.3f  y:%+.3f
            [Z/X]    [C/V]
follow_spd  %.1f     [UP/DN]
step        %.3f     [KP+/-]
─────────────────────────────
cam pos     x:%.2f  y:%.2f  z:%.2f
player pos  x:%.2f  y:%.2f  z:%.2f""" % [
		area_text,
		_cam.offset_x, _cam.offset_y, _cam.offset_z,
		_cam.rotation_x, _cam.rotation_y,
		_cam.follow_speed,
		step,
		_cam.global_position.x, _cam.global_position.y, _cam.global_position.z,
		player_pos.x, player_pos.y, player_pos.z
	]


func _reset_camera() -> void:
	if not _cam or not is_instance_valid(_cam):
		_cam = get_tree().get_first_node_in_group("camera")
	if not _cam:
		return
	_cam.offset_x = default_offset_x
	_cam.offset_y = default_offset_y
	_cam.offset_z = default_offset_z
	_cam.rotation_x = default_rotation_x
	_cam.rotation_y = default_rotation_y
	_cam.follow_speed = default_follow_speed
	_cam.rotation_degrees = Vector3(default_rotation_x, default_rotation_y, 0.0)
