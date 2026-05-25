# npc_interaction_area.gd
# Area3D child of NPC — proximity detection, prompt label.
# Set locked = true to prevent the prompt from showing (e.g. during battle).

extends Area3D

@export_group("Prompt")
@export var show_prompt: bool = true
@export var prompt_text: String = "[E] Talk"
@export var prompt_height: float = 2.2
@export var prompt_scale: float = 1.0
@export var prompt_font_size: int = 32

var _prompt_label: Label3D
var _npc: Node
var player_in_range: bool = false

# When locked, the prompt will never show regardless of player proximity
var locked: bool = false

func _ready() -> void:
	_npc = get_parent()
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	if show_prompt:
		_build_prompt()

func _build_prompt() -> void:
	_prompt_label = Label3D.new()
	_prompt_label.text = prompt_text
	_prompt_label.font_size = prompt_font_size
	_prompt_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt_label.position.y = prompt_height
	_prompt_label.scale = Vector3(prompt_scale, prompt_scale, prompt_scale)
	_prompt_label.hide()
	add_child(_prompt_label)

func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	player_in_range = true
	if not locked and not _in_battle() and _prompt_label:
		_prompt_label.show()
	if _npc and _npc.has_method("on_player_entered"):
		_npc.on_player_entered()

func _on_body_exited(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	player_in_range = false
	if _prompt_label:
		_prompt_label.hide()
	if _npc and _npc.has_method("on_player_exited"):
		_npc.on_player_exited()

func hide_prompt() -> void:
	if _prompt_label:
		_prompt_label.hide()

func show_prompt_label() -> void:
	if _prompt_label and player_in_range and not locked and not _in_battle():
		_prompt_label.show()

func _in_battle() -> bool:
	return get_tree().get_first_node_in_group("battle_manager") != null

func lock() -> void:
	locked = true
	hide_prompt()

func unlock() -> void:
	locked = false
	if player_in_range:
		show_prompt_label()