#pragma once

#if defined(TILES)

#include <optional>
#include <string>
#include <vector>

#include "color.h"
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

/// Text that may carry color tags; untagged parts use `color`.
struct span {
    std::string text = {};
    nc_color color = c_light_gray;
};

inline auto write_span( JsonOut &jsout, const span &s ) -> void
{
    godot_bridge::write_spans( jsout, s.text, s.color );
}

/// A list row (see `rows` in the README's screen schema).
struct row {
    span text = {};
    /// Extra right-aligned columns.
    std::vector<span> cells = {};
    /// Index the cursor uses for this row; defaults to its position in the list.
    std::optional<int> i = std::nullopt;
    /// Pick code sent when clicked; defaults to `pane * row_stride + i`.
    std::optional<int> pick = std::nullopt;
    bool heading = false;
    bool enabled = true;
    span note = {};
    /// Lucide icon name and its curses color.
    std::string icon = {};
    std::string icon_color = {};
    std::string sym = {};
    std::string sym_color = {};
    int indent = 0;
    std::string tip = {};
};

inline auto write_row( JsonOut &jsout, const row &r ) -> void
{
    jsout.start_object();
    jsout.member( "text" );
    write_span( jsout, r.text );
    if( !r.cells.empty() ) {
        jsout.member( "cells" );
        jsout.start_array();
        for( const auto &c : r.cells ) {
            write_span( jsout, c );
        }
        jsout.end_array();
    }
    if( r.i ) {
        jsout.member( "i", *r.i );
    }
    if( r.pick ) {
        jsout.member( "pick", *r.pick );
    }
    if( r.heading ) {
        jsout.member( "heading", true );
    }
    if( !r.enabled ) {
        jsout.member( "enabled", false );
    }
    if( !r.note.text.empty() ) {
        jsout.member( "note" );
        write_span( jsout, r.note );
    }
    if( !r.icon.empty() ) {
        jsout.member( "icon", r.icon );
        if( !r.icon_color.empty() ) {
            jsout.member( "icon_color", r.icon_color );
        }
    }
    if( !r.sym.empty() ) {
        jsout.member( "sym", r.sym );
        jsout.member( "sym_color", r.sym_color );
    }
    if( r.indent > 0 ) {
        jsout.member( "indent", r.indent );
    }
    if( !r.tip.empty() ) {
        jsout.member( "tip", r.tip );
    }
    jsout.end_object();
}

/// A tab or sub-tab.
struct tab {
    std::string text = {};
    bool active = false;
    int pick = tab_pick;
    bool enabled = true;
    std::string icon = {};
    std::string count = {};
    std::string tip = {};
};

inline auto write_tab( JsonOut &jsout, const tab &t ) -> void
{
    jsout.start_object();
    jsout.member( "text", t.text );
    jsout.member( "active", t.active );
    jsout.member( "pick", t.pick );
    jsout.member( "enabled", t.enabled );
    if( !t.icon.empty() ) {
        jsout.member( "icon", t.icon );
    }
    if( !t.count.empty() ) {
        jsout.member( "count", t.count );
    }
    if( !t.tip.empty() ) {
        jsout.member( "tip", t.tip );
    }
    jsout.end_object();
}

/// A chip in the header: `[icon] label value`.
struct stat {
    std::string icon = {};
    std::string label = {};
    span value = {};
    std::string tip = {};
};

inline auto write_stat( JsonOut &jsout, const stat &s ) -> void
{
    jsout.start_object();
    if( !s.icon.empty() ) {
        jsout.member( "icon", s.icon );
    }
    if( !s.label.empty() ) {
        jsout.member( "label", s.label );
    }
    jsout.member( "value" );
    write_span( jsout, s.value );
    if( !s.tip.empty() ) {
        jsout.member( "tip", s.tip );
    }
    jsout.end_object();
}

/// Writes `tab_keys`: the keys that switch to the previous and next tab.
inline auto write_tab_keys( JsonOut &jsout, const std::string &prev, const std::string &next,
                            const std::string &category ) -> void
{
    jsout.member( "tab_keys" );
    jsout.start_object();
    jsout.member( "prev", godot_bridge::key_label( prev, category ) );
    jsout.member( "next", godot_bridge::key_label( next, category ) );
    jsout.end_object();
}

} // namespace cata::godot_screen

#endif // TILES
