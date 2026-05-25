# FollowerManager.gd
# Autoload singleton — tracks active party followers and respawns them
# into the current scene after every scene transition and battle return.
#
# Register in Project > Project Settings > Autoload as "FollowerManager".

extends Node

var _follower_scenes: Array[PackedScene] = []
var _active_instances: Array[Node] = []

func add_follower(scene: PackedScene) -> void:
	if not _follower_scenes.has(scene):
		_follower_scenes.append(scene)

func remove_follower(scene: PackedScene) -> void:
	_follower_scenes.erase(scene)

func has_followers() -> bool:
	return not _follower_scenes.is_empty()

func clear_followers() -> void:
	_follower_scenes.clear()
	for instance in _active_instances:
		if is_instance_valid(instance):
			instance.queue_free()
	_active_instances.clear()

# Returns resource paths of active follower scenes — for saving
func get_follower_paths() -> Array:
	var paths: Array = []
	for scene in _follower_scenes:
		if scene and scene.resource_path != "":
			paths.append(scene.resource_path)
	return paths

# Restores followers from saved paths — called on load
func restore_from_paths(paths: Array) -> void:
	clear_followers()
	for path in paths:
		if ResourceLoader.exists(path):
			var scene = load(path)
			if scene:
				_follower_scenes.append(scene)
		else:
			push_warning("FollowerManager: saved follower path not found: %s" % path)

# Called by SceneLoader after every scene load and battle return.
func respawn_followers(scene_root: Node, player: Node) -> void:
	for instance in _active_instances:
		if is_instance_valid(instance):
			instance.queue_free()
	_active_instances.clear()

	if _follower_scenes.is_empty():
		return
	if not player or not is_instance_valid(player):
		push_warning("FollowerManager: no valid player to spawn followers near")
		return

	for i in _follower_scenes.size():
		var scene = _follower_scenes[i]
		var follower = scene.instantiate()
		scene_root.add_child(follower)
		var offset = Vector3(0.0, 0.0, 1.5 + i * 1.0)
		var rotated_offset = offset.rotated(Vector3.UP, player.rotation.y + PI)
		follower.global_position = player.global_position + rotated_offset
		follower.rotation.y = player.rotation.y
		_active_instances.append(follower)