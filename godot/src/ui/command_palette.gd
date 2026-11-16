extends Control
## Command search (Ctrl+K): type a few letters of any action of the main game view and press
## Enter to run it. Empty, it lists what applies where the player stands, then recent commands,
## then everything by group. Each row shows the action's key, so it also teaches the keyboard.
## While it is open, keys go to its search field instead of the game.

const RECENT_PATH := "user://commands.cfg"
const RECENT_MAX := 8
const ROW_HEIGHT := 40
const VISIBLE_ROWS := 10
const GROUP_ICONS := {
	"Look": "eye", "Interact": "hand", "Inventory": "backpack", "Combat": "sword", "Craft": "hammer",
	"Info": "id-card", "Game": "play", "Settings": "settings", "Help": "circle-question-mark",
	"Debug": "bug",
}

## [id, name, key, group] for every command, as the game sent them.
var _commands := []
var _suggested := []
var _recent := []
## Rows shown now: {"cmd": [...], "tag": String}.
var _shown := []
var _selected := 0
var _field: LineEdit
var _list: VBoxContainer
var _scroll: ScrollContainer
var _empty: Label


func _ready() -> void:
	add_to_group("godot_modal")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var scrim := ColorRect.new()
	scrim.color = Slate.SCRIM
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scrim)
	gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			queue_free())

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", Slate.card_box(18, 14))
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.anchor_left = 0.5
	card.anchor_right = 0.5
	card.offset_left = -330
	card.offset_right = 330
	card.anchor_top = 0.14
	card.anchor_bottom = 0.14
	add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	card.add_child(col)

	var search := PanelContainer.new()
	var box := Slate.box(Color(1, 1, 1, 0.05), 12, Slate.ACCENT, 1)
	box.content_margin_left = 12
	box.content_margin_right = 10
	search.add_theme_stylebox_override("panel", box)
	col.add_child(search)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	search.add_child(row)
	row.add_child(Slate.icon_rect("search", 18, Slate.MUTED))
	_field = LineEdit.new()
	_field.placeholder_text = "Find a command…"
	_field.flat = true
	for state in ["normal", "focus", "read_only"]:
		_field.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_field.custom_minimum_size.y = 42
	_field.add_theme_font_size_override("font_size", 16)
	_field.add_theme_color_override("font_placeholder_color", Slate.FAINT)
	_field.add_theme_color_override("caret_color", Slate.ACCENT)
	_field.text_changed.connect(func(_t): _filter())
	row.add_child(_field)
	row.add_child(Slate.key_chip("Esc"))

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size.y = ROW_HEIGHT * VISIBLE_ROWS
	col.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 0)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)
	_empty = Slate.label("Loading commands…", 14, Slate.MUTED)
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_list.add_child(_empty)

	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 14)
	col.add_child(foot)
	for hint in [["↑ ↓", "choose"], ["Enter", "run"], ["Esc", "close"]]:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 6)
		h.add_child(Slate.key_chip(hint[0]))
		h.add_child(Slate.label(hint[1], 12, Slate.FAINT))
		foot.add_child(h)

	var cfg := ConfigFile.new()
	if cfg.load(RECENT_PATH) == OK:
		_recent = cfg.get_value("commands", "recent", [])
	Bridge.commands_received.connect(_on_commands)
	Bridge.send({"t": "commands"})
	_field.grab_focus.call_deferred()


func _on_commands(list: Array, suggested: Array) -> void:
	_commands = list
	_suggested = suggested
	_filter()


## Arrows, Enter and Escape drive the list; every other key types into the field.
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	match event.keycode:
		KEY_ESCAPE:
			queue_free()
		KEY_UP:
			_select(_selected - 1)
		KEY_DOWN:
			_select(_selected + 1)
		KEY_PAGEUP:
			_select(_selected - VISIBLE_ROWS)
		KEY_PAGEDOWN:
			_select(_selected + VISIBLE_ROWS)
		KEY_ENTER, KEY_KP_ENTER:
			if _selected < _shown.size():
				_run(_shown[_selected]["cmd"])
		_:
			return
	get_viewport().set_input_as_handled()


