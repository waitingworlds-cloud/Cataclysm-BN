#pragma once

#if defined(TILES)

#include "coordinates.h"
#include "point.h"

/// What the map view shows, told to the Godot front end so it can light the map and play effects
/// over it (see `godot_bridge.h`).
namespace cata::godot_scene
{

/// Where the map view was just drawn.
struct view {
    /// Top left corner of the view, in frame pixels.
    point at;
    /// Tile at the middle of the view.
    tripoint_bub_ms center;
    /// Pixel size of one tile.
    point tile;
    /// Pixel size of the view.
    point size;
};

/// Describes the view and its tiles (light, visibility, sky, creatures) for the next frame.
auto publish( const view &v ) -> void;

} // namespace cata::godot_scene

#endif // TILES
