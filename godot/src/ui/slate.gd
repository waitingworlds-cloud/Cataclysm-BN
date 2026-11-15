class_name Slate
extends RefCounted
## The interface's visual language ("Holo Terminal"): opaque dark teal modules in a gunmetal
## frame, cyan hairlines and chamfered corners, hazard yellow for the primary action and the
## selection, red for threats. Rajdhani for interface text, Oxanium for headings and Share Tech
## Mono for numbers and key hints.

## The frame between modules.
const GROUND := Color("#1a2d31")
const CARD := Color("#07161a")
const CARD_SOLID := Color("#07161a")
const RAISED := Color("#0f272c")
const BORDER := Color(0.369, 0.918, 0.831, 0.22)
const BORDER_STRONG := Color(0.369, 0.918, 0.831, 0.45)
const HOVER := Color(0.369, 0.918, 0.831, 0.10)
const TRACK := Color(0.369, 0.918, 0.831, 0.13)
const TEXT := Color("#d9f7f3")
const SOFT := Color("#b4dfd9")
const MUTED := Color("#8fc4bd")
const FAINT := Color("#5f918b")
## Hazard yellow: the primary action and whatever is selected.
const ACCENT := Color("#fcee0a")
const ACCENT_TEXT := Color("#0a1214")
## Cyan: frames, headings and healthy readouts.
const CYAN := Color("#5eead4")
const GOOD := Color("#7cffb2")
const WARN := Color("#ffb000")
const DANGER := Color("#ff5a6a")
const INFO := Color("#7cc8ff")
const SCRIM := Color(0.016, 0.047, 0.055, 0.72)
## Item slot plate: lit steel, so pixel sprites read against it.
const PLATE_LIGHT := Color("#71888f")
const PLATE_MID := Color("#475a61")
const PLATE_DARK := Color("#2e3d43")
const PLATE_BORDER := Color("#86aaaf")
## Text sizes are tuned for a wider face; Rajdhani runs small, so sizes scale up to match.
const TEXT_SCALE := 1.14

## Game (curses) color names mapped onto colors that read well on Slate cards.
const CURSES := {
	"black": Color("#7f9c98"),
	"white": Color("#d9f7f3"),
	"light_gray": Color("#b4dfd9"),
	"ltgray": Color("#b4dfd9"),
	"dark_gray": Color("#6f9590"),
	"dkgray": Color("#6f9590"),
	"red": Color("#ff5a6a"),
	"light_red": Color("#ff8a7a"),
	"ltred": Color("#ff8a7a"),
	"green": Color("#7cffb2"),
	"light_green": Color("#a8ffcc"),
	"ltgreen": Color("#a8ffcc"),
	"blue": Color("#7cc8ff"),
	"light_blue": Color("#a6dbff"),
	"ltblue": Color("#a6dbff"),
	"cyan": Color("#5eead4"),
	"light_cyan": Color("#9af5e6"),
	"ltcyan": Color("#9af5e6"),
	"magenta": Color("#d79bff"),
	"pink": Color("#ff9fd6"),
	"brown": Color("#e0a56a"),
	"yellow": Color("#ffd84a"),
}

static var _fonts := {}
static var _icons := {}
static var _icon_scale := 1.0
static var _theme: Theme
static var _separator: RegEx
static var _lead: RegEx
static var _gaps: RegEx


## Slate color for a game color name such as `c_light_red`, `h_white` or `c_white_red`.
static func curses(name: String, fallback := TEXT) -> Color:
	if name.length() > 2 and name[1] == "_":
		name = name.substr(2)
	if CURSES.has(name):
		return CURSES[name]
	# Foreground/background pairs: the foreground is the longest known prefix.
	var parts := name.split("_")
	for n in range(parts.size() - 1, 0, -1):
		var head := "_".join(parts.slice(0, n))
		if CURSES.has(head):
			return CURSES[head]
	return fallback


## Upper-cases the first letter only; `capitalize()` would also split names like "McNeal".
## `text` made safe to put inside BBCode.
static func escape(text: String) -> String:
	return text.replace("[", "[lb]")


static func cap(text: String) -> String:
	return text.substr(0, 1).to_upper() + text.substr(1) if text != "" else text


