extends Control
## The inventory: the game's `inventory_selector` and its variants (inventory, drop, pick up, use,
## and every "choose an item" prompt), in the frame the main screen uses. One module per list the
## game shows, side by side in the game's order so the left and right keys move the way they
## look: what you carry and what is nearby as grids of item slots grouped by category, what you
## wear and what you have chosen as rows, and the selected item with its actions at the right.
## Lists with their own columns (calories, damage, ...) are shown as rows so nothing the old
## screen showed is lost, and any grid can be switched to rows.
##
## The game owns the lists, the cursor and the filter; a click selects a slot or presses the key
## bound to an action, exactly as the keyboard would.

const Hud := preload("res://src/ui/hud.gd")
## Picks arrive in the game as `pane * STRIDE + row index` (see `inventory_ui.cpp`).
const STRIDE := 100000
const SLOT := 66.0
const SLOT_GAP := 6
const ROW_HEIGHT := 40
## Narrowest extra column a list shows (damage, encumbrance, ...), and the gap between them.
const MIN_CELL_WIDTH := 30
const MAX_CELL_WIDTH := 190
const CELL_GAP := 10
const PANE_TITLES := {"carried": "Carried", "nearby": "Nearby // In reach", "worn": "Rig // Equipment", "selection": "Chosen"}
## Actions on the selected item, when the screen's input context has them.
const ITEM_ACTIONS := [
	["WIELD", "Wield", "Hold this item in your hands"],
	["WEAR", "Wear", "Put this item on"],
	["EXAMINE", "Examine", "Read the item's full description"],
	["TOGGLE_FAVORITE", "Favorite", "Favorites are kept when you drop everything else"],
]
## Actions on the whole list.
const LIST_ACTIONS := [
	["CATEGORY_SELECTION", "By category", "Move between categories instead of items"],
	["unload_all", "Unload all", "Unload every carried item that can be unloaded"],
	["DROP_NON_FAVORITE", "Not favorites", "Mark or unmark everything that is not a favorite or worn"],
]
const SETTINGS := "user://interface.cfg"
## What dropping a dragged item does, by verb.
const DROP_WORDS := {"wear": "Wear", "wield": "Wield", "take_off": "Take off", "drop": "Drop here"}

## Slots or rows for plain item lists; the player's choice, kept between runs.
static var grid_view := true
static var _settings_loaded := false

var view_id := 0

var _msg := {}
var _columns: Array = []
## Vector2i(pane, row index) -> the slot or row showing it.
var _cells := {}
var _pane_modules: Array = []
## For each column: its scroll box, the names it lists and whether it is a grid, or null.
var _pane_lists: Array = []
var _cursor := Vector2i(-1, -1)
var _multi := false

var _cockpit: Cockpit
var _cols: HBoxContainer
var _panes: HBoxContainer
var _keyed := false
var _load_module: Hud.Module
var _load_inline: VBoxContainer
var _load_foot: VBoxContainer
var _foot_kind := ""
var _search: PanelContainer
var _search_text: Label
var _search_key: PanelContainer
var _detail: Hud.Module
var _slot: ItemSlot
var _name: RichTextLabel
var _category: Label
var _facts: HBoxContainer
var _denial: PanelContainer
var _denial_text: RichTextLabel
var _info_scroll: ScrollContainer
var _info: RichTextLabel
var _no_item: Label
var _amount: Label
var _confirm: ActionButton
var _actions: GridContainer
var _buttons := {}
## Items can be dragged in the inventory itself (not in the "choose an item" prompts): onto the
## rig to wear, back to carried to take off, onto Wield or Wear, onto the map strip to drop.
var _draggable := false
## Vector2i(pane, row index) -> the row's data, for the picture that follows the mouse.
var _rows := {}
var _drop_glow: PanelContainer
var _drop_word: Label
var _glow_area: Control


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_load_settings()
	_cockpit = Cockpit.new()
	add_child(_cockpit)
	_cockpit.close_pressed.connect(func(): Bridge.press(view_id, "QUIT"))
	_cockpit.tab_pressed.connect(func(action: String):
		# Leave this screen, then open the other one as its key would.
		Bridge.press(view_id, "QUIT")
		Bridge.run(action))
	_cockpit.laid_out.connect(_layout)

	_cols = HBoxContainer.new()
	_cols.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cols.add_theme_constant_override("separation", Cockpit.GUT)
	_cols.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cockpit.body.add_child(_cols)
	var middle := VBoxContainer.new()
	middle.add_theme_constant_override("separation", Cockpit.GUT)
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cols.add_child(middle)
	_panes = HBoxContainer.new()
	_panes.add_theme_constant_override("separation", Cockpit.GUT)
	_panes.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_panes.mouse_filter = Control.MOUSE_FILTER_IGNORE
	middle.add_child(_panes)
	# Weight and volume sit under the map strip; without the strip they get a module here.
	_load_module = Hud.Module.new("Load")
	_load_inline = VBoxContainer.new()
	_load_inline.add_theme_constant_override("separation", 6)
	_load_module.set_body(_load_inline, 12, 8)
	_load_module.visible = false
	middle.add_child(_load_module)
	_cols.add_child(_build_detail())
	_build_drop_glow()
	var strip := _cockpit.drop_area()
	strip.set_drag_forwarding(Callable(), _can_drop.bind("map", strip), _drop.bind("map"))
	for act in ["WIELD", "WEAR"]:
		var b: Control = _buttons[act]
		b.set_drag_forwarding(Callable(), _can_drop.bind(act, b), _drop.bind(act))
	_layout()


