extends Control
## In-game HUD around the map: a header with the time, weather and place, a sidebar with the map,
## threats and messages, and an action bar, all docked to the window's edges. The survivor card
## (body, needs and stats) floats over the map's top left corner. Rebuilt from the `hud` message
## the game sends whenever the main view redraws; the game keeps its map view inside the bars.
##
## It shows everything the old sidebar did. Parts the sidebar lets players switch off (compass,
## minimap, log, armor, mod panels) follow the sidebar options menu, opened with the gear button.

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

const NEEDS := [["thirst", "Thirst"], ["hunger", "Hunger"], ["fatigue", "Rest"]]

## Compass directions in the game's order: clockwise from north, then close by.
const DIRS := ["N", "NE", "E", "SE", "S", "SW", "W", "NW", "Near"]

## Health words for the colors the sidebar paints limb bars with.
const HEALTH_WORDS := {
	"c_green": "Healthy",
	"c_light_green": "Scratched",
	"c_yellow": "Hurt",
	"c_light_red": "Badly hurt",
	"c_red": "Critical",
	"c_light_gray": "Disabled",
}

## Threat words for the colors the sidebar's compass gives monster names and NPCs.
const THREAT_WORDS := {
	"c_red": "Extreme threat",
	"c_light_red": "High threat",
	"c_white": "Moderate threat",
	"c_light_gray": "Low threat",
	"c_dark_gray": "Passive",
	"c_light_green": "Follower",
	"c_pink": "Neutral",
}

## What each injury means, shown when a limb is inspected.
const INJURY_NOTES := {
	"Bleeding": "Losing blood. Bandage it or apply pressure.",
	"Bitten": "Bitten. Disinfect it before it gets infected.",
	"Infected": "Infected. It needs antibiotics.",
	"Broken": "Broken. Splint it so it can mend.",
	"Broken, splinted": "Broken and splinted, mending.",
}

const HEADER_HEIGHT := 56
const BAR_HEIGHT := 84
const SIDE_WIDTH := 320
const SIDE_PADDING := 16
const MAP_SIZE := 288
const SURVIVOR_WIDTH := 440
const GAP := 16
## Action bar button widths, widest first; the narrowest drops the labels.
const DOCK_WIDTHS := [70, 58, 44]
const CORNER_WIDTH := 3 * 40 + 2 * 6

## Weather words and the icon that fits them, checked in order.
const WEATHER_ICONS := [
	["thunder", "cloud-lightning"], ["lightning", "cloud-lightning"], ["snow", "cloud-snow"],
	["flurr", "cloud-snow"], ["sleet", "cloud-snow"], ["drizzle", "cloud-drizzle"], ["rain", "cloud-rain"],
	["fog", "cloud-fog"], ["mist", "cloud-fog"], ["haz", "cloud-fog"], ["overcast", "cloud"],
	["cloud", "cloud"], ["sunny", "sun"], ["clear", "sun"], ["fair", "cloud-sun"],
]

var _hud := {}
var _keys := {}
var _tab := "needs"
var _selected_part := ""
var _map_mode := "local"

# Survivor card
var _body: BodyView
var _name: Label
var _weapon: RichTextLabel
var _tab_buttons := {}
var _needs_view: VBoxContainer
var _body_view: VBoxContainer
var _stats_view: VBoxContainer
var _needs := {}
var _stamina: NeedRow
var _warmth: NeedRow
var _vitals := {}
var _limb_rows := {}
var _limb_list: VBoxContainer
var _limb_detail: VBoxContainer
var _stat_tiles := {}
var _stat_rows: VBoxContainer
var _chips: HFlowContainer

# Header: time, weather and place
var _header: PanelContainer
var _header_row: HBoxContainer
var _clock_day: Label
var _clock_time: Label
## Header groups by id: [box, icon, label].
var _groups := {}
var _wanted := {}
var _wind_arrow: TextureRect
var _vehicle_row: HBoxContainer

# Sidebar: map, threats, mod panels and messages
var _side: PanelContainer
var _minimap: TextureRect
var _area: AreaView
var _map_switch: HBoxContainer
var _map_buttons := {}
var _threats_box: VBoxContainer
var _threat_count: Label
var _threat_list: VBoxContainer
var _widgets: VBoxContainer
var _log_box: VBoxContainer
var _log_list: VBoxContainer
var _log_button: Button

# Action bar
var _bar: PanelContainer
var _balance: Control
var _dock_buttons := {}
var _options_button: Button

# Hover card: what is under the mouse on the map (the game's "Mouse View" box), shown like a
# tooltip once the mouse rests.
const HOVER_DELAY := 0.35
const HOVER_WIDTH := 420
var _hover: PanelContainer
var _hover_text: RichTextLabel
var _hover_on_map := false
var _hover_still := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_header()
	_build_side()
	_build_bar()
	_build_survivor_card()
	_build_hover()
	Bridge.minimap_received.connect(func(texture: ImageTexture): _minimap.texture = texture)
	Bridge.connected.connect(_send_insets)
	_send_insets()


## Tells the game which edges the bars cover, so it keeps the map view (and the player at its
## center) inside the space that is left.
func _send_insets() -> void:
	Bridge.send({"t": "insets", "left": 0, "top": HEADER_HEIGHT, "right": SIDE_WIDTH, "bottom": BAR_HEIGHT})


# --- Shared pieces -------------------------------------------------------------------------------

func _card(width: float, parent: Control = self) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", Slate.card_box(18, 18))
	card.custom_minimum_size.x = width
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(card)
	return card


## Flat panel for a bar docked to one edge, with a hairline on the side facing the map.
func _bar_box(edge: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Slate.CARD_SOLID
	sb.border_color = Slate.BORDER
	match edge:
		SIDE_TOP:
			sb.border_width_top = 1
		SIDE_BOTTOM:
			sb.border_width_bottom = 1
		SIDE_LEFT:
			sb.border_width_left = 1
	return sb


func _section_title(text: String) -> Label:
	return Slate.label(text, 15, Slate.TEXT, Slate.heavy())


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


func _rule() -> ColorRect:
	var d := ColorRect.new()
	d.color = Slate.BORDER
	d.custom_minimum_size = Vector2(0, 1)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return d


func _chip(text: String, color: Color, tooltip := "", action := "") -> PanelContainer:
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", Slate.pill_box(Color(color, 0.16), 11, 5))
	chip.tooltip_text = tooltip
	chip.mouse_filter = Control.MOUSE_FILTER_STOP if tooltip != "" or action != "" else Control.MOUSE_FILTER_IGNORE
	if action != "":
		chip.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		chip.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				Bridge.run_action(action))
	chip.add_child(Slate.label(text, 13, color.lightened(0.15), Slate.bold()))
	return chip


func _icon_button(icon_name: String, tooltip: String, box_size := 40, icon_size := 18) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.icon = Slate.icon(icon_name, icon_size)
	b.tooltip_text = tooltip
	b.custom_minimum_size = Vector2(box_size, box_size)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var sb := Slate.box(Color(0, 0, 0, 0), 8, Slate.BORDER, 0)
	sb.set_content_margin_all(0)
	b.add_theme_stylebox_override("normal", sb)
	var hot := Slate.box(Slate.HOVER, 8, Slate.BORDER, 0)
	hot.set_content_margin_all(0)
	b.add_theme_stylebox_override("hover", hot)
	b.add_theme_stylebox_override("pressed", hot)
	b.add_theme_color_override("icon_normal_color", Slate.FAINT)
	b.add_theme_color_override("icon_hover_color", Slate.TEXT)
	b.add_theme_color_override("icon_pressed_color", Slate.TEXT)
	return b


