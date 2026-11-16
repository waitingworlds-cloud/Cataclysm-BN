class_name MapStage
extends Control
## The map as a lit, moving picture.
##
## The game draws the map and says, per tile, how lit, visible and open to the sky it is (the
## `scene`). A shader on the map's picture turns that into light with shape (warm pools around
## lamps, the cone of a flashlight, shadows beside walls and under creatures), soft edges on what
## you cannot see, swaying plants, rain and the time of day. When the view moves a tile the
## picture glides there instead of jumping, and hits shake it and float their damage over it.
##
## None of it holds the game up: every effect plays over a turn that is already done.

const SHADER := "
shader_type canvas_item;
uniform sampler2D prev : filter_nearest, repeat_disable;
uniform sampler2D tiles_n : filter_nearest, repeat_disable;
uniform sampler2D tiles_l : filter_linear, repeat_disable;
uniform float amount = 0.0;
uniform float lit = 0.0;
uniform vec4 view = vec4(0.0);
uniform vec2 tile = vec2(32.0);
uniform vec2 grid = vec2(1.0);
uniform vec2 glide = vec2(0.0);
uniform vec2 step_px = vec2(0.0);
uniform float blend = 1.0;
uniform vec2 shake = vec2(0.0);
uniform vec4 you = vec4(0.0);
uniform float night = 0.0;
uniform float dusk = 0.0;
uniform float dark = 0.0;
uniform float rain = 0.0;
uniform float snow = 0.0;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
bool inside(vec2 p) {
	return p.x >= view.x && p.y >= view.y && p.x < view.x + view.z && p.y < view.y + view.w;
}
bool within(vec2 p, vec4 r) {
	return p.x >= r.x && p.y >= r.y && p.x < r.x + r.z && p.y < r.y + r.w;
}
int flags_at(vec2 cell) {
	if (cell.x < 0.0 || cell.y < 0.0 || cell.x >= grid.x || cell.y >= grid.y) {
		return 0;
	}
	return int(texture(tiles_n, (floor(cell) + 0.5) / grid).b * 255.0 + 0.5);
}
vec3 grade(vec3 c) {
	float lum = dot(c, vec3(0.3, 0.59, 0.11));
	vec3 g = mix(vec3(lum), c, 0.92);
	float low = clamp(1.0 - lum * 2.2, 0.0, 1.0);
	float high = clamp(lum * 2.0 - 1.0, 0.0, 1.0);
	g += low * vec3(-0.02, 0.02, 0.04) + high * vec3(0.05, 0.02, -0.04);
	g = (g - 0.5) * 1.10 + 0.5;
	return pow(clamp(g, 0.0, 1.0), vec3(1.06));
}

