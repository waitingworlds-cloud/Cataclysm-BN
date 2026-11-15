extends Control
## A full screen the game describes as data (view kind `screen`): title, tabs, search, one or more
## lists, a details side panel with action buttons, and key hints. Crafting, construction, the
## character sheet and most other big screens use it; the game decides what each part holds and
## what clicking it does (see README.md, "Screens").
##
## It sits in the frame the main screen uses (see `cockpit.gd`): the title or the tabs to the
## other big screens in the top bar, a panel with the screen's own tabs and search, one module
## per list, the side panel as a module at the right, and the key hints along the bottom. A
## docked screen (look around, the item list, the overmap's panel) is a single panel over the
## right side instead, so the map stays visible and clickable.
##
## Clicking a row selects it (a pick with no key pressed); clicking the selected row again, or
## double clicking, picks it and presses the pane's `confirm` action. Tabs and buttons send the
## pick or action the game gave them. Every key still goes to the game.

const SlateButton := preload("res://src/ui/slate_button.gd")
const Hud := preload("res://src/ui/hud.gd")

const STRIDE := 100000
const ROW_HEIGHT := 34
## Rows that show an item in a slot (recipes) are taller.
const SLOT_ROW_HEIGHT := 60
const MIN_CELL_WIDTH := 30
const MAX_CELL_WIDTH := 220
const CELL_GAP := 12
const LINE_HEIGHT := 22.0
## Tallest the character preview gets before it shrinks to fit.
const PREVIEW_HEIGHT := 280.0

var view_id := 0
## A docked screen as narrow as the main screen's right column: buttons go one per line.
var _narrow := false

var _msg := {}
## Which dock a docked screen is in: "right" (over the main screen's right column) or "side"
## (the one column of a wide frame, for the overmap and vehicles).
var _dock_kind := ""
## "" until the first message, then "framed" or "docked".
var _mode := ""
var _shell: Control
var _cockpit: Cockpit
var _cols: BoxContainer
var _main: VBoxContainer
var _filter: PanelContainer
var _center: Control
var _card: PanelContainer
var _title: Label
var _close: Button
var _info_row: Control
var _subtitle: RichTextLabel
var _stats: HBoxContainer
var _tab_bar: Control
var _tabs: HFlowContainer
var _subtab_bar: Control
var _subtabs: HFlowContainer
var _toolbar: Control
var _search: PanelContainer
var _search_text: Label
var _search_icon: TextureRect
var _search_label: Label
var _search_key: PanelContainer
var _toggles: HFlowContainer
var _toolbar_row: BoxContainer
var _body: BoxContainer
var _pane_row: HBoxContainer
var _aside: PanelContainer
var _aside_strip: Control
var _aside_strip_title: Label
var _aside_pad: MarginContainer
var _aside_slot: ItemSlot
var _aside_icon: TextureRect
var _aside_title: RichTextLabel
var _foot_stamp := 0
## Columns a grid of buttons ended up with, by what it holds (see `_fit_grid`).
var _grid_fit := {}
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
var _dock_footer: Control
var _footer: RichTextLabel
var _hints: Container

## Panes as built: the Pane node and the hash of the rows it was built from, so unchanged lists
## aren't rebuilt on every key press.
var _panes: Array = []
var _pane_hashes: Array = []
var _rows := {}
var _cursor := Vector2i(-1, -1)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Bridge.frame_received.connect(_on_frame)
	# The parts every screen has; `_assemble` puts them in the frame or in a docked panel.
	_info_row = _build_info()
	_tab_bar = _build_tabs()
	_subtab_bar = _build_subtabs()
	_toolbar = _build_toolbar()
	_pane_row = HBoxContainer.new()
	_pane_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pane_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_pane_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_aside()
	resized.connect(_layout)


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


static func _unparent(node: Node) -> void:
	if node != null and node.get_parent() != null:
		node.get_parent().remove_child(node)


## Puts the screen's parts where its mode wants them: in the frame, or in one docked panel.
func _assemble(mode: String) -> void:
	for part in [_info_row, _tab_bar, _subtab_bar, _toolbar, _pane_row, _aside]:
		_unparent(part)
	if _shell != null:
		_shell.queue_free()
	_mode = mode
	_cockpit = null
	_card = null
	_dock_footer = null
	# The lists are built for the mode they are in.
	_panes.clear()
	_pane_hashes.clear()
	_rows.clear()
	for c in _pane_row.get_children():
		_pane_row.remove_child(c)
		c.queue_free()
	if mode == "framed":
		_assemble_framed()
	else:
		_assemble_docked()


func _assemble_framed() -> void:
	_cockpit = Cockpit.new()
	_shell = _cockpit
	add_child(_cockpit)
	_cockpit.close_pressed.connect(_quit)
	_cockpit.tab_pressed.connect(func(action: String):
		# Leave this screen, then open the other one as its key would.
		_quit()
		Bridge.run(action))
	_cockpit.laid_out.connect(_layout)
	_cols = BoxContainer.new()
	_cols.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cols.add_theme_constant_override("separation", Cockpit.GUT)
	_cols.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cockpit.body.add_child(_cols)
	_main = VBoxContainer.new()
	_main.add_theme_constant_override("separation", Cockpit.GUT)
	_main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_main.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cols.add_child(_main)
	_filter = PanelContainer.new()
	var filter_box := Slate.module_box(0)
	filter_box.content_margin_top = 10
	filter_box.content_margin_bottom = 2
	_filter.add_theme_stylebox_override("panel", filter_box)
	_filter.mouse_filter = Control.MOUSE_FILTER_STOP
	var filter_col := VBoxContainer.new()
	filter_col.add_theme_constant_override("separation", 0)
	_filter.add_child(filter_col)
	for part in [_info_row, _tab_bar, _subtab_bar, _toolbar]:
		filter_col.add_child(part)
	_main.add_child(_filter)
	_pane_row.add_theme_constant_override("separation", Cockpit.GUT)
	_main.add_child(_pane_row)
	_cols.add_child(_aside)


func _assemble_docked() -> void:
	_center = CenterContainer.new()
	_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _dock_kind == "side":
		# A map of its own (the overmap, a vehicle) gets the frame with a wide viewport, and
		# this screen is the column beside it.
		_cockpit = Cockpit.new()
		_cockpit.wide = true
		_shell = _cockpit
		add_child(_cockpit)
		_cockpit.close_pressed.connect(_quit)
		_cockpit.tab_pressed.connect(func(action: String):
			_quit()
			Bridge.run(action))
		_cockpit.laid_out.connect(_layout)
		_cockpit.body.add_child(_center)
	else:
		_shell = Control.new()
		_shell.set_anchors_preset(Control.PRESET_FULL_RECT)
		_shell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_shell)
		_shell.add_child(_center)
	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", Slate.module_box(0))
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_center.add_child(_card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	_card.add_child(col)
	col.add_child(_build_dock_header())
	for part in [_info_row, _tab_bar, _subtab_bar, _toolbar]:
		col.add_child(part)
	_body = BoxContainer.new()
	_body.vertical = true
	_body.add_theme_constant_override("separation", 0)
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_body)
	_pane_row.add_theme_constant_override("separation", 0)
	_body.add_child(_pane_row)
	_body.add_child(_aside)
	_dock_footer = _build_dock_footer()
	col.add_child(_dock_footer)
	# In the frame the hints go on its strip along the bottom, like every other screen's.
	_dock_footer.visible = _cockpit == null


