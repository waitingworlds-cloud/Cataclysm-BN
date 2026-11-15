# Bright Nights Godot front end

A new interface for Cataclysm: Bright Nights, drawn by [Godot](https://godotengine.org). Godot owns
the window. It starts the game in the background, shows the map the game renders, and draws the HUD,
menus and prompts itself: the map sits in a bordered viewport inside a frame of opaque modules (a
top bar, a column on each side and a bottom deck), in dark teal with cyan lines and hazard-yellow
actions, set in Oxanium, Rajdhani and Share Tech Mono.

Every action still runs through the game's own code and keybindings. Godot never changes game state
directly; clicking a button presses the key bound to that action.

## Running

1. Build the tiles game as usual (see `docs/en/dev/guides/building/cmake.md`), for example:

   ```sh
   cmake --preset linux-slim
   cmake --build --preset linux-slim --target cataclysm-bn-tiles
   ```

2. Install Godot 4.7 or newer (the standard build, not .NET).

3. Start the front end from the repository root:

   ```sh
   godot --path godot
   ```

   It looks for the game next to the Godot executable, in the repository root, in `build/src/`,
   and in `out/build/<preset>/src/` (and its `Release`, `RelWithDebInfo` or `Debug` folder for a
   Visual Studio build). Options go after `--`:

   | Option             | Meaning                                                           |
   | ------------------ | ----------------------------------------------------------------- |
   | `--bn=PATH`        | Game executable to start (also `BN_EXECUTABLE`)                    |
   | `--bn-root=PATH`   | Folder holding `data/` (defaults to the nearest one above the game) |
   | `--userdir=PATH`   | Save, config and mod folder passed to the game                      |
   | `--world=NAME`     | World to open straight away                                         |
   | `--port=N`         | Listen on a fixed port instead of a free one                        |
   | `--attach`         | Don't start the game; wait for one started by hand (see below)      |

   To debug the game in a debugger, start Godot with `-- --attach --port=7777`, then run the game
   with `BN_GODOT_BRIDGE=127.0.0.1:7777`.

Set `BN_BRIDGE_DEBUG=1` to print every message the game sends (except the HUD) to Godot's output,
cut to 300 characters; `BN_BRIDGE_DEBUG=full` prints them whole.

## A standalone app

`export_presets.cfg` has Windows and Linux presets that build the front end into one executable.
With Godot's export templates installed:

```sh
godot --headless --path godot --export-release "Windows Desktop" BrightNights.exe
```

Put the app in the game's folder, next to `cataclysm-bn-tiles` and `data/`, and it finds the game
there. Icons and fonts use Godot's "Keep File" import so the app reads them as files in both a run
from this folder and an exported app; a new icon needs an `.import` file holding
`[remap]` and `importer="keep"`, like the others.

## Big screens

`src/display.gd` scales the interface with the screen: 1080p is 100%, 1440p 125%, 4K 200%. The
map has its own integer scale (1×, 2× on 1440p, 3× on 4K): the game renders at the window size
divided by it and Godot shows the frame enlarged with nearest filtering, so tiles stay sharp and
the game draws far fewer pixels. Sizes, insets and mouse positions sent to the game are in game
pixels (`Display.game_size`, `Display.to_game`).

Ctrl+= / Ctrl+- change the interface size, Ctrl+Shift+= / Ctrl+Shift+- the map size, Ctrl+0 goes
back to automatic. The monitor button in the bottom deck opens the same settings as a card. The
choice is saved in `user://display.cfg`.

## What is drawn by Godot

Almost everything outside the map. Each screen keeps every key it had, and shows everything the old
one did.

| Area                | Screens drawn by Godot                                                       |
| ------------------- | ---------------------------------------------------------------------------- |
| Playing             | HUD (top bar, side columns, bottom deck, map hover tip), message log, look around and descriptions, nearby items, monsters and vehicles, aiming, tombstone and last words |
| Items               | Inventory and every item list built on it, item actions, item info, comparison, pickup, advanced inventory, sort armor, vending machines, enchanting, the defense mode caravan |
| Making things       | Crafting, construction                                                       |
| Character           | Character sheet, morale, bionics, mutations, martial arts and technique details, blood test results, missions, factions, scores, diary |
| World               | Overmap legend, search and note editor, vehicle screen, computer terminals, conversations with NPCs, trade |
| Menus and prompts   | List menus (with search, categories and side panels), questions and notices, text prompts, multi-line text editor, long texts and help topics, error reports |
| Settings            | Options, keybindings, auto pickup, safe mode, auto notes, distractions, colors, zones |
| Developer tools     | Lua console, map editor (details docked beside the map, its menus as list menus) |
| Outside a game      | Title screen, world picker, world creation and mod lists, character creation with the character preview, defense mode setup, loading progress |
| Games               | The handheld and computer minigames: robot finds kitten, lights on, minesweeper, snake, sokoban |

No screen is left in the game's old style. A screen Godot doesn't know (one a mod or a later update
adds) is still shown as the game draws it, so nothing is ever unreachable.

Long menus (the map editor lists thousands of terrain types) build only the rows around what is in
view, with spacers that keep the scroll bar true to the whole list. A menu the game asks again on
every cursor blink stays open between those asks instead of closing and reopening.

## The HUD

The HUD replaces the game's sidebar and shows everything the sidebar shows, following the same rules
(health as bars unless the health style is numbers, a clock only with a watch, and so on). It is a
frame around the map: nothing floats over the map and the map never runs to the window's edge. The
game keeps its map view inside the viewport, so the survivor stays centered in what you can see.

- **Top bar**: who you are, what you wield and how you move, with the safe mode chip; season, day
  and time; the creature compass as a strip (marks under each direction something is seen in);
  weather, temperature, light, wind and moon; the place and coordinates.
- **Left column**: *Rig // Vitals* (a body figure and a bar per limb; click one for its health,
  injuries and outer armor; a striped alert with a use-item button for bleeding, bites and
  infections), *Needs // State* (thirst, hunger, rest, stamina, warmth and pain, then mood, focus,
  speed, move cost, noise, attributes, weight, volume, bionic power, mana and armor), *Vehicle* while you
  drive (speed, cruise control, heading, fuel) and the *Event log*.
