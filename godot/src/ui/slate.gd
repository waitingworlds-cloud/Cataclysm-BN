class_name Slate
extends RefCounted
## The Slate visual language: map first, floating rounded cards, Manrope for interface text and
## JetBrains Mono for numbers and key hints, amber accent.

const GROUND := Color("#10151c")
const CARD := Color(0.063, 0.082, 0.110, 0.92)
const CARD_SOLID := Color("#151b24")
const RAISED := Color("#1c2430")
const BORDER := Color(1, 1, 1, 0.08)
const BORDER_STRONG := Color(1, 1, 1, 0.14)
const HOVER := Color(1, 1, 1, 0.07)
const TRACK := Color(1, 1, 1, 0.10)
const TEXT := Color("#eef2f6")
const SOFT := Color("#c9d2dd")
const MUTED := Color("#a7b3c2")
const FAINT := Color("#6b7686")
const ACCENT := Color("#f4b63f")
const ACCENT_TEXT := Color("#10151c")
const GOOD := Color("#5fd39a")
const WARN := Color("#f4b63f")
const DANGER := Color("#ff6b5e")
const INFO := Color("#6aa8ff")
const SCRIM := Color(0.02, 0.03, 0.05, 0.55)

## Game (curses) color names mapped onto colors that read well on Slate cards.
const CURSES := {
	"black": Color("#8a94a3"),
	"white": Color("#eef2f6"),
	"light_gray": Color("#c9d2dd"),
	"ltgray": Color("#c9d2dd"),
	"dark_gray": Color("#7d8794"),
	"dkgray": Color("#7d8794"),
	"red": Color("#ff6b5e"),
	"light_red": Color("#ff8a7f"),
	"ltred": Color("#ff8a7f"),
	"green": Color("#5fd39a"),
	"light_green": Color("#8ee6b5"),
	"ltgreen": Color("#8ee6b5"),
	"blue": Color("#6aa8ff"),
	"light_blue": Color("#9cc6ff"),
	"ltblue": Color("#9cc6ff"),
	"cyan": Color("#4fd1d9"),
	"light_cyan": Color("#8de9ee"),
	"ltcyan": Color("#8de9ee"),
	"magenta": Color("#c58cff"),
	"pink": Color("#f59ad2"),
	"brown": Color("#d39a5f"),
	"yellow": Color("#f4d35e"),
}

static var _fonts := {}
static var _icons := {}
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


static func body() -> FontFile:
	return font("Manrope-Medium")


static func semibold() -> FontFile:
	return font("Manrope-SemiBold")


static func bold() -> FontFile:
	return font("Manrope-Bold")


static func heavy() -> FontFile:
	return font("Manrope-ExtraBold")


static func mono() -> FontFile:
	return font("JetBrainsMono-Regular")


static func mono_bold() -> FontFile:
	return font("JetBrainsMono-Bold")


## White line icon from icons/, rendered crisply at `size` pixels; tint with modulate.
static func icon(name: String, size := 20) -> Texture2D:
	var key := "%s@%d" % [name, size]
	if not _icons.has(key):
		var data := FileAccess.get_file_as_bytes("res://icons/%s.svg" % name)
		var image := Image.new()
		if data.is_empty() or image.load_svg_from_buffer(data, size / 24.0) != Error.OK:
			image = Image.create(size, size, false, Image.FORMAT_RGBA8)
		_icons[key] = ImageTexture.create_from_image(image)
	return _icons[key]


static func box(bg: Color, radius := 16, border := BORDER, border_width := 1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.corner_detail = 10
	sb.anti_aliasing = true
	sb.anti_aliasing_size = 0.8
	if border_width > 0:
		sb.border_color = border
		sb.set_border_width_all(border_width)
	return sb


static func card_box(radius := 16, padding := 16) -> StyleBoxFlat:
	var sb := box(CARD, radius)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 22
	sb.shadow_offset = Vector2(0, 8)
	sb.set_content_margin_all(padding)
	return sb


static func pill_box(bg: Color, padding_h := 10, padding_v := 4) -> StyleBoxFlat:
	var sb := box(bg, 999, BORDER, 0)
	sb.content_margin_left = padding_h
	sb.content_margin_right = padding_h
	sb.content_margin_top = padding_v
	sb.content_margin_bottom = padding_v
	return sb


## Shared theme: fonts, text colors, tooltips, scrollbars and buttons.
static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = body()
	t.default_font_size = 14
	t.set_color("font_color", "Label", TEXT)
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_font("normal_font", "RichTextLabel", body())
	t.set_font("bold_font", "RichTextLabel", bold())
	t.set_font("mono_font", "RichTextLabel", mono())
	t.set_constant("line_separation", "RichTextLabel", 2)

	var tip := box(RAISED, 10, BORDER_STRONG)
	tip.set_content_margin_all(10)
	tip.shadow_color = Color(0, 0, 0, 0.4)
	tip.shadow_size = 12
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_font_size("font_size", "TooltipLabel", 13)

	var grabber := box(Color(1, 1, 1, 0.18), 4, BORDER, 0)
	var grabber_hot := box(Color(1, 1, 1, 0.30), 4, BORDER, 0)
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
	var pressed := box(Color(1, 1, 1, 0.12), 10, BORDER, 0)
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


## Color of the first run, as a Slate color.
static func lead_color(spans, fallback := TEXT) -> Color:
	if typeof(spans) == TYPE_ARRAY and spans.size() > 0 and spans[0].size() > 1:
		return curses(String(spans[0][1]), fallback)
	return fallback


static func label(text: String, size := 14, color := TEXT, f: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
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
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## Small rounded key hint, e.g. the `i` on the Bag button.
static func key_chip(key: String, size := 11) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", pill_box(Color(1, 1, 1, 0.08), 6, 1))
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l := label(key, size, MUTED, mono())
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
