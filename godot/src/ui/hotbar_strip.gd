extends PanelContainer
## The item hotbar on the map (see hotbar.gd): nine slots showing each pinned item's symbol and
## how many you carry. Click or Alt+number to use, right-click to clear, drag one slot onto
## another to swap them.

const SLOT := 46

var _slots: Array = []
var _hud: Array = []


func _ready() -> void:
	var sb := Slate.card_box(14, 6)
	add_theme_stylebox_override("panel", sb)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	add_child(row)
	for i in Hotbar.SIZE:
		var slot := Slot.new(i)
		row.add_child(slot)
		_slots.append(slot)
	Hotbar.changed.connect(_refresh)
	_refresh()


## The HUD's `hotbar` list: per slot null or {type, name, count, sym, color, wielded}.
func apply(hotbar: Array) -> void:
	_hud = hotbar
	_refresh()


func _refresh() -> void:
	for i in _slots.size():
		var info = _hud[i] if i < _hud.size() else null
		# Until the game reports a newly pinned slot, show it as pinned but unknown.
		if info == null and Hotbar.slots[i] != "":
			info = {"type": Hotbar.slots[i], "name": Hotbar.slots[i], "count": 0, "sym": "?"}
		if info != null and String(info.get("type", "")) != Hotbar.slots[i]:
			info = null
		(_slots[i] as Slot).show_item(info)


class Slot extends PanelContainer:
	var index := 0
	var _glyph: Label
	var _count: Label
	var _number: Label
	var _filled := false
	var _wielded := false
	var _hover := false

	func _init(i: int) -> void:
		index = i
		custom_minimum_size = Vector2(SLOT, SLOT)
		mouse_filter = Control.MOUSE_FILTER_STOP
		var stack := Control.new()
		stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(stack)
		_glyph = Slate.label("", 22, Slate.TEXT, Slate.mono_bold())
		_glyph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		stack.add_child(_glyph)
		_number = Slate.label(str(i + 1), 10, Slate.FAINT, Slate.mono_bold())
		_number.position = Vector2(4, 1)
		stack.add_child(_number)
		_count = Slate.label("", 11, Slate.SOFT, Slate.mono_bold())
		_count.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_count.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		_count.offset_right = -4
		_count.offset_bottom = -1
		stack.add_child(_count)
		mouse_entered.connect(func():
			_hover = true
			_restyle())
		mouse_exited.connect(func():
			_hover = false
			_restyle())
		gui_input.connect(_on_input)
		_restyle()

	func show_item(info) -> void:
		_filled = info != null
		if not _filled:
			_glyph.text = ""
			_count.text = ""
			_wielded = false
			tooltip_text = "Empty slot %d. Pin an item from its item card (Alt+%d there)." % [index + 1, index + 1]
			mouse_default_cursor_shape = Control.CURSOR_ARROW
		else:
			var count := int(info.get("count", 0))
			_glyph.text = String(info.get("sym", "?"))
			_glyph.add_theme_color_override("font_color", Slate.curses(String(info.get("color", "c_white"))))
			_glyph.modulate.a = 1.0 if count > 0 else 0.35
			_count.text = str(count) if count != 1 else ""
			_count.add_theme_color_override("font_color", Slate.SOFT if count > 0 else Slate.DANGER)
			_wielded = bool(info.get("wielded", false))
			var name := String(info.get("name", ""))
			tooltip_text = "%s%s\nAlt+%d or click to use · right-click to remove · drag to move" % [
				name, "" if count > 0 else " (none carried)", index + 1]
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_restyle()

	func _restyle() -> void:
		var bg := Color(1, 1, 1, 0.10 if _hover and _filled else 0.05 if _filled else 0.02)
		var border := Slate.ACCENT if _wielded else Slate.BORDER_STRONG if _hover else Slate.BORDER
		var sb := Slate.box(bg, 10, border, 1)
		sb.set_content_margin_all(0)
		add_theme_stylebox_override("panel", sb)
		_number.add_theme_color_override("font_color", Slate.MUTED if _filled else Slate.FAINT)

	func _on_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_RIGHT and _filled:
				Hotbar.clear(index)
			accept_event()
		elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			# A press and release on the same slot uses it; a drag ends in _drop_data elsewhere.
			if _filled and get_global_rect().has_point(get_global_mouse_position()):
				Hotbar.use(index)
			accept_event()

	func _get_drag_data(_at: Vector2) -> Variant:
		if not _filled:
			return null
		var ghost := Slate.label(_glyph.text, 22, _glyph.get_theme_color("font_color"), Slate.mono_bold())
		set_drag_preview(ghost)
		return {"hotbar_slot": index}

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return data is Dictionary and data.has("hotbar_slot")

	func _drop_data(_at: Vector2, data: Variant) -> void:
		var from := int(data["hotbar_slot"])
		if from != index:
			Hotbar.swap(from, index)