func _tile(title: String, value_size := 17) -> Array:
	var tile := PanelContainer.new()
	var sb := Slate.box(Color(1, 1, 1, 0.05), 10, Slate.BORDER, 0)
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	tile.add_theme_stylebox_override("panel", sb)
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.mouse_filter = Control.MOUSE_FILTER_PASS
	var t := VBoxContainer.new()
	t.add_theme_constant_override("separation", 0)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(t)
	var value := Slate.label("", value_size, Slate.TEXT, Slate.mono_bold())
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_child(value)
	var name := Slate.label(title, 10, Slate.MUTED, Slate.bold())
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_child(name)
	return [tile, value]


func _key(action: String) -> String:
	return String(_keys.get(action, ""))


func _with_key(text: String, action: String) -> String:
	var key := _key(action)
	return "%s  (%s)" % [text, key] if key != "" else text


static func _colored(info, fallback := Slate.TEXT) -> Color:
	if typeof(info) != TYPE_DICTIONARY:
		return fallback
	return Slate.curses(String(info.get("color", "")), fallback)


static func _text(info) -> String:
	if typeof(info) != TYPE_DICTIONARY:
		return ""
	return String(info.get("text", "")).strip_edges()


static func _hex(c: Color) -> String:
	return c.to_html(false)


static func _escape(text: String) -> String:
	return text.replace("[", "[lb]")


## Upper-cases the first letter only; `capitalize()` would also split names like "McNeal".
static func _cap(text: String) -> String:
	return text.substr(0, 1).to_upper() + text.substr(1) if text != "" else text


# --- Survivor card -------------------------------------------------------------------------------

func _build_survivor_card() -> void:
	var card := _card(SURVIVOR_WIDTH)
	card.position = Vector2(GAP, HEADER_HEIGHT + GAP)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	card.add_child(col)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 18)
	col.add_child(top)
	_body = BodyView.new()
	_body.part_clicked.connect(_on_part_clicked)
	top.add_child(_body)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 2)
	top.add_child(info)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 2)
	info.add_child(head)
	_name = Slate.label("", 20, Slate.TEXT, Slate.heavy())
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name.clip_text = true
	head.add_child(_name)
	for tab in [["needs", "heart-pulse", "Needs"], ["body", "person-standing", "Body: check each limb"],
			["stats", "chart-column", "Stats, carrying and armor"]]:
		var b := _icon_button(tab[1], tab[2], 28, 16)
		var id: String = tab[0]
		b.pressed.connect(func(): _set_tab(id))
		head.add_child(b)
		_tab_buttons[id] = b

	_weapon = Slate.rich(14)
	_weapon.autowrap_mode = TextServer.AUTOWRAP_OFF
	_weapon.clip_contents = true
	info.add_child(_weapon)
	info.add_child(_spacer(10))

	_needs_view = VBoxContainer.new()
	_needs_view.add_theme_constant_override("separation", 9)
	info.add_child(_needs_view)
	for need in NEEDS:
		var row := NeedRow.new(need[1])
		_needs_view.add_child(row)
		_needs[need[0]] = row
	_stamina = NeedRow.new("Stamina")
	_needs_view.add_child(_stamina)
	_warmth = NeedRow.new("Warmth")
	_needs_view.add_child(_warmth)

	_body_view = VBoxContainer.new()
	_body_view.add_theme_constant_override("separation", 8)
	info.add_child(_body_view)
	_limb_list = VBoxContainer.new()
	_limb_list.add_theme_constant_override("separation", 1)
	_body_view.add_child(_limb_list)
	_limb_detail = VBoxContainer.new()
	_limb_detail.add_theme_constant_override("separation", 5)
	_body_view.add_child(_limb_detail)

	_stats_view = VBoxContainer.new()
	_stats_view.add_theme_constant_override("separation", 10)
	info.add_child(_stats_view)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 6)
	_stats_view.add_child(grid)
	for stat in [["str", "STR"], ["dex", "DEX"], ["int", "INT"], ["per", "PER"]]:
		var tile := _tile(stat[1])
		grid.add_child(tile[0])
		_stat_tiles[stat[0]] = tile[1]
	_stat_rows = VBoxContainer.new()
	_stat_rows.add_theme_constant_override("separation", 5)
	_stats_view.add_child(_stat_rows)

	# The sidebar's movement panel, always in view.
	var vitals := HBoxContainer.new()
	vitals.add_theme_constant_override("separation", 6)
	col.add_child(vitals)
	for v in [["mood", "Mood"], ["focus", "Focus"], ["speed", "Speed"], ["move", "Move"], ["noise", "Noise"]]:
		var tile := _tile(v[1], 15)
		vitals.add_child(tile[0])
		_vitals[v[0]] = tile

	_chips = HFlowContainer.new()
	_chips.add_theme_constant_override("h_separation", 6)
	_chips.add_theme_constant_override("v_separation", 6)
	col.add_child(_chips)
	_set_tab("needs")


func _set_tab(tab: String) -> void:
	_tab = tab
	if tab != "body":
		_selected_part = ""
	_needs_view.visible = tab == "needs"
	_body_view.visible = tab == "body"
	_stats_view.visible = tab == "stats"
	for id in _tab_buttons:
		var b: Button = _tab_buttons[id]
		var on: bool = id == tab
		var sb := Slate.box(Color(1, 1, 1, 0.10) if on else Color(0, 0, 0, 0), 8, Slate.BORDER, 0)
		sb.set_content_margin_all(0)
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_color_override("icon_normal_color", Slate.ACCENT if on else Slate.FAINT)
	_body.selected = _selected_part
	_body.queue_redraw()
	if not _hud.is_empty():
		_update_body_view()


func _on_part_clicked(id: String) -> void:
	# Clicking the part being inspected again goes back to the needs.
	if _tab == "body" and _selected_part == id:
		_set_tab("needs")
		return
	_set_tab("body")
	_selected_part = id
	_body.selected = id
	_body.queue_redraw()
	_update_body_view()


# --- Header --------------------------------------------------------------------------------------

func _build_header() -> void:
	_header = PanelContainer.new()
	var sb := _bar_box(SIDE_BOTTOM)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	_header.add_theme_stylebox_override("panel", sb)
	_header.anchor_right = 1.0
	_header.offset_bottom = HEADER_HEIGHT
	_header.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_header)
	_header_row = HBoxContainer.new()
	_header_row.add_theme_constant_override("separation", 20)
	_header_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header.add_child(_header_row)

	var clock := HBoxContainer.new()
	clock.add_theme_constant_override("separation", 12)
	clock.mouse_filter = Control.MOUSE_FILTER_PASS
	clock.tooltip_text = "Season, day and time. Without a watch the time is a guess, and underground there is none."
	_header_row.add_child(clock)
	_clock_day = Slate.label("", 15, Slate.TEXT, Slate.bold())
	clock.add_child(_clock_day)
	_clock_time = Slate.label("", 15, Slate.ACCENT, Slate.mono_bold())
	clock.add_child(_clock_time)
	_header_row.add_child(_divider())

	_groups["weather"] = _group("cloud", "Weather")
	_groups["temperature"] = _group("thermometer", "Temperature (needs a thermometer)")
	_groups["light"] = _group("sun-dim", "Light where you stand")
	_groups["wind"] = _group("wind", "Wind; the arrow shows where it blows")
	_wind_arrow = Slate.icon_rect("arrow-up", 14, Slate.SOFT)
	_wind_arrow.pivot_offset = Vector2(7, 7)
	_wind_arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_groups["wind"][0].add_child(_wind_arrow)
	_groups["moon"] = _group("moon", "Moon phase")

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header_row.add_child(spacer)

	_vehicle_row = HBoxContainer.new()
	_vehicle_row.add_theme_constant_override("separation", 10)
	_vehicle_row.mouse_filter = Control.MOUSE_FILTER_PASS
	_vehicle_row.visible = false
	_header_row.add_child(_vehicle_row)
	_groups["place"] = _group("map-pin", "Where you are")
	_groups["coords"] = _group("compass", "Overmap coordinates", true)
	# The window's width, not the header's: a header too full for the window grows past it.
	resized.connect(_fit_header)


