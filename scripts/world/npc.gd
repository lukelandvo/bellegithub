# npc.gd
# Attach to the root CharacterBody3D of an NPC scene.
# Uses an enum state machine for clean state management.
# Interaction range is handled by a child npc_interaction_area.gd on an Area3D.
#
# Recruitment:
#   Set recruit_flag and follower_scene in the inspector.
#   In your dialogue file, use <<set recruited_x = true>> on the join branch.
#   When dialogue ends with that flag set, the NPC spawns the follower at its
#   position and removes itself from the world.

extends CharacterBody3D

enum State { IDLE, WANDER, APPROACH, TALK, DEFEATED }

var _state: State = State.IDLE

@export_group("Identity")
@export var npc_type: String = ""
@export var scene_id: String = ""
@export var instance_index: int = 0

@export_group("Dialogue")
@export var dialogue: DialogueResource
@export var dialogue_start: String = "start"

@export_group("Encounter")
@export var encounter: Resource
@export var defeat_flag: String = ""

@export_group("Post Defeat")
@export var post_defeat_idle: String = ""
@export var post_defeat_dialogue_start: String = ""
@export var post_defeat_dialogue_seen_flag: String = ""

@export_group("Recruitment")
@export var recruit_flag: String = ""
@export var follower_scene: PackedScene = null
@export var npc_name: String = ""
@export var join_title: String = ""

@export_group("Save Point")
@export var is_save_npc: bool = false
@export var save_point_id: String = ""
@export var save_point_name: String = ""
@export var save_menu_scene: PackedScene = null

@export_group("Animations")
@export var idle_animation: String = "idle"
@export var walk_animation: String = "walk"
@export var talk_animation: String = ""
@export var greeting_animation: String = ""
@export var greeting_flag: String = ""

@export_group("Facing")
@export var body_node_name: String = "Armature"
@export var facing_offset_degrees: float = 0.0
@export var face_speed: float = 10.0

@export_group("Wander")
@export var can_wander: bool = false
@export var wander_speed: float = 1.5
@export var wander_radius: float = 3.0
@export var wander_wait_min: float = 2.0
@export var wander_wait_max: float = 5.0
@export var wander_move_min: float = 1.0
@export var wander_move_max: float = 3.0

@export_group("Approach")
@export var can_approach: bool = false
@export var approach_speed: float = 2.5
@export var approach_trigger_distance: float = 8.0
@export var approach_flag: String = ""

@export_group("Node References")
@export var interaction_area: Area3D

@onready var anim_player: AnimationPlayer = $AnimationPlayer

var _body: Node3D
var _player: Node3D
var _spawn_position: Vector3
var _original_rotation_y: float
var _greeting_playing: bool = false
var _approach_done: bool = false
var _victory_flag_key: String = ""
var _dialogue_triggered: bool = false

var _wander_state: String = "waiting"
var _wander_timer: float = 0.0
var _wander_target: Vector3 = Vector3.ZERO
var _wander_direction: Vector3 = Vector3.ZERO

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

func _ready() -> void:
	add_to_group("npc")
	_body = get_node_or_null(body_node_name)
	_spawn_position = global_position
	if _body:
		_original_rotation_y = _body.rotation.y

	if npc_type != "" and scene_id != "":
		_victory_flag_key = FlagService.make_instance_flag(npc_type, scene_id, instance_index)
	elif defeat_flag != "":
		_victory_flag_key = defeat_flag

	DialogueManager.dialogue_started.connect(_on_dialogue_started)
	DialogueManager.dialogue_ended.connect(_on_dialogue_ended)

	await get_tree().process_frame

	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		_player = players[0]

	if recruit_flag != "" and FlagService.get_bool(recruit_flag):
		queue_free()
		return

	if _victory_flag_key != "" and FlagService.get_bool(_victory_flag_key):
		_enter_state(State.DEFEATED)
		return

	if can_approach and approach_flag != "" and FlagService.get_bool(approach_flag):
		_approach_done = true

	_wander_timer = randf_range(wander_wait_min, wander_wait_max)
	_enter_state(State.WANDER if can_wander else State.IDLE)

	if anim_player:
		anim_player.animation_finished.connect(_on_animation_finished)

func _exit_tree() -> void:
	if DialogueManager.dialogue_started.is_connected(_on_dialogue_started):
		DialogueManager.dialogue_started.disconnect(_on_dialogue_started)
	if DialogueManager.dialogue_ended.is_connected(_on_dialogue_ended):
		DialogueManager.dialogue_ended.disconnect(_on_dialogue_ended)

