extends Control
## In-game HUD over the map: survivor card, time and place, stats, message log and action dock.
## Rebuilt from the `hud` message the game sends whenever the main view redraws.

const DOCK := [
	["inventory", "Bag", "backpack", "Open your inventory"],
	["craft", "Craft", "hammer", "Craft items"],
	["construct", "Build", "brick-wall", "Build or deconstruct"],
	["pickup", "Pick up", "hand", "Pick up items nearby"],
	["look", "Look", "eye", "Look around"],
	["fire", "Fire", "crosshair", "Fire your weapon"],
	["wait", "Wait", "hourglass", "Wait or rest"],
	["map", "Map", "map", "Open the map"],
	["messages", "Log", "book-open", "Read the message log"],
	["player_data", "Survivor", "user-round", "View your character"],
]

const NEEDS := [
	["thirst", "Thirst"],
	["hunger", "Hunger"],
	["fatigue", "Rest"],
	["body_temp", "Warmth"],
]

var _keys := {}
var _body: BodyView
var _name: Label
var _weapon: RichTextLabel
var _needs := {}
var _stamina: NeedRow
var _chips: HFlowContainer
var _clock_day: Label
var _clock_time: Label
var _weather: RichTextLabel
var _place: Label
var _stats := {}
var _carry: VBoxContainer
var _log: VBoxContainer
var _log_button: Button
var _dock_buttons := {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_survivor_card()
	_build_status_pill()
	_build_stats_card()
	_build_log()
	_build_dock()
	_build_zoom()


# --- Layout --------------------------------------------------------------------------------------

func _card(width: float) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", Slate.card_box())
	card.custom_minimum_size.x = width
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(card)
	return card


func _build_survivor_card() -> void:
	var card := _card(330)
	card.position = Vector2(20, 20)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	card.add_child(col)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	col.add_child(top)
	_body = BodyView.new()
	top.add_child(_body)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 2)
	top.add_child(info)
	_name = Slate.label("", 17, Slate.TEXT, Slate.heavy())
	_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name.max_lines_visible = 2
	info.add_child(_name)
	_weapon = Slate.rich(13)
	_weapon.autowrap_mode = TextServer.AUTOWRAP_OFF
	_weapon.clip_contents = true
	info.add_child(_weapon)

	var needs := VBoxContainer.new()
	needs.add_theme_constant_override("separation", 7)
	info.add_child(_spacer(8))
	info.add_child(needs)
	for need in NEEDS:
		var row := NeedRow.new(need[1])
		needs.add_child(row)
		_needs[need[0]] = row
	_stamina = NeedRow.new("Stamina")
	needs.add_child(_stamina)

	_chips = HFlowContainer.new()
	_chips.add_theme_constant_override("h_separation", 6)
	_chips.add_theme_constant_override("v_separation", 6)
	col.add_child(_chips)


func _build_status_pill() -> void:
	var pill := PanelContainer.new()
	var sb := Slate.card_box(999, 0)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 9
	sb.content_margin_bottom = 9
	pill.add_theme_stylebox_override("panel", sb)
	pill.mouse_filter = Control.MOUSE_FILTER_STOP
	pill.set_anchors_preset(Control.PRESET_CENTER_TOP)
	pill.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pill.position.y = 20
	add_child(pill)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	pill.add_child(row)
	_clock_day = Slate.label("", 14, Slate.TEXT, Slate.bold())
	row.add_child(_clock_day)
	_clock_time = Slate.label("", 14, Slate.ACCENT, Slate.mono_bold())
	row.add_child(_clock_time)
	row.add_child(_divider())
	_weather = Slate.rich(14)
	_weather.autowrap_mode = TextServer.AUTOWRAP_OFF
	_weather.fit_content = true
	_weather.custom_minimum_size.x = 10
	row.add_child(_weather)
	row.add_child(_divider())
	var pin := Slate.icon_rect("map-pin", 16, Slate.MUTED)
	row.add_child(pin)
	_place = Slate.label("", 14, Slate.SOFT)
	row.add_child(_place)


