# BattleUI.gd
# Drives all combat progression. E advances everything.
# Attach to a CanvasLayer node in battle.tscn.
#
# New turn flow:
#   INTRO -> COLLECTING (get action from each living party member)
#         -> RESOLVING (execute queue in speed order)
#         -> back to COLLECTING for next round
#   Win/Lose/Flee ends the loop.

extends CanvasLayer

@export_group("Node References")
@export var message_label: Label
@export var action_menu: PanelContainer
@export var menu_container: VBoxContainer

@export_group("Status Boxes")
@export var status_boxes: Array[Control] = []

@export_group("Typewriter")
@export var typewrite_speed: float = 0.03
@export var cursor_character: String = ">"
@export var wait_character: String = "*"

@export_group("Menu")
@export var menu_selector: String = ">"
@export var menu_font_size: int = 16
@export var menu_item_height: int = 28
@export var menu_item_width: int = 150
@export var menu_normal_color: Color = Color.WHITE
@export var menu_selected_color: Color = Color.YELLOW

@export_group("Victory")
@export var victory_music_seek: float = 4.5

@export_group("Game Over")
@export var game_over_scene: PackedScene

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

enum UIState {
	INTRO,
	COLLECTING,          # gathering party actions
	WAITING_FOR_E,       # executing queue, waiting for E to advance
	SUBMENU_TARGET,
	SUBMENU_ACTION,
	SUBMENU_ACTION_TARGET,
	SUBMENU_ACTION_PARTY_TARGET,  # for HEAL and RESTORE_PP targeting a party member
	SUBMENU_ITEMS,
	SUBMENU_ITEM_TARGET,
	POST_BATTLE,
	DONE
}

var ui_state: UIState = UIState.INTRO
var post_battle_queue: Array = []
var is_typing: bool = false
var skip_typing: bool = false
var selected_index: int = 0

var _main_labels: Array[String] = ["Fight", "Action", "Items", "Run"]
var _current_labels: Array[String] = []
var _menu_buttons: Array[Button] = []

var _pending_action_move = null   # ActionMove
var _pending_item: ItemData = null
var _current_member_index: int = 0
var _e_cooldown: bool = false
var _victory_seeked: bool = false

# Collected party actions for this round — Array of Dictionaries
# Each: { "member_index", "type", "target", "move", "item" }
var _collected_actions: Array = []
var _collection_order: Array = []   # living party indices in slot order
var _collection_cursor: int = 0     # which member we're currently asking

# Execution queue for this round — sorted by speed
var _round_queue: Array = []
var _queue_cursor: int = 0

var battle_manager: Node

signal _e_pressed

# ---------------------------------------------------------------------------
# Ready
# ---------------------------------------------------------------------------

func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	battle_manager = get_tree().get_first_node_in_group("battle_manager")
	if not battle_manager:
		push_error("BattleUI: BattleManager not found")
		return

	battle_manager.hp_updated.connect(_on_hp_updated)
	battle_manager.pp_updated.connect(_on_pp_updated)
	battle_manager.enemy_hp_updated.connect(_on_enemy_hp_updated)

	_hide_action_menu()
	_init_status_boxes()

	await get_tree().create_timer(0.1).timeout
	ui_state = UIState.INTRO
	await _typewrite(battle_manager.get_intro_message())

# ---------------------------------------------------------------------------
# Status boxes
# ---------------------------------------------------------------------------

func _init_status_boxes() -> void:
	for i in range(battle_manager.party.size()):
		if i >= status_boxes.size():
			break
		var box = status_boxes[i]
		if not box:
			continue
		var member = battle_manager.party[i]
		_set_label(box, "NameLabel", member.character_name)
		_set_label(box, "HPLabel", "HP %d / %d" % [member.current_hp, member.max_hp])
		_set_label(box, "PPLabel", "PP %d / %d" % [member.current_pp, member.max_pp])

func _set_label(box: Control, label_name: String, text: String) -> void:
	var label = box.find_child(label_name, true, false)
	if label and label is Label:
		label.text = text

# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("interact"):
		emit_signal("_e_pressed")

	var in_menu = ui_state in [
		UIState.COLLECTING, UIState.SUBMENU_TARGET,
		UIState.SUBMENU_ACTION, UIState.SUBMENU_ACTION_TARGET,
		UIState.SUBMENU_ACTION_PARTY_TARGET,
		UIState.SUBMENU_ITEMS, UIState.SUBMENU_ITEM_TARGET
	]

	if in_menu and not is_typing:
		if Input.is_action_just_pressed("move_forward"):
			selected_index = wrapi(selected_index - 1, 0, _current_labels.size())
			_update_menu_selection()
		elif Input.is_action_just_pressed("move_back"):
			selected_index = wrapi(selected_index + 1, 0, _current_labels.size())
			_update_menu_selection()

	if not Input.is_action_just_pressed("interact"):
		return
	if _e_cooldown:
		return
	_trigger_e_cooldown()

	match ui_state:
		UIState.INTRO:
			if is_typing: skip_typing = true
			else: _begin_collection_phase()

		UIState.COLLECTING:
			if not is_typing: _confirm_main_action()

		UIState.SUBMENU_TARGET:
			if not is_typing: _confirm_target_fight()

		UIState.SUBMENU_ACTION:
			if not is_typing: _confirm_action()

		UIState.SUBMENU_ACTION_TARGET:
			if not is_typing: _confirm_action_target()

		UIState.SUBMENU_ACTION_PARTY_TARGET:
			if not is_typing: _confirm_action_party_target()

		UIState.SUBMENU_ITEMS:
			if not is_typing: _confirm_item_selection()

		UIState.SUBMENU_ITEM_TARGET:
			if not is_typing: _confirm_item_target()

		UIState.WAITING_FOR_E:
			if is_typing: skip_typing = true
			elif _any_anim_playing(): _skip_enemy_anims()
			else: _advance_queue()

		UIState.POST_BATTLE:
			if is_typing:
				skip_typing = true
			elif post_battle_queue.size() > 0:
				await _typewrite(post_battle_queue.pop_front())
			else:
				ui_state = UIState.DONE
				if battle_manager.state == battle_manager.BattleState.LOSE:
					_show_game_over()
				else:
					battle_manager._return_to_world()

# ---------------------------------------------------------------------------
# Game over
# ---------------------------------------------------------------------------

func _show_game_over() -> void:
	if not game_over_scene:
		push_error("BattleUI: no game_over_scene assigned in inspector")
		return
	var go = game_over_scene.instantiate()
	get_tree().root.add_child(go)
	go.open()

# ---------------------------------------------------------------------------
# Collection phase — gather one action per living party member
# ---------------------------------------------------------------------------

func _begin_collection_phase() -> void:
	_collected_actions.clear()
	_collection_order.clear()
	_collection_cursor = 0

	for i in range(battle_manager.party.size()):
		if battle_manager.party_alive[i]:
			_collection_order.append(i)

	if _collection_order.is_empty():
		return

	_ask_member(_collection_order[0])

func _ask_member(member_index: int) -> void:
	_current_member_index = member_index
	_show_main_menu(member_index)

func _advance_collection() -> void:
	_collection_cursor += 1
	if _collection_cursor < _collection_order.size():
		_ask_member(_collection_order[_collection_cursor])
	else:
		# All party members have chosen — build and execute the round
		_commit_party_actions()
		_begin_resolution_phase()

func _commit_party_actions() -> void:
	for entry in _collected_actions:
		battle_manager.queue_party_action(
			entry["member_index"],
			entry["type"],
			entry["target"],
			entry.get("move", null),
			entry.get("item", null)
		)

func _show_main_menu(member_index: int) -> void:
	ui_state = UIState.COLLECTING
	selected_index = 0
	_current_labels = _main_labels.duplicate()
	_build_menu(_current_labels)
	_update_menu_selection()
	var member = battle_manager.party[member_index]
	_typewrite("What will %s do?" % member.character_name)

func _confirm_main_action() -> void:
	match selected_index:
		0: _open_target_submenu()
		1: _open_action_submenu()
		2: _open_items_submenu()
		3: _try_flee()

