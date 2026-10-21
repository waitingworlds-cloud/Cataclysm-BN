extends Control
## An item and everything you can do with it (the game's item action menu): the item's details on
## the left, its actions on the right. The game keeps the selection; clicking an action picks it,
## exactly as moving to it and pressing Enter would.

const MAX_SIZE := Vector2(940, 780)
const ACTION_ICONS := {
	"ACTIVATE": "zap", "READ": "book-open", "EAT": "utensils", "WEAR": "shirt", "WIELD": "sword",
	"UNWIELD": "sword", "THROW": "send", "CHANGE_SIDE": "arrow-left-right", "TAKE_OFF": "shirt",
	"DROP": "arrow-down-to-line", "UNLOAD": "package-open", "RELOAD": "rotate-ccw",
	"PART_RELOAD": "rotate-ccw", "MEND": "wrench", "SALVAGE": "scissors", "DISASSEMBLE": "recycle",
	"SHOW_KILL_LIST": "skull", "FAVORITE_ADD": "star", "FAVORITE_REMOVE": "star-off",
	"DROP_WITH_CLOTHING": "shirt", "OPEN_ITEM_IN_HHG": "external-link", "REASSIGN": "keyboard",
	"AUTOPICKUP_ADD": "hand", "AUTOPICKUP_REMOVE": "hand",
}

const SlateButton := preload("res://src/ui/slate_button.gd")

var view_id := 0
## Item type id, for pinning the item to the hotbar.
var item_type := ""

var _card: PanelContainer
var _glyph: Label
var _name: RichTextLabel
var _category: Label
var _info: RichTextLabel
var _info_scroll: ScrollContainer
var _list: VBoxContainer
var _list_scroll: ScrollContainer
var _rows: Array = []
var _hints: HBoxContainer
var _sent_actions: Array = []
var _selected := -1
var _pin: SlateButton


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
	var style := Slate.card_box(18, 0)
	style.bg_color = Slate.CARD_SOLID
	_card.add_theme_stylebox_override("panel", style)
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(_card)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	_card.add_child(col)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 0)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)
	body.add_child(_build_item())
	body.add_child(_build_actions())
	col.add_child(_build_footer())
	resized.connect(_layout)
	_layout()


func _build_item() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	col.add_child(head)
	var tile := PanelContainer.new()
	tile.add_theme_stylebox_override("panel", Slate.box(Color(1, 1, 1, 0.06), 12, Slate.BORDER, 1))
	tile.custom_minimum_size = Vector2(56, 56)
	tile.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_glyph = Slate.label("", 28, Slate.TEXT, Slate.mono_bold())
	_glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tile.add_child(_glyph)
	head.add_child(tile)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 4)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(names)
	_name = Slate.rich(19)
	_name.add_theme_font_override("normal_font", Slate.heavy())
	names.add_child(_name)
	_category = Slate.label("", 11, Slate.FAINT, Slate.bold())
	names.add_child(_category)

	var line := ColorRect.new()
	line.color = Slate.BORDER
	line.custom_minimum_size.y = 1
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(line)
	_info_scroll = ScrollContainer.new()
	_info_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_info_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_info_scroll)
	_info = Slate.rich(13)
	_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_info.add_theme_color_override("default_color", Slate.SOFT)
	_info.add_theme_constant_override("line_separation", 4)
	_info_scroll.add_child(_info)

	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "top", "right", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 22)
	pad.add_child(col)
	return pad


func _build_actions() -> Control:
	var box := PanelContainer.new()
	var sb := Slate.box(Color(1, 1, 1, 0.025), 0, Slate.BORDER, 0)
	sb.border_width_left = 1
	sb.border_color = Slate.BORDER
	sb.corner_radius_top_right = 18
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 18
	sb.content_margin_bottom = 12
	box.add_theme_stylebox_override("panel", sb)
	box.custom_minimum_size.x = 320
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	box.add_child(col)

	var head := HBoxContainer.new()
	var title := Slate.label("Actions", 13, Slate.MUTED, Slate.bold())
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := Button.new()
	close.icon = Slate.icon("x", 18)
	close.tooltip_text = "Back"
	close.focus_mode = Control.FOCUS_NONE
	close.custom_minimum_size = Vector2(32, 32)
	close.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	close.add_theme_color_override("icon_normal_color", Slate.MUTED)
	close.add_theme_color_override("icon_hover_color", Slate.TEXT)
	close.pressed.connect(func(): Bridge.press(view_id, "QUIT"))
	head.add_child(close)
	var head_pad := MarginContainer.new()
	head_pad.add_theme_constant_override("margin_left", 10)
	head_pad.add_child(head)
	col.add_child(head_pad)

	_list_scroll = ScrollContainer.new()
	_list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_list_scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 2)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_scroll.add_child(_list)
	return box


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
	row.add_theme_constant_override("separation", 16)
	bar.add_child(row)
	_pin = SlateButton.new("star", "Pin to hotbar")
	_pin.set_key("Alt 1–9")
	_pin.tooltip_text = "Put this item on the hotbar. Alt+1 to Alt+9 pick the slot; on the map they use it."
	_pin.pressed.connect(func(): pin_to(-1))
	row.add_child(_pin)
	_hints = HBoxContainer.new()
	_hints.add_theme_constant_override("separation", 16)
	_hints.alignment = BoxContainer.ALIGNMENT_END
	_hints.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_hints)
	return bar