static func _load_settings() -> void:
	if _settings_loaded:
		return
	_settings_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) == OK:
		grid_view = bool(cfg.get_value("inventory", "grid", true))


static func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value("inventory", "grid", grid_view)
	cfg.save(SETTINGS)


# --- Building ------------------------------------------------------------------------------------

func _rule() -> ColorRect:
	var line := ColorRect.new()
	line.color = Slate.BORDER
	line.custom_minimum_size.y = 1
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


func _build_detail() -> Control:
	_detail = Hud.Module.new("Selected item", Slate.ACCENT)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	_detail.set_body(col, 16, 14)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	col.add_child(head)
	_slot = ItemSlot.new(92)
	_slot.selected = true
	_slot.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	head.add_child(_slot)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 5)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(names)
	_name = Slate.rich(19)
	_name.add_theme_font_override("normal_font", Slate.heading())
	names.add_child(_name)
	_category = Slate.label("", 11, Slate.MUTED, Slate.mono())
	names.add_child(_category)
	_facts = HBoxContainer.new()
	_facts.add_theme_constant_override("separation", 6)
	names.add_child(_facts)

	# Why the selected item can't be chosen here, in full (rows only have room for the start).
	_denial = PanelContainer.new()
	var denial_box := Slate.box(Color(Slate.DANGER, 0.1), 0, Color(Slate.DANGER, 0.5), 1)
	denial_box.content_margin_left = 12
	denial_box.content_margin_right = 12
	denial_box.content_margin_top = 8
	denial_box.content_margin_bottom = 8
	_denial.add_theme_stylebox_override("panel", denial_box)
	_denial_text = Slate.rich(13)
	_denial_text.add_theme_color_override("default_color", Slate.DANGER)
	_denial.add_child(_denial_text)
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

	# How many of a stack to mark, while you type it.
	_amount = Slate.label("", 14, Slate.ACCENT, Slate.mono())
	_amount.visible = false
	col.add_child(_amount)
	_confirm = ActionButton.new(true)
	_confirm.pressed.connect(func(): Bridge.press(view_id, "CONFIRM"))
	col.add_child(_confirm)
	_actions = GridContainer.new()
	_actions.columns = 2
	_actions.add_theme_constant_override("h_separation", 6)
	_actions.add_theme_constant_override("v_separation", 6)
	col.add_child(_actions)
	for a in ITEM_ACTIONS + LIST_ACTIONS:
		var b := ActionButton.new(false)
		b.set_label(String(a[1]))
		b.tooltip_text = String(a[2])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var act: String = a[0]
		b.pressed.connect(func(): Bridge.press(view_id, act))
		_actions.add_child(b)
		_buttons[act] = b
	return _detail


