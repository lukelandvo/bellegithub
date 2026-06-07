# player.gd
# Attach to the root CharacterBody3D of the player scene.
#
# Movement angle override:
#   When a camera_area sets override_movement_angle, forward/back moves
#   along a fixed world axis and left/right strafes perpendicular to it.
#   The character faces the direction it's moving. No turning in this mode.
#   Call clear_movement_angle_override() to restore normal tank controls.

extends CharacterBody3D

@export_group("Movement")
@export var speed: float = 5.0
@export var run_speed: float = 8.0
@export var turn_speed: float = 120.0

@export_group("Feel")
@export var acceleration: float = 15.0
@export var deceleration: float = 20.0

@export_group("Locomotion Animations")
@export var walk_animation: String = "walk"
@export var run_animation: String = "run"

@export_subgroup("Animation Speeds")
@export var walk_speed: float = 1.0
@export var run_anim_speed: float = 1.0

@export_group("Idle Rotation")
@export var idle_animation_1: String = "idle_normal"
@export var idle_animation_1_repeats: int = 3
@export var idle_animation_2: String = "idle_happy"
@export var idle_animation_2_repeats: int = 1
@export var idle_animation_3: String = ""
@export var idle_animation_3_repeats: int = 1

@export_group("Blend Times")
@export var blend_idle: float = 0.2
@export var blend_locomotion: float = 0.15

@export_group("Node References")
@export var armature: Node3D
@export var animation_player: AnimationPlayer

var can_move: bool = true
var is_in_dialogue: bool = false
var is_running: bool = false

var _current_animation: String = ""
var _interact_cooldown: bool = false
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

var _is_moving: bool = false
var _idle_slot: int = 0
var _idle_play_count: int = 0
var _idle_started: bool = false

var _facing_angle: float = 0.0

# Movement angle override — set by camera_area for fixed-camera rooms.
# When active: forward/back moves along this axis, left/right strafes.
# Cleared on area exit.
var _movement_angle_override: float = 0.0
var _use_movement_override: bool = false

func _ready() -> void:
	add_to_group("player")
	floor_max_angle = deg_to_rad(60.0)
	DialogueManager.dialogue_started.connect(_on_dialogue_started)
	DialogueManager.dialogue_ended.connect(_on_dialogue_ended)
	if animation_player:
		_set_animation_looping()
		animation_player.animation_finished.connect(_on_animation_finished)
		_start_idle_rotation()

func _exit_tree() -> void:
	if DialogueManager.dialogue_started.is_connected(_on_dialogue_started):
		DialogueManager.dialogue_started.disconnect(_on_dialogue_started)
	if DialogueManager.dialogue_ended.is_connected(_on_dialogue_ended):
		DialogueManager.dialogue_ended.disconnect(_on_dialogue_ended)
	if animation_player and animation_player.animation_finished.is_connected(_on_animation_finished):
		animation_player.animation_finished.disconnect(_on_animation_finished)

func get_facing_angle() -> float:
	return _facing_angle

func set_facing_angle(angle_rad: float) -> void:
	_facing_angle = angle_rad
	if armature:
		armature.rotation.y = angle_rad

func set_movement_angle_override(angle_rad: float) -> void:
	_movement_angle_override = angle_rad
	_use_movement_override = true

func clear_movement_angle_override() -> void:
	_use_movement_override = false

func _on_dialogue_started(_resource: Resource) -> void:
	is_in_dialogue = true

func _on_dialogue_ended(_resource: Resource) -> void:
	is_in_dialogue = false
	_interact_cooldown = true
	await get_tree().create_timer(0.2).timeout
	if not is_instance_valid(self):
		return
	_interact_cooldown = false

func _on_animation_finished(anim_name: String) -> void:
	if anim_name == walk_animation or anim_name == run_animation:
		return
	if _is_moving or is_in_dialogue:
		return
	if anim_name != _get_idle_anim_for_slot(_idle_slot):
		return
	_idle_play_count += 1
	if _idle_play_count >= _get_idle_repeats_for_slot(_idle_slot):
		_idle_play_count = 0
		_idle_slot = _next_valid_idle_slot(_idle_slot)
	_play_current_idle()

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta

	if is_in_dialogue:
		velocity.x = move_toward(velocity.x, 0.0, deceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, deceleration * delta)
		move_and_slide()
		AudioManager.stop_footsteps()
		return

	is_running = Input.is_action_pressed("run") and can_move
	var current_speed: float = run_speed if is_running else speed
	var was_moving: bool = _is_moving

	if _use_movement_override:
		_physics_process_override(delta, current_speed)
	else:
		_physics_process_normal(delta, current_speed)

	if _is_moving and is_on_floor():
		AudioManager.start_footsteps(is_running)
		_play_animation(run_animation if is_running else walk_animation,
				run_anim_speed if is_running else walk_speed, blend_locomotion)
	else:
		AudioManager.stop_footsteps()
		if was_moving and not _is_moving and not _idle_started:
			_idle_started = true
			_start_idle_rotation()

	move_and_slide()

	if Input.is_action_just_pressed("interact") and can_move:
		_try_interact()