void fragment() {
	vec2 texel = TEXTURE_PIXEL_SIZE;
	vec2 fp = UV / texel;
	if (amount <= 0.0 || !inside(fp)) {
		COLOR = texture(TEXTURE, UV);
	} else {
		vec2 wp = fp - glide - shake;
		vec2 cell = (wp - view.xy) / tile;
		int flags = 0;
		vec4 tl = vec4(0.0, 1.0, 0.0, 1.0);
		float here_seen = 1.0;
		if (lit > 0.5) {
			flags = flags_at(cell);
			vec2 tuv = clamp(cell / grid, vec2(0.0), vec2(1.0));
			tl = texture(tiles_l, tuv);
			here_seen = texture(tiles_n, clamp((floor(cell) + 0.5) / grid, vec2(0.0), vec2(1.0))).g;
		}
		// Plants lean in the wind from the top, rooted at the bottom; water wobbles.
		if (here_seen > 0.3) {
			if ((flags & 8) != 0) {
				float h = 1.0 - fract(cell.y);
				float a = sin(TIME * 1.6 + floor(cell.x) * 1.7 + floor(cell.y) * 0.9)
						+ 0.5 * sin(TIME * 2.9 + floor(cell.x) * 0.6);
				wp.x += a * h * h * tile.x * 0.03;
			} else if ((flags & 16) != 0) {
				wp.x += sin(TIME * 1.3 + cell.y * 9.0) * tile.x * 0.012;
			}
		}
		bool now = inside(wp);
		vec2 cp = clamp(wp, view.xy + 0.5, view.xy + view.zw - 0.5);
		vec3 c = texture(TEXTURE, cp * texel).rgb;
		bool walking = you.z > 0.0 && (step_px.x != 0.0 || step_px.y != 0.0);
		if (blend < 1.0 || !now || walking) {
			vec2 pp = wp + step_px;
			if (inside(pp)) {
				vec3 before = texture(prev, pp * texel).rgb;
				float k = blend;
				if (walking) {
					// You are drawn apart (below): under you goes the ground as it was seen before
					// you stood on it, and where you stood, the ground as it is seen now.
					if (within(wp, you)) {
						k = 0.0;
					} else if (within(pp, you)) {
						k = 1.0;
					}
				}
				c = now ? mix(before, c, k) : before;
			}
		}
		if (walking && within(fp, you)) {
			// You stay in the middle of the view while the world glides under you: what differs
			// between your tile now and the same ground a step ago is you.
			vec3 me = texture(TEXTURE, fp * texel).rgb;
			vec3 ground = texture(prev, clamp(fp + step_px, view.xy + 0.5, view.xy + view.zw - 0.5) * texel).rgb;
			vec3 d = abs(me - ground);
			if (max(d.r, max(d.g, d.b)) > 0.07) {
				c = me;
			}
		}
		if (lit > 0.5) {
			float l = tl.r;
			float seen = smoothstep(0.12, 0.6, tl.g);
			float gloom = max(night, dark);
			// Light with shape: unlit ground sinks, lit ground warms and blooms.
			float glow = smoothstep(0.24, 0.62, l) * gloom * seen;
			float flick = 1.0 + 0.03 * sin(TIME * 11.0 + floor(cell.x * 0.2) * 3.1) * sin(TIME * 7.3);
			c *= mix(1.0, 0.84, gloom * (1.0 - smoothstep(0.10, 0.36, l)) * seen);
			c += c * vec3(0.30, 0.17, 0.02) * glow * flick;
			c += vec3(1.0, 0.72, 0.42) * 0.04 * glow * glow * flick;
			// Shadows fall down and to the right of whatever blocks light.
			if ((flags & 1) == 0) {
				float sh = 0.0;
				for (int i = 1; i <= 6; i++) {
					vec2 q = cell - vec2(0.105, 0.09) * float(i);
					sh = max(sh, float(flags_at(q) & 1) * (1.0 - float(i) / 7.0));
				}
				c *= 1.0 - sh * mix(0.30, 0.18, gloom) * seen;
			}
			float under = 0.0;
			for (int dy = 0; dy <= 1; dy++) {
				for (int dx = 0; dx <= 1; dx++) {
					vec2 t = floor(cell) - vec2(float(dx), float(dy));
					if ((flags_at(t) & 4) != 0) {
						vec2 d = (cell - (t + vec2(0.60, 0.94))) / vec2(0.36, 0.12);
						under = max(under, 1.0 - smoothstep(0.45, 1.0, length(d)));
					}
				}
			}
			if (you.z > 0.0) {
				vec2 d = (fp - (you.xy + you.zw * vec2(0.60, 0.94))) / (you.zw * vec2(0.36, 0.12));
				under = max(under, 1.0 - smoothstep(0.45, 1.0, length(d)));
			}
			c *= 1.0 - 0.30 * under;
			// What you cannot see right now cools and drifts with mist, with a soft edge.
			float fog = 1.0 - seen;
			float mist = noise(wp * 0.013 + vec2(TIME * 0.021, TIME * 0.012))
					* noise(wp * 0.031 - vec2(TIME * 0.016, 0.0));
			c = mix(c, c * vec3(0.68, 0.77, 0.90), fog * 0.5);
			c += vec3(0.035, 0.05, 0.065) * mist * fog;
			// Time of day.
			c *= mix(vec3(1.0), vec3(0.80, 0.88, 1.10), night * 0.55 * (1.0 - glow));
			c *= mix(vec3(1.0), vec3(1.10, 0.98, 0.86), dusk * 0.6);
			float outside = float((flags & 2) != 0);
			if (rain > 0.0) {
				float wet = outside * seen * rain;
				c = mix(c, c * vec3(0.82, 0.89, 0.98), wet * 0.55);
				c += vec3(0.50, 0.60, 0.70) * pow(noise(wp * 0.37), 5.0) * 0.22 * wet;
				vec2 tc = floor(cell);
				float hsh = hash(tc);
				float ph = fract(TIME * 0.9 + hsh * 7.0);
				vec2 ctr = tc + 0.25 + 0.5 * vec2(hash(tc + 3.1), hash(tc + 7.7));
				float r = length((cell - ctr) * vec2(1.0, 1.6));
				float ring = smoothstep(0.035, 0.0, abs(r - ph * 0.28)) * (1.0 - ph)
						* step(hsh, 0.15 + 0.45 * rain);
				c += vec3(0.55, 0.65, 0.75) * ring * 0.20 * wet;
				vec2 sp = fp;
				sp.x += sp.y * 0.18;
				float column = floor(sp.x / 6.0);
				float hc = hash(vec2(column, 1.0));
				float y = fract(sp.y / 96.0 - TIME * (1.7 + hc * 1.3) + hc * 13.0);
				float streak = smoothstep(0.0, 0.02, y) * smoothstep(0.17, 0.02, y)
						* step(hc, 0.10 + 0.25 * rain)
						* step(abs(fract(sp.x / 6.0) - 0.5), 0.06);
				c += vec3(0.62, 0.72, 0.82) * streak * 0.22 * outside * seen;
			}
			if (snow > 0.0) {
				vec2 sp = fp + vec2(sin(TIME * 0.7 + fp.y * 0.02) * 6.0, -TIME * 14.0);
				vec2 gc = floor(sp / 11.0);
				vec2 gf = fract(sp / 11.0) - 0.5;
				float flake = step(hash(gc), 0.05 + 0.10 * snow)
						* smoothstep(0.16, 0.05, length(gf + (vec2(hash(gc + 1.7), hash(gc + 5.1)) - 0.5) * 0.5));
				c += vec3(0.85, 0.90, 0.95) * flake * 0.5 * outside * seen;
			}
		}
		COLOR = vec4(mix(c, grade(c), amount), 1.0);
	}
}
"

