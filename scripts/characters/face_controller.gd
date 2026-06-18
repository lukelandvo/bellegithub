# face_controller.gd
# Attach to a Node3D under a character's root.
# Drives swappable expression textures via UV offset on the cel shader atlas.
#
# Uses two SEPARATE AnimationPlayers — eye_anim_player and mouth_anim_player —
# so a blink can never interrupt a talk animation or vice versa. They're
# physically incapable of touching each other's playback state since they're
# different nodes.
#
# Atlas setup: 256x256 PNG, 4x4 grid, 64x64 per cell.
#
# Blink animation setup: on eye_anim_player, add a PROPERTY TRACK on this
# node targeting "current_eye_cell" and keyframe it through your blink-stage
# Vector2 cells (e.g. open -> half_closed -> closed -> half_open -> open).
# Property tracks scrub live in the editor, unlike method tracks, so you can
# drag the timeline and watch the eyes change frame by frame.
# Call restore_eyes() on the last key only if you want to snap back to a
# named expression different from where the property track ends.
#
# Talk animation setup: on mouth_anim_player, build a looping animation and
# set talk_animation_name to match it. Leave blank to use the simple
# two-cell open/closed flap instead.

@tool
class_name FaceController
extends Node3D

@export_group("References")
@export var eye_quad: MeshInstance3D
@export var mouth_quad: MeshInstance3D
## Separate AnimationPlayers for eyes and mouth so a blink firing mid-talk
## can never interrupt the talk animation (or vice versa) — they're
## physically incapable of touching each other's playback state.
@export var eye_anim_player: AnimationPlayer
@export var mouth_anim_player: AnimationPlayer

@export_group("Atlas")
@export var atlas_grid: int = 4

@export_group("Expressions")
@export var eye_expressions: Dictionary = {}
@export var mouth_expressions: Dictionary = {}

@export_group("Defaults")
@export var neutral_eyes: String = "neutral":
	set(value):
		neutral_eyes = value
		if Engine.is_editor_hint():
			set_eyes(neutral_eyes)
@export var neutral_mouth: String = "neutral":
	set(value):
		neutral_mouth = value
		if Engine.is_editor_hint():
			set_mouth(neutral_mouth)
@export var blink_expression: String = "closed"
@export var talking_open_mouth: String = "open"
@export var talking_closed_mouth: String = "neutral"

@export_group("Editor Preview")
## Type an eye expression name here and toggle to preview it live in the editor.
@export var preview_eyes_name: String = "":
	set(value):
		preview_eyes_name = value
		if Engine.is_editor_hint() and preview_eyes_name != "":
			set_eyes(preview_eyes_name)
## Type a mouth expression name here and toggle to preview it live in the editor.
@export var preview_mouth_name: String = "":
	set(value):
		preview_mouth_name = value
		if Engine.is_editor_hint() and preview_mouth_name != "":
			set_mouth(preview_mouth_name)

@export_group("Animations")
@export var blink_anim_name: String = "blink"

@export_group("Idle Blink")
@export var auto_blink: bool = true
@export var blink_interval_min: float = 2.5
@export var blink_interval_max: float = 6.0
@export var blink_duration: float = 0.12

@export_group("Talking")
## If set, start_talking() plays this AnimationPlayer animation on loop
## instead of flapping between talking_open_mouth / talking_closed_mouth.
## Leave blank to use the simple two-cell flap.
@export var talk_animation_name: String = ""
@export var talk_frame_duration: float = 0.1

var _current_eyes: String = ""
var _is_talking: bool = false
var _using_talk_animation: bool = false
var _blink_playing: bool = false
var _blink_timer: float = 0.0
var _talk_timer: float = 0.0
var _talk_open: bool = false
var _eye_material: ShaderMaterial
var _mouth_material: ShaderMaterial

# Animatable properties — target these with AnimationPlayer PROPERTY tracks
# (not method tracks) so the AnimationPlayer timeline scrubs live in the
# editor. Setting either of these directly applies the UV cell immediately.
var current_eye_cell: Vector2 = Vector2.ZERO:
	set(value):
		current_eye_cell = value
		if not _eye_material:
			_eye_material = _resolve_shader_material(eye_quad)
		_apply_cell(_eye_material, value)

var current_mouth_cell: Vector2 = Vector2.ZERO:
	set(value):
		current_mouth_cell = value
		if not _mouth_material:
			_mouth_material = _resolve_shader_material(mouth_quad)
		_apply_cell(_mouth_material, value)

