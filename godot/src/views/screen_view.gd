extends Control
## A full screen the game describes as data (view kind `screen`): header, tabs, search, one or more
## lists, a details side panel with action buttons, and key hints. Crafting, construction, the
## character sheet and most other big screens use it; the game decides what each part holds and
## what clicking it does (see README.md, "Screens").
##
## Clicking a row selects it (a pick with no key pressed); clicking the selected row again, or
## double clicking, picks it and presses the pane's `confirm` action. Tabs and buttons send the
## pick or action the game gave them. Every key still goes to the game.

const SlateButton := preload("res://src/ui/slate_button.gd")
const Hud := preload("res://src/ui/hud.gd")

const STRIDE := 100000
const ROW_HEIGHT := 34
const MIN_CELL_WIDTH := 30
const MAX_CELL_WIDTH := 220
const CELL_GAP := 12
const LINE_HEIGHT := 22.0
## Tallest the character preview gets before it shrinks to fit.
const PREVIEW_HEIGHT := 280.0

var view_id := 0

var _msg := {}
var _scrim: ColorRect
var _center: CenterContainer
var _card: PanelContainer
var _badge_icon: TextureRect
var _title: Label
var _close: Button
var _subtitle: RichTextLabel
var _stats: HBoxContainer
var _tab_bar: Control
var _tabs: HBoxContainer
var _tab_scroll: ScrollContainer
var _tab_prev: PanelContainer
var _tab_next: PanelContainer
var _subtab_bar: Control
var _subtabs: HBoxContainer
var _toolbar: Control
var _search: PanelContainer
var _search_text: Label
var _search_icon: TextureRect
var _search_label: Label
var _search_key: PanelContainer
var _toggles: HFlowContainer
var _toolbar_row: BoxContainer
var _body: BoxContainer
var _body_rule: ColorRect
var _pane_row: HBoxContainer
var _aside: PanelContainer
var _aside_tile: PanelContainer
var _aside_glyph: Label
var _aside_icon: TextureRect
var _aside_title: RichTextLabel
var _aside_subtitle: Label
var _aside_warn: PanelContainer
var _aside_rule: ColorRect
var _aside_warn_text: RichTextLabel
var _aside_scroll: ScrollContainer
var _aside_body: RichTextLabel
var _aside_sections: VBoxContainer
var _aside_empty: Label
var _buttons: VBoxContainer
## The character's sprite in character creation, cropped out of the game's frame where it is drawn.
var _preview: VBoxContainer
var _preview_image: TextureRect
var _preview_atlas := AtlasTexture.new()
var _preview_buttons: HBoxContainer
var _footer: RichTextLabel
var _hints: HBoxContainer

## Panes as built: the Pane node and the hash of the rows it was built from, so unchanged lists
## aren't rebuilt on every key press.
var _panes: Array = []
var _pane_hashes: Array = []
var _rows := {}
var _cursor := Vector2i(-1, -1)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Bridge.frame_received.connect(_on_frame)
	_scrim = ColorRect.new()
	_scrim.color = Slate.SCRIM
	_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_scrim.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_quit())
	add_child(_scrim)

	_center = CenterContainer.new()
	_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_center)
	var center := _center

	_card = PanelContainer.new()
	var card_style := Slate.card_box(18, 0)
	card_style.bg_color = Slate.CARD_SOLID
	_card.add_theme_stylebox_override("panel", card_style)
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(_card)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	_card.add_child(col)
	col.add_child(_build_header())
	_tab_bar = _build_tabs()
	col.add_child(_tab_bar)
	_subtab_bar = _build_subtabs()
	col.add_child(_subtab_bar)
	_toolbar = _build_toolbar()
	col.add_child(_toolbar)
	_body_rule = _rule()
	col.add_child(_body_rule)
	var body := BoxContainer.new()
	_body = body
	body.add_theme_constant_override("separation", 0)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)
	_pane_row = HBoxContainer.new()
	_pane_row.add_theme_constant_override("separation", 0)
	_pane_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pane_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_pane_row)
	body.add_child(_build_aside())
	col.add_child(_build_footer())
	resized.connect(_layout)
	_layout()


func _quit() -> void:
	var act := String(_msg.get("quit", "QUIT"))
	if act != "":
		Bridge.press(view_id, act)


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
	_badge_icon = Slate.icon_rect("list", 20, Slate.ACCENT)
	badge.add_child(_badge_icon)
	row.add_child(badge)

	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 1)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(titles)
	_title = Slate.label("", 19, Slate.TEXT, Slate.heavy())
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	titles.add_child(_title)
	_subtitle = Slate.rich(12)
	_subtitle.add_theme_color_override("default_color", Slate.FAINT)
	titles.add_child(_subtitle)

	_stats = HBoxContainer.new()
	_stats.add_theme_constant_override("separation", 10)
	_stats.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_stats)

	var close := Button.new()
	_close = close
	close.icon = Slate.icon("x", 18)
	close.tooltip_text = "Close"
	close.focus_mode = Control.FOCUS_NONE
	close.custom_minimum_size = Vector2(36, 36)
	close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	close.add_theme_color_override("icon_normal_color", Slate.MUTED)
	close.add_theme_color_override("icon_hover_color", Slate.TEXT)
	close.pressed.connect(_quit)
	row.add_child(close)
	return _margin(row, 22, 18, 16, 14)


func _build_tabs() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_tab_prev = Slate.key_chip("", 10)
	_tab_prev.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_tab_prev)
	_tab_scroll = ScrollContainer.new()
	_tab_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_tab_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tab_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_tab_scroll)
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 4)
	_tab_scroll.add_child(_tabs)
	_tab_next = Slate.key_chip("", 10)
	_tab_next.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_tab_next)
	return _margin(row, 18, 0, 18, 10)


func _build_subtabs() -> Control:
	_subtabs = HBoxContainer.new()
	_subtabs.add_theme_constant_override("separation", 6)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_child(_subtabs)
	return _margin(scroll, 22, 0, 22, 12)


