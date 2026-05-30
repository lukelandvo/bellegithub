# BattleManager.gd
# Pure logic — no awaits. BattleUI drives all progression.
# Attach to a node in battle.tscn.
#
# Turn flow:
#   1. BattleUI collects one queued action from every living party member.
#   2. BattleManager.build_round_queue() merges party actions + enemy actions,
#      sorted by speed descending (ties go to party members, then lower slot index).
#   3. BattleUI executes each entry in the queue in order.
#   4. Repeat until win/lose/flee.
#
# v4.5: do_attack() uses member.get_effective_offense()
#        queue_party_action() uses member.get_effective_speed()
# v4.6: Enemy debuffs now write to member._temp_*_penalty instead of base stats.
#        clear_battle_penalties() called on all party members at end of every battle.
#        do_action() checks target existence before spending PP on DAMAGE moves.

extends Node

enum BattleState { INTRO, COLLECTING, RESOLVING, WIN, LOSE, FLED }
enum ActionType { FIGHT, PSI, ITEM, FLEE }

@export_group("Spawning")
@export var enemy_spacing: float = 2.0

@export_group("Background")
@export var default_background: PackedScene

@export_group("Debug")
@export var debug_full_heal: bool = false

var state: BattleState = BattleState.INTRO

var party: Array = []
var party_alive: Array = []

var enemies: Array = []
var enemy_instances: Array = []
var enemy_anims: Array = []
var enemy_alive: Array = []
var _move_cooldown_counters: Array = []
var _turn_count: int = 0

var _queued_actions: Array = []

@export var spawn_root: Node

signal hp_updated(member_index: int, current_hp: int, max_hp: int)
signal battle_finished
signal pp_updated(member_index: int, current_pp: int, max_pp: int)
signal enemy_hp_updated(enemy_index: int, current_hp: int, max_hp: int, display_name: String)

func _ready() -> void:
	add_to_group("battle_manager")

	var encounter = BattleSession.consume()
	if not encounter:
		push_error("BattleManager: no encounter — BattleSession.confirmed_encounter was null")
		return

	if debug_full_heal:
		for member in BattleSession.active_party:
			member.full_restore()

	party = BattleSession.active_party.duplicate()
	for member in party:
		party_alive.append(member.is_alive())

	var bg_scene: PackedScene = null
	if encounter.battle_background:
		bg_scene = encounter.battle_background
	elif default_background:
		bg_scene = default_background
	if bg_scene:
		spawn_root.add_child(bg_scene.instantiate())

	var roster = encounter.pick_roster()
	if roster:
		enemies = roster.enemies.duplicate()

	if enemies.is_empty():
		push_error("BattleManager: no enemies in roster — check encounter setup")
		return

	var track: AudioStream = BattleSession.pending_music
	if not track:
		track = encounter.battle_music
	BattleSession.pending_music = null
	if track:
		AudioManager.play_music_stream(track)
	else:
		AudioManager.play_music("battle_default")

	for i in range(enemies.size()):
		enemies[i] = enemies[i].duplicate()
		enemies[i].stats = enemies[i].stats.duplicate(true)

	var original_names: Array = []
	for slot in enemies:
		original_names.append(slot.display_name if slot.display_name != "" else slot.stats.enemy_name)

	var name_counts: Dictionary = {}
	for base in original_names:
		name_counts[base] = name_counts.get(base, 0) + 1

	var name_seen: Dictionary = {}
	for i in range(enemies.size()):
		var base = original_names[i]
		if name_counts.get(base, 0) > 1:
			var idx = name_seen.get(base, 0)
			enemies[i].display_name = "%s %s" % [base, char(65 + idx)]
			name_seen[base] = idx + 1
		elif enemies[i].display_name == "":
			enemies[i].display_name = base

	var center_node = spawn_root.find_child("EnemySpawnCenter", true, false)
	var center_pos: Vector3 = center_node.global_position if center_node else Vector3.ZERO
	var count = enemies.size()

	for i in range(count):
		var slot = enemies[i]
		var offset = (i - (count - 1) / 2.0) * enemy_spacing
		var spawn_pos = center_pos + Vector3(offset, 0.0, 0.0)

		var instance: Node3D = null
		if slot.scene:
			instance = slot.scene.instantiate()
			spawn_root.add_child(instance)
			instance.global_position = spawn_pos

		enemy_instances.append(instance)
		enemy_alive.append(true)

		var anim_node = null
		if instance and instance.has_method("play_idle"):
			anim_node = instance
			if anim_node.has_method("enter_battle"):
				anim_node.enter_battle()
		enemy_anims.append(anim_node)

		var counters: Array = []
		if slot.stats:
			for move in slot.stats.moves:
				counters.append(move.cooldown_turns)
		_move_cooldown_counters.append(counters)

