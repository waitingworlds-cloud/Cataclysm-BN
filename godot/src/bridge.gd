extends Node
## Connection to the game process.
##
## Godot listens on a local port, starts the game with BN_GODOT_BRIDGE pointing at it, then
## exchanges length-prefixed messages over the socket:
##   game -> Godot: [u32 length][u8 kind][payload]; kind 1 = frame, 2 = JSON, 3 = minimap
##   Godot -> game: [u32 length][JSON]
## See README.md for the message types.

signal connected
signal frame_received(texture: ImageTexture)
signal minimap_received(texture: ImageTexture)
signal frame_meta(main_view: bool, views: Array)
signal hud_received(hud: Dictionary)
signal view_received(view: Dictionary)
signal entries_received(id: int, entries: Array)
signal view_closed(id: int)
signal game_exited(reason: String)

const KIND_FRAME := 1
const KIND_JSON := 2
const KIND_MINIMAP := 3

var _server := TCPServer.new()
var _peer: StreamPeerTCP
var _pid := -1
var _buf := PackedByteArray()
var _pos := 0
var _texture: ImageTexture
var _minimap: ImageTexture
var _said_hello := false
var _pending_mouse := {}
var launch_error := ""
var _debug := OS.has_environment("BN_BRIDGE_DEBUG")
## With `BN_BRIDGE_DEBUG=full`, messages print whole instead of cut to 300 characters.
var _debug_full := OS.get_environment("BN_BRIDGE_DEBUG") == "full"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var opts := _options()
	var port := int(opts.get("port", "0"))
	var err := _server.listen(port, "127.0.0.1")
	if err != OK:
		launch_error = "Could not open a local port for the game (error %d)." % err
		return
	port = _server.get_local_port()
	if opts.has("attach"):
		print("Bridge: waiting for a game started with BN_GODOT_BRIDGE=127.0.0.1:%d" % port)
		return
	_launch(opts, port)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		if _peer != null and _peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			send({"t": "quit"})
			_peer.poll()


## Command line options given after `--`, e.g. `godot --path godot -- --bn=/path/to/cataclysm-bn-tiles`.
func _options() -> Dictionary:
	var out := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--"):
			var pair := arg.substr(2).split("=", true, 1)
			out[pair[0]] = pair[1] if pair.size() > 1 else ""
	return out


func _find_game(opts: Dictionary) -> String:
	if opts.has("bn"):
		return opts["bn"]
	if OS.has_environment("BN_EXECUTABLE"):
		return OS.get_environment("BN_EXECUTABLE")
	var exe_name := "cataclysm-bn-tiles" + (".exe" if OS.get_name() == "Windows" else "")
	var here := OS.get_executable_path().get_base_dir()
	var repo := ProjectSettings.globalize_path("res://").path_join("..").simplify_path()
	var candidates := [here.path_join(exe_name), repo.path_join(exe_name), repo.path_join("build/src").path_join(exe_name)]
	for preset in ["linux-slim", "linux-full", "osx-arm-slim", "windows-tiles-sounds-x64-msvc"]:
		var dir := repo.path_join("out/build/%s/src" % preset)
		candidates.append(dir.path_join(exe_name))
		# Visual Studio builds go in a folder per configuration.
		for config in ["Release", "RelWithDebInfo", "Debug"]:
			candidates.append(dir.path_join(config).path_join(exe_name))
	for path in candidates:
		if FileAccess.file_exists(path):
			return path
	return ""


func _find_root(opts: Dictionary, game: String) -> String:
	if opts.has("bn-root"):
		return opts["bn-root"]
	# The game's base path is the folder holding data/.
	var dir := game.get_base_dir()
	for i in 6:
		if DirAccess.dir_exists_absolute(dir.path_join("data/json")):
			return dir
		dir = dir.path_join("..").simplify_path()
	return game.get_base_dir()


func _launch(opts: Dictionary, port: int) -> void:
	var game := _find_game(opts)
	if game == "":
		launch_error = "Could not find the game. Start with -- --bn=/path/to/cataclysm-bn-tiles."
		return
	var root := _find_root(opts, game)
	var args := PackedStringArray(["--basepath", root.path_join("")])
	if opts.has("userdir"):
		args.append_array(["--userdir", String(opts["userdir"]).path_join("")])
	elif OS.get_name() == "Windows":
		# On Windows the game keeps saves and settings in its own folder. It finds that folder
		# from the working directory, which is wrong when the app is started from a shortcut.
		args.append_array(["--userdir", root.path_join("")])
	if opts.has("world"):
		args.append_array(["--world", opts["world"]])
	OS.set_environment("BN_GODOT_BRIDGE", "127.0.0.1:%d" % port)
	_pid = OS.create_process(game, args)
	if _pid <= 0:
		launch_error = "Could not start the game at %s." % game


