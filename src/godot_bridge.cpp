#if defined(TILES)

#include "godot_bridge.h"

#include <SDL3/SDL.h>

#include <algorithm>
#include <array>
#include <atomic>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <memory>
#include <mutex>
#include <ranges>
#include <sstream>
#include <stack>
#include <string>
#include <thread>
#include <utility>
#include <vector>

#include "color.h"
#include "cursesport.h"
#include "debug.h"
#include "godot_bridge_socket.h"
#include "godot_commands.h"
#include "input.h"
#include "json.h"
#include "output.h"
#include "string_formatter.h"
#include "ui_manager.h"

// Cell size of the game's main font (sdltiles.cpp).
extern int fontwidth;
extern int fontheight;

namespace cata::godot_bridge
{

namespace
{

/// Message kinds sent to Godot. Every message is `[u32 length][u8 kind][payload]`, little endian,
/// where `length` counts the kind byte and the payload.
enum class message_kind : std::uint8_t {
    /// `[u32 width][u32 height][width * height RGBA8 pixels]`
    frame = 1,
    /// UTF-8 JSON object with a `t` member naming its type.
    json = 2,
    /// The pixel minimap the HUD shows, laid out like `frame`.
    minimap = 3,
};

struct pending_pick {
    const void *owner = nullptr;
    int index = 0;
};

struct bridge_state {
    std::unique_ptr<net::connection> link;
    std::atomic<bool> running = false;
    std::uint32_t event_type = 0;

    std::mutex inbox_mutex;
    std::deque<std::string> inbox;

    std::mutex send_mutex;

    point size = point( 1280, 800 );
    /// Docked HUD bars, in pixels: left, top, right, bottom.
    std::array<int, 4> insets = {};
    bool layout_changed = false;
    point mouse = point_zero;
    std::string text_buffer;
    input_event pending_input;

    int next_view_id = 1;
    std::vector<native_view *> views;
    std::optional<pending_pick> pick;
    int suppression_depth = 0;

