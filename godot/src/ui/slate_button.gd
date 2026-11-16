extends PanelContainer
## Button with an icon, a label and the key that does the same thing. The `primary` one is
## hazard yellow with a cut corner; the rest are outlined. `set_on` lights a toggle that is
## switched on.

signal pressed

var _primary := false
var _enabled := true
var _on := false
var _hover := false
var _icon: TextureRect
var _label: Label
var _key: PanelContainer
var _size := 12
## Smallest text size a fitting label shrinks to before it ends in "..." (0: never shrinks).
var _least := 0


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
	_size = 11 if small else (16 if primary else 12)
	_label = Slate.label(text, _size, fg, Slate.spaced(Slate.heading(), 1 if small else 2))
	_label.uppercase = true
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_label)
	_key = Slate.key_chip("", 10)
	if primary:
		var chip := Slate.box(Color(0, 0, 0, 0), 0, Color(Slate.ACCENT_TEXT, 0.8), 1)
		chip.content_margin_left = 5
		chip.content_margin_right = 5
		_key.add_theme_stylebox_override("panel", chip)
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


## Lets the label get smaller, down to `least`, when the button is narrower than its text (the
## main action in a narrow panel), and only then end in "...".
func set_fitting(least := 11) -> void:
	_least = least
	set_compressible()
	_label.custom_minimum_size.y = _label.get_minimum_size().y
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if not _label.resized.is_connected(_fit):
		_label.resized.connect(_fit)
	_fit()


func _fit() -> void:
	if _least <= 0 or _label.size.x <= 0:
		return
	var font := _label.get_theme_font("font")
	var text := _label.text.to_upper()
	var size := _size
	while size > _least and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, Slate.fs(size)).x > _label.size.x:
		size -= 1
	if _label.get_theme_font_size("font_size") != Slate.fs(size):
		_label.add_theme_font_size_override("font_size", Slate.fs(size))


## Whether the label is wider than the room it has (it would end in "...").
func is_cut() -> bool:
	if _label.size.x <= 0:
		return false
	var font := _label.get_theme_font("font")
	return font.get_string_size(_label.text.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, Slate.fs(_size)).x > _label.size.x + 0.5


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
	var small: bool = get_meta("small", false)
	var hot := _hover and _enabled
	var sb: StyleBoxFlat
	if _primary:
		sb = Slate.box(Slate.ACCENT.lightened(0.3) if hot else Slate.ACCENT, 14, Slate.BORDER, 0)
		Fx.glow(sb, Slate.ACCENT, 12 if hot else 8, 0.42 if hot else 0.3)
	elif _on:
		sb = Slate.box(Color(Slate.CYAN, 0.3 if hot else 0.22), 0, Color(Slate.CYAN, 0.9), 1)
	else:
		sb = Slate.box(Color(Slate.CYAN, 0.14) if hot else Color(0, 0, 0, 0), 0, Color(Slate.CYAN, 0.35), 1)
	sb.content_margin_left = 9 if small else (14 if _primary else 10)
	sb.content_margin_right = 7 if small else 10
	sb.content_margin_top = 4 if small else (11 if _primary else 7)
	sb.content_margin_bottom = 4 if small else (11 if _primary else 7)
	add_theme_stylebox_override("panel", sb)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		if _enabled:
			pressed.emit()
