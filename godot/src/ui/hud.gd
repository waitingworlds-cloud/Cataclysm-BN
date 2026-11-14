extends Control
## The main screen: a frame of modules around the map, which sits in a bordered viewport in the
## middle and never runs to the window's edges or under a panel.
##
##   top bar      who you are, the date, time and sky, a compass strip of what is in view, and
##                where you are
##   left column  body readout, needs and stats, and the event log
##   right column the pocket paper area map, everything in sight, and what is within reach
##   bottom deck  the wielded item, the hotbar, the move mode and the main actions
##
## Rebuilt from the `hud` message the game sends whenever the main view redraws. It shows
## everything the old sidebar did; parts the sidebar lets players switch off (compass, minimap,
## log, armor, mod panels) follow the sidebar options menu, opened with the gear button.
##
## Mouse: every button shows the key it presses. Limbs, needs, the log, creatures in sight and
## things in reach can all be clicked; right-click a map square for what can be done there.

const DisplayCard := preload("res://src/ui/display_card.gd")
const CommandPalette := preload("res://src/ui/command_palette.gd")
const HotbarStrip := preload("res://src/ui/hotbar_strip.gd")

## Deck buttons: action, label, icon, tooltip.
const DOCK := [
	["inventory", "Bag", "backpack", "Open your inventory"],
	["craft", "Craft", "hammer", "Craft items"],
	["construct", "Build", "brick-wall", "Build or deconstruct"],
	["pickup", "Pick up", "hand", "Pick up items nearby"],
	["look", "Look", "eye", "Look around"],
	["fire", "Fire", "crosshair", "Fire your weapon"],
	["wait", "Wait", "hourglass", "Wait or rest"],
	["map", "Map", "map", "Open the map"],
	["player_data", "You", "user-round", "View your character"],
	["#commands", "All", "search", "Find any command"],
]

## Needs shown as bars: hud member, label, the action a click runs, and its tooltip.
const NEEDS := [
	["thirst", "Thirst", "eat", "Click to eat or drink"],
	["hunger", "Hunger", "eat", "Click to eat or drink"],
	["fatigue", "Rest", "sleep", "Click to sleep"],
	["stamina", "Stamina", "", "Running and fighting use stamina"],
	["warmth", "Warmth", "", "Body temperature and where it is heading"],
	["pain", "Pain", "", "Pain slows you down"],
]

## Compass directions in the game's order: clockwise from north, then close by.
const DIRS := ["N", "NE", "E", "SE", "S", "SW", "W", "NW", "NEAR"]
const DIR_WORDS := ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west", "close by"]

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

## What each injury means, shown under the body readout.
const INJURY_NOTES := {
	"Bleeding": "Losing blood. Bandage it or apply pressure.",
	"Bitten": "Bitten. Disinfect it before it gets infected.",
	"Infected": "Infected. It needs antibiotics.",
	"Broken": "Broken. Splint it so it can mend.",
	"Broken, splinted": "Broken and splinted, mending.",
}

## Short labels for what can be done on a square within reach.
const REACH_LABELS := {
	"attack": "Attack", "talk": "Talk", "fire": "Fire", "open": "Open", "close": "Close",
	"pick_up": "Pick up", "butcher": "Butcher", "examine": "Examine", "jump": "Jump over",
	"walk": "Walk here", "describe": "Look closer",
}

const GUT := 8
const TOP_HEIGHT := 58
const DECK_HEIGHT := 128
## The frame's top and bottom bands, gutters included; screens docked beside the map sit
## between them.
const HEADER_HEIGHT := GUT + TOP_HEIGHT + GUT
const BAR_HEIGHT := GUT + DECK_HEIGHT + GUT
const LEFT_WIDTH := 400
const RIGHT_WIDTH := 360
const HEAD_HEIGHT := 30

## Weather words and the icon that fits them, checked in order.
const WEATHER_ICONS := [
	["thunder", "cloud-lightning"], ["lightning", "cloud-lightning"], ["snow", "cloud-snow"],
	["flurr", "cloud-snow"], ["sleet", "cloud-snow"], ["drizzle", "cloud-drizzle"], ["rain", "cloud-rain"],
	["fog", "cloud-fog"], ["mist", "cloud-fog"], ["haz", "cloud-fog"], ["overcast", "cloud"],
	["cloud", "cloud"], ["sunny", "sun"], ["clear", "sun"], ["fair", "cloud-sun"],
]

const PAPER_SHADER := "
shader_type canvas_item;
// The game's pixel minimap redrawn as ink on gray paper: the brighter a square, the darker
// its ink; what was never seen stays blank paper.
uniform vec3 paper = vec3(0.60, 0.59, 0.52);
uniform vec3 ink = vec3(0.13, 0.15, 0.15);
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float light = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	float amount = smoothstep(0.03, 0.80, light) * 0.78;
	// Uneven paper: a soft fold shadow and a little grain.
	float fold = 0.035 * (sin(UV.x * 9.4) + sin(UV.y * 7.1 + 1.3));
	float grain = fract(sin(dot(floor(UV * 420.0), vec2(12.9898, 78.233))) * 43758.5453) * 0.045;
	vec3 sheet = paper * (0.97 + fold) - grain;
	vec2 edge = smoothstep(vec2(0.0), vec2(0.10), UV) * smoothstep(vec2(0.0), vec2(0.10), 1.0 - UV);
	sheet *= mix(0.80, 1.0, edge.x * edge.y);
	COLOR = vec4(mix(sheet, ink, amount), 1.0);
}
"

var _hud := {}
var _keys := {}
var _selected_part := ""
var _map_mode := "local"
var _reach_pick := ""
var _left_width := float(LEFT_WIDTH)
var _right_width := float(RIGHT_WIDTH)

# Frame and bezel
var _frame: FrameView

# Top bar
var _identity: PanelContainer
var _name: Label
var _weapon: RichTextLabel
var _safe: Button
var _status: PanelContainer
var _status_row: HBoxContainer
var _clock_day: Label
var _clock_time: Label
var _compass: CompassStrip
## Sky readouts by id: [box, icon, label].
var _groups := {}
var _wanted := {}
var _wind_arrow: TextureRect
var _vehicle_row: HBoxContainer
var _place_box: PanelContainer
var _place: Label
var _coords: Label
var _map_button: Button

# Left column
var _left: VBoxContainer
var _vitals: Module
var _body: BodyView
var _limb_rows := {}
var _limb_list: VBoxContainer
var _limb_detail: VBoxContainer
var _alerts: VBoxContainer
var _armor_rows: VBoxContainer
var _needs_module: Module
var _needs := {}
var _stats := {}
var _stat_flow: HFlowContainer
var _widgets: VBoxContainer
var _log_module: Module
var _log_list: VBoxContainer
var _log_button: Button

# Right column
var _right: VBoxContainer
var _map_module: Module
var _map_view: Control
var _minimap: TextureRect
var _marks: MapMarks
var _area: AreaView
var _map_buttons := {}
var _map_switch: HBoxContainer
var _map_legend: Label
var _sight_module: Module
var _sight_list: VBoxContainer
var _sight_button: Button
var _reach_module: Module
var _reach_list: VBoxContainer

# Bottom deck
var _deck: PanelContainer
var _deck_row: HBoxContainer
var _wielded: ItemSlot
var _hotbar: HotbarStrip
var _mode_buttons := {}
var _mode_hint: HBoxContainer
var _dock_buttons := {}
var _options_button: Button

# Hover tip: what is under the mouse on the map (the game's "Mouse View" box), shown like a
# tooltip once the mouse rests. Kept short and always inside the map viewport.
const HOVER_DELAY := 0.35
const HOVER_WIDTH := 300
const HOVER_LINES := 7
var _hover: PanelContainer
var _hover_text: RichTextLabel
var _hover_title: Label
var _hover_acts: RichTextLabel
var _hover_on_map := false
var _hover_still := 0.0

var _last := {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame = FrameView.new()
	_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_frame)
	_build_top()
	_build_left()
	_build_right()
	_build_deck()
	_build_hover()
	Bridge.minimap_received.connect(func(texture: ImageTexture): _minimap.texture = texture)
	Bridge.connected.connect(_send_insets)
	Display.changed.connect(_layout)
	resized.connect(_layout)
	_layout()


# --- Layout --------------------------------------------------------------------------------------

## The map viewport: the space the frame leaves in the middle.
func map_rect() -> Rect2:
	var x := GUT + _left_width + GUT
	var y := GUT + TOP_HEIGHT + GUT
	return Rect2(x, y, maxf(size.x - x - GUT - _right_width - GUT, 80), maxf(size.y - y - GUT - DECK_HEIGHT - GUT, 80))


func _layout() -> void:
	# Narrow windows give the map room by slimming the columns.
	_left_width = clampf(size.x * 0.21, 320, LEFT_WIDTH)
	_right_width = clampf(size.x * 0.19, 280, RIGHT_WIDTH)
	var column_top := GUT + TOP_HEIGHT + GUT
	var column_height := maxf(size.y - column_top - GUT - DECK_HEIGHT - GUT, 80)
	_identity.position = Vector2(GUT, GUT)
	_identity.size = Vector2(_left_width, TOP_HEIGHT)
	_place_box.position = Vector2(size.x - GUT - _right_width, GUT)
	_place_box.size = Vector2(_right_width, TOP_HEIGHT)
	var map := map_rect()
	_status.position = Vector2(map.position.x, GUT)
	_status.size = Vector2(map.size.x, TOP_HEIGHT)
	_left.position = Vector2(GUT, column_top)
	_left.size = Vector2(_left_width, column_height)
	_right.position = Vector2(size.x - GUT - _right_width, column_top)
	_right.size = Vector2(_right_width, column_height)
	_map_view.custom_minimum_size = Vector2(0, roundf((_right_width - 2) * 0.72))
	_deck.position = Vector2(GUT, size.y - GUT - DECK_HEIGHT)
	_deck.size = Vector2(maxf(size.x - 2 * GUT, 80), DECK_HEIGHT)
	_frame.viewport = map
	_frame.queue_redraw()
	_fit_deck()
	_fit_status()
	# A panel can't be made smaller than its content, so set the sizes again now that the deck
	# and the status strip have been fitted to the new width.
	_deck.size = Vector2(maxf(size.x - 2 * GUT, 80), DECK_HEIGHT)
	_status.size = Vector2(map.size.x, TOP_HEIGHT)
	_send_insets()


## Tells the game which edges the frame covers, so it keeps the map view (and the player at its
## center) inside the viewport.
func _send_insets() -> void:
	var map := map_rect().grow(-2)
	Bridge.send({"t": "insets", "left": Display.to_game(map.position.x), "top": Display.to_game(map.position.y),
			"right": Display.to_game(size.x - map.end.x), "bottom": Display.to_game(size.y - map.end.y)})


# --- Shared pieces -------------------------------------------------------------------------------

func _panel(parent: Control = self, padding := 0) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Slate.module_box(padding))
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(p)
	return p


func _column() -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", GUT)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
	return col