func _build_toolbar() -> Control:
	# Side by side, or the toggles below the search box in a docked (narrow) screen.
	var row := BoxContainer.new()
	_toolbar_row = row
	row.add_theme_constant_override("separation", 10)
	_search = PanelContainer.new()
	_search.add_theme_stylebox_override("panel", _search_box(false))
	_search.mouse_filter = Control.MOUSE_FILTER_STOP
	_search.mouse_default_cursor_shape = Control.CURSOR_IBEAM
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_search.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			var search: Dictionary = _msg.get("search", {})
			if not bool(search.get("typing", false)) and String(search.get("act", "")) != "":
				Bridge.press(view_id, String(search["act"])))
	var search_row := HBoxContainer.new()
	search_row.add_theme_constant_override("separation", 10)
	search_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_search.add_child(search_row)
	_search_icon = Slate.icon_rect("search", 16, Slate.MUTED)
	search_row.add_child(_search_icon)
	_search_label = Slate.label("", 14, Slate.MUTED, Slate.semibold())
	search_row.add_child(_search_label)
	_search_text = Slate.label("", 14, Slate.FAINT)
	_search_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	search_row.add_child(_search_text)
	_search_key = Slate.key_chip("", 10)
	search_row.add_child(_search_key)
	row.add_child(_search)
	_toggles = HFlowContainer.new()
	_toggles.add_theme_constant_override("h_separation", 8)
	_toggles.add_theme_constant_override("v_separation", 8)
	_toggles.alignment = FlowContainer.ALIGNMENT_END
	_toggles.size_flags_horizontal = Control.SIZE_SHRINK_END
	row.add_child(_toggles)
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
	_aside.mouse_filter = Control.MOUSE_FILTER_PASS

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	_aside.add_child(col)
	col.add_child(_build_preview())

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	col.add_child(head)
	_aside_tile = PanelContainer.new()
	_aside_tile.add_theme_stylebox_override("panel", Slate.box(Color(1, 1, 1, 0.06), 12, Slate.BORDER, 1))
	_aside_tile.custom_minimum_size = Vector2(48, 48)
	_aside_tile.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var tile_stack := Control.new()
	tile_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_aside_tile.add_child(tile_stack)
	_aside_glyph = Slate.label("", 24, Slate.TEXT, Slate.mono_bold())
	_aside_glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_aside_glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_aside_glyph.set_anchors_preset(Control.PRESET_FULL_RECT)
	tile_stack.add_child(_aside_glyph)
	_aside_icon = Slate.icon_rect("list", 22, Slate.ACCENT)
	_aside_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	tile_stack.add_child(_aside_icon)
	head.add_child(_aside_tile)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 4)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(names)
	_aside_title = Slate.rich(17)
	_aside_title.add_theme_font_override("normal_font", Slate.bold())
	names.add_child(_aside_title)
	_aside_subtitle = Slate.label("", 11, Slate.FAINT, Slate.bold())
	_aside_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	names.add_child(_aside_subtitle)

	_aside_warn = PanelContainer.new()
	var warn_box := Slate.box(Color(Slate.DANGER, 0.1), 10, Color(Slate.DANGER, 0.35), 1)
	warn_box.content_margin_left = 12
	warn_box.content_margin_right = 12
	warn_box.content_margin_top = 8
	warn_box.content_margin_bottom = 8
	_aside_warn.add_theme_stylebox_override("panel", warn_box)
	var warn_row := HBoxContainer.new()
	warn_row.add_theme_constant_override("separation", 10)
	_aside_warn.add_child(warn_row)
	var alert := Slate.icon_rect("circle-alert", 16, Slate.DANGER)
	alert.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	warn_row.add_child(alert)
	_aside_warn_text = Slate.rich(13)
	_aside_warn_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_aside_warn_text.add_theme_color_override("default_color", Slate.DANGER)
	warn_row.add_child(_aside_warn_text)
	col.add_child(_aside_warn)

	_aside_rule = _rule()
	col.add_child(_aside_rule)
	_aside_scroll = ScrollContainer.new()
	_aside_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_aside_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_aside_scroll)
	_aside_body = Slate.rich(13)
	_aside_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_aside_body.add_theme_color_override("default_color", Slate.SOFT)
	_aside_body.add_theme_constant_override("line_separation", 4)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 16)
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_aside_scroll.add_child(stack)
	stack.add_child(_aside_body)
	_aside_sections = VBoxContainer.new()
	_aside_sections.add_theme_constant_override("separation", 16)
	stack.add_child(_aside_sections)
	_aside_empty = Slate.label("", 14, Slate.FAINT)
	_aside_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_aside_empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_aside_empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_aside_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_aside_empty)
	_buttons = VBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 8)
	col.add_child(_buttons)
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
	var most: Array = _msg.get("size", [1440, 920])
	var target := Vector2(minf(viewport.x - 48, float(most[0])), minf(viewport.y - 48, float(most[1])))
	# A docked screen sits over the HUD's sidebar and leaves the map visible and clickable
	# (look around); the others float in the middle over a dimmed backdrop. A "side" dock takes
	# the window's full height, for screens shown while the HUD is hidden (the overmap).
	var dock := String(_msg.get("dock", ""))
	var docked := dock == "right" or dock == "side"
	_scrim.visible = not docked
	if docked:
		var width := minf(float(most[0]), viewport.x * 0.45)
		var gap := 10.0
		var top := float(Hud.HEADER_HEIGHT) if dock == "right" else 0.0
		var bottom := float(Hud.BAR_HEIGHT) if dock == "right" else 0.0
		target = Vector2(width, viewport.y - top - bottom - 2 * gap)
		# The card shrinks first: a container is never smaller than its child's minimum size.
		_card.custom_minimum_size = target
		_center.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_center.position = Vector2(viewport.x - width - gap, top + gap)
		_center.size = target
	else:
		_center.set_anchors_preset(Control.PRESET_FULL_RECT)
		_center.offset_left = 0
		_center.offset_top = 0
		_center.offset_right = 0
		_center.offset_bottom = 0
	_card.custom_minimum_size = target
	var aside: Dictionary = _msg.get("aside", {})
	var wanted := float(aside.get("width", 400))
	var alone := Array(_msg.get("panes", [])).is_empty()
	_pane_row.visible = not alone
	# A docked screen is narrow: lists above the side panel, toggles below the search box.
	_body.vertical = docked
	_toolbar_row.vertical = docked
	_toggles.alignment = FlowContainer.ALIGNMENT_BEGIN if docked else FlowContainer.ALIGNMENT_END
	# Beside the search box the toggles take what it leaves and wrap onto more lines if needed.
	_toggles.size_flags_horizontal = Control.SIZE_FILL if docked else Control.SIZE_EXPAND_FILL
	_toggles.size_flags_stretch_ratio = 1.0 if docked else 2.0
	_search.custom_minimum_size.x = 0 if docked else 300
	var sb := _aside.get_theme_stylebox("panel") as StyleBoxFlat
	sb.border_width_left = 0 if alone or docked else 1
	sb.border_width_top = 1 if docked and not alone else 0
	sb.bg_color = Color(0, 0, 0, 0) if alone else Color(1, 1, 1, 0.025)
	_aside.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_aside.size_flags_stretch_ratio = 1.8 if docked else 1.0
	if alone or docked:
		# Only the side panel, or stacked under the lists: it takes the card's width.
		_aside.custom_minimum_size.x = 0
		_aside.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		_aside.size_flags_horizontal = Control.SIZE_FILL
		# The side panel takes up to 40% of the card unless the screen says otherwise (help text).
		_aside.custom_minimum_size.x = clampf(minf(wanted, target.x * float(aside.get("share", 0.4))), 260, wanted)


