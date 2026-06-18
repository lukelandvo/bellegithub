# camera.gd
# Camera3D in main.tscn — always stays behind the player.
#
# Two hold modes exist intentionally:
#   _hold_position — temporary, used during battle return. Released via release_hold().
#   _is_fixed      — persistent, set by camera_area when fixed_camera = true.
#                    Released when entering a non-fixed camera_area.
#
# Fixed camera horizontal drift:
#   When _fixed_x_influence > 0, the camera slides along its own right axis
#   as the player moves left/right within the room. 0.0 = fully locked,
#   1.0 = fully follows. Works correctly at any camera angle.

extends Camera3D

@export_group("Target")
@export var target: Node3D

@export_group("Follow")
@export var follow_speed: float = 4.0
@export var rotation_follow_speed: float = 8.0

@export_group("Camera Offset")
@export var offset_x: float = 0.0
@export var offset_y: float = 1.647
@export var offset_z: float = 9.0
@export var rotation_x: float = -15.4

@export_group("Intro")
@export var use_intro: bool = false
@export var intro_position: Vector3 = Vector3.ZERO
@export var intro_rotation: Vector3 = Vector3.ZERO
@export var intro_duration: float = 2.0
@export var intro_ease: float = -2.0

@export_group("Bounds")
@export var use_bounds: bool = true
@export var min_x: float = -100.0
@export var max_x: float = 100.0
@export var min_z: float = -100.0
@export var max_z: float = 100.0

var _camera_angle_rad: float = 0.0
var _is_in_intro: bool = false
var _intro_timer: float = 0.0
var _intro_start_pos: Vector3 = Vector3.ZERO
var _intro_start_rot: Vector3 = Vector3.ZERO
var _hold_position: bool = false
var _blend_start_angle_rad: float = 0.0

# Fixed camera state.
var _is_fixed: bool = false
var _fixed_base_position: Vector3 = Vector3.ZERO
var _fixed_x_influence: float = 0.0
var _fixed_follow_speed: float = 3.0

func _ready() -> void:
	add_to_group("camera")
	rotation_degrees = Vector3(rotation_x, 0.0, 0.0)
	if not target:
		push_warning("camera: no target assigned")
		return
	if use_intro:
		global_position = intro_position
		rotation_degrees = intro_rotation
		_intro_start_pos = intro_position
		_intro_start_rot = intro_rotation
		_blend_start_angle_rad = deg_to_rad(intro_rotation.y)
		_is_in_intro = true
		_intro_timer = 0.0
	else:
		_snap_to_target()

func _process(delta: float) -> void:
	if _hold_position:
		return

	if _is_fixed:
		_process_fixed(delta)
		return

	if not target:
		return

	if target.has_method("get_facing_angle"):
		var target_angle: float = target.get_facing_angle() + PI
		_camera_angle_rad = lerp_angle(_camera_angle_rad, target_angle, rotation_follow_speed * delta)

	if _is_in_intro:
		_intro_timer += delta
		var player_is_moving: bool = false
		if target.has_method("get_facing_angle"):
			if target.get("velocity") and target.velocity.length() > 0.5:
				player_is_moving = true
		if player_is_moving or _intro_timer >= intro_duration:
			_is_in_intro = false
			_camera_angle_rad = _blend_start_angle_rad
		else:
			var t: float = clamp(_intro_timer / max(intro_duration, 0.001), 0.0, 1.0)
			t = ease(t, intro_ease)
			global_position = _intro_start_pos.lerp(_desired_position(), t)
			var target_rot_y: float = rad_to_deg(_camera_angle_rad)
			rotation_degrees = Vector3(
				lerpf(_intro_start_rot.x, rotation_x, t),
				rad_to_deg(lerp_angle(deg_to_rad(_intro_start_rot.y), deg_to_rad(target_rot_y), t)),
				0.0
			)
	else:
		global_position = global_position.lerp(_desired_position(), 1.0 - exp(-follow_speed * delta))
		rotation_degrees = Vector3(rotation_x, rad_to_deg(_camera_angle_rad), 0.0)

func _process_fixed(delta: float) -> void:
	# Horizontal drift along the camera's own right axis.
	# Influence of 0 = fully locked. Influence of 1 = full horizontal follow.
	if _fixed_x_influence <= 0.0 or not target:
		return
	var cam_right: Vector3 = global_transform.basis.x
	var player_offset: Vector3 = target.global_position - _fixed_base_position
	var drift: Vector3 = cam_right * (cam_right.dot(player_offset) * _fixed_x_influence)
	var desired_pos: Vector3 = _fixed_base_position + drift
	global_position = global_position.lerp(desired_pos, 1.0 - exp(-_fixed_follow_speed * delta))

func play_intro(from_position: Vector3, from_rotation: Vector3, duration: float) -> void:
	if duration <= 0.0:
		_snap_to_target()
		return
	global_position = from_position
	rotation_degrees = from_rotation
	_intro_start_pos = from_position
	_intro_start_rot = from_rotation
	_blend_start_angle_rad = deg_to_rad(from_rotation.y)
	_is_in_intro = true
	_intro_timer = 0.0

func set_bounds(p_min_x: float, p_max_x: float, p_min_z: float, p_max_z: float) -> void:
	min_x = p_min_x
	max_x = p_max_x
	min_z = p_min_z
	max_z = p_max_z

func apply_offset(p_offset_x: float, p_offset_y: float, p_offset_z: float,
		p_rotation_x: float, _p_rotation_y: float) -> void:
	offset_x = p_offset_x
	offset_y = p_offset_y
	offset_z = p_offset_z
	rotation_x = p_rotation_x

# ---------------------------------------------------------------------------
# Fixed camera — used by camera_area when fixed_camera = true.
# ---------------------------------------------------------------------------

func set_fixed(fixed_position: Vector3, rot_degrees: Vector3,
		x_influence: float = 0.0, fixed_speed: float = 3.0) -> void:
	_is_fixed = true
	_is_in_intro = false
	_fixed_base_position = fixed_position
	_fixed_x_influence = x_influence
	_fixed_follow_speed = fixed_speed
	global_position = fixed_position
	rotation_degrees = rot_degrees

func release_fixed() -> void:
	_is_fixed = false
	_camera_angle_rad = deg_to_rad(rotation_degrees.y)

# ---------------------------------------------------------------------------
# Battle hold — temporary, released by SceneLoader after battle return.
# ---------------------------------------------------------------------------

func snap_to_position(saved_position: Vector3) -> void:
	global_position = saved_position
	_hold_position = true

func release_hold() -> void:
	_hold_position = false

# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

func _desired_position() -> Vector3:
	var cos_a: float = cos(_camera_angle_rad)
	var sin_a: float = sin(_camera_angle_rad)
	var offset = Vector3(
		offset_x * cos_a + offset_z * sin_a,
		offset_y,
		-offset_x * sin_a + offset_z * cos_a
	)
	var desired = target.global_position + offset
	if use_bounds:
		desired.x = clamp(desired.x, min_x, max_x)
		desired.z = clamp(desired.z, min_z, max_z)
	return desired

func snap_to_target() -> void:
	_snap_to_target()

func _snap_to_target() -> void:
	if target and target.has_method("get_facing_angle"):
		_camera_angle_rad = target.get_facing_angle() + PI
	global_position = _desired_position()