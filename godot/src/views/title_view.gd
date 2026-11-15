extends Control
## The title screen (view kind `title`): the game's title art over a column of sections (new game,
## load, worlds, settings, ...) and a panel with the chosen section's choices, plus the tip of the
## day. Keys work as in the old main menu. Clicking a section opens it, clicking a choice selects
## it, and clicking the selected choice again (or double clicking) opens it. Characters in the
## selected world, and the Continue card, load at once.

const SlateButton := preload("res://src/ui/slate_button.gd")

const Hud := preload("res://src/ui/hud.gd")

const LINE_HEIGHT := 22.0
const GUT := 8
const TOP := 58
const NAV_WIDTH := 400

var view_id := 0

var _msg := {}
var _bezel: Bezel
var _glow: TextureRect
var _art: RichTextLabel
var _nav: VBoxContainer
var _nav_module: Hud.Module
var _continue_slot: VBoxContainer
var _tabs: VBoxContainer
var _section_module: Hud.Module
var _list_scroll: ScrollContainer
var _list: VBoxContainer
var _empty: Label
var _text_scroll: ScrollContainer
var _text: RichTextLabel
var _action: CenterContainer
var _action_icon: TextureRect
var _action_text: Label
var _action_slot: HBoxContainer
var _tip: RichTextLabel
var _notice: RichTextLabel
var _hints: HBoxContainer
var _last_scroll := -1
var _last_section := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

	# The same frame as in the game: gunmetal ground, a bar up top, a viewport (here it shows
	# the title), modules below it and a strip of keys along the bottom.
	var ground := ColorRect.new()
	ground.color = Slate.GROUND
	ground.set_anchors_preset(Control.PRESET_FULL_RECT)
	ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ground)

	var outer := MarginContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		outer.add_theme_constant_override("margin_" + side, GUT)
	add_child(outer)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", GUT)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(col)

	col.add_child(_build_top())

	_bezel = Bezel.new()
	col.add_child(_bezel)
	# A soft light behind the title art.
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color(Slate.CYAN, 0.16), Color(Slate.CYAN, 0.0)])
	var light := GradientTexture2D.new()
	light.gradient = gradient
	light.fill = GradientTexture2D.FILL_RADIAL
	light.fill_from = Vector2(0.5, 0.5)
	light.fill_to = Vector2(1.0, 0.5)
	light.width = 512
	light.height = 256
	_glow = TextureRect.new()
	_glow.texture = light
	_glow.stretch_mode = TextureRect.STRETCH_SCALE
	_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bezel.add_child(_glow)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bezel.add_child(center)
	_art = Slate.rich(14, true)
	_art.autowrap_mode = TextServer.AUTOWRAP_OFF
	_art.add_theme_font_override("normal_font", Slate.mono())
	_art.add_theme_constant_override("line_separation", -2)
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(_art)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", GUT)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(row)
	row.add_child(_build_nav())
	row.add_child(_build_panel())

	col.add_child(_build_footer())
	resized.connect(_layout)


# --- Building ------------------------------------------------------------------------------------

func _panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Slate.module_box(0))
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	return p


## The bar along the top: the game's name where the character's stands in play, and where you are.
func _build_top() -> Control:
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", GUT)
	top.custom_minimum_size.y = TOP
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var identity := _panel()
	identity.custom_minimum_size.x = NAV_WIDTH
	var id_row := HBoxContainer.new()
	id_row.add_theme_constant_override("separation", 10)
	id_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	identity.add_child(_margin(id_row, 14, 0, 12, 0))
	var name := Slate.label("Bright Nights", 18, Slate.TEXT, Slate.spaced(Slate.heavy(), 1))
	name.uppercase = true
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	id_row.add_child(name)
	top.add_child(identity)
	var bar := _panel()
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bar_row := HBoxContainer.new()
	bar_row.add_theme_constant_override("separation", 14)
	bar_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(_margin(bar_row, 18, 0, 14, 0))
	var title := Slate.label("Main menu", 17, Slate.CYAN, Slate.spaced(Slate.heavy(), 2))
	title.uppercase = true
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar_row.add_child(title)
	top.add_child(bar)
	return top


func _build_nav() -> Control:
	_nav_module = Hud.Module.new("Menu")
	_nav_module.custom_minimum_size.x = NAV_WIDTH
	_nav = VBoxContainer.new()
	_nav.add_theme_constant_override("separation", 10)
	_nav.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_continue_slot = VBoxContainer.new()
	_continue_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_nav.add_child(_continue_slot)
	_tabs = VBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 2)
	_tabs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_nav.add_child(_tabs)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_nav.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_nav)
	_nav_module.set_body(scroll, 10, 10)
	return _nav_module


