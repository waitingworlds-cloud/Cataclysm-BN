class_name Cockpit
extends Control
## The frame a full screen sits in (inventory, crafting, ...), matching the main screen: who you
## are at the top left, a bar with the screen's name or the tabs to the other big screens, the
## map in a bezel down the left side, the screen's modules beside it and a strip of key hints
## along the bottom. Nothing floats over the map: the map strip is the same picture as the main
## screen, moved so that you stay in the middle of it (see `main.gd`).
##
## A screen adds its modules to `body`, puts something small in `foot` (the module under the map
## strip) and tells the frame what its title, tabs and hints are.

signal laid_out
## A tab was clicked: the action that opens the other screen.
signal tab_pressed(action: String)
signal close_pressed

const Hud := preload("res://src/ui/hud.gd")
const GUT := 8
const TOP := 58
const FOOT := 38
## Below this width there is no room for the map strip.
const STRIP_MIN_WINDOW := 1360.0
## The big screens you can jump between: the action that opens each, and its name.
const TABS := [
	["inventory", "Inventory"],
	["craft", "Crafting"],
	["construct", "Construction"],
	["player_data", "Character"],
	["map", "Map"],
	["messages", "Log"],
]

## True while a game is running and its map is on screen behind this frame. Outside a game
## (the main menu's screens, character creation) there is no map strip and no one to name.
static var in_game := false

## A wide frame turns the layout around for screens that are a map of their own (the overmap,
## a vehicle): the viewport takes most of the room and the screen gets one column at the right,
## `side_width` wide. The viewport is live there: clicks in it go to the game.
var wide := false
## In a wide frame: the height of the module under the viewport (0: no module there).
var wide_foot := 0.0
var side_width := 400.0
## The part of the game's picture that belongs in the viewport, in interface units. Empty: the
## main screen's map.
var source := Rect2()

## Where modules go: the area right of the map strip, between the top bar and the hints.
var body: Control
## The small module under the map strip; hidden when there is no strip.
var foot: Hud.Module
## The map strip in this control's coordinates; no size when the window is too narrow for it.
var strip := Rect2()

var _frame: Hud.FrameView
var _strip_click: Control
var _identity: PanelContainer
var _name: Label
var _chips: HBoxContainer
var _bar: PanelContainer
var _bar_row: HBoxContainer
var _title: Label
var _subtitle: RichTextLabel
var _tab_row: HBoxContainer
var _tabs := {}
var _back: Hud.KeyButton
var _hint_panel: PanelContainer
var _hints: HBoxContainer
var _footer: RichTextLabel
var _active_tab := ""
var _back_label := "Back to map"
var _laid_in_game := false
var _foot_body: Control


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_to_group("cockpit")

	_frame = Hud.FrameView.new()
	_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_frame)
	# The map strip is a picture, not a second map: a click on it goes back to the real one.
	_strip_click = Control.new()
	_strip_click.mouse_filter = Control.MOUSE_FILTER_STOP
	_strip_click.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_strip_click.tooltip_text = "Back to the map"
	_strip_click.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			close_pressed.emit())
	add_child(_strip_click)

	_identity = _panel()
	var id_row := HBoxContainer.new()
	id_row.add_theme_constant_override("separation", 10)
	id_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_identity.add_child(_margin(id_row, 14, 0, 12, 0))
	_name = Slate.label("", 18, Slate.TEXT, Slate.spaced(Slate.heavy(), 1))
	_name.uppercase = true
	_name.clip_text = true
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	id_row.add_child(_name)
	_chips = HBoxContainer.new()
	_chips.add_theme_constant_override("separation", 8)
	_chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	id_row.add_child(_chips)

	_bar = _panel()
	_bar_row = HBoxContainer.new()
	_bar_row.add_theme_constant_override("separation", 14)
	_bar_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.add_child(_margin(_bar_row, 0, 0, 14, 0))
	_tab_row = HBoxContainer.new()
	_tab_row.add_theme_constant_override("separation", 0)
	_tab_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tab_row.visible = false
	_bar_row.add_child(_tab_row)
	for tab in TABS:
		var action: String = tab[0]
		var t := Tab.new(String(tab[1]))
		t.pressed.connect(func():
			if action != _active_tab:
				tab_pressed.emit(action))
		_tab_row.add_child(t)
		_tabs[action] = t
	var title_box := HBoxContainer.new()
	title_box.add_theme_constant_override("separation", 12)
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_row.add_child(title_box)
	var lead := Control.new()
	lead.custom_minimum_size.x = 4
	lead.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_box.add_child(lead)
	_title = Slate.label("", 17, Slate.CYAN, Slate.spaced(Slate.heavy(), 2))
	_title.uppercase = true
	title_box.add_child(_title)
	# Not fitted to its text: a long hint is cut off instead of widening the bar.
	_subtitle = Slate.rich(12, false)
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_OFF
	_subtitle.clip_contents = true
	_subtitle.custom_minimum_size.y = 18
	_subtitle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_subtitle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_subtitle.add_theme_color_override("default_color", Slate.MUTED)
	title_box.add_child(_subtitle)
	_back = Hud.KeyButton.new("Back to map")
	_back.set_key("Esc")
	_back.pressed.connect(func(): close_pressed.emit())
	_bar_row.add_child(_back)

	body = Control.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(body)

	foot = Hud.Module.new("In hand")
	add_child(foot)

	_hint_panel = _panel()
	var hint_row := HBoxContainer.new()
	hint_row.add_theme_constant_override("separation", 18)
	hint_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_panel.add_child(_margin(hint_row, 14, 0, 14, 0))
	_hints = HBoxContainer.new()
	_hints.add_theme_constant_override("separation", 18)
	_hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_row.add_child(_hints)
	_footer = Slate.rich(12, false)
	_footer.autowrap_mode = TextServer.AUTOWRAP_OFF
	_footer.clip_contents = true
	_footer.custom_minimum_size.y = 18
	_footer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_footer.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_footer.add_theme_color_override("default_color", Slate.MUTED)
	hint_row.add_child(_footer)


