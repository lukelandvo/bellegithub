# game_over.gd
# CanvasLayer shown when the player is defeated in battle.
# Shows GAME OVER with two options:
#   - Restart from Beginning: reloads initial scene without touching saves
#   - Load Save: opens save slot picker
#
# Scene structure:
#   CanvasLayer (layer 20) — game_over.gd
#     [everything built in code]

extends CanvasLayer

@export var font_size_title: int = 48
@export var font_size_menu: int = 20
@export var selector: String = "► "
@export var normal_color: Color = Color.WHITE
@export var selected_color: Color = Color.YELLOW
@export var background_color: Color = Color(0.0, 0.0, 0.0, 0.92)

const OPTIONS := ["Restart from Beginning", "Load Save"]

var _selected: int = 0
var _active: bool = false
var _option_labels: Array[Label] = []
@export var load_menu_scene_path: String = "res://scenes/ui/menu/menu_load.tscn"


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	hide()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = background_color
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	vbox.add_theme_constant_override("separation", 24)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(vbox)

	var title := Label.new()
	title.text = "GAME OVER"
	title.add_theme_font_size_override("font_size", font_size_title)
	title.add_theme_color_override("font_color", Color.RED)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 16)
	vbox.add_child(spacer)

	for option in OPTIONS:
		var lbl := Label.new()
		lbl.text = "  " + option
		lbl.add_theme_font_size_override("font_size", font_size_menu)
		lbl.add_theme_color_override("font_color", normal_color)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(lbl)
		_option_labels.append(lbl)


func open() -> void:
	_selected = 0
	_update_selection()
	show()
	_active = true


func _update_selection() -> void:
	for i in _option_labels.size():
		var is_sel = i == _selected
		_option_labels[i].text = (selector if is_sel else "  ") + OPTIONS[i]
		_option_labels[i].add_theme_color_override("font_color",
			selected_color if is_sel else normal_color)


func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return

	if event.is_action_pressed("move_forward"):
		_selected = wrapi(_selected - 1, 0, OPTIONS.size())
		_update_selection()
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("move_back"):
		_selected = wrapi(_selected + 1, 0, OPTIONS.size())
		_update_selection()
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("interact") and not event.is_echo():
		_active = false
		match _selected:
			0: _restart_from_beginning()
			1: _open_load_menu()
		get_viewport().set_input_as_handled()


func _restart_from_beginning() -> void:
	var loaders = get_tree().get_nodes_in_group("scene_loader")
	if loaders.is_empty():
		push_error("game_over: no scene_loader found")
		return
	var loader = loaders[0]
	queue_free()
	# reload initial scene without touching saves
	if loader.has_method("restart_from_beginning"):
		loader.restart_from_beginning()
	else:
		push_error("game_over: SceneLoader has no restart_from_beginning method")


func _open_load_menu() -> void:
	# instantiate the load menu as a standalone overlay
	if not ResourceLoader.exists(load_menu_scene_path):
		push_error("game_over: load menu scene not found at '%s'" % load_menu_scene_path)
		return
	var packed = load(load_menu_scene_path)
	var menu = packed.instantiate()
	menu.add_to_group("standalone_load_menu")
	get_tree().root.add_child(menu)
	# hide game over while load menu is open
	hide()
	queue_free()