func _spacer(height: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = height
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _vline(height := 0.0) -> ColorRect:
	var d := ColorRect.new()
	d.color = Slate.BORDER
	d.custom_minimum_size = Vector2(1, height)
	if height > 0.0:
		d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return d


func _rule() -> ColorRect:
	var d := ColorRect.new()
	d.color = Slate.BORDER
	d.custom_minimum_size = Vector2(0, 1)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return d


## Small outlined button with its key, e.g. `[P] FULL LOG`, for module headers and rows.
func _key_button(text: String, tooltip: String, run: Callable) -> Button:
	var b := KeyButton.new(text)
	b.tooltip_text = tooltip
	b.pressed.connect(run)
	return b


func _icon_button(icon_name: String, tooltip: String, box_size := 30, icon_size := 16) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.icon = Slate.icon(icon_name, icon_size)
	b.tooltip_text = tooltip
	b.custom_minimum_size = Vector2(box_size, box_size)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var sb := Slate.box(Color(Slate.CYAN, 0.05), 0, Slate.BORDER, 1)
	sb.set_content_margin_all(0)
	b.add_theme_stylebox_override("normal", sb)
	var hot := Slate.box(Color(Slate.CYAN, 0.18), 0, Slate.BORDER_STRONG, 1)
	hot.set_content_margin_all(0)
	b.add_theme_stylebox_override("hover", hot)
	b.add_theme_stylebox_override("pressed", hot)
	b.add_theme_color_override("icon_normal_color", Slate.MUTED)
	b.add_theme_color_override("icon_hover_color", Slate.TEXT)
	b.add_theme_color_override("icon_pressed_color", Slate.TEXT)
	return b


func _key(action: String) -> String:
	return String(_keys.get(action, ""))


func _with_key(text: String, action: String) -> String:
	var key := _key(action)
	return "%s  (%s)" % [text, key] if key != "" else text


## True when this part of the hud message changed since it was last drawn.
func _changed(id: String, value) -> bool:
	if _last.has(id) and _last[id] == value:
		return false
	_last[id] = value
	return true


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


# --- Top bar -------------------------------------------------------------------------------------

func _build_top() -> void:
	# Who you are.
	_identity = _panel()
	var id_row := HBoxContainer.new()
	id_row.add_theme_constant_override("separation", 10)
	var id_margin := _margin(id_row, 14, 5, 12, 5)
	_identity.add_child(id_margin)
	var id_col := VBoxContainer.new()
	id_col.add_theme_constant_override("separation", -2)
	id_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	id_col.alignment = BoxContainer.ALIGNMENT_CENTER
	id_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	id_row.add_child(id_col)
	_name = Slate.label("", 18, Slate.TEXT, Slate.spaced(Slate.heavy(), 1))
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name.clip_text = true
	_name.uppercase = true
	id_col.add_child(_name)
	# Not fitted to its text: a long weapon name is cut off instead of widening the module.
	_weapon = Slate.rich(11, false)
	_weapon.add_theme_font_override("normal_font", Slate.mono())
	_weapon.autowrap_mode = TextServer.AUTOWRAP_OFF
	_weapon.clip_contents = true
	_weapon.custom_minimum_size.y = 17
	_weapon.mouse_filter = Control.MOUSE_FILTER_PASS
	_weapon.tooltip_text = "What you are wielding, your fighting style and how you are moving"
	id_col.add_child(_weapon)
	_safe = Button.new()
	_safe.focus_mode = Control.FOCUS_NONE
	_safe.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_safe.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_safe.add_theme_font_override("font", Slate.mono())
	_safe.add_theme_font_size_override("font_size", Slate.fs(11))
	_safe.pressed.connect(func(): Bridge.run("safemode"))
	id_row.add_child(_safe)

	# Date, time, what is in view around you, and the sky.
	_status = _panel()
	_status_row = HBoxContainer.new()
	_status_row.add_theme_constant_override("separation", 14)
	_status_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status.add_child(_margin(_status_row, 16, 0, 16, 0))
	var clock := HBoxContainer.new()
	clock.add_theme_constant_override("separation", 12)
	clock.mouse_filter = Control.MOUSE_FILTER_PASS
	clock.tooltip_text = "Season, day and time. Without a watch the time is a guess, and underground there is none."
	_status_row.add_child(clock)
	_clock_day = Slate.label("", 14, Slate.TEXT, Slate.spaced(Slate.heading(), 1))
	_clock_day.uppercase = true
	clock.add_child(_clock_day)
	_clock_time = Slate.label("", 17, Slate.ACCENT, Slate.mono())
	clock.add_child(_clock_time)
	_status_row.add_child(_vline())
	_vehicle_row = HBoxContainer.new()
	_vehicle_row.add_theme_constant_override("separation", 10)
	_vehicle_row.mouse_filter = Control.MOUSE_FILTER_PASS
	_vehicle_row.visible = false
	_status_row.add_child(_vehicle_row)
	_compass = CompassStrip.new()
	_compass.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_row.add_child(_compass)
	_status_row.add_child(_vline())
	_groups["weather"] = _group("cloud", "Weather")
	_groups["temperature"] = _group("thermometer", "Temperature (needs a thermometer)")
	_groups["light"] = _group("sun-dim", "Light where you stand")
	_groups["wind"] = _group("wind", "Wind; the arrow shows where it blows")
	_wind_arrow = Slate.icon_rect("arrow-up", 13, Slate.SOFT)
	_wind_arrow.pivot_offset = Vector2(6.5, 6.5)
	_wind_arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_groups["wind"][0].add_child(_wind_arrow)
	_groups["moon"] = _group("moon", "Moon phase")

	# Where you are.
	_place_box = _panel()
	var place_row := HBoxContainer.new()
	place_row.add_theme_constant_override("separation", 10)
	_place_box.add_child(_margin(place_row, 14, 5, 12, 5))
	var place_col := VBoxContainer.new()
	place_col.add_theme_constant_override("separation", -2)
	place_col.alignment = BoxContainer.ALIGNMENT_CENTER
	place_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	place_col.mouse_filter = Control.MOUSE_FILTER_PASS
	place_col.tooltip_text = "Where you are, and your overmap coordinates"
	place_row.add_child(place_col)
	_coords = Slate.label("", 10, Slate.MUTED, Slate.mono())
	place_col.add_child(_coords)
	_place = Slate.label("", 15, Slate.TEXT, Slate.spaced(Slate.heading(), 1))
	_place.uppercase = true
	_place.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_place.clip_text = true
	place_col.add_child(_place)
	_map_button = _key_button("Map", "Open the map", func(): Bridge.run("map"))
	_map_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	place_row.add_child(_map_button)


func _margin(child: Control, left: int, top: int, right: int, bottom: int) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", left)
	m.add_theme_constant_override("margin_top", top)
	m.add_theme_constant_override("margin_right", right)
	m.add_theme_constant_override("margin_bottom", bottom)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(child)
	return m


## One sky readout in the top bar: [box, icon, label].
func _group(icon_name: String, tooltip: String) -> Array:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.tooltip_text = tooltip
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	_status_row.add_child(box)
	var icon := Slate.icon_rect(icon_name, 15, Slate.FAINT)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(icon)
	var label := Slate.label("", 12, Slate.SOFT, Slate.mono())
	label.uppercase = true
	box.add_child(label)
	return [box, icon, label]


func _set_group(id: String, text: String, color := Slate.SOFT) -> void:
	var g: Array = _groups[id]
	(g[2] as Label).text = text
	(g[2] as Label).add_theme_color_override("font_color", color)
	_wanted[id] = text != ""


## Shows every sky readout that fits, dropping the least important first in narrow windows.
## Whatever a narrow window hides is listed in the weather's tooltip, so nothing is lost.
func _fit_status() -> void:
	if _groups.is_empty():
		return
	for id in _groups:
		_groups[id][0].visible = bool(_wanted.get(id, false))
	var hidden: PackedStringArray = []
	for id in ["moon", "wind", "light", "temperature"]:
		if _status_needed() <= map_rect().size.x - 32:
			break
		if _groups[id][0].visible:
			_groups[id][0].visible = false
			hidden.append("%s: %s" % [_groups[id][0].tooltip_text.get_slice(" (", 0).get_slice(";", 0), _groups[id][2].text])
	hidden.reverse()
	_groups["weather"][0].tooltip_text = "\n".join(PackedStringArray(["Weather"]) + hidden)


func _status_needed() -> float:
	var total := 0.0
	var shown := 0
	for c in _status_row.get_children():
		if c is Control and c.visible:
			total += (c as Control).get_combined_minimum_size().x
			shown += 1
	return total + maxi(shown - 1, 0) * 14


# --- Left column: body, needs and the log -------------------------------------------------------

func _build_left() -> void:
	_left = _column()

	_vitals = Module.new("Rig // Vitals")
	_left.add_child(_vitals)
	var vitals := VBoxContainer.new()
	vitals.add_theme_constant_override("separation", 8)
	_vitals.set_body(vitals, 12, 10)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 14)
	vitals.add_child(top)
	_body = BodyView.new()
	_body.part_clicked.connect(_on_part_clicked)
	top.add_child(_body)
	_limb_list = VBoxContainer.new()
	_limb_list.add_theme_constant_override("separation", 0)
	_limb_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_limb_list.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_child(_limb_list)
	_limb_detail = VBoxContainer.new()
	_limb_detail.add_theme_constant_override("separation", 3)
	vitals.add_child(_limb_detail)
	_alerts = VBoxContainer.new()
	_alerts.add_theme_constant_override("separation", 6)
	vitals.add_child(_alerts)
	_armor_rows = VBoxContainer.new()
	_armor_rows.add_theme_constant_override("separation", 2)
	vitals.add_child(_armor_rows)

	_needs_module = Module.new("Needs // State")
	_left.add_child(_needs_module)
	var needs := VBoxContainer.new()
	needs.add_theme_constant_override("separation", 10)
	_needs_module.set_body(needs, 12, 10)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 9)
	needs.add_child(grid)
	for need in NEEDS:
		var cell := NeedCell.new(need[1], need[2], need[3])
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(cell)
		_needs[need[0]] = cell
	needs.add_child(_rule())
	_stat_flow = HFlowContainer.new()
	_stat_flow.add_theme_constant_override("h_separation", 14)
	_stat_flow.add_theme_constant_override("v_separation", 3)
	needs.add_child(_stat_flow)
	for stat in [["mood", "Mood"], ["focus", "Focus"], ["speed", "Spd"], ["move", "Move"], ["noise", "Noise"],
			["str", "Str"], ["dex", "Dex"], ["int", "Int"], ["per", "Per"], ["weight", "Weight"], ["volume", "Vol"],
			["power", "Power"], ["mana", "Mana"], ["goal", "Goal"]]:
		var pair := StatPair.new(stat[1])
		_stat_flow.add_child(pair)
		_stats[stat[0]] = pair

	# Panels that Lua mods add to the sidebar.
	_widgets = VBoxContainer.new()
	_widgets.add_theme_constant_override("separation", GUT)
	_widgets.visible = false
	_left.add_child(_widgets)

	# The log fills the rest of the column, newest at the bottom; older lines scroll off the top.
	_log_module = Module.new("Event log")
	_log_module.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_left.add_child(_log_module)
	_log_button = _key_button("Full log", "Read the whole message log", func(): Bridge.run("messages"))
	_log_module.head.add_child(_log_button)
	var clip := Control.new()
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_STOP
	clip.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	clip.tooltip_text = "Click to read the whole log"
	clip.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			Bridge.run("messages"))
	_log_module.set_body(clip, 12, 8)
	_log_list = VBoxContainer.new()
	_log_list.add_theme_constant_override("separation", 5)
	_log_list.anchor_top = 1.0
	_log_list.anchor_bottom = 1.0
	_log_list.anchor_right = 1.0
	_log_list.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_log_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.add_child(_log_list)


func _on_part_clicked(id: String) -> void:
	# Clicking the part being inspected again closes its details.
	_selected_part = "" if _selected_part == id else id
	_body.selected = _selected_part
	_body.queue_redraw()
	_last.erase("body")
	_update_body()


# --- Right column: area map, in sight, in reach --------------------------------------------------

