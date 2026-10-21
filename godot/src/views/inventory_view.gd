extends Control
## The inventory: the game's `inventory_selector` and its variants (inventory, drop, pick up, use,
## and every "choose an item" prompt). A large card with weight and volume at the top, one pane
## per list the game shows (carried, nearby, worn, chosen) and the selected item's details with
## its actions. The game owns the lists, the cursor and the filter; a click selects a row or
## presses the key bound to an action, exactly as the keyboard would.

## Picks arrive in the game as `pane * STRIDE + row index` (see `inventory_ui.cpp`).
const STRIDE := 100000
const ROW_HEIGHT := 36
## Narrowest extra column a list shows (damage, encumbrance, ...), and the gap between them.
const MIN_CELL_WIDTH := 30
const MAX_CELL_WIDTH := 190
const CELL_GAP := 10
const ASIDE_WIDTH := 390.0
const MAX_SIZE := Vector2(1440, 920)
const PANE_NAMES := {"carried": "Carried", "nearby": "Nearby", "worn": "Worn", "selection": "Chosen"}
const PANE_ICONS := {"carried": "backpack", "nearby": "map-pin", "worn": "shirt", "selection": "square-check-big"}
## Item actions offered next to the details, when the screen's input context has them.
const ITEM_ACTIONS := [
	["WIELD", "Wield", "sword"],
	["WEAR", "Wear", "shirt"],
	["EXAMINE", "Examine", "eye"],
	["TOGGLE_FAVORITE", "Favorite", "star"],
]

var view_id := 0

var _msg := {}
var _columns: Array = []
var _rows := {}
var _panes: Array = []
var _cursor := Vector2i(-1, -1)
var _multi := false
var _has_cells := false

var _card: PanelContainer
var _title: Label
var _hint: RichTextLabel
var _stats: HBoxContainer
var _search: PanelContainer
var _search_text: Label
var _search_key: PanelContainer
var _category_button: PillButton
var _unload_button: PillButton
var _count_chip: PanelContainer
var _count_label: Label
var _pane_row: HBoxContainer
var _aside: PanelContainer
var _glyph: Label
var _glyph_tile: PanelContainer
var _name: RichTextLabel
var _category: Label
var _denial: PanelContainer
var _denial_text: RichTextLabel
var _info_scroll: ScrollContainer
var _info: RichTextLabel
var _no_item: Label
var _actions: GridContainer
var _confirm: PillButton
var _item_buttons := {}
var _footer: RichTextLabel
var _hints: HBoxContainer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var scrim := ColorRect.new()
	scrim.color = Slate.SCRIM
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	scrim.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			Bridge.press(view_id, "QUIT"))
	add_child(scrim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_card = PanelContainer.new()
	# Solid, unlike the HUD's cards: a full screen reads better without the map showing through.
	var card_style := Slate.card_box(18, 0)
	card_style.bg_color = Slate.CARD_SOLID
	_card.add_theme_stylebox_override("panel", card_style)
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(_card)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	_card.add_child(col)
	col.add_child(_build_header())
	col.add_child(_build_toolbar())
	col.add_child(_rule())
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 0)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)
	_pane_row = HBoxContainer.new()
	_pane_row.add_theme_constant_override("separation", 0)
	_pane_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(_pane_row)
	body.add_child(_build_aside())
	col.add_child(_build_footer())
	resized.connect(_layout)
	_layout()


# --- Building ------------------------------------------------------------------------------------

func _rule(vertical := false) -> ColorRect:
	var line := ColorRect.new()
	line.color = Slate.BORDER
	if vertical:
		line.custom_minimum_size.x = 1
	else:
		line.custom_minimum_size.y = 1
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


func _margin(child: Control, left: int, top: int, right: int, bottom: int) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", left)
	m.add_theme_constant_override("margin_top", top)
	m.add_theme_constant_override("margin_right", right)
	m.add_theme_constant_override("margin_bottom", bottom)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(child)
	return m


func _build_header() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var badge := PanelContainer.new()
	badge.add_theme_stylebox_override("panel", Slate.box(Color(Slate.ACCENT, 0.14), 10, Slate.BORDER, 0))
	badge.custom_minimum_size = Vector2(38, 38)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var icon := Slate.icon_rect("backpack", 20, Slate.ACCENT)
	badge.add_child(icon)
	row.add_child(badge)

	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 1)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(titles)
	_title = Slate.label("", 19, Slate.TEXT, Slate.heavy())
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	titles.add_child(_title)
	_hint = Slate.rich(12)
	_hint.autowrap_mode = TextServer.AUTOWRAP_OFF
	_hint.add_theme_color_override("default_color", Slate.FAINT)
	titles.add_child(_hint)

	_stats = HBoxContainer.new()
	_stats.add_theme_constant_override("separation", 22)
	_stats.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_stats)

	var close := Button.new()
	close.icon = Slate.icon("x", 18)
	close.tooltip_text = "Close"
	close.focus_mode = Control.FOCUS_NONE
	close.custom_minimum_size = Vector2(36, 36)
	close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	close.add_theme_color_override("icon_normal_color", Slate.MUTED)
	close.add_theme_color_override("icon_hover_color", Slate.TEXT)
	close.pressed.connect(func(): Bridge.press(view_id, "QUIT"))
	row.add_child(close)
	return _margin(row, 22, 18, 16, 14)