## A docked panel's own title strip, like a module's, with a way to close it.
func _build_dock_header() -> Control:
	var strip := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Slate.RAISED
	sb.border_color = Slate.BORDER
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = 7
	sb.corner_detail = 1
	sb.content_margin_left = 12
	sb.content_margin_right = 6
	strip.add_theme_stylebox_override("panel", sb)
	strip.custom_minimum_size.y = Hud.HEAD_HEIGHT + 4
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	strip.add_child(row)
	var marker := ColorRect.new()
	marker.color = Slate.ACCENT
	marker.custom_minimum_size = Vector2(7, 7)
	marker.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(marker)
	_title = Slate.label("", 13, Slate.ACCENT, Slate.spaced(Slate.heavy(), 2))
	_title.uppercase = true
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(_title)
	_close = Button.new()
	_close.icon = Slate.icon("x", 16)
	_close.tooltip_text = "Close"
	_close.focus_mode = Control.FOCUS_NONE
	_close.custom_minimum_size = Vector2(28, 28)
	_close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_close.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_close.add_theme_color_override("icon_normal_color", Slate.MUTED)
	_close.add_theme_color_override("icon_hover_color", Slate.TEXT)
	_close.pressed.connect(_quit)
	row.add_child(_close)
	return strip


func _build_dock_footer() -> Control:
	var bar := PanelContainer.new()
	var sb := Slate.box(Color(0, 0, 0, 0.18), 0, Slate.BORDER, 0)
	sb.border_width_top = 1
	sb.border_color = Slate.BORDER
	sb.content_margin_left = 14
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	bar.add_theme_stylebox_override("panel", sb)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	bar.add_child(col)
	_footer = Slate.rich(12)
	_footer.add_theme_color_override("default_color", Slate.MUTED)
	col.add_child(_footer)
	_hints = HFlowContainer.new()
	_hints.add_theme_constant_override("h_separation", 14)
	_hints.add_theme_constant_override("v_separation", 6)
	col.add_child(_hints)
	return bar


## The screen's own status line and figures (how many recipes are hidden, whether you can craft).
func _build_info() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	_subtitle = Slate.rich(12)
	_subtitle.add_theme_color_override("default_color", Slate.MUTED)
	_subtitle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_subtitle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_subtitle)
	_stats = HBoxContainer.new()
	_stats.add_theme_constant_override("separation", 8)
	_stats.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_stats)
	return _margin(row, 14, 0, 14, 8)


func _build_tabs() -> Control:
	var row := HBoxContainer.new()
	# Tabs that do not fit on one line wrap onto the next, so none is ever out of sight.
	_tabs = HFlowContainer.new()
	_tabs.add_theme_constant_override("h_separation", 6)
	_tabs.add_theme_constant_override("v_separation", 6)
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_tabs)
	return _margin(row, 14, 0, 14, 8)


func _build_subtabs() -> Control:
	_subtabs = HFlowContainer.new()
	_subtabs.add_theme_constant_override("h_separation", 4)
	_subtabs.add_theme_constant_override("v_separation", 2)
	return _margin(_subtabs, 14, 0, 14, 8)


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
	search_row.add_theme_constant_override("separation", 8)
	search_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_search.add_child(search_row)
	_search_icon = Slate.icon_rect("search", 15, Slate.CYAN)
	search_row.add_child(_search_icon)
	_search_label = Slate.label("", 13, Slate.MUTED, Slate.semibold())
	search_row.add_child(_search_label)
	_search_text = Slate.label("", 13, Slate.FAINT, Slate.mono())
	_search_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	search_row.add_child(_search_text)
	_search_key = Slate.key_chip("", 10)
	search_row.add_child(_search_key)
	row.add_child(_search)
	_toggles = HFlowContainer.new()
	_toggles.add_theme_constant_override("h_separation", 6)
	_toggles.add_theme_constant_override("v_separation", 6)
	_toggles.alignment = FlowContainer.ALIGNMENT_END
	_toggles.size_flags_horizontal = Control.SIZE_SHRINK_END
	row.add_child(_toggles)
	return _margin(row, 14, 0, 14, 8)


func _search_box(active: bool) -> StyleBoxFlat:
	var sb := Slate.box(Color(0, 0, 0, 0.25), 0, Slate.ACCENT if active else Color(Slate.CYAN, 0.4), 1)
	sb.content_margin_left = 10
	sb.content_margin_right = 6
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb


func _build_aside() -> Control:
	_aside = PanelContainer.new()
	_aside.mouse_filter = Control.MOUSE_FILTER_STOP
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 0)
	_aside.add_child(outer)

	# In the frame the side panel is a module with its own title strip.
	var strip := PanelContainer.new()
	_aside_strip = strip
	var strip_box := StyleBoxFlat.new()
	strip_box.bg_color = Slate.RAISED
	strip_box.border_color = Slate.BORDER
	strip_box.border_width_bottom = 1
	strip_box.corner_radius_top_left = 7
	strip_box.corner_detail = 1
	strip_box.content_margin_left = 12
	strip_box.content_margin_right = 8
	strip.add_theme_stylebox_override("panel", strip_box)
	strip.custom_minimum_size.y = Hud.HEAD_HEIGHT
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var strip_row := HBoxContainer.new()
	strip_row.add_theme_constant_override("separation", 8)
	strip_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.add_child(strip_row)
	var marker := ColorRect.new()
	marker.color = Slate.ACCENT
	marker.custom_minimum_size = Vector2(7, 7)
	marker.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip_row.add_child(marker)
	_aside_strip_title = Slate.label("SELECTED", 12, Slate.ACCENT, Slate.spaced(Slate.heavy(), 2))
	strip_row.add_child(_aside_strip_title)
	outer.add_child(strip)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	_aside_pad = _margin(col, 16, 14, 16, 14)
	_aside_pad.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(_aside_pad)
	col.add_child(_build_preview())

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	col.add_child(head)
	# What the panel is about: an item on a steel plate, or an icon for things that aren't items.
	_aside_slot = ItemSlot.new(72)
	_aside_slot.selected = true
	_aside_slot.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	head.add_child(_aside_slot)
	_aside_icon = Slate.icon_rect("list", 26, Slate.CYAN)
	_aside_icon.custom_minimum_size = Vector2(44, 44)
	_aside_icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	head.add_child(_aside_icon)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 4)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(names)
	_aside_title = Slate.rich(19)
	_aside_title.add_theme_font_override("normal_font", Slate.heading())
	names.add_child(_aside_title)
	_aside_subtitle = Slate.label("", 11, Slate.MUTED, Slate.mono())
	_aside_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	names.add_child(_aside_subtitle)

	_aside_warn = PanelContainer.new()
	var warn_box := Slate.box(Color(Slate.DANGER, 0.1), 0, Color(Slate.DANGER, 0.5), 1)
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
	# Room at the right for the scroll bar, so it never lies over the text.
	var stack_pad := _margin(stack, 0, 0, 14, 0)
	stack_pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_aside_scroll.add_child(stack_pad)
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
	_buttons.add_theme_constant_override("separation", 6)
	col.add_child(_buttons)
	return _aside


func _layout() -> void:
	if _mode == "":
		return
	var aside: Dictionary = _msg.get("aside", {})
	var wanted := float(aside.get("width", 400))
	var alone := Array(_msg.get("panes", [])).is_empty()
	_pane_row.visible = not alone
	if _mode == "framed":
		_layout_framed(aside, wanted, alone)
	else:
		_layout_docked(alone)


func _layout_framed(aside: Dictionary, wanted: float, alone: bool) -> void:
	var room := _cockpit.body.size
	# A screen that asks for less width than there is (a short list, a small game) keeps to it,
	# in the middle, instead of stretching thin across the frame.
	var most: Array = _msg.get("size", [0, 0])
	var width := room.x
	if float(most[0]) > 0 and String(_msg.get("nav", "")) == "":
		width = minf(room.x, maxf(float(most[0]) * 1.1, 1040.0))
		# Nearly all of it is all of it: a thin strip of bare frame at each side helps nobody.
		if width > room.x * 0.85:
			width = room.x
	_cols.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_cols.position = Vector2(roundf((room.x - width) / 2), 0)
	_cols.size = Vector2(width, room.y)
	# With lists the side panel stands beside them; alone it takes the room under the tabs.
	_cols.vertical = alone
	_main.visible = _filter.visible or not alone
	_main.size_flags_vertical = Control.SIZE_FILL
	_toolbar_row.vertical = false
	_toggles.alignment = FlowContainer.ALIGNMENT_END
	# Beside the search box the toggles take what it leaves and wrap onto more lines if needed.
	_toggles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_toggles.size_flags_stretch_ratio = 2.0
	_search.custom_minimum_size.x = 280
	_aside.add_theme_stylebox_override("panel", Slate.module_box(0))
	_aside_strip.visible = not alone
	_aside.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if alone:
		_aside.custom_minimum_size.x = 0
		_aside.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		_aside.size_flags_horizontal = Control.SIZE_FILL
		# The side panel takes up to 40% of the room unless the screen says otherwise (help text).
		_aside.custom_minimum_size.x = clampf(minf(wanted, width * float(aside.get("share", 0.3))), 260, wanted)


