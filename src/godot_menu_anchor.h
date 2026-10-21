#pragma once

#include <optional>

#include "point.h"

namespace cata::godot_bridge
{

/// Asks the Godot front end to show the next native menu beside `px` (window pixels), like a
/// context menu, instead of in the middle of the screen.
auto anchor_next_menu( point px ) -> void;

/// The anchor set for the next native menu, if any; taking it clears it.
auto take_menu_anchor() -> std::optional<point>;

} // namespace cata::godot_bridge
