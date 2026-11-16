#pragma once

#include <memory>
#include <optional>

#include "coordinates.h"
#include "cursesdef.h"

class ui_adaptor;

class live_view
{
    public:
        live_view();
        ~live_view();

        void init();
        void show( const tripoint_bub_ms &p );
        bool is_enabled();
        void hide();

    private:
        tripoint_bub_ms mouse_position;

        catacurses::window win;
        std::unique_ptr<ui_adaptor> ui;
};

#if defined(TILES)
/// Map square the mouse rests on while the Godot front end is in use. Its hover card shows what
/// the "Mouse View" box would.
auto godot_hover_position() -> std::optional<tripoint_bub_ms>;
#endif
