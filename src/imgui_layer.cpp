#if defined(TILES)

#include "imgui_layer.h"

#include <algorithm>
#include <deque>

#include <SDL3/SDL.h>

#include "cata_imgui.h"
#include "imgui_impl_sdl3.h"
#include "imgui_impl_sdlrenderer3.h"
#include "options.h"
#include "slate_hud.h"
#include "slate_theme.h"

namespace cata::imgui_layer
{

namespace
{

struct layer_state {
    SDL_Renderer *renderer = nullptr;
    bool ready = false;
    bool hud_drawn_last_frame = false;
    int main_view_depth = 0;
    std::deque<input_event> queued;
};

auto state() -> layer_state & // *NOPAD*
{
    static auto storage = layer_state{};
    return storage;
}

auto is_mouse_event( const SDL_Event &ev ) -> bool
{
    switch( ev.type ) {
        case SDL_EVENT_MOUSE_MOTION:
        case SDL_EVENT_MOUSE_BUTTON_DOWN:
        case SDL_EVENT_MOUSE_BUTTON_UP:
        case SDL_EVENT_MOUSE_WHEEL:
            return true;
        default:
            return false;
    }
}

auto is_keyboard_event( const SDL_Event &ev ) -> bool
{
    switch( ev.type ) {
        case SDL_EVENT_KEY_DOWN:
        case SDL_EVENT_KEY_UP:
        case SDL_EVENT_TEXT_INPUT:
        case SDL_EVENT_TEXT_EDITING:
            return true;
        default:
            return false;
    }
}

auto hud_enabled() -> bool
{
    return is_main_view_active() && get_option<bool>( "SLATE_GUI" );
}

auto begin_frame( bool draw_hud ) -> void
{
    ImGui_ImplSDLRenderer3_NewFrame();
    ImGui_ImplSDL3_NewFrame();
    ImGui::NewFrame();
    if( draw_hud ) {
        slate::draw_hud();
    }
}

} // namespace

auto init( SDL_Window *window, SDL_Renderer *renderer ) -> void
{
    auto &s = state();
    if( s.ready ) {
        return;
    }
    IMGUI_CHECKVERSION();
    ImGui::CreateContext();
    auto &io = ImGui::GetIO();
    // Layout is driven by code for now; don't write imgui.ini next to the binary.
    io.IniFilename = nullptr;
    io.LogFilename = nullptr;
    slate::apply_theme();
    slate::load_fonts();
    ImGui_ImplSDL3_InitForSDLRenderer( window, renderer );
    ImGui_ImplSDLRenderer3_Init( renderer );
    s.renderer = renderer;
    s.ready = true;
}

auto shutdown() -> void
{
    auto &s = state();
    if( !s.ready ) {
        return;
    }
    ImGui_ImplSDLRenderer3_Shutdown();
    ImGui_ImplSDL3_Shutdown();
    ImGui::DestroyContext();
    s = layer_state{};
}

auto is_ready() -> bool
{
    return state().ready;
}

auto process_event( const SDL_Event &ev ) -> bool
{
    if( !state().ready ) {
        return false;
    }
    ImGui_ImplSDL3_ProcessEvent( &ev );
    const auto &io = ImGui::GetIO();
    if( is_mouse_event( ev ) ) {
        return io.WantCaptureMouse;
    }
    if( is_keyboard_event( ev ) ) {
        return io.WantCaptureKeyboard;
    }
    return false;
}

auto render() -> void
{
    auto &s = state();
    if( !s.ready ) {
        return;
    }
    const auto draw_hud = hud_enabled();
    // ImGui keeps auto-sized windows hidden on the frame they first appear, while it measures them.
    // The game only redraws on input, so run a throwaway frame first or the HUD would show up late.
    if( draw_hud && !s.hud_drawn_last_frame ) {
        begin_frame( true );
        ImGui::EndFrame();
    }
    begin_frame( draw_hud );
    ImGui::Render();
    ImGui_ImplSDLRenderer3_RenderDrawData( ImGui::GetDrawData(), s.renderer );
    s.hud_drawn_last_frame = draw_hud;
}

auto wants_mouse() -> bool
{
    return state().ready && ImGui::GetIO().WantCaptureMouse;
}

auto queue_action( const std::string &action_id, const std::string &category ) -> void
{
    const auto &events = inp_mngr.get_input_for_action( action_id, category );
    const auto key = std::ranges::find_if( events, []( const input_event & ev ) { return ev.type == input_event_t::keyboard; } );
    if( key != events.end() ) {
        state().queued.push_back( *key );
    }
}

auto pop_queued_input() -> std::optional<input_event>
{
    auto &queued = state().queued;
    if( queued.empty() ) {
        return std::nullopt;
    }
    auto next = queued.front();
    queued.pop_front();
    return next;
}

main_view_scope::main_view_scope()
{
    ++state().main_view_depth;
}

main_view_scope::~main_view_scope()
{
    --state().main_view_depth;
}

auto is_main_view_active() -> bool
{
    return state().main_view_depth > 0;
}

} // namespace cata::imgui_layer

#endif // TILES
