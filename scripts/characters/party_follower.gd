# party_follower.gd
# Attach to a CharacterBody3D in the follower's scene.
# Follows a target (player or another follower) along a recorded position history.
#
# Set target_group to "player" for the first follower.
# Set target_group to "follower1" (or whatever group the first follower is in)
# for the second follower — creates a natural chain/train effect.
#
# Add this node to its own group (e.g. "follower1", "follower2") so other
# followers can target it.
#
# Movement zones (based on distance to target):
#   within follow_distance   → full stop, idle
#   within run_threshold     → walk
#   beyond run_threshold     → run to catch up

extends CharacterBody3D

# ---------------------------------------------------------------------------
# Inspector — node references
# ---------------------------------------------------------------------------

@export_group("Node References")
@export var armature: Node3D
@export var animation_player: AnimationPlayer

# ---------------------------------------------------------------------------
# Inspector — targeting
# ---------------------------------------------------------------------------

@export_group("Targeting")
@export var target_group: String = "player"    # group to search for follow target

# ---------------------------------------------------------------------------
# Inspector — follow behavior
# ---------------------------------------------------------------------------

@export_group("Follow")
@export var follow_distance: float = 2.0
@export var run_threshold: float = 4.0
@export var walk_speed: float = 4.0
@export var run_speed: float = 7.0
@export var teleport_distance: float = 12.0
@export var history_length: int = 60
@export var face_speed: float = 10.0
@export var acceleration: float = 3.0
@export var deceleration: float = 10.0
@export var move_delay: float = 0.5

# ---------------------------------------------------------------------------
# Inspector — animations
# ---------------------------------------------------------------------------

@export_group("Locomotion Animations")
@export var walk_animation: String = "walk"
@export var run_animation: String = "run"

@export_subgroup("Animation Speeds")
@export var walk_speed_anim: float = 1.0
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

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _target: Node3D = null
var _position_history: Array[Vector3] = []
var _idle_slot: int = 0
var _idle_play_count: int = 0
var _idle_started: bool = false
var _current_animation: String = ""
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _move_delay_timer: float = 0.0
var _facing_angle: float = 0.0

# ---------------------------------------------------------------------------
# Ready
# ---------------------------------------------------------------------------

func _ready() -> void:
	await get_tree().process_frame
	var targets = get_tree().get_nodes_in_group(target_group)
	if targets.size() > 0:
		_target = targets[0]
	else:
		push_warning("party_follower: no node found in group '%s'" % target_group)
		return

	for i in range(history_length):
		_position_history.append(_target.global_position)

	if animation_player:
		_set_animation_looping()
		animation_player.animation_finished.connect(_on_animation_finished)
		_start_idle_rotation()

# ---------------------------------------------------------------------------
# Public — other followers can read this to teleport behind us
# ---------------------------------------------------------------------------

func get_facing_angle() -> float:
	return _facing_angle

