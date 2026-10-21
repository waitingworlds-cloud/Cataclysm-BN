extends Control
## A list menu (the game's `uilist`): a centered card with a title, optional search and category
## tabs, rows with key hints, and a description panel. The game owns the selection and the
## filter; clicking a row picks it, which the game handles as if its key had been pressed.

const ROW_HEIGHT := 38
## Height a row takes in the list, with the gap below it.
const ROW_STEP := ROW_HEIGHT + 2
## Rows built at a time. A long menu (the map editor lists thousands of terrain types) builds only
## the stretch around what is in view; spacers keep the scroll bar true to the whole list.
const WINDOW := 120
const MIN_WIDTH := 440.0
const MAX_WIDTH := 920.0
## A line the game drew across a panel to separate sections.
static var _RULE := RegEx.create_from_string("(?m)^(\\[/?color[^\\]]*\\])*[─-]{3,}(\\[/?color[^\\]]*\\])*$")

var view_id := 0

var _entries: Array = []
var _shown: Array = []
var _selected := -1
var _hovered := -1
var _cancel := false
var _describe := false
var _rows := {}
var _rows_dirty := true
var _has_keys := false
## Entries of the shown rows, in order, and the position in it of the first row built.
var _listed: Array = []
var _first := 0
var _top_pad: Control
var _bottom_pad: Control
## Width of the widest entry's text, measured when the entries arrive.
var _widest := 0.0

var _scrim: ColorRect
var _card: PanelContainer
var _title: Label
var _close: Button
var _text: RichTextLabel
var _tabs: HBoxContainer
var _tab_label: Label
var _search: PanelContainer
var _search_text: Label
var _search_key: PanelContainer
var _scroll: ScrollContainer
var _list: VBoxContainer
var _empty: Label
var _desc_box: PanelContainer
var _desc: RichTextLabel
var _footer: RichTextLabel
var _hints: HBoxContainer
var _body: HBoxContainer
var _side: PanelContainer
var _side_scroll: ScrollContainer
var _side_text: RichTextLabel
var _side_cols := 0
var _side_lines := 0
var _center: CenterContainer
## Where the menu opens as a context menu (the mouse, in interface units), or null for centered.
var _anchor = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scrim = ColorRect.new()
	_scrim.color = Slate.SCRIM
	_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_scrim.gui_input.connect(_on_scrim_input)
	add_child(_scrim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_center = center

	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", Slate.card_box(18, 0))
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(_card)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	_card.add_child(col)

	col.add_child(_build_header())
	col.add_child(_build_search())
	_body = HBoxContainer.new()
	_body.add_theme_constant_override("separation", 0)
	col.add_child(_body)
	var main := VBoxContainer.new()
	main.add_theme_constant_override("separation", 0)
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_child(_build_list())
	main.add_child(_build_description())
	_body.add_child(main)
	_body.add_child(_build_side())
	col.add_child(_build_footer())
	resized.connect(_layout)


# --- Building ------------------------------------------------------------------------------------

func _padded(child: Control, left := 20, top := 0, right := 20, bottom := 0) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", left)
	m.add_theme_constant_override("margin_top", top)
	m.add_theme_constant_override("margin_right", right)
	m.add_theme_constant_override("margin_bottom", bottom)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(child)
	return m


func _build_header() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	col.add_child(row)
	_title = Slate.label("", 18, Slate.TEXT, Slate.heavy())
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_title)

	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 4)
	_tabs.visible = false
	row.add_child(_tabs)
	_tabs.add_child(_icon_button("chevron-left", "Previous category", func(): Bridge.press(view_id, "LEFT")))
	var tab := PanelContainer.new()
	tab.add_theme_stylebox_override("panel", Slate.pill_box(Color(1, 1, 1, 0.07), 12, 5))
	tab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tab_label = Slate.label("", 13, Slate.TEXT, Slate.semibold())
	tab.add_child(_tab_label)
	_tabs.add_child(tab)
	_tabs.add_child(_icon_button("chevron-right", "Next category", func(): Bridge.press(view_id, "RIGHT")))

	_close = _icon_button("x", "Close (Esc)", func(): Bridge.press(view_id, "QUIT"))
	row.add_child(_close)

	_text = Slate.rich(14)
	_text.add_theme_color_override("default_color", Slate.MUTED)
	_text.visible = false
	col.add_child(_text)
	return _padded(col, 22, 18, 14, 12)