func get_intro_message() -> String:
	if enemies.is_empty():
		return "An enemy appears!"
	if enemies.size() == 1:
		return "You encounter the %s!" % enemies[0].display_name
	var names: Array = enemies.map(func(s): return s.display_name)
	if names.size() == 2:
		return "You encounter %s and %s!" % [names[0], names[1]]
	var all_but_last = names.slice(0, names.size() - 1)
	return "You encounter %s, and %s!" % [", ".join(all_but_last), names[names.size() - 1]]

func queue_party_action(member_index: int, type: int, target: int, move = null, item = null) -> void:
	_queued_actions.append({
		"actor": "party",
		"index": member_index,
		"type": type,
		"target": target,
		"move": move,
		"item": item,
		"speed": party[member_index].get_effective_speed()
	})

func _queue_enemy_actions() -> void:
	_turn_count += 1
	for i in range(enemies.size()):
		if not enemy_alive[i]:
			continue
		_tick_cooldowns(i)
		var move = _pick_enemy_move(i)
		var target = pick_enemy_target()
		_queued_actions.append({
			"actor": "enemy",
			"index": i,
			"type": ActionType.FIGHT,
			"target": target,
			"move": move,
			"item": null,
			"speed": enemies[i].stats.speed
		})

func build_round_queue() -> Array:
	_queue_enemy_actions()
	_queued_actions.sort_custom(func(a, b):
		if a["speed"] != b["speed"]:
			return a["speed"] > b["speed"]
		if a["actor"] != b["actor"]:
			return a["actor"] == "party"
		if a["actor"] == "party":
			return a["index"] < b["index"]
		return a["index"] < b["index"]
	)
	var queue = _queued_actions.duplicate()
	_queued_actions.clear()
	return queue

func get_living_enemies() -> Array:
	var result = []
	for i in range(enemies.size()):
		if enemy_alive[i]:
			result.append({ "index": i, "display_name": enemies[i].display_name })
	return result

func get_living_party() -> Array:
	var result = []
	for i in range(party.size()):
		if party_alive[i]:
			result.append({ "index": i, "name": party[i].character_name })
	return result

func get_attack_announce(member_index: int, target_index: int) -> String:
	return "%s attacks %s!" % [party[member_index].character_name, enemies[target_index].display_name]

func do_attack(member_index: int, target_index: int) -> Dictionary:
	var actual_target = _resolve_enemy_target(target_index)
	if actual_target == -1:
		return {
			"message": "No targets remain.",
			"anim": "", "anim_override": -1, "enemy_index": -1,
			"member_index": member_index, "hit": false, "skipped": true
		}

	var member = party[member_index]
	var hit = randf() < 0.8
	if not hit:
		return {
			"message": "%s missed!" % member.character_name,
			"anim": "", "anim_override": -1, "enemy_index": actual_target,
			"member_index": member_index, "hit": false
		}

	var stats = enemies[actual_target].stats
	var damage = stats.take_damage(member.get_effective_offense())
	_check_enemy_phase(actual_target)
	_emit_enemy_hp(actual_target)

	if stats.current_hp <= 0:
		enemy_alive[actual_target] = false
		_start_death_fade(actual_target)
		if _all_enemies_dead():
			state = BattleState.WIN
		return {
			"message": "You dealt %d damage!" % damage,
			"anim": "death", "anim_override": -1,
			"enemy_index": actual_target, "member_index": member_index,
			"death_message": "%s has been defeated!" % enemies[actual_target].display_name,
			"hit": true
		}

	return {
		"message": "You dealt %d damage!" % damage,
		"anim": "hurt", "anim_override": -1,
		"enemy_index": actual_target, "member_index": member_index,
		"hit": true
	}

