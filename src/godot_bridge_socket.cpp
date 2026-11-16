#if defined(TILES)

#include "godot_bridge_socket.h"

#include <cstdint>
#include <string>

#if defined(_WIN32)
#   include <winsock2.h>
#   include <ws2tcpip.h>
#else
#   include <arpa/inet.h>
#   include <netinet/in.h>
#   include <netinet/tcp.h>
#   include <sys/socket.h>
#   include <unistd.h>
#endif

namespace cata::godot_bridge::net
{

namespace
{

#if defined(_WIN32)
using native_socket = SOCKET;
const auto invalid_native_socket = INVALID_SOCKET;
auto close_native( native_socket s ) -> void { closesocket( s ); }
auto ensure_started() -> bool
{
    static const auto started = [] {
        auto data = WSADATA{};
        return WSAStartup( MAKEWORD( 2, 2 ), &data ) == 0;
    }();
    return started;
}
#else
using native_socket = int;
const auto invalid_native_socket = -1;
auto close_native( native_socket s ) -> void { ::close( s ); }
auto ensure_started() -> bool { return true; }
#endif

auto as_native( std::intptr_t handle ) -> native_socket { return static_cast<native_socket>( handle ); }

} // namespace

connection::connection( std::intptr_t handle ) : handle( handle ) {}

connection::~connection()
{
    shutdown();
    close_native( as_native( handle ) );
}

auto connection::open( const std::string &host, int port ) -> std::unique_ptr<connection>
{
    if( !ensure_started() ) {
        return nullptr;
    }
    const auto s = ::socket( AF_INET, SOCK_STREAM, IPPROTO_TCP );
    if( s == invalid_native_socket ) {
        return nullptr;
    }
    auto addr = sockaddr_in{};
    addr.sin_family = AF_INET;
    addr.sin_port = htons( static_cast<std::uint16_t>( port ) );
    if( inet_pton( AF_INET, host.c_str(), &addr.sin_addr ) != 1 ||
        ::connect( s, reinterpret_cast<const sockaddr *>( &addr ), sizeof( addr ) ) != 0 ) {
        close_native( s );
        return nullptr;
    }
    // Frames are large and input events are tiny; neither should wait for Nagle.
    auto nodelay = 1;
    setsockopt( s, IPPROTO_TCP, TCP_NODELAY, reinterpret_cast<const char *>( &nodelay ),
                sizeof( nodelay ) );
    return std::unique_ptr<connection>( new connection( static_cast<std::intptr_t>( s ) ) );
}

auto connection::send_all( const void *data, std::size_t size ) -> bool
{
    const auto *bytes = static_cast<const char *>( data );
    while( size > 0 ) {
        const auto sent = ::send( as_native( handle ), bytes, static_cast<int>( size ), 0 );
        if( sent <= 0 ) {
            return false;
        }
        bytes += sent;
        size -= static_cast<std::size_t>( sent );
    }
    return true;
}

auto connection::recv_all( void *data, std::size_t size ) -> bool
{
    auto *bytes = static_cast<char *>( data );
    while( size > 0 ) {
        const auto got = ::recv( as_native( handle ), bytes, static_cast<int>( size ), 0 );
        if( got <= 0 ) {
            return false;
        }
        bytes += got;
        size -= static_cast<std::size_t>( got );
    }
    return true;
}

auto connection::shutdown() -> void
{
#if defined(_WIN32)
    ::shutdown( as_native( handle ), SD_BOTH );
#else
    ::shutdown( as_native( handle ), SHUT_RDWR );
#endif
}

} // namespace cata::godot_bridge::net

#endif // TILES
