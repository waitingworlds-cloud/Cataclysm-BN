#pragma once

#if defined(TILES)

#include <functional>
#include <optional>
#include <string>

#include "action.h"

class JsonOut;

/// Command search in the Godot front end: every action of the main game view, with its name,
/// key and group, so players can find one by typing instead of remembering keys.
namespace cata::godot_commands
{

/// Writes the `commands` message body: `list` of `[id, name, key, group]` and `suggested` ids
/// that apply where the player stands right now.
auto write( JsonOut &jsout ) -> void;

/// Runs `id` next time the action menu opens; used for actions without a key.
auto request( const std::string &id ) -> void;

/// Runs `task` next time the action menu opens, in place of the menu: for things the game has
/// no action for, such as using a hotbar slot.
auto request_task( std::function<void()> task ) -> void;

/// The action asked for with `request`, if any; taking it clears it.
auto take_requested() -> std::optional<action_id>;

/// Runs the task asked for with `request_task`, if any; true when there was one.
auto run_requested_task() -> bool;

} // namespace cata::godot_commands

#endif // TILES
