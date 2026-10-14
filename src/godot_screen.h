#pragma once

#if defined(TILES)

#include <string>

#include "godot_bridge.h"
#include "json.h"

/// Helpers for screens drawn by the Godot front end's generic `screen` view (see
/// `godot/README.md`, "Screens"): small pieces every such screen writes.
namespace cata::godot_screen
{

/// Pick codes for a row: `pane * row_stride + row`.
constexpr auto row_stride = 100000;
/// Pick codes for tabs and sub-tabs, above any row code.
constexpr auto tab_pick = 100 * row_stride;
constexpr auto subtab_pick = tab_pick + row_stride;

struct button {
    /// Action pressed when clicked (looked up in the view's input category).
    std::string act = {};
    std::string text = {};
    /// Lucide icon name.
    std::string icon = {};
    /// Input category of `act`, for the key shown on the button.
    std::string category = {};
    bool primary = false;
    bool enabled = true;
    std::string tip = {};
};

/// Writes a button object: `{act, text, icon, key, primary, enabled}`.
inline auto write_button( JsonOut &jsout, const button &b ) -> void
{
    jsout.start_object();
    jsout.member( "act", b.act );
    jsout.member( "text", b.text );
    if( !b.icon.empty() ) {
        jsout.member( "icon", b.icon );
    }
    jsout.member( "key", godot_bridge::key_label( b.act, b.category ) );
    jsout.member( "primary", b.primary );
    jsout.member( "enabled", b.enabled );
    if( !b.tip.empty() ) {
        jsout.member( "tip", b.tip );
    }
    jsout.end_object();
}

/// Writes a footer key hint `{key, text}` for the key bound to `act` in `category`.
inline auto write_hint( JsonOut &jsout, const std::string &act, const std::string &category,
                        const std::string &text ) -> void
{
    jsout.start_object();
    jsout.member( "key", godot_bridge::key_label( act, category ) );
    jsout.member( "text", text );
    jsout.end_object();
}

/// Writes a footer key hint with a fixed key label, such as "↑↓".
inline auto write_fixed_hint( JsonOut &jsout, const std::string &key,
                              const std::string &text ) -> void
{
    jsout.start_object();
    jsout.member( "key", key );
    jsout.member( "text", text );
    jsout.end_object();
}

} // namespace cata::godot_screen

#endif // TILES
