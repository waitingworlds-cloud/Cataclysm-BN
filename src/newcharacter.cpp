#include "avatar.h" // IWYU pragma: associated
#include "newcharacter.h" // IWYU pragma: associated

#include <algorithm>
#include <array>
#include <climits>
#include <cstdlib>
#include <functional>
#include <iosfwd>
#include <iterator>
#include <list>
#include <map>
#include <memory>
#include <optional>
#include <ranges>
#include <set>
#include <tuple>
#include <unordered_map>
#include <utility>
#include <vector>

#include "addiction.h"
#include "bionics.h"
#include "cached_options.h"
#include "cata_utility.h"
#include "catacharset.h"
#include "debug.h"
#if defined(TILES)
#   include "character_preview.h"
#   include "cata_tiles.h"
#   include "godot_bridge.h"
#   include "godot_screen.h"
#endif
#include "character.h"
#include "character_martial_arts.h"
#include "color.h"
#include "cursesdef.h"
#include "enchantments/enchantment.h"
#include "filesystem.h"
#include "fstream_utils.h"
#include "game.h"
#include "game_constants.h"
#include "ime.h"
#include "input.h"
#include "int_id.h"
#include "inventory.h"
#include "json.h"
#include "magic/magic.h"
#include "make_static.h"
#include "map/lightmap.h"
#include "mapsharing.h"
#include "martialarts.h"
#include "monster.h"
#include "mutation.h"
#include "name.h"
#include "npc_class.h"
#include "options.h"
#include "output.h"
#include "path_info.h"
#include "pimpl.h"
#include "pldata.h"
#include "profession.h"
#include "ranged.h"
#include "recipe.h"
#include "recipe_dictionary.h"
#include "rng.h"
#include "scenario.h"
#include "sdltiles.h"
#include "skill.h"
#include "start_location.h"
#include "string_formatter.h"
#include "string_id.h"
#include "string_input_popup.h"
#include "string_utils.h"
#include "translations.h"
#include "type_id.h"
#include "ui.h"
#include "ui_manager.h"
#include "units_utility.h"
#include "vehicle/veh_type.h"
#include "worldfactory.h"

static const std::string flag_CHALLENGE( "CHALLENGE" );
static const std::string flag_CITY_START( "CITY_START" );
static const std::string flag_SECRET( "SECRET" );

static const std::string type_hair_style( "hair_style" );
static const std::string type_hair_color( "hair_color" );

static const flag_id json_flag_no_auto_equip( "no_auto_equip" );
static const flag_id json_flag_auto_wield( "auto_wield" );

static const trait_id trait_XS( "XS" );
static const trait_id trait_XXXL( "XXXL" );

static const trait_flag_str_id flag_MALE_EXCLUSIVE( "MALE_EXCLUSIVE" );
static const trait_flag_str_id flag_FEMALE_EXCLUSIVE( "FEMALE_EXCLUSIVE" );
static const trait_flag_str_id flag_MALE_PREFERRED( "MALE_PREFERRED" );
static const trait_flag_str_id flag_FEMALE_PREFERRED( "FEMALE_PREFERRED" );

static auto profession_age_limits_enabled() -> bool
{
    if( world_generator && world_generator->active_world ) {
        return world_generator->active_world->info->WORLD_OPTIONS["ENFORCE_PROFESSION_AGE_RANGE"]
               .value_as<bool>();
    }
    return false;
}

static auto profession_age_bounds( const profession &prof ) -> std::pair<int, int>
{
    if( profession_age_limits_enabled() ) {
        if( const auto range = prof.starting_age_range() ) {
            return { range->min, range->max };
        }
    }
    return { profession::min_age, profession::max_age };
}

static auto random_age_for_profession( const profession &prof ) -> int
{
    const auto [min_age, max_age] = profession_age_bounds( prof );
    if( min_age == max_age ) {
        return min_age;
    }
    return rng( min_age, max_age );
}

static auto scenario_is_selectable( const scenario &scen, const bool cities_enabled ) -> bool
{
    return !scen.scen_is_blacklisted() && ( !scen.has_flag( flag_CITY_START ) || cities_enabled );
}

static auto first_selectable_scenario( const bool cities_enabled ) -> const scenario * // *NOPAD*
{
    const auto &scenarios = scenario::get_all();
    const auto iter = std::ranges::find_if( scenarios, [cities_enabled]( const scenario & scen ) {
        return scenario_is_selectable( scen, cities_enabled );
    } );
    return iter != scenarios.end() ? &( *iter ) : scenario::generic();
}

static auto first_selectable_scenario( const std::vector<const scenario *> &scenarios,
                                       const bool cities_enabled ) -> const scenario * // *NOPAD*
{
    const auto iter = std::ranges::find_if( scenarios, [cities_enabled]( const scenario * scen ) {
        return scenario_is_selectable( *scen, cities_enabled );
    } );
    return iter != scenarios.end() ? *iter : scenarios.front();
}

// Colors used in this file: (Most else defaults to c_light_gray)
#define COL_STAT_ACT        c_white   // Selected stat
#define COL_STAT_BONUS      c_light_green // Bonus
#define COL_STAT_NEUTRAL    c_white   // Neutral Property
#define COL_STAT_PENALTY    c_light_red   // Penalty
#define COL_TR_GOOD         c_green   // Good trait descriptive text
#define COL_TR_GOOD_OFF_ACT c_light_gray  // A toggled-off good trait
#define COL_TR_GOOD_ON_ACT  c_light_green // A toggled-on good trait
#define COL_TR_GOOD_OFF_PAS c_dark_gray  // A toggled-off good trait
#define COL_TR_GOOD_ON_PAS  c_green   // A toggled-on good trait
#define COL_TR_BAD          c_red     // Bad trait descriptive text
#define COL_TR_BAD_OFF_ACT  c_light_gray  // A toggled-off bad trait
#define COL_TR_BAD_ON_ACT   c_light_red   // A toggled-on bad trait
#define COL_TR_BAD_OFF_PAS  c_dark_gray  // A toggled-off bad trait
#define COL_TR_BAD_ON_PAS   c_red     // A toggled-on bad trait
#define COL_TR_NEUT         c_brown     // Neutral trait descriptive text
#define COL_TR_NEUT_OFF_ACT c_dark_gray  // A toggled-off neutral trait
#define COL_TR_NEUT_ON_ACT  c_yellow   // A toggled-on neutral trait
#define COL_TR_NEUT_OFF_PAS c_dark_gray  // A toggled-off neutral trait
#define COL_TR_NEUT_ON_PAS  c_brown     // A toggled-on neutral trait
#define COL_SKILL_USED      c_green   // A skill with at least one point
#define COL_HEADER          c_white   // Captions, like "Profession items"
#define COL_NOTE_MINOR      c_light_gray  // Just regular note

enum {
    HIGH_STAT = 14 // The point after which stats cost double
};

namespace
{

static bool has_any_magic( const profession_id &prof )
{
    for( spell_type spell : spell_type::get_all() ) {
        if( spell.starting_spell || g->scen->spellquery( spell.id ) ||
            prof->is_allowed_spell( spell.id ) ) {
            return true;
        }
    }
    return false;
}

static int get_max_tabs( const profession_id &prof )
{
    int max = 8;
    if( prof->forbids_bionics() || g->scen->forbids_bionics() ) {
        max--;
    }
    if( !has_any_magic( prof ) || prof->forbids_spells() || g->scen->forbids_spells() ) {
        max--;
    }
    return max;
}
}

static int skill_increment_cost( const Character &u, const skill_id &skill );

enum struct tab_direction {
    NONE,
    FORWARD,
    BACKWARD,
    QUIT
};

tab_direction set_points( avatar &u, points_left &points );
tab_direction set_stats( avatar &u, points_left &points );
tab_direction set_traits( avatar &u, points_left &points );
tab_direction set_bionics( avatar &u, points_left &points );
tab_direction set_magic( avatar &u, points_left &points );
tab_direction set_scenario( avatar &u, points_left &points, tab_direction direction );
tab_direction set_profession( avatar &u, points_left &points, tab_direction direction );
tab_direction set_skills( avatar &u, points_left &points );
tab_direction set_description( avatar &you, bool allow_reroll, points_left &points );

static std::optional<std::string> query_for_template_name();
void reset_scenario( avatar &u, const scenario *scen );

#if defined(TILES)
namespace
{

namespace gs = cata::godot_screen;

/// The character creation tabs, in the order `avatar::create` steps through them.
enum class chargen_step : int {
    points,
    scenario,
    profession,
    stats,
    traits,
    bionics,
    magic,
    skills,
    overview,
};

/// Tab clicked in the Godot front end; `avatar::create` goes there once the current tab returns.
auto chargen_jump = std::optional<int> {};

/// Tabs shown for `prof`; a tab's position is its number in `avatar::create`.
auto chargen_steps( const profession_id &prof ) -> std::vector<chargen_step>
{
    auto steps = std::vector{ chargen_step::points, chargen_step::scenario, chargen_step::profession,
                              chargen_step::stats, chargen_step::traits };
    if( !prof->forbids_bionics() && !g->scen->forbids_bionics() ) {
        steps.push_back( chargen_step::bionics );
    }
    if( has_any_magic( prof ) && !prof->forbids_spells() && !g->scen->forbids_spells() ) {
        steps.push_back( chargen_step::magic );
    }
    steps.push_back( chargen_step::skills );
    steps.push_back( chargen_step::overview );
    return steps;
}

struct step_label {
    std::string text;
    std::string icon;
};

auto label_of( const chargen_step step ) -> step_label
{
    switch( step ) {
        case chargen_step::points:
            return { .text = _( "Points" ), .icon = "coins" };
        case chargen_step::scenario:
            return { .text = _( "Scenario" ), .icon = "map" };
        case chargen_step::profession:
            return { .text = _( "Profession" ), .icon = "briefcase" };
        case chargen_step::stats:
            return { .text = _( "Stats" ), .icon = "chart-column" };
        case chargen_step::traits:
            return { .text = _( "Traits" ), .icon = "dna" };
        case chargen_step::bionics:
            return { .text = _( "Bionics" ), .icon = "cpu" };
        case chargen_step::magic:
            return { .text = _( "Magic" ), .icon = "sparkles" };
        case chargen_step::skills:
            return { .text = _( "Skills" ), .icon = "graduation-cap" };
        case chargen_step::overview:
            return { .text = _( "Overview" ), .icon = "id-card" };
    }
    return {};
}

/// Number of `step` among the tabs shown for `prof`.
auto step_index( const chargen_step step, const profession_id &prof ) -> int
{
    const auto steps = chargen_steps( prof );
    return static_cast<int>( std::ranges::find( steps, step ) - steps.begin() );
}

/// Direction that leaves `current` when `pick` is a click on another tab; the tab is remembered
/// in `chargen_jump`.
auto chargen_tab_click( const int pick, const chargen_step current,
                        const profession_id &prof ) -> std::optional<tab_direction>
{
    const auto to = pick - gs::tab_pick;
    const auto from = step_index( current, prof );
    if( pick < gs::tab_pick || pick >= gs::subtab_pick || to == from ||
        to >= static_cast<int>( chargen_steps( prof ).size() ) ) {
        return std::nullopt;
    }
    chargen_jump = to;
    return to > from ? tab_direction::FORWARD : tab_direction::BACKWARD;
}

/// Native view for a character creation tab: it covers the whole screen.
auto chargen_view( ui_adaptor &ui, const avatar &u, const std::string &category,
                   const std::function<void( ui_adaptor & )> &init_windows )
-> std::unique_ptr<cata::godot_bridge::native_view>
{
    if( !cata::godot_bridge::native_screens() ) {
        return nullptr;
    }
    auto view = std::make_unique<cata::godot_bridge::native_view>( "screen", &u, category );
    view->attach( ui );
    ui.on_screen_resize( [init_windows]( ui_adaptor & ui ) {
        init_windows( ui );
        ui.position( point_zero, point_zero );
    } );
    ui.position( point_zero, point_zero );
    return view;
}

/// What every character creation tab shows around its own content.
struct chargen_frame {
    const avatar &u;
    const points_left &points;
    chargen_step step = chargen_step::points;
    /// Input category of the tab's keys.
    std::string category;
    /// Change to the points if the highlighted entry were chosen.
    int net_cost = 0;
    /// More header chips, after the points.
    std::vector<gs::stat> extra = {};
};

auto pool_color( const int left ) -> nc_color
{
    return left >= 0 ? c_light_gray : c_red;
}

auto write_points_stats( JsonOut &jsout, const points_left &points ) -> void
{
    switch( points.limit ) {
        case points_left::MULTI_POOL: {
            const auto valid = points.stat_points_left() >= 0 && points.trait_points_left() >= 0 &&
                               points.skill_points_left() >= 0;
            gs::write_stat( jsout, { .icon = "chart-column", .label = _( "Stats" ),
                                     .value = { .text = std::to_string( points.stat_points ), .color = pool_color( points.stat_points_left() ) }
                                   } );
            gs::write_stat( jsout, { .icon = "dna", .label = _( "Traits" ),
                                     .value = { .text = std::to_string( points.trait_points ), .color = pool_color( points.trait_points_left() ) }
                                   } );
            gs::write_stat( jsout, { .icon = "graduation-cap", .label = _( "Skills" ),
                                     .value = { .text = std::to_string( points.skill_points ), .color = pool_color( points.skill_points_left() ) }
                                   } );
            gs::write_stat( jsout, { .icon = "coins", .label = _( "Points left" ),
                                     .value = { .text = std::to_string( points.skill_points_left() ), .color = valid ? c_white : c_red },
                                     .tip = _( "Stats, traits and skills have separate point pools.\n"
                                               "Putting stat points into traits and skills is allowed and putting trait points into skills is allowed.\n"
                                               "Scenarios and professions affect skill point pool." )
                                   } );
            break;
        }
        case points_left::ONE_POOL:
            gs::write_stat( jsout, { .icon = "coins", .label = _( "Points left" ),
                                     .value = { .text = std::to_string( points.skill_points_left() ), .color = pool_color( points.skill_points_left() ) }
                               } );
            break;
        case points_left::TRANSFER:
            gs::write_stat( jsout, { .icon = "coins", .value = { .text = _( "Character Transfer: No changes can be made." ) } } );
            break;
        case points_left::FREEFORM:
            gs::write_stat( jsout, { .icon = "coins", .value = { .text = _( "Freeform" ) } } );
            break;
    }
}

/// Writes the title, tabs and point counts.
auto write_chargen_frame( JsonOut &jsout, const chargen_frame &f ) -> void
{
    jsout.member( "title", _( "New character" ) );
    jsout.member( "icon", "user-plus" );
    jsout.member( "size", std::array{ 1560, 980 } );
    jsout.member( "subtitle" );
    gs::write_span( jsout, { .text = string_format( "%s%s  ·  %s%s", _( "Scenario: " ),
                                     g->scen->gender_appropriate_name( f.u.male ), _( "Profession: " ),
                                     f.u.prof->gender_appropriate_name( f.u.male ) )
                           } );
    jsout.member( "tabs" );
    jsout.start_array();
    for( const auto &[i, step] : chargen_steps( f.u.prof ) | std::views::enumerate ) {
        const auto label = label_of( step );
        gs::write_tab( jsout, { .text = label.text, .active = step == f.step,
                                .pick = gs::tab_pick + static_cast<int>( i ), .icon = label.icon
                              } );
    }
    jsout.end_array();
    gs::write_tab_keys( jsout, "PREV_TAB", "NEXT_TAB", f.category );
    jsout.member( "stats" );
    jsout.start_array();
    write_points_stats( jsout, f.points );
    if( f.net_cost != 0 ) {
        gs::write_stat( jsout, { .label = _( "If chosen" ),
                                 .value = { .text = string_format( "%+d", -f.net_cost ), .color = f.net_cost > 0 ? c_red : c_green }
                               } );
    }
    for( const auto &s : f.extra ) {
        gs::write_stat( jsout, s );
    }
    jsout.end_array();
}

/// The primary button: on to the next tab.
auto write_next_button( JsonOut &jsout, const chargen_frame &f ) -> void
{
    const auto steps = chargen_steps( f.u.prof );
    const auto next = static_cast<size_t>( step_index( f.step, f.u.prof ) + 1 );
    const auto text = next < steps.size() ? string_format( _( "Next: %s" ),
                      label_of( steps[next] ).text ) :
                      std::string( _( "Finish" ) );
    gs::write_button( jsout, { .act = "NEXT_TAB", .text = text, .icon = "chevron-right", .category = f.category, .primary = true } );
}

/// Footer hints every tab shows last.
auto write_nav_hints( JsonOut &jsout, const std::string &category ) -> void
{
    gs::write_hint( jsout, "PREV_TAB", category, _( "Previous tab" ) );
    gs::write_hint( jsout, "NEXT_TAB", category, _( "Next tab" ) );
    gs::write_hint( jsout, "QUIT", category, _( "Main menu" ) );
}

/// Buttons that re-roll the whole character.
auto write_reroll_toggles( JsonOut &jsout, const std::string &category,
                           const bool appearance ) -> void
{
    gs::write_toggle( jsout, { .act = "REROLL_CHARACTER", .text = _( "Random character" ), .icon = "dices", .category = category,
                               .tip = _( "Reroll random character" )
                             }, false );
    gs::write_toggle( jsout, { .act = "REROLL_CHARACTER_WITH_SCENARIO", .text = _( "Random scenario too" ), .icon = "shuffle",
                               .category = category, .tip = _( "Reroll random character with scenario" )
                             }, false );
    if( appearance ) {
        gs::write_toggle( jsout, { .act = "REROLL_APPEARANCE", .text = _( "Random looks" ), .icon = "palette", .category = category,
                                   .tip = _( "Reroll appearance" )
                                 }, false );
    }
}

/// What choosing an entry does to the points: `-2` in red for a cost of 2.
auto cost_span( const int cost ) -> gs::span
{
    if( cost == 0 ) {
        return { .text = "0", .color = c_dark_gray };
    }
    return { .text = string_format( "%+d", -cost ), .color = cost > 0 ? c_light_red : c_light_green };
}

/// A scenario or profession in the list to choose from.
struct choice_row {
    std::string name;
    int cost = 0;
    bool chosen = false;
    /// Can't be chosen in this world.
    bool unavailable = false;
};

auto write_choice_row( JsonOut &jsout, const choice_row &c ) -> void
{
    const auto color = c.chosen ? COL_SKILL_USED : c.unavailable ? c_dark_gray : c_light_gray;
    gs::write_row( jsout, { .text = { .text = c.name, .color = color }, .cells = { cost_span( c.cost ) },
                            .note = { .text = c.chosen ? _( "Chosen" ) : "", .color = COL_SKILL_USED }
                          } );
}

/// Search box and toggles above the scenario and profession lists.
struct choice_toolbar {
    std::string category;
    std::string filter;
    std::string placeholder;
    bool by_points = true;
    /// The character's gender, when the list can switch it.
    std::optional<bool> male = std::nullopt;
};

auto write_choice_toolbar( JsonOut &jsout, const choice_toolbar &t ) -> void
{
    jsout.member( "search" );
    jsout.start_object();
    jsout.member( "text", t.filter );
    jsout.member( "act", "FILTER" );
    jsout.member( "key", cata::godot_bridge::key_label( "FILTER", t.category ) );
    jsout.member( "placeholder", t.placeholder );
    jsout.end_object();
    jsout.member( "toggles" );
    jsout.start_array();
    gs::write_toggle( jsout, { .act = "SORT", .text = string_format( _( "Sort by: %s" ), t.by_points ? _( "points" ) : _( "name" ) ),
                               .icon = "arrow-down-up", .category = t.category
                             }, false );
    if( t.male ) {
        gs::write_toggle( jsout, { .act = "CHANGE_GENDER", .text = *t.male ? _( "Male" ) : _( "Female" ), .icon = "users",
                                   .category = t.category, .tip = _( "Change gender" )
                                 }, false );
    }
    jsout.end_array();
}

/// A trait or bionic on the traits or bionics tab.
struct pick_entry {
    std::string name;
    int points = 0;
    bool has = false;
    bool blocked = false;
};

/// The traits or bionics tab: advantages, disadvantages and neutral ones side by side.
struct pick_pages {
    std::array<std::vector<pick_entry>, 3> pages = {};
    int used_pages = 3;
    int page = 0;
    std::array<int, 3> cursors = {};
    /// Description of the highlighted entry.
    std::string description = {};
    /// Button texts that add or remove the highlighted entry.
    std::string add_text = {};
    std::string remove_text = {};
    /// The character's sprite shown above the description, when the preview is on.
    const character_preview_window *preview = nullptr;
};

/// Godot covers the game's frame and crops the character preview out of it, so the preview gets
/// room for its largest zoom instead of squeezing beside the lists.
auto prepare_native_preview( character_preview_window &preview ) -> void
{
    constexpr auto orientation = character_preview_window::Orientation{ .type = character_preview_window::TOP_LEFT };
    preview.prepare( TERMY - 2, TERMX - 2, &orientation, 0 );
}

/// Where Godot finds the character in the frame, for the side panel. `category` holds the zoom and
/// clothes keys; a tab without them passes it empty and gets no buttons.
auto write_preview( JsonOut &jsout, const character_preview_window &preview,
                    const std::string &category ) -> void
{
    const auto area = preview.drawn_area();
    if( !area ) {
        return;
    }
    jsout.member( "preview" );
    jsout.start_object();
    jsout.member( "rect", std::array{ area->at.x, area->at.y, area->size.x, area->size.y } );
    jsout.member( "buttons" );
    jsout.start_array();
    if( !category.empty() ) {
        gs::write_button( jsout, { .act = "zoom_out", .text = _( "Zoom out" ), .icon = "zoom-out", .category = category } );
        gs::write_button( jsout, { .act = "zoom_in", .text = _( "Zoom in" ), .icon = "zoom-in", .category = category } );
        // clothes_showing() is true while the clothes are hidden.
        gs::write_toggle( jsout, { .act = "TOGGLE_CHARACTER_PREVIEW_CLOTHES", .text = _( "Clothes" ), .icon = "shirt", .category = category },
                          !preview.clothes_showing() );
    }
    jsout.end_array();
    jsout.end_object();
}

auto write_pick_pages( JsonOut &jsout, const chargen_frame &f, const pick_pages &p ) -> void
{
    struct page_style {
        std::string title;
        std::string icon;
        nc_color on;
        nc_color text;
    };
    const auto styles = std::array{
        page_style{ .title = _( "Advantages" ), .icon = "chevrons-up", .on = COL_TR_GOOD_ON_ACT, .text = COL_TR_GOOD },
        page_style{ .title = _( "Disadvantages" ), .icon = "chevrons-down", .on = COL_TR_BAD_ON_ACT, .text = COL_TR_BAD },
        page_style{ .title = _( "Neutral" ), .icon = "circle-dot", .on = COL_TR_NEUT_ON_ACT, .text = COL_TR_NEUT },
    };
    jsout.member( "active_pane", p.page );
    jsout.member( "panes" );
    jsout.start_array();
    for( auto page = 0; page < p.used_pages; page++ ) {
        const auto &entries = p.pages[page];
        const auto &style = styles[page];
        jsout.start_object();
        jsout.member( "title", style.title );
        jsout.member( "icon", style.icon );
        const auto taken = std::ranges::count_if( entries, &pick_entry::has );
        jsout.member( "count", taken > 0 ? string_format( "%d / %d", static_cast<int>( taken ),
                      static_cast<int>( entries.size() ) ) :
                      std::to_string( entries.size() ) );
        jsout.member( "cursor", p.cursors[page] );
        jsout.member( "mark_act", "CONFIRM" );
        jsout.member( "empty", _( "None!" ) );
        jsout.member( "rows" );
        jsout.start_array();
        for( const auto &e : entries ) {
            gs::write_row( jsout, { .text = { .text = e.name, .color = e.has ? style.on : e.blocked ? c_dark_gray : c_light_gray },
            .cells = { { .text = std::to_string( std::abs( e.points ) ), .color = e.blocked && !e.has ? c_dark_gray : style.text } },
            .mark = e.has
                                  } );
        }
        jsout.end_array();
        jsout.end_object();
    }
    jsout.end_array();

    jsout.member( "aside" );
    jsout.start_object();
    jsout.member( "width", 460 );
    if( p.preview != nullptr ) {
        write_preview( jsout, *p.preview, f.category );
    }
    const auto &entries = p.pages[p.page];
    const auto cursor = p.cursors[p.page];
    const auto has_entry = cursor >= 0 && static_cast<size_t>( cursor ) < entries.size();
    if( has_entry ) {
        const auto &e = entries[cursor];
        const auto &style = styles[p.page];
        const auto cost = std::abs( e.points );
        jsout.member( "title" );
        gs::write_span( jsout, { .text = e.name, .color = c_white } );
        jsout.member( "subtitle", style.title );
        jsout.member( "body" );
        gs::write_span( jsout, { .text = colorize( string_format( vgettext( "%s %s %d point", "%s %s %d points", cost ), e.name,
                                         e.points < 0 ? _( "earns" ) : _( "costs" ), cost ), style.text ) + "\n\n" + p.description
                               } );
    }
    jsout.member( "buttons" );
    jsout.start_array();
    if( has_entry ) {
        const auto &e = entries[cursor];
        gs::write_button( jsout, { .act = "CONFIRM", .text = e.has ? p.remove_text : p.add_text, .icon = e.has ? "minus" : "plus",
                                   .category = f.category, .enabled = e.has || !e.blocked
                                 } );
    }
    write_next_button( jsout, f );
    jsout.end_array();
    jsout.end_object();

    jsout.member( "toggles" );
    jsout.start_array();
    write_reroll_toggles( jsout, f.category, true );
    jsout.end_array();

    jsout.member( "hints" );
    jsout.start_array();
    gs::write_fixed_hint( jsout, "↑↓", _( "Choose" ) );
    gs::write_fixed_hint( jsout, "←→", _( "Switch list" ) );
    gs::write_hint( jsout, "CONFIRM", f.category, _( "Take or remove" ) );
    gs::write_hint( jsout, "RANDOMIZE", f.category, _( "Random pick" ) );
    write_nav_hints( jsout, f.category );
    jsout.end_array();
}

} // namespace
#endif

void Character::pick_name( bool bUseDefault )
{
    if( bUseDefault && !get_option<std::string>( "DEF_CHAR_NAME" ).empty() ) {
        name = get_option<std::string>( "DEF_CHAR_NAME" );
    } else {
        name = Name::generate( male );
    }
}

static matype_id choose_ma_style( const character_type type, const std::vector<matype_id> &styles,
                                  const avatar &u )
{
    if( type == character_type::NOW || type == character_type::FULL_RANDOM ) {
        return random_entry( styles );
    }
    if( styles.size() == 1 ) {
        return styles.front();
    }

    input_context ctxt( "MELEE_STYLE_PICKER" );
    ctxt.register_action( "SHOW_DESCRIPTION" );

    uilist menu;
    menu.allow_cancel = false;
    menu.text = string_format( _( "Select a style.\n"
                                  "\n"
                                  "STR: <color_white>%d</color>, DEX: <color_white>%d</color>, "
                                  "PER: <color_white>%d</color>, INT: <color_white>%d</color>\n"
                                  "Press [<color_yellow>%s</color>] for more info.\n" ),
                               u.get_str(), u.get_dex(), u.get_per(), u.get_int(),
                               ctxt.get_desc( "SHOW_DESCRIPTION" ) );
    ma_style_callback callback( 0, styles );
    menu.callback = &callback;
    menu.input_category = "MELEE_STYLE_PICKER";
    menu.additional_actions.emplace_back( "SHOW_DESCRIPTION", translation() );
    menu.desc_enabled = true;

    for( auto &s : styles ) {
        auto &style = s.obj();
        menu.addentry_desc( style.name.translated(), style.description.translated() );
    }
    while( true ) {
        menu.query( true );
        auto &selected = styles[menu.ret];
        if( query_yn( _( "Use this style?" ) ) ) {
            return selected;
        }
    }
}

/**
 * Check if the given player can pick this job with the given amount
 * of points.
 *
 * @return true, if player can pick profession. Otherwise - false.
 */
static bool can_pick_prof( const profession &prof, const Character &u, int points )
{
    return prof.point_cost() - u.prof->point_cost() <= points;
}

static void learn_spells( const profession &prof, avatar &you )
{
    for( const std::pair<spell_id, int> spell_pair : prof.spells() ) {
        you.magic->learn_spell( spell_pair.first, you, true );
        spell &sp = you.magic->get_spell( spell_pair.first );
        sp.gain_levels( spell_pair.second );
    }
}

