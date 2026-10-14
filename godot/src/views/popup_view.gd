extends Control
## A message or question from the game (`query_popup`, behind `popup`, `query_yn` and friends):
## a card with the text and one button per answer. Each button shows the key that answers it.

var view_id := 0

var _buttons_data: Array = []
var _cursor := 0
var _anykey := false
var _cancel := false
var _top := false
var _full := false

var _scrim: ColorRect
var _center: CenterContainer
var _top_box: MarginContainer
var _card: PanelContainer
var _scroll: ScrollContainer
var _text: RichTextLabel
var _actions: HBoxContainer
var _anykey_hint: HBoxContainer
var _close: Button


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scrim = ColorRect.new()
	_scrim.color = Slate.SCRIM
	_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_scrim.gui_input.connect(_on_scrim_input)
	add_child(_scrim)

	_center = CenterContainer.new()
	_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_center)

	# Popups the game puts at the top of the screen are notices, not questions.
	_top_box = MarginContainer.new()
	_top_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_top_box.add_theme_constant_override("margin_top", 72)
	_top_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_top_box)

	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", Slate.card_box(18, 22))
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_card.gui_input.connect(_on_card_input)
	_center.add_child(_card)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	_card.add_child(col)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	col.add_child(body)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(_scroll)
	_text = Slate.rich(15)
	_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text.add_theme_constant_override("line_separation", 3)
	_text.selection_enabled = false
	_scroll.add_child(_text)

	_close = Button.new()
	_close.icon = Slate.icon("x", 18)
	_close.tooltip_text = "Close (Esc)"
	_close.custom_minimum_size = Vector2(32, 32)
	_close.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_close.add_theme_color_override("icon_normal_color", Slate.MUTED)
	_close.add_theme_color_override("icon_hover_color", Slate.TEXT)
	_close.pressed.connect(func(): Bridge.press(view_id, "QUIT"))
	body.add_child(_close)

	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 10)
	col.add_child(foot)
	_anykey_hint = HBoxContainer.new()
	_anykey_hint.add_theme_constant_override("separation", 8)
	_anykey_hint.add_child(Slate.label("Press any key or click to continue", 13, Slate.MUTED))
	_anykey_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(_anykey_hint)
	_actions = HBoxContainer.new()
	_actions.add_theme_constant_override("separation", 10)
	_actions.alignment = BoxContainer.ALIGNMENT_END
	_actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(_actions)
	resized.connect(_layout)
	# A new view stays hidden until the game's next frame lists it, and text measured while
	# hidden has no width, so measure again once it shows.
	visibility_changed.connect(_layout)


func apply(msg: Dictionary) -> void:
	var spans: Array = msg.get("text", [])
	_text.text = Slate.bbcode(spans).strip_edges()
	_anykey = bool(msg.get("anykey", false))
	_cancel = bool(msg.get("cancel", false))
	_top = bool(msg.get("top", false))
	_full = bool(msg.get("full", false))
	_cursor = int(msg.get("cursor", 0))
	var buttons: Array = msg.get("buttons", [])
	if buttons != _buttons_data:
		_buttons_data = buttons
		_rebuild_buttons()
	_restyle_buttons()

	_close.visible = _cancel and buttons.is_empty()
	_anykey_hint.visible = _anykey
	_actions.get_parent().visible = _anykey or not buttons.is_empty()
	_scrim.visible = not _top
	_card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if _anykey else Control.CURSOR_ARROW

	# A notice sits at the top of the screen, a question in the middle.
	var parent := _card.get_parent()
	var wanted: Control = _top_box if _top else _center
	if parent != wanted:
		parent.remove_child(_card)
		wanted.add_child(_card)
	_layout()


func _rebuild_buttons() -> void:
	for c in _actions.get_children():
		c.queue_free()
	for i in _buttons_data.size():
		var data: Dictionary = _buttons_data[i]
		var b := AnswerButton.new()
		b.setup(String(data.get("label", "")), String(data.get("key", "")))
		b.pressed.connect(func(): Bridge.pick(view_id, i))
		_actions.add_child(b)


func _restyle_buttons() -> void:
	var i := 0
	for b in _actions.get_children():
		if b is AnswerButton and not b.is_queued_for_deletion():
			b.set_primary(i == _cursor)
			i += 1


func _layout() -> void:
	if _card == null or not is_inside_tree():
		return
	var viewport := get_viewport_rect().size
	var plain := _text.get_parsed_text()
	var longest := 0.0
	for line in plain.split("\n"):
		longest = maxf(longest, Slate.body().get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x)
	var width := 0.0
	if _full:
		width = minf(viewport.x - 160, 980)
	else:
		width = clampf(longest + 60, 380, minf(620, viewport.x - 80))
	_card.custom_minimum_size.x = width
	_text.custom_minimum_size.x = width - 44 - (44 if _close.visible else 0)
	# Long texts scroll inside the card instead of running off screen.
	var max_text := viewport.y - (140 if _full else 260)
	_scroll.custom_minimum_size.y = 0
	await get_tree().process_frame
	if is_instance_valid(_text):
		_scroll.custom_minimum_size.y = minf(_text.get_content_height(), max_text) if not _full else max_text
	if _top:
		_top_box.position.x = (viewport.x - _card.size.x) / 2


func _on_scrim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _anykey:
			Bridge.press(view_id, "CONFIRM")
		elif _cancel:
			Bridge.press(view_id, "QUIT")


func _on_card_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and _anykey:
		Bridge.press(view_id, "CONFIRM")


class AnswerButton extends Button:
	var _label: Label
	var _chip: PanelContainer
	var _primary := false

	func setup(text: String, key: String) -> void:
		custom_minimum_size = Vector2(96, 40)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(row)
		_label = Slate.label(text, 14, Slate.TEXT, Slate.bold())
		row.add_child(_label)
		_chip = Slate.key_chip(key, 11)
		row.add_child(_chip)
		var w := Slate.bold().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		w += 0.0 if key == "" else 14 + Slate.mono().get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 8
		custom_minimum_size.x = maxf(96, w + 36)
		_restyle()

	func set_primary(on: bool) -> void:
		_primary = on
		_restyle()

	func _restyle() -> void:
		var bg := Slate.ACCENT if _primary else Color(1, 1, 1, 0.06)
		var hot := Slate.ACCENT.lightened(0.12) if _primary else Color(1, 1, 1, 0.11)
		var border := Color(0, 0, 0, 0) if _primary else Slate.BORDER_STRONG
		add_theme_stylebox_override("normal", Slate.box(bg, 10, border, 1))
		add_theme_stylebox_override("hover", Slate.box(hot, 10, border, 1))
		add_theme_stylebox_override("pressed", Slate.box(hot.darkened(0.1), 10, border, 1))
		add_theme_stylebox_override("hover_pressed", Slate.box(hot.darkened(0.1), 10, border, 1))
		_label.add_theme_color_override("font_color", Slate.ACCENT_TEXT if _primary else Slate.TEXT)
		var chip_bg := Color(0, 0, 0, 0.16) if _primary else Color(1, 1, 1, 0.08)
		_chip.add_theme_stylebox_override("panel", Slate.pill_box(chip_bg, 6, 1))
		(_chip.get_child(0) as Label).add_theme_color_override("font_color",
				Color(Slate.ACCENT_TEXT, 0.75) if _primary else Slate.MUTED)