func _build_right() -> void:
	_right = _column()

	_map_module = Module.new("Area map")
	_right.add_child(_map_module)
	_map_switch = HBoxContainer.new()
	_map_switch.add_theme_constant_override("separation", 4)
	_map_module.head.add_child(_map_switch)
	for mode in [["local", "Nearby", "The area around you, square by square"],
			["area", "Overmap", "The overmap around you, with notes, your mission and hordes"]]:
		var b := Button.new()
		b.text = String(mode[1]).to_upper()
		b.tooltip_text = mode[2]
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.add_theme_font_override("font", Slate.mono())
		b.add_theme_font_size_override("font_size", Slate.fs(10))
		var id: String = mode[0]
		b.pressed.connect(func():
			_map_mode = id
			_update_map())
		_map_switch.add_child(b)
		_map_buttons[id] = b
	_map_view = Control.new()
	_map_view.clip_contents = true
	_map_view.mouse_filter = Control.MOUSE_FILTER_STOP
	_map_view.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_map_view.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			Bridge.run("map"))
	_map_module.set_body(_map_view, 0, 0)
	var paper := ColorRect.new()
	paper.color = Color("#99968a")
	paper.set_anchors_preset(Control.PRESET_FULL_RECT)
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_view.add_child(paper)
	_minimap = TextureRect.new()
	_minimap.set_anchors_preset(Control.PRESET_FULL_RECT)
	_minimap.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_minimap.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_minimap.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = PAPER_SHADER
	var material := ShaderMaterial.new()
	material.shader = shader
	_minimap.material = material
	_map_view.add_child(_minimap)
	_marks = MapMarks.new()
	_marks.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_view.add_child(_marks)
	_area = AreaView.new()
	_area.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_view.add_child(_area)
	var legend := PanelContainer.new()
	var legend_box := StyleBoxFlat.new()
	legend_box.bg_color = Color(0.10, 0.11, 0.10, 0.55)
	legend_box.content_margin_left = 10
	legend_box.content_margin_top = 1
	legend_box.content_margin_bottom = 2
	legend.add_theme_stylebox_override("panel", legend_box)
	legend.anchor_top = 1.0
	legend.anchor_bottom = 1.0
	legend.anchor_right = 1.0
	legend.grow_vertical = Control.GROW_DIRECTION_BEGIN
	legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_view.add_child(legend)
	_map_legend = Slate.label("", 10, Color("#e8e6da"), Slate.mono())
	legend.add_child(_map_legend)

	_sight_module = Module.new("In sight", Slate.DANGER)
	_right.add_child(_sight_module)
	_sight_button = _key_button("List", "List everything in view", func(): Bridge.run("listitems"))
	_sight_module.head.add_child(_sight_button)
	_sight_list = VBoxContainer.new()
	_sight_list.add_theme_constant_override("separation", 0)
	_sight_module.set_body(_sight_list, 0, 4)

	_reach_module = Module.new("In reach", Slate.ACCENT)
	_reach_module.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_right.add_child(_reach_module)
	var reach_clip := Control.new()
	reach_clip.clip_contents = true
	reach_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reach_module.set_body(reach_clip, 12, 10)
	_reach_list = VBoxContainer.new()
	_reach_list.add_theme_constant_override("separation", 8)
	_reach_list.anchor_right = 1.0
	_reach_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reach_clip.add_child(_reach_list)


# --- Bottom deck ---------------------------------------------------------------------------------

func _build_deck() -> void:
	_deck = _panel()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	_deck.add_child(_margin(row, 16, 8, 10, 8))
	_deck_row = row

	var wield_col := _deck_block("Wielded")
	row.add_child(wield_col)
	_wielded = ItemSlot.new(84)
	_wielded.mouse_filter = Control.MOUSE_FILTER_STOP
	_wielded.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_wielded.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			Bridge.run("wield"))
	wield_col.add_child(_wielded)

	var hotbar_col := _deck_block("Hotbar // Alt + number")
	row.add_child(hotbar_col)
	_hotbar = HotbarStrip.new(84)
	hotbar_col.add_child(_hotbar)
	row.add_child(_vline())

	var mode_col := _deck_block("Move mode")
	mode_col.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(mode_col)
	var modes := HBoxContainer.new()
	modes.add_theme_constant_override("separation", 0)
	mode_col.add_child(modes)
	for mode in [["W", "Walk", "reset_move"], ["R", "Run", "toggle_run"], ["C", "Crouch", "toggle_crouch"],
			["P", "Prone", "toggle_prone"]]:
		var b := Button.new()
		b.text = String(mode[1]).to_upper()
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.add_theme_font_override("font", Slate.spaced(Slate.bold(), 1))
		b.add_theme_font_size_override("font_size", Slate.fs(12))
		b.custom_minimum_size = Vector2(0, 30)
		var action: String = mode[2]
		b.pressed.connect(func(): Bridge.run(action))
		modes.add_child(b)
		_mode_buttons[mode[0]] = b
	_mode_hint = HBoxContainer.new()
	_mode_hint.add_theme_constant_override("separation", 6)
	mode_col.add_child(_mode_hint)

	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(gap)

	var dock := HBoxContainer.new()
	dock.add_theme_constant_override("separation", 0)
	row.add_child(dock)
	for entry in DOCK:
		var button := DockButton.new(entry[0], entry[1], entry[2], entry[3])
		if entry[0] == "#commands":
			button.pressed.connect(open_commands)
		dock.add_child(button)
		_dock_buttons[entry[0]] = button

	# View tools: map zoom, the display card and the HUD options.
	var tools := GridContainer.new()
	tools.columns = 2
	tools.add_theme_constant_override("h_separation", 4)
	tools.add_theme_constant_override("v_separation", 4)
	tools.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(tools)
	for z in [["zoom_in", "zoom-in", "Zoom the map in"], ["zoom_out", "zoom-out", "Zoom the map out"],
			["#display", "monitor", "Display: interface and map size (Ctrl =, Ctrl −, with Shift for the map)"],
			["toggle_panel_adm", "settings", "HUD options"]]:
		var b := _icon_button(z[1], z[2], 34, 17)
		var action: String = z[0]
		if action == "#display":
			b.pressed.connect(_open_display_card)
		else:
			b.pressed.connect(func(): Bridge.run(action))
		tools.add_child(b)
		if action == "toggle_panel_adm":
			_options_button = b


func _deck_block(title: String) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := Slate.label(title.to_upper(), 10, Slate.MUTED, Slate.mono())
	label.name = "Title"
	col.add_child(label)
	return col


func open_commands() -> void:
	if get_node_or_null("CommandPalette") == null:
		var palette := CommandPalette.new()
		palette.name = "CommandPalette"
		add_child(palette)


func _open_display_card() -> void:
	if get_node_or_null("DisplayCard") == null:
		var card := DisplayCard.new()
		card.name = "DisplayCard"
		add_child(card)


## Narrow windows shrink the item slots first, then drop the labels under the action icons.
func _fit_deck() -> void:
	if _hotbar == null:
		return
	var room := size.x - 2 * GUT - 28
	for option in [[84.0, 72, true], [72.0, 72, true], [64.0, 64, true], [56.0, 60, true], [56.0, 46, false],
			[48.0, 46, false], [40.0, 40, false]]:
		var side: float = option[0]
		_wielded.custom_minimum_size = Vector2(side, side)
		_hotbar.set_side(side)
		for b in _dock_buttons.values():
			(b as DockButton).set_width(option[1], option[2])
		if _deck_row.get_combined_minimum_size().x <= room:
			break


# --- Hover tip -----------------------------------------------------------------------------------

func _build_hover() -> void:
	_hover = PanelContainer.new()
	var sb := Slate.box(Slate.RAISED, 10, Slate.BORDER_STRONG, 1)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 9
	sb.shadow_color = Color(0, 0, 0, 0.4)
	sb.shadow_size = 6
	_hover.add_theme_stylebox_override("panel", sb)
	_hover.custom_minimum_size.x = HOVER_WIDTH
	_hover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover.visible = false
	add_child(_hover)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover.add_child(col)
	_hover_title = Slate.label("", 12, Slate.TEXT, Slate.heading())
	_hover_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_hover_title.clip_text = true
	col.add_child(_hover_title)
	_hover_text = Slate.rich(12)
	_hover_text.add_theme_color_override("default_color", Slate.SOFT)
	_hover_text.add_theme_constant_override("line_separation", 1)
	# Its own width from the start, so the first tip doesn't wrap at zero width and come out tall.
	_hover_text.custom_minimum_size.x = HOVER_WIDTH - 24
	col.add_child(_hover_text)
	_hover_acts = Slate.rich(11)
	_hover_acts.add_theme_color_override("default_color", Slate.MUTED)
	_hover_acts.custom_minimum_size.x = HOVER_WIDTH - 24
	col.add_child(_hover_acts)


## Called by the window as the mouse enters or leaves the map.
func set_map_hover(on: bool) -> void:
	_hover_on_map = on
	_hover_still = 0.0
	_update_hover()


## Called on every mouse move over the map: the tip hides until the mouse rests again.
func map_mouse_moved() -> void:
	_hover_still = 0.0
	_update_hover()


func _process(delta: float) -> void:
	if _hover_still < HOVER_DELAY:
		_hover_still += delta
		if _hover_still >= HOVER_DELAY:
			_update_hover()


## The game's description of a square, cut down to what fits a tooltip: the first few lines,
## with a note when there is more (Look, or a right-click, has the rest).
func _hover_body(spans: Array) -> String:
	var lines := Slate.tidy_body(Slate.bbcode(spans, Slate.SOFT)).split("\n")
	var kept: PackedStringArray = []
	for line in lines:
		if line.strip_edges() == "" and (kept.is_empty() or kept[kept.size() - 1] == ""):
			continue
		kept.append(line)
	while not kept.is_empty() and kept[kept.size() - 1].strip_edges() == "":
		kept.remove_at(kept.size() - 1)
	if kept.size() > HOVER_LINES:
		kept = kept.slice(0, HOVER_LINES)
		kept.append("[color=#%s]…  right-click for actions[/color]" % _hex(Slate.FAINT))
	return "\n".join(kept)


## The short tip for a square in plain view: who or what is there, a few facts, and what a
## right-click offers.
func _show_tip(tip: Dictionary) -> void:
	var tone := String(tip.get("tone", ""))
	var tones := {"hostile": Slate.DANGER, "friendly": Slate.GOOD, "neutral": Slate.WARN}
	_hover_title.visible = true
	_hover_title.text = String(tip.get("title", "")).to_upper()
	_hover_title.add_theme_color_override("font_color", tones.get(tone, Slate.TEXT))
	var lines: PackedStringArray = []
	for line in (tip.get("lines", []) as Array).slice(0, HOVER_LINES):
		var text := Slate.cap(String(line[0]).strip_edges().trim_suffix("."))
		if text != "":
			lines.append("[color=#%s]%s[/color]" % [_hex(Slate.curses(String(line[1]))), Slate.escape(text)])
	_hover_text.visible = not lines.is_empty()
	_hover_text.text = "\n".join(lines)
	var acts: Array = tip.get("acts", [])
	_hover_acts.visible = not acts.is_empty()
	if not acts.is_empty():
		var names: PackedStringArray = []
		for act in acts:
			names.append(Slate.escape(String(REACH_LABELS.get(String(act), String(act)))))
		_hover_acts.text = "[color=#%s]RIGHT-CLICK[/color]  %s" % [_hex(Slate.CYAN), "  ·  ".join(names)]


func _update_hover() -> void:
	var spans: Array = _hud.get("hover", [])
	var tip: Dictionary = _hud.get("tip", {})
	var show := _hover_on_map and _hover_still >= HOVER_DELAY and not (spans.is_empty() and tip.is_empty())
	_hover.visible = show
	if not show:
		return
	if tip.is_empty():
		# A square that can't be seen clearly: the game's own few words for it.
		_hover_title.visible = false
		_hover_acts.visible = false
		_hover_text.visible = true
		_hover_text.text = _hover_body(spans)
	else:
		_show_tip(tip)
	_hover.reset_size()
	# Beside the mouse and always inside the map viewport: flipped to the left or lifted up
	# near the viewport's edges.
	var mouse := get_local_mouse_position()
	var card := _hover.get_combined_minimum_size()
	var area := map_rect().grow(-8)
	var at := mouse + Vector2(18, 18)
	if at.x + card.x > area.end.x:
		at.x = mouse.x - 18 - card.x
	if at.y + card.y > area.end.y:
		at.y = mouse.y - 18 - card.y
	at.x = clampf(at.x, area.position.x, maxf(area.position.x, area.end.x - card.x))
	at.y = clampf(at.y, area.position.y, maxf(area.position.y, area.end.y - card.y))
	_hover.position = at


# --- Updates -------------------------------------------------------------------------------------

func apply(hud: Dictionary) -> void:
	_hud = hud
	_keys = hud.get("keys", {})
	var show: Dictionary = hud.get("show", {})

	_update_identity(hud)
	_update_body()
	_update_alerts(hud)
	_update_armor(hud, show)
	_update_needs(hud)
	_update_stats(hud)
	_update_status(hud)
	_update_vehicle(hud.get("vehicle", {}))
	_update_map()
	_update_sight(hud, show)
	var reach := _reach_sorted(hud.get("reach", []))
	_update_reach(reach)
	_update_widgets(hud.get("widgets", []))
	_log_module.visible = bool(show.get("log", true))
	_update_log(hud.get("messages", []))
	_update_deck(hud)
	_frame.set_tags(_level_name(hud), "Zoom %d× // Ctrl Shift + / −" % Display.map_scale())
	_frame.set_targets(hud.get("view", {}), hud.get("sight", []) if bool(show.get("compass", true)) else [],
			_reach_target(reach))
	_update_hover()


func _level_name(hud: Dictionary) -> String:
	var z := int(hud.get("z", 0))
	if z == 0:
		return "View // Ground level"
	return "View // %d %s ground" % [absi(z), "above" if z > 0 else "below"]