const GLIDE_TIME := 0.12
const BLEND_TIME := 0.09
const TEXT_TIME := 1.05

## The map's picture; the shader goes on it.
var frame: TextureRect
var _material: ShaderMaterial
var _scene := {}
var _tiles: ImageTexture
var _has_scene := false
var _tile := Vector2(32, 32)
var _at := Vector2.ZERO
var _origin := Vector2.ZERO
## Where the view was centered when the last frame came in, on the world map.
var _camera := Vector3i.ZERO
var _had_camera := false
var _glide_from := Vector2.ZERO
var _glide_start := -1.0e9
var _blend_start := -1.0e9
var _shake_amp := 0.0
var _shake_start := -1.0e9
var _shake_time := 0.22
## Floating texts: {cell, text, label, color, size, born, lane}.
var _texts: Array = []
## Flashes on a tile: {cell, color, born, dead}.
var _flashes: Array = []
var _hurt_at := -1.0e9
## Health of hostile creatures in view by tile, to light the part that was just lost.
var _health := {}
var _lost: Array = []
var _on := false
var _debug := OS.has_environment("BN_FX_DEBUG")
## Stretches the glide for looking at it frame by frame (development only).
var _slow := float(OS.get_environment("BN_FX_SLOW")) if OS.has_environment("BN_FX_SLOW") else 1.0
var _frames := 0
var _debug_at := 0.0
var _lit_on := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true