## Health in the look's colors, from the color the game gives a health bar: healthy is the
## frame's cyan, then amber, then red.
static func health_color(name: String) -> Color:
	match name:
		"c_green":
			return CYAN
		"c_light_green":
			return Color("#8fe9c4")
		"c_yellow":
			return WARN
		"c_light_red":
			return Color("#ff8a5a")
		"c_red":
			return DANGER
		"c_dark_gray", "c_light_gray":
			return FAINT
	return curses(name, CYAN)


## Severity of a game color, used to size bars for needs the game only describes in words.
static func severity(name: String) -> float:
	var c := name.substr(2) if name.length() > 2 and name[1] == "_" else name
	if c.begins_with("light_green") or c == "white":
		return 1.0
	if c.begins_with("green") or c.begins_with("light_gray"):
		return 0.85
	if c.begins_with("yellow") or c.begins_with("light_blue"):
		return 0.55
	if c.begins_with("light_red") or c.begins_with("cyan"):
		return 0.35
	if c.begins_with("red") or c.begins_with("blue") or c.begins_with("magenta"):
		return 0.15
	return 0.7


static func font(name: String) -> FontFile:
	if not _fonts.has(name):
		var f := FontFile.new()
		f.load_dynamic_font("res://fonts/%s.ttf" % name)
		f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		f.hinting = TextServer.HINTING_LIGHT
		f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
		_fonts[name] = f
	return _fonts[name]


static func body() -> Font:
	return font("Rajdhani-Medium")


static func semibold() -> Font:
	return font("Rajdhani-SemiBold")


static func bold() -> Font:
	return font("Rajdhani-Bold")


## Headings and names.
static func heavy() -> Font:
	return font("Oxanium-Bold")


static func heading() -> Font:
	return font("Oxanium-SemiBold")


static func mono() -> Font:
	return font("ShareTechMono-Regular")


## Share Tech Mono has one weight; the bold is the same face thickened slightly.
static func mono_bold() -> Font:
	if not _fonts.has("#mono_bold"):
		var v := FontVariation.new()
		v.base_font = font("ShareTechMono-Regular")
		v.variation_embolden = 0.35
		_fonts["#mono_bold"] = v
	return _fonts["#mono_bold"]


## `base` with extra space between letters, for headings in capitals.
static func spaced(base: Font, extra: int) -> Font:
	var key := "#spaced:%d:%d" % [base.get_instance_id(), extra]
	if not _fonts.has(key):
		var v := FontVariation.new()
		v.base_font = base
		v.spacing_glyph = extra
		_fonts[key] = v
	return _fonts[key]


## A text size in interface units, scaled for the interface faces.
static func fs(size: float) -> int:
	return roundi(size * TEXT_SCALE)


## White line icon from icons/, `size` interface units wide and rendered crisply at the current
## interface scale; tint with modulate.
static func icon(name: String, size := 20) -> Texture2D:
	var key := "%s@%d" % [name, size]
	if not _icons.has(key):
		var texture := ImageTexture.new()
		_draw_icon(texture, name, size)
		_icons[key] = texture
	return _icons[key]


## Redraws every icon for a new interface scale; nodes showing them update on their own.
static func set_icon_scale(scale: float) -> void:
	if is_equal_approx(scale, _icon_scale):
		return
	_icon_scale = scale
	for key in _icons:
		var parts := String(key).split("@")
		_draw_icon(_icons[key], parts[0], int(parts[1]))


static func _draw_icon(texture: ImageTexture, name: String, size: int) -> void:
	var data := FileAccess.get_file_as_bytes("res://icons/%s.svg" % name)
	var image := Image.new()
	if data.is_empty() or image.load_svg_from_buffer(data, size * _icon_scale / 24.0) != Error.OK:
		image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	texture.set_image(image)
	texture.set_size_override(Vector2i(size, size))