func _try_flee() -> void:
	_hide_action_menu()
	var result = battle_manager.do_flee()
	if result["fled"]:
		ui_state = UIState.WAITING_FOR_E
		await _typewrite(result["message"])
		ui_state = UIState.DONE
		battle_manager._return_to_world()
	else:
		# Failed flee — still uses this member's turn, skip rest of collection
		ui_state = UIState.WAITING_FOR_E
		await _typewrite(result["message"])
		_collected_actions.clear()
		_collection_cursor = _collection_order.size()  # skip remaining members
		_commit_party_actions()
		_begin_resolution_phase()

# ---------------------------------------------------------------------------
# Fight submenu
# ---------------------------------------------------------------------------

func _open_target_submenu() -> void:
	var living = battle_manager.get_living_enemies()
	if living.size() == 1:
		_record_fight(living[0]["index"])
		return
	ui_state = UIState.SUBMENU_TARGET
	selected_index = 0
	_current_labels = []
	for entry in living:
		var stats = battle_manager.enemies[entry["index"]].stats
		_current_labels.append("%s HP:%d" % [entry["display_name"], stats.current_hp])
	_current_labels.append("Back")
	_build_menu(_current_labels)
	_update_menu_selection()
	_typewrite("Who to attack?")

func _confirm_target_fight() -> void:
	var living = battle_manager.get_living_enemies()
	if selected_index >= living.size():
		_show_main_menu(_current_member_index)
		return
	_record_fight(living[selected_index]["index"])

func _record_fight(target_index: int) -> void:
	_collected_actions.append({
		"member_index": _current_member_index,
		"type": battle_manager.ActionType.FIGHT,
		"target": target_index,
		"move": null,
		"item": null
	})
	_hide_action_menu()
	_advance_collection()

# ---------------------------------------------------------------------------
# Action submenu
# ---------------------------------------------------------------------------

func _open_action_submenu() -> void:
	var member = battle_manager.party[_current_member_index]
	var moves = member.psi_moves
	if moves.is_empty():
		await _typewrite("%s doesn't know any actions!" % member.character_name)
		_show_main_menu(_current_member_index)
		return
	ui_state = UIState.SUBMENU_ACTION
	selected_index = 0
	_current_labels = []
	for move in moves:
		_current_labels.append("%s (%d PP)" % [move.move_name, move.pp_cost])
	_current_labels.append("Back")
	_build_menu(_current_labels)
	_update_menu_selection()
	_typewrite("Choose an action.")

func _confirm_action() -> void:
	var member = battle_manager.party[_current_member_index]
	var moves = member.psi_moves
	if selected_index >= moves.size():
		_show_main_menu(_current_member_index)
		return
	_pending_action_move = moves[selected_index]
	match _pending_action_move.effect_type:
		ActionMove.EffectType.DAMAGE:
			_open_action_target_submenu()
		ActionMove.EffectType.HEAL, ActionMove.EffectType.RESTORE_PP:
			_open_action_party_target_submenu()
		_:
			_record_action(-1)

func _open_action_party_target_submenu() -> void:
	ui_state = UIState.SUBMENU_ACTION_PARTY_TARGET
	selected_index = 0
	_current_labels = []
	for i in range(battle_manager.party.size()):
		if not battle_manager.party_alive[i]:
			continue
		var member = battle_manager.party[i]
		_current_labels.append("%s  HP %d/%d" % [member.character_name, member.current_hp, member.max_hp])
	_current_labels.append("Back")
	_build_menu(_current_labels)
	_update_menu_selection()
	_typewrite("Use on who?")

func _confirm_action_party_target() -> void:
	var living_indices: Array = []
	for i in range(battle_manager.party.size()):
		if battle_manager.party_alive[i]:
			living_indices.append(i)
	if selected_index >= living_indices.size():
		_open_action_submenu()
		return
	_record_action(living_indices[selected_index])

func _open_action_target_submenu() -> void:
	var living = battle_manager.get_living_enemies()
	if living.size() == 1:
		_record_action(living[0]["index"])
		return
	ui_state = UIState.SUBMENU_ACTION_TARGET
	selected_index = 0
	_current_labels = []
	for entry in living:
		var stats = battle_manager.enemies[entry["index"]].stats
		_current_labels.append("%s HP:%d" % [entry["display_name"], stats.current_hp])
	_current_labels.append("Back")
	_build_menu(_current_labels)
	_update_menu_selection()
	_typewrite("Who to target?")