func _build_stats_card() -> void:
	var card := _card(250)
	card.anchor_left = 1.0
	card.anchor_right = 1.0
	card.offset_left = -270
	card.offset_right = -20
	card.offset_top = 20
	card.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	card.add_child(col)

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 6)
	col.add_child(grid)
	for stat in [["str", "STR"], ["dex", "DEX"], ["int", "INT"], ["per", "PER"]]:
		var tile := PanelContainer.new()
		var sb := Slate.box(Color(1, 1, 1, 0.05), 10, Slate.BORDER, 0)
		sb.content_margin_top = 6
		sb.content_margin_bottom = 6
		tile.add_theme_stylebox_override("panel", sb)
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var t := VBoxContainer.new()
		t.add_theme_constant_override("separation", 0)
		tile.add_child(t)
		var value := Slate.label("", 17, Slate.TEXT, Slate.mono_bold())
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		t.add_child(value)
		var name := Slate.label(stat[1], 10, Slate.MUTED, Slate.bold())
		name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		t.add_child(name)
		grid.add_child(tile)
		_stats[stat[0]] = value

	_carry = VBoxContainer.new()
	_carry.add_theme_constant_override("separation", 6)
	col.add_child(_carry)


func _build_log() -> void:
	_log = VBoxContainer.new()
	_log.add_theme_constant_override("separation", 6)
	_log.custom_minimum_size.x = 470
	_log.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_log.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_log.position = Vector2(20, -118)
	_log.alignment = BoxContainer.ALIGNMENT_END
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_log)
	_log_button = Button.new()
	_log_button.focus_mode = Control.FOCUS_NONE
	_log_button.add_theme_font_size_override("font_size", 12)
	_log_button.add_theme_color_override("font_color", Slate.SOFT)
	var sb := Slate.pill_box(Slate.CARD, 12, 5)
	sb.border_color = Slate.BORDER
	sb.set_border_width_all(1)
	_log_button.add_theme_stylebox_override("normal", sb)
	var sbh := sb.duplicate()
	sbh.bg_color = Slate.RAISED
	_log_button.add_theme_stylebox_override("hover", sbh)
	_log_button.add_theme_stylebox_override("pressed", sbh)
	_log_button.pressed.connect(func(): Bridge.run_action("messages"))


func _build_dock() -> void:
	var dock := PanelContainer.new()
	var sb := Slate.card_box(18, 8)
	dock.add_theme_stylebox_override("panel", sb)
	dock.mouse_filter = Control.MOUSE_FILTER_STOP
	dock.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	dock.grow_horizontal = Control.GROW_DIRECTION_BOTH
	dock.grow_vertical = Control.GROW_DIRECTION_BEGIN
	dock.position.y = -20
	add_child(dock)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	dock.add_child(row)
	for entry in DOCK:
		var button := DockButton.new(entry[0], entry[1], entry[2], entry[3])
		row.add_child(button)
		_dock_buttons[entry[0]] = button


func _build_zoom() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	row.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	row.grow_vertical = Control.GROW_DIRECTION_BEGIN
	row.position = Vector2(-20, -20)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	for z in [["zoom_in", "plus", "Zoom in"], ["zoom_out", "minus", "Zoom out"]]:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.icon = Slate.icon(z[1], 18)
		b.tooltip_text = z[2]
		b.custom_minimum_size = Vector2(40, 40)
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var sb := Slate.box(Slate.CARD, 12)
		sb.set_content_margin_all(0)
		b.add_theme_stylebox_override("normal", sb)
		var sbh := sb.duplicate()
		sbh.bg_color = Slate.RAISED
		b.add_theme_stylebox_override("hover", sbh)
		b.add_theme_stylebox_override("pressed", sbh)
		var action: String = z[0]
		b.pressed.connect(func(): Bridge.run_action(action))
		row.add_child(b)


