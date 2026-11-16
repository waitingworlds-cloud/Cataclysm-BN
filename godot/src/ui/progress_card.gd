extends PanelContainer
## Progress of a long action (crafting, reading, butchering, travelling, sleeping) at the foot of
## the map, in place of the old interface's wait popup: what you are doing, a bar with how far
## along it is, the time left, and a button that stops it as the pause key does. The game's full
## message, speed factors included, shows on hover.

const Hud := preload("res://src/ui/hud.gd")
const WIDTH := 460.0

var _title: Label
var _kind: Label
var _bar: Hud.SegmentBar
var _percent: Label
var _time: Label
var _sub: Label
var _stop: Hud.ReachButton
var _stop_key := ""
var _shown := {}


func _init() -> void:
	var sb := Slate.module_box(0)
	sb.border_color = Color(Slate.ACCENT, 0.7)
	sb.set_border_width_all(1)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 18
	add_theme_stylebox_override("panel", sb)
	custom_minimum_size.x = WIDTH
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var pad := MarginContainer.new()
	for side in ["left", "right"]:
		pad.add_theme_constant_override("margin_" + side, 14)
	for side in ["top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 10)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(pad)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(head)
	var marker := ColorRect.new()
	marker.color = Slate.ACCENT
	marker.custom_minimum_size = Vector2(6, 6)
	marker.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(marker)
	_kind = Slate.label("In progress", 11, Slate.ACCENT, Slate.spaced(Slate.heavy(), 2))
	_kind.uppercase = true
	_kind.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_kind)
	_time = Slate.label("", 11, Slate.MUTED, Slate.mono())
	head.add_child(_time)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(row)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 6)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text)
	_title = Slate.label("", 15, Slate.TEXT, Slate.semibold())
	_title.clip_text = true
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text.add_child(_title)
	var meter := HBoxContainer.new()
	meter.add_theme_constant_override("separation", 10)
	meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_child(meter)
	_bar = Hud.SegmentBar.new(24)
	_bar.custom_minimum_size.y = 9
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	meter.add_child(_bar)
	_percent = Slate.label("", 13, Slate.ACCENT, Slate.mono())
	_percent.custom_minimum_size.x = 48
	_percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	meter.add_child(_percent)
	_sub = Slate.label("", 11, Slate.MUTED, Slate.mono())
	_sub.visible = false
	text.add_child(_sub)


## `activity` is the HUD's `activity`: {kind, text (runs), stoppable, and for activities whose
## message has no progress, done (0 to 1) and left (time)}, or empty when idle.
## `stop_key` labels the key that stops it.
func apply(activity: Dictionary, stop_key: String) -> void:
	var state := [activity, stop_key]
	if state == _shown.get("state"):
		return
	_shown["state"] = state
	visible = not activity.is_empty()
	if not visible:
		return
	var kind := String(activity.get("kind", "activity"))
	_kind.text = {"sleep": "Sleeping", "travel": "Travelling"}.get(kind, "In progress")
	var lines := Slate.plain(activity.get("text", [])).split("\n", false)
	var parsed := parse(lines)
	_title.text = Slate.cap(String(parsed["title"]))
	var percent: float = parsed["percent"]
	if percent < 0.0 and activity.has("done"):
		percent = clampf(float(activity["done"]) * 100.0, 0.0, 100.0)
	if parsed["time"] == "" and String(activity.get("left", "")) != "":
		parsed["time"] = String(activity["left"]) + " left"
	_bar.visible = percent >= 0.0
	_percent.visible = percent >= 0.0
	if percent >= 0.0:
		_bar.set_level(percent / 100.0, Slate.ACCENT)
		_percent.text = "%d%%" % floori(percent)
	_time.text = String(parsed["time"]).to_upper()
	_sub.text = String(parsed["sub"])
	_sub.visible = _sub.text != ""
	tooltip_text = "\n".join(lines).strip_edges()
	_set_stop(bool(activity.get("stoppable", true)), stop_key)


func _set_stop(on: bool, key: String) -> void:
	if _stop != null and (not on or key != _stop_key):
		_stop.queue_free()
		_stop = null
	if on and _stop == null:
		_stop_key = key
		_stop = Hud.ReachButton.new("Stop", key, false, true)
		_stop.custom_minimum_size.x = 92
		_stop.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_stop.tooltip_text = "Stop, as the pause key does (the game asks first)"
		_stop.pressed.connect(func(): Bridge.run_action("pause"))
		_title.get_parent().get_parent().add_child(_stop)


## Reads the game's progress message: its first line names the action; "Progress"/"Current" and
## "Total" lines carry percentages, "Time left" and "Estimated time" the time; a message without
## those lines (crafting) may still carry a percentage in its first line.
static func parse(lines: PackedStringArray) -> Dictionary:
	var out := {"title": "", "percent": -1.0, "time": "", "sub": ""}
	if lines.is_empty():
		return out
	var pct := RegEx.create_from_string("(\\d+(?:\\.\\d+)?)\\s*%")
	out["title"] = lines[0].strip_edges().trim_suffix(":")
	var total := -1.0
	var current := -1.0
	for i in lines.size():
		var line := lines[i].strip_edges().trim_prefix("-").strip_edges()
		var m := pct.search(line)
		if line.begins_with("Total"):
			if m != null:
				total = float(m.get_string(1))
		elif line.begins_with("Progress") or line.begins_with("Current"):
			if m != null:
				current = float(m.get_string(1))
		elif line.begins_with("Processing"):
			out["sub"] = line
		elif line.begins_with("Time left:") or line.begins_with("Estimated time:"):
			if out["time"] == "" or line.begins_with("Estimated time:"):
				out["time"] = line.get_slice(":", 1).strip_edges() + " left"
		elif i == 0 and m != null:
			current = float(m.get_string(1))
	out["percent"] = total if total >= 0.0 else current
	if lines[0].contains("%") and total < 0.0 and current >= 0.0:
		# "Crafting: knife (45%)": the title without the number the bar shows.
		out["title"] = pct.sub(lines[0], "", true).replace("()", "").strip_edges().trim_suffix(":")
	return out
