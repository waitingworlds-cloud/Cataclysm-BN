#if defined(TILES)

#include "godot_square.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <numbers>
#include <ranges>
#include <utility>

#include "avatar.h"
#include "cata_tiles.h"
#include "color.h"
#include "creature.h"
#include "enums.h"
#include "game.h"
#include "godot_bridge.h"
#include "iexamine.h"
#include "item.h"
#include "json.h"
#include "line.h"
#include "map/field.h"
#include "map/map.h"
#include "map/mapdata.h"
#include "monster.h"
#include "options.h"
#include "output.h"
#include "sdltiles.h"
#include "string_formatter.h"
#include "string_utils.h"
#include "translations.h"
#include "trap.h"
#include "travel/travel_destination.h"
#include "vehicle/vehicle.h"
#include "vehicle/vehicle_part.h"
#include "vehicle/vpart_position.h"

namespace
{

using cata::godot_square::choice;
using cata::godot_square::option;

struct pending_request {
    std::optional<tripoint_bub_ms> target;
    std::optional<choice> what;
};

auto pending() -> pending_request & // *NOPAD*
{
    static auto request = pending_request{};
    return request;
}

auto choice_names() -> const std::array<std::pair<choice, std::string>, 11> & // *NOPAD*
{
    static const auto names = std::array<std::pair<choice, std::string>, 11> { {
            { choice::walk, "walk" }, { choice::attack, "attack" }, { choice::talk, "talk" },
            { choice::fire, "fire" }, { choice::open, "open" }, { choice::close, "close" },
            { choice::examine, "examine" }, { choice::pick_up, "pick_up" },
            { choice::butcher, "butcher" }, { choice::jump, "jump" },
            { choice::describe, "describe" },
        }
    };
    return names;
}

/// The creature on `target` if the avatar sees it and it isn't the avatar.
auto seen_creature_at( const tripoint_bub_ms &target ) -> Creature * // *NOPAD*
{
    const auto &u = get_avatar();
    auto *const critter = g->critter_at<Creature>( target );
    return critter != nullptr && critter != &u && u.sees( *critter ) ? critter : nullptr;
}

/// Whether examining the square does something of its own (a door, a bed, a vending machine).
auto has_examine_action( const tripoint_bub_ms &p ) -> bool
{
    auto &m = get_map();
    return ( m.has_furn( p ) && m.furn( p ).obj().examine != &iexamine::none ) ||
           m.ter( p ).obj().examine != &iexamine::none;
}

/// One kind of item lying on a square, for the HUD's item strip.
struct item_kind {
    itype_id type;
    std::string name;
    std::string sym;
    nc_color color = c_white;
    int count = 0;
};

auto write_items( JsonOut &jsout, const std::vector<item_kind> &kinds ) -> void
{
    constexpr auto shown = 12;
    jsout.member( "kinds", static_cast<int>( kinds.size() ) );
    jsout.member( "items" );
    jsout.start_array();
    for( const auto &kind : kinds | std::views::take( shown ) ) {
        jsout.start_object();
        jsout.member( "type", kind.type.str() );
        jsout.member( "name", kind.name );
        jsout.member( "sym", kind.sym );
        jsout.member( "color", string_from_color( kind.color ) );
        jsout.member( "count", kind.count );
        jsout.end_object();
    }
    jsout.end_array();
}

/// Writes one `reach` entry for the square at `offset`, or nothing when it has nothing to act on.
auto write_reach_square( JsonOut &jsout, const point offset ) -> void
{
    auto &m = get_map();
    const auto &u = get_avatar();
    const auto p = u.bub_pos() + offset;
    if( !m.inbounds( p ) ) {
        return;
    }
    auto options = cata::godot_square::options_at( p );
    std::erase_if( options, []( const option & o ) {
        return o.what == choice::walk || o.what == choice::describe;
    } );
    const auto *const critter = seen_creature_at( p );

    auto kinds = std::vector<item_kind> {};
    auto total = 0;
    const item *corpse = nullptr;
    if( m.has_items( p ) && m.sees_some_items( p, u ) ) {
        for( const item *const it : m.i_at( p ) ) {
            ++total;
            if( corpse == nullptr && it->is_corpse() ) {
                corpse = it;
            }
            const auto known = std::ranges::find( kinds, it->typeId(), &item_kind::type );
            if( known != kinds.end() ) {
                known->count += it->count();
                continue;
            }
            kinds.push_back( { .type = it->typeId(), .name = remove_color_tags( it->tname() ), .sym = it->symbol(),
                               .color = it->color(), .count = it->count() } );
        }
    }

    const auto acts_on_square = std::ranges::any_of( options, []( const option & o ) {
        return o.what == choice::open || o.what == choice::close;
    } );
    const auto veh = m.veh_at( p );
    if( critter == nullptr && kinds.empty() && !acts_on_square && !has_examine_action( p ) && !veh ) {
        return;
    }

    auto title = std::string();
    if( critter != nullptr ) {
        title = critter->get_name();
    } else if( corpse != nullptr ) {
        title = remove_color_tags( corpse->tname() );
    } else if( veh ) {
        title = veh->vehicle().name;
    } else if( m.has_furn( p ) ) {
        title = m.furnname( p );
    } else if( kinds.size() == 1 && !acts_on_square ) {
        title = kinds.front().name;
    } else {
        title = m.tername( p );
    }

    jsout.start_object();
    jsout.member( "dx", offset.x );
    jsout.member( "dy", offset.y );
    jsout.member( "dir", cata::godot_square::direction_index( offset ) );
    jsout.member( "title", title );
    jsout.member( "count", total );
    jsout.member( "corpse", corpse != nullptr );
    jsout.member( "critter", critter != nullptr );
    jsout.member( "hostile", critter != nullptr && critter->attitude_to( u ) == Attitude::A_HOSTILE );
    // Bare ground that can only be examined (water to drink, a tree to climb) goes last.
    jsout.member( "plain", critter == nullptr && kinds.empty() && !acts_on_square && !veh &&
                  !m.has_furn( p ) );
    write_items( jsout, kinds );
    jsout.member( "options" );
    jsout.start_array();
    for( const auto &o : options ) {
        jsout.start_object();
        jsout.member( "id", cata::godot_square::name_of( o.what ) );
        jsout.member( "text", o.text );
        jsout.member( "key", o.key == ACTION_NULL ? std::string() :
                      cata::godot_bridge::key_label( action_ident( o.key ), "DEFAULTMODE" ) );
        jsout.end_object();
    }
    jsout.end_array();
    jsout.end_object();
}

} // namespace

