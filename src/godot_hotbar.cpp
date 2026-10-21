#include "godot_hotbar.h"

#include <algorithm>
#include <optional>
#include <ranges>
#include <utility>

#include "avatar.h"
#include "avatar_action.h"
#include "color.h"
#include "item.h"
#include "item_contents.h"
#include "itype.h"
#include "json.h"
#include "messages.h"
#include "string_formatter.h"
#include "translations.h"
#include "type_id.h"

namespace
{

auto slots() -> std::vector<std::string> & // *NOPAD*
{
    static auto ids = std::vector<std::string>( 9 );
    return ids;
}

auto slot_type( const int slot ) -> std::optional<itype_id>
{
    if( slot < 0 || slot >= static_cast<int>( slots().size() ) || slots()[slot].empty() ) {
        return std::nullopt;
    }
    const auto id = itype_id( slots()[slot] );
    return id.is_valid() ? std::optional<itype_id>( id ) : std::nullopt;
}

/// The one kind of food or drink `it` holds, if that is all it holds.
auto sole_content( const item &it ) -> const item * // *NOPAD*
{
    if( it.contents.empty() || it.contents.num_item_stacks() != 1 ) {
        return nullptr;
    }
    const auto &inside = it.contents.front();
    return inside.is_comestible() ? &inside : nullptr;
}

/// Carried items of `type`, or containers holding only that, the wielded one first.
auto carried( const avatar &u, const itype_id &type ) -> std::vector<item *>
{
    auto found = u.items_with( [&type]( const item & it ) {
        const auto *inside = sole_content( it );
        return it.typeId() == type || ( inside != nullptr && inside->typeId() == type );
    } );
    // Food inside a matching container is used through the container, as the item card does.
    auto inner = std::vector<const item *> {};
    for( const auto *it : found ) {
        if( it->typeId() != type ) {
            inner.push_back( sole_content( *it ) );
        }
    }
    std::erase_if( found, [&inner]( const item * it ) {
        return std::ranges::contains( inner, it );
    } );
    std::ranges::stable_partition( found, [&u]( const item * it ) {
        return u.is_wielding( *it );
    } );
    return found;
}

auto carried_count( const std::vector<item *> &items, const itype_id &type ) -> int
{
    auto total = 0;
    for( const auto *it : items ) {
        total += it->typeId() == type ? it->count() : sole_content( *it )->count();
    }
    return total;
}

} // namespace

auto cata::godot_hotbar::type_for( const item &it ) -> std::string
{
    const auto *inside = sole_content( it );
    return ( inside != nullptr ? inside->typeId() : it.typeId() ).str();
}

auto cata::godot_hotbar::set_slots( std::vector<std::string> ids ) -> void
{
    ids.resize( 9 );
    slots() = std::move( ids );
}

auto cata::godot_hotbar::write( JsonOut &jsout ) -> void
{
    const auto &u = get_avatar();
    jsout.member( "hotbar" );
    jsout.start_array();
    for( auto slot = 0; slot < static_cast<int>( slots().size() ); ++slot ) {
        const auto type = slot_type( slot );
        if( !type ) {
            jsout.write_null();
            continue;
        }
        const auto items = carried( u, *type );
        jsout.start_object();
        jsout.member( "type", type->str() );
        const auto count = carried_count( items, *type );
        jsout.member( "name", item::nname( *type, std::max( count, 1 ) ) );
        jsout.member( "count", count );
        jsout.member( "sym", type->obj().sym );
        jsout.member( "color", string_from_color( type->obj().color ) );
        jsout.member( "wielded", !items.empty() && u.is_wielding( *items.front() ) );
        jsout.end_object();
    }
    jsout.end_array();
}

auto cata::godot_hotbar::use( const int slot ) -> void
{
    const auto type = slot_type( slot );
    if( !type ) {
        return;
    }
    auto &u = get_avatar();
    const auto items = carried( u, *type );
    if( items.empty() ) {
        add_msg( m_info, _( "You don't have any %s." ), item::nname( *type, 2 ) );
        return;
    }
    auto &it = *items.front();
    if( it.is_comestible() || it.is_food_container() ) {
        avatar_action::eat( u, &it );
    } else if( it.has_use() ) {
        avatar_action::use_item( u, &it );
    } else if( it.is_book() ) {
        u.read( &it );
    } else if( it.is_armor() && !u.is_worn( it ) ) {
        u.wear_possessed( it );
    } else {
        avatar_action::wield( it );
    }
}
