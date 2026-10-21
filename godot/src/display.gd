extends Node
## Interface and map size for big screens.
##
## The interface scales by a factor picked from the screen height (1080p is 1x, 4K is 2x) unless
## the player picks one. The game draws the map at the window size divided by the map scale, and
## Godot shows it enlarged with sharp pixels: tiles get bigger and the game has fewer pixels to
## draw and send. Shortcuts: Ctrl+= / Ctrl+- for the interface, with Shift for the map, Ctrl+0 to
## go back to automatic.

signal changed

const PATH := "user://display.cfg"
const UI_STEPS := [1.0, 1.25, 1.5, 1.75, 2.0, 2.25, 2.5, 2.75, 3.0, 3.5, 4.0]
const MAP_MAX := 6

## 0 means automatic.
var ui_choice := 0.0
var map_choice := 0
var _ui := 0.0
var _map := 0


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		ui_choice = float(cfg.get_value("display", "interface", 0.0))
		map_choice = int(cfg.get_value("display", "map", 0))
	var window := get_window()
	# The default window is small on a big screen; start filling it.
	var screen := DisplayServer.screen_get_usable_rect(window.current_screen)
	if screen.size.x > window.size.x * 1.3 or screen.size.y > window.size.y * 1.3:
		window.position = screen.position
		window.size = screen.size
		window.mode = Window.MODE_MAXIMIZED
	# Moving the window to another screen can change the automatic scale.
	window.size_changed.connect(_apply)
	_apply()


## Interface scale picked from the screen the window is on.
func auto_ui() -> float:
	var height := DisplayServer.screen_get_size(get_window().current_screen).y
	var raw := height / 1080.0
	var pick := 1.0
	for step in UI_STEPS:
		if step <= raw + 0.01:
			pick = step
	return pick


func ui_scale() -> float:
	return ui_choice if ui_choice > 0.0 else auto_ui()


## Screen pixels per game pixel on the map. Automatic keeps about the same number of tiles in
## view on 1440p and 4K screens, a little closer than on 1080p.
func map_scale() -> int:
	if map_choice > 0:
		return map_choice
	var height := DisplayServer.screen_get_size(get_window().current_screen).y
	return 3 if height >= 1800 else 2 if height >= 1300 else 1


## Size in game pixels of an area measured in interface units.
func to_game(logical: float) -> int:
	return int(logical * _ui / _map)


func game_size(logical: Vector2) -> Vector2i:
	return Vector2i(to_game(logical.x), to_game(logical.y))


## How much bigger than one interface unit a game pixel is drawn.
func frame_scale() -> float:
	return _map / _ui


func step_ui(direction: int) -> void:
	var at := 0
	for i in UI_STEPS.size():
		if UI_STEPS[i] <= ui_scale() + 0.01:
			at = i
	ui_choice = UI_STEPS[clampi(at + direction, 0, UI_STEPS.size() - 1)]
	_save()


func step_map(direction: int) -> void:
	map_choice = clampi(map_scale() + direction, 1, MAP_MAX)
	_save()


func set_ui(choice: float) -> void:
	ui_choice = choice
	_save()


func set_map(choice: int) -> void:
	map_choice = choice
	_save()


func reset() -> void:
	ui_choice = 0.0
	map_choice = 0
	_save()


## Short description of the current sizes, e.g. "Interface 200% · Map 2×".
func describe() -> String:
	return "Interface %d%%%s · Map %d×%s" % [roundi(_ui * 100), " (auto)" if ui_choice <= 0.0 else "",
			_map, " (auto)" if map_choice <= 0 else ""]


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("display", "interface", ui_choice)
	cfg.set_value("display", "map", map_choice)
	cfg.save(PATH)
	_apply()


func _apply() -> void:
	var ui := ui_scale()
	var map := map_scale()
	if is_equal_approx(ui, _ui) and map == _map:
		return
	_ui = ui
	_map = map
	Slate.set_icon_scale(ui)
	get_window().content_scale_factor = ui
	changed.emit()
