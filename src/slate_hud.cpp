#if defined(TILES)

#include "slate_hud.h"

#include <algorithm>
#include <array>
#include <optional>
#include <ranges>
#include <string>
#include <vector>

#include "avatar.h"
#include "bodypart.h"
#include "color.h"
#include "imgui_layer.h"
#include "input.h"
#include "item.h"
#include "slate_theme.h"
#include "string_formatter.h"
#include "translations.h"

namespace cata::slate
{

namespace
{

constexpr auto hud_window_flags = ImGuiWindowFlags_NoDecoration | ImGuiWindowFlags_NoMove |
                                  ImGuiWindowFlags_NoSavedSettings | ImGuiWindowFlags_AlwaysAutoResize |
                                  ImGuiWindowFlags_NoFocusOnAppearing | ImGuiWindowFlags_NoNav;

constexpr auto screen_margin = 16.0f;
constexpr auto default_mode = "DEFAULTMODE";

/// One limb of the body silhouette, in silhouette-local pixels.
struct limb_shape {
    const char *id;
    ImVec2 min;
    ImVec2 max;
    float rounding;
};

/// Character's right side is drawn on the viewer's left, like a figure facing you.
constexpr auto silhouette = std::array
{
    limb_shape{ .id = "head", .min = { 24, 0 }, .max = { 46, 22 }, .rounding = 11 },
    limb_shape{ .id = "torso", .min = { 19, 26 }, .max = { 51, 72 }, .rounding = 9 },
    limb_shape{ .id = "arm_r", .min = { 3, 28 }, .max = { 16, 74 }, .rounding = 6.5f },
    limb_shape{ .id = "arm_l", .min = { 54, 28 }, .max = { 67, 74 }, .rounding = 6.5f },
    limb_shape{ .id = "leg_r", .min = { 20, 76 }, .max = { 34, 128 }, .rounding = 7 },
    limb_shape{ .id = "leg_l", .min = { 36, 76 }, .max = { 50, 128 }, .rounding = 7 },
};
constexpr auto silhouette_size = ImVec2( 70, 128 );

struct dock_action {
    const char *id;
    const char *label;
};

constexpr auto dock_actions = std::array
{
    dock_action{ .id = "inventory", .label = translate_marker( "Bag" ) },
    dock_action{ .id = "craft", .label = translate_marker( "Craft" ) },
    dock_action{ .id = "construct", .label = translate_marker( "Build" ) },
    dock_action{ .id = "pickup", .label = translate_marker( "Pick up" ) },
    dock_action{ .id = "look", .label = translate_marker( "Look" ) },
    dock_action{ .id = "fire", .label = translate_marker( "Fire" ) },
    dock_action{ .id = "wait", .label = translate_marker( "Wait" ) },
    dock_action{ .id = "map", .label = translate_marker( "Map" ) },
};
constexpr auto dock_button_size = ImVec2( 72, 56 );

struct need_row {
    std::string label;
    std::string state;
    ImU32 col;
    float fill;
};

/// Maps the curses color a game description carries onto the Slate palette.
auto severity_color( const nc_color &col ) -> ImU32
{
    const auto value = static_cast<int>( col );
    const auto is_any = [value]( std::initializer_list<nc_color> options ) {
        return std::ranges::any_of( options, [value]( const nc_color & c ) { return value == static_cast<int>( c ); } );
    };
    if( is_any( { c_red, c_light_red } ) ) {
        return color::danger;
    }
    if( is_any( { c_yellow, c_brown } ) ) {
        return color::warn;
    }
    if( is_any( { c_green, c_light_green } ) ) {
        return color::ok;
    }
    if( is_any( { c_blue, c_light_blue, c_cyan, c_light_cyan } ) ) {
        return color::info;
    }
    return color::text;
}

/// Rough bar fill implied by a severity color, for needs that only expose a description.
auto severity_fill( ImU32 col ) -> float
{
    if( col == color::danger ) {
        return 0.2f;
    }
    if( col == color::warn ) {
        return 0.45f;
    }
    return 0.85f;
}

auto hp_color( int cur, int max ) -> ImU32
{
    if( max <= 0 || cur <= 0 ) {
        return color::disabled;
    }
    const auto ratio = static_cast<float>( cur ) / static_cast<float>( max );
    return ratio > 0.75f ? color::ok : ratio > 0.4f ? color::warn : color::danger;
}

auto key_hint( const std::string &action_id ) -> std::string
{
    const auto &events = inp_mngr.get_input_for_action( action_id, default_mode );
    const auto key = std::ranges::find_if( events, []( const input_event & ev ) { return ev.type == input_event_t::keyboard; } );
    if( key == events.end() ) {
        return {};
    }
    return inp_mngr.get_keyname( key->get_first_input(), key->type );
}

auto description_row( const std::string &label,
                      const std::pair<std::string, nc_color> &desc ) -> need_row
{
    const auto col = desc.first.empty() ? color::ok : severity_color( desc.second );
    return {
        .label = label,
        .state = desc.first.empty() ? _( "Fine" ) : desc.first,
        .col = col,
        .fill = severity_fill( col ),
    };
}

auto collect_needs( const avatar &you ) -> std::vector<need_row>
{
    const auto stamina_max = std::max( you.get_stamina_max(), 1 );
    const auto stamina = static_cast<float>( you.get_stamina() ) / static_cast<float>( stamina_max );
    return {
        description_row( _( "Thirst" ), you.get_thirst_description() ),
        description_row( _( "Hunger" ), you.get_hunger_description() ),
        description_row( _( "Fatigue" ), you.get_fatigue_description() ),
        need_row{
            .label = _( "Stamina" ),
            .state = string_format( "%d%%", static_cast<int>( stamina * 100.0f ) ),
            .col = color::info,
            .fill = stamina,
        },
    };
}

auto text_at( ImDrawList &dl, ImFont *font, float size, ImVec2 pos, ImU32 col,
              const std::string &text ) -> void
{
    dl.AddText( font, size, pos, col, text.c_str() );
}

auto text_size( ImFont *font, float size, const std::string &text ) -> ImVec2
{
    return font->CalcTextSizeA( size, FLT_MAX, 0.0f, text.c_str() );
}

auto draw_silhouette( const avatar &you ) -> void
{
    auto &dl = *ImGui::GetWindowDrawList();
    ImGui::Dummy( silhouette_size );
    const auto origin = ImGui::GetItemRectMin();
    const auto mouse = ImGui::GetIO().MousePos;

    for( const auto &bp : you.get_all_body_parts( true ) ) {
        const auto id = bp.id().str();
        const auto shape = std::ranges::find_if( silhouette, [&id]( const limb_shape & s ) { return id == s.id; } );
        if( shape == silhouette.end() ) {
            continue;
        }
        const auto min = ImVec2( origin.x + shape->min.x, origin.y + shape->min.y );
        const auto max = ImVec2( origin.x + shape->max.x, origin.y + shape->max.y );
        const auto cur = you.get_part_hp_cur( bp );
        const auto hp_max = you.get_part_hp_max( bp );
        dl.AddRectFilled( min, max, hp_color( cur, hp_max ), shape->rounding );

        const auto hovered = ImGui::IsWindowHovered() && mouse.x >= min.x && mouse.x < max.x &&
                             mouse.y >= min.y && mouse.y < max.y;
        if( hovered ) {
            dl.AddRect( ImVec2( min.x - 2, min.y - 2 ), ImVec2( max.x + 2, max.y + 2 ), color::text,
                        shape->rounding + 2, 0, 1.5f );
            ImGui::SetTooltip( "%s  %d / %d", body_part_name_as_heading( bp, 1 ).c_str(), cur, hp_max );
        }
    }
}

auto draw_needs( const avatar &you ) -> void
{
    const auto &f = fonts();
    constexpr auto bar_width = 180.0f;
    constexpr auto bar_height = 5.0f;
    for( const auto &row : collect_needs( you ) ) {
        auto &dl = *ImGui::GetWindowDrawList();
        const auto pos = ImGui::GetCursorScreenPos();
        const auto state_size = text_size( f.heading, size::small, row.state );
        text_at( dl, f.body, size::small, pos, color::muted, row.label );
        text_at( dl, f.heading, size::small, ImVec2( pos.x + bar_width - state_size.x, pos.y ), row.col,
                 row.state );
        const auto bar_y = pos.y + size::small + 4.0f;
        dl.AddRectFilled( ImVec2( pos.x, bar_y ), ImVec2( pos.x + bar_width, bar_y + bar_height ),
                          color::track, 3.0f );
        const auto fill = std::clamp( row.fill, 0.0f, 1.0f );
        dl.AddRectFilled( ImVec2( pos.x, bar_y ), ImVec2( pos.x + bar_width * fill, bar_y + bar_height ),
                          row.col, 3.0f );
        ImGui::Dummy( ImVec2( bar_width, size::small + 4.0f + bar_height + 3.0f ) );
    }
}

auto draw_survivor_card( const avatar &you ) -> void
{
    const auto &f = fonts();
    ImGui::SetNextWindowPos( ImVec2( screen_margin, screen_margin ), ImGuiCond_Always );
    if( !ImGui::Begin( "##slate_survivor", nullptr, hud_window_flags ) ) {
        ImGui::End();
        return;
    }
    draw_silhouette( you );
    ImGui::SameLine( 0.0f, 16.0f );
    ImGui::BeginGroup();
    ImGui::PushFont( f.heading, size::title );
    ImGui::TextUnformatted( you.get_name().c_str() );
    ImGui::PopFont();
    const auto &weapon = you.primary_weapon();
    const auto wielding = weapon.is_null() ? std::string( _( "Unarmed" ) ) : weapon.tname();
    ImGui::PushFont( f.body, size::small );
    ImGui::PushStyleColor( ImGuiCol_Text, color::muted );
    ImGui::TextUnformatted( wielding.c_str() );
    ImGui::PopStyleColor();
    ImGui::PopFont();
    ImGui::Dummy( ImVec2( 0.0f, 2.0f ) );
    draw_needs( you );
    ImGui::EndGroup();

    const auto pain = you.get_pain_description();
    if( !pain.first.empty() ) {
        ImGui::PushFont( f.heading, size::small );
        ImGui::PushStyleColor( ImGuiCol_Text, severity_color( pain.second ) );
        ImGui::TextUnformatted( pain.first.c_str() );
        ImGui::PopStyleColor();
        ImGui::PopFont();
    }
    ImGui::End();
}

auto draw_dock_button( const dock_action &action ) -> void
{
    const auto &f = fonts();
    ImGui::PushID( action.id );
    const auto clicked = ImGui::InvisibleButton( "##dock", dock_button_size );
    const auto hovered = ImGui::IsItemHovered();
    const auto min = ImGui::GetItemRectMin();
    const auto max = ImGui::GetItemRectMax();
    auto &dl = *ImGui::GetWindowDrawList();
    if( hovered ) {
        dl.AddRectFilled( min, max, ImGui::IsItemActive() ? color::rgba( 0xf4, 0xb6, 0x3f,
                          90 ) : color::hover, 12.0f );
    }
    const auto label = std::string( _( action.label ) );
    const auto label_size = text_size( f.heading, size::body, label );
    text_at( dl, f.heading, size::body,
             ImVec2( min.x + ( dock_button_size.x - label_size.x ) * 0.5f, max.y - label_size.y - 9.0f ),
             color::text, label );
    const auto key = key_hint( action.id );
    if( !key.empty() ) {
        // Key chip: the bound key in a small pill above the label.
        const auto key_size = text_size( f.mono_bold, size::small, key );
        const auto chip_w = std::max( key_size.x + 12.0f, 22.0f );
        const auto chip_min = ImVec2( min.x + ( dock_button_size.x - chip_w ) * 0.5f, min.y + 8.0f );
        const auto chip_max = ImVec2( chip_min.x + chip_w, chip_min.y + key_size.y + 4.0f );
        dl.AddRectFilled( chip_min, chip_max, color::rgba( 0xf4, 0xb6, 0x3f, 38 ), 5.0f );
        text_at( dl, f.mono_bold, size::small,
                 ImVec2( chip_min.x + ( chip_w - key_size.x ) * 0.5f, chip_min.y + 2.0f ), color::accent, key );
    }
    if( hovered && !key.empty() ) {
        ImGui::SetTooltip( _( "Click, or press %s" ), key.c_str() );
    }
    if( clicked ) {
        imgui_layer::queue_action( action.id, default_mode );
    }
    ImGui::PopID();
}

auto draw_action_dock() -> void
{
    const auto &io = ImGui::GetIO();
    ImGui::SetNextWindowPos( ImVec2( io.DisplaySize.x * 0.5f, io.DisplaySize.y - screen_margin ),
                             ImGuiCond_Always,
                             ImVec2( 0.5f, 1.0f ) );
    ImGui::PushStyleVar( ImGuiStyleVar_WindowPadding, ImVec2( 8.0f, 8.0f ) );
    ImGui::PushStyleVar( ImGuiStyleVar_WindowRounding, 18.0f );
    ImGui::PushStyleVar( ImGuiStyleVar_ItemSpacing, ImVec2( 4.0f, 4.0f ) );
    if( ImGui::Begin( "##slate_dock", nullptr, hud_window_flags ) ) {
        auto first = true;
        for( const auto &action : dock_actions ) {
            if( !first ) {
                ImGui::SameLine();
            }
            first = false;
            draw_dock_button( action );
        }
    }
    ImGui::End();
    ImGui::PopStyleVar( 3 );
}

} // namespace

auto draw_hud() -> void
{
    const auto &you = get_avatar();
    draw_survivor_card( you );
    draw_action_dock();
}

} // namespace cata::slate

#endif // TILES
