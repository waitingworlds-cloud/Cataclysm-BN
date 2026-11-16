#include "catalua_console.h"

#include "catalua_log.h"
#include "catalua_impl.h"
#include "cursesdef.h"
#include "game.h"
#include "init.h"
#include "input.h"
#include "output.h"
#include "string_editor_window.h"
#include "string_utils.h"
#include "ui_manager.h"
#include "uistate.h"

#include <algorithm>
#include <array>
#include <ranges>

#if defined(TILES)
#   include "color.h"
#   include "godot_bridge.h"
#   include "godot_screen.h"
#   include "json.h"
#endif

namespace cata
{

namespace
{

struct numbered_prompt_line {
    int number = 0;
    std::string text;
};

auto split_prompt_lines( const std::string &text ) -> std::vector<std::string>
{
    auto lines = std::vector<std::string>();
    auto start = std::string::size_type{ 0 };
    while( start <= text.size() ) {
        const auto end = text.find( '\n', start );
        if( end == std::string::npos ) {
            lines.push_back( text.substr( start ) );
            break;
        }
        lines.push_back( text.substr( start, end - start ) );
        start = end + 1;
        if( start == text.size() ) {
            lines.emplace_back();
            break;
        }
    }
    if( lines.empty() ) {
        lines.emplace_back();
    }
    return lines;
}

auto format_line_number( const int line_number, const int width ) -> std::string
{
    if( line_number <= 0 ) {
        return std::string( width, ' ' );
    }
    auto rendered = std::to_string( line_number );
    const auto padding = width - static_cast<int>( rendered.size() );
    if( padding > 0 ) {
        rendered.insert( rendered.begin(), padding, ' ' );
    }
    return rendered;
}

auto build_numbered_prompt_lines( const std::string &text, const int content_width )
-> std::vector<numbered_prompt_line>
{
    auto lines = std::vector<numbered_prompt_line>();
    const auto logical_lines = split_prompt_lines( text );
    auto line_number = 1;
    for( auto i = 0; i < static_cast<int>( logical_lines.size() ); ++i ) {
        auto folded = foldstring( logical_lines[i], content_width );
        if( folded.empty() ) {
            folded.emplace_back();
        }
        for( auto j = 0; j < static_cast<int>( folded.size() ); ++j ) {
            lines.push_back( numbered_prompt_line{
                .number = j == 0 ? line_number : 0,
                .text = std::move( folded[j] ),
            } );
        }
        ++line_number;
    }
    return lines;
}

#if defined(TILES)
/// Writes `text` as one span, as the console prints it: color tags in Lua output stay literal.
auto write_plain_span( JsonOut &jsout, const std::string &text, const nc_color &color ) -> void
{
    jsout.start_array();
    jsout.start_array();
    jsout.write( text );
    jsout.write( string_from_color( color ) );
    jsout.end_array();
    jsout.end_array();
}
#endif

} // namespace

struct folded_log_msg {
    bool is_head = false;
    LuaLogLevel level;
    std::string text;
};

static std::vector<folded_log_msg> build_folded_log( int width )
{
    std::vector<folded_log_msg> ret;
    for( const lua_log_msg &msg : get_lua_log_instance().get_entries() ) {
        std::vector<std::string> lines = foldstring( msg.text, width );
        for( int i = static_cast<int>( lines.size() ) - 1; i >= 0; i-- ) {
            ret.push_back( folded_log_msg{ i == 0, msg.level, std::move( lines[i] ) } );
        }
    }
    return ret;
}

static nc_color get_log_level_color( LuaLogLevel level )
{
    switch( level ) {
        case LuaLogLevel::Input:
            return c_white;
        case LuaLogLevel::DebugMsg:
            return c_magenta;
        case LuaLogLevel::Error:
            return c_red;
        case LuaLogLevel::Warn:
            return c_yellow;
        case LuaLogLevel::Info:
            return c_light_gray;
        default:
            debugmsg( "Log level color not defined!" );
            return c_white;
    }
}

static std::vector<std::string> &get_input_history()
{
    return uistate.gethistory( "LUA_CONSOLE" );
}

static int num_history_entries()
{
    return static_cast<int>( get_input_history().size() );
}

static void add_to_input_history( const std::string &s )
{
    std::vector<std::string> &hist = get_input_history();
    for( auto it = hist.begin(); it != hist.end(); it++ ) {
        if( *it == s ) {
            // Refresh existing history entry
            std::string msg = std::move( *it );
            hist.erase( it );
            hist.push_back( std::move( msg ) );
            return;
        }
    }
    // Add new history entry
    hist.push_back( s );
}

void show_lua_console_impl()
{
    input_context ctxt( "LUA_CONSOLE" );
    ctxt.register_action( "HELP_KEYBINDINGS" );
    ctxt.register_action( "EDIT" );
    ctxt.register_action( "QUIT" );
    ctxt.register_action( "RELOAD" );
    ctxt.register_action( "TOGGLE_EXPANDED" );
    ctxt.register_action( "HISTORY_UP" );
    ctxt.register_action( "HISTORY_DOWN" );
    ctxt.register_action( "SCROLL_UP" );
    ctxt.register_action( "SCROLL_DOWN" );
    ctxt.register_action( "SCROLL_TOP" );
    ctxt.register_action( "SCROLL_BOTTOM" );

    ui_adaptor ui;

    constexpr auto CURRENT_INPUT = -1;
    constexpr auto scroll_speed = 5;
    constexpr auto collapsed_input_area_size = 5;

    point win_pos;
    point win_size;
    point log_pos;
    point log_size;
    point prompt_pos;
    point prompt_size;

    auto log_scroll_pos = 0;
    auto log_folded = std::vector<folded_log_msg>();

    auto use_expanded_view = false;
    auto input_area_size = collapsed_input_area_size;

    const auto get_input_area_size = [&]( const point & window_size,
    const bool expanded ) -> int {
        const auto max_input_size = std::max( collapsed_input_area_size, window_size.y - 8 );
        if( !expanded )
        {
            return collapsed_input_area_size;
        }
        const auto target_size = std::max( collapsed_input_area_size, window_size.y / 2 );
        return std::min( max_input_size, target_size );
    };

    const auto create_string_editor = [&]() {
        // Offset by one for the scrollbar
        return catacurses::newwin( prompt_size.y, prompt_size.x + 1, prompt_pos - point_east );
    };

    catacurses::window w_console;
    catacurses::window w_log;
    catacurses::window w_prompt;

    std::string current_input;
    int history_cursor = CURRENT_INPUT;

    auto is_editing = false;

#if defined(TILES)
    // Godot draws the console as a screen: the output, the command and the console's keys.
    auto native = cata::godot_bridge::native_screens() ?
                  std::make_unique<cata::godot_bridge::native_view>( "screen", &ui, "LUA_CONSOLE" ) : nullptr;
    if( native ) {
        native->attach( ui );
    }
#endif

    ui.on_screen_resize( [&]( ui_adaptor & ui ) {
        win_size = point( TERMX, TERMY );
        win_pos = point( ( TERMX - win_size.x ) / 2, ( TERMY - win_size.y ) / 2 );
        input_area_size = get_input_area_size( win_size, use_expanded_view );
        prompt_size = point( win_size.x - 3, input_area_size );
        prompt_pos = win_pos + point( 2, win_size.y - input_area_size - 1 );
        log_pos = win_pos + point_south_east;
        log_size = win_size + point( -2, -7 - input_area_size );
        w_console = catacurses::newwin( win_size.y, win_size.x, win_pos );
        w_log = catacurses::newwin( log_size.y, log_size.x, log_pos );
        w_prompt = catacurses::newwin( prompt_size.y, prompt_size.x, prompt_pos );
#if defined(TILES)
        if( native ) {
            ui.position( point_zero, point_zero );
            return;
        }
#endif
        ui.position_from_window( w_console );
    } );
    ui.mark_resize();

#if defined(TILES)
    const auto publish_native = [&]() {
        namespace gs = cata::godot_screen;
        const auto &entries = get_lua_log_instance().get_entries();
        // The old window scrolls by folded lines up from the newest; find the entry at the top of that view.
        auto top_entry = std::optional<int>();
        if( log_scroll_pos > 0 ) {
            auto lines = 0;
            for( const auto &[i, msg] : entries | std::views::enumerate ) {
                lines += static_cast<int>( foldstring( msg.text, 76 ).size() );
                if( lines >= log_scroll_pos + log_size.y || i + 1 == std::ssize( entries ) ) {
                    top_entry = static_cast<int>( std::ssize( entries ) - 1 - i );
                    break;
                }
            }
        }
        const auto browsing = history_cursor != CURRENT_INPUT;
        const auto &command = browsing ? get_input_history()[history_cursor] : current_input;
        const auto category = std::string( "LUA_CONSOLE" );
        native->publish( [&]( JsonOut & jsout ) {
            jsout.member( "title", _( "Lua console" ) );
            jsout.member( "icon", "terminal" );
            jsout.member( "size", std::array{ 1280, 900 } );
            jsout.member( "toggles" );
            jsout.start_array();
            gs::write_toggle( jsout, { .act = "TOGGLE_EXPANDED", .text = _( "Tall editor" ), .icon = "unfold-vertical", .category = category },
                              use_expanded_view );
            jsout.end_array();

            jsout.member( "panes" );
            jsout.start_array();
            jsout.start_object();
            jsout.member( "title", _( "Output" ) );
            jsout.member( "icon", "scroll-text" );
            jsout.member( "count", std::to_string( entries.size() ) );
            if( top_entry ) {
                jsout.member( "scroll_entry", *top_entry );
            } else {
                jsout.member( "scroll_end", true );
            }
            jsout.member( "entries" );
            jsout.start_array();
            for( const auto &msg : entries | std::views::reverse ) {
                jsout.start_object();
                jsout.member( "text" );
                // Commands stand out with a prompt mark, as in the old window.
                write_plain_span( jsout, msg.level == LuaLogLevel::Input ? "> " + msg.text : msg.text,
                                  get_log_level_color( msg.level ) );
                jsout.end_object();
            }
            jsout.end_array();
            jsout.end_object();
            jsout.end_array();

            jsout.member( "aside" );
            jsout.start_object();
            jsout.member( "width", 520 );
            jsout.member( "share", 0.4 );
            jsout.member( "title" );
            gs::write_span( jsout, { .text = browsing ? string_format( _( "Command %d of %d" ), history_cursor + 1, num_history_entries() ) : _( "Command" ), .color = c_white } );
            jsout.member( "subtitle", browsing ? _( "From history" ) : command.empty() ? "" :
                          _( "Not run yet" ) );
            if( !command.empty() ) {
                jsout.member( "body" );
                write_plain_span( jsout, command, c_light_gray );
                jsout.member( "mono", true );
            }
            jsout.member( "empty", _( "Nothing written yet." ) );
            jsout.member( "buttons" );
            jsout.start_array();
            gs::write_button( jsout, { .act = "EDIT", .text = command.empty() ? _( "Write a command" ) : _( "Edit and run" ), .icon = "pencil", .category = category, .primary = true } );
            gs::write_button( jsout, { .act = "HISTORY_UP", .text = _( "Older command" ), .icon = "chevron-up", .category = category,
                                       .enabled = num_history_entries() > 0 && history_cursor != 0
                                     } );
            gs::write_button( jsout, { .act = "HISTORY_DOWN", .text = _( "Newer command" ), .icon = "chevron-down", .category = category,
                                       .enabled = browsing
                                     } );
            gs::write_button( jsout, { .act = "RELOAD", .text = _( "Reload Lua" ), .icon = "refresh-cw", .category = category } );
            jsout.end_array();
            jsout.end_object();

            jsout.member( "hints" );
            jsout.start_array();
            gs::write_hint( jsout, "EDIT", category, _( "Edit" ) );
            gs::write_hint( jsout, "HISTORY_UP", category, _( "Older" ) );
            gs::write_hint( jsout, "HISTORY_DOWN", category, _( "Newer" ) );
            gs::write_hint( jsout, "SCROLL_UP", category, _( "Scroll up" ) );
            gs::write_hint( jsout, "SCROLL_DOWN", category, _( "Scroll down" ) );
            gs::write_hint( jsout, "SCROLL_TOP", category, _( "Oldest" ) );
            gs::write_hint( jsout, "SCROLL_BOTTOM", category, _( "Newest" ) );
            gs::write_hint( jsout, "QUIT", category, _( "Close" ) );
            jsout.end_array();
        } );
    };
#endif

    ui.on_redraw( [&]( const ui_adaptor & ) {
#if defined(TILES)
        if( native ) {
            publish_native();
            return;
        }
#endif
        werase( w_console );
        draw_border( w_console );
        std::string separator;
        int separator_y = win_size.y - prompt_size.y - 2;
        for( int i = 0; i < win_size.x - 2; i++ ) {
            separator += LINE_OXOX_S;
        }
        mvwprintz( w_console, point( 1, separator_y ), c_light_gray, separator );
        mvwprintz( w_console, point( 1, separator_y - 4 ), c_light_gray, separator );
        if( is_editing ) {
            mvwprintz( w_console, point( 1, separator_y - 3 ), c_light_gray,
                       _( "Press Ctrl+S to run script, press Esc to cancel" )
                     );
            mvwprintz( w_console, point( 1, separator_y - 2 ), c_light_gray,
                       _( "Press arrow keys to navigate text input" )
                     );
            mvwprintz( w_console, point( 1, separator_y - 1 ), c_light_gray,
                       _( "Press Enter to add new line" )
                     );
        } else {
            mvwprintz( w_console, point( 1, separator_y - 3 ), c_light_gray,
                       _( "Press Enter to enter/edit command, Esc to quit" )
                     );
            mvwprintz( w_console, point( 1, separator_y - 2 ), c_light_gray,
                       _( "Press Up/Down arrows to select from history" )
                     );
            mvwprintz( w_console, point( 1, separator_y - 1 ), c_light_gray,
                       string_format(
                           _( "Press PgUp/PgDn/Home/End to scroll output window, %s to toggle expanded input view" ),
                           ctxt.get_desc( "TOGGLE_EXPANDED" )
                       )
                     );
        }

        scrollbar()
        .offset_x( 0 )
        .offset_y( 1 )
        .content_size( log_folded.size() )
        .viewport_size( log_size.y )
        .viewport_pos( static_cast<int>( log_folded.size() ) - log_scroll_pos - log_size.y )
        .scroll_to_last( false )
        .apply( w_console );

        wnoutrefresh( w_console );

        werase( w_log );

        int y_pos = log_size.y - 1;
        int start_line = log_scroll_pos;
        int end_line = std::min( static_cast<int>( log_folded.size() ), start_line + log_size.y );
        for( int log_line = start_line; log_line < end_line; log_line++ ) {
            const folded_log_msg &msg = log_folded[log_line];
            nc_color col = get_log_level_color( msg.level );
            int x_pos = 1;
            if( msg.level == LuaLogLevel::Input ) {
                // User input is indented, and first line is highlighted
                x_pos = 2;
                if( msg.is_head ) {
                    mvwprintz( w_log, point( 1, y_pos ), col, ">" );
                }
            }
            mvwprintz( w_log, point( x_pos, y_pos ), col, msg.text );
            y_pos--;
        }

        wnoutrefresh( w_log );

        werase( w_prompt );

        const auto prompt_text =
            history_cursor == CURRENT_INPUT ? current_input : get_input_history()[history_cursor];
        const auto prompt_line_count = std::max(
                                           1,
                                           static_cast<int>( split_prompt_lines( prompt_text ).size() )
                                       );
        const auto line_number_width =
            std::max( 2, static_cast<int>( std::to_string( prompt_line_count ).size() ) );
        const auto gutter_width = line_number_width + 1;
        const auto content_width = std::max( 1, prompt_size.x - gutter_width );
        const auto prompt_lines = build_numbered_prompt_lines( prompt_text, content_width );
        const auto prompt_start_line =
            std::max( 0, static_cast<int>( prompt_lines.size() ) - prompt_size.y );
        const auto visible_lines =
            std::min( prompt_size.y, static_cast<int>( prompt_lines.size() ) - prompt_start_line );
        for( auto i = 0; i < visible_lines; ++i ) {
            const auto &line = prompt_lines[prompt_start_line + i];
            mvwprintz(
                w_prompt,
                point( 0, i ),
                c_light_gray,
                "%s",
                format_line_number( line.number, line_number_width )
            );
            mvwprintz(
                w_prompt,
                point( gutter_width, i ),
                c_light_gray,
                "%s",
                line.text
            );
        }

        wnoutrefresh( w_prompt );
    } );

    bool log_invalidated = true;
    while( true ) {
        if( log_invalidated ) {
            log_invalidated = false;
            log_scroll_pos = 0;
            log_folded = build_folded_log( 76 );
        }
        ui_manager::redraw_invalidated();

        const std::string act = ctxt.handle_input();

        if( act == "QUIT" ) {
            // Close
            return;
        } else if( act == "HISTORY_UP" ) {
            int sz = num_history_entries();
            if( sz != 0 && history_cursor != 0 ) {
                if( history_cursor == CURRENT_INPUT ) {
                    history_cursor = sz - 1;
                } else {
                    history_cursor = std::max( 0, history_cursor - 1 );
                }
            }
            // Update input preview
            ui.invalidate_ui();
        } else if( act == "HISTORY_DOWN" ) {
            int sz = num_history_entries();
            if( sz != 0 && history_cursor != CURRENT_INPUT ) {
                if( history_cursor == sz - 1 ) {
                    history_cursor = CURRENT_INPUT;
                } else {
                    history_cursor = std::min( history_cursor + 1, sz - 1 );
                }
            }
            // Update input preview
            ui.invalidate_ui();
        } else if( act == "SCROLL_UP" || act == "SCROLL_TOP" ) {
            int limit = std::max( 0, static_cast<int>( log_folded.size() ) - log_size.y );
            if( act == "SCROLL_TOP" ) {
                log_scroll_pos = limit;
            } else {
                log_scroll_pos = std::min( limit, log_scroll_pos + scroll_speed );
            }
            ui.invalidate_ui();
        } else if( act == "SCROLL_DOWN" ) {
            log_scroll_pos = std::max( 0, log_scroll_pos - scroll_speed );
            ui.invalidate_ui();
        } else if( act == "SCROLL_BOTTOM" ) {
            log_scroll_pos = 0;
            ui.invalidate_ui();
        } else if( act == "EDIT" ) {
            // Edit
            is_editing = true;
            ui.invalidate_ui();
            string_editor_window ew(
                create_string_editor,
                history_cursor == CURRENT_INPUT ? current_input : get_input_history()[history_cursor],
            string_editor_window::string_editor_window_options{
                .show_line_numbers = true,
            }
            );
            std::pair<bool, std::string> res = ew.query_string();
            is_editing = false;
            history_cursor = CURRENT_INPUT;
            if( res.first ) {
                // Confirmed
                current_input.clear();
                add_to_input_history( res.second );
                log_invalidated = true;
                run_console_input( DynamicDataLoader::get_instance().lua->lua, res.second );
            } else {
                // Canceled, save input for later use
                current_input = res.second;
            }
            // Godot draws the editor, so closing it frees no part of the console that would redraw it.
            ui.invalidate_ui();
        } else if( act == "RELOAD" ) {
            ui.invalidate_ui();
            log_invalidated = true;
            reload_lua_code();
        } else if( act == "TOGGLE_EXPANDED" ) {
            use_expanded_view = !use_expanded_view;
            ui.mark_resize();
            ui.invalidate_ui();
        }
    }
}

} // namespace cata
