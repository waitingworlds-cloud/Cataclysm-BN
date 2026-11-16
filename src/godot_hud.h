#pragma once

#include <string>

/// State of the main game screen for the Godot front end's HUD (see `godot_bridge.h`).
namespace cata::godot_hud
{

/// Everything the sidebar would show for the avatar, as a JSON object of type `hud`.
/// Marks shown messages as seen, like drawing the sidebar does.
auto build() -> std::string;

} // namespace cata::godot_hud