# ---------------------------------------------------------------------------
# State machine
# ---------------------------------------------------------------------------

func _enter_state(new_state: State) -> void:
	_state = new_state
	match new_state:
		State.IDLE:
			velocity = Vector3.ZERO
			_play_animation(idle_animation)

		State.WANDER:
			_wander_state = "waiting"
			_wander_timer = randf_range(wander_wait_min, wander_wait_max)
			_play_animation(idle_animation)

		State.APPROACH:
			_play_animation(walk_animation)

		State.TALK:
			velocity = Vector3.ZERO
			if talk_animation != "" and anim_player and anim_player.has_animation(talk_animation):
				_play_animation(talk_animation)
			else:
				_play_animation(idle_animation)

		State.DEFEATED:
			velocity = Vector3.ZERO
			can_wander = false
			set_physics_process(false)
			if interaction_area:
				interaction_area.hide_prompt()
			if post_defeat_idle != "" and anim_player and anim_player.has_animation(post_defeat_idle):
				var anim = anim_player.get_animation(post_defeat_idle)
				if anim:
					anim.loop_mode = Animation.LOOP_LINEAR
				anim_player.play(post_defeat_idle)
				if post_defeat_dialogue_start != "" and dialogue:
					_try_fire_post_defeat_dialogue()
			else:
				visible = false
				if interaction_area:
					interaction_area.set_deferred("monitoring", false)
				for child in get_children():
					if child is CollisionShape3D:
						child.set_deferred("disabled", true)

# ---------------------------------------------------------------------------
# Physics process
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = 0.0

	match _state:
		State.IDLE:
			velocity.x = 0.0
			velocity.z = 0.0
		State.WANDER:
			if can_wander:
				_handle_wander(delta)
			else:
				velocity.x = 0.0
				velocity.z = 0.0
		State.APPROACH:
			_handle_approach(delta)
		State.TALK:
			velocity.x = 0.0
			velocity.z = 0.0
			_face_player(delta)
		State.DEFEATED:
			velocity.x = 0.0
			velocity.z = 0.0

	move_and_slide()

	if _state == State.WANDER or _state == State.IDLE:
		if can_approach and not _approach_done and _player:
			var dist = global_position.distance_to(_player.global_position)
			if dist <= approach_trigger_distance:
				_enter_state(State.APPROACH)

# ---------------------------------------------------------------------------
# Wander
# ---------------------------------------------------------------------------

func _handle_wander(delta: float) -> void:
	_wander_timer -= delta
	if _wander_state == "waiting":
		velocity.x = 0.0
		velocity.z = 0.0
		if _wander_timer <= 0.0:
			var angle = randf() * TAU
			var dist = randf() * wander_radius
			_wander_target = _spawn_position + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
			_wander_direction = (_wander_target - global_position)
			_wander_direction.y = 0.0
			_wander_direction = _wander_direction.normalized()
			_wander_state = "moving"
			_wander_timer = randf_range(wander_move_min, wander_move_max)
			_play_animation(walk_animation)
	elif _wander_state == "moving":
		velocity.x = _wander_direction.x * wander_speed
		velocity.z = _wander_direction.z * wander_speed
		if _body and _wander_direction.length() > 0.1:
			var target_rot = atan2(_wander_direction.x, _wander_direction.z)
			_body.rotation.y = lerp_angle(_body.rotation.y, target_rot, face_speed * delta)
		if global_position.distance_to(_wander_target) < 0.3 or _wander_timer <= 0.0:
			_wander_state = "waiting"
			_wander_timer = randf_range(wander_wait_min, wander_wait_max)
			velocity.x = 0.0
			velocity.z = 0.0
			_play_animation(idle_animation)

# ---------------------------------------------------------------------------
# Approach
# ---------------------------------------------------------------------------

func _handle_approach(delta: float) -> void:
	if not _player:
		_enter_state(State.IDLE)
		return
	var dir = (_player.global_position - global_position)
	dir.y = 0.0
	var dist = dir.length()
	if dist <= 2.0:
		velocity.x = 0.0
		velocity.z = 0.0
		if approach_flag != "":
			FlagService.set_flag(approach_flag)
		_approach_done = true
		_trigger_approach_dialogue()
		_enter_state(State.WANDER if can_wander else State.IDLE)
		return
	dir = dir.normalized()
	velocity.x = dir.x * approach_speed
	velocity.z = dir.z * approach_speed
	if _body:
		var target_rot = atan2(dir.x, dir.z)
		_body.rotation.y = lerp_angle(_body.rotation.y, target_rot, face_speed * delta)