func _filter() -> void:
	var query := _field.text.strip_edges().to_lower()
	_shown = []
	if query == "":
		var by_id := {}
		for cmd in _commands:
			by_id[cmd[0]] = cmd
		var seen := {}
		for id in _suggested:
			if by_id.has(id) and not seen.has(id):
				seen[id] = true
				_shown.append({"cmd": by_id[id], "tag": "Right here"})
		for id in _recent:
			if by_id.has(id) and not seen.has(id):
				seen[id] = true
				_shown.append({"cmd": by_id[id], "tag": "Recent"})
		for cmd in _commands:
			if not seen.has(cmd[0]):
				_shown.append({"cmd": cmd, "tag": cmd[3]})
	else:
		var scored := []
		for cmd in _commands:
			var score := _score(query, cmd)
			if score > 0:
				if cmd[0] in _suggested:
					score += 30
				if cmd[0] in _recent:
					score += 20 - _recent.find(cmd[0])
				scored.append([score, cmd])
		scored.sort_custom(func(a, b): return a[0] > b[0])
		for s in scored:
			_shown.append({"cmd": s[1], "tag": s[1][3]})
	_selected = 0
	_build_rows()


## Fuzzy match: every letter of the query in order, best when they start words or run together.
## The key and the group name also match, so "craft" or "&" find what they should.
static func _score(query: String, cmd: Array) -> int:
	var name := String(cmd[1]).to_lower()
	var key := String(cmd[2]).to_lower()
	if key != "" and query == key:
		return 200
	var best := 0
	var at := name.find(query)
	if at >= 0:
		best = 150 - at + (40 if at == 0 or name[at - 1] == " " else 0)
	var pos := 0
	var run := 0
	var total := 0
	for c in query:
		if c == " ":
			continue
		var found := name.find(c, pos)
		if found < 0:
			total = -1
			break
		var word_start := found == 0 or name[found - 1] == " " or name[found - 1] == "("
		total += 10 + (12 if word_start else 0) + (8 if found == pos and run > 0 else 0)
		run = run + 1 if found == pos else 1
		pos = found + 1
	if total > 0:
		best = max(best, total - name.length() / 4)
	if best == 0 and String(cmd[3]).to_lower().begins_with(query):
		best = 5
	return best


func _build_rows() -> void:
	for child in _list.get_children():
		child.queue_free()
	if _shown.is_empty():
		var none := Slate.label("No command matches." if _commands.size() > 0 else "Loading commands…", 14, Slate.MUTED)
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		none.custom_minimum_size.y = ROW_HEIGHT
		_list.add_child(none)
		return
	for i in _shown.size():
		_list.add_child(_make_row(i))
	_paint()


func _make_row(index: int) -> Control:
	var cmd: Array = _shown[index]["cmd"]
	var tag: String = _shown[index]["tag"]
	var row := PanelContainer.new()
	row.custom_minimum_size.y = ROW_HEIGHT
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	row.mouse_entered.connect(func(): _select(index, false))
	row.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_run(cmd))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	row.add_child(line)
	var accent := Slate.ACCENT if tag == "Right here" else Slate.MUTED
	line.add_child(Slate.icon_rect(GROUP_ICONS.get(cmd[3], "circle-dot"), 16, accent))
	var text := String(cmd[1])
	var name := Slate.label(text.left(1).to_upper() + text.substr(1), 15, Slate.TEXT)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(name)
	var group := Slate.label(tag, 12, Slate.ACCENT if tag == "Right here" else Slate.FAINT)
	group.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(group)
	var key := Slate.key_chip(Slate.key_name(cmd[2]), 12)
	key.custom_minimum_size.x = 56
	line.add_child(key)
	return row


func _paint() -> void:
	var rows := _list.get_children()
	for i in rows.size():
		var hot := i == _selected
		var sb := Slate.box(Color(1, 1, 1, 0.09) if hot else Color(0, 0, 0, 0), 10,
				Slate.BORDER_STRONG if hot else Slate.BORDER, 1 if hot else 0)
		sb.content_margin_left = 12
		sb.content_margin_right = 8
		rows[i].add_theme_stylebox_override("panel", sb)


func _select(index: int, scroll := true) -> void:
	if _shown.is_empty():
		return
	_selected = clampi(index, 0, _shown.size() - 1)
	_paint()
	if scroll:
		var top := _selected * ROW_HEIGHT
		if top < _scroll.scroll_vertical:
			_scroll.scroll_vertical = top
		elif top + ROW_HEIGHT > _scroll.scroll_vertical + _scroll.size.y:
			_scroll.scroll_vertical = top + ROW_HEIGHT - int(_scroll.size.y)


func _run(cmd: Array) -> void:
	_recent.erase(cmd[0])
	_recent.push_front(cmd[0])
	_recent = _recent.slice(0, RECENT_MAX)
	var cfg := ConfigFile.new()
	cfg.set_value("commands", "recent", _recent)
	cfg.save(RECENT_PATH)
	Bridge.send({"t": "run", "id": cmd[0]})
	queue_free()