func _update_identity(hud: Dictionary) -> void:
	_name.text = String(hud.get("name", ""))
	var runs := []
	for run in hud.get("weapon", []):
		runs.append([String(run[0]).to_upper(), run[1] if run.size() > 1 else ""])
	var weapon := Slate.bbcode(runs, Slate.MUTED)
	var style := String(hud.get("style", ""))
	if style != "" and style != "No style":
		# The sidebar shows the style red when armed and blue when fighting bare-handed.
		var style_color := Slate.curses("c_red" if bool(hud.get("armed", false)) else "c_light_blue", Slate.MUTED)
		weapon += "[color=#%s] // [/color][color=#%s]%s[/color]" % [_hex(Slate.FAINT), _hex(style_color), _escape(style).to_upper()]
	var modes := {"W": "WALKING", "R": "RUNNING", "C": "CROUCHING", "P": "PRONE"}
	var move := _text(hud.get("move", {}))
	weapon += "[color=#%s] // [/color][color=#%s]%s[/color]" % [_hex(Slate.FAINT), _hex(Slate.MUTED), String(modes.get(move, "WALKING"))]
	_weapon.text = weapon

	# Safe mode is always shown, as in the sidebar; click it to switch.
	var safe := bool(hud.get("safe_mode", true))
	var color := Slate.curses(String(hud.get("safe_color", "")), Slate.GOOD)
	_safe.text = "SAFE MODE" if safe else ("SAFE RETURNING" if bool(hud.get("safe_auto", false)) else "SAFE MODE OFF")
	_safe.tooltip_text = _with_key("Safe mode stops you when a monster comes into view. Click to switch", "safemode")
	var sb := Slate.box(Color(color, 0.10), 0, Color(color, 0.7), 1)
	sb.content_margin_left = 7
	sb.content_margin_right = 7
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	var hot := sb.duplicate() as StyleBoxFlat
	hot.bg_color = Color(color, 0.25)
	_safe.add_theme_stylebox_override("normal", sb)
	_safe.add_theme_stylebox_override("hover", hot)
	_safe.add_theme_stylebox_override("pressed", hot)
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		_safe.add_theme_color_override(state, color)


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
		return "%d/%d" % [int(p["cur"]), int(p["max"])]
	if bool(p.get("broken", false)):
		return "Mending"
	return String(HEALTH_WORDS.get(String(p.get("color", "")), ""))


func _update_body() -> void:
	var parts: Array = _hud.get("body", [])
	if not _changed("body", [parts, _selected_part]):
		return
	_body.set_parts(parts)
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
		var injured := String(p.get("status", "c_light_gray")) != "c_light_gray"
		_limb_rows[id].set_state(String(p.get("label", "")), float(p.get("level", 0)),
				Slate.health_color(String(p.get("color", ""))), _health_word(p), injured, id == _selected_part)
		if id == _selected_part:
			selected = p
	_vitals.set_note("Click a limb to inspect" if selected.is_empty() else "")

	for c in _limb_detail.get_children():
		c.queue_free()
	_limb_detail.visible = not selected.is_empty()
	if selected.is_empty():
		return
	_limb_detail.add_child(_rule())
	var title := HBoxContainer.new()
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_limb_detail.add_child(title)
	var name := Slate.label(String(selected.get("label", "")).to_upper(), 13, Slate.TEXT, Slate.spaced(Slate.heading(), 1))
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_child(name)
	var word := String(HEALTH_WORDS.get(String(selected.get("color", "")), ""))
	title.add_child(Slate.label(word.to_upper(), 11, Slate.health_color(String(selected.get("color", ""))), Slate.mono()))
	var states := _part_state(selected)
	if states.is_empty():
		_limb_detail.add_child(Slate.label("No bleeding, bites, infection or breaks.", 12, Slate.MUTED))
	for s in states:
		var color := Slate.curses(String(selected.get("status", "")), Slate.SOFT) if not String(s).begins_with("Broken") else Slate.SOFT
		var line := Slate.label(String(INJURY_NOTES.get(s, s)), 12, color)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_limb_detail.add_child(line)
	var worn := Slate.rich(12)
	worn.autowrap_mode = TextServer.AUTOWRAP_OFF
	worn.clip_contents = true
	worn.text = "[color=#%s]Outer layer   [/color]%s" % [_hex(Slate.FAINT), Slate.bbcode(selected.get("armor", []), Slate.SOFT)]
	_limb_detail.add_child(worn)


## Injuries as striped alerts under the body readout: one per kind, naming the parts.
func _update_alerts(hud: Dictionary) -> void:
	var injuries := {}
	var colors := {}
	for p in hud.get("body", []):
		for s in _part_state(p):
			var kind := String(s)
			if not injuries.has(kind):
				injuries[kind] = []
				colors[kind] = Slate.SOFT if kind.begins_with("Broken") else Slate.curses(String(p.get("status", "")), Slate.DANGER)
			injuries[kind].append(String(p.get("label", "")))
	if not _changed("alerts", [injuries, _key("apply")]):
		return
	for c in _alerts.get_children():
		c.queue_free()
	_alerts.visible = not injuries.is_empty()
	for kind in injuries:
		var treat := not String(kind).begins_with("Broken, splinted")
		_alerts.add_child(AlertBox.new("%s // %s" % [String(kind).get_slice(",", 0), ", ".join(injuries[kind])],
				String(INJURY_NOTES.get(kind, "")), colors[kind], _key("apply") if treat else "", "Use item"))


## The sidebar's armor panel, when it is switched on: the outer layer on each body part.
func _update_armor(hud: Dictionary, show: Dictionary) -> void:
	var armor: Array = hud.get("armor", []) if bool(show.get("armor", false)) else []
	if not _changed("armor", armor):
		return
	for c in _armor_rows.get_children():
		c.queue_free()
	_armor_rows.visible = not armor.is_empty()
	if armor.is_empty():
		return
	_armor_rows.add_child(_rule())
	_armor_rows.add_child(Slate.label("OUTER LAYERS", 10, Slate.MUTED, Slate.mono()))
	for slot in armor:
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var l := Slate.label(String(slot.get("label", "")).to_upper(), 11, Slate.MUTED, Slate.mono())
		l.custom_minimum_size.x = 64
		row.add_child(l)
		var item := Slate.rich(12)
		item.autowrap_mode = TextServer.AUTOWRAP_OFF
		item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		item.clip_contents = true
		item.text = Slate.bbcode(slot.get("item", []), Slate.SOFT)
		row.add_child(item)
		_armor_rows.add_child(row)


func _update_needs(hud: Dictionary) -> void:
	for id in ["thirst", "hunger", "fatigue"]:
		var info: Dictionary = hud.get(id, {})
		var text := _text(info)
		var color_name := String(info.get("color", "c_white"))
		var cell: NeedCell = _needs[id]
		cell.set_value(text if text != "" else "Fine", Slate.curses(color_name, Slate.CYAN) if text != "" else Slate.CYAN,
				Slate.severity(color_name) if text != "" else 1.0)
		cell.set_key(_key(cell.action))
	var stamina: Dictionary = hud.get("stamina", {})
	var stamina_color := _colored(stamina, Slate.CYAN)
	if String(stamina.get("color", "")) in ["c_green", "c_light_green", ""]:
		stamina_color = Slate.CYAN
	_needs["stamina"].set_value(String(stamina.get("text", "")), stamina_color, float(stamina.get("level", 0)))
	var warm: Dictionary = hud.get("body_temp", {})
	var trend: Dictionary = hud.get("body_temp_trend", {})
	var warm_name := String(warm.get("color", ""))
	var warm_color := Slate.CYAN if warm_name in ["c_green", "c_light_green", "c_white", ""] else _colored(warm, Slate.CYAN)
	_needs["warmth"].set_value(_text(warm), warm_color, Slate.severity(warm_name))
	_needs["warmth"].set_note(_text(trend).trim_prefix("(").trim_suffix(")"))
	var pain: Dictionary = hud.get("pain", {})
	var pain_text := _text(pain)
	_needs["pain"].set_value(pain_text if pain_text != "" else "None", _colored(pain, Slate.DANGER) if pain_text != "" else Slate.CYAN,
			1.0 - Slate.severity(String(pain.get("color", ""))) if pain_text != "" else 0.0)


func _update_stats(hud: Dictionary) -> void:
	var morale := int(hud.get("morale", 0))
	_stats["mood"].set_value(String(hud.get("morale_face", "")), Slate.curses(String(hud.get("morale_color", "")), Slate.SOFT),
			"Mood: morale %+d" % morale)
	var focus: Dictionary = hud.get("focus", {})
	var trend := int(hud.get("focus_trend", 0))
	var arrow := "↑" if trend > 0 else ("↓" if trend < 0 else "")
	var trend_words := ", rising" if trend > 0 else (", falling" if trend < 0 else ", steady")
	_stats["focus"].set_value(_text(focus) + arrow, _colored(focus), "Focus %s%s" % [_text(focus), trend_words])
	var speed: Dictionary = hud.get("speed", {})
	_stats["speed"].set_value(_text(speed), _colored(speed), "Speed %s; 100 is normal" % _text(speed))
	var move: Dictionary = hud.get("move", {})
	var modes := {"W": "walking", "R": "running", "C": "crouching", "P": "prone"}
	var cost := int(hud.get("move_cost", 0))
	_stats["move"].set_value(str(cost), _colored(move, Slate.SOFT),
			"Your last step cost %d moves; you are %s" % [cost, String(modes.get(_text(move), "walking"))])
	if bool(hud.get("deaf", false)):
		_stats["noise"].set_value("Deaf", Slate.DANGER, "You can't hear anything")
	else:
		var sound := String(hud.get("sound", ""))
		_stats["noise"].set_value(sound if sound != "" else "–", Slate.WARN if bool(hud.get("noisy", false)) else Slate.SOFT,
				"How much noise you are making")
	for stat in [["str", "Strength"], ["dex", "Dexterity"], ["int", "Intelligence"], ["per", "Perception"]]:
		var info: Dictionary = hud.get(stat[0], {})
		_stats[stat[0]].set_value(_text(info), _colored(info), stat[1])
	_stats["weight"].set_value(_text(hud.get("weight", {})), _colored(hud.get("weight", {}), Slate.SOFT), "Weight carried, against what you can carry")
	_stats["volume"].set_value(_text(hud.get("volume", {})), _colored(hud.get("volume", {}), Slate.SOFT), "Volume carried, against the room you have")
	var power: Dictionary = hud.get("power", {})
	_stats["power"].visible = _text(power) != "--" and _text(power) != ""
	_stats["power"].set_value(_text(power), _colored(power, Slate.INFO), "Bionic power")
	_stats["mana"].visible = hud.has("mana")
	if hud.has("mana"):
		var mana: Dictionary = hud["mana"]
		_stats["mana"].set_value("%s/%d" % [_text(mana), int(hud.get("mana_max", 0))], _colored(mana, Slate.INFO), "Mana")
	_stats["goal"].visible = hud.has("goal")
	if hud.has("goal"):
		_stats["goal"].set_value(String(hud["goal"]), Slate.SOFT, "What your character needs most")


func _update_status(hud: Dictionary) -> void:
	_clock_day.text = "%s // Day %d" % [String(hud.get("season", "")), int(hud.get("day", 1))]
	match String(hud.get("time_kind", "clock")):
		"clock":
			_clock_time.text = String(hud.get("time", ""))
			_clock_time.add_theme_color_override("font_color", Slate.ACCENT)
		"approx":
			_clock_time.text = String(hud.get("time", "")).to_upper()
			_clock_time.add_theme_color_override("font_color", Slate.ACCENT)
		_:
			_clock_time.text = "TIME UNKNOWN"
			_clock_time.add_theme_color_override("font_color", Slate.MUTED)

	if bool(hud.get("underground", false)):
		_set_group("weather", "Underground", Slate.SOFT)
		(_groups["weather"][1] as TextureRect).texture = Slate.icon("layers", 15)
	else:
		var weather: Dictionary = hud.get("weather", {})
		_set_group("weather", _text(weather), _colored(weather, Slate.SOFT))
		(_groups["weather"][1] as TextureRect).texture = Slate.icon(_weather_icon(_text(weather)), 15)
	var temp := String(hud.get("temperature", "-"))
	if temp == "-" or temp == "":
		_set_group("temperature", "No thermometer", Slate.FAINT)
	else:
		_set_group("temperature", temp, Slate.SOFT)
	var light: Dictionary = hud.get("light", {})
	_set_group("light", _text(light), _colored(light, Slate.SOFT))
	var wind: Dictionary = hud.get("wind", {})
	_set_group("wind", _text(wind), _colored(wind, Slate.SOFT))
	var angles := {"⇑": 0, "⇗": 45, "⇒": 90, "⇘": 135, "⇓": 180, "⇙": 225, "⇐": 270, "⇖": 315}
	var arrow := String(hud.get("wind_arrow", ""))
	_wind_arrow.visible = angles.has(arrow)
	_wind_arrow.rotation_degrees = float(angles.get(arrow, 0))
	_set_group("moon", String(hud.get("moon", "")))
	_place.text = String(hud.get("place", ""))
	_coords.text = "LOCATION // %s" % String(hud.get("coords", ""))
	_map_button.set_key(_key("map"))
	var compass: Dictionary = hud.get("compass", {})
	_compass.visible = bool(hud.get("show", {}).get("compass", true))
	_compass.set_dirs(compass.get("dirs", []))
	_fit_status()


