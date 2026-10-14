extends Control
## A text prompt from the game (`string_input_popup`): title, explanation, a field with a caret,
## and OK / Cancel. Typing goes to the game, which sends back the value and the caret position.
## With `multiline` it is the game's text editor (a diary page, Lua input): the game folds the
## text into `lines` and says where the caret is; clicking in the text moves the caret there.

var view_id := 0

var _title: Label
var _description: RichTextLabel
var _field: FieldView
var _editor: EditorView
var _counter: Label
var _note: Label
var _card: PanelContainer
var _ok: Button
var _cancel: Button


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
	_editor = EditorView.new()
	_editor.visible = false
	_editor.clicked.connect(func(code: int): Bridge.pick(view_id, code, ""))
	col.add_child(_editor)
	_counter = Slate.label("", 12, Slate.FAINT, Slate.mono())
	_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	col.add_child(_counter)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	col.add_child(actions)
	_note = Slate.label("", 12, Slate.FAINT)
	_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	actions.add_child(_note)
	_cancel = _button("Cancel", "Esc", false, func(): Bridge.press(view_id, "TEXT.QUIT"))
	actions.add_child(_cancel)
	_ok = _button("OK", "Enter", true, func(): Bridge.press(view_id, "TEXT.CONFIRM"))
	actions.add_child(_ok)


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
	var name := Slate.label(text, 14, Slate.ACCENT_TEXT if primary else Slate.TEXT, Slate.bold())
	name.name = "Text"
	row.add_child(name)
	var chip := Slate.key_chip(key, 10)
	chip.name = "Key"
	if primary:
		chip.add_theme_stylebox_override("panel", Slate.pill_box(Color(0, 0, 0, 0.16), 6, 1))
		(chip.get_child(0) as Label).add_theme_color_override("font_color", Color(Slate.ACCENT_TEXT, 0.75))
	row.add_child(chip)
	b.pressed.connect(action)
	return b


## Sets a button's text and key chip.
static func _relabel(b: Button, text: String, key: String) -> void:
	(b.find_child("Text", true, false) as Label).text = text
	var chip := b.find_child("Key", true, false) as Control
	chip.visible = key != ""
	if key != "":
		(chip.get_child(0) as Label).text = Slate.key_name(key)


func apply(msg: Dictionary) -> void:
	var title := Slate.plain(msg.get("title", [])).strip_edges()
	_title.text = title
	_title.visible = title != ""
	var description: Array = msg.get("description", [])
	_description.text = Slate.bbcode(description, Slate.MUTED).strip_edges()
	_description.visible = Slate.plain(description).strip_edges() != ""
	var multiline := bool(msg.get("multiline", false))
	_field.visible = not multiline
	_editor.visible = multiline
	if multiline:
		var keys: Dictionary = msg.get("keys", {})
		_editor.set_state(msg)
		_counter.visible = false
		_note.text = "Enter starts a new line"
		_relabel(_ok, "Save", String(keys.get("confirm", "")))
		_relabel(_cancel, "Cancel", String(keys.get("cancel", "")))
		_card.custom_minimum_size.x = 0
		return
	_note.text = ""
	_relabel(_ok, "OK", "Enter")
	_relabel(_cancel, "Cancel", "Esc")
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


