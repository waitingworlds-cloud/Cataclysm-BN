#include "scores_ui.h"

#include <algorithm>
#include <cassert>
#include <iterator>
#include <memory>
#include <ranges>
#include <string>
#include <tuple>
#include <utility>
#include <vector>

#include "achievement.h"
#include "color.h"
#include "cursesdef.h"
#include "event_statistics.h"
#if defined(TILES)
#include "godot_bridge.h"
#include "godot_screen.h"
#endif
#include "input.h"
#include "kill_tracker.h"
#include "output.h"
#include "point.h"
#include "stats_tracker.h"
#include "translations.h"
#include "ui.h"
#include "ui_manager.h"

#if defined(TILES)
namespace
{

/// A text screen drawn by the Godot front end: optional tabs over a scrolling body.
struct text_screen {
    std::string title;
    std::string icon;
    std::vector<std::string> tabs = {};
    int tab = 0;
    const std::string &text;
    bool mono = false;
    int scroll = 0;
};

auto publish_text_screen( cata::godot_bridge::native_view &native, const text_screen &ts ) -> void
{
    namespace gs = cata::godot_screen;
    const auto category = std::string( "SCORES" );
    native.publish( [&]( JsonOut & jsout ) {
        jsout.member( "title", ts.title );
        jsout.member( "icon", ts.icon );
        jsout.member( "size", std::array{ 1100, 880 } );
        if( !ts.tabs.empty() ) {
            jsout.member( "tabs" );
            jsout.start_array();
            for( const auto &[n, name] : ts.tabs | std::views::enumerate ) {
                gs::write_tab( jsout, { .text = name, .active = static_cast<int>( n ) == ts.tab, .pick = gs::tab_pick + static_cast<int>( n ) } );
            }
            jsout.end_array();
            gs::write_tab_keys( jsout, "PREV_TAB", "NEXT_TAB", category );
        }
        jsout.member( "aside" );
        jsout.start_object();
        jsout.member( "mono", ts.mono );
        jsout.member( "scroll", ts.scroll );
        jsout.member( "body" );
        gs::write_span( jsout, { .text = ts.text } );
        jsout.end_object();
        jsout.member( "hints" );
        jsout.start_array();
        gs::write_fixed_hint( jsout, "↑↓", _( "Scroll" ) );
        if( !ts.tabs.empty() ) {
            gs::write_hint( jsout, "NEXT_TAB", category, _( "Next tab" ) );
        }
        gs::write_hint( jsout, "QUIT", category, _( "Close" ) );
        jsout.end_array();
    } );
}

/// Scrolls a Godot text screen for `action`, as the classic text view would.
auto scroll_text_screen( int &scroll, const std::string &action, const std::string &text ) -> void
{
    const auto lines = static_cast<int>( std::ranges::count( text, '\n' ) );
    const auto delta = action == "DOWN" ? 1 : action == "UP" ? -1 : action == "PAGE_DOWN" ? 20 :
                       action == "PAGE_UP" ? -20 : 0;
    scroll = std::clamp( scroll + delta, 0, std::max( lines, 0 ) );
}

} // namespace
#endif

static std::string get_achievements_text( const achievements_tracker &achievements )
{
    std::string os;
    std::vector<const achievement *> valid_achievements = achievements.valid_achievements();
    valid_achievements.erase(
        std::remove_if( valid_achievements.begin(), valid_achievements.end(),
    [&]( const achievement * a ) {
        return achievements.is_hidden( a );
    } ), valid_achievements.end() );
    using sortable_achievement =
        std::tuple<achievement_completion, std::string, const achievement *>;
    std::vector<sortable_achievement> sortable_achievements;
    std::transform( valid_achievements.begin(), valid_achievements.end(),
                    std::back_inserter( sortable_achievements ),
    [&]( const achievement * ach ) {
        achievement_completion comp = achievements.is_completed( ach->id );
        return std::make_tuple( comp, ach->name().translated(), ach );
    } );
    std::sort( sortable_achievements.begin(), sortable_achievements.end(), localized_compare );
    for( const sortable_achievement &ach : sortable_achievements ) {
        os += achievements.ui_text_for( std::get<const achievement *>( ach ) ) + "\n";
    }
    if( valid_achievements.empty() ) {
        os += _( "This game has no valid achievements.\n" );
    }
    os += _( "Note that only achievements that existed when you started this game and still "
             "exist now will appear here." );
    return os;
}

