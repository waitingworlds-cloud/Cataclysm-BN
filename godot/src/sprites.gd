extends Node
## Tile sprites for the interface: items in slots show the same pixel art as on the map. The
## game draws the sprites it is asked for from its tileset and sends them as a strip; they are
## kept here by id. An id is a tile category and a name, e.g. `item:knife_combat`.

signal changed

## id -> Texture2D, or null when the tileset has no sprite for it.
var _textures := {}
var _wanted := {}
var _asked := {}


func _ready() -> void:
	Bridge.sprites_received.connect(_on_sprites)
	Bridge.connected.connect(_reset)


func _reset() -> void:
	_textures.clear()
	_wanted.clear()
	_asked.clear()
	changed.emit()


## The sprite for an item type, or null while it is on its way or when there is none.
func item(type: String) -> Texture2D:
	return _lookup("item:" + type) if type != "" else null


## True once the game has answered for this item type (with a sprite or without).
func item_known(type: String) -> bool:
	return _textures.has("item:" + type)


func _lookup(id: String) -> Texture2D:
	if _textures.has(id):
		return _textures[id]
	if not _asked.has(id):
		_wanted[id] = true
	return null


func _process(_delta: float) -> void:
	if _wanted.is_empty() or not Bridge.is_connected_to_game():
		return
	var ids := _wanted.keys()
	for id in ids:
		_asked[id] = true
	_wanted.clear()
	Bridge.send({"t": "sprites", "ids": ids})


func _on_sprites(meta: Dictionary, strip: Image) -> void:
	var ids: Array = meta.get("ids", [])
	var found: Array = meta.get("found", [])
	var width := int(meta.get("w", 0))
	var height := int(meta.get("h", 0))
	if width <= 0 or height <= 0:
		return
	for i in ids.size():
		var id := String(ids[i])
		if i >= found.size() or not bool(found[i]) or (i + 1) * width > strip.get_width():
			_textures[id] = null
			continue
		var cell := strip.get_region(Rect2i(i * width, 0, width, height))
		# Trim the empty border so the art fills its slot.
		var used := cell.get_used_rect()
		if used.size.x <= 0 or used.size.y <= 0:
			_textures[id] = null
			continue
		var side := maxi(used.size.x, used.size.y)
		var square := Image.create(side, side, false, Image.FORMAT_RGBA8)
		square.blit_rect(cell, used, Vector2i((side - used.size.x) / 2, (side - used.size.y) / 2))
		_textures[id] = ImageTexture.create_from_image(square)
	changed.emit()
