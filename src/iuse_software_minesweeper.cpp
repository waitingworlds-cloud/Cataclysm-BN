#include "iuse_software_minesweeper.h"

#include <algorithm>
#include <array>
#include <functional>
#include <memory>
#include <optional>
#include <string>
#include <vector>

#include "catacharset.h"
#include "color.h"
#include "cursesdef.h"
#if defined(TILES)
#include "godot_bridge.h"
#include "godot_screen.h"
#endif
#include "input.h"
#include "output.h"
#include "point.h"
#include "rng.h"
#include "string_formatter.h"
#include "string_input_popup.h"
#include "translations.h"
#include "ui.h"
#include "ui_manager.h"

minesweeper_game::minesweeper_game()
{
    min = point( 8, 8 );
    max = point_zero;
    offset = point_zero;
}

void minesweeper_game::new_level()
{
    auto set_num = [&]( const std::string & sType, int &iVal, const int iMin, const int iMax ) {
        const std::string desc = string_format( _( "Min: %d Max: %d" ), iMin, iMax );

        do {
            if( iVal < iMin || iVal > iMax ) {
                iVal = iMin;
            }

            string_input_popup()
            .title( sType )
            .width( 5 )
            .description( desc )
            .edit( iVal );
        } while( iVal < iMin || iVal > iMax );
    };

    uilist difficulty;
    difficulty.allow_cancel = false;
    difficulty.text = _( "Game Difficulty" );
    difficulty.entries.emplace_back( 0, true, 'b', _( "Beginner" ) );
    difficulty.entries.emplace_back( 1, true, 'i', _( "Intermediate" ) );
    difficulty.entries.emplace_back( 2, true, 'e', _( "Expert" ) );
    difficulty.entries.emplace_back( 3, true, 'c', _( "Custom" ) );
    difficulty.query();

    switch( difficulty.ret ) {
        case 0:
            level = point( 8, 8 );
            iBombs = 10;
            break;
        case 1:
            level = point( 16, 16 );
            iBombs = 40;
            break;
        case 2:
            level = point( 30, 16 );
            iBombs = 99;
            break;
        case 3:
        default:
            point new_level = min;

            set_num( _( "Level width:" ), new_level.x, min.x, max.x );
            set_num( _( "Level height:" ), new_level.y, min.y, max.y );

            const int area = new_level.x * new_level.y;
            int new_ibombs = area * 0.1;

            set_num( _( "Number of bombs:" ), new_ibombs, new_ibombs, area * 0.6 );

            level = new_level;
            iBombs = new_ibombs;
            break;
    }

    // NOLINTNEXTLINE(cata-use-named-point-constants)
    offset = ( max - level ) / 2 + point( 1, 1 );

    mLevel.clear();
    mLevelReveal.clear();

    int iRandX;
    int iRandY;
    for( int i = 0; i < iBombs; i++ ) {
        do {
            iRandX = rng( 0, level.x - 1 );
            iRandY = rng( 0, level.y - 1 );
        } while( mLevel[iRandY][iRandX] == bomb );

        mLevel[iRandY][iRandX] = bomb;
    }

    for( int y = 0; y < level.y; y++ ) {
        for( int x = 0; x < level.x; x++ ) {
            if( mLevel[y][x] == bomb ) {
                for( point p : closest_points_first<point>( {x, y}, 1 ) ) {
                    if( p.x >= 0 && p.x < level.x && p.y >= 0 && p.y < level.y ) {
                        if( mLevel[p.y][p.x] != bomb ) {
                            mLevel[p.y][p.x]++;
                        }
                    }
                }
            }
        }
    }
}

bool minesweeper_game::check_win()
{
    for( int y = 0; y < level.y; y++ ) {
        for( int x = 0; x < level.x; x++ ) {
            if( ( mLevelReveal[y][x] == flag || mLevelReveal[y][x] == unknown ) &&
                mLevel[y][x] != bomb ) {
                return false;
            }
        }
    }

    return true;
}