- **Viewport**: the map in a bezel. Threats in view get red corner brackets, the nearest with a
  name tag, and the thing the *In reach* panel leads with gets yellow ones.
- **Right column**: the *Area map* (the pixel minimap redrawn as a gray paper map with a ring for
  you, a red cross per seen threat and a dot for anyone else, or the nearby overmap), *In sight*
  (every creature in view, nearest first, with distance, direction and health) and *In reach*
  (what is on your square and the eight around it: items with their sprites, doors, furniture,
  people, each with its actions as buttons). Lua sidebar widgets from mods go here too.
- **Bottom deck**: the wielded item and the nine hotbar slots on lit steel plates, the move mode,
  the action buttons with their keys, and zoom, display and HUD options.

The HUD options button (or `}`, the sidebar options key) opens the game's sidebar options: turning a
panel off there hides the matching part of the HUD.

Every key still goes to the game first: the HUD never takes keyboard focus, and its buttons press
the key bound to their action.

### Mouse

Everything on the main screen can be done with the mouse as well as the keys.

- **Rest the mouse on a map square** for a short tip: who or what is there, the ground, what lies
  on it, and what a right-click offers. The tip stays inside the viewport. The full description is
  in the look screens.
- **Right-click a square** (or click a row of *In sight*) for a menu, beside the mouse, of what
  can be done there right now: walk, attack, talk, fire, open, close, pick up, butcher, examine,
  jump over, look closer. `src/godot_square.cpp` decides the choices; the *In reach* buttons run
  the same choices without the menu.