auto cata::godot_square::name_of( const choice what ) -> std::string
{
    const auto found = std::ranges::find( choice_names(), what,
                                          &std::pair<choice, std::string>::first );
    return found == choice_names().end() ? std::string() : found->second;
}

auto cata::godot_square::health_word( const Creature &critter ) -> std::string
{
    const auto percent = critter.hp_percentage();
    if( percent >= 100 ) {
        return _( "Uninjured" );
    } else if( percent >= 80 ) {
        return _( "Lightly injured" );
    } else if( percent >= 60 ) {
        return _( "Moderately injured" );
    } else if( percent >= 30 ) {
        return _( "Heavily injured" );
    } else if( percent >= 10 ) {
        return _( "Severely injured" );
    }
    return _( "Nearly dead" );
}

auto cata::godot_square::move_view( const view_change &change ) -> void
{
    // Pixels dragged that did not yet add up to a square.
    static auto rest = point();
    // The most squares the view can be away from the avatar.
    constexpr auto reach = 48;
    // Zoom is the size of a square in sixteenths: from a quarter to four times.
    constexpr auto farthest = 4.0;
    constexpr auto closest = 64.0;
    auto &you = get_avatar();
    if( change.center ) {
        you.view_offset.x() = g->driving_view_offset.x;
        you.view_offset.y() = g->driving_view_offset.y;
        rest = point();
    }
    if( change.zoom_to > 0.0f ) {
        g->set_zoom( static_cast<float>( std::clamp( static_cast<double>( change.zoom_to ), farthest,
                                         closest ) ) );
        g->mark_main_ui_adaptor_resize();
    }
    if( change.zoom != 0 ) {
        // The wheel takes at least four steps to double the size, so each notch is a small one.
        const auto steps = std::max( get_option<int>( "ZOOM_STEP_COUNT" ), 4 );
        // Steps from the current size, which can be between levels (the size the front end
        // picked for the tileset), so zooming in and back out returns to the same size.
        const auto zoom = g->get_zoom() * std::pow( 2.0, static_cast<double>( change.zoom ) / steps );
        g->set_zoom( static_cast<float>( std::clamp( zoom, farthest, closest ) ) );
        g->mark_main_ui_adaptor_resize();
    }
    if( change.shift != point_zero ) {
        you.view_offset.x() = std::clamp( you.view_offset.x() + change.shift.x, -reach, reach );
        you.view_offset.y() = std::clamp( you.view_offset.y() + change.shift.y, -reach, reach );
    }
    if( change.drag != point_zero && tilecontext ) {
        const auto square = point( std::max( tilecontext->get_tile_width(), 1 ),
                                   std::max( tilecontext->get_tile_height(), 1 ) );
        // The map follows the hand: dragged right, the view moves left.
        rest += change.drag;
        const auto squares = point( rest.x / square.x, rest.y / square.y );
        rest -= point( squares.x * square.x, squares.y * square.y );
        you.view_offset.x() = std::clamp( you.view_offset.x() - squares.x, -reach, reach );
        you.view_offset.y() = std::clamp( you.view_offset.y() - squares.y, -reach, reach );
    }
    // A moved view needs the map drawn again; without this a drag or shift only showed after
    // the next turn.
    if( change.center || change.shift != point_zero || change.drag != point_zero ) {
        g->invalidate_main_ui_adaptor();
    }
}