# --- Updates from the game -----------------------------------------------------------------------

func apply(msg: Dictionary) -> void:
	_msg = msg
	_badge_icon.texture = Slate.icon(String(msg.get("icon", "list")), 20)
	_title.text = String(msg.get("title", ""))
	# Screens that can't be left with a key (a conversation) have no close button.
	_close.visible = String(msg.get("quit", "QUIT")) != ""
	var subtitle: Array = msg.get("subtitle", [])
	_subtitle.text = Slate.bbcode(subtitle, Slate.FAINT).strip_edges()
	_subtitle.visible = _subtitle.text != ""
	_apply_stats(msg.get("stats", []))
	_apply_tabs(msg)
	_apply_subtabs(msg.get("subtabs", []))
	_apply_toolbar(msg)
	_layout()
	_apply_panes(msg.get("panes", []))
	_apply_aside(msg)
	_footer.text = Slate.bbcode(msg.get("footer", []), Slate.MUTED).strip_edges()
	_apply_hints(msg.get("hints", []))
	_apply_cursor()


func _apply_stats(stats: Array) -> void:
	for c in _stats.get_children():
		c.queue_free()
	for s in stats:
		var chip := PanelContainer.new()
		chip.add_theme_stylebox_override("panel", Slate.pill_box(Color(1, 1, 1, 0.05), 10, 5))
		chip.mouse_filter = Control.MOUSE_FILTER_PASS
		chip.tooltip_text = String(s.get("tip", ""))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(row)
		if String(s.get("icon", "")) != "":
			row.add_child(Slate.icon_rect(String(s["icon"]), 14, Slate.MUTED))
		var label := String(s.get("label", ""))
		if label != "":
			row.add_child(Slate.label(label, 12, Slate.MUTED, Slate.semibold()))
		var value := Slate.rich(12)
		value.autowrap_mode = TextServer.AUTOWRAP_OFF
		value.add_theme_font_override("normal_font", Slate.mono())
		value.text = Slate.bbcode(s.get("value", []), Slate.TEXT).strip_edges()
		row.add_child(value)
		_stats.add_child(chip)


func _apply_tabs(msg: Dictionary) -> void:
	var tabs: Array = msg.get("tabs", [])
	_tab_bar.visible = not tabs.is_empty()
	for c in _tabs.get_children():
		c.queue_free()
	var keys: Dictionary = msg.get("tab_keys", {})
	_set_chip(_tab_prev, String(keys.get("prev", "")))
	_set_chip(_tab_next, String(keys.get("next", "")))
	var active_tab: Control = null
	for t in tabs:
		var tab := _tab(t, false)
		_tabs.add_child(tab)
		if bool(t.get("active", false)):
			active_tab = tab
	if active_tab != null:
		_reveal_tab.call_deferred(active_tab)


func _reveal_tab(tab: Control) -> void:
	await get_tree().process_frame
	if is_instance_valid(tab):
		_tab_scroll.ensure_control_visible(tab)


func _apply_subtabs(subtabs: Array) -> void:
	_subtab_bar.visible = not subtabs.is_empty()
	for c in _subtabs.get_children():
		c.queue_free()
	for t in subtabs:
		_subtabs.add_child(_tab(t, true))


func _set_chip(chip: PanelContainer, key: String) -> void:
	(chip.get_child(0) as Label).text = Slate.key_name(key)
	chip.visible = key != ""


## One tab: amber when active. Clicking sends the tab's pick (or presses its action).
func _tab(t: Dictionary, small: bool) -> Control:
	var active := bool(t.get("active", false))
	var tab := PanelContainer.new()
	var bg := Color(Slate.ACCENT, 0.15) if active else Color(0, 0, 0, 0)
	var sb := Slate.box(bg, 8, Color(Slate.ACCENT, 0.5) if active else Slate.BORDER, 1 if (active or small) else 0)
	sb.content_margin_left = 10 if small else 12
	sb.content_margin_right = 10 if small else 12
	sb.content_margin_top = 4 if small else 7
	sb.content_margin_bottom = 4 if small else 7
	tab.add_theme_stylebox_override("panel", sb)
	tab.mouse_filter = Control.MOUSE_FILTER_STOP
	tab.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tab.tooltip_text = String(t.get("tip", ""))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tab.add_child(row)
	var color := Slate.ACCENT if active else (Slate.MUTED if bool(t.get("enabled", true)) else Slate.FAINT)
	if String(t.get("icon", "")) != "":
		row.add_child(Slate.icon_rect(String(t["icon"]), 14, color))
	var label := Slate.label(String(t.get("text", "")), 11 if small else 12, color, Slate.bold())
	row.add_child(label)
	if String(t.get("count", "")) != "":
		row.add_child(Slate.label(String(t["count"]), 11, Slate.FAINT, Slate.mono()))
	tab.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			if t.has("pick"):
				Bridge.pick(view_id, int(t["pick"]), String(t.get("act", "")))
			elif t.has("act"):
				Bridge.press(view_id, String(t["act"])))
	return tab