- **Left-click a square** to walk there, as in the game.
- Parts of the frame act on a click: a limb (inspect), thirst and hunger (eat), rest (sleep), the
  wielded slot (wield), a hotbar slot (use; right-click clears, drag swaps), the move mode
  buttons, the safe mode chip, the event log (full log) and the area map (overmap).

Item sprites come from the game's tileset: Godot asks for the ids it needs (`sprites`), the game
draws them into a strip and sends it back, and `src/sprites.gd` caches them. Until a sprite
arrives, or when the tileset has none, a slot shows the item's map symbol.

## The frame around full screens

Every full screen sits in the same frame as the main screen (`src/ui/cockpit.gd`, class
`Cockpit`), so opening one never feels like leaving the game:

- **Top left**: who you are, with chips for injuries, needs and the nearest threat, and the clock.
- **Top bar**: tabs to the big screens (Inventory, Crafting, Construction, Character, Map, Log),
  each with its key, or the screen's name for pickers and prompts. Clicking a tab closes the
  screen and opens the other one as its key would.
- **Map strip**: the map in a bezel down the left, with you in the middle. It is the main screen's
  picture, moved (`main.gd` `_place_frame`), not a second map; a click on it goes back to the map.
  Under it a small module shows what you hold, or the screen's own summary (the inventory's load).
- **Body**: the screen's modules.
- **Bottom strip**: the screen's key hints.

A window narrower than 1360 units has no map strip, and outside a game (character creation, world
setup) there is no strip and no identity box. Screens that are a map of their own (the overmap, a
vehicle) use the frame's `wide` layout: the viewport takes most of the room and is live (clicks go
to the game), and the screen is one column at the right.
In the vehicle screen a click on a square of the
vehicle moves the cursor there and the mouse wheel zooms; its column lists the parts on that square
as rows (picture, kind, a condition bar and word, what it holds, what it does).

The title screen (`src/views/title_view.gd`) is built like the frame: the title art stands in the
viewport, the sections are a module at the left with the choices of the open one beside it, and
the tip of the day shares the strip along the bottom with the keys.

## The inventory

