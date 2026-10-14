# Bright Nights Godot front end

A new interface for Cataclysm: Bright Nights, drawn by [Godot](https://godotengine.org). Godot owns
the window. It starts the game in the background, shows the map the game renders, and draws the HUD,
menus and prompts itself in the Slate style: a map framed by a header, a sidebar and an action bar,
rounded cards, Manrope and JetBrains Mono, amber accent.

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

   It looks for the game next to the Godot executable, in the repository root, and in
   `out/build/<preset>/src/`. Options go after `--`:

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

## What is drawn by Godot

| Screen                                  | Status                                |
| --------------------------------------- | ------------------------------------- |
| HUD: survivor card, time and place, map and threats, message log, action dock | Godot |
| List menus (`uilist`): search, categories, descriptions | Godot                    |
| Questions and notices (`query_popup`, `popup`, `query_yn`) | Godot                  |
| Text prompts (`string_input_popup`)     | Godot                                 |
| Inventory and every item list built on it (drop, pick up, wield, wear, use, ...) | Godot |
| Item actions (the menu after choosing an item in the inventory) | Godot              |
| Menus that draw extra panels beside their list | Game (old style), for now      |
| Advanced inventory, crafting, character sheet, main menu and other full screens | Game (old style), being rebuilt one by one |

When the game shows one of its old-style screens, Godot shows it as the game drew it, so nothing is
ever unreachable.

## The HUD

The HUD replaces the game's sidebar and shows everything the sidebar shows, following the same rules
(health as bars unless the health style is numbers, a clock only with a watch, and so on). Three
bars are docked to the window edges and the game keeps its map view in the space between them, so
the survivor stays centered in what you can see:

- **Header**, along the top: season, day and time, weather, temperature, light, wind and moon, and
  on the right the place and coordinates. While driving it also shows the vehicle's speed, cruise
  control, heading and fuel.
- **Sidebar**, on the right: the pixel minimap or the nearby overmap, every creature in view with
  its threat level and direction (the sidebar compass), Lua sidebar widgets from mods, and the
  message log.
- **Action bar**, along the bottom: the action dock in the middle, and zoom and HUD options on the
  right.
- **Survivor card**, floating at the top left of the map: a body figure colored by each limb's
  health, with bleeding, bites, infections and breaks outlined. Click a limb, or open the body tab,
  to see its health, injuries and outer armor. Tabs switch between needs (thirst, hunger, rest,
  stamina, warmth), body, and stats (attributes, weight, volume, bionic power, mana, armor). Mood,
  focus, speed, move cost and noise are always shown, with chips for injuries, pain, move mode and
  safe mode.

The HUD options button (or `}`, the sidebar options key) opens the game's sidebar options: turning a
panel off there hides the matching part of the HUD.

Every key still goes to the game first: the HUD never takes keyboard focus, and its buttons press
the key bound to their action.

## The inventory

The inventory and every item list built on it (drop, pick up, wield, wear, use and the other "choose
an item" prompts) show as one large card:

- Weight and volume carried as bars against your limits, and a search box (`/`).
- One pane per list the game shows: carried, nearby, worn and, while marking items to drop or pick
  up, the ones you chose. Items are grouped by category, with their key, symbol, name and weight, or
  the list's own columns (damage, encumbrance, ...) where it has them.
- The selected item's full description on the right, with buttons for its actions.

Click an item to select it, and click it again (or double click) to confirm. In lists where you mark
items, the box on the left marks one. Choosing an item in the inventory opens its actions as a card
beside its description. The keys work as before: arrows, `Tab` to jump by category, number keys for
amounts, and each action's own key.

## How it works

The game runs with SDL's offscreen video driver and connects to Godot over a local TCP socket.

Game to Godot: `[u32 length, little endian][u8 kind][payload]`

- kind 1, frame: `[u32 width][u32 height][RGBA8 pixels]`, sent whenever the game presents a frame.
- kind 2, JSON with a `t` field:
  - `hello {protocol}`: first message.
  - `frame {main, views}`: whether the main game view (and so the HUD) is showing, and which native
    screens are visible. A native screen is hidden while an old-style screen covers it.
  - `hud {...}`: everything the HUD shows; sent when it changes while the main view is visible.
  - `view {id, kind, ...}`: state of a native screen. `kind` is `menu`, `popup`, `text_input`,
    `inventory` or `item_actions`.
  - `entries {id, entries}`: a menu's rows, or an inventory's lists, sent only when they change.
  - `close {id}`: the screen is gone.
- kind 3, minimap: same layout as a frame; the game's pixel minimap, sent when it changes while
  the HUD shows the map.

Godot to game: `[u32 length][JSON]`

- `hello {w, h}`, `resize {w, h}`: window size in pixels.
- `insets {left, top, right, bottom}`: pixels the HUD's docked bars cover at each edge. The game
  lays its map view out in the rest of the window.
- `key {k, m, r, down}`: SDL keycode and modifiers. `text {s}`: typed text.
- `mouse {e: move|down|up|wheel, x, y, b, dy}`: mouse over the map.
- `action {id, cat}`: press the key bound to a game action, e.g. `inventory`.
- `pick {id, index, act}`: choose entry `index` in native screen `id`, then press `act`. An empty
  `act` only moves the cursor there. Inventory entries are `list * 100000 + row`.
- `press {id, act}`: press the key bound to `act` in native screen `id`'s input context.
- `quit`: the window was closed.

Game side: `src/godot_bridge.{h,cpp}` (connection, input, frames, native screens),
`src/godot_hud.h` with the builder at the end of `src/panels.cpp`, and the native branches in
`src/ui.cpp`, `src/popup.cpp`, `src/string_input_popup.cpp`, `src/inventory_ui.cpp` and
`src/examine_item_menu.cpp`.

Godot side: `src/bridge.gd` (process and socket), `src/main.gd` (layers), `src/ui/hud.gd`,
`src/views/*.gd`, and `src/ui/slate.gd` (colors, fonts, icons and shared styles).

## Credits

- Fonts: Manrope and JetBrains Mono, SIL Open Font License (`fonts/`).
- Icons: [Lucide](https://lucide.dev), ISC License (`icons/LICENSE-lucide.txt`).