## A docked screen sits over the HUD's right column and leaves the map visible and clickable
## (look around). A "side" dock takes the window's full height, for screens shown while the HUD
## is hidden (the overmap).
func _dock_rect() -> Rect2:
	var viewport := get_viewport_rect().size
	var most: Array = _msg.get("size", [1440, 920])
	var dock := String(_msg.get("dock", ""))
	if _cockpit != null:
		return Rect2(Vector2.ZERO, _cockpit.body.size)
	if dock == "right":
		# Exactly the main screen's right column: its modules give way, the map stays clear.
		var hud := get_tree().get_first_node_in_group("hud") as Hud
		if hud != null:
			return hud.right_rect()
	var width := minf(float(most[0]), viewport.x * 0.45)
	var gap := float(Hud.GUT)
	var top := float(Hud.HEADER_HEIGHT) - gap if dock == "right" else 0.0
	var bottom := float(Hud.BAR_HEIGHT) - gap if dock == "right" else 0.0
	return Rect2(viewport.x - width - gap, top + gap, width, viewport.y - top - bottom - 2 * gap)


func _layout_docked(alone: bool) -> void:
	var place := _dock_rect()
	var target := place.size
	# The card shrinks first: a container is never smaller than its child's minimum size.
	_card.custom_minimum_size = target
	_center.position = place.position
	_center.size = target
	# A docked screen is narrow: lists above the side panel, toggles below the search box.
	_toolbar_row.vertical = true
	_toggles.alignment = FlowContainer.ALIGNMENT_BEGIN
	_toggles.size_flags_horizontal = Control.SIZE_FILL
	_toggles.size_flags_stretch_ratio = 1.0
	_search.custom_minimum_size.x = 0
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = Slate.BORDER
	sb.border_width_top = 0 if alone else 1
	_aside.add_theme_stylebox_override("panel", sb)
	_aside_strip.visible = false
	_aside.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_aside.size_flags_stretch_ratio = 1.8
	_aside.custom_minimum_size.x = 0
	_aside.size_flags_horizontal = Control.SIZE_EXPAND_FILL


# --- Updates from the game -----------------------------------------------------------------------

func apply(msg: Dictionary) -> void:
	_msg = msg
	var dock := String(msg.get("dock", ""))
	var mode := "docked" if dock == "right" or dock == "side" else "framed"
	if mode != _mode or (mode == "docked" and dock != _dock_kind):
		_dock_kind = dock if mode == "docked" else ""
		_assemble(mode)
	var title := String(msg.get("title", ""))
	var quit := String(msg.get("quit", "QUIT"))
	# The frame gives the column its width first: how the buttons are laid out depends on it.
	if _mode == "docked" and _cockpit != null:
		_apply_wide_frame(msg, title, quit)
		_apply_foot(msg.get("foot", {}))
	_narrow = _mode == "docked" and _dock_rect().size.x < 440
	if _mode == "framed":
		# One of the big screens (`nav` names the action that opens it) lights its tab up top.
		var nav := String(msg.get("nav", ""))
		if nav != "":
			_cockpit.set_tabs(nav)
			_cockpit.set_back("Back to map", "Esc")
		else:
			_cockpit.set_title(title)
			_cockpit.set_back("Back", "Esc")
		# Screens that can't be left with a key (a conversation) have no way back.
		_cockpit.set_back_visible(quit != "")
	else:
		_title.text = title
		# In the frame the way back is on its top bar.
		_close.visible = quit != "" and _cockpit == null
	var subtitle: Array = msg.get("subtitle", [])
	_subtitle.text = Slate.bbcode(subtitle, Slate.MUTED).strip_edges()
	_apply_stats(msg.get("stats", []))
	_info_row.visible = _subtitle.text != "" or _stats.get_child_count() > 0
	_apply_tabs(msg)
	_apply_subtabs(msg.get("subtabs", []))
	_apply_toolbar(msg)
	if _filter != null:
		_filter.visible = _info_row.visible or _tab_bar.visible or _subtab_bar.visible or _toolbar.visible
	_layout()
	_apply_panes(msg.get("panes", []))
	_apply_aside(msg)
	var footer := Slate.bbcode(msg.get("footer", []), Slate.MUTED).strip_edges()
	if _cockpit != null:
		_cockpit.set_footer(footer)
	else:
		_footer.text = footer
		_footer.visible = footer != ""
	_apply_hints(msg.get("hints", []))
	_apply_cursor()


## The frame around a screen that is a map of its own: its tab or title up top, and the part of
## the game's picture it draws (`view`, in game pixels) in the viewport.
func _apply_wide_frame(msg: Dictionary, title: String, quit: String) -> void:
	var nav := String(msg.get("nav", ""))
	if nav != "":
		_cockpit.set_tabs(nav)
		_cockpit.set_back("Back to map", "Esc")
	else:
		_cockpit.set_title(String(msg.get("frame_title", title)))
		_cockpit.set_back("Back", "Esc")
	_cockpit.set_back_visible(quit != "")
	_close.visible = false
	var most: Array = msg.get("size", [400, 0])
	var view: Array = msg.get("view", [])
	var source := Rect2(Vector2.ZERO, get_viewport_rect().size)
	if view.size() == 4:
		source = Rect2(float(view[0]), float(view[1]), float(view[2]), float(view[3]))
		source = Rect2(source.position * Display.frame_scale(), source.size * Display.frame_scale())
	_cockpit.set_viewport_source(source, float(most[0]))


## The module under a wide frame's viewport: the screen's numbers (`stats`: label and value) in
## columns, read down each one, and its `gauges` (name, bar, readout) at the right. The vehicle
## screen puts the vehicle's stats and fuel there.
func _apply_foot(foot: Dictionary) -> void:
	var stats: Array = foot.get("stats", [])
	var gauges: Array = foot.get("gauges", [])
	if stats.is_empty() and gauges.is_empty():
		_cockpit.set_wide_foot(0)
		return
	var stamp := hash([foot, _cockpit.strip.size.x])
	if stamp == _foot_stamp:
		return
	_foot_stamp = stamp
	const LINE := 22.0
	var gauge_width := 0.0 if gauges.is_empty() else 380.0
	var room := maxf(_cockpit.strip.size.x - 24 - gauge_width, 200)
	var columns := clampi(int(room / 300.0), 1, 3)
	var lines := maxi(ceili(stats.size() / float(columns)), mini(gauges.size(), 6))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	for c in columns:
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 0)
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for i in range(c * lines, mini((c + 1) * lines, stats.size())):
			var stat: Dictionary = stats[i]
			var label := Slate.label(String(stat.get("label", "")).to_upper(), 11, Slate.MUTED, Slate.mono())
			label.custom_minimum_size.y = LINE
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			grid.add_child(label)
			var value := Slate.rich(13)
			value.autowrap_mode = TextServer.AUTOWRAP_OFF
			value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			value.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			value.clip_contents = true
			value.text = Slate.bbcode(stat.get("value", []), Slate.TEXT)
			grid.add_child(value)
		row.add_child(grid)
	if not gauges.is_empty():
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.custom_minimum_size.x = gauge_width
		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 0)
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(grid)
		for g in gauges:
			var color := Slate.curses(String(g.get("color", "c_white")), Slate.WARN)
			var name := Slate.label(Slate.cap(String(g.get("name", ""))), 13, Slate.TEXT)
			name.custom_minimum_size.y = LINE
			name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			grid.add_child(name)
			var bar := Hud.SegmentBar.new(10)
			bar.custom_minimum_size = Vector2(90, 7)
			bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			bar.set_level(float(g.get("level", 0.0)), color)
			grid.add_child(bar)
			var readout := Slate.label(_gauge_readout(g.get("detail", [])), 11, Slate.SOFT, Slate.mono())
			readout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			readout.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			readout.mouse_filter = Control.MOUSE_FILTER_PASS
			readout.tooltip_text = readout.text
			grid.add_child(readout)
		row.add_child(scroll)
	_cockpit.set_foot(String(foot.get("title", "")), row)
	_cockpit.set_wide_foot(Hud.HEAD_HEIGHT + 20 + lines * LINE)


