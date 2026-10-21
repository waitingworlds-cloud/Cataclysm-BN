#if defined(TILES)

#include "godot_commands.h"

#include <array>
#include <ranges>
#include <string_view>
#include <utility>
#include <vector>

#include "avatar.h"
#include "game.h"
#include "godot_bridge.h"
#include "input.h"
#include "item.h"
#include "json.h"
#include "map/map.h"
#include "vehicle/vpart_position.h"

namespace
{

struct command_group {
    std::string_view name;
    std::vector<action_id> actions;
};

/// Groups as the game's own action menu sorts them.
auto groups() -> const std::vector<command_group> & // *NOPAD*
{
    static const auto all = std::vector<command_group> {
        { .name = "Look", .actions = { ACTION_LOOK, ACTION_PEEK, ACTION_LIST_ITEMS, ACTION_ZONES, ACTION_MAP, ACTION_SKY } },
        {
            .name = "Interact", .actions = {
                ACTION_EXAMINE, ACTION_JUMP, ACTION_SMASH, ACTION_MOVE_DOWN, ACTION_MOVE_UP, ACTION_OPEN,
                ACTION_CLOSE, ACTION_CHAT, ACTION_PICKUP, ACTION_PICKUP_ALL, ACTION_PICKUP_FEET, ACTION_GRAB,
                ACTION_HAUL, ACTION_BUTCHER, ACTION_LOOT
            }
        },
        {
            .name = "Inventory", .actions = {
                ACTION_INVENTORY, ACTION_ADVANCEDINV, ACTION_SORT_ARMOR, ACTION_DIR_DROP, ACTION_DROP,
                ACTION_COMPARE, ACTION_ORGANIZE, ACTION_USE, ACTION_USE_WIELDED, ACTION_WEAR, ACTION_TAKE_OFF,
                ACTION_EAT, ACTION_OPEN_CONSUME, ACTION_READ, ACTION_WIELD, ACTION_UNLOAD, ACTION_UNLOAD_ALL,
                ACTION_MEND, ACTION_ITEMACTION
            }
        },
        {
            .name = "Combat", .actions = {
                ACTION_CYCLE_MOVE, ACTION_RESET_MOVE, ACTION_TOGGLE_RUN, ACTION_TOGGLE_CROUCH,
                ACTION_TOGGLE_PRONE, ACTION_OPEN_MOVEMENT, ACTION_FIRE, ACTION_RELOAD_ITEM,
                ACTION_RELOAD_WEAPON, ACTION_RELOAD_WIELDED, ACTION_CAST_SPELL, ACTION_CAST_LAST_SPELL,
                ACTION_SELECT_FIRE_MODE, ACTION_SELECT_DEFAULT_AMMO, ACTION_THROW, ACTION_FIRE_BURST,
                ACTION_PICK_STYLE, ACTION_AUTOATTACK, ACTION_TOGGLE_MANUAL_COMBAT_MODE,
                ACTION_TOGGLE_AUTO_TRAVEL_MODE, ACTION_TOGGLE_SAFEMODE, ACTION_TOGGLE_AUTOSAFE,
                ACTION_IGNORE_ENEMY, ACTION_WHITELIST_ENEMY, ACTION_TOGGLE_AUTO_FEATURES,
                ACTION_TOGGLE_AUTO_PULP_BUTCHER, ACTION_TOGGLE_AUTO_MINING, ACTION_TOGGLE_AUTO_FORAGING,
                ACTION_TOGGLE_AUTO_PICKUP
            }
        },
        {
            .name = "Craft", .actions = {
                ACTION_CRAFT, ACTION_RECRAFT, ACTION_LONGCRAFT, ACTION_CONSTRUCT, ACTION_DISASSEMBLE, ACTION_SALVAGE
            }
        },
        {
            .name = "Info", .actions = {
                ACTION_PL_INFO, ACTION_MISSIONS, ACTION_SCORES, ACTION_FACTIONS, ACTION_MORALE,
                ACTION_MESSAGES, ACTION_DIARY, ACTION_BIONICS, ACTION_MUTATIONS
            }
        },
        {
            .name = "Game", .actions = {
                ACTION_WAIT, ACTION_PAUSE, ACTION_SLEEP, ACTION_CONTROL_VEHICLE, ACTION_TOGGLE_THIEF_MODE,
                ACTION_CENTER, ACTION_TOGGLE_MAP_MEMORY, ACTION_ZOOM_OUT, ACTION_ZOOM_IN,
                ACTION_TOGGLE_HOUR_TIMER, ACTION_SWAP_TO_NPC, ACTION_SAVE, ACTION_QUICKSAVE,
                ACTION_QUICKLOAD, ACTION_SUICIDE, ACTION_MAIN_MENU
            }
        },
        {
            .name = "Settings", .actions = {
                ACTION_OPTIONS, ACTION_KEYBINDINGS, ACTION_AUTOPICKUP, ACTION_AUTONOTES, ACTION_SAFEMODE,
                ACTION_COLOR, ACTION_WORLD_MODS, ACTION_DISTRACTION_MANAGER, ACTION_TOGGLE_PANEL_ADM,
                ACTION_PANEL_MGMT, ACTION_TOGGLE_PIXEL_MINIMAP, ACTION_RELOAD_TILESET,
                ACTION_TOGGLE_CHARACTER_PREVIEW_CLOTHES, ACTION_DISPLAY_TILES_NO_VFX
            }
        },
        { .name = "Help", .actions = { ACTION_HELP, ACTION_OPEN_WIKI, ACTION_OPEN_HHG } },
        {
            .name = "Debug", .actions = {
                ACTION_DEBUG, ACTION_LUA_CONSOLE, ACTION_LUA_RELOAD, ACTION_TOGGLE_DEBUG_MODE,
                ACTION_DISPLAY_SCENT, ACTION_DISPLAY_SCENT_TYPE, ACTION_DISPLAY_TEMPERATURE,
                ACTION_DISPLAY_VEHICLE_AI, ACTION_DISPLAY_VISIBILITY, ACTION_DISPLAY_LIGHTING,
                ACTION_DISPLAY_RADIATION, ACTION_DISPLAY_TRANSPARENCY, ACTION_DISPLAY_OUTSIDE,
                ACTION_DISPLAY_SUBMAP_GRID, ACTION_DISPLAY_SOUND_ABSORPTION, ACTION_DISPLAY_SOUND_WALLS,
                ACTION_TOGGLE_ZONE_OVERLAY
            }
        },
    };
    return all;
}

/// Actions that apply where the player stands, as the action menu puts them first.
auto suggested() -> std::vector<action_id>
{
    auto &u = get_avatar();
    auto &here = get_map();
    auto out = std::vector<action_id> {};
    const auto add = [&]( const action_id act ) {
        if( !std::ranges::contains( out, act ) ) {
            out.push_back( act );
        }
    };
    if( here.veh_at( u.bub_pos() ) ) {
        add( ACTION_CONTROL_VEHICLE );
    }
    for( const auto &pos : here.points_in_radius( u.bub_pos(), 1 ) ) {
        if( pos == u.bub_pos() ) {
            for( const auto act : { ACTION_BUTCHER, ACTION_MOVE_UP, ACTION_MOVE_DOWN } ) {
                if( can_interact_at( act, pos ) ) {
                    add( act );
                }
            }
            if( here.has_items( pos ) ) {
                add( ACTION_PICKUP );
            }
            continue;
        }
        if( here.obstructed_by_vehicle_rotation( u.bub_pos(), pos ) ) {
            continue;
        }
        for( const auto act : { ACTION_OPEN, ACTION_CLOSE, ACTION_EXAMINE } ) {
            if( can_interact_at( act, pos ) ) {
                add( act );
            }
        }
    }
    if( !u.get_hostile_creatures( 60 ).empty() &&
        ( u.primary_weapon().is_gun() || u.primary_weapon().reach_range( u ) > 1 ) ) {
        add( ACTION_FIRE );
    }
    return out;
}

auto requested_action() -> std::optional<action_id> & // *NOPAD*
{
    static auto requested = std::optional<action_id> {};
    return requested;
}

} // namespace

auto cata::godot_commands::write( JsonOut &jsout ) -> void
{
    if( !g ) {
        return;
    }
    const auto ctxt = get_default_mode_input_context();
    jsout.member( "list" );
    jsout.start_array();
    for( const auto &group : groups() ) {
        for( const auto act : group.actions ) {
            const auto id = action_ident( act );
            jsout.start_array();
            jsout.write( id );
            jsout.write( ctxt.get_action_name( id ) );
            jsout.write( cata::godot_bridge::key_label( id, "DEFAULTMODE" ) );
            jsout.write( std::string( group.name ) );
            jsout.end_array();
        }
    }
    jsout.end_array();
    jsout.member( "suggested" );
    jsout.start_array();
    for( const auto act : suggested() ) {
        jsout.write( action_ident( act ) );
    }
    jsout.end_array();
}

auto cata::godot_commands::request( const std::string &id ) -> void
{
    const auto act = look_up_action( id );
    requested_action() = act == ACTION_NULL ? std::nullopt : std::optional<action_id>( act );
}

auto cata::godot_commands::take_requested() -> std::optional<action_id>
{
    return std::exchange( requested_action(), std::nullopt );
}

#endif // TILES