void avatar::randomize( const bool random_scenario, points_left &points, bool play_now )
{
    const int max_stat_points = points.is_freeform() ? 20 : MAX_STAT;
    const int max_trait_points = get_option<int>( "MAX_TRAIT_POINTS" );
    // Reset everything to the defaults to have a clean state.
    *this = avatar();

    male = ( rng( 1, 100 ) > 50 );
    if( !MAP_SHARING::isSharing() ) {
        play_now ? pick_name() : pick_name( true );
    } else {
        name = MAP_SHARING::getUsername();
    }
    // if adjusting min and max height from 145 and 200, make sure to see set_description()
    init_height = rng( 145, 200 );
    const auto cities_enabled =
        world_generator->active_world->info->WORLD_OPTIONS["CITY_SIZE"].getValue() !=
        "0";
    if( random_scenario ) {
        std::vector<const scenario *> scenarios;
        for( const auto &scen : scenario::get_all() ) {
            if( !scen.has_flag( flag_CHALLENGE ) && scenario_is_selectable( scen, cities_enabled ) ) {
                scenarios.emplace_back( &scen );
            }
        }
        if( scenarios.empty() ) {
            g->scen = first_selectable_scenario( cities_enabled );
        } else {
            g->scen = random_entry( scenarios );
        }
    } else if( !scenario_is_selectable( *g->scen, cities_enabled ) ) {
        g->scen = first_selectable_scenario( cities_enabled );
    }

    prof = g->scen->weighted_random_profession();
    random_start_location = true;
    // if adjusting min and max age from 16 and 55, make sure to see set_description()
    set_base_age( random_age_for_profession( *prof ) );

    str_max = rng( 6, HIGH_STAT - 2 );
    dex_max = rng( 6, HIGH_STAT - 2 );
    int_max = rng( 6, HIGH_STAT - 2 );
    per_max = rng( 6, HIGH_STAT - 2 );
    points.stat_points = points.stat_points - str_max - dex_max - int_max - per_max;
    points.skill_points = points.skill_points - prof->point_cost() - g->scen->point_cost();
    // The default for each stat is 8, and that default does not cost any points.
    // Values below give points back, values above require points. The line above has removed
    // to many points, therefore they are added back.
    points.stat_points += 8 * 4;

    int num_gtraits = 0;
    int num_btraits = 0;
    int tries = 0;
    newcharacter::add_traits( *this, points ); // adds mandatory profession/scenario traits.
    for( const trait_id &mut : get_mutations() ) {
        const mutation_branch &mut_info = mut.obj();
        if( mut_info.profession ) {
            continue;
        }
        // Scenario/profession traits do not cost any points, but they are counted toward
        // the limit (MAX_TRAIT_POINTS)
        if( mut_info.points >= 0 ) {
            num_gtraits += mut_info.points;
        } else {
            num_btraits -= mut_info.points;
        }
    }

    /* The loops variable is used to prevent the algorithm running in an infinite loop */
    unsigned int loops = 0;

    while( loops <= 100000 && ( !points.is_valid() || rng( -3, 20 ) > points.skill_points_left() ) ) {
        loops++;
        trait_id rn;
        if( num_btraits < max_trait_points && one_in( 3 ) ) {
            tries = 0;
            do {
                rn = newcharacter::random_bad_trait();
                tries++;
            } while( ( has_trait( rn ) || num_btraits - rn->points > max_trait_points ) &&
                     tries < 5 );

            if( tries < 5 && !newcharacter::has_conflicting_trait( *this, rn ) ) {
                toggle_trait( rn );
                points.trait_points -= rn->points;
                num_btraits -= rn->points;
            }
        } else {
            switch( rng( 1, 4 ) ) {
                case 1:
                    if( str_max > 5 ) {
                        str_max--;
                        points.stat_points++;
                    }
                    break;
                case 2:
                    if( dex_max > 5 ) {
                        dex_max--;
                        points.stat_points++;
                    }
                    break;
                case 3:
                    if( int_max > 5 ) {
                        int_max--;
                        points.stat_points++;
                    }
                    break;
                case 4:
                    if( per_max > 5 ) {
                        per_max--;
                        points.stat_points++;
                    }
                    break;
            }
        }
    }

    loops = 0;
    while( points.has_spare() && loops <= 100000 ) {
        const bool allow_stats = points.stat_points_left() > 0;
        const bool allow_traits = points.trait_points_left() > 0 && num_gtraits < max_trait_points;
        int r = rng( 1, 9 );
        trait_id rn;
        switch( r ) {
            case 1:
            case 2:
            case 3:
            case 4:
                if( allow_traits ) {
                    rn = newcharacter::random_good_trait();
                    auto &mdata = rn.obj();
                    if( !has_trait( rn ) && points.trait_points_left() >= mdata.points &&
                        num_gtraits + mdata.points <= max_trait_points &&
                        !newcharacter::has_conflicting_trait( *this, rn ) ) {
                        toggle_trait( rn );
                        points.trait_points -= mdata.points;
                        num_gtraits += mdata.points;
                    }
                    break;
                }
            /* fallthrough */
            case 5:
                if( allow_stats ) {
                    switch( rng( 1, 4 ) ) {
                        case 1:
                            if( str_max < HIGH_STAT ) {
                                str_max++;
                                points.stat_points--;
                            } else if( points.stat_points_left() >= 2 && str_max < max_stat_points ) {
                                str_max++;
                                points.stat_points = points.stat_points - 2;
                            }
                            break;
                        case 2:
                            if( dex_max < HIGH_STAT ) {
                                dex_max++;
                                points.stat_points--;
                            } else if( points.stat_points_left() >= 2 && dex_max < max_stat_points ) {
                                dex_max++;
                                points.stat_points = points.stat_points - 2;
                            }
                            break;
                        case 3:
                            if( int_max < HIGH_STAT ) {
                                int_max++;
                                points.stat_points--;
                            } else if( points.stat_points_left() >= 2 && int_max < max_stat_points ) {
                                int_max++;
                                points.stat_points = points.stat_points - 2;
                            }
                            break;
                        case 4:
                            if( per_max < HIGH_STAT ) {
                                per_max++;
                                points.stat_points--;
                            } else if( points.stat_points_left() >= 2 && per_max < max_stat_points ) {
                                per_max++;
                                points.stat_points = points.stat_points - 2;
                            }
                            break;
                    }
                    break;
                }
            /* fallthrough */
            case 6:
            case 7:
            case 8:
            case 9:
                const skill_id aSkill = Skill::random_skill();
                const int level = get_skill_level( aSkill, true );

                if( level < points.skill_points_left() && level < MAX_SKILL && loops > 10000 ) {
                    points.skill_points -= skill_increment_cost( *this, aSkill );
                    // For balance reasons, increasing a skill from level 0 gives you 1 extra level for free
                    set_skill_level( aSkill, ( level == 0 ? 2 : level + 1 ) );
                }
                break;
        }
        loops++;
    }

    randomize_cosmetics();
    set_body();
}

void Character::clear_cosmetic_traits( std::string mutation_type, trait_id new_trait )
{
    for( const mutation_branch &mb : mutation_branch::get_all() ) {
        if( mb.points == 0 && mb.types.contains( mutation_type ) ) {
            if( has_trait( mb.id ) && mb.id != new_trait ) {
                toggle_trait( mb.id );
            }
        }
    }
}

namespace
{

auto set_cosmetic_trait( Character &c, std::string mutation_type, const trait_id &trait ) -> void
{
    if( trait.is_valid() ) {
        c.clear_cosmetic_traits( mutation_type, trait );

        if( !c.has_trait( trait ) ) {
            c.toggle_trait( trait );
        }
    }
}

auto selected_cosmetic_trait( const Character &c,
                              const std::string &mutation_type ) -> std::optional<trait_id>
{
    const auto mutations = get_mutations_in_type( mutation_type );
    const auto has_trait = std::bind_front( &Character::has_trait, &c );
    const auto selected = std::ranges::find_if( mutations, has_trait );
    return selected != mutations.end() ? std::optional<trait_id>( *selected ) : std::nullopt;
}

auto restore_cosmetic_trait( Character &c, const std::string &mutation_type,
                             const std::optional<trait_id> &trait ) -> void
{
    if( trait && g->scen->traitquery( *trait ) ) {
        set_cosmetic_trait( c, mutation_type, *trait );
    }
}

auto default_hair_style_for( const avatar &u ) -> trait_id
{
    static const auto male_default_hair_style = trait_id( "hair_medium" );
    static const auto female_default_hair_style = trait_id( "hair_long" );
    return u.male ? male_default_hair_style : female_default_hair_style;
}

auto set_default_hair_style( avatar &u ) -> void
{
    set_cosmetic_trait( u, type_hair_style, default_hair_style_for( u ) );
}

auto restore_or_default_hair_style( avatar &u, const std::optional<trait_id> &hair_style ) -> void
{
    restore_cosmetic_trait( u, type_hair_style, hair_style );
    if( !selected_cosmetic_trait( u, type_hair_style ) ) {
        set_default_hair_style( u );
    }
}

} // namespace

void avatar::randomize_cosmetics()
{
    std::ranges::for_each( get_all_mutation_type_ids(), [this]( const std::string & type_id ) {
        const bool mandatory = mutation_type_is_mandatory( type_id );
        const int chance = mutation_type_random_chance( type_id );
        if( mandatory || ( chance > 0 && x_in_y( chance, 100 ) ) ) {
            randomize_cosmetic_trait( type_id );
        }
    } );
}

bool avatar::create( character_type type, const std::string &tempname )
{
    // TODO: This block should not be needed
    if( get_body().contains( body_part_arm_r ) ) {
        remove_primary_weapon();
    }

    prof = profession::generic();
    g->scen = scenario::generic();
    male = get_option<std::string>( "DEF_CHAR_GENDER" ) == "male";

    const bool interactive = type != character_type::NOW &&
                             type != character_type::FULL_RANDOM;

    int tab = 0;
    points_left points = points_left();

    switch( type ) {
        case character_type::CUSTOM:
            // We can randomize cosmetics for a custom character, it's fine. Not sure I like the idea of a "default" appearance
            randomize_cosmetics();
            // don't make them bald!
            set_default_hair_style( *this );
            break;
        case character_type::RANDOM:
            //random scenario, default name if exist
            randomize( true, points );
            tab = get_max_tabs( prof );
            break;
        case character_type::NOW:
            //default world, fixed scenario, random name
            randomize( false, points, true );
            break;
        case character_type::FULL_RANDOM:
            //default world, random scenario, random name
            randomize( true, points, true );
            break;
        case character_type::TEMPLATE:
            if( !load_template( tempname, points ) ) {
                return false;
            }
            // We want to prevent recipes known by the template from being applied to the
            // new character. The recipe list will be rebuilt when entering the game.
            // Except if it is a character transfer template
            if( points.limit != points_left::TRANSFER ) {
                learned_recipes->clear();
            }
            tab = get_max_tabs( prof );
            break;
    }

    auto nameExists = [&]( const std::string & name ) {
        return world_generator->active_world->info->save_exists( save_t::from_save_id( name ) ) &&
               !query_yn( _( "A save with the name '%s' already exists in this world.\n"
                             "Saving will overwrite the already existing character.\n\n"
                             "Continue anyways?" ), name );
    };
    set_body();
    const bool allow_reroll = true;
    tab_direction result = tab_direction::QUIT;
    do {
        if( !interactive ) {
            // no window is created because "Play now"  does not require any configuration
            if( nameExists( name ) ) {
                return false;
            }

            break;
        }

        if( points.limit == points_left::TRANSFER ) {
            tab = get_max_tabs( prof );
        }
#if defined(TILES)
        const auto from = tab;
#endif

        switch( tab ) {
            case 0:
                result = set_points( *this, points );
                break;
            case 1:
                result = set_scenario( *this, points, result );
                break;
            case 2:
                result = set_profession( *this, points, result );
                break;
            case 3:
                result = set_stats( *this, points );
                break;
            case 4:
                result = set_traits( *this, points );
                break;
            case 5:
                if( prof->forbids_bionics() || g->scen->forbids_bionics() ) {
                    if( !has_any_magic( prof ) ||
                        prof->forbids_spells() || g->scen->forbids_spells() ) {
                        result = set_skills( *this, points );
                    } else {
                        result = set_magic( *this, points );
                    }
                } else {
                    result = set_bionics( *this, points );
                }
                break;
            case 6:
                if( prof->forbids_bionics() || g->scen->forbids_bionics() ) {
                    if( !has_any_magic( prof ) ||
                        prof->forbids_spells() || g->scen->forbids_spells() ) {
                        result = set_description( *this, allow_reroll, points );
                    } else {
                        result = set_skills( *this, points );
                    }
                } else if( !has_any_magic( prof ) ||
                           prof->forbids_spells() || g->scen->forbids_spells() ) {
                    result = set_skills( *this, points );
                } else {
                    result = set_magic( *this, points );
                }
                break;
            case 7:
                if( prof->forbids_bionics() || g->scen->forbids_bionics() ) {
                    result = set_description( *this, allow_reroll, points );
                } else if( !has_any_magic( prof ) ||
                           prof->forbids_spells() || g->scen->forbids_spells() ) {
                    result = set_description( *this, allow_reroll, points );
                } else {
                    result = set_skills( *this, points );
                }
                break;
            case 8:
                result = set_description( *this, allow_reroll, points );
                break;
        }

        switch( result ) {
            case tab_direction::NONE:
                break;
            case tab_direction::FORWARD:
                tab++;
                break;
            case tab_direction::BACKWARD:
                tab--;
                break;
            case tab_direction::QUIT:
                tab = -1;
                break;
        }
#if defined(TILES)
        // A tab clicked in the Godot front end. The profession's cost is taken from the skill points
        // on the tabs after the profession tab, as stepping through the tabs does.
        if( const auto jump = std::exchange( chargen_jump, std::nullopt ); jump && tab >= 0 ) {
            if( from < 2 && *jump > 2 ) {
                points.skill_points -= prof->point_cost();
            } else if( from >= 2 && *jump < 1 ) {
                points.skill_points += prof->point_cost();
            }
            tab = *jump;
        }
#endif

        if( !( tab >= 0 && tab <= get_max_tabs( prof ) ) ) {
            if( tab != -1 && nameExists( name ) ) {
                tab = get_max_tabs( prof );
            } else {
                break;
            }
        }

    } while( true );

    if( tab < 0 ) {
        return false;
    }

    if( points.limit == points_left::TRANSFER ) {
        return true;
    }

    save_template( _( "Last Character" ), points );

    recalc_hp();

    remove_primary_weapon( );

    // Grab the skills from the profession, if there are any
    // We want to do this before the recipes
    for( const profession::StartingSkill &e : prof->skills() ) {
        mod_skill_level( e.first, e.second );
    }

    // setup staring bank money
    cash = prof->starting_cash().value_or( rng( -200000, 200000 ) );

    if( has_trait( trait_XS ) ) {
        set_stored_kcal( 10000 );
        toggle_trait( trait_XS );
    }
    if( has_trait( trait_XXXL ) ) {
        set_stored_kcal( 125000 );
        toggle_trait( trait_XXXL );
    }

    // Learn recipes
    for( const auto &e : recipe_dict ) {
        const auto &r = e.second;
        if( !r.has_flag( flag_SECRET ) && !knows_recipe( &r ) && has_recipe_requirements( r ) ) {
            learn_recipe( &r );
        }
    }
    for( mtype_id elem : prof->pets() ) {
        starting_pets.push_back( elem );
    }

    if( g->scen->vehicle() != vproto_id::NULL_ID() ) {
        starting_vehicle = g->scen->vehicle();
    } else {
        starting_vehicle = prof->vehicle();
    }

    std::vector<detached_ptr<item>> prof_items = prof->items( male, get_mutations() );

    for( detached_ptr<item> &it : prof_items ) {
        if( it->has_flag( STATIC( flag_id( "WET" ) ) ) ) {
            it->activate();
            it->set_counter( 450 ); // Give it some time to dry off
        }
        if( it->is_book() ) {
            items_identified.insert( it->typeId() );
        }
        // TODO: debugmsg if food that isn't a seed is inedible
        if( it->has_flag( json_flag_no_auto_equip ) ) {
            it->unset_flag( json_flag_no_auto_equip );
            inv.add_item( std::move( it ), false );
        } else if( it->has_flag( json_flag_auto_wield ) ) {
            it->unset_flag( json_flag_auto_wield );
            if( !is_armed() ) {
                wield( std::move( it ) );
            } else {
                inv.add_item( std::move( it ), false );
            }
        } else if( it->is_armor() ) {
            // TODO: debugmsg if wearing fails
            wear_item( std::move( it ), false );
        } else {
            inv.add_item( std::move( it ), false );
        }
    }

    std::vector<addiction> prof_addictions = prof->addictions();
    for( std::vector<addiction>::const_iterator iter = prof_addictions.begin();
         iter != prof_addictions.end(); ++iter ) {
        addictions.push_back( *iter );
    }

    for( const bionic_id &bio : prof->CBMs() ) {
        add_bionic( bio );
    }
    // Adjust current energy level to maximum
    set_power_level( get_max_power_level() );

    for( const trait_id &t : get_base_traits() ) {
        std::vector<matype_id> styles;
        for( const matype_id &s : t->initial_ma_styles ) {
            if( !martial_arts_data->has_martialart( s ) ) {
                styles.push_back( s );
            }
        }
        if( !styles.empty() ) {
            const matype_id ma_type = choose_ma_style( type, styles, *this );
            martial_arts_data->add_martialart( ma_type );
            martial_arts_data->set_style( ma_type );
        }
    }

    // Activate some mutations right from the start.
    for( const trait_id &mut : get_mutations() ) {
        const auto &branch = mut.obj();
        if( branch.starts_active ) {
            my_mutations[mut].powered = true;
        }
    }

    learn_spells( *prof, *this );

    // Ensure that persistent morale effects (e.g. Optimist) are present at the start.
    apply_persistent_morale();

    return true;
}

static void draw_character_tabs( const catacurses::window &w, const std::string &sTab,
                                 const profession_id &prof )
{
    std::vector<std::string> tab_captions = {
        _( "POINTS" ),
        _( "SCENARIO" ),
        _( "PROFESSION" ),
        _( "STATS" ),
        _( "TRAITS" ),
        _( "SKILLS" ),
        _( "OVERVIEW" ),
    };
    if( has_any_magic( prof ) && !( prof->forbids_spells() ||
                                    g->scen->forbids_spells() ) ) {
        tab_captions.insert( tab_captions.begin() + 5, _( "MAGIC" ) );
    }
    if( !prof->forbids_bionics() && !g->scen->forbids_bionics() ) {
        tab_captions.insert( tab_captions.begin() + 5, _( "BIONICS" ) );
    }

    draw_tabs( w, tab_captions, sTab );
    draw_border_below_tabs( w );

    for( int i = 1; i < TERMX - 1; i++ ) {
        mvwputch( w, point( i, 4 ), BORDER_COLOR, LINE_OXOX );
    }
    mvwputch( w, point( 0, 4 ), BORDER_COLOR, LINE_XXXO ); // |-
    mvwputch( w, point( TERMX - 1, 4 ), BORDER_COLOR, LINE_XOXX ); // -|
}
static void draw_points( const catacurses::window &w, points_left &points, int netPointCost = 0 )
{
    // Clear line (except borders)
    mvwprintz( w, point( 2, 3 ), c_black, std::string( getmaxx( w ) - 3, ' ' ) );
    std::string points_msg = points.to_string();
    int pMsg_length = utf8_width( remove_color_tags( points_msg ), true );
    nc_color color = c_light_gray;
    print_colored_text( w, point( 2, 3 ), color, c_light_gray, points_msg );
    if( netPointCost > 0 ) {
        mvwprintz( w, point( pMsg_length + 2, 3 ), c_red, "(-%d)", std::abs( netPointCost ) );
    } else if( netPointCost < 0 ) {
        mvwprintz( w, point( pMsg_length + 2, 3 ), c_green, "(+%d)", std::abs( netPointCost ) );
    }
}

template <class Compare>
void draw_sorting_indicator( const catacurses::window &w_sorting, const input_context &ctxt,
                             Compare sorter )
{
    const auto sort_order = sorter.sort_by_points ? _( "points" ) : _( "name" );
    const auto sort_text = string_format(
                               _( "<color_white>Sort by:</color> %1$s "
                                  "(Press <color_light_green>%2$s</color> to change sorting.)" ),
                               sort_order, ctxt.get_desc( "SORT" ) );
    fold_and_print( w_sorting, point_zero, ( TERMX / 2 ), c_light_gray, sort_text );
}

tab_direction set_points( avatar &u, points_left &points )
{
    tab_direction retval = tab_direction::NONE;

    ui_adaptor ui;
    catacurses::window w;
    catacurses::window w_description;
    const auto init_windows = [&]( ui_adaptor & ui ) {
        w = catacurses::newwin( TERMY, TERMX, point_zero );
        w_description = catacurses::newwin( TERMY - 6, TERMX - 35, point( 31, 5 ) );
        ui.position_from_window( w );
    };
    init_windows( ui );
    ui.on_screen_resize( init_windows );

    input_context ctxt( "NEW_CHAR_POINTS" );
    ctxt.register_cardinal();
    ctxt.register_action( "PREV_TAB" );
    ctxt.register_action( "HELP_KEYBINDINGS" );
    ctxt.register_action( "NEXT_TAB" );
    ctxt.register_action( "QUIT" );
    ctxt.register_action( "CONFIRM" );

    const std::string point_pool = get_option<std::string>( "CHARACTER_POINT_POOLS" );

    using point_limit_tuple = std::tuple<points_left::point_limit, std::string, std::string>;
    std::vector<point_limit_tuple> opts;

    const point_limit_tuple multi_pool = std::make_tuple( points_left::MULTI_POOL,
                                         _( "Multiple pools" ),
                                         _( "Stats, traits and skills have separate point pools.\n"
                                            "Putting stat points into traits and skills is allowed and putting trait points into skills is allowed.\n"
                                            "Scenarios and professions affect skill point pool." ) );

    const point_limit_tuple one_pool = std::make_tuple( points_left::ONE_POOL, _( "Single pool" ),
                                       _( "Stats, traits and skills share a single point pool." ) );

    const point_limit_tuple freeform = std::make_tuple( points_left::FREEFORM, _( "Freeform" ),
                                       _( "No point limits are enforced." ) );

    if( point_pool == "multi_pool" ) {
        opts = {{ multi_pool }};
    } else if( point_pool == "no_freeform" ) {
        opts = {{ multi_pool, one_pool }};
    } else {
        opts = {{ multi_pool, one_pool, freeform }};
    }

    int highlighted = 0;

#if defined(TILES)
    const auto native = chargen_view( ui, u, "NEW_CHAR_POINTS", init_windows );
    const auto publish_native = [&]() {
        const auto frame = chargen_frame{ .u = u, .points = points, .step = chargen_step::points, .category = "NEW_CHAR_POINTS" };
        native->publish( [&]( JsonOut & jsout ) {
            write_chargen_frame( jsout, frame );
            jsout.member( "panes" );
            jsout.start_array();
            jsout.start_object();
            jsout.member( "title", _( "Point pools" ) );
            jsout.member( "icon", "coins" );
            jsout.member( "cursor", highlighted );
            jsout.member( "rows" );
            jsout.start_array();
            for( const auto &[limit, name, description] : opts ) {
                const auto chosen = points.limit == limit;
                gs::write_row( jsout, { .text = { .text = name, .color = chosen ? COL_SKILL_USED : c_light_gray },
                                        .note = { .text = chosen ? _( "Chosen" ) : "", .color = COL_SKILL_USED }
                                      } );
            }
            jsout.end_array();
            jsout.end_object();
            jsout.end_array();

            const auto &[limit, name, description] = opts[highlighted];
            jsout.member( "aside" );
            jsout.start_object();
            jsout.member( "width", 820 );
            jsout.member( "share", 0.55 );
            jsout.member( "title" );
            gs::write_span( jsout, { .text = name, .color = c_white } );
            jsout.member( "body" );
            gs::write_span( jsout, { .text = description } );
            jsout.member( "buttons" );
            jsout.start_array();
            gs::write_button( jsout, { .act = "CONFIRM", .text = _( "Use these pools" ), .icon = "check", .category = frame.category,
                                       .enabled = points.limit != limit
                                     } );
            write_next_button( jsout, frame );
            jsout.end_array();
            jsout.end_object();

            jsout.member( "hints" );
            jsout.start_array();
            gs::write_fixed_hint( jsout, "↑↓", _( "Choose" ) );
            gs::write_hint( jsout, "CONFIRM", frame.category, _( "Use" ) );
            write_nav_hints( jsout, frame.category );
            jsout.end_array();
        } );
    };
#endif

    ui.on_redraw( [&]( const ui_adaptor & ) {
#if defined(TILES)
        if( native ) {
            publish_native();
            return;
        }
#endif
        draw_character_tabs( w, _( "POINTS" ), u.prof );

        const auto &cur_opt = opts[highlighted];

        draw_points( w, points );

        // Clear the bottom of the screen.
        werase( w_description );

        for( int i = 0; i < static_cast<int>( opts.size() ); i++ ) {
            nc_color color = ( points.limit == std::get<0>( opts[i] ) ? COL_SKILL_USED : c_light_gray );
            if( highlighted == i ) {
                color = hilite( color );
            }
            mvwprintz( w, point( 2, 5 + i ), color, std::get<1>( opts[i] ) );
        }

        fold_and_print( w_description, point_zero, getmaxx( w_description ),
                        COL_SKILL_USED, std::get<2>( cur_opt ) );

        wnoutrefresh( w );
        wnoutrefresh( w_description );
    } );

    do {
        if( highlighted < 0 ) {
            highlighted = opts.size() - 1;
        } else if( highlighted >= static_cast<int>( opts.size() ) ) {
            highlighted = 0;
        }
        ui_manager::redraw();
        const std::string action = ctxt.handle_input();
#if defined(TILES)
        if( const auto pick = native ? cata::godot_bridge::take_pick( &u ) : std::nullopt ) {
            if( const auto direction = chargen_tab_click( *pick, chargen_step::points, u.prof ) ) {
                retval = *direction;
                continue;
            }
            if( *pick < gs::tab_pick && *pick < static_cast<int>( opts.size() ) ) {
                highlighted = *pick;
            }
        }
#endif
        if( action == "DOWN" ) {
            highlighted++;
        } else if( action == "UP" ) {
            highlighted--;
        } else if( action == "PREV_TAB" && query_yn( _( "Return to main menu?" ) ) ) {
            retval = tab_direction::BACKWARD;
        } else if( action == "NEXT_TAB" ) {
            retval = tab_direction::FORWARD;
        } else if( action == "QUIT" && query_yn( _( "Return to main menu?" ) ) ) {
            retval = tab_direction::QUIT;
        } else if( action == "CONFIRM" ) {
            const auto &cur_opt = opts[highlighted];
            points.limit = std::get<0>( cur_opt );
        }
    } while( retval == tab_direction::NONE );

    return retval;
}

