extends HBoxContainer
## The item hotbar in the bottom deck (see hotbar.gd): nine slots showing each pinned item's
## sprite and how many you carry. Click or Alt+number to use, right-click to clear, drag one
## slot onto another to swap them.

var _slots: Array = []
var _hud: Array = []


func _init(side := 78.0, gap := 6) -> void:
	add_theme_constant_override("separation", gap)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in Hotbar.SIZE:
		var slot := Slot.new(i, side)
		add_child(slot)
		_slots.append(slot)


func _ready() -> void:
	Hotbar.changed.connect(_refresh)
	_refresh()


func set_side(side: float) -> void:
	for slot in _slots:
		(slot as Control).custom_minimum_size = Vector2(side, side)


## The HUD's `hotbar` list: per slot null or {type, name, count, sym, color, wielded}.
func apply(hotbar: Array) -> void:
	if hotbar == _hud:
		return
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


class Slot extends ItemSlot:
	var index := 0

	func _init(i: int, side: float) -> void:
		super(side)
		index = i
		tag = str(i + 1)
		mouse_filter = Control.MOUSE_FILTER_STOP
		gui_input.connect(_on_input)

	func show_item(info) -> void:
		if info == null:
			clear()
			tooltip_text = "Empty slot %d. Pin an item from its item card (Alt+%d there)." % [index + 1, index + 1]
			mouse_default_cursor_shape = Control.CURSOR_ARROW
			return
		var carried := int(info.get("count", 0))
		selected = bool(info.get("wielded", false))
		dimmed = carried <= 0
		count = "x%d" % carried if carried != 1 else ""
		count_color = Slate.TEXT if carried > 0 else Slate.DANGER
		set_item(String(info.get("type", "")), String(info.get("sym", "?")),
				Slate.curses(String(info.get("color", "c_white"))))
		tooltip_text = "%s%s\nAlt+%d or click: use  ·  right-click: remove  ·  drag: move" % [
			String(info.get("name", "")), "" if carried > 0 else " (none carried)", index + 1]
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	func _on_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_RIGHT and filled:
				Hotbar.clear(index)
			accept_event()
		elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			# A press and release on the same slot uses it; a drag ends in _drop_data elsewhere.
			if filled and get_global_rect().has_point(get_global_mouse_position()):
				Hotbar.use(index)
			accept_event()

	func _get_drag_data(_at: Vector2) -> Variant:
		if not filled:
			return null
		var ghost := ItemSlot.new(48)
		ghost.set_item(item_type, glyph, glyph_color)
		set_drag_preview(ghost)
		return {"hotbar_slot": index}

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return data is Dictionary and data.has("hotbar_slot")

	func _drop_data(_at: Vector2, data: Variant) -> void:
		var from := int(data["hotbar_slot"])
		if from != index:
			Hotbar.swap(from, index)