func setup(frame_view: TextureRect) -> void:
	frame = frame_view
	_material = Fx.material(SHADER)
	frame.material = _material
	Bridge.scene_received.connect(_on_scene)
	Bridge.fx_received.connect(_on_fx)
	Bridge.frame_received.connect(_on_frame)


## `rect` is where the map shows; `overlay` is whether hits and numbers play (the main screen),
## and `lighting` whether the map's picture is the map at all.
func place(rect: Rect2, overlay: bool, lighting: bool) -> void:
	if position != rect.position or size != rect.size:
		position = rect.position
		size = rect.size
	_on = overlay
	visible = overlay
	_lit_on = lighting
	_material.set_shader_parameter("amount", 1.0 if lighting else 0.0)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _vec(value, fallback := Vector2.ZERO) -> Vector2:
	if typeof(value) == TYPE_ARRAY and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return fallback


func _on_scene(meta: Dictionary, tiles: Image) -> void:
	_scene = meta
	_has_scene = true
	_tile = _vec(meta.get("tile"), Vector2(32, 32))
	_at = _vec(meta.get("at"))
	_origin = _vec(meta.get("origin"))
	if _tiles != null and Vector2i(_tiles.get_size()) == tiles.get_size():
		_tiles.update(tiles)
	else:
		_tiles = ImageTexture.create_from_image(tiles)
		_material.set_shader_parameter("tiles_n", _tiles)
		_material.set_shader_parameter("tiles_l", _tiles)
	var grid := Vector2(tiles.get_size())
	var view_size := _vec(meta.get("size"), grid * _tile)
	_material.set_shader_parameter("lit", 1.0)
	_material.set_shader_parameter("view", Vector4(_at.x, _at.y, view_size.x, view_size.y))
	_material.set_shader_parameter("tile", _tile)
	_material.set_shader_parameter("grid", grid)
	var underground := bool(meta.get("underground", false))
	var sun := float(meta.get("sun", 1.0))
	_material.set_shader_parameter("night", 0.0 if underground else 1.0 - smoothstep(0.05, 0.6, sun))
	_material.set_shader_parameter("dusk", 0.0 if underground else smoothstep(0.02, 0.25, sun) * (1.0 - smoothstep(0.35, 0.8, sun)))
	_material.set_shader_parameter("dark", 1.0 if underground else 0.0)
	var precip := clampf(float(meta.get("precip", 0)) / 4.0, 0.0, 1.0)
	var rains := bool(meta.get("rain", false))
	_material.set_shader_parameter("rain", precip if rains and not underground else 0.0)
	_material.set_shader_parameter("snow", precip if not rains and not underground else 0.0)
	# You are drawn apart from the world while it glides, when the view is centered on you.
	var me := _vec(meta.get("you"), Vector2(-1, -1))
	var middle := ((view_size / _tile) / 2.0).floor()
	var cam_cell := _vec(meta.get("center"), middle)
	if me == cam_cell and me.x >= 0:
		_material.set_shader_parameter("you", Vector4(_at.x + me.x * _tile.x, _at.y + me.y * _tile.y, _tile.x, _tile.y))
	else:
		_material.set_shader_parameter("you", Vector4.ZERO)
	_track_health(meta.get("mobs", []))


