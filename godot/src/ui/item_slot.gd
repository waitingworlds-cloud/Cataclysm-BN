class_name ItemSlot
extends Control
## One item slot: a lit steel plate with the item's map sprite on it, so pixel art reads clearly
## against the dark interface. Falls back to the item's map symbol while the sprite is on its
## way or when the tileset has none. Optional corner tags: a slot number or word at the top
## left and a count at the bottom right.

static var _plate: GradientTexture2D

var item_type := ""
var glyph := ""
var glyph_color := Slate.TEXT
var tag := ""
var count := ""
var count_color := Slate.TEXT
## Yellow frame: the wielded item or the current selection.
var selected := false
## An empty slot is a dark recess instead of a plate.
var filled := false
## Shown at reduced strength, e.g. a pinned item you carry none of.
var dimmed := false
var hot := false
var _art: Control


func _init(side := 64.0) -> void:
	custom_minimum_size = Vector2(side, side)
	mouse_filter = Control.MOUSE_FILTER_PASS
	_art = Control.new()
	_art.set_anchors_preset(Control.PRESET_FULL_RECT)
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_art.draw.connect(_draw_art)
	add_child(_art)
	mouse_entered.connect(func():
		hot = true
		refresh())
	mouse_exited.connect(func():
		hot = false
		refresh())


func _ready() -> void:
	Sprites.changed.connect(refresh)


func set_item(type: String, sym := "", sym_color := Slate.TEXT) -> void:
	item_type = type
	glyph = sym
	glyph_color = sym_color
	filled = type != "" or sym != ""
	refresh()


func clear() -> void:
	item_type = ""
	glyph = ""
	count = ""
	filled = false
	selected = false
	dimmed = false
	refresh()


func refresh() -> void:
	queue_redraw()
	_art.queue_redraw()


static func plate() -> GradientTexture2D:
	if _plate == null:
		var g := Gradient.new()
		g.set_color(0, Slate.PLATE_LIGHT)
		g.set_color(1, Slate.PLATE_DARK)
		g.add_point(0.55, Slate.PLATE_MID)
		_plate = GradientTexture2D.new()
		_plate.gradient = g
		_plate.width = 64
		_plate.height = 64
		_plate.fill = GradientTexture2D.FILL_RADIAL
		_plate.fill_from = Vector2(0.5, 0.42)
		_plate.fill_to = Vector2(1.05, 1.05)
	return _plate


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	if not filled:
		draw_rect(rect, Color(0, 0, 0, 0.28))
		draw_rect(rect.grow(-0.5), Color(Slate.CYAN, 0.30 if hot else 0.16), false, 1.0)
		return
	# A soft shadow under the plate lifts it off the module.
	draw_rect(Rect2(rect.position + Vector2(0, 2), rect.size), Color(0, 0, 0, 0.35))
	draw_texture_rect(plate(), rect, false, Color(1.12, 1.12, 1.12) if hot else Color.WHITE)
	var border := Slate.ACCENT if selected else (Slate.PLATE_BORDER.lightened(0.25) if hot else Slate.PLATE_BORDER)
	var width := 2.0 if selected else 1.0
	draw_rect(rect.grow(-width / 2), border, false, width)


func _draw_art() -> void:
	var mono := Slate.mono()
	if filled:
		var sprite := Sprites.item(item_type)
		var alpha := 0.4 if dimmed else 1.0
		if sprite != null:
			# Whole-number scaling in screen pixels keeps the pixel art sharp.
			var ui := maxf(Display.ui_scale(), 1.0)
			var room := (minf(size.x, size.y) - 10.0) * ui
			var scale := maxf(floorf(room / sprite.get_width()), 1.0)
			var side := sprite.get_width() * scale / ui
			var at := ((size - Vector2(side, side)) / 2).round()
			_art.draw_texture_rect(sprite, Rect2(at + Vector2(1, 2), Vector2(side, side)), false, Color(0, 0, 0, 0.35 * alpha))
			_art.draw_texture_rect(sprite, Rect2(at, Vector2(side, side)), false, Color(1, 1, 1, alpha))
		elif glyph != "":
			var fs := int(size.y * 0.46)
			var w := mono.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var base := Vector2((size.x - w) / 2, (size.y + mono.get_ascent(fs) - mono.get_descent(fs)) / 2)
			_art.draw_string(mono, base + Vector2(1, 1), glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.5 * alpha))
			_art.draw_string(mono, base, glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(glyph_color.lightened(0.25), alpha))
	if tag != "":
		var fs := 11
		var w := mono.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var box := Rect2(0, 0, w + 8, 15)
		if selected:
			_art.draw_rect(box, Slate.ACCENT)
			_art.draw_string(mono, Vector2(4, 11.5), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Slate.ACCENT_TEXT)
		else:
			_art.draw_rect(box, Color(Slate.CARD, 0.82 if filled else 0.0))
			_art.draw_string(mono, Vector2(4, 11.5), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Slate.SOFT if filled else Slate.FAINT)
	if count != "":
		var fs := 12
		var w := mono.get_string_size(count, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var box := Rect2(size.x - w - 8, size.y - 16, w + 8, 16)
		_art.draw_rect(box, Color(Slate.CARD, 0.88))
		_art.draw_string(mono, Vector2(box.position.x + 4, size.y - 3.5), count, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, count_color)
