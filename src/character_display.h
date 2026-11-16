#pragma once

#include <vector>

#include "character_stat.h"
#if defined(TILES)
#include "godot_screen.h"
#endif

class Character;
class item;
class avatar;
class ui_adaptor;

namespace catacurses
{
class window;
} // namespace catacurses

namespace character_display
{

/**
 * Formats and prints encumbrance info to specified window
 */
void print_encumbrance( ui_adaptor &ui, const catacurses::window &win, const Character &ch,
                        int line = -1,
                        const item *selected_clothing = nullptr );

/**
 * @brief Handles and displays detailed character info for the '@' screen.
 *
 * @param ch Character to display info for. Has to be non-const reference
 * to allow toggling skills and upgrading stats for stats-through-x mods.
 */
void disp_info( Character &ch );

/**
 * Handles upgrade of avatar stats.
 */
void upgrade_stat_prompt( avatar &you, const character_stat &stat );

/** Gets the minimum combined bare-handed damage from skill, bionics, and mutations for display functions */
int display_empty_handed_base_damage( const Character &you );

#if defined(TILES)
/// What `print_encumbrance` shows, as rows for a Godot screen: each body part's encumbrance,
/// layering penalty and warmth. Parts `selected_clothing` covers are green.
auto encumbrance_rows( const Character &ch,
                       const item *selected_clothing = nullptr ) -> std::vector<cata::godot_screen::row>;
#endif

} // namespace character_display