func _weather_icon(weather: String) -> String:
	var w := weather.to_lower()
	for pair in WEATHER_ICONS:
		if w.contains(pair[0]):
			return pair[1]
	return "cloud"


func _update_vehicle(veh: Dictionary) -> void:
	if not _changed("vehicle", veh):
		return
	_vehicle_row.visible = not veh.is_empty()
	for c in _vehicle_row.get_children():
		c.queue_free()
	if veh.is_empty():
		return
	_vehicle_row.add_child(Slate.icon_rect("car", 17, Slate.CYAN))
	_vehicle_row.add_child(Slate.label(String(veh.get("name", "")).to_upper(), 13, Slate.TEXT, Slate.heading()))
	_vehicle_row.tooltip_text = "The vehicle you are controlling"
	_vehicle_row.add_child(Slate.label(String(veh.get("heading", "")), 13, Slate.SOFT, Slate.mono()))
	var speed: Dictionary = veh.get("speed", {})
	var speed_label := Slate.label("%s %s" % [_text(speed), String(veh.get("unit", ""))], 14,
			_colored(speed, Slate.INFO), Slate.mono())
	speed_label.tooltip_text = "Speed; the color shows engine strain"
	speed_label.mouse_filter = Control.MOUSE_FILTER_PASS
	_vehicle_row.add_child(speed_label)
	if veh.has("cruise"):
		var cruise := Slate.label("→ %d" % int(veh["cruise"]), 13, Slate.curses("c_light_green"), Slate.mono())
		cruise.tooltip_text = "Cruise control speed"
		cruise.mouse_filter = Control.MOUSE_FILTER_PASS
		_vehicle_row.add_child(cruise)
	if veh.has("takeoff"):
		var takeoff: Dictionary = veh["takeoff"]
		_vehicle_row.add_child(Slate.icon_rect("plane", 15, Slate.MUTED))
		var lift := Slate.label(_text(takeoff), 13, _colored(takeoff, Slate.SOFT), Slate.mono())
		lift.tooltip_text = "Speed needed to take off"
		lift.mouse_filter = Control.MOUSE_FILTER_PASS
		_vehicle_row.add_child(lift)
	if veh.has("fuel"):
		var fuel: Dictionary = veh["fuel"]
		_vehicle_row.add_child(Slate.icon_rect("fuel", 15, Slate.MUTED))
		var gauge := FuelGauge.new(int(fuel.get("mark", 0)), _colored(fuel, Slate.WARN))
		gauge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_vehicle_row.add_child(gauge)
		_vehicle_row.add_child(Slate.label(String(fuel.get("name", "")).to_upper(), 11, Slate.MUTED, Slate.mono()))
	_vehicle_row.add_child(_vline())


func _update_map() -> void:
	var show: Dictionary = _hud.get("show", {})
	var has_local := bool(show.get("map", true))
	var mode := _map_mode if has_local else "area"
	_minimap.visible = mode == "local"
	_marks.visible = mode == "local"
	_area.visible = mode == "area"
	_area.set_cells(_hud.get("area", []))
	var info: Dictionary = _hud.get("minimap", {})
	_marks.set_sight(_hud.get("sight", []), float(info.get("tile", 3.0)), _minimap)
	_map_switch.visible = has_local
	_map_legend.text = "○ you   × seen threat   · other" if mode == "local" else "overmap around you"
	_map_view.tooltip_text = _with_key("Click to open the map", "map")
	_map_module.set_note("North up" if not has_local else "")
	for id in _map_buttons:
		var b: Button = _map_buttons[id]
		var on: bool = id == mode
		var sb := Slate.box(Color(Slate.CYAN, 0.20) if on else Color(0, 0, 0, 0), 0, Color(Slate.CYAN, 0.55 if on else 0.25), 1)
		sb.content_margin_left = 6
		sb.content_margin_right = 6
		sb.content_margin_top = 0
		sb.content_margin_bottom = 0
		for state in ["normal", "hover", "pressed", "hover_pressed"]:
			b.add_theme_stylebox_override(state, sb)
		b.add_theme_color_override("font_color", Slate.TEXT if on else Slate.MUTED)
		b.add_theme_color_override("font_hover_color", Slate.TEXT)
		b.add_theme_color_override("font_pressed_color", Slate.TEXT)


## Every creature in view, nearest first, with how far and which way. The sidebar's compass
## switch decides whether it shows. Click one for what you can do about it.
func _update_sight(hud: Dictionary, show: Dictionary) -> void:
	_sight_module.visible = bool(show.get("compass", true))
	if not _sight_module.visible:
		return
	var sight: Array = hud.get("sight", [])
	if not _changed("sight", [sight, _key("listitems"), _right_width]):
		return
	var hostile := sight.any(func(s): return bool(s.get("hostile", false)))
	_sight_module.set_title("In sight  %02d" % sight.size(), Slate.DANGER if hostile else Slate.CYAN)
	_sight_button.set_key(_key("listitems"))
	for c in _sight_list.get_children():
		c.queue_free()
	if sight.is_empty():
		var none := Slate.label("Nothing in sight.", 13, Slate.FAINT)
		_sight_list.add_child(_margin(none, 14, 4, 12, 6))
		return
	var room := 6
	var lead := true
	for i in mini(sight.size(), room):
		var row := SightRow.new(sight[i], lead and bool(sight[i].get("hostile", false)))
		lead = lead and not bool(sight[i].get("hostile", false))
		_sight_list.add_child(row)
	if sight.size() > room:
		var more := Slate.label("+ %d MORE // %s LIST" % [sight.size() - room, _key("listitems")], 11, Slate.MUTED, Slate.mono())
		_sight_list.add_child(_margin(more, 14, 3, 12, 3))


## What is on your square and the eight around it: bodies, items, doors, furniture, people.
## The first is laid out in full with its actions; the rest are one line each.
func _update_reach(reach: Array) -> void:
	if not _changed("reach", [reach, _reach_pick, _right_width]):
		return
	for c in _reach_list.get_children():
		c.queue_free()
	if reach.is_empty():
		var none := Slate.label("Nothing within reach. Right-click a map square for what you can do there.", 13, Slate.FAINT)
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_reach_list.add_child(none)
		return
	var lead := 0
	for i in reach.size():
		if _reach_key(reach[i]) == _reach_pick:
			lead = i
	_reach_list.add_child(_reach_lead(reach[lead]))
	var shown := 0
	for i in reach.size():
		if i == lead:
			continue
		if shown >= 4:
			_reach_list.add_child(Slate.label("+ %d MORE NEARBY" % (reach.size() - 1 - shown), 11, Slate.MUTED, Slate.mono()))
			break
		_reach_list.add_child(_reach_line(reach[i]))
		shown += 1


## What is in reach with the most pressing first: threats, then other creatures, then items,
## then things like doors and furniture, and bare ground last. The game's own order (here, then clockwise from
## north) holds within each group.
static func _reach_sorted(reach: Array) -> Array:
	var ranked := []
	for i in reach.size():
		var e: Dictionary = reach[i]
		var rank := 3
		if bool(e.get("hostile", false)):
			rank = 0
		elif bool(e.get("critter", false)):
			rank = 1
		elif int(e.get("count", 0)) > 0:
			rank = 2
		elif bool(e.get("plain", false)):
			rank = 4
		ranked.append([rank, i, e])
	ranked.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	return ranked.map(func(r): return r[2])


## The thing in reach that is laid out in full, as the map marks it: its square, name, note and
## the key of its first action. Empty when nothing is in reach.
func _reach_target(reach: Array) -> Dictionary:
	if reach.is_empty():
		return {}
	var lead: Dictionary = reach[0]
	for entry in reach:
		if _reach_key(entry) == _reach_pick:
			lead = entry
	var options: Array = lead.get("options", [])
	var count := int(lead.get("count", 0))
	var parts := PackedStringArray([String(lead.get("title", ""))])
	if count > 0:
		parts.append("%d item%s" % [count, "" if count == 1 else "s"])
	if not options.is_empty():
		parts.append(_reach_label(lead, options[0]))
	return {"dx": int(lead.get("dx", 0)), "dy": int(lead.get("dy", 0)), "hostile": bool(lead.get("hostile", false)),
			"tag": " // ".join(parts)}


static func _reach_key(entry: Dictionary) -> String:
	return "%d,%d" % [int(entry.get("dx", 0)), int(entry.get("dy", 0))]


static func _reach_where(entry: Dictionary) -> String:
	var dir := int(entry.get("dir", 8))
	return "HERE" if dir >= 8 else String(DIR_WORDS[dir]).to_upper()


static func _reach_note(entry: Dictionary) -> String:
	var count := int(entry.get("count", 0))
	var where := _reach_where(entry)
	if count > 0:
		return "%d ITEM%s // %s" % [count, "" if count == 1 else "S", where]
	return where


func _reach_label(entry: Dictionary, option: Dictionary) -> String:
	var id := String(option.get("id", ""))
	if id == "pick_up" and bool(entry.get("corpse", false)):
		return "Loot"
	return String(REACH_LABELS.get(id, String(option.get("text", ""))))


func _reach_lead(entry: Dictionary) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 7)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var offset := Vector2i(int(entry.get("dx", 0)), int(entry.get("dy", 0)))
	var hostile := bool(entry.get("hostile", false))
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(head)
	var title := Slate.label(String(entry.get("title", "")).to_upper(), 16, Slate.DANGER if hostile else Slate.ACCENT, Slate.spaced(Slate.heavy(), 1))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.clip_text = true
	head.add_child(title)
	var note := Slate.label(_reach_note(entry), 11, Slate.MUTED, Slate.mono())
	note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(note)

	var items: Array = entry.get("items", [])
	if not items.is_empty():
		var strip := HBoxContainer.new()
		strip.add_theme_constant_override("separation", 5)
		strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(strip)
		var side := floorf((_right_width - 26 - 5 * 5) / 6.0)
		var room := 6 if items.size() <= 6 else 5
		for i in mini(items.size(), room):
			var it: Dictionary = items[i]
			var slot := ItemSlot.new(side)
			slot.set_item(String(it.get("type", "")), String(it.get("sym", "?")), Slate.curses(String(it.get("color", "c_white"))))
			var n := int(it.get("count", 1))
			slot.count = "x%d" % n if n > 1 else ""
			slot.mouse_filter = Control.MOUSE_FILTER_STOP
			slot.tooltip_text = String(it.get("name", ""))
			strip.add_child(slot)
		if items.size() > room:
			var more := Slate.label("+%d" % (int(entry.get("kinds", items.size())) - room), 14, Slate.MUTED, Slate.mono())
			more.custom_minimum_size = Vector2(side, side)
			more.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			more.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			strip.add_child(more)

	var options: Array = entry.get("options", [])
	for i in options.size():
		var option: Dictionary = options[i]
		var choice := String(option.get("id", ""))
		var b := ReachButton.new(_reach_label(entry, option).to_upper(), Slate.key_name(String(option.get("key", ""))), i == 0, hostile)
		b.tooltip_text = String(option.get("text", ""))
		b.pressed.connect(func(): Bridge.square(offset, choice))
		col.add_child(b)
	return col