func _build_search(head: HBoxContainer) -> void:
	_search = PanelContainer.new()
	_search.mouse_filter = Control.MOUSE_FILTER_STOP
	_search.mouse_default_cursor_shape = Control.CURSOR_IBEAM
	_search.custom_minimum_size = Vector2(190, 22)
	_search.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_search.tooltip_text = "Search your items"
	_search.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			if String(_msg.get("prompt", "")) == "":
				Bridge.press(view_id, "INVENTORY_FILTER"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_search.add_child(row)
	row.add_child(Slate.label(">", 11, Slate.CYAN, Slate.mono()))
	_search_text = Slate.label("", 11, Slate.FAINT, Slate.mono())
	_search_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_text.clip_text = true
	row.add_child(_search_text)
	_search_key = Slate.key_chip("/", 10)
	row.add_child(_search_key)
	head.add_child(_search)


func _search_box(active: bool) -> StyleBoxFlat:
	var sb := Slate.box(Color(0, 0, 0, 0.25), 0, Slate.ACCENT if active else Color(Slate.CYAN, 0.4), 1)
	sb.content_margin_left = 8
	sb.content_margin_right = 4
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	return sb


func _layout() -> void:
	if _cols == null:
		return
	var width := _cockpit.body.size.x
	_detail.custom_minimum_size.x = clampf(roundf(width * 0.29), 280, 420)
	_update_load()


# --- Updates from the game -----------------------------------------------------------------------

func set_entries(columns: Array) -> void:
	_columns = columns
	_build_panes()
	if not _msg.is_empty():
		apply(_msg)
	_apply_cursor(true)


func apply(msg: Dictionary) -> void:
	_msg = msg
	var title := Slate.plain(msg.get("title", [])).strip_edges()
	if title == "":
		title = "Inventory"
	var keys: Dictionary = msg.get("keys", {})
	var quit := Slate.key_name(String(keys.get("QUIT", "Esc")))
	# The inventory itself is one of the big screens; everything else is a question to answer.
	_draggable = title == "Inventory"
	if title == "Inventory":
		_cockpit.set_tabs("inventory")
		_cockpit.set_back("Back to map", quit)
	else:
		_cockpit.set_title(title, Slate.bbcode(msg.get("hint", []), Slate.MUTED).strip_edges())
		_cockpit.set_back("Cancel", quit)

	var prompt := String(msg.get("prompt", ""))
	_update_search()
	_amount.visible = prompt == "count"
	_amount.text = "AMOUNT  %s▏" % String(msg.get("prompt_text", ""))

	var confirm_label := String(msg.get("confirm_label", ""))
	_confirm.set_label(confirm_label if confirm_label != "" else ("Confirm" if _multi else "Select"))
	_confirm.set_key(Slate.key_name(String(keys.get("CONFIRM", ""))))
	_confirm.set_enabled(bool(msg.get("available", true)))
	(_buttons["CATEGORY_SELECTION"] as ActionButton).set_on(bool(msg.get("category_mode", false)))

	_update_detail(msg.get("detail", {}), keys)
	_cockpit.set_footer(Slate.bbcode(msg.get("footer", []), Slate.MUTED).strip_edges())
	_update_hints(keys, prompt == "filter" or prompt == "count")
	_update_load()
	_apply_cursor(false)


func _update_search() -> void:
	if not is_instance_valid(_search):
		return
	var keys: Dictionary = _msg.get("keys", {})
	var typing := String(_msg.get("prompt", "")) == "filter"
	var filter := String(_msg.get("prompt_text", "")) if typing else String(_msg.get("filter", ""))
	_search.add_theme_stylebox_override("panel", _search_box(typing or filter != ""))
	if typing or filter != "":
		_search_text.text = filter + ("▏" if typing else "")
		_search_text.add_theme_color_override("font_color", Slate.TEXT)
	else:
		_search_text.text = "search"
		_search_text.add_theme_color_override("font_color", Slate.FAINT)
	_search.visible = keys.has("INVENTORY_FILTER")
	_search_key.visible = not typing and String(keys.get("INVENTORY_FILTER", "")) != ""
	(_search_key.get_child(0) as Label).text = Slate.key_name(String(keys.get("INVENTORY_FILTER", "")))


func _update_detail(detail: Dictionary, keys: Dictionary) -> void:
	var has_item := not detail.is_empty()
	_slot.visible = has_item
	_name.visible = has_item
	_category.visible = has_item
	_facts.visible = has_item
	_info_scroll.visible = has_item
	_denial.visible = has_item and detail.has("denial")
	_no_item.visible = not has_item
	if not has_item:
		_no_item.text = "Nothing to show here." if bool(_msg.get("empty", false)) else "Select an item to see its details."
	for a in ITEM_ACTIONS:
		var b: ActionButton = _buttons[a[0]]
		b.visible = has_item and keys.has(a[0])
		b.set_key(Slate.key_name(String(keys.get(a[0], ""))))
	for a in LIST_ACTIONS:
		var b: ActionButton = _buttons[a[0]]
		b.visible = keys.has(a[0])
		b.set_key(Slate.key_name(String(keys.get(a[0], ""))))
	if not has_item:
		return
	_slot.set_item(String(detail.get("type", "")), String(detail.get("sym", "?")), Slate.curses(String(detail.get("sym_color", "c_white"))))
	_slot.star = bool(detail.get("fav", false))
	_name.text = Slate.bbcode(detail.get("name", []), Slate.TEXT)
	_category.text = String(detail.get("category", "")).to_upper()
	for c in _facts.get_children():
		_facts.remove_child(c)
		c.queue_free()
	for fact in [["Weight", String(detail.get("weight", ""))], ["Volume", String(detail.get("volume", ""))]]:
		if String(fact[1]) != "":
			_facts.add_child(_fact(String(fact[0]), String(fact[1])))
	_denial_text.text = Slate.bbcode(detail.get("denial", []), Slate.DANGER).strip_edges()
	var info := Slate.bbcode(detail.get("info", []), Slate.SOFT)
	# The game separates sections with "--" lines; show them as spacing instead.
	info = info.replace("\n--\n", "\n\n").replace("--\n", "\n").strip_edges()
	if info != _info.text:
		_info.text = info
		_info_scroll.scroll_vertical = 0
	(_buttons["TOGGLE_FAVORITE"] as ActionButton).set_label("Unfavorite" if bool(detail.get("fav", false)) else "Favorite")


## A small labeled value, e.g. `WEIGHT 1.10 kg`.
func _fact(title: String, value: String) -> Control:
	var box := PanelContainer.new()
	var sb := Slate.box(Slate.RAISED, 0, Slate.BORDER, 0)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	box.add_theme_stylebox_override("panel", sb)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", -2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(col)
	col.add_child(Slate.label(title.to_upper(), 9, Slate.FAINT, Slate.mono()))
	col.add_child(Slate.label(value, 12, Slate.TEXT, Slate.mono()))
	return box


func _update_hints(keys: Dictionary, typing: bool) -> void:
	if typing:
		_cockpit.set_hints([["Enter", "done"], ["Esc", "cancel"]])
		return
	var hints := [["↑↓", "move"]]
	if _multi:
		hints.append([Slate.key_name(String(keys.get("RIGHT", "→"))), "mark"])
		hints.append(["0-9", "amount"])
	elif _visible_panes() > 1:
		hints.append(["←→", "switch list"])
	hints.append([Slate.key_name(String(keys.get("CONFIRM", "Enter"))), _confirm.get_label().to_lower()])
	if keys.has("INVENTORY_FILTER"):
		hints.append([Slate.key_name(String(keys.get("INVENTORY_FILTER", "/"))), "search"])
	if _keyed:
		hints.append(["a-z", "pick by letter"])
	hints.append([Slate.key_name(String(keys.get("QUIT", "Esc"))), "back"])
	_cockpit.set_hints(hints)


## Weight and volume carried, as bars against the limit: under the map strip, or in a module of
## their own when the window has no room for the strip.
func _update_load() -> void:
	if _cockpit == null or _msg.is_empty():
		return
	var stats: Array = _msg.get("stats", [])
	var kind := "hand" if stats.is_empty() else "load"
	if kind != _foot_kind:
		_foot_kind = kind
		if kind == "load":
			_load_foot = VBoxContainer.new()
			_load_foot.add_theme_constant_override("separation", 6)
			_load_foot.alignment = BoxContainer.ALIGNMENT_CENTER
			_cockpit.set_foot("Load", _load_foot)
		else:
			_load_foot = null
			_cockpit.show_in_hand()
	_load_module.visible = kind == "load" and not _cockpit.has_foot()
	if kind != "load":
		return
	for box in [_load_foot, _load_inline]:
		for c in box.get_children():
			box.remove_child(c)
			c.queue_free()
		for s in stats:
			box.add_child(_stat(String(s.get("label", "")), s.get("current", []), s.get("limit", [])))


func _stat(label: String, current: Array, limit: Array) -> Control:
	var parts := label.trim_suffix(":").split("(")
	var name := parts[0].strip_edges()
	var unit := parts[1].trim_suffix(")").strip_edges() if parts.size() > 1 else ""
	var now := Slate.plain(current).strip_edges()
	var most := Slate.plain(limit).strip_edges()
	var ratio := 0.0
	if most.is_valid_float() and float(most) > 0.0 and now.is_valid_float():
		ratio = float(now) / float(most)
	var color := Slate.CYAN
	if ratio > 1.0:
		color = Slate.DANGER
	elif ratio > 0.85:
		color = Slate.WARN
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.tooltip_text = "%s carried: %s of %s %s" % [name, now, most, unit]
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	var title := Slate.label(name.to_upper(), 11, Slate.MUTED, Slate.mono())
	title.custom_minimum_size.x = 62
	row.add_child(title)
	var meter := Meter.new()
	meter.ratio = ratio
	meter.color = color
	meter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(meter)
	var value := Slate.rich(11)
	value.autowrap_mode = TextServer.AUTOWRAP_OFF
	value.add_theme_font_override("normal_font", Slate.mono())
	value.text = "%s[color=#%s] / %s %s[/color]" % [Slate.bbcode(current, Slate.TEXT), Slate.MUTED.to_html(false), most, unit]
	row.add_child(value)
	return row


# --- Panes ---------------------------------------------------------------------------------------

func _visible_panes() -> int:
	return _columns.filter(func(c): return bool(c.get("visible", false))).size()


static func _has_cells(rows: Array) -> bool:
	return rows.any(func(r): return not r.has("cat") and not r.get("cells", []).is_empty())


func _build_panes() -> void:
	# Where each list stood, to put it back when the rebuilt list is the same one with a
	# change in it (an item was marked or is gone) and not start at the top again.
	var kept := []
	for old in _pane_lists:
		kept.append(null if old == null else [old[1], old[2], (old[0] as ScrollContainer).scroll_vertical])
	_pane_lists.clear()
	for c in _panes.get_children():
		_panes.remove_child(c)
		c.queue_free()
	_cells.clear()
	_rows.clear()
	_pane_modules.clear()
	_multi = false
	_keyed = false
	_search = null
	var first := true
	for p in _columns.size():
		var column: Dictionary = _columns[p]
		if not bool(column.get("visible", false)):
			_pane_modules.append(null)
			_pane_lists.append(null)
			continue
		var role := String(column.get("role", ""))
		var rows: Array = column.get("rows", [])
		var multi := bool(column.get("multi", false))
		_multi = _multi or multi
		_keyed = _keyed or rows.any(func(r): return String(r.get("key", "")) != "")
		var can_grid := role in ["carried", "nearby"] and not _has_cells(rows)
		var as_grid := can_grid and grid_view
		var module := Hud.Module.new(String(PANE_TITLES.get(role, role.capitalize())))
		module.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# Grids want the room; what you chose only repeats names from the other lists.
		module.size_flags_stretch_ratio = 1.5 if as_grid else 0.8 if role == "selection" else 1.0
		var items := rows.filter(func(r): return not r.has("cat")).size()
		module.set_note("%d worn" % items if role == "worn" else "1 item" if items == 1 else "%d items" % items)
		if first:
			first = false
			if can_grid:
				module.head.add_child(_view_switch())
			_build_search(module.head)
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var list := VBoxContainer.new()
		list.add_theme_constant_override("separation", 3)
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.mouse_filter = Control.MOUSE_FILTER_IGNORE
		scroll.add_child(list)
		module.set_body(scroll, 12, 10)
		scroll.set_drag_forwarding(Callable(), _can_drop_pane.bind(p), _drop_pane.bind(p))
		if as_grid:
			_fill_grid(list, p, rows, multi)
		else:
			_fill_rows(list, p, rows, multi)
		if items == 0:
			var empty := Slate.label("Nothing here.", 13, Slate.FAINT)
			empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			empty.custom_minimum_size.y = 80
			empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			list.add_child(empty)
		_panes.add_child(module)
		_pane_modules.append(module)
		var names := PackedStringArray(rows.map(func(r): return Slate.plain(r.get("text", []))))
		_pane_lists.append([scroll, names, as_grid])
		if p < kept.size() and kept[p] != null and kept[p][1] == as_grid and _same_list(kept[p][0], names):
			_restore_scroll(scroll, int(kept[p][2]))
	if _panes.get_child_count() == 0:
		var module := Hud.Module.new("Items")
		module.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var empty := Slate.label("Nothing to show here.", 14, Slate.FAINT)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
		module.set_body(empty)
		_panes.add_child(module)


## Whether two lists of row names are the same list with some changes: most names are in both.
static func _same_list(before: PackedStringArray, after: PackedStringArray) -> bool:
	if before.is_empty() or after.is_empty():
		return false
	var had := {}
	for n in before:
		had[n] = true
	var shared := 0
	for n in after:
		if had.has(n):
			shared += 1
	return shared * 10 >= maxi(before.size(), after.size()) * 6


## Puts a rebuilt list where it stood. The bar is given the room first, so that the list does
## not show its top for a frame while it is laid out.
func _restore_scroll(scroll: ScrollContainer, offset: int) -> void:
	if offset <= 0:
		return
	var bar := scroll.get_v_scroll_bar()
	bar.max_value = maxf(bar.max_value, offset + bar.page + 1)
	scroll.scroll_vertical = offset
	await get_tree().process_frame
	if is_instance_valid(scroll):
		scroll.scroll_vertical = offset


## Slots or rows, for plain item lists: two small buttons with the current one lit.
func _view_switch() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for choice in [[true, "Slots", "Show items as slots"], [false, "Rows", "Show items as rows with their names and weight"]]:
		var on: bool = choice[0] == grid_view
		var b := Button.new()
		b.text = String(choice[1]).to_upper()
		b.tooltip_text = String(choice[2])
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_default_cursor_shape = Control.CURSOR_ARROW if on else Control.CURSOR_POINTING_HAND
		b.add_theme_font_override("font", Slate.mono())
		b.add_theme_font_size_override("font_size", Slate.fs(10))
		var sb := Slate.box(Slate.CYAN if on else Color(0, 0, 0, 0), 0, Color(Slate.CYAN, 0.9 if on else 0.4), 1)
		sb.content_margin_left = 7
		sb.content_margin_right = 7
		sb.content_margin_top = 1
		sb.content_margin_bottom = 1
		var hot := sb.duplicate() as StyleBoxFlat
		if not on:
			hot.bg_color = Color(Slate.CYAN, 0.15)
		for state in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(state, sb if state == "normal" else hot)
		for state in ["font_color", "font_hover_color", "font_pressed_color"]:
			b.add_theme_color_override(state, Slate.ACCENT_TEXT if on else Slate.SOFT)
		var want: bool = choice[0]
		b.pressed.connect(func():
			if grid_view != want:
				grid_view = want
				_save_settings()
				set_entries(_columns))
		row.add_child(b)
	return row


func _category_head(list: VBoxContainer, name: String, cells: Array, widths: Array) -> void:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title := Slate.label(name.to_upper(), 12, Slate.CYAN, Slate.spaced(Slate.heading(), 2))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	row.add_child(title)
	var titles := HBoxContainer.new()
	titles.add_theme_constant_override("separation", CELL_GAP)
	titles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(titles)
	for i in cells.size():
		var c := Slate.label(String(cells[i]).strip_edges().to_upper(), 9, Slate.MUTED, Slate.mono())
		c.custom_minimum_size.x = widths[i] if i < widths.size() else MIN_CELL_WIDTH
		c.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		c.clip_text = true
		c.tooltip_text = String(cells[i]).strip_edges()
		c.mouse_filter = Control.MOUSE_FILTER_PASS
		titles.add_child(c)
	var box := MarginContainer.new()
	box.add_theme_constant_override("margin_right", 10)
	box.add_theme_constant_override("margin_top", 0 if list.get_child_count() == 0 else 10)
	box.add_theme_constant_override("margin_bottom", 3)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(row)
	list.add_child(box)


func _fill_grid(list: VBoxContainer, p: int, rows: Array, multi: bool) -> void:
	var flow: HFlowContainer = null
	for row_data in rows:
		if row_data.has("cat"):
			_category_head(list, String(row_data["cat"]), [], [])
			flow = null
			continue
		if flow == null:
			flow = HFlowContainer.new()
			flow.add_theme_constant_override("h_separation", SLOT_GAP)
			flow.add_theme_constant_override("v_separation", SLOT_GAP)
			flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
			list.add_child(flow)
		var index := int(row_data.get("i", -1))
		var slot := GridSlot.new(SLOT)
		slot.setup(row_data, multi)
		_connect_cell(slot, Vector2i(p, index), multi, row_data)
		flow.add_child(slot)


func _fill_rows(list: VBoxContainer, p: int, rows: Array, multi: bool) -> void:
	var keyed: bool = rows.any(func(r): return String(r.get("key", "")) != "")
	var widths := _cell_widths(rows)
	for row_data in rows:
		if row_data.has("cat"):
			_category_head(list, String(row_data["cat"]), row_data.get("cells", []), widths)
			continue
		var index := int(row_data.get("i", -1))
		var row := InvRow.new()
		row.setup(row_data, multi, keyed, widths)
		_connect_cell(row, Vector2i(p, index), multi, row_data)
		list.add_child(row)


## A click selects; a second click, a double click or a right click does what Enter does here:
## in lists where items are marked it marks, everywhere else it chooses the item.
func _connect_cell(cell, at: Vector2i, multi: bool, row: Dictionary) -> void:
	var code := at.x * STRIDE + at.y
	_rows[at] = row
	(cell as Control).set_drag_forwarding(_drag_from.bind(at), _can_drop_pane.bind(at.x), _drop_pane.bind(at.x))
	var act := "RIGHT" if multi else "CONFIRM"
	cell.clicked.connect(func():
		if at != _cursor:
			Bridge.pick(view_id, code, ""))
	cell.activated.connect(func(): Bridge.pick(view_id, code, act))
	_cells[at] = cell


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
				w = Slate.mono().get_string_size(String(cells[i]).strip_edges().to_upper(),
						HORIZONTAL_ALIGNMENT_LEFT, -1, Slate.fs(9)).x
			else:
				w = InvRow.cell_text_width(Slate.plain(cells[i]).strip_edges())
			if i >= widths.size():
				widths.append(MIN_CELL_WIDTH)
			widths[i] = clampf(ceilf(w) + 4, widths[i], MAX_CELL_WIDTH)
	return widths


# --- Dragging items ------------------------------------------------------------------------------

func _build_drop_glow() -> void:
	_drop_glow = PanelContainer.new()
	var sb := Slate.box(Color(Slate.ACCENT, 0.10), 4, Slate.ACCENT, 2)
	sb.set_content_margin_all(10)
	_drop_glow.add_theme_stylebox_override("panel", sb)
	_drop_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drop_glow.visible = false
	_drop_glow.top_level = true
	_drop_word = Slate.label("", 14, Slate.ACCENT_TEXT, Slate.spaced(Slate.heavy(), 2))
	_drop_word.uppercase = true
	var chip := PanelContainer.new()
	var chip_box := Slate.box(Slate.ACCENT, 2, Slate.ACCENT, 0)
	chip_box.content_margin_left = 10
	chip_box.content_margin_right = 10
	chip_box.content_margin_top = 4
	chip_box.content_margin_bottom = 4
	chip.add_theme_stylebox_override("panel", chip_box)
	chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	chip.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(_drop_word)
	_drop_glow.add_child(chip)
	add_child(_drop_glow)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and _drop_glow != null:
		_drop_glow.visible = false


func _process(_delta: float) -> void:
	# Leaving a place to drop for one that takes nothing hides its glow.
	if _drop_glow != null and _drop_glow.visible and (not is_instance_valid(_glow_area)
			or not _glow_area.get_global_rect().has_point(_glow_area.get_global_mouse_position())):
		_drop_glow.visible = false


func _role(p: int) -> String:
	return String(_columns[p].get("role", "")) if p >= 0 and p < _columns.size() else ""


func _drag_from(_at_pos: Vector2, at: Vector2i) -> Variant:
	var role := _role(at.x)
	if not _draggable or role not in ["carried", "worn"] or not _rows.has(at):
		return null
	var row: Dictionary = _rows[at]
	if not bool(row.get("enabled", true)):
		return null
	var ghost := ItemSlot.new(SLOT)
	ghost.set_item(String(row.get("type", "")), String(row.get("sym", "?")), Slate.curses(String(row.get("sym_color", "c_white"))))
	ghost.selected = true
	ghost.modulate.a = 0.85
	# The picture sits under the pointer's tip, not to its lower right.
	var holder := Control.new()
	holder.add_child(ghost)
	ghost.position = -Vector2(SLOT, SLOT) / 2
	set_drag_preview(holder)
	return {"inv_cell": at, "from": role}


## What dropping `data` on `target` does: a verb, or "" when it does nothing there.
func _verb_for(target: String, data: Variant) -> String:
	if not (data is Dictionary and data.has("inv_cell")):
		return ""
	var from := String(data["from"])
	match target:
		"worn", "WEAR":
			return "wear" if from != "worn" else ""
		"carried":
			return "take_off" if from == "worn" else ""
		"WIELD":
			return "wield"
		"map":
			return "drop"
	return ""


func _can_drop_pane(at_pos: Vector2, data: Variant, p: int) -> bool:
	var area: Control = _pane_modules[p] if p < _pane_modules.size() and _pane_modules[p] != null else null
	return area != null and _can_drop(at_pos, data, _role(p), area)


func _drop_pane(at_pos: Vector2, data: Variant, p: int) -> void:
	_drop(at_pos, data, _role(p))


func _can_drop(_at_pos: Vector2, data: Variant, target: String, area: Control) -> bool:
	var verb := _verb_for(target, data)
	if verb == "":
		_drop_glow.visible = false
		return false
	_drop_word.text = DROP_WORDS[verb]
	_glow_area = area
	var rect := area.get_global_rect()
	# On a button the item under the pointer would hide the word, so the glow grows upward to
	# show it above the button.
	var chip_h := _drop_word.get_combined_minimum_size().y + 18
	if rect.size.y < chip_h * 2.5:
		rect = rect.grow_side(SIDE_TOP, chip_h)
	_drop_glow.position = rect.position
	_drop_glow.size = rect.size
	_drop_glow.visible = true
	return true


func _drop(_at_pos: Vector2, data: Variant, target: String) -> void:
	_drop_glow.visible = false
	var verb := _verb_for(target, data)
	if verb != "":
		var at: Vector2i = data["inv_cell"]
		Bridge.drag_item(view_id, at.x * STRIDE + at.y, verb)


func _apply_cursor(force_scroll: bool) -> void:
	var active := int(_msg.get("active", 0))
	var cursors: Array = _msg.get("cursors", [])
	var cursor := Vector2i(active, int(cursors[active]) if active < cursors.size() else -1)
	var moved := cursor != _cursor
	_cursor = cursor
	for at in _cells:
		var p: int = at.x
		var on: bool = p < cursors.size() and at.y == int(cursors[p])
		_cells[at].set_selected(on, p == active)
	for p in _pane_modules.size():
		if _pane_modules[p] != null:
			var module: Hud.Module = _pane_modules[p]
			var role := String(_columns[p].get("role", ""))
			module.set_title(String(PANE_TITLES.get(role, role.capitalize())), Slate.ACCENT if p == active else Slate.CYAN)
	if (moved or force_scroll) and _cells.has(_cursor):
		_scroll_to(_cells[_cursor])


func _scroll_to(cell: Control) -> void:
	# Cells lay out on the next frame; wait so the scroll target is right.
	await get_tree().process_frame
	if not is_instance_valid(cell):
		return
	var node := cell.get_parent()
	while node != null and not node is ScrollContainer:
		node = node.get_parent()
	if node != null:
		(node as ScrollContainer).ensure_control_visible(cell)
		(node as ScrollContainer).scroll_horizontal = 0


## An item in a grid: its sprite on a steel plate with its letter, count and marks. Hover shows
## its name, weight and volume, and why it can't be chosen when it can't.
class GridSlot extends ItemSlot:
	signal clicked
	signal activated
	var _on_release := ""

	var _enabled := true
	var _cursor := false

	func _init(side := 64.0) -> void:
		super(side)

	func setup(row: Dictionary, multi: bool) -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		_enabled = bool(row.get("enabled", true))
		set_item(String(row.get("type", "")), String(row.get("sym", "?")), Slate.curses(String(row.get("sym_color", "c_white"))))
		tag = String(row.get("key", ""))
		count = String(row.get("count", ""))
		dimmed = not _enabled or row.has("denial")
		star = bool(row.get("fav", false))
		if multi and int(row.get("chosen", 0)) > 0:
			mark = "ok" if int(row.get("chosen", 0)) >= int(row.get("avail", 1)) else str(int(row.get("chosen", 0)))
		if _enabled:
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var lines := PackedStringArray([Slate.plain(row.get("text", [])).replace(char(0xa0), " ").strip_edges()])
		lines.append("%s  ·  %s" % [String(row.get("weight", "")), String(row.get("volume", ""))])
		var denial := Slate.plain(row.get("denial", [])).strip_edges()
		if denial != "":
			lines.append(denial)
		tooltip_text = "\n".join(lines)

	func set_selected(on: bool, active: bool) -> void:
		_cursor = on and active
		if selected != _cursor or soft != (on and not active):
			selected = _cursor
			soft = on and not active
			refresh()

	func _gui_input(event: InputEvent) -> void:
		# A click chooses or acts on release, so a press can start dragging the item instead
		# (choosing it on the press would rebuild the list under the pointer).
		if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var on_release := _on_release
			_on_release = ""
			if on_release != "" and not get_viewport().gui_is_dragging():
				emit_signal(on_release)
		if event is InputEventMouseButton and event.pressed:
			_on_release = ""
			if event.button_index == MOUSE_BUTTON_LEFT:
				accept_event()
				if not _enabled:
					return
				if event.double_click:
					activated.emit()
				elif _cursor:
					_on_release = "activated"
				else:
					_on_release = "clicked"
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				accept_event()
				if _enabled:
					activated.emit()


## An item as a row: mark box, slot, letter, name, the list's extra columns or the weight.
class InvRow extends PanelContainer:
	signal clicked
	signal activated
	var _on_release := ""

	var _enabled := true
	var _selected := false
	var _active := false
	var _hover := false
	var _slot: ItemSlot

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

		_slot = ItemSlot.new(32)
		_slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_slot.set_item(String(row.get("type", "")), String(row.get("sym", "?")), Slate.curses(String(row.get("sym_color", "c_white"))))
		line.add_child(_slot)

		if keyed:
			var key := String(row.get("key", ""))
			var holder := CenterContainer.new()
			holder.custom_minimum_size.x = 22
			holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var chip := Slate.key_chip(key, 11)
			if key != "":
				(chip.get_child(0) as Label).add_theme_color_override("font_color",
						Slate.curses(String(row.get("key_color", "")), Slate.CYAN))
			holder.add_child(chip)
			line.add_child(holder)

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
			var weight := Slate.label(String(row.get("weight", "")), 12, Slate.MUTED, Slate.mono())
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
		box.add_theme_stylebox_override("panel", Slate.box(Slate.ACCENT if on else Color(0, 0, 0, 0), 0,
				Slate.ACCENT if on else Slate.BORDER_STRONG, 0 if on else 1))
		box.custom_minimum_size = Vector2(20, 20)
		box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		box.mouse_filter = Control.MOUSE_FILTER_STOP
		box.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		box.tooltip_text = "Mark or unmark"
		if on and chosen < avail:
			var count := Slate.label(str(chosen), 11, Slate.ACCENT_TEXT, Slate.mono())
			count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			box.add_child(count)
		elif on:
			box.add_child(Slate.icon_rect("check", 14, Slate.ACCENT_TEXT))
		box.gui_input.connect(func(e: InputEvent):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				box.accept_event()
				activated.emit())
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
		return Slate.mono().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, Slate.fs(12)).x

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
			_slot.selected = on and active
			_slot.refresh()
			_restyle()

	func _restyle() -> void:
		var bg := Color(0, 0, 0, 0)
		if _selected and _active:
			bg = Color(Slate.ACCENT, 0.10)
		elif _selected or (_hover and _enabled):
			bg = Color(Slate.CYAN, 0.08)
		var sb := Slate.box(bg, 0, Slate.BORDER, 0)
		if _selected:
			# A yellow edge marks the item the keys act on; cyan, a list's resting cursor.
			sb.border_width_left = 3
			sb.border_color = Slate.ACCENT if _active else Color(Slate.CYAN, 0.6)
		sb.content_margin_left = 8
		sb.content_margin_right = 10
		sb.content_margin_top = 3
		sb.content_margin_bottom = 3
		add_theme_stylebox_override("panel", sb)

	func _gui_input(event: InputEvent) -> void:
		# A click chooses or acts on release, so a press can start dragging the item instead
		# (choosing it on the press would rebuild the list under the pointer).
		if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var on_release := _on_release
			_on_release = ""
			if on_release != "" and not get_viewport().gui_is_dragging():
				emit_signal(on_release)
		if event is InputEventMouseButton and event.pressed:
			_on_release = ""
			if event.button_index == MOUSE_BUTTON_LEFT:
				accept_event()
				if not _enabled:
					return
				if event.double_click:
					activated.emit()
				elif (_selected and _active):
					_on_release = "activated"
				else:
					_on_release = "clicked"
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				accept_event()
				if _enabled:
					activated.emit()


## A bar of small cells, filled up to `ratio`.
class Meter extends Control:
	var ratio := 0.0
	var color := Slate.CYAN

	func _init() -> void:
		custom_minimum_size = Vector2(60, 8)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var cells := maxi(int(size.x / 10.0), 4)
		var width := (size.x - (cells - 1) * 2.0) / cells
		var lit := ceili(clampf(ratio, 0.0, 1.0) * cells)
		for i in cells:
			draw_rect(Rect2(i * (width + 2.0), 0, width, size.y), color if i < lit else Slate.TRACK)