## One icon-and-text item in the header: [box, icon, label].
func _group(icon_name: String, tooltip: String, mono := false) -> Array:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 7)
	box.tooltip_text = tooltip
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	_header_row.add_child(box)
	var icon := Slate.icon_rect(icon_name, 16, Slate.FAINT)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(icon)
	var label := Slate.label("", 13 if mono else 14, Slate.SOFT, Slate.mono() if mono else Slate.semibold())
	box.add_child(label)
	return [box, icon, label]


func _set_group(id: String, text: String, color := Slate.SOFT) -> void:
	var g: Array = _groups[id]
	(g[2] as Label).text = text
	(g[2] as Label).add_theme_color_override("font_color", color)
	_wanted[id] = text != ""


## Shows every header item that fits, dropping the least important first in narrow windows.
## Whatever a narrow window hides is listed in the place's tooltip, so nothing is lost.
func _fit_header() -> void:
	for id in _groups:
		_groups[id][0].visible = bool(_wanted.get(id, false))
	var hidden: PackedStringArray = []
	for id in ["coords", "moon", "wind", "light", "temperature"]:
		if _header_needed() <= size.x - 44:
			break
		if _groups[id][0].visible:
			_groups[id][0].visible = false
			hidden.append("%s: %s" % [_groups[id][0].tooltip_text.get_slice(" (", 0).get_slice(";", 0), _groups[id][2].text])
	hidden.reverse()
	_groups["place"][0].tooltip_text = "\n".join(PackedStringArray(["Where you are"]) + hidden)


func _header_needed() -> float:
	var total := 0.0
	var shown := 0
	for c in _header_row.get_children():
		if c is Control and c.visible:
			total += (c as Control).get_combined_minimum_size().x
			shown += 1
	return total + maxi(shown - 1, 0) * 20


# --- Sidebar: map, threats, mod panels and messages ----------------------------------------------

func _build_side() -> void:
	_side = PanelContainer.new()
	var sb := _bar_box(SIDE_LEFT)
	sb.set_content_margin_all(SIDE_PADDING)
	_side.add_theme_stylebox_override("panel", sb)
	_side.anchor_left = 1.0
	_side.anchor_right = 1.0
	_side.anchor_bottom = 1.0
	_side.offset_left = -SIDE_WIDTH
	_side.offset_top = HEADER_HEIGHT
	_side.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_side)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	_side.add_child(col)

	var holder := Control.new()
	holder.custom_minimum_size = Vector2(MAP_SIZE, MAP_SIZE)
	holder.clip_contents = true
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(holder)
	var map_bg := Panel.new()
	map_bg.add_theme_stylebox_override("panel", Slate.box(Color(0, 0, 0, 0.55), 12, Slate.BORDER, 0))
	map_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	map_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(map_bg)
	_minimap = TextureRect.new()
	_minimap.set_anchors_preset(Control.PRESET_FULL_RECT)
	_minimap.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	_minimap.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(_minimap)
	_area = AreaView.new()
	_area.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(_area)
	var frame := Panel.new()
	frame.add_theme_stylebox_override("panel", Slate.box(Color(0, 0, 0, 0), 12, Slate.BORDER_STRONG, 1))
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(frame)

	_map_switch = HBoxContainer.new()
	_map_switch.add_theme_constant_override("separation", 4)
	col.add_child(_map_switch)
	for mode in [["local", "Nearby", "The area around you, tile by tile"],
			["area", "Overmap", "The overmap around you, with notes, your mission and hordes"]]:
		var b := Button.new()
		b.text = mode[1]
		b.tooltip_text = mode[2]
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.add_theme_font_size_override("font_size", 12)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var id: String = mode[0]
		b.pressed.connect(func():
			_map_mode = id
			_update_map())
		_map_switch.add_child(b)
		_map_buttons[id] = b

	_threats_box = VBoxContainer.new()
	_threats_box.add_theme_constant_override("separation", 8)
	col.add_child(_threats_box)
	_threats_box.add_child(_rule())
	var head := HBoxContainer.new()
	_threats_box.add_child(head)
	var title := _section_title("Threats")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_threat_count = Slate.label("", 13, Slate.MUTED, Slate.bold())
	head.add_child(_threat_count)
	_threat_list = VBoxContainer.new()
	_threat_list.add_theme_constant_override("separation", 6)
	_threats_box.add_child(_threat_list)

	_widgets = VBoxContainer.new()
	_widgets.add_theme_constant_override("separation", 14)
	_widgets.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_widgets)

	# Messages fill the rest of the sidebar, newest at the bottom; older ones scroll off the top.
	_log_box = VBoxContainer.new()
	_log_box.add_theme_constant_override("separation", 8)
	_log_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_log_box)
	_log_box.add_child(_rule())
	var log_head := HBoxContainer.new()
	_log_box.add_child(log_head)
	var log_title := _section_title("Messages")
	log_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_head.add_child(log_title)
	_log_button = Button.new()
	_log_button.focus_mode = Control.FOCUS_NONE
	_log_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_log_button.add_theme_font_size_override("font_size", 12)
	_log_button.add_theme_color_override("font_color", Slate.MUTED)
	_log_button.add_theme_color_override("font_hover_color", Slate.TEXT)
	var lb := Slate.pill_box(Color(1, 1, 1, 0.06), 10, 4)
	_log_button.add_theme_stylebox_override("normal", lb)
	var lbh := Slate.pill_box(Color(1, 1, 1, 0.12), 10, 4)
	_log_button.add_theme_stylebox_override("hover", lbh)
	_log_button.add_theme_stylebox_override("pressed", lbh)
	_log_button.pressed.connect(func(): Bridge.run_action("messages"))
	log_head.add_child(_log_button)
	var clip := Control.new()
	clip.clip_contents = true
	clip.size_flags_vertical = Control.SIZE_EXPAND_FILL
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log_box.add_child(clip)
	_log_list = VBoxContainer.new()
	_log_list.add_theme_constant_override("separation", 7)
	_log_list.anchor_top = 1.0
	_log_list.anchor_bottom = 1.0
	_log_list.anchor_right = 1.0
	_log_list.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_log_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.add_child(_log_list)


# --- Action bar ----------------------------------------------------------------------------------