func _apply_toolbar(msg: Dictionary) -> void:
	var search: Dictionary = msg.get("search", {})
	var toggles: Array = msg.get("toggles", [])
	_toolbar.visible = not search.is_empty() or not toggles.is_empty()
	_search.visible = not search.is_empty()
	if not search.is_empty():
		var typing := bool(search.get("typing", false))
		var text := String(search.get("text", ""))
		_search.add_theme_stylebox_override("panel", _search_box(typing))
		_search.tooltip_text = String(search.get("tip", ""))
		# The box doubles as a plain text field (a world's name) with its own icon and label.
		_search_icon.texture = Slate.icon(String(search.get("icon", "search")), 16)
		_search_label.text = String(search.get("label", ""))
		_search_label.visible = _search_label.text != ""
		_search.mouse_default_cursor_shape = Control.CURSOR_IBEAM if search.has("act") else Control.CURSOR_ARROW
		if typing or text != "":
			_search_text.text = text + ("▏" if typing else "")
			_search_text.add_theme_color_override("font_color", Slate.TEXT)
		else:
			_search_text.text = String(search.get("placeholder", "Search"))
			_search_text.add_theme_color_override("font_color", Slate.FAINT)
		_set_chip(_search_key, "" if typing else String(search.get("key", "")))
	for c in _toggles.get_children():
		c.queue_free()
	for t in toggles:
		var b := SlateButton.new(String(t.get("icon", "")), String(t.get("text", "")), false)
		b.set_key(String(t.get("key", "")))
		b.set_on(bool(t.get("on", false)))
		b.set_enabled(bool(t.get("enabled", true)))
		b.tooltip_text = String(t.get("tip", ""))
		_connect_action(b, t)
		_toggles.add_child(b)
	_body_rule.visible = _toolbar.visible or _tab_bar.visible or _subtab_bar.visible


## Wires a button to the pick or action the game gave it.
func _connect_action(b: SlateButton, spec: Dictionary) -> void:
	b.pressed.connect(func():
		if spec.has("pick"):
			Bridge.pick(view_id, int(spec["pick"]), String(spec.get("act", "")))
		elif spec.has("act"):
			Bridge.press(view_id, String(spec["act"])))


func _apply_panes(panes: Array) -> void:
	var rebuild := panes.size() != _panes.size()
	if not rebuild:
		for p in panes.size():
			if _pane_hash(panes[p]) != _pane_hashes[p]:
				rebuild = true
				break
	if rebuild:
		_build_panes(panes)
	for p in panes.size():
		(_panes[p] as Pane).apply_state(panes[p])


func _pane_hash(pane: Dictionary) -> int:
	return JSON.stringify([pane.get("rows", []), pane.get("body", []), pane.get("entries", []),
			pane.get("columns", []), pane.get("title", ""), pane.get("empty", ""), pane.has("grid")]).hash()


func _build_panes(panes: Array) -> void:
	for c in _pane_row.get_children():
		c.queue_free()
	_panes.clear()
	_pane_hashes.clear()
	_rows.clear()
	for p in panes.size():
		var spec: Dictionary = panes[p]
		if p > 0:
			_pane_row.add_child(_rule(true))
		var pane := Pane.new()
		pane.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pane.size_flags_stretch_ratio = float(spec.get("stretch", 1.0))
		_pane_row.add_child(pane)
		pane.setup(spec)
		if pane.board != null:
			_connect_board(pane.board, p, spec)
		_panes.append(pane)
		_pane_hashes.append(_pane_hash(spec))
		var rows: Array = spec.get("rows", [])
		var widths := _cell_widths(rows)
		var keyed := rows.any(func(r): return String(r.get("key", "")) != "")
		var glyphs := rows.any(func(r): return String(r.get("sym", "")) != "")
		var marks := rows.any(func(r): return r.has("mark"))
		var confirm := String(spec.get("confirm", "CONFIRM"))
		for i in rows.size():
			var r: Dictionary = rows[i]
			if bool(r.get("heading", false)):
				pane.add_heading(r, widths)
				continue
			var row := ListRow.new()
			row.setup(r, {"keyed": keyed, "glyphs": glyphs, "marks": marks, "widths": widths})
			var index := int(r.get("i", i))
			var code := int(r.get("pick", p * STRIDE + index))
			var at := Vector2i(p, index)
			# A row may override what clicking it again, or its check box, presses.
			var row_confirm := String(r.get("confirm", confirm))
			var mark_act := String(r.get("mark_act", spec.get("mark_act", "")))
			row.clicked.connect(func():
				if at != _cursor or row_confirm == "":
					Bridge.pick(view_id, code, "")
				else:
					Bridge.pick(view_id, code, row_confirm))
			row.activated.connect(func():
				if row_confirm != "":
					Bridge.pick(view_id, code, row_confirm))
			row.marked.connect(func(): Bridge.pick(view_id, code, mark_act))
			pane.add_row(row)
			_rows[at] = row
		pane.finish()


## A board's squares send their pick, `pane * STRIDE + row * 1000 + column`, with the action the
## game gave for that mouse button (none only moves its cursor there).
func _connect_board(board: Board, p: int, spec: Dictionary) -> void:
	var acts := {MOUSE_BUTTON_LEFT: String(spec.get("click", "")), MOUSE_BUTTON_RIGHT: String(spec.get("right_click", ""))}
	board.cell_clicked.connect(func(row: int, column: int, button: int):
		if acts.has(button):
			Bridge.pick(view_id, p * STRIDE + row * 1000 + column, acts[button]))


