#pragma once

#if defined(TILES)

#include <cstdint>

#include "cata_imgui.h"

/// The "Slate" visual language for the ImGui layer: map first, floating rounded cards,
/// Manrope for UI text and JetBrains Mono for numbers and key hints.
namespace cata::slate
{

/// Palette, as packed 0xAABBGGRR colors ready for ImDrawList.
namespace color
{
constexpr auto rgba( std::uint8_t r, std::uint8_t g, std::uint8_t b, std::uint8_t a = 255 ) -> ImU32
{
    return IM_COL32( r, g, b, a );
}
inline constexpr auto ground = rgba( 0x10, 0x15, 0x1c );
inline constexpr auto card = rgba( 0x10, 0x15, 0x1c, 232 );
inline constexpr auto card_border = rgba( 255, 255, 255, 20 );
inline constexpr auto track = rgba( 255, 255, 255, 26 );
inline constexpr auto hover = rgba( 255, 255, 255, 24 );
inline constexpr auto text = rgba( 0xee, 0xf2, 0xf6 );
inline constexpr auto muted = rgba( 0xa7, 0xb3, 0xc2 );
inline constexpr auto accent = rgba( 0xf4, 0xb6, 0x3f );
inline constexpr auto ok = rgba( 0x5f, 0xd3, 0x9a );
inline constexpr auto warn = rgba( 0xf4, 0xb6, 0x3f );
inline constexpr auto danger = rgba( 0xff, 0x6b, 0x5e );
inline constexpr auto info = rgba( 0x6a, 0xa8, 0xff );
inline constexpr auto disabled = rgba( 0x6b, 0x76, 0x86 );
} // namespace color

struct font_set {
    ImFont *body = nullptr;
    ImFont *heading = nullptr;
    ImFont *mono = nullptr;
    ImFont *mono_bold = nullptr;
};

/// Type scale in unscaled pixels; pass these to ImGui::PushFont.
namespace size
{
inline constexpr auto small = 12.0f;
inline constexpr auto body = 14.0f;
inline constexpr auto title = 18.0f;
} // namespace size

/// Sets ImGui's global style (rounding, spacing, widget colors) to Slate.
auto apply_theme() -> void;

/// Loads the Slate fonts from the game's font directory into the ImGui atlas.
/// Falls back to ImGui's built-in font when a file is missing.
auto load_fonts() -> void;

auto fonts() -> const font_set &; // *NOPAD*

} // namespace cata::slate

#endif // TILES