## Weight or volume carried, as a bar against the limit.
func _stat(label: String, current: Array, limit: Array) -> Control:
	var parts := label.trim_suffix(":").split("(")
	var name := parts[0].strip_edges()
	var unit := parts[1].trim_suffix(")").strip_edges() if parts.size() > 1 else ""
	var now := Slate.plain(current).strip_edges()
	var most := Slate.plain(limit).strip_edges()
	var ratio := 0.0
	if most.is_valid_float() and float(most) > 0.0 and now.is_valid_float():
		ratio = float(now) / float(most)
	var color := Slate.GOOD
	if ratio > 1.0:
		color = Slate.DANGER
	elif ratio > 0.85:
		color = Slate.WARN

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.custom_minimum_size.x = 170
	col.tooltip_text = "%s carried: %s of %s %s" % [name, now, most, unit]
	col.mouse_filter = Control.MOUSE_FILTER_PASS
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(top)
	var title := Slate.label(name, 12, Slate.MUTED, Slate.semibold())
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var value := Slate.rich(12)
	value.autowrap_mode = TextServer.AUTOWRAP_OFF
	value.add_theme_font_override("normal_font", Slate.mono())
	value.text = "%s[color=#%s] / %s %s[/color]" % [
			Slate.bbcode(current, Slate.TEXT), Slate.FAINT.to_html(false), most, unit]
	top.add_child(value)
	var track := PanelContainer.new()
	track.add_theme_stylebox_override("panel", Slate.box(Slate.TRACK, 3, Slate.BORDER, 0))
	track.custom_minimum_size.y = 6
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(track)
	# A PanelContainer stretches its child, so the fill sits in a plain holder where anchors apply.
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(holder)
	var fill := Panel.new()
	fill.add_theme_stylebox_override("panel", Slate.box(color, 3, Slate.BORDER, 0))
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.anchor_bottom = 1.0
	fill.anchor_right = clampf(ratio, 0.0, 1.0)
	holder.add_child(fill)
	return col


func _build_toolbar() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	_search = PanelContainer.new()
	_search.add_theme_stylebox_override("panel", _search_box(false))
	_search.mouse_filter = Control.MOUSE_FILTER_STOP
	_search.mouse_default_cursor_shape = Control.CURSOR_IBEAM
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.tooltip_text = "Search your items"
	_search.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			if String(_msg.get("prompt", "")) == "":
				Bridge.press(view_id, "INVENTORY_FILTER"))
	var search_row := HBoxContainer.new()
	search_row.add_theme_constant_override("separation", 10)
	search_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_search.add_child(search_row)
	search_row.add_child(Slate.icon_rect("search", 16, Slate.MUTED))
	_search_text = Slate.label("", 14, Slate.FAINT)
	_search_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	search_row.add_child(_search_text)
	_search_key = Slate.key_chip("/")
	search_row.add_child(_search_key)
	row.add_child(_search)

	_count_chip = PanelContainer.new()
	_count_chip.add_theme_stylebox_override("panel", _search_box(true))
	_count_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_count_label = Slate.label("", 14, Slate.TEXT, Slate.mono())
	_count_chip.add_child(_count_label)
	_count_chip.visible = false
	row.add_child(_count_chip)

	_category_button = PillButton.new("layers", "Jump by category", false)
	_category_button.tooltip_text = "Move between categories instead of items"
	_category_button.pressed.connect(func(): Bridge.press(view_id, "CATEGORY_SELECTION"))
	row.add_child(_category_button)
	_unload_button = PillButton.new("package-open", "Unload all", false)
	_unload_button.tooltip_text = "Unload every carried item that can be unloaded"
	_unload_button.pressed.connect(func(): Bridge.press(view_id, "unload_all"))
	row.add_child(_unload_button)
	return _margin(row, 22, 0, 22, 14)


func _search_box(active: bool) -> StyleBoxFlat:
	var sb := Slate.box(Color(1, 1, 1, 0.05), 10, Slate.ACCENT if active else Slate.BORDER, 1)
	sb.content_margin_left = 12
	sb.content_margin_right = 8
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


