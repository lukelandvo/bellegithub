# game_manager.gd
# Handles area swapping within a scene.
# Assign areas in the inspector array.
# Add a camera_area.gd node per area with matching area_index.
#
# Camera is injected by SceneLoader at load time and on area transitions.
# Camera areas are cached on first use for O(1) lookup.
#
# current_area_index is public so SceneLoader can read the active area
# before a battle starts and restore it correctly on return.

extends Node

@export var areas: Array[Node3D] = []

# FIX: track which area is active so SceneLoader.load_battle() can save
# and restore it accurately, rather than blindly grabbing the first
# camera_area node from the scene tree (which was always area 0).
var current_area_index: int = 0

var _camera_area_cache: Dictionary = {}  # area_index -> camera_area node

func _ready() -> void:
	add_to_group("game_manager")
	await get_tree().process_frame
	await get_tree().process_frame
	_build_camera_area_cache()
	change_area(0)

func _build_camera_area_cache() -> void:
	_camera_area_cache.clear()
	for cam_area in get_tree().get_nodes_in_group("camera_area"):
		if cam_area.get("area_index") != null:
			_camera_area_cache[cam_area.area_index] = cam_area

func change_area(index: int, spawn_pos: Vector3 = Vector3.ZERO,
		rotation_y: float = 0.0, camera: Camera3D = null) -> void:
	if areas.is_empty():
		push_error("GameManager: no areas assigned")
		return
	if index < 0 or index >= areas.size():
		push_error("GameManager: area index %d out of range" % index)
		return

	current_area_index = index

	for i in areas.size():
		var area: Node3D = areas[i]
		if i == index:
			area.visible = true
			area.process_mode = Node.PROCESS_MODE_ALWAYS
		else:
			area.visible = false
			area.process_mode = Node.PROCESS_MODE_DISABLED

	# O(1) camera area lookup via cache
	if _camera_area_cache.has(index):
		var cam_area = _camera_area_cache[index]
		if camera:
			cam_area.camera = camera
		cam_area.apply()

	if spawn_pos != Vector3.ZERO:
		var players = get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			var p = players[0]
			p.global_position = spawn_pos
			if p.has_method("set_facing_angle"):
				p.set_facing_angle(deg_to_rad(rotation_y))
			else:
				p.rotation.y = deg_to_rad(rotation_y)
				if p.get("armature") and p.armature:
					p.armature.rotation.y = deg_to_rad(rotation_y)
