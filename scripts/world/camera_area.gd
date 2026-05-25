# camera_area.gd
# World scene node — per-area camera bounds and offset overrides.
# Camera is injected by SceneLoader at load time via the camera property.
# No inspector wiring needed — SceneLoader handles it automatically.
#
# Intro system:
#   Enable "use_intro" and set intro_position, intro_rotation, intro_duration
#   in the inspector for this area. When the area activates, the camera will
#   hold that position/angle, then blend back behind the player once they move
#   or the duration expires.

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

@export_group("Area Intro")
@export var use_intro: bool = false
@export var intro_position: Vector3 = Vector3.ZERO
@export var intro_rotation: Vector3 = Vector3.ZERO
@export var intro_duration: float = 2.0

func _ready() -> void:
	add_to_group("camera_area")
	# Camera is injected by SceneLoader after scene load — no warning needed here

func apply() -> void:
	if not camera or not is_instance_valid(camera):
		push_error("camera_area: camera reference is invalid on node '%s'" % name)
		return
	camera.use_bounds = use_bounds
	camera.set_bounds(min_x, max_x, min_z, max_z)
	if override_offset:
		camera.apply_offset(offset_x, offset_y, offset_z, rotation_x, rotation_y)
	if use_intro and camera.has_method("play_intro"):
		camera.play_intro(intro_position, intro_rotation, intro_duration)