func _build_aside() -> Control:
	_aside = PanelContainer.new()
	var sb := Slate.box(Color(1, 1, 1, 0.025), 0, Slate.BORDER, 0)
	sb.border_width_left = 1
	sb.border_color = Slate.BORDER
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 18
	sb.content_margin_bottom = 18
	_aside.add_theme_stylebox_override("panel", sb)
	_aside.custom_minimum_size.x = ASIDE_WIDTH
	_aside.mouse_filter = Control.MOUSE_FILTER_PASS

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	_aside.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	col.add_child(head)
	_glyph_tile = PanelContainer.new()
	_glyph_tile.add_theme_stylebox_override("panel", Slate.box(Color(1, 1, 1, 0.06), 12, Slate.BORDER, 1))
	_glyph_tile.custom_minimum_size = Vector2(52, 52)
	_glyph_tile.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_glyph = Slate.label("", 26, Slate.TEXT, Slate.mono_bold())
	_glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_glyph_tile.add_child(_glyph)
	head.add_child(_glyph_tile)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 4)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(names)
	_name = Slate.rich(17)
	_name.add_theme_font_override("normal_font", Slate.bold())
	names.add_child(_name)
	_category = Slate.label("", 11, Slate.FAINT, Slate.bold())
	names.add_child(_category)

	# Why the selected item can't be chosen here, in full (rows only have room for the start).
	_denial = PanelContainer.new()
	var denial_box := Slate.box(Color(Slate.DANGER, 0.1), 10, Color(Slate.DANGER, 0.35), 1)
	denial_box.content_margin_left = 12
	denial_box.content_margin_right = 12
	denial_box.content_margin_top = 8
	denial_box.content_margin_bottom = 8
	_denial.add_theme_stylebox_override("panel", denial_box)
	var denial_row := HBoxContainer.new()
	denial_row.add_theme_constant_override("separation", 10)
	_denial.add_child(denial_row)
	var alert := Slate.icon_rect("circle-alert", 16, Slate.DANGER)
	alert.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	denial_row.add_child(alert)
	_denial_text = Slate.rich(13)
	_denial_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_denial_text.add_theme_color_override("default_color", Slate.DANGER)
	denial_row.add_child(_denial_text)
	col.add_child(_denial)

	col.add_child(_rule())
	_info_scroll = ScrollContainer.new()
	_info_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_info_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_info_scroll)
	_info = Slate.rich(13)
	_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_info.add_theme_color_override("default_color", Slate.SOFT)
	_info.add_theme_constant_override("line_separation", 4)
	_info_scroll.add_child(_info)
	_no_item = Slate.label("Select an item to see its details.", 14, Slate.FAINT)
	_no_item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_no_item.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_no_item.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_no_item.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_no_item)

	_confirm = PillButton.new("corner-down-left", "Select", true)
	_confirm.pressed.connect(func(): Bridge.press(view_id, "CONFIRM"))
	col.add_child(_confirm)
	_actions = GridContainer.new()
	_actions.columns = 2
	_actions.add_theme_constant_override("h_separation", 8)
	_actions.add_theme_constant_override("v_separation", 8)
	col.add_child(_actions)
	for a in ITEM_ACTIONS:
		var b := PillButton.new(a[2], a[1], false)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var act: String = a[0]
		b.pressed.connect(func(): Bridge.press(view_id, act))
		_actions.add_child(b)
		_item_buttons[act] = b
	return _aside


func _build_footer() -> Control:
	var bar := PanelContainer.new()
	var sb := Slate.box(Color(0, 0, 0, 0.18), 0, Slate.BORDER, 0)
	sb.border_width_top = 1
	sb.border_color = Slate.BORDER
	sb.corner_radius_bottom_left = 18
	sb.corner_radius_bottom_right = 18
	sb.content_margin_left = 22
	sb.content_margin_right = 18
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
	_hints.add_theme_constant_override("separation", 16)
	row.add_child(_hints)
	return bar


func _layout() -> void:
	if _card == null:
		return
	var viewport := get_viewport_rect().size
	var target := Vector2(minf(viewport.x - 48, MAX_SIZE.x), minf(viewport.y - 48, MAX_SIZE.y))
	_card.custom_minimum_size = target
	# Narrow windows, and lists with extra columns, give the details less room.
	var aside := clampf(target.x * 0.3, 300, ASIDE_WIDTH)
	_aside.custom_minimum_size.x = 300.0 if _has_cells else aside


# --- Updates from the game -----------------------------------------------------------------------

func set_entries(columns: Array) -> void:
	_columns = columns
	_has_cells = columns.any(func(c): return c.get("visible", false) and c.get("rows", []).any(
			func(r): return not r.has("cat") and not r.get("cells", []).is_empty()))
	_layout()
	_build_panes()
	_apply_cursor(true)