func _physics_process_normal(delta: float, current_speed: float) -> void:
	# Standard tank controls — left/right turns, forward/back moves.
	if can_move:
		if Input.is_action_pressed("move_left"):
			_facing_angle += deg_to_rad(turn_speed) * delta
		if Input.is_action_pressed("move_right"):
			_facing_angle -= deg_to_rad(turn_speed) * delta

	if armature:
		armature.rotation.y = _facing_angle

	var forward = Vector3(sin(_facing_angle), 0.0, cos(_facing_angle))

	if can_move and Input.is_action_pressed("move_forward"):
		_is_moving = true
		_idle_started = false
		velocity.x = move_toward(velocity.x, forward.x * current_speed, acceleration * delta)
		velocity.z = move_toward(velocity.z, forward.z * current_speed, acceleration * delta)
	elif can_move and Input.is_action_pressed("move_back"):
		_is_moving = true
		_idle_started = false
		velocity.x = move_toward(velocity.x, -forward.x * current_speed, acceleration * delta)
		velocity.z = move_toward(velocity.z, -forward.z * current_speed, acceleration * delta)
	else:
		_is_moving = false
		velocity.x = move_toward(velocity.x, 0.0, deceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, deceleration * delta)

func _physics_process_override(delta: float, current_speed: float) -> void:
	# Fixed-camera controls — movement is relative to the override angle.
	# forward/back moves along the camera axis, left/right strafes.
	# Character visually faces whichever direction it's moving.
	var cam_forward = Vector3(sin(_movement_angle_override), 0.0, cos(_movement_angle_override))
	var cam_right = Vector3(cos(_movement_angle_override), 0.0, -sin(_movement_angle_override))

	var move_dir := Vector3.ZERO
	if can_move:
		if Input.is_action_pressed("move_forward"):
			move_dir += cam_forward
		if Input.is_action_pressed("move_back"):
			move_dir -= cam_forward
		if Input.is_action_pressed("move_left"):
			move_dir += cam_right
		if Input.is_action_pressed("move_right"):
			move_dir -= cam_right

	if move_dir.length() > 0.01:
		move_dir = move_dir.normalized()
		_is_moving = true
		_idle_started = false
		_facing_angle = atan2(move_dir.x, move_dir.z)
		if armature:
			armature.rotation.y = _facing_angle
		velocity.x = move_toward(velocity.x, move_dir.x * current_speed, acceleration * delta)
		velocity.z = move_toward(velocity.z, move_dir.z * current_speed, acceleration * delta)
	else:
		_is_moving = false
		velocity.x = move_toward(velocity.x, 0.0, deceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, deceleration * delta)

func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_T:
			SaveManager.add_item("hamburger")
			_show_item_message("Got a Hamburger!")
		if event.keycode == KEY_Y:
			SaveManager.add_item("hammer")
			_show_item_message("Got a Hammer!")

func _try_interact() -> void:
	if _interact_cooldown:
		return
	for npc in get_tree().get_nodes_in_group("npc"):
		if is_instance_valid(npc) and npc.has_method("interact"):
			if npc.interaction_area and npc.interaction_area.player_in_range:
				npc.interact()
				break

func enable_movement() -> void:
	can_move = true

func disable_movement() -> void:
	can_move = false
	AudioManager.stop_footsteps()
	for npc in get_tree().get_nodes_in_group("npc"):
		if npc.get("interaction_area") and npc.interaction_area:
			npc.interaction_area.hide_prompt()
	if animation_player:
		_start_idle_rotation()

func _show_item_message(message: String) -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 10
	get_tree().root.add_child(canvas)
	var label := Label.new()
	label.text = message
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 20)
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	label.offset_top += 80
	label.offset_bottom += 80
	canvas.add_child(label)
	var tween := get_tree().create_tween()
	tween.tween_interval(2.0)
	tween.tween_callback(canvas.queue_free)

func _start_idle_rotation() -> void:
	_idle_slot = 0
	_idle_play_count = 0
	_play_current_idle()

func _play_current_idle() -> void:
	var anim: String = _get_idle_anim_for_slot(_idle_slot)
	if anim == "" or not animation_player:
		return
	if not animation_player.has_animation(anim):
		push_warning("player: idle animation '%s' not found" % anim)
		return
	_current_animation = anim
	animation_player.speed_scale = 1.0
	animation_player.play(anim, blend_idle)

func _get_idle_anim_for_slot(slot: int) -> String:
	match slot:
		0: return idle_animation_1
		1: return idle_animation_2
		2: return idle_animation_3
	return ""

func _get_idle_repeats_for_slot(slot: int) -> int:
	match slot:
		0: return idle_animation_1_repeats
		1: return idle_animation_2_repeats
		2: return idle_animation_3_repeats
	return 1

func _next_valid_idle_slot(current: int) -> int:
	for i in range(3):
		var next: int = (current + 1 + i) % 3
		var anim: String = _get_idle_anim_for_slot(next)
		if anim != "" and animation_player.has_animation(anim):
			return next
	return 0

func _set_animation_looping() -> void:
	if not animation_player:
		return
	for anim_name in [walk_animation, run_animation]:
		_set_loop_mode(anim_name, Animation.LOOP_LINEAR)
	for anim_name in [idle_animation_1, idle_animation_2, idle_animation_3]:
		if anim_name != "":
			_set_loop_mode(anim_name, Animation.LOOP_NONE)

func _set_loop_mode(anim_name: String, mode: Animation.LoopMode) -> void:
	if not animation_player.has_animation(anim_name):
		return
	var anim: Animation = animation_player.get_animation(anim_name)
	if anim:
		anim.loop_mode = mode

func _play_animation(anim_name: String, anim_speed: float = 1.0, blend: float = 0.15) -> void:
	if not animation_player:
		return
	if _current_animation == anim_name:
		return
	if not animation_player.has_animation(anim_name):
		push_warning("player: animation '%s' not found" % anim_name)
		return
	animation_player.speed_scale = anim_speed
	animation_player.play(anim_name, blend)
	_current_animation = anim_name