namespace
{

auto overmap_dragged() -> point & // *NOPAD*
{
    static auto dragged = point();
    return dragged;
}

} // namespace

auto cata::godot_square::drag_overmap( const point drag ) -> void
{
    overmap_dragged() += drag;
}

auto cata::godot_square::take_overmap_drag() -> point
{
    auto &rest = overmap_dragged();
    if( !overmap_tilecontext ) {
        rest = point();
        return point();
    }
    const auto square = point( std::max( overmap_tilecontext->get_tile_width(), 1 ),
                               std::max( overmap_tilecontext->get_tile_height(), 1 ) );
    const auto squares = point( rest.x / square.x, rest.y / square.y );
    rest -= point( squares.x * square.x, squares.y * square.y );
    return -squares;
}

auto cata::godot_square::direction_index( const point offset ) -> int
{
    if( offset == point_zero ) {
        return 8;
    }
    // Clockwise from north; screen y grows southward.
    const auto angle = std::atan2( static_cast<double>( offset.x ), static_cast<double>( -offset.y ) );
    const auto step = static_cast<int>( std::lround( angle / ( std::numbers::pi / 4.0 ) ) );
    return ( step + 8 ) % 8;
}

auto cata::godot_square::title_at( const tripoint_bub_ms &target ) -> std::string
{
    const auto &u = get_avatar();
    if( target.xy() == u.bub_pos().xy() ) {
        return _( "Here" );
    }
    auto &m = get_map();
    const auto *const critter = seen_creature_at( target );
    const auto name = critter != nullptr ? critter->get_name() :
                      m.has_furn( target ) ? m.furnname( target ) : m.tername( target );
    return to_upper_case( name.substr( 0, 1 ) ) + name.substr( 1 );
}