tab_direction set_stats( avatar &u, points_left &points )
{
    const int max_stat_points = points.is_freeform() ? 20 : MAX_STAT;

    unsigned char sel = 1;
    const int iSecondColumn = std::max( 27, utf8_width( points.to_string(), true ) + 9 );
    input_context ctxt( "NEW_CHAR_STATS" );
    ctxt.register_cardinal();
    ctxt.register_action( "PREV_TAB" );
    ctxt.register_action( "HELP_KEYBINDINGS" );
    ctxt.register_action( "RANDOMIZE" );
    ctxt.register_action( "NEXT_TAB" );
    ctxt.register_action( "QUIT" );

    ui_adaptor ui;
    catacurses::window w;
    catacurses::window w_description;
    const auto init_windows = [&]( ui_adaptor & ui ) {
        w = catacurses::newwin( TERMY, TERMX, point_zero );
        w_description = catacurses::newwin( 8, TERMX - iSecondColumn - 1,
                                            point( iSecondColumn, 6 ) );
        ui.position_from_window( w );
    };
    init_windows( ui );
    ui.on_screen_resize( init_windows );

    // There is no map loaded currently, so any access to the map will
    // fail (player::suffer, called from player::reset_stats), might access
    // the map:
    // There are traits that check/change the radioactivity on the map,
    // that check if in sunlight...
    // Setting the position to -1 ensures that the INBOUNDS check in
    // map.cpp is triggered. This check prevents access to invalid position
    // on the map (like -1,0) and instead returns a dummy default value.
    auto old_pos = u.bub_pos();
    old_pos.x() = -1;
    u.Character::setpos( old_pos );
    u.reset();
    // set position back to 0 to prevent out-of-bound access to lightmap
    // array in map::build_seen_cache()
    old_pos.x() = 0;
    u.Character::setpos( old_pos );

#if defined(TILES)
    const auto native = chargen_view( ui, u, "NEW_CHAR_STATS", init_windows );
    const auto publish_native = [&]() {
        struct stat_row {
            std::string name;
            int value;
            /// Shown when raising the stat further costs 2 points.
            std::string expensive;
        };
        const auto stats = std::array{
            stat_row{ .name = _( "Strength" ), .value = u.str_max, .expensive = _( "Increasing Str further costs 2 points." ) },
            stat_row{ .name = _( "Dexterity" ), .value = u.dex_max, .expensive = _( "Increasing Dex further costs 2 points." ) },
            stat_row{ .name = _( "Intelligence" ), .value = u.int_max, .expensive = _( "Increasing Int further costs 2 points." ) },
            stat_row{ .name = _( "Perception" ), .value = u.per_max, .expensive = _( "Increasing Per further costs 2 points." ) },
        };
        const auto line = []( const std::string & text, const nc_color & color ) { return colorize( text, color ) + "\n"; };
        auto body = std::string();
        switch( sel ) {
            case 1:
                u.recalc_hp();
                body = line( string_format( _( "Base HP: %d" ), u.get_part_hp_max( bodypart_id( "head" ) ) ),
                             COL_STAT_NEUTRAL ) +
                       line( string_format( _( "Carry weight: %.1f %s" ), convert_weight( u.weight_capacity() ),
                                            weight_units() ),
                             COL_STAT_NEUTRAL ) +
                       line( string_format( _( "Melee damage bonus: +%.1f" ), u.bonus_damage( false ) ),
                             COL_STAT_BONUS ) + "\n" +
                       _( "Strength also makes you more resistant to many diseases and poisons, and makes actions which require brute force more effective." );
                break;
            case 2:
                body = line( string_format( _( "Melee to-hit bonus: +%.2f" ), u.get_hit_base() ), COL_STAT_BONUS ) +
                       line( string_format( _( "Throwing penalty per target's dodge: +%d" ),
                                            ranged::throw_dispersion_per_dodge( u, false ) ), COL_STAT_BONUS ) +
                       ( u.ranged_dex_mod() != 0 ? line( string_format( _( "Ranged penalty: -%d" ),
                               std::abs( u.ranged_dex_mod() ) ),
                               COL_STAT_PENALTY ) : "" ) + "\n" +
                       _( "Dexterity also enhances many actions which require finesse." );
                break;
            case 3: {
                const auto read_spd = u.read_speed( false );
                body = line( string_format( _( "Read times: %d%%" ), read_spd ),
                             read_spd == 100 ? COL_STAT_NEUTRAL :
                             read_spd < 100 ? COL_STAT_BONUS : COL_STAT_PENALTY ) +
                       line( string_format( _( "Skill rust: %d%%" ), u.rust_rate() ), COL_STAT_PENALTY ) +
                       line( string_format( _( "Crafting bonus: +%d%%" ), u.get_int() ), COL_STAT_BONUS ) + "\n" +
                       _( "Intelligence is also used when crafting, installing bionics, and interacting with NPCs." );
                break;
            }
            default:
                body = ( u.ranged_per_mod() > 0 ? line( string_format( _( "Aiming penalty: -%d" ),
                                                        u.ranged_per_mod() ),
                                                        COL_STAT_PENALTY ) : "" ) +
                       line( string_format( _( "Night vision bonus: +%.1f" ), vision::nv_range_from_per( u.per_max ) ),
                             COL_STAT_BONUS ) +
                       "\n" + _( "Perception is also used for detecting traps, camouflaged creatures, and other things of interest." );
                break;
        }
        const auto &current = stats[sel - 1];
        const auto frame = chargen_frame{ .u = u, .points = points, .step = chargen_step::stats, .category = "NEW_CHAR_STATS" };
        native->publish( [&]( JsonOut & jsout ) {
            write_chargen_frame( jsout, frame );
            jsout.member( "panes" );
            jsout.start_array();
            jsout.start_object();
            jsout.member( "title", _( "Stats" ) );
            jsout.member( "icon", "chart-column" );
            jsout.member( "cursor", sel - 1 );
            jsout.member( "confirm", "" );
            jsout.member( "rows" );
            jsout.start_array();
            for( const auto &st : stats ) {
                gs::write_row( jsout, { .text = { .text = st.name, .color = c_white },
                .cells = { { .text = std::to_string( st.value ), .color = st.value >= HIGH_STAT ? c_yellow : c_white } },
                .note = { .text = st.value >= HIGH_STAT ? _( "2 points per level" ) : "", .color = c_yellow }
                                      } );
            }
            jsout.end_array();
            jsout.end_object();
            jsout.end_array();

            jsout.member( "aside" );
            jsout.start_object();
            jsout.member( "width", 820 );
            jsout.member( "share", 0.55 );
            jsout.member( "title" );
            gs::write_span( jsout, { .text = string_format( "%s %d", current.name, current.value ), .color = c_white } );
            if( current.value >= HIGH_STAT ) {
                jsout.member( "warn" );
                gs::write_span( jsout, { .text = current.expensive, .color = c_light_red } );
            }
            jsout.member( "body" );
            gs::write_span( jsout, { .text = body } );
            jsout.member( "buttons" );
            jsout.start_array();
            gs::write_button( jsout, { .act = "LEFT", .text = _( "Lower" ), .icon = "minus", .category = frame.category,
                                       .enabled = current.value > 4
                                     } );
            gs::write_button( jsout, { .act = "RIGHT", .text = _( "Raise" ), .icon = "plus", .category = frame.category,
                                       .enabled = current.value < max_stat_points
                                     } );
            write_next_button( jsout, frame );
            jsout.end_array();
            jsout.end_object();

            jsout.member( "hints" );
            jsout.start_array();
            gs::write_fixed_hint( jsout, "↑↓", _( "Choose" ) );
            gs::write_hint( jsout, "LEFT", frame.category, _( "Lower" ) );
            gs::write_hint( jsout, "RIGHT", frame.category, _( "Raise" ) );
            write_nav_hints( jsout, frame.category );
            jsout.end_array();
        } );
    };
#endif

    ui.on_redraw( [&]( const ui_adaptor & ) {
#if defined(TILES)
        if( native ) {
            publish_native();
            return;
        }
#endif
        werase( w );
        draw_character_tabs( w, _( "STATS" ), u.prof );
        fold_and_print( w, point( 2, 16 ), getmaxx( w ) - 4, COL_NOTE_MINOR,
                        _( "    <color_light_green>%s</color> / <color_light_green>%s</color> to select a statistic.\n"
                           "    <color_light_green>%s</color> to increase the statistic.\n"
                           "    <color_light_green>%s</color> to decrease the statistic.\n"
                           "\n"
                           "    <color_light_green>%s</color> lets you view and alter keybindings.\n"
                           "    <color_light_green>%s</color> takes you to the next tab.\n"
                           "    <color_light_green>%s</color> returns you to the main menu." ),
                        ctxt.get_desc( "UP" ), ctxt.get_desc( "DOWN" ),
                        ctxt.get_desc( "RIGHT" ), ctxt.get_desc( "LEFT" ),
                        ctxt.get_desc( "HELP_KEYBINDINGS" ), ctxt.get_desc( "NEXT_TAB" ), ctxt.get_desc( "PREV_TAB" )
                      );

        // This is description line, meaning its length excludes first column and border
        const std::string clear_line( getmaxx( w ) - iSecondColumn - 1, ' ' );
        mvwprintz( w, point( iSecondColumn, 3 ), c_black, clear_line );
        for( int i = 6; i < 13; i++ ) {
            mvwprintz( w, point( iSecondColumn, i ), c_black, clear_line );
        }

        draw_points( w, points );

        mvwprintz( w, point( 2, 6 ), c_light_gray, _( "Strength:" ) );
        mvwprintz( w, point( 16, 6 ), c_light_gray, "%2d", u.str_max );
        mvwprintz( w, point( 2, 7 ), c_light_gray, _( "Dexterity:" ) );
        mvwprintz( w, point( 16, 7 ), c_light_gray, "%2d", u.dex_max );
        mvwprintz( w, point( 2, 8 ), c_light_gray, _( "Intelligence:" ) );
        mvwprintz( w, point( 16, 8 ), c_light_gray, "%2d", u.int_max );
        mvwprintz( w, point( 2, 9 ), c_light_gray, _( "Perception:" ) );
        mvwprintz( w, point( 16, 9 ), c_light_gray, "%2d", u.per_max );

        werase( w_description );
        switch( sel ) {
            case 1:
                mvwprintz( w, point( 2, 6 ), COL_STAT_ACT, _( "Strength:" ) );
                mvwprintz( w, point( 16, 6 ), COL_STAT_ACT, "%2d", u.str_max );
                if( u.str_max >= HIGH_STAT ) {
                    mvwprintz( w, point( iSecondColumn, 3 ), c_light_red,
                               _( "Increasing Str further costs 2 points." ) );
                }
                u.recalc_hp();
                mvwprintz( w_description, point_zero, COL_STAT_NEUTRAL, _( "Base HP: %d" ),
                           u.get_part_hp_max( bodypart_id( "head" ) ) );
                // NOLINTNEXTLINE(cata-use-named-point-constants)
                mvwprintz( w_description, point( 0, 1 ), COL_STAT_NEUTRAL, _( "Carry weight: %.1f %s" ),
                           convert_weight( u.weight_capacity() ), weight_units() );
                mvwprintz( w_description, point( 0, 2 ), COL_STAT_BONUS, _( "Melee damage bonus: +%.1f" ),
                           u.bonus_damage( false ) );
                fold_and_print( w_description, point( 0, 4 ), getmaxx( w_description ) - 1, COL_STAT_NEUTRAL,
                                _( "Strength also makes you more resistant to many diseases and poisons, and makes actions which require brute force more effective." ) );
                break;

            case 2:
                mvwprintz( w, point( 2, 7 ), COL_STAT_ACT, _( "Dexterity:" ) );
                mvwprintz( w, point( 16, 7 ), COL_STAT_ACT, "%2d", u.dex_max );
                if( u.dex_max >= HIGH_STAT ) {
                    mvwprintz( w, point( iSecondColumn, 3 ), c_light_red,
                               _( "Increasing Dex further costs 2 points." ) );
                }
                mvwprintz( w_description, point_zero, COL_STAT_BONUS, _( "Melee to-hit bonus: +%.2f" ),
                           u.get_hit_base() );
                // NOLINTNEXTLINE(cata-use-named-point-constants)
                mvwprintz( w_description, point( 0, 1 ), COL_STAT_BONUS,
                           _( "Throwing penalty per target's dodge: +%d" ),
                           ranged::throw_dispersion_per_dodge( u, false ) );
                if( u.ranged_dex_mod() != 0 ) {
                    mvwprintz( w_description, point( 0, 2 ), COL_STAT_PENALTY, _( "Ranged penalty: -%d" ),
                               std::abs( u.ranged_dex_mod() ) );
                }
                fold_and_print( w_description, point( 0, 4 ), getmaxx( w_description ) - 1, COL_STAT_NEUTRAL,
                                _( "Dexterity also enhances many actions which require finesse." ) );
                break;

            case 3: {
                mvwprintz( w, point( 2, 8 ), COL_STAT_ACT, _( "Intelligence:" ) );
                mvwprintz( w, point( 16, 8 ), COL_STAT_ACT, "%2d", u.int_max );
                if( u.int_max >= HIGH_STAT ) {
                    mvwprintz( w, point( iSecondColumn, 3 ), c_light_red,
                               _( "Increasing Int further costs 2 points." ) );
                }
                const int read_spd = u.read_speed( false );
                mvwprintz( w_description, point_zero, ( read_spd == 100 ? COL_STAT_NEUTRAL :
                                                        ( read_spd < 100 ? COL_STAT_BONUS : COL_STAT_PENALTY ) ),
                           _( "Read times: %d%%" ), read_spd );
                // NOLINTNEXTLINE(cata-use-named-point-constants)
                mvwprintz( w_description, point( 0, 1 ), COL_STAT_PENALTY, _( "Skill rust: %d%%" ),
                           u.rust_rate() );
                mvwprintz( w_description, point( 0, 2 ), COL_STAT_BONUS, _( "Crafting bonus: +%d%%" ),
                           u.get_int() );
                fold_and_print( w_description, point( 0, 4 ), getmaxx( w_description ) - 1, COL_STAT_NEUTRAL,
                                _( "Intelligence is also used when crafting, installing bionics, and interacting with NPCs." ) );
            }
            break;

            case 4:
                mvwprintz( w, point( 2, 9 ), COL_STAT_ACT, _( "Perception:" ) );
                mvwprintz( w, point( 16, 9 ), COL_STAT_ACT, "%2d", u.per_max );
                if( u.per_max >= HIGH_STAT ) {
                    mvwprintz( w, point( iSecondColumn, 3 ), c_light_red,
                               _( "Increasing Per further costs 2 points." ) );
                }
                if( u.ranged_per_mod() > 0 ) {
                    mvwprintz( w_description, point_zero, COL_STAT_PENALTY, _( "Aiming penalty: -%d" ),
                               u.ranged_per_mod() );
                }
                mvwprintz( w_description, point( 0, 2 ), COL_STAT_BONUS, _( "Night vision bonus: +%.1f" ),
                           vision::nv_range_from_per( u.per_max ) );
                fold_and_print( w_description, point( 0, 4 ), getmaxx( w_description ) - 1, COL_STAT_NEUTRAL,
                                _( "Perception is also used for detecting traps, camouflaged creatures, and other things of interest." ) );
                break;
        }

        wnoutrefresh( w );
        wnoutrefresh( w_description );
    } );

    do {
        ui_manager::redraw();
        const std::string action = ctxt.handle_input();
#if defined(TILES)
        if( const auto pick = native ? cata::godot_bridge::take_pick( &u ) : std::nullopt ) {
            if( const auto direction = chargen_tab_click( *pick, chargen_step::stats, u.prof ) ) {
                return *direction;
            }
            if( *pick >= 0 && *pick < 4 ) {
                sel = static_cast<unsigned char>( *pick + 1 );
            }
        }
#endif
        if( action == "DOWN" ) {
            if( sel < 4 ) {
                sel++;
            } else {
                sel = 1;
            }
        } else if( action == "UP" ) {
            if( sel > 1 ) {
                sel--;
            } else {
                sel = 4;
            }
        } else if( action == "RANDOMIZE" ) {
            sel = rng( 1, 4 );
        } else if( action == "LEFT" ) {
            if( sel == 1 && u.str_max > 4 ) {
                if( u.str_max > HIGH_STAT ) {
                    points.stat_points++;
                }
                u.str_max--;
                points.stat_points++;
            } else if( sel == 2 && u.dex_max > 4 ) {
                if( u.dex_max > HIGH_STAT ) {
                    points.stat_points++;
                }
                u.dex_max--;
                points.stat_points++;
            } else if( sel == 3 && u.int_max > 4 ) {
                if( u.int_max > HIGH_STAT ) {
                    points.stat_points++;
                }
                u.int_max--;
                points.stat_points++;
            } else if( sel == 4 && u.per_max > 4 ) {
                if( u.per_max > HIGH_STAT ) {
                    points.stat_points++;
                }
                u.per_max--;
                points.stat_points++;
            }
        } else if( action == "RIGHT" ) {
            if( sel == 1 && u.str_max < max_stat_points ) {
                points.stat_points--;
                if( u.str_max >= HIGH_STAT ) {
                    points.stat_points--;
                }
                u.str_max++;
            } else if( sel == 2 && u.dex_max < max_stat_points ) {
                points.stat_points--;
                if( u.dex_max >= HIGH_STAT ) {
                    points.stat_points--;
                }
                u.dex_max++;
            } else if( sel == 3 && u.int_max < max_stat_points ) {
                points.stat_points--;
                if( u.int_max >= HIGH_STAT ) {
                    points.stat_points--;
                }
                u.int_max++;
            } else if( sel == 4 && u.per_max < max_stat_points ) {
                points.stat_points--;
                if( u.per_max >= HIGH_STAT ) {
                    points.stat_points--;
                }
                u.per_max++;
            }
        } else if( action == "PREV_TAB" ) {
            return tab_direction::BACKWARD;
        } else if( action == "NEXT_TAB" ) {
            return tab_direction::FORWARD;
        } else if( action == "QUIT" && query_yn( _( "Return to main menu?" ) ) ) {
            return tab_direction::QUIT;
        }
    } while( true );
}

tab_direction set_traits( avatar &u, points_left &points )
{
    const int max_trait_points = get_option<int>( "MAX_TRAIT_POINTS" );

    // Track how many good / bad POINTS we have; cap both at MAX_TRAIT_POINTS
    int num_good = 0;
    int num_bad = 0;

    struct trait_entry {
        trait_id id;
        bool avatar_has;
        bool conflicts;
        bool forbidden;
    };
    std::vector<trait_entry> vStartingTraits[3];

    for( auto &bio_iter : bionic_data::get_all() ) {
        if( bio_iter.points > 0 ) {
            if( u.has_bionic( bio_iter.id ) ) {
                num_good += bio_iter.points;
            }
        } else if( bio_iter.points < 0 ) {
            if( u.has_bionic( bio_iter.id ) ) {
                num_bad += bio_iter.points;
            }
        }
    }

    for( auto &traits_iter : mutation_branch::get_all() ) {
        // Don't list blacklisted traits
        if( mutation_branch::trait_is_blacklisted( traits_iter.id ) ) {
            continue;
        }

        // Hide exclusive traits for the wrong gender
        if( u.male ) {
            if( traits_iter.flags.contains( flag_FEMALE_EXCLUSIVE ) ) {
                continue;
            }
        } else {
            if( traits_iter.flags.contains( flag_MALE_EXCLUSIVE ) ) {
                continue;
            }
        }

        // Always show profession locked traits, regardless of if they are forbidden
        const std::vector<trait_id> proftraits = u.prof->get_locked_traits();
        const bool is_proftrait = std::find( proftraits.begin(), proftraits.end(),
                                             traits_iter.id ) != proftraits.end();
        // We show all starting traits, even if we can't pick them, to keep the interface consistent.
        if( traits_iter.startingtrait || g->scen->traitquery( traits_iter.id ) ||
            u.prof->is_allowed_trait( traits_iter.id ) || is_proftrait ) {
            size_t page;
            if( traits_iter.points > 0 ) {
                page = 0;
                if( u.has_trait( traits_iter.id ) ) {
                    num_good += traits_iter.points;
                }
            } else if( traits_iter.points < 0 ) {
                page = 1;
                if( u.has_trait( traits_iter.id ) ) {
                    num_bad += traits_iter.points;
                }
            } else {
                page = 2;
            }
            vStartingTraits[page].push_back( { traits_iter.id, false, false, g->scen->is_forbidden_trait( traits_iter.id ) } );
        }
    }
    //If the third page is empty, only use the first two.
    const int used_pages = vStartingTraits[2].empty() ? 2 : 3;

    for( auto &vStartingTrait : vStartingTraits ) {
        std::sort( vStartingTrait.begin(), vStartingTrait.end(), []( const trait_entry & a,
        const trait_entry & b ) {
            return trait_display_nocolor_sort( a.id, b.id );
        } );
    }

    const auto recalc_display_cache = [&]() {
        for( int page = 0; page < used_pages; page++ ) {
            for( trait_entry &entry : vStartingTraits[page] ) {
                entry.conflicts = newcharacter::has_conflicting_trait( u, entry.id );
                entry.avatar_has = u.has_trait( entry.id );
            }
        }
    };
    recalc_display_cache();

    int iCurWorkingPage = 0;
    int iStartPos[3] = { 0, 0, 0 };
    int iCurrentLine[3] = { 0, 0, 0 };
    size_t traits_size[3];
    for( int i = 0; i < 3; i++ ) {
        traits_size[i] = vStartingTraits[i].size();
    }

    size_t iContentHeight;
    size_t page_width;

    ui_adaptor ui;
    catacurses::window w;
    catacurses::window w_description;

#if defined(TILES)
    character_preview_window character_preview;
    character_preview.init( &u );
    const bool use_character_preview = get_option<bool>( "USE_CHARACTER_PREVIEW" ) &&
                                       get_option<bool>( "USE_TILES" );
#endif

    const auto init_windows = [&]( ui_adaptor & ui ) {
        w = catacurses::newwin( TERMY, TERMX, point_zero );
        w_description = catacurses::newwin( 3, TERMX - 2, point( 1, TERMY - 4 ) );
        page_width = std::min( ( TERMX - 4 ) / used_pages, 38 );

#if defined(TILES)
        const int int_page_width = static_cast<int>( page_width );

        if( use_character_preview && cata::godot_bridge::native_screens() ) {
            prepare_native_preview( character_preview );
        } else if( use_character_preview ) {
            constexpr int preview_nlines_min = 7;
            constexpr int preview_ncols_min = 10;
            const int preview_nlines = std::max( ( TERMY - 9 ) / 3, preview_nlines_min );
            const int preview_ncols = std::max( ( TERMX - int_page_width * 3 - 4 ) / 3 - 5, preview_ncols_min );
            constexpr auto orientation = character_preview_window::Orientation{
                character_preview_window::TOP_RIGHT,
                character_preview_window::Margin{0, 2, 5, 0}
            };
            character_preview.prepare(
                preview_nlines, preview_ncols,
                &orientation, int_page_width * 3 + 5
            );
        }
#endif

        ui.position_from_window( w );

        iContentHeight = TERMY - 9;

        for( int i = 0; i < 3; i++ ) {
            // Shift start position to avoid iterating beyond end
            int total = static_cast<int>( traits_size[i] );
            int heigth = static_cast<int>( iContentHeight );
            iStartPos[i] = std::min( iStartPos[i], std::max( 0, total - heigth ) );
        }
    };
    init_windows( ui );
    ui.on_screen_resize( init_windows );

    input_context ctxt( "NEW_CHAR_TRAITS" );
    ctxt.register_cardinal();
    ctxt.register_action( "CONFIRM" );
    ctxt.register_action( "PREV_TAB" );
    ctxt.register_action( "NEXT_TAB" );
    ctxt.register_action( "HELP_KEYBINDINGS" );
    ctxt.register_action( "RANDOMIZE" );
    ctxt.register_action( "REROLL_CHARACTER" );
    ctxt.register_action( "REROLL_CHARACTER_WITH_SCENARIO" );
    ctxt.register_action( "REROLL_APPEARANCE" );
    ctxt.register_action( "QUIT" );
#if defined(TILES)
    ctxt.register_action( "zoom_in" );
    ctxt.register_action( "zoom_out" );
    ctxt.register_action( "TOGGLE_CHARACTER_PREVIEW_CLOTHES" );
#endif


#if defined(TILES)
    const auto native = chargen_view( ui, u, "NEW_CHAR_TRAITS", init_windows );
    const auto publish_native = [&]() {
        auto view = pick_pages{ .used_pages = used_pages, .page = iCurWorkingPage,
                                .cursors = { iCurrentLine[0], iCurrentLine[1], iCurrentLine[2] },
                                .add_text = _( "Take trait" ), .remove_text = _( "Remove trait" ),
                                .preview = use_character_preview ? &character_preview : nullptr };
        for( auto page = 0; page < 3; page++ ) {
            view.pages[page] = vStartingTraits[page] | std::views::transform( [&]( const trait_entry & e ) {
                return pick_entry{ .name = e.id->name(), .points = e.id->points, .has = e.avatar_has, .blocked = e.conflicts || e.forbidden };
            } ) | std::ranges::to<std::vector>();
        }
        if( const auto &current = vStartingTraits[iCurWorkingPage]; !current.empty() ) {
            const auto &e = current[iCurrentLine[iCurWorkingPage]];
            view.description = e.id->desc();
        }
        auto frame = chargen_frame{ .u = u, .points = points, .step = chargen_step::traits, .category = "NEW_CHAR_TRAITS" };
        if( !points.is_freeform() ) {
            frame.extra = {
                { .label = _( "Advantages" ), .value = { .text = string_format( "%d/%d", num_good, max_trait_points ), .color = c_light_green } },
                { .label = _( "Disadvantages" ), .value = { .text = string_format( "%d/-%d", num_bad, max_trait_points ), .color = c_light_red } },
            };
        }
        native->publish( [&]( JsonOut & jsout ) {
            write_chargen_frame( jsout, frame );
            write_pick_pages( jsout, frame, view );
        } );
    };
#endif

    ui.on_redraw( [&]( const ui_adaptor & ) {
#if defined(TILES)
        if( native ) {
            publish_native();
            if( use_character_preview ) {
                character_preview.display();
            }
            return;
        }
#endif
        werase( w );
        werase( w_description );

        draw_character_tabs( w, _( "TRAITS" ), u.prof );

        draw_points( w, points );
        int full_string_length = 0;
        const int remaining_points_length = utf8_width( points.to_string(), true );
        if( !points.is_freeform() ) {
            std::string full_string =
                string_format( "<color_light_green>%2d/%-2d</color> <color_light_red>%3d/-%-2d</color>",
                               num_good, max_trait_points, num_bad, max_trait_points );
            fold_and_print( w, point( remaining_points_length + 3, 3 ), getmaxx( w ) - 2, c_white,
                            full_string );
            full_string_length = utf8_width( full_string, true ) + remaining_points_length + 3;
        } else {
            full_string_length = remaining_points_length + 3;
        }

        for( int iCurrentPage = 0; iCurrentPage < 3; iCurrentPage++ ) {
            nc_color col_on_act, col_off_act, col_on_pas, col_off_pas, hi_on, hi_off, col_tr;
            switch( iCurrentPage ) {
                case 0:
                    col_on_act = COL_TR_GOOD_ON_ACT;
                    col_off_act = COL_TR_GOOD_OFF_ACT;
                    col_on_pas = COL_TR_GOOD_ON_PAS;
                    col_off_pas = COL_TR_GOOD_OFF_PAS;
                    col_tr = COL_TR_GOOD;
                    break;
                case 1:
                    col_on_act = COL_TR_BAD_ON_ACT;
                    col_off_act = COL_TR_BAD_OFF_ACT;
                    col_on_pas = COL_TR_BAD_ON_PAS;
                    col_off_pas = COL_TR_BAD_OFF_PAS;
                    col_tr = COL_TR_BAD;
                    break;
                default:
                    col_on_act = COL_TR_NEUT_ON_ACT;
                    col_off_act = COL_TR_NEUT_OFF_ACT;
                    col_on_pas = COL_TR_NEUT_ON_PAS;
                    col_off_pas = COL_TR_NEUT_OFF_PAS;
                    col_tr = COL_TR_NEUT;
                    break;
            }

            int &start = iStartPos[iCurrentPage];
            int current = iCurrentLine[iCurrentPage];
            calcStartPos( start, current, iContentHeight, traits_size[iCurrentPage] );
            int end = start + static_cast<int>( std::min( traits_size[iCurrentPage], iContentHeight ) );

            for( int i = start; i < end; i++ ) {
                const trait_entry &entry = vStartingTraits[iCurrentPage][i];
                const mutation_branch &mdata = entry.id.obj();
                if( current == i && iCurrentPage == iCurWorkingPage ) {
                    int points = mdata.points;
                    bool negativeTrait = points < 0;
                    if( negativeTrait ) {
                        points *= -1;
                    }
                    mvwprintz( w, point( full_string_length + 3, 3 ), col_tr,
                               vgettext( "%s %s %d point", "%s %s %d points", points ),
                               mdata.name(),
                               negativeTrait ? _( "earns" ) : _( "costs" ),
                               points );
                    fold_and_print( w_description, point_zero,
                                    TERMX - 2, col_tr,
                                    mdata.desc() );
                }

                nc_color col;
                if( iCurWorkingPage == iCurrentPage ) {
                    if( entry.avatar_has ) {
                        col = col_on_act;
                    } else if( entry.conflicts || entry.forbidden ) {
                        col = c_dark_gray;
                    } else {
                        col = col_off_act;
                    }
                    if( current == i ) {
                        col = hilite( col );
                    }
                } else {
                    if( entry.avatar_has ) {
                        col = col_on_pas;
                    } else if( entry.conflicts || entry.forbidden ) {
                        col = c_light_gray;
                    } else {
                        col = col_off_pas;
                    }
                }

                int cur_y = 5 + i - start;
                int cur_x = 2 + iCurrentPage * page_width;
                mvwprintz( w, point( cur_x, cur_y ), col, utf8_truncate( mdata.name(), page_width - 2 ) );
            }

            draw_scrollbar( w, iCurrentLine[iCurrentPage], iContentHeight, traits_size[iCurrentPage],
                            point( page_width * iCurrentPage, 5 ) );
        }
        // Draws main window, traits description window and character preview window
        wnoutrefresh( w );
        wnoutrefresh( w_description );
#if defined(TILES)
        // Draws character preview
        if( use_character_preview ) {
            character_preview.display();
        }
#endif
    } );

    do {
        ui_manager::redraw();
        const std::string action = ctxt.handle_input();
#if defined(TILES)
        if( const auto pick = native ? cata::godot_bridge::take_pick( &u ) : std::nullopt ) {
            if( const auto direction = chargen_tab_click( *pick, chargen_step::traits, u.prof ) ) {
                character_preview.clear();
                return *direction;
            }
            const auto page = *pick / gs::row_stride;
            const auto row = *pick % gs::row_stride;
            if( page < used_pages && static_cast<size_t>( row ) < traits_size[page] ) {
                iCurWorkingPage = page;
                iCurrentLine[page] = row;
            }
        }
        if( action == "zoom_in" && use_character_preview ) {
            character_preview.zoom_in();
        }
        if( action == "zoom_out" && use_character_preview ) {
            character_preview.zoom_out();
        }
        if( action == "TOGGLE_CHARACTER_PREVIEW_CLOTHES" && use_character_preview ) {
            character_preview.toggle_clothes();
        }
#endif
        if( action == "LEFT" ) {
            iCurWorkingPage--;
            if( iCurWorkingPage < 0 ) {
                iCurWorkingPage = used_pages - 1;
            }
        } else if( action == "RIGHT" ) {
            iCurWorkingPage++;
            if( iCurWorkingPage > used_pages - 1 ) {
                iCurWorkingPage = 0;
            }
        } else if( action == "UP" ) {
            if( iCurrentLine[iCurWorkingPage] == 0 ) {
                iCurrentLine[iCurWorkingPage] = traits_size[iCurWorkingPage] - 1;
            } else {
                iCurrentLine[iCurWorkingPage]--;
            }
        } else if( action == "REROLL_CHARACTER" ) {
            points.init_from_options();
            u.randomize( false, points );
            // Return tab_direction::NONE so we re-enter this tab again, but it forces a complete redrawing of it.
            return tab_direction::NONE;
        } else if( action == "REROLL_CHARACTER_WITH_SCENARIO" ) {
            points.init_from_options();
            u.randomize( true, points );
            // Return tab_direction::NONE so we re-enter this tab again, but it forces a complete redrawing of it.
            return tab_direction::NONE;
        } else if( action == "REROLL_APPEARANCE" ) {
            u.randomize_cosmetics();
            //u.set_body();
            // Return tab_direction::NONE so we re-enter this tab again, but it forces a complete redrawing of it.
            return tab_direction::NONE;
        } else if( action == "DOWN" ) {
            iCurrentLine[iCurWorkingPage]++;
            if( static_cast<size_t>( iCurrentLine[iCurWorkingPage] ) >= traits_size[iCurWorkingPage] ) {
                iCurrentLine[iCurWorkingPage] = 0;
            }
        } else if( action == "RANDOMIZE" ) {
            iCurrentLine[iCurWorkingPage] = rng( 0, traits_size[iCurWorkingPage] - 1 );
        } else if( action == "CONFIRM" ) {
            int inc_type = 0;
            const trait_id cur_trait = vStartingTraits[iCurWorkingPage][iCurrentLine[iCurWorkingPage]].id;
            const mutation_branch &mdata = cur_trait.obj();

            // Look through the profession bionics, and see if any of them conflict with this trait
            std::vector<bionic_id> cbms_blocking_trait = bionics_cancelling_trait( u.prof->CBMs(), cur_trait );
            std::vector<bionic_id> cbms_blocking_trait2 = bionics_cancelling_trait( u.get_bionics(),
                    cur_trait );
            for( auto cbm : cbms_blocking_trait2 ) {
                cbms_blocking_trait.push_back( cbm );
            }
            const bool has_trait = u.has_trait( cur_trait );

            if( has_trait ) {

                inc_type = -1;

                if( g->scen->is_locked_trait( cur_trait ) ) {
                    inc_type = 0;
                    popup( _( "Your scenario of %s prevents you from removing this trait." ),
                           g->scen->gender_appropriate_name( u.male ) );
                } else if( u.prof->is_locked_trait( cur_trait ) ) {
                    inc_type = 0;
                    popup( _( "Your profession of %s prevents you from removing this trait." ),
                           u.prof->gender_appropriate_name( u.male ) );
                } else {
                    const auto mandatory_type = std::ranges::find_if( cur_trait.obj().types,
                    []( const auto & t ) { return mutation_type_is_mandatory( t ); } );
                    if( mandatory_type != cur_trait.obj().types.end() ) {
                        inc_type = 0;
                        popup( _( "You need to select 1 %s." ), mutation_type_display_name( *mandatory_type ) );
                    }
                }
            } else if( newcharacter::has_conflicting_trait( u, cur_trait ) ) {
                const auto &new_types = cur_trait.obj().types;
                const bool do_swap = std::ranges::any_of( new_types,
                []( const auto & t ) { return mutation_type_swaps_on_conflict( t ); } );
                if( do_swap ) {
                    const auto base_traits = u.get_base_traits();
                    auto it = std::ranges::find_if( base_traits, [&]( const trait_id & tr ) {
                        return tr != cur_trait && std::ranges::any_of( tr.obj().types,
                        [&]( const auto & t ) { return new_types.contains( t ); } );
                    } );
                    if( it != base_traits.end() ) {
                        inc_type = 1;
                        u.toggle_trait( *it );
                    } else {
                        popup( _( "You already picked a conflicting trait!" ) );
                    }
                } else {
                    popup( _( "You already picked a conflicting trait!" ) );
                }
            } else if( g->scen->is_forbidden_trait( cur_trait ) ) {
                popup( _( "The scenario you picked prevents you from taking this trait!" ) );
            } else if( u.prof->is_forbidden_trait( cur_trait ) ) {
                popup( _( "Your profession of %s prevents you from taking this trait." ),
                       u.prof->gender_appropriate_name( u.male ) );
            } else if( !cbms_blocking_trait.empty() ) {
                // Grab a list of the names of the bionics that block this trait
                // So that the player know what is preventing them from taking it
                std::vector<std::string> conflict_names;
                conflict_names.reserve( cbms_blocking_trait.size() );
                for( const bionic_id &conflict : cbms_blocking_trait ) {
                    conflict_names.emplace_back( conflict->name.translated() );
                }
                popup( _( "The following bionics prevent you from taking this trait: %s." ),
                       enumerate_as_string( conflict_names ) );
            } else if( iCurWorkingPage == 0 && num_good + mdata.points >
                       max_trait_points && !points.is_freeform() ) {
                popup( vgettext( "Sorry, but you can only take %d point of advantages.",
                                 "Sorry, but you can only take %d points of advantages.", max_trait_points ),
                       max_trait_points );

            } else if( iCurWorkingPage != 0 && num_bad + mdata.points <
                       -max_trait_points && !points.is_freeform() ) {
                popup( vgettext( "Sorry, but you can only take %d point of disadvantages.",
                                 "Sorry, but you can only take %d points of disadvantages.", max_trait_points ),
                       max_trait_points );

            } else {
                inc_type = 1;
            }

            //inc_type is either -1 or 1, so we can just multiply by it to invert
            if( inc_type != 0 ) {
                u.toggle_trait( cur_trait );
#if defined(TILES)
                // If character had trait - it's now removed. Trait could blocked some clothes, need to retoggle
                if( has_trait && character_preview.clothes_showing() ) {
                    character_preview.toggle_clothes();
                    character_preview.toggle_clothes();
                }
#endif
                points.trait_points -= mdata.points * inc_type;
                if( iCurWorkingPage == 0 ) {
                    num_good += mdata.points * inc_type;
                } else {
                    num_bad += mdata.points * inc_type;
                }
            }

            recalc_display_cache();
        } else if( action == "PREV_TAB" ) {
#if defined(TILES)
            character_preview.clear();
#endif
            return tab_direction::BACKWARD;
        } else if( action == "NEXT_TAB" ) {
#if defined(TILES)
            character_preview.clear();
#endif
            return tab_direction::FORWARD;
        } else if( action == "QUIT" && query_yn( _( "Return to main menu?" ) ) ) {
#if defined(TILES)
            character_preview.clear();
#endif
            return tab_direction::QUIT;
        }
    } while( true );
}