static std::string get_scores_text( stats_tracker &stats )
{
    std::string os;
    std::vector<const score *> valid_scores = stats.valid_scores();
    for( const score *scr : valid_scores ) {
        os += scr->description( stats ) + "\n";
    }
    if( valid_scores.empty() ) {
        os += _( "This game has no valid scores.\n" );
    }
    os += _( "\nNote that only scores that existed when you started this game and still exist now "
             "will appear here." );
    return os;
}

void show_scores_ui( const achievements_tracker &achievements, stats_tracker &stats,
                     const kill_tracker &kills )
{
    catacurses::window w;

    enum class tab_mode {
        achievements,
        scores,
        kills,
        num_tabs,
        first_tab = achievements,
    };

    tab_mode tab = static_cast<tab_mode>( 0 );
    input_context ctxt( "SCORES" );
    ctxt.register_cardinal();
    ctxt.register_action( "PAGE_UP" );
    ctxt.register_action( "PAGE_DOWN" );
    ctxt.register_action( "QUIT" );
    ctxt.register_action( "PREV_TAB" );
    ctxt.register_action( "NEXT_TAB" );
    ctxt.register_action( "HELP_KEYBINDINGS" );

    catacurses::window w_view;
    scrolling_text_view view( w_view );
    bool new_tab = true;

    ui_adaptor ui;
#if defined(TILES)
    // Godot shows the tab's text in a scrolling panel.
    auto native = cata::godot_bridge::native_screens() ?
                  std::make_unique<cata::godot_bridge::native_view>( "screen", &stats, "SCORES" ) : nullptr;
    if( native ) {
        native->attach( ui );
    }
    auto native_text = std::string();
    auto native_scroll = 0;
#endif
    const auto &init_windows = [&]( ui_adaptor & ui ) {
        w = new_centered_win( TERMY - 2, FULL_SCREEN_WIDTH );
        w_view = catacurses::newwin( getmaxy( w ) - 4, getmaxx( w ) - 1,
                                     point( getbegx( w ), getbegy( w ) + 3 ) );
        ui.position_from_window( w );
#if defined(TILES)
        if( native ) {
            ui.position( point_zero, point_zero );
        }
#endif
    };
    ui.on_screen_resize( init_windows );
    // initialize explicitly here since w_view is used before first redraw
    init_windows( ui );

    const std::vector<std::pair<tab_mode, std::string>> tabs = {
        { tab_mode::achievements, _( "ACHIEVEMENTS" ) },
        { tab_mode::scores, _( "SCORES" ) },
        { tab_mode::kills, _( "KILLS" ) },
    };

    ui.on_redraw( [&]( const ui_adaptor & ) {
#if defined(TILES)
        if( native ) {
            publish_text_screen( *native, {
                .title = _( "Scores" ),
                .icon = "trophy",
                .tabs = { _( "Achievements" ), _( "Scores" ), _( "Kills" ) },
                .tab = static_cast<int>( tab ),
                .text = native_text,
                .mono = tab == tab_mode::kills,
                .scroll = native_scroll,
            } );
            return;
        }
#endif
        werase( w );
        draw_tabs( w, tabs, tab );
        draw_border_below_tabs( w );
        wnoutrefresh( w );

        view.draw( c_white );
    } );

    while( true ) {
        if( new_tab ) {
            std::string text;
            switch( tab ) {
                case tab_mode::achievements:
                    text = get_achievements_text( achievements );
                    break;
                case tab_mode::scores:
                    text = get_scores_text( stats );
                    break;
                case tab_mode::kills:
                    text = kills.get_kills_text();
                    break;
                case tab_mode::num_tabs:
                    assert( false );
                    break;
            }
            view.set_text( text );
#if defined(TILES)
            native_text = text;
            native_scroll = 0;
#endif
        }

        ui_manager::redraw();
        const std::string action = ctxt.handle_input();
        new_tab = false;
#if defined(TILES)
        if( native ) {
            if( const auto pick = cata::godot_bridge::take_pick( &stats ) ) {
                const auto picked = *pick - cata::godot_screen::tab_pick;
                if( picked >= 0 && picked < static_cast<int>( tab_mode::num_tabs ) ) {
                    tab = static_cast<tab_mode>( picked );
                    new_tab = true;
                    continue;
                }
            }
            scroll_text_screen( native_scroll, action, native_text );
        }
#endif
        if( action == "RIGHT" || action == "NEXT_TAB" ) {
            tab = static_cast<tab_mode>( static_cast<int>( tab ) + 1 );
            if( tab >= tab_mode::num_tabs ) {
                tab = tab_mode::first_tab;
            }
            new_tab = true;
        } else if( action == "LEFT" || action == "PREV_TAB" ) {
            tab = static_cast<tab_mode>( static_cast<int>( tab ) - 1 );
            if( tab < tab_mode::first_tab ) {
                tab = static_cast<tab_mode>( static_cast<int>( tab_mode::num_tabs ) - 1 );
            }
            new_tab = true;
        } else if( action == "DOWN" ) {
            view.scroll_down();
        } else if( action == "UP" ) {
            view.scroll_up();
        } else if( action == "PAGE_DOWN" ) {
            view.page_down();
        } else if( action == "PAGE_UP" ) {
            view.page_up();
        } else if( action == "CONFIRM" || action == "QUIT" ) {
            break;
        }
    }
}

