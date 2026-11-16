extends RefCounted
## Turns Godot key events into the SDL key and text events the game understands.

const SDLK_SCANCODE_MASK := 1 << 30
const MOD_SHIFT := 0x0001
const MOD_CTRL := 0x0040
const MOD_ALT := 0x0100
const MOD_GUI := 0x0400

## Godot keys without a printable character, as SDL keycodes.
const SPECIAL := {
	KEY_ESCAPE: 27,
	KEY_TAB: 9,
	KEY_BACKTAB: 9,
	KEY_BACKSPACE: 8,
	KEY_ENTER: 13,
	KEY_DELETE: 127,
	KEY_INSERT: SDLK_SCANCODE_MASK | 73,
	KEY_HOME: SDLK_SCANCODE_MASK | 74,
	KEY_PAGEUP: SDLK_SCANCODE_MASK | 75,
	KEY_END: SDLK_SCANCODE_MASK | 77,
	KEY_PAGEDOWN: SDLK_SCANCODE_MASK | 78,
	KEY_RIGHT: SDLK_SCANCODE_MASK | 79,
	KEY_LEFT: SDLK_SCANCODE_MASK | 80,
	KEY_DOWN: SDLK_SCANCODE_MASK | 81,
	KEY_UP: SDLK_SCANCODE_MASK | 82,
	KEY_KP_DIVIDE: SDLK_SCANCODE_MASK | 84,
	KEY_KP_MULTIPLY: SDLK_SCANCODE_MASK | 85,
	KEY_KP_SUBTRACT: SDLK_SCANCODE_MASK | 86,
	KEY_KP_ADD: SDLK_SCANCODE_MASK | 87,
	KEY_KP_ENTER: SDLK_SCANCODE_MASK | 88,
	KEY_KP_1: SDLK_SCANCODE_MASK | 89,
	KEY_KP_2: SDLK_SCANCODE_MASK | 90,
	KEY_KP_3: SDLK_SCANCODE_MASK | 91,
	KEY_KP_4: SDLK_SCANCODE_MASK | 92,
	KEY_KP_5: SDLK_SCANCODE_MASK | 93,
	KEY_KP_6: SDLK_SCANCODE_MASK | 94,
	KEY_KP_7: SDLK_SCANCODE_MASK | 95,
	KEY_KP_8: SDLK_SCANCODE_MASK | 96,
	KEY_KP_9: SDLK_SCANCODE_MASK | 97,
	KEY_KP_0: SDLK_SCANCODE_MASK | 98,
	KEY_KP_PERIOD: SDLK_SCANCODE_MASK | 99,
	KEY_F1: SDLK_SCANCODE_MASK | 58,
	KEY_F2: SDLK_SCANCODE_MASK | 59,
	KEY_F3: SDLK_SCANCODE_MASK | 60,
	KEY_F4: SDLK_SCANCODE_MASK | 61,
	KEY_F5: SDLK_SCANCODE_MASK | 62,
	KEY_F6: SDLK_SCANCODE_MASK | 63,
	KEY_F7: SDLK_SCANCODE_MASK | 64,
	KEY_F8: SDLK_SCANCODE_MASK | 65,
	KEY_F9: SDLK_SCANCODE_MASK | 66,
	KEY_F10: SDLK_SCANCODE_MASK | 67,
	KEY_F11: SDLK_SCANCODE_MASK | 68,
	KEY_F12: SDLK_SCANCODE_MASK | 69,
}

const MODIFIER_KEYS := [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META, KEY_CAPSLOCK, KEY_NUMLOCK]


static func modifiers(event: InputEventKey) -> int:
	var mod := 0
	if event.shift_pressed:
		mod |= MOD_SHIFT
	if event.ctrl_pressed:
		mod |= MOD_CTRL
	if event.alt_pressed:
		mod |= MOD_ALT
	if event.meta_pressed:
		mod |= MOD_GUI
	return mod


## Messages for one Godot key event: an SDL key event, plus a text event for printable keys,
## like SDL itself sends.
static func translate(event: InputEventKey) -> Array:
	var out := []
	# The game only acts on key presses (and Alt releases, which aren't forwarded).
	if not event.pressed or event.keycode in MODIFIER_KEYS:
		return out
	var mod := modifiers(event)
	var code := 0
	if SPECIAL.has(event.keycode):
		code = SPECIAL[event.keycode]
	elif event.keycode >= 32 and event.keycode < 127:
		code = String.chr(event.keycode).to_lower().unicode_at(0)
	if code != 0:
		out.append({"t": "key", "k": code, "m": mod, "r": event.echo, "down": event.pressed})
	var typing := event.unicode >= 32 and not event.ctrl_pressed and not event.meta_pressed
	var keypad_digit := event.keycode >= KEY_KP_0 and event.keycode <= KEY_KP_9
	if typing and (not SPECIAL.has(event.keycode) or keypad_digit):
		out.append({"t": "text", "s": String.chr(event.unicode)})
	return out
