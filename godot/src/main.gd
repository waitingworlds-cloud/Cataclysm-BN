extends Control
## Root of the front end: the game's frame at the bottom, the HUD above it, native screens
## (menus, prompts) on top. Keyboard input always goes to the game; mouse input goes to whatever
## Godot control is under the pointer, and to the game when that is the map.

const Hud := preload("res://src/ui/hud.gd")
const MenuView := preload("res://src/views/menu_view.gd")
const PopupView := preload("res://src/views/popup_view.gd")
const TextInputView := preload("res://src/views/text_input_view.gd")
const InventoryView := preload("res://src/views/inventory_view.gd")
const ItemActionsView := preload("res://src/views/item_actions_view.gd")
const ScreenView := preload("res://src/views/screen_view.gd")
const TitleView := preload("res://src/views/title_view.gd")
const LoadingView := preload("res://src/views/loading_view.gd")
const Keys := preload("res://src/keys.gd")

var frame_view: TextureRect
var hud: Hud
var view_layer: Control
var splash: Control
var views := {}
var visible_views := []
var _last_size := Vector2.ZERO


func _ready() -> void:
	theme = Slate.theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var ground := ColorRect.new()
	ground.color = Slate.GROUND
	ground.set_anchors_preset(Control.PRESET_FULL_RECT)
	ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ground)

	frame_view = TextureRect.new()
	frame_view.stretch_mode = TextureRect.STRETCH_KEEP
	frame_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	frame_view.mouse_filter = Control.MOUSE_FILTER_PASS
	frame_view.gui_input.connect(_on_frame_input)
	frame_view.mouse_entered.connect(func(): hud.set_map_hover(true))
	frame_view.mouse_exited.connect(func(): hud.set_map_hover(false))
	add_child(frame_view)

	hud = Hud.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.visible = false
	add_child(hud)

	view_layer = Control.new()
	view_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	view_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(view_layer)

	splash = _make_splash()
	add_child(splash)

	Bridge.connected.connect(_on_connected)
	Bridge.frame_received.connect(_on_frame)
	Bridge.frame_meta.connect(_on_frame_meta)
	Bridge.hud_received.connect(hud.apply)
	Bridge.view_received.connect(_on_view)
	Bridge.entries_received.connect(_on_entries)
	Bridge.view_closed.connect(_on_view_closed)
	Bridge.game_exited.connect(_on_game_exited)
	if Bridge.launch_error != "":
		_show_splash_message(Bridge.launch_error)


func _make_splash() -> Control:
	var box := CenterContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 10)
	box.add_child(col)
	var title := Slate.label("Bright Nights", 34, Slate.TEXT, Slate.heavy())
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var status := Slate.label("Starting the game…", 15, Slate.MUTED)
	status.name = "Status"
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(status)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(220, 4)
	bar.show_percentage = false
	bar.indeterminate = true
	bar.add_theme_stylebox_override("background", Slate.box(Slate.TRACK, 2, Slate.BORDER, 0))
	bar.add_theme_stylebox_override("fill", Slate.box(Slate.ACCENT, 2, Slate.BORDER, 0))
	col.add_child(bar)
	return box


func _show_splash_message(text: String) -> void:
	splash.visible = true
	var status := splash.find_child("Status", true, false) as Label
	status.text = text


func _on_connected() -> void:
	_last_size = size


func _on_game_exited(reason: String) -> void:
	_show_splash_message(reason)
	hud.visible = false


func _process(_delta: float) -> void:
	if Bridge.is_connected_to_game() and size != _last_size and size.x > 0:
		_last_size = size
		Bridge.send_resize(size)


func _on_frame(texture: ImageTexture) -> void:
	frame_view.texture = texture
	frame_view.size = texture.get_size()
	splash.visible = false


func _on_frame_meta(main_view: bool, shown: Array) -> void:
	hud.visible = main_view
	visible_views = shown.map(func(id): return int(id))
	for id in views:
		views[id].visible = id in visible_views


func _on_view(msg: Dictionary) -> void:
	var id := int(msg["id"])
	if not views.has(id):
		var view: Control
		match String(msg.get("kind", "")):
			"menu":
				view = MenuView.new()
			"popup":
				view = PopupView.new()
			"text_input":
				view = TextInputView.new()
			"inventory":
				view = InventoryView.new()
			"item_actions":
				view = ItemActionsView.new()
			"screen":
				view = ScreenView.new()
			"title":
				view = TitleView.new()
			"loading":
				view = LoadingView.new()
			_:
				return
		view.view_id = id
		view.set_anchors_preset(Control.PRESET_FULL_RECT)
		view.visible = id in visible_views
		view_layer.add_child(view)
		views[id] = view
	views[id].apply(msg)


func _on_entries(id: int, entries: Array) -> void:
	if not views.has(id):
		var view := MenuView.new()
		view.view_id = id
		view.set_anchors_preset(Control.PRESET_FULL_RECT)
		view.visible = id in visible_views
		view_layer.add_child(view)
		views[id] = view
	views[id].set_entries(entries)


func _on_view_closed(id: int) -> void:
	if views.has(id):
		views[id].queue_free()
		views.erase(id)


func _input(event: InputEvent) -> void:
	# The game owns the keyboard: every key goes to it, even while a Godot menu is open.
	if event is InputEventKey:
		for msg in Keys.translate(event):
			if OS.has_environment("BN_BRIDGE_DEBUG"):
				print("key ", event, " -> ", msg)
			Bridge.send(msg)
		get_viewport().set_input_as_handled()


func _on_frame_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		Bridge.send_mouse_move(event.position)
		hud.map_mouse_moved()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			Bridge.send_mouse("wheel", mb.position, 0, 1)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			Bridge.send_mouse("wheel", mb.position, 0, -1)
		elif mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			var sdl_button: int = {MOUSE_BUTTON_LEFT: 1, MOUSE_BUTTON_MIDDLE: 2, MOUSE_BUTTON_RIGHT: 3}[mb.button_index]
			Bridge.send_mouse("down" if mb.pressed else "up", mb.position, sdl_button)