func apply(msg: Dictionary) -> void:
	_msg = msg
	_title.text = Slate.plain(msg.get("title", [])).strip_edges()
	if _title.text == "":
		_title.text = "Inventory"
	var hint: Array = msg.get("hint", [])
	_hint.text = Slate.bbcode(hint, Slate.FAINT).strip_edges()
	_hint.visible = Slate.plain(hint).strip_edges() != ""

	for c in _stats.get_children():
		c.queue_free()
	for s in msg.get("stats", []):
		_stats.add_child(_stat(String(s.get("label", "")), s.get("current", []), s.get("limit", [])))

	var keys: Dictionary = msg.get("keys", {})
	var prompt := String(msg.get("prompt", ""))
	var typing := prompt == "filter"
	var filter := String(msg.get("prompt_text", "")) if typing else String(msg.get("filter", ""))
	_search.add_theme_stylebox_override("panel", _search_box(typing))
	if typing or filter != "":
		_search_text.text = filter + ("▏" if typing else "")
		_search_text.add_theme_color_override("font_color", Slate.TEXT)
	else:
		_search_text.text = "Search"
		_search_text.add_theme_color_override("font_color", Slate.FAINT)
	_search.visible = keys.has("INVENTORY_FILTER")
	_search_key.visible = not typing and String(keys.get("INVENTORY_FILTER", "")) != ""
	(_search_key.get_child(0) as Label).text = Slate.key_name(String(keys.get("INVENTORY_FILTER", "")))
	_count_chip.visible = prompt == "count"
	_count_label.text = "Amount  %s▏" % String(msg.get("prompt_text", ""))

	_category_button.visible = keys.has("CATEGORY_SELECTION")
	_category_button.set_key(Slate.key_name(String(keys.get("CATEGORY_SELECTION", ""))))
	_category_button.set_on(bool(msg.get("category_mode", false)))
	_unload_button.visible = keys.has("unload_all")
	_unload_button.set_key(Slate.key_name(String(keys.get("unload_all", ""))))

	var confirm_label := String(msg.get("confirm_label", ""))
	_confirm.set_text(confirm_label if confirm_label != "" else ("Confirm" if _multi else "Select"))
	_confirm.set_key(Slate.key_name(String(keys.get("CONFIRM", ""))))
	_confirm.set_enabled(bool(msg.get("available", true)))

	_update_detail(msg.get("detail", {}), keys)
	_footer.text = Slate.bbcode(msg.get("footer", []), Slate.MUTED).strip_edges()
	_update_hints(keys, typing or prompt == "count")
	_apply_cursor(false)


func _update_detail(detail: Dictionary, keys: Dictionary) -> void:
	var has_item := not detail.is_empty()
	_glyph_tile.visible = has_item
	_name.visible = has_item
	_category.visible = has_item
	_info_scroll.visible = has_item
	_denial.visible = has_item and detail.has("denial")
	_no_item.visible = not has_item
	if not has_item:
		_no_item.text = "Nothing to show here." if bool(_msg.get("empty", false)) else "Select an item to see its details."
	for act in _item_buttons:
		var b: PillButton = _item_buttons[act]
		b.visible = has_item and keys.has(act)
		b.set_key(Slate.key_name(String(keys.get(act, ""))))
	if not has_item:
		return
	_glyph.text = String(detail.get("sym", "?"))
	_glyph.add_theme_color_override("font_color", Slate.curses(String(detail.get("sym_color", "c_white"))))
	_name.text = Slate.bbcode(detail.get("name", []), Slate.TEXT)
	_category.text = String(detail.get("category", "")).to_upper()
	_denial_text.text = Slate.bbcode(detail.get("denial", []), Slate.DANGER).strip_edges()
	var info := Slate.bbcode(detail.get("info", []), Slate.SOFT)
	# The game separates sections with "--" lines; show them as spacing instead.
	info = info.replace("\n--\n", "\n\n").replace("--\n", "\n").strip_edges()
	if info != _info.text:
		_info.text = info
		_info_scroll.scroll_vertical = 0
	var fav := bool(detail.get("fav", false))
	(_item_buttons["TOGGLE_FAVORITE"] as PillButton).set_text("Unfavorite" if fav else "Favorite")


