#pragma once

#if defined(TILES)

namespace cata::slate
{

/// Draws the in-game Slate HUD over the map: the survivor card (top left)
/// and the clickable action dock (bottom center).
auto draw_hud() -> void;

} // namespace cata::slate

#endif // TILES