## The game's own words beside a gauge ("45%, 250 mL/hour, 2 hours until empty"), from the row of
## cells it printed them in.
func _gauge_readout(rows: Array) -> String:
	var text := ""
	if not rows.is_empty():
		for run in rows[0]:
			text += String(run[0])
	return text.strip_edges()


func _apply_stats(stats: Array) -> void:
	for c in _stats.get_children():
		_stats.remove_child(c)
		c.queue_free()
	for s in stats:
		var chip := PanelContainer.new()
		var sb := Slate.box(Slate.RAISED, 0, Slate.BORDER, 0)
		sb.content_margin_left = 8
		sb.content_margin_right = 8
		sb.content_margin_top = 3
		sb.content_margin_bottom = 3
		chip.add_theme_stylebox_override("panel", sb)
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
			row.add_child(Slate.label(label.to_upper(), 10, Slate.MUTED, Slate.mono()))
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
		_tabs.remove_child(c)
		c.queue_free()
	# The keys that step through the tabs stand at the two ends of the row, and wrap with it.
	var keys: Dictionary = msg.get("tab_keys", {})
	if String(keys.get("prev", "")) != "":
		_tabs.add_child(_tab_key(String(keys["prev"])))
	for t in tabs:
		_tabs.add_child(_tab(t, false))
	if String(keys.get("next", "")) != "":
		_tabs.add_child(_tab_key(String(keys["next"])))


func _tab_key(key: String) -> Control:
	var chip := Slate.key_chip(Slate.key_name(key), 10)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return chip


func _apply_subtabs(subtabs: Array) -> void:
	_subtab_bar.visible = not subtabs.is_empty()
	for c in _subtabs.get_children():
		_subtabs.remove_child(c)
		c.queue_free()
	for t in subtabs:
		_subtabs.add_child(_tab(t, true))


func _set_chip(chip: PanelContainer, key: String) -> void:
	(chip.get_child(0) as Label).text = Slate.key_name(key)
	chip.visible = key != ""


## One tab. The current one is lit cyan (a small one, underlined); the others are outlined.
## Clicking sends the tab's pick (or presses its action).
func _tab(t: Dictionary, small: bool) -> Control:
	var active := bool(t.get("active", false))
	var enabled := bool(t.get("enabled", true))
	var tab := PanelContainer.new()
	var sb: StyleBoxFlat
	if small:
		sb = StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0)
		sb.border_color = Slate.CYAN
		sb.border_width_bottom = 2 if active else 0
		sb.content_margin_bottom = 3 if active else 5
		sb.content_margin_top = 3
	else:
		sb = Slate.box(Slate.CYAN if active else Color(0, 0, 0, 0), 0, Color(Slate.CYAN, 0.9 if active else 0.35), 1)
		sb.content_margin_top = 5
		sb.content_margin_bottom = 5
	sb.content_margin_left = 9 if small else 11
	sb.content_margin_right = 9 if small else 11
	tab.add_theme_stylebox_override("panel", sb)
	tab.mouse_filter = Control.MOUSE_FILTER_STOP
	tab.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tab.tooltip_text = String(t.get("tip", ""))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tab.add_child(row)
	var color := Slate.SOFT if enabled else Slate.FAINT
	if active:
		color = Slate.CYAN if small else Slate.ACCENT_TEXT
	if String(t.get("icon", "")) != "":
		row.add_child(Slate.icon_rect(String(t["icon"]), 14, color))
	var label := Slate.label(String(t.get("text", "")).to_upper(), 11 if small else 12, color,
			Slate.spaced(Slate.mono() if small else Slate.heading(), 1))
	row.add_child(label)
	if String(t.get("count", "")) != "":
		row.add_child(Slate.label(String(t["count"]), 11, Color(color, 0.75), Slate.mono()))
	if not active:
		var normal := sb
		var hot := sb.duplicate() as StyleBoxFlat
		hot.bg_color = Color(Slate.CYAN, 0.14)
		tab.mouse_entered.connect(func(): tab.add_theme_stylebox_override("panel", hot))
		tab.mouse_exited.connect(func(): tab.add_theme_stylebox_override("panel", normal))
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
		_search.add_theme_stylebox_override("panel", _search_box(typing or text != ""))
		_search.tooltip_text = String(search.get("tip", ""))
		# The box doubles as a plain text field (a world's name) with its own icon and label.
		_search_icon.texture = Slate.icon(String(search.get("icon", "search")), 15)
		_search_label.text = String(search.get("label", ""))
		_search_label.visible = _search_label.text != ""
		_search.mouse_default_cursor_shape = Control.CURSOR_IBEAM if search.has("act") else Control.CURSOR_ARROW
		if typing or text != "":
			_search_text.text = text + ("▏" if typing else "")
			_search_text.add_theme_color_override("font_color", Slate.TEXT)
		else:
			_search_text.text = String(search.get("placeholder", "Search")).to_lower()
			_search_text.add_theme_color_override("font_color", Slate.FAINT)
		_set_chip(_search_key, "" if typing else String(search.get("key", "")))
	for c in _toggles.get_children():
		_toggles.remove_child(c)
		c.queue_free()
	for t in toggles:
		var b := SlateButton.new(String(t.get("icon", "")), String(t.get("text", "")), false, true)
		b.set_key(String(t.get("key", "")))
		b.set_on(bool(t.get("on", false)))
		b.set_enabled(bool(t.get("enabled", true)))
		b.tooltip_text = String(t.get("tip", ""))
		_connect_action(b, t)
		_toggles.add_child(b)


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
		_pane_row.remove_child(c)
		c.queue_free()
	_panes.clear()
	_pane_hashes.clear()
	_rows.clear()
	var framed := _mode == "framed"
	for p in panes.size():
		var spec: Dictionary = panes[p]
		if p > 0 and not framed:
			_pane_row.add_child(_rule(true))
		var pane := Pane.new()
		pane.setup(spec, framed)
		# In the frame each list is a module of its own.
		var holder: Control = pane
		if framed:
			holder = PanelContainer.new()
			holder.add_theme_stylebox_override("panel", Slate.module_box(0))
			holder.mouse_filter = Control.MOUSE_FILTER_STOP
			holder.add_child(pane)
		holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		holder.size_flags_stretch_ratio = float(spec.get("stretch", 1.0))
		_pane_row.add_child(holder)
		if pane.board != null:
			_connect_board(pane.board, p, spec)
		_panes.append(pane)
		_pane_hashes.append(_pane_hash(spec))
		var rows: Array = spec.get("rows", [])
		var widths := _cell_widths(rows)
		var keyed := rows.any(func(r): return String(r.get("key", "")) != "")
		var glyphs := rows.any(func(r): return String(r.get("sym", "")) != "")
		var marks := rows.any(func(r): return r.has("mark"))
		var slots := rows.any(func(r): return r.has("slot"))
		var confirm := String(spec.get("confirm", "CONFIRM"))
		for i in rows.size():
			var r: Dictionary = rows[i]
			if bool(r.get("heading", false)):
				pane.add_heading(r, widths)
				continue
			var row := ListRow.new()
			row.setup(r, {"keyed": keyed, "glyphs": glyphs, "marks": marks, "widths": widths, "slots": slots})
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
				w = Slate.mono().get_string_size(Slate.plain(cells[i]).strip_edges().to_upper(),
						HORIZONTAL_ALIGNMENT_LEFT, -1, Slate.fs(9)).x
			else:
				w = ListRow.text_width(Slate.plain(cells[i]).strip_edges())
			if i >= widths.size():
				widths.append(0.0)
			# A column with nothing in it (no amounts in a list of single things) takes no room.
			if w > 0:
				widths[i] = clampf(ceilf(w) + 4, maxf(widths[i], MIN_CELL_WIDTH), MAX_CELL_WIDTH)
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
	var type := String(aside.get("type", ""))
	# "Selected" only when the module shows a picked thing (it has a name or a picture).
	var fallback := "Selected" if aside.has("title") or aside.has("type") else "Details"
	_aside_strip_title.text = String(aside.get("heading", fallback)).to_upper()
	_aside_slot.visible = has_title and (sym != "" or type != "")
	_aside_slot.set_item(type, sym, Slate.curses(String(aside.get("sym_color", "c_white"))))
	_aside_icon.visible = has_title and not _aside_slot.visible and icon != ""
	if icon != "":
		_aside_icon.texture = Slate.icon(icon, 26)
	_aside_title.get_parent().visible = has_title
	_aside_title.get_parent().get_parent().visible = has_title
	_aside_rule.visible = has_title
	_aside_title.text = Slate.bbcode(aside.get("title", []), Slate.TEXT)
	_aside_subtitle.text = String(aside.get("subtitle", "")).to_upper()
	_aside_subtitle.visible = _aside_subtitle.text != ""
	var warn: Array = aside.get("warn", [])
	_aside_warn.visible = not warn.is_empty()
	_aside_warn_text.text = Slate.bbcode(warn, Slate.DANGER).strip_edges()
	var body_spans = aside.get("body", [])
	if bool(aside.get("mono", false)) and _mode == "docked":
		# A line with two things set far apart (a creature's name and its mood) is drawn closer
		# together when it is too long for the panel, before anything gets smaller.
		# (Three characters are kept back for a health bar, whose blocks are wider than letters.)
		var per_char := Slate.mono().get_string_size("0000000000", HORIZONTAL_ALIGNMENT_LEFT, -1, Slate.fs(12)).x / 10.0
		body_spans = Slate.narrow_gaps(body_spans, int((_dock_rect().size.x - 46) / per_char) - 3)
	var body := Slate.tidy_body(Slate.bbcode(body_spans, Slate.SOFT))
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
		var points := 12.0
		if _mode == "docked":
			# Columns the game lined up stay lined up in a narrow panel: the text gets a little
			# smaller instead of wrapping (down to a size that still reads well).
			# Measured at the sizes the font can really take (whole pixels), widest line first.
			var longest := ""
			for text_line in Slate.plain(body_spans).split("\n"):
				if text_line.rstrip(" ").length() > longest.length():
					longest = text_line.rstrip(" ")
			var room := _dock_rect().size.x - 46
			points = 10.0
			for step in [12.0, 11.0, 10.5]:
				if Slate.mono().get_string_size(longest, HORIZONTAL_ALIGNMENT_LEFT, -1, Slate.fs(step)).x <= room:
					points = step
					break
		_aside_body.add_theme_font_size_override("normal_font_size", Slate.fs(points))
	else:
		_aside_body.remove_theme_font_override("normal_font")
		_aside_body.add_theme_font_size_override("normal_font_size", Slate.fs(13))
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
	var box := Slate.box(Color.BLACK, 12, Slate.BORDER_STRONG, 1)
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
	_preview_buttons.add_theme_constant_override("separation", 6)
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
		_preview_buttons.remove_child(c)
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