tab_direction set_bionics( avatar &u, points_left &points )
{
    const int max_trait_points = get_option<int>( "MAX_TRAIT_POINTS" );

    // Track how many good / bad POINTS we have; cap both at MAX_TRAIT_POINTS
    int num_good = 0;
    int num_bad = 0;

    struct bionic_entry {
        bionic_id id;
        bool avatar_has;
        bool conflicts;
        bool forbidden;
    };
    std::vector<bionic_entry> vStartingBionics[3];

    for( auto &traits_iter : mutation_branch::get_all() ) {
        if( traits_iter.points > 0 ) {
            if( u.has_trait( traits_iter.id ) ) {
                num_good += traits_iter.points;
            }
        } else if( traits_iter.points < 0 ) {
            if( u.has_trait( traits_iter.id ) ) {
                num_bad += traits_iter.points;
            }
        }
    }

    for( auto &bio_iter : bionic_data::get_all() ) {

        // Always show profession locked traits, regardless of if they are forbidden
        const std::vector<bionic_id> profbionics = u.prof->CBMs();
        const bool is_profbionic = std::find( profbionics.begin(), profbionics.end(),
                                              bio_iter.id ) != profbionics.end();
        // We show all starting traits, even if we can't pick them, to keep the interface consistent.
        if( bio_iter.starting_bionic || g->scen->bionicquery( bio_iter.id ) ||
            u.prof->is_allowed_bionic( bio_iter.id ) || is_profbionic ) {
            size_t page;
            if( bio_iter.points > 0 ) {
                page = 0;
                if( u.has_bionic( bio_iter.id ) ) {
                    num_good += bio_iter.points;
                }
            } else if( bio_iter.points < 0 ) {
                page = 1;
                if( u.has_bionic( bio_iter.id ) ) {
                    num_bad += bio_iter.points;
                }
            } else {
                page = 2;
            }
            vStartingBionics[page].push_back( { bio_iter.id, false, false, g->scen->is_forbidden_bionic( bio_iter.id ) } );
        }
    }
    //If the third page is empty, only use the first two.
    const int used_pages = vStartingBionics[2].empty() ? 2 : 3;

    for( auto &vStartingBionic : vStartingBionics ) {
        std::sort( vStartingBionic.begin(), vStartingBionic.end(), []( const bionic_entry & a,
        const bionic_entry & b ) {
            return localized_compare( a.id->name.translated(), b.id->name.translated() );
        } );
    }

    const auto recalc_display_cache = [&]() {
        auto cbms = u.prof->CBMs();
        for( int page = 0; page < used_pages; page++ ) {
            for( bionic_entry &entry : vStartingBionics[page] ) {
                entry.conflicts = newcharacter::bionic_has_conflict( u, entry.id );
                entry.avatar_has = u.has_bionic( entry.id ) ||
                                   std::find( cbms.begin(), cbms.end(), entry.id ) != cbms.end();
            }
        }
    };
    recalc_display_cache();

    int iCurWorkingPage = 0;
    int iStartPos[3] = { 0, 0, 0 };
    int iCurrentLine[3] = { 0, 0, 0 };
    size_t bionics_size[3];
    for( int i = 0; i < 3; i++ ) {
        bionics_size[i] = vStartingBionics[i].size();
    }

    size_t iContentHeight;
    size_t page_width;

    ui_adaptor ui;
    catacurses::window w;
    catacurses::window w_description;

#if defined(TILES)
    character_preview_window character_preview;
    character_preview.init( &u );
    const bool use_character_preview = get_option<bool>( "USE_CHARACTER_PREVIEW" ) &&
                                       get_option<bool>( "USE_TILES" );
#endif

    const auto init_windows = [&]( ui_adaptor & ui ) {
        w = catacurses::newwin( TERMY, TERMX, point_zero );
        w_description = catacurses::newwin( 3, TERMX - 2, point( 1, TERMY - 4 ) );
        page_width = std::min( ( TERMX - 4 ) / used_pages, 38 );

#if defined(TILES)
        const int int_page_width = static_cast<int>( page_width );

        if( use_character_preview && cata::godot_bridge::native_screens() ) {
            prepare_native_preview( character_preview );
        } else if( use_character_preview ) {
            constexpr int preview_nlines_min = 7;
            constexpr int preview_ncols_min = 10;
            const int preview_nlines = std::max( ( TERMY - 9 ) / 3, preview_nlines_min );
            const int preview_ncols = std::max( ( TERMX - int_page_width * 3 - 4 ) / 3 - 5, preview_ncols_min );
            constexpr auto orientation = character_preview_window::Orientation{
                character_preview_window::TOP_RIGHT,
                character_preview_window::Margin{0, 2, 5, 0}
            };
            character_preview.prepare(
                preview_nlines, preview_ncols,
                &orientation, int_page_width * 3 + 5
            );
        }
#endif

        ui.position_from_window( w );

        iContentHeight = TERMY - 9;

        for( int i = 0; i < 3; i++ ) {
            // Shift start position to avoid iterating beyond end
            int total = static_cast<int>( bionics_size[i] );
            int heigth = static_cast<int>( iContentHeight );
            iStartPos[i] = std::min( iStartPos[i], std::max( 0, total - heigth ) );
        }
    };
    init_windows( ui );
    ui.on_screen_resize( init_windows );

    input_context ctxt( "NEW_CHAR_TRAITS" );
    ctxt.register_cardinal();
    ctxt.register_action( "CONFIRM" );
    ctxt.register_action( "PREV_TAB" );
    ctxt.register_action( "NEXT_TAB" );
    ctxt.register_action( "HELP_KEYBINDINGS" );
    ctxt.register_action( "RANDOMIZE" );
    ctxt.register_action( "REROLL_CHARACTER" );
    ctxt.register_action( "REROLL_CHARACTER_WITH_SCENARIO" );
    ctxt.register_action( "REROLL_APPEARANCE" );
    ctxt.register_action( "QUIT" );
#if defined(TILES)
    ctxt.register_action( "zoom_in" );
    ctxt.register_action( "zoom_out" );
    ctxt.register_action( "TOGGLE_CHARACTER_PREVIEW_CLOTHES" );
#endif


#if defined(TILES)
    const auto native = chargen_view( ui, u, "NEW_CHAR_TRAITS", init_windows );
    const auto publish_native = [&]() {
        auto view = pick_pages{ .used_pages = used_pages, .page = iCurWorkingPage,
                                .cursors = { iCurrentLine[0], iCurrentLine[1], iCurrentLine[2] },
                                .add_text = _( "Add bionic" ), .remove_text = _( "Remove bionic" ),
                                .preview = use_character_preview ? &character_preview : nullptr };
        for( auto page = 0; page < 3; page++ ) {
            view.pages[page] = vStartingBionics[page] | std::views::transform( [&]( const bionic_entry & e ) {
                return pick_entry{ .name = e.id->name.translated(), .points = e.id->points, .has = e.avatar_has, .blocked = e.conflicts || e.forbidden };
            } ) | std::ranges::to<std::vector>();
        }
        if( const auto &current = vStartingBionics[iCurWorkingPage]; !current.empty() ) {
            const auto &e = current[iCurrentLine[iCurWorkingPage]];
            view.description = e.id->description.translated();
        }
        auto frame = chargen_frame{ .u = u, .points = points, .step = chargen_step::bionics, .category = "NEW_CHAR_TRAITS" };
        if( !points.is_freeform() ) {
            frame.extra = {
                { .label = _( "Advantages" ), .value = { .text = string_format( "%d/%d", num_good, max_trait_points ), .color = c_light_green } },
                { .label = _( "Disadvantages" ), .value = { .text = string_format( "%d/-%d", num_bad, max_trait_points ), .color = c_light_red } },
            };
        }
        native->publish( [&]( JsonOut & jsout ) {
            write_chargen_frame( jsout, frame );
            write_pick_pages( jsout, frame, view );
        } );
    };
#endif

    ui.on_redraw( [&]( const ui_adaptor & ) {
#if defined(TILES)
        if( native ) {
            publish_native();
            if( use_character_preview ) {
                character_preview.display();
            }
            return;
        }
#endif
        werase( w );
        werase( w_description );

        draw_character_tabs( w, _( "BIONICS" ), u.prof );

        draw_points( w, points );
        int full_string_length = 0;
        const int remaining_points_length = utf8_width( points.to_string(), true );
        if( !points.is_freeform() ) {
            std::string full_string =
                string_format( "<color_light_green>%2d/%-2d</color> <color_light_red>%3d/-%-2d</color>",
                               num_good, max_trait_points, num_bad, max_trait_points );
            fold_and_print( w, point( remaining_points_length + 3, 3 ), getmaxx( w ) - 2, c_white,
                            full_string );
            full_string_length = utf8_width( full_string, true ) + remaining_points_length + 3;
        } else {
            full_string_length = remaining_points_length + 3;
        }

        for( int iCurrentPage = 0; iCurrentPage < 3; iCurrentPage++ ) {
            nc_color col_on_act, col_off_act, col_on_pas, col_off_pas, hi_on, hi_off, col_tr;
            switch( iCurrentPage ) {
                case 0:
                    col_on_act = COL_TR_GOOD_ON_ACT;
                    col_off_act = COL_TR_GOOD_OFF_ACT;
                    col_on_pas = COL_TR_GOOD_ON_PAS;
                    col_off_pas = COL_TR_GOOD_OFF_PAS;
                    col_tr = COL_TR_GOOD;
                    break;
                case 1:
                    col_on_act = COL_TR_BAD_ON_ACT;
                    col_off_act = COL_TR_BAD_OFF_ACT;
                    col_on_pas = COL_TR_BAD_ON_PAS;
                    col_off_pas = COL_TR_BAD_OFF_PAS;
                    col_tr = COL_TR_BAD;
                    break;
                default:
                    col_on_act = COL_TR_NEUT_ON_ACT;
                    col_off_act = COL_TR_NEUT_OFF_ACT;
                    col_on_pas = COL_TR_NEUT_ON_PAS;
                    col_off_pas = COL_TR_NEUT_OFF_PAS;
                    col_tr = COL_TR_NEUT;
                    break;
            }

            int &start = iStartPos[iCurrentPage];
            int current = iCurrentLine[iCurrentPage];
            calcStartPos( start, current, iContentHeight, bionics_size[iCurrentPage] );
            int end = start + static_cast<int>( std::min( bionics_size[iCurrentPage], iContentHeight ) );

            for( int i = start; i < end; i++ ) {
                const bionic_entry &entry = vStartingBionics[iCurrentPage][i];
                const bionic_data &bio = entry.id.obj();
                if( current == i && iCurrentPage == iCurWorkingPage ) {
                    int points = bio.points;
                    bool negativeTrait = points < 0;
                    if( negativeTrait ) {
                        points *= -1;
                    }
                    mvwprintz( w, point( full_string_length + 3, 3 ), col_tr,
                               vgettext( "%s %s %d point", "%s %s %d points", points ),
                               bio.name,
                               negativeTrait ? _( "earns" ) : _( "costs" ),
                               points );
                    fold_and_print( w_description, point_zero,
                                    TERMX - 2, col_tr,
                                    bio.description.translated() );
                }

                nc_color col;
                if( iCurWorkingPage == iCurrentPage ) {
                    if( entry.avatar_has ) {
                        col = col_on_act;
                    } else if( entry.conflicts || entry.forbidden ) {
                        col = c_dark_gray;
                    } else {
                        col = col_off_act;
                    }
                    if( current == i ) {
                        col = hilite( col );
                    }
                } else {
                    if( entry.avatar_has ) {
                        col = col_on_pas;
                    } else if( entry.conflicts || entry.forbidden ) {
                        col = c_light_gray;
                    } else {
                        col = col_off_pas;
                    }
                }

                int cur_y = 5 + i - start;
                int cur_x = 2 + iCurrentPage * page_width;
                mvwprintz( w, point( cur_x, cur_y ), col, utf8_truncate( bio.name.translated(), page_width - 2 ) );
            }

            draw_scrollbar( w, iCurrentLine[iCurrentPage], iContentHeight, bionics_size[iCurrentPage],
                            point( page_width * iCurrentPage, 5 ) );
        }
        // Draws main window, traits description window and character preview window
        wnoutrefresh( w );
        wnoutrefresh( w_description );
#if defined(TILES)
        // Draws character preview
        if( use_character_preview ) {
            character_preview.display();
        }
#endif
    } );

    do {
        ui_manager::redraw();
        const std::string action = ctxt.handle_input();
#if defined(TILES)
        if( const auto pick = native ? cata::godot_bridge::take_pick( &u ) : std::nullopt ) {
            if( const auto direction = chargen_tab_click( *pick, chargen_step::bionics, u.prof ) ) {
                character_preview.clear();
                return *direction;
            }
            const auto page = *pick / gs::row_stride;
            const auto row = *pick % gs::row_stride;
            if( page < used_pages && static_cast<size_t>( row ) < bionics_size[page] ) {
                iCurWorkingPage = page;
                iCurrentLine[page] = row;
            }
        }
        if( action == "zoom_in" && use_character_preview ) {
            character_preview.zoom_in();
        }
        if( action == "zoom_out" && use_character_preview ) {
            character_preview.zoom_out();
        }
        if( action == "TOGGLE_CHARACTER_PREVIEW_CLOTHES" && use_character_preview ) {
            character_preview.toggle_clothes();
        }
#endif
        if( action == "LEFT" ) {
            iCurWorkingPage--;
            if( iCurWorkingPage < 0 ) {
                iCurWorkingPage = used_pages - 1;
            }
        } else if( action == "RIGHT" ) {
            iCurWorkingPage++;
            if( iCurWorkingPage > used_pages - 1 ) {
                iCurWorkingPage = 0;
            }
        } else if( action == "UP" ) {
            if( iCurrentLine[iCurWorkingPage] == 0 ) {
                iCurrentLine[iCurWorkingPage] = bionics_size[iCurWorkingPage] - 1;
            } else {
                iCurrentLine[iCurWorkingPage]--;
            }
        } else if( action == "REROLL_CHARACTER" ) {
            points.init_from_options();
            u.randomize( false, points );
            // Return tab_direction::NONE so we re-enter this tab again, but it forces a complete redrawing of it.
            return tab_direction::NONE;
        } else if( action == "REROLL_CHARACTER_WITH_SCENARIO" ) {
            points.init_from_options();
            u.randomize( true, points );
            // Return tab_direction::NONE so we re-enter this tab again, but it forces a complete redrawing of it.
            return tab_direction::NONE;
        } else if( action == "REROLL_APPEARANCE" ) {
            u.randomize_cosmetics();
            //u.set_body();
            // Return tab_direction::NONE so we re-enter this tab again, but it forces a complete redrawing of it.
            return tab_direction::NONE;
        } else if( action == "DOWN" ) {
            iCurrentLine[iCurWorkingPage]++;
            if( static_cast<size_t>( iCurrentLine[iCurWorkingPage] ) >= bionics_size[iCurWorkingPage] ) {
                iCurrentLine[iCurWorkingPage] = 0;
            }
        } else if( action == "RANDOMIZE" ) {
            iCurrentLine[iCurWorkingPage] = rng( 0, bionics_size[iCurWorkingPage] - 1 );
        } else if( action == "CONFIRM" ) {
            int inc_type = 0;
            const bionic_id cur_bionic = vStartingBionics[iCurWorkingPage][iCurrentLine[iCurWorkingPage]].id;
            const bionic_data &bio = cur_bionic.obj();

            std::vector<trait_id> conflicting_traits;
            // Look through the profession bionics, and see if any of them conflict with this trait
            for( trait_id id : bio.canceled_mutations ) {
                if( u.has_trait( id ) ) {
                    conflicting_traits.push_back( id );
                }
            }
            std::vector<bionic_id> missing_bionics;
            if( !bio.required_bionics.empty() ) {
                for( const bionic_id &req_bid : bio.required_bionics ) {
                    if( !u.has_bionic( req_bid ) ) {
                        missing_bionics.push_back( req_bid );
                    }
                }
            }
            bionic_id has_downgrade = bionic_id::NULL_ID();
            if( cur_bionic->upgraded_bionic != bionic_id::NULL_ID() ) {
                bionic_id downgrade = cur_bionic->upgraded_bionic;
                if( u.has_bionic( downgrade ) ) {
                    has_downgrade = downgrade;
                }
                if( has_downgrade == bionic_id::NULL_ID() ) {
                    while( downgrade->upgraded_bionic != bionic_id::NULL_ID() ) {
                        downgrade = cur_bionic->upgraded_bionic;
                        if( u.has_bionic( downgrade ) ) {
                            has_downgrade = downgrade;
                            break;
                        }
                    }
                }
            }
            bionic_id has_upgrade = bionic_id::NULL_ID();
            for( bionic_id bio : cur_bionic->available_upgrades ) {
                if( u.has_bionic( bio ) ) {
                    has_upgrade = bio;
                    break;
                }
            }
            const bool has_bionic = u.has_bionic( cur_bionic );
            if( has_bionic ) {
                std::vector<std::string> dependent_bionics;
                for( const bionic &i : u.get_bionic_collection() ) {
                    const bionic_id &bid = i.id;
                    // look at required bionics for every installed bionic
                    for( const bionic_id &req_bid : bid->required_bionics ) {
                        if( req_bid == cur_bionic ) {
                            dependent_bionics.push_back( bid->name.translated() );
                        }
                    }
                }
                if( !dependent_bionics.empty() ) {
                    popup( _( "These bionics are dependent on the bionic you are trying to uninstall %s." ),
                           enumerate_as_string( dependent_bionics ) );
                } else {
                    inc_type = - 1;
                }
            } else if( g->scen->forbids_bionics() ) {
                popup( _( "The scenario you picked prevents you from taking any bionics!" ) );
            } else if( u.prof->forbids_bionics() ) {
                popup( _( "The profession you picked prevents you from taking any bionics!" ) );
            } else if( g->scen->is_forbidden_bionic( cur_bionic ) ) {
                popup( _( "The scenario you picked prevents you from taking this bionic!" ) );
            } else if( u.prof->is_forbidden_bionic( cur_bionic ) ) {
                popup( _( "Your profession of %s prevents you from taking this bionic." ),
                       u.prof->gender_appropriate_name( u.male ) );
            } else if( g->scen->is_locked_bionic( cur_bionic ) ) {
                inc_type = 0;
                popup( _( "Your scenario of %s prevents you from removing this bionic." ),
                       g->scen->gender_appropriate_name( u.male ) );
            } else if( u.prof->is_locked_bionic( cur_bionic ) ) {
                inc_type = 0;
                popup( _( "Your profession of %s prevents you from removing this bionic." ),
                       u.prof->gender_appropriate_name( u.male ) );
            } else if( !conflicting_traits.empty() ) {
                // Grab a list of the names of the bionics that block this trait
                // So that the player know what is preventing them from taking it
                std::vector<std::string> conflict_names;
                conflict_names.reserve( conflicting_traits.size() );
                for( const trait_id &conflict : conflicting_traits ) {
                    conflict_names.emplace_back( conflict.obj().name() );
                }
                popup( _( "The following traits prevent you from taking this bionic: %s." ),
                       enumerate_as_string( conflict_names ) );
            } else if( iCurWorkingPage == 0 && num_good + bio.points >
                       max_trait_points && !points.is_freeform() ) {
                popup( vgettext( "Sorry, but you can only take %d point of advantages.",
                                 "Sorry, but you can only take %d points of advantages.", max_trait_points ),
                       max_trait_points );

            } else if( iCurWorkingPage != 0 && num_bad + bio.points <
                       -max_trait_points && !points.is_freeform() ) {
                popup( vgettext( "Sorry, but you can only take %d point of disadvantages.",
                                 "Sorry, but you can only take %d points of disadvantages.", max_trait_points ),
                       max_trait_points );

            } else if( !u.bionic_installation_issues( cur_bionic ).empty() ) {
                const auto &issues = u.bionic_installation_issues( cur_bionic );
                std::string detailed_info;
                for( auto &elem : issues ) {
                    //~ <Body part name>: <number of slots> more slot(s) needed.
                    detailed_info += string_format( _( "\n%s: %i more slot(s) needed." ),
                                                    body_part_name_as_heading( elem.first->token, 1 ),
                                                    elem.second );
                }
                popup( _( "Not enough space for bionic installation!%s" ), detailed_info );
            } else if( !missing_bionics.empty() ) {
                // Grab a list of the names of the bionics that block this trait
                // So that the player know what is preventing them from taking it
                std::vector<std::string> conflict_names;
                conflict_names.reserve( missing_bionics.size() );
                for( const bionic_id &conflict : missing_bionics ) {
                    conflict_names.emplace_back( conflict->name.translated() );
                }
                popup( _( "The lack of the following bionics are prevent you from taking this bionic: %s." ),
                       enumerate_as_string( conflict_names ) );
            } else if( has_downgrade != bionic_id::NULL_ID() ) {
                popup( _( "You already have the downgraded version of the bionic: %s" ), has_downgrade->name );
            } else if( has_upgrade != bionic_id::NULL_ID() ) {
                popup( _( "You already have the upgraded version of the bionic: %s" ), has_upgrade->name );
            } else {
                inc_type = 1;
            }

            //inc_type is either -1 or 1, so we can just multiply by it to invert
            if( inc_type != 0 ) {
                u.toggle_bionic( cur_bionic );
#if defined(TILES)
                // If character had trait - it's now removed. Trait could blocked some clothes, need to retoggle
                if( has_bionic && character_preview.clothes_showing() ) {
                    character_preview.toggle_clothes();
                    character_preview.toggle_clothes();
                }
#endif
                points.trait_points -= bio.points * inc_type;

                if( iCurWorkingPage == 0 ) {
                    num_good += bio.points * inc_type;
                } else {
                    num_bad += bio.points * inc_type;
                }
            }

            recalc_display_cache();
        } else if( action == "PREV_TAB" ) {
#if defined(TILES)
            character_preview.clear();
#endif
            return tab_direction::BACKWARD;
        } else if( action == "NEXT_TAB" ) {
#if defined(TILES)
            character_preview.clear();
#endif
            return tab_direction::FORWARD;
        } else if( action == "QUIT" && query_yn( _( "Return to main menu?" ) ) ) {
#if defined(TILES)
            character_preview.clear();
#endif
            return tab_direction::QUIT;
        }
    } while( true );
}

struct {
    bool sort_by_points = true;
    bool male = false;
    /** @related player */
    bool operator()( const profession_id &a, const profession_id &b ) {
        // The generic ("Unemployed") profession should be listed first.
        const profession_id &gen = profession::generic();
        if( b == gen ) {
            return false;
        } else if( a == gen ) {
            return true;
        }

        if( sort_by_points ) {
            return a->point_cost() < b->point_cost();
        } else {
            return localized_compare( a->gender_appropriate_name( male ),
                                      b->gender_appropriate_name( male ) );
        }
    }
} profession_sorter;