func _confirm_action_target() -> void:
	var living = battle_manager.get_living_enemies()
	if selected_index >= living.size():
		_open_action_submenu()
		return
	_record_action(living[selected_index]["index"])

func _record_action(target_index: int) -> void:
	_collected_actions.append({
		"member_index": _current_member_index,
		"type": battle_manager.ActionType.PSI,
		"target": target_index,
		"move": _pending_action_move,
		"item": null
	})
	_hide_action_menu()
	_advance_collection()

# ---------------------------------------------------------------------------
# Items submenu
# ---------------------------------------------------------------------------

func _open_items_submenu() -> void:
	var items = SaveManager.get_inventory()
	if items.is_empty():
		await _typewrite("You have no items!")
		_show_main_menu(_current_member_index)
		return
	ui_state = UIState.SUBMENU_ITEMS
	selected_index = 0
	_current_labels = []
	for item_id in items:
		var qty = SaveManager.get_quantity(item_id)
		var display = ItemRegistry.get_display_name(item_id)
		_current_labels.append("%s x%d" % [display, qty])
	_current_labels.append("Back")
	_build_menu(_current_labels)
	_update_menu_selection()
	_typewrite("Choose an item.")

func _confirm_item_selection() -> void:
	var items = SaveManager.get_inventory()
	if selected_index >= items.size():
		_show_main_menu(_current_member_index)
		return
	var item_id = items[selected_index]
	_pending_item = ItemRegistry.get_item(item_id)
	if not _pending_item:
		await _typewrite("Unknown item.")
		_show_main_menu(_current_member_index)
		return
	_open_item_target_submenu()

func _open_item_target_submenu() -> void:
	ui_state = UIState.SUBMENU_ITEM_TARGET
	selected_index = 0
	_current_labels = []
	for i in range(battle_manager.party.size()):
		if not battle_manager.party_alive[i]:
			continue
		var member = battle_manager.party[i]
		_current_labels.append("%s  HP %d/%d" % [member.character_name, member.current_hp, member.max_hp])
	_current_labels.append("Back")
	_build_menu(_current_labels)
	_update_menu_selection()
	_typewrite("Use on who?")

func _confirm_item_target() -> void:
	var living_indices: Array = []
	for i in range(battle_manager.party.size()):
		if battle_manager.party_alive[i]:
			living_indices.append(i)
	if selected_index >= living_indices.size():
		_open_items_submenu()
		return
	_record_item(living_indices[selected_index])

func _record_item(target_index: int) -> void:
	_collected_actions.append({
		"member_index": _current_member_index,
		"type": battle_manager.ActionType.ITEM,
		"target": target_index,
		"move": null,
		"item": _pending_item
	})
	_hide_action_menu()
	_advance_collection()

# ---------------------------------------------------------------------------
# Resolution phase — execute queue in speed order
# ---------------------------------------------------------------------------

func _begin_resolution_phase() -> void:
	_round_queue = battle_manager.build_round_queue()
	_queue_cursor = 0
	ui_state = UIState.WAITING_FOR_E
	_advance_queue()

func _advance_queue() -> void:
	# Check win/lose before advancing
	if battle_manager.state == battle_manager.BattleState.WIN:
		_start_post_battle(true)
		return
	if battle_manager.state == battle_manager.BattleState.LOSE:
		_start_post_battle(false)
		return

	if _queue_cursor >= _round_queue.size():
		# Round over — start next collection phase
		_begin_collection_phase()
		return

	var entry = _round_queue[_queue_cursor]
	_queue_cursor += 1

	# Skip dead actors
	if entry["actor"] == "party":
		if not battle_manager.party_alive[entry["index"]]:
			_advance_queue()
			return
		await _execute_party_entry(entry)
	else:
		if not battle_manager.enemy_alive[entry["index"]]:
			_advance_queue()
			return
		await _execute_enemy_entry(entry)

