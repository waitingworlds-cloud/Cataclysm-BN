#include "iuse_software_sokoban.h"

#include <algorithm>
#include <array>
#include <cstdlib>
#include <functional>
#include <memory>
#include <optional>
#include <stdexcept>

#include "cata_utility.h"
#include "catacharset.h"
#include "color.h"
#include "cursesdef.h"
#include "fstream_utils.h"
#if defined(TILES)
#include "godot_bridge.h"
#include "godot_screen.h"
#endif
#include "input.h"
#include "output.h"
#include "path_info.h"
#include "point.h"
#include "string_formatter.h"
#include "translations.h"
#include "ui_manager.h"

#if defined(TILES)
namespace
{

/// The move from `from` toward a clicked square, along the longer way, or none for the same square.
auto step_action( const point from, const point to ) -> std::string
{
    const auto d = to - from;
    if( d == point_zero ) {
        return {};
    }
    if( std::abs( d.x ) >= std::abs( d.y ) ) {
        return d.x < 0 ? "LEFT" : "RIGHT";
    }
    return d.y < 0 ? "UP" : "DOWN";
}

} // namespace
#endif

sokoban_game::sokoban_game() = default;

void sokoban_game::print_score( const catacurses::window &w_sokoban, int iScore, int iMoves )
{
    mvwprintz( w_sokoban, point( 3, 1 ), c_white, _( "Level: %d/%d" ), iCurrentLevel + 1, iNumLevel );
    wprintw( w_sokoban, "    " );

    mvwprintz( w_sokoban, point( 3, 2 ), c_white, _( "Score: %d" ), iScore );

    mvwprintz( w_sokoban, point( 3, 3 ), c_white, _( "Moves: %d" ), iMoves );
    wprintw( w_sokoban, "    " );

    mvwprintz( w_sokoban, point( 3, 4 ), c_white, _( "Total moves: %d" ), iTotalMoves );
}

void sokoban_game::parse_level( std::istream &fin )
{
    /*
    # Wall
    $ Package
    space Floor
    . Goal
    * Package on Goal
    @ Sokoban
    + Sokoban on Goal
    */

    iCurrentLevel = 0;
    iNumLevel = 0;

    vLevel.clear();
    vUndo.clear();
    vLevelDone.clear();

    std::string sLine;
    while( !fin.eof() ) {
        safe_getline( fin, sLine );

        if( sLine.substr( 0, 3 ) == "; #" ) {
            iNumLevel++;
            continue;
        } else if( sLine[0] == ';' ) {
            continue;
        }

        if( sLine.empty() ) {
            //Find level start
            vLevel.resize( iNumLevel + 1 );
            vLevelDone.resize( iNumLevel + 1 );
            mLevelInfo[iNumLevel]["MaxLevelY"] = 0;
            mLevelInfo[iNumLevel]["MaxLevelX"] = 0;
            mLevelInfo[iNumLevel]["PlayerY"] = 0;
            mLevelInfo[iNumLevel]["PlayerX"] = 0;
            continue;
        }

        if( mLevelInfo[iNumLevel]["MaxLevelX"] < sLine.length() ) {
            mLevelInfo[iNumLevel]["MaxLevelX"] = sLine.length();
        }

        for( size_t i = 0; i < sLine.length(); i++ ) {
            if( sLine[i] == '@' ) {
                if( mLevelInfo[iNumLevel]["PlayerY"] == 0 && mLevelInfo[iNumLevel]["PlayerX"] == 0 ) {
                    mLevelInfo[iNumLevel]["PlayerY"] = mLevelInfo[iNumLevel]["MaxLevelY"];
                    mLevelInfo[iNumLevel]["PlayerX"] = i;
                } else {
                    // TODO: describe why it's invalid
                    throw std::runtime_error( "invalid content of sokoban file" );
                }
            }

            if( sLine[i] == '.' || sLine[i] == '*' || sLine[i] == '+' ) {
                vLevelDone[iNumLevel].emplace_back( static_cast<int>
                                                    ( mLevelInfo[iNumLevel]["MaxLevelY"] ), static_cast<int>( i ) );
            }

            vLevel[iNumLevel][mLevelInfo[iNumLevel]["MaxLevelY"]][i] = sLine[i];
        }

        mLevelInfo[iNumLevel]["MaxLevelY"]++;
    }
}

