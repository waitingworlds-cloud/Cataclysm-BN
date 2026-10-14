#include "game.h" // IWYU pragma: associated

#include <algorithm>
#include <array>
#include <map>
#include <memory>
#include <ranges>
#include <string>
#include <vector>

#include "avatar.h"
#include "calendar.h"
#include "color.h"
#include "debug.h"
#if defined(TILES)
#include "godot_bridge.h"
#include "godot_screen.h"
#endif
#include "input.h"
#include "mission.h"
#include "npc.h"
#include "output.h"
#include "string_formatter.h"
#include "string_utils.h"
#include "translations.h"
#include "ui.h"
#include "ui_manager.h"

void game::list_missions()
{
    catacurses::window w_missions;

    enum class tab_mode : int {
        TAB_ACTIVE = 0,
        TAB_COMPLETED,
        TAB_FAILED,
        NUM_TABS,
        FIRST_TAB = 0,
        LAST_TAB = NUM_TABS - 1
    };
    tab_mode tab = tab_mode::FIRST_TAB;
    size_t selection = 0;
    int entries_per_page = 0;
    input_context ctxt( "MISSIONS" );
    ctxt.register_cardinal();
    ctxt.register_action( "CONFIRM" );
    ctxt.register_action( "QUIT" );
    ctxt.register_action( "HELP_KEYBINDINGS" );

    ui_adaptor ui;
#if defined(TILES)
    // Godot lists the missions with the chosen one's details beside them.
    auto native = cata::godot_bridge::native_screens() ?
                  std::make_unique<cata::godot_bridge::native_view>( "screen", &u, "MISSIONS" ) : nullptr;
    if( native ) {
        native->attach( ui );
    }
#endif
    ui.on_screen_resize( [&]( ui_adaptor & ui ) {
        w_missions = new_centered_win( FULL_SCREEN_HEIGHT, FULL_SCREEN_WIDTH );

        // content ranges from y=3 to FULL_SCREEN_HEIGHT - 2
        entries_per_page = FULL_SCREEN_HEIGHT - 4;

        ui.position_from_window( w_missions );
#if defined(TILES)
        if( native ) {
            ui.position( point_zero, point_zero );
        }
#endif
    } );
    ui.mark_resize();

    std::vector<mission *> umissions;

#if defined(TILES)
    const auto publish_native = [&]() {
        namespace gs = cata::godot_screen;
        const auto category = std::string( "MISSIONS" );
        const auto counts = std::array {
            u.get_active_missions().size(), u.get_completed_missions().size(), u.get_failed_missions().size()
        };
        native->publish( [&]( JsonOut & jsout ) {
            jsout.member( "title", _( "Missions" ) );
            jsout.member( "icon", "scroll-text" );
            jsout.member( "size", std::array{ 1240, 780 } );
            jsout.member( "tabs" );
            jsout.start_array();
            const auto tab_names = std::array { _( "Active" ), _( "Completed" ), _( "Failed" ) };
            const auto tab_icons = std::array { "target", "circle-check", "circle-x" };
            for( const auto n : std::views::iota( 0, static_cast<int>( tab_names.size() ) ) ) {
                gs::write_tab( jsout, {
                    .text = tab_names[n],
                    .active = static_cast<int>( tab ) == n,
                    .pick = gs::tab_pick + n,
                    .icon = tab_icons[n],
                    .count = std::to_string( counts[n] ),
                } );
            }
            jsout.end_array();
            gs::write_tab_keys( jsout, "LEFT", "RIGHT", category );

            const auto active_tab = tab == tab_mode::TAB_ACTIVE;
            jsout.member( "panes" );
            jsout.start_array();
            jsout.start_object();
            jsout.member( "title", _( "Missions" ) );
            jsout.member( "icon", "scroll-text" );
            jsout.member( "cursor", static_cast<int>( selection ) );
            jsout.member( "confirm", active_tab ? "CONFIRM" : "" );
            jsout.member( "rows" );
            jsout.start_array();
            for( auto *miss : umissions ) {
                const auto current = u.get_active_mission() == miss;
                gs::write_row( jsout, {
                    .text = { .text = miss->name(), .color = current ? c_light_green : c_white },
                    .note = { .text = current ? _( "Current" ) : "", .color = c_light_green },
                } );
            }
            jsout.end_array();
            jsout.end_object();
            jsout.end_array();

            jsout.member( "aside" );
            jsout.start_object();
            jsout.member( "width", 640 );
            jsout.member( "share", 0.55 );
            if( selection < umissions.size() ) {
                auto *miss = umissions[selection];
                const auto current = u.get_active_mission() == miss;
                jsout.member( "title" );
                gs::write_span( jsout, { .text = miss->name(), .color = current ? c_light_green : c_white } );
                if( miss->get_npc_id().is_valid() ) {
                    if( const npc *guy = g->find_npc( miss->get_npc_id() ) ) {
                        jsout.member( "subtitle", string_format( _( "For %s" ), guy->disp_name() ) );
                    }
                }
                auto body = miss->get_description();
                for( const auto &[count, id] : miss->get_likely_rewards() ) {
                    body = replace_all( body, "<reward_count:" + id.str() + ">", std::to_string( count ) );
                }
                if( miss->has_deadline() ) {
                    const auto deadline = miss->get_deadline();
                    body += "\n\n" + string_format( _( "Deadline: %s" ), to_string( deadline ) );
                    if( tab != tab_mode::TAB_COMPLETED ) {
                        const auto remaining = deadline - calendar::turn;
                        const auto remaining_time = remaining <= 0_turns ? std::string( _( "None!" ) ) :
                                                    u.has_watch() ? to_string( remaining ) : to_string_approx( remaining );
                        body += "\n" + string_format( _( "Time remaining: %s" ), remaining_time );
                    }
                }
                if( miss->has_target() ) {
                    body += "\n" + string_format( _( "Target: %s   You: %s" ), miss->get_target().to_string(),
                                                  u.abs_omt_pos().to_string() );
                }
                jsout.member( "body" );
                gs::write_span( jsout, { .text = body } );
                if( active_tab ) {
                    jsout.member( "buttons" );
                    jsout.start_array();
                    gs::write_button( jsout, { .act = "CONFIRM", .text = _( "Make this my current mission" ), .icon = "target",
                                               .category = category, .primary = true, .enabled = !current
                                             } );
                    jsout.end_array();
                }
            } else {
                static const auto nope = std::array {
                    translate_marker( "You have no active missions!" ),
                    translate_marker( "You haven't completed any missions!" ),
                    translate_marker( "You haven't failed any missions!" ),
                };
                jsout.member( "empty", _( nope[static_cast<int>( tab )] ) );
            }
            jsout.end_object();

            jsout.member( "hints" );
            jsout.start_array();
            gs::write_fixed_hint( jsout, "↑↓", _( "Choose" ) );
            gs::write_fixed_hint( jsout, "←→", _( "Tab" ) );
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
        werase( w_missions );
        // entries_per_page * page number
        const int top_of_page = entries_per_page * ( selection / entries_per_page );
        const int bottom_of_page =
            std::min( top_of_page + entries_per_page - 1, static_cast<int>( umissions.size() ) - 1 );

        for( int i = 3; i < FULL_SCREEN_HEIGHT - 1; i++ ) {
            mvwputch( w_missions, point( 30, i ), BORDER_COLOR, LINE_XOXO );
        }

        const std::vector<std::pair<tab_mode, std::string>> tabs = {
            { tab_mode::TAB_ACTIVE, _( "ACTIVE MISSIONS" ) },
            { tab_mode::TAB_COMPLETED, _( "COMPLETED MISSIONS" ) },
            { tab_mode::TAB_FAILED, _( "FAILED MISSIONS" ) },
        };
        draw_tabs( w_missions, tabs, tab );
        draw_border_below_tabs( w_missions );

        mvwputch( w_missions, point( 30, 2 ), BORDER_COLOR,
                  tab == tab_mode::TAB_COMPLETED ? ' ' : LINE_OXXX ); // ^|^
        mvwputch( w_missions, point( 30, FULL_SCREEN_HEIGHT - 1 ), BORDER_COLOR, LINE_XXOX ); // _|_

        draw_scrollbar( w_missions, selection, entries_per_page, umissions.size(), point( 0, 3 ) );

        for( int i = top_of_page; i <= bottom_of_page; i++ ) {
            const auto miss = umissions[i];
            const nc_color col = u.get_active_mission() == miss ? c_light_green : c_white;
            const int y = i - top_of_page + 3;
            trim_and_print( w_missions, point( 1, y ), 28,
                            static_cast<int>( selection ) == i ? hilite( col ) : col,
                            miss->name() );
        }

        if( selection < umissions.size() ) {
            const auto miss = umissions[selection];
            const nc_color col = u.get_active_mission() == miss ? c_light_green : c_white;
            std::string for_npc;
            if( miss->get_npc_id().is_valid() ) {
                npc *guy = g->find_npc( miss->get_npc_id() );
                if( guy ) {
                    for_npc = string_format( _( " for %s" ), guy->disp_name() );
                }
            }

            int y = 3;
            y += fold_and_print( w_missions, point( 31, y ), getmaxx( w_missions ) - 33, col,
                                 miss->name() + for_npc );

            auto format_tokenized_description = []( const std::string & description,
            const std::vector<std::pair<int, itype_id>> &rewards ) {
                std::string formatted_description = description;
                for( const auto &reward : rewards ) {
                    std::string token = "<reward_count:" + reward.second.str() + ">";
                    formatted_description = replace_all( formatted_description, token,
                                                         string_format( "%d", reward.first ) );
                }
                return formatted_description;
            };

            y++;
            if( !miss->get_description().empty() ) {
                y += fold_and_print( w_missions, point( 31, y ), getmaxx( w_missions ) - 33, c_white,
                                     format_tokenized_description( miss->get_description(), miss->get_likely_rewards() ) );
            }
            if( miss->has_deadline() ) {
                const time_point deadline = miss->get_deadline();
                mvwprintz( w_missions, point( 31, ++y ), c_white, _( "Deadline: %s" ), to_string( deadline ) );

                if( tab != tab_mode::TAB_COMPLETED ) {
                    // There's no point in displaying this for a completed mission.
                    // @ TODO: But displaying when you completed it would be useful.
                    const time_duration remaining = deadline - calendar::turn;
                    std::string remaining_time;

                    if( remaining <= 0_turns ) {
                        remaining_time = _( "None!" );
                    } else if( u.has_watch() ) {
                        remaining_time = to_string( remaining );
                    } else {
                        remaining_time = to_string_approx( remaining );
                    }

                    mvwprintz( w_missions, point( 31, ++y ), c_white, _( "Time remaining: %s" ), remaining_time );
                }
            }
            if( miss->has_target() ) {
                const tripoint_abs_omt pos = u.abs_omt_pos();
                // TODO: target does not contain a z-component, targets are assumed to be on z=0
                mvwprintz( w_missions, point( 31, ++y ), c_white, _( "Target: %s   You: %s" ),
                           miss->get_target().to_string(), pos.to_string() );
            }
        } else {
            static const std::map< tab_mode, std::string > nope = {
                { tab_mode::TAB_ACTIVE, translate_marker( "You have no active missions!" ) },
                { tab_mode::TAB_COMPLETED, translate_marker( "You haven't completed any missions!" ) },
                { tab_mode::TAB_FAILED, translate_marker( "You haven't failed any missions!" ) }
            };
            mvwprintz( w_missions, point( 31, 4 ), c_light_red, _( nope.at( tab ) ) );
        }

        wnoutrefresh( w_missions );
    } );

    while( true ) {
        umissions.clear();
        if( tab < tab_mode::FIRST_TAB || tab >= tab_mode::NUM_TABS ) {
            debugmsg( "The sanity check failed because tab=%d", static_cast<int>( tab ) );
            tab = tab_mode::FIRST_TAB;
        }
        switch( tab ) {
            case tab_mode::TAB_ACTIVE:
                umissions = u.get_active_missions();
                break;
            case tab_mode::TAB_COMPLETED:
                umissions = u.get_completed_missions();
                break;
            case tab_mode::TAB_FAILED:
                umissions = u.get_failed_missions();
                break;
            default:
                break;
        }
        if( ( !umissions.empty() && selection >= umissions.size() ) ||
            ( umissions.empty() && selection != 0 ) ) {
            debugmsg( "Sanity check failed: selection=%d, size=%d", static_cast<int>( selection ),
                      static_cast<int>( umissions.size() ) );
            selection = 0;
        }
        ui_manager::redraw();
        const std::string action = ctxt.handle_input();
#if defined(TILES)
        if( const auto pick = native ? cata::godot_bridge::take_pick( &u ) : std::nullopt ) {
            namespace gs = cata::godot_screen;
            if( *pick >= gs::tab_pick && *pick < gs::tab_pick + static_cast<int>( tab_mode::NUM_TABS ) ) {
                tab = static_cast<tab_mode>( *pick - gs::tab_pick );
                selection = 0;
                continue;
            }
            if( *pick >= 0 && static_cast<size_t>( *pick ) < umissions.size() ) {
                selection = static_cast<size_t>( *pick );
            }
        }
#endif
        if( action == "RIGHT" ) {
            tab = static_cast<tab_mode>( static_cast<int>( tab ) + 1 );
            if( tab >= tab_mode::NUM_TABS ) {
                tab = tab_mode::FIRST_TAB;
            }
            selection = 0;
        } else if( action == "LEFT" ) {
            tab = static_cast<tab_mode>( static_cast<int>( tab ) - 1 );
            if( tab < tab_mode::FIRST_TAB ) {
                tab = tab_mode::LAST_TAB;
            }
            selection = 0;
        } else if( action == "DOWN" ) {
            selection++;
            if( selection >= umissions.size() ) {
                selection = 0;
            }
        } else if( action == "UP" ) {
            if( selection == 0 ) {
                selection = umissions.empty() ? 0 : umissions.size() - 1;
            } else {
                selection--;
            }
        } else if( action == "CONFIRM" ) {
            if( tab == tab_mode::TAB_ACTIVE && selection < umissions.size() ) {
                u.set_active_mission( *umissions[selection] );
            }
            break;
        } else if( action == "QUIT" ) {
            break;
        }
    }
}