func _ready() -> void:
	resized.connect(_layout)
	Display.changed.connect(_layout)
	visibility_changed.connect(refresh_identity)
	Bridge.hud_received.connect(func(_hud: Dictionary): refresh_identity())
	_layout()
	refresh_identity()
	if _foot_body == null:
		show_in_hand()


func _process(_delta: float) -> void:
	if _laid_in_game != in_game:
		_layout()


# --- What a screen sets --------------------------------------------------------------------------

## For a wide frame: the part of the game's picture its viewport shows and how wide the column
## beside it is.
func set_viewport_source(rect: Rect2, side: float) -> void:
	if rect != source or side != side_width:
		source = rect
		side_width = side
		_layout()


## In a wide frame: makes room under the viewport for the `foot` module, `height` tall (0 takes
## the module away).
func set_wide_foot(height: float) -> void:
	if height != wide_foot:
		wide_foot = height
		_layout()


## A plain title, for screens you can't tab away from (pickers and prompts), with the screen's
## own hint beside it.
func set_title(title: String, hint_bbcode := "") -> void:
	_active_tab = ""
	_tab_row.visible = false
	_title.visible = true
	_title.text = title
	_subtitle.text = hint_bbcode
	_fit_bar()


## Shows the tabs to the big screens, with `action`'s tab lit.
func set_tabs(action: String) -> void:
	_active_tab = action
	_tab_row.visible = true
	_title.visible = false
	_subtitle.text = ""
	_refresh_tabs()
	_fit_bar()


## Key hints along the bottom: `[key, what it does]` pairs.
func set_hints(hints: Array) -> void:
	for c in _hints.get_children():
		_hints.remove_child(c)
		c.queue_free()
	for h in hints:
		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 7)
		item.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if String(h[0]) != "":
			item.add_child(Slate.key_chip(String(h[0]).to_upper(), 10))
		item.add_child(Slate.label(String(h[1]), 13, Slate.MUTED))
		_hints.add_child(item)


## The screen's own status line, right of the hints.
func set_footer(bbcode: String) -> void:
	_footer.text = bbcode


func set_back(label: String, key: String) -> void:
	_back_label = label
	_back.set_label(label)
	_back.set_key(key)
	_back.tooltip_text = label


func set_back_visible(on: bool) -> void:
	_back.visible = on


## The wielded item in the small module under the map strip: what most screens show there.
func show_in_hand() -> void:
	var hud := _hud()
	var wielded = hud.state().get("wielded", null) if hud != null else null
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var slot := ItemSlot.new(44)
	slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slot)
	var name := Slate.label("Bare hands", 15, Slate.MUTED, Slate.semibold())
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.clip_text = true
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(name)
	if typeof(wielded) == TYPE_DICTIONARY:
		slot.selected = true
		slot.set_item(String(wielded.get("type", "")), String(wielded.get("sym", "?")), Slate.curses(String(wielded.get("color", "c_white"))))
		name.text = Slate.cap(String(wielded.get("name", "")))
		name.add_theme_color_override("font_color", Slate.TEXT)
	set_foot("In hand", row)