auto cata::godot_square::options_at( const tripoint_bub_ms &target ) -> std::vector<option>
{
    auto &m = get_map();
    auto &u = get_avatar();
    const auto here = tripoint_bub_ms( target.xy(), u.bub_pos().z() );
    const auto dist = square_dist( target.xy().raw(), u.bub_pos().xy().raw() );
    const auto is_self = dist == 0;
    const auto is_adjacent = dist == 1;
    const auto inside = !m.is_outside( u.bub_pos() );
    auto *const critter = is_self ? nullptr : seen_creature_at( target );

    auto options = std::vector<option> {};
    const auto add = [&options]( const choice what, const std::string & text, const action_id key ) {
        options.push_back( { .what = what, .text = text, .key = key } );
    };

    if( critter != nullptr ) {
        // Attacking comes first with someone hostile; with anyone else it is offered last.
        const auto hostile = critter->attitude_to( u ) == Attitude::A_HOSTILE;
        if( hostile && is_adjacent ) {
            add( choice::attack, string_format( _( "Attack %s" ), critter->disp_name() ), ACTION_NULL );
        }
        if( critter->is_npc() && dist <= 6 ) {
            add( choice::talk, string_format( _( "Talk to %s" ), critter->disp_name() ), ACTION_CHAT );
        }
        if( u.primary_weapon().is_gun() ) {
            add( choice::fire, string_format( _( "Fire at %s" ), critter->disp_name() ), ACTION_FIRE );
        }
    }
    if( !is_self && critter == nullptr && avatar_knows_travel_destination( u, target ) ) {
        add( choice::walk, is_adjacent ? _( "Step here" ) : _( "Walk here" ), ACTION_NULL );
    }
    if( is_adjacent && m.can_open_door( &u, here, inside ) ) {
        add( choice::open, _( "Open" ), ACTION_OPEN );
    }
    if( is_adjacent && m.close_door( here, inside, true ) ) {
        add( choice::close, _( "Close" ), ACTION_CLOSE );
    }
    if( is_self || is_adjacent ) {
        if( m.has_items( target ) ) {
            add( choice::pick_up, _( "Pick up items" ), ACTION_PICKUP );
        }
        if( is_self && std::ranges::any_of( m.i_at( target ), &item::is_corpse ) ) {
            add( choice::butcher, _( "Butcher or dissect" ), ACTION_BUTCHER );
        }
        add( choice::examine, string_format( _( "Examine %s" ), m.disp_name( target ) ), ACTION_EXAMINE );
    }
    if( is_adjacent && iexamine::can_jump_over_tile( u, target ) ) {
        add( choice::jump, _( "Jump over" ), ACTION_JUMP );
    }
    // Hitting someone who isn't hostile is never the first thing offered.
    if( critter != nullptr && is_adjacent && critter->attitude_to( u ) != Attitude::A_HOSTILE ) {
        add( choice::attack, string_format( _( "Push or attack %s" ), critter->disp_name() ),
             ACTION_NULL );
    }
    if( !is_self && u.sees( target ) ) {
        add( choice::describe, _( "Look closer" ), ACTION_NULL );
    }
    return options;
}

namespace
{

/// One line of the hover tip.
struct tip_line {
    std::string text;
    nc_color color = c_light_gray;
};

auto write_tip_lines( JsonOut &jsout, const std::vector<tip_line> &lines ) -> void
{
    jsout.member( "lines" );
    jsout.start_array();
    for( const auto &line : lines ) {
        jsout.start_array();
        jsout.write( line.text );
        jsout.write( string_from_color( line.color ) );
        jsout.end_array();
    }
    jsout.end_array();
}

/// What lies on the square in one line: "3 items: rock, plank +1 more".
auto items_line( const tripoint_bub_ms &p ) -> std::optional<tip_line>
{
    auto &m = get_map();
    const auto &u = get_avatar();
    if( !m.has_items( p ) || !m.sees_some_items( p, u ) ) {
        return std::nullopt;
    }
    if( m.has_flag( "CONTAINER", p ) && !m.could_see_items( p, u ) ) {
        return tip_line{ .text = _( "You cannot see what is inside of it." ) };
    }
    constexpr auto named = 2;
    auto names = std::vector<std::string> {};
    auto total = 0;
    for( const item *const it : m.i_at( p ) ) {
        ++total;
        const auto name = remove_color_tags( it->tname() );
        if( !std::ranges::contains( names, name ) ) {
            names.push_back( name );
        }
    }
    auto text = names.front();
    for( const auto &name : names | std::views::drop( 1 ) | std::views::take( named - 1 ) ) {
        text += ", " + name;
    }
    const auto more = static_cast<int>( names.size() ) - named;
    if( more > 0 ) {
        text += string_format( _( " +%d more" ), more );
    }
    return tip_line{ .text = total == 1 ? text : string_format( _( "%d items: %s" ), total, text ),
                     .color = c_white };
}

} // namespace

