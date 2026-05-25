# BattleUI.gd
# Drives all combat progression. E advances everything.
# Attach to a CanvasLayer node in battle.tscn.
#
# Turn flow:
#   INTRO -> each party member acts -> each enemy acts -> repeat
#   Win/Lose/Flee ends the loop and returns to world.
#
# Signal-based E press — no busy-wait polling.

extends CanvasLayer

# ---------------------------------------------------------------------------
# Node references — wire in inspector
# ---------------------------------------------------------------------------

@export_group("Node References")
@export var message_label: Label
@export var action_menu: PanelContainer
@export var menu_container: VBoxContainer

# ---------------------------------------------------------------------------
# Per-party-member status boxes
# Wire up to 4 status box containers. Leave extras blank for single-member party.
# Each status box should have: NameLabel, HPLabel, PPLabel as children.
# ---------------------------------------------------------------------------

@export_group("Status Boxes")
@export var status_boxes: Array[Control] = []

# ---------------------------------------------------------------------------
# Inspector — typewriter
# ---------------------------------------------------------------------------

@export_group("Typewriter")
@export var typewrite_speed: float = 0.03
@export var cursor_character: String = ">"
@export var wait_character: String = "*"

# ---------------------------------------------------------------------------
# Inspector — menu
# ---------------------------------------------------------------------------

@export_group("Menu")
@export var menu_selector: String = ">"
@export var menu_font_size: int = 16
@export var menu_item_height: int = 28
@export var menu_item_width: int = 150
@export var menu_normal_color: Color = Color.WHITE
@export var menu_selected_color: Color = Color.YELLOW

# ---------------------------------------------------------------------------
# Inspector — victory
# ---------------------------------------------------------------------------

@export_group("Victory")
@export var victory_music_seek: float = 4.5

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

enum UIState {
	INTRO,
	WAITING_FOR_E,
	PARTY_TURN,
	SUBMENU_TARGET,
	SUBMENU_ACTION,
	SUBMENU_ACTION_TARGET,
	SUBMENU_ITEMS,
	POST_BATTLE,
	DONE
}

var ui_state: UIState = UIState.INTRO
var pending_next: String = ""
var post_battle_queue: Array = []
var is_typing: bool = false
var skip_typing: bool = false
var selected_index: int = 0

var _main_labels: Array[String] = ["Fight", "Action", "Items", "Run"]
var _current_labels: Array[String] = []
var _menu_buttons: Array[Button] = []

var _pending_action_move = null   # ActionMove resource
var _current_member_index: int = 0
var _e_cooldown: bool = false
var _victory_seeked: bool = false

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
# Status box initialization
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
		UIState.PARTY_TURN, UIState.SUBMENU_TARGET,
		UIState.SUBMENU_ACTION, UIState.SUBMENU_ACTION_TARGET,
		UIState.SUBMENU_ITEMS
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
			else:
				_begin_party_turn(0)

		UIState.PARTY_TURN:
			if not is_typing: _confirm_main_action()

		UIState.SUBMENU_TARGET:
			if not is_typing: _confirm_target_fight()

		UIState.SUBMENU_ACTION:
			if not is_typing: _confirm_action()

		UIState.SUBMENU_ACTION_TARGET:
			if not is_typing: _confirm_action_target()

		UIState.SUBMENU_ITEMS:
			if not is_typing: _confirm_item_action()

		UIState.WAITING_FOR_E:
			if is_typing: skip_typing = true
			elif _any_anim_playing(): _skip_enemy_anims()
			else: _handle_next()

		UIState.POST_BATTLE:
			if is_typing:
				skip_typing = true
			elif post_battle_queue.size() > 0:
				if not _victory_seeked:
					_victory_seeked = true
				await _typewrite(post_battle_queue.pop_front())
			else:
				ui_state = UIState.DONE
				battle_manager._return_to_world()

# ---------------------------------------------------------------------------
# Party turn
# ---------------------------------------------------------------------------

func _begin_party_turn(member_index: int) -> void:
	_current_member_index = member_index
	# Skip KO'd members
	if not battle_manager.party_alive[member_index]:
		var next = _find_next_party_member(member_index)
		if next == -1:
			# All party KO'd — shouldn't happen here but guard anyway
			return
		_begin_party_turn(next)
		return
	battle_manager.start_party_turn(member_index)
	_show_main_menu(member_index)

func _find_next_party_member(after: int) -> int:
	for i in range(after + 1, battle_manager.party.size()):
		if battle_manager.party_alive[i]:
			return i
	return -1

func _show_main_menu(member_index: int) -> void:
	ui_state = UIState.PARTY_TURN
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
		3:
			_hide_action_menu()
			ui_state = UIState.WAITING_FOR_E
			var result = battle_manager.do_flee(_current_member_index)
			pending_next = result["next"]
			await _typewrite(result["message"])
			if result["next"] == "fled":
				ui_state = UIState.DONE
				battle_manager._return_to_world()

# ---------------------------------------------------------------------------
# Fight submenu
# ---------------------------------------------------------------------------