func _build_bar() -> void:
	_bar = PanelContainer.new()
	var sb := _bar_box(SIDE_TOP)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	_bar.add_theme_stylebox_override("panel", sb)
	_bar.anchor_top = 1.0
	_bar.anchor_bottom = 1.0
	_bar.anchor_right = 1.0
	_bar.offset_top = -BAR_HEIGHT
	_bar.offset_right = -SIDE_WIDTH
	_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_bar.add_child(row)

	# Room on the left matching the zoom buttons, so the actions sit in the middle of the map.
	_balance = Control.new()
	_balance.custom_minimum_size.x = CORNER_WIDTH
	_balance.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_balance)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(center)
	var dock := HBoxContainer.new()
	dock.add_theme_constant_override("separation", 4)
	center.add_child(dock)
	for entry in DOCK:
		var button := DockButton.new(entry[0], entry[1], entry[2], entry[3])
		dock.add_child(button)
		_dock_buttons[entry[0]] = button

	var corner := HBoxContainer.new()
	corner.add_theme_constant_override("separation", 6)
	corner.alignment = BoxContainer.ALIGNMENT_END
	corner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(corner)
	for z in [["zoom_out", "zoom-out", "Zoom out"], ["zoom_in", "zoom-in", "Zoom in"],
			["toggle_panel_adm", "settings", "HUD options"]]:
		var b := _icon_button(z[1], z[2], 40, 18)
		var plain := Slate.box(Color(1, 1, 1, 0.05), 10, Slate.BORDER, 0)
		plain.set_content_margin_all(0)
		b.add_theme_stylebox_override("normal", plain)
		var hot := Slate.box(Color(1, 1, 1, 0.12), 10, Slate.BORDER, 0)
		hot.set_content_margin_all(0)
		b.add_theme_stylebox_override("hover", hot)
		b.add_theme_stylebox_override("pressed", hot)
		b.add_theme_color_override("icon_normal_color", Slate.SOFT)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var action: String = z[0]
		b.pressed.connect(func(): Bridge.run_action(action))
		corner.add_child(b)
		if action == "toggle_panel_adm":
			_options_button = b
	resized.connect(_fit_bar)
	_fit_bar()


## Narrow windows first give up the room that centers the actions, then tighten the buttons.
func _fit_bar() -> void:
	var room := size.x - SIDE_WIDTH - 32.0
	var count := _dock_buttons.size()
	var needed := func(w: int) -> float: return count * w + (count - 1) * 4 + 12 + CORNER_WIDTH
	_balance.visible = needed.call(DOCK_WIDTHS[0]) + 12 + CORNER_WIDTH <= room
	var level: int = DOCK_WIDTHS.size() - 1
	for i in DOCK_WIDTHS.size():
		if needed.call(DOCK_WIDTHS[i]) <= room:
			level = i
			break
	for b in _dock_buttons.values():
		(b as DockButton).set_width(DOCK_WIDTHS[level], level < DOCK_WIDTHS.size() - 1)


# --- Updates -------------------------------------------------------------------------------------

# --- Hover card ----------------------------------------------------------------------------------

func _build_hover() -> void:
	_hover = PanelContainer.new()
	_hover.add_theme_stylebox_override("panel", Slate.card_box(12, 14))
	_hover.custom_minimum_size.x = HOVER_WIDTH
	_hover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover.visible = false
	add_child(_hover)
	_hover_text = Slate.rich(12)
	_hover_text.add_theme_font_override("normal_font", Slate.mono())
	_hover_text.add_theme_color_override("default_color", Slate.SOFT)
	_hover_text.add_theme_constant_override("line_separation", 3)
	_hover.add_child(_hover_text)


## Called by the window as the mouse enters or leaves the map (a HUD card covering the map counts
## as leaving it).
func set_map_hover(on: bool) -> void:
	_hover_on_map = on
	_hover_still = 0.0
	_update_hover()


## Called on every mouse move over the map: the card hides until the mouse rests again.
func map_mouse_moved() -> void:
	_hover_still = 0.0
	_update_hover()


func _process(delta: float) -> void:
	if _hover_still < HOVER_DELAY:
		_hover_still += delta
		if _hover_still >= HOVER_DELAY:
			_update_hover()


func _update_hover() -> void:
	var spans: Array = _hud.get("hover", [])
	var show := _hover_on_map and _hover_still >= HOVER_DELAY and not spans.is_empty()
	_hover.visible = show
	if not show:
		return
	_hover_text.text = Slate.tidy_body(Slate.bbcode(spans, Slate.SOFT))
	_hover.reset_size()
	# Beside the mouse, kept inside the map between the bars: flipped to the left or up near the
	# sidebar or the action bar.
	var mouse := get_local_mouse_position()
	var card := _hover.get_combined_minimum_size()
	var area := Rect2(0, HEADER_HEIGHT, size.x - SIDE_WIDTH, size.y - HEADER_HEIGHT - BAR_HEIGHT)
	var at := mouse + Vector2(20, 20)
	if at.x + card.x > area.end.x:
		at.x = mouse.x - 20 - card.x
	if at.y + card.y > area.end.y:
		at.y = area.end.y - card.y - 8
	at.x = clampf(at.x, area.position.x + 8, maxf(area.position.x + 8, area.end.x - card.x - 8))
	at.y = maxf(at.y, area.position.y + 8)
	_hover.position = at


func apply(hud: Dictionary) -> void:
	_hud = hud
	_keys = hud.get("keys", {})
	var show: Dictionary = hud.get("show", {})

	_name.text = String(hud.get("name", ""))
	var weapon := Slate.bbcode(hud.get("weapon", []), Slate.MUTED)
	var style := String(hud.get("style", ""))
	if style != "" and style != "No style":
		# The sidebar shows the style red when armed and blue when fighting bare-handed.
		var style_color := Slate.curses("c_red" if bool(hud.get("armed", false)) else "c_light_blue", Slate.MUTED)
		weapon += "[color=#%s]  ·  [/color][color=#%s]%s[/color]" % [_hex(Slate.FAINT), _hex(style_color), _escape(style)]
	_weapon.text = weapon
	_body.set_parts(hud.get("body", []))

	_update_needs(hud)
	_update_vitals(hud)
	_update_body_view()
	_update_stats(hud, show)
	_update_chips(hud)
	_update_status(hud)
	_update_vehicle(hud.get("vehicle", {}))
	_update_map()
	_update_threats(hud, show)
	_update_widgets(hud.get("widgets", []))
	_log_box.visible = bool(show.get("log", true))
	_update_log(hud.get("messages", []))
	for action in _dock_buttons:
		_dock_buttons[action].set_key(_key(action))
	_options_button.tooltip_text = _with_key("HUD options: choose what the HUD shows", "toggle_panel_adm")
	_update_hover()


func _update_needs(hud: Dictionary) -> void:
	for need in NEEDS:
		var info: Dictionary = hud.get(need[0], {})
		var text := _text(info)
		var color_name := String(info.get("color", "c_white"))
		_needs[need[0]].set_value(text if text != "" else "Fine", Slate.curses(color_name, Slate.GOOD),
				Slate.severity(color_name) if text != "" else 1.0)
	var stamina: Dictionary = hud.get("stamina", {})
	_stamina.set_value(String(stamina.get("text", "")), Slate.INFO, float(stamina.get("level", 0)))
	_stamina.set_bar_color(_colored(stamina, Slate.INFO))
	var warm: Dictionary = hud.get("body_temp", {})
	var trend: Dictionary = hud.get("body_temp_trend", {})
	_warmth.set_value(_text(warm), _colored(warm, Slate.GOOD), Slate.severity(String(warm.get("color", ""))))
	_warmth.set_note(_text(trend).trim_prefix("(").trim_suffix(")"), _colored(trend, Slate.MUTED))