func _build_panel() -> Control:
	_section_module = Hud.Module.new("", Slate.ACCENT)
	_section_module.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var stack := Control.new()
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_section_module.set_body(stack, 0, 0)

	_list_scroll = ScrollContainer.new()
	_list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	stack.add_child(_list_scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_scroll.add_child(_margin(_list, 12, 12, 14, 12))

	_empty = Slate.label("", 14, Slate.MUTED)
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty.set_anchors_preset(Control.PRESET_FULL_RECT)
	stack.add_child(_empty)

	_text_scroll = ScrollContainer.new()
	_text_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_text_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	stack.add_child(_text_scroll)
	_text = Slate.rich(14, true)
	_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text.add_theme_color_override("default_color", Slate.SOFT)
	_text.add_theme_constant_override("line_separation", 4)
	_text_scroll.add_child(_margin(_text, 22, 16, 26, 16))

	_action = CenterContainer.new()
	_action.set_anchors_preset(Control.PRESET_FULL_RECT)
	_action.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(_action)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	_action.add_child(box)
	_action_icon = Slate.icon_rect("book-open", 40, Slate.MUTED)
	_action_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(_action_icon)
	_action_text = Slate.label("", 15, Slate.SOFT)
	_action_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_action_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_action_text.custom_minimum_size.x = 420
	box.add_child(_action_text)
	_action_slot = HBoxContainer.new()
	_action_slot.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(_action_slot)
	return _section_module


## The strip along the bottom: the tip of the day, and the keys.
func _build_footer() -> Control:
	var strip := _panel()
	strip.custom_minimum_size.y = 38
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 18)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.add_child(_margin(bar, 14, 7, 14, 7))

	var tip := HBoxContainer.new()
	tip.add_theme_constant_override("separation", 10)
	tip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bulb := Slate.icon_rect("lightbulb", 16, Slate.ACCENT)
	bulb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tip.add_child(bulb)
	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", 2)
	lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lines.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip.add_child(lines)
	_tip = Slate.rich(13)
	_tip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lines.add_child(_tip)
	_notice = Slate.rich(12)
	lines.add_child(_notice)
	bar.add_child(tip)

	_hints = HBoxContainer.new()
	_hints.add_theme_constant_override("separation", 16)
	_hints.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(_hints)
	return strip


func _margin(child: Control, left: int, top: int, right: int, bottom: int) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", left)
	m.add_theme_constant_override("margin_top", top)
	m.add_theme_constant_override("margin_right", right)
	m.add_theme_constant_override("margin_bottom", bottom)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.add_child(child)
	return m


func _layout() -> void:
	if _art == null:
		return
	var view := size
	# The viewport takes a good quarter of the window, and the art fills it without losing its
	# shape: the font shrinks until it fits.
	var room := Vector2(view.x - 2 * GUT - 80, clampf(roundf(view.y * 0.28), 120, 320))
	_bezel.custom_minimum_size.y = room.y
	var art: Array = _msg.get("art", [])
	var cols := 1
	for line in art:
		cols = maxi(cols, Slate.plain(line).length())
	var lines := maxi(1, art.size())
	var font := Slate.mono()
	var size_px := 22
	while size_px > 7:
		var w := font.get_string_size("M", HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x * cols
		var h := (font.get_height(size_px) - 2) * lines
		if w <= minf(room.x, 1100) and h <= room.y - 44:
			break
		size_px -= 1
	if art.size() <= 1:
		size_px = 34
		_art.add_theme_font_override("normal_font", Slate.heavy())
	else:
		_art.add_theme_font_override("normal_font", font)
	_art.add_theme_font_size_override("normal_font_size", size_px)
	# A narrow window keeps most of its width for the section's choices.
	var nav_width := minf(NAV_WIDTH, roundf(view.x * 0.32))
	_nav_module.custom_minimum_size.x = nav_width


# --- Updates from the game -----------------------------------------------------------------------

func apply(msg: Dictionary) -> void:
	var art_changed: bool = msg.get("art", []) != _msg.get("art", [])
	_msg = msg
	if art_changed:
		var text := PackedStringArray()
		for line in msg.get("art", []):
			text.append(Slate.bbcode(line, Slate.TEXT))
		_art.text = "\n".join(text)
	_bezel.set_tag(String(msg.get("version", "")))
	_apply_nav(msg)
	_apply_section(msg.get("section", {}))
	_tip.text = Slate.bbcode(msg.get("tip", []), Slate.SOFT)
	_notice.text = Slate.bbcode(msg.get("notice", []), Slate.MUTED)
	_apply_hints(msg.get("hints", []))
	_layout()


func _apply_nav(msg: Dictionary) -> void:
	for c in _continue_slot.get_children():
		c.queue_free()
	var cont: Dictionary = msg.get("continue", {})
	if not cont.is_empty():
		_continue_slot.add_child(_continue_card(cont))
	for c in _tabs.get_children():
		c.queue_free()
	for t in msg.get("tabs", []):
		_tabs.add_child(_tab(t))


func _continue_card(spec: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var restyle := func(hover: bool):
		var sb := Slate.box(Slate.ACCENT.lightened(0.1) if hover else Slate.ACCENT, 14, Slate.BORDER, 0)
		sb.content_margin_left = 16
		sb.content_margin_right = 16
		sb.content_margin_top = 12
		sb.content_margin_bottom = 12
		card.add_theme_stylebox_override("panel", sb)
	restyle.call(false)
	card.mouse_entered.connect(restyle.bind(true))
	card.mouse_exited.connect(restyle.bind(false))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)
	row.add_child(Slate.icon_rect("circle-play", 26, Slate.ACCENT_TEXT))
	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", 0)
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lines)
	lines.add_child(Slate.label(String(spec.get("text", "Continue")), 16, Slate.ACCENT_TEXT, Slate.heavy()))
	var who := Slate.label("%s  ·  %s" % [spec.get("name", ""), spec.get("world", "")], 12, Color(Slate.ACCENT_TEXT, 0.75), Slate.semibold())
	who.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	lines.add_child(who)
	var pick := int(spec.get("pick", 0))
	card.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			card.accept_event()
			Bridge.pick(view_id, pick, ""))
	return card