func do_action(member_index: int, move: ActionMove, target_index: int) -> Dictionary:
	var member = party[member_index]

	# For damage moves, verify a target exists BEFORE spending PP.
	var actual_damage_target: int = -1
	if move.effect_type == ActionMove.EffectType.DAMAGE:
		actual_damage_target = _resolve_enemy_target(target_index)
		if actual_damage_target == -1:
			return {
				"message": "No targets remain.",
				"anim": "", "anim_override": -1, "enemy_index": -1,
				"member_index": member_index, "skipped": true
			}

	if not member.use_pp(move.pp_cost):
		return {
			"message": "Not enough PP!",
			"anim": "", "anim_override": -1, "enemy_index": -1, "member_index": member_index
		}
	_emit_pp(member_index)

	var roll = randi_range(-move.variance, move.variance)
	var result_message: String
	var anim: String = ""
	var anim_enemy: int = -1

	match move.effect_type:
		ActionMove.EffectType.DAMAGE:
			anim_enemy = actual_damage_target
			var stats = enemies[actual_damage_target].stats
			var power = maxi(1, move.power + roll - stats.defense)
			stats.current_hp -= power
			stats.current_hp = maxi(0, stats.current_hp)
			_check_enemy_phase(actual_damage_target)
			_emit_enemy_hp(actual_damage_target)
			result_message = "%s dealt %d damage!" % [move.move_name, power]
			if stats.current_hp <= 0:
				enemy_alive[actual_damage_target] = false
				_start_death_fade(actual_damage_target)
				if _all_enemies_dead():
					state = BattleState.WIN
				return {
					"message": result_message,
					"anim": "death", "anim_override": -1,
					"enemy_index": anim_enemy, "member_index": member_index,
					"death_message": "%s has been defeated!" % enemies[actual_damage_target].display_name
				}
			anim = "hurt"

		ActionMove.EffectType.HEAL:
			var target = party[target_index] if target_index >= 0 and target_index < party.size() else member
			var actual_target_index = target_index if target_index >= 0 and target_index < party.size() else member_index
			var amount = target.heal(move.power + roll)
			_emit_hp(actual_target_index)
			result_message = "%s restored %d HP to %s!" % [move.move_name, amount, target.character_name]

		ActionMove.EffectType.RESTORE_PP:
			var target = party[target_index] if target_index >= 0 and target_index < party.size() else member
			var actual_target_index = target_index if target_index >= 0 and target_index < party.size() else member_index
			var amount = target.restore_pp(move.power + roll)
			_emit_pp(actual_target_index)
			result_message = "%s restored %d PP to %s!" % [move.move_name, amount, target.character_name]

	return {
		"message": result_message,
		"anim": anim, "anim_override": -1,
		"enemy_index": anim_enemy, "member_index": member_index
	}

func do_item(member_index: int, item: ItemData, target_index: int) -> Dictionary:
	var target = party[target_index]
	var result_message: String

	match item.effect_type:
		ItemData.EffectType.HEAL_HP:
			if target.current_hp >= target.max_hp:
				result_message = "%s's HP is already full!" % target.character_name
			else:
				var amount = target.heal(item.power)
				_emit_hp(target_index)
				result_message = "%s recovered %d HP!" % [target.character_name, amount]

		ItemData.EffectType.RESTORE_PP:
			if target.current_pp >= target.max_pp:
				result_message = "%s's PP is already full!" % target.character_name
			else:
				var amount = target.restore_pp(item.power)
				_emit_pp(target_index)
				result_message = "%s recovered %d PP!" % [target.character_name, amount]

		_:
			result_message = "Nothing happened."

	SaveManager.remove_item(item.item_id)

	return {
		"message": result_message,
		"anim": "", "anim_override": -1, "enemy_index": -1, "member_index": member_index
	}

func do_flee() -> Dictionary:
	if randf() < 0.7:
		state = BattleState.FLED
		for member in party:
			member.clear_battle_penalties()
		return { "fled": true, "message": "Got away safely!" }
	return { "fled": false, "message": "Couldn't escape!" }

func get_enemy_announce(enemy_index: int) -> Dictionary:
	var slot = enemies[enemy_index]
	var move = _queued_enemy_move(enemy_index)
	var message: String
	if move == null:
		message = "%s attacks!" % slot.display_name
	else:
		message = move.use_message.replace("{enemy}", slot.display_name)
	return {
		"message": message,
		"move": move,
		"anim_override": move.anim_override if move else -1,
		"attack_animation_name": move.attack_animation_name if move else "",
		"prepare_animation_name": move.prepare_animation_name if move else "",
		"miss_animation_name": move.miss_animation_name if move else "",
		"animation_speed": move.animation_speed if move else 1.0,
		"prepare_speed": move.prepare_speed if move else 1.0,
		"miss_speed": move.miss_speed if move else 1.0,
		"attack_sound": move.attack_sound if move else null,
		"hit_sound": move.hit_sound if move else null,
		"enemy_index": enemy_index
	}

