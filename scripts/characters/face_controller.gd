# face_controller.gd
# Attach to a Node3D under a character's root.
# Drives swappable expression textures via UV offset on the cel shader atlas.
# AnimationPlayer (assigned in inspector) handles multi-frame blink sequences.
#
# Atlas setup: 256x256 PNG, 4x4 grid, 64x64 per cell.
# Blink animation: add a Method Track pointing at this node, call
# set_eyes_cell(Vector2) for each frame, call restore_eyes() on the last key.

class_name FaceController
extends Node3D

@export_group("References")
@export var eye_quad: MeshInstance3D
@export var mouth_quad: MeshInstance3D
@export var anim_player: AnimationPlayer

@export_group("Atlas")
@export var atlas_grid: int = 4

@export_group("Expressions")
@export var eye_expressions: Dictionary = {}
@export var mouth_expressions: Dictionary = {}

@export_group("Defaults")
@export var neutral_eyes: String = "neutral"
@export var neutral_mouth: String = "neutral"
@export var blink_expression: String = "closed"
@export var talking_open_mouth: String = "open"
@export var talking_closed_mouth: String = "neutral"

@export_group("Animations")
@export var blink_anim_name: String = "blink"

@export_group("Idle Blink")
@export var auto_blink: bool = true
@export var blink_interval_min: float = 2.5
@export var blink_interval_max: float = 6.0
@export var blink_duration: float = 0.12

@export_group("Talking")
@export var talk_frame_duration: float = 0.1

var _current_eyes: String = ""
var _is_talking: bool = false
var _blink_playing: bool = false
var _blink_timer: float = 0.0
var _talk_timer: float = 0.0
var _talk_open: bool = false
var _eye_material: ShaderMaterial
var _mouth_material: ShaderMaterial

func _ready() -> void:
	_eye_material = _resolve_shader_material(eye_quad)
	_mouth_material = _resolve_shader_material(mouth_quad)
	if anim_player:
		anim_player.animation_finished.connect(_on_animation_finished)
	set_eyes(neutral_eyes)
	set_mouth(neutral_mouth)
	_schedule_next_blink()

func _process(delta: float) -> void:
	if auto_blink and not _is_talking and not _blink_playing:
		_blink_timer -= delta
		if _blink_timer <= 0.0:
			play_blink()
			_schedule_next_blink()
	if _is_talking:
		_talk_timer -= delta
		if _talk_timer <= 0.0:
			_talk_open = not _talk_open
			set_mouth(talking_open_mouth if _talk_open else talking_closed_mouth)
			_talk_timer = talk_frame_duration

# ----- Public API -----

func set_eyes(expr_name: String) -> void:
	if not eye_expressions.has(expr_name):
		push_warning("FaceController: unknown eye expression '%s'" % expr_name)
		return
	_current_eyes = expr_name
	_apply_cell(_eye_material, eye_expressions[expr_name])

func set_mouth(expr_name: String) -> void:
	if not mouth_expressions.has(expr_name):
		push_warning("FaceController: unknown mouth expression '%s'" % expr_name)
		return
	_apply_cell(_mouth_material, mouth_expressions[expr_name])

func set_expression(eyes: String, mouth: String) -> void:
	set_eyes(eyes)
	set_mouth(mouth)

# For AnimationPlayer method tracks — sets a cell directly by coordinate
# without going through the named expression dictionary.
# Use these in blink/reaction animation keyframes.
func set_eyes_cell(cell: Vector2) -> void:
	_apply_cell(_eye_material, cell)

func set_mouth_cell(cell: Vector2) -> void:
	_apply_cell(_mouth_material, cell)

# Call this on the LAST keyframe of any eye animation.
# Restores whatever named expression was active before the animation started,
# so a blink during "hurt" eyes returns to "hurt" rather than "neutral".
func restore_eyes() -> void:
	set_eyes(_current_eyes)

func play_blink() -> void:
	if _blink_playing:
		return
	_blink_playing = true
	if anim_player and anim_player.has_animation(blink_anim_name):
		anim_player.play(blink_anim_name)
		return
	# Fallback: single-frame snap if no animation is set up yet.
	if not eye_expressions.has(blink_expression):
		_blink_playing = false
		return
	var previous := _current_eyes
	_apply_cell(_eye_material, eye_expressions[blink_expression])
	await get_tree().create_timer(blink_duration).timeout
	_blink_playing = false
	set_eyes(previous)

func start_talking() -> void:
	_is_talking = true
	_talk_open = false
	_talk_timer = 0.0

func stop_talking() -> void:
	_is_talking = false
	set_mouth(neutral_mouth)

# ----- Internal -----

func _on_animation_finished(anim_name: String) -> void:
	if anim_name == blink_anim_name:
		_blink_playing = false

func _apply_cell(mat: ShaderMaterial, cell: Vector2) -> void:
	if not mat:
		return
	var step := 1.0 / float(atlas_grid)
	mat.set_shader_parameter("uv_scale", Vector2(step, step))
	mat.set_shader_parameter("uv_offset", Vector2(cell.x * step, cell.y * step))

func _resolve_shader_material(quad: MeshInstance3D) -> ShaderMaterial:
	if not quad:
		return null
	var mat = quad.get_surface_override_material(0)
	if mat == null and quad.mesh:
		mat = quad.mesh.surface_get_material(0)
		if mat is ShaderMaterial:
			mat = mat.duplicate()
			quad.set_surface_override_material(0, mat)
	if mat is ShaderMaterial:
		return mat
	push_warning("FaceController: quad '%s' has no ShaderMaterial" % quad.name)
	return null

func _schedule_next_blink() -> void:
	_blink_timer = randf_range(blink_interval_min, blink_interval_max)