## Titled blocks below the body (a vehicle's parts, its overview, its stats): text, optionally in
## a fixed-width font to keep columns the game lined up, or `parts` as one row each.
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
			var head_row := HBoxContainer.new()
			head_row.add_theme_constant_override("separation", 10)
			box.add_child(head_row)
			var head := Slate.label("", 12, Slate.CYAN, Slate.spaced(Slate.heading(), 2))
			head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			head_row.add_child(head)
			head_row.add_child(Slate.label("", 10, Slate.MUTED, Slate.spaced(Slate.mono(), 1)))
			var text := Slate.rich(13)
			text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			text.add_theme_color_override("default_color", Slate.SOFT)
			text.add_theme_constant_override("line_separation", 3)
			box.add_child(text)
			var rows := VBoxContainer.new()
			rows.add_theme_constant_override("separation", 0)
			box.add_child(rows)
			_aside_sections.add_child(box)
		var head_row := box.get_child(0) as HBoxContainer
		var head := head_row.get_child(0) as Label
		head.text = String(spec.get("title", "")).to_upper()
		var tag := head_row.get_child(1) as Label
		tag.text = String(spec.get("tag", "")).to_upper()
		head_row.visible = head.text != ""
		var label := box.get_child(1) as RichTextLabel
		if bool(spec.get("mono", false)):
			label.add_theme_font_override("normal_font", Slate.mono())
			label.add_theme_font_size_override("normal_font_size", Slate.fs(12))
		else:
			label.remove_theme_font_override("normal_font")
			label.add_theme_font_size_override("normal_font_size", Slate.fs(13))
		var text := Slate.tidy_body(Slate.bbcode(spec.get("body", []), Slate.SOFT))
		if spec.has("label"):
			text = "[color=#%s]%s[/color]" % [Slate.DANGER.to_html(false), Slate.escape(String(spec["label"]))]
		if label.text != text:
			label.text = text
		label.visible = text != ""
		var parts: Array = spec.get("parts", [])
		var groups: Array = spec.get("groups", [])
		var aim: Dictionary = spec.get("aim", {})
		var rows := box.get_child(2) as VBoxContainer
		rows.visible = not parts.is_empty() or not groups.is_empty() or not aim.is_empty()
		var stamp := hash([parts, groups, aim])
		if rows.get_meta("stamp", 0) != stamp:
			rows.set_meta("stamp", stamp)
			for c in rows.get_children():
				rows.remove_child(c)
				c.queue_free()
			for part in parts:
				rows.add_child(PartRow.new(part))
			for group in groups:
				rows.add_child(GroupHead.new(group.get("head", [])))
				for line in group.get("rows", []):
					var row := GroupRow.new(line)
					row.chosen.connect(func(key: String): Bridge.send({"t": "text", "s": key}))
					rows.add_child(row)
			if not aim.is_empty():
				var panel := AimPanel.new(aim)
				panel.chosen.connect(func(action: String): Bridge.press(view_id, action))
				rows.add_child(panel)
		# The keys that page through the parts bring the next one to the top.
		var to := int(spec.get("scroll_to", 0))
		if not parts.is_empty() and rows.get_meta("at", 0) != to:
			rows.set_meta("at", to)
			_show_part.call_deferred(rows, to)
		box.visible = text != "" or not parts.is_empty() or not groups.is_empty() or not aim.is_empty()


func _show_part(rows: VBoxContainer, index: int) -> void:
	if not is_instance_valid(rows) or index >= rows.get_child_count():
		return
	await get_tree().process_frame
	if not is_instance_valid(rows) or index >= rows.get_child_count():
		return
	var row := rows.get_child(index) as Control
	_aside_scroll.scroll_vertical = int(row.global_position.y - _aside_scroll.get_child(0).global_position.y) if index > 0 else 0


