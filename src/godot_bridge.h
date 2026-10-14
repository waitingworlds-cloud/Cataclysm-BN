#pragma once

#if defined(TILES)

#include <functional>
#include <optional>
#include <string>

#include "cursesdef.h"
#include "point.h"

class JsonOut;
class nc_color;
class ui_adaptor;
struct input_event;
struct SDL_Renderer;
struct SDL_Texture;
union SDL_Event;

/// Link to the Godot front end (see `godot/README.md`).
///
/// The Godot app starts the game with `BN_GODOT_BRIDGE=host:port` set. The game then renders off
/// screen, streams each finished frame to Godot, takes keyboard and mouse input from it, and hands
/// screens that Godot can draw natively (menus, prompts, the HUD) over as JSON instead of drawing
/// them with curses.
namespace cata::godot_bridge
{

/// Connects to the Godot app named by `BN_GODOT_BRIDGE` and waits for its window size.
/// Call before SDL starts; returns false when the game was not started by Godot.
auto connect() -> bool;

/// Starts receiving input from Godot. Call once SDL is initialized.
auto start() -> void;

/// True when the game is running inside the Godot front end.
auto is_active() -> bool;

/// Pixel size of the Godot window, as last reported.
auto window_size() -> point;

/// Edges of the window the HUD's docked bars cover, in terminal cells.
struct screen_insets {
    int left = 0;
    int top = 0;
    int right = 0;
    int bottom = 0;
};
/// Space the HUD covers; the game keeps its map view inside the rest of the window.
auto map_insets() -> screen_insets;
/// True once after Godot reported new insets, telling the frame code to lay the screens out again.
auto take_layout_change() -> bool;

/// What `translate_event` did with an event taken from the SDL queue.
enum class event_result {
    /// Not a bridge event; handle it as usual.
    passthrough,
    /// Rewritten in place into the regular SDL event it stands for; handle it as usual.
    rewritten,
    /// Became a game input; read it with `take_input`.
    input,
    /// Fully handled; nothing left to do.
    consumed,
};

auto translate_event( SDL_Event &ev ) -> event_result;
auto take_input() -> input_event;

/// Mouse position in game pixels, as last reported by Godot.
auto mouse_position() -> point;

/// Sends the finished frame held in the render target `frame` to Godot.
auto send_frame( SDL_Renderer *renderer, SDL_Texture *frame ) -> void;
/// Tells Godot which native screens are showing and whether the HUD is, if that changed. Native
/// screens draw nothing in curses, so opening one doesn't produce a frame on its own.
auto sync_screens() -> void;

/// Asks for the pixel minimap to be rendered for Godot with the next frame; the HUD builder calls
/// this while the HUD shows the map.
auto request_minimap() -> void;
/// True once per `request_minimap`, telling the frame code to render the minimap.
auto take_minimap_request() -> bool;
/// Sends the minimap held in the render target `image` to Godot, unless it is unchanged.
auto send_minimap( SDL_Renderer *renderer, SDL_Texture *image ) -> void;

auto shutdown() -> void;

/// Called while the main game view redraws, so Godot knows when to show its HUD.
auto note_main_view( const ui_adaptor &ui ) -> void;

/// Replaces the HUD state Godot shows over the main view.
auto set_hud( std::string json ) -> void;

/// True when screens should be handed to Godot instead of drawn with curses.
auto native_screens() -> bool;

/// A screen Godot draws natively in place of the curses window that would normally show it.
/// Godot removes the screen when this is destroyed.
class native_view
{
    public:
        /// `owner` identifies the game object behind the screen (for `take_pick`), and
        /// `input_category` is the input context its keys are looked up in.
        native_view( std::string kind, const void *owner, std::string input_category );
        ~native_view();
        native_view( const native_view & ) = delete;
        auto operator=( const native_view & ) -> native_view & = delete; // *NOPAD*

        /// Ties the view to the `ui_adaptor` that keeps the screen on the UI stack, so Godot hides it
        /// while a curses screen is open above it.
        auto attach( const ui_adaptor &ui ) -> void;
        /// Sends the screen's current state; `write_body` adds the members specific to its kind.
        auto publish( const std::function<void( JsonOut & )> &write_body ) -> void;
        /// Builds a message of type `type` about this view without sending it.
        auto compose( const std::string &type,
                      const std::function<void( JsonOut & )> &write_body ) const -> std::string;
        /// Sends a message built with `compose`.
        auto send( const std::string &message ) const -> void;

        auto get_id() const -> int { return id; }
        auto get_owner() const -> const void * { return owner; } // *NOPAD*
        auto get_adaptor() const -> const ui_adaptor * { return adaptor; } // *NOPAD*
        auto get_input_category() const -> const std::string & { return input_category; } // *NOPAD*

    private:
        int id;
        std::string kind;
        const void *owner;
        std::string input_category;
        const ui_adaptor *adaptor = nullptr;
};

/// Entry the player clicked in the native view of `owner`, if any. Clears it.
auto take_pick( const void *owner ) -> std::optional<int>;

/// While one of these is alive, text fields embedded in a native screen skip curses drawing.
class curses_draw_suppression
{
    public:
        curses_draw_suppression();
        ~curses_draw_suppression();
        curses_draw_suppression( const curses_draw_suppression & ) = delete;
        auto operator=( const curses_draw_suppression & ) -> curses_draw_suppression & = delete; // *NOPAD*
};
auto curses_draw_suppressed() -> bool;

/// Writes `text` as an array of `[text, color]` runs, resolving its color tags. Text outside any
/// tag uses `base`. Colors are curses color names such as `c_light_red`.
auto write_spans( JsonOut &jsout, const std::string &text, const nc_color &base ) -> void;

/// A curses window outside the visible screen, for running existing drawing code whose text
/// is then sent to Godot with `write_window_spans`.
auto capture_window( int lines, int cols ) -> catacurses::window;

/// Columns of a window to send: `[left, left + width)`; a negative width means to the right edge.
struct window_columns {
    int left = 0;
    int width = -1;
    /// Leaves out the first column when it only holds a drawn divider line.
    bool skip_divider = false;
};

/// Writes the text drawn in `w` as an array of `[text, color]` runs, one line per row, without
/// trailing blanks or empty lines at the end.
auto write_window_spans( JsonOut &jsout, const catacurses::window &w,
const window_columns &columns = {} ) -> void;

/// Part of a window: `size` cells from `at`; a zero size runs to the window's edge.
struct window_area {
    point at = point_zero;
    point size = point_zero;
};

/// Writes the cells of `w` in `area` as rows of `[text, color]` runs, every cell in its place
/// (blanks too), for boards Godot draws as a grid of squares (the minigames).
auto write_window_grid( JsonOut &jsout, const catacurses::window &w,
const window_area &area = {} ) -> void;

/// Copies the cells of `from` into `to` with its top left corner at `at`, for drawing code that
/// makes its own window beside a captured one.
auto copy_window( const catacurses::window &from, const catacurses::window &to, point at ) -> void;

/// Label of the key bound to `action` in `category`, or empty when unbound.
auto key_label( const std::string &action, const std::string &category ) -> std::string;

} // namespace cata::godot_bridge

#endif // TILES
