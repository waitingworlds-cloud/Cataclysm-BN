#pragma once

#include <string>
#include <utility>
#include <vector>

/// Warnings for the Godot front end's alert banner: messages the game marks as warnings (a
/// monster spotted in safe mode, hunger, something breaking), so they stand out from the log.
namespace cata::godot_hud
{

/// New warning messages since the HUD last read the log, as `{time of day, text}`. Call before
/// `Messages::sidebar_lines`, which marks messages as seen.
auto new_warnings() -> std::vector<std::pair<std::string, std::string>>;

} // namespace cata::godot_hud