int minesweeper_game::start_game()
{
    catacurses::window w_minesweeper_border;
    catacurses::window w_minesweeper;

    ui_adaptor ui;
#if defined(TILES)
    // Godot draws the field as a board of squares: click to dig, right click to flag.
    auto native = cata::godot_bridge::native_screens() ?
                  std::make_unique<cata::godot_bridge::native_view>( "screen", this, "MINESWEEPER" ) : nullptr;
    if( native ) {
        native->attach( ui );
    }
#endif
    ui.on_screen_resize( [&]( ui_adaptor & ui ) {
        const point iCenter( TERMX > FULL_SCREEN_WIDTH ? ( TERMX - FULL_SCREEN_WIDTH ) / 2 : 0,
                             TERMY > FULL_SCREEN_HEIGHT ? ( TERMY - FULL_SCREEN_HEIGHT ) / 2 : 0 );

        w_minesweeper_border = catacurses::newwin( FULL_SCREEN_HEIGHT, FULL_SCREEN_WIDTH,
                               iCenter );
        w_minesweeper = catacurses::newwin( FULL_SCREEN_HEIGHT - 2, FULL_SCREEN_WIDTH - 2,
                                            iCenter + point_south_east );
        max = point( FULL_SCREEN_WIDTH - 4, FULL_SCREEN_HEIGHT - 4 );
        ui.position_from_window( w_minesweeper_border );
#if defined(TILES)
        if( native ) {
            w_minesweeper_border = cata::godot_bridge::capture_window( FULL_SCREEN_HEIGHT, FULL_SCREEN_WIDTH );
            w_minesweeper = cata::godot_bridge::capture_window( FULL_SCREEN_HEIGHT - 2, FULL_SCREEN_WIDTH - 2 );
            ui.position( point_zero, point_zero );
        }
#endif
    } );
    ui.mark_resize();

    input_context ctxt( "MINESWEEPER" );
    ctxt.register_cardinal();
    ctxt.register_action( "NEW" );
    ctxt.register_action( "FLAG" );
    ctxt.register_action( "CONFIRM" );
    ctxt.register_action( "QUIT" );
    ctxt.register_action( "HELP_KEYBINDINGS" );

    static const std::array<nc_color, 9> aColors = {{
            c_white,
            c_light_gray,
            c_cyan,
            c_blue,
            c_light_blue,
            c_green,
            c_magenta,
            c_red,
            c_yellow
        }
    };

    int iScore = 5;

    point pl;

    bool started = false;
    bool boom = false;
    ui.on_redraw( [&]( const ui_adaptor & ) {
        werase( w_minesweeper_border );
        draw_border( w_minesweeper_border );

        std::vector<std::string> shortcuts;
        shortcuts.emplace_back( _( "<n>ew level" ) );
        shortcuts.emplace_back( _( "<f>lag" ) );
        shortcuts.emplace_back( _( "<q>uit" ) );

        int iWidth = 0;
        for( auto &shortcut : shortcuts ) {
            if( iWidth > 0 ) {
                iWidth += 1;
            }
            iWidth += utf8_width( shortcut );
        }

        int iPos = FULL_SCREEN_WIDTH - iWidth - 1;
        for( auto &shortcut : shortcuts ) {
            shortcut_print( w_minesweeper_border, point( iPos, 0 ), c_white, c_light_green, shortcut );
            iPos += utf8_width( shortcut ) + 1;
        }

        mvwputch( w_minesweeper_border, point( 2, 0 ), hilite( c_white ), _( "Minesweeper" ) );

        wnoutrefresh( w_minesweeper_border );

        if( !started ) {
            return;
        }

        werase( w_minesweeper );
        draw_custom_border( w_minesweeper, 1, 1, 1, 1, 1, 1, 1, 1, BORDER_COLOR,
                            // NOLINTNEXTLINE(cata-use-named-point-constants)
                            offset + point( -1, -1 ), level.y + 2, level.x + 2 );
        for( int y = 0; y < level.y; ++y ) {
            for( int x = 0; x < level.x; ++x ) {
                char ch = '?';
                nc_color col = c_red;
                const int num = mLevel[y][x];
                switch( mLevelReveal[y][x] ) {
                    case unknown:
                        if( boom && num == bomb ) {
                            ch = '*';
                            col = h_red;
                        } else {
                            ch = '#';
                            col = c_white;
                        }
                        break;
                    case flag:
                        ch = '!';
                        if( boom && num == bomb ) {
                            col = h_red;
                        } else {
                            col = c_yellow;
                        }
                        break;
                    case seen: {
                        if( num == bomb ) {
                            ch = '*';
                            col = boom ? h_red : c_red;
                        } else if( num == 0 ) {
                            ch = ' ';
                            col = aColors[num];
                        } else if( num >= 1 && num <= 8 ) {
                            ch = '0' + num;
                            col = aColors[num];
                        }
                        break;
                    }
                }
                if( !boom && pl == point( x, y ) ) {
                    col = hilite( col );
                }
                mvwputch( w_minesweeper, offset + point( x, y ), col, ch );
            }
        }
        wnoutrefresh( w_minesweeper );
#if defined(TILES)
        if( native ) {
            namespace gs = cata::godot_screen;
            const auto category = std::string( "MINESWEEPER" );
            native->publish( [&]( JsonOut & jsout ) {
                jsout.member( "title", _( "Minesweeper" ) );
                jsout.member( "icon", "bomb" );
                jsout.member( "size", std::array{ std::clamp( level.x * 36 + 460, 900, 1500 ), std::clamp( level.y * 36 + 260, 600, 940 ) } );
                jsout.member( "stats" );
                jsout.start_array();
                gs::write_stat( jsout, { .icon = "bomb", .label = _( "Mines" ), .value = { .text = std::to_string( iBombs ), .color = c_white } } );
                jsout.end_array();
                jsout.member( "panes" );
                jsout.start_array();
                jsout.start_object();
                jsout.member( "cell", 34 );
                jsout.member( "square", true );
                jsout.member( "raised", "#!" );
                jsout.member( "hide", "#" );
                jsout.member( "click", "CONFIRM" );
                jsout.member( "right_click", "FLAG" );
                jsout.member( "grid" );
                cata::godot_bridge::write_window_grid( jsout, w_minesweeper, { .at = offset, .size = level } );
                jsout.end_object();
                jsout.end_array();
                jsout.member( "aside" );
                jsout.start_object();
                jsout.member( "width", 340 );
                jsout.member( "body" );
                gs::write_span( jsout, { .text = _( "Click a square to dig it up, or right click to flag it." ) } );
                jsout.member( "buttons" );
                jsout.start_array();
                gs::write_button( jsout, { .act = "CONFIRM", .text = _( "Dig" ), .icon = "shovel", .category = category, .primary = true } );
                gs::write_button( jsout, { .act = "FLAG", .text = _( "Flag" ), .icon = "flag", .category = category } );
                gs::write_button( jsout, { .act = "NEW", .text = _( "New level" ), .icon = "rotate-ccw", .category = category } );
                jsout.end_array();
                jsout.end_object();
                jsout.member( "hints" );
                jsout.start_array();
                gs::write_fixed_hint( jsout, "↑↓←→", _( "Move" ) );
                gs::write_hint( jsout, "CONFIRM", category, _( "Dig" ) );
                gs::write_hint( jsout, "FLAG", category, _( "Flag" ) );
                gs::write_hint( jsout, "NEW", category, _( "New level" ) );
                gs::write_hint( jsout, "QUIT", category, _( "Quit" ) );
                jsout.end_array();
            } );
        }
#endif
    } );

    std::function<void ( point )> rec_reveal = [&]( point  pt ) {
        if( mLevelReveal[pt.y][pt.x] == unknown || mLevelReveal[pt.y][pt.x] == flag ) {
            mLevelReveal[pt.y][pt.x] = seen;

            if( mLevel[pt.y][pt.x] == 0 ) {
                for( point p : closest_points_first( pt, 1 ) ) {
                    if( p.x >= 0 && p.x < level.x && p.y >= 0 && p.y < level.y ) {
                        if( mLevelReveal[p.y][p.x] != seen ) {
                            rec_reveal( p );
                        }
                    }
                }
            }
        }
    };

    const auto &reveal_all = [&]() {
        for( int y = 0; y < level.y; ++y ) {
            for( int x = 0; x < level.x; ++x ) {
                if( mLevelReveal[y][x] == unknown || ( mLevelReveal[y][x] == flag && mLevel[y][x] != bomb ) ) {
                    mLevelReveal[y][x] = seen;
                }
            }
        }
    };

    std::string action = "NEW";

    do {
        if( action == "NEW" ) {
            new_level();

            pl = point_zero;

            started = true;
            boom = false;
        }

        if( check_win() ) {
            reveal_all();
            ui.invalidate_ui();
            popup_top( _( "Congratulations, you won!" ) );

            iScore = 30;

            action = "QUIT";
        } else {
            ui_manager::redraw();
            action = ctxt.handle_input();
#if defined(TILES)
            // A clicked square: `row * 1000 + column`.
            if( const auto pick = native ? cata::godot_bridge::take_pick( this ) : std::nullopt ) {
                pl = point( std::clamp( *pick % 1000, 0, level.x - 1 ), std::clamp( *pick / 1000, 0,
                            level.y - 1 ) );
            }
#endif
        }

        if( const std::optional<tripoint_rel_ms> vec = ctxt.get_direction( action ) ) {
            const point newp = pl + vec->xy().raw();
            if( half_open_rectangle<point>( point_zero, level ).contains( newp ) ) {
                pl = newp;
            }
        } else if( action == "FLAG" ) {
            if( mLevelReveal[pl.y][pl.x] == unknown ) {
                mLevelReveal[pl.y][pl.x] = flag;
            } else if( mLevelReveal[pl.y][pl.x] == flag ) {
                mLevelReveal[pl.y][pl.x] = unknown;
            }
        } else if( action == "CONFIRM" ) {
            if( mLevelReveal[pl.y][pl.x] != seen ) {
                if( mLevel[pl.y][pl.x] == bomb ) {
                    boom = true;
                    reveal_all();
                    ui.invalidate_ui();
                    popup_top( _( "Boom, you're dead!  Better luck next time." ) );
                    action = "QUIT";
                } else if( mLevelReveal[pl.y][pl.x] == unknown ) {
                    rec_reveal( pl );
                }
            }
        }
    } while( action != "QUIT" );

    return iScore;
}