func _apply_buttons(buttons: Array) -> void:
	for c in _buttons.get_children():
		_buttons.remove_child(c)
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
			if _narrow:
				b.set_fitting()
			continue
		if grid == null:
			grid = GridContainer.new()
			grid.columns = 1 if _narrow else (3 if _mode == "docked" and _dock_rect().size.x >= 640 else 2)
			# Many buttons in a narrow panel (aiming) go two abreast when their labels fit,
			# so the panel keeps room for what it has to say.
			if _narrow and buttons.size() >= 8:
				grid.columns = 2
			grid.add_theme_constant_override("h_separation", 6)
			grid.add_theme_constant_override("v_separation", 6)
			_buttons.add_child(grid)
		grid.add_child(b)
		b.set_compressible()
	_buttons.visible = not buttons.is_empty()
	if grid != null:
		# What fitted last time for these buttons at this width is used straight away.
		var key := hash([buttons.map(func(spec): return String(spec.get("text", ""))), grid.columns,
				int(_buttons.size.x / 40)])
		grid.columns = int(_grid_fit.get(key, grid.columns))
		_fit_grid(grid, key)


## A grid of buttons takes fewer columns when a label would be cut short in it. Checked once
## the layout has settled, and remembered under `key`.
func _fit_grid(grid: GridContainer, key: int) -> void:
	while is_inside_tree() and is_instance_valid(grid) and grid.columns > 1:
		await get_tree().process_frame
		await get_tree().process_frame
		if not is_instance_valid(grid):
			return
		var cut := false
		for b in grid.get_children():
			cut = cut or (b is SlateButton and b.is_cut())
		if not cut:
			return
		grid.columns -= 1
		_grid_fit[key] = grid.columns


func _apply_hints(hints: Array) -> void:
	if _cockpit != null:
		var pairs := []
		for h in hints:
			pairs.append([Slate.key_name(String(h.get("key", ""))), String(h.get("text", "")).to_lower()])
		_cockpit.set_hints(pairs)
		return
	for c in _hints.get_children():
		_hints.remove_child(c)
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
	var _marker: ColorRect
	var _note_box: Control
	var _framed := false
	var _scroll: ScrollContainer
	var _list: VBoxContainer
	var _text: RichTextLabel
	var _entries: Array[Control] = []
	var _items := 0
	var _empty := ""

	func setup(spec: Dictionary, framed := false) -> void:
		add_theme_constant_override("separation", 0)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_empty = String(spec.get("empty", "Nothing here."))
		_framed = framed
		var titled := String(spec.get("title", "")) != ""
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 8)
		head.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# A module's title strip in the frame: a marker, the name, the count at the right.
		_marker = ColorRect.new()
		_marker.color = Slate.CYAN
		_marker.custom_minimum_size = Vector2(7, 7)
		_marker.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		head.add_child(_marker)
		_title = Slate.label(String(spec.get("title", "")), 12, Slate.CYAN, Slate.spaced(Slate.heavy(), 2))
		_title.uppercase = true
		head.add_child(_title)
		_count = Slate.label("", 10, Slate.MUTED, Slate.mono())
		_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		head.add_child(_count)
		var strip := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Slate.RAISED if framed else Color(0, 0, 0, 0)
		sb.border_color = Slate.BORDER
		sb.border_width_bottom = 1
		sb.corner_radius_top_left = 7 if framed else 0
		sb.corner_detail = 1
		sb.content_margin_left = 12
		sb.content_margin_right = 10
		strip.add_theme_stylebox_override("panel", sb)
		strip.custom_minimum_size.y = Hud.HEAD_HEIGHT
		strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		strip.add_child(head)
		strip.visible = titled
		add_child(strip)
		# A line or two under the title, such as where the list's items are (moving items).
		_note = Slate.rich(12)
		_note.add_theme_color_override("default_color", Slate.MUTED)
		_note.visible = false
		var note_box := MarginContainer.new()
		note_box.add_theme_constant_override("margin_left", 12)
		note_box.add_theme_constant_override("margin_right", 12)
		note_box.add_theme_constant_override("margin_top", 6)
		note_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		note_box.add_child(_note)
		_note_box = note_box
		_note_box.visible = false
		add_child(note_box)

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
		_note_box.visible = _note.visible
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
		var title := Slate.label(Slate.plain(r.get("text", [])).strip_edges().to_upper(), 12,
				Slate.lead_color(r.get("text", []), Slate.CYAN), Slate.spaced(Slate.heading(), 2))
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.clip_text = true
		row.add_child(title)
		var cells: Array = r.get("cells", [])
		for i in cells.size():
			var c := Slate.label(Slate.plain(cells[i]).strip_edges().to_upper(), 9, Slate.MUTED, Slate.mono())
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

	## The list the keys are on has a yellow title, like a selected module.
	func set_active(on: bool) -> void:
		var tone := Slate.ACCENT if on else Slate.CYAN
		_title.add_theme_color_override("font_color", tone)
		_marker.color = tone


## One row: optional mark box, key, glyph or icon, text, a note and extra columns.
class ListRow extends PanelContainer:
	signal clicked
	signal activated
	signal marked

	var _enabled := true
	var _selected := false
	var _active := false
	var _hover := false
	## "ready", "missing" or "locked": a bar at the row's left edge in that color.
	var _tone := ""

	static func text_width(text: String) -> float:
		return Slate.mono().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, Slate.fs(12)).x

	func setup(row: Dictionary, opts: Dictionary) -> void:
		_enabled = bool(row.get("enabled", true))
		var slotted := bool(opts.get("slots", false))
		custom_minimum_size.y = SLOT_ROW_HEIGHT if slotted else ROW_HEIGHT
		_tone = String(row.get("tone", ""))
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
		if slotted:
			# The thing the row is about on a steel plate (a recipe's result).
			var spec: Dictionary = row.get("slot", {})
			var slot := ItemSlot.new(46)
			slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			if not spec.is_empty():
				slot.set_item(String(spec.get("type", "")), String(spec.get("sym", "?")), Slate.curses(String(spec.get("color", "c_white"))))
			slot.dimmed = _tone == "locked"
			line.add_child(slot)
			# A row with no item of its own (a group of recipes) shows its icon in the slot's place.
			if spec.is_empty() and String(row.get("icon", "")) != "":
				var mark := Slate.icon_rect(String(row["icon"]), 20, Slate.CYAN)
				mark.set_anchors_preset(Control.PRESET_FULL_RECT)
				slot.add_child(mark)
		elif bool(opts.get("glyphs", false)) and String(row.get("type", "")) != "":
			# An item: its sprite on a small plate, like everywhere else items are shown.
			var plate := ItemSlot.new(30)
			plate.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
			plate.set_item(String(row["type"]), String(row.get("sym", "?")), Slate.curses(String(row.get("sym_color", "c_white"))))
			line.add_child(plate)
		elif bool(opts.get("glyphs", false)):
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
		if String(row.get("icon", "")) != "" and not slotted:
			var icon := Slate.icon_rect(String(row["icon"]), 16, Slate.curses(String(row.get("icon_color", "")), Slate.MUTED))
			icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			line.add_child(icon)

		var name: Control
		if slotted:
			# One color and room to spare for the slots beside it: a long name ends in "…".
			var plain_name := Slate.label(Slate.plain(text).strip_edges(), 15, Slate.lead_color(text, Slate.TEXT), Slate.semibold())
			plain_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			plain_name.clip_text = true
			plain_name.custom_minimum_size = Vector2(120, 22)
			name = plain_name
		else:
			var rich_name := Slate.rich(14, false)
			rich_name.autowrap_mode = TextServer.AUTOWRAP_OFF
			rich_name.clip_contents = true
			rich_name.custom_minimum_size = Vector2(60, 22)
			rich_name.add_theme_font_override("normal_font", Slate.semibold())
			rich_name.text = Slate.bbcode(text, Slate.TEXT)
			name = rich_name
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		name.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var meta := String(row.get("meta", ""))
		if meta != "":
			# A second line under the name: what kind of thing it is, how long it takes.
			var names := VBoxContainer.new()
			names.add_theme_constant_override("separation", 0)
			names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			names.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			names.mouse_filter = Control.MOUSE_FILTER_IGNORE
			names.add_child(name)
			var sub := Slate.label(meta.to_upper(), 10, Slate.MUTED, Slate.mono())
			sub.clip_text = true
			sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			names.add_child(sub)
			line.add_child(names)
		else:
			line.add_child(name)

		if slotted and not (row.get("note", []) as Array).is_empty():
			# A short tag after the name (a recipe not looked at yet).
			var tag_text: Array = row["note"]
			var tag := Slate.label(Slate.plain(tag_text).strip_edges().to_upper(), 10, Slate.lead_color(tag_text, Slate.ACCENT), Slate.mono())
			tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			line.add_child(tag)
		# What the row needs, as small slots: outlined green when you have it, red when you don't.
		var parts: Array = row.get("parts", [])
		if not parts.is_empty():
			var needs := HBoxContainer.new()
			needs.add_theme_constant_override("separation", 5)
			needs.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			needs.mouse_filter = Control.MOUSE_FILTER_IGNORE
			line.add_child(needs)
			for part in parts:
				var have := bool(part.get("have", false))
				var slot := ItemSlot.new(34)
				slot.mouse_filter = Control.MOUSE_FILTER_PASS
				slot.set_item(String(part.get("type", "")), String(part.get("sym", "?")), Slate.curses(String(part.get("color", "c_white"))))
				slot.tooltip_text = "%s\n%s" % [String(part.get("name", "")), "You have this." if have else "Missing."]
				slot.edge = Slate.GOOD if have else Slate.DANGER
				slot.dimmed = not have
				needs.add_child(slot)
			var more := int(row.get("parts_more", 0))
			if more > 0:
				needs.add_child(Slate.label("+%d" % more, 11, Slate.MUTED, Slate.mono()))
		var status := String(row.get("status", ""))
		if status != "":
			var tones := {"ready": Slate.GOOD, "missing": Slate.WARN, "locked": Slate.FAINT}
			var state := Slate.label(status.to_upper(), 11, tones.get(_tone, Slate.MUTED), Slate.mono())
			state.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			state.custom_minimum_size.x = 82
			line.add_child(state)

		var note: Array = row.get("note", [])
		if not note.is_empty() and not slotted:
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
			bg = Color(Slate.ACCENT, 0.10)
		elif _selected or _hover:
			bg = Color(Slate.CYAN, 0.08)
		var sb := Slate.box(bg, 0, Slate.BORDER, 0)
		var tones := {"ready": Slate.GOOD, "missing": Slate.WARN, "locked": Color(Slate.FAINT, 0.5)}
		if tones.has(_tone):
			# Rows with a state keep its color at the left edge; the cursor is a yellow outline.
			sb.border_color = tones[_tone]
			sb.border_width_left = 4
			if _selected and _active:
				sb.border_color = Slate.ACCENT
				sb.set_border_width_all(1)
				sb.border_width_left = 4
		elif _selected:
			# A yellow edge marks the row the keys act on; cyan, a list's resting cursor.
			sb.border_width_left = 3
			sb.border_color = Slate.ACCENT if _active else Color(Slate.CYAN, 0.6)
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