int sokoban_game::get_wall_connection( point i )
{
    bool bTop = false;
    bool bRight = false;
    bool bBottom = false;
    bool bLeft = false;

    if( mLevel[i.y - 1][i.x] == "#" ) {
        bTop = true;
    }

    if( mLevel[i.y][i.x + 1] == "#" ) {
        bRight = true;
    }

    if( mLevel[i.y + 1][i.x] == "#" ) {
        bBottom = true;
    }

    if( mLevel[i.y][i.x - 1] == "#" ) {
        bLeft = true;
    }

    if( !bRight && !bLeft ) {
        return LINE_XOXO; //

    } else if( !bTop && !bBottom ) {
        return LINE_OXOX;

    } else if( bTop && bRight && !bBottom && !bLeft ) {
        return LINE_XXOO;

    } else if( !bTop && bRight && bBottom && !bLeft ) {
        return LINE_OXXO;

    } else if( !bTop && !bRight && bBottom && bLeft ) {
        return LINE_OOXX;

    } else if( bTop && !bRight && !bBottom && bLeft ) {
        return LINE_XOOX;

    } else if( bTop && bRight && bBottom && !bLeft ) {
        return LINE_XXXO;

    } else if( bTop && bRight && !bBottom && bLeft ) {
        return LINE_XXOX;

    } else if( bTop && !bRight && bBottom && bLeft ) {
        return LINE_XOXX;

    } else if( !bTop && bRight && bBottom && bLeft ) {
        return LINE_OXXX;

    } else if( bTop && bRight && bBottom && bLeft ) {
        return LINE_XXXX;
    }

    return '#';
}

void sokoban_game::draw_level( const catacurses::window &w_sokoban )
{
    const point iOffset( ( FULL_SCREEN_WIDTH - 2 - mLevelInfo[iCurrentLevel]["MaxLevelX"] ) / 2,
                         ( FULL_SCREEN_HEIGHT - 2 - mLevelInfo[iCurrentLevel]["MaxLevelY"] ) / 2 );

    for( auto &elem : mLevel ) {
        for( std::map<int, std::string>::iterator iterX = elem.second.begin();
             iterX != elem.second.end(); ++iterX ) {
            std::string sTile = iterX->second;

            if( sTile == "#" ) {
                mvwputch( w_sokoban, iOffset + point( iterX->first, elem.first ),
                          c_white, get_wall_connection( point( iterX->first, elem.first ) ) );

            } else {
                nc_color cCol = c_white;

                if( sTile == "." || sTile == "*" ||  sTile == "+" ) {
                    cCol = red_background( c_white );
                }

                if( sTile == "." ) {
                    sTile = " ";
                }

                if( sTile == "*" ) {
                    sTile = "$";
                }

                if( sTile == "+" ) {
                    sTile = "@";
                }

                mvwprintz( w_sokoban, iOffset + point( iterX->first, elem.first ), cCol, sTile );
            }
        }
    }
}

bool sokoban_game::check_win()
{
    for( auto &elem : vLevelDone[iCurrentLevel] ) {
        if( mLevel[elem.first][elem.second] != "*" ) {
            return false;
        }
    }
    return true;
}