auto cata::godot_square::write_tip( JsonOut &jsout, const tripoint_bub_ms &target ) -> void
{
    auto &m = get_map();
    const auto &u = get_avatar();
    if( !m.inbounds( target ) ) {
        return;
    }
    const auto &cache = m.get_visibility_variables_cache();
    if( m.get_visibility( m.apparent_light_at( target, cache ), cache ) != VIS_CLEAR ) {
        return;
    }
    const auto is_self = target.xy() == u.bub_pos().xy();
    const auto *const critter = is_self ? nullptr : seen_creature_at( target );
    const auto veh = m.veh_at( target );
    const auto ground = m.has_furn( target ) ? m.furnname( target ) : m.tername( target );

    auto title = ground;
    auto tone = std::string();
    auto lines = std::vector<tip_line> {};
    if( critter != nullptr ) {
        title = critter->get_name();
        const auto attitude = critter->attitude_to( u );
        tone = attitude == Attitude::A_HOSTILE ? "hostile" :
               attitude == Attitude::A_FRIENDLY ? "friendly" : "neutral";
        const auto *const mon = critter->as_monster();
        const auto mood = mon != nullptr ? mon->get_attitude() :
                          std::pair<std::string, nc_color>( Creature::get_attitude_ui_data( attitude ).first.translated(),
                                  Creature::get_attitude_ui_data( attitude ).second );
        // The game's attitude words end in a full stop ("Friendly."); the tip joins them instead.
        const auto word = mood.first.ends_with( '.' ) ? mood.first.substr( 0, mood.first.size() - 1 ) :
                          mood.first;
        lines.push_back( { .text = string_format( "%s  ·  %s", word, health_word( *critter ) ),
                           .color = mood.second } );
    } else if( is_self ) {
        title = _( "You" );
    } else if( veh ) {
        title = veh->vehicle().name;
    }
    if( veh ) {
        if( const auto part = veh->part_displayed() ) {
            lines.push_back( { .text = part->part().name() } );
        }
    }
    if( title != ground ) {
        lines.push_back( { .text = ground } );
    }
    if( m.has_furn( target ) ) {
        lines.push_back( { .text = m.tername( target ), .color = c_dark_gray } );
    }
    if( m.impassable( target ) ) {
        lines.push_back( { .text = _( "Impassable" ), .color = c_dark_gray } );
    } else if( const auto cost = m.move_cost( target ) * 50; cost != 100 ) {
        lines.push_back( { .text = string_format( _( "Move cost %d" ), cost ), .color = c_dark_gray } );
    }
    for( const auto &fld : m.field_at( target ) ) {
        lines.push_back( { .text = fld.second.name(), .color = fld.second.color() } );
    }
    if( const auto &tr = m.tr_at( target ); !tr.is_null() && tr.can_see( target, u ) ) {
        lines.push_back( { .text = tr.name(), .color = c_yellow } );
    }
    if( const auto items = items_line( target ) ) {
        lines.push_back( *items );
    }

    constexpr auto shown_acts = 3;
    jsout.member( "tip" );
    jsout.start_object();
    jsout.member( "title", title );
    jsout.member( "tone", tone );
    write_tip_lines( jsout, lines );
    jsout.member( "acts" );
    jsout.start_array();
    for( const auto &o : options_at( target ) | std::views::take( shown_acts ) ) {
        jsout.write( name_of( o.what ) );
    }
    jsout.end_array();
    jsout.end_object();
}

auto cata::godot_square::request( const point offset, const std::string &what ) -> void
{
    const auto &u = get_avatar();
    const auto found = std::ranges::find( choice_names(), what,
                                          &std::pair<choice, std::string>::second );
    pending() = pending_request{
        .target = u.bub_pos() + offset,
        .what = found == choice_names().end() ? std::nullopt : std::optional<choice>( found->first ),
    };
}

auto cata::godot_square::take_target() -> std::optional<tripoint_bub_ms>
{
    return std::exchange( pending().target, std::nullopt );
}

auto cata::godot_square::take_choice() -> std::optional<choice>
{
    return std::exchange( pending().what, std::nullopt );
}

auto cata::godot_square::write_reach( JsonOut &jsout ) -> void
{
    // The avatar's own square first, then clockwise from north.
    static constexpr auto offsets = std::array<point, 9> { {
            { 0, 0 }, { 0, -1 }, { 1, -1 }, { 1, 0 }, { 1, 1 }, { 0, 1 }, { -1, 1 }, { -1, 0 }, { -1, -1 },
        }
    };
    jsout.member( "reach" );
    jsout.start_array();
    for( const auto offset : offsets ) {
        write_reach_square( jsout, offset );
    }
    jsout.end_array();
}

#endif // TILES