func _execute_party_entry(entry: Dictionary) -> void:
	var member_index = entry["index"]
	var member = battle_manager.party[member_index]

	match entry["type"]:
		battle_manager.ActionType.FIGHT:
			var target_index = entry["target"]
			var announce = battle_manager.get_attack_announce(member_index, target_index)
			AudioManager.play_sfx("player_attack")
			var anim_node = battle_manager.enemy_anims[target_index] if target_index >= 0 else null
			if anim_node and anim_node.has_method("play_prepare"):
				anim_node.play_prepare("", 1.0)
			await _typewrite(announce)
			await _await_e_press()
			_trigger_e_cooldown()
			var result = battle_manager.do_attack(member_index, target_index)
			if result.get("skipped", false):
				await _typewrite(result["message"])
				return
			if result.get("hit", true) == false:
				AudioManager.play_sfx("player_miss")
			else:
				AudioManager.play_sfx("player_hit")
			_play_result_anim(result)
			await _typewrite(result["message"])
			if result.get("death_message", "") != "":
				await _typewrite(result["death_message"])

		battle_manager.ActionType.PSI:
			var move = entry["move"]
			var target_index = entry["target"]
			var announce = "%s uses %s!" % [member.character_name, move.move_name]
			if move.use_sound:
				AudioManager.play_sfx("action_use")
			await _typewrite(announce)
			await _await_e_press()
			_trigger_e_cooldown()
			# For damage moves, target_index is an enemy index.
			# For heal/restore_pp, target_index is a party member index.
			var result = battle_manager.do_action(member_index, move, target_index)
			if result.get("skipped", false):
				await _typewrite(result["message"])
				return
			_play_result_anim(result)
			await _typewrite(result["message"])
			if result.get("death_message", "") != "":
				await _typewrite(result["death_message"])

		battle_manager.ActionType.ITEM:
			var item = entry["item"]
			var target_index = entry["target"]
			var announce = "%s uses %s!" % [member.character_name, item.display_name]
			if item.use_sound:
				AudioManager.play_sfx("item_use")
			await _typewrite(announce)
			await _await_e_press()
			_trigger_e_cooldown()
			var result = battle_manager.do_item(member_index, item, target_index)
			await _typewrite(result["message"])

func _execute_enemy_entry(entry: Dictionary) -> void:
	var enemy_index = entry["index"]
	var announce = battle_manager.get_enemy_announce(enemy_index)
	var target_member = entry["target"]

	if announce.get("attack_sound"):
		AudioManager.play_sfx("enemy_attack")

	var anim_node = battle_manager.enemy_anims[enemy_index]
	if anim_node and anim_node.has_method("play_prepare"):
		anim_node.play_prepare(
			announce.get("prepare_animation_name", ""),
			announce.get("prepare_speed", 1.0)
		)

	await _typewrite(announce["message"])
	await _await_e_press()
	_trigger_e_cooldown()

	var result = battle_manager.do_enemy_turn(enemy_index, announce["move"], target_member)

	if result.get("hit", true) == false:
		AudioManager.play_sfx("player_miss")
		if anim_node and anim_node.has_method("play_miss"):
			anim_node.play_miss(
				announce.get("miss_animation_name", ""),
				announce.get("miss_speed", 1.0)
			)
	else:
		if result.get("hit_sound"):
			AudioManager.play_sfx("player_hit")
		result["animation_speed"] = announce.get("animation_speed", 1.0)
		_play_result_anim(result)

	await _typewrite(result["message"])
	while _any_anim_playing():
		await get_tree().process_frame

# ---------------------------------------------------------------------------
# Post battle
# ---------------------------------------------------------------------------

func _start_post_battle(won: bool) -> void:
	while _any_anim_playing():
		await get_tree().process_frame
	if won:
		post_battle_queue = battle_manager.get_win_messages()
	else:
		post_battle_queue = battle_manager.get_lose_messages()
	ui_state = UIState.POST_BATTLE
	await _typewrite(post_battle_queue.pop_front())

# ---------------------------------------------------------------------------
# Animation dispatch
# ---------------------------------------------------------------------------