func _tab(t: Dictionary) -> Control:
	var active := bool(t.get("active", false))
	var item := PanelContainer.new()
	item.mouse_filter = Control.MOUSE_FILTER_STOP
	item.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var restyle := func(hover: bool):
		var bg := Color(1, 1, 1, 0.09) if active else (Color(1, 1, 1, 0.05) if hover else Color(0, 0, 0, 0))
		var sb := Slate.box(bg, 10, Slate.BORDER, 0)
		if active:
			sb.border_width_left = 3
			sb.border_color = Slate.ACCENT
		sb.content_margin_left = 14
		sb.content_margin_right = 12
		sb.content_margin_top = 9
		sb.content_margin_bottom = 9
		item.add_theme_stylebox_override("panel", sb)
	restyle.call(false)
	item.mouse_entered.connect(restyle.bind(true))
	item.mouse_exited.connect(restyle.bind(false))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item.add_child(row)
	row.add_child(Slate.icon_rect(String(t.get("icon", "chevron-right")), 18, Slate.ACCENT if active else Slate.MUTED))
	var label := Slate.label(String(t.get("text", "")), 15, Slate.TEXT if active else Slate.SOFT, Slate.bold() if active else Slate.semibold())
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var key := String(t.get("key", ""))
	if key != "":
		row.add_child(Slate.key_chip(key, 10))
	var pick := int(t.get("pick", 0))
	item.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			item.accept_event()
			Bridge.pick(view_id, pick, ""))
	return item


func _apply_section(section: Dictionary) -> void:
	var section_title := String(section.get("title", ""))
	_section_module.set_title(section_title, Slate.ACCENT)
	var rows: Array = section.get("rows", [])
	var body := Slate.bbcode(section.get("body", []), Slate.SOFT)
	var action: Dictionary = section.get("action", {})
	_list_scroll.visible = not rows.is_empty()
	_text_scroll.visible = body != ""
	_action.visible = not action.is_empty()
	_empty.visible = rows.is_empty() and body == "" and action.is_empty()
	_empty.text = String(section.get("empty", ""))

	var key := "%s|%s" % [section_title, body.length()]
	if body != "":
		if key != _last_section:
			_text.text = Slate.tidy_body(body)
			_last_scroll = -1
		var scroll := int(section.get("scroll", 0))
		if scroll != _last_scroll:
			_last_scroll = scroll
			_text_scroll.scroll_vertical = int(scroll * LINE_HEIGHT)
	_last_section = key

	for c in _list.get_children():
		c.queue_free()
	var cursor := int(section.get("cursor", -1))
	var selected: Control = null
	for r in rows:
		var on := int(r.get("pick", -1)) == cursor
		var row := _choice(r, on)
		_list.add_child(row)
		if on:
			selected = row
	if selected != null:
		_list_scroll.ensure_control_visible.call_deferred(selected)

	for c in _action_slot.get_children():
		c.queue_free()
	if not action.is_empty():
		_action_icon.texture = Slate.icon(String(section.get("icon", "play")), 40)
		_action_text.text = String(action.get("text", ""))
		var spec: Dictionary = action
		var b := SlateButton.new(String(spec.get("icon", "")), String(spec.get("text", "")), true)
		b.set_key(String(spec.get("key", "")))
		var act := String(spec.get("act", ""))
		b.pressed.connect(func(): Bridge.press(view_id, act))
		_action_slot.add_child(b)


