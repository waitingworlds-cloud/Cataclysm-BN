#if defined(TILES)

#include "slate_theme.h"

#include <string>

#include "filesystem.h"
#include "path_info.h"

namespace cata::slate
{

namespace
{

auto font_storage() -> font_set & // *NOPAD*
{
    static auto storage = font_set{};
    return storage;
}

auto to_vec4( ImU32 col ) -> ImVec4
{
    return ImGui::ColorConvertU32ToFloat4( col );
}

/// Adds a font from data/font/, merging the bundled unifont behind it for glyphs it lacks
/// (CJK names, symbols). Returns nullptr when the file is missing.
auto add_font( const std::string &file ) -> ImFont *
{
    auto &io = ImGui::GetIO();
    const auto path = PATH_INFO::fontdir() + file;
    if( !file_exist( path ) ) {
        return nullptr;
    }
    auto *font = io.Fonts->AddFontFromFileTTF( path.c_str(), size::body );
    const auto fallback = PATH_INFO::fontdir() + "unifont.ttf";
    if( font != nullptr && file_exist( fallback ) ) {
        auto merge = ImFontConfig{};
        merge.MergeMode = true;
        io.Fonts->AddFontFromFileTTF( fallback.c_str(), size::body, &merge );
    }
    return font;
}

} // namespace

auto fonts() -> const font_set & // *NOPAD*
{
    return font_storage();
}

auto load_fonts() -> void
{
    auto &io = ImGui::GetIO();
    auto &f = font_storage();
    f.body = add_font( "slate/Manrope-Medium.ttf" );
    f.heading = add_font( "slate/Manrope-ExtraBold.ttf" );
    f.mono = add_font( "slate/JetBrainsMono-Regular.ttf" );
    f.mono_bold = add_font( "slate/JetBrainsMono-Bold.ttf" );
    if( f.body == nullptr ) {
        f.body = io.Fonts->AddFontDefault();
    }
    for( auto *slot : { &f.heading, &f.mono, &f.mono_bold } ) {
        if( *slot == nullptr ) {
            *slot = f.body;
        }
    }
    io.FontDefault = f.body;
}

auto apply_theme() -> void
{
    auto &style = ImGui::GetStyle();
    style.WindowRounding = 16.0f;
    style.ChildRounding = 12.0f;
    style.FrameRounding = 10.0f;
    style.PopupRounding = 12.0f;
    style.GrabRounding = 10.0f;
    style.TabRounding = 8.0f;
    style.ScrollbarRounding = 10.0f;
    style.WindowBorderSize = 1.0f;
    style.FrameBorderSize = 0.0f;
    style.PopupBorderSize = 1.0f;
    style.WindowPadding = ImVec2( 16.0f, 16.0f );
    style.FramePadding = ImVec2( 10.0f, 6.0f );
    style.ItemSpacing = ImVec2( 8.0f, 8.0f );
    style.ItemInnerSpacing = ImVec2( 6.0f, 6.0f );
    style.FontSizeBase = size::body;

    auto *c = style.Colors;
    c[ImGuiCol_Text] = to_vec4( color::text );
    c[ImGuiCol_TextDisabled] = to_vec4( color::disabled );
    c[ImGuiCol_WindowBg] = to_vec4( color::card );
    c[ImGuiCol_PopupBg] = to_vec4( color::rgba( 0x14, 0x1a, 0x23, 245 ) );
    c[ImGuiCol_Border] = to_vec4( color::card_border );
    c[ImGuiCol_FrameBg] = to_vec4( color::track );
    c[ImGuiCol_FrameBgHovered] = to_vec4( color::rgba( 255, 255, 255, 36 ) );
    c[ImGuiCol_FrameBgActive] = to_vec4( color::rgba( 255, 255, 255, 48 ) );
    c[ImGuiCol_Button] = to_vec4( color::rgba( 0, 0, 0, 0 ) );
    c[ImGuiCol_ButtonHovered] = to_vec4( color::hover );
    c[ImGuiCol_ButtonActive] = to_vec4( color::rgba( 0xf4, 0xb6, 0x3f, 90 ) );
    c[ImGuiCol_Header] = to_vec4( color::hover );
    c[ImGuiCol_HeaderHovered] = to_vec4( color::rgba( 255, 255, 255, 36 ) );
    c[ImGuiCol_HeaderActive] = to_vec4( color::rgba( 0xf4, 0xb6, 0x3f, 60 ) );
    c[ImGuiCol_Separator] = to_vec4( color::card_border );
    c[ImGuiCol_CheckMark] = to_vec4( color::accent );
    c[ImGuiCol_SliderGrab] = to_vec4( color::accent );
    c[ImGuiCol_SliderGrabActive] = to_vec4( color::accent );
    c[ImGuiCol_ScrollbarBg] = to_vec4( color::rgba( 0, 0, 0, 0 ) );
    c[ImGuiCol_ScrollbarGrab] = to_vec4( color::track );
    c[ImGuiCol_PlotHistogram] = to_vec4( color::accent );
    c[ImGuiCol_NavCursor] = to_vec4( color::accent );
}

} // namespace cata::slate

#endif // TILES
