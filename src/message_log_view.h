#pragma once

#include <cstddef>
#include <string>
#include <vector>

#include "color.h"

namespace Messages
{

/// One message as the sidebar log would show it.
struct log_line {
    std::string time;
    std::string text;
    nc_color color;
    /// Arrived since the player last looked at the log.
    bool fresh = false;
};

/// The newest messages the sidebar log would show, oldest first, at most `count` of them.
/// Marks them as seen, like drawing the sidebar log does.
auto sidebar_lines( std::size_t count ) -> std::vector<log_line>;

} // namespace Messages
