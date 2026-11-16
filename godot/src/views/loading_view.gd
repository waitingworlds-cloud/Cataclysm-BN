extends Control
## The game's loading progress (`loading_ui`): what it is loading, the step it is on and how far
## along it is. A card in the frame's look, low on the screen so the loading art stays in view,
## with a segmented hazard bar, the steps so far and the tip of the day to read while waiting.

const CELLS := 40

var view_id := 0

var _title: Label
var _count: Label
var _bar: Control
var _step: Label
var _done_list: VBoxContainer
var _tip: RichTextLabel
var _tip_box: Control
var _level := 0.0
var _shown := 0.0
var _unknown := true
var _last_step := ""
var _steps: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The art dims toward the edges, so the card and the frame hold the eye.
	var shade := Control.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.draw.connect(func():
		var r := Rect2(Vector2.ZERO, shade.size)
		var depth := minf(r.size.x, r.size.y) * 0.32
		var dark := Color(0.012, 0.035, 0.043, 0.82)
		var clear := Color(dark, 0.0)
		var i := r.grow(-depth)
		for q in [[r.position, Vector2(r.end.x, r.position.y), Vector2(i.end.x, i.position.y), i.position],
				[Vector2(r.end.x, r.position.y), r.end, i.end, Vector2(i.end.x, i.position.y)],
				[r.end, Vector2(r.position.x, r.end.y), Vector2(i.position.x, i.end.y), i.end],
				[Vector2(r.position.x, r.end.y), r.position, i.position, Vector2(i.position.x, i.end.y)]]:
			shade.draw_polygon(PackedVector2Array(q), PackedColorArray([dark, dark, clear, clear]))
		# The frame's bezel and corner marks.
		var v := r.grow(-8)
		for step in 4:
			shade.draw_rect(v.grow(1.5 + step * 2.0), Color(Slate.CYAN, 0.16 - step * 0.035), false, 2.0)
		shade.draw_rect(v, Color(Slate.CYAN, 0.75), false, 2.0)
		var arm := 22.0
		var inset := v.grow(-9)
		for corner in [[inset.position, Vector2(1, 1)], [Vector2(inset.end.x, inset.position.y), Vector2(-1, 1)],
				[Vector2(inset.position.x, inset.end.y), Vector2(1, -1)], [inset.end, Vector2(-1, -1)]]:
			var at: Vector2 = corner[0]
			var way: Vector2 = corner[1]
			shade.draw_polyline(PackedVector2Array([at + Vector2(arm * way.x, 0), at, at + Vector2(0, arm * way.y)]), Slate.CYAN, 2.0))
	shade.resized.connect(shade.queue_redraw)
	add_child(shade)

	var box := MarginContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	box.add_theme_constant_override("margin_bottom", 56)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)

	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 10)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(stack)

	var card := PanelContainer.new()
	var sb := Slate.card_box(14, 0)
	sb.bg_color = Color(Slate.CARD, 0.94)
	card.add_theme_stylebox_override("panel", sb)
	card.custom_minimum_size = Vector2(640, 0)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(card)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	card.add_child(col)

	_title = Slate.prompt_title()
	_title.add_theme_color_override("font_color", Slate.CYAN)
	_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_count = Slate.label("", 13, Slate.ACCENT, Slate.mono())
	_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(6, 0)
	col.add_child(Slate.prompt_head(_title, [_count, spacer]))

	var body := MarginContainer.new()
	for side in ["left", "right"]:
		body.add_theme_constant_override("margin_" + side, 18)
	body.add_theme_constant_override("margin_top", 14)
	body.add_theme_constant_override("margin_bottom", 14)
	col.add_child(body)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 10)
	body.add_child(inner)

	_bar = Control.new()
	_bar.custom_minimum_size = Vector2(0, 16)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.draw.connect(_draw_bar)
	inner.add_child(_bar)

	_done_list = VBoxContainer.new()
	_done_list.add_theme_constant_override("separation", 2)
	inner.add_child(_done_list)

	_step = Slate.label("", 13, Slate.TEXT, Slate.mono())
	_step.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	inner.add_child(_step)

	_tip_box = PanelContainer.new()
	var tb := Slate.box(Color(Slate.CARD, 0.94), 12, Slate.BORDER_STRONG, 1)
	tb.content_margin_left = 16
	tb.content_margin_right = 16
	tb.content_margin_top = 9
	tb.content_margin_bottom = 9
	_tip_box.add_theme_stylebox_override("panel", tb)
	_tip_box.custom_minimum_size = Vector2(640, 0)
	_tip_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(_tip_box)
	var tip_row := HBoxContainer.new()
	tip_row.add_theme_constant_override("separation", 10)
	_tip_box.add_child(tip_row)
	var bulb := Slate.icon_rect("lightbulb", 18, Slate.ACCENT)
	bulb.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	tip_row.add_child(bulb)
	_tip = Slate.rich(13)
	_tip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tip_row.add_child(_tip)
	_tip.text = Fx.last_tip
	_tip_box.visible = Fx.last_tip != ""


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	# The bar eases toward where loading really is, so it never jumps.
	_shown = move_toward(_shown, _level, delta * maxf(absf(_level - _shown) * 6.0, 0.2))
	_bar.queue_redraw()


## Slanted hazard-yellow cells; the newest lit ones glow. With no total to count toward, a
## group of lit cells runs along the bar instead.
func _draw_bar() -> void:
	var gap := 3.0
	var w := (_bar.size.x - gap * (CELLS - 1)) / CELLS
	var h := _bar.size.y
	var lean := h * 0.32
	var t := Time.get_ticks_msec() / 1000.0
	for i in CELLS:
		var x := i * (w + gap)
		var on := float(i) / CELLS < _shown
		var head := on and float(i + 3) / CELLS >= _shown
		if _unknown:
			var run := fmod(t * 0.7, 1.0) * (CELLS + 8) - 8
			on = i >= run and i < run + 8
			head = on
		var quad := PackedVector2Array([Vector2(x + lean, 0), Vector2(x + w + lean, 0), Vector2(x + w, h), Vector2(x, h)])
		if head:
			var halo := PackedVector2Array([Vector2(x + lean - 3, -3), Vector2(x + w + lean + 3, -3), Vector2(x + w + 3, h + 3), Vector2(x - 3, h + 3)])
			_bar.draw_colored_polygon(halo, Color(Slate.ACCENT, 0.18))
		_bar.draw_colored_polygon(quad, Slate.ACCENT if on else Color(Slate.CYAN, 0.12))


func apply(msg: Dictionary) -> void:
	_title.text = String(msg.get("title", ""))
	var total := int(msg.get("total", 0))
	var done := int(msg.get("done", 0))
	_unknown = total == 0
	_level = float(done) / maxi(total, 1)
	_count.text = "%d%%" % roundi(_level * 100) if total > 0 else ""
	var step := String(msg.get("step", ""))
	if step != _last_step:
		# Steps already finished stay listed, ticked, a few deep.
		if _last_step != "":
			_steps.append(_last_step)
			if _steps.size() > 3:
				_steps.pop_front()
			for c in _done_list.get_children():
				c.queue_free()
			for s in _steps:
				var row := Slate.label("[x] " + s, 12, Slate.FAINT, Slate.mono())
				row.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
				_done_list.add_child(row)
		_last_step = step
	_step.text = ("> " + step + "...") if step != "" else ""
