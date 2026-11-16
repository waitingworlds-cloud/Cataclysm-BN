#pragma once

#if defined(TILES)

#include <optional>
#include <string>
#include <vector>

#include "action.h"
#include "coordinates.h"
#include "point.h"

class Creature;
class JsonOut;

/// What can be done on a map square in the Godot front end: the right-click menu's choices, the
/// HUD's "in reach" list built from them, and requests from the HUD to act on a square.
namespace cata::godot_square
{

enum class choice : int {
    walk, attack, talk, fire, open, close, examine, pick_up, butcher, jump, describe
};

/// One thing that can be done on a square.
struct option {
    choice what = choice::examine;
    /// Menu text, e.g. "Pick up items".
    std::string text;
    /// The action whose key does the same, or `ACTION_NULL`.
    action_id key = ACTION_NULL;
};

/// The name the HUD and Godot use for `what`, e.g. `pick_up`.
auto name_of( choice what ) -> std::string;

/// Everything the avatar can do on `target` right now, most likely first.
auto options_at( const tripoint_bub_ms &target ) -> std::vector<option>;

/// What the square is called in its menu: the creature seen there, else the terrain or furniture.
auto title_at( const tripoint_bub_ms &target ) -> std::string;

/// Asks for the square `offset` from the avatar to be acted on as if it had been right-clicked.
/// With an empty `what` its menu opens; otherwise that choice runs without one.
auto request( point offset, const std::string &what ) -> void;

/// The square asked for with `request`, if any; taking it clears it.
auto take_target() -> std::optional<tripoint_bub_ms>;

/// The choice asked for with `request`, if any; taking it clears it.
auto take_choice() -> std::optional<choice>;

/// Writes the HUD's `reach` member: the avatar's square and the eight around it that have
/// something to act on, each with its items and choices.
auto write_reach( JsonOut &jsout ) -> void;

/// Writes the HUD's `tip` member for the square under the resting mouse: a short summary (who or
/// what is there, the ground, items) and the names of the first choices a right-click offers. Nothing for a square the
/// avatar can't see clearly; the full description stays in the look screens.
auto write_tip( JsonOut &jsout, const tripoint_bub_ms &target ) -> void;

/// How hurt a creature looks, in a word or two: "Uninjured" to "Nearly dead".
auto health_word( const Creature &critter ) -> std::string;

/// A change of the main map's view made with the mouse.
struct view_change {
    /// Zoom steps in (positive) or out (negative).
    int zoom = 0;
    /// How far the map was dragged, in screen pixels.
    point drag;
    /// Put the view back on the avatar.
    bool center = false;
};

/// Zooms and moves the main map's view. Unlike the zoom keys the zoom stops at either end, and a
/// drag moves the view by whole squares (what is left over counts toward the next drag).
auto move_view( const view_change &change ) -> void;

/// Adds a drag of the overmap screen with the middle button, in screen pixels.
auto drag_overmap( point drag ) -> void;

/// How many overmap squares the view should move for the drags since the last call (the map
/// follows the hand); taking it clears it. Pixels that don't make a whole square are kept.
auto take_overmap_drag() -> point;

/// Compass direction of `offset` for the HUD: 0 to 7 clockwise from north, 8 for no offset.
auto direction_index( point offset ) -> int;

} // namespace cata::godot_square

#endif // TILES