The inventory and every item list built on it (drop, pick up, wield, wear, use and the other "choose
an item" prompts) fill the frame (`src/views/inventory_view.gd`):

- One module per list the game shows, in the game's order so the arrow keys match: carried, nearby,
  worn and, while marking items to drop or pick up, the ones you chose. Carried and nearby items
  show as slots on steel plates grouped by category, or as rows (the `Slots / Rows` switch, or
  always when the list has its own columns such as damage or encumbrance).
- A search box (`/`), and weight and volume carried as bars under the map strip.
- *Selected item* on the right: its plate, weight and volume, full description and its actions.

Click an item to select it, and click it again (or double click, or right-click) to confirm. In
lists where you mark items, the same click marks one. Resting the mouse on a slot names the item
with its weight and volume. Choosing an item in the inventory opens its actions as a screen of its
own (`src/views/item_actions_view.gd`), where it can also be pinned to the hotbar. The keys work as
before: arrows, `Tab` to jump by category, number keys for amounts, and each action's own key.

## Screens

Most big screens are drawn by one data-driven view, `screen` (`src/views/screen_view.gd`). The game
describes the screen as JSON each time it redraws, using the helpers in `src/godot_screen.h`, and
Godot lays it out in the frame: tabs, a search box with toggles, one or more lists as modules, a
details module with buttons, and key hints on the frame's bottom strip. Text fields marked "spans" are arrays of `[text, curses color]`, so the
game's color tags carry over.

| Field                  | Meaning                                                                   |
| ---------------------- | ------------------------------------------------------------------------- |
| `title`, `icon`        | Header text and Lucide icon                                                |
| `nav`                  | For one of the big screens: the action that opens it (`craft`, `construct`, `player_data`, `messages`, `map`), which lights its tab in the top bar |
| `subtitle`             | Spans under the title                                                     |
| `stats`                | Header chips `{icon, label, value (spans), tip}`                          |
| `tabs`, `subtabs`      | `{text, active, pick, enabled, icon, count, tip}`; `tab_keys {prev, next}` labels the keys that switch tabs |
| `search`               | `{act, text, typing, placeholder, label, icon, key, tip}`                 |
| `toggles`              | Toolbar buttons that show a setting: `{act, text, icon, key, on, enabled, tip}` |
| `panes`, `active_pane` | Lists side by side (see below), and the one holding the cursor            |
| `aside`                | Details panel: `title` and `warn` (spans), `subtitle`, `icon` or `sym` and `sym_color`, `body` (spans), `mono`, `type` (the item whose sprite goes on the plate), `sections [{title, body, mono}]` or `[{title, tag, label, scroll_to, parts [{type, sym, sym_color, name, kind, state, level, health, note, selected, desc}]}]` (a vehicle's parts on one square, a row each with a condition bar) or `[{title, groups [{head, rows [{key, name, type, state, level, health, dim, selected, detail}]}]}]` (a vehicle's engines, tanks, batteries and seats: `head` and `detail` are rows of `[text, color]` runs, a row with a `key` is clicked to type that key), `heading` (the panel's name, in place of "Selected" or "Details"), `empty`, `buttons`, `width`, `share`, `preview {rect, buttons}` (the character sprite, cropped from the game's frame at `rect` = x, y, w, h pixels) |
| `buttons`              | `{act, text, icon, key, primary, enabled, tip, pick}`; with `pick` the button sends that pick with `act` |
| `hints`, `footer`      | Key hints `{key, text}` and a line of spans at the bottom                  |
| `quit`                 | Action of the close button (default `QUIT`; empty hides it)               |
| `size`                 | Largest size `[w, h]` in pixels                                           |
| `foot`                 | Under a wide frame's viewport: `title`, `stats [{label, value}]` (value is spans) and `gauges [{name, color, level, detail}]` (a bar each, `level` 0 to 1; a vehicle's stats and fuel) |
| `dock`                 | `right`: the screen takes the place of the main screen's right column, exactly, so the map stays clear and clickable (look around, nearby items, aiming); `side`: the screen is the column of a wide frame around a map of its own (the overmap, a vehicle) |
| `view`                 | With `dock: side`: where the game draws that map, `[x, y, w, h]` in game pixels. The game draws it across the whole window and the frame shows the middle of it in its viewport |

