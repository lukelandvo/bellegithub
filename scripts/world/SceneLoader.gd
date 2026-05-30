# SceneLoader.gd
# Node in main.tscn — owns scene loading, unloading, and spawn points.
#
# v4.6: _load_from_save now resets _save_loading = false on all early-return
# error paths, preventing follower respawns from being suppressed in
# subsequent scene loads for the rest of the session.

extends Node

@export_group("References")
@export var scene_root: Node3D
@export var player: CharacterBody3D
@export var camera: Camera3D
@export var transition_manager: Node
@export var cinematic_manager: Node

@export_group("Timing")
@export var door_pause: float = 1.0
@export var music_fade_in: float = 1.5
@export var battle_settle_frames: int = 4

@export_group("Initial Scene")
@export var initial_scene: PackedScene
@export var initial_spawn_point: String = "SpawnPoint"
@export var initial_scene_id: String = ""
@export var initial_music_id: String = ""

@export_group("Battle")
@export var battle_scene: PackedScene

const SCENE_REGISTRY: Dictionary = {
	"CC_area1": "res://scenes/world/Critter Canyon/CC_area1.tscn",
	"cc_visitor": "res://scenes/world/Critter Canyon/cc_visitor.tscn",
}

var current_scene: Node = null
var current_packed_scene: PackedScene = null
var current_scene_id: String = ""

var _return_packed_scene: PackedScene = null
var _return_scene_id: String = ""
var _pre_battle_position: Vector3 = Vector3.ZERO
var _pre_battle_rotation: float = 0.0
var _pre_battle_camera_position: Vector3 = Vector3.ZERO
var _pre_battle_area: int = 0
var _is_battle_return: bool = false
var _battle_loading: bool = false
var _save_loading: bool = false

signal scene_loaded(scene_id: String)
signal battle_return_complete

func _ready() -> void:
	add_to_group("scene_loader")
	if initial_scene:
		_run_intro()

func _run_intro() -> void:
	_load_scene_internal(initial_scene, initial_spawn_point)
	current_scene_id = initial_scene_id
	if OS.is_debug_build(): print("SceneLoader: _run_intro set current_scene_id to '%s'" % current_scene_id)
	if player:
		player.disable_movement()
	await get_tree().process_frame
	await get_tree().process_frame
	if initial_music_id != "":
		AudioManager.play_music(initial_music_id)
	await transition_manager.fade_in()
	if player:
		player.enable_movement()

func load_scene(scene: PackedScene, scene_id: String, spawn_point: String = "",
		music_id: String = "", sfx_id: String = "") -> void:
	if player:
		player.disable_movement()
	await transition_manager.fade_out()
	AudioManager.stop_music()
	if sfx_id != "":
		AudioManager.play_sfx(sfx_id)
	_load_scene_internal(scene, spawn_point)
	current_scene_id = scene_id
	await get_tree().create_timer(door_pause).timeout
	if music_id != "":
		AudioManager.play_music(music_id)
	await transition_manager.fade_in()
	if player:
		player.enable_movement()
	if not _save_loading:
		FollowerManager.respawn_followers(scene_root, player)
	emit_signal("scene_loaded", scene_id)
	emit_signal("battle_return_complete")

func area_transition(target_area: int, spawn_position: Vector3,
		arrival_rotation_y: float, game_manager: Node, sfx_id: String = "") -> void:
	if player:
		player.disable_movement()
	await transition_manager.fade_out()
	if sfx_id != "":
		AudioManager.play_sfx(sfx_id)
	if game_manager:
		game_manager.change_area(target_area, spawn_position, arrival_rotation_y, camera)
	await get_tree().create_timer(door_pause).timeout
	await transition_manager.fade_in()
	if player:
		player.enable_movement()

