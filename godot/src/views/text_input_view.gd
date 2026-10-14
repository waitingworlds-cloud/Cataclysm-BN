extends Control
## A text prompt from the game (`string_input_popup`): title, explanation, a field with a caret,
## and OK / Cancel. Typing goes to the game, which sends back the value and the caret position.

var view_id := 0

var _title: Label
var _description: RichTextLabel
var _field: FieldView
var _counter: Label
var _card: PanelContainer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var scrim := ColorRect.new()
	scrim.color = Slate.SCRIM
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(scrim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", Slate.card_box(18, 22))
	_card.custom_minimum_size.x = 500
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(_card)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	_card.add_child(col)

	_title = Slate.label("", 18, Slate.TEXT, Slate.heavy())
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_title)
	_description = Slate.rich(14)
	_description.add_theme_color_override("default_color", Slate.MUTED)
	col.add_child(_description)

	_field = FieldView.new()
	col.add_child(_field)
	_counter = Slate.label("", 12, Slate.FAINT, Slate.mono())
	_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	col.add_child(_counter)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	actions.alignment = BoxContainer.ALIGNMENT_END
	col.add_child(actions)
	actions.add_child(_button("Cancel", "Esc", false, func(): Bridge.press(view_id, "TEXT.QUIT")))
	actions.add_child(_button("OK", "Enter", true, func(): Bridge.press(view_id, "TEXT.CONFIRM")))


func _button(text: String, key: String, primary: bool, action: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(110, 40)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var bg := Slate.ACCENT if primary else Color(1, 1, 1, 0.06)
	var hot := Slate.ACCENT.lightened(0.12) if primary else Color(1, 1, 1, 0.11)
	var border := Color(0, 0, 0, 0) if primary else Slate.BORDER_STRONG
	b.add_theme_stylebox_override("normal", Slate.box(bg, 10, border, 1))
	b.add_theme_stylebox_override("hover", Slate.box(hot, 10, border, 1))
	b.add_theme_stylebox_override("pressed", Slate.box(hot.darkened(0.1), 10, border, 1))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(row)
	row.add_child(Slate.label(text, 14, Slate.ACCENT_TEXT if primary else Slate.TEXT, Slate.bold()))
	var chip := Slate.key_chip(key, 10)
	if primary:
		chip.add_theme_stylebox_override("panel", Slate.pill_box(Color(0, 0, 0, 0.16), 6, 1))
		(chip.get_child(0) as Label).add_theme_color_override("font_color", Color(Slate.ACCENT_TEXT, 0.75))
	row.add_child(chip)
	b.pressed.connect(action)
	return b


func apply(msg: Dictionary) -> void:
	var title := Slate.plain(msg.get("title", [])).strip_edges()
	_title.text = title
	_title.visible = title != ""
	var description: Array = msg.get("description", [])
	_description.text = Slate.bbcode(description, Slate.MUTED).strip_edges()
	_description.visible = Slate.plain(description).strip_edges() != ""
	var value := String(msg.get("value", ""))
	var max_length := int(msg.get("max_length", 0))
	_field.set_state(value, int(msg.get("cursor", value.length())), String(msg.get("edit", "")),
			bool(msg.get("digits", false)))
	# Only worth showing when the limit is one a player could reach.
	_counter.visible = max_length > 0 and max_length <= 256
	_counter.text = "%d / %d" % [value.length(), max_length]
	var viewport := get_viewport_rect().size
	_card.custom_minimum_size.x = clampf(viewport.x * 0.36, 460, 640)


class FieldView extends Control:
	var _value := ""
	var _cursor := 0
	var _edit := ""
	var _digits := false
	var _blink := 0.0
	var _scroll := 0.0

	func _init() -> void:
		custom_minimum_size = Vector2(0, 46)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_state(value: String, cursor: int, edit: String, digits: bool) -> void:
		_value = value
		_cursor = clampi(cursor, 0, value.length())
		_edit = edit
		_digits = digits
		_blink = 0.0
		queue_redraw()

	func _process(delta: float) -> void:
		var was := fmod(_blink, 1.0) < 0.55
		_blink += delta
		if was != (fmod(_blink, 1.0) < 0.55):
			queue_redraw()

	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)
		draw_style_box(Slate.box(Color(1, 1, 1, 0.05), 10, Color(Slate.ACCENT, 0.7), 1), rect)
		var f: Font = Slate.mono() if _digits else Slate.body()
		var fs := 16
		var pad := 14.0
		var inner := size.x - pad * 2
		var before := _value.substr(0, _cursor)
		var caret_x := f.get_string_size(before, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		# Keep the caret in view when the text is longer than the field.
		if caret_x - _scroll > inner:
			_scroll = caret_x - inner
		elif caret_x < _scroll:
			_scroll = caret_x
		var baseline := (size.y + f.get_ascent(fs) - f.get_descent(fs)) / 2
		var clip := Rect2(pad, 0, inner, size.y)
		RenderingServer.canvas_item_set_clip(get_canvas_item(), true)
		var x := pad - _scroll
		var shown := _value.insert(_cursor, _edit) if _edit != "" else _value
		draw_string(f, Vector2(x, baseline), shown, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Slate.TEXT)
		if _edit != "":
			var ew := f.get_string_size(_edit, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_line(Vector2(x + caret_x, baseline + 3), Vector2(x + caret_x + ew, baseline + 3), Slate.ACCENT, 1.5)
		if fmod(_blink, 1.0) < 0.55:
			var cx := clampf(x + caret_x, clip.position.x, clip.end.x)
			draw_rect(Rect2(cx, (size.y - fs * 1.3) / 2, 2, fs * 1.3), Slate.ACCENT)
		if _value == "" and _edit == "":
			draw_string(f, Vector2(pad + 6, baseline), "Type here", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Slate.FAINT)
