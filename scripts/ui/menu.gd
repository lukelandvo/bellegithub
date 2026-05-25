# menu.gd
# Attach to the root Control of menu.tscn.
# All layout is defined in the editor — this script handles logic only.
#
# Setup:
#   1. Mark Content node as unique (right-click > Access as Unique Name)
#   2. Set button text in the inspector: PARTY, INVENTORY, EQUIPMENT, ACTIONS, LOAD
#   3. Name the tab button container exactly "TabBar"

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

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	var tab_bar = find_child("TabBar", true, false)
	if tab_bar:
		for child in tab_bar.get_children():
			if child is Button:
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

func _switch_tab(index: int) -> void:
	if index < 0 or index >= _tab_scenes.size():
		push_error("menu: tab index %d out of range" % index)
		return
	if _tab_scenes.is_empty():
		return
	if _tab_scenes[_current_tab]:
		_tab_scenes[_current_tab].visible = false
	if not _tab_buttons.is_empty():
		_set_tab_active(_tab_buttons[_current_tab], false)

	_current_tab = index

	if not _tab_buttons.is_empty():
		_set_tab_active(_tab_buttons[_current_tab], true)
	if _tab_scenes[_current_tab]:
		_tab_scenes[_current_tab].visible = true
		if _tab_scenes[_current_tab].has_method("refresh"):
			_tab_scenes[_current_tab].refresh()

func _set_tab_active(btn: Button, active: bool) -> void:
	btn.add_theme_color_override("font_color",
		STYLE_TEXT_COLOR if active else STYLE_TEXT_DIM)

func on_open() -> void:
	_switch_tab(_current_tab)

func on_close() -> void:
	pass