func _spacer(height: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = height
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _divider() -> ColorRect:
	var d := ColorRect.new()
	d.color = Color(1, 1, 1, 0.15)
	d.custom_minimum_size = Vector2(1, 14)
	d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return d


func _chip(text: String, color: Color, tooltip := "") -> PanelContainer:
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", Slate.pill_box(Color(color, 0.16), 10, 4))
	chip.tooltip_text = tooltip
	chip.mouse_filter = Control.MOUSE_FILTER_PASS if tooltip != "" else Control.MOUSE_FILTER_IGNORE
	var l := Slate.label(text, 12, color.lightened(0.15), Slate.bold())
	chip.add_child(l)
	return chip


# --- Updates -------------------------------------------------------------------------------------

func apply(hud: Dictionary) -> void:
	_keys = hud.get("keys", {})
	_body.set_parts(hud.get("body", []))
	_name.text = String(hud.get("name", ""))
	var weapon := Slate.bbcode(hud.get("weapon", []), Slate.MUTED)
	var style := String(hud.get("style", ""))
	if style != "" and style != "No style":
		weapon += "[color=#%s]  ·  %s[/color]" % [Slate.FAINT.to_html(false), style.replace("[", "[lb]")]
	_weapon.text = weapon

	for need in NEEDS:
		var info: Dictionary = hud.get(need[0], {})
		var text := String(info.get("text", ""))
		var color_name := String(info.get("color", "c_white"))
		_needs[need[0]].set_value(text if text != "" else "Fine", Slate.curses(color_name, Slate.GOOD),
				Slate.severity(color_name) if text != "" else 1.0)
	var stamina := float(hud.get("stamina", 0))
	var stamina_max := maxf(float(hud.get("stamina_max", 1)), 1.0)
	_stamina.set_value("%d%%" % roundi(stamina / stamina_max * 100.0), Slate.INFO, stamina / stamina_max)

	_update_chips(hud)
	_update_status(hud)
	for stat in _stats:
		var info: Dictionary = hud.get(stat, {})
		_stats[stat].text = String(info.get("text", "")).strip_edges()
		_stats[stat].add_theme_color_override("font_color", Slate.curses(String(info.get("color", "")), Slate.TEXT))
	_update_carry(hud)
	_update_log(hud.get("messages", []))
	for action in _dock_buttons:
		_dock_buttons[action].set_key(String(_keys.get(action, "")))


func _update_chips(hud: Dictionary) -> void:
	for c in _chips.get_children():
		c.queue_free()
	var pain: Dictionary = hud.get("pain", {})
	if String(pain.get("text", "")).strip_edges() != "":
		_chips.add_child(_chip(String(pain["text"]).strip_edges(), Slate.curses(String(pain.get("color", "")), Slate.DANGER)))
	var morale := int(hud.get("morale", 0))
	var morale_color := Slate.curses(String(hud.get("morale_color", "c_white")), Slate.SOFT)
	_chips.add_child(_chip("Morale %+d" % morale, morale_color, "Mood %s" % String(hud.get("morale_face", ""))))
	_chips.add_child(_chip("Focus %d" % int(hud.get("focus", 0)), Slate.SOFT))
	_chips.add_child(_chip("Speed %d" % int(hud.get("speed", 0)), Slate.SOFT))
	var move: Dictionary = hud.get("move", {})
	var move_names := {"R": "Running", "C": "Crouching", "P": "Prone"}
	var move_text := String(move.get("text", "W"))
	if move_names.has(move_text):
		_chips.add_child(_chip(move_names[move_text], Slate.curses(String(move.get("color", "")), Slate.INFO)))
	if not bool(hud.get("safe_mode", true)):
		_chips.add_child(_chip("Safe mode off", Slate.WARN, "Monsters coming into view won't interrupt you"))
	if bool(hud.get("deaf", false)):
		_chips.add_child(_chip("Deaf", Slate.DANGER))


func _update_status(hud: Dictionary) -> void:
	_clock_day.text = "%s · Day %d" % [String(hud.get("season", "")), int(hud.get("day", 1))]
	var clock := String(hud.get("clock", ""))
	_clock_time.text = clock if clock != "" else String(hud.get("time_approx", ""))
	_clock_time.add_theme_font_override("font", Slate.mono_bold() if clock != "" else Slate.bold())
	var parts := []
	if bool(hud.get("underground", false)):
		parts.append("[color=#%s]Underground[/color]" % Slate.SOFT.to_html(false))
	else:
		var weather: Dictionary = hud.get("weather", {})
		parts.append("[color=#%s]%s[/color]" % [Slate.curses(String(weather.get("color", "")), Slate.SOFT).to_html(false), String(weather.get("text", ""))])
	var temp := String(hud.get("temperature", "-"))
	if temp != "-" and temp != "":
		parts.append("[color=#%s]%s[/color]" % [Slate.SOFT.to_html(false), temp])
	var light: Dictionary = hud.get("light", {})
	if light.has("text"):
		parts.append("[color=#%s]%s[/color]" % [Slate.curses(String(light.get("color", "")), Slate.SOFT).to_html(false), String(light["text"]).capitalize()])
	_weather.text = "  ·  ".join(parts)
	_place.text = String(hud.get("place", "")).capitalize()


func _update_carry(hud: Dictionary) -> void:
	var rows := []
	var w: Dictionary = hud.get("weight", {})
	var v: Dictionary = hud.get("volume", {})
	rows.append(_stat_row("Weight", String(w.get("text", "")), Slate.curses(String(w.get("color", "")), Slate.SOFT)))
	rows.append(_stat_row("Volume", String(v.get("text", "")), Slate.curses(String(v.get("color", "")), Slate.SOFT)))
	var power: Dictionary = hud.get("power", {})
	if String(power.get("text", "--")) != "--":
		rows.append(_stat_row("Power", String(power["text"]), Slate.curses(String(power.get("color", "")), Slate.INFO)))
	var mana: Dictionary = hud.get("mana", {})
	if String(mana.get("text", "--")) != "--":
		rows.append(_stat_row("Mana", String(mana["text"]), Slate.curses(String(mana.get("color", "")), Slate.INFO)))
	if not bool(hud.get("deaf", false)) and String(hud.get("sound", "")) != "":
		rows.append(_stat_row("Noise", String(hud["sound"]), Slate.SOFT))
	for c in _carry.get_children():
		c.queue_free()
	for row in rows:
		_carry.add_child(row)


func _stat_row(name: String, value: String, color: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Slate.label(name, 13, Slate.MUTED)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	row.add_child(Slate.label(value.strip_edges(), 13, color, Slate.mono()))
	return row


func _update_log(messages: Array) -> void:
	for c in _log.get_children():
		_log.remove_child(c)
		if c != _log_button:
			c.queue_free()
	var recent := messages.slice(maxi(messages.size() - 6, 0))
	var n := recent.size()
	for i in n:
		var msg: Dictionary = recent[i]
		var row := PanelContainer.new()
		var sb := Slate.box(Color(Slate.GROUND, 0.88), 10, Slate.BORDER, 0)
		sb.content_margin_left = 12
		sb.content_margin_right = 12
		sb.content_margin_top = 7
		sb.content_margin_bottom = 7
		row.add_theme_stylebox_override("panel", sb)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var age := n - 1 - i
		row.modulate.a = 1.0 if bool(msg.get("fresh", false)) else clampf(0.92 - age * 0.09, 0.45, 0.92)
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		row.add_child(line)
		var dot := DotView.new(Slate.lead_color(msg.get("text", []), Slate.SOFT))
		line.add_child(dot)
		var text := Slate.rich(14)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.text = Slate.bbcode(msg.get("text", []), Slate.SOFT)
		line.add_child(text)
		_log.add_child(row)
	var key := String(_keys.get("messages", ""))
	_log_button.text = "Message log" + ("  ·  %s" % key if key != "" else "")
	_log.add_child(_log_button)
	_log_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN


# --- Pieces --------------------------------------------------------------------------------------

## Body silhouette colored by each part's health; hover a part for its numbers.
class BodyView extends Control:
	const SHAPES := {
		"head": Rect2(24, 0, 22, 22),
		"torso": Rect2(19, 26, 32, 46),
		"arm_r": Rect2(3, 28, 13, 46),
		"arm_l": Rect2(54, 28, 13, 46),
		"leg_r": Rect2(20, 76, 14, 52),
		"leg_l": Rect2(36, 76, 14, 52),
	}
	var parts := {}
	var hovered := ""

	func _init() -> void:
		custom_minimum_size = Vector2(70, 128)
		mouse_filter = Control.MOUSE_FILTER_STOP

	func set_parts(list: Array) -> void:
		parts.clear()
		for p in list:
			parts[String(p.get("id", ""))] = p
		queue_redraw()
		_update_tooltip()

	func _health_color(ratio: float) -> Color:
		if ratio <= 0.0:
			return Color("#4a5260")
		if ratio < 0.25:
			return Slate.DANGER
		if ratio < 0.5:
			return Color("#f49a3f")
		if ratio < 0.8:
			return Color("#f4d35e")
		return Slate.GOOD

	func _draw() -> void:
		for id in SHAPES:
			var rect: Rect2 = SHAPES[id]
			var p: Dictionary = parts.get(id, {})
			var ratio := float(p.get("cur", 1)) / maxf(float(p.get("max", 1)), 1.0)
			var color := _health_color(ratio)
			if id == "head":
				color = color.lightened(0.25)
			var sb := StyleBoxFlat.new()
			sb.bg_color = color
			sb.set_corner_radius_all(11 if id == "head" else 7)
			sb.anti_aliasing = true
			if id == hovered:
				sb.border_color = Color(1, 1, 1, 0.9)
				sb.set_border_width_all(2)
				sb.set_expand_margin_all(2)
			draw_style_box(sb, rect)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseMotion:
			var now := ""
			for id in SHAPES:
				if SHAPES[id].grow(2).has_point(event.position):
					now = id
			if now != hovered:
				hovered = now
				queue_redraw()
				_update_tooltip()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_MOUSE_EXIT and hovered != "":
			hovered = ""
			queue_redraw()

	func _update_tooltip() -> void:
		if hovered == "" or not parts.has(hovered):
			var lines := []
			for id in ["head", "torso", "arm_l", "arm_r", "leg_l", "leg_r"]:
				if parts.has(id):
					lines.append("%s  %d / %d" % [parts[id]["label"], int(parts[id]["cur"]), int(parts[id]["max"])])
			tooltip_text = "\n".join(lines)
		else:
			var p: Dictionary = parts[hovered]
			tooltip_text = "%s  %d / %d" % [p["label"], int(p["cur"]), int(p["max"])]


## One labelled need with a state word and a bar.
class NeedRow extends VBoxContainer:
	var _state: Label
	var _bar: BarView

	func _init(title: String) -> void:
		add_theme_constant_override("separation", 3)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var top := HBoxContainer.new()
		top.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(top)
		var name := Slate.label(title, 12, Slate.MUTED)
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(name)
		_state = Slate.label("", 12, Slate.TEXT, Slate.bold())
		top.add_child(_state)
		_bar = BarView.new()
		add_child(_bar)

	func set_value(text: String, color: Color, fill: float) -> void:
		_state.text = text
		_state.add_theme_color_override("font_color", color)
		_bar.set_fill(fill, color)


class BarView extends Control:
	var fill := 1.0
	var color := Slate.GOOD

	func _init() -> void:
		custom_minimum_size = Vector2(0, 5)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_fill(value: float, c: Color) -> void:
		fill = clampf(value, 0.0, 1.0)
		color = c
		queue_redraw()

	func _draw() -> void:
		var track := StyleBoxFlat.new()
		track.bg_color = Slate.TRACK
		track.set_corner_radius_all(3)
		draw_style_box(track, Rect2(Vector2.ZERO, size))
		if fill > 0.0:
			var bar := StyleBoxFlat.new()
			bar.bg_color = color
			bar.set_corner_radius_all(3)
			draw_style_box(bar, Rect2(Vector2.ZERO, Vector2(maxf(size.x * fill, 5), size.y)))


class DotView extends Control:
	var color: Color

	func _init(c: Color) -> void:
		color = c
		custom_minimum_size = Vector2(8, 18)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_circle(Vector2(4, 10), 4, color)


## Dock button: icon, label, and the key it is bound to.
class DockButton extends Button:
	var action: String
	var _key: Label
	var _hint: String

	func _init(action_id: String, title: String, icon_name: String, hint: String) -> void:
		action = action_id
		_hint = hint
		focus_mode = Control.FOCUS_NONE
		custom_minimum_size = Vector2(68, 62)
		var normal := Slate.box(Color(0, 0, 0, 0), 12, Slate.BORDER, 0)
		var hover := Slate.box(Color(1, 1, 1, 0.08), 12, Slate.BORDER, 0)
		var down := Slate.box(Slate.ACCENT, 12, Slate.BORDER, 0)
		add_theme_stylebox_override("normal", normal)
		add_theme_stylebox_override("hover", hover)
		add_theme_stylebox_override("pressed", down)
		add_theme_stylebox_override("hover_pressed", down)
		var col := VBoxContainer.new()
		col.set_anchors_preset(Control.PRESET_FULL_RECT)
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.add_theme_constant_override("separation", 5)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(col)
		var glyph := Slate.icon_rect(icon_name, 22, Slate.TEXT)
		glyph.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(glyph)
		var name := Slate.label(title, 11, Slate.TEXT, Slate.bold())
		name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(name)
		_key = Slate.label("", 10, Slate.MUTED, Slate.mono())
		_key.position = Vector2(0, 3)
		_key.size = Vector2(62, 14)
		_key.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		add_child(_key)
		pressed.connect(func(): Bridge.run_action(action))

	func set_key(key: String) -> void:
		_key.text = key
		tooltip_text = "%s  (%s)" % [_hint, key] if key != "" else _hint