# ---------------------------------------------------------------------------
# Facing
# ---------------------------------------------------------------------------

func _face_player(delta: float) -> void:
	if not _player or not _body:
		return
	var dir = (_player.global_position - global_position)
	dir.y = 0.0
	if dir.length() > 0.1:
		var target_rot = atan2(dir.x, dir.z) - deg_to_rad(facing_offset_degrees)
		_body.rotation.y = lerp_angle(_body.rotation.y, target_rot, face_speed * delta)

# ---------------------------------------------------------------------------
# Interaction area callbacks
# ---------------------------------------------------------------------------

func on_player_entered() -> void:
	pass

func on_player_exited() -> void:
	pass

# ---------------------------------------------------------------------------
# Interact
# ---------------------------------------------------------------------------

func interact() -> void:
	if _state == State.TALK:
		return
	if _dialogue_triggered:
		return
	if is_save_npc and FlagService.get_bool("save_menu_open"):
		return
	if _state == State.DEFEATED:
		if post_defeat_dialogue_start != "" and dialogue:
			if not interaction_area or not interaction_area.player_in_range:
				return
			_dialogue_triggered = true
			DialogueManager.show_dialogue_balloon(dialogue, post_defeat_dialogue_start)
		return
	if not interaction_area or not interaction_area.player_in_range:
		return
	if not dialogue:
		return

	if greeting_animation != "" and greeting_flag != "" and not FlagService.get_bool(greeting_flag):
		if anim_player and anim_player.has_animation(greeting_animation):
			_greeting_playing = true
			anim_player.play(greeting_animation)
			FlagService.set_flag(greeting_flag)

	if encounter and (_victory_flag_key == "" or not FlagService.get_bool(_victory_flag_key)):
		BattleSession.set_encounter(encounter)

	_dialogue_triggered = true
	DialogueManager.show_dialogue_balloon(dialogue, dialogue_start)

# ---------------------------------------------------------------------------
# Post-defeat dialogue
# ---------------------------------------------------------------------------

func _try_fire_post_defeat_dialogue() -> void:
	if post_defeat_dialogue_seen_flag != "" and FlagService.get_bool(post_defeat_dialogue_seen_flag):
		return
	var loaders = get_tree().get_nodes_in_group("scene_loader")
	if loaders.size() > 0 and loaders[0].has_signal("battle_return_complete"):
		await loaders[0].battle_return_complete
	else:
		await get_tree().create_timer(1.0).timeout
	if post_defeat_dialogue_seen_flag != "":
		FlagService.set_flag(post_defeat_dialogue_seen_flag)
	DialogueManager.show_dialogue_balloon(dialogue, post_defeat_dialogue_start)

func _trigger_approach_dialogue() -> void:
	if not dialogue:
		return
	if encounter and (_victory_flag_key == "" or not FlagService.get_bool(_victory_flag_key)):
		BattleSession.set_encounter(encounter)
	_dialogue_triggered = true
	DialogueManager.show_dialogue_balloon(dialogue, dialogue_start)

# ---------------------------------------------------------------------------
# Dialogue callbacks
# ---------------------------------------------------------------------------

func _on_dialogue_started(_resource: Resource) -> void:
	if not interaction_area or not interaction_area.player_in_range:
		return
	interaction_area.lock()
	_enter_state(State.TALK)

func _on_dialogue_ended(_resource: Resource) -> void:
	_dialogue_triggered = false

	# Recruitment paths fire before state guard — join balloon fires outside TALK state.
	if _is_recruiting and not _recruit_done:
		_finish_recruit()
		return

	if recruit_flag != "" and FlagService.get_bool(recruit_flag) and not _is_recruiting and not _recruit_done:
		_recruit()
		return

	# Battle trigger — checked before state guard so the confrontation fires correctly.
	# Also checks that this NPC actually has an encounter assigned, preventing
	# other NPCs' dialogue endings from accidentally triggering this battle.
	if BattleSession.pending_encounter != null and encounter != null and _state == State.TALK:
		var loaders = get_tree().get_nodes_in_group("scene_loader")
		if loaders.size() > 0 and loaders[0].has_method("load_battle"):
			loaders[0].load_battle(BattleSession.pending_encounter)
		return

	if _state != State.TALK:
		return

	# Save NPC confirm message just finished — restore to normal.
	if is_save_npc and FlagService.get_bool("save_confirming"):
		FlagService.clear_flag("save_confirming")
		await get_tree().create_timer(0.25).timeout
		if interaction_area:
			interaction_area.unlock()
		var player = get_tree().get_first_node_in_group("player")
		if player and player.has_method("enable_movement"):
			player.enable_movement()
		_enter_state(State.WANDER if can_wander else State.IDLE)
		return

	# Save NPC — only open slot menu if player chose yes.
	if is_save_npc and FlagService.get_bool("wants_save"):
		FlagService.clear_flag("wants_save")
		_open_save_menu()
		return

	# No battle, no recruit — restore prompt and return to normal state.
	interaction_area.unlock()
	_enter_state(State.WANDER if can_wander else State.IDLE)

