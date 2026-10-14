#pragma once

#if defined(TILES)

// Include Dear ImGui through this header rather than "imgui.h" directly.
// debug.h defines a function-like DebugLog macro, which collides with ImGui::DebugLog.
#pragma push_macro("DebugLog")
#undef DebugLog
#include "imgui.h" // IWYU pragma: export
#pragma pop_macro("DebugLog")

#endif // TILES