## Flat panel with the look's chamfer: the top left and bottom right corners are cut, the other
## two square. `radius` sets how deep the cut is; small boxes (bars, cells) stay square.
static func box(bg: Color, radius := 16, border := BORDER, border_width := 1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	var cut := 0 if radius < 6 else clampi(roundi(radius * 0.6), 4, 10)
	sb.corner_radius_top_left = cut
	sb.corner_radius_bottom_right = cut
	sb.corner_detail = 1
	sb.anti_aliasing = true
	sb.anti_aliasing_size = 0.6
	if border_width > 0:
		sb.border_color = border
		sb.set_border_width_all(border_width)
	return sb


## A card over a dimmed screen (menus, prompts): an opaque module with a strong frame.
static func card_box(radius := 16, padding := 16) -> StyleBoxFlat:
	var sb := box(CARD, radius, BORDER_STRONG)
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 10
	sb.shadow_offset = Vector2(0, 4)
	sb.set_content_margin_all(padding)
	return sb


static func pill_box(bg: Color, padding_h := 10, padding_v := 4) -> StyleBoxFlat:
	var sb := box(bg, 8, BORDER, 0)
	sb.content_margin_left = padding_h
	sb.content_margin_right = padding_h
	sb.content_margin_top = padding_v
	sb.content_margin_bottom = padding_v
	return sb


## One module of the frame: opaque, hairline border, no shadow.
static func module_box(padding := 0) -> StyleBoxFlat:
	var sb := box(CARD, 12, BORDER_STRONG, 1)
	sb.set_content_margin_all(padding)
	return sb


## The title of a prompt (a menu, a question, a text box): a module heading, in hazard yellow
## because a prompt is where the keys act right now.
static func prompt_title() -> Label:
	var title := label("", 14, ACCENT, spaced(heavy(), 2))
	title.uppercase = true
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return title


## The strip across the top of a prompt: a marker, the `title` and, at the right, whatever else
## belongs there (`extras`: category arrows, a close button).
static func prompt_head(title: Label, extras: Array = []) -> PanelContainer:
	var strip := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = RAISED
	sb.border_color = BORDER
	sb.border_width_bottom = 1
	# The card's cut corner shows through.
	sb.corner_radius_top_left = 9
	sb.corner_detail = 1
	sb.content_margin_left = 16
	sb.content_margin_right = 8
	sb.content_margin_top = 7
	sb.content_margin_bottom = 7
	strip.add_theme_stylebox_override("panel", sb)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	strip.add_child(row)
	var marker := ColorRect.new()
	marker.color = ACCENT
	marker.custom_minimum_size = Vector2(7, 7)
	marker.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(marker)
	row.add_child(title)
	for extra in extras:
		row.add_child(extra)
	return strip


## Lit steel plate behind an item sprite.
static func plate_box(selected := false, hot := false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PLATE_MID.lightened(0.08) if hot else PLATE_MID
	sb.border_color = ACCENT if selected else (PLATE_BORDER.lightened(0.2) if hot else PLATE_BORDER)
	sb.set_border_width_all(2 if selected else 1)
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 3
	sb.shadow_offset = Vector2(0, 2)
	return sb


## Shared theme: fonts, text colors, tooltips, scrollbars and buttons.
static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = body()
	t.default_font_size = fs(14)
	t.set_color("font_color", "Label", TEXT)
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_font("normal_font", "RichTextLabel", body())
	t.set_font("bold_font", "RichTextLabel", bold())
	t.set_font("mono_font", "RichTextLabel", mono())
	t.set_constant("line_separation", "RichTextLabel", 2)

	var tip := box(RAISED, 10, BORDER_STRONG)
	tip.content_margin_left = 10
	tip.content_margin_right = 10
	tip.content_margin_top = 6
	tip.content_margin_bottom = 6
	tip.shadow_color = Color(0, 0, 0, 0.4)
	tip.shadow_size = 6
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_font("font", "TooltipLabel", semibold())
	t.set_font_size("font_size", "TooltipLabel", fs(13))

	var grabber := box(Color(CYAN, 0.30), 4, BORDER, 0)
	var grabber_hot := box(Color(CYAN, 0.55), 4, BORDER, 0)
	var track := StyleBoxEmpty.new()
	track.content_margin_left = 4
	track.content_margin_right = 4
	t.set_stylebox("scroll", "VScrollBar", track)
	t.set_stylebox("grabber", "VScrollBar", grabber)
	t.set_stylebox("grabber_highlight", "VScrollBar", grabber_hot)
	t.set_stylebox("grabber_pressed", "VScrollBar", grabber_hot)

	var flat := box(Color(0, 0, 0, 0), 10, BORDER, 0)
	flat.set_content_margin_all(8)
	var hover := box(HOVER, 10, BORDER, 0)
	hover.set_content_margin_all(8)
	var pressed := box(Color(CYAN, 0.20), 10, BORDER, 0)
	pressed.set_content_margin_all(8)
	for state in ["normal", "disabled"]:
		t.set_stylebox(state, "Button", flat)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("hover_pressed", "Button", pressed)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", TEXT)
	t.set_color("font_pressed_color", "Button", TEXT)
	t.set_font("font", "Button", semibold())
	_theme = t
	return t


## BBCode for `[text, color]` runs sent by the game.
## The game separates sections with "--" lines (sometimes colored); shows them as spacing instead.
static func tidy_body(bb: String) -> String:
	if _separator == null:
		var tag := "(\\[/?color[^\\]]*\\])*"
		_separator = RegEx.create_from_string("(?m)^" + tag + "-{2,}" + tag + "$")
		_lead = RegEx.create_from_string("^((?:\\[color=[^\\]]*\\])?)\\s+")
		_gaps = RegEx.create_from_string("\\n(\\s*\\n){2,}")
	var out := _separator.sub(bb, "", true)
	out = _lead.sub(out, "$1")
	return _gaps.sub(out, "\n\n", true).strip_edges()


static func bbcode(spans, fallback := TEXT) -> String:
	var out := ""
	if typeof(spans) != TYPE_ARRAY:
		return out
	for run in spans:
		var text := String(run[0]).replace("[", "[lb]")
		var name := String(run[1]) if run.size() > 1 else ""
		var color := curses(name, fallback) if name != "" else fallback
		# Highlighted text (a list's cursor drawn by the game) keeps a tinted background.
		if name.begins_with("h_"):
			out += "[bgcolor=#%s][color=#%s]%s[/color][/bgcolor]" % [Color(ACCENT, 0.24).to_html(true),
					color.lightened(0.3).to_html(false), text]
		else:
			out += "[color=#%s]%s[/color]" % [color.to_html(false), text]
	return out


## Plain text of `[text, color]` runs.
static func plain(spans) -> String:
	var out := ""
	if typeof(spans) == TYPE_ARRAY:
		for run in spans:
			out += String(run[0])
	return out


## Text the game laid out in columns, with the widest gap of each line that is longer than
## `max_chars` made narrower, so that the line fits without the whole text getting smaller.
static func narrow_gaps(spans, max_chars: int) -> Array:
	if typeof(spans) != TYPE_ARRAY:
		return []
	if max_chars <= 0:
		return spans
	var lines := [[]]
	for run in spans:
		var parts := String(run[0]).split("\n")
		for i in parts.size():
			if i > 0:
				lines.append([])
			if parts[i] != "":
				var piece: Array = run.duplicate()
				piece[0] = parts[i]
				lines[-1].append(piece)
	var out := []
	for n in lines.size():
		var line: Array = lines[n]
		var text := ""
		for piece in line:
			text += String(piece[0])
		var extra := text.rstrip(" ").length() - max_chars
		if extra > 0:
			# The longest run of blanks in the line gives up what the line is too long by.
			var best_at := -1
			var best_len := 0
			var at := -1
			for i in text.length():
				if text[i] != " ":
					at = -1
					continue
				if at < 0:
					at = i
				if i - at + 1 > best_len:
					best_len = i - at + 1
					best_at = at
			var cut := mini(extra, best_len - 2)
			if cut > 0:
				var pos := 0
				for piece in line:
					var s := String(piece[0])
					var a := clampi(best_at - pos, 0, s.length())
					var b := clampi(best_at + cut - pos, 0, s.length())
					pos += s.length()
					if b > a:
						piece[0] = s.substr(0, a) + s.substr(b)
		for piece in line:
			if String(piece[0]) != "":
				out.append(piece)
		if n < lines.size() - 1:
			if not line.is_empty() and not out.is_empty():
				out[-1][0] = String(out[-1][0]) + "\n"
			else:
				out.append(["\n", "c_light_gray"])
	return out


## The game's color for a kind of hit (great, normal, graze), in the interface's colors.
static func hit_color(name: String) -> Color:
	match name:
		"c_green":
			return GOOD
		"c_light_gray", "c_white":
			return CYAN
		"c_magenta":
			return WARN
	return curses(name, CYAN)


## Color of the first run, as a Slate color.
static func lead_color(spans, fallback := TEXT) -> Color:
	if typeof(spans) == TYPE_ARRAY and spans.size() > 0 and spans[0].size() > 1:
		return curses(String(spans[0][1]), fallback)
	return fallback


static func label(text: String, size := 14, color := TEXT, f: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fs(size))
	l.add_theme_color_override("font_color", color)
	if f != null:
		l.add_theme_font_override("font", f)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func rich(size := 14, fit := true) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = fit
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.add_theme_font_size_override("normal_font_size", fs(size))
	r.add_theme_font_size_override("bold_font_size", fs(size))
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## A line of cells the game printed (rows of `[text, color]` runs, see `write_window_grid`) as
## `[left, right]` BBCode: what stands at the left, and what was printed against the right edge
## (after the widest gap). The right part keeps its blanks, so columns printed in a fixed width
## font still line up under each other; without a wide gap all of it is the right part.
static func split_line(rows: Array, fallback: Color) -> Array:
	var cells := []
	if not rows.is_empty():
		for run in rows[0]:
			var name := String(run[1]) if run.size() > 1 else ""
			for ch in String(run[0]):
				cells.append([ch, name])
	var first := -1
	var last := -1
	for i in cells.size():
		if cells[i][0] != " ":
			first = i if first < 0 else first
			last = i
	if first < 0:
		return ["", ""]
	var gap_at := -1
	var gap := 0
	var blank_from := -1
	for i in range(first, last + 1):
		if cells[i][0] != " ":
			blank_from = -1
			continue
		blank_from = i if blank_from < 0 else blank_from
		if i - blank_from + 1 > gap:
			gap = i - blank_from + 1
			gap_at = blank_from
	if gap < 12:
		return ["", _cells_bbcode(cells, first, cells.size(), fallback, true)]
	return [_cells_bbcode(cells, first, gap_at, fallback, false),
			_cells_bbcode(cells, gap_at + gap, cells.size(), fallback, true)]


static func _cells_bbcode(cells: Array, from: int, to: int, fallback: Color, keep_blanks: bool) -> String:
	var out := ""
	var i := from
	while i < to:
		var name := String(cells[i][1])
		var text := ""
		while i < to and String(cells[i][1]) == name:
			text += String(cells[i][0])
			i += 1
		if keep_blanks:
			text = text.replace(" ", "\u00a0")
		else:
			while text.contains("  "):
				text = text.replace("  ", " ")
		var color := curses(name, fallback) if name != "" else fallback
		out += "[color=#%s]%s[/color]" % [color.to_html(false), text.replace("[", "[lb]")]
	return out


## Small rounded key hint, e.g. the `i` on the Bag button.
static func key_chip(key: String, size := 11) -> PanelContainer:
	var chip := PanelContainer.new()
	var sb := box(Color(0, 0, 0, 0), 0, Color(CYAN, 0.55), 1)
	sb.content_margin_left = 5
	sb.content_margin_right = 5
	chip.add_theme_stylebox_override("panel", sb)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l := label(key, size, CYAN, mono())
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chip.add_child(l)
	chip.visible = key != ""
	return chip


static func icon_rect(name: String, size := 20, color := TEXT) -> TextureRect:
	var r := TextureRect.new()
	r.texture = icon(name, size)
	r.custom_minimum_size = Vector2(size, size)
	r.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	r.modulate = color
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## Friendlier name for a key label the game sends, e.g. `RETURN` becomes `Enter`.
static func key_name(key: String) -> String:
	const NAMES := {
		"RETURN": "Enter", "ESC": "Esc", "TAB": "Tab", "BTAB": "Shift+Tab", "BACKTAB": "Shift+Tab", "SPACE": "Space",
		"BACKSPACE": "Backspace", "DELETE": "Del", "HOME": "Home", "END": "End", "PPAGE": "PgUp",
		"NPAGE": "PgDn", "UP": "↑", "DOWN": "↓", "LEFT": "←", "RIGHT": "→",
	}
	# A hint for several keys lists them with spaces between ("PPAGE NPAGE").
	if key.contains(" "):
		var names := PackedStringArray()
		for part in key.split(" ", false):
			names.append(key_name(part))
		return " ".join(names)
	if key.begins_with("CTRL+") and key.length() > 5:
		return "Ctrl+" + key.substr(5)
	return NAMES.get(key, key)