    const ui_adaptor *main_view = nullptr;
    std::string hud;
    std::string sent_hud;
    std::string sent_meta;
    std::vector<std::uint8_t> frame_bytes;
    bool minimap_requested = false;
    std::vector<std::uint8_t> minimap_bytes;
    std::vector<std::uint8_t> sent_minimap;
};

auto state() -> bridge_state & // *NOPAD*
{
    static auto storage = bridge_state{};
    return storage;
}

auto put_u32( std::uint8_t *out, std::uint32_t value ) -> void
{
    out[0] = static_cast<std::uint8_t>( value & 0xff );
    out[1] = static_cast<std::uint8_t>( ( value >> 8 ) & 0xff );
    out[2] = static_cast<std::uint8_t>( ( value >> 16 ) & 0xff );
    out[3] = static_cast<std::uint8_t>( ( value >> 24 ) & 0xff );
}

auto get_u32( const std::uint8_t *in ) -> std::uint32_t
{
    return static_cast<std::uint32_t>( in[0] ) | ( static_cast<std::uint32_t>( in[1] ) << 8 ) |
           ( static_cast<std::uint32_t>( in[2] ) << 16 ) | ( static_cast<std::uint32_t>( in[3] ) << 24 );
}

auto send_message( message_kind kind, const void *head, std::size_t head_size, const void *body,
                   std::size_t body_size ) -> void
{
    auto &s = state();
    if( !s.link ) {
        return;
    }
    auto header = std::array<std::uint8_t, 5> {};
    put_u32( header.data(), static_cast<std::uint32_t>( 1 + head_size + body_size ) );
    header[4] = static_cast<std::uint8_t>( kind );
    const auto lock = std::lock_guard<std::mutex>( s.send_mutex );
    const auto ok = s.link->send_all( header.data(), header.size() ) &&
                    ( head_size == 0 || s.link->send_all( head, head_size ) ) &&
                    ( body_size == 0 || s.link->send_all( body, body_size ) );
    if( !ok ) {
        DebugLog( DL::Warn, DC::Main ) << "Godot bridge: connection lost while sending";
    }
}

auto send_json( const std::string &json ) -> void
{
    send_message( message_kind::json, nullptr, 0, json.data(), json.size() );
}

/// Reads one length-prefixed JSON message sent by Godot.
auto read_message( net::connection &link ) -> std::optional<std::string>
{
    auto header = std::array<std::uint8_t, 4> {};
    if( !link.recv_all( header.data(), header.size() ) ) {
        return std::nullopt;
    }
    const auto size = get_u32( header.data() );
    auto body = std::string( size, '\0' );
    if( size > 0 && !link.recv_all( body.data(), size ) ) {
        return std::nullopt;
    }
    return body;
}

auto reader_loop() -> void
{
    auto &s = state();
    while( s.running ) {
        auto message = read_message( *s.link );
        if( !message ) {
            break;
        }
        {
            const auto lock = std::lock_guard<std::mutex>( s.inbox_mutex );
            s.inbox.push_back( std::move( *message ) );
        }
        auto ev = SDL_Event{};
        ev.type = s.event_type;
        SDL_PushEvent( &ev );
    }
    if( s.running ) {
        // Godot went away (window closed or crashed); quit like a closed game window would.
        auto ev = SDL_Event{};
        ev.type = SDL_EVENT_QUIT;
        SDL_PushEvent( &ev );
    }
}

auto pop_inbox() -> std::optional<std::string>
{
    auto &s = state();
    const auto lock = std::lock_guard<std::mutex>( s.inbox_mutex );
    if( s.inbox.empty() ) {
        return std::nullopt;
    }
    auto message = std::move( s.inbox.front() );
    s.inbox.pop_front();
    return message;
}

/// First keyboard input bound to `action` in `category`.
auto key_for_action( const std::string &action, const std::string &category ) ->
std::optional<input_event>
{
    const auto &events = inp_mngr.get_input_for_action( action, category );
    const auto key = std::ranges::find_if( events, []( const input_event & ev ) { return ev.type == input_event_t::keyboard; } );
    if( key == events.end() ) {
        return std::nullopt;
    }
    return *key;
}

auto find_view( int id ) -> native_view *
{
    const auto &views = state().views;
    const auto found = std::ranges::find_if( views, [id]( const native_view * v ) { return v->get_id() == id; } );
    return found == views.end() ? nullptr : *found;
}

auto set_mouse( const JsonObject &obj ) -> void
{
    state().mouse = point( obj.get_int( "x", 0 ), obj.get_int( "y", 0 ) );
}

/// Turns a key press Godot reported (as SDL keycode and modifiers) into an SDL key event.
auto rewrite_key( SDL_Event &ev, const JsonObject &obj ) -> void
{
    const auto down = obj.get_bool( "down", true );
    ev = SDL_Event{};
    ev.type = down ? SDL_EVENT_KEY_DOWN : SDL_EVENT_KEY_UP;
    ev.key.key = static_cast<SDL_Keycode>( obj.get_int( "k" ) );
    ev.key.mod = static_cast<SDL_Keymod>( obj.get_int( "m", 0 ) );
    ev.key.repeat = obj.get_bool( "r", false );
    ev.key.down = down;
}

auto rewrite_mouse( SDL_Event &ev, const JsonObject &obj ) -> void
{
    set_mouse( obj );
    const auto kind = obj.get_string( "e" );
    const auto x = static_cast<float>( state().mouse.x );
    const auto y = static_cast<float>( state().mouse.y );
    ev = SDL_Event{};
    if( kind == "wheel" ) {
        ev.type = SDL_EVENT_MOUSE_WHEEL;
        ev.wheel.y = static_cast<float>( obj.get_int( "dy", 0 ) );
        ev.wheel.mouse_x = x;
        ev.wheel.mouse_y = y;
    } else if( kind == "down" || kind == "up" ) {
        ev.type = kind == "down" ? SDL_EVENT_MOUSE_BUTTON_DOWN : SDL_EVENT_MOUSE_BUTTON_UP;
        ev.button.button = static_cast<std::uint8_t>( obj.get_int( "b", SDL_BUTTON_LEFT ) );
        ev.button.down = kind == "down";
        ev.button.x = x;
        ev.button.y = y;
    } else {
        ev.type = SDL_EVENT_MOUSE_MOTION;
        ev.motion.x = x;
        ev.motion.y = y;
    }
}

/// Queues the key bound to `action` as the next game input. An empty `action` queues an input that
/// does nothing but let the screen apply a pick and redraw (it reads as `TIMEOUT`).
auto press_action( const std::string &action, const std::string &category ) -> event_result
{
    if( action.empty() ) {
        auto nudge = input_event();
        nudge.type = input_event_t::timeout;
        state().pending_input = nudge;
        return event_result::input;
    }
    const auto key = key_for_action( action, category );
    if( !key ) {
        return event_result::consumed;
    }
    state().pending_input = *key;
    return event_result::input;
}

auto parse_size( const JsonObject &obj ) -> point
{
    return point( std::max( obj.get_int( "w", 0 ), 320 ), std::max( obj.get_int( "h", 0 ), 240 ) );
}

auto collect_visible_views() -> std::vector<int>
{
    return state().views
    | std::views::filter( []( const native_view * v ) { return v->get_adaptor() != nullptr && ui_adaptor::position_on_stack( v->get_adaptor() ) == ui_adaptor::stack_position::visible; } )
    | std::views::transform( &native_view::get_id )
    | std::ranges::to<std::vector>();
}

auto main_view_visible() -> bool
{
    auto &s = state();
    if( s.main_view == nullptr ) {
        return false;
    }
    const auto position = ui_adaptor::position_on_stack( s.main_view );
    if( position == ui_adaptor::stack_position::absent ) {
        s.main_view = nullptr;
        return false;
    }
    return position == ui_adaptor::stack_position::visible;
}

/// Reads the render target `texture` into `out` as `[u32 width][u32 height][RGBA8 pixels]`.
auto read_image( SDL_Renderer *renderer, SDL_Texture *texture,
                 std::vector<std::uint8_t> &out ) -> bool
{
    SDL_SetRenderTarget( renderer, texture );
    auto *const read = SDL_RenderReadPixels( renderer, nullptr );
    if( read == nullptr ) {
        return false;
    }
    auto *const rgba = SDL_ConvertSurface( read, SDL_PIXELFORMAT_ABGR8888 );
    SDL_DestroySurface( read );
    if( rgba == nullptr ) {
        return false;
    }
    const auto width = static_cast<std::uint32_t>( rgba->w );
    const auto height = static_cast<std::uint32_t>( rgba->h );
    const auto row_bytes = static_cast<std::size_t>( width ) * 4;
    out.resize( 8 + row_bytes * height );
    put_u32( out.data(), width );
    put_u32( out.data() + 4, height );
    const auto *pixels = static_cast<const std::uint8_t *>( rgba->pixels );
    for( auto y = std::size_t{ 0 }; y < height; ++y ) {
        std::memcpy( out.data() + 8 + y * row_bytes, pixels + y * rgba->pitch, row_bytes );
    }
    SDL_DestroySurface( rgba );
    return true;
}

} // namespace

auto connect() -> bool
{
    const auto *target = std::getenv( "BN_GODOT_BRIDGE" );
    if( target == nullptr || *target == '\0' ) {
        return false;
    }
    const auto spec = std::string( target );
    const auto colon = spec.rfind( ':' );
    const auto host = colon == std::string::npos ? std::string( "127.0.0.1" ) : spec.substr( 0, colon );
    const auto port = std::atoi( colon == std::string::npos ? spec.c_str() : spec.c_str() + colon + 1 );
    auto &s = state();
    s.link = net::connection::open( host, port );
    if( !s.link ) {
        DebugLog( DL::Error, DC::Main ) << "Godot bridge: could not connect to " << spec;
        return false;
    }
    send_json( R"({"t":"hello","protocol":1})" );
    // Godot answers with its window size, which the game window must match.
    while( true ) {
        const auto message = read_message( *s.link );
        if( !message ) {
            s.link.reset();
            return false;
        }
        auto stream = std::istringstream( *message );
        auto jsin = JsonIn( stream );
        auto obj = jsin.get_object();
        obj.allow_omitted_members();
        if( obj.get_string( "t" ) == "hello" ) {
            s.size = parse_size( obj );
            break;
        }
    }
    DebugLog( DL::Info, DC::Main ) << "Godot bridge: connected to " << spec << ", window " << s.size.x
                                   << "x" << s.size.y;
    return true;
}

auto start() -> void
{
    auto &s = state();
    if( !s.link || s.running ) {
        return;
    }
    s.event_type = SDL_RegisterEvents( 1 );
    s.running = true;
    // The reader only ever blocks on the socket; let it end with the process.
    std::thread( reader_loop ).detach();
}

auto is_active() -> bool
{
    return state().link != nullptr;
}

auto window_size() -> point
{
    return state().size;
}

auto map_insets() -> screen_insets
{
    const auto &s = state();
    const auto &px = s.insets;
    const auto scale = std::max( get_scaling_factor(), 1 );
    const auto cell_w = std::max( fontwidth * scale, 1 );
    const auto cell_h = std::max( fontheight * scale, 1 );
    // The map reaches just under each bar, so no strip of empty frame shows between them.
    const auto before = []( int pixels, int cell ) { return std::max( pixels, 0 ) / cell; };
    const auto after = []( int pixels, int window, int cell, int cells ) {
        const auto end = ( std::max( window - std::max( pixels, 0 ), 0 ) + cell - 1 ) / cell;
        return std::max( cells - end, 0 );
    };
    return screen_insets{
        .left = before( px[0], cell_w ),
        .top = before( px[1], cell_h ),
        .right = after( px[2], s.size.x, cell_w, TERMX ),
        .bottom = after( px[3], s.size.y, cell_h, TERMY ),
    };
}

auto take_layout_change() -> bool
{
    return std::exchange( state().layout_changed, false );
}

auto translate_event( SDL_Event &ev ) -> event_result
{
    auto &s = state();
    if( !s.running || ev.type != s.event_type ) {
        return event_result::passthrough;
    }
    const auto message = pop_inbox();
    if( !message ) {
        return event_result::consumed;
    }
    try {
        auto stream = std::istringstream( *message );
        auto jsin = JsonIn( stream );
        auto obj = jsin.get_object();
        obj.allow_omitted_members();
        const auto type = obj.get_string( "t" );
        if( type == "key" ) {
            rewrite_key( ev, obj );
            return event_result::rewritten;
        }
        if( type == "text" ) {
            // SDL text events point at their text; keep it alive until the next bridge event.
            s.text_buffer = obj.get_string( "s" );
            ev = SDL_Event{};
            ev.type = SDL_EVENT_TEXT_INPUT;
            ev.text.text = s.text_buffer.c_str();
            return event_result::rewritten;
        }
        if( type == "mouse" ) {
            rewrite_mouse( ev, obj );
            return event_result::rewritten;
        }
        if( type == "resize" ) {
            s.size = parse_size( obj );
            ev = SDL_Event{};
            ev.type = SDL_EVENT_WINDOW_RESIZED;
            ev.window.data1 = s.size.x;
            ev.window.data2 = s.size.y;
            return event_result::rewritten;
        }
        if( type == "insets" ) {
            const auto insets = std::array {
                obj.get_int( "left", 0 ), obj.get_int( "top", 0 ), obj.get_int( "right", 0 ), obj.get_int( "bottom", 0 ),
            };
            if( insets != s.insets ) {
                s.insets = insets;
                s.layout_changed = true;
            }
            return event_result::consumed;
        }
        if( type == "action" ) {
            return press_action( obj.get_string( "id" ), obj.get_string( "cat", "DEFAULTMODE" ) );
        }
        if( type == "commands" ) {
            auto out = std::ostringstream();
            auto jsout = JsonOut( out );
            jsout.start_object();
            jsout.member( "t", "commands" );
            cata::godot_commands::write( jsout );
            jsout.end_object();
            send_json( out.str() );
            return event_result::consumed;
        }
        if( type == "run" ) {
            // Actions without a key go through the action menu, which picks the requested one.
            const auto id = obj.get_string( "id" );
            if( key_for_action( id, "DEFAULTMODE" ) ) {
                return press_action( id, "DEFAULTMODE" );
            }
            cata::godot_commands::request( id );
            return press_action( "action_menu", "DEFAULTMODE" );
        }
        if( type == "pick" || type == "press" ) {
            const auto *view = find_view( obj.get_int( "id", 0 ) );
            if( view == nullptr ) {
                return event_result::consumed;
            }
            if( type == "pick" ) {
                s.pick = pending_pick{ .owner = view->get_owner(), .index = obj.get_int( "index" ) };
            }
            return press_action( obj.get_string( "act", "CONFIRM" ), view->get_input_category() );
        }
        if( type == "quit" ) {
            ev = SDL_Event{};
            ev.type = SDL_EVENT_QUIT;
            return event_result::rewritten;
        }
    } catch( const std::exception &err ) {
        DebugLog( DL::Warn, DC::Main ) << "Godot bridge: bad message: " << err.what();
    }
    return event_result::consumed;
}

auto take_input() -> input_event
{
    return std::exchange( state().pending_input, input_event() );
}

auto mouse_position() -> point
{
    return state().mouse;
}

auto send_frame( SDL_Renderer *renderer, SDL_Texture *frame ) -> void
{
    auto &s = state();
    if( !s.link || !read_image( renderer, frame, s.frame_bytes ) ) {
        return;
    }
    sync_screens();
    send_message( message_kind::frame, nullptr, 0, s.frame_bytes.data(), s.frame_bytes.size() );
}

auto request_minimap() -> void
{
    state().minimap_requested = true;
}

auto take_minimap_request() -> bool
{
    return std::exchange( state().minimap_requested, false ) && state().link != nullptr;
}

auto send_minimap( SDL_Renderer *renderer, SDL_Texture *image ) -> void
{
    auto &s = state();
    if( !s.link || !read_image( renderer, image, s.minimap_bytes ) ||
        s.minimap_bytes == s.sent_minimap ) {
        return;
    }
    s.sent_minimap = s.minimap_bytes;
    send_message( message_kind::minimap, nullptr, 0, s.minimap_bytes.data(), s.minimap_bytes.size() );
}

auto sync_screens() -> void
{
    auto &s = state();
    if( !s.link ) {
        return;
    }
    // Tell Godot which of its native screens, and whether the HUD, belong on screen now.
    const auto main_visible = main_view_visible();
    auto meta = std::ostringstream();
    auto jsout = JsonOut( meta );
    jsout.start_object();
    jsout.member( "t", "frame" );
    jsout.member( "main", main_visible );
    jsout.member( "views", collect_visible_views() );
    jsout.end_object();
    if( meta.str() != s.sent_meta ) {
        s.sent_meta = meta.str();
        send_json( s.sent_meta );
    }
    if( main_visible && s.hud != s.sent_hud ) {
        s.sent_hud = s.hud;
        send_json( s.sent_hud );
    }
}

auto shutdown() -> void
{
    auto &s = state();
    s.running = false;
    if( s.link ) {
        s.link->shutdown();
    }
}

auto note_main_view( const ui_adaptor &ui ) -> void
{
    state().main_view = &ui;
}

auto set_hud( std::string json ) -> void
{
    state().hud = std::move( json );
}

auto native_screens() -> bool
{
    return is_active();
}

native_view::native_view( std::string kind, const void *owner, std::string input_category )
    : id( state().next_view_id++ ), kind( std::move( kind ) ), owner( owner ),
      input_category( std::move( input_category ) )
{
    state().views.push_back( this );
}

native_view::~native_view()
{
    auto &views = state().views;
    std::erase( views, this );
    send_json( string_format( R"({"t":"close","id":%d})", id ) );
}

auto native_view::attach( const ui_adaptor &ui ) -> void
{
    adaptor = &ui;
}

auto native_view::publish( const std::function<void( JsonOut & )> &write_body ) -> void
{
    send( compose( "view", write_body ) );
}

auto native_view::compose( const std::string &type,
                           const std::function<void( JsonOut & )> &write_body ) const -> std::string
{
    auto out = std::ostringstream();
    auto jsout = JsonOut( out );
    jsout.start_object();
    jsout.member( "t", type );
    jsout.member( "id", id );
    jsout.member( "kind", kind );
    write_body( jsout );
    jsout.end_object();
    return out.str();
}

auto native_view::send( const std::string &message ) const -> void
{
    send_json( message );
}

auto take_pick( const void *owner ) -> std::optional<int>
{
    auto &pick = state().pick;
    if( !pick || pick->owner != owner ) {
        return std::nullopt;
    }
    const auto index = pick->index;
    pick.reset();
    return index;
}

curses_draw_suppression::curses_draw_suppression()
{
    ++state().suppression_depth;
}

curses_draw_suppression::~curses_draw_suppression()
{
    --state().suppression_depth;
}

auto curses_draw_suppressed() -> bool
{
    return state().suppression_depth > 0;
}

auto write_spans( JsonOut &jsout, const std::string &text, const nc_color &base ) -> void
{
    jsout.start_array();
    auto colors = std::stack<std::string>();
    colors.push( string_from_color( base ) );
    for( const auto &segment : split_by_color( text ) ) {
        if( segment.empty() ) {
            continue;
        }
        auto run = segment;
        if( segment[0] == '<' ) {
            const auto tag = get_color_from_tag( segment, report_color_error::no );
            if( tag.type == color_tag_parse_result::open_color_tag ) {
                colors.push( string_from_color( tag.color ) );
            } else if( tag.type == color_tag_parse_result::close_color_tag && colors.size() > 1 ) {
                colors.pop();
            }
            if( tag.type != color_tag_parse_result::non_color_tag ) {
                run = rm_prefix( segment );
            }
        }
        if( run.empty() ) {
            continue;
        }
        jsout.start_array();
        jsout.write( run );
        jsout.write( colors.top() );
        jsout.end_array();
    }
    jsout.end_array();
}

auto capture_window( const int lines, const int cols ) -> catacurses::window
{
    // Placed right of the visible screen: anything a draw function pushes to the frame is clipped.
    return catacurses::newwin( lines, cols, point( TERMX + 1, 0 ) );
}

namespace
{

/// Color name of a drawn cell. Cells on a colored background (a list's cursor, white on blue) are
/// marked `h_`, with the text's color, or the background's for dark text.
auto cell_color( const cata_cursesport::cursecell &c ) -> std::string
{
    // Curses names of the 16 base colors; bright ones are `base + 8`.
    static constexpr auto names = std::array {
        "black", "red", "green", "brown", "blue", "magenta", "cyan", "light_gray",
        "dark_gray", "light_red", "light_green", "yellow", "light_blue", "pink", "light_cyan", "white",
    };
    const auto shown = c.BG != catacurses::black && c.FG == catacurses::black ? c.BG : c.FG;
    return std::string( c.BG == catacurses::black ? "c_" : "h_" ) +
           names[std::clamp( static_cast<int>( shown ), 0, 15 )];
}

} // namespace

auto write_window_spans( JsonOut &jsout, const catacurses::window &w,
                         const window_columns &columns ) -> void
{
    const auto color_of = &cell_color;
    const auto *win = w.get<cata_cursesport::WINDOW>();
    jsout.start_array();
    if( win == nullptr ) {
        jsout.end_array();
        return;
    }
    const auto is_divider = [&]( const cata_cursesport::curseline & line ) {
        static const auto parts = std::array<std::string, 9> { "│", "┬", "┴", "┼", "├", "┤", "|", " ", "" };
        return columns.left < 0 || columns.left >= static_cast<int>( line.chars.size() ) ||
               std::ranges::contains( parts, line.chars[columns.left].ch );
    };
    const auto skip = columns.skip_divider && std::ranges::all_of( win->line, is_divider ) ? 1 : 0;
    // Lines without their trailing blanks, then without trailing empty lines.
    auto rows = std::vector<std::vector<const cata_cursesport::cursecell *>>();
    for( const auto &line : win->line ) {
        const auto left = std::clamp( columns.left + skip, 0, static_cast<int>( line.chars.size() ) );
        const auto width = columns.width < 0 ? static_cast<int>( line.chars.size() ) - left :
                           std::min( columns.width - skip, static_cast<int>( line.chars.size() ) - left );
        auto cells = line.chars
                     | std::views::drop( left )
                     | std::views::take( width )
        | std::views::transform( []( const auto & c ) { return &c; } )
        | std::ranges::to<std::vector>();
        while( !cells.empty() && ( cells.back()->ch.empty() || cells.back()->ch == " " ) ) {
            cells.pop_back();
        }
        rows.push_back( std::move( cells ) );
    }
    while( !rows.empty() && rows.back().empty() ) {
        rows.pop_back();
    }
    // Drawing code that starts below a title it no longer draws leaves blank lines on top.
    const auto blank_top = std::ranges::distance( rows | std::views::take_while(
                               &std::vector<const cata_cursesport::cursecell *>::empty ) );
    rows.erase( rows.begin(), rows.begin() + blank_top );
    auto run = std::string();
    auto run_color = std::string();
    const auto flush = [&]() {
        if( !run.empty() ) {
            jsout.start_array();
            jsout.write( run );
            jsout.write( run_color );
            jsout.end_array();
            run.clear();
        }
    };
    for( const auto &[y, cells] : rows | std::views::enumerate ) {
        if( y > 0 ) {
            run += "\n";
        }
        for( const auto *cell : cells ) {
            const auto color = color_of( *cell );
            // A space takes the color around it, except at the edge of a highlight.
            const auto highlight_edge = color.starts_with( "h_" ) || run_color.starts_with( "h_" );
            if( color != run_color && ( cell->ch != " " || highlight_edge ) ) {
                flush();
                run_color = color;
            }
            run += cell->ch;
        }
    }
    flush();
    jsout.end_array();
}

auto write_window_grid( JsonOut &jsout, const catacurses::window &w,
                        const window_area &area ) -> void
{
    jsout.start_array();
    const auto *win = w.get<cata_cursesport::WINDOW>();
    if( win == nullptr ) {
        jsout.end_array();
        return;
    }
    const auto lines = static_cast<int>( win->line.size() );
    const auto bottom = area.size.y > 0 ? std::min( lines, area.at.y + area.size.y ) : lines;
    for( const auto y : std::views::iota( std::max( area.at.y, 0 ), std::max( bottom, 0 ) ) ) {
        const auto &chars = win->line[y].chars;
        const auto width = static_cast<int>( chars.size() );
        const auto right = area.size.x > 0 ? std::min( width, area.at.x + area.size.x ) : width;
        jsout.start_array();
        auto run = std::string();
        auto run_color = std::string();
        const auto flush = [&]() {
            if( !run.empty() ) {
                jsout.start_array();
                jsout.write( run );
                jsout.write( run_color );
                jsout.end_array();
                run.clear();
            }
        };
        for( const auto x : std::views::iota( std::max( area.at.x, 0 ), std::max( right, 0 ) ) ) {
            const auto &cell = chars[x];
            // Wide glyphs leave an empty cell after them, which is not a square of its own.
            if( cell.ch.empty() ) {
                continue;
            }
            const auto color = cell_color( cell );
            if( color != run_color ) {
                flush();
                run_color = color;
            }
            run += cell.ch;
        }
        flush();
        jsout.end_array();
    }
    jsout.end_array();
}

auto copy_window( const catacurses::window &from, const catacurses::window &to,
                  const point at ) -> void
{
    const auto *src = from.get<cata_cursesport::WINDOW>();
    auto *dst = to.get<cata_cursesport::WINDOW>();
    if( src == nullptr || dst == nullptr ) {
        return;
    }
    for( const auto &[y, line] : src->line | std::views::enumerate ) {
        const auto dy = at.y + static_cast<int>( y );
        if( dy < 0 || dy >= static_cast<int>( dst->line.size() ) ) {
            continue;
        }
        auto &target = dst->line[dy];
        for( const auto &[x, cell] : line.chars | std::views::enumerate ) {
            const auto dx = at.x + static_cast<int>( x );
            if( dx >= 0 && dx < static_cast<int>( target.chars.size() ) ) {
                target.chars[dx] = cell;
            }
        }
        target.touched = true;
    }
}

auto key_label( const std::string &action, const std::string &category ) -> std::string
{
    // An arrow key reads better than the vi-style letter bound to the same direction.
    const auto &events = inp_mngr.get_input_for_action( action, category );
    const auto arrow = std::ranges::find_if( events, []( const input_event & ev ) {
        const auto code = ev.get_first_input();
        return ev.type == input_event_t::keyboard &&
               ( code == KEY_UP || code == KEY_DOWN || code == KEY_LEFT || code == KEY_RIGHT );
    } );
    const auto key = arrow != events.end() ? std::optional( *arrow ) : key_for_action( action,
                     category );
    if( !key ) {
        return {};
    }
    return inp_mngr.get_keyname( key->get_first_input(), key->type );
}

} // namespace cata::godot_bridge

#endif // TILES