int sokoban_game::start_game()
{
    int iScore = 0;
    int iMoves = 0;
    iTotalMoves = 0;

    point dir;

    using namespace std::placeholders;
    read_from_file( PATH_INFO::sokoban(), std::bind( &sokoban_game::parse_level, this, _1 ) );

    catacurses::window w_sokoban;
    ui_adaptor ui;
#if defined(TILES)
    // Godot draws the level as a board; clicking a square steps toward it.
    auto native = cata::godot_bridge::native_screens() ?
                  std::make_unique<cata::godot_bridge::native_view>( "screen", this, "SOKOBAN" ) : nullptr;
    if( native ) {
        native->attach( ui );
    }
#endif
    ui.on_screen_resize( [&]( ui_adaptor & ) {
        const point iOffset( TERMX > FULL_SCREEN_WIDTH ? ( TERMX - FULL_SCREEN_WIDTH ) / 2 : 0,
                             TERMY > FULL_SCREEN_HEIGHT ? ( TERMY - FULL_SCREEN_HEIGHT ) / 2 : 0 );
        w_sokoban = catacurses::newwin( FULL_SCREEN_HEIGHT, FULL_SCREEN_WIDTH,
                                        iOffset );
        ui.position_from_window( w_sokoban );
#if defined(TILES)
        if( native ) {
            w_sokoban = cata::godot_bridge::capture_window( FULL_SCREEN_HEIGHT, FULL_SCREEN_WIDTH );
            ui.position( point_zero, point_zero );
        }
#endif
    } );
    ui.mark_resize();

    input_context ctxt( "SOKOBAN" );
    ctxt.register_cardinal();
    ctxt.register_action( "NEXT" );
    ctxt.register_action( "PREV" );
    ctxt.register_action( "RESET" );
    ctxt.register_action( "QUIT" );
    ctxt.register_action( "UNDO" );
    ctxt.register_action( "HELP_KEYBINDINGS" );

#if defined(TILES)
    // The level alone; its counters become stats and its shortcuts buttons.
    const auto publish_native = [&]() {
        namespace gs = cata::godot_screen;
        const auto category = std::string( "SOKOBAN" );
        const auto level_size = point( static_cast<int>( mLevelInfo[iCurrentLevel]["MaxLevelX"] ),
                                       static_cast<int>( mLevelInfo[iCurrentLevel]["MaxLevelY"] ) );
        const auto level_at = point( ( FULL_SCREEN_WIDTH - 2 - level_size.x ) / 2,
                                     ( FULL_SCREEN_HEIGHT - 2 - level_size.y ) / 2 );
        native->publish( [&]( JsonOut & jsout ) {
            jsout.member( "title", _( "Sokoban" ) );
            jsout.member( "icon", "package" );
            jsout.member( "size", std::array{ 1180, 780 } );
            jsout.member( "stats" );
            jsout.start_array();
            gs::write_stat( jsout, { .icon = "layers", .label = _( "Level" ), .value = { .text = string_format( "%d/%d", iCurrentLevel + 1, iNumLevel ), .color = c_white } } );
            gs::write_stat( jsout, { .icon = "trophy", .label = _( "Score" ), .value = { .text = std::to_string( iScore ), .color = c_white } } );
            gs::write_stat( jsout, { .icon = "footprints", .label = _( "Moves" ), .value = { .text = std::to_string( iMoves ), .color = c_white } } );
            gs::write_stat( jsout, { .label = _( "Total moves" ), .value = { .text = std::to_string( iTotalMoves ), .color = c_light_gray } } );
            jsout.end_array();
            jsout.member( "panes" );
            jsout.start_array();
            jsout.start_object();
            jsout.member( "cell", 36 );
            jsout.member( "square", true );
            jsout.member( "raised", "$" );
            jsout.member( "click", "" );
            jsout.member( "grid" );
            cata::godot_bridge::write_window_grid( jsout, w_sokoban, { .at = level_at, .size = level_size } );
            jsout.end_object();
            jsout.end_array();
            jsout.member( "aside" );
            jsout.start_object();
            jsout.member( "width", 380 );
            jsout.member( "body" );
            gs::write_span( jsout, { .text = _( "You are <color_white>@</color>.  Push every crate <color_white>$</color> onto a highlighted goal square.  Click a square to step toward it." ) } );
            jsout.member( "buttons" );
            jsout.start_array();
            gs::write_button( jsout, { .act = "UNDO", .text = _( "Undo move" ), .icon = "undo-2", .category = category, .primary = true } );
            gs::write_button( jsout, { .act = "RESET", .text = _( "Reset" ), .icon = "rotate-ccw", .category = category } );
            gs::write_button( jsout, { .act = "PREV", .text = _( "Previous level" ), .icon = "skip-back", .category = category } );
            gs::write_button( jsout, { .act = "NEXT", .text = _( "Next level" ), .icon = "skip-forward", .category = category } );
            jsout.end_array();
            jsout.end_object();
            jsout.member( "hints" );
            jsout.start_array();
            gs::write_fixed_hint( jsout, "↑↓←→", _( "Move" ) );
            gs::write_hint( jsout, "UNDO", category, _( "Undo move" ) );
            gs::write_hint( jsout, "RESET", category, _( "Reset" ) );
            gs::write_hint( jsout, "PREV", category, _( "Previous level" ) );
            gs::write_hint( jsout, "NEXT", category, _( "Next level" ) );
            gs::write_hint( jsout, "QUIT", category, _( "Quit" ) );
            jsout.end_array();
        } );
    };
#endif

    ui.on_redraw( [&]( const ui_adaptor & ) {
        werase( w_sokoban );
        draw_border( w_sokoban, BORDER_COLOR, _( "Sokoban" ), hilite( c_white ) );

        std::vector<std::string> shortcuts;
        shortcuts.emplace_back( _( "<+> next" ) ); // '+': next
        shortcuts.emplace_back( _( "<-> prev" ) ); // '-': prev
        shortcuts.emplace_back( _( "<r>eset" ) ); // 'r': reset
        shortcuts.emplace_back( _( "<q>uit" ) ); // 'q': quit
        shortcuts.emplace_back( _( "<u>ndo move" ) ); // 'u': undo move

        int indent = 10;
        for( auto &shortcut : shortcuts ) {
            indent = std::max( indent, utf8_width( shortcut ) + 1 );
        }
        indent = std::min( indent, 30 );

        for( size_t i = 0; i < shortcuts.size(); i++ ) {
            shortcut_print( w_sokoban, point( FULL_SCREEN_WIDTH - indent, i + 1 ),
                            c_white, c_light_green, shortcuts[i] );
        }

        print_score( w_sokoban, iScore, iMoves );

        draw_level( w_sokoban );
        wnoutrefresh( w_sokoban );
#if defined(TILES)
        if( native ) {
            publish_native();
        }
#endif
    } );

    point pl;

    bool bNewLevel = true;
    bool bMoved = false;
    do {
        if( bNewLevel ) {
            bNewLevel = false;

            iMoves = 0;
            vUndo.clear();

            pl.y = mLevelInfo[iCurrentLevel]["PlayerY"];
            pl.x = mLevelInfo[iCurrentLevel]["PlayerX"];
            mLevel = vLevel[iCurrentLevel];
        }

        std::string action;
        if( check_win() ) {
            //we won yay
            if( !mAlreadyWon[iCurrentLevel] ) {
                iScore += 500;
                mAlreadyWon[iCurrentLevel] = true;
            }
            action = "NEXT";

        } else {
            ui_manager::redraw();
            //Check input
            action = ctxt.handle_input();
#if defined(TILES)
            // A clicked square: `row * 1000 + column` of the level.
            if( const auto pick = native ? cata::godot_bridge::take_pick( this ) : std::nullopt ) {
                action = step_action( pl, point( *pick % 1000, *pick / 1000 ) );
            }
#endif
        }

        bMoved = false;
        if( const std::optional<tripoint_rel_ms> vec = ctxt.get_direction( action ) ) {
            dir = vec->xy().raw();
            bMoved = true;
        } else if( action == "QUIT" ) {
            return iScore;
        } else if( action == "UNDO" ) {
            point pl_new;
            bool bUndoSkip = false;
            //undo move
            if( !vUndo.empty() ) {
                //reset last player pos
                mLevel[pl.y][pl.x] = mLevel[pl.y][pl.x] == "+" ? "." : " ";
                pl_new = vUndo[vUndo.size() - 1].old;
                mLevel[pl_new.y][pl_new.x] = vUndo[vUndo.size() - 1].sTileOld;

                vUndo.pop_back();

                bUndoSkip = true;
            }

            if( bUndoSkip && !vUndo.empty() ) {
                dir = vUndo[vUndo.size() - 1].old;

                if( vUndo[vUndo.size() - 1].sTileOld == "$" ||
                    vUndo[vUndo.size() - 1].sTileOld == "*" ) {
                    mLevel[pl.y][pl.x] = mLevel[pl.y][pl.x] == "." ? "*" : "$";
                    point np = pl + dir;
                    mLevel[np.y][np.x] = mLevel[np.y][np.x] == "*" ?
                                         "." : " ";

                    vUndo.pop_back();
                }
            }

            if( bUndoSkip ) {
                pl = pl_new;
            }
        } else if( action == "RESET" ) {
            //reset level
            bNewLevel = true;
        } else if( action == "NEXT" ) {
            //next level
            iCurrentLevel++;
            if( iCurrentLevel >= iNumLevel ) {
                iCurrentLevel = 0;
            }
            bNewLevel = true;
        } else if( action == "PREV" ) {
            //previous level
            iCurrentLevel--;
            if( iCurrentLevel < 0 ) {
                iCurrentLevel = iNumLevel - 1;
            }
            bNewLevel = true;
        }

        if( bMoved ) {
            //check if we can move the player
            std::string sMoveTo = mLevel[pl.y + dir.y][pl.x + dir.x];
            bool bMovePlayer = false;

            if( sMoveTo != "#" ) {
                if( sMoveTo == "$" || sMoveTo == "*" ) {
                    //Check if we can move the package
                    point p_pack = pl + dir * 2;
                    std::string sMovePackTo = mLevel[p_pack.y][p_pack.x];
                    if( sMovePackTo == "." || sMovePackTo == " " ) {
                        //move both
                        bMovePlayer = true;
                        mLevel[p_pack.y][p_pack.x] = sMovePackTo == "." ? "*" : "$";

                        vUndo.emplace_back( dir, sMoveTo );

                        iMoves--;
                    }
                } else {
                    bMovePlayer = true;
                }

                if( bMovePlayer ) {
                    //move player
                    vUndo.emplace_back( pl, mLevel[pl.y][pl.x] );

                    mLevel[pl.y][pl.x] = mLevel[pl.y][pl.x] == "+" ? "." : " ";
                    mLevel[pl.y + dir.y][pl.x + dir.x] = sMoveTo == "." || sMoveTo == "*" ? "+" : "@";

                    pl += dir;

                    iMoves++;
                    iTotalMoves++;
                }
            }
        }

    } while( true );

    return iScore;
}