## Width of each extra column: as wide as its widest value or title, up to a limit.
static func _cell_widths(rows: Array) -> Array:
	var widths := []
	for r in rows:
		var cells: Array = r.get("cells", [])
		var heading := bool(r.get("heading", false))
		for i in cells.size():
			var w := 0.0
			if heading:
				w = Slate.bold().get_string_size(Slate.plain(cells[i]).strip_edges().to_upper(),
						HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
			else:
				w = ListRow.text_width(Slate.plain(cells[i]).strip_edges())
			if i >= widths.size():
				widths.append(MIN_CELL_WIDTH)
			widths[i] = clampf(ceilf(w) + 4, widths[i], MAX_CELL_WIDTH)
	return widths


func _apply_cursor() -> void:
	var panes: Array = _msg.get("panes", [])
	var active := int(_msg.get("active_pane", 0))
	var cursor := Vector2i(-1, -1)
	for p in panes.size():
		var c := int(panes[p].get("cursor", -1))
		if p == active:
			cursor = Vector2i(p, c)
	var moved := cursor != _cursor
	_cursor = cursor
	for at in _rows:
		var on: bool = at.y == int(panes[at.x].get("cursor", -1)) if at.x < panes.size() else false
		(_rows[at] as ListRow).set_selected(on, at.x == active)
	for p in _panes.size():
		(_panes[p] as Pane).set_active(p == active and panes.size() > 1)
	if _rows.has(_cursor):
		_scroll_to(_rows[_cursor], moved)


func _scroll_to(row: Control, moved: bool) -> void:
	await get_tree().process_frame
	if not is_instance_valid(row):
		return
	var scroll := row.get_parent().get_parent().get_parent() as ScrollContainer
	if scroll != null:
		if moved:
			scroll.ensure_control_visible(row)
		scroll.scroll_horizontal = 0


func _apply_aside(msg: Dictionary) -> void:
	_aside.visible = msg.has("aside")
	if not _aside.visible:
		return
	var aside: Dictionary = msg["aside"]
	_apply_preview(aside.get("preview", {}))
	var has_title := aside.has("title")
	var sym := String(aside.get("sym", ""))
	var icon := String(aside.get("icon", ""))
	_aside_tile.visible = has_title and (sym != "" or icon != "")
	_aside_glyph.text = sym
	_aside_glyph.add_theme_color_override("font_color", Slate.curses(String(aside.get("sym_color", "c_white"))))
	_aside_icon.visible = sym == "" and icon != ""
	if icon != "":
		_aside_icon.texture = Slate.icon(icon, 22)
	_aside_title.get_parent().visible = has_title
	_aside_rule.visible = has_title
	_aside_title.text = Slate.bbcode(aside.get("title", []), Slate.TEXT)
	_aside_subtitle.text = String(aside.get("subtitle", "")).to_upper()
	_aside_subtitle.visible = _aside_subtitle.text != ""
	var warn: Array = aside.get("warn", [])
	_aside_warn.visible = not warn.is_empty()
	_aside_warn_text.text = Slate.bbcode(warn, Slate.DANGER).strip_edges()
	var body := Slate.tidy_body(Slate.bbcode(aside.get("body", []), Slate.SOFT))
	var empty := String(aside.get("empty", ""))
	var sections: Array = aside.get("sections", [])
	_apply_sections(sections)
	_aside_body.visible = body != ""
	_aside_scroll.visible = body != "" or not sections.is_empty()
	_aside_empty.visible = _aside_scroll.visible == false and empty != ""
	_aside_empty.text = empty
	# Text laid out in columns by the game (look around) keeps its alignment in a fixed-width font.
	if bool(aside.get("mono", false)):
		_aside_body.add_theme_font_override("normal_font", Slate.mono())
		_aside_body.add_theme_font_size_override("normal_font_size", 12)
	else:
		_aside_body.remove_theme_font_override("normal_font")
		_aside_body.add_theme_font_size_override("normal_font_size", 13)
	if body != _aside_body.text:
		_aside_body.text = body
		_aside_scroll.scroll_vertical = 0
	if aside.has("scroll"):
		_aside_scroll.scroll_vertical = int(float(aside["scroll"]) * LINE_HEIGHT)
	_apply_buttons(aside.get("buttons", msg.get("buttons", [])))


func _build_preview() -> Control:
	_preview = VBoxContainer.new()
	_preview.add_theme_constant_override("separation", 8)
	var well := PanelContainer.new()
	# Black like the game draws behind the character, so the crop has no visible edge.
	var box := Slate.box(Color.BLACK, 12, Slate.BORDER, 1)
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	well.add_theme_stylebox_override("panel", box)
	_preview.add_child(well)
	_preview_image = TextureRect.new()
	_preview_image.texture = _preview_atlas
	_preview_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	well.add_child(_preview_image)
	_preview_buttons = HBoxContainer.new()
	_preview_buttons.add_theme_constant_override("separation", 8)
	_preview.add_child(_preview_buttons)
	_preview.visible = false
	return _preview


## Shows the part of the game's frame where it drew the character (`rect` in frame pixels), with
## the zoom and clothes buttons.
func _apply_preview(spec: Dictionary) -> void:
	var rect: Array = spec.get("rect", [])
	_preview.visible = rect.size() == 4
	if not _preview.visible:
		return
	var region := Rect2(float(rect[0]), float(rect[1]), float(rect[2]), float(rect[3]))
	if _preview_atlas.region != region:
		_preview_atlas.region = region
	# Pixel art stays crisp at its own size; a sprite too big for the panel shrinks smoothly.
	var height := minf(region.size.y, PREVIEW_HEIGHT)
	_preview_image.custom_minimum_size.y = height
	_preview_image.texture_filter = TEXTURE_FILTER_LINEAR if region.size.y > PREVIEW_HEIGHT else TEXTURE_FILTER_NEAREST
	for c in _preview_buttons.get_children():
		c.queue_free()
	var buttons: Array = spec.get("buttons", [])
	_preview_buttons.visible = not buttons.is_empty()
	for b_spec in buttons:
		# Zoom buttons fit as an icon and a key; a switch keeps its name so its state reads.
		var text := String(b_spec.get("text", ""))
		var is_switch: bool = b_spec.has("on")
		var b := SlateButton.new(String(b_spec.get("icon", "")), text if is_switch else "", false, true)
		b.set_key(String(b_spec.get("key", "")))
		b.tooltip_text = text
		if is_switch:
			b.set_on(bool(b_spec["on"]))
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_connect_action(b, b_spec)
		_preview_buttons.add_child(b)


func _on_frame(texture: ImageTexture) -> void:
	if _preview_atlas.atlas != texture:
		_preview_atlas.atlas = texture


## Titled blocks of text below the body (a vehicle's parts, its description, its stats), each
## optionally in a fixed-width font to keep columns the game lined up.
func _apply_sections(sections: Array) -> void:
	var have := _aside_sections.get_child_count()
	for i in range(sections.size(), have):
		_aside_sections.get_child(i).queue_free()
	for i in sections.size():
		var spec: Dictionary = sections[i]
		var box: VBoxContainer
		if i < have:
			box = _aside_sections.get_child(i) as VBoxContainer
		else:
			box = VBoxContainer.new()
			box.add_theme_constant_override("separation", 6)
			var head := Slate.label("", 11, Slate.FAINT, Slate.bold())
			box.add_child(head)
			var text := Slate.rich(13)
			text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			text.add_theme_color_override("default_color", Slate.SOFT)
			text.add_theme_constant_override("line_separation", 3)
			box.add_child(text)
			_aside_sections.add_child(box)
		var head := box.get_child(0) as Label
		head.text = String(spec.get("title", "")).to_upper()
		head.visible = head.text != ""
		var label := box.get_child(1) as RichTextLabel
		if bool(spec.get("mono", false)):
			label.add_theme_font_override("normal_font", Slate.mono())
			label.add_theme_font_size_override("normal_font_size", 12)
		else:
			label.remove_theme_font_override("normal_font")
			label.add_theme_font_size_override("normal_font_size", 13)
		var text := Slate.tidy_body(Slate.bbcode(spec.get("body", []), Slate.SOFT))
		if label.text != text:
			label.text = text
		box.visible = text != ""


func _apply_buttons(buttons: Array) -> void:
	for c in _buttons.get_children():
		c.queue_free()
	var grid: GridContainer = null
	for spec in buttons:
		var primary := bool(spec.get("primary", false))
		var b := SlateButton.new(String(spec.get("icon", "")), String(spec.get("text", "")), primary)
		b.set_key(String(spec.get("key", "")))
		b.set_enabled(bool(spec.get("enabled", true)))
		b.tooltip_text = String(spec.get("tip", ""))
		# A button for a setting (a map marker) shows whether it is on.
		if spec.has("on"):
			b.set_on(bool(spec["on"]))
		if spec.has("color"):
			b.set_text_color(Slate.curses(String(spec["color"])))
		_connect_action(b, spec)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if primary:
			_buttons.add_child(b)
			continue
		b.set_compressible()
		if grid == null:
			grid = GridContainer.new()
			grid.columns = 2
			grid.add_theme_constant_override("h_separation", 8)
			grid.add_theme_constant_override("v_separation", 8)
			_buttons.add_child(grid)
		grid.add_child(b)
	_buttons.visible = not buttons.is_empty()


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


## One list: an optional header with its name and count, then its rows (or a block of text).
class Pane extends VBoxContainer:
	var board: Board
	var _title: Label
	var _count: Label
	var _note: RichTextLabel
	var _underline: ColorRect
	var _scroll: ScrollContainer
	var _list: VBoxContainer
	var _text: RichTextLabel
	var _entries: Array[Control] = []
	var _items := 0
	var _empty := ""

	func setup(spec: Dictionary) -> void:
		add_theme_constant_override("separation", 0)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_empty = String(spec.get("empty", "Nothing here."))
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 8)
		head.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if String(spec.get("icon", "")) != "":
			head.add_child(Slate.icon_rect(String(spec["icon"]), 15, Slate.MUTED))
		_title = Slate.label(String(spec.get("title", "")), 13, Slate.MUTED, Slate.bold())
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
		var head_col := VBoxContainer.new()
		head_col.add_theme_constant_override("separation", 4)
		head_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		head_col.add_child(head)
		# A line or two under the title, such as where the list's items are (moving items).
		_note = Slate.rich(12)
		_note.add_theme_color_override("default_color", Slate.FAINT)
		_note.visible = false
		head_col.add_child(_note)
		head_box.add_child(head_col)
		head_box.visible = String(spec.get("title", "")) != ""
		add_child(head_box)
		_underline = ColorRect.new()
		_underline.custom_minimum_size.y = 2
		_underline.color = Color(0, 0, 0, 0)
		_underline.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_underline.visible = head_box.visible
		add_child(_underline)

		_scroll = ScrollContainer.new()
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
		if spec.has("body"):
			_text = Slate.rich(13)
			_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_text.add_theme_color_override("default_color", Slate.SOFT)
			_text.add_theme_constant_override("line_separation", 4)
			_text.text = Slate.tidy_body(Slate.bbcode(spec["body"], Slate.SOFT))
			var text_pad := MarginContainer.new()
			for side in ["left", "right"]:
				text_pad.add_theme_constant_override("margin_" + side, 10)
			text_pad.add_child(_text)
			_list.add_child(text_pad)
			_items = -1
		elif spec.has("entries"):
			_add_entries(spec["entries"])
		elif spec.has("grid"):
			board = Board.new()
			board.setup(spec)
			_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
			(_list.get_parent() as Control).size_flags_vertical = Control.SIZE_EXPAND_FILL
			_list.add_child(board)
			_items = -1

	## A log: wrapped entries, each with a time shown only where it changes (the message log).
	func _add_entries(entries: Array) -> void:
		var prev_time := ""
		var timed := entries.any(func(e): return String(e.get("time", "")) != "")
		for e in entries:
			var time := String(e.get("time", ""))
			var line := HBoxContainer.new()
			line.add_theme_constant_override("separation", 14)
			line.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var stamp := Slate.label(time if time != prev_time else "", 11, Slate.curses("c_light_blue"), Slate.mono())
			stamp.custom_minimum_size.x = 104
			stamp.visible = timed
			stamp.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			stamp.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			stamp.add_theme_constant_override("line_spacing", 0)
			line.add_child(stamp)
			var text := Slate.rich(14)
			text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			text.text = Slate.bbcode(e.get("text", []), Slate.TEXT)
			line.add_child(text)
			var box := MarginContainer.new()
			box.add_theme_constant_override("margin_left", 4)
			box.add_theme_constant_override("margin_right", 10)
			box.add_theme_constant_override("margin_top", 10 if time != prev_time and not _entries.is_empty() else 2)
			box.mouse_filter = Control.MOUSE_FILTER_IGNORE
			box.add_child(line)
			_list.add_child(box)
			_entries.append(box)
			prev_time = time
		_items = entries.size()

	func apply_state(spec: Dictionary) -> void:
		if board != null:
			board.setup(spec)
		_count.text = String(spec.get("count", str(_items) if _items > 0 else ""))
		_title.text = String(spec.get("title", ""))
		_note.text = Slate.bbcode(spec.get("note", []), Slate.FAINT).strip_edges()
		_note.visible = _note.text != ""
		if _text != null and spec.has("scroll"):
			_scroll.scroll_vertical = int(float(spec["scroll"]) * LINE_HEIGHT)
		if spec.has("scroll_row") and _list.get_child_count() > 0:
			await get_tree().process_frame
			var row := _list.get_child(clampi(int(spec["scroll_row"]), 0, _list.get_child_count() - 1)) as Control
			_scroll.scroll_vertical = int(row.position.y)
		if not _entries.is_empty() and (spec.has("scroll_entry") or bool(spec.get("scroll_end", false))):
			await get_tree().process_frame
			if bool(spec.get("scroll_end", false)):
				_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)
			else:
				var at := clampi(int(spec["scroll_entry"]), 0, _entries.size() - 1)
				_scroll.scroll_vertical = int(_entries[at].position.y)

	func add_heading(r: Dictionary, widths: Array) -> void:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", CELL_GAP)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var title := Slate.label(Slate.plain(r.get("text", [])).strip_edges().to_upper(), 11,
				Slate.lead_color(r.get("text", []), Slate.FAINT), Slate.bold())
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.clip_text = true
		row.add_child(title)
		var cells: Array = r.get("cells", [])
		for i in cells.size():
			var c := Slate.label(Slate.plain(cells[i]).strip_edges().to_upper(), 9, Slate.FAINT, Slate.bold())
			c.custom_minimum_size.x = widths[i] if i < widths.size() else MIN_CELL_WIDTH
			c.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			c.clip_text = true
			row.add_child(c)
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
		if _items == 0:
			var empty := Slate.label(_empty, 13, Slate.FAINT)
			empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			empty.custom_minimum_size.y = 80
			empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			_list.add_child(empty)

	func set_active(on: bool) -> void:
		_title.add_theme_color_override("font_color", Slate.TEXT if on else Slate.MUTED)
		_underline.color = Color(Slate.ACCENT, 0.9) if on else Slate.BORDER


