# transition.gd
# Attach to an Area3D at any transition point within a scene.
# Triggers an area swap via SceneLoader.area_transition() -> GameManager.change_area().
#
# SceneLoader is injected at load time via inject_scene_loader().
# GameManager is wired directly in the inspector — same scene, no injection needed.
#
# Setup:
#   - Area3D (this script) — add to "scene_exit" group so SceneLoader injects itself
#     - CollisionShape3D
#   Wire game_manager in the inspector to the GameManager node in this scene.

extends Area3D

@export_group("Destination")
@export var target_area: int = 0
@export var spawn_position: Vector3 = Vector3.ZERO
@export var arrival_rotation_y: float = 0.0

@export_group("Audio")
@export var sfx_id: String = ""

@export_group("Flag Gate")
@export var required_flag: String = ""

@export_group("Node References")
@export var game_manager: Node

var _scene_loader: Node = null
var _is_transitioning: bool = false

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func inject_scene_loader(loader: Node) -> void:
	_scene_loader = loader

func _on_body_entered(body: Node3D) -> void:
	if _is_transitioning:
		return
	if not body.is_in_group("player"):
		return
	if not _scene_loader:
		push_error("transition: no SceneLoader injected — check SceneLoader._inject_scene_exits()")
		return
	if not game_manager:
		push_error("transition: no GameManager assigned — wire in inspector")
		return
	if required_flag != "" and not FlagService.get_bool(required_flag):
		return

	_is_transitioning = true
	set_deferred("monitoring", false)

	await _scene_loader.area_transition(target_area, spawn_position, arrival_rotation_y, game_manager, sfx_id)

	_is_transitioning = false
	set_deferred("monitoring", true)
