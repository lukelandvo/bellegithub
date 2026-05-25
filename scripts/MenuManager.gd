# MenuManager.gd
# Autoload singleton — opens and closes the pause menu.
# Add to Project > Project Settings > Autoload as "MenuManager".

extends Node

@export var menu_scene_path: String = "res://scenes/ui/menu/menu.tscn"

var _menu_instance: Control = null
var _is_open: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process_input(true)
	add_to_group("menu_manager")

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("menu"):
		if _is_open:
			close_menu()
		else:
			open_menu()
		get_viewport().set_input_as_handled()

func open_menu() -> void:
	if _is_open:
		return
	var packed: PackedScene = load(menu_scene_path)
	if not packed:
		push_error("MenuManager: could not load menu scene at '%s'" % menu_scene_path)
		return
	_menu_instance = packed.instantiate()
	get_tree().root.add_child(_menu_instance)
	_menu_instance.on_open()
	get_tree().paused = true
	_is_open = true

func close_menu() -> void:
	if not _is_open:
		return
	if _menu_instance:
		_menu_instance.on_close()
		_menu_instance.queue_free()
		_menu_instance = null
	get_tree().paused = false
	_is_open = false

func is_open() -> bool:
	return _is_open