func do_enemy_turn(enemy_index: int, move, target_member_index: int) -> Dictionary:
	var slot = enemies[enemy_index]
	var stats = slot.stats
	var member = party[target_member_index]
	var hit = randf() < 0.8

	if not hit:
		return {
			"message": "%s missed!" % slot.display_name,
			"anim": "", "anim_override": move.anim_override if move else -1,
			"enemy_index": enemy_index, "member_index": target_member_index,
			"hit": false, "hit_sound": null
		}

	var message: String
	if move == null:
		var damage = member.take_damage(stats.offense)
		_emit_hp(target_member_index)
		message = "%s takes %d damage!" % [member.character_name, damage]
	else:
		var roll = randi_range(-move.variance, move.variance)
		match move.effect_type:
			EnemyMove.EffectType.ATTACK:
				var damage = member.take_damage(stats.offense + roll)
				_emit_hp(target_member_index)
				message = "%s takes %d damage!" % [member.character_name, damage]
			EnemyMove.EffectType.DAMAGE_FLAT:
				var damage = maxi(1, move.power + roll)
				member.current_hp -= damage
				member.current_hp = maxi(0, member.current_hp)
				_emit_hp(target_member_index)
				message = "%s takes %d damage!" % [member.character_name, damage]
			EnemyMove.EffectType.HEAL_SELF:
				var heal_amount = move.power + roll
				stats.current_hp = mini(stats.current_hp + heal_amount, stats.max_hp)
				_emit_enemy_hp(enemy_index)
				message = "%s recovered %d HP!" % [slot.display_name, heal_amount]
			EnemyMove.EffectType.HEAL_ALLY:
				var living_allies = []
				for i in range(enemies.size()):
					if enemy_alive[i] and i != enemy_index:
						living_allies.append(i)
				if living_allies.is_empty():
					var heal_amount = move.power + roll
					stats.current_hp = mini(stats.current_hp + heal_amount, stats.max_hp)
					_emit_enemy_hp(enemy_index)
					message = "%s recovered %d HP!" % [slot.display_name, heal_amount]
				else:
					var target_i = living_allies[randi() % living_allies.size()]
					var ally_stats = enemies[target_i].stats
					var heal_amount = move.power + roll
					ally_stats.current_hp = mini(ally_stats.current_hp + heal_amount, ally_stats.max_hp)
					_emit_enemy_hp(target_i)
					message = "%s healed %s for %d HP!" % [slot.display_name, enemies[target_i].display_name, heal_amount]
			EnemyMove.EffectType.TAUNT:
				message = move.use_message.replace("{enemy}", slot.display_name)
			EnemyMove.EffectType.LOWER_OFFENSE:
				var amount = maxi(1, move.power + roll)
				member._temp_offense_penalty += amount
				message = move.result_message if move.result_message != "" else \
					"%s's offense went down by %d!" % [member.character_name, amount]
				message = message.replace("{enemy}", slot.display_name).replace("{player}", member.character_name).replace("{amount}", str(amount))
			EnemyMove.EffectType.LOWER_DEFENSE:
				var amount = maxi(1, move.power + roll)
				member._temp_defense_penalty += amount
				message = move.result_message if move.result_message != "" else \
					"%s's defense went down by %d!" % [member.character_name, amount]
				message = message.replace("{enemy}", slot.display_name).replace("{player}", member.character_name).replace("{amount}", str(amount))
			EnemyMove.EffectType.LOWER_SPEED:
				var amount = maxi(1, move.power + roll)
				member._temp_speed_penalty += amount
				message = move.result_message if move.result_message != "" else \
					"%s's speed went down by %d!" % [member.character_name, amount]
				message = message.replace("{enemy}", slot.display_name).replace("{player}", member.character_name).replace("{amount}", str(amount))
			EnemyMove.EffectType.LOWER_GUTS:
				var amount = maxi(1, move.power + roll)
				member._temp_guts_penalty += amount
				message = move.result_message if move.result_message != "" else \
					"%s's guts went down by %d!" % [member.character_name, amount]
				message = message.replace("{enemy}", slot.display_name).replace("{player}", member.character_name).replace("{amount}", str(amount))
			_:
				message = "%s does something!" % slot.display_name

	if member.current_hp <= 0:
		party_alive[target_member_index] = false
		_emit_hp(target_member_index)
		if _all_party_ko():
			state = BattleState.LOSE

	return {
		"message": message,
		"anim": "attack",
		"anim_override": move.anim_override if move else -1,
		"attack_animation_name": move.attack_animation_name if move else "",
		"enemy_index": enemy_index,
		"member_index": target_member_index,
		"hit": true,
		"hit_sound": move.hit_sound if move else null
	}

