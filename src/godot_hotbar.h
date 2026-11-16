#pragma once

#include <string>
#include <vector>

class item;
class JsonOut;

/// Item hotbar of the Godot front end: nine slots that each hold an item type. Using a slot eats,
/// uses, reads, wears or wields the first such item the avatar carries. Godot keeps the slots
/// for each character and sends them here; the HUD reports what each slot holds.
namespace cata::godot_hotbar
{

/// The type to pin for `it`: what it holds when it is a container of one food or drink (a
/// bottle of water pins the water), else its own type.
auto type_for( const item &it ) -> std::string;

/// Replaces the slots with item type ids; an empty id is an empty slot.
auto set_slots( std::vector<std::string> ids ) -> void;

/// Writes the `hotbar` member of the HUD: per slot its type, name, symbol, color and how many
/// the avatar carries, or null for an empty slot.
auto write( JsonOut &jsout ) -> void;

/// Uses the item in `slot`, or says there is none.
auto use( int slot ) -> void;

} // namespace cata::godot_hotbar