func _update_hints(keys: Dictionary, typing: bool) -> void:
	for c in _hints.get_children():
		c.queue_free()
	if typing:
		_hints.add_child(_hint_item("Enter", "Done"))
		_hints.add_child(_hint_item("Esc", "Cancel"))
		return
	_hints.add_child(_hint_item("↑↓", "Move"))
	if _multi:
		_hints.add_child(_hint_item(Slate.key_name(String(keys.get("RIGHT", "→"))), "Mark"))
		_hints.add_child(_hint_item("0-9", "Amount"))
	elif _visible_panes() > 1:
		_hints.add_child(_hint_item("←→", "Switch list"))
	_hints.add_child(_hint_item(Slate.key_name(String(keys.get("CONFIRM", "Enter"))), _confirm.get_text()))
	_hints.add_child(_hint_item(Slate.key_name(String(keys.get("QUIT", "Esc"))), "Close"))


func _hint_item(key: String, text: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(Slate.key_chip(key, 10))
	h.add_child(Slate.label(text, 12, Slate.MUTED))
	return h


# --- Panes and rows ------------------------------------------------------------------------------

func _visible_panes() -> int:
	return _columns.filter(func(c): return bool(c.get("visible", false))).size()


func _build_panes() -> void:
	for c in _pane_row.get_children():
		c.queue_free()
	_rows.clear()
	_panes.clear()
	_multi = false
	var first := true
	for p in _columns.size():
		var column: Dictionary = _columns[p]
		if not bool(column.get("visible", false)):
			_panes.append(null)
			continue
		_multi = _multi or bool(column.get("multi", false))
		if not first:
			_pane_row.add_child(_rule(true))
		first = false
		var pane := Pane.new()
		pane.setup(column)
		pane.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# The chosen items only repeat names from the other lists; they need less room.
		pane.size_flags_stretch_ratio = 0.7 if String(column.get("role", "")) == "selection" else 1.0
		_pane_row.add_child(pane)
		_panes.append(pane)
		var multi := bool(column.get("multi", false))
		var keyed: bool = column.get("rows", []).any(func(r): return String(r.get("key", "")) != "")
		var widths := _cell_widths(column.get("rows", []))
		for row_data in column.get("rows", []):
			var index := int(row_data.get("i", -1))
			if row_data.has("cat"):
				pane.add_category(String(row_data["cat"]), row_data.get("cells", []), widths)
				continue
			var row := InvRow.new()
			row.setup(row_data, multi, keyed, widths)
			var code := p * STRIDE + index
			row.clicked.connect(_on_row_clicked.bind(Vector2i(p, index), code))
			row.activated.connect(func(): Bridge.pick(view_id, code, "CONFIRM"))
			row.marked.connect(func(): Bridge.pick(view_id, code, "RIGHT"))
			pane.add_row(row)
			_rows[Vector2i(p, index)] = row
		pane.finish()


## Width of each extra column in a list: as wide as its widest value or title, like the old list
## (which also leaves out rows showing why they can't be chosen), up to a limit.
static func _cell_widths(rows: Array) -> Array:
	var widths := []
	for r in rows:
		if r.has("denial"):
			continue
		var cells: Array = r.get("cells", [])
		for i in cells.size():
			var w := 0.0
			if r.has("cat"):
				w = Slate.bold().get_string_size(String(cells[i]).strip_edges().to_upper(),
						HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
			else:
				w = InvRow.cell_text_width(Slate.plain(cells[i]).strip_edges())
			if i >= widths.size():
				widths.append(MIN_CELL_WIDTH)
			widths[i] = clampf(ceilf(w) + 4, widths[i], MAX_CELL_WIDTH)
	return widths


func _on_row_clicked(at: Vector2i, code: int) -> void:
	# Select only: an empty action lets the game apply the pick without pressing anything.
	if at != _cursor:
		Bridge.pick(view_id, code, "")


func _apply_cursor(force_scroll: bool) -> void:
	var active := int(_msg.get("active", 0))
	var cursors: Array = _msg.get("cursors", [])
	var cursor := Vector2i(active, int(cursors[active]) if active < cursors.size() else -1)
	var moved := cursor != _cursor
	_cursor = cursor
	for at in _rows:
		var row: InvRow = _rows[at]
		var p: int = at.x
		var on: bool = p < cursors.size() and at.y == int(cursors[p])
		row.set_selected(on, p == active)
	for p in _panes.size():
		if _panes[p] != null:
			(_panes[p] as Pane).set_active(p == active)
	if (moved or force_scroll) and _rows.has(_cursor):
		_scroll_to(_rows[_cursor])


func _scroll_to(row: Control) -> void:
	# Rows lay out on the next frame; wait so the scroll target is right.
	await get_tree().process_frame
	if not is_instance_valid(row):
		return
	var scroll := row.get_parent().get_parent().get_parent() as ScrollContainer
	if scroll != null:
		scroll.ensure_control_visible(row)
		# Keep rows wider than their pane cut at the right, so the name stays in view.
		scroll.scroll_horizontal = 0


## One list (carried, nearby, worn or chosen): a header with its name and count, then its rows.
class Pane extends VBoxContainer:
	var _title: Label
	var _count: Label
	var _underline: ColorRect
	var _scroll: ScrollContainer
	var _list: VBoxContainer
	var _items := 0

	func setup(column: Dictionary) -> void:
		add_theme_constant_override("separation", 0)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var role := String(column.get("role", ""))
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 8)
		head.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var icon := Slate.icon_rect(PANE_ICONS.get(role, "box"), 15, Slate.MUTED)
		head.add_child(icon)
		_title = Slate.label(PANE_NAMES.get(role, role.capitalize()), 13, Slate.MUTED, Slate.bold())
		head.add_child(_title)
		_count = Slate.label("", 12, Slate.FAINT, Slate.mono())
		_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		head.add_child(_count)
		var head_box := MarginContainer.new()
		for side in ["left", "right"]:
			head_box.add_theme_constant_override("margin_" + side, 18)
		head_box.add_theme_constant_override("margin_top", 14)
		head_box.add_theme_constant_override("margin_bottom", 10)
		head_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		head_box.add_child(head)
		add_child(head_box)
		_underline = ColorRect.new()
		_underline.custom_minimum_size.y = 2
		_underline.color = Color(0, 0, 0, 0)
		_underline.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_underline)

		_scroll = ScrollContainer.new()
		# Rows never widen the pane; in a very narrow one their right edge is cut off instead.
		_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
		_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		add_child(_scroll)
		var pad := MarginContainer.new()
		pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for side in ["left", "right"]:
			pad.add_theme_constant_override("margin_" + side, 10)
		pad.add_theme_constant_override("margin_top", 6)
		pad.add_theme_constant_override("margin_bottom", 10)
		pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_scroll.add_child(pad)
		_list = VBoxContainer.new()
		_list.add_theme_constant_override("separation", 2)
		_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pad.add_child(_list)

	func add_category(name: String, cells: Array, widths: Array) -> void:
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var title := Slate.label(name.to_upper(), 11, Slate.FAINT, Slate.bold())
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.clip_text = true
		row.add_child(title)
		var titles := HBoxContainer.new()
		titles.add_theme_constant_override("separation", CELL_GAP)
		titles.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(titles)
		for i in cells.size():
			var cell = cells[i]
			var c := Slate.label(String(cell).strip_edges().to_upper(), 9, Slate.FAINT, Slate.bold())
			c.custom_minimum_size.x = widths[i] if i < widths.size() else MIN_CELL_WIDTH
			c.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			c.clip_text = true
			c.tooltip_text = String(cell).strip_edges()
			c.mouse_filter = Control.MOUSE_FILTER_PASS
			titles.add_child(c)
		var box := MarginContainer.new()
		box.add_theme_constant_override("margin_left", 10)
		box.add_theme_constant_override("margin_right", 12)
		box.add_theme_constant_override("margin_top", 0 if _list.get_child_count() == 0 else 12)
		box.add_theme_constant_override("margin_bottom", 4)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(row)
		_list.add_child(box)

	func add_row(row: Control) -> void:
		_items += 1
		_list.add_child(row)

	func finish() -> void:
		_count.text = str(_items) if _items > 0 else ""
		if _items == 0:
			var empty := Slate.label("Nothing here.", 13, Slate.FAINT)
			empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			empty.custom_minimum_size.y = 80
			empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			_list.add_child(empty)

	func set_active(on: bool) -> void:
		_title.add_theme_color_override("font_color", Slate.TEXT if on else Slate.MUTED)
		_underline.color = Color(Slate.ACCENT, 0.9) if on else Slate.BORDER