func _update_vitals(hud: Dictionary) -> void:
	var morale := int(hud.get("morale", 0))
	_set_vital("mood", String(hud.get("morale_face", "")),
			Slate.curses(String(hud.get("morale_color", "")), Slate.SOFT), "Mood: morale %+d" % morale)
	var focus: Dictionary = hud.get("focus", {})
	var trend := int(hud.get("focus_trend", 0))
	var arrow := "↑" if trend > 0 else ("↓" if trend < 0 else "")
	var trend_words := ", rising" if trend > 0 else (", falling" if trend < 0 else ", steady")
	_set_vital("focus", _text(focus) + arrow, _colored(focus), "Focus %s%s" % [_text(focus), trend_words])
	var speed: Dictionary = hud.get("speed", {})
	_set_vital("speed", _text(speed), _colored(speed), "Speed %s; 100 is normal" % _text(speed))
	var move: Dictionary = hud.get("move", {})
	var modes := {"W": "walking", "R": "running", "C": "crouching", "P": "prone"}
	var cost := int(hud.get("move_cost", 0))
	_set_vital("move", "%d%s" % [cost, _text(move)], _colored(move, Slate.SOFT),
			"Your last step cost %d moves; you are %s" % [cost, String(modes.get(_text(move), "walking"))])
	if bool(hud.get("deaf", false)):
		_set_vital("noise", "Deaf", Slate.DANGER, "You can't hear anything")
	else:
		var sound := String(hud.get("sound", ""))
		_set_vital("noise", sound if sound != "" else "–", Slate.WARN if bool(hud.get("noisy", false)) else Slate.SOFT,
				"How much noise you are making")


func _set_vital(id: String, value: String, color: Color, tooltip: String) -> void:
	var tile: Array = _vitals[id]
	(tile[1] as Label).text = value
	(tile[1] as Label).add_theme_color_override("font_color", color)
	(tile[0] as Control).tooltip_text = tooltip


static func _part_state(p: Dictionary) -> Array:
	var states := []
	if bool(p.get("broken", false)):
		states.append("Broken, splinted" if bool(p.get("splinted", false)) else "Broken")
	if bool(p.get("bleeding", false)):
		states.append("Bleeding")
	if bool(p.get("bitten", false)):
		states.append("Bitten")
	if bool(p.get("infected", false)):
		states.append("Infected")
	return states


static func _health_word(p: Dictionary) -> String:
	if p.has("cur"):
		return "%d / %d" % [int(p["cur"]), int(p["max"])]
	if bool(p.get("broken", false)):
		return "Mending"
	return String(HEALTH_WORDS.get(String(p.get("color", "")), ""))


func _update_body_view() -> void:
	var parts: Array = _hud.get("body", [])
	var ids := parts.map(func(p): return String(p.get("id", "")))
	if ids != _limb_rows.keys():
		for c in _limb_list.get_children():
			c.queue_free()
		_limb_rows.clear()
		for id in ids:
			var row := LimbRow.new(id)
			row.clicked.connect(_on_part_clicked)
			_limb_list.add_child(row)
			_limb_rows[id] = row
	var selected := {}
	for p in parts:
		var id := String(p.get("id", ""))
		var states := _part_state(p)
		var health_color := Slate.curses(String(p.get("color", "")), Slate.SOFT)
		var injury := String(p.get("status", "c_light_gray")) != "c_light_gray"
		var state_text := ", ".join(states) if not states.is_empty() else _health_word(p)
		var state_color := Slate.curses(String(p.get("status", "")), Slate.SOFT) if injury else health_color
		_limb_rows[id].set_state(String(p.get("label", "")), float(p.get("level", 0)), health_color,
				state_text, state_color, id == _selected_part)
		if id == _selected_part:
			selected = p

	for c in _limb_detail.get_children():
		c.queue_free()
	if selected.is_empty():
		_limb_detail.add_child(Slate.label("Click a limb to inspect it.", 12, Slate.FAINT))
		return
	_limb_detail.add_child(_rule())
	var title := HBoxContainer.new()
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_limb_detail.add_child(title)
	var name := Slate.label(_cap(String(selected.get("label", ""))), 14, Slate.TEXT, Slate.bold())
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_child(name)
	title.add_child(Slate.label(_health_word(selected), 13, Slate.curses(String(selected.get("color", "")), Slate.SOFT),
			Slate.mono_bold() if selected.has("cur") else Slate.bold()))
	var injury_color := Slate.curses(String(selected.get("status", "")), Slate.SOFT)
	var states := _part_state(selected)
	if states.is_empty():
		_limb_detail.add_child(Slate.label("No bleeding, bites, infection or breaks.", 12, Slate.MUTED))
	for s in states:
		var color := injury_color if not String(s).begins_with("Broken") else Slate.SOFT
		var line := Slate.label(String(INJURY_NOTES.get(s, s)), 12, color)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_limb_detail.add_child(line)
	var worn := Slate.rich(12)
	worn.autowrap_mode = TextServer.AUTOWRAP_OFF
	worn.clip_contents = true
	worn.text = "[color=#%s]Outer layer   [/color]%s" % [_hex(Slate.FAINT), Slate.bbcode(selected.get("armor", []), Slate.SOFT)]
	_limb_detail.add_child(worn)


func _update_stats(hud: Dictionary, show: Dictionary) -> void:
	for stat in _stat_tiles:
		var info: Dictionary = hud.get(stat, {})
		_stat_tiles[stat].text = _text(info)
		_stat_tiles[stat].add_theme_color_override("font_color", _colored(info))
	for c in _stat_rows.get_children():
		c.queue_free()
	_stat_rows.add_child(_stat_row("Weight", hud.get("weight", {}), Slate.SOFT))
	_stat_rows.add_child(_stat_row("Volume", hud.get("volume", {}), Slate.SOFT))
	var power: Dictionary = hud.get("power", {})
	if _text(power) != "--":
		_stat_rows.add_child(_stat_row("Bionic power", power, Slate.INFO))
	if hud.has("mana"):
		var mana: Dictionary = hud["mana"]
		_stat_rows.add_child(_stat_row("Mana", {"text": "%s / %d" % [_text(mana), int(hud.get("mana_max", 0))],
				"color": String(mana.get("color", ""))}, Slate.INFO))
	if hud.has("goal"):
		_stat_rows.add_child(_stat_row("Goal", {"text": String(hud["goal"])}, Slate.SOFT))
	if bool(show.get("armor", false)):
		_stat_rows.add_child(_spacer(2))
		_stat_rows.add_child(Slate.label("Outer layers", 12, Slate.MUTED, Slate.bold()))
		for slot in hud.get("armor", []):
			var row := HBoxContainer.new()
			row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var l := Slate.label(String(slot.get("label", "")), 13, Slate.MUTED)
			l.custom_minimum_size.x = 56
			row.add_child(l)
			var item := Slate.rich(13)
			item.autowrap_mode = TextServer.AUTOWRAP_OFF
			item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			item.clip_contents = true
			item.text = Slate.bbcode(slot.get("item", []), Slate.SOFT)
			row.add_child(item)
			_stat_rows.add_child(row)