## Pins the item to hotbar `slot` (0 to 8), or the first free one when -1.
func pin_to(slot: int) -> void:
	if item_type == "":
		return
	var used := Hotbar.pin(item_type, slot)
	_update_pin()
	if used < 0:
		_pin.set_text("Hotbar is full: use Alt+1–9")


func _update_pin() -> void:
	var at := Hotbar.slots.find(item_type)
	_pin.set_text("On hotbar · slot %d" % (at + 1) if at >= 0 else "Pin to hotbar")


func _layout() -> void:
	if _card == null:
		return
	var viewport := get_viewport_rect().size
	_card.custom_minimum_size = Vector2(minf(viewport.x - 64, MAX_SIZE.x), minf(viewport.y - 64, MAX_SIZE.y))


func apply(msg: Dictionary) -> void:
	item_type = String(msg.get("type", ""))
	_pin.visible = item_type != ""
	_update_pin()
	_glyph.text = String(msg.get("sym", "?"))
	_glyph.add_theme_color_override("font_color", Slate.curses(String(msg.get("sym_color", "c_white"))))
	_name.text = Slate.bbcode(msg.get("name", []), Slate.TEXT)
	_category.text = String(msg.get("category", "")).to_upper()
	var info := Slate.bbcode(msg.get("info", []), Slate.SOFT)
	# The game separates sections with "--" lines; show them as spacing instead.
	_info.text = info.replace("\n--\n", "\n\n").replace("--\n", "\n").strip_edges()
	# Page Up and Page Down move the details by the game's scroll steps (lines).
	_info_scroll.scroll_vertical = maxi(int(msg.get("scroll", 0)), 0) * 22

	var actions: Array = msg.get("actions", [])
	if actions != _sent_actions:
		_sent_actions = actions
		_build_rows(actions)
	var selected := int(msg.get("selected", 0))
	var moved := selected != _selected
	_selected = selected
	for i in _rows.size():
		(_rows[i] as ActionRow).set_selected(i == selected)
	if moved and selected >= 0 and selected < _rows.size():
		_scroll_to(_rows[selected])

	var keys: Dictionary = msg.get("keys", {})
	for c in _hints.get_children():
		c.queue_free()
	_hints.add_child(_hint_item("↑↓", "Move"))
	_hints.add_child(_hint_item(Slate.key_name(String(keys.get("CONFIRM", "Enter"))), "Do it"))
	_hints.add_child(_hint_item("PgUp PgDn", "Scroll details"))
	_hints.add_child(_hint_item(Slate.key_name(String(keys.get("QUIT", "Esc"))), "Back"))


func _build_rows(actions: Array) -> void:
	for c in _list.get_children():
		c.queue_free()
	_rows.clear()
	for i in actions.size():
		var row := ActionRow.new()
		row.setup(actions[i])
		var index := i
		row.clicked.connect(func(): Bridge.pick(view_id, index, "CONFIRM"))
		_list.add_child(row)
		_rows.append(row)


func _scroll_to(row: Control) -> void:
	await get_tree().process_frame
	if is_instance_valid(row):
		_list_scroll.ensure_control_visible(row)


func _hint_item(key: String, text: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(Slate.key_chip(key, 10))
	h.add_child(Slate.label(text, 12, Slate.MUTED))
	return h


## One action: icon, name and key. The game colors actions by whether they can be done; here
## doable actions read normally, ones that can't be done now are red, impossible ones are dim.
class ActionRow extends PanelContainer:
	signal clicked

	var _selected := false
	var _hover := false

	func setup(action: Dictionary) -> void:
		custom_minimum_size.y = 36
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(func():
			_hover = true
			_restyle())
		mouse_exited.connect(func():
			_hover = false
			_restyle())
		var color_name := String(action.get("color", ""))
		var color := Slate.TEXT
		var icon_color := Slate.MUTED
		if color_name.ends_with("light_gray"):
			color = Slate.FAINT
			icon_color = Slate.FAINT
			tooltip_text = "You can't do this with this item."
		elif color_name.ends_with("light_red"):
			color = Slate.curses("c_light_red")
			icon_color = color
			tooltip_text = "You can't do this right now."
		elif color_name == "c_red":
			color = Slate.DANGER
			icon_color = color

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(row)
		row.add_child(Slate.icon_rect(ACTION_ICONS.get(String(action.get("act", "")), "list"), 16, icon_color))
		var name := Slate.label(String(action.get("name", "")), 14, color, Slate.semibold())
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(name)
		row.add_child(Slate.key_chip(Slate.key_name(String(action.get("key", ""))), 11))
		_restyle()

	func set_selected(on: bool) -> void:
		if on != _selected:
			_selected = on
			_restyle()

	func _restyle() -> void:
		var bg := Color(0, 0, 0, 0)
		if _selected:
			bg = Color(1, 1, 1, 0.09)
		elif _hover:
			bg = Color(1, 1, 1, 0.05)
		var sb := Slate.box(bg, 10, Slate.BORDER, 0)
		if _selected:
			sb.border_width_left = 3
			sb.border_color = Slate.ACCENT
		sb.content_margin_left = 10
		sb.content_margin_right = 8
		sb.content_margin_top = 4
		sb.content_margin_bottom = 4
		add_theme_stylebox_override("panel", sb)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			clicked.emit()
