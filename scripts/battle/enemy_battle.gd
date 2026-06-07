# enemy_battle.gd
# Attach to the root node of your enemy scene.
# Owns all enemy animation logic.

extends Node3D

@export_group("Animation Names")
@export var idle_animation: String = "idle"
@export var combat_idle_animation: String = "combat_idle"
@export var hurt_animation: String = "hurt"
@export var death_animation: String = "death"

@export_group("Default Attack Animations")
@export var default_prepare_animation: String = ""
@export var default_miss_animation: String = ""
@export var attack_anims: Array[EnemyAttackAnim] = []

@export_group("Phases")
@export var phases: Array[EnemyPhase] = []

@export_group("Blend Times")
@export var blend_to_idle: float = 0.2
@export var blend_combat_idle: float = 0.15
@export var blend_attack: float = 0.1
@export var blend_prepare: float = 0.15
@export var blend_hurt: float = 0.05
@export var blend_death: float = 0.1
@export var blend_miss: float = 0.1

@export_group("Sounds")
@export var death_sound: AudioStream

@onready var anim_player: AnimationPlayer = $AnimationPlayer

var _active_attack_anims: Array[EnemyAttackAnim] = []
var _sorted_phases: Array[EnemyPhase] = []
var _active_phase: int = -1
var _in_battle: bool = false
var _skipping: bool = false
var _is_dead: bool = false

signal animation_finished

func _ready() -> void:
	add_to_group("world_npc")
	_active_attack_anims = attack_anims.duplicate()
	_sorted_phases = phases.duplicate()
	_sorted_phases.sort_custom(func(a, b): return a.hp_threshold > b.hp_threshold)
	if anim_player:
		anim_player.animation_finished.connect(_on_anim_player_finished)
	play_idle()

func freeze() -> void:
	if anim_player and anim_player.is_playing():
		anim_player.pause()

func unfreeze() -> void:
	if anim_player and not anim_player.is_playing():
		anim_player.play()

func _on_anim_player_finished(anim_name: String) -> void:
	if anim_name == combat_idle_animation or anim_name == idle_animation:
		return
	if _is_dead:
		return
	emit_signal("animation_finished")
	if anim_name != death_animation:
		if _in_battle:
			play_combat_idle()
		else:
			play_idle()

func enter_battle() -> void:
	_in_battle = true
	play_combat_idle()

func play_idle() -> void:
	if not anim_player or not anim_player.has_animation(idle_animation):
		return
	_skipping = false
	anim_player.speed_scale = 1.0
	if anim_player.current_animation != idle_animation:
		anim_player.play(idle_animation, blend_to_idle)

func play_combat_idle() -> void:
	if _is_dead:
		return
	var anim = combat_idle_animation
	if not anim_player:
		return
	if not anim_player.has_animation(anim):
		anim = idle_animation
	if not anim_player.has_animation(anim):
		return
	var animation = anim_player.get_animation(anim)
	if animation:
		animation.loop_mode = Animation.LOOP_LINEAR
	_skipping = false
	anim_player.speed_scale = 1.0
	if anim_player.current_animation != anim:
		anim_player.play(anim, blend_combat_idle)

func skip_animation() -> void:
	if _is_dead:
		return
	if anim_player and anim_player.is_playing():
		_skipping = true

func play_prepare(move_prepare_anim: String = "", speed_override: float = 1.0) -> void:
	var anim = move_prepare_anim if move_prepare_anim != "" else default_prepare_animation
	if anim == "" or not anim_player or not anim_player.has_animation(anim):
		play_combat_idle()
		return
	var animation = anim_player.get_animation(anim)
	if animation:
		animation.loop_mode = Animation.LOOP_LINEAR
	_skipping = false
	anim_player.speed_scale = speed_override
	anim_player.play(anim, blend_prepare)

func play_attack(anim_override: int = -1, anim_name_override: String = "", speed_override: float = 1.0) -> void:
	var anim_name: String = ""
	if anim_name_override != "":
		anim_name = anim_name_override
	elif anim_override >= 0 and anim_override < _active_attack_anims.size():
		anim_name = _active_attack_anims[anim_override].animation_name
	elif not _active_attack_anims.is_empty():
		anim_name = _pick_weighted_attack()

	if anim_name == "" or not anim_player or not anim_player.has_animation(anim_name):
		# No valid attack animation resolved. play_prepare() set the prepare
		# clip to LOOP_LINEAR, so if we just return here the enemy keeps looping
		# its prepare pose forever and anything waiting on _any_anim_playing()
		# (BattleUI's enemy-turn wait AND its post-battle/defeat wait) hangs the
		# whole battle. Always settle back to combat idle first. This mirrors how
		# play_miss() already handles its own missing-animation case.
		play_combat_idle()
		emit_signal("animation_finished")
		return

	_skipping = false
	anim_player.speed_scale = speed_override
	anim_player.play(anim_name, blend_attack)

	while anim_player.is_playing() and not _skipping:
		await get_tree().process_frame

	_skipping = false
	anim_player.speed_scale = 1.0
	play_combat_idle()
	emit_signal("animation_finished")

func play_miss(move_miss_anim: String = "", speed_override: float = 1.0) -> void:
	var anim = move_miss_anim if move_miss_anim != "" else default_miss_animation
	if anim == "" or not anim_player or not anim_player.has_animation(anim):
		play_combat_idle()
		return
	_skipping = false
	anim_player.speed_scale = speed_override
	anim_player.play(anim, blend_miss)
	while anim_player.is_playing() and not _skipping:
		await get_tree().process_frame
	_skipping = false
	anim_player.speed_scale = 1.0
	play_combat_idle()

func play_hurt() -> void:
	if not anim_player or not anim_player.has_animation(hurt_animation):
		emit_signal("animation_finished")
		return
	_skipping = false
	anim_player.speed_scale = 1.0
	anim_player.play(hurt_animation, blend_hurt)
	while anim_player.is_playing() and not _skipping:
		await get_tree().process_frame
	_skipping = false
	anim_player.speed_scale = 1.0
	play_combat_idle()
	emit_signal("animation_finished")

func play_death() -> void:
	if not anim_player or not anim_player.has_animation(death_animation):
		queue_free()
		return
	_is_dead = true
	_skipping = false
	anim_player.speed_scale = 1.0
	anim_player.play(death_animation, blend_death)
	while anim_player.is_playing():
		await get_tree().process_frame
	await get_tree().create_timer(0.3).timeout
	queue_free()

func check_phase(current_hp: int, max_hp: int) -> bool:
	if _sorted_phases.is_empty():
		return false
	var hp_ratio = float(current_hp) / float(max_hp)
	var new_phase = -1
	for i in range(_sorted_phases.size()):
		if hp_ratio <= _sorted_phases[i].hp_threshold:
			new_phase = i
		else:
			break
	if new_phase != _active_phase:
		_active_phase = new_phase
		if new_phase >= 0 and not _sorted_phases[new_phase].attack_anims.is_empty():
			_active_attack_anims = _sorted_phases[new_phase].attack_anims.duplicate()
		else:
			_active_attack_anims = attack_anims.duplicate()
		return true
	return false

func _pick_weighted_attack() -> String:
	var total: float = 0.0
	for entry in _active_attack_anims:
		total += entry.weight
	var roll = randf() * total
	var running: float = 0.0
	for entry in _active_attack_anims:
		running += entry.weight
		if roll <= running:
			return entry.animation_name
	if _active_attack_anims.is_empty():
		return ""
	return _active_attack_anims[_active_attack_anims.size() - 1].animation_name