/** Handle the profession tab of the character generation menu */
tab_direction set_profession( avatar &u, points_left &points,
                              const tab_direction direction )
{
    int cur_id = 0;
    tab_direction retval = tab_direction::NONE;
    int desc_offset = 0;
    int iContentHeight = 0;
    int iStartPos = 0;

    ui_adaptor ui;
    catacurses::window w;
    catacurses::window w_description;
    catacurses::window w_sorting;
    catacurses::window w_genderswap;
    catacurses::window w_items;
#if defined(TILES)
    character_preview_window character_preview;
    character_preview.init( &u );
    const bool use_character_preview = get_option<bool>( "USE_CHARACTER_PREVIEW" ) &&
                                       get_option<bool>( "USE_TILES" );
#endif
    const auto init_windows = [&]( ui_adaptor & ui ) {
        iContentHeight = TERMY - 10;
        w = catacurses::newwin( TERMY, TERMX, point_zero );
        w_description = catacurses::newwin( 4, TERMX - 2, point( 1, TERMY - 5 ) );
        w_sorting = catacurses::newwin( 1, 55, point( TERMX / 2, 5 ) );
        w_genderswap = catacurses::newwin( 1, 55, point( TERMX / 2, 6 ) );
        w_items = catacurses::newwin( iContentHeight - 2, 55, point( TERMX / 2, 7 ) );
#if defined(TILES)
        const int int_page_width = 55;

        if( use_character_preview && cata::godot_bridge::native_screens() ) {
            prepare_native_preview( character_preview );
        } else if( use_character_preview ) {
            constexpr int preview_nlines_min = 7;
            constexpr int preview_ncols_min = 10;
            const int preview_nlines = std::max( ( TERMY - 9 ) / 3, preview_nlines_min );
            const int preview_ncols = std::max( ( TERMX - int_page_width - 4 ) / 3 - 5,
                                                preview_ncols_min );
            constexpr auto orientation = character_preview_window::Orientation{
                character_preview_window::TOP_RIGHT,
                character_preview_window::Margin{0, 2, 5, 0}
            };
            character_preview.prepare(
                preview_nlines, preview_ncols,
                &orientation, int_page_width + 5
            );
        }
#endif
        ui.position_from_window( w );
    };
    init_windows( ui );
    ui.on_screen_resize( init_windows );

    input_context ctxt( "NEW_CHAR_PROFESSIONS" );
    ctxt.register_cardinal();
    ctxt.register_action( "CONFIRM" );
    ctxt.register_action( "CHANGE_GENDER" );
    ctxt.register_action( "PREV_TAB" );
    ctxt.register_action( "NEXT_TAB" );
    ctxt.register_action( "SORT" );
    ctxt.register_action( "HELP_KEYBINDINGS" );
    ctxt.register_action( "RANDOMIZE" );
    ctxt.register_action( "FILTER" );
    ctxt.register_action( "QUIT" );

    bool recalc_profs = true;
    int profs_length = 0;
    std::string filterstring;
    std::vector<string_id<profession>> sorted_profs;

    if( direction == tab_direction::FORWARD ) {
        points.skill_points -= u.prof->point_cost();
    }

    int iheight = 0;

    // Everything a profession starts with: addictions, traits, skills, items, bionics and more.
    const auto profession_details = [&]( const profession & prof ) -> std::string {
        std::string buffer;
        // Profession addictions
        const auto prof_addictions = prof.addictions();
        if( !prof_addictions.empty() )
        {
            buffer += colorize( _( "Addictions:" ), c_light_blue ) + "\n";
            for( const auto &a : prof_addictions ) {
                const auto format = pgettext( "set_profession_addictions", "%1$s (%2$d)" );
                buffer += string_format( format, addiction_name( a ), a.intensity ) + "\n";
            }
        }

        // Profession traits
        const auto prof_traits = prof.get_locked_traits();
        buffer += colorize( _( "Traits:" ), c_light_blue ) + "\n";
        if( prof_traits.empty() )
        {
            buffer += pgettext( "set_profession_trait", "None" ) + std::string( "\n" );
        } else
        {
            for( const auto &t : prof_traits ) {
                buffer += mutation_branch::get_name( t ) + "\n";
            }
        }

        // Profession skills
        std::vector<std::pair<skill_id, int>> prof_skills = prof.skills();
        std::stable_sort( prof_skills.begin(), prof_skills.end(),
                          []( const std::pair<skill_id, int> &a, const std::pair<skill_id, int> &b )
        {
            return localized_compare( std::make_pair( a.first->display_category(), a.first->name() ),
                                      std::make_pair( b.first->display_category(), b.first->name() ) );
        } );
        buffer += colorize( _( "Skills:" ), c_light_blue ) + "\n";
        if( prof_skills.empty() )
        {
            buffer += pgettext( "set_profession_skill", "None" ) + std::string( "\n" );
        } else
        {
            skill_displayType_id cur_category = skill_displayType_id::NULL_ID();
            for( const auto &sl : prof_skills ) {
                if( cur_category != sl.first->display_category() ) {
                    cur_category = sl.first->display_category();
                    buffer += colorize( string_format( sl.first->display_category()->display_string() ),
                                        c_yellow ) + "\n";
                }
                const auto format = pgettext( "set_profession_skill", "%1$s (%2$d)" );
                buffer += "  " + string_format( format, sl.first.obj().name(), sl.second ) + "\n";
            }
        }

        // Profession items
        const auto prof_items = prof.items( u.male, u.get_mutations() );
        buffer += colorize( _( "Items:" ), c_light_blue ) + "\n";
        if( prof_items.empty() )
        {
            buffer += pgettext( "set_profession_item", "None" ) + std::string( "\n" );
        } else
        {
            // TODO: If the item group is randomized *at all*, these will be different each time
            // and it won't match what you actually start with
            // TODO: Put like items together like the inventory does, so we don't have to scroll
            // through a list of a dozen forks.
            std::string buffer_wielded;
            std::string buffer_worn;
            std::string buffer_inventory;
            for( const auto &it : prof_items ) {
                if( it->has_flag( json_flag_no_auto_equip ) ) {
                    buffer_inventory += it->display_name() + "\n";
                } else if( it->has_flag( json_flag_auto_wield ) ) {
                    buffer_wielded += it->display_name() + "\n";
                } else if( it->is_armor() ) {
                    buffer_worn += it->display_name() + "\n";
                } else {
                    buffer_inventory += it->display_name() + "\n";
                }
            }
            buffer += colorize( _( "Wielded:" ), c_cyan ) + "\n";
            buffer += !buffer_wielded.empty() ? buffer_wielded : pgettext( "set_profession_item_wielded",
                      "None\n" );
            buffer += colorize( _( "Worn:" ), c_cyan ) + "\n";
            buffer += !buffer_worn.empty() ? buffer_worn : pgettext( "set_profession_item_worn", "None\n" );
            buffer += colorize( _( "Inventory:" ), c_cyan ) + "\n";
            buffer += !buffer_inventory.empty() ? buffer_inventory : pgettext( "set_profession_item_inventory",
                      "None\n" );
        }

        // Profession bionics, active bionics shown first
        auto prof_CBMs = prof.CBMs();
        std::sort( begin( prof_CBMs ), end( prof_CBMs ), []( const bionic_id & a, const bionic_id & b )
        {
            return a->activated && !b->activated;
        } );
        buffer += colorize( _( "Bionics:" ), c_light_blue ) + "\n";
        if( prof_CBMs.empty() )
        {
            buffer += pgettext( "set_profession_bionic", "None" ) + std::string( "\n" );
        } else
        {
            for( const auto &b : prof_CBMs ) {
                const auto &cbm = b.obj();

                if( cbm.activated && cbm.has_flag( STATIC( flag_id( "BIONIC_TOGGLED" ) ) ) ) {
                    buffer += string_format( _( "%s (toggled)" ), cbm.name ) + "\n";
                } else if( cbm.activated ) {
                    buffer += string_format( _( "%s (activated)" ), cbm.name ) + "\n";
                } else {
                    buffer += cbm.name + "\n";
                }
            }
        }
        // Profession pet
        if( !prof.pets().empty() )
        {
            buffer += colorize( _( "Pets:" ), c_light_blue ) + "\n";
            for( auto elem : prof.pets() ) {
                monster mon( elem );
                buffer += mon.get_name() + "\n";
            }
        }
        // Profession vehicle
        if( prof.vehicle() )
        {
            buffer += colorize( _( "Vehicle:" ), c_light_blue ) + "\n";
            vproto_id veh_id = prof.vehicle();
            buffer += veh_id->name + "\n";
        }
        // Profession spells
        if( !prof.spells().empty() )
        {
            buffer += colorize( _( "Spells:" ), c_light_blue ) + "\n";
            for( const std::pair<spell_id, int> spell_pair : prof.spells() ) {
                buffer += string_format( _( "%s level %d" ), spell_pair.first->name, spell_pair.second ) + "\n";
            }
        }

        // Profession money
        std::optional<int> cash = prof.starting_cash();

        if( cash.has_value() )
        {
            buffer += colorize( _( "Money:" ), c_light_blue ) + "\n";
            buffer += format_money( cash.value() ) + "\n";
        }
        // Profession companions
        std::vector<npc_class_id> npcs = prof.npcs();

        if( !npcs.empty() )
        {
            buffer += "\n" + colorize( _( "Companions:" ), c_light_blue ) + "\n";
            for( const npc_class_id &id : npcs ) {
                if( id.is_valid() ) {
                    const npc_class &npc_cls = id.obj();
                    buffer += npc_cls.get_name() + "\n";
                }
            }
        }
        return buffer;
    };

#if defined(TILES)
    // Draws the character preview with the highlighted profession, so it shows that profession's
    // clothes and bionics rather than the currently chosen one's.
    const auto display_preview = [&]() {
        if( cur_id < 0 || static_cast<size_t>( cur_id ) >= sorted_profs.size() ) {
            character_preview.display();
            return;
        }
        const auto old_prof = u.prof;
        u.prof = sorted_profs[cur_id];
        character_preview.display();
        u.prof = old_prof;
    };
    const auto native = chargen_view( ui, u, "NEW_CHAR_PROFESSIONS", init_windows );
    const auto publish_native = [&]() {
        const auto valid = cur_id >= 0 && static_cast<size_t>( cur_id ) < sorted_profs.size();
        const auto frame = chargen_frame{ .u = u, .points = points, .step = chargen_step::profession, .category = "NEW_CHAR_PROFESSIONS",
                                          .net_cost = valid ? sorted_profs[cur_id]->point_cost() - u.prof->point_cost() : 0 };
        native->publish( [&]( JsonOut & jsout ) {
            write_chargen_frame( jsout, frame );
            write_choice_toolbar( jsout, { .category = frame.category, .filter = filterstring,
                                           .placeholder = _( "Search by profession name." ), .by_points = profession_sorter.sort_by_points,
                                           .male = u.male
                                         } );
            jsout.member( "panes" );
            jsout.start_array();
            jsout.start_object();
            jsout.member( "title", _( "Professions" ) );
            jsout.member( "icon", "briefcase" );
            jsout.member( "count", std::to_string( sorted_profs.size() ) );
            jsout.member( "cursor", cur_id );
            jsout.member( "rows" );
            jsout.start_array();
            for( const auto &p : sorted_profs ) {
                write_choice_row( jsout, { .name = p->gender_appropriate_name( u.male ), .cost = p->point_cost(), .chosen = p == u.prof } );
            }
            jsout.end_array();
            jsout.end_object();
            jsout.end_array();

            jsout.member( "aside" );
            jsout.start_object();
            jsout.member( "width", 560 );
            if( use_character_preview ) {
                write_preview( jsout, character_preview, "" );
            }
            if( valid ) {
                const auto &prof = *sorted_profs[cur_id];
                const auto cost = std::abs( prof.point_cost() );
                const auto cost_text = prof.point_cost() < 0 ?
                                       vgettext( "Profession %1$s earns %2$d point", "Profession %1$s earns %2$d points", cost ) :
                                       vgettext( "Profession %1$s costs %2$d point", "Profession %1$s costs %2$d points", cost );
                const auto can_pick = can_pick_prof( prof, u, points.skill_points_left() );
                const auto details = profession_details( prof );
                // Lets the keys scroll the details as far as the old screen did.
                iheight = static_cast<int>( std::ranges::count( details, '\n' ) );
                jsout.member( "title" );
                gs::write_span( jsout, { .text = prof.gender_appropriate_name( u.male ), .color = c_white } );
                jsout.member( "body" );
                gs::write_span( jsout, { .text = colorize( string_format( cost_text, prof.gender_appropriate_name( u.male ), cost ),
                                                 can_pick ? c_green : c_light_red ) + "\n\n" + prof.description( u.male ) + "\n\n" + details
                                       } );
                jsout.member( "scroll", desc_offset );
            }
            jsout.member( "buttons" );
            jsout.start_array();
            gs::write_button( jsout, { .act = "CONFIRM", .text = _( "Choose profession" ), .icon = "check", .category = frame.category,
                                       .enabled = valid && sorted_profs[cur_id] != u.prof
                                     } );
            write_next_button( jsout, frame );
            jsout.end_array();
            jsout.end_object();

            jsout.member( "hints" );
            jsout.start_array();
            gs::write_fixed_hint( jsout, "↑↓", _( "Choose" ) );
            gs::write_hint( jsout, "CONFIRM", frame.category, _( "Pick" ) );
            gs::write_fixed_hint( jsout, "←→", _( "Scroll details" ) );
            gs::write_hint( jsout, "RANDOMIZE", frame.category, _( "Random pick" ) );
            write_nav_hints( jsout, frame.category );
            jsout.end_array();
        } );
    };
#endif

    ui.on_redraw( [&]( const ui_adaptor & ) {
#if defined(TILES)
        if( native ) {
            publish_native();
            if( use_character_preview ) {
                display_preview();
            }
            return;
        }
#endif
        werase( w );
        draw_character_tabs( w, _( "PROFESSION" ), u.prof );

        // Draw filter indicator
        for( int i = 1; i < getmaxx( w ) - 1; i++ ) {
            mvwputch( w, point( i, getmaxy( w ) - 1 ), BORDER_COLOR, LINE_OXOX );
        }
        const auto filter_indicator = filterstring.empty() ? _( "no filter" )
                                      : filterstring;
        mvwprintz( w, point( 2, getmaxy( w ) - 1 ), c_light_gray, "<%s>", filter_indicator );

        const bool cur_id_is_valid = cur_id >= 0 && static_cast<size_t>( cur_id ) < sorted_profs.size();

        werase( w_description );
        if( cur_id_is_valid ) {
            int netPointCost = sorted_profs[cur_id]->point_cost() - u.prof->point_cost();
            bool can_pick = can_pick_prof( *sorted_profs[cur_id], u, points.skill_points_left() );
            const std::string clear_line( getmaxx( w ) - 2, ' ' );

            // Clear the bottom of the screen and header.
            mvwprintz( w, point( 1, 3 ), c_light_gray, clear_line );

            int pointsForProf = sorted_profs[cur_id]->point_cost();
            bool negativeProf = pointsForProf < 0;
            if( negativeProf ) {
                pointsForProf *= -1;
            }
            // Draw header.
            draw_points( w, points, netPointCost );
            std::string prof_msg_temp;
            if( negativeProf ) {
                //~ 1s - profession name, 2d - current character points.
                prof_msg_temp = vgettext( "Profession %1$s earns %2$d point",
                                          "Profession %1$s earns %2$d points",
                                          pointsForProf );
            } else {
                //~ 1s - profession name, 2d - current character points.
                prof_msg_temp = vgettext( "Profession %1$s costs %2$d point",
                                          "Profession %1$s costs %2$d points",
                                          pointsForProf );
            }

            int pMsg_length = utf8_width( remove_color_tags( points.to_string() ) );
            mvwprintz( w, point( pMsg_length + 9, 3 ), can_pick ? c_green : c_light_red, prof_msg_temp.c_str(),
                       sorted_profs[cur_id]->gender_appropriate_name( u.male ),
                       pointsForProf );

            fold_and_print( w_description, point_zero, TERMX - 2, c_green,
                            sorted_profs[cur_id]->description( u.male ) );
        }

        //Draw options
        calcStartPos( iStartPos, cur_id, iContentHeight, profs_length );
        const int end_pos = iStartPos + ( ( iContentHeight > profs_length ) ?
                                          profs_length : iContentHeight );
        int i;
        for( i = iStartPos; i < end_pos; i++ ) {
            mvwprintz( w, point( 2, 5 + i - iStartPos ), c_light_gray,
                       "                                             " ); // Clear the line
            nc_color col;
            if( u.prof != sorted_profs[i] ) {
                col = ( cur_id_is_valid && sorted_profs[i] == sorted_profs[cur_id] ? h_light_gray : c_light_gray );
            } else {
                col = ( cur_id_is_valid &&
                        sorted_profs[i] == sorted_profs[cur_id] ? hilite( COL_SKILL_USED ) : COL_SKILL_USED );
            }
            mvwprintz( w, point( 2, 5 + i - iStartPos ), col,
                       sorted_profs[i]->gender_appropriate_name( u.male ) );
        }
        //Clear rest of space in case stuff got filtered out
        for( ; i < iStartPos + iContentHeight; ++i ) {
            mvwprintz( w, point( 2, 5 + i - iStartPos ), c_light_gray,
                       "                                             " ); // Clear the line
        }

        werase( w_items );
        werase( w_sorting );
        werase( w_genderswap );
        if( cur_id_is_valid ) {
            const auto buffer = profession_details( *sorted_profs[cur_id] );
            const auto scroll_msg = string_format(
                                        _( "Press <color_light_green>%1$s</color> or <color_light_green>%2$s</color> to scroll." ),
                                        ctxt.get_desc( "LEFT" ),
                                        ctxt.get_desc( "RIGHT" ) );
            iheight = print_scrollable( w_items, desc_offset, buffer, c_light_gray, scroll_msg );

            draw_sorting_indicator( w_sorting, ctxt, profession_sorter );

            std::string g_switch_msg = u.male ?
                                       //~ Gender switch message. 1s - change key name, 2s - profession name.
                                       _( "Press <color_light_green>%1$s</color> to switch "
                                          "to <color_magenta>%2$s</color> (<color_pink>female</color>)." ) :
                                       //~ Gender switch message. 1s - change key name, 2s - profession name.
                                       _( "Press <color_light_green>%1$s</color> to switch "
                                          "to <color_magenta>%2$s</color> (<color_light_cyan>male</color>)." );
            fold_and_print( w_genderswap, point_zero, ( TERMX / 2 ), c_light_gray, g_switch_msg.c_str(),
                            ctxt.get_desc( "CHANGE_GENDER" ),
                            sorted_profs[cur_id]->gender_appropriate_name( !u.male ) );
        }

        draw_scrollbar( w, cur_id, iContentHeight, profs_length, point( 0, 5 ) );

        wnoutrefresh( w );
        wnoutrefresh( w_description );
        wnoutrefresh( w_items );
        wnoutrefresh( w_genderswap );
        wnoutrefresh( w_sorting );
#if defined(TILES)
        if( use_character_preview ) {
            display_preview();
        }
#endif
    } );

    do {
        if( recalc_profs ) {
            sorted_profs = g->scen->permitted_professions();
            const auto new_end = std::remove_if( sorted_profs.begin(),
            sorted_profs.end(), [&]( const string_id<profession> &arg ) {
                return !lcmatch( arg->gender_appropriate_name( u.male ), filterstring );
            } );
            sorted_profs.erase( new_end, sorted_profs.end() );
            profs_length = sorted_profs.size();
            if( profs_length == 0 ) {
                popup( _( "Nothing found." ) ); // another case of black box in tiles
                filterstring.clear();
                continue;
            }

            // Sort professions by points.
            // profession_display_sort() keeps "unemployed" at the top.
            profession_sorter.male = u.male;
            std::stable_sort( sorted_profs.begin(), sorted_profs.end(), profession_sorter );

            // Select the current profession, if possible.
            for( int i = 0; i < profs_length; ++i ) {
                if( sorted_profs[i] == u.prof ) {
                    cur_id = i;
                    break;
                }
            }
            if( cur_id > profs_length - 1 ) {
                cur_id = 0;
            }

            recalc_profs = false;
        }

        ui_manager::redraw();
        const std::string action = ctxt.handle_input();
#if defined(TILES)
        if( const auto pick = native ? cata::godot_bridge::take_pick( &u ) : std::nullopt ) {
            if( const auto direction = chargen_tab_click( *pick, chargen_step::profession, u.prof ) ) {
                retval = *direction;
                continue;
            }
            if( *pick < profs_length && *pick != cur_id ) {
                cur_id = *pick;
                desc_offset = 0;
            }
        }
#endif
        if( action == "DOWN" ) {
            cur_id++;
            if( cur_id > profs_length - 1 ) {
                cur_id = 0;
            }
            desc_offset = 0;
            // Update preview immediately when moving selection
#if defined(TILES)
            if( use_character_preview ) {
                ui_manager::redraw();
            }
#endif
        } else if( action == "UP" ) {
            cur_id--;
            if( cur_id < 0 ) {
                cur_id = profs_length - 1;
            }
            desc_offset = 0;
#if defined(TILES)
            if( use_character_preview ) {
                ui_manager::redraw();
            }
#endif
        } else if( action == "LEFT" ) {
            if( desc_offset > 0 ) {
                desc_offset--;
            }
        } else if( action == "RANDOMIZE" ) {
            cur_id = rng( 0, profs_length - 1 );
        } else if( action == "RIGHT" ) {
            if( desc_offset < iheight ) {
                desc_offset++;
            }
        } else if( action == "CONFIRM" ) {
            // Remove traits from the previous profession
            for( const trait_id &old_trait : u.prof->get_locked_traits() ) {
                u.toggle_trait( old_trait );
            }
            const int netPointCost = sorted_profs[cur_id]->point_cost() - u.prof->point_cost();
            u.prof = sorted_profs[cur_id];
            u.set_base_age( random_age_for_profession( *u.prof ) );
            // Add traits for the new profession (and perhaps scenario, if, for example,
            // both the scenario and old profession require the same trait)
            newcharacter::add_traits( u, points );
            points.skill_points -= netPointCost;
        } else if( action == "CHANGE_GENDER" ) {
            u.male = !u.male;
            profession_sorter.male = u.male;
            if( !profession_sorter.sort_by_points ) {
                std::sort( sorted_profs.begin(), sorted_profs.end(), profession_sorter );
            }
        } else if( action == "PREV_TAB" ) {
            retval = tab_direction::BACKWARD;
        } else if( action == "NEXT_TAB" ) {
            retval = tab_direction::FORWARD;
        } else if( action == "SORT" ) {
            profession_sorter.sort_by_points = !profession_sorter.sort_by_points;
            recalc_profs = true;
        } else if( action == "FILTER" ) {
            string_input_popup()
            .title( _( "Search:" ) )
            .width( 60 )
            .description( _( "Search by profession name." ) )
            .edit( filterstring );
            recalc_profs = true;
        } else if( action == "QUIT" && query_yn( _( "Return to main menu?" ) ) ) {
            retval = tab_direction::QUIT;
        }

    } while( retval == tab_direction::NONE );

    return retval;
}

/**
 * @return The skill points to consume when a skill is increased (by one level) from the
 * current level.
 *
 * @note: There is one exception: if the current level is 0, it can be boosted by 2 levels for 1 point.
 */
static int skill_increment_cost( const Character &u, const skill_id &skill )
{
    return std::max( 1, ( u.get_skill_level( skill, true ) + 1 ) / 2 );
}

tab_direction set_skills( avatar &u, points_left &points )
{
    ui_adaptor ui;
    catacurses::window w;
    catacurses::window w_description;
    int iContentHeight = 0;
    const auto init_windows = [&]( ui_adaptor & ui ) {
        iContentHeight = TERMY - 6;
        w = catacurses::newwin( TERMY, TERMX, point_zero );
        w_description = catacurses::newwin( iContentHeight, TERMX - 35, point( 31, 5 ) );
        ui.position_from_window( w );
    };
    init_windows( ui );
    ui.on_screen_resize( init_windows );

    auto sorted_skills = Skill::get_skills_sorted_by( []( const Skill & a, const Skill & b ) {
        return localized_compare( std::make_pair( a.display_category(), a.name() ),
                                  std::make_pair( b.display_category(), b.name() ) );
    } );

    skill_displayType_id current_category = skill_displayType_id::NULL_ID();
    // Actual line that the skill takes up.
    int display_line = 0;
    std::vector<std::pair<const Skill *, int>> skill_list;
    for( const Skill *skl : sorted_skills ) {
        if( current_category != skl->display_category() ) {
            current_category = skl->display_category();
            display_line++;
        }
        skill_list.emplace_back( skl, display_line );
        display_line++;
    }

    const int num_skills = skill_list.size();
    int cur_offset = 0;
    int cur_pos = 0;
    const Skill *currentSkill = skill_list[cur_pos].first;
    int selected = 0;

    input_context ctxt( "NEW_CHAR_SKILLS" );
    ctxt.register_cardinal();
    ctxt.register_action( "SCROLL_DOWN" );
    ctxt.register_action( "SCROLL_UP" );
    ctxt.register_action( "PREV_TAB" );
    ctxt.register_action( "NEXT_TAB" );
    ctxt.register_action( "RANDOMIZE" );
    ctxt.register_action( "HELP_KEYBINDINGS" );
    ctxt.register_action( "QUIT" );

    std::map<skill_id, int> prof_skills;
    const auto &pskills = u.prof->skills();

    std::copy( pskills.begin(), pskills.end(),
               std::inserter( prof_skills, prof_skills.begin() ) );

    const int remaining_points_length = utf8_width( points.to_string(), true );

    // The skill's description and the recipes it would let the character craft.
    const auto skill_text = [&]() -> std::string {
        // We want recipes from profession skills displayed, but without boosting the skills
        // Copy the skills, and boost the copy
        SkillLevelMap with_prof_skills = u.get_all_skills();
        for( const auto &sk : prof_skills )
        {
            with_prof_skills.mod_skill_level( sk.first, sk.second );
        }

        std::map<std::string, std::vector<std::pair<std::string, int> > > recipes;
        for( const auto &e : recipe_dict )
        {
            const auto &r = e.second;
            if( r.has_flag( "SECRET" ) ) {
                continue;
            }
            //Find out if the current skill and its level is in the requirement list
            auto req_skill = r.required_skills.find( currentSkill->ident() );
            int skill = req_skill != r.required_skills.end() ? req_skill->second : 0;
            bool would_autolearn_recipe =
                recipe_dict.all_autolearn().contains( &r ) &&
                with_prof_skills.meets_skill_requirements( r.autolearn_requirements );

            if( !would_autolearn_recipe && !r.never_learn &&
                ( r.skill_used == currentSkill->ident() || skill > 0 ) &&
                with_prof_skills.has_recipe_requirements( r ) )  {

                recipes[r.skill_used->name()].emplace_back(
                    r.result_name( /*decorated=*/true ),
                    ( skill > 0 ) ? skill : r.difficulty
                );
            }
        }

        std::string rec_disp;

        for( auto &elem : recipes )
        {
            std::sort( elem.second.begin(), elem.second.end(),
                       []( const std::pair<std::string, int> &lhs,
            const std::pair<std::string, int> &rhs ) {
                return localized_compare( std::make_pair( lhs.second, lhs.first ),
                                          std::make_pair( rhs.second, rhs.first ) );
            } );

            const std::string rec_temp = enumerate_as_string( elem.second.begin(), elem.second.end(),
            []( const std::pair<std::string, int> &rec ) {
                return string_format( "%s (%d)", rec.first, rec.second );
            } );

            if( elem.first == currentSkill->name() ) {
                rec_disp = "\n\n" + colorize( rec_temp, c_brown ) + rec_disp;
            } else {
                rec_disp += "\n\n" + colorize( "[" + elem.first + "]\n" + rec_temp, c_light_gray );
            }
        }

        return currentSkill->description() + rec_disp;
    };

#if defined(TILES)
    const auto native = chargen_view( ui, u, "NEW_CHAR_SKILLS", init_windows );
    const auto publish_native = [&]() {
        const auto frame = chargen_frame{ .u = u, .points = points, .step = chargen_step::skills, .category = "NEW_CHAR_SKILLS" };
        native->publish( [&]( JsonOut & jsout ) {
            write_chargen_frame( jsout, frame );
            jsout.member( "panes" );
            jsout.start_array();
            jsout.start_object();
            jsout.member( "title", _( "Skills" ) );
            jsout.member( "icon", "graduation-cap" );
            jsout.member( "cursor", cur_pos );
            jsout.member( "confirm", "" );
            jsout.member( "rows" );
            jsout.start_array();
            auto category = skill_displayType_id::NULL_ID();
            for( const auto &[i, entry] : skill_list | std::views::enumerate ) {
                const auto *skill = entry.first;
                if( category != skill->display_category() ) {
                    category = skill->display_category();
                    gs::write_row( jsout, { .text = { .text = category->display_string(), .color = c_yellow }, .heading = true } );
                }
                const auto level = u.get_skill_level( skill->ident(), true );
                const auto bonus = prof_skills.find( skill->ident() );
                gs::write_row( jsout, { .text = { .text = skill->name(), .color = level > 0 ? COL_SKILL_USED : c_light_gray },
                .cells = {
                    { .text = level > 0 ? std::to_string( level ) : "", .color = COL_SKILL_USED },
                    { .text = bonus != prof_skills.end() ? string_format( "+%d", bonus->second ) : "", .color = c_white },
                },
                .i = static_cast<int>( i ),
                .tip = bonus != prof_skills.end() ? _( "Your profession adds the levels in white." ) : ""
                                      } );
            }
            jsout.end_array();
            jsout.end_object();
            jsout.end_array();

            const auto cost = skill_increment_cost( u, currentSkill->ident() );
            const auto level = u.get_skill_level( currentSkill->ident(), true );
            const auto upgrade_levels = level == 0 ? 2 : 1;
            const auto upgrade_levels_s = string_format( vgettext( "%d level", "%d levels", upgrade_levels ),
                                          upgrade_levels );
            jsout.member( "aside" );
            jsout.start_object();
            jsout.member( "width", 620 );
            jsout.member( "title" );
            gs::write_span( jsout, { .text = currentSkill->name(), .color = c_white } );
            jsout.member( "subtitle", currentSkill->display_category()->display_string() );
            jsout.member( "body" );
            gs::write_span( jsout, { .text = colorize( string_format( vgettext( "Upgrading %s by %s costs %d point",
                                             "Upgrading %s by %s costs %d points", cost ), currentSkill->name(), upgrade_levels_s, cost ),
                                             points.skill_points_left() >= cost ? COL_SKILL_USED : c_light_red ) + "\n\n" + skill_text(),
                                     .color = c_light_gray
                                   } );
            jsout.member( "scroll", selected );
            jsout.member( "buttons" );
            jsout.start_array();
            gs::write_button( jsout, { .act = "LEFT", .text = _( "Lower" ), .icon = "minus", .category = frame.category, .enabled = level > 0 } );
            gs::write_button( jsout, { .act = "RIGHT", .text = _( "Raise" ), .icon = "plus", .category = frame.category, .enabled = level < MAX_SKILL } );
            write_next_button( jsout, frame );
            jsout.end_array();
            jsout.end_object();

            jsout.member( "hints" );
            jsout.start_array();
            gs::write_fixed_hint( jsout, "↑↓", _( "Choose" ) );
            gs::write_hint( jsout, "LEFT", frame.category, _( "Lower" ) );
            gs::write_hint( jsout, "RIGHT", frame.category, _( "Raise" ) );
            gs::write_hint( jsout, "SCROLL_DOWN", frame.category, _( "Scroll" ) );
            write_nav_hints( jsout, frame.category );
            jsout.end_array();
        } );
    };
#endif

    ui.on_redraw( [&]( const ui_adaptor & ) {
#if defined(TILES)
        if( native ) {
            publish_native();
            return;
        }
#endif
        draw_character_tabs( w, _( "SKILLS" ), u.prof );

        draw_points( w, points );
        // Clear the bottom of the screen.
        werase( w_description );
        mvwprintz( w, point( remaining_points_length + 9, 3 ), c_light_gray,
                   std::string( getmaxx( w ) - remaining_points_length - 10, ' ' ) );

        // Write the hint as to upgrade costs
        const int cost = skill_increment_cost( u, currentSkill->ident() );
        const int level = u.get_skill_level( currentSkill->ident(), true );
        const int upgrade_levels = level == 0 ? 2 : 1;
        // We have two different strings to pluralize, so we have to use two
        // translation calls.
        const std::string upgrade_levels_s = string_format(
                //~ levels here are skill levels at character creation time
                vgettext( "%d level", "%d levels", upgrade_levels ), upgrade_levels );
        const nc_color color = points.skill_points_left() >= cost ? COL_SKILL_USED : c_light_red;
        mvwprintz( w, point( remaining_points_length + 9, 3 ), color,
                   //~ Second string is e.g. "1 level" or "2 levels"
                   vgettext( "Upgrading %s by %s costs %d point",
                             "Upgrading %s by %s costs %d points", cost ),
                   currentSkill->name(), upgrade_levels_s, cost );

        const auto rec_disp = skill_text();

        const auto vFolded = foldstring( rec_disp, getmaxx( w_description ) );
        int iLines = vFolded.size();

        if( selected < 0 ) {
            selected = 0;
        } else if( iLines < iContentHeight ) {
            selected = 0;
        } else if( selected >= iLines - iContentHeight ) {
            selected = iLines - iContentHeight;
        }

        fold_and_print_from( w_description, point_zero, getmaxx( w_description ),
                             selected, COL_SKILL_USED, rec_disp );

        draw_scrollbar( w, selected, iContentHeight, iLines,
                        point( getmaxx( w ) - 1, 5 ), BORDER_COLOR, true );

        // skill_list[cur_pos].second - 1 so the first skill is considered the first item on scrollbar.
        // display_line - 1 and iContentHeight - 1 compensates for the offset by the prior.
        // same application in the draw_scrolbar function later.
        calcStartPos( cur_offset, skill_list[cur_pos].second - 1, iContentHeight - 1, display_line - 1 );
        current_category = skill_displayType_id::NULL_ID();
        for( int i = 0; i < num_skills && skill_list[i].second - cur_offset - 1 < iContentHeight; ++i ) {
            const int y = 5 + skill_list[i].second - cur_offset;
            // Necessary because cur_offset doesn't indicate the first object to read. A bit hacky.
            if( y < 5 ) {
                continue;
            }
            const skill_displayType_id &display_type = skill_list[i].first->display_category();
            const Skill *thisSkill = skill_list[i].first;
            if( current_category != display_type && y - 1 >= 5 ) {
                // Clear the line
                mvwprintz( w, point( 2, y - 1 ), c_light_gray, std::string( getmaxx( w ) - 3, ' ' ) );
                mvwprintz( w, point( 2, y - 1 ), c_yellow, display_type->display_string() );
                current_category = display_type;
            }
            if( y < iContentHeight + 5 ) {
                // Clear the line. 2 for x-coord because category names will be scrolled over.
                mvwprintz( w, point( 2, y ), c_light_gray, std::string( getmaxx( w ) - 3, ' ' ) );
                if( u.get_skill_level( thisSkill->ident(), true ) == 0 ) {
                    mvwprintz( w, point( 4, y ),
                               ( i == cur_pos ? h_light_gray : c_light_gray ), thisSkill->name() );
                } else {
                    mvwprintz( w, point( 4, y ),
                               ( i == cur_pos ? hilite( COL_SKILL_USED ) : COL_SKILL_USED ),
                               thisSkill->name() );
                    mvwprintz( w, point( 20, y ),
                               ( i == cur_pos ? hilite( COL_SKILL_USED ) : COL_SKILL_USED ),
                               " (%d)", u.get_skill_level( thisSkill->ident(), true ) );
                }
            }
            for( auto &prof_skill : u.prof->skills() ) {
                if( prof_skill.first == thisSkill->ident() ) {
                    wprintz( w, ( i == cur_pos ? h_white : c_white ), " (+%d)",
                             static_cast<int>( prof_skill.second ) );
                    break;
                }
            }
        }

        draw_scrollbar( w, skill_list[cur_pos].second - 1, iContentHeight - 1, display_line - 1, point( 0,
                        5 ) );

        wnoutrefresh( w );
        wnoutrefresh( w_description );
    } );

    do {
        ui_manager::redraw();
        const std::string action = ctxt.handle_input();
#if defined(TILES)
        if( const auto pick = native ? cata::godot_bridge::take_pick( &u ) : std::nullopt ) {
            if( const auto direction = chargen_tab_click( *pick, chargen_step::skills, u.prof ) ) {
                return *direction;
            }
            if( *pick < num_skills ) {
                cur_pos = *pick;
                currentSkill = skill_list[cur_pos].first;
                selected = 0;
            }
        }
        if( native && ( action == "SCROLL_DOWN" || action == "SCROLL_UP" ) ) {
            // The old screen stops scrolling at the end of the text it folded; this one at its last line.
            const auto lines = static_cast<int>( std::ranges::count( skill_text(), '\n' ) );
            selected = std::clamp( selected + ( action == "SCROLL_DOWN" ? 1 : -1 ), 0, lines );
            continue;
        }
#endif
        if( action == "DOWN" ) {
            cur_pos = modulo( cur_pos + 1, num_skills );
            currentSkill = skill_list[cur_pos].first;
        } else if( action == "UP" ) {
            cur_pos = modulo( cur_pos - 1, num_skills );
            currentSkill = skill_list[cur_pos].first;
        } else if( action == "RANDOMIZE" ) {
            cur_pos = modulo( rng( 0, num_skills - 1 ), num_skills );
        } else if( action == "LEFT" ) {
            const int level = u.get_skill_level( currentSkill->ident(), true );
            if( level > 0 ) {
                // For balance reasons, increasing a skill from level 0 gives 1 extra level for free, but
                // decreasing it from level 2 forfeits the free extra level (thus changes it to 0)
                u.mod_skill_level( currentSkill->ident(), level == 2 ? -2 : -1 );
                // Done *after* the decrementing to get the original cost for incrementing back.
                points.skill_points += skill_increment_cost( u, currentSkill->ident() );
            }
        } else if( action == "RIGHT" ) {
            const int level = u.get_skill_level( currentSkill->ident(), true );
            if( level < MAX_SKILL ) {
                points.skill_points -= skill_increment_cost( u, currentSkill->ident() );
                // For balance reasons, increasing a skill from level 0 gives 1 extra level for free
                u.mod_skill_level( currentSkill->ident(), level == 0 ? +2 : +1 );
            }
        } else if( action == "SCROLL_DOWN" ) {
            selected++;
        } else if( action == "SCROLL_UP" ) {
            selected--;
        } else if( action == "PREV_TAB" ) {
            return tab_direction::BACKWARD;
        } else if( action == "NEXT_TAB" ) {
            return tab_direction::FORWARD;
        } else if( action == "QUIT" && query_yn( _( "Return to main menu?" ) ) ) {
            return tab_direction::QUIT;
        }
    } while( true );
}