func pick_enemy_target() -> int:
	var living = []
	for i in range(party.size()):
		if party_alive[i]:
			living.append(i)
	if living.is_empty():
		return 0
	return living[randi() % living.size()]

func _resolve_enemy_target(target_index: int) -> int:
	if enemy_alive[target_index]:
		return target_index
	for i in range(enemies.size()):
		if enemy_alive[i]:
			return i
	return -1

func get_win_messages() -> Array:
	var total_exp = 0
	var total_money = 0
	for slot in enemies:
		total_exp += slot.stats.experience_reward
		total_money += slot.stats.money_reward
		if slot.victory_flag != "":
			FlagService.set_flag(slot.victory_flag)

	var leveled_up_names: Array = []
	var unlocked_moves: Dictionary = {}
	for member in party:
		member.clear_battle_penalties()
		var levels = member.add_experience(total_exp)
		if levels > 0:
			leveled_up_names.append(member.character_name)
		if not member.newly_unlocked_moves.is_empty():
			unlocked_moves[member.character_name] = member.newly_unlocked_moves.duplicate()

	AudioManager.play_music("victory")

	var messages: Array = []
	messages.append("You win!")
	messages.append("Gained %d EXP!" % total_exp)
	for member_name in leveled_up_names:
		messages.append("%s leveled up!" % member_name)
		if unlocked_moves.has(member_name):
			for move_name in unlocked_moves[member_name]:
				messages.append("%s learned %s!" % [member_name, move_name])
	if total_money > 0:
		messages.append("Got $%d!" % total_money)
	return messages

func get_lose_messages() -> Array:
	for member in party:
		member.clear_battle_penalties()
	return ["You were defeated..."]

func _return_to_world() -> void:
	emit_signal("battle_finished")

func _all_enemies_dead() -> bool:
	return enemy_alive.all(func(a): return not a)

func _all_party_ko() -> bool:
	return party_alive.all(func(a): return not a)

func _start_death_fade(enemy_index: int) -> void:
	var anim_node = enemy_anims[enemy_index]
	if anim_node:
		if anim_node.death_sound:
			AudioManager.play_sfx("enemy_death")
		if anim_node.has_method("play_death"):
			anim_node.play_death()

func _check_enemy_phase(enemy_index: int) -> void:
	var anim = enemy_anims[enemy_index]
	if anim and anim.has_method("check_phase"):
		var stats = enemies[enemy_index].stats
		anim.check_phase(stats.current_hp, stats.max_hp)

func _pick_enemy_move(enemy_index: int) -> EnemyMove:
	var moves = enemies[enemy_index].stats.moves
	if moves.is_empty():
		return null
	var counters = _move_cooldown_counters[enemy_index]
	var available: Array = []
	var available_indices: Array = []
	for i in range(moves.size()):
		if counters[i] <= 0:
			available.append(moves[i])
			available_indices.append(i)
	if available.is_empty():
		return null
	var total_weight: float = 0.0
	for move in available:
		total_weight += move.weight
	var roll = randf() * total_weight
	var running: float = 0.0
	for i in range(available.size()):
		running += available[i].weight
		if roll <= running:
			counters[available_indices[i]] = available[i].cooldown_turns
			return available[i]
	counters[available_indices[-1]] = available[-1].cooldown_turns
	return available[-1]

func _queued_enemy_move(enemy_index: int) -> EnemyMove:
	for entry in _queued_actions:
		if entry["actor"] == "enemy" and entry["index"] == enemy_index:
			return entry.get("move", null)
	return null

func _tick_cooldowns(enemy_index: int) -> void:
	var counters = _move_cooldown_counters[enemy_index]
	for i in range(counters.size()):
		if counters[i] > 0:
			counters[i] -= 1

func _emit_hp(member_index: int) -> void:
	var member = party[member_index]
	emit_signal("hp_updated", member_index, member.current_hp, member.max_hp)

func _emit_pp(member_index: int) -> void:
	var member = party[member_index]
	emit_signal("pp_updated", member_index, member.current_pp, member.max_pp)

func _emit_enemy_hp(index: int) -> void:
	var stats = enemies[index].stats
	emit_signal("enemy_hp_updated", index, stats.current_hp, stats.max_hp, enemies[index].display_name)