## Notes which hostile creatures lost health since the last scene, to flash that part of their bar.
func _track_health(mobs: Array) -> void:
	var seen := {}
	for mob in mobs:
		if typeof(mob) != TYPE_ARRAY or mob.size() < 4 or not bool(mob[3]):
			continue
		var key := Vector2i(int(mob[0]) + int(_origin.x), int(mob[1]) + int(_origin.y))
		var hp := float(mob[2])
		seen[key] = hp
		# A creature that stepped onto the tile is not one that was hurt there: look around it too.
		var before := -1.0
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var was = _health.get(key + Vector2i(dx, dy))
				if was != null and float(was) > hp and (before < 0.0 or float(was) < before):
					before = float(was)
		if before > hp + 0.001:
			_lost.append({"key": key, "from": before, "to": hp, "born": _now()})
	_health = seen


func _on_frame(_texture: ImageTexture) -> void:
	if not _has_scene:
		return
	var cam_raw = _scene.get("cam")
	if typeof(cam_raw) != TYPE_ARRAY or cam_raw.size() < 3:
		return
	var camera := Vector3i(int(cam_raw[0]), int(cam_raw[1]), int(cam_raw[2]))
	var before := Bridge.frame_before()
	var now := _now()
	var moved := Vector2.ZERO
	if _had_camera and camera != _camera and camera.z == _camera.z:
		moved = Vector2(camera.x - _camera.x, camera.y - _camera.y)
	var jumped := not _had_camera or camera.z != _camera.z or absf(moved.x) > 2.0 or absf(moved.y) > 2.0
	_camera = camera
	_had_camera = true
	if before == null or jumped or not _lit_on:
		_glide_start = -1.0e9
		_blend_start = -1.0e9
		_material.set_shader_parameter("step_px", Vector2.ZERO)
		return
	_material.set_shader_parameter("prev", before)
	if moved != Vector2.ZERO:
		# Carry on from wherever the last glide had got to, so held keys flow.
		var step := moved * _tile
		var left := _glide_now(now)
		_glide_from = step + left
		_glide_from.x = clampf(_glide_from.x, -1.6 * _tile.x, 1.6 * _tile.x)
		_glide_from.y = clampf(_glide_from.y, -1.6 * _tile.y, 1.6 * _tile.y)
		_glide_start = now
		_material.set_shader_parameter("step_px", step)
	else:
		_material.set_shader_parameter("step_px", Vector2.ZERO)
		if _glide_now(now) != Vector2.ZERO:
			# A second frame of the same step (an animation): keep gliding, nothing to cross over.
			_blend_start = -1.0e9
			return
	_blend_start = now


func _glide_now(now: float) -> Vector2:
	var t := (now - _glide_start) / (GLIDE_TIME * _slow)
	if t >= 1.0 or t < 0.0:
		return Vector2.ZERO
	var k := 1.0 - t
	return _glide_from * k * k


func _shake_now(now: float) -> Vector2:
	var t := (now - _shake_start) / _shake_time
	if t >= 1.0 or t < 0.0:
		return Vector2.ZERO
	var k := (1.0 - t) * (1.0 - t) * _shake_amp
	return Vector2(sin(now * 91.0), cos(now * 77.0)) * k


func _process(_delta: float) -> void:
	if _material == null:
		return
	var now := _now()
	var glide := _glide_now(now)
	# Whole screen pixels, so the pixel art stays sharp while it moves.
	var per := maxf(frame.scale.x * maxf(Display.ui_scale(), 1.0), 1.0)
	glide = (glide * per).round() / per
	_material.set_shader_parameter("glide", glide)
	_material.set_shader_parameter("shake", (_shake_now(now) * per).round() / per)
	_material.set_shader_parameter("blend", clampf((now - _blend_start) / (BLEND_TIME * _slow), 0.0, 1.0))
	if _debug:
		_frames += 1
		if now - _debug_at >= 1.0:
			print("map stage: %d fps" % _frames)
			_frames = 0
			_debug_at = now
	if not _on:
		return
	_texts = _texts.filter(func(t): return now - t["born"] < TEXT_TIME)
	_flashes = _flashes.filter(func(f): return now - f["born"] < 0.45)
	_lost = _lost.filter(func(l): return now - l["born"] < 0.5)
	queue_redraw()