void show_kills( kill_tracker &kills )
{
    catacurses::window w;

    input_context ctxt( "SCORES" );
    ctxt.register_cardinal();
    ctxt.register_action( "PAGE_UP" );
    ctxt.register_action( "PAGE_DOWN" );
    ctxt.register_action( "QUIT" );
    ctxt.register_action( "HELP_KEYBINDINGS" );

    catacurses::window w_view;
    scrolling_text_view view( w_view );

    ui_adaptor ui;
#if defined(TILES)
    auto native = cata::godot_bridge::native_screens() ?
                  std::make_unique<cata::godot_bridge::native_view>( "screen", &kills, "SCORES" ) : nullptr;
    if( native ) {
        native->attach( ui );
    }
    const auto native_text = kills.get_kills_text();
    auto native_scroll = 0;
#endif
    const auto &init_windows = [&]( ui_adaptor & ui ) {
        w = new_centered_win( TERMY - 2, FULL_SCREEN_WIDTH );
        w_view = catacurses::newwin( getmaxy( w ) - 4, getmaxx( w ) - 1,
                                     point( getbegx( w ), getbegy( w ) + 3 ) );
        ui.position_from_window( w );
        view.set_text( kills.get_kills_text() );
#if defined(TILES)
        if( native ) {
            ui.position( point_zero, point_zero );
        }
#endif
    };
    ui.on_screen_resize( init_windows );
    // initialize explicitly here since w_view is used before first redraw
    init_windows( ui );

    ui.on_redraw( [&]( const ui_adaptor & ) {
#if defined(TILES)
        if( native ) {
            publish_text_screen( *native, { .title = _( "Kills" ), .icon = "skull", .text = native_text, .mono = true, .scroll = native_scroll } );
            return;
        }
#endif
        werase( w );
        draw_border( w );
        wnoutrefresh( w );
        view.draw( c_white );
    } );

    while( true ) {
        ui_manager::redraw();
        const std::string action = ctxt.handle_input();
#if defined(TILES)
        if( native ) {
            scroll_text_screen( native_scroll, action, native_text );
        }
#endif
        if( action == "DOWN" ) {
            view.scroll_down();
        } else if( action == "UP" ) {
            view.scroll_up();
        } else if( action == "PAGE_DOWN" ) {
            view.page_down();
        } else if( action == "PAGE_UP" ) {
            view.page_up();
        } else if( action == "CONFIRM" || action == "QUIT" ) {
            break;
        }
    }
}