func is_connected_to_game() -> bool:
	return _peer != null and _peer.get_status() == StreamPeerTCP.STATUS_CONNECTED


func _process(_delta: float) -> void:
	if _peer == null:
		if _server.is_listening() and _server.is_connection_available():
			_peer = _server.take_connection()
			_peer.set_no_delay(true)
		elif _pid > 0 and not OS.is_process_running(_pid):
			_pid = -1
			game_exited.emit("The game closed before it connected.")
		return
	_peer.poll()
	if _peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		_peer = null
		game_exited.emit("The game has closed.")
		return
	if not _pending_mouse.is_empty():
		send(_pending_mouse)
		_pending_mouse = {}
	_read()


func _read() -> void:
	while true:
		var available := _peer.get_available_bytes()
		if available <= 0:
			break
		var got := _peer.get_partial_data(available)
		if got[0] != OK:
			break
		_buf.append_array(got[1])
	# Parse every complete message in the buffer.
	while _buf.size() - _pos >= 5:
		var length := _buf.decode_u32(_pos)
		if _buf.size() - _pos - 4 < length:
			break
		var kind := _buf[_pos + 4]
		var start := _pos + 5
		var end := _pos + 4 + length
		if kind == KIND_FRAME:
			_texture = _decode_image(start, end, _texture)
			if _texture != null:
				frame_received.emit(_texture)
		elif kind == KIND_MINIMAP:
			_minimap = _decode_image(start, end, _minimap)
			if _minimap != null:
				minimap_received.emit(_minimap)
		elif kind == KIND_JSON:
			_on_json(_buf.slice(start, end).get_string_from_utf8())
		_pos = end
	if _pos > 0 and _pos >= _buf.size():
		_buf.clear()
		_pos = 0
	elif _pos > 16 * 1024 * 1024:
		_buf = _buf.slice(_pos)
		_pos = 0


## Decodes `[u32 width][u32 height][RGBA8 pixels]` into `texture`, reusing it when the size fits.
func _decode_image(start: int, end: int, texture: ImageTexture) -> ImageTexture:
	var width := _buf.decode_u32(start)
	var height := _buf.decode_u32(start + 4)
	var pixels := _buf.slice(start + 8, end)
	if pixels.size() != width * height * 4:
		return texture
	var image := Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, pixels)
	if texture != null and texture.get_width() == width and texture.get_height() == height:
		texture.update(image)
		return texture
	return ImageTexture.create_from_image(image)


func _on_json(text: String) -> void:
	var msg = JSON.parse_string(text)
	if typeof(msg) != TYPE_DICTIONARY:
		if _debug:
			print("bad message from game: ", text.left(4000))
		return
	if _debug and msg.get("t", "") != "hud":
		print("game: ", text if _debug_full else text.left(300))
	match String(msg.get("t", "")):
		"hello":
			if not _said_hello:
				_said_hello = true
				var size := Display.game_size(get_viewport().get_visible_rect().size)
				send({"t": "hello", "w": size.x, "h": size.y})
				connected.emit()
		"frame":
			frame_meta.emit(bool(msg.get("main", false)), msg.get("views", []))
		"hud":
			hud_received.emit(msg)
		"view":
			view_received.emit(msg)
		"entries":
			entries_received.emit(int(msg.get("id", 0)), msg.get("entries", []))
		"close":
			view_closed.emit(int(msg.get("id", 0)))


## Sends one JSON message to the game.
func send(msg: Dictionary) -> void:
	if not is_connected_to_game():
		return
	var body := JSON.stringify(msg).to_utf8_buffer()
	var header := PackedByteArray()
	header.resize(4)
	header.encode_u32(0, body.size())
	_peer.put_data(header + body)


## Mouse motion is coalesced to one message per frame.
func send_mouse_move(pos: Vector2) -> void:
	_pending_mouse = {"t": "mouse", "e": "move", "x": int(pos.x), "y": int(pos.y)}


func send_mouse(kind: String, pos: Vector2, button := 1, dy := 0) -> void:
	_pending_mouse = {}
	send({"t": "mouse", "e": kind, "x": int(pos.x), "y": int(pos.y), "b": button, "dy": dy})


## Runs a game action (as named in the keybindings) by pressing the key bound to it.
func run_action(action_id: String, category := "DEFAULTMODE") -> void:
	send({"t": "action", "id": action_id, "cat": category})


## Picks entry `index` in native view `view_id`, then presses `act` (CONFIRM by default).
func pick(view_id: int, index: int, act := "CONFIRM") -> void:
	send({"t": "pick", "id": view_id, "index": index, "act": act})


## Presses the key bound to `act` in native view `view_id`'s input context.
func press(view_id: int, act: String) -> void:
	send({"t": "press", "id": view_id, "act": act})


## Tells the game the window's size in game pixels.
func send_resize(size: Vector2i) -> void:
	send({"t": "resize", "w": size.x, "h": size.y})
