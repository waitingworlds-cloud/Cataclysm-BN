extends Control
## An item and everything you can do with it (the game's item action menu), in the frame the
## inventory uses: the item and its full description in the middle, its actions at the right.
## The game keeps the selection; clicking an action picks it, exactly as moving to it and
## pressing Enter would.

const Hud := preload("res://src/ui/hud.gd")
const ACTION_ICONS := {
	"ACTIVATE": "zap", "READ": "book-open", "EAT": "utensils", "WEAR": "shirt", "WIELD": "sword",
	"UNWIELD": "sword", "THROW": "send", "CHANGE_SIDE": "arrow-left-right", "TAKE_OFF": "shirt",
	"DROP": "arrow-down-to-line", "UNLOAD": "package-open", "RELOAD": "rotate-ccw",
	"PART_RELOAD": "rotate-ccw", "MEND": "wrench", "SALVAGE": "scissors", "DISASSEMBLE": "recycle",
	"SHOW_KILL_LIST": "skull", "FAVORITE_ADD": "star", "FAVORITE_REMOVE": "star-off",
	"DROP_WITH_CLOTHING": "shirt", "OPEN_ITEM_IN_HHG": "external-link", "REASSIGN": "keyboard",
	"AUTOPICKUP_ADD": "hand", "AUTOPICKUP_REMOVE": "hand",
}
## The description is easier to read in a column than across the whole screen.
const INFO_WIDTH := 760.0

var view_id := 0
## Item type id, for pinning the item to the hotbar.
var item_type := ""

var _cockpit: Cockpit
var _slot: ItemSlot
var _name: RichTextLabel
var _category: Label
var _info: RichTextLabel
var _info_scroll: ScrollContainer
var _actions: Hud.Module
var _list: VBoxContainer
var _list_scroll: ScrollContainer
var _rows: Array = []
var _sent_actions: Array = []
var _selected := -1
var _pin: ActionButton


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cockpit = Cockpit.new()
	add_child(_cockpit)
	_cockpit.close_pressed.connect(func(): Bridge.press(view_id, "QUIT"))
	_cockpit.laid_out.connect(_layout)
	_cockpit.set_title("Item actions")
	_cockpit.set_back("Back", "Esc")

	var cols := HBoxContainer.new()
	cols.set_anchors_preset(Control.PRESET_FULL_RECT)
	cols.add_theme_constant_override("separation", Cockpit.GUT)
	cols.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cockpit.body.add_child(cols)
	cols.add_child(_build_item())
	cols.add_child(_build_actions())
	_layout()


func _build_item() -> Control:
	var module := Hud.Module.new("Item", Slate.ACCENT)
	module.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	module.set_body(col, 18, 16)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	col.add_child(head)
	_slot = ItemSlot.new(96)
	_slot.selected = true
	_slot.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	head.add_child(_slot)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 6)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(names)
	_name = Slate.rich(24)
	_name.add_theme_font_override("normal_font", Slate.heading())
	names.add_child(_name)
	_category = Slate.label("", 12, Slate.MUTED, Slate.mono())
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
	_info = Slate.rich(14)
	_info.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_info.add_theme_color_override("default_color", Slate.SOFT)
	_info.add_theme_constant_override("line_separation", 4)
	_info_scroll.add_child(_info)
	return module


func _build_actions() -> Control:
	_actions = Hud.Module.new("Actions")
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	_actions.set_body(col, 10, 10)
	_list_scroll = ScrollContainer.new()
	_list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_list_scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 2)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_scroll.add_child(_list)
	_pin = ActionButton.new(false)
	_pin.set_key("Alt 1-9")
	_pin.tooltip_text = "Put this item on the hotbar. Alt+1 to Alt+9 pick the slot; on the map they use it."
	_pin.pressed.connect(func(): pin_to(-1))
	col.add_child(_pin)
	return _actions


## Pins the item to hotbar `slot` (0 to 8), or the first free one when -1.
func pin_to(slot: int) -> void:
	if item_type == "":
		return
	var used := Hotbar.pin(item_type, slot)
	_update_pin()
	if used < 0:
		_pin.set_label("Hotbar full: Alt+1-9")


func _update_pin() -> void:
	var at := Hotbar.slots.find(item_type)
	_pin.set_label("On hotbar // slot %d" % (at + 1) if at >= 0 else "Pin to hotbar")
	_pin.set_on(at >= 0)


func _layout() -> void:
	if _actions == null:
		return
	var width := _cockpit.body.size.x
	_actions.custom_minimum_size.x = clampf(roundf(width * 0.29), 280, 420)
	_info.custom_minimum_size.x = minf(INFO_WIDTH, maxf(width - _actions.custom_minimum_size.x - 60, 200))


func apply(msg: Dictionary) -> void:
	item_type = String(msg.get("type", ""))
	_pin.visible = item_type != ""
	_update_pin()
	_slot.set_item(item_type, String(msg.get("sym", "?")), Slate.curses(String(msg.get("sym_color", "c_white"))))
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
	var quit := Slate.key_name(String(keys.get("QUIT", "Esc")))
	_cockpit.set_back("Back", quit)
	_cockpit.set_hints([["↑↓", "move"], [Slate.key_name(String(keys.get("CONFIRM", "Enter"))), "do it"],
			["PgUp PgDn", "scroll the description"], ["Alt 1-9", "pin to hotbar"], [quit, "back"]])


func _build_rows(actions: Array) -> void:
	for c in _list.get_children():
		_list.remove_child(c)
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
		var icon_color := Slate.CYAN
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
		var name := Slate.label(String(action.get("name", "")).to_upper(), 13, color, Slate.spaced(Slate.heading(), 2))
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
			bg = Color(Slate.ACCENT, 0.10)
		elif _hover:
			bg = Color(Slate.CYAN, 0.10)
		var sb := Slate.box(bg, 0, Slate.BORDER, 0)
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