## One row: optional mark box, key, glyph or icon, text, a note and extra columns.
class ListRow extends PanelContainer:
	signal clicked
	signal activated
	signal marked

	var _enabled := true
	var _selected := false
	var _active := false
	var _hover := false

	static func text_width(text: String) -> float:
		return Slate.mono().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x

	func setup(row: Dictionary, opts: Dictionary) -> void:
		_enabled = bool(row.get("enabled", true))
		custom_minimum_size.y = ROW_HEIGHT
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if _enabled else Control.CURSOR_ARROW
		if bool(row.get("passive", false)):
			# Information only: not clickable, but not dimmed either.
			mouse_filter = Control.MOUSE_FILTER_PASS
			mouse_default_cursor_shape = Control.CURSOR_ARROW
			set_meta("passive", true)
		mouse_entered.connect(func():
			_hover = _enabled and not has_meta("passive")
			_restyle())
		mouse_exited.connect(func():
			_hover = false
			_restyle())
		var text: Array = _trimmed(row.get("text", []))
		tooltip_text = Slate.plain(text).replace(char(0xa0), " ")
		if String(row.get("tip", "")) != "":
			tooltip_text += "\n" + String(row["tip"])

		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(line)

		if int(row.get("indent", 0)) > 0:
			var gap := Control.new()
			gap.custom_minimum_size.x = 14 * int(row["indent"])
			gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
			line.add_child(gap)
		if bool(opts.get("marks", false)):
			line.add_child(_mark_box(row))
		if bool(opts.get("keyed", false)):
			var key := String(row.get("key", ""))
			var slot := CenterContainer.new()
			slot.custom_minimum_size.x = 22
			slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var chip := Slate.key_chip(key, 11)
			chip.visible = key != ""
			slot.add_child(chip)
			line.add_child(slot)
		if bool(opts.get("glyphs", false)):
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
		if String(row.get("icon", "")) != "":
			var icon := Slate.icon_rect(String(row["icon"]), 16, Slate.curses(String(row.get("icon_color", "")), Slate.MUTED))
			icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			line.add_child(icon)

		var name := Slate.rich(14, false)
		name.autowrap_mode = TextServer.AUTOWRAP_OFF
		name.clip_contents = true
		name.custom_minimum_size = Vector2(60, 22)
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		name.add_theme_font_override("normal_font", Slate.semibold())
		name.text = Slate.bbcode(text, Slate.TEXT)
		line.add_child(name)

		var note: Array = row.get("note", [])
		if not note.is_empty():
			var n := Slate.label(Slate.plain(note).strip_edges(), 12, Slate.lead_color(note, Slate.FAINT))
			n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			n.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			n.custom_minimum_size.x = 60
			n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			n.size_flags_stretch_ratio = 0.6
			line.add_child(n)

		var widths: Array = opts.get("widths", [])
		var cells: Array = row.get("cells", [])
		if not cells.is_empty():
			var values := HBoxContainer.new()
			values.add_theme_constant_override("separation", CELL_GAP)
			values.mouse_filter = Control.MOUSE_FILTER_IGNORE
			line.add_child(values)
			for i in cells.size():
				var runs := _trimmed(cells[i])
				var width: float = widths[i] if i < widths.size() else MIN_CELL_WIDTH
				var plain := Slate.plain(runs)
				if text_width(plain) + 4 > width:
					var cut := Slate.label(plain, 12, Slate.lead_color(runs, Slate.MUTED), Slate.mono())
					cut.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
					cut.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
					cut.custom_minimum_size.x = width
					cut.size_flags_vertical = Control.SIZE_SHRINK_CENTER
					cut.tooltip_text = plain
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
		if not _enabled:
			for c in line.get_children():
				(c as CanvasItem).modulate.a = 0.55
		_restyle()

	func _mark_box(row: Dictionary) -> Control:
		# A row without a check box in a list that has them keeps the space, so texts line up.
		if not row.has("mark"):
			var space := Control.new()
			space.custom_minimum_size = Vector2(22, 22)
			space.mouse_filter = Control.MOUSE_FILTER_IGNORE
			return space
		var on := bool(row.get("mark", false))
		var box := PanelContainer.new()
		box.add_theme_stylebox_override("panel", Slate.box(Slate.ACCENT if on else Color(0, 0, 0, 0), 6,
				Slate.ACCENT if on else Slate.BORDER_STRONG, 0 if on else 2))
		box.custom_minimum_size = Vector2(22, 22)
		box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		box.mouse_filter = Control.MOUSE_FILTER_STOP
		box.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		if on:
			box.add_child(Slate.icon_rect("check", 14, Slate.ACCENT_TEXT))
		box.gui_input.connect(func(e: InputEvent):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				box.accept_event()
				marked.emit())
		return box

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
		elif _selected or _hover:
			bg = Color(1, 1, 1, 0.045)
		var sb := Slate.box(bg, 10, Slate.BORDER, 0)
		if _selected and _active:
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
			if not _enabled or has_meta("passive"):
				return
			if event.double_click:
				activated.emit()
			else:
				clicked.emit()