func _icon_button(icon: String, tip: String, action: Callable) -> Button:
	var b := Button.new()
	b.icon = Slate.icon(icon, 18)
	b.tooltip_text = tip
	b.custom_minimum_size = Vector2(34, 34)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_theme_color_override("icon_normal_color", Slate.MUTED)
	b.add_theme_color_override("icon_hover_color", Slate.TEXT)
	b.pressed.connect(action)
	return b


func _build_search() -> Control:
	_search = PanelContainer.new()
	_search.add_theme_stylebox_override("panel", _search_box(false))
	_search.mouse_filter = Control.MOUSE_FILTER_STOP
	_search.mouse_default_cursor_shape = Control.CURSOR_IBEAM
	_search.tooltip_text = "Search this list"
	_search.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			Bridge.press(view_id, "FILTER"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_search.add_child(row)
	row.add_child(Slate.icon_rect("search", 16, Slate.MUTED))
	_search_text = Slate.label("", 14, Slate.FAINT)
	_search_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(_search_text)
	_search_key = Slate.key_chip("/")
	row.add_child(_search_key)
	var wrap := _padded(_search, 20, 0, 20, 10)
	wrap.visible = false
	return wrap


func _search_box(active: bool) -> StyleBoxFlat:
	var sb := Slate.box(Color(1, 1, 1, 0.05), 10, Slate.ACCENT if active else Slate.BORDER, 1)
	sb.content_margin_left = 12
	sb.content_margin_right = 8
	sb.content_margin_top = 7
	sb.content_margin_bottom = 7
	return sb


func _build_list() -> Control:
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 0)
	var line := ColorRect.new()
	line.color = Slate.BORDER
	line.custom_minimum_size.y = 1
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(line)

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	stack.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", ROW_STEP - ROW_HEIGHT)
	_scroll.add_child(_padded(_list, 10, 8, 10, 8))
	(_list.get_parent() as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_top_pad = Control.new()
	_top_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_list.add_child(_top_pad)
	_bottom_pad = Control.new()
	_bottom_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_list.add_child(_bottom_pad)
	_scroll.get_v_scroll_bar().value_changed.connect(_on_scrolled)

	_empty = Slate.label("Nothing matches.", 14, Slate.FAINT)
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty.custom_minimum_size.y = 60
	_empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty.visible = false
	stack.add_child(_empty)
	return stack


func _build_description() -> Control:
	_desc_box = PanelContainer.new()
	var sb := Slate.box(Color(1, 1, 1, 0.035), 0, Slate.BORDER, 0)
	sb.border_width_top = 1
	sb.border_color = Slate.BORDER
	sb.set_content_margin_all(18)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	_desc_box.add_theme_stylebox_override("panel", sb)
	_desc_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_desc = Slate.rich(14)
	_desc.add_theme_color_override("default_color", Slate.SOFT)
	_desc_box.add_child(_desc)
	_desc_box.visible = false
	return _desc_box


## Panel the game draws beside the entries (spell details, a map preview): its text keeps the
## game's column layout, so it uses a fixed-width font.
func _build_side() -> Control:
	_side = PanelContainer.new()
	_side.mouse_filter = Control.MOUSE_FILTER_PASS
	_side.visible = false
	_side_scroll = ScrollContainer.new()
	_side_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_side_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_side.add_child(_side_scroll)
	_side_text = Slate.rich(12)
	_side_text.add_theme_font_override("normal_font", Slate.mono())
	_side_text.add_theme_color_override("default_color", Slate.SOFT)
	_side_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_side_scroll.add_child(_side_text)
	return _side


func _side_box(left: bool) -> StyleBoxFlat:
	var sb := Slate.box(Color(1, 1, 1, 0.035), 0, Slate.BORDER, 0)
	sb.border_color = Slate.BORDER
	sb.border_width_top = 1
	if left:
		sb.border_width_right = 1
	else:
		sb.border_width_left = 1
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	return sb


## Width of the side panel: room for its columns, but never more than most of the screen.
func _side_width(avail: float) -> float:
	if not _side.visible:
		return 0.0
	var cell := Slate.mono().get_string_size("M", HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	return minf(_side_cols * cell + 40, avail * 0.62)


func _build_footer() -> Control:
	var bar := PanelContainer.new()
	var sb := Slate.box(Color(0, 0, 0, 0.18), 0, Slate.BORDER, 0)
	sb.border_width_top = 1
	sb.border_color = Slate.BORDER
	sb.corner_radius_bottom_left = 18
	sb.corner_radius_bottom_right = 18
	sb.content_margin_left = 22
	sb.content_margin_right = 16
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	bar.add_theme_stylebox_override("panel", sb)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	bar.add_child(row)
	_footer = Slate.rich(12)
	_footer.add_theme_color_override("default_color", Slate.MUTED)
	_footer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_footer.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_footer)
	_hints = HBoxContainer.new()
	_hints.add_theme_constant_override("separation", 14)
	row.add_child(_hints)
	return bar


func _hint(key: String, text: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(Slate.key_chip(key, 10))
	h.add_child(Slate.label(text, 12, Slate.MUTED))
	return h


# --- Updates from the game -----------------------------------------------------------------------

func set_entries(entries: Array) -> void:
	_entries = entries
	_has_keys = entries.any(func(e): return String(e.get("key", "")) != "")
	_widest = _measure_widest()
	_rows_dirty = true
	_refresh_rows()


## Width of the widest entry. Only the entries with the most characters are measured, as a menu
## can have thousands.
func _measure_widest() -> float:
	var lengths := PackedInt32Array()
	lengths.resize(_entries.size())
	var longest := 0
	for i in _entries.size():
		var e: Dictionary = _entries[i]
		var n := Slate.plain(e.get("text", [])).strip_edges().length()
		if e.has("column"):
			n += Slate.plain(e["column"]).strip_edges().length() + 3
		lengths[i] = n
		longest = maxi(longest, n)
	var widest := 0.0
	var measured := 0
	for i in _entries.size():
		if lengths[i] < longest * 0.8 or measured >= 64:
			continue
		measured += 1
		var e: Dictionary = _entries[i]
		var w := Slate.body().get_string_size(Slate.plain(e.get("text", [])).strip_edges(),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		if e.has("column"):
			w += 24 + Slate.body().get_string_size(Slate.plain(e["column"]).strip_edges(),
					HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		widest = maxf(widest, w)
	return widest


func apply(msg: Dictionary) -> void:
	var anchor: Array = msg.get("anchor", [])
	_anchor = Vector2(float(anchor[0]), float(anchor[1])) * Display.frame_scale() if anchor.size() == 2 else null
	_scrim.color = Color(0, 0, 0, 0) if _anchor != null else Slate.SCRIM
	var title := Slate.plain(msg.get("title", [])).strip_edges()
	var text: Array = msg.get("text", [])
	var plain_text := Slate.plain(text).strip_edges()
	# Many menus only ask a question in their text; a short one reads best as the title.
	var text_as_title := title == "" and plain_text != "" and plain_text.length() <= 70 and not "\n" in plain_text
	if text_as_title:
		_title.text = plain_text
	else:
		_title.text = title if title != "" else "Choose an option"
	_text.text = Slate.bbcode(text, Slate.MUTED).strip_edges()
	_text.visible = plain_text != "" and not text_as_title

	_cancel = bool(msg.get("cancel", false))
	_close.visible = _cancel

	var has_tabs := bool(msg.get("categories", false))
	_tabs.visible = has_tabs
	_tab_label.text = String(msg.get("category", ""))

	var can_filter := bool(msg.get("can_filter", false))
	var filtering := bool(msg.get("filtering", false))
	var filter := String(msg.get("filter", ""))
	# Short lists don't need a search box; the filter key still works.
	_search.get_parent().visible = can_filter and (_entries.size() > 8 or filtering or filter != "")
	_search.add_theme_stylebox_override("panel", _search_box(filtering))
	if filter != "" or filtering:
		_search_text.text = filter + ("▏" if filtering else "")
		_search_text.add_theme_color_override("font_color", Slate.TEXT)
	else:
		_search_text.text = "Search"
		_search_text.add_theme_color_override("font_color", Slate.FAINT)
	var filter_key := String(msg.get("filter_key", ""))
	_search_key.visible = filter_key != "" and not filtering
	(_search_key.get_child(0) as Label).text = filter_key

	var side: Dictionary = msg.get("side", {})
	var had_side := _side.visible
	_side.visible = not side.is_empty()
	if _side.visible:
		var left := bool(side.get("left", false))
		_body.move_child(_side, 0 if left else _body.get_child_count() - 1)
		_side.add_theme_stylebox_override("panel", _side_box(left))
		var side_text := _RULE.sub(Slate.bbcode(side.get("lines", []), Slate.SOFT), "", true).rstrip(" \n")
		if side_text != _side_text.text:
			_side_text.text = side_text
		var cols := int(side.get("cols", 0))
		var lines := side_text.count("\n") + 1
		if cols != _side_cols or lines != _side_lines or not had_side:
			_side_cols = cols
			_side_lines = lines
			_layout()

	_describe = bool(msg.get("describe", false))
	var footer: Array = msg.get("footer", [])
	_footer.text = Slate.bbcode(footer, Slate.MUTED).strip_edges()
	_update_hints(filtering)

	var shown: Array = msg.get("shown", []).map(func(i): return int(i))
	if shown != _shown:
		_shown = shown
		_rows_dirty = true
	var selected := int(msg.get("selected", -1))
	var moved := selected != _selected
	_selected = selected
	_refresh_rows()
	if moved:
		_scroll_to_selected()
	_update_description()
	_place.call_deferred()


func _update_hints(filtering: bool) -> void:
	for c in _hints.get_children():
		c.queue_free()
	if filtering:
		_hints.add_child(_hint("Enter", "Done"))
		_hints.add_child(_hint("Esc", "Clear"))
		return
	_hints.add_child(_hint("↑↓", "Move"))
	_hints.add_child(_hint("Enter", "Select"))
	if _cancel:
		_hints.add_child(_hint("Esc", "Close"))


# --- Rows ----------------------------------------------------------------------------------------

func _refresh_rows() -> void:
	if not is_inside_tree():
		return
	if _rows_dirty:
		_rows_dirty = false
		_listed = _shown.filter(func(i): return i >= 0 and i < _entries.size())
		_first = _window_start(_listed.find(_selected))
		_build_rows()
		_empty.visible = _listed.is_empty() and not _entries.is_empty()
		_layout()
	for index in _rows:
		_rows[index].set_selected(index == _selected)


## First row to build so that the row at `pos` is near the middle of what is built.
@warning_ignore("integer_division")
func _window_start(pos: int) -> int:
	if pos < 0:
		return 0
	return clampi(pos - WINDOW / 2, 0, maxi(_listed.size() - WINDOW, 0))


func _build_rows() -> void:
	for index in _rows:
		var old: Control = _rows[index]
		_list.remove_child(old)
		old.queue_free()
	_rows.clear()
	var last := mini(_first + WINDOW, _listed.size())
	for pos in range(_first, last):
		var index: int = _listed[pos]
		var row := MenuRow.new()
		row.setup(_entries[index], _has_keys)
		row.set_selected(index == _selected)
		row.clicked.connect(_on_row_clicked.bind(index))
		row.hovered.connect(_on_row_hovered.bind(index))
		_list.add_child(row)
		_rows[index] = row
	_list.move_child(_bottom_pad, -1)
	# A hidden spacer takes no room and no gap; a shown one stands in for its rows and their gaps.
	_top_pad.visible = _first > 0
	_top_pad.custom_minimum_size.y = _first * ROW_STEP - (ROW_STEP - ROW_HEIGHT)
	var after := _listed.size() - last
	_bottom_pad.visible = after > 0
	_bottom_pad.custom_minimum_size.y = after * ROW_STEP - (ROW_STEP - ROW_HEIGHT)


## Builds the stretch of rows around what scrolled into view, before it runs out.
@warning_ignore("integer_division")
func _on_scrolled(value: float) -> void:
	if _listed.size() <= WINDOW:
		return
	var top := int(value / ROW_STEP)
	var seen := int(_scroll.size.y / ROW_STEP) + 1
	var margin := WINDOW / 6
	var near_top := _first > 0 and top < _first + margin
	var near_end := _first + WINDOW < _listed.size() and top + seen > _first + WINDOW - margin
	if near_top or near_end:
		_first = clampi(top + seen / 2 - WINDOW / 2, 0, _listed.size() - WINDOW)
		_build_rows()


func _layout() -> void:
	if _card == null or not is_inside_tree():
		return
	var viewport := get_viewport_rect().size
	var widest := _widest
	var avail := viewport.x - 80
	var side := _side_width(avail)
	var narrowest := 260.0 if _anchor != null else 300.0 if side > 0 else MIN_WIDTH
	var width := clampf(widest + (100.0 if _has_keys else 60.0), narrowest, minf(MAX_WIDTH, avail - side))
	_card.custom_minimum_size.x = width + side
	_side.custom_minimum_size.x = side
	var rows := maxi(_listed.size(), 1)
	var reserved := 260.0 + (160.0 if _describe else 0.0)
	_scroll.custom_minimum_size.y = minf(rows * (ROW_HEIGHT + 2) + 16, maxf(viewport.y - reserved, 160))
	if _side.visible:
		var lines_height := _side_lines * 17.0 + 28
		_side_scroll.custom_minimum_size.y = minf(lines_height, maxf(viewport.y - 260.0, 160))
	_scroll.visible = not _listed.is_empty()
	_place.call_deferred()


## Centered, or beside the mouse as a context menu, kept inside the window.
func _place() -> void:
	if _center == null or not is_inside_tree():
		return
	if _anchor == null:
		_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		return
	var card := _card.get_combined_minimum_size()
	var viewport := get_viewport_rect().size
	var at: Vector2 = _anchor + Vector2(14, 10)
	if at.x + card.x > viewport.x - 8:
		at.x = _anchor.x - 14 - card.x
	at.x = clampf(at.x, 8, maxf(8, viewport.x - card.x - 8))
	at.y = clampf(at.y, 8, maxf(8, viewport.y - card.y - 8))
	_center.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_center.position = at
	_center.size = card


func _scroll_to_selected() -> void:
	if not _rows.has(_selected):
		var pos := _listed.find(_selected)
		if pos < 0:
			return
		_first = _window_start(pos)
		_build_rows()
	var row: Control = _rows[_selected]
	# Rows lay out on the next frame; wait so the scroll target is right.
	await get_tree().process_frame
	if is_instance_valid(row):
		_scroll.ensure_control_visible(row)


func _on_row_clicked(index: int) -> void:
	if _entries[index].get("enabled", true):
		Bridge.pick(view_id, index)


func _on_row_hovered(index: int, inside: bool) -> void:
	_hovered = index if inside else -1
	_update_description()


func _update_description() -> void:
	var index := _hovered if _hovered >= 0 else _selected
	var desc = []
	if _describe and index >= 0 and index < _entries.size():
		desc = _entries[index].get("desc", [])
	var has_desc := Slate.plain(desc).strip_edges() != ""
	_desc_box.visible = _describe
	_desc.text = Slate.bbcode(desc, Slate.SOFT).strip_edges() if has_desc else "[color=#%s]No description.[/color]" % Slate.FAINT.to_html(false)


func _on_scrim_input(event: InputEvent) -> void:
	# A context menu also closes on a right click elsewhere.
	var closing_click: bool = event is InputEventMouseButton and event.pressed and (event.button_index == MOUSE_BUTTON_LEFT
			or (_anchor != null and event.button_index == MOUSE_BUTTON_RIGHT))
	if closing_click and _cancel:
		Bridge.press(view_id, "QUIT")


class MenuRow extends PanelContainer:
	signal clicked
	signal hovered(inside: bool)

	var _enabled := true
	var _selected := false
	var _hover := false
	var _accent: ColorRect
	var _text: RichTextLabel

	func setup(entry: Dictionary, has_keys: bool) -> void:
		_enabled = bool(entry.get("enabled", true))
		custom_minimum_size.y = 38
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if _enabled else Control.CURSOR_ARROW
		mouse_entered.connect(func():
			_hover = true
			_restyle()
			hovered.emit(true))
		mouse_exited.connect(func():
			_hover = false
			_restyle()
			hovered.emit(false))

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(row)

		if has_keys:
			var key := String(entry.get("key", ""))
			var slot := CenterContainer.new()
			slot.custom_minimum_size.x = 30
			slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var chip := Slate.key_chip(key, 11)
			chip.visible = key != ""
			slot.add_child(chip)
			row.add_child(slot)

		var extra := Slate.plain(entry.get("extra", [])).strip_edges()
		if extra != "":
			var mark := Slate.rich(14)
			mark.autowrap_mode = TextServer.AUTOWRAP_OFF
			mark.fit_content = true
			mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			mark.add_theme_font_override("normal_font", Slate.mono_bold())
			mark.text = _trimmed(entry["extra"], Slate.ACCENT)
			mark.custom_minimum_size.x = Slate.mono_bold().get_string_size(extra, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 2
			row.add_child(mark)

		_text = Slate.rich(15)
		_text.autowrap_mode = TextServer.AUTOWRAP_OFF
		_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_text.add_theme_font_override("normal_font", Slate.semibold())
		_text.text = _trimmed(entry.get("text", []))
		row.add_child(_text)

		if entry.has("column"):
			var column := Slate.rich(14)
			column.autowrap_mode = TextServer.AUTOWRAP_OFF
			column.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			column.add_theme_color_override("default_color", Slate.MUTED)
			column.add_theme_font_override("normal_font", Slate.mono())
			column.text = "[right]%s[/right]" % _trimmed(entry["column"], Slate.MUTED)
			column.custom_minimum_size.x = Slate.mono().get_string_size(
					Slate.plain(entry["column"]).strip_edges(), HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 4
			row.add_child(column)

		modulate.a = 1.0 if _enabled else 0.42
		_restyle()

	## BBCode for runs, without the padding curses menus use for alignment.
	func _trimmed(spans, fallback := Slate.TEXT) -> String:
		if typeof(spans) != TYPE_ARRAY or spans.is_empty():
			return ""
		var runs: Array = spans.duplicate(true)
		runs[0][0] = String(runs[0][0]).strip_edges(true, false)
		runs[-1][0] = String(runs[-1][0]).strip_edges(false, true)
		return Slate.bbcode(runs, fallback)

	func set_selected(on: bool) -> void:
		if on != _selected:
			_selected = on
			_restyle()

	func _restyle() -> void:
		var bg := Color(0, 0, 0, 0)
		if _selected:
			bg = Color(1, 1, 1, 0.09)
		elif _hover and _enabled:
			bg = Color(1, 1, 1, 0.05)
		var sb := Slate.box(bg, 10, Slate.BORDER, 0)
		if _selected:
			# Amber edge on the left marks the row Enter will pick.
			sb.border_width_left = 3
			sb.border_color = Slate.ACCENT
		sb.content_margin_left = 10
		sb.content_margin_right = 12
		sb.content_margin_top = 4
		sb.content_margin_bottom = 4
		add_theme_stylebox_override("panel", sb)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			if _enabled:
				clicked.emit()
