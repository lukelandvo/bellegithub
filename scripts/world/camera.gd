# camera.gd
# Camera3D in main.tscn — always stays behind the player.
# Reads player facing angle via target.get_facing_angle().
# Wire target (player CharacterBody3D) in the inspector.
#
# Intro system:
#   When a camera_area calls play_intro(), the camera holds a fixed position
#   and angle for intro_duration seconds. As soon as the player moves, the
#   intro cuts short and the camera blends back behind them.
#   Set intro_duration = 0 to skip the hold and just snap behind the player.

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

# Tracks the camera angle at the moment the intro blend-back starts,
# so we can lerp_angle() from there rather than from intro_rotation.y
var _blend_start_angle_rad: float = 0.0

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
	if not target or _hold_position:
		return

	# Always track the desired behind-the-player angle
	if target.has_method("get_facing_angle"):
		var target_angle: float = target.get_facing_angle() + PI
		_camera_angle_rad = lerp_angle(_camera_angle_rad, target_angle, rotation_follow_speed * delta)

	if _is_in_intro:
		_intro_timer += delta

		# Early exit: if the player moves, immediately start blending back
		var player_is_moving: bool = false
		if target.has_method("get_facing_angle"):
			# Check if the player's velocity is significant
			if target.get("velocity") and target.velocity.length() > 0.5:
				player_is_moving = true

		if player_is_moving or _intro_timer >= intro_duration:
			# Start blend-back from where the camera currently is
			_is_in_intro = false
			# Snap the angle tracker to the intro angle so the lerp
			# starts from the right place rather than jumping
			_camera_angle_rad = _blend_start_angle_rad
		else:
			# Hold the intro position and angle
			var t: float = clamp(_intro_timer / max(intro_duration, 0.001), 0.0, 1.0)
			t = ease(t, intro_ease)
			global_position = _intro_start_pos.lerp(_desired_position(), t)

			# FIX: use lerp_angle per axis instead of Vector3.lerp for rotation.
			# Vector3.lerp on degree values spins backward across the 0/360 boundary
			# (e.g. intro at 350 deg, target at 10 deg = spins 340 deg the wrong way).
			var target_rot_y: float = rad_to_deg(_camera_angle_rad)
			rotation_degrees = Vector3(
				lerpf(_intro_start_rot.x, rotation_x, t),
				rad_to_deg(lerp_angle(deg_to_rad(_intro_start_rot.y), deg_to_rad(target_rot_y), t)),
				0.0
			)
	else:
		global_position = global_position.lerp(_desired_position(), 1.0 - exp(-follow_speed * delta))
		rotation_degrees = Vector3(rotation_x, rad_to_deg(_camera_angle_rad), 0.0)

# ---------------------------------------------------------------------------
# Called by camera_area.gd when entering a new area that has an intro set up
# ---------------------------------------------------------------------------

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

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

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

func _snap_to_target() -> void:
	if target and target.has_method("get_facing_angle"):
		_camera_angle_rad = target.get_facing_angle() + PI
	global_position = _desired_position()