## A board of character squares (the minigames) in the game's colors, as large as fits. Text
## boards draw each cell as a mono glyph. Square boards (`square`) draw a tile per cell: `lit`
## characters as lit tiles, `raised` ones as raised tiles, `hide` ones with no glyph on top.
## On any board, `fill` characters become solid blocks and `dot` ones round dots, in their color.
## Highlighted cells (the cursor) get a ring, unless the board is `plain` (colored backgrounds
## that mean nothing).
class Board extends Control:
	signal cell_clicked(row: int, column: int, button: int)

	const PAD := 10.0
	const GAP := 2.0
	## Line drawing characters as the arms they join (up 1, right 2, down 4, left 8), drawn as
	## strokes so walls meet across squares.
	const LINES := {"─": 10, "│": 5, "┌": 6, "┐": 12, "└": 3, "┘": 9, "├": 7, "┤": 13, "┬": 14,
			"┴": 11, "┼": 15}

	var _back := Slate.box(Color(1, 1, 1, 0.03), 8, Slate.BORDER, 1)
	var _flat_box := Slate.box(Color(1, 1, 1, 0.04), 5, Color(0, 0, 0, 0), 0)
	var _raised_box := Slate.box(Color(1, 1, 1, 0.13), 5, Color(1, 1, 1, 0.2), 1)
	var _lit_box := Slate.box(Slate.ACCENT, 6, Slate.ACCENT.lightened(0.35), 1)
	var _ring_box := Slate.box(Color(Slate.ACCENT, 0.16), 5, Slate.ACCENT, 2)
	var _boom_box := Slate.box(Color(Slate.DANGER, 0.35), 5, Slate.DANGER, 2)
	var _rows: Array = []
	var _columns := 0
	var _font: Font
	var _want := 22
	var _square := false
	var _raised := ""
	var _hide := ""
	var _lit := ""
	var _fill := ""
	var _dot := ""
	var _plain := false
	var _cell := Vector2(14, 28)
	var _font_size := 22
	var _origin := Vector2.ZERO

	func setup(spec: Dictionary) -> void:
		_font = Slate.mono()
		_want = int(spec.get("cell", 22))
		_square = bool(spec.get("square", false))
		_raised = String(spec.get("raised", ""))
		_hide = String(spec.get("hide", ""))
		_lit = String(spec.get("lit", ""))
		_fill = String(spec.get("fill", ""))
		_dot = String(spec.get("dot", ""))
		_plain = bool(spec.get("plain", false))
		_rows = []
		_columns = 0
		for runs in spec.get("grid", []):
			var cells := []
			for run in runs:
				var name := String(run[1]) if run.size() > 1 else ""
				for ch in String(run[0]):
					cells.append([ch, name])
			_columns = maxi(_columns, cells.size())
			_rows.append(cells)
		custom_minimum_size = Vector2(_columns, _rows.size()) * 6 + Vector2(PAD, PAD) * 2
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		size_flags_vertical = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_STOP
		queue_redraw()

	## Cell size and font size for the room there is: as asked for, or smaller to fit.
	func _layout() -> void:
		var glyph := _font.get_string_size("M", HORIZONTAL_ALIGNMENT_LEFT, -1, 100).x / 100.0
		var want := Vector2(_want, _want) if _square else Vector2(ceilf(_want * glyph), ceilf(_want * 1.3))
		var room := size - Vector2(PAD, PAD) * 2
		var scale := 1.0
		if _columns > 0 and not _rows.is_empty():
			scale = minf(1.0, minf(room.x / (want.x * _columns), room.y / (want.y * _rows.size())))
		_cell = (want * scale).floor().max(Vector2(3, 3))
		_font_size = maxi(6, int((_want * 0.55 if _square else float(_want)) * scale))
		_origin = ((size - _cell * Vector2(_columns, _rows.size())) / 2).floor()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()

	func _draw() -> void:
		_layout()
		draw_style_box(_back, Rect2(_origin, _cell * Vector2(_columns, _rows.size())).grow(PAD))
		var baseline := (_cell.y - _font.get_height(_font_size)) / 2 + _font.get_ascent(_font_size)
		for y in _rows.size():
			var cells: Array = _rows[y]
			for x in cells.size():
				var ch := String(cells[x][0])
				var name := String(cells[x][1])
				var at := _origin + Vector2(x * _cell.x, y * _cell.y)
				var lit := name.begins_with("h_")
				if lit:
					name = "c_" + name.substr(2)
					lit = not _plain
				var color := Slate.curses(name, Slate.TEXT)
				if _square:
					var tile := Rect2(at, _cell).grow(-GAP)
					if _lit.contains(ch):
						draw_style_box(_lit_box, tile)
					elif _raised.contains(ch):
						draw_style_box(_raised_box, tile)
					elif ch != " " and not LINES.has(ch):
						draw_style_box(_flat_box, tile)
					if lit:
						draw_style_box(_boom_box if name == "c_red" else _ring_box, tile)
				elif lit:
					draw_rect(Rect2(at, _cell), Color(Slate.ACCENT, 0.3))
					color = color.lightened(0.25)
				if LINES.has(ch):
					_draw_lines(at, int(LINES[ch]), color)
				elif _fill.contains(ch):
					draw_rect(Rect2(at, _cell).grow(-1), color)
				elif _dot.contains(ch):
					draw_circle(at + _cell / 2, minf(_cell.x, _cell.y) * 0.42, color)
				elif ch != " " and not _hide.contains(ch):
					var left := (_cell.x - _font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size).x) / 2
					draw_string(_font, at + Vector2(left, baseline), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size, color)

	func _draw_lines(at: Vector2, arms: int, color: Color) -> void:
		var mid := at + _cell / 2
		var width := maxf(2.0, roundf(minf(_cell.x, _cell.y) / 7.0))
		var ends := [Vector2(0, -_cell.y / 2), Vector2(_cell.x / 2, 0), Vector2(0, _cell.y / 2), Vector2(-_cell.x / 2, 0)]
		for i in 4:
			if arms & (1 << i):
				draw_line(mid, mid + ends[i], color, width)
		draw_rect(Rect2(mid - Vector2(width, width) / 2, Vector2(width, width)), color)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			var cell := Vector2i(((event.position - _origin) / _cell).floor())
			if cell.y >= 0 and cell.y < _rows.size() and cell.x >= 0 and cell.x < _columns:
				accept_event()
				cell_clicked.emit(cell.y, cell.x, event.button_index)
