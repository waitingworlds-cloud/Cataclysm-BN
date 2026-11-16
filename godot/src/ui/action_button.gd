class_name ActionButton
extends Button
## An action with the key that does the same thing: hazard yellow for the main one, outlined
## for the rest. A toggle that is on is lit cyan.

var _primary := false
var _on := false
var _text: Label
var _chip: Label


func _init(primary: bool) -> void:
	_primary = primary
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	custom_minimum_size = Vector2(0, 44 if primary else 34)
	var ink := Slate.ACCENT_TEXT if primary else Slate.TEXT
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 14 if primary else 10
	row.offset_right = -10
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	_text = Slate.label("", 17 if primary else 13, ink, Slate.spaced(Slate.heading(), 2))
	_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text.clip_text = true
	_text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_text.uppercase = true
	row.add_child(_text)
	_chip = Slate.label("", 11, ink if primary else Slate.CYAN, Slate.mono())
	_chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_chip.custom_minimum_size = Vector2(20, 19)
	_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_chip.visible = false
	var edge := Color(ink, 0.8) if primary else Color(Slate.CYAN, 0.6)
	_chip.draw.connect(func(): _chip.draw_rect(Rect2(Vector2(0.5, 0.5), _chip.size - Vector2(1, 1)), edge, false, 1.0))
	row.add_child(_chip)
	_restyle()


func set_label(text: String) -> void:
	_text.text = text


func get_label() -> String:
	return _text.text


func set_key(key: String) -> void:
	_chip.text = " %s " % key if key.length() > 1 else key
	_chip.visible = key != ""


func set_enabled(on: bool) -> void:
	disabled = not on
	modulate.a = 1.0 if on else 0.4
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if on else Control.CURSOR_ARROW


func set_on(on: bool) -> void:
	if on != _on:
		_on = on
		_restyle()


func _restyle() -> void:
	var normal: StyleBoxFlat
	var hot: StyleBoxFlat
	if _primary:
		normal = Slate.box(Slate.ACCENT, 14, Slate.BORDER, 0)
		hot = Slate.box(Slate.ACCENT.lightened(0.3), 14, Slate.BORDER, 0)
	else:
		normal = Slate.box(Color(Slate.CYAN, 0.22) if _on else Color(0, 0, 0, 0), 0, Color(Slate.CYAN, 0.9 if _on else 0.35), 1)
		hot = Slate.box(Color(Slate.CYAN, 0.3 if _on else 0.14), 0, Slate.BORDER_STRONG, 1)
	add_theme_stylebox_override("normal", normal)
	add_theme_stylebox_override("disabled", normal)
	add_theme_stylebox_override("hover", hot)
	add_theme_stylebox_override("pressed", hot)