func _stat_row(name: String, info, fallback: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Slate.label(name, 13, Slate.MUTED)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	row.add_child(Slate.label(_text(info), 13, _colored(info, fallback), Slate.mono()))
	return row


func _update_chips(hud: Dictionary) -> void:
	for c in _chips.get_children():
		c.queue_free()
	# Injuries first, one chip per kind listing the parts, like "Bleeding · Left arm".
	var injuries := {}
	var colors := {}
	for p in hud.get("body", []):
		for s in _part_state(p):
			var kind := "Broken" if String(s).begins_with("Broken") else String(s)
			if not injuries.has(kind):
				injuries[kind] = []
				colors[kind] = Slate.SOFT if kind == "Broken" else Slate.curses(String(p.get("status", "")), Slate.DANGER)
			injuries[kind].append(_cap(String(p.get("label", ""))))
	for kind in injuries:
		_chips.add_child(_chip("%s · %s" % [kind, ", ".join(injuries[kind])], colors[kind]))
	var pain: Dictionary = hud.get("pain", {})
	if _text(pain) != "":
		_chips.add_child(_chip(_text(pain), _colored(pain, Slate.DANGER)))
	var move := _text(hud.get("move", {}))
	var move_names := {"R": "Running", "C": "Crouching", "P": "Prone"}
	if move_names.has(move):
		_chips.add_child(_chip(move_names[move], _colored(hud.get("move", {}), Slate.INFO)))
	for carry in [["weight", "Weight"], ["volume", "Volume"]]:
		var info: Dictionary = hud.get(carry[0], {})
		if String(info.get("color", "c_light_gray")) != "c_light_gray":
			_chips.add_child(_chip("%s %s" % [carry[1], _text(info)], _colored(info, Slate.WARN)))
	# Safe mode is always shown, as in the sidebar; click it to switch.
	var safe := bool(hud.get("safe_mode", true))
	var safe_text := "Safe mode" if safe else ("Safe mode returning" if bool(hud.get("safe_auto", false)) else "Safe mode off")
	_chips.add_child(_chip(safe_text, Slate.curses(String(hud.get("safe_color", "")), Slate.GOOD),
			_with_key("Safe mode stops you when a monster comes into view. Click to switch", "safemode"), "safemode"))


func _update_status(hud: Dictionary) -> void:
	_clock_day.text = "%s · Day %d" % [String(hud.get("season", "")), int(hud.get("day", 1))]
	match String(hud.get("time_kind", "clock")):
		"clock":
			_clock_time.text = String(hud.get("time", ""))
			_clock_time.add_theme_font_override("font", Slate.mono_bold())
			_clock_time.add_theme_color_override("font_color", Slate.ACCENT)
		"approx":
			_clock_time.text = String(hud.get("time", ""))
			_clock_time.add_theme_font_override("font", Slate.bold())
			_clock_time.add_theme_color_override("font_color", Slate.ACCENT)
		_:
			_clock_time.text = "Time unknown"
			_clock_time.add_theme_font_override("font", Slate.bold())
			_clock_time.add_theme_color_override("font_color", Slate.MUTED)

	if bool(hud.get("underground", false)):
		_set_group("weather", "Underground", Slate.SOFT)
		(_groups["weather"][1] as TextureRect).texture = Slate.icon("layers", 16)
	else:
		var weather: Dictionary = hud.get("weather", {})
		_set_group("weather", _text(weather), _colored(weather, Slate.SOFT))
		(_groups["weather"][1] as TextureRect).texture = Slate.icon(_weather_icon(_text(weather)), 16)
	var temp := String(hud.get("temperature", "-"))
	if temp == "-" or temp == "":
		_set_group("temperature", "No thermometer", Slate.FAINT)
	else:
		_set_group("temperature", temp, Slate.SOFT)
	var light: Dictionary = hud.get("light", {})
	_set_group("light", _cap(_text(light)), _colored(light, Slate.SOFT))
	var wind: Dictionary = hud.get("wind", {})
	_set_group("wind", _text(wind), _colored(wind, Slate.SOFT))
	var angles := {"⇑": 0, "⇗": 45, "⇒": 90, "⇘": 135, "⇓": 180, "⇙": 225, "⇐": 270, "⇖": 315}
	var arrow := String(hud.get("wind_arrow", ""))
	_wind_arrow.visible = angles.has(arrow)
	_wind_arrow.rotation_degrees = float(angles.get(arrow, 0))
	_set_group("moon", String(hud.get("moon", "")))
	_set_group("place", _cap(String(hud.get("place", ""))), Slate.TEXT)
	_set_group("coords", String(hud.get("coords", "")), Slate.MUTED)
	_fit_header()


func _weather_icon(weather: String) -> String:
	var w := weather.to_lower()
	for pair in WEATHER_ICONS:
		if w.contains(pair[0]):
			return pair[1]
	return "cloud"


func _update_vehicle(veh: Dictionary) -> void:
	_vehicle_row.visible = not veh.is_empty()
	if veh.is_empty():
		return
	for c in _vehicle_row.get_children():
		c.queue_free()
	_vehicle_row.add_child(Slate.icon_rect("car", 18, Slate.SOFT))
	_vehicle_row.add_child(Slate.label(String(veh.get("name", "")), 14, Slate.TEXT, Slate.bold()))
	_vehicle_row.tooltip_text = "The vehicle you are controlling"
	_vehicle_row.add_child(_divider())
	_vehicle_row.add_child(Slate.label(String(veh.get("heading", "")), 14, Slate.SOFT, Slate.mono()))
	_vehicle_row.add_child(_divider())
	var speed: Dictionary = veh.get("speed", {})
	var speed_label := Slate.label("%s %s" % [_text(speed), String(veh.get("unit", ""))], 14,
			_colored(speed, Slate.INFO), Slate.mono_bold())
	speed_label.tooltip_text = "Speed; the color shows engine strain"
	speed_label.mouse_filter = Control.MOUSE_FILTER_PASS
	_vehicle_row.add_child(speed_label)
	if veh.has("cruise"):
		var cruise := Slate.label("→ %d" % int(veh["cruise"]), 14, Slate.curses("c_light_green"), Slate.mono())
		cruise.tooltip_text = "Cruise control speed"
		cruise.mouse_filter = Control.MOUSE_FILTER_PASS
		_vehicle_row.add_child(cruise)
	if veh.has("takeoff"):
		var takeoff: Dictionary = veh["takeoff"]
		_vehicle_row.add_child(_divider())
		_vehicle_row.add_child(Slate.icon_rect("plane", 16, Slate.MUTED))
		var lift := Slate.label(_text(takeoff), 14, _colored(takeoff, Slate.SOFT), Slate.mono())
		lift.tooltip_text = "Speed needed to take off"
		lift.mouse_filter = Control.MOUSE_FILTER_PASS
		_vehicle_row.add_child(lift)
	if veh.has("fuel"):
		var fuel: Dictionary = veh["fuel"]
		_vehicle_row.add_child(_divider())
		_vehicle_row.add_child(Slate.icon_rect("fuel", 16, Slate.MUTED))
		var gauge := FuelGauge.new(int(fuel.get("mark", 0)), _colored(fuel, Slate.WARN))
		gauge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_vehicle_row.add_child(gauge)
		_vehicle_row.add_child(Slate.label(String(fuel.get("name", "")), 13, Slate.MUTED))


func _update_map() -> void:
	var show: Dictionary = _hud.get("show", {})
	var has_local := bool(show.get("map", true))
	var mode := _map_mode if has_local else "area"
	_minimap.visible = mode == "local"
	_area.visible = mode == "area"
	_area.set_cells(_hud.get("area", []))
	_map_switch.visible = has_local
	for id in _map_buttons:
		var b: Button = _map_buttons[id]
		var on: bool = id == mode
		var sb := Slate.pill_box(Color(1, 1, 1, 0.10) if on else Color(0, 0, 0, 0), 10, 5)
		for state in ["normal", "hover", "pressed", "hover_pressed"]:
			b.add_theme_stylebox_override(state, sb)
		b.add_theme_color_override("font_color", Slate.TEXT if on else Slate.MUTED)
		b.add_theme_color_override("font_hover_color", Slate.TEXT)
		b.add_theme_color_override("font_pressed_color", Slate.TEXT)


func _update_threats(hud: Dictionary, show: Dictionary) -> void:
	_threats_box.visible = bool(show.get("compass", true))
	if not _threats_box.visible:
		return
	var compass: Dictionary = hud.get("compass", {})
	var total := 0
	var danger := false
	for d in compass.get("dirs", []):
		total += int(d.get("count", 0))
		danger = danger or bool(d.get("danger", false))
	_threat_count.text = "%d in view" % total if total > 0 else ""
	_threat_count.add_theme_color_override("font_color", Slate.DANGER if danger else Slate.MUTED)
	for c in _threat_list.get_children():
		c.queue_free()
	var list: Array = compass.get("list", [])
	if list.is_empty():
		_threat_list.add_child(Slate.label("Nothing in sight", 13, Slate.FAINT))
		return
	for i in mini(list.size(), 6):
		_threat_list.add_child(_threat_row(list[i]))
	if list.size() > 6:
		_threat_list.add_child(Slate.label("and %d more" % (list.size() - 6), 12, Slate.MUTED))


func _threat_row(entry: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var color := Slate.curses(String(entry.get("color", "")), Slate.SOFT)
	var badge := PanelContainer.new()
	badge.custom_minimum_size = Vector2(34, 34)
	badge.add_theme_stylebox_override("panel", Slate.box(Color(color, 0.16), 9, Color(color, 0.3), 1))
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sym := Slate.label(String(entry.get("sym", "?")), 16, color.lightened(0.1), Slate.mono_bold())
	sym.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sym.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_child(sym)
	row.add_child(badge)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 0)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text)
	var name := Slate.label(_cap(String(entry.get("name", ""))), 14, Slate.TEXT, Slate.bold())
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name.clip_text = true
	text.add_child(name)
	var danger := String(entry.get("danger", ""))
	var danger_color := Slate.curses(danger, Slate.MUTED) if danger in ["c_red", "c_light_red"] else Slate.MUTED
	text.add_child(Slate.label(String(THREAT_WORDS.get(danger, "")), 12, danger_color))
	var where := Slate.label(DIRS[clampi(int(entry.get("dir", 8)), 0, 8)], 13, Slate.SOFT, Slate.mono_bold())
	where.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(where)
	return row