func _choice(r: Dictionary, on: bool) -> Control:
	var item := PanelContainer.new()
	item.mouse_filter = Control.MOUSE_FILTER_PASS
	item.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var restyle := func(hover: bool):
		var bg := Color(Slate.ACCENT, 0.10) if on else (Color(1, 1, 1, 0.05) if hover else Color(0, 0, 0, 0))
		var sb := Slate.box(bg, 12, Color(Slate.ACCENT, 0.45) if on else Slate.BORDER, 1 if on else 0)
		sb.content_margin_left = 14
		sb.content_margin_right = 14
		sb.content_margin_top = 10
		sb.content_margin_bottom = 10
		item.add_theme_stylebox_override("panel", sb)
	restyle.call(false)
	item.mouse_entered.connect(restyle.bind(true))
	item.mouse_exited.connect(restyle.bind(false))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item.add_child(row)
	var tile := PanelContainer.new()
	tile.add_theme_stylebox_override("panel", Slate.box(Color(Slate.ACCENT, 0.16) if on else Color(1, 1, 1, 0.06), 10, Slate.BORDER, 0))
	tile.custom_minimum_size = Vector2(38, 38)
	tile.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon := Slate.icon_rect(String(r.get("icon", "chevron-right")), 20, Slate.ACCENT if on else Slate.SOFT)
	tile.add_child(icon)
	row.add_child(tile)

	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", 3)
	lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(lines)
	var title := Slate.rich(15)
	title.add_theme_font_override("normal_font", Slate.bold())
	title.text = Slate.bbcode(r.get("text", []), Slate.TEXT)
	lines.add_child(title)
	var note := Slate.bbcode(r.get("note", []), Slate.MUTED)
	if note != "":
		var n := Slate.rich(13)
		n.add_theme_color_override("default_color", Slate.MUTED)
		n.text = note
		lines.add_child(n)
	var saves: Array = r.get("saves", [])
	if note == "" and (not on or saves.is_empty()):
		lines.alignment = BoxContainer.ALIGNMENT_CENTER
	if on and not saves.is_empty():
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 8)
		flow.add_theme_constant_override("v_separation", 8)
		lines.add_child(_margin(flow, 0, 6, 0, 0))
		for s in saves:
			var b := SlateButton.new("user-round", String(s.get("text", "")), false, true)
			var pick := int(s.get("pick", 0))
			b.pressed.connect(func(): Bridge.pick(view_id, pick, ""))
			flow.add_child(b)

	var key := String(r.get("key", ""))
	if key != "":
		var chip := Slate.key_chip(key, 11)
		chip.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(chip)

	var pick := int(r.get("pick", 0))
	item.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			item.accept_event()
			Bridge.pick(view_id, pick, "CONFIRM" if on or e.double_click else ""))
	return item


func _apply_hints(hints: Array) -> void:
	for c in _hints.get_children():
		c.queue_free()
	for h in hints:
		var key := String(h.get("key", ""))
		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 6)
		item.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if key != "":
			item.add_child(Slate.key_chip(Slate.key_name(key), 10))
		item.add_child(Slate.label(String(h.get("text", "")), 12, Slate.MUTED))
		_hints.add_child(item)


## The viewport's bezel, as around the map in play: here the title stands in it.
class Bezel extends Control:
	var _tag := ""

	func _init() -> void:
		clip_contents = true
		mouse_filter = Control.MOUSE_FILTER_STOP

	func set_tag(text: String) -> void:
		if text != _tag:
			_tag = text
			queue_redraw()

	func _draw() -> void:
		var v := Rect2(Vector2.ZERO, size)
		draw_rect(v, Color("#03090b"))
		draw_rect(v.grow(-1), Color(Slate.CYAN, 0.75), false, 2.0)
		draw_rect(v.grow(-2.5), Color(0, 0, 0, 0.55), false, 1.0)
		var arm := 22.0
		var inset := v.grow(-9)
		for corner in [[inset.position, Vector2(1, 1)], [Vector2(inset.end.x, inset.position.y), Vector2(-1, 1)],
				[Vector2(inset.position.x, inset.end.y), Vector2(1, -1)], [inset.end, Vector2(-1, -1)]]:
			var at: Vector2 = corner[0]
			var way: Vector2 = corner[1]
			draw_polyline(PackedVector2Array([at + Vector2(arm * way.x, 0), at, at + Vector2(0, arm * way.y)]), Slate.CYAN, 2.0)
		if _tag == "":
			return
		var font := Slate.mono()
		var fs := Slate.fs(10)
		var text := _tag.to_upper()
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 14
		var box := Rect2(Vector2(inset.end.x - arm - 8 - w, inset.end.y - 15), Vector2(w, 18))
		draw_rect(box, Color(Slate.CARD, 0.9))
		draw_rect(box.grow(-0.5), Color(Slate.CYAN, 0.6), false, 1.0)
		draw_string(font, Vector2(box.position.x + 7, box.position.y + 13), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Slate.CYAN)