# ---------------------------------------------------------------------------
# Physics process
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not _target:
		return

	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = 0.0

	_position_history.push_front(_target.global_position)
	if _position_history.size() > history_length:
		_position_history.pop_back()

	var dist_to_target = global_position.distance_to(_target.global_position)

	# Teleport if way too far
	if dist_to_target > teleport_distance:
		_teleport_behind_target()
		move_and_slide()
		return

	# Within stop zone — full stop
	if dist_to_target <= follow_distance:
		_move_delay_timer = 0.0
		velocity.x = move_toward(velocity.x, 0.0, deceleration * delta * 60.0)
		velocity.z = move_toward(velocity.z, 0.0, deceleration * delta * 60.0)
		move_and_slide()
		_update_animation(dist_to_target)
		return

	# Outside stop zone — increment delay timer
	_move_delay_timer += delta

	if _move_delay_timer < move_delay:
		velocity.x = move_toward(velocity.x, 0.0, deceleration * delta * 60.0)
		velocity.z = move_toward(velocity.z, 0.0, deceleration * delta * 60.0)
		move_and_slide()
		_update_animation(dist_to_target)
		return

	# Find target in position history
	var target_pos: Vector3 = _position_history[_position_history.size() - 1]
	for i in range(_position_history.size()):
		var hist_pos = _position_history[i]
		if _target.global_position.distance_to(hist_pos) >= follow_distance:
			target_pos = hist_pos
			break

	var dir = target_pos - global_position
	dir.y = 0.0

	if dir.length() > 0.05:
		dir = dir.normalized()
		_facing_angle = atan2(dir.x, dir.z)
		var is_running = dist_to_target > run_threshold
		var target_speed = run_speed if is_running else walk_speed
		velocity.x = move_toward(velocity.x, dir.x * target_speed, acceleration * delta * 60.0)
		velocity.z = move_toward(velocity.z, dir.z * target_speed, acceleration * delta * 60.0)

		if armature:
			armature.rotation.y = lerp_angle(armature.rotation.y, _facing_angle, face_speed * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, deceleration * delta * 60.0)
		velocity.z = move_toward(velocity.z, 0.0, deceleration * delta * 60.0)

	move_and_slide()
	_update_animation(dist_to_target)

# ---------------------------------------------------------------------------
# Animation update
# ---------------------------------------------------------------------------

func _update_animation(dist_to_target: float) -> void:
	var actual_speed = Vector2(velocity.x, velocity.z).length()

	if actual_speed > 0.2 and is_on_floor():
		_idle_started = false
		var is_running = dist_to_target > run_threshold
		_play_animation(run_animation if is_running else walk_animation,
				run_anim_speed if is_running else walk_speed_anim, blend_locomotion)
	else:
		if not _idle_started:
			_idle_started = true
			_start_idle_rotation()

# ---------------------------------------------------------------------------
# Teleport behind target
# ---------------------------------------------------------------------------

func _teleport_behind_target() -> void:
	if not _target:
		return
	var facing = _target.get_facing_angle() if _target.has_method("get_facing_angle") else 0.0
	var behind = Vector3(sin(facing), 0.0, cos(facing)) * follow_distance
	global_position = _target.global_position - behind
	velocity = Vector3.ZERO
	_move_delay_timer = 0.0
	for i in range(_position_history.size()):
		_position_history[i] = global_position

# ---------------------------------------------------------------------------
# Animation finished — drives idle rotation
# ---------------------------------------------------------------------------

func _on_animation_finished(anim_name: String) -> void:
	if anim_name == walk_animation or anim_name == run_animation:
		return
	if not _idle_started:
		return
	if anim_name != _get_idle_anim_for_slot(_idle_slot):
		return
	_idle_play_count += 1
	if _idle_play_count >= _get_idle_repeats_for_slot(_idle_slot):
		_idle_play_count = 0
		_idle_slot = _next_valid_idle_slot(_idle_slot)
	_play_current_idle()

# ---------------------------------------------------------------------------
# Idle rotation helpers
# ---------------------------------------------------------------------------

func _start_idle_rotation() -> void:
	_idle_slot = 0
	_idle_play_count = 0
	_play_current_idle()

func _play_current_idle() -> void:
	var anim: String = _get_idle_anim_for_slot(_idle_slot)
	if anim == "" or not animation_player:
		return
	if not animation_player.has_animation(anim):
		push_warning("party_follower: idle animation '%s' not found" % anim)
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

# ---------------------------------------------------------------------------
# Animation
# ---------------------------------------------------------------------------

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

func _play_animation(anim_name: String, speed: float = 1.0, blend: float = 0.15) -> void:
	if not animation_player:
		return
	if _current_animation == anim_name:
		return
	if not animation_player.has_animation(anim_name):
		push_warning("party_follower: animation '%s' not found" % anim_name)
		return
	animation_player.speed_scale = speed
	animation_player.play(anim_name, blend)
	_current_animation = anim_name