func _reach_line(entry: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var offset := Vector2i(int(entry.get("dx", 0)), int(entry.get("dy", 0)))
	var pick := _reach_key(entry)
	var text := Button.new()
	text.flat = true
	text.focus_mode = Control.FOCUS_NONE
	text.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	text.alignment = HORIZONTAL_ALIGNMENT_LEFT
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.clip_text = true
	text.text = "%s  //  %s" % [Slate.cap(String(entry.get("title", ""))), _reach_note(entry).to_lower()]
	text.tooltip_text = "Click to show its actions"
	text.add_theme_font_override("font", Slate.body())
	text.add_theme_font_size_override("font_size", Slate.fs(13))
	text.add_theme_color_override("font_color", Slate.DANGER if bool(entry.get("hostile", false)) else Slate.SOFT)
	var plain := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "focus"]:
		text.add_theme_stylebox_override(state, plain)
	text.pressed.connect(func():
		_reach_pick = pick
		_update_reach(_reach_sorted(_hud.get("reach", []))))
	row.add_child(text)
	var options: Array = entry.get("options", [])
	if not options.is_empty():
		var option: Dictionary = options[0]
		var choice := String(option.get("id", ""))
		var b := _key_button(_reach_label(entry, option), String(option.get("text", "")), func(): Bridge.square(offset, choice))
		(b as KeyButton).set_key(Slate.key_name(String(option.get("key", ""))))
		row.add_child(b)
	return row


func _update_widgets(widgets: Array) -> void:
	if not _changed("widgets", widgets):
		return
	for c in _widgets.get_children():
		c.queue_free()
	_widgets.visible = not widgets.is_empty()
	for w in widgets:
		var module := Module.new(String(w.get("name", "")))
		_widgets.add_child(module)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 2)
		module.set_body(col, 12, 8)
		for line in w.get("lines", []):
			var l := Slate.rich(13)
			l.text = Slate.bbcode(line, Slate.SOFT)
			col.add_child(l)


func _update_log(messages: Array) -> void:
	_log_button.set_key(_key("messages"))
	if not _changed("log", messages):
		return
	for c in _log_list.get_children():
		c.queue_free()
	var n := messages.size()
	for i in n:
		var msg: Dictionary = messages[i]
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var age := n - 1 - i
		line.modulate.a = 1.0 if bool(msg.get("fresh", false)) else clampf(0.92 - age * 0.06, 0.38, 0.92)
		var mark := Slate.label(">", 12, Slate.lead_color(msg.get("text", []), Slate.CYAN), Slate.mono())
		mark.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		line.add_child(mark)
		var text := Slate.rich(12)
		text.add_theme_font_override("normal_font", Slate.mono())
		text.add_theme_constant_override("line_separation", 1)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.text = Slate.bbcode(msg.get("text", []), Slate.SOFT)
		line.add_child(text)
		_log_list.add_child(line)


func _update_deck(hud: Dictionary) -> void:
	var wielded = hud.get("wielded", null)
	if typeof(wielded) == TYPE_DICTIONARY:
		_wielded.selected = true
		_wielded.tag = "HANDS"
		_wielded.set_item(String(wielded.get("type", "")), String(wielded.get("sym", "?")), Slate.curses(String(wielded.get("color", "c_white"))))
		_wielded.tooltip_text = _with_key("%s\nClick to wield something else" % String(wielded.get("name", "")), "wield")
	else:
		_wielded.clear()
		_wielded.tag = "HANDS"
		_wielded.tooltip_text = _with_key("Bare hands. Click to wield something", "wield")
	_hotbar.apply(hud.get("hotbar", []))

	var move := _text(hud.get("move", {}))
	if move == "":
		move = "W"
	for id in _mode_buttons:
		var b: Button = _mode_buttons[id]
		var on: bool = id == move
		var sb := Slate.box(Slate.CYAN if on else Color(0, 0, 0, 0), 0, Color(Slate.CYAN, 0.9 if on else 0.3), 1)
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		var hot := sb.duplicate() as StyleBoxFlat
		if not on:
			hot.bg_color = Color(Slate.CYAN, 0.15)
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", hot)
		b.add_theme_stylebox_override("pressed", hot)
		for state in ["font_color", "font_hover_color", "font_pressed_color"]:
			b.add_theme_color_override(state, Slate.ACCENT_TEXT if on else Slate.SOFT)
		var action: String = {"W": "reset_move", "R": "toggle_run", "C": "toggle_crouch", "P": "toggle_prone"}[id]
		b.tooltip_text = _with_key({"W": "Walk", "R": "Run: faster, uses stamina", "C": "Crouch: slower and quieter, harder to see",
				"P": "Go prone"}[id], action)
	if _changed("mode_hint", _key("cycle_move")):
		for c in _mode_hint.get_children():
			c.queue_free()
		if _key("cycle_move") != "":
			_mode_hint.add_child(Slate.key_chip(Slate.key_name(_key("cycle_move")), 11))
			_mode_hint.add_child(Slate.label("cycle", 12, Slate.MUTED))

	for action in _dock_buttons:
		_dock_buttons[action].set_key("^K" if action == "#commands" else Slate.key_name(_key(action)))
	_options_button.tooltip_text = _with_key("HUD options: choose what the HUD shows", "toggle_panel_adm")


# --- Pieces --------------------------------------------------------------------------------------

## The gunmetal frame around the map viewport and the viewport's bezel: a cyan border, corner
## brackets and two small tags. It swallows clicks on the frame so they don't reach the map
## underneath.
class FrameView extends Control:
	var viewport := Rect2()
	var _tag_top := ""
	var _tag_bottom := ""
	var _targets: Array = []

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _has_point(point: Vector2) -> bool:
		return not viewport.grow(-2).has_point(point)

	func set_tags(top: String, bottom: String) -> void:
		if top != _tag_top or bottom != _tag_bottom:
			_tag_top = top
			_tag_bottom = bottom
			queue_redraw()

	## Marks on the map: red brackets on each hostile creature in sight (the nearest gets a
	## name tag), yellow brackets on the thing in reach that the right column lays out.
	func set_targets(view: Dictionary, sight: Array, reach: Dictionary) -> void:
		var state := [view, sight, reach]
		if state != _targets:
			_targets = state
			queue_redraw()

	## The square `offset` squares from the player, in interface units; empty when the game
	## did not say where squares are (isometric tilesets).
	func _square(offset: Vector2) -> Rect2:
		var view: Dictionary = _targets[0]
		if view.is_empty():
			return Rect2()
		var scale := Display.frame_scale()
		var tile := Vector2(float(view.get("w", 0)), float(view.get("h", 0)))
		var at := Vector2(float(view.get("x", 0)), float(view.get("y", 0))) + offset * tile
		return Rect2(at * scale, tile * scale)

	func _draw_brackets(rect: Rect2, color: Color) -> void:
		var arm := maxf(rect.size.x * 0.28, 5.0)
		var r := rect.grow(3)
		for corner in [[r.position, Vector2(1, 1)], [Vector2(r.end.x, r.position.y), Vector2(-1, 1)],
				[Vector2(r.position.x, r.end.y), Vector2(1, -1)], [r.end, Vector2(-1, -1)]]:
			var at: Vector2 = corner[0]
			var way: Vector2 = corner[1]
			draw_polyline(PackedVector2Array([at + Vector2(arm * way.x, 0), at, at + Vector2(0, arm * way.y)]), color, 2.0)

	## A small label beside a marked square, kept inside the viewport.
	func _draw_target_tag(rect: Rect2, text: String, color: Color) -> void:
		var font := Slate.mono()
		var fs := Slate.fs(10)
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 14
		var area := viewport.grow(-12)
		var at := Vector2(rect.end.x + 12, rect.get_center().y - 9)
		if at.x + w > area.end.x:
			at.x = rect.position.x - 12 - w
		at.x = clampf(at.x, area.position.x, maxf(area.position.x, area.end.x - w))
		at.y = clampf(at.y, area.position.y, area.end.y - 18)
		var box := Rect2(at, Vector2(w, 18))
		draw_rect(box, Color(Slate.CARD, 0.9))
		draw_rect(box.grow(-0.5), color, false, 1.0)
		draw_string(font, Vector2(at.x + 7, at.y + 13), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)

	func _draw_targets() -> void:
		if _targets.is_empty() or (_targets[0] as Dictionary).is_empty():
			return
		var inside := viewport.grow(-6)
		var tagged := false
		var marked := 0
		for s in _targets[1]:
			if not bool(s.get("hostile", false)) or marked >= 16:
				continue
			var rect := _square(Vector2(float(s.get("dx", 0)), float(s.get("dy", 0))))
			if not inside.encloses(rect.grow(3)):
				continue
			marked += 1
			_draw_brackets(rect, Slate.DANGER)
			if not tagged:
				tagged = true
				var words := PackedStringArray([String(s.get("name", "")), "%d %s" % [int(s.get("dist", 0)),
						DIRS[clampi(int(s.get("dir", 8)), 0, 8)]], String(s.get("health", ""))])
				_draw_target_tag(rect, " // ".join(words).to_upper(), Slate.DANGER)
		var reach: Dictionary = _targets[2]
		if not reach.is_empty() and not bool(reach.get("hostile", false)):
			var offset := Vector2(float(reach.get("dx", 0)), float(reach.get("dy", 0)))
			var rect := _square(offset)
			if offset != Vector2.ZERO and inside.encloses(rect.grow(3)):
				_draw_brackets(rect, Slate.ACCENT)
				_draw_target_tag(rect, String(reach.get("tag", "")).to_upper(), Slate.ACCENT)

	func _draw() -> void:
		var v := viewport
		_draw_targets()
		# The frame: everything outside the viewport.
		draw_rect(Rect2(0, 0, size.x, v.position.y), Slate.GROUND)
		draw_rect(Rect2(0, v.end.y, size.x, size.y - v.end.y), Slate.GROUND)
		draw_rect(Rect2(0, v.position.y, v.position.x, v.size.y), Slate.GROUND)
		draw_rect(Rect2(v.end.x, v.position.y, size.x - v.end.x, v.size.y), Slate.GROUND)
		# The bezel.
		draw_rect(v.grow(-1), Color(Slate.CYAN, 0.75), false, 2.0)
		draw_rect(v.grow(-2.5), Color(0, 0, 0, 0.55), false, 1.0)
		var arm := 22.0
		var inset := v.grow(-9)
		for corner in [[inset.position, Vector2(1, 1)], [Vector2(inset.end.x, inset.position.y), Vector2(-1, 1)],
				[Vector2(inset.position.x, inset.end.y), Vector2(1, -1)], [inset.end, Vector2(-1, -1)]]:
			var at: Vector2 = corner[0]
			var way: Vector2 = corner[1]
			draw_polyline(PackedVector2Array([at + Vector2(arm * way.x, 0), at, at + Vector2(0, arm * way.y)]), Slate.CYAN, 2.0)
		var mono := Slate.mono()
		var fs := Slate.fs(10)
		if _tag_top != "":
			_draw_tag(mono, fs, _tag_top.to_upper(), Vector2(inset.position.x + arm + 8, inset.position.y - 1), false)
		if _tag_bottom != "":
			_draw_tag(mono, fs, _tag_bottom.to_upper(), Vector2(inset.end.x - arm - 8, inset.end.y - 15), true)

	func _draw_tag(font: Font, fs: int, text: String, at: Vector2, right: bool) -> void:
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var box := Rect2(at.x - (w + 14 if right else 0.0), at.y, w + 14, 17)
		draw_rect(box, Color(Slate.CARD, 0.86))
		draw_rect(box.grow(-0.5), Color(Slate.CYAN, 0.5), false, 1.0)
		draw_string(font, Vector2(box.position.x + 7, box.position.y + 12.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Slate.CYAN)


## One module of the frame: a header strip with a marker and a title, then its body.
class Module extends PanelContainer:
	var head: HBoxContainer
	var _marker: ColorRect
	var _title: Label
	var _note: Label
	var _col: VBoxContainer

	func _init(title: String, tone := Slate.CYAN) -> void:
		add_theme_stylebox_override("panel", Slate.module_box(0))
		mouse_filter = Control.MOUSE_FILTER_STOP
		_col = VBoxContainer.new()
		_col.add_theme_constant_override("separation", 0)
		_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_col)
		var strip := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Slate.RAISED
		sb.border_color = Slate.BORDER
		sb.border_width_bottom = 1
		sb.corner_radius_top_left = 7
		sb.corner_detail = 1
		sb.content_margin_left = 12
		sb.content_margin_right = 8
		strip.add_theme_stylebox_override("panel", sb)
		strip.custom_minimum_size.y = HEAD_HEIGHT
		strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_col.add_child(strip)
		head = HBoxContainer.new()
		head.add_theme_constant_override("separation", 8)
		head.mouse_filter = Control.MOUSE_FILTER_IGNORE
		strip.add_child(head)
		_marker = ColorRect.new()
		_marker.custom_minimum_size = Vector2(7, 7)
		_marker.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		head.add_child(_marker)
		_title = Slate.label("", 12, tone, Slate.spaced(Slate.heavy(), 2))
		_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(_title)
		_note = Slate.label("", 10, Slate.MUTED, Slate.mono())
		_note.visible = false
		head.add_child(_note)
		set_title(title, tone)

	func set_title(title: String, tone := Slate.CYAN) -> void:
		_title.text = title.to_upper()
		_title.add_theme_color_override("font_color", tone)
		_marker.color = tone

	## Small note at the right of the header.
	func set_note(text: String) -> void:
		_note.text = text.to_upper()
		_note.visible = text != ""

	func set_body(body: Control, pad_h := 12, pad_v := 10) -> void:
		var m := MarginContainer.new()
		m.add_theme_constant_override("margin_left", pad_h)
		m.add_theme_constant_override("margin_right", pad_h)
		m.add_theme_constant_override("margin_top", pad_v)
		m.add_theme_constant_override("margin_bottom", pad_v)
		m.size_flags_vertical = Control.SIZE_EXPAND_FILL
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		m.add_child(body)
		_col.add_child(m)


