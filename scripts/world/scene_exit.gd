# scene_exit.gd
# Attach to an Area3D to trigger a full scene transition.
# SceneLoader injects itself at load time via inject_scene_loader().
#
# Flag gate: if required_flag is set, the exit is blocked until
# FlagService reports that flag as true.
#
# Setup:
#   - Area3D (this script) — add to "scene_exit" group
#     - CollisionShape3D (box or cylinder covering the exit zone)

extends Area3D

@export_group("Destination")
@export_file("*.tscn") var target_scene_path: String = ""
@export var spawn_point: String = "SpawnPoint"
@export var scene_id: String = ""

@export_group("Audio")
@export var sfx_id: String = ""
@export var music_id: String = ""

@export_group("Flag Gate")
@export var required_flag: String = ""
@export var blocked_dialogue: String = ""

var _scene_loader: Node = null
var _is_transitioning: bool = false

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func inject_scene_loader(loader: Node) -> void:
	_scene_loader = loader

func _on_body_entered(body: Node3D) -> void:
	print("scene_exit entered | transitioning: ", _is_transitioning, " | loader: ", _scene_loader, " | flag: '", required_flag, "' | body: ", body.name)
	if _is_transitioning:
		return
	if not body.is_in_group("player"):
		return
	if target_scene_path == "":
		push_error("scene_exit: no target_scene_path assigned on %s" % name)
		return
	if not _scene_loader:
		push_error("scene_exit: no SceneLoader injected — check SceneLoader._inject_scene_exits()")
		return
	if required_flag != "" and not FlagService.get_bool(required_flag):
		return
	_is_transitioning = true
	set_deferred("monitoring", false)
	var scene: PackedScene = load(target_scene_path)
	if not scene:
		push_error("scene_exit: failed to load scene at '%s'" % target_scene_path)
		_is_transitioning = false
		set_deferred("monitoring", true)
		return
	await _scene_loader.load_scene(scene, scene_id, spawn_point, music_id, sfx_id)
