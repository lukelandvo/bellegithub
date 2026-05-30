# menu.gd
# Attach to the root Control of menu.tscn.
# Owns zone state — "tabs" or "content".
# A/D navigates tabs, S moves into content, W at top of content returns to tabs.

extends Control

const STYLE_TEXT_COLOR := Color(0.92, 0.92, 0.96, 1.0)
const STYLE_TEXT_DIM   := Color(0.55, 0.55, 0.65, 1.0)

const TABS := [
	{ "scene": "res://scenes/ui/menu/menu_party.tscn" },
	{ "scene": "res://scenes/ui/menu/menu_inventory.tscn" },
	{ "scene": "res://scenes/ui/menu/menu_equipment.tscn" },
	{ "scene": "res://scenes/ui/menu/menu_actions.tscn" },
	{ "scene": "res://scenes/ui/menu/menu_load.tscn" },
]

@onready var _content: MarginContainer = %Content

var _tab_buttons: Array = []
var _tab_scenes: Array = []
var _current_tab: int = 0
var _zone: String = "tabs"  # "tabs" or "content"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	var tab_bar = find_child("TabBar", true, false)
	if tab_bar:
		for child in tab_bar.get_children():
			if child is Button:
				child.focus_mode = Control.FOCUS_NONE
				child.add_theme_color_override("font_color", STYLE_TEXT_DIM)  # add this
				var index = _tab_buttons.size()
				_tab_buttons.append(child)
				child.pressed.connect(_switch_tab.bind(index))
	else:
		push_error("menu: could not find TabBar node")

	for tab in TABS:
		var packed: PackedScene = load(tab["scene"])
		if packed:
			var instance: Control = packed.instantiate()
			instance.visible = false
			instance.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			instance.size_flags_vertical = Control.SIZE_EXPAND_FILL
			_content.add_child(instance)
			_tab_scenes.append(instance)
		else:
			push_error("menu: could not load tab scene '%s'" % tab["scene"])
			_tab_scenes.append(null)

	_switch_tab(0)

func _unhandled_input(event: InputEvent) -> void:
	if _zone == "tabs":
		if event.is_action_pressed("move_left"):
			_switch_tab(wrapi(_current_tab - 1, 0, _tab_scenes.size()))
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("move_right"):
			_switch_tab(wrapi(_current_tab + 1, 0, _tab_scenes.size()))
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("move_back"):
			_enter_content()
			get_viewport().set_input_as_handled()
	elif _zone == "content":
		# Let the active tab handle input — it calls back via at_top_of_content()
		pass

func _switch_tab(index: int) -> void:
	if index < 0 or index >= _tab_scenes.size():
		return
	if _tab_scenes.is_empty():
		return

	# Deactivate current tab content
	var current = _tab_scenes[_current_tab]
	if current and current.has_method("deactivate_content"):
		current.deactivate_content()
	if current:
		current.visible = false
	if not _tab_buttons.is_empty():
		_set_tab_active(_tab_buttons[_current_tab], false)

	_current_tab = index
	_zone = "tabs"

	if not _tab_buttons.is_empty():
		_set_tab_active(_tab_buttons[_current_tab], true)
	var next = _tab_scenes[_current_tab]
	if next:
		next.visible = true
		if next.has_method("refresh"):
			next.refresh()

func _enter_content() -> void:
	var tab = _tab_scenes[_current_tab]
	if tab and tab.has_method("activate_content"):
		_zone = "content"
		tab.activate_content()
	# If tab has no content navigation, stay in tabs zone

func at_top_of_content() -> void:
	# Called by active tab when W is pressed at the first item
	_zone = "tabs"
	var tab = _tab_scenes[_current_tab]
	if tab and tab.has_method("deactivate_content"):
		tab.deactivate_content()

func _set_tab_active(btn: Button, active: bool) -> void:
	btn.add_theme_color_override("font_color",
		STYLE_TEXT_COLOR if active else STYLE_TEXT_DIM)

func on_open() -> void:
	_zone = "tabs"
	_switch_tab(0)

func on_close() -> void:
	var tab = _tab_scenes[_current_tab]
	if tab and tab.has_method("deactivate_content"):
		tab.deactivate_content()