## One part of a vehicle on the square being looked at: its picture on a plate, its name, what
## kind of part it is, how damaged it is, what it holds and what it does.
class PartRow extends PanelContainer:
	func _init(part: Dictionary) -> void:
		var selected := bool(part.get("selected", false))
		var sb := StyleBoxFlat.new()
		sb.bg_color = Slate.RAISED if selected else Color(0, 0, 0, 0)
		sb.border_color = Slate.ACCENT if selected else Slate.BORDER
		sb.border_width_left = 2 if selected else 0
		sb.border_width_bottom = 0 if selected else 1
		sb.content_margin_left = 8
		sb.content_margin_right = 8
		sb.content_margin_top = 7
		sb.content_margin_bottom = 7
		add_theme_stylebox_override("panel", sb)
		mouse_filter = Control.MOUSE_FILTER_PASS
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 12)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(line)
		var slot := ItemSlot.new(40)
		slot.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.set_item(String(part.get("type", "")), String(part.get("sym", "?")), Slate.curses(String(part.get("sym_color", "c_white"))))
		slot.selected = selected
		line.add_child(slot)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 3)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(col)
		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 10)
		col.add_child(top)
		var name := Slate.label(Slate.cap(String(part.get("name", ""))), 14, Slate.TEXT, Slate.semibold())
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		top.add_child(name)
		var kind := String(part.get("kind", ""))
		if kind != "":
			top.add_child(Slate.label(kind.to_upper(), 10, Slate.FAINT, Slate.spaced(Slate.mono(), 1)))
		var health := float(part.get("health", 1.0))
		var level := int(part.get("level", 0))
		var color := Slate.CYAN if level < 0 else (Slate.GOOD if level <= 1 else (Slate.WARN if level == 2 else Slate.DANGER))
		var state := HBoxContainer.new()
		state.add_theme_constant_override("separation", 8)
		col.add_child(state)
		var bar := Hud.SegmentBar.new(5)
		bar.custom_minimum_size = Vector2(44, 6)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.set_level(health, color)
		state.add_child(bar)
		state.add_child(Slate.label(String(part.get("state", "")).to_upper(), 10, color, Slate.spaced(Slate.mono(), 1)))
		var note := String(part.get("note", ""))
		if note != "":
			var extra := Slate.label(note, 11, Slate.SOFT, Slate.mono())
			extra.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			extra.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			extra.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			state.add_child(extra)
		var desc := Slate.tidy_body(Slate.bbcode(part.get("desc", []), Slate.MUTED))
		if desc != "":
			var text := Slate.rich(12)
			text.add_theme_color_override("default_color", Slate.MUTED)
			text.add_theme_constant_override("line_separation", 2)
			text.mouse_filter = Control.MOUSE_FILTER_IGNORE
			text.text = desc
			col.add_child(text)


## Heading of a group of rows in a side panel section (the vehicle overview's "Engines", with
## its totals), and the names of the columns its rows end in.
class GroupHead extends MarginContainer:
	func _init(head: Array) -> void:
		add_theme_constant_override("margin_top", 10)
		add_theme_constant_override("margin_bottom", 2)
		add_theme_constant_override("margin_left", 8)
		add_theme_constant_override("margin_right", 8)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 12)
		add_child(line)
		var parts: Array = Slate.split_line(head, Slate.SOFT)
		# A heading printed alone is all "right part": it goes at the left all the same.
		var left := String(parts[0]) if String(parts[0]) != "" else String(parts[1])
		var name := Slate.rich(13)
		name.autowrap_mode = TextServer.AUTOWRAP_OFF
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name.clip_contents = true
		name.add_theme_font_override("normal_font", Slate.semibold())
		name.text = left
		line.add_child(name)
		if String(parts[0]) != "":
			var columns := Slate.rich(11)
			columns.autowrap_mode = TextServer.AUTOWRAP_OFF
			columns.add_theme_font_override("normal_font", Slate.mono())
			columns.text = Slate.split_line(head, Slate.MUTED)[1]
			line.add_child(columns)