## Replaces what the small module under the map strip shows.
func set_foot(title: String, content: Control) -> void:
	foot.set_title(title)
	if _foot_body != null:
		# The module wraps its body in a margin; drop that with it.
		_foot_body.get_parent().queue_free()
	_foot_body = content
	foot.set_body(content, 12, 8)


func has_foot() -> bool:
	return foot.visible


# --- Layout --------------------------------------------------------------------------------------

func _hud() -> Hud:
	return get_tree().get_first_node_in_group("hud") as Hud if is_inside_tree() else null


func _layout() -> void:
	var top := GUT + TOP + GUT
	var column_height := maxf(size.y - top - GUT - FOOT - GUT, 80)
	var hud := _hud()
	strip = Rect2()
	_laid_in_game = in_game
	# A wide frame only ever opens over a running game.
	var playing := in_game or wide
	if wide:
		var side := minf(side_width, roundf(size.x * 0.45))
		var under := wide_foot + GUT if wide_foot > 0 else 0.0
		strip = Rect2(GUT, top, maxf(size.x - 3 * GUT - side, 80), maxf(column_height - under, 80))
	elif hud != null and in_game and size.x >= STRIP_MIN_WINDOW:
		# The strip shows a cut of the main screen's map, so it can't be bigger than that.
		var map := hud.map_rect()
		var width := minf(clampf(roundf(size.x * 0.235), 320, 460), map.size.x)
		strip = Rect2(GUT, top, width, minf(map.size.y, column_height))
	var has_strip := strip.size.x > 0
	_frame.viewport = strip if has_strip else Rect2(-40, -40, 8, 8)
	_frame.queue_redraw()
	_strip_click.visible = has_strip and not wide
	_strip_click.position = strip.position
	_strip_click.size = strip.size

	var left_width := strip.size.x if has_strip else clampf(size.x * 0.25, 220, 340)
	if wide:
		left_width = clampf(roundf(size.x * 0.235), 320, 460)
	_identity.visible = playing
	_identity.position = Vector2(GUT, GUT)
	_identity.size = Vector2(left_width, TOP)
	_bar.position = Vector2(GUT + left_width + GUT if playing else GUT, GUT)
	_bar.size = Vector2(maxf(size.x - _bar.position.x - GUT, 80), TOP)
	_fit_bar()
	_bar.size = Vector2(maxf(size.x - _bar.position.x - GUT, 80), TOP)

	var body_left := strip.end.x + GUT if has_strip else float(GUT)
	body.position = Vector2(body_left, top)
	body.size = Vector2(maxf(size.x - body_left - GUT, 80), column_height)

	var foot_top := strip.end.y + GUT
	var foot_height := top + column_height - foot_top
	foot.visible = has_strip and foot_height >= 56 and (not wide or wide_foot > 0)
	foot.position = Vector2(GUT, foot_top)
	foot.size = Vector2(strip.size.x, foot_height)

	_hint_panel.position = Vector2(GUT, size.y - GUT - FOOT)
	_hint_panel.size = Vector2(maxf(size.x - 2 * GUT, 80), FOOT)
	laid_out.emit()


## Narrow bars drop the tabs' key hints, then shorten the way back.
func _fit_bar() -> void:
	if _back == null:
		return
	for t in _tabs.values():
		(t as Tab).set_compact(false)
	_back.set_label(_back_label)
	if not _tab_row.visible:
		return
	var room := _bar.size.x - 14
	if _bar_row.get_combined_minimum_size().x > room:
		_back.set_label("Back")
	if _bar_row.get_combined_minimum_size().x > room:
		for t in _tabs.values():
			(t as Tab).set_compact(true)


func _refresh_tabs() -> void:
	var hud := _hud()
	for action in _tabs:
		var t: Tab = _tabs[action]
		t.set_on(action == _active_tab)
		var key := Slate.key_name(hud.key(action)) if hud != null else ""
		t.set_key(key)
		t.tooltip_text = "You are here" if action == _active_tab else "Open %s" % String(t.title).to_lower()


