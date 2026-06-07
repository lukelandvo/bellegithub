# camera_area.gd
# World scene node — per-area camera bounds and offset overrides.
#
# Fixed Camera mode:
#   Enable fixed_camera and set fixed_position / fixed_rotation_degrees.
#   The camera sits at that exact position — no follow, no bounds.
#   fixed_x_influence (0.0–1.0) adds a small horizontal drift along the
#   camera's right axis so the player doesn't walk off the edge of frame.
#   fixed_follow_speed controls how fast that drift tracks.
#
# Movement Override mode:
#   Enable override_movement_angle and set movement_angle_degrees.
#   forward/back moves along that world angle, left/right strafes.
#   Character faces the direction it moves. Use alongside fixed_camera.
#   0° = north, 90° = east, 180° = south, 270° = west.

extends Node

@export_group("References")
@export var camera: Camera3D

@export_group("Area")
@export var area_index: int = 0

@export_group("Camera Bounds")
@export var use_bounds: bool = true
@export var min_x: float = -2.0
@export var max_x: float = 10.0
@export var min_z: float = -10.0
@export var max_z: float = 10.0

@export_group("Camera Offset Override")
@export var override_offset: bool = false
@export var offset_x: float = 0.0
@export var offset_y: float = 1.647
@export var offset_z: float = 9.0
@export var rotation_x: float = -15.4
@export var rotation_y: float = 0.0

@export_group("Fixed Camera")
@export var fixed_camera: bool = false
@export var fixed_position: Vector3 = Vector3.ZERO
@export var fixed_rotation_degrees: Vector3 = Vector3(-15.0, 0.0, 0.0)
@export_range(0.0, 1.0, 0.01) var fixed_x_influence: float = 0.0
@export var fixed_follow_speed: float = 3.0

@export_group("Movement Override")
@export var override_movement_angle: bool = false
@export var movement_angle_degrees: float = 0.0

@export_group("Area Intro")
@export var use_intro: bool = false
@export var intro_position: Vector3 = Vector3.ZERO
@export var intro_rotation: Vector3 = Vector3.ZERO
@export var intro_duration: float = 2.0

func _ready() -> void:
	add_to_group("camera_area")

func apply() -> void:
	if not camera or not is_instance_valid(camera):
		push_error("camera_area: camera reference is invalid on node '%s'" % name)
		return

	# Camera setup.
	if fixed_camera:
		camera.set_fixed(fixed_position, fixed_rotation_degrees,
				fixed_x_influence, fixed_follow_speed)
	else:
		if camera.has_method("release_fixed"):
			camera.release_fixed()
		camera.use_bounds = use_bounds
		camera.set_bounds(min_x, max_x, min_z, max_z)
		if override_offset:
			camera.apply_offset(offset_x, offset_y, offset_z, rotation_x, rotation_y)
		if use_intro and camera.has_method("play_intro"):
			camera.play_intro(intro_position, intro_rotation, intro_duration)

	# Movement override.
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_method("set_movement_angle_override"):
		if override_movement_angle:
			player.set_movement_angle_override(deg_to_rad(movement_angle_degrees))
		else:
			player.clear_movement_angle_override()
