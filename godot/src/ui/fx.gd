class_name Fx
extends RefCounted
## The polish pass: glow, atmosphere and motion shared by every screen.
##
## Nothing here changes what a screen shows or how it is used. Glow sits around lit things and
## never on text, the scanlines and grain cover the panels and never the map, and every motion
## plays out something that has already happened, so no key ever waits for an animation.

## Scanlines, film grain and a faint sheen over the panels. `hole` (screen pixels) is left clear:
## the map viewport.
const ATMOSPHERE_SHADER := "
shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;
uniform vec4 hole = vec4(0.0);
uniform float scale = 1.0;
uniform float lines = 0.10;
uniform float grain = 0.045;
float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}
void fragment() {
	vec2 p = FRAGCOORD.xy;
	if (p.x > hole.x && p.y > hole.y && p.x < hole.x + hole.z && p.y < hole.y + hole.w) {
		COLOR = vec4(0.0);
	} else {
		float period = max(3.0, floor(1.5 * scale + 0.5));
		float dark = step(mod(p.y, period), 0.999) * lines;
		float n = hash(floor(p / max(1.0, scale * 0.5)) + floor(TIME * 24.0) * vec2(17.0, 31.0));
		float g = (n - 0.5) * 2.0 * grain;
		float sheen = max(0.0, 0.045 * (1.0 - (UV.x * 1.1 + UV.y * 2.2)));
		COLOR = vec4(vec3(max(g, 0.0) + sheen), dark + max(-g, 0.0));
	}
}
"

static var _shaders := {}
## The tip of the day as the title screen last showed it (BBCode), for the loading screen.
static var last_tip := ""


static func shader(code: String) -> Shader:
	if not _shaders.has(code):
		var s := Shader.new()
		s.code = code
		_shaders[code] = s
	return _shaders[code]


static func material(code: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader(code)
	return m


## Soft light around a box, in its own color: for the primary action, lit bars and the row of
## the creature you are facing. The glow lies outside the box, so what is written in it stays
## sharp.
static func glow(sb: StyleBoxFlat, color: Color, size := 8, strength := 0.38) -> StyleBoxFlat:
	sb.shadow_color = Color(color, strength)
	sb.shadow_size = size
	sb.shadow_offset = Vector2.ZERO
	return sb


## A slow breath between 0 and 1, the same for everything that pulses so they pulse together.
static func breath(period := 1.6) -> float:
	return 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * TAU / period)


## A screen coming up: it fades in and settles a few units from the right (cards settle from
## slightly small instead). Purely for the eye; the screen takes keys from its first frame.
static func enter(view: Control, card := false) -> void:
	if not view.is_inside_tree():
		return
	if view.has_meta("fx_enter"):
		var old = view.get_meta("fx_enter")
		if old is Tween and (old as Tween).is_valid():
			(old as Tween).kill()
	var t := view.create_tween().set_parallel(true)
	view.set_meta("fx_enter", t)
	view.modulate.a = 0.0
	t.tween_property(view, "modulate:a", 1.0, 0.14).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	if card:
		view.pivot_offset = view.size / 2
		view.scale = Vector2(0.975, 0.975)
		t.tween_property(view, "scale", Vector2.ONE, 0.16).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	else:
		view.position.x = 22.0
		t.tween_property(view, "position:x", 0.0, 0.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)


## A short flash of `color` over `control`, for a button whose key was just pressed.
static func flash(control: Control, color: Color, time := 0.28) -> void:
	if not control.is_inside_tree() or not control.is_visible_in_tree():
		return
	var old := control.get_node_or_null("FxFlash")
	if old != null:
		old.free()
	var box := Panel.new()
	box.name = "FxFlash"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(color, 0.22)
	sb.border_color = color
	sb.set_border_width_all(2)
	glow(sb, color, 10, 0.55)
	box.add_theme_stylebox_override("panel", sb)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	control.add_child(box)
	var t := box.create_tween()
	t.tween_property(box, "modulate:a", 0.0, time).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	t.tween_callback(box.queue_free)