func _play_result_anim(result: Dictionary) -> void:
	var enemy_index = result.get("enemy_index", -1)
	if enemy_index < 0:
		return
	var anim_node = battle_manager.enemy_anims[enemy_index]
	match result.get("anim", ""):
		"hurt":
			if anim_node: anim_node.play_hurt()
		"death":
			pass  # owned by BattleManager._start_death_fade()
		"attack":
			if anim_node:
				anim_node.play_attack(
					result.get("anim_override", -1),
					result.get("attack_animation_name", ""),
					result.get("animation_speed", 1.0)
				)

func _any_anim_playing() -> bool:
	for anim_node in battle_manager.enemy_anims:
		if not anim_node or anim_node.get("_is_dead"):
			continue
		if anim_node.anim_player and anim_node.anim_player.is_playing():
			var current = anim_node.anim_player.current_animation
			if current != anim_node.idle_animation and current != anim_node.combat_idle_animation:
				return true
	return false

func _skip_enemy_anims() -> void:
	for anim_node in battle_manager.enemy_anims:
		if anim_node and not anim_node.get("_is_dead") and anim_node.has_method("skip_animation"):
			anim_node.skip_animation()
	await get_tree().process_frame
	_advance_queue()

# ---------------------------------------------------------------------------
# Signal callbacks
# ---------------------------------------------------------------------------

func _on_hp_updated(member_index: int, current_hp: int, max_hp: int) -> void:
	if member_index >= status_boxes.size():
		return
	var box = status_boxes[member_index]
	if box:
		_set_label(box, "HPLabel", "HP %d / %d" % [current_hp, max_hp])

func _on_pp_updated(member_index: int, current_pp: int, max_pp: int) -> void:
	if member_index >= status_boxes.size():
		return
	var box = status_boxes[member_index]
	if box:
		_set_label(box, "PPLabel", "PP %d / %d" % [current_pp, max_pp])

func _on_enemy_hp_updated(_index: int, _current_hp: int, _max_hp: int, _display_name: String) -> void:
	pass

# ---------------------------------------------------------------------------
# Menu rendering
# ---------------------------------------------------------------------------

func _build_menu(labels: Array) -> void:
	for btn in _menu_buttons:
		btn.queue_free()
	_menu_buttons.clear()
	for label in labels:
		var btn = Button.new()
		btn.text = " " + label
		btn.focus_mode = Control.FOCUS_NONE
		btn.flat = true
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(menu_item_width, menu_item_height)
		btn.add_theme_font_size_override("font_size", menu_font_size)
		btn.add_theme_color_override("font_color", menu_normal_color)
		btn.add_theme_color_override("font_hover_color", menu_normal_color)
		btn.add_theme_color_override("font_pressed_color", menu_normal_color)
		btn.add_theme_color_override("font_focus_color", menu_normal_color)
		menu_container.add_child(btn)
		_menu_buttons.append(btn)
	action_menu.visible = true

func _update_menu_selection() -> void:
	for i in range(_menu_buttons.size()):
		var is_selected = i == selected_index
		_menu_buttons[i].text = (menu_selector + " " if is_selected else "  ") + _current_labels[i]
		_menu_buttons[i].add_theme_color_override("font_color",
			menu_selected_color if is_selected else menu_normal_color)

func _hide_action_menu() -> void:
	action_menu.visible = false
	for btn in _menu_buttons:
		btn.queue_free()
	_menu_buttons.clear()

# ---------------------------------------------------------------------------
# E press
# ---------------------------------------------------------------------------

func _await_e_press() -> void:
	await _e_pressed

func _trigger_e_cooldown() -> void:
	_e_cooldown = true
	await get_tree().create_timer(0.2).timeout
	_e_cooldown = false

# ---------------------------------------------------------------------------
# Typewriter
# ---------------------------------------------------------------------------

func _typewrite(text: String) -> void:
	is_typing = true
	skip_typing = false
	message_label.text = cursor_character + " "
	for i in range(text.length()):
		if skip_typing:
			break
		message_label.text += text[i]
		if text[i] != " ":
			AudioManager.play_sfx("dialogue_bloop")
		await get_tree().create_timer(typewrite_speed).timeout
	message_label.text = cursor_character + " " + text + " " + wait_character + " "
	is_typing = false
