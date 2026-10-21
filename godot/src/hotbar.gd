extends Node
## Item hotbar slots: nine item types per character, saved in user://hotbar.cfg and sent to the
## game, which reports in the HUD what each slot holds. Alt+1 to Alt+9 use a slot on the map and
## pin the open item card's item to it; plain 1 to 9 stay movement keys.

signal changed

const PATH := "user://hotbar.cfg"
const SIZE := 9

var slots: Array = []
var _character := ""


func _ready() -> void:
	slots.resize(SIZE)
	slots.fill("")
	Bridge.hud_received.connect(_on_hud)
	Bridge.connected.connect(func(): _character = "")


func _on_hud(hud: Dictionary) -> void:
	var character := String(hud.get("name", ""))
	if character == _character:
		return
	_character = character
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	var saved: Array = cfg.get_value("characters", _character, [])
	slots.fill("")
	for i in mini(saved.size(), SIZE):
		slots[i] = String(saved[i])
	_send()


## Puts `item_type` in `slot`, or the first empty slot when `slot` is -1. Returns the slot used,
## or -1 when every slot is full.
func pin(item_type: String, slot := -1) -> int:
	if slot < 0:
		slot = slots.find(item_type)
	if slot < 0:
		slot = slots.find("")
	if slot < 0:
		return -1
	var old := slots.find(item_type)
	if old >= 0 and old != slot:
		slots[old] = slots[slot]
	slots[slot] = item_type
	_save()
	return slot


func clear(slot: int) -> void:
	slots[slot] = ""
	_save()


func swap(a: int, b: int) -> void:
	var held: String = slots[a]
	slots[a] = slots[b]
	slots[b] = held
	_save()


func use(slot: int) -> void:
	if slots[slot] != "":
		Bridge.send({"t": "hotbar_use", "slot": slot})


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	cfg.set_value("characters", _character, slots)
	cfg.save(PATH)
	_send()


func _send() -> void:
	Bridge.send({"t": "hotbar", "slots": slots})
	changed.emit()