## Outlined button with the key it presses in a box, e.g. `[P] FULL LOG`.
class KeyButton extends Button:
	var _chip: Label
	var _text: Label

	func _init(text: String) -> void:
		focus_mode = Control.FOCUS_NONE
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var plain := StyleBoxEmpty.new()
		for state in ["normal", "hover", "pressed", "focus"]:
			add_theme_stylebox_override(state, plain)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(row)
		_chip = Slate.label("", 10, Slate.CYAN, Slate.mono())
		_chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_chip.custom_minimum_size = Vector2(18, 17)
		_chip.visible = false
		row.add_child(_chip)
		_text = Slate.label(text.to_upper(), 10, Slate.MUTED, Slate.mono())
		row.add_child(_text)
		row.resized.connect(func(): custom_minimum_size = row.get_combined_minimum_size())
		mouse_entered.connect(func(): _text.add_theme_color_override("font_color", Slate.TEXT))
		mouse_exited.connect(func(): _text.add_theme_color_override("font_color", Slate.MUTED))
		_chip.draw.connect(func(): _chip.draw_rect(Rect2(Vector2(0.5, 0.5), _chip.size - Vector2(1, 1)), Color(Slate.CYAN, 0.6), false, 1.0))
		custom_minimum_size = Vector2(0, 17)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func set_key(key: String) -> void:
		_chip.text = " %s " % key if key.length() > 1 else key
		_chip.visible = key != ""
		custom_minimum_size = (get_child(0) as Control).get_combined_minimum_size()


## A big action on something in reach. The first is hazard yellow; the rest are outlined.
class ReachButton extends Button:
	func _init(label: String, key: String, primary: bool, danger := false) -> void:
		focus_mode = Control.FOCUS_NONE
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		custom_minimum_size = Vector2(0, 38 if primary else 34)
		var fill := Slate.DANGER if danger else Slate.ACCENT
		var normal := Slate.box(fill if primary else Color(0, 0, 0, 0), 12 if primary else 0, Color(Slate.CYAN, 0.35), 0 if primary else 1)
		var hot := Slate.box(fill.lightened(0.25) if primary else Color(Slate.CYAN, 0.14), 12 if primary else 0, Slate.BORDER_STRONG, 0 if primary else 1)
		add_theme_stylebox_override("normal", normal)
		add_theme_stylebox_override("hover", hot)
		add_theme_stylebox_override("pressed", hot)
		var ink := Slate.ACCENT_TEXT if primary else Slate.TEXT
		var row := HBoxContainer.new()
		row.set_anchors_preset(Control.PRESET_FULL_RECT)
		row.offset_left = 12
		row.offset_right = -10
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(row)
		var text := Slate.label(label, 15 if primary else 14, ink, Slate.spaced(Slate.heading(), 2))
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		if key != "":
			var chip := Slate.label(" %s " % key if key.length() > 1 else key, 11, ink if primary else Slate.CYAN, Slate.mono())
			chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			chip.custom_minimum_size = Vector2(20, 19)
			chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			var edge := Color(ink, 0.8) if primary else Color(Slate.CYAN, 0.6)
			chip.draw.connect(func(): chip.draw_rect(Rect2(Vector2(0.5, 0.5), chip.size - Vector2(1, 1)), edge, false, 1.0))
			row.add_child(chip)


## Body figure: each part outlined and filled in its health color, with the spine as a column
## of cells. Injured parts pulse in the sidebar's injury color (red bleeding, blue bitten,
## green infected); a broken part is cracked. Click a part to inspect it.
class BodyView extends Control:
	signal part_clicked(id: String)

	const SHAPES := {
		"head": Rect2(30, 2, 24, 24),
		"torso": Rect2(26, 32, 32, 58),
		"arm_r": Rect2(8, 34, 13, 56),
		"arm_l": Rect2(63, 34, 13, 56),
		"leg_r": Rect2(26, 95, 14, 66),
		"leg_l": Rect2(44, 95, 14, 66),
	}
	var parts := {}
	var hovered := ""
	var selected := ""
	var _time := 0.0

	func _init() -> void:
		custom_minimum_size = Vector2(84, 178)
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

	func _draw() -> void:
		for id in SHAPES:
			var rect: Rect2 = SHAPES[id]
			var p: Dictionary = parts.get(id, {})
			var name := String(p.get("color", "c_green"))
			var color := Slate.health_color(name)
			var healthy := name == "c_green" or name == "c_light_green"
			var fill := Color(color, 0.16 if healthy else 0.55)
			if id == hovered:
				fill.a += 0.2
			if id == "head":
				var center := rect.get_center()
				draw_circle(center, rect.size.x / 2, fill)
				draw_arc(center, rect.size.x / 2, 0, TAU, 28, color, 1.5, true)
			else:
				draw_rect(rect, fill)
				draw_rect(rect.grow(-0.75), color, false, 1.5)
			if id == "torso":
				# The spine: one cell per fifth of the torso's health.
				var level := float(p.get("level", 1.0))
				for i in 5:
					var cell := Rect2(rect.position.x + 11, rect.position.y + 7 + i * 9.4, 10, 6)
					draw_rect(cell, color if level * 5.0 > 4 - i else Color(color, 0.25))
			var status := String(p.get("status", "c_light_gray"))
			if id == selected:
				draw_rect(rect.grow(3), Slate.ACCENT, false, 1.5)
			elif status != "c_light_gray":
				draw_rect(rect.grow(3), Color(Slate.curses(status, Slate.DANGER), 0.55 + 0.45 * sin(_time * 4.0)), false, 2.0)
			if bool(p.get("broken", false)):
				# A jagged gap across the limb reads as a break; a splint shows as a bar beside it.
				var y := rect.position.y + rect.size.y * 0.5
				var x0 := rect.position.x - 1
				var w := rect.size.x + 2
				var crack := PackedVector2Array([Vector2(x0, y - 2), Vector2(x0 + w * 0.3, y + 3),
						Vector2(x0 + w * 0.55, y - 3), Vector2(x0 + w * 0.8, y + 2), Vector2(x0 + w, y - 1)])
				draw_polyline(crack, Slate.CARD, 3.0, true)
				if bool(p.get("splinted", false)):
					var side := rect.position.x - 6 if rect.position.x < 42 else rect.end.x + 3
					draw_line(Vector2(side + 1.5, y - 16), Vector2(side + 1.5, y + 16), Slate.INFO, 3.0, true)
		# The figure faces you, so its right side is on your left.
		var font := Slate.mono()
		draw_string(font, Vector2(26, 175), "R", HORIZONTAL_ALIGNMENT_CENTER, 14, 10, Slate.FAINT)
		draw_string(font, Vector2(44, 175), "L", HORIZONTAL_ALIGNMENT_CENTER, 14, 10, Slate.FAINT)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseMotion:
			var now := _part_at(event.position)
			if now != hovered:
				hovered = now
				queue_redraw()
				tooltip_text = "Click a limb to inspect it" if now == "" or not parts.has(now) else \
						"%s: click to inspect" % Slate.cap(String(parts[now].get("label", "")))
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


## One limb beside the figure: name, a ten-cell health bar, and its health in numbers (or a
## word when the character can't tell).
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
		tooltip_text = "Click to inspect"
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(row)
		_name = Slate.label("", 12, Slate.SOFT, Slate.mono())
		_name.custom_minimum_size.x = 58
		_name.clip_text = true
		row.add_child(_name)
		_bar = SegmentBar.new(10)
		_bar.custom_minimum_size.x = 40
		_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(_bar)
		_state = Slate.label("", 12, Slate.TEXT, Slate.mono())
		# Wide enough for the longest word ("BADLY HURT"), so every bar ends at the same place.
		_state.custom_minimum_size.x = 84
		_state.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(_state)

	func set_state(label: String, level: float, color: Color, state: String, injured: bool, selected: bool) -> void:
		_name.text = label.to_upper().replace("LEFT", "L").replace("RIGHT", "R")
		var hurt := color != Slate.CYAN
		_name.add_theme_color_override("font_color", color if hurt or injured else Slate.SOFT)
		_bar.set_level(level, color)
		_state.text = state.to_upper()
		_state.add_theme_color_override("font_color", color if hurt else Slate.TEXT)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(Slate.ACCENT, 0.12) if selected else Color(0, 0, 0, 0)
		sb.content_margin_left = 6
		sb.content_margin_right = 6
		sb.content_margin_top = 3
		sb.content_margin_bottom = 3
		if selected:
			sb.border_color = Slate.ACCENT
			sb.border_width_left = 2
		add_theme_stylebox_override("panel", sb)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			clicked.emit(id)


## A bar of square cells, filled left to right; the last filled cell can be partly full.
class SegmentBar extends Control:
	var level := 1.0
	var color := Slate.CYAN
	var cells := 10

	func _init(count := 10) -> void:
		cells = count
		custom_minimum_size = Vector2(60, 7)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_level(value: float, c: Color) -> void:
		level = clampf(value, 0.0, 1.0)
		color = c
		queue_redraw()

	func _draw() -> void:
		var gap := 2.0
		var w := (size.x - gap * (cells - 1)) / cells
		for i in cells:
			var r := Rect2(i * (w + gap), 0, w, size.y)
			draw_rect(r, Slate.TRACK)
			var fill := clampf(level * cells - i, 0.0, 1.0)
			if fill > 0.0:
				draw_rect(Rect2(r.position, Vector2(maxf(r.size.x * fill, 2), r.size.y)), color)


## One need: its name, the game's word for how it stands, and a bar. Some can be clicked to
## act on them (eat, sleep).
class NeedCell extends VBoxContainer:
	var action := ""
	var _hint := ""
	var _name: Label
	var _state: Label
	var _note: Label
	var _bar: SegmentBar

	func _init(title: String, run: String, hint: String) -> void:
		action = run
		_hint = hint
		add_theme_constant_override("separation", 3)
		mouse_filter = Control.MOUSE_FILTER_STOP
		tooltip_text = hint
		if action != "":
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 6)
		top.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(top)
		_name = Slate.label(title.to_upper(), 11, Slate.MUTED, Slate.mono())
		_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(_name)
		_note = Slate.label("", 10, Slate.MUTED, Slate.mono())
		_note.visible = false
		top.add_child(_note)
		_state = Slate.label("", 11, Slate.TEXT, Slate.mono())
		top.add_child(_state)
		_bar = SegmentBar.new(12)
		_bar.custom_minimum_size.x = 40
		add_child(_bar)

	func set_value(text: String, color: Color, fill: float) -> void:
		_state.text = text.to_upper()
		_state.add_theme_color_override("font_color", color)
		_name.add_theme_color_override("font_color", color if color != Slate.CYAN else Slate.MUTED)
		_bar.set_level(fill, color)

	func set_note(text: String) -> void:
		_note.text = text.to_upper()
		_note.visible = text != ""

	func set_key(key: String) -> void:
		tooltip_text = "%s  (%s)" % [_hint, key] if key != "" else _hint

	func _gui_input(event: InputEvent) -> void:
		if action != "" and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			Bridge.run(action)