## The game's multi-line editor: its folded lines in a fixed-width font, a caret, optional line
## numbers, and the text being composed with an input method underlined.
class EditorView extends Control:
	signal clicked(code: int)

	const FONT_SIZE := 14
	const PAD := 14.0
	## Pick code for a click: `row * PICK_STRIDE + column` (string_editor_window.cpp).
	const PICK_STRIDE := 10000

	var _lines: Array = []
	var _numbers: Array = []
	var _cursor := Vector2i.ZERO
	var _preview: Array = []
	var _rows := 24
	var _top := 0
	var _blink := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_IBEAM
		clip_contents = true

	func _cell() -> Vector2:
		var f := Slate.mono()
		return Vector2(f.get_char_size(ord("M"), FONT_SIZE).x, ceilf(f.get_height(FONT_SIZE)) + 5)

	func _gutter() -> float:
		if _numbers.is_empty():
			return 0.0
		var most := 1
		for n in _numbers:
			most = maxi(most, int(n))
		return (str(most).length() + 2) * _cell().x

	func set_state(msg: Dictionary) -> void:
		_lines = msg.get("lines", [])
		_numbers = msg.get("numbers", [])
		var c: Array = msg.get("cursor", [0, 0])
		_cursor = Vector2i(int(c[0]), int(c[1]))
		_preview = msg.get("preview", [])
		_rows = maxi(1, int(msg.get("rows", 24)))
		var cell := _cell()
		var viewport := get_viewport_rect().size
		# As tall as the game's page, but never taller than the window leaves room for.
		_rows = mini(_rows, maxi(4, int((viewport.y - 260) / cell.y)))
		custom_minimum_size = Vector2(_gutter() + int(msg.get("columns", 80)) * cell.x + PAD * 2 + 8,
				_rows * cell.y + PAD * 2)
		# Keep the caret's line in view.
		if _cursor.y < _top:
			_top = _cursor.y
		elif _cursor.y >= _top + _rows:
			_top = _cursor.y - _rows + 1
		_top = clampi(_top, 0, maxi(0, _lines.size() - _rows))
		_blink = 0.0
		queue_redraw()

	func _process(delta: float) -> void:
		var was := fmod(_blink, 1.0) < 0.55
		_blink += delta
		if was != (fmod(_blink, 1.0) < 0.55):
			queue_redraw()

	func _draw() -> void:
		draw_style_box(Slate.box(Color(1, 1, 1, 0.04), 10, Color(Slate.ACCENT, 0.6), 1), Rect2(Vector2.ZERO, size))
		var f := Slate.mono()
		var cell := _cell()
		var gutter := _gutter()
		var ascent := f.get_ascent(FONT_SIZE)
		for i in range(_top, mini(_lines.size(), _top + _rows)):
			var y := PAD + (i - _top) * cell.y
			var baseline := y + ascent + 2
			if not _numbers.is_empty() and i < _numbers.size() and int(_numbers[i]) > 0:
				var n := str(int(_numbers[i]))
				draw_string(f, Vector2(PAD + gutter - (n.length() + 1) * cell.x, baseline), n,
						HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Slate.FAINT if i != _cursor.y else Slate.MUTED)
			var x := PAD + gutter
			for run in _lines[i]:
				var text := String(run[0])
				draw_string(f, Vector2(x, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE,
						Slate.curses(String(run[1]), Slate.TEXT))
				x += f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
		# Text still being composed with an input method, underlined.
		if _preview.size() == 4:
			for row in range(int(_preview[1]), int(_preview[3]) + 1):
				if row < _top or row >= _top + _rows:
					continue
				var from := int(_preview[0]) if row == int(_preview[1]) else 0
				var to := int(_preview[2]) + 1 if row == int(_preview[3]) else 200
				var uy := PAD + (row - _top + 1) * cell.y - 3
				draw_line(Vector2(PAD + gutter + from * cell.x, uy), Vector2(PAD + gutter + to * cell.x, uy),
						Slate.ACCENT, 1.5)
		if fmod(_blink, 1.0) < 0.55 and _cursor.y >= _top and _cursor.y < _top + _rows:
			draw_rect(Rect2(PAD + gutter + _cursor.x * cell.x - 1, PAD + (_cursor.y - _top) * cell.y + 2, 2,
					cell.y - 4), Slate.ACCENT)
		# Where the shown lines sit in the whole text.
		if _lines.size() > _rows:
			var track := size.y - PAD * 2
			var h := maxf(24.0, track * _rows / _lines.size())
			var at := PAD + (track - h) * _top / maxf(1.0, _lines.size() - _rows)
			draw_rect(Rect2(size.x - 7, at, 3, h), Color(1, 1, 1, 0.18))

	func _gui_input(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb == null or not mb.pressed:
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var step := -3 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 3
			_top = clampi(_top + step, 0, maxi(0, _lines.size() - _rows))
			queue_redraw()
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT and not _lines.is_empty():
			var cell := _cell()
			var col := maxi(0, roundi((mb.position.x - PAD - _gutter()) / cell.x))
			var row := clampi(_top + floori((mb.position.y - PAD) / cell.y), 0, _lines.size() - 1)
			clicked.emit(row * PICK_STRIDE + col)
			accept_event()