tab_direction set_magic( avatar &u, points_left &points )
{
    ui_adaptor ui;
    catacurses::window w;
    catacurses::window w_description;
    int iContentHeight = 0;
    const auto init_windows = [&]( ui_adaptor & ui ) {
        iContentHeight = TERMY - 6;
        w = catacurses::newwin( TERMY, TERMX, point_zero );
        w_description = catacurses::newwin( iContentHeight, TERMX / 2 - 4, point( TERMX / 2, 5 ) );
        ui.position_from_window( w );
    };
    init_windows( ui );
    ui.on_screen_resize( init_windows );

    std::vector<spell_id> sorted_spells;
    for( spell_type spell : spell_type::get_all() ) {
        if( spell.starting_spell || g->scen->spellquery( spell.id ) ||
            u.prof->is_allowed_spell( spell.id ) ) {
            sorted_spells.push_back( spell.id );
        }
    }
    std::ranges::sort( sorted_spells, [&]( const spell_id & left, const spell_id & right ) {
        // Sort by name in class
        // Within a sorted list of classes
        if( left->spell_class == right->spell_class ) {
            return localized_compare( left->name.translated(), right->name.translated() );
        } else {
            if( left->spell_class == trait_id( "NONE" ) ) {
                return true;
            } else if( right->spell_class == trait_id( "NONE" ) ) {
                return false;
            }
            return localized_compare( left->spell_class->name(), right->spell_class->name() );
        }
        return false;
    } );

    // Actual line that the skill takes up.
    int display_line = 0;
    trait_id current_spell_class = trait_id::NULL_ID();
    std::vector<std::pair<spell_id, int>> spell_list;
    for( const spell_id &spell : sorted_spells ) {
        if( current_spell_class != spell->spell_class ) {
            current_spell_class = spell->spell_class;
            display_line++;
        }
        spell_list.emplace_back( spell, display_line );
        display_line++;
    }

    const int num_spells = spell_list.size();
    int cur_offset = 0;
    int cur_pos = 0;
    spell_id current_spell = spell_list[cur_pos].first;
    int selected = 0;

    input_context ctxt( "NEW_CHAR_SKILLS" );
    ctxt.register_cardinal();
    ctxt.register_action( "SCROLL_DOWN" );
    ctxt.register_action( "SCROLL_UP" );
    ctxt.register_action( "PREV_TAB" );
    ctxt.register_action( "NEXT_TAB" );
    ctxt.register_action( "RANDOMIZE" );
    ctxt.register_action( "HELP_KEYBINDINGS" );
    ctxt.register_action( "QUIT" );

    const int remaining_points_length = utf8_width( points.to_string(), true );

#if defined(TILES)
    const auto native = chargen_view( ui, u, "NEW_CHAR_SKILLS", init_windows );
    const auto publish_native = [&]() {
        const auto frame = chargen_frame{ .u = u, .points = points, .step = chargen_step::magic, .category = "NEW_CHAR_SKILLS" };
        const auto spell_level = [&]( const spell_id & sp ) { return u.magic->knows_spell( sp ) ? u.magic->get_spell( sp ).get_level() : -1; };
        native->publish( [&]( JsonOut & jsout ) {
            write_chargen_frame( jsout, frame );
            jsout.member( "panes" );
            jsout.start_array();
            jsout.start_object();
            jsout.member( "title", _( "Spells" ) );
            jsout.member( "icon", "sparkles" );
            jsout.member( "cursor", cur_pos );
            jsout.member( "confirm", "" );
            jsout.member( "rows" );
            jsout.start_array();
            auto spell_class = trait_id::NULL_ID();
            for( const auto &[i, entry] : spell_list | std::views::enumerate ) {
                const auto &sp = entry.first;
                if( spell_class != sp->spell_class ) {
                    spell_class = sp->spell_class;
                    gs::write_row( jsout, { .text = { .text = spell_class == trait_id( "NONE" ) ? _( "Classless" ) : spell_class->name(), .color = c_yellow },
                                            .heading = true
                                          } );
                }
                const auto level = spell_level( sp );
                gs::write_row( jsout, { .text = { .text = sp->name.translated(), .color = level >= 0 ? COL_SKILL_USED : c_light_gray },
                .cells = { { .text = level >= 0 ? std::to_string( level ) : "", .color = COL_SKILL_USED } },
                .i = static_cast<int>( i )
                                      } );
            }
            jsout.end_array();
            jsout.end_object();
            jsout.end_array();

            const auto level = spell_level( current_spell );
            const auto cost = level >= 0 ? current_spell->increase_points : current_spell->starting_points;
            jsout.member( "aside" );
            jsout.start_object();
            jsout.member( "width", 620 );
            jsout.member( "title" );
            gs::write_span( jsout, { .text = current_spell->name.translated(), .color = c_white } );
            jsout.member( "body" );
            gs::write_span( jsout, { .text = colorize( string_format( vgettext( "Upgrading %s by 1 level costs %d point",
                                             "Upgrading %s by 1 level costs %d points", cost ), current_spell->name, cost ),
                                             points.trait_points_left() >= cost ? COL_SKILL_USED : c_light_red ) + "\n\n" +
                                             current_spell->description.translated(), .color = c_light_gray
                                   } );
            jsout.member( "buttons" );
            jsout.start_array();
            gs::write_button( jsout, { .act = "LEFT", .text = _( "Lower" ), .icon = "minus", .category = frame.category, .enabled = level >= 0 } );
            gs::write_button( jsout, { .act = "RIGHT", .text = _( "Raise" ), .icon = "plus", .category = frame.category,
                                       .enabled = level < current_spell->max_starting_level
                                     } );
            write_next_button( jsout, frame );
            jsout.end_array();
            jsout.end_object();

            jsout.member( "hints" );
            jsout.start_array();
            gs::write_fixed_hint( jsout, "↑↓", _( "Choose" ) );
            gs::write_hint( jsout, "LEFT", frame.category, _( "Lower" ) );
            gs::write_hint( jsout, "RIGHT", frame.category, _( "Raise" ) );
            write_nav_hints( jsout, frame.category );
            jsout.end_array();
        } );
    };
#endif

    ui.on_redraw( [&]( const ui_adaptor & ) {
#if defined(TILES)
        if( native ) {
            publish_native();
            return;
        }
#endif
        draw_character_tabs( w, _( "MAGIC" ), u.prof );

        draw_points( w, points );
        // Clear the bottom of the screen.
        werase( w_description );
        mvwprintz( w, point( remaining_points_length + 9, 3 ), c_light_gray,
                   std::string( getmaxx( w ) - remaining_points_length - 10, ' ' ) );

        // Write the hint as to upgrade costs
        const bool knows = u.magic->knows_spell( current_spell );
        const int cost = knows ? current_spell->increase_points : current_spell->starting_points;
        const int level = knows ? u.magic->get_spell( current_spell ).get_level() : 0;
        // We have two different strings to pluralize, so we have to use two
        // translation calls.
        const nc_color color = points.trait_points_left() >= cost ? COL_SKILL_USED : c_light_red;
        mvwprintz( w, point( remaining_points_length + 9, 3 ), color,
                   //~ Second string is e.g. "1 level" or "2 levels"
                   vgettext( "Upgrading %s by 1 level costs %d point",
                             "Upgrading %s by 1 level costs %d points", cost ),
                   current_spell->name, cost );

        std::string rec_disp = current_spell->description.translated();

        const auto vFolded = foldstring( rec_disp, getmaxx( w_description ) );
        int iLines = vFolded.size();

        if( selected < 0 ) {
            selected = 0;
        } else if( iLines < iContentHeight ) {
            selected = 0;
        } else if( selected >= iLines - iContentHeight ) {
            selected = iLines - iContentHeight;
        }

        fold_and_print_from( w_description, point_zero, getmaxx( w_description ),
                             selected, COL_SKILL_USED, rec_disp );

        draw_scrollbar( w, selected, iContentHeight, iLines,
                        point( getmaxx( w ) - 1, 5 ), BORDER_COLOR, true );

        // spell_list[cur_pos].second - 1 so the first skill is considered the first item on scrollbar.
        // display_line - 1 and iContentHeight - 1 compensates for the offset by the prior.
        // same application in the draw_scrolbar function later.
        calcStartPos( cur_offset, spell_list[cur_pos].second - 1, iContentHeight - 1, display_line - 1 );
        current_spell_class = trait_id::NULL_ID();
        for( int i = 0; i < num_spells && spell_list[i].second - cur_offset - 1 < iContentHeight; ++i ) {
            const int y = 5 + spell_list[i].second - cur_offset;
            // Necessary because cur_offset doesn't indicate the first object to read. A bit hacky.
            if( y < 5 ) {
                continue;
            }
            const trait_id &spell_class = spell_list[i].first->spell_class;
            const spell_id &thisspell = spell_list[i].first;
            if( current_spell_class != spell_class && y - 1 >= 5 ) {
                // Clear the line
                mvwprintz( w, point( 2, y - 1 ), c_light_gray, std::string( getmaxx( w ) - 3, ' ' ) );
                if( spell_class == trait_id( "NONE" ) ) {
                    mvwprintz( w, point( 2, y - 1 ), c_yellow, _( "Classless" ) );
                } else {
                    mvwprintz( w, point( 2, y - 1 ), c_yellow, spell_class->name() );
                }
                current_spell_class = spell_class;
            }
            if( y < iContentHeight + 5 ) {
                // Clear the line. 2 for x-coord because category names will be scrolled over.
                mvwprintz( w, point( 2, y ), c_light_gray, std::string( getmaxx( w ) - 3, ' ' ) );
                if( !u.magic->knows_spell( thisspell ) ) {
                    mvwprintz( w, point( 4, y ),
                               ( i == cur_pos ? h_light_gray : c_light_gray ), thisspell->name.translated() );
                } else {
                    mvwprintz( w, point( 4, y ),
                               ( i == cur_pos ? hilite( COL_SKILL_USED ) : COL_SKILL_USED ),
                               thisspell->name.translated() );
                    mvwprintz( w, point( TERMX / 2 - 10, y ),
                               ( i == cur_pos ? hilite( COL_SKILL_USED ) : COL_SKILL_USED ),
                               " (%d)", u.magic->get_spell( thisspell ).get_level() );
                }
            }
        }

        draw_scrollbar( w, spell_list[cur_pos].second - 1, iContentHeight - 1, display_line - 1, point( 0,
                        5 ) );

        wnoutrefresh( w );
        wnoutrefresh( w_description );
    } );

    do {
        ui_manager::redraw();
        const std::string action = ctxt.handle_input();
#if defined(TILES)
        if( const auto pick = native ? cata::godot_bridge::take_pick( &u ) : std::nullopt ) {
            if( const auto direction = chargen_tab_click( *pick, chargen_step::magic, u.prof ) ) {
                return *direction;
            }
            if( *pick < num_spells ) {
                cur_pos = *pick;
                current_spell = spell_list[cur_pos].first;
            }
        }
#endif
        if( action == "DOWN" ) {
            cur_pos = modulo( cur_pos + 1, num_spells );
            current_spell = spell_list[cur_pos].first;
        } else if( action == "UP" ) {
            cur_pos = modulo( cur_pos - 1, num_spells );
            current_spell = spell_list[cur_pos].first;
        } else if( action == "RANDOMIZE" ) {
            cur_pos = modulo( rng( 0, num_spells - 1 ), num_spells );
        } else if( action == "LEFT" ) {
            const spell_id &thisspell = spell_list[cur_pos].first;
            bool knows = u.magic->knows_spell( thisspell );
            const int level = knows ? u.magic->get_spell( thisspell ).get_level() : -1;
            if( knows ) {
                if( level - 1 < 0 ) {
                    u.magic->forget_spell( thisspell );
                    points.trait_points += thisspell->starting_points;
                } else {
                    u.magic->get_spell( thisspell ).set_level( level - 1 );
                    points.trait_points += thisspell->increase_points;
                }
            }
        } else if( action == "RIGHT" ) {
            const spell_id &thisspell = spell_list[cur_pos].first;
            if( !u.magic->can_learn_spell( u, thisspell ) ) {
                popup( _( "You cannot learn this spell!" ) );
            } else if( g->scen->is_forbidden_spell( thisspell ) ) {
                popup( _( "This scenario prevents you from taking this spell" ) );
            } else if( u.prof->is_forbidden_spell( thisspell ) ) {
                popup( _( "This profession prevents you from taking this spell" ) );
            } else {
                const bool knows = u.magic->knows_spell( thisspell );
                const int level = knows ? u.magic->get_spell( thisspell ).get_level() : -1;
                if( level < thisspell->max_starting_level ) {
                    const int cost = knows ? thisspell->increase_points : thisspell->starting_points;
                    points.trait_points -= cost;
                    if( !knows ) {
                        u.magic->learn_spell( thisspell, u, true );
                    } else {
                        u.magic->get_spell( thisspell ).set_level( level + 1 );
                    }
                }
            }
        } else if( action == "SCROLL_DOWN" ) {
            selected++;
        } else if( action == "SCROLL_UP" ) {
            selected--;
        } else if( action == "PREV_TAB" ) {
            return tab_direction::BACKWARD;
        } else if( action == "NEXT_TAB" ) {
            return tab_direction::FORWARD;
        } else if( action == "QUIT" && query_yn( _( "Return to main menu?" ) ) ) {
            return tab_direction::QUIT;
        }
    } while( true );
}

struct {
    bool sort_by_points = true;
    bool male = false;
    bool cities_enabled = false;
    /** @related player */
    bool operator()( const scenario *a, const scenario *b ) {
        if( cities_enabled ) {
            // The generic ("Unemployed") profession should be listed first.
            const scenario *gen = scenario::generic();
            if( b == gen ) {
                return false;
            } else if( a == gen ) {
                return true;
            }
        }

        if( !cities_enabled && a->has_flag( "CITY_START" ) != b->has_flag( "CITY_START" ) ) {
            return a->has_flag( "CITY_START" ) < b->has_flag( "CITY_START" );
        } else if( sort_by_points ) {
            return a->point_cost() < b->point_cost();
        } else {
            return localized_compare( a->gender_appropriate_name( male ),
                                      b->gender_appropriate_name( male ) );
        }
    }
} scenario_sorter;

tab_direction set_scenario( avatar &u, points_left &points,
                            const tab_direction direction )
{
    int cur_id = 0;
    tab_direction retval = tab_direction::NONE;
    int iContentHeight = 0;
    int iStartPos = 0;

    ui_adaptor ui;
    catacurses::window w;
    catacurses::window w_description;
    catacurses::window w_sorting;
    catacurses::window w_profession;
    catacurses::window w_location;
    catacurses::window w_vehicle;
    catacurses::window w_flags;
    const auto init_windows = [&]( ui_adaptor & ui ) {
        iContentHeight = TERMY - 10;
        w = catacurses::newwin( TERMY, TERMX, point_zero );
        w_description = catacurses::newwin( 4, TERMX - 2, point( 1, TERMY - 5 ) );
        w_sorting = catacurses::newwin( 2, ( TERMX / 2 ) - 1, point( TERMX / 2, 5 ) );
        w_profession = catacurses::newwin( 4, ( TERMX / 2 ) - 1, point( TERMX / 2, 7 ) );
        w_location = catacurses::newwin( 3, ( TERMX / 2 ) - 1, point( TERMX / 2, 11 ) );
        w_vehicle = catacurses::newwin( 3, ( TERMX / 2 ) - 1, point( TERMX / 2, 14 ) );
        // 11 = 2 + 4 + 3 + 3, so we use rest of space for flags
        w_flags = catacurses::newwin( iContentHeight - 14, ( TERMX / 2 ) - 1,
                                      point( TERMX / 2, 17 ) );
        ui.position_from_window( w );
    };
    init_windows( ui );
    ui.on_screen_resize( init_windows );

    input_context ctxt( "NEW_CHAR_SCENARIOS" );
    ctxt.register_cardinal();
    ctxt.register_action( "CONFIRM" );
    ctxt.register_action( "PREV_TAB" );
    ctxt.register_action( "NEXT_TAB" );
    ctxt.register_action( "SORT" );
    ctxt.register_action( "HELP_KEYBINDINGS" );
    ctxt.register_action( "RANDOMIZE" );
    ctxt.register_action( "FILTER" );
    ctxt.register_action( "QUIT" );

    bool recalc_scens = true;
    int scens_length = 0;
    std::string filterstring;
    std::vector<const scenario *> sorted_scens;

    if( direction == tab_direction::BACKWARD ) {
        points.skill_points += u.prof->point_cost();
    }

#if defined(TILES)
    // What the old screen shows beside the list: professions, location, vehicle and flags.
    const auto scenario_details = [&]( const scenario & scen ) -> std::string {
        const auto heading = []( const std::string & text ) { return colorize( text, COL_HEADER ) + "\n"; };
        auto psorter = profession_sorter;
        psorter.sort_by_points = true;
        const auto permitted = scen.permitted_professions();
        const auto default_prof = *std::ranges::min_element( permitted, psorter );
        const auto prof_points = default_prof->point_cost();
        auto text = heading( _( "Professions:" ) ) + scen.prof_count_str() + _( ", default:\n" ) +
                    default_prof->gender_appropriate_name( u.male );
        if( prof_points != 0 )
        {
            text += colorize( string_format( " (%+d)", -prof_points ), prof_points > 0 ? c_red : c_green );
        }
        text += "\n\n" + heading( _( "Scenario Location:" ) ) +
                string_format( _( "%s (%d locations, %d variants)" ), scen.start_name(), scen.start_location_count(),
                               scen.start_location_targets_count() ) + "\n\n";
        text += heading( _( "Scenario Vehicle:" ) ) + ( scen.vehicle() ? scen.vehicle()->name : "" ) + "\n\n";
        text += heading( _( "Scenario Flags:" ) );
        struct flag_text {
            std::string flag;
            std::string text;
        };
        const auto seasons = std::array{
            flag_text{ .flag = "SPR_START", .text = _( "Spring start" ) },
            flag_text{ .flag = "SUM_START", .text = _( "Summer start" ) },
            flag_text{ .flag = "AUT_START", .text = _( "Autumn start" ) },
            flag_text{ .flag = "WIN_START", .text = _( "Winter start" ) },
            flag_text{ .flag = "SUM_ADV_START", .text = _( "Next summer start" ) },
        };
        if( const auto season = std::ranges::find_if( seasons, [&]( const flag_text & f ) { return scen.has_flag( f.flag ); } );
        season != seasons.end() )
        {
            text += season->text + "\n";
        }
        const auto others = std::array{
            flag_text{ .flag = "INFECTED", .text = _( "Infected player" ) },
            flag_text{ .flag = "BAD_DAY", .text = _( "Drunk and sick player" ) },
            flag_text{ .flag = "FIRE_START", .text = _( "Fire nearby" ) },
            flag_text{ .flag = "SUR_START", .text = _( "Zombies nearby" ) },
            flag_text{ .flag = "HELI_CRASH", .text = _( "Various limb wounds" ) },
        };
        for( const auto &f : others | std::views::filter( [&]( const flag_text & f ) { return scen.has_flag( f.flag ); } ) )
        {
            text += f.text + "\n";
        }
        if( get_option<std::string>( "STARTING_NPC" ) == "scenario" && scen.has_flag( "LONE_START" ) )
        {
            text += std::string( _( "No starting NPC" ) ) + "\n";
        }
        if( scen.has_flag( "BORDERED" ) )
        {
            text += std::string( _( "Starting location is bordered by an immense wall" ) ) + "\n";
        }
        return text;
    };
    const auto unavailable = [&]( const scenario & scen ) { return scen.has_flag( "CITY_START" ) && !scenario_sorter.cities_enabled; };
    const auto native = chargen_view( ui, u, "NEW_CHAR_SCENARIOS", init_windows );
    const auto publish_native = [&]() {
        const auto valid = cur_id >= 0 && static_cast<size_t>( cur_id ) < sorted_scens.size();
        const auto frame = chargen_frame{ .u = u, .points = points, .step = chargen_step::scenario, .category = "NEW_CHAR_SCENARIOS",
                                          .net_cost = valid ? sorted_scens[cur_id]->point_cost() - g->scen->point_cost() : 0 };
        native->publish( [&]( JsonOut & jsout ) {
            write_chargen_frame( jsout, frame );
            write_choice_toolbar( jsout, { .category = frame.category, .filter = filterstring,
                                           .placeholder = _( "Search by scenario name." ), .by_points = scenario_sorter.sort_by_points
                                         } );
            jsout.member( "panes" );
            jsout.start_array();
            jsout.start_object();
            jsout.member( "title", _( "Scenarios" ) );
            jsout.member( "icon", "map" );
            jsout.member( "count", std::to_string( sorted_scens.size() ) );
            jsout.member( "cursor", cur_id );
            jsout.member( "rows" );
            jsout.start_array();
            for( const auto *scen : sorted_scens ) {
                write_choice_row( jsout, { .name = scen->gender_appropriate_name( u.male ), .cost = scen->point_cost(),
                                           .chosen = scen == g->scen, .unavailable = unavailable( *scen )
                                         } );
            }
            jsout.end_array();
            jsout.end_object();
            jsout.end_array();

            jsout.member( "aside" );
            jsout.start_object();
            jsout.member( "width", 560 );
            if( valid ) {
                const auto &scen = *sorted_scens[cur_id];
                const auto cost = std::abs( scen.point_cost() );
                const auto cost_text = scen.point_cost() < 0 ?
                                       vgettext( "Scenario %1$s earns %2$d point", "Scenario %1$s earns %2$d points", cost ) :
                                       vgettext( "Scenario %1$s costs %2$d point", "Scenario %1$s cost %2$d points", cost );
                const auto can_pick = scen.can_pick( *g->scen, points.skill_points_left() );
                jsout.member( "title" );
                gs::write_span( jsout, { .text = scen.gender_appropriate_name( u.male ), .color = c_white } );
                if( unavailable( scen ) ) {
                    jsout.member( "warn" );
                    gs::write_span( jsout, { .text = _( "This scenario is not available in this world due to city size settings." ), .color = c_red } );
                }
                jsout.member( "body" );
                gs::write_span( jsout, { .text = colorize( string_format( cost_text, scen.gender_appropriate_name( u.male ), cost ),
                                                 can_pick ? c_green : c_light_red ) + "\n\n" + scen.description( u.male ) + "\n\n" +
                                                 scenario_details( scen )
                                       } );
            }
            jsout.member( "buttons" );
            jsout.start_array();
            gs::write_button( jsout, { .act = "CONFIRM", .text = _( "Choose scenario" ), .icon = "check", .category = frame.category,
                                       .enabled = valid && sorted_scens[cur_id] != g->scen && !unavailable( *sorted_scens[cur_id] )
                                     } );
            write_next_button( jsout, frame );
            jsout.end_array();
            jsout.end_object();

            jsout.member( "hints" );
            jsout.start_array();
            gs::write_fixed_hint( jsout, "↑↓", _( "Choose" ) );
            gs::write_hint( jsout, "CONFIRM", frame.category, _( "Pick" ) );
            gs::write_hint( jsout, "RANDOMIZE", frame.category, _( "Random pick" ) );
            write_nav_hints( jsout, frame.category );
            jsout.end_array();
        } );
    };
#endif

    ui.on_redraw( [&]( const ui_adaptor & ) {
#if defined(TILES)
        if( native ) {
            publish_native();
            return;
        }
#endif
        werase( w );
        draw_character_tabs( w, _( "SCENARIO" ), u.prof );

        // Draw filter indicator
        for( int i = 1; i < getmaxx( w ) - 1; i++ ) {
            mvwputch( w, point( i, getmaxy( w ) - 1 ), BORDER_COLOR, LINE_OXOX );
        }
        const auto filter_indicator = filterstring.empty() ? _( "no filter" )
                                      : filterstring;
        mvwprintz( w, point( 2, getmaxy( w ) - 1 ), c_light_gray, "<%s>", filter_indicator );

        const bool cur_id_is_valid = cur_id >= 0 && static_cast<size_t>( cur_id ) < sorted_scens.size();

        werase( w_description );
        if( cur_id_is_valid ) {
            int netPointCost = sorted_scens[cur_id]->point_cost() - g->scen->point_cost();
            bool can_pick = sorted_scens[cur_id]->can_pick( *g->scen, points.skill_points_left() );
            const std::string clear_line( getmaxx( w_description ), ' ' );

            // Clear the bottom of the screen and header.
            mvwprintz( w, point( 1, 3 ), c_light_gray, clear_line );

            int pointsForScen = sorted_scens[cur_id]->point_cost();
            bool negativeScen = pointsForScen < 0;
            if( negativeScen ) {
                pointsForScen *= -1;
            }

            // Draw header.
            draw_points( w, points, netPointCost );

            std::string scen_msg_temp;
            if( negativeScen ) {
                //~ 1s - scenario name, 2d - current character points.
                scen_msg_temp = vgettext( "Scenario %1$s earns %2$d point",
                                          "Scenario %1$s earns %2$d points",
                                          pointsForScen );
            } else {
                //~ 1s - scenario name, 2d - current character points.
                scen_msg_temp = vgettext( "Scenario %1$s costs %2$d point",
                                          "Scenario %1$s cost %2$d points",
                                          pointsForScen );
            }

            int pMsg_length = utf8_width( remove_color_tags( points.to_string() ) );
            mvwprintz( w, point( pMsg_length + 9, 3 ), can_pick ? c_green : c_light_red, scen_msg_temp.c_str(),
                       sorted_scens[cur_id]->gender_appropriate_name( u.male ),
                       pointsForScen );

            const std::string scenDesc = sorted_scens[cur_id]->description( u.male );

            if( sorted_scens[cur_id]->has_flag( "CITY_START" ) && !scenario_sorter.cities_enabled ) {
                const std::string scenUnavailable =
                    _( "This scenario is not available in this world due to city size settings." );
                fold_and_print( w_description, point_zero, TERMX - 2, c_red, scenUnavailable );
                // NOLINTNEXTLINE(cata-use-named-point-constants)
                fold_and_print( w_description, point( 0, 1 ), TERMX - 2, c_green, scenDesc );
            } else {
                fold_and_print( w_description, point_zero, TERMX - 2, c_green, scenDesc );
            }
        }

        //Draw options
        calcStartPos( iStartPos, cur_id, iContentHeight, scens_length );
        const int end_pos = iStartPos + ( ( iContentHeight > scens_length ) ?
                                          scens_length : iContentHeight );
        int i;
        for( i = iStartPos; i < end_pos; i++ ) {
            mvwprintz( w, point( 2, 5 + i - iStartPos ), c_light_gray,
                       "                                             " );
            nc_color col;
            if( g->scen != sorted_scens[i] ) {
                if( cur_id_is_valid && sorted_scens[i] == sorted_scens[cur_id] &&
                    sorted_scens[i]->has_flag( "CITY_START" ) && !scenario_sorter.cities_enabled ) {
                    col = h_dark_gray;
                } else if( cur_id_is_valid && sorted_scens[i] != sorted_scens[cur_id] &&
                           sorted_scens[i]->has_flag( "CITY_START" ) && !scenario_sorter.cities_enabled ) {
                    col = c_dark_gray;
                } else {
                    col = ( cur_id_is_valid && sorted_scens[i] == sorted_scens[cur_id] ? h_light_gray : c_light_gray );
                }
            } else {
                col = ( cur_id_is_valid &&
                        sorted_scens[i] == sorted_scens[cur_id] ? hilite( COL_SKILL_USED ) : COL_SKILL_USED );
            }
            mvwprintz( w, point( 2, 5 + i - iStartPos ), col,
                       sorted_scens[i]->gender_appropriate_name( u.male ) );

        }
        //Clear rest of space in case stuff got filtered out
        for( ; i < iStartPos + iContentHeight; ++i ) {
            mvwprintz( w, point( 2, 5 + i - iStartPos ), c_light_gray,
                       "                                             " ); // Clear the line
        }

        werase( w_sorting );
        werase( w_profession );
        werase( w_location );
        werase( w_vehicle );
        werase( w_flags );

        if( cur_id_is_valid ) {
            draw_sorting_indicator( w_sorting, ctxt, scenario_sorter );

            mvwprintz( w_profession, point_zero, COL_HEADER, _( "Professions:" ) );
            wprintz( w_profession, c_light_gray,
                     string_format( _( "\n%s" ), sorted_scens[cur_id]->prof_count_str() ) );
            wprintz( w_profession, c_light_gray, _( ", default:\n" ) );

            auto psorter = profession_sorter;
            psorter.sort_by_points = true;
            const auto permitted = sorted_scens[cur_id]->permitted_professions();
            const auto default_prof = *std::min_element( permitted.begin(), permitted.end(), psorter );
            const int prof_points = default_prof->point_cost();
            wprintz( w_profession, c_light_gray,
                     default_prof->gender_appropriate_name( u.male ) );
            if( prof_points > 0 ) {
                wprintz( w_profession, c_red, " (-%d)", prof_points );
            } else if( prof_points < 0 ) {
                wprintz( w_profession, c_green, " (+%d)", -prof_points );
            }

            mvwprintz( w_location, point_zero, COL_HEADER, _( "Scenario Location:" ) );
            wprintz( w_location, c_light_gray, ( "\n" ) );
            wprintz( w_location, c_light_gray,
                     string_format( _( "%s (%d locations, %d variants)" ),
                                    sorted_scens[cur_id]->start_name(),
                                    sorted_scens[cur_id]->start_location_count(),
                                    sorted_scens[cur_id]->start_location_targets_count() ) );

            mvwprintz( w_vehicle, point_zero, COL_HEADER, _( "Scenario Vehicle:" ) );
            wprintz( w_vehicle, c_light_gray, ( "\n" ) );
            if( sorted_scens[cur_id]->vehicle() ) {
                wprintz( w_vehicle, c_light_gray, sorted_scens[cur_id]->vehicle()->name );
            }

            mvwprintz( w_flags, point_zero, COL_HEADER, _( "Scenario Flags:" ) );
            wprintz( w_flags, c_light_gray, ( "\n" ) );

            if( sorted_scens[cur_id]->has_flag( "SPR_START" ) ) {
                wprintz( w_flags, c_light_gray, _( "Spring start" ) );
                wprintz( w_flags, c_light_gray, ( "\n" ) );
            } else if( sorted_scens[cur_id]->has_flag( "SUM_START" ) ) {
                wprintz( w_flags, c_light_gray, _( "Summer start" ) );
                wprintz( w_flags, c_light_gray, ( "\n" ) );
            } else if( sorted_scens[cur_id]->has_flag( "AUT_START" ) ) {
                wprintz( w_flags, c_light_gray, _( "Autumn start" ) );
                wprintz( w_flags, c_light_gray, ( "\n" ) );
            } else if( sorted_scens[cur_id]->has_flag( "WIN_START" ) ) {
                wprintz( w_flags, c_light_gray, _( "Winter start" ) );
                wprintz( w_flags, c_light_gray, ( "\n" ) );
            } else if( sorted_scens[cur_id]->has_flag( "SUM_ADV_START" ) ) {
                wprintz( w_flags, c_light_gray, _( "Next summer start" ) );
                wprintz( w_flags, c_light_gray, ( "\n" ) );
            }

            if( sorted_scens[cur_id]->has_flag( "INFECTED" ) ) {
                wprintz( w_flags, c_light_gray, _( "Infected player" ) );
                wprintz( w_flags, c_light_gray, ( "\n" ) );
            }
            if( sorted_scens[cur_id]->has_flag( "BAD_DAY" ) ) {
                wprintz( w_flags, c_light_gray, _( "Drunk and sick player" ) );
                wprintz( w_flags, c_light_gray, ( "\n" ) );
            }
            if( sorted_scens[cur_id]->has_flag( "FIRE_START" ) ) {
                wprintz( w_flags, c_light_gray, _( "Fire nearby" ) );
                wprintz( w_flags, c_light_gray, ( "\n" ) );
            }
            if( sorted_scens[cur_id]->has_flag( "SUR_START" ) ) {
                wprintz( w_flags, c_light_gray, _( "Zombies nearby" ) );
                wprintz( w_flags, c_light_gray, ( "\n" ) );
            }
            if( sorted_scens[cur_id]->has_flag( "HELI_CRASH" ) ) {
                wprintz( w_flags, c_light_gray, _( "Various limb wounds" ) );
                wprintz( w_flags, c_light_gray, ( "\n" ) );
            }
            if( get_option<std::string>( "STARTING_NPC" ) == "scenario" &&
                sorted_scens[cur_id]->has_flag( "LONE_START" ) ) {
                wprintz( w_flags, c_light_gray, _( "No starting NPC" ) );
                wprintz( w_flags, c_light_gray, ( "\n" ) );
            }
            if( sorted_scens[cur_id]->has_flag( "BORDERED" ) ) {
                wprintz( w_flags, c_light_gray, _( "Starting location is bordered by an immense wall" ) );
                wprintz( w_flags, c_light_gray, ( "\n" ) );
            }
        }

        draw_scrollbar( w, cur_id, iContentHeight, scens_length, point( 0, 5 ) );
        wnoutrefresh( w );
        wnoutrefresh( w_description );
        wnoutrefresh( w_sorting );
        wnoutrefresh( w_profession );
        wnoutrefresh( w_location );
        wnoutrefresh( w_vehicle );
        wnoutrefresh( w_flags );
    } );

    do {
        if( recalc_scens ) {
            sorted_scens.clear();
            auto &wopts = world_generator->active_world->info->WORLD_OPTIONS;
            for( const auto &scen : scenario::get_all() ) {
                if( scen.scen_is_blacklisted() ) {
                    continue;
                }
                if( !lcmatch( scen.gender_appropriate_name( u.male ), filterstring ) ) {
                    continue;
                }
                sorted_scens.push_back( &scen );
            }
            scens_length = sorted_scens.size();
            if( scens_length == 0 ) {
                popup( _( "Nothing found." ) ); // another case of black box in tiles
                filterstring.clear();
                continue;
            }

            // Sort scenarios by points.
            // scenario_display_sort() keeps "Evacuee" at the top.
            scenario_sorter.male = u.male;
            scenario_sorter.cities_enabled = wopts["CITY_SIZE"].getValue() != "0";
            std::stable_sort( sorted_scens.begin(), sorted_scens.end(), scenario_sorter );

            // Reset if the current scenario is no longer selectable, such as when a mod whitelist hides it.
            if( !scenario_is_selectable( *g->scen, scenario_sorter.cities_enabled ) ) {
                const auto *fallback_scenario = first_selectable_scenario( sorted_scens,
                                                scenario_sorter.cities_enabled );
                reset_scenario( u, fallback_scenario );
                points.init_from_options();
                points.skill_points -= g->scen->point_cost();
            }

            // Select the current scenario, if possible.
            for( int i = 0; i < scens_length; ++i ) {
                if( sorted_scens[i]->ident() == g->scen->ident() ) {
                    cur_id = i;
                    break;
                }
            }
            if( cur_id > scens_length - 1 ) {
                cur_id = 0;
            }

            recalc_scens = false;
        }

        ui_manager::redraw();
        const std::string action = ctxt.handle_input();
#if defined(TILES)
        if( const auto pick = native ? cata::godot_bridge::take_pick( &u ) : std::nullopt ) {
            if( const auto direction = chargen_tab_click( *pick, chargen_step::scenario, u.prof ) ) {
                retval = *direction;
                continue;
            }
            if( *pick < scens_length ) {
                cur_id = *pick;
            }
        }
#endif
        if( action == "DOWN" ) {
            cur_id++;
            if( cur_id > scens_length - 1 ) {
                cur_id = 0;
            }
        } else if( action == "UP" ) {
            cur_id--;
            if( cur_id < 0 ) {
                cur_id = scens_length - 1;
            }
        } else if( action == "RANDOMIZE" ) {
            cur_id = rng( 0, scens_length - 1 );
        } else if( action == "CONFIRM" ) {
            if( sorted_scens[cur_id]->has_flag( "CITY_START" ) && !scenario_sorter.cities_enabled ) {
                continue;
            }
            reset_scenario( u, sorted_scens[cur_id] );
            points.init_from_options();
            points.skill_points -= sorted_scens[cur_id]->point_cost();
        } else if( action == "PREV_TAB" ) {
            retval = tab_direction::BACKWARD;
        } else if( action == "NEXT_TAB" ) {
            retval = tab_direction::FORWARD;
        } else if( action == "SORT" ) {
            scenario_sorter.sort_by_points = !scenario_sorter.sort_by_points;
            recalc_scens = true;
        } else if( action == "FILTER" ) {
            string_input_popup()
            .title( _( "Search:" ) )
            .width( 60 )
            .description( _( "Search by scenario name." ) )
            .edit( filterstring );
            recalc_scens = true;
        } else if( action == "QUIT" && query_yn( _( "Return to main menu?" ) ) ) {
            retval = tab_direction::QUIT;
        }
    } while( retval == tab_direction::NONE );

    return retval;
}