func _shake(amp: float, time := 0.22) -> void:
	if amp >= _shake_now(_now()).length():
		_shake_amp = amp
		_shake_time = time
		_shake_start = _now()


func _on_fx(list: Array) -> void:
	var now := _now()
	for fx in list:
		if typeof(fx) != TYPE_DICTIONARY:
			continue
		var cell := Vector2(float(fx.get("x", 0)), float(fx.get("y", 0)))
		match String(fx.get("k", "")):
			"hit":
				var you := bool(fx.get("you", false))
				var dead := bool(fx.get("dead", false))
				_flashes.append({"cell": cell, "color": Slate.DANGER if you else Color.WHITE, "born": now, "dead": dead})
				if you:
					_hurt_at = now
					_shake(2.2, 0.26)
				else:
					_shake(2.6 if dead else 1.4, 0.3 if dead else 0.2)
			"text":
				_add_text(fx, cell, now)


func _add_text(fx: Dictionary, cell: Vector2, now: float) -> void:
	var kind := String(fx.get("kind", ""))
	if kind == "hp":
		# The creature's health shows as a bar over it instead.
		return
	var a := String(fx.get("a", ""))
	var b := String(fx.get("b", ""))
	var bk := String(fx.get("bk", ""))
	var entry := {"cell": cell, "born": now, "label": "", "size": 15.0, "color": Slate.TEXT}
	if fx.has("dmg"):
		entry["text"] = str(int(fx["dmg"]))
		entry["size"] = 22.0
		entry["label"] = b
		if String(fx.get("ak", "")) == "bad":
			entry["text"] = "-" + entry["text"]
			entry["color"] = Slate.DANGER
		elif bk == "critical" or bk == "headshot":
			entry["color"] = Slate.ACCENT
			entry["size"] = 28.0
			_shake(2.8, 0.3)
		elif bk == "grazing":
			entry["color"] = Slate.MUTED
			entry["size"] = 18.0
	else:
		entry["text"] = (a + " " + b).strip_edges()
		entry["color"] = Slate.MUTED
	if String(entry["text"]) == "":
		return
	var lane := 0
	for t in _texts:
		if t["cell"] == cell and now - t["born"] < 0.5:
			lane += 1
	entry["lane"] = lane
	_texts.append(entry)


## Where a tile's top left corner is, in this control. `cell` is a tile in the game's map
## coordinates, as effects name it.
func _tile_at(cell: Vector2) -> Vector2:
	var now := _now()
	var px := _at + (cell - _origin) * _tile + _glide_now(now) + _shake_now(now)
	return frame.position + px * frame.scale.x - position


func _draw() -> void:
	if not _on or not _has_scene:
		return
	var now := _now()
	var unit := _tile * frame.scale.x
	for f in _flashes:
		var age: float = now - f["born"]
		var at := _tile_at(f["cell"])
		var k := clampf(1.0 - age / 0.16, 0.0, 1.0)
		if k > 0.0:
			draw_rect(Rect2(at, unit), Color(f["color"], 0.55 * k * k))
		if f["dead"]:
			var r := age / 0.45
			var ring := Color(Slate.DANGER, 0.7 * (1.0 - r))
			draw_arc(at + unit / 2, unit.x * (0.3 + 0.7 * r), 0, TAU, 40, ring, maxf(2.0 * (1.0 - r), 0.6), true)
	_draw_health(now, unit)
	var font := Slate.heavy()
	var small := Slate.bold()
	for t in _texts:
		var age: float = now - t["born"]
		var k := age / TEXT_TIME
		var pop := 1.0 + 0.4 * clampf(1.0 - age / 0.12, 0.0, 1.0)
		var fade := clampf((1.0 - k) / 0.35, 0.0, 1.0)
		var size := int(round(float(t["size"]) * pop))
		var text := String(t["text"])
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var rise := unit.y * (0.25 + 0.75 * (1.0 - (1.0 - k) * (1.0 - k)))
		var at := _tile_at(t["cell"]) + Vector2(unit.x / 2 - width / 2 + int(t["lane"]) * unit.x * 0.45, -rise + unit.y * 0.35)
		at = at.round()
		var color := Color(t["color"], fade)
		draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 5, Color(0, 0, 0, 0.85 * fade))
		draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
		var label := String(t["label"]).to_upper()
		if label != "":
			var lsize := 11
			var lwidth := small.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, lsize).x
			var lat := Vector2(at.x + width / 2 - lwidth / 2, at.y - size * 0.95).round()
			draw_string_outline(small, lat, label, HORIZONTAL_ALIGNMENT_LEFT, -1, lsize, 4, Color(0, 0, 0, 0.85 * fade))
			draw_string(small, lat, label, HORIZONTAL_ALIGNMENT_LEFT, -1, lsize, color)
	var hurt := clampf(1.0 - (now - _hurt_at) / 0.4, 0.0, 1.0)
	if hurt > 0.0:
		_edge(Rect2(Vector2.ZERO, size), 60.0, Color(Slate.DANGER, 0.42 * hurt * hurt))


