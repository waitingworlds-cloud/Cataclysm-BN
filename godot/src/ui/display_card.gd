extends Control
## Card for the interface and map sizes (see display.gd), opened from the HUD's monitor button.
## The keyboard shortcuts it lists work everywhere, so it is never needed for keyboard play.

const SlateButton := preload("res://src/ui/slate_button.gd")

var _ui_value: Label
var _map_value: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var scrim := ColorRect.new()
	scrim.color = Slate.SCRIM
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scrim)
	# A click outside the card closes it.
	gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			queue_free())

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", Slate.card_box(18, 20))
	card.custom_minimum_size.x = 540
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	card.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	col.add_child(head)
	head.add_child(Slate.icon_rect("monitor", 20, Slate.ACCENT))
	var title := Slate.label("Display", 18, Slate.TEXT, Slate.heavy())
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := Button.new()
	close.icon = Slate.icon("x", 18)
	close.flat = true
	close.focus_mode = Control.FOCUS_NONE
	close.tooltip_text = "Close"
	close.pressed.connect(queue_free)
	head.add_child(close)

	_ui_value = _stepper(col, "Interface size", "Text, cards and bars.", "Ctrl = / Ctrl −",
			Display.step_ui)
	_map_value = _stepper(col, "Map size", "Bigger tiles, drawn with sharp pixels. The zoom buttons still zoom on top of this.",
			"Ctrl Shift = / Ctrl Shift −", Display.step_map)

	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 10)
	col.add_child(foot)
	var auto := SlateButton.new("refresh-cw", "Automatic sizes")
	auto.set_key("Ctrl 0")
	auto.pressed.connect(Display.reset)
	foot.add_child(auto)
	var note := Slate.label("Automatic sizes follow your screen: 4K is 200% with a 3× map.", 12, Slate.FAINT)
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	foot.add_child(note)

	Display.changed.connect(_refresh)
	_refresh()


## Escape closes the card instead of reaching the game.
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		queue_free()


func _stepper(parent: Control, name: String, help: String, keys: String, step: Callable) -> Label:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 2)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	text.add_child(Slate.label(name, 14, Slate.TEXT, Slate.bold()))
	var sub := Slate.label(help, 12, Slate.MUTED)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(sub)
	text.add_child(Slate.label(keys, 11, Slate.FAINT, Slate.mono()))
	var less := _round_button("minus", "Smaller")
	less.pressed.connect(func(): step.call(-1))
	row.add_child(less)
	var value := Slate.label("", 15, Slate.ACCENT, Slate.mono_bold())
	value.custom_minimum_size.x = 92
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(value)
	var more := _round_button("plus", "Bigger")
	more.pressed.connect(func(): step.call(1))
	row.add_child(more)
	return value


func _round_button(icon_name: String, tooltip: String) -> Button:
	var b := Button.new()
	b.icon = Slate.icon(icon_name, 16)
	b.tooltip_text = tooltip
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(36, 36)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var plain := Slate.box(Color(1, 1, 1, 0.06), 10, Slate.BORDER, 1)
	plain.set_content_margin_all(0)
	b.add_theme_stylebox_override("normal", plain)
	var hot := Slate.box(Color(1, 1, 1, 0.14), 10, Slate.BORDER_STRONG, 1)
	hot.set_content_margin_all(0)
	b.add_theme_stylebox_override("hover", hot)
	b.add_theme_stylebox_override("pressed", hot)
	return b


func _refresh() -> void:
	_ui_value.text = "%d%%" % roundi(Display.ui_scale() * 100) + (" auto" if Display.ui_choice <= 0.0 else "")
	_map_value.text = "%d×" % Display.map_scale() + (" auto" if Display.map_choice <= 0 else "")