## Who you are and how you are doing, from the main screen's last state: name, injuries, the
## time and the nearest threat.
func refresh_identity() -> void:
	if not is_visible_in_tree():
		return
	var hud := _hud()
	if hud == null:
		return
	var state: Dictionary = hud.state()
	_name.text = String(state.get("name", ""))
	for c in _chips.get_children():
		_chips.remove_child(c)
		c.queue_free()
	var injuries := {}
	for p in state.get("body", []):
		for s in Hud._part_state(p):
			injuries[String(s).get_slice(",", 0)] = Slate.SOFT if String(s).begins_with("Broken") else Slate.DANGER
	for kind in injuries:
		_chips.add_child(Slate.label(String(kind).to_upper(), 11, injuries[kind], Slate.mono()))
	for need in ["thirst", "hunger", "fatigue"]:
		var info: Dictionary = state.get(need, {})
		var text := String(info.get("text", ""))
		if text != "" and Slate.severity(String(info.get("color", ""))) < 0.6:
			_chips.add_child(Slate.label(text.to_upper(), 11, Slate.curses(String(info.get("color", "")), Slate.WARN), Slate.mono()))
	if String(state.get("time_kind", "clock")) == "clock" and String(state.get("time", "")) != "":
		_chips.add_child(Slate.label(String(state.get("time", "")), 13, Slate.ACCENT, Slate.mono()))
	for s in state.get("sight", []):
		if bool(s.get("hostile", false)):
			var threat := Slate.label(" %s %d %s " % [String(s.get("name", "")).to_upper(), int(s.get("dist", 0)),
					Hud.DIRS[clampi(int(s.get("dir", 8)), 0, 8)]], 11, Slate.DANGER, Slate.mono())
			threat.draw.connect(func(): threat.draw_rect(Rect2(Vector2(0.5, 0.5), threat.size - Vector2(1, 1)), Color(Slate.DANGER, 0.8), false, 1.0))
			_chips.add_child(threat)
			break
	# A crowded box keeps the name and drops chips from the front.
	var room := _identity.size.x - 26 - 90
	while _chips.get_child_count() > 1 and _chips.get_combined_minimum_size().x > room:
		var first := _chips.get_child(0)
		_chips.remove_child(first)
		first.queue_free()
	if _tab_row.visible:
		_refresh_tabs()


func _panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Slate.module_box(0))
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(p)
	return p


func _margin(child: Control, left: int, top: int, right: int, bottom: int) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", left)
	m.add_theme_constant_override("margin_top", top)
	m.add_theme_constant_override("margin_right", right)
	m.add_theme_constant_override("margin_bottom", bottom)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(child)
	return m


## One tab of the top bar: the screen's name and its key. The lit tab is the screen you are on.
class Tab extends Button:
	var title := ""
	var _on := false
	var _compact := false
	var _text: Label
	var _key: Label

	func _init(text: String) -> void:
		title = text
		focus_mode = Control.FOCUS_NONE
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		size_flags_vertical = Control.SIZE_FILL
		var row := HBoxContainer.new()
		row.set_anchors_preset(Control.PRESET_FULL_RECT)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 8)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(row)
		_text = Slate.label(text.to_upper(), 14, Slate.SOFT, Slate.spaced(Slate.heading(), 2))
		row.add_child(_text)
		_key = Slate.label("", 11, Slate.MUTED, Slate.mono())
		_key.visible = false
		row.add_child(_key)
		_restyle()

	func set_on(on: bool) -> void:
		_on = on
		mouse_default_cursor_shape = Control.CURSOR_ARROW if on else Control.CURSOR_POINTING_HAND
		_restyle()

	func set_key(key: String) -> void:
		_key.text = key
		_key.visible = key != "" and not _compact
		_fit()

	func set_compact(on: bool) -> void:
		_compact = on
		_key.visible = _key.text != "" and not on
		_fit()

	func _fit() -> void:
		var width := 0.0
		for c in [_text, _key]:
			if (c as Control).visible:
				width += (c as Control).get_combined_minimum_size().x + 8
		custom_minimum_size.x = width + (20 if _compact else 36)

	func _restyle() -> void:
		var normal := StyleBoxFlat.new()
		normal.bg_color = Slate.CYAN if _on else Color(0, 0, 0, 0)
		if _on:
			normal.corner_radius_top_left = 9
			normal.corner_radius_bottom_right = 9
			normal.corner_detail = 1
		var hot := normal.duplicate() as StyleBoxFlat
		if not _on:
			hot.bg_color = Color(Slate.CYAN, 0.14)
		add_theme_stylebox_override("normal", normal)
		add_theme_stylebox_override("hover", hot)
		add_theme_stylebox_override("pressed", hot)
		_text.add_theme_color_override("font_color", Slate.ACCENT_TEXT if _on else Slate.SOFT)
		_key.add_theme_color_override("font_color", Color(Slate.ACCENT_TEXT, 0.75) if _on else Slate.MUTED)
		_fit()