namespace char_creation
{
enum description_selector {
    NAME,
    HEIGHT,
    AGE
};

static void draw_height( const catacurses::window &w_height, const avatar &you,
                         const bool highlight )
{
    werase( w_height );
    mvwprintz( w_height, point_zero, highlight ? h_light_gray : c_light_gray, _( "Height:" ) );
    unsigned height_pos = 1 + utf8_width( _( "Height:" ) );
    mvwprintz( w_height, point( height_pos, 0 ), c_white, string_format( "%d cm",
               you.base_height() ) );
    wnoutrefresh( w_height );
}

static void draw_age( const catacurses::window &w_age, const avatar &you, const bool highlight )
{
    werase( w_age );
    mvwprintz( w_age, point_zero, highlight ? h_light_gray : c_light_gray, _( "Age:" ) );
    unsigned age_pos = 1 + utf8_width( _( "Age:" ) );
    mvwprintz( w_age, point( age_pos, 0 ), c_white, string_format( "%d", you.base_age() ) );
    wnoutrefresh( w_age );
}
} // namespace char_creation

tab_direction set_description( avatar &you, const bool allow_reroll,
                               points_left &points )
{
    static constexpr int RANDOM_START_LOC_ENTRY = INT_MIN;
    const std::string RANDOM_START_LOC_TEXT_TEMPLATE =
        _( "<color_red>* Random location *</color> (<color_white>%d</color> variants)" );
    const std::string START_LOC_TEXT_TEMPLATE = _( "%s (<color_white>%d</color> variants)" );

    ui_adaptor ui;
    catacurses::window w;
    catacurses::window w_name;
    catacurses::window w_gender;
    catacurses::window w_location;
    catacurses::window w_stats;
    catacurses::window w_traits;
    catacurses::window w_bionics;
    catacurses::window w_misc;
    catacurses::window w_gear;
    catacurses::window w_scenario;
    catacurses::window w_profession;
    catacurses::window w_skills;
    catacurses::window w_guide;
    catacurses::window w_height;
    catacurses::window w_age;

#if defined(TILES)
    character_preview_window character_preview;
    character_preview.init( &you );
    const bool use_character_preview = get_option<bool>( "USE_CHARACTER_PREVIEW" ) &&
                                       get_option<bool>( "USE_TILES" );
#endif

    const auto init_windows = [&]( ui_adaptor & ui ) {
        // Row 1
        w = catacurses::newwin( TERMY, TERMX, point_zero );
        w_name = catacurses::newwin( 3, 42, point( 2, 5 ) );
        w_gender = catacurses::newwin( 2, 33, point( 46, 5 ) );
        w_height = catacurses::newwin( 1, 20, point( 80, 5 ) );
        w_location = catacurses::newwin( 2, 60, point( 100, 5 ) );
        w_scenario = catacurses::newwin( 1, std::max( 1, TERMX - 161 ), point( 160, 5 ) );
        w_profession = catacurses::newwin( 1, std::max( 1, TERMX - 161 ), point( 160, 6 ) );

        // Row 2
        w_age = catacurses::newwin( 1, 12, point( 80, 6 ) );

        // Big Row
        w_stats = catacurses::newwin( 6, 20, point( 2, 9 ) );
        w_skills = catacurses::newwin( std::max( 1, TERMY - 17 ), 25, point( 2, 16 ) );
        w_traits = catacurses::newwin( std::max( 1, TERMY - 10 ), 30, point( 28, 9 ) );
        w_bionics = catacurses::newwin( std::max( 1, TERMY - 10 ), 30, point( 59, 9 ) );
        w_misc = catacurses::newwin( std::max( 1, TERMY - 10 ), 30, point( 90, 9 ) );
        w_gear = catacurses::newwin( std::max( 1, TERMY - 10 ), std::max( 1, TERMX - 122 ), point( 121,
                                     9 ) );

        // Very bottom Row
        w_guide = catacurses::newwin( 6, std::max( 1, TERMX - 3 ), point( 2, TERMY - 7 ) );

#if defined(TILES)
        const int int_page_width = 38;

        if( use_character_preview && cata::godot_bridge::native_screens() ) {
            prepare_native_preview( character_preview );
        } else if( use_character_preview ) {
            constexpr int preview_nlines_min = 7;
            constexpr int preview_ncols_min = 10;
            const int preview_nlines = std::max( ( TERMY - 9 ) / 3, preview_nlines_min );
            const int preview_ncols = std::max( ( TERMX - int_page_width * 3 - 4 ) / 3 - 5, preview_ncols_min );
            constexpr auto orientation = character_preview_window::Orientation{
                character_preview_window::TOP_RIGHT,
                character_preview_window::Margin{0, 2, 10, 0}
            };
            character_preview.prepare(
                preview_nlines, preview_ncols,
                &orientation, int_page_width * 3 + 5
            );
        }
#endif

        ui.position_from_window( w );
    };
    init_windows( ui );
    ui.on_screen_resize( init_windows );

    const unsigned namebar_pos = 1 + utf8_width( _( "Name:" ) );
    unsigned male_pos = 1 + utf8_width( _( "Gender:" ) );
    unsigned female_pos = 2 + male_pos + utf8_width( _( "Male" ) );

    input_context ctxt( "NEW_CHAR_DESCRIPTION" );
    ctxt.register_cardinal();
    ctxt.register_action( "SAVE_TEMPLATE" );
    ctxt.register_action( "RANDOMIZE_CHAR_DESCRIPTION" );
    ctxt.register_action( "CHANGE_GENDER" );
    ctxt.register_action( "PREV_TAB" );
    ctxt.register_action( "NEXT_TAB" );
    ctxt.register_action( "HELP_KEYBINDINGS" );
    ctxt.register_action( "CHOOSE_LOCATION" );
    ctxt.register_action( "REROLL_CHARACTER" );
    ctxt.register_action( "REROLL_CHARACTER_WITH_SCENARIO" );
    ctxt.register_action( "CONFIRM" );
    ctxt.register_action( "QUIT" );
#if defined(TILES)
    ctxt.register_action( "zoom_in" );
    ctxt.register_action( "zoom_out" );
    ctxt.register_action( "TOGGLE_CHARACTER_PREVIEW_CLOTHES" );
#endif

    uilist select_location;
    select_location.text = _( "Select a starting location." );
    int offset = 1;
    const std::string random_start_location_text = string_format( RANDOM_START_LOC_TEXT_TEMPLATE,
            g->scen->start_location_targets_count() );
    uilist_entry entry_random_start_location( RANDOM_START_LOC_ENTRY, true, -1,
            random_start_location_text );
    select_location.entries.emplace_back( entry_random_start_location );
    for( const auto &loc : start_locations::get_all() ) {
        if( g->scen->allowed_start( loc.id ) ) {
            uilist_entry entry( loc.id.id().to_i(), true, -1,
                                string_format( START_LOC_TEXT_TEMPLATE, loc.name(), loc.targets_count() ) );

            select_location.entries.emplace_back( entry );

            if( !you.random_start_location &&
                loc.id.id() == you.start_location.id() ) {
                select_location.selected = offset;
            }
            offset++;
        }
    }
    if( you.random_start_location ) {
        select_location.selected = 0;
    }
    select_location.setup();
    if( MAP_SHARING::isSharing() ) {
        you.name = MAP_SHARING::getUsername();  // set the current username as default character name
    } else if( !get_option<std::string>( "DEF_CHAR_NAME" ).empty() ) {
        you.name = get_option<std::string>( "DEF_CHAR_NAME" );
    }

    char_creation::description_selector current_selector = char_creation::NAME;

    bool no_name_entered = false;
#if defined(TILES)
    const auto native = chargen_view( ui, you, "NEW_CHAR_DESCRIPTION", init_windows );
    const auto publish_native = [&]() {
        const auto category = std::string( "NEW_CHAR_DESCRIPTION" );
        const auto frame = chargen_frame{ .u = you, .points = points, .step = chargen_step::overview, .category = category };
        const auto none = gs::row{ .text = { .text = _( "None!" ), .color = c_light_red }, .passive = true };
        const auto heading = []( const std::string & text ) { return gs::row{ .text = { .text = text, .color = c_yellow }, .heading = true }; };
        const auto line = []( const std::string & text, const nc_color & color ) {
            return gs::row{ .text = { .text = text, .color = color }, .passive = true };
        };
        const auto field = []( const std::string & label, const gs::span & value ) {
            return gs::row{ .text = { .text = label, .color = c_light_gray }, .note = value, .passive = true };
        };
        // Each list: the rows of one column.
        auto columns = std::array<std::vector<gs::row>, 4> {};

        auto &about = columns[0];
        const auto name_value = no_name_entered ? gs::span{ .text = _( "--- NO NAME ENTERED ---" ), .color = c_yellow } :
                                you.name.empty() ? gs::span{ .text = _( "--- RANDOM NAME ---" ), .color = c_light_gray } :
                                gs::span{ .text = you.name, .color = c_white };
        about.push_back( { .text = { .text = _( "Name" ), .color = c_white }, .i = 0, .note = name_value } );
        about.push_back( { .text = { .text = _( "Height" ), .color = c_white }, .i = 1,
                           .note = { .text = string_format( "%d cm", you.base_height() ), .color = c_white }
                         } );
        about.push_back( { .text = { .text = _( "Age" ), .color = c_white }, .i = 2,
                           .note = { .text = std::to_string( you.base_age() ), .color = c_white }
                         } );
        about.push_back( heading( _( "Details" ) ) );
        about.push_back( field( _( "Gender" ), { .text = you.male ? _( "Male" ) : _( "Female" ), .color = you.male ? c_light_cyan : c_pink } ) );
        about.push_back( field( _( "Starting location" ), {
            .text = you.random_start_location ? remove_color_tags( random_start_location_text ) :
            string_format( remove_color_tags( START_LOC_TEXT_TEMPLATE ), you.start_location.obj().name(), you.start_location.obj().targets_count() ),
            .color = you.random_start_location ? c_red : c_white
        } ) );
        about.push_back( field( _( "Scenario" ), { .text = g->scen->gender_appropriate_name( you.male ), .color = c_white } ) );
        about.push_back( field( _( "Profession" ), { .text = you.prof->gender_appropriate_name( you.male ), .color = c_white } ) );
        about.push_back( heading( _( "Stats" ) ) );
        struct stat_value {
            std::string name;
            int value;
        };
        for( const auto &st : std::array{
        stat_value{ .name = _( "Strength" ), .value = you.str_max }, stat_value{ .name = _( "Dexterity" ), .value = you.dex_max },
            stat_value{ .name = _( "Intelligence" ), .value = you.int_max }, stat_value{ .name = _( "Perception" ), .value = you.per_max } } ) {
            about.push_back( field( st.name, { .text = std::to_string( st.value ), .color = c_white } ) );
        }

        auto &abilities = columns[1];
        abilities.push_back( heading( _( "Traits" ) ) );
        auto current_traits = points.limit == points_left::TRANSFER ? you.get_mutations() :
                              you.get_base_traits();
        std::ranges::sort( current_traits, trait_display_sort );
        for( const auto &t : current_traits ) {
            abilities.push_back( line( t->name(), t->get_display_color() ) );
        }
        if( current_traits.empty() ) {
            abilities.push_back( none );
        }
        abilities.push_back( heading( _( "Bionics" ) ) );
        auto current_bionics = you.prof->CBMs();
        std::ranges::copy( you.get_bionic_collection() | std::views::transform( &bionic::id ),
                           std::back_inserter( current_bionics ) );
        std::ranges::sort( current_bionics, []( const bionic_id & a, const bionic_id & b ) {
            return localized_compare( a->name.translated(), b->name.translated() );
        } );
        for( const auto &b : current_bionics ) {
            abilities.push_back( line( b->name.translated(), c_white ) );
        }
        if( current_bionics.empty() ) {
            abilities.push_back( none );
        }
        abilities.push_back( heading( _( "Spells" ) ) );
        for( const auto &[sp, level] : you.prof->spells() ) {
            abilities.push_back( line( string_format( _( "%s level %d" ), sp->name, level ), c_white ) );
        }
        for( const auto *sp : you.magic->get_spells() ) {
            abilities.push_back( line( string_format( _( "%s level %d" ), sp->id()->name, sp->get_level() ),
                                       c_white ) );
        }
        if( you.prof->spells().empty() && !you.magic->knows_spell() ) {
            abilities.push_back( none );
        }

        auto &skills = columns[2];
        auto skill_category = skill_displayType_id::NULL_ID();
        for( const auto *skill : Skill::get_skills_sorted_by( []( const Skill & a, const Skill & b ) {
        return localized_compare( std::make_pair( a.display_category(), a.name() ),
                                  std::make_pair( b.display_category(), b.name() ) );
        } ) ) {
            auto level = you.get_skill_level( skill->ident(), false );
            if( points.limit != points_left::TRANSFER ) {
                const auto &prof_skills = you.prof->skills();
                const auto bonus = std::ranges::find( prof_skills, skill->ident(),
                                                      &profession::StartingSkill::first );
                level += bonus != prof_skills.end() ? bonus->second : 0;
            }
            if( level <= 0 ) {
                continue;
            }
            if( skill_category != skill->display_category() ) {
                skill_category = skill->display_category();
                skills.push_back( heading( skill_category->display_string() ) );
            }
            skills.push_back( field( skill->name(), { .text = std::to_string( level ), .color = c_white } ) );
        }
        if( skills.empty() ) {
            skills.push_back( none );
        }

        auto &gear = columns[3];
        auto wielded = std::vector<std::string>();
        auto worn = std::vector<std::string>();
        auto carried = std::vector<std::string>();
        for( const auto &it : you.prof->items( you.male, you.get_mutations() ) ) {
            if( it->has_flag( json_flag_no_auto_equip ) ) {
                carried.push_back( it->display_name() );
            } else if( it->has_flag( json_flag_auto_wield ) ) {
                wielded.push_back( it->display_name() );
            } else if( it->is_armor() ) {
                worn.push_back( it->display_name() );
            } else {
                carried.push_back( it->display_name() );
            }
        }
        const auto add_list = [&]( const std::string & title, const std::vector<std::string> &names ) {
            gear.push_back( heading( title ) );
            std::ranges::transform( names, std::back_inserter( gear ), [&]( const std::string & n ) { return line( n, c_white ); } );
            if( names.empty() ) {
                gear.push_back( none );
            }
        };
        add_list( _( "Wielded" ), wielded );
        add_list( _( "Worn" ), worn );
        add_list( _( "Inventory" ), carried );
        auto vehicles = std::vector<std::string>();
        if( g->scen->vehicle() ) {
            vehicles.push_back( g->scen->vehicle()->name );
        }
        if( you.prof->vehicle() ) {
            vehicles.push_back( you.prof->vehicle()->name );
        }
        add_list( _( "Vehicle" ), vehicles );
        add_list( _( "Companions" ), you.prof->npcs() | std::views::filter( &npc_class_id::is_valid )
        | std::views::transform( []( const npc_class_id & id ) { return id->get_name(); } ) |
        std::ranges::to<std::vector>() );
        gear.push_back( heading( _( "Cash" ) ) );
        gear.push_back( line( you.prof->starting_cash() ? format_money( *you.prof->starting_cash() ) :
                              _( "Random!" ), c_white ) );
        add_list( _( "Pets" ), you.prof->pets() | std::views::filter( &mtype_id::is_valid )
        | std::views::transform( []( const mtype_id & id ) { return monster( id ).get_name(); } ) |
        std::ranges::to<std::vector>() );
        add_list( _( "Addictions" ), you.prof->addictions() | std::views::transform( [](
        const addiction & a ) { return addiction_name( a ); } )
        | std::ranges::to<std::vector>() );

        native->publish( [&]( JsonOut & jsout ) {
            write_chargen_frame( jsout, frame );

            jsout.member( "toggles" );
            jsout.start_array();
            gs::write_toggle( jsout, { .act = "CHANGE_GENDER", .text = you.male ? _( "Male" ) : _( "Female" ), .icon = "users",
                                       .category = category, .tip = _( "Change gender" )
                                     }, false );
            gs::write_toggle( jsout, { .act = "CHOOSE_LOCATION", .text = _( "Starting location" ), .icon = "map-pin",
                                       .category = category, .tip = _( "Choose character start location" )
                                     }, false );
            gs::write_toggle( jsout, { .act = "RANDOMIZE_CHAR_DESCRIPTION", .text = _( "Random description" ), .icon = "dices",
                                       .category = category, .enabled = !MAP_SHARING::isSharing(), .tip = _( "Pick random character description" )
                                     }, false );
            gs::write_toggle( jsout, { .act = "SAVE_TEMPLATE", .text = _( "Save template" ), .icon = "save", .category = category },
                              false );
            if( allow_reroll ) {
                write_reroll_toggles( jsout, category, false );
            }
            jsout.end_array();

            struct column_style {
                std::string title;
                std::string icon;
                double stretch;
            };
            const auto styles = std::array{
                column_style{ .title = _( "Character" ), .icon = "user", .stretch = 1.35 },
                column_style{ .title = _( "Traits and bionics" ), .icon = "dna", .stretch = 1.0 },
                column_style{ .title = _( "Skills" ), .icon = "graduation-cap", .stretch = 0.85 },
                column_style{ .title = _( "Starting gear" ), .icon = "backpack", .stretch = 1.2 },
            };
            jsout.member( "active_pane", 0 );
            jsout.member( "panes" );
            jsout.start_array();
            for( const auto &[i, style] : styles | std::views::enumerate ) {
                jsout.start_object();
                jsout.member( "title", style.title );
                jsout.member( "icon", style.icon );
                jsout.member( "stretch", style.stretch );
                jsout.member( "count", "" );
                jsout.member( "cursor", i == 0 ? static_cast<int>( current_selector ) : -1 );
                jsout.member( "rows" );
                jsout.start_array();
                for( const auto &r : columns[i] ) {
                    gs::write_row( jsout, r );
                }
                jsout.end_array();
                jsout.end_object();
            }
            jsout.end_array();

            jsout.member( "aside" );
            jsout.start_object();
            jsout.member( "width", 340 );
            if( use_character_preview ) {
                write_preview( jsout, character_preview, category );
            }
            jsout.member( "title" );
            const auto selected = std::array{ _( "Name" ), _( "Height" ), _( "Age" ) } [current_selector];
            gs::write_span( jsout, { .text = selected, .color = c_white } );
            auto warning = std::string();
            if( !points.is_valid() ) {
                warning = points.skill_points_left() < 0 ?
                          _( "Too many points allocated, change some features and try again." ) :
                          points.trait_points_left() < 0 ?
                          _( "Too many trait points allocated, change some traits or lower some stats and try again." ) :
                          points.stat_points_left() < 0 ?
                          _( "Too many stat points allocated, lower some stats and try again." ) :
                          _( "Too many points allocated, change some features and try again." );
            } else if( points.has_spare() ) {
                warning = _( "You have points left; they are lost when you start." );
            }
            if( !warning.empty() ) {
                jsout.member( "warn" );
                gs::write_span( jsout, { .text = warning, .color = points.is_valid() ? c_yellow : c_light_red } );
            }
            jsout.member( "body" );
            const auto [min_age, max_age] = profession_age_bounds( *you.prof );
            gs::write_span( jsout, { .text = current_selector == char_creation::NAME ? _( "Your name. Leave it empty for a random one." ) :
                                             current_selector == char_creation::HEIGHT ? _( "Your height in centimeters, from 145 to 200." ) :
                                             string_format( _( "Your age in years, from %d to %d." ), min_age, max_age )
                                   } );
            jsout.member( "buttons" );
            jsout.start_array();
            if( current_selector != char_creation::NAME ) {
                gs::write_button( jsout, { .act = "DOWN", .text = _( "Lower" ), .icon = "minus", .category = category } );
                gs::write_button( jsout, { .act = "UP", .text = _( "Raise" ), .icon = "plus", .category = category } );
            }
            gs::write_button( jsout, { .act = "CONFIRM", .text = _( "Edit" ), .icon = "pencil", .category = category,
                                       .enabled = !MAP_SHARING::isSharing()
                                     } );
            gs::write_button( jsout, { .act = "NEXT_TAB", .text = _( "Start game" ), .icon = "play", .category = category, .primary = true } );
            jsout.end_array();
            jsout.end_object();

            jsout.member( "hints" );
            jsout.start_array();
            gs::write_fixed_hint( jsout, "←→", _( "Choose" ) );
            gs::write_fixed_hint( jsout, "↑↓", _( "Change" ) );
            gs::write_hint( jsout, "CONFIRM", category, _( "Edit" ) );
            gs::write_hint( jsout, "NEXT_TAB", category, _( "Start game" ) );
            gs::write_hint( jsout, "PREV_TAB", category, _( "Previous tab" ) );
            gs::write_hint( jsout, "QUIT", category, _( "Main menu" ) );
            jsout.end_array();
        } );
    };
#endif
    ui.on_redraw( [&]( const ui_adaptor & ) {
#if defined(TILES)
        if( native ) {
            publish_native();
            if( use_character_preview ) {
                character_preview.display();
            }
            return;
        }
#endif
        draw_character_tabs( w, _( "OVERVIEW" ), you.prof );

        draw_points( w, points );

        //Draw the line between editable and non-editable stuff.
        for( int i = 0; i < getmaxx( w ); ++i ) {
            if( i == 0 ) {
                mvwputch( w, point( i, 8 ), BORDER_COLOR, LINE_XXXO );
            } else if( i == getmaxx( w ) - 1 ) {
                wputch( w, BORDER_COLOR, LINE_XOXX );
            } else {
                wputch( w, BORDER_COLOR, LINE_OXOX );
            }
        }
        wnoutrefresh( w );

        wclear( w_stats );
        wclear( w_traits );
        wclear( w_bionics );
        wclear( w_skills );
        wclear( w_guide );

        std::vector<std::string> vStatNames;
        mvwprintz( w_stats, point_zero, COL_HEADER, _( "Stats:" ) );
        vStatNames.emplace_back( _( "Strength:" ) );
        vStatNames.emplace_back( _( "Dexterity:" ) );
        vStatNames.emplace_back( _( "Intelligence:" ) );
        vStatNames.emplace_back( _( "Perception:" ) );
        int pos = 0;
        for( size_t i = 0; i < vStatNames.size(); i++ ) {
            std::string theName = "\t" + vStatNames[i];
            pos = ( utf8_width( theName ) > pos ?
                    utf8_width( theName ) : pos );
            mvwprintz( w_stats, point( 0, i + 1 ), c_light_gray, theName );
        }
        mvwprintz( w_stats, point( pos + 1, 1 ), c_light_gray, "%2d", you.str_max );
        mvwprintz( w_stats, point( pos + 1, 2 ), c_light_gray, "%2d", you.dex_max );
        mvwprintz( w_stats, point( pos + 1, 3 ), c_light_gray, "%2d", you.int_max );
        mvwprintz( w_stats, point( pos + 1, 4 ), c_light_gray, "%2d", you.per_max );
        wnoutrefresh( w_stats );

        mvwprintz( w_traits, point_zero, COL_HEADER, _( "Traits: " ) );
        std::vector<trait_id> current_traits = points.limit == points_left::TRANSFER ? you.get_mutations() :
                                               you.get_base_traits();
        std::sort( current_traits.begin(), current_traits.end(), trait_display_sort );
        if( current_traits.empty() ) {
            wprintz( w_traits, c_light_red, _( "None!" ) );
        } else {
            for( size_t i = 0; i < current_traits.size(); i++ ) {
                const auto current_trait = current_traits[i];
                trim_and_print( w_traits, point( 0, i + 1 ), getmaxx( w_traits ) - 1,
                                current_trait->get_display_color(), "\t" + current_trait->name() );
            }
        }

        wnoutrefresh( w_traits );

        mvwprintz( w_bionics, point_zero, COL_HEADER, _( "Bionics: " ) );

        std::vector<bionic_id> current_bionics;
        for( auto id : you.prof->CBMs() ) {
            current_bionics.push_back( id );
        }
        for( auto bio : you.get_bionic_collection() ) {
            current_bionics.push_back( bio.id );
        }

        std::sort( current_bionics.begin(), current_bionics.end(), []( const bionic_id & a,
        const bionic_id & b ) {
            return localized_compare( a->name.translated(), b->name.translated() );
        } );

        pos = 1;
        if( current_bionics.empty() ) {
            wprintz( w_bionics, c_light_red, _( "None!" ) );
        } else {
            for( size_t i = 0; i < current_bionics.size(); i++ ) {
                const auto current_bionic = current_bionics[i];
                trim_and_print( w_bionics, point( 0, pos ), getmaxx( w_bionics ) - 1,
                                c_white, "\t" + current_bionic->name.translated() );
                pos++;
            }
        }

        mvwprintz( w_bionics, point( 0, pos ), COL_HEADER, _( "Spells: " ) );
        pos++;
        if( !you.prof->spells().empty() ) {
            for( const std::pair<spell_id, int> spell_pair : you.prof->spells() ) {
                trim_and_print( w_bionics, point( 0, pos ), getmaxx( w_bionics ) - 1,
                                c_white, "\t" + string_format( _( "%s level %d" ), spell_pair.first->name, spell_pair.second ) );
                pos++;
            }
        }
        if( you.magic->knows_spell() ) {
            for( const spell *spell : you.magic->get_spells() ) {
                trim_and_print( w_bionics, point( 0, pos ), getmaxx( w_bionics ) - 1,
                                c_white, "\t" + string_format( _( "%s level %d" ), spell->id()->name, spell->get_level() ) );
                pos++;
            }
        }
        if( you.prof->spells().empty() && !you.magic->knows_spell() ) {
            wprintz( w_bionics, c_light_red, _( "None!" ) );
        }


        wnoutrefresh( w_bionics );

        mvwprintz( w_skills, point_zero, COL_HEADER, _( "Skills:" ) );

        auto skillslist = Skill::get_skills_sorted_by( [&]( const Skill & a, const Skill & b ) {
            return localized_compare( std::make_pair( a.display_category(), a.name() ),
                                      std::make_pair( b.display_category(), b.name() ) );
        } );

        int line = 1;
        bool has_skills = false;
        profession::StartingSkillList list_skills = you.prof->skills();
        skill_displayType_id last_category = skill_displayType_id::NULL_ID();
        for( auto &elem : skillslist ) {
            // Here we can display the actual level because it is not editing it
            int level = you.get_skill_level( elem->ident(), false );

            if( points.limit != points_left::TRANSFER ) {
                for( auto &prof_skill : you.prof->skills() ) {
                    if( prof_skill.first == elem->ident() ) {
                        level += static_cast<int>( prof_skill.second );
                        break;
                    }
                }
            }

            if( level > 0 ) {
                if( last_category != elem->display_category() ) {
                    last_category = elem->display_category();
                    mvwprintz( w_skills, point( 0, line ), c_yellow,
                               "\t" + elem->display_category()->display_string() );
                    line++;
                }
                mvwprintz( w_skills, point( 2, line ), c_light_gray,
                           elem->name() + ":" );
                mvwprintz( w_skills, point( 22, line ), c_light_gray, "%-2d",
                           level );
                line++;
                has_skills = true;
            }
        }
        if( !has_skills ) {
            mvwprintz( w_skills, point( utf8_width( _( "Skills:" ) ) + 1, 0 ), c_light_red, _( "None!" ) );
        }
        wnoutrefresh( w_skills );


        fold_and_print( w_guide, point( 0, getmaxy( w_guide ) - 4 ), ( TERMX / 2 ), c_light_gray,
                        _( "Press <color_light_green>%s</color> or <color_light_green>%s</color> "
                           "to cycle through name, height, and age." ),
                        ctxt.get_desc( "LEFT" ),
                        ctxt.get_desc( "RIGHT" ) );

        fold_and_print( w_guide, point( 0, getmaxy( w_guide ) - 3 ), ( TERMX / 2 ), c_light_gray,
                        _( "Press <color_light_green>%s</color> and <color_light_green>%s</color> to change height and age." ),
                        ctxt.get_desc( "UP" ),
                        ctxt.get_desc( "DOWN" ) );

        fold_and_print( w_guide, point( 0, getmaxy( w_guide ) - 2 ), ( TERMX / 2 ), c_light_gray,
                        _( "Press <color_light_green>%s</color> to enter popup input." ),
                        ctxt.get_desc( "CONFIRM" ) );

        fold_and_print( w_guide, point( 0, getmaxy( w_guide ) - 1 ), ( TERMX / 2 ), c_light_gray,
                        _( "Press <color_light_green>%s</color> to finish character creation "
                           "or <color_light_green>%s</color> to go back." ),
                        ctxt.get_desc( "NEXT_TAB" ),
                        ctxt.get_desc( "PREV_TAB" ) );
        if( allow_reroll ) {
            fold_and_print( w_guide, point( 0, getmaxy( w_guide ) - 5 ), ( TERMX / 2 ), c_light_gray,
                            _( "Press <color_light_green>%s</color> to save character template, "
                               "<color_light_green>%s</color> to re-roll or <color_light_green>%s</color> for random scenario." ),
                            ctxt.get_desc( "SAVE_TEMPLATE" ),
                            ctxt.get_desc( "REROLL_CHARACTER" ),
                            ctxt.get_desc( "REROLL_CHARACTER_WITH_SCENARIO" ) );
        } else {
            fold_and_print( w_guide, point( 0, getmaxy( w_guide ) - 5 ), ( TERMX / 2 ), c_light_gray,
                            _( "Press <color_light_green>%s</color> to save a template of this character." ),
                            ctxt.get_desc( "SAVE_TEMPLATE" ) );
        }
        wnoutrefresh( w_guide );

        wclear( w_name );
        mvwprintz( w_name, point_zero,
                   current_selector == char_creation::NAME ? h_light_gray : c_light_gray, _( "Name:" ) );
        if( no_name_entered ) {
            mvwprintz( w_name, point( namebar_pos, 0 ), h_light_gray, _( "--- NO NAME ENTERED ---" ) );
        } else if( you.name.empty() ) {
            mvwprintz( w_name, point( namebar_pos, 0 ), c_light_gray, _( "--- RANDOM NAME ---" ) );
        } else {
            mvwprintz( w_name, point( namebar_pos, 0 ), c_white, you.name );
        }

        if( !MAP_SHARING::isSharing() ) { // no random names when sharing maps
            // NOLINTNEXTLINE(cata-use-named-point-constants)
            fold_and_print( w_name, point( 0, 1 ), ( TERMX / 2 ), c_light_gray,
                            _( "Press <color_light_green>%s</color> to edit.\nPress <color_light_green>%s</color> to randomize description." ),
                            ctxt.get_desc( "CONFIRM" ), ctxt.get_desc( "RANDOMIZE_CHAR_DESCRIPTION" ) );
        }
        wnoutrefresh( w_name );

        mvwprintz( w_gender, point_zero, c_light_gray, _( "Gender:" ) );
        mvwprintz( w_gender, point( male_pos, 0 ), ( you.male ? c_light_cyan : c_light_gray ),
                   _( "Male" ) );
        mvwprintz( w_gender, point( female_pos, 0 ), ( you.male ? c_light_gray : c_pink ),
                   _( "Female" ) );
        // NOLINTNEXTLINE(cata-use-named-point-constants)
        fold_and_print( w_gender, point( 0, 1 ), ( TERMX / 2 ), c_light_gray,
                        _( "Press <color_light_green>%s</color> to switch gender" ),
                        ctxt.get_desc( "CHANGE_GENDER" ) );
        wnoutrefresh( w_gender );

        char_creation::draw_age( w_age, you, current_selector == char_creation::AGE );
        char_creation::draw_height( w_height, you, current_selector == char_creation::HEIGHT );

        const std::string location_prompt = string_format(
                                                _( "Press <color_light_green>%s</color> to select location." ),
                                                ctxt.get_desc( "CHOOSE_LOCATION" ) );

        werase( w_location );
        // NOLINTNEXTLINE(cata-use-named-point-constants)
        fold_and_print( w_location, point( 0, 1 ), ( TERMX / 2 ), c_light_gray, location_prompt );
        mvwprintz( w_location, point_zero, c_light_gray, _( "Starting location:" ) );
        // ::find will return empty location if id was not found. Debug msg will be printed too.
        mvwprintz( w_location, point( utf8_width( _( "Starting location:" ) ) + 1, 0 ),
                   you.random_start_location ? c_red : c_white,
                   you.random_start_location ? remove_color_tags( random_start_location_text ) :
                   string_format( remove_color_tags( START_LOC_TEXT_TEMPLATE ),
                                  you.start_location.obj().name(),
                                  you.start_location.obj().targets_count() ) );
        wnoutrefresh( w_location );

        mvwprintz( w_bionics, point_zero, COL_HEADER, _( "Bionics: " ) );
        if( current_bionics.empty() ) {
            wprintz( w_traits, c_light_red, _( "None!" ) );
        } else {
            for( size_t i = 0; i < current_bionics.size(); i++ ) {
                const auto current_bionic = current_bionics[i];
                trim_and_print( w_bionics, point( 0, i + 1 ), getmaxx( w_traits ) - 1,
                                c_white, "\t" + current_bionic->name.translated() );
            }
        }

        werase( w_misc );
        int misc_point = 1;
        mvwprintz( w_misc, point_zero, c_white, _( "Vehicle: " ) );
        const vproto_id scen_veh = g->scen->vehicle();
        const vproto_id prof_veh = you.prof->vehicle();
        if( !scen_veh && !prof_veh ) {
            wprintz( w_misc, c_light_red, _( "None!" ) );
        }
        if( scen_veh ) {
            trim_and_print( w_misc, point( 0, misc_point ), getmaxx( w_misc ) - 1,
                            c_white, "\t" + scen_veh->name );
            misc_point++;
        }
        if( prof_veh ) {
            trim_and_print( w_misc, point( 0, misc_point ), getmaxx( w_misc ) - 1,
                            c_white, "\t" + prof_veh->name );
            misc_point++;
        }
        std::vector<npc_class_id> npcs = you.prof->npcs();
        mvwprintz( w_misc, point( 0, misc_point ), c_white, _( "Companions: " ) );
        misc_point ++;
        if( !npcs.empty() ) {
            for( const npc_class_id &id : npcs ) {
                if( id.is_valid() ) {
                    const npc_class &npc_cls = id.obj();
                    trim_and_print( w_misc, point( 0, misc_point ), getmaxx( w_misc ) - 1,
                                    c_white, "\t" + npc_cls.get_name() );
                    misc_point ++;
                }
            }
        } else {
            wprintz( w_misc, c_light_red, _( "None!" ) );
        }

        mvwprintz( w_misc, point( 0, misc_point ), c_white, _( "Cash: " ) );

        if( !you.prof->starting_cash() ) {
            wprintz( w_misc, c_white, _( "Random!" ) );
        } else {
            wprintz( w_misc, c_white, format_money( you.prof->starting_cash().value() ) );
        }
        misc_point++;

        mvwprintz( w_misc, point( 0, misc_point ), c_white, _( "Pets: " ) );
        misc_point++;
        if( you.prof->pets().empty() ) {
            wprintz( w_misc, c_light_red, _( "None!" ) );
        } else {
            for( mtype_id &id : you.prof->pets() ) {
                if( id.is_valid() ) {
                    monster pet( id );
                    trim_and_print( w_misc, point( 0, misc_point ), getmaxx( w_misc ) - 1,
                                    c_white, "\t" + pet.get_name() );
                    misc_point ++;
                }
            }
        }

        mvwprintz( w_misc, point( 0, misc_point ), c_white, _( "Addictions: " ) );
        misc_point++;
        if( you.prof->addictions().empty() ) {
            wprintz( w_misc, c_light_red, _( "None!" ) );
        } else {
            for( addiction &addict : you.prof->addictions() ) {
                trim_and_print( w_misc, point( 0, misc_point ), getmaxx( w_misc ) - 1,
                                c_white, "\t" + addiction_name( addict ) );
                misc_point ++;
            }
        }

        wnoutrefresh( w_misc );

        werase( w_gear );

        const auto prof_items = you.prof->items( you.male, you.get_mutations() );

        int item_point = 1;

        mvwprintz( w_gear, point( 0, 0 ), c_white, _( "Items: " ) );

        if( prof_items.empty() ) {
            wprintz( w_gear, c_light_red, _( "None!" ) );
        } else {
            std::vector<std::string> wielded;
            std::vector<std::string> worn;
            std::vector<std::string> inventory;
            for( const auto &it : prof_items ) {
                if( it->has_flag( json_flag_no_auto_equip ) ) {
                    inventory.push_back( it->display_name() );
                } else if( it->has_flag( json_flag_auto_wield ) ) {
                    wielded.push_back( it->display_name() );
                } else if( it->is_armor() ) {
                    worn.push_back( it->display_name() );
                } else {
                    inventory.push_back( it->display_name() );
                }
            }

            mvwprintz( w_gear, point( 1, item_point ), c_yellow, _( "Wielded: " ) );
            item_point ++;
            if( wielded.empty() ) {
                wprintz( w_gear, c_light_red, _( "None!" ) );
            } else {
                for( std::string name : wielded ) {
                    trim_and_print( w_gear, point( 0, item_point ), getmaxx( w_gear ) - 1,
                                    c_white, "\t\t" + name );
                    item_point ++;
                }
            }
            mvwprintz( w_gear, point( 1, item_point ), c_yellow, _( "Worn: " ) );
            item_point ++;
            if( worn.empty() ) {
                wprintz( w_gear, c_light_red, _( "None!" ) );
            } else {
                for( std::string name : worn ) {
                    trim_and_print( w_gear, point( 0, item_point ), getmaxx( w_gear ) - 1,
                                    c_white, "\t\t" + name );
                    item_point ++;
                }
            }
            mvwprintz( w_gear, point( 1, item_point ), c_yellow, _( "Inventory: " ) );
            item_point ++;
            if( inventory.empty() ) {
                wprintz( w_gear, c_light_red, _( "None!" ) );
            } else {
                for( std::string name : inventory ) {
                    trim_and_print( w_gear, point( 0, item_point ), getmaxx( w_gear ) - 1,
                                    c_white, "\t\t" + name );
                    item_point ++;
                }
            }
        }

        wnoutrefresh( w_gear );

        werase( w_scenario );
        mvwprintz( w_scenario, point_zero, COL_HEADER, _( "Scenario: " ) );
        wprintz( w_scenario, c_light_gray, g->scen->gender_appropriate_name( you.male ) );
        wnoutrefresh( w_scenario );

        werase( w_profession );
        mvwprintz( w_profession, point_zero, COL_HEADER, _( "Profession: " ) );
        wprintz( w_profession, c_light_gray, you.prof->gender_appropriate_name( you.male ) );
        wnoutrefresh( w_profession );

#if defined(TILES)
        // Draws character preview
        if( use_character_preview ) {
            character_preview.display();
        }
#endif
    } );

    // do not switch IME mode now, but restore previous mode on return
    ime_sentry sentry( ime_sentry::keep );

    int min_allowed_age = profession::min_age;
    int max_allowed_age = profession::max_age;
    // in centimeters. 2 std. deviations below average female height
    int min_allowed_height = 145;
    int max_allowed_height = 200;

    do {
        const auto [new_min_age, new_max_age] = profession_age_bounds( *you.prof );
        min_allowed_age = new_min_age;
        max_allowed_age = new_max_age;
        you.set_base_age( clamp( you.base_age(), min_allowed_age, max_allowed_age ) );
        ui_manager::redraw();
        const std::string action = ctxt.handle_input();
#if defined(TILES)
        if( const auto pick = native ? cata::godot_bridge::take_pick( &you ) : std::nullopt ) {
            if( const auto direction = chargen_tab_click( *pick, chargen_step::overview, you.prof ) ) {
                character_preview.clear();
                return *direction;
            }
            if( *pick >= 0 && *pick <= char_creation::AGE ) {
                current_selector = static_cast<char_creation::description_selector>( *pick );
            }
        }
        if( action == "zoom_in" && use_character_preview ) {
            character_preview.zoom_in();
        }
        if( action == "zoom_out" && use_character_preview ) {
            character_preview.zoom_out();
        }
        if( action == "TOGGLE_CHARACTER_PREVIEW_CLOTHES" && use_character_preview ) {
            character_preview.toggle_clothes();
        }
#endif
        if( action == "NEXT_TAB" ) {
            if( !points.is_valid() ) {
                if( points.skill_points_left() < 0 ) {
                    popup( _( "Too many points allocated, change some features and try again." ) );
                } else if( points.trait_points_left() < 0 ) {
                    popup( _( "Too many trait points allocated, change some traits or lower some stats and try again." ) );
                } else if( points.stat_points_left() < 0 ) {
                    popup( _( "Too many stat points allocated, lower some stats and try again." ) );
                } else {
                    popup( _( "Too many points allocated, change some features and try again." ) );
                }
                continue;
            } else if( points.has_spare() &&
                       !query_yn( _( "Remaining points will be discarded, are you sure you want to proceed?" ) ) ) {
                continue;
            } else if( you.name.empty() ) {
                no_name_entered = true;
                ui_manager::redraw();
                if( !query_yn( _( "Are you SURE you're finished?  Your name will be randomly generated." ) ) ) {
                    continue;
                } else {
                    you.pick_name();
#if defined(TILES)
                    character_preview.clear();
#endif
                    return tab_direction::FORWARD;
                }
            } else if( query_yn( _( "Are you SURE you're finished?" ) ) ) {
#if defined(TILES)
                character_preview.clear();
#endif
                return tab_direction::FORWARD;
            } else {
                continue;
            }
        } else if( action == "PREV_TAB" ) {
#if defined(TILES)
            character_preview.clear();
#endif
            return tab_direction::BACKWARD;
        } else if( action == "RIGHT" ) {
            switch( current_selector ) {
                case char_creation::NAME:
                    current_selector = char_creation::HEIGHT;
                    break;
                case char_creation::HEIGHT:
                    current_selector = char_creation::AGE;
                    break;
                case char_creation::AGE:
                    current_selector = char_creation::NAME;
                    break;
            }
        } else if( action == "LEFT" ) {
            switch( current_selector ) {
                case char_creation::NAME:
                    current_selector = char_creation::AGE;
                    break;
                case char_creation::HEIGHT:
                    current_selector = char_creation::NAME;
                    break;
                case char_creation::AGE:
                    current_selector = char_creation::HEIGHT;
                    break;
            }
        } else if( action == "UP" ) {
            switch( current_selector ) {
                case char_creation::HEIGHT:
                    if( you.base_height() < max_allowed_height ) {
                        you.mod_base_height( 1 );
                    }
                    break;
                case char_creation::AGE:
                    if( you.base_age() < max_allowed_age ) {
                        you.mod_base_age( 1 );
                    }
                    break;
                default:
                    break;
            }
        } else if( action == "DOWN" ) {
            switch( current_selector ) {
                case char_creation::HEIGHT:
                    if( you.base_height() > min_allowed_height ) {
                        you.mod_base_height( -1 );
                    }
                    break;
                case char_creation::AGE:
                    if( you.base_age() > min_allowed_age ) {
                        you.mod_base_age( -1 );
                    }
                    break;
                default:
                    break;
            }
        } else if( action == "REROLL_CHARACTER" && allow_reroll ) {
            points.init_from_options();
            you.randomize( false, points );
            // Return tab_direction::NONE so we re-enter this tab again, but it forces a complete redrawing of it.
            return tab_direction::NONE;
        } else if( action == "REROLL_CHARACTER_WITH_SCENARIO" && allow_reroll ) {
            points.init_from_options();
            you.randomize( true, points );
            // Return tab_direction::NONE so we re-enter this tab again, but it forces a complete redrawing of it.
            return tab_direction::NONE;
        } else if( action == "SAVE_TEMPLATE" ) {
            if( const auto name = query_for_template_name() ) {
                you.save_template( *name, points );
            }
        } else if( action == "RANDOMIZE_CHAR_DESCRIPTION" ) {
            you.male = one_in( 2 );
            if( !MAP_SHARING::isSharing() ) { // Don't allow random names when sharing maps. We don't need to check at the top as you won't be able to edit the name
                you.pick_name();
                no_name_entered = you.name.empty();
            }
            you.set_base_age( rng( 16, 55 ) );
            you.set_base_height( rng( 145, 200 ) );
        } else if( action == "CHANGE_GENDER" ) {
            you.male = !you.male;
        } else if( action == "CHOOSE_LOCATION" ) {
            select_location.query();
            if( select_location.ret == RANDOM_START_LOC_ENTRY ) {
                you.random_start_location = true;
            } else if( select_location.ret >= 0 ) {
                for( const auto &loc : start_locations::get_all() ) {
                    if( loc.id.id().to_i() == select_location.ret ) {
                        you.random_start_location = false;
                        you.start_location = loc.id;
                        break;
                    }
                }
            }
        } else if( action == "CONFIRM" &&
                   // Don't edit names when sharing maps
                   !MAP_SHARING::isSharing() ) {

            string_input_popup popup;
            switch( current_selector ) {
                case char_creation::NAME: {
                    popup.title( _( "Enter name.  Cancel to delete all." ) )
                    .text( you.name )
                    .only_digits( false );
                    you.name = popup.query_string();
                    no_name_entered = you.name.empty();
                    break;
                }
                case char_creation::AGE: {
                    const std::string title = string_format( _( "Enter age in years.  Minimum %d, maximum %d" ),
                                              min_allowed_age, max_allowed_age );
                    popup.title( title )
                    .text( string_format( "%d", you.base_age() ) )
                    .only_digits( true );
                    const int result = popup.query_int();
                    if( result != 0 ) {
                        you.set_base_age( clamp( result, min_allowed_age, max_allowed_age ) );
                    }
                    break;
                }
                case char_creation::HEIGHT: {
                    popup.title( _( "Enter height in centimeters.  Minimum 145, maximum 200" ) )
                    .text( string_format( "%d", you.base_height() ) )
                    .only_digits( true );
                    const int result = popup.query_int();
                    if( result != 0 ) {
                        you.set_base_height( clamp( result, 145, 200 ) );
                    }
                    break;
                }
            }

        } else if( action == "QUIT" && query_yn( _( "Return to main menu?" ) ) ) {
#if defined(TILES)
            character_preview.clear();
#endif
            return tab_direction::QUIT;
        }
    } while( true );
}