## A row of such a group: the key that picks it (while something is being picked), its picture
## and name, and what the game prints for it at the right. A row with a key can be clicked.
class GroupRow extends PanelContainer:
	signal chosen(key: String)

	var _key := ""

	func _init(row: Dictionary) -> void:
		_key = String(row.get("key", ""))
		var selected := bool(row.get("selected", false))
		var dim := bool(row.get("dim", false))
		var sb := StyleBoxFlat.new()
		sb.bg_color = Slate.RAISED if selected else Color(0, 0, 0, 0)
		sb.border_color = Slate.ACCENT if selected else Slate.BORDER
		sb.border_width_left = 2 if selected else 0
		sb.border_width_bottom = 0 if selected else 1
		sb.content_margin_left = 8
		sb.content_margin_right = 8
		sb.content_margin_top = 4
		sb.content_margin_bottom = 4
		add_theme_stylebox_override("panel", sb)
		mouse_filter = Control.MOUSE_FILTER_STOP if _key != "" else Control.MOUSE_FILTER_PASS
		if _key != "":
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(line)
		var slot := ItemSlot.new(26)
		slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.set_item(String(row.get("type", "")), "", Slate.TEXT)
		slot.modulate.a = 0.5 if dim else 1.0
		line.add_child(slot)
		# The key stands in the same place on every row while something is being picked.
		if _key != "":
			var chip := Slate.key_chip(_key, 10)
			chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			chip.custom_minimum_size.x = 20
			line.add_child(chip)
		elif dim:
			var gap := Control.new()
			gap.custom_minimum_size.x = 20
			line.add_child(gap)
		var name := Slate.rich(13)
		name.autowrap_mode = TextServer.AUTOWRAP_OFF
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		name.clip_contents = true
		name.text = Slate.bbcode(row.get("name", []), Slate.FAINT if dim else Slate.TEXT)
		if dim:
			name.modulate.a = 0.6
		line.add_child(name)
		# Its condition, as on the rows of the parts on a square; the word is in the tooltip.
		if row.has("health"):
			var level := int(row.get("level", 0))
			var color := Slate.CYAN if level < 0 else (Slate.GOOD if level <= 1 else (Slate.WARN if level == 2 else Slate.DANGER))
			var bar := Hud.SegmentBar.new(5)
			bar.custom_minimum_size = Vector2(44, 6)
			bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			bar.set_level(float(row.get("health", 1.0)), color)
			bar.modulate.a = 0.5 if dim else 1.0
			line.add_child(bar)
			tooltip_text = String(row.get("state", ""))
		var detail := Slate.rich(12)
		detail.autowrap_mode = TextServer.AUTOWRAP_OFF
		detail.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		detail.add_theme_font_override("normal_font", Slate.mono())
		detail.text = Slate.split_line(row.get("detail", []), Slate.SOFT)[1]
		# Every row keeps the same width for it, so the bars before it line up.
		detail.custom_minimum_size.x = 150
		detail.text = "[right]%s[/right]" % detail.text
		line.add_child(detail)

	func _gui_input(event: InputEvent) -> void:
		if _key != "" and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			chosen.emit(_key)


## How good a shot or a throw would be: how steady the aim is, then each way to fire as a row
## that fires that way when clicked.
class AimPanel extends VBoxContainer:
	signal chosen(action: String)

	func _init(aim: Dictionary) -> void:
		add_theme_constant_override("separation", 6)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		if aim.has("steadiness"):
			var level := clampf(float(aim["steadiness"]), 0.0, 1.0)
			var line := HBoxContainer.new()
			line.add_theme_constant_override("separation", 10)
			add_child(line)
			line.add_child(Slate.label(String(aim.get("steadiness_label", "Steadiness")).to_upper(), 11, Slate.MUTED, Slate.spaced(Slate.mono(), 1)))
			var bar := Hud.SegmentBar.new(20)
			bar.custom_minimum_size = Vector2(80, 7)
			bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			bar.set_level(level, Slate.CYAN)
			line.add_child(bar)
			var value := Slate.label("%d%%" % roundi(level * 100), 11, Slate.TEXT, Slate.mono())
			value.custom_minimum_size.x = 40
			value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			line.add_child(value)
		var rows: Array = aim.get("rows", [])
		if not rows.is_empty():
			# What the colors of the bars stand for, once.
			var legend := HBoxContainer.new()
			legend.add_theme_constant_override("separation", 14)
			add_child(legend)
			for chance in rows[0].get("chances", []):
				var item := HBoxContainer.new()
				item.add_theme_constant_override("separation", 5)
				var dot := ColorRect.new()
				dot.custom_minimum_size = Vector2(8, 8)
				dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				dot.color = Slate.hit_color(String(chance.get("color", "")))
				dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
				item.add_child(dot)
				item.add_child(Slate.label(String(chance.get("label", "")).to_upper(), 10, Slate.MUTED, Slate.spaced(Slate.mono(), 1)))
				legend.add_child(item)
		var list := VBoxContainer.new()
		list.add_theme_constant_override("separation", 0)
		add_child(list)
		for row in rows:
			var line := AimRow.new(row, String(aim.get("moves_label", "moves")))
			line.chosen.connect(func(action: String): chosen.emit(action))
			list.add_child(line)
		var note := String(aim.get("note", ""))
		if note != "":
			add_child(Slate.label(note, 12, Slate.SOFT))


## One way to fire: its key and name, the moves it takes, and a bar of the chances to hit with
## their sum beside it (each chance is in the tooltip). A click fires that way.
class AimRow extends PanelContainer:
	signal chosen(action: String)

	var _action := ""
	var _box: StyleBoxFlat

	func _init(row: Dictionary, unit: String) -> void:
		_action = String(row.get("action", ""))
		_box = StyleBoxFlat.new()
		_box.bg_color = Color(0, 0, 0, 0)
		_box.border_color = Slate.BORDER
		_box.border_width_top = 1
		_box.content_margin_left = 6
		_box.content_margin_right = 0
		_box.content_margin_top = 4
		_box.content_margin_bottom = 5
		add_theme_stylebox_override("panel", _box)
		mouse_filter = Control.MOUSE_FILTER_STOP
		if _action != "":
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			mouse_entered.connect(func(): _lit(true))
			mouse_exited.connect(func(): _lit(false))
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 4)
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(cell)
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(line)
		line.add_child(Slate.key_chip(Slate.key_name(String(row.get("key", ""))), 10))
		var name := Slate.label(String(row.get("label", "")), 13, Slate.TEXT)
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name.clip_text = true
		line.add_child(name)
		line.add_child(Slate.label("%d %s" % [int(row.get("moves", 0)), unit], 11, Slate.INFO, Slate.mono()))
		var segments := []
		var words := PackedStringArray()
		var total := 0
		for chance in row.get("chances", []):
			var percent := int(chance.get("percent", 0))
			total += percent
			segments.append([percent / 100.0, Slate.hit_color(String(chance.get("color", "")))])
			words.append("%s %d%%" % [String(chance.get("label", "")), percent])
		var under := HBoxContainer.new()
		under.add_theme_constant_override("separation", 10)
		under.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(under)
		var bar := ChanceBar.new(segments)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		under.add_child(bar)
		var sum := Slate.label("%d%%" % total, 11, Slate.TEXT, Slate.mono())
		sum.custom_minimum_size.x = 40
		sum.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		under.add_child(sum)
		tooltip_text = ", ".join(words)

	func _lit(on: bool) -> void:
		_box.bg_color = Slate.RAISED if on else Color(0, 0, 0, 0)
		_box.border_color = Slate.ACCENT if on else Slate.BORDER

	func _gui_input(event: InputEvent) -> void:
		if _action != "" and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			chosen.emit(_action)


## A bar of chances side by side, each a share of the whole width in its own color.
class ChanceBar extends Control:
	var _segments := []

	func _init(segments: Array) -> void:
		_segments = segments
		custom_minimum_size = Vector2(80, 8)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Slate.TRACK)
		var x := 0.0
		for segment in _segments:
			var w := clampf(float(segment[0]), 0.0, 1.0) * size.x
			if w <= 0.0:
				continue
			w = minf(w, size.x - x)
			draw_rect(Rect2(x, 0, maxf(w - 1.0, 1.0), size.y), segment[1])
			x += w


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
	## How much larger than asked for a board gets when there is room for it.
	const GROW := 1.6
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

	## Cell size and font size for the room there is: as asked for, larger (up to GROW) when the
	## room is big, or smaller to fit.
	func _layout() -> void:
		var glyph := _font.get_string_size("M", HORIZONTAL_ALIGNMENT_LEFT, -1, 100).x / 100.0
		var want := Vector2(_want, _want) if _square else Vector2(ceilf(_want * glyph), ceilf(_want * 1.3))
		var room := size - Vector2(PAD, PAD) * 2
		var scale := 1.0
		if _columns > 0 and not _rows.is_empty():
			scale = minf(GROW, minf(room.x / (want.x * _columns), room.y / (want.y * _rows.size())))
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