func _open_target_submenu() -> void:
	var living = battle_manager.get_living_enemies()
	if living.size() == 1:
		_execute_fight(living[0]["index"])
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
	_execute_fight(living[selected_index]["index"])

func _execute_fight(target_index: int) -> void:
	_hide_action_menu()
	ui_state = UIState.WAITING_FOR_E
	var announce = battle_manager.get_attack_announce(_current_member_index, target_index)
	AudioManager.play_sfx("player_attack")

	var anim_node = battle_manager.enemy_anims[target_index]
	if anim_node and anim_node.has_method("play_prepare"):
		anim_node.play_prepare("", 1.0)

	await _typewrite(announce)
	await _await_e_press()
	_trigger_e_cooldown()

	var result = battle_manager.do_attack(_current_member_index, target_index)
	if result.get("hit", true) == false:
		AudioManager.play_sfx("player_miss")
	else:
		AudioManager.play_sfx("player_hit")
	_play_result_anim(result)
	pending_next = result["next"]
	await _typewrite(result["message"])
	if result.get("death_message", "") != "":
		await _typewrite(result["death_message"])

# ---------------------------------------------------------------------------
# Action submenu
# ---------------------------------------------------------------------------

func _open_action_submenu() -> void:
	var member = battle_manager.party[_current_member_index]
	var moves = member.psi_moves
	if moves.is_empty():
		await _typewrite("%s doesn't know any actions!" % member.character_name)
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
	if _pending_action_move.effect_type == ActionMove.EffectType.DAMAGE:
		_open_action_target_submenu()
	else:
		_execute_action(-1)

func _open_action_target_submenu() -> void:
	var living = battle_manager.get_living_enemies()
	if living.size() == 1:
		_execute_action(living[0]["index"])
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
	_execute_action(living[selected_index]["index"])

func _execute_action(target_index: int) -> void:
	_hide_action_menu()
	ui_state = UIState.WAITING_FOR_E
	var member = battle_manager.party[_current_member_index]
	var announce = "%s uses %s!" % [member.character_name, _pending_action_move.move_name]
	if _pending_action_move.use_sound:
		AudioManager.play_sfx("action_use")
	await _typewrite(announce)
	await _await_e_press()
	_trigger_e_cooldown()
	var result = battle_manager.do_action(_current_member_index, _pending_action_move, target_index)
	if result["next"] == "party_turn_%d" % _current_member_index:
		await _typewrite(result["message"])
		_show_main_menu(_current_member_index)
		return
	_play_result_anim(result)
	pending_next = result["next"]
	await _typewrite(result["message"])
	if result.get("death_message", "") != "":
		await _typewrite(result["death_message"])

# ---------------------------------------------------------------------------
# Items submenu
# ---------------------------------------------------------------------------

func _open_items_submenu() -> void:
	var items = SaveManager.get_inventory()
	if items.is_empty():
		await _typewrite("You have no items!")
		return
	ui_state = UIState.SUBMENU_ITEMS
	selected_index = 0
	_current_labels = []
	for item_id in items:
		var qty = SaveManager.get_quantity(item_id)
		_current_labels.append("%s x%d" % [item_id, qty])
	_current_labels.append("Back")
	_build_menu(_current_labels)
	_update_menu_selection()
	_typewrite("Choose an item.")

func _confirm_item_action() -> void:
	var items = SaveManager.get_inventory()
	if selected_index >= items.size():
		_show_main_menu(_current_member_index)
		return
	# Item use — placeholder until ItemData system is built
	await _typewrite("Items not yet implemented.")
	_show_main_menu(_current_member_index)

# ---------------------------------------------------------------------------
# Progression
# ---------------------------------------------------------------------------

func _handle_next() -> void:
	if pending_next.begins_with("party_turn_"):
		var member_index = int(pending_next.split("_")[2])
		_begin_party_turn(member_index)
		return

	if pending_next.begins_with("enemy_turn_"):
		var enemy_index = int(pending_next.split("_")[2])
		ui_state = UIState.WAITING_FOR_E

		var announce = battle_manager.get_enemy_announce(enemy_index)
		var target_member = battle_manager.pick_enemy_target()

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
		pending_next = result["next"]

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
		return

	match pending_next:
		"win":
			post_battle_queue = battle_manager.get_win_messages()
			ui_state = UIState.POST_BATTLE
			await _typewrite(post_battle_queue.pop_front())
		"lose":
			post_battle_queue = battle_manager.get_lose_messages()
			ui_state = UIState.POST_BATTLE
			await _typewrite(post_battle_queue.pop_front())
		"fled":
			ui_state = UIState.DONE
			battle_manager._return_to_world()

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
	_handle_next()

# ---------------------------------------------------------------------------
# Signal callbacks — update status boxes
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
	pass  # Enemy HP display handled in scene — override if needed

# ---------------------------------------------------------------------------
# Menu rendering
# ---------------------------------------------------------------------------

func _build_menu(labels: Array[String]) -> void:
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
# E press signal
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
