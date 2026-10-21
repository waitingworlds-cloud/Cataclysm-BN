extends PanelContainer
## Rounded button with an icon, a label and the key that does the same thing. `primary` buttons
## are amber; `set_on` outlines a toggle that is switched on.

signal pressed

var _primary := false
var _enabled := true
var _on := false
var _hover := false
var _icon: TextureRect
var _label: Label
var _key: PanelContainer


func _init(icon_name: String, text: String, primary := false, small := false) -> void:
	_primary = primary
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6 if small else 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	var fg := Slate.ACCENT_TEXT if primary else Slate.TEXT
	_icon = Slate.icon_rect(icon_name if icon_name != "" else "chevron-right", 14 if small else 16, fg)
	_icon.visible = icon_name != ""
	row.add_child(_icon)
	_label = Slate.label(text, 12 if small else 13, fg, Slate.bold())
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_label)
	_key = Slate.key_chip("", 10)
	if primary:
		_key.add_theme_stylebox_override("panel", Slate.pill_box(Color(0, 0, 0, 0.16), 6, 1))
		(_key.get_child(0) as Label).add_theme_color_override("font_color", Slate.ACCENT_TEXT)
	_key.visible = false
	row.add_child(_key)
	mouse_entered.connect(func():
		_hover = true
		_restyle())
	mouse_exited.connect(func():
		_hover = false
		_restyle())
	set_meta("small", small)
	_restyle()


func set_text(text: String) -> void:
	_label.text = text


## Lets the label end in "..." when the button is narrower than its text (buttons in a grid).
func set_compressible() -> void:
	_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tooltip_text = _label.text


func get_text() -> String:
	return _label.text


func set_key(key: String) -> void:
	(_key.get_child(0) as Label).text = Slate.key_name(key)
	_key.visible = key != ""


func set_enabled(on: bool) -> void:
	_enabled = on
	modulate.a = 1.0 if on else 0.45
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if on else Control.CURSOR_ARROW


func set_on(on: bool) -> void:
	_on = on
	_restyle()


## Text color for buttons whose label carries a game color (an action that can't be done now).
func set_text_color(color: Color) -> void:
	_label.add_theme_color_override("font_color", color)
	_icon.modulate = color


func _restyle() -> void:
	var bg: Color
	if _primary:
		bg = Slate.ACCENT.lightened(0.12) if _hover and _enabled else Slate.ACCENT
	elif _on:
		bg = Color(Slate.ACCENT, 0.16 if _hover else 0.12)
	else:
		bg = Color(1, 1, 1, 0.11 if _hover and _enabled else 0.06)
	var small: bool = get_meta("small", false)
	var sb := Slate.box(bg, 8 if small else 10, Color(Slate.ACCENT, 0.6) if _on else Slate.BORDER, 1 if _on else 0)
	sb.content_margin_left = 10 if small else 12
	sb.content_margin_right = 8 if small else 10
	sb.content_margin_top = 5 if small else 8
	sb.content_margin_bottom = 5 if small else 8
	add_theme_stylebox_override("panel", sb)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		if _enabled:
			pressed.emit()