std::vector<trait_id> Character::get_base_traits() const
{
    return std::vector<trait_id>( my_traits.begin(), my_traits.end() );
}

std::vector<trait_id> Character::get_mutations( bool include_hidden ) const
{
    std::vector<trait_id> result;
    for( const std::pair<const trait_id, char_trait_data> &t : my_mutations ) {
        if( include_hidden || t.first.obj().player_display ) {
            result.push_back( t.first );
        }
    }
    for( const trait_id &ench_trait : enchantment_cache->get_mutations() ) {
        if( include_hidden || ench_trait->player_display ) {
            bool found = false;
            for( const trait_id &exist : result ) {
                if( exist == ench_trait ) {
                    found = true;
                    break;
                }
            }
            if( !found ) {
                result.push_back( ench_trait );
            }
        }
    }
    return result;
}

void Character::clear_mutations()
{
    while( !my_traits.empty() ) {
        toggle_trait( *my_traits.begin() );
    }
    while( !my_mutations.empty() ) {
        unset_mutation( my_mutations.begin()->first );
    }
    cached_mutations.clear();
}

void Character::clear_skills()
{
    for( auto &sk : *_skills ) {
        sk.second.level( 0 );
    }
}

void newcharacter::add_traits( Character &ch )
{
    points_left points = points_left();
    add_traits( ch, points );
}

void newcharacter::add_traits( Character &ch, points_left &points )
{
    for( const trait_id &tr : ch.prof->get_locked_traits() ) {
        if( !ch.has_trait( tr ) ) {
            ch.toggle_trait( tr );
        } else {
            points.trait_points += tr->points;
        }
    }
    for( const trait_id &tr : g->scen->get_locked_traits() ) {
        if( !ch.has_trait( tr ) ) {
            ch.toggle_trait( tr );
        }
    }
}

trait_id newcharacter::random_good_trait()
{
    std::vector<trait_id> vTraitsGood;

    for( auto &traits_iter : mutation_branch::get_all() ) {
        if( traits_iter.points > 0 && g->scen->traitquery( traits_iter.id ) &&
            traits_iter.randomstartingtrait ) {
            vTraitsGood.push_back( traits_iter.id );
        }
    }

    return random_entry( vTraitsGood );
}

trait_id newcharacter::random_bad_trait()
{
    std::vector<trait_id> vTraitsBad;

    for( auto &traits_iter : mutation_branch::get_all() ) {
        if( traits_iter.points < 0 && g->scen->traitquery( traits_iter.id ) &&
            traits_iter.randomstartingtrait ) {
            vTraitsBad.push_back( traits_iter.id );
        }
    }

    return random_entry( vTraitsBad );
}

trait_id Character::get_random_trait( const std::function<bool( const mutation_branch & )> &func )
{
    std::vector<trait_id> vTraits;

    for( const mutation_branch &traits_iter : mutation_branch::get_all() ) {
        if( func( traits_iter ) ) {
            vTraits.push_back( traits_iter.id );
        }
    }

    return random_entry( vTraits );
}


auto newcharacter::add_default_mutation_type_traits( Character &ch ) -> void
{
    for( const auto &default_mutation : get_default_mutations_for_types() ) {
        const auto mutations = get_mutations_in_type( default_mutation.type_id );
        const auto has_mutation_type = std::ranges::any_of( mutations, [&]( const auto & trait ) {
            return ch.has_trait( trait );
        } );
        if( !has_mutation_type && default_mutation.trait.is_valid() ) {
            if( ch.has_base_trait( default_mutation.trait ) ) {
                ch.set_mutation( default_mutation.trait );
            } else {
                ch.toggle_trait( default_mutation.trait );
            }
        }
    }
}

void Character::randomize_cosmetic_trait( std::string mutation_type )
{
    trait_id trait = get_random_trait( [&]( const mutation_branch & mb ) {
        if( mb.points != 0 || !mb.types.contains( mutation_type ) ) {
            return false;
        }
        if( male ) {
            return !mb.flags.contains( flag_FEMALE_EXCLUSIVE ) &&
                   !mb.flags.contains( flag_FEMALE_PREFERRED );
        } else {
            return !mb.flags.contains( flag_MALE_EXCLUSIVE ) &&
                   !mb.flags.contains( flag_MALE_PREFERRED );
        }
    } );

    if( trait.is_valid() ) {
        clear_cosmetic_traits( mutation_type, trait );

        if( !has_trait( trait ) ) {
            toggle_trait( trait );
        }
    }
}

std::optional<std::string> query_for_template_name()
{
    static const std::set<int> fname_char_blacklist = {
#if defined(_WIN32)
        '\"', '*', '/', ':', '<', '>', '?', '\\', '|',
        '\x01', '\x02', '\x03', '\x04', '\x05', '\x06', '\x07',         '\x09',
        '\x0B', '\x0C',         '\x0E', '\x0F', '\x10', '\x11', '\x12',
        '\x13', '\x14',         '\x16', '\x17', '\x18', '\x19', '\x1A',
        '\x1C', '\x1D', '\x1E', '\x1F'
#else
        '/'
#endif
    };
    std::string title = _( "Name of template:" );
    std::string desc = _( "Keep in mind you may not use special characters like / in filenames" );

    string_input_popup spop;
    spop.title( title );
    spop.description( desc );
    spop.width( FULL_SCREEN_WIDTH - utf8_width( title ) - 8 );
    for( int character : fname_char_blacklist ) {
        spop.callbacks[ character ] = []() {
            return true;
        };
    }

    spop.query_string( true );
    if( spop.canceled() ) {
        return std::nullopt;
    } else {
        return spop.text();
    }
}

void avatar::character_to_template( const std::string &name )
{
    points_left points;
    points.stat_points = 0;
    points.trait_points = 0;
    points.skill_points = 0;
    points.limit = points_left::TRANSFER;
    save_template( name, points );
}

void avatar::save_template( const std::string &name, const points_left &points )
{
    std::string name_san = ensure_valid_file_name( name );
    write_to_file( PATH_INFO::templatedir() + name_san + ".template", [&]( std::ostream & fout ) {
        JsonOut jsout( fout, true );

        jsout.start_array();

        jsout.start_object();
        jsout.member( "stat_points", points.stat_points );
        jsout.member( "trait_points", points.trait_points );
        jsout.member( "skill_points", points.skill_points );
        jsout.member( "limit", points.limit );
        jsout.member( "starting_vehicle", starting_vehicle );
        jsout.member( "random_start_location", random_start_location );
        if( !random_start_location ) {
            jsout.member( "start_location", start_location );
        }
        jsout.end_object();

        serialize( jsout );

        jsout.end_array();
    }, _( "player template" ) );
}

bool avatar::load_template( const std::string &template_name, points_left &points )
{
    return read_from_file_json( PATH_INFO::templatedir() + template_name +
    ".template", [&]( JsonIn & jsin ) {

        if( jsin.test_array() ) {
            // not a legacy template
            jsin.start_array();

            if( jsin.end_array() ) {
                return;
            }

            JsonObject jobj = jsin.get_object();

            points.stat_points = jobj.get_int( "stat_points" );
            points.trait_points = jobj.get_int( "trait_points" );
            points.skill_points = jobj.get_int( "skill_points" );
            points.limit = static_cast<points_left::point_limit>( jobj.get_int( "limit" ) );

            if( jobj.has_member( "starting_vehicle" ) ) {
                starting_vehicle = vproto_id( jobj.get_string( "starting_vehicle" ) );
            } else {
                starting_vehicle = vproto_id::NULL_ID();
            }
            random_start_location = jobj.get_bool( "random_start_location", true );
            const std::string jobj_start_location = jobj.get_string( "start_location", "" );

            // g->scen->allowed_start( loc.ident() ) is checked once scenario loads in avatar::load()
            for( const auto &loc : start_locations::get_all() ) {
                if( loc.id.str() == jobj_start_location ) {
                    random_start_location = false;
                    this->start_location = loc.id;
                    break;
                }
            }

            if( jsin.end_array() ) {
                return;
            }
        } else {
            points.stat_points = 0;
            points.trait_points = 0;
            points.skill_points = 0;
        }

        deserialize( jsin );

        if( MAP_SHARING::isSharing() ) {
            // just to make sure we have the right name
            name = MAP_SHARING::getUsername();
        }
    } );
}

void reset_scenario( avatar &u, const scenario *scen )
{
    auto psorter = profession_sorter;
    psorter.sort_by_points = true;
    const std::vector<profession_id> permitted = scen->permitted_professions();
    const profession_id &default_prof = *std::min_element( permitted.begin(), permitted.end(),
                                        psorter );

    const auto previous_hair_style = selected_cosmetic_trait( u, type_hair_style );
    const auto previous_hair_color = selected_cosmetic_trait( u, type_hair_color );

    u.random_start_location = true;
    u.str_max = 8;
    u.dex_max = 8;
    u.int_max = 8;
    u.per_max = 8;
    g->scen = scen;
    u.prof = default_prof;
    u.set_base_age( random_age_for_profession( *u.prof ) );
    for( auto &t : u.get_mutations() ) {
        if( t.obj().hp_modifier != 0 ) {
            u.toggle_trait( t );
        }
    }
    u.clear_mutations();
    u.recalc_hp();
    u.clear_skills();
    u.clear_bionics();
    newcharacter::add_traits( u );
    restore_cosmetic_trait( u, type_hair_color, previous_hair_color );
    restore_or_default_hair_style( u, previous_hair_style );
}

points_left::points_left()
{
    limit = MULTI_POOL;
    init_from_options();
}

void points_left::init_from_options()
{
    stat_points = get_option<int>( "INITIAL_STAT_POINTS" );
    trait_points = get_option<int>( "INITIAL_TRAIT_POINTS" );
    skill_points = get_option<int>( "INITIAL_SKILL_POINTS" );
}

// Highest amount of points to spend on stats without points going invalid
int points_left::stat_points_left() const
{
    switch( limit ) {
        case FREEFORM:
        case ONE_POOL:
            return stat_points + trait_points + skill_points;
        case MULTI_POOL:
            return std::min( trait_points_left(),
                             stat_points + std::min( 0, trait_points + skill_points ) );
        case TRANSFER:
            return 0;
    }

    return 0;
}

int points_left::trait_points_left() const
{
    switch( limit ) {
        case FREEFORM:
        case ONE_POOL:
            return stat_points + trait_points + skill_points;
        case MULTI_POOL:
            return stat_points + trait_points + std::min( 0, skill_points );
        case TRANSFER:
            return 0;
    }

    return 0;
}

int points_left::skill_points_left() const
{
    return stat_points + trait_points + skill_points;
}

bool points_left::is_freeform()
{
    return limit == FREEFORM;
}

bool points_left::is_valid()
{
    return is_freeform() ||
           ( stat_points_left() >= 0 && trait_points_left() >= 0 &&
             skill_points_left() >= 0 );
}

bool points_left::has_spare()
{
    return !is_freeform() && is_valid() && skill_points_left() > 0;
}

std::string points_left::to_string()
{
    if( limit == MULTI_POOL ) {
        return string_format(
                   _( "Points left: <color_%s>%d</color>%c<color_%s>%d</color>%c<color_%s>%d</color>=<color_%s>%d</color>" ),
                   stat_points_left() >= 0 ? "light_gray" : "red", stat_points,
                   trait_points >= 0 ? '+' : '-',
                   trait_points_left() >= 0 ? "light_gray" : "red", std::abs( trait_points ),
                   skill_points >= 0 ? '+' : '-',
                   skill_points_left() >= 0 ? "light_gray" : "red", std::abs( skill_points ),
                   is_valid() ? "light_gray" : "red", stat_points + trait_points + skill_points );
    } else if( limit == ONE_POOL ) {
        return string_format( _( "Points left: %4d" ), skill_points_left() );
    } else if( limit == TRANSFER ) {
        return _( "Character Transfer: No changes can be made." );
    } else {
        return _( "Freeform" );
    }
}

namespace newcharacter
{

bool has_conflicting_trait( const Character &ch, const trait_id &t )
{
    return ch.has_opposite_trait( t ) ||
           has_lower_trait( ch, t ) ||
           has_higher_trait( ch, t ) ||
           has_same_type_trait( ch, t ) ;
}

bool bionic_has_conflict( const Character &ch, const bionic_id &b )
{
    bool has_conflict_mut = false;
    for( const trait_id &mid : b->canceled_mutations ) {
        if( ch.has_trait( mid ) ) {
            has_conflict_mut = true;
        }
    }
    bool lacks_needed_bio = false;
    if( !b->required_bionics.empty() ) {
        for( const bionic_id &req_bid : b->required_bionics ) {
            if( !ch.has_bionic( req_bid ) ) {
                lacks_needed_bio = true;
                break;
            }
        }
    }

    bool upgrade_issues = false;
    if( !b->available_upgrades.empty() ) {
        for( const bionic_id &up_bid : b->available_upgrades ) {
            if( ch.has_bionic( up_bid ) ) {
                upgrade_issues = true;
            }
        }
    }

    if( b->upgraded_bionic != bionic_id::NULL_ID() ) {
        if( ch.has_bionic( b->upgraded_bionic ) ) {
            upgrade_issues = true;
        }
    }

    return !ch.bionic_installation_issues( b ).empty() ||
           has_conflict_mut ||
           lacks_needed_bio ||
           upgrade_issues;
}

bool has_lower_trait( const Character &ch, const trait_id &t )
{
    for( const trait_id &it : t->prereqs ) {
        if( ch.has_trait( it ) || has_lower_trait( ch, it ) ) {
            return true;
        }
    }
    return false;
}

bool has_higher_trait( const Character &ch, const trait_id &t )
{
    for( const trait_id &it : t->replacements ) {
        if( ch.has_trait( it ) || has_higher_trait( ch, it ) ) {
            return true;
        }
    }
    return false;
}

bool has_same_type_trait( const Character &ch, const trait_id &t )
{
    for( const trait_id &it : get_mutations_in_types( t->types ) ) {
        if( ch.has_trait( it ) && t != it ) {
            return true;
        }
    }
    return false;
}

} // namespace newcharacter