func _ready() -> void:
	_eye_material = _resolve_shader_material(eye_quad)
	_mouth_material = _resolve_shader_material(mouth_quad)
	if eye_anim_player:
		if not eye_anim_player.animation_finished.is_connected(_on_eye_animation_finished):
			eye_anim_player.animation_finished.connect(_on_eye_animation_finished)
	if mouth_anim_player:
		if not mouth_anim_player.animation_finished.is_connected(_on_mouth_animation_finished):
			mouth_anim_player.animation_finished.connect(_on_mouth_animation_finished)
	set_eyes(neutral_eyes)
	set_mouth(neutral_mouth)
	if not Engine.is_editor_hint():
		_schedule_next_blink()

func _process(delta: float) -> void:
	# Auto-blink and talking only run during actual gameplay, not in the editor.
	# This keeps the editor viewport quiet (no surprise blinking while you're
	# UV-painting or posing the model) and avoids get_tree() calls that are
	# invalid outside a running scene tree.
	if Engine.is_editor_hint():
		return
	if auto_blink and not _blink_playing:
		_blink_timer -= delta
		if _blink_timer <= 0.0:
			play_blink()
			_schedule_next_blink()
	if _is_talking and not _using_talk_animation:
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
	if not _eye_material:
		_eye_material = _resolve_shader_material(eye_quad)
	_current_eyes = expr_name
	current_eye_cell = eye_expressions[expr_name]

func set_mouth(expr_name: String) -> void:
	if not mouth_expressions.has(expr_name):
		push_warning("FaceController: unknown mouth expression '%s'" % expr_name)
		return
	if not _mouth_material:
		_mouth_material = _resolve_shader_material(mouth_quad)
	current_mouth_cell = mouth_expressions[expr_name]

func set_expression(eyes: String, mouth: String) -> void:
	set_eyes(eyes)
	set_mouth(mouth)

# For AnimationPlayer method tracks — sets a cell directly by coordinate
# without going through the named expression dictionary.
# Use these in blink/reaction animation keyframes.
# Kept for backward compatibility with any existing method-track calls.
# Prefer animating current_eye_cell / current_mouth_cell directly via a
# PROPERTY track instead — see header comment.
func set_eyes_cell(cell: Vector2) -> void:
	current_eye_cell = cell

func set_mouth_cell(cell: Vector2) -> void:
	current_mouth_cell = cell

# Call this on the LAST keyframe of any eye animation.
# Restores whatever named expression was active before the animation started,
# so a blink during "hurt" eyes returns to "hurt" rather than "neutral".
func restore_eyes() -> void:
	set_eyes(_current_eyes)

func play_blink() -> void:
	if Engine.is_editor_hint():
		# No scene tree timer available in the editor — just snap the cell
		# so you can still see the blink pose without crashing on get_tree().
		if eye_expressions.has(blink_expression):
			current_eye_cell = eye_expressions[blink_expression]
		return
	if _blink_playing:
		return
	_blink_playing = true
	if eye_anim_player and eye_anim_player.has_animation(blink_anim_name):
		eye_anim_player.play(blink_anim_name)
		return
	# Fallback: single-frame snap if no animation is set up yet.
	if not eye_expressions.has(blink_expression):
		_blink_playing = false
		return
	var previous := _current_eyes
	current_eye_cell = eye_expressions[blink_expression]
	await get_tree().create_timer(blink_duration).timeout
	_blink_playing = false
	set_eyes(previous)

func start_talking() -> void:
	_is_talking = true
	if mouth_anim_player and talk_animation_name != "" and mouth_anim_player.has_animation(talk_animation_name):
		_using_talk_animation = true
		mouth_anim_player.play(talk_animation_name)
		return
	# Fallback: no talk animation configured for this character — use the
	# simple two-cell open/closed flap instead.
	_using_talk_animation = false
	_talk_open = false
	_talk_timer = 0.0

func stop_talking() -> void:
	_is_talking = false
	if _using_talk_animation and mouth_anim_player:
		mouth_anim_player.stop()
		_using_talk_animation = false
	set_mouth(neutral_mouth)

# ----- Internal -----

func _on_eye_animation_finished(anim_name: String) -> void:
	if anim_name == blink_anim_name:
		_blink_playing = false

func _on_mouth_animation_finished(_anim_name: String) -> void:
	pass

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