## One item: key, glyph, name, extra columns and weight. Click selects it, a second click or a
## double click confirms it, and in lists where items are marked the box on the left marks it.
class InvRow extends PanelContainer:
	signal clicked
	signal activated
	signal marked

	var _enabled := true
	var _selected := false
	var _active := false
	var _hover := false

	func setup(row: Dictionary, multi: bool, keyed: bool, widths: Array) -> void:
		_enabled = bool(row.get("enabled", true))
		custom_minimum_size.y = ROW_HEIGHT
		mouse_filter = Control.MOUSE_FILTER_STOP
		# Items that can't be chosen here only show why, on hover; clicking them does nothing.
		if _enabled:
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(func():
			_hover = true
			_restyle())
		mouse_exited.connect(func():
			_hover = false
			_restyle())
		# The full name, for names cut short in narrow panes, and why an item can't be chosen.
		var denial := Slate.plain(row.get("denial", [])).strip_edges()
		tooltip_text = Slate.plain(_trimmed(row.get("text", []))).replace(char(0xa0), " ")
		if denial != "":
			tooltip_text += "\n" + denial

		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(line)

		if multi:
			line.add_child(_mark_box(row))

		if keyed:
			var key := String(row.get("key", ""))
			var slot := CenterContainer.new()
			slot.custom_minimum_size.x = 22
			slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var chip := Slate.key_chip(key, 11)
			if key != "":
				(chip.get_child(0) as Label).add_theme_color_override("font_color",
						Slate.curses(String(row.get("key_color", "")), Slate.MUTED))
			slot.add_child(chip)
			line.add_child(slot)

		var tile := PanelContainer.new()
		tile.add_theme_stylebox_override("panel", Slate.box(Color(1, 1, 1, 0.05), 7, Slate.BORDER, 0))
		tile.custom_minimum_size = Vector2(26, 26)
		tile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var glyph := Slate.label(String(row.get("sym", "")), 15, Slate.curses(String(row.get("sym_color", ""))), Slate.mono_bold())
		glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		tile.add_child(glyph)
		line.add_child(tile)

		# Not sized to its text: long names are cut at the pane's edge rather than widening it.
		var name := Slate.rich(14, false)
		name.autowrap_mode = TextServer.AUTOWRAP_OFF
		name.clip_contents = true
		name.custom_minimum_size = Vector2(60, 22)
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		name.add_theme_font_override("normal_font", Slate.semibold())
		name.text = _name_bbcode(_trimmed(row.get("text", [])))
		line.add_child(name)

		if bool(row.get("fav", false)):
			line.add_child(Slate.icon_rect("star", 14, Slate.ACCENT))

		var cells: Array = row.get("cells", [])
		if denial != "" or not _enabled:
			for c in line.get_children():
				(c as CanvasItem).modulate.a = 0.5
		if denial != "":
			# As in the old list: the reason takes the place of the values, kept bright so it reads.
			# Name and reason share the row by length; whichever doesn't fit ends in "...".
			var reason := Slate.label(denial, 12, Slate.DANGER)
			reason.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			reason.custom_minimum_size.x = 80
			reason.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			reason.size_flags_stretch_ratio = Slate.body().get_string_size(denial,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			name.size_flags_stretch_ratio = Slate.semibold().get_string_size(tooltip_text.get_slice("\n", 0),
					HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
			line.add_child(reason)
		elif cells.is_empty():
			var weight := Slate.label(String(row.get("weight", "")), 12, Slate.FAINT, Slate.mono())
			weight.tooltip_text = String(row.get("volume", ""))
			weight.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			weight.custom_minimum_size.x = 64
			line.add_child(weight)
		else:
			# Lists with their own columns show those instead of the weight (it's in the details).
			var values := HBoxContainer.new()
			values.add_theme_constant_override("separation", CELL_GAP)
			values.mouse_filter = Control.MOUSE_FILTER_IGNORE
			line.add_child(values)
			for i in cells.size():
				var runs := _trimmed(cells[i])
				var width: float = widths[i] if i < widths.size() else MIN_CELL_WIDTH
				var text := Slate.plain(runs)
				if cell_text_width(text) + 4 > width:
					# Too long for the column (a long yield, say): one color, ending in "...".
					var cut := Slate.label(text, 12, Slate.lead_color(runs, Slate.MUTED), Slate.mono())
					cut.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
					cut.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
					cut.custom_minimum_size.x = width
					cut.size_flags_vertical = Control.SIZE_SHRINK_CENTER
					cut.tooltip_text = text
					cut.mouse_filter = Control.MOUSE_FILTER_PASS
					values.add_child(cut)
					continue
				var c := Slate.rich(12, false)
				c.autowrap_mode = TextServer.AUTOWRAP_OFF
				c.clip_contents = true
				c.custom_minimum_size = Vector2(width, 18)
				c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				c.add_theme_font_override("normal_font", Slate.mono())
				c.text = "[right]%s[/right]" % Slate.bbcode(runs, Slate.MUTED)
				values.add_child(c)
		if not _enabled and denial == "":
			(line.get_child(line.get_child_count() - 1) as CanvasItem).modulate.a = 0.5
		_restyle()

	func _mark_box(row: Dictionary) -> Control:
		var chosen := int(row.get("chosen", 0))
		var avail := int(row.get("avail", 1))
		var box := PanelContainer.new()
		var on := chosen > 0
		box.add_theme_stylebox_override("panel", Slate.box(Slate.ACCENT if on else Color(0, 0, 0, 0), 6,
				Slate.ACCENT if on else Slate.BORDER_STRONG, 0 if on else 2))
		box.custom_minimum_size = Vector2(22, 22)
		box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		box.mouse_filter = Control.MOUSE_FILTER_STOP
		box.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		box.tooltip_text = "Mark or unmark"
		if on and chosen < avail:
			var count := Slate.label(str(chosen), 11, Slate.ACCENT_TEXT, Slate.mono_bold())
			count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			box.add_child(count)
		elif on:
			box.add_child(Slate.icon_rect("check", 14, Slate.ACCENT_TEXT))
		box.gui_input.connect(func(e: InputEvent):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				box.accept_event()
				marked.emit())
		return box

	## The name, with the game's condition marks (`||`, `|\\`, `|.`, ...) in the mono font so
	## they line up like a small gauge.
	func _name_bbcode(runs: Array) -> String:
		if runs.size() > 1:
			var head := String(runs[0][0]).replace(char(0xa0), " ").strip_edges()
			if head != "" and head.lstrip("|\\.X") == "":
				var rest := Slate.bbcode(runs.slice(1), Slate.TEXT)
				return "[code]%s[/code]%s" % [Slate.bbcode([runs[0]], Slate.TEXT), rest]
		return Slate.bbcode(runs, Slate.TEXT)

	static func cell_text_width(text: String) -> float:
		return Slate.mono().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x

	## Runs without the padding curses lists use for alignment.
	func _trimmed(spans) -> Array:
		if typeof(spans) != TYPE_ARRAY or spans.is_empty():
			return []
		var runs: Array = spans.duplicate(true)
		runs[0][0] = String(runs[0][0]).strip_edges(true, false)
		runs[-1][0] = String(runs[-1][0]).strip_edges(false, true)
		return runs

	func set_selected(on: bool, active: bool) -> void:
		if on != _selected or active != _active:
			_selected = on
			_active = active
			_restyle()

	func _restyle() -> void:
		var bg := Color(0, 0, 0, 0)
		if _selected and _active:
			bg = Color(1, 1, 1, 0.09)
		elif _selected or (_hover and _enabled):
			bg = Color(1, 1, 1, 0.045)
		var sb := Slate.box(bg, 10, Slate.BORDER, 0)
		if _selected and _active:
			# Amber edge on the left marks the item the keys act on.
			sb.border_width_left = 3
			sb.border_color = Slate.ACCENT
		sb.content_margin_left = 8
		sb.content_margin_right = 12
		sb.content_margin_top = 4
		sb.content_margin_bottom = 4
		add_theme_stylebox_override("panel", sb)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			if not _enabled:
				return
			if event.double_click or (_selected and _active):
				activated.emit()
			else:
				clicked.emit()


## Rounded button with an icon, a label and the key that does the same thing.
class PillButton extends PanelContainer:
	signal pressed

	var _primary := false
	var _enabled := true
	var _on := false
	var _hover := false
	var _icon: TextureRect
	var _label: Label
	var _key: PanelContainer

	func _init(icon_name: String, text: String, primary: bool) -> void:
		_primary = primary
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(row)
		var fg := Slate.ACCENT_TEXT if primary else Slate.TEXT
		_icon = Slate.icon_rect(icon_name, 16, fg)
		row.add_child(_icon)
		_label = Slate.label(text, 13, fg, Slate.bold())
		row.add_child(_label)
		var gap := Control.new()
		gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(gap)
		_key = Slate.key_chip("", 10)
		if primary:
			_key.add_theme_stylebox_override("panel", Slate.pill_box(Color(0, 0, 0, 0.16), 6, 1))
			(_key.get_child(0) as Label).add_theme_color_override("font_color", Slate.ACCENT_TEXT)
		row.add_child(_key)
		mouse_entered.connect(func():
			_hover = true
			_restyle())
		mouse_exited.connect(func():
			_hover = false
			_restyle())
		_restyle()

	func set_text(text: String) -> void:
		_label.text = text

	func get_text() -> String:
		return _label.text

	func set_key(key: String) -> void:
		(_key.get_child(0) as Label).text = key
		_key.visible = key != ""

	func set_enabled(on: bool) -> void:
		_enabled = on
		modulate.a = 1.0 if on else 0.45
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if on else Control.CURSOR_ARROW

	## Shows a toggle as switched on (amber outline).
	func set_on(on: bool) -> void:
		_on = on
		_restyle()

	func _restyle() -> void:
		var bg: Color
		if _primary:
			bg = Slate.ACCENT.lightened(0.12) if _hover and _enabled else Slate.ACCENT
		else:
			bg = Color(1, 1, 1, 0.11 if _hover and _enabled else 0.06)
		var sb := Slate.box(bg, 10, Slate.ACCENT if _on else Slate.BORDER, 1 if _on else 0)
		sb.content_margin_left = 12
		sb.content_margin_right = 10
		sb.content_margin_top = 8
		sb.content_margin_bottom = 8
		add_theme_stylebox_override("panel", sb)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			if _enabled:
				pressed.emit()
