#if defined(TILES)

#include "godot_scene.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <sstream>
#include <string>
#include <utility>
#include <vector>

#include "avatar.h"
#include "calendar.h"
#include "creature.h"
#include "enums.h"
#include "game.h"
#include "game_constants.h"
#include "godot_bridge.h"
#include "json.h"
#include "map/lightmap.h"
#include "map/map.h"
#include "map/mapdata.h"
#include "monster.h"
#include "output.h"
#include "weather/weather.h"
#include "weather/weather_type.h"

namespace
{

/// Bits of a tile's flag byte (the blue channel).
constexpr auto flag_opaque = std::uint8_t { 1 };
constexpr auto flag_outside = std::uint8_t { 2 };
constexpr auto flag_creature = std::uint8_t { 4 };
constexpr auto flag_plant = std::uint8_t { 8 };
constexpr auto flag_water = std::uint8_t { 16 };
constexpr auto flag_wall = std::uint8_t { 32 };

/// Light as a byte: the square root keeps the dim end, where the eye tells levels apart, wide.
auto light_byte( const float light ) -> std::uint8_t
{
    const auto share = std::sqrt( std::clamp( light, 0.0f, 100.0f ) / 100.0f );
    return static_cast<std::uint8_t>( std::lround( share * 255.0f ) );
}

auto visibility_byte( const lit_level level ) -> std::uint8_t
{
    switch( level ) {
        case lit_level::LIT:
        case lit_level::BRIGHT:
            return 255;
        case lit_level::BRIGHT_ONLY:
        case lit_level::LOW:
            return 170;
        default:
            return 0;
    }
}

auto precipitation( const weather_type &weather ) -> int
{
    switch( weather.precip ) {
        case precip_class::very_light:
            return 1;
        case precip_class::light:
            return 2;
        case precip_class::medium:
            return 3;
        case precip_class::heavy:
            return 4;
        default:
            return 0;
    }
}

} // namespace

auto cata::godot_scene::publish( const view &v ) -> void
{
    if( !g || v.tile.x <= 0 || v.tile.y <= 0 ) {
        return;
    }
    auto &here = get_map();
    const auto &you = get_avatar();
    const auto z = v.center.z();
    const auto origin = v.center.xy() - point( POSX, POSY );
    const auto grid = point( std::clamp( ( v.size.x + v.tile.x - 1 ) / v.tile.x, 1, 160 ),
                             std::clamp( ( v.size.y + v.tile.y - 1 ) / v.tile.y, 1, 120 ) );
    const auto &cache = here.access_cache( z );

    auto scene = cata::godot_bridge::scene_state{ .grid = grid };
    scene.tiles.assign( static_cast<std::size_t>( grid.x ) * grid.y * 4, 0 );
    const auto cell = [&]( const point at ) -> std::uint8_t * { // *NOPAD*
        return scene.tiles.data() + ( static_cast<std::size_t>( at.y ) * grid.x + at.x ) * 4;
    };
    for( auto row = 0; row < grid.y; ++row ) {
        for( auto col = 0; col < grid.x; ++col ) {
            const auto p = tripoint_bub_ms( origin + point( col, row ), z );
            auto *out = cell( point( col, row ) );
            out[3] = 255;
            if( !cache.inbounds( p.xy() ) ) {
                continue;
            }
            const auto at = cache.idx( p.x(), p.y() );
            out[0] = light_byte( here.ambient_light_at( p ) );
            out[1] = visibility_byte( cache.visibility_cache[at] );
            auto flags = std::uint8_t{ 0 };
            if( here.light_transparency( p ) <= LIGHT_TRANSPARENCY_SOLID ) {
                flags |= flag_opaque;
            }
            if( cache.outside_cache[at] ) {
                flags |= flag_outside;
            }
            if( here.has_flag_ter_or_furn( "TREE", p ) || here.has_flag_ter_or_furn( "SHRUB", p ) ||
                here.has_flag_ter_or_furn( "YOUNG", p ) || here.has_flag_ter_or_furn( "FLOWER", p ) ) {
                flags |= flag_plant;
            }
            if( here.has_flag_ter( TFLAG_SWIMMABLE, p ) || here.has_flag_ter( TFLAG_DEEP_WATER, p ) ) {
                flags |= flag_water;
            }
            if( here.has_flag_ter( TFLAG_WALL, p ) ) {
                flags |= flag_wall;
            }
            out[2] = flags;
        }
    }

    const auto now = calendar::turn;
    const auto &weather = *get_weather().weather_id;
    const auto player_cell = you.bub_pos().xy() - origin;

    auto text = std::ostringstream();
    auto jsout = JsonOut( text );
    jsout.start_object();
    jsout.member( "t", "scene" );
    jsout.member( "tile" );
    jsout.start_array();
    jsout.write( v.tile.x );
    jsout.write( v.tile.y );
    jsout.end_array();
    jsout.member( "at" );
    jsout.start_array();
    jsout.write( v.at.x );
    jsout.write( v.at.y );
    jsout.end_array();
    jsout.member( "size" );
    jsout.start_array();
    jsout.write( v.size.x );
    jsout.write( v.size.y );
    jsout.end_array();
    jsout.member( "origin" );
    jsout.start_array();
    jsout.write( origin.x() );
    jsout.write( origin.y() );
    jsout.end_array();
    const auto camera = bub_to_abs( v.center );
    jsout.member( "cam" );
    jsout.start_array();
    jsout.write( camera.x() );
    jsout.write( camera.y() );
    jsout.write( camera.z() );
    jsout.end_array();
    jsout.member( "center" );
    jsout.start_array();
    jsout.write( POSX );
    jsout.write( POSY );
    jsout.end_array();
    jsout.member( "you" );
    jsout.start_array();
    jsout.write( player_cell.x() );
    jsout.write( player_cell.y() );
    jsout.end_array();
    jsout.member( "hour", hour_of_day<int>( now ) + minute_of_hour<int>( now ) / 60.0 );
    jsout.member( "sun", std::clamp( sunlight( now, false ) / 100.0, 0.0, 1.0 ) );
    jsout.member( "outside", here.is_outside( you.bub_pos() ) );
    jsout.member( "underground", z < 0 );
    jsout.member( "weather", weather.id.str() );
    jsout.member( "precip", precipitation( weather ) );
    jsout.member( "rain", weather.rains );
    jsout.member( "mobs" );
    jsout.start_array();
    for( Creature &critter : g->all_creatures() ) {
        const auto pos = critter.bub_pos();
        const auto at = pos.xy() - origin;
        if( pos.z() != z || at.x() < 0 || at.y() < 0 || at.x() >= grid.x || at.y() >= grid.y ) {
            continue;
        }
        if( &critter != &you && !you.sees( critter ) ) {
            continue;
        }
        if( &critter == &you ) {
            continue;
        }
        cell( point( at.x(), at.y() ) )[2] |= flag_creature;
        const auto hp_max = std::max( critter.get_hp_max(), 1 );
        jsout.start_array();
        jsout.write( at.x() );
        jsout.write( at.y() );
        jsout.write( std::clamp( static_cast<double>( critter.get_hp() ) / hp_max, 0.0, 1.0 ) );
        jsout.write( critter.attitude_to( you ) == Attitude::A_HOSTILE );
        jsout.end_array();
    }
    jsout.end_array();
    jsout.end_object();
    scene.json = text.str();
    cata::godot_bridge::set_scene( std::move( scene ) );
}

#endif // TILES