func _update_widgets(widgets: Array) -> void:
	for c in _widgets.get_children():
		c.queue_free()
	_widgets.visible = not widgets.is_empty()
	for w in widgets:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 4)
		_widgets.add_child(col)
		col.add_child(_rule())
		col.add_child(_section_title(String(w.get("name", ""))))
		for line in w.get("lines", []):
			var l := Slate.rich(13)
			l.text = Slate.bbcode(line, Slate.SOFT)
			col.add_child(l)


func _update_log(messages: Array) -> void:
	for c in _log_list.get_children():
		c.queue_free()
	var n := messages.size()
	for i in n:
		var msg: Dictionary = messages[i]
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 9)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var age := n - 1 - i
		line.modulate.a = 1.0 if bool(msg.get("fresh", false)) else clampf(0.95 - age * 0.06, 0.4, 0.95)
		line.add_child(DotView.new(Slate.lead_color(msg.get("text", []), Slate.SOFT)))
		var text := Slate.rich(14)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.text = Slate.bbcode(msg.get("text", []), Slate.SOFT)
		line.add_child(text)
		_log_list.add_child(line)
	var key := _key("messages")
	_log_button.text = "Full log" + ("  ·  %s" % key if key != "" else "")


# --- Pieces --------------------------------------------------------------------------------------

## Body silhouette: each part filled with the color the sidebar gives its health, ringed in the
## sidebar's injury color (red bleeding, blue bitten, green infected), cracked when broken.
## Click a part to inspect it.
class BodyView extends Control:
	signal part_clicked(id: String)

	const SHAPES := {
		"head": Rect2(28, 0, 30, 30),
		"torso": Rect2(23, 36, 40, 62),
		"arm_r": Rect2(3, 38, 16, 62),
		"arm_l": Rect2(67, 38, 16, 62),
		"leg_r": Rect2(24, 103, 18, 70),
		"leg_l": Rect2(44, 103, 18, 70),
	}
	var parts := {}
	var hovered := ""
	var selected := ""
	var _time := 0.0

	func _init() -> void:
		custom_minimum_size = Vector2(86, 194)
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		tooltip_text = "Click a limb to inspect it"

	func set_parts(list: Array) -> void:
		parts.clear()
		for p in list:
			parts[String(p.get("id", ""))] = p
		queue_redraw()

	func _process(delta: float) -> void:
		# Injured parts pulse gently so they catch the eye.
		for id in parts:
			if String(parts[id].get("status", "c_light_gray")) != "c_light_gray":
				_time += delta
				queue_redraw()
				return

	func _fill(p: Dictionary) -> Color:
		var name := String(p.get("color", "c_green"))
		if name == "c_dark_gray":
			return Color("#4a5260")
		if name == "c_light_gray":
			return Color("#3a414c")
		return Slate.curses(name, Slate.GOOD)

	func _draw() -> void:
		for id in SHAPES:
			var rect: Rect2 = SHAPES[id]
			var p: Dictionary = parts.get(id, {})
			var sb := StyleBoxFlat.new()
			sb.bg_color = _fill(p)
			if id == hovered:
				sb.bg_color = sb.bg_color.lightened(0.18)
			sb.set_corner_radius_all(15 if id == "head" else 8)
			sb.anti_aliasing = true
			var status := String(p.get("status", "c_light_gray"))
			if id == selected:
				sb.border_color = Color(1, 1, 1, 0.95)
				sb.set_border_width_all(2)
				sb.set_expand_margin_all(4)
			elif status != "c_light_gray":
				sb.border_color = Color(Slate.curses(status, Slate.DANGER), 0.6 + 0.4 * sin(_time * 4.0))
				sb.set_border_width_all(3)
				sb.set_expand_margin_all(3)
			draw_style_box(sb, rect)
			if bool(p.get("broken", false)):
				# A jagged gap across the limb reads as a break; a splint shows as a bar beside it.
				var y := rect.position.y + rect.size.y * 0.5
				var x0 := rect.position.x - 1
				var w := rect.size.x + 2
				var crack := PackedVector2Array([Vector2(x0, y - 2), Vector2(x0 + w * 0.3, y + 3),
						Vector2(x0 + w * 0.55, y - 3), Vector2(x0 + w * 0.8, y + 2), Vector2(x0 + w, y - 1)])
				draw_polyline(crack, Slate.CARD_SOLID, 3.0, true)
				if bool(p.get("splinted", false)):
					var side := rect.position.x - 6 if rect.position.x < 43 else rect.end.x + 3
					draw_line(Vector2(side + 1.5, y - 16), Vector2(side + 1.5, y + 16), Slate.curses("c_light_blue", Slate.TEXT), 3.0, true)
		# The figure faces you, so its right side is on your left.
		var font := Slate.mono()
		draw_string(font, Vector2(26, 190), "R", HORIZONTAL_ALIGNMENT_CENTER, 14, 10, Slate.FAINT)
		draw_string(font, Vector2(46, 190), "L", HORIZONTAL_ALIGNMENT_CENTER, 14, 10, Slate.FAINT)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseMotion:
			var now := _part_at(event.position)
			if now != hovered:
				hovered = now
				queue_redraw()
				tooltip_text = "Click a limb to inspect it" if now == "" or not parts.has(now) else \
						"%s: click to inspect" % String(parts[now].get("label", ""))
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var id := _part_at(event.position)
			if id != "":
				part_clicked.emit(id)

	func _part_at(pos: Vector2) -> String:
		for id in SHAPES:
			if SHAPES[id].grow(3).has_point(pos):
				return id
		return ""

	func _notification(what: int) -> void:
		if what == NOTIFICATION_MOUSE_EXIT and hovered != "":
			hovered = ""
			queue_redraw()