func load_battle(_encounter: Resource) -> void:
	if _battle_loading:
		return
	if not battle_scene:
		push_error("SceneLoader: battle_scene not assigned in inspector")
		return

	_battle_loading = true

	if player:
		player.disable_movement()
	_freeze_world_entities()
	FollowerManager.hide_followers()

	if player:
		_pre_battle_position = player.global_position
		_pre_battle_rotation = player.rotation.y
	if camera:
		_pre_battle_camera_position = camera.global_position
	for cam_area in get_tree().get_nodes_in_group("camera_area"):
		if cam_area.get("area_index") != null:
			_pre_battle_area = cam_area.area_index
			break
	_return_packed_scene = current_packed_scene
	_return_scene_id = current_scene_id
	_is_battle_return = true

	BattleSession.confirm_encounter()

	await cinematic_manager.play_confrontation()

	if player:
		player.visible = false
	_load_scene_internal(battle_scene, "", true)
	await get_tree().process_frame
	await get_tree().process_frame
	var bm = get_tree().get_first_node_in_group("battle_manager")
	if bm and bm.has_signal("battle_finished"):
		if not bm.battle_finished.is_connected(end_battle):
			bm.battle_finished.connect(end_battle, CONNECT_ONE_SHOT)
	await get_tree().create_timer(0.3).timeout
	await transition_manager.fade_in()
	_battle_loading = false

func _freeze_world_entities() -> void:
	for npc in get_tree().get_nodes_in_group("npc"):
		npc.set_process(false)
		npc.set_physics_process(false)
		if npc.get("anim_player") and npc.anim_player:
			npc.anim_player.pause()
		if npc.get("interaction_area") and npc.interaction_area:
			if npc.interaction_area.has_method("lock"):
				npc.interaction_area.lock()
	for enemy in get_tree().get_nodes_in_group("world_npc"):
		if enemy.has_method("freeze"):
			enemy.freeze()
		else:
			if enemy.get("anim_player") and enemy.anim_player:
				enemy.anim_player.pause()

func _unfreeze_world_entities() -> void:
	for npc in get_tree().get_nodes_in_group("npc"):
		npc.set_process(true)
		npc.set_physics_process(true)
		if npc.get("anim_player") and npc.anim_player:
			var current = npc.anim_player.current_animation
			if current != "":
				npc.anim_player.play(current)
		if npc.get("interaction_area") and npc.interaction_area:
			if npc.interaction_area.has_method("unlock"):
				npc.interaction_area.unlock()
	for enemy in get_tree().get_nodes_in_group("world_npc"):
		if enemy.has_method("unfreeze"):
			enemy.unfreeze()
		else:
			if enemy.get("anim_player") and enemy.anim_player:
				enemy.anim_player.play()

func end_battle() -> void:
	if player:
		player.disable_movement()
		player.visible = false
	transition_manager.set_black()
	if camera and camera.has_method("snap_to_position"):
		camera.snap_to_position(_pre_battle_camera_position)
	if player and _pre_battle_position != Vector3.ZERO:
		player.global_position = _pre_battle_position
		player.rotation.y = _pre_battle_rotation
	if _return_packed_scene:
		_load_scene_internal(_return_packed_scene)
		current_scene_id = _return_scene_id
	for i in range(battle_settle_frames):
		await get_tree().process_frame
	var gm = _find_game_manager()
	if gm and _pre_battle_area != 0:
		gm.change_area(_pre_battle_area, Vector3.ZERO, 0.0, camera)
	await get_tree().physics_frame
	await get_tree().physics_frame
	if player:
		player.visible = true
		if _pre_battle_position != Vector3.ZERO:
			player.global_position = _pre_battle_position
			player.rotation.y = _pre_battle_rotation
	_clear_battle_state()
	await get_tree().create_timer(0.3).timeout
	cinematic_manager.resume_world()
	_unfreeze_world_entities()
	AudioManager.play_music(current_scene_id)
	FollowerManager.respawn_followers(scene_root, player)
	await transition_manager.fade_in()
	if camera and camera.has_method("release_hold"):
		camera.release_hold()
	if player:
		player.enable_movement()
	_inject_scene_exits()
	emit_signal("battle_return_complete")

