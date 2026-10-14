#pragma once

#if defined(TILES)

#include <optional>
#include <string>

#include "input.h"

union SDL_Event;
struct SDL_Renderer;
struct SDL_Window;

/// Dear ImGui layer drawn on top of the curses-emulated tiles display.
///
/// The layer owns the ImGui context and its SDL3 backends. It is rendered at native window
/// resolution after the curses frame buffer is composited, so its text stays crisp at any
/// scaling factor. Widgets never call game code directly: clicks are queued as keybinding
/// actions and replayed through the normal input loop, so user keybindings still apply.
namespace cata::imgui_layer
{

/// Creates the ImGui context, loads the Slate fonts and attaches the SDL3 backends.
auto init( SDL_Window *window, SDL_Renderer *renderer ) -> void;
auto shutdown() -> void;
auto is_ready() -> bool;

/// Feeds an SDL event to ImGui.
/// Returns true when ImGui owns the event (e.g. the mouse is over a panel) and the game must ignore it.
auto process_event( const SDL_Event &ev ) -> bool;

/// Builds and draws one ImGui frame onto the renderer's current target.
auto render() -> void;

/// True while the mouse is over an ImGui window or a widget is being dragged.
auto wants_mouse() -> bool;

/// Queues a keybinding action clicked in the GUI. It is replayed as the key bound to it.
auto queue_action( const std::string &action_id, const std::string &category ) -> void;

/// Returns the next queued GUI input, if any. Called by the SDL input loop.
auto pop_queued_input() -> std::optional<input_event>;

/// Marks the main map view (the default-mode input loop) as active for its lifetime.
/// The in-game HUD is only drawn while one of these is alive.
class main_view_scope
{
    public:
        main_view_scope();
        ~main_view_scope();
        main_view_scope( const main_view_scope & ) = delete;
        auto operator=( const main_view_scope & ) -> main_view_scope & = delete; // *NOPAD*
};

auto is_main_view_active() -> bool;

} // namespace cata::imgui_layer

#endif // TILES