A pane holds `rows`, a `body` of spans, `entries` (a log) or a `grid` (a game board), with `title`, `icon`, `count`, `note`,
`empty`, `cursor`, `stretch`, `confirm` (action for clicking the selected row again, default
`CONFIRM`) and `mark_act` (action for a row's check box). A row has `text` and `cells` (spans),
`i`, `pick`, `heading`, `enabled`, `passive`, `note`, `icon`, `sym`, `type` (an item: its sprite
on a small plate in place of the glyph), `indent`, `tip`, `mark`, `key`, `confirm` and `mark_act`.
A column whose cells are all empty takes no room. A list about things you make also takes `slot {type, sym, color}`
(the result on a steel plate), `meta` (a second line), `parts [{type, sym, color, name, have}]`
(what it needs, as small slots framed green or red, each with a tooltip), `parts_more`, and
`status` with `tone` (`ready`, `missing` or `locked`: a colored bar at the row's left edge).

A `grid` is rows of `[text, color]` runs, one character per square, written from a window with
`write_window_grid`. It is drawn as large as fits up to `cell` pixels. `square` boards draw a tile
per square, with `lit`, `raised` and `hide` naming the characters drawn as lit tiles, raised tiles,
or with no glyph; on any board `fill` characters are solid blocks and `dot` ones round dots, and
`plain` ignores colored backgrounds. Clicking a square sends pick `pane * 100000 + row * 1000 +
column` with the pane's `click` action (`right_click` for the right button; an empty action only
wakes the game).

Clicking a row sends pick `pane * 100000 + i` (or the row's `pick`) with no key: the game moves its
cursor there. `i` is the row's position in the list unless given, and a heading takes a position
too, so lists with headings give each data row its `i`. Tabs use picks from `100 * 100000` up.

The game side follows the same pattern in each screen: create a `native_view` of kind `screen` in
the screen's input context, `publish` the JSON from the screen's redraw callback, and after
`handle_input` read `take_pick` to move the cursor or switch tab.

## How it works

The game runs with SDL's offscreen video driver and connects to Godot over a local TCP socket.

Game to Godot: `[u32 length, little endian][u8 kind][payload]`

- kind 1, frame: `[u32 width][u32 height][RGBA8 pixels]`, sent whenever the game presents a frame.
- kind 2, JSON with a `t` field:
  - `hello {protocol}`: first message.
  - `frame {main, views}`: whether the main game view (and so the HUD) is showing, and which native
    screens are visible. A native screen is hidden while an old-style screen covers it.
  - `hud {...}`: everything the HUD shows; sent when it changes while the main view is visible.
  - `view {id, kind, ...}`: state of a native screen. `kind` is `menu`, `popup`, `text_input`
    (one line, or the multi-line editor with `multiline`), `inventory`, `item_actions`, `screen`
    (see "Screens"), `title` (the title screen) or `loading`.
  - `entries {id, entries}`: a menu's rows, or an inventory's lists, sent only when they change.
  - `close {id}`: the screen is gone.
- kind 3, minimap: same layout as a frame; the game's pixel minimap, sent when it changes while
  the HUD shows the map.
- kind 4, sprites: `[u32 json length][JSON {ids, found, w, h}][u32 width][u32 height][RGBA8]`, a
  strip of `w` by `h` tiles, one per asked id, in answer to `sprites`.

Godot to game: `[u32 length][JSON]`

- `hello {w, h}`, `resize {w, h}`: window size in pixels.
- `insets {left, top, right, bottom}`: pixels the HUD's docked bars cover at each edge. The game
  lays its map view out in the rest of the window.
- `key {k, m, r, down}`: SDL keycode and modifiers. `text {s}`: typed text.
- `mouse {e: move|down|up|wheel, x, y, b, dy}`: mouse over the map.
- `action {id, cat}`: press the key bound to a game action, e.g. `inventory`.
- `square {dx, dy, choice, x, y}`: act on the map square at that offset from the avatar as if it
  had been right-clicked. With an empty `choice` its menu opens at `x, y`; otherwise that choice
  (`pick_up`, `examine`, ...) runs at once.
- `sprites {ids}`: ask for tileset sprites, e.g. `item:rock`.
- `pick {id, index, act}`: choose entry `index` in native screen `id`, then press `act`. An empty
  `act` only moves the cursor there. Inventory entries are `list * 100000 + row`.
- `press {id, act}`: press the key bound to `act` in native screen `id`'s input context.
- `quit`: the window was closed.

Game side: `src/godot_bridge.{h,cpp}` (connection, input, frames, native screens),
`src/godot_hud.h` with the builder at the end of `src/panels.cpp`, `src/godot_square.{h,cpp}`
(what can be done on a map square, the *In reach* list and the hover tip), `src/godot_screen.h` (helpers
for `screen` views), and a native branch in each screen's own file, found by searching for
`native_view`.

Godot side: `src/bridge.gd` (process and socket), `src/main.gd` (layers), `src/ui/hud.gd`,
`src/ui/item_slot.gd` (the steel item slot), `src/sprites.gd`, `src/views/*.gd`, and
`src/ui/slate.gd` (colors, fonts, icons and shared styles).

## Credits

- Fonts: Oxanium, Rajdhani and Share Tech Mono, SIL Open Font License (`fonts/`).
- Icons: [Lucide](https://lucide.dev), ISC License (`icons/LICENSE-lucide.txt`).