func _load_from_save(scene_id: String) -> void:
	_save_loading = true

	if scene_id == "" or not SCENE_REGISTRY.has(scene_id):
		push_error("SceneLoader: _load_from_save invalid scene_id '%s'" % scene_id)
		_save_loading = false
		return

	var scene: PackedScene = load(SCENE_REGISTRY[scene_id])
	if not scene:
		push_error("SceneLoader: failed to load scene '%s'" % SCENE_REGISTRY[scene_id])
		_save_loading = false
		return

	if player:
		player.disable_movement()
	await transition_manager.fade_out()

	var menu_manager = get_tree().get_first_node_in_group("menu_manager")
	if menu_manager and menu_manager.has_method("close_menu"):
		menu_manager.close_menu()

	_load_scene_internal(scene)
	current_scene_id = scene_id

	await get_tree().process_frame
	await get_tree().process_frame

	if player:
		player.visible = true
	if player and SaveManager.saved_player_position != Vector3.ZERO:
		player.global_position = SaveManager.saved_player_position
		player.rotation.y = SaveManager.saved_player_rotation

	_save_loading = false
	FollowerManager.restore_from_paths(SaveManager._pending_follower_paths)
	FollowerManager.respawn_followers(scene_root, player)

	for node in get_tree().get_nodes_in_group("standalone_load_menu"):
		node.queue_free()

	if camera and camera.has_method("snap_to_target"):
		camera.snap_to_target()

	await get_tree().create_timer(door_pause).timeout
	await transition_manager.fade_in()

	if player:
		player.enable_movement()

	emit_signal("scene_loaded", scene_id)
	emit_signal("battle_return_complete")

func restart_from_beginning() -> void:
	if not initial_scene:
		push_error("SceneLoader: no initial_scene assigned")
		return
	FollowerManager.clear_followers()
	if player:
		player.disable_movement()
	await transition_manager.fade_out()
	_load_scene_internal(initial_scene, initial_spawn_point)
	current_scene_id = initial_scene_id
	await get_tree().process_frame
	await get_tree().process_frame
	if player:
		player.visible = true
	if camera and camera.has_method("snap_to_target"):
		camera.snap_to_target()
	if initial_music_id != "":
		AudioManager.play_music(initial_music_id)
	await transition_manager.fade_in()
	if player:
		player.enable_movement()

func load_scene_by_id(scene_id: String, spawn_point: String = "", music_id: String = "") -> void:
	if scene_id == "":
		push_error("SceneLoader: load_scene_by_id called with empty scene_id")
		return
	if not SCENE_REGISTRY.has(scene_id):
		push_error("SceneLoader: scene_id '%s' not found in SCENE_REGISTRY" % scene_id)
		return
	var scene: PackedScene = load(SCENE_REGISTRY[scene_id])
	if not scene:
		push_error("SceneLoader: failed to load scene at '%s'" % SCENE_REGISTRY[scene_id])
		return
	await load_scene(scene, scene_id, spawn_point, music_id)

func _load_scene_internal(scene: PackedScene, spawn_point: String = "", is_battle: bool = false) -> void:
	var old_scene: Node = current_scene
	current_scene = scene.instantiate()
	scene_root.add_child(current_scene)
	if not is_battle:
		current_packed_scene = scene
	if spawn_point != "":
		var spawn: Node = current_scene.find_child(spawn_point, true, false)
		if spawn and player:
			player.global_position = spawn.global_position
			player.rotation.y = spawn.rotation.y
			if player.get("armature") and player.armature:
				player.armature.rotation.y = spawn.rotation.y
		else:
			push_warning("SceneLoader: spawn point '%s' not found in scene" % spawn_point)
	if old_scene:
		old_scene.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	if not _is_battle_return:
		_apply_first_camera_area()
		_inject_scene_exits()

func _apply_first_camera_area() -> void:
	for cam_area in get_tree().get_nodes_in_group("camera_area"):
		if cam_area.get("area_index") == 0:
			cam_area.camera = camera
			cam_area.apply()
			break

func _inject_scene_exits() -> void:
	for exit in get_tree().get_nodes_in_group("scene_exit"):
		if exit.has_method("inject_scene_loader"):
			exit.inject_scene_loader(self)

func _clear_battle_state() -> void:
	_return_packed_scene = null
	_return_scene_id = ""
	_pre_battle_position = Vector3.ZERO
	_pre_battle_rotation = 0.0
	_pre_battle_camera_position = Vector3.ZERO
	_pre_battle_area = 0
	_is_battle_return = false

func _find_game_manager() -> Node:
	for gm in get_tree().get_nodes_in_group("game_manager"):
		return gm
	return null