## Hurt hostile creatures carry a small bar of five parts; a part just lost flashes white first.
func _draw_health(now: float, unit: Vector2) -> void:
	var mobs = _scene.get("mobs", [])
	if typeof(mobs) != TYPE_ARRAY:
		return
	for mob in mobs:
		if typeof(mob) != TYPE_ARRAY or mob.size() < 4 or not bool(mob[3]):
			continue
		var hp := float(mob[2])
		if hp >= 0.999:
			continue
		var cell := Vector2(float(mob[0]), float(mob[1])) + _origin
		var key := Vector2i(cell)
		var lost_from := hp
		var lost_k := 0.0
		for l in _lost:
			if l["key"] == key:
				lost_from = maxf(lost_from, float(l["from"]))
				lost_k = maxf(lost_k, 1.0 - (now - float(l["born"])) / 0.5)
		var at := _tile_at(cell)
		var parts := 5
		var gap := 1.0
		var width := unit.x * 0.78
		var part := (width - gap * (parts - 1)) / parts
		var bar := Vector2(at.x + (unit.x - width) / 2, at.y - 5.0).round()
		draw_rect(Rect2(bar - Vector2(1, 1), Vector2(width + 2, 5)), Color(0, 0, 0, 0.7))
		for i in parts:
			var from := float(i) / parts
			var to := float(i + 1) / parts
			var r := Rect2(bar + Vector2(i * (part + gap), 0), Vector2(part, 3))
			var fill := clampf((hp - from) / (to - from), 0.0, 1.0)
			draw_rect(r, Color("#26090c"))
			if lost_k > 0.0 and lost_from > from:
				var was := clampf((lost_from - from) / (to - from), 0.0, 1.0)
				draw_rect(Rect2(r.position, Vector2(part * was, 3)), Color(1, 1, 1, lost_k))
			if fill > 0.0:
				draw_rect(Rect2(r.position, Vector2(part * fill, 3)), Slate.DANGER)


func _edge(r: Rect2, depth: float, color: Color) -> void:
	var clear := Color(color, 0.0)
	var a := r.position
	var b := r.end
	var quads := [
		[a, Vector2(b.x, a.y), Vector2(b.x, a.y + depth), Vector2(a.x, a.y + depth)],
		[Vector2(a.x, b.y), b, Vector2(b.x, b.y - depth), Vector2(a.x, b.y - depth)],
		[a, Vector2(a.x, b.y), Vector2(a.x + depth, b.y), Vector2(a.x + depth, a.y)],
		[Vector2(b.x, a.y), b, Vector2(b.x - depth, b.y), Vector2(b.x - depth, a.y)],
	]
	for q in quads:
		draw_polygon(PackedVector2Array(q), PackedColorArray([color, color, clear, clear]))