## A small labelled value in the stats line, e.g. `SPD 103`.
class StatPair extends HBoxContainer:
	var _value: Label

	func _init(title: String) -> void:
		add_theme_constant_override("separation", 6)
		mouse_filter = Control.MOUSE_FILTER_PASS
		add_child(Slate.label(title.to_upper(), 11, Slate.MUTED, Slate.mono()))
		_value = Slate.label("", 12, Slate.TEXT, Slate.mono_bold())
		add_child(_value)

	func set_value(text: String, color: Color, tooltip: String) -> void:
		_value.text = text
		_value.add_theme_color_override("font_color", color)
		tooltip_text = tooltip


## An injury under the body readout: a striped warning with what it is, what to do about it,
## and a button for the action that treats it.
class AlertBox extends PanelContainer:
	var _color: Color

	func _init(title: String, note: String, color: Color, key: String, action_label: String) -> void:
		_color = color
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(color, 0.10)
		sb.border_color = color
		sb.border_width_left = 3
		sb.content_margin_left = 14
		sb.content_margin_right = 10
		sb.content_margin_top = 6
		sb.content_margin_bottom = 7
		add_theme_stylebox_override("panel", sb)
		clip_contents = true
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(row)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 0)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(col)
		var head := Slate.label(title.to_upper(), 13, Slate.TEXT, Slate.spaced(Slate.heavy(), 1))
		head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(head)
		if note != "":
			var body := Slate.label(note, 12, Slate.SOFT)
			body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			col.add_child(body)
		if key != "":
			var b := KeyButton.new(action_label)
			b.set_key(Slate.key_name(key))
			b.tooltip_text = "Use an item, such as a bandage"
			b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			b.pressed.connect(func(): Bridge.run("apply"))
			row.add_child(b)

	func _draw() -> void:
		# Hazard stripes, faint, behind the text.
		var step := 16.0
		var x := -size.y
		while x < size.x:
			draw_line(Vector2(x, size.y), Vector2(x + size.y, 0), Color(_color, 0.10), 5.0, true)
			x += step


## The top bar's compass strip: the eight directions, with a marker under each one that has
## creatures in view (red when one of them is dangerous). Hover a direction for the count.
class CompassStrip extends Control:
	## Left to right, with north in the middle.
	const ORDER := [5, 6, 7, 0, 1, 2, 3, 4]
	var dirs: Array = []

	func _init() -> void:
		custom_minimum_size = Vector2(220, 40)
		mouse_filter = Control.MOUSE_FILTER_STOP
		tooltip_text = "Creatures in view, by direction"

	func set_dirs(list: Array) -> void:
		if list != dirs:
			dirs = list
			queue_redraw()

	func _slot(i: int) -> float:
		return size.x * (i + 0.5) / ORDER.size()

	func _draw() -> void:
		var mono := Slate.mono()
		var fs := Slate.fs(11)
		var mid := size.y / 2
		for i in ORDER.size():
			var dir: int = ORDER[i]
			var x := _slot(i)
			var info: Dictionary = dirs[dir] if dir < dirs.size() else {}
			var count := int(info.get("count", 0))
			var north := dir == 0
			var color := Slate.CYAN if north else Slate.MUTED
			var label: String = DIRS[dir]
			var w := mono.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs + (2 if north else 0)).x
			draw_string(mono, Vector2(x - w / 2, mid - 2), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs + (2 if north else 0), color)
			draw_line(Vector2(x, mid + 3), Vector2(x, mid + 8), Color(color, 0.7), 1.0)
			if count > 0:
				var tone := Slate.DANGER if bool(info.get("danger", false)) else Slate.WARN
				var marks := mini(count, 3)
				for m in marks:
					var cx := x + (m - (marks - 1) / 2.0) * 9.0
					draw_colored_polygon(PackedVector2Array([Vector2(cx, mid + 9), Vector2(cx + 5, mid + 17), Vector2(cx - 5, mid + 17)]), tone)
		var near: Dictionary = dirs[8] if dirs.size() > 8 else {}
		if int(near.get("count", 0)) > 0:
			draw_rect(Rect2(0, mid + 15, size.x, 2), Color(Slate.DANGER, 0.8))

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseMotion:
			var i := clampi(int(event.position.x / size.x * ORDER.size()), 0, ORDER.size() - 1)
			var dir: int = ORDER[i]
			var info: Dictionary = dirs[dir] if dir < dirs.size() else {}
			var count := int(info.get("count", 0))
			var near := int((dirs[8] as Dictionary).get("count", 0)) if dirs.size() > 8 else 0
			var text := "%s: %s" % [Slate.cap(DIR_WORDS[dir]), "nothing in view" if count == 0 else "%d in view" % count]
			if near > 0:
				text += "\n%d right next to you" % near
			tooltip_text = text


## Pen marks over the paper map: a ring where you are, a red cross on each hostile creature
## you can see, a dot on the others.
class MapMarks extends Control:
	var sight: Array = []
	var tile := 3.0
	var _map: TextureRect

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_sight(list: Array, tile_pixels: float, map: TextureRect) -> void:
		_map = map
		if list != sight or tile_pixels != tile:
			sight = list
			tile = tile_pixels
		queue_redraw()

	func _draw() -> void:
		var center := (size / 2).floor()
		# The map texture is scaled to cover the panel; marks follow the same scale.
		var scale := 1.0
		if _map != null and _map.texture != null:
			var tex := _map.texture.get_size()
			scale = maxf(size.x / tex.x, size.y / tex.y)
		var step := tile * scale
		var red := Color("#b3202c")
		var ink := Color("#1f2424")
		for s in sight:
			var at := center + Vector2(float(s.get("dx", 0)), float(s.get("dy", 0))) * step
			if at.x < 4 or at.y < 4 or at.x > size.x - 4 or at.y > size.y - 4:
				continue
			if bool(s.get("hostile", false)):
				var arm := 4.5
				draw_line(at - Vector2(arm, arm), at + Vector2(arm, arm), red, 2.0, true)
				draw_line(at + Vector2(-arm, arm), at + Vector2(arm, -arm), red, 2.0, true)
			else:
				draw_circle(at, 2.5, ink)
		draw_circle(center, 5.5, Color("#f4f1e4"))
		draw_arc(center, 5.5, 0, TAU, 24, ink, 2.0, true)
		draw_circle(center, 1.5, ink)


## One creature in view: its name, how far and which way. The nearest hostile one is marked.
## Click for what you can do about it; the tooltip has its threat and state.
class SightRow extends PanelContainer:
	var _offset: Vector2i
	var _lead := false
	var _hostile := false

	func _init(s: Dictionary, lead: bool) -> void:
		_lead = lead
		_hostile = bool(s.get("hostile", false))
		_offset = Vector2i(int(s.get("dx", 0)), int(s.get("dy", 0)))
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var danger := String(s.get("danger", ""))
		var lines := PackedStringArray()
		var threat := String(THREAT_WORDS.get(danger, ""))
		var health := String(s.get("health", ""))
		lines.append(", ".join(PackedStringArray([threat, health]).duplicate()).trim_prefix(", ").trim_suffix(", ") if threat != "" or health != "" else "")
		lines.append("%d squares %s. Click for actions." % [int(s.get("dist", 0)), DIR_WORDS[clampi(int(s.get("dir", 8)), 0, 8)]])
		tooltip_text = "\n".join(lines).strip_edges()
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(row)
		var name_color := Slate.TEXT if _hostile else Slate.curses(danger, Slate.SOFT)
		var name := Slate.label(String(s.get("name", "")).to_upper(), 13, name_color, Slate.spaced(Slate.semibold(), 1))
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name.clip_text = true
		row.add_child(name)
		var where := "%d %s" % [int(s.get("dist", 0)), DIRS[clampi(int(s.get("dir", 8)), 0, 8)]]
		row.add_child(Slate.label(where, 12, Slate.TEXT if _lead else Slate.MUTED, Slate.mono()))
		mouse_entered.connect(func(): _restyle(true))
		mouse_exited.connect(func(): _restyle(false))
		_restyle(false)

	func _restyle(hot: bool) -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(Slate.DANGER, 0.30 if hot else 0.20) if _lead else (Color(Slate.CYAN, 0.10) if hot else Color(0, 0, 0, 0))
		sb.content_margin_left = 14
		sb.content_margin_right = 12
		sb.content_margin_top = 4
		sb.content_margin_bottom = 4
		if _lead:
			sb.border_color = Slate.DANGER
			sb.border_width_left = 3
		add_theme_stylebox_override("panel", sb)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			Bridge.square(_offset)


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
			var fill := color if i <= mark and mark > 0 else Slate.TRACK
			if mark == 0 and i == 0:
				fill = Slate.DANGER
			draw_rect(Rect2(i * 13.0, 1, 10, 8), fill)


## The overmap around the avatar, glyph by glyph as the game draws it, the avatar in the middle,
## inked on the same paper as the area map.
class AreaView extends Control:
	var cells: Array = []

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_cells(rows: Array) -> void:
		if rows != cells:
			cells = rows
			queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("#99968a"))
		var n := cells.size()
		if n == 0:
			return
		var cell := minf(size.x, size.y - 18) / n
		var origin := (Vector2(size.x, size.y - 18) - Vector2(cell * n, cell * n)) / 2
		var f := Slate.mono_bold()
		var fs := int(cell * 0.66)
		for y in n:
			var row: Array = cells[y]
			for x in row.size():
				var c: Array = row[x]
				var rect := Rect2(origin + Vector2(x * cell, y * cell), Vector2(cell, cell))
				var bg := String(c[2]) if c.size() > 2 else "black"
				var fg := Slate.curses(String(c[1])).darkened(0.72)
				if bg != "black":
					draw_rect(rect.grow(-2), Slate.curses(bg).darkened(0.45))
					fg = Color("#f4f1e4")
				var glyph := String(c[0])
				if glyph.strip_edges() == "":
					continue
				var w := f.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				var base := rect.position + Vector2((cell - w) / 2, (cell + f.get_ascent(fs) - f.get_descent(fs)) / 2)
				draw_string(f, base, glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, fg)


## Deck button: icon, label, and the key it is bound to in a box.
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
		custom_minimum_size = Vector2(72, 104)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var normal := StyleBoxFlat.new()
		normal.bg_color = Color(0, 0, 0, 0)
		normal.border_color = Slate.BORDER
		normal.border_width_left = 1
		add_theme_stylebox_override("normal", normal)
		var hot := normal.duplicate() as StyleBoxFlat
		hot.bg_color = Color(Slate.CYAN, 0.12)
		add_theme_stylebox_override("hover", hot)
		var down := normal.duplicate() as StyleBoxFlat
		down.bg_color = Color(Slate.ACCENT, 0.9)
		add_theme_stylebox_override("pressed", down)
		add_theme_stylebox_override("hover_pressed", down)
		var col := VBoxContainer.new()
		col.set_anchors_preset(Control.PRESET_FULL_RECT)
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.add_theme_constant_override("separation", 5)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(col)
		var glyph := Slate.icon_rect(icon_name, 26, Slate.CYAN)
		glyph.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(glyph)
		_name = Slate.label(title.to_upper(), 11, Slate.TEXT, Slate.spaced(Slate.bold(), 1))
		_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(_name)
		_key = Slate.label("", 10, Slate.CYAN, Slate.mono())
		_key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_key.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_key.custom_minimum_size = Vector2(18, 17)
		_key.draw.connect(func(): _key.draw_rect(Rect2(Vector2(0.5, 0.5), _key.size - Vector2(1, 1)), Color(Slate.CYAN, 0.55), false, 1.0))
		col.add_child(_key)
		if not action.begins_with("#"):
			pressed.connect(func(): Bridge.run(action))

	## Narrow buttons in small windows; without the label the tooltip still names the action.
	func set_width(width: int, labeled: bool) -> void:
		custom_minimum_size.x = width
		_name.visible = labeled

	func set_key(key: String) -> void:
		_key.text = " %s " % key if key.length() > 1 else key
		_key.visible = key != ""
		tooltip_text = "%s  (%s)" % [_hint, key] if key != "" else _hint