## One limb in the body view: name, the sidebar's five-cell health bar, and its state.
class LimbRow extends PanelContainer:
	signal clicked(id: String)

	var id: String
	var _name: Label
	var _bar: SegmentBar
	var _state: Label

	func _init(part_id: String) -> void:
		id = part_id
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(row)
		_name = Slate.label("", 13, Slate.SOFT)
		_name.custom_minimum_size.x = 70
		row.add_child(_name)
		_bar = SegmentBar.new()
		_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(_bar)
		_state = Slate.label("", 12, Slate.SOFT, Slate.bold())
		_state.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_state.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_state.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_state.clip_text = true
		row.add_child(_state)

	func set_state(label: String, level: float, bar_color: Color, state: String, state_color: Color, selected: bool) -> void:
		_name.text = label.substr(0, 1).to_upper() + label.substr(1)
		_bar.set_level(level, bar_color)
		_state.text = state
		_state.add_theme_color_override("font_color", state_color)
		var sb := Slate.box(Color(1, 1, 1, 0.09) if selected else Color(0, 0, 0, 0), 7, Slate.BORDER, 0)
		sb.content_margin_left = 6
		sb.content_margin_right = 6
		sb.content_margin_top = 3
		sb.content_margin_bottom = 3
		add_theme_stylebox_override("panel", sb)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			clicked.emit(id)


## Five cells filled in half steps, like the sidebar's health bars.
class SegmentBar extends Control:
	var level := 1.0
	var color := Slate.GOOD

	func _init() -> void:
		custom_minimum_size = Vector2(80, 7)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_level(value: float, c: Color) -> void:
		level = clampf(value, 0.0, 1.0)
		color = c
		queue_redraw()

	func _draw() -> void:
		var gap := 3.0
		var w := (size.x - gap * 4) / 5.0
		for i in 5:
			var r := Rect2(i * (w + gap), 0, w, size.y)
			var track := StyleBoxFlat.new()
			track.bg_color = Slate.TRACK
			track.set_corner_radius_all(2)
			draw_style_box(track, r)
			var fill := clampf(level * 5.0 - i, 0.0, 1.0)
			if fill > 0.0:
				var bar := StyleBoxFlat.new()
				bar.bg_color = color
				bar.set_corner_radius_all(2)
				draw_style_box(bar, Rect2(r.position, Vector2(maxf(r.size.x * fill, 3), r.size.y)))


## One labelled need with a state word, an optional note and a bar.
class NeedRow extends VBoxContainer:
	var _state: Label
	var _note: Label
	var _bar: BarView
	var _bar_color: Variant = null

	func _init(title: String) -> void:
		add_theme_constant_override("separation", 4)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 6)
		top.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(top)
		var name := Slate.label(title, 13, Slate.MUTED)
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(name)
		_note = Slate.label("", 12, Slate.MUTED, Slate.semibold())
		_note.visible = false
		top.add_child(_note)
		_state = Slate.label("", 13, Slate.TEXT, Slate.bold())
		top.add_child(_state)
		_bar = BarView.new()
		add_child(_bar)

	func set_value(text: String, color: Color, fill: float) -> void:
		_state.text = text
		_state.add_theme_color_override("font_color", color)
		_bar.set_fill(fill, _bar_color if _bar_color != null else color)

	func set_bar_color(c: Color) -> void:
		_bar_color = c
		_bar.set_fill(_bar.fill, c)

	func set_note(text: String, color: Color) -> void:
		_note.text = text
		_note.visible = text != ""
		_note.add_theme_color_override("font_color", color)


class BarView extends Control:
	var fill := 1.0
	var color := Slate.GOOD

	func _init() -> void:
		custom_minimum_size = Vector2(0, 6)
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
			draw_style_box(bar, Rect2(Vector2.ZERO, Vector2(maxf(size.x * fill, 6), size.y)))


## The sidebar's fuel gauge (E, 1/4, 1/2, 3/4, F) as five marks, lit up to the current one.
class FuelGauge extends Control:
	var mark := 0
	var color := Slate.WARN

	func _init(m: int, c: Color) -> void:
		mark = m
		color = c
		custom_minimum_size = Vector2(63, 10)
		mouse_filter = Control.MOUSE_FILTER_PASS
		tooltip_text = ["Empty", "A quarter full", "Half full", "Three quarters full", "Full"][clampi(m, 0, 4)]

	func _draw() -> void:
		for i in 5:
			var sb := StyleBoxFlat.new()
			sb.bg_color = color if i <= mark and mark > 0 else Slate.TRACK
			if mark == 0 and i == 0:
				sb.bg_color = Slate.DANGER
			sb.set_corner_radius_all(2)
			draw_style_box(sb, Rect2(i * 13.0, 1, 10, 8))


## The overmap around the avatar, glyph by glyph as the game draws it, the avatar in the middle.
class AreaView extends Control:
	var cells: Array = []

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_cells(rows: Array) -> void:
		if rows != cells:
			cells = rows
			queue_redraw()

	func _draw() -> void:
		var n := cells.size()
		if n == 0:
			return
		var cell := minf(size.x, size.y) / n
		var origin := (size - Vector2(cell * n, cell * n)) / 2
		var f := Slate.mono_bold()
		var fs := int(cell * 0.62)
		for y in n:
			var row: Array = cells[y]
			for x in row.size():
				var c: Array = row[x]
				var rect := Rect2(origin + Vector2(x * cell, y * cell), Vector2(cell, cell))
				var bg := String(c[2]) if c.size() > 2 else "black"
				var fg := Slate.curses(String(c[1]))
				if bg != "black":
					draw_style_box(Slate.box(Slate.curses(bg), 6, Slate.BORDER, 0), rect.grow(-2))
					fg = Slate.GROUND
				var glyph := String(c[0])
				if glyph.strip_edges() == "":
					continue
				var w := f.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				var base := rect.position + Vector2((cell - w) / 2, (cell + f.get_ascent(fs) - f.get_descent(fs)) / 2)
				draw_string(f, base, glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, fg)


class DotView extends Control:
	var color: Color

	func _init(c: Color) -> void:
		color = c
		custom_minimum_size = Vector2(8, 20)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_circle(Vector2(4, 11), 4, color)


## Dock button: icon, label, and the key it is bound to.
class DockButton extends Button:
	var action: String
	var _key: Label
	var _name: Label
	var _hint: String

	func _init(action_id: String, title: String, icon_name: String, hint: String) -> void:
		action = action_id
		_hint = hint
		focus_mode = Control.FOCUS_NONE
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		custom_minimum_size = Vector2(70, 64)
		add_theme_stylebox_override("normal", Slate.box(Color(0, 0, 0, 0), 12, Slate.BORDER, 0))
		add_theme_stylebox_override("hover", Slate.box(Color(1, 1, 1, 0.08), 12, Slate.BORDER, 0))
		var down := Slate.box(Slate.ACCENT, 12, Slate.BORDER, 0)
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
		_name = Slate.label(title, 12, Slate.TEXT, Slate.bold())
		_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(_name)
		_key = Slate.label("", 10, Slate.MUTED, Slate.mono())
		_key.position = Vector2(0, 3)
		_key.size = Vector2(64, 14)
		_key.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		add_child(_key)
		pressed.connect(func(): Bridge.run_action(action))

	## Narrow buttons in small windows; without the label the tooltip still names the action.
	func set_width(width: int, labeled: bool) -> void:
		custom_minimum_size.x = width
		_name.visible = labeled
		_key.size = Vector2(width - 6, 14)

	func set_key(key: String) -> void:
		_key.text = key
		tooltip_text = "%s  (%s)" % [_hint, key] if key != "" else _hint