# ---------------------------------------------------------------------------
# Recruitment
# ---------------------------------------------------------------------------

var _recruit_done: bool = false
var _is_recruiting: bool = false

func _recruit() -> void:
	if _is_recruiting or _recruit_done:
		return
	if not follower_scene:
		push_error("npc '%s': recruit_flag set but no follower_scene assigned" % name)
		return
	_is_recruiting = true
	if join_title != "" and dialogue:
		DialogueManager.show_dialogue_balloon(dialogue, join_title)
	else:
		_finish_recruit()

func _finish_recruit() -> void:
	if _recruit_done:
		return
	_recruit_done = true
	FollowerManager.add_follower(follower_scene)
	var scene_root = get_tree().get_first_node_in_group("scene_loader")
	if scene_root and scene_root.get("scene_root"):
		FollowerManager.respawn_followers(scene_root.scene_root, get_tree().get_first_node_in_group("player"))
	if npc_name != "":
		_show_join_message(npc_name + " joined the party!")
	queue_free()

func _show_join_message(message: String) -> void:
	var label = Label.new()
	label.text = message
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 20)
	var canvas = CanvasLayer.new()
	canvas.layer = 10
	get_tree().root.add_child(canvas)
	canvas.add_child(label)
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	label.offset_top += 80
	label.offset_bottom += 80
	var tween = get_tree().create_tween()
	tween.tween_interval(2.0)
	tween.tween_callback(canvas.queue_free)

# ---------------------------------------------------------------------------
# Save point
# ---------------------------------------------------------------------------

func _open_save_menu() -> void:
	if not save_menu_scene:
		push_error("npc '%s': is_save_npc is true but no save_menu_scene assigned" % name)
		return
	var _current_scene_id = ""
	var loaders = get_tree().get_nodes_in_group("scene_loader")
	if loaders.size() > 0:
		_current_scene_id = loaders[0].current_scene_id
	var player_pos = _player.global_position if _player else Vector3.ZERO
	var player_rot = _player.rotation.y if _player else 0.0
	SaveManager.activate_save_point(save_point_id, save_point_name, _current_scene_id, player_pos, player_rot)
	if interaction_area:
		interaction_area.lock()
	var menu = save_menu_scene.instantiate()
	get_tree().root.add_child(menu)
	menu.save_completed.connect(_on_save_completed)
	menu.save_cancelled.connect(_on_save_cancelled)
	menu.open()

func _on_save_completed(_slot: int) -> void:
	FlagService.set_flag("save_confirming")
	if dialogue:
		DialogueManager.show_dialogue_balloon(dialogue, "save_confirm")

func _on_save_cancelled() -> void:
	if interaction_area:
		interaction_area.unlock()
	_enter_state(State.WANDER if can_wander else State.IDLE)

# ---------------------------------------------------------------------------
# Animation
# ---------------------------------------------------------------------------

func _on_animation_finished(anim_name: String) -> void:
	if anim_name == greeting_animation and _greeting_playing:
		_greeting_playing = false
		_play_animation(idle_animation, 0.3)

func _play_animation(anim_name: String, blend: float = 0.2) -> void:
	if not anim_player or anim_name == "":
		return
	if not anim_player.has_animation(anim_name):
		push_warning("npc: animation '%s' not found on %s" % [anim_name, name])
		return
	if anim_player.current_animation == anim_name:
		return
	anim_player.play(anim_name, blend)

func reset_to_spawn() -> void:
	global_position = _spawn_position
	velocity = Vector3.ZERO
	set_physics_process(true)
	_enter_state(State.WANDER if can_wander else State.IDLE)
