extends VBoxContainer
## Warnings the game just gave (a creature comes into view, you are about to fall asleep, an
## item is about to break), shown for a few seconds at the top of the map so they are not lost
## in the log. Each one also stays in the log. Hover holds them; a click dismisses one.

const SHOWN := 3
const HOLD := 6.0
const FADE := 0.5

## A warning text shown in the last `QUIET_MS` milliseconds does not show again.
const QUIET_MS := 90000

var _seen := {}


func _init() -> void:
	add_theme_constant_override("separation", 6)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## `alerts` is the HUD's `alerts`: [time, text] pairs of warnings since the last update. The
## same warning arrives in several updates, and some repeat every few turns (cold feet while
## waiting): one already shown stays quiet for a while, as it still is in the log.
func apply(alerts: Array) -> void:
	var now := Time.get_ticks_msec()
	for alert in alerts:
		if not (alert is Array) or alert.size() < 2:
			continue
		var text := String(alert[1])
		if now - int(_seen.get(text, -QUIET_MS)) < QUIET_MS:
			continue
		_seen[text] = now
		_add(String(alert[0]), text)
	if _seen.size() > 64:
		for text in _seen.keys():
			if now - int(_seen[text]) >= QUIET_MS:
				_seen.erase(text)


func _add(time: String, text: String) -> void:
	var live := get_children().filter(func(c): return not c.is_queued_for_deletion())
	while live.size() >= SHOWN:
		live.pop_front().queue_free()
	var pill := PanelContainer.new()
	var sb := Slate.pill_box(Color(Slate.CARD_SOLID, 0.94), 12, 6)
	sb.border_color = Color(Slate.WARN, 0.8)
	sb.border_width_left = 3
	sb.set_corner_radius_all(4)
	pill.add_theme_stylebox_override("panel", sb)
	pill.mouse_filter = Control.MOUSE_FILTER_STOP
	pill.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pill.tooltip_text = "%s  %s\nClick to dismiss. It stays in the log." % [time, text]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(row)
	var mark := Slate.label("!", 14, Slate.WARN, Slate.heavy())
	row.add_child(mark)
	var body := Slate.label(Slate.cap(text), 14, Slate.TEXT, Slate.semibold())
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var font := body.get_theme_font("font")
	var width := font.get_string_size(body.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			body.get_theme_font_size("font_size")).x
	body.custom_minimum_size.x = minf(520.0, ceilf(width) + 2.0)
	row.add_child(body)
	var stamp := Slate.label(time, 11, Slate.MUTED, Slate.mono())
	stamp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(stamp)
	add_child(pill)

	pill.modulate.a = 0.0
	var tween := pill.create_tween()
	tween.tween_property(pill, "modulate:a", 1.0, 0.15)
	var timer := get_tree().create_timer(HOLD)
	timer.timeout.connect(_expire.bind(pill))
	pill.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			pill.queue_free()
			pill.accept_event())


## Fades a warning out once its time is up, unless the pointer is on it (then it waits again).
func _expire(pill: PanelContainer) -> void:
	if not is_instance_valid(pill) or pill.is_queued_for_deletion():
		return
	if pill.get_global_rect().has_point(pill.get_global_mouse_position()):
		get_tree().create_timer(1.5).timeout.connect(_expire.bind(pill))
		return
	var tween := pill.create_tween()
	tween.tween_property(pill, "modulate:a", 0.0, FADE)
	tween.tween_callback(pill.queue_free)
