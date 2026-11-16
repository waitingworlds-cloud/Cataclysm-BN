#pragma once

#if defined(TILES)

#include <optional>
#include <string>

/// Items dragged in the Godot front end. A drop sends a pick (which selects the item) with a verb
/// saying what to do with it: `wear`, `wield`, `take_off` or `drop`.
namespace cata::godot_bridge
{

/// The verb of the last drag in the native view of `owner`, if any; taking it clears it.
auto take_drag_verb( const void *owner ) -> std::optional<std::string>;

} // namespace cata::godot_bridge

#endif // TILES
