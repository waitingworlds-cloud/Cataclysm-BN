#pragma once

#if defined(TILES)

#include <cstddef>
#include <cstdint>
#include <memory>
#include <string>

/// Minimal blocking TCP client used by the Godot bridge. Kept in its own translation unit so the
/// platform socket headers don't leak into game code.
namespace cata::godot_bridge::net
{

class connection
{
    public:
        /// Connects to `host:port`, or returns null when nothing is listening there.
        static auto open( const std::string &host, int port ) -> std::unique_ptr<connection>;

        ~connection();
        connection( const connection & ) = delete;
        auto operator=( const connection & ) -> connection & = delete; // *NOPAD*

        /// Writes all of `data`. False once the peer has gone away.
        auto send_all( const void *data, std::size_t size ) -> bool;
        /// Reads exactly `size` bytes into `data`. False once the peer has gone away.
        auto recv_all( void *data, std::size_t size ) -> bool;
        /// Stops both directions, waking any thread blocked in `recv_all`.
        auto shutdown() -> void;

    private:
        explicit connection( std::intptr_t handle );
        std::intptr_t handle;
};

} // namespace cata::godot_bridge::net

#endif // TILES
