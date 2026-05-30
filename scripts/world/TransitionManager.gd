# TransitionManager.gd
# Node in main.tscn — handles all screen fades and visual transitions.
# Does not know about scenes, loading, or cinematics.
# SceneLoader and CinematicManager call into this for fades.
#
# Wire this node's reference into SceneLoader and CinematicManager via @export.

extends Node

# ---------------------------------------------------------------------------
# Inspector
# ---------------------------------------------------------------------------

@export_group("Timing")
@export var default_fade_duration: float = 0.5

@export_group("Colors")
@export var fade_color: Color = Color(0, 0, 0, 1)

# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

var _overlay: ColorRect
var _canvas: CanvasLayer

# ---------------------------------------------------------------------------
# Ready
# ---------------------------------------------------------------------------

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_canvas = CanvasLayer.new()
	_canvas.layer = 99
	add_child(_canvas)

	_overlay = ColorRect.new()
	_overlay.color = fade_color
	_overlay.anchor_right = 1.0
	_overlay.anchor_bottom = 1.0
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(_overlay)

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func fade_out(duration: float = -1.0) -> void:
	# Fade to black
	await _fade(0.0, 1.0, _resolve_duration(duration))

func fade_in(duration: float = -1.0) -> void:
	# Fade from black
	await _fade(1.0, 0.0, _resolve_duration(duration))

func fade_to(alpha: float, duration: float = -1.0) -> void:
	# Fade to a specific alpha value
	await _fade(_overlay.color.a, alpha, _resolve_duration(duration))

func flash(duration: float = 0.1) -> void:
	# Instant white flash, fades out
	_overlay.color = Color(1, 1, 1, 1)
	await _fade(1.0, 0.0, duration)
	_overlay.color.r = fade_color.r
	_overlay.color.g = fade_color.g
	_overlay.color.b = fade_color.b

func set_black() -> void:
	# Instantly set to fully black — use before a scene load
	_overlay.color = Color(fade_color.r, fade_color.g, fade_color.b, 1.0)

func set_clear() -> void:
	# Instantly set to fully transparent
	_overlay.color = Color(fade_color.r, fade_color.g, fade_color.b, 0.0)

func is_faded_out() -> bool:
	return _overlay.color.a >= 1.0

# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

func _fade(from_alpha: float, to_alpha: float, duration: float) -> void:
	_overlay.color.a = from_alpha
	var tween: Tween = get_tree().create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(_overlay, "color:a", to_alpha, duration)
	await tween.finished

func _resolve_duration(duration: float) -> float:
	return duration if duration >= 0.0 else default_fade_duration
