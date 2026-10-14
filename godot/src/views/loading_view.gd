extends Control
## The game's loading progress (`loading_ui`): what it is loading, the step it is on and how far
## along it is, as a small card low on the screen so the loading art stays in view.

var view_id := 0

var _title: Label
var _count: Label
var _bar: ProgressBar
var _step: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := MarginContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	box.add_theme_constant_override("margin_bottom", 48)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", Slate.card_box(14, 18))
	card.custom_minimum_size = Vector2(520, 0)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(card)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	card.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	col.add_child(head)
	_title = Slate.label("", 16, Slate.TEXT, Slate.bold())
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head.add_child(_title)
	_count = Slate.label("", 13, Slate.MUTED, Slate.mono())
	head.add_child(_count)

	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(0, 6)
	_bar.show_percentage = false
	_bar.add_theme_stylebox_override("background", Slate.box(Slate.TRACK, 3, Slate.BORDER, 0))
	_bar.add_theme_stylebox_override("fill", Slate.box(Slate.ACCENT, 3, Slate.BORDER, 0))
	col.add_child(_bar)

	_step = Slate.label("", 13, Slate.MUTED)
	_step.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(_step)


func apply(msg: Dictionary) -> void:
	_title.text = String(msg.get("title", ""))
	var total := int(msg.get("total", 0))
	var done := int(msg.get("done", 0))
	_count.text = "%d / %d" % [done, total] if total > 0 else ""
	_bar.indeterminate = total == 0
	_bar.max_value = maxi(total, 1)
	_bar.value = done
	_step.text = String(msg.get("step", ""))
