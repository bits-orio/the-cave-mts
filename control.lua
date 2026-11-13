local underground_blueprints = require("scripts.underground_blueprints")
local underground_world_sync = require("scripts.underground_world_sync")
local underground_item_ui = require("scripts.underground_item_ui")
local cave_teams = require("scripts.cave_teams")
local cave_lifecycle = require("scripts.cave_lifecycle")
local mirror = require("scripts.lib.mirror")
local pop_text = require("scripts.pop_text")
local world = require("scripts.world")
local collapse = require("scripts.collapse")
local roof_support = require("scripts.roof_support")
local roof_support_mining = require("scripts.roof_support_mining")

local function reevaluate_removed_roof(record, player_index)
    if not record then return end
    local surface = game.surfaces[record.surface_index]
    if not (surface and surface.valid) then return end
    collapse.evaluate_around(surface,
        {x = (record.x1 + record.x2) / 2, y = (record.y1 + record.y2) / 2},
        record.area / 2 + 2, player_index)
    roof_support.refresh_previews()
end
local advancing_collapse = require("scripts.advancing_collapse")
local threats = require("scripts.threats")
require("scripts.integrations.mother")
local dig_tracker = require("scripts.dig_tracker")
local dig_spawner = require("scripts.dig_spawner")
local cave_enemy_expansion = require("scripts.cave_enemy_expansion")
local enemy_nest_growth = require("scripts.enemy_nest_growth")
local dig_yield = require("scripts.dig_yield")
local ore_veins = require("scripts.ore_veins")
local mobile_factory_resources = require("scripts.mobile_factory_resources")
local bob_ores_resources = require("scripts.bob_ores_resources")
bob_ores_resources.configure_world(world)
local treasure = require("scripts.treasure")
local caverns = require("scripts.caverns")
local uranium_caves = require("scripts.uranium_caves")
local mineral_caves = require("scripts.mineral_caves")
local lost_city = require("scripts.lost_city")
local fortified_vaults = require("scripts.fortified_vaults")
local cave_evolution = require("scripts.cave_evolution")
local charting = require("scripts.charting")
local install_guard = require("scripts.install_guard")
local admin_kit = require("scripts.admin_kit")
local sim = require("scripts.sim")
local depth_levels = require("scripts.depth_levels")
local region_features = require("scripts.region_features")
local market_coin = require("scripts.market_coin")
local coin_maker = require("scripts.coin_maker")
local advancing_recovery = require("scripts.advancing_recovery")
advancing_recovery.configure_rewards(market_coin.on_entity_died)
local ore_protection = require("scripts.ore_protection")
local ore_missing = require("scripts.ore_missing")
local ore_blood = require("scripts.ore_blood")
local bob_enemies = require("scripts.bob_enemies")
local enemy_brood_split = require("scripts.enemy_brood_split")
local drill_filter = require("scripts.drill_filter")
local mining_drill_pipette = require("scripts.mining_drill_pipette")
local resource_eraser = require("scripts.resource_eraser")
local train_interiors = require("scripts.train_interiors")
local shelter_core = require("scripts.shelter_core")
local equipment_grid_upgrades = require("scripts.equipment_grid_upgrades")
local wind_turbine = require("scripts.wind_turbine")
local solar_display = require("scripts.solar_display")
local interior_maintenance = require("scripts.interior_maintenance")
local cave_accumulator_visuals = require("scripts.cave_accumulator_visuals")
local portable_cave_accumulators = require("scripts.portable_cave_accumulators")
local warp_outpost = require("scripts.warp_outpost")
local inventory_repair = require("scripts.inventory_repair")
local turret_range = require("scripts.turret_range")
local nearby_ammo_count = require("scripts.nearby_ammo_count")
local gun_turret_autoload = require("scripts.gun_turret_autoload")
local underground_belt_reach = require("scripts.underground_belt_reach")
local underground_pipe_reach = require("scripts.underground_pipe_reach")
local belt_stack_sync = require("scripts.belt_stack_sync")
local industrial_loaders = require("scripts.industrial_loaders")
local cave_damage_indicator = require("scripts.damage_indicator.main")
local darkness_infestation = require("scripts.darkness_infestation")
local cave_respawn = require("scripts.cave_respawn")
local lamp_pole = require("scripts.lamp_pole")
local fulgora_lightning = require("scripts.fulgora_lightning")
local faster_start = require("scripts.faster_start")
local starter_pack = require("scripts.starter_pack")
local starting_inventory = require("scripts.starting_inventory")
local chemical_rockets = require("scripts.chemical_rockets")
local offline_player_body = require("scripts.offline_player_body")
local extra_storage_tanks = require("scripts.extra_storage_tanks")
local portable_tanks = require("scripts.portable_tanks")
local tnt_boxes = require("scripts.tnt_boxes")
local weapon_digging = require("scripts.weapon_digging")
local welcome_gui = require("scripts.welcome_gui")
local information_gui = require("scripts.information_gui")
local teleport = require("scripts.teleport")
local minimal_wire = require("scripts.minimal_wire")
local everything_on_nauvis_progression = require("scripts.everything_on_nauvis_progression")
local quality_everything = require("scripts.quality_everything")
local soft_reset = require("scripts.soft_reset")
local main_train_defeat = require("scripts.main_train_defeat")
local game_settings = require("scripts.game_settings")
local settings = game_settings.proxy(settings)

-- Bind extraction-cave modules directly once while require() is legal. Runtime
-- events must never guess Factorio's internal package.loaded cache keys.
bob_enemies.configure_expansion_api(cave_enemy_expansion)
caverns.configure_extraction_cave_apis(uranium_caves, mineral_caves, lost_city)
caverns.configure_train_safety_api(train_interiors)
world.configure_extraction_cave_apis(uranium_caves, mineral_caves)
depth_levels.configure_extraction_cave_apis(uranium_caves, mineral_caves)
train_interiors.wave_defense.configure_extraction_cave_apis(caverns, uranium_caves, mineral_caves)
enemy_nest_growth.configure_start_anchor_api {
    get_start_anchor = function(surface)
        local force = cave_teams.owner_force(surface)
        local train_anchor = train_interiors.initial_starter_train_center(surface, force)
        if train_anchor then return train_anchor end
        if force and force.valid then return force.get_spawn_position(surface) end
        return { x = 0, y = 0 }
    end,
}
cave_enemy_expansion.configure_objective_api {
    get_objective = function(force)
        if shelter_core.is_enabled() then return shelter_core.get_anchor(force) end
        return train_interiors.main_locomotive_for_force(force)
    end,
}
advancing_collapse.configure_assault_objective_api {
    get_owner_force = function(surface)
        return cave_teams.owner_force(surface)
    end,
    get_objective = function(force)
        if shelter_core.is_enabled() then return shelter_core.get_anchor(force) end
        return train_interiors.main_locomotive_for_force(force)
    end,
}
advancing_collapse.configure_catch_up_api {
    get_owner_force = cave_teams.owner_force,
    get_main_locomotive = train_interiors.main_locomotive_for_force,
}
advancing_collapse.configure_start_area_api {
    get_train_center = train_interiors.initial_starter_train_center,
    train_enabled = train_interiors.is_enabled,
}

uranium_caves.register_commands()
mineral_caves.register_commands()
lost_city.register_commands()
fortified_vaults.register_commands()
caverns.register_commands()
cave_enemy_expansion.register_commands()
advancing_collapse.register_commands()

local inserter_config_setting = settings and settings.startup and settings.startup["the-cave-inserter-configurable"]
local inserter_config_enabled = not inserter_config_setting or inserter_config_setting.value == "enabled"
local inserter_config
if inserter_config_enabled then
    inserter_config = require("scripts.inserter_config")
else
    -- A relative GUI created while the feature was enabled is persisted in the
    -- save. Disabling the Startup setting must therefore actively remove that
    -- stale GUI instead of merely replacing the runtime handlers with no-ops.
    local function delete_stale_gui(player)
        if not (player and player.valid) then return end
        local relative_gui = player.gui and player.gui.relative
        local frame = relative_gui and relative_gui.inserter_config
        if frame and frame.valid then
            frame.destroy()
        end
    end

    local function delete_all_stale_guis()
        if not game then return end
        for _, player in pairs(game.players) do
            delete_stale_gui(player)
        end
    end

    local function delete_player_stale_gui(event)
        if not (event and event.player_index and game) then return end
        delete_stale_gui(game.get_player(event.player_index))
    end

    local function no_op() end
    inserter_config = {
        on_init = delete_all_stale_guis,
        on_configuration_changed = delete_all_stale_guis,
        on_player_created = delete_player_stale_gui,
        on_entity_settings_pasted = no_op,
        on_gui_opened = delete_player_stale_gui,
        on_gui_closed = delete_player_stale_gui,
        on_gui_click = no_op,
        on_player_rotated_entity = no_op,
        on_research_finished = no_op,
        on_research_reversed = no_op,
        on_rotation_adjust = no_op,
        on_distance_adjust = no_op,
        on_offset_adjust = no_op,
    }
end

local function the_cave_startup_enabled(name, default_enabled)
    local setting = settings and settings.startup and settings.startup[name]
    if not setting then return default_enabled ~= false end
    return setting.value == "enabled" or setting.value == true
end

local function the_cave_damage_indicator_enabled()
    return the_cave_startup_enabled("the-cave-integrated-damage-indicator", true)
end


-- No crashed spaceship in a cave: disable freeplay's crash site and intro.
-- The Cave's own first-join welcome panel now provides the mode-aware rules.
local function disable_crash_site()
    if remote.interfaces["freeplay"] then
        pcall(remote.call, "freeplay", "set_disable_crashsite", true)
        if remote.interfaces["freeplay"].set_skip_intro then
            pcall(remote.call, "freeplay", "set_skip_intro", true)
        end
    end
end



-- Fixed solar output by lighting mode:
-- Permanent Day = 60kW, Permanent Night = 30kW, Pitch Black = 15kW.
local THE_CAVE_SOLAR_DAY = 1
local THE_CAVE_SOLAR_NIGHT = 10
local THE_CAVE_SOLAR_PITCH_BLACK = 5

-- Factorissimo owns the daytime and brightness settings of its factory-floor
-- surfaces. The Cave must never overwrite those values, otherwise Permanent
-- Night/Pitch Black can immediately undo Factorissimo's Interior Lighting
-- upgrade. Cache the result because this check runs once per second.
local the_cave_factorissimo_surface_cache = {}
local THE_CAVE_FACTORISSIMO_SURFACE_MARKERS = {
    "factory-floor",
    "factory floor",
    "factorissimo",
}

local function the_cave_is_factorissimo_surface(surface)
    if not (surface and surface.valid) then return false end

    local cached = the_cave_factorissimo_surface_cache[surface.index]
    if cached ~= nil then return cached end

    local detected = false
    local interfaces = remote and remote.interfaces
    local interface = interfaces and interfaces["factorissimo"]

    -- Factorissimo 3 exposes this official compatibility API. It accepts a
    -- LuaSurface, surface name, or surface index.
    if interface and interface.is_factorissimo_surface then
        local ok, result = pcall(
            remote.call,
            "factorissimo",
            "is_factorissimo_surface",
            surface
        )
        if ok and result then detected = true end
    end

    -- Fallback for Behrooz Factorissimo and older compatible forks.
    if not detected then
        local name = string.lower(surface.name or "")
        for _, marker in ipairs(THE_CAVE_FACTORISSIMO_SURFACE_MARKERS) do
            if name:find(marker, 1, true) then
                detected = true
                break
            end
        end
    end

    the_cave_factorissimo_surface_cache[surface.index] = detected
    return detected
end

local function the_cave_get_lighting_mode(surface)
    if warp_outpost and warp_outpost.get_lighting_mode then
        local runtime_mode = warp_outpost.get_lighting_mode(surface)
        if runtime_mode then return runtime_mode end
    end
    if settings and settings.startup and settings.startup["the-cave-underground-lighting-mode"] then
        return settings.startup["the-cave-underground-lighting-mode"].value or "permanent-night"
    end
    return "permanent-night"
end

local function the_cave_apply_lighting_to_surface(surface)
    if not (surface and surface.valid) then return end

    -- Factorissimo manages its own factory interior lighting. Skipping these
    -- surfaces lets its Interior Lighting research work even when The Cave is
    -- set to Permanent Night or Pitch Black.
    if the_cave_is_factorissimo_surface(surface) then return end

    -- Mobile Factory owns the lighting of both its main factory floor and its
    -- Control Room. Never overwrite those private surfaces with The Cave's
    -- Permanent Night, Pitch Black, Permanent Day or Normal profile.
    if mobile_factory_resources.is_interior_surface(surface) then return end

    if train_interiors.is_train_surface and train_interiors.is_train_surface(surface) then
        pcall(function() surface.always_day = true end)
        pcall(function() surface.freeze_daytime = true end)
        pcall(function() surface.daytime = 0.1 end)
        pcall(function() surface.min_brightness = 0.15 end)
        pcall(function() surface.solar_power_multiplier = 1 end)
        return
    end

    if shelter_core.is_shelter_surface and shelter_core.is_shelter_surface(surface) then
        pcall(function() surface.always_day = true end)
        pcall(function() surface.freeze_daytime = true end)
        pcall(function() surface.daytime = 0.1 end)
        pcall(function() surface.min_brightness = 0.15 end)
        pcall(function() surface.solar_power_multiplier = 1 end)
        return
    end

    if (lost_city.is_lost_city_surface and lost_city.is_lost_city_surface(surface))
        or (uranium_caves.is_uranium_cave_surface and uranium_caves.is_uranium_cave_surface(surface))
        or (mineral_caves.is_mineral_cave_surface and mineral_caves.is_mineral_cave_surface(surface))
        or (fortified_vaults.is_fortified_vault_surface and fortified_vaults.is_fortified_vault_surface(surface)) then
        -- These modules initialise their fixed lighting at creation/migration.
        -- Ordinary global lighting enforcement must not rewrite them each second.
        return
    end

    local mode = the_cave_get_lighting_mode(surface)

    if mode == "normal" then
        -- Normal Factorio day/night cycle.
        pcall(function() surface.always_day = false end)
        pcall(function() surface.freeze_daytime = false end)
        pcall(function() surface.solar_power_multiplier = 1 end)
        -- Restore the normal day/night transition shape if a darker mode was used before.
        pcall(function() surface.dusk = 0.25 end)
        pcall(function() surface.evening = 0.45 end)
        pcall(function() surface.morning = 0.55 end)
        pcall(function() surface.dawn = 0.75 end)
        pcall(function() surface.show_clouds = true end)
        pcall(function() surface.min_brightness = 0.15 end)
        return
    end

    if mode == "permanent-day" then
        -- Builder-friendly mode: keep the cave fully lit.
        pcall(function() surface.always_day = true end)
        pcall(function() surface.freeze_daytime = false end)
        pcall(function() surface.daytime = 0.0 end)
        pcall(function() surface.solar_power_multiplier = THE_CAVE_SOLAR_DAY end)
        pcall(function() surface.show_clouds = true end)
        pcall(function() surface.min_brightness = 0.15 end)
        return
    end

    if mode == "pitch-black" then
        -- Hardcore cave mode:
        -- keep the cave extremely dark, but do not place the surface inside
        -- Factorio's full zero-solar night window. Using 0.44 with normal
        -- dusk/evening thresholds allows weak solar output, then min_brightness
        -- keeps the visual ambience close to pitch black.
        pcall(function() surface.always_day = false end)
        pcall(function() surface.freeze_daytime = true end)
        pcall(function() surface.daytime = 0.44 end)
        pcall(function() surface.dusk = 0.25 end)
        pcall(function() surface.evening = 0.45 end)
        pcall(function() surface.morning = 0.55 end)
        pcall(function() surface.dawn = 0.75 end)
        pcall(function() surface.show_clouds = false end)
        pcall(function() surface.brightness_visual_weights = {r = 1, g = 1, b = 1} end)
        pcall(function() surface.min_brightness = 0 end)
        pcall(function() surface.solar_power_multiplier = THE_CAVE_SOLAR_PITCH_BLACK end)
        return
    end

    -- Default / compatibility mode: current The Cave permanent night.
    pcall(function() surface.always_day = false end)
    pcall(function() surface.freeze_daytime = true end)
    pcall(function() surface.daytime = 0.44 end)
    pcall(function() surface.dusk = 0.25 end)
    pcall(function() surface.evening = 0.45 end)
    pcall(function() surface.morning = 0.55 end)
    pcall(function() surface.dawn = 0.75 end)
    pcall(function() surface.solar_power_multiplier = THE_CAVE_SOLAR_NIGHT end)
    pcall(function() surface.min_brightness = 0 end)
end

-- Only cave worlds, The Cave's own surfaces, planets and platforms take its
-- lighting. Other mods' surfaces, such as a team mod's lobby, keep their own.
local function the_cave_lights_surface(surface)
    return cave_lifecycle.worlds.is_cave_world(surface) or surface.name:find("^the%-cave%-") ~= nil
        or surface.planet ~= nil or surface.platform ~= nil
end

-- A team mod pauses a force by switching off solar on its surfaces. Leave those
-- surfaces alone until it resumes the force.
local function the_cave_paused_surfaces()
    local paused = {}
    for _, force in ipairs(cave_teams.active_forces()) do
        if cave_teams.is_paused(force) then
            for _, surface in ipairs(cave_lifecycle.owned_surfaces(force)) do paused[surface.index] = true end
            for index in pairs(storage.cave_worlds or {}) do
                if cave_lifecycle.worlds.owner_force(index) == force then paused[index] = true end
            end
        end
    end
    return paused
end

local function make_cave_dark()
    -- Applies the selected The Cave lighting mode.
    -- Enforced repeatedly because scenarios, surfaces, or other mods may try to
    -- move time forward again.
    local paused = storage.the_cave_team_adapter and the_cave_paused_surfaces() or {}
    for _, surface in pairs(game.surfaces) do
        if the_cave_lights_surface(surface) and not paused[surface.index] then
            the_cave_apply_lighting_to_surface(surface)
        end
        solar_display.sync(surface)
    end
end

local function initialize_the_cave_runtime(is_soft_reset)
    cave_lifecycle.on_init()
    interior_maintenance.reset()
    disable_crash_site()
    if is_soft_reset then
        -- A staged restart is an intentional fresh world at a non-zero tick.
        -- Never let the mid-save install guard block its world conversion.
        storage.mid_save_install = nil
        -- These are derived module-local caches, not saved state. They must not
        -- retain facts from chunks or force relationships that were just reset.
        mirror.wipe()
        collapse.wipe_cache()
        nearby_ammo_count.on_force_relationship_changed()
        the_cave_factorissimo_surface_cache = {}
    end
    game_settings.apply_to_forces()
    -- Complete planet discovery before zone state is initialized so every
    -- unassigned Everything-on-Nauvis region family is available immediately.
    everything_on_nauvis_progression.on_init()
    quality_everything.on_init()
    dig_tracker.on_init()
    charting.on_init()
    collapse.on_init()
    roof_support.rebuild()
    roof_support_mining.initialize()
    threats.on_init()
    caverns.on_init()
    bob_enemies.on_configuration_changed()
    caverns.scheduled.on_init()
    uranium_caves.on_init()
    mineral_caves.on_init()
    lost_city.on_init()
    fortified_vaults.on_init()
    cave_evolution.sync_all()
    pop_text.on_init()
    depth_levels.on_init()
    if not is_soft_reset then install_guard.on_init() end
    advancing_collapse.on_init()
    caverns.progression.on_init()
    ore_missing.on_init()
    drill_filter.on_init()
    train_interiors.on_init()
    -- Guard first: on a mid-save install the world conversion must not run,
    -- or it would void an existing base.
    if not storage.mid_save_install then
        world.on_init(is_soft_reset)
        advancing_collapse.on_world_ready()
    end
    shelter_core.on_init(is_soft_reset)
    train_interiors.on_configuration_changed()
    if ore_veins.on_init then ore_veins.on_init() end
    mobile_factory_resources.on_init()
    enemy_nest_growth.on_init(is_soft_reset)
    dig_spawner.on_configuration_changed()
    cave_enemy_expansion.on_init(is_soft_reset)
    weapon_digging.on_init()
    dig_spawner.apply_expansion_setting()
    make_cave_dark()
    market_coin.on_init()
    coin_maker.on_init()
    enemy_brood_split.on_init()
    ore_protection.on_init()
    equipment_grid_upgrades.on_init()
    wind_turbine.on_init()
    cave_accumulator_visuals.on_init()
    lamp_pole.on_init()
    warp_outpost.on_init()
    inventory_repair.on_init()
    turret_range.on_init()
    underground_belt_reach.on_init()
    underground_pipe_reach.on_init()
    if the_cave_damage_indicator_enabled() then cave_damage_indicator.on_init() end
    inserter_config.on_init()
    darkness_infestation.on_init()
    faster_start.on_init()
    starter_pack.on_init()
    chemical_rockets.on_init()
    offline_player_body.on_init()
    welcome_gui.on_init()
    information_gui.on_init()
    teleport.on_init()
    minimal_wire.on_init()
    portable_tanks.on_configuration_changed()
    tnt_boxes.on_init()
    shelter_core.refresh_spawn_positions()
end

local function initialize_existing_player(player_index)
    local event = { player_index = player_index }
    everything_on_nauvis_progression.on_player_created(event)
    underground_belt_reach.on_player_created(event)
    underground_pipe_reach.on_player_created(event)
    inserter_config.on_player_created(event)
    ore_missing.on_player_created(event)
    market_coin.on_player_created(event)
    equipment_grid_upgrades.on_player_created(event)
    install_guard.on_player_created(event)
    train_interiors.on_player_created(event)
    shelter_core.on_player_created(event)
    warp_outpost.on_player_created(event)
    inventory_repair.on_player_created(event)
    starting_inventory.on_player_ready(event)
    welcome_gui.on_player_created(event)
    information_gui.on_player_created(event)
    teleport.on_player_created(event)
    advancing_collapse.on_player_created(event)
    cave_teams.queue_arrival(player_index)
end

soft_reset.configure {
    active_forces = cave_teams.active_forces,
    home_surface = cave_teams.home_surface,
    player_force = cave_teams.player_force,
    on_started = cave_lifecycle.on_server_reset_started,
    on_finished = cave_lifecycle.on_server_reset_finished,
    before_wipe_state = advancing_collapse.destroy_visuals,
    initialize_runtime = function()
        initialize_the_cave_runtime(true)
    end,
    initialize_player = initialize_existing_player,
    post_initialize_runtime = function(reset)
        shelter_core.on_soft_reset_world_ready(reset)
    end,
}

shelter_core.set_soft_reset_handler(cave_lifecycle.on_defeated)
warp_outpost.set_main_train_defeat_handler(cave_lifecycle.on_defeated)
cave_lifecycle.set_player_initializer(initialize_existing_player)

script.on_init(function()
    disable_crash_site()
    initialize_the_cave_runtime(false)
end)

script.on_load(function()
    if the_cave_damage_indicator_enabled() then cave_damage_indicator.on_load() end
end)

script.on_configuration_changed(function()
    cave_lifecycle.on_configuration_changed()
    interior_maintenance.reset()
    -- Existing saves and team forces receive the same discovery state before
    -- Advancing Collapse refreshes its available zone families.
    everything_on_nauvis_progression.on_configuration_changed()
    quality_everything.on_configuration_changed()
    advancing_collapse.on_configuration_changed()
    caverns.scheduled.on_configuration_changed()
    caverns.progression.on_configuration_changed()
    region_features.on_configuration_changed()
    world.on_configuration_changed()
    ore_protection.on_init()
    ore_missing.on_configuration_changed()
    drill_filter.on_configuration_changed()
    train_interiors.on_configuration_changed()
    shelter_core.on_configuration_changed()
    if ore_veins.on_init then ore_veins.on_init() end
    mobile_factory_resources.on_configuration_changed()
    bob_ores_resources.on_configuration_changed()
    bob_enemies.on_configuration_changed()
    if not storage.pending_collapses then collapse.on_init() end
    roof_support.rebuild()
    roof_support_mining.initialize()
    collapse.cancel_roof_jobs()
    -- ADR 0008: the stress ledger is gone; clear dead state from old saves.
    storage.stress = nil
    storage.new_tiles = nil
    storage.support_reach = nil
    storage.collapse_log = storage.collapse_log or {}
    storage.warn_renders = storage.warn_renders or {}
    storage.telegraphs = storage.telegraphs or {}
    collapse.cleanup_disabled_state()
    collapse.cleanup_exempt_state()
    -- Retire every legacy ALT-mode stress triangle. Normal players only see
    -- the boxed countdown after a collapse has actually been scheduled.
    collapse.clear_warning_markers()
    caverns.on_configuration_changed()
    uranium_caves.on_configuration_changed()
    mineral_caves.on_configuration_changed()
    lost_city.on_configuration_changed()
    fortified_vaults.on_configuration_changed()
    cave_evolution.sync_all()
    pop_text.on_init()
    depth_levels.on_init()
    enemy_nest_growth.on_configuration_changed()
    dig_spawner.on_configuration_changed()
    cave_enemy_expansion.on_configuration_changed()
    dig_spawner.apply_expansion_setting()
    make_cave_dark()
    market_coin.on_configuration_changed()
    coin_maker.on_configuration_changed()
    enemy_brood_split.on_configuration_changed()
    equipment_grid_upgrades.on_configuration_changed()
    wind_turbine.on_configuration_changed()
    cave_accumulator_visuals.on_configuration_changed()
    lamp_pole.on_configuration_changed()
    warp_outpost.on_configuration_changed()
    inventory_repair.on_configuration_changed()
    turret_range.on_configuration_changed()
    underground_belt_reach.on_configuration_changed()
    underground_pipe_reach.on_configuration_changed()
    underground_world_sync.on_configuration_changed()
    underground_blueprints.on_configuration_changed()
    for _,player in pairs(game.players) do
        underground_item_ui.on_inventory_changed{player_index=player.index}
        underground_item_ui.on_quickbar_changed{player_index=player.index}
    end
    offline_player_body.on_configuration_changed()
    faster_start.on_configuration_changed()
    starter_pack.on_configuration_changed()
    starting_inventory.on_configuration_changed()
    chemical_rockets.on_configuration_changed()
    belt_stack_sync.on_configuration_changed()
    if the_cave_damage_indicator_enabled() then
        cave_damage_indicator.on_configuration_changed()
    else
        cave_damage_indicator.cleanup_legacy_shared_state()
    end

    -- Retire the old screen-frame countdown (replaced by world pop texts).
    for _, player in pairs(game.players) do
        local frame = player.gui.screen["diggy-cavern-countdown"]
        if frame then frame.destroy() end
    end

    -- Clear crash-site debris from saves created before it was disabled.
    local nauvis = game.surfaces["nauvis"]
    if nauvis and nauvis.valid then
        for _, entity in pairs(nauvis.find_entities_filtered { area = { { -80, -80 }, { 80, 80 } } }) do
            if entity.valid and entity.name:find("crash%-site") then
                entity.destroy()
            end
        end
    end

    -- Heal saves that doubled the spawn ring on copied team surfaces (the
    -- ensure_chunk -> build_chunk rebuild, fixed in world.build_chunk). The
    -- duplicates only ever land in the carve-out, so a tight per-surface
    -- sweep removes the extra cover, keeping one per tile.
    local removed = 0
    for _, surface in pairs(game.surfaces) do
        if surface.valid then
            local seen = {}
            for _, e in pairs(surface.find_entities_filtered {
                name = { "diggy-rock", "diggy-tree", "diggy-rubble" },
                area = { { -64, -64 }, { 64, 64 } },
            }) do
                local key = math.floor(e.position.x) .. "," .. math.floor(e.position.y)
                if seen[key] then
                    e.destroy()
                    removed = removed + 1
                else
                    seen[key] = true
                end
            end
        end
    end
    if removed > 0 then
        log("[DIGGY] removed " .. removed .. " duplicated spawn-ring cover entities")
    end

    -- Saves store runtime settings, so defaults shipped by old releases stick
    -- forever. Rebase saves still on the exact old shipped defaults (the
    -- "every rock spawns biters" era) to the current ones; custom values are
    -- left untouched.
    local rebase = {
        ["diggy-dig-biter-chance"] = { old = { [1.0] = true, [0.1] = true, [0.015] = true }, new = 0.045 },
        ["diggy-dig-nest-chance"] = { old = { [0.1] = true, [0.01] = true, [0.002] = true, [0.05] = true, [0.02] = true }, new = 0 },
        ["diggy-cavern-worm-multiplier"] = { old = { [1.0] = true, [2.0] = true, [1.5] = true }, new = 1.0 },
        ["diggy-cavern-chance"] = { old = { [0.02] = true, [0.03] = true }, new = 0.05 },
        ["diggy-treasure-chance"] = { old = { [0.004] = true }, new = 0.005 },
        ["diggy-pack-size-multiplier"] = { old = { [1.0] = true, [2.0] = true }, new = 3.0 },
        ["diggy-collapse-broadcast"] = { old = { [true] = true }, new = false },
        -- The support-economy levers settled on tuned defaults (1.5 catches
        -- the old strut default clamped into the new range).
        ["diggy-wall-support"] = { old = { [5] = true }, new = 3 },
        ["diggy-strut-strength-max"] = { old = { [2] = true, [1.5] = true }, new = 1 },
        ["diggy-wall-crowding"] = { old = { [1] = true }, new = 1.2 },
    }
    for name, r in pairs(rebase) do
        if r.old[settings.global[name].value] then
            settings.global[name] = { value = r.new }
            game.print({ "diggy.setting-rebased", { "mod-setting-name." .. name }, tostring(r.new) })
        end
    end
    inserter_config.on_configuration_changed()
    darkness_infestation.on_configuration_changed()
    welcome_gui.on_configuration_changed()
    information_gui.on_configuration_changed()
    teleport.on_configuration_changed()
    minimal_wire.on_configuration_changed()
    portable_tanks.on_configuration_changed()
    tnt_boxes.on_configuration_changed()
    game_settings.apply_to_forces()
    game_settings.cancel_advancing_train_crafting()
end)

local COVER = { ["diggy-rock"] = true, ["diggy-rubble"] = true }

-- Restrict the resource/extraction exception to damage whose immediate runtime
-- cause is a Demolisher head, segment or Demolisher-owned attack prototype.
-- Name matching covers all three vanilla sizes and their segmented/effect
-- prototypes without probing optional Space Age prototypes during script load.
local function demolisher_dig_context(event)
    if not (event and event.name == defines.events.on_entity_died) then return false end
    local cause = event.cause
    if not (cause and cause.valid) then return false end

    local cause_name = cause.name
    if type(cause_name) ~= "string" or not cause_name:find("demolisher", 1, true) then
        return false
    end

    local orientation = 0
    pcall(function() orientation = tonumber(cause.orientation) or 0 end)
    orientation = orientation % 1
    local cardinal = math.floor(orientation * 4 + 0.5) % 4
    local directions = {
        [0] = { 0, -1 }, -- north
        [1] = { 1, 0 },  -- east
        [2] = { 0, 1 },  -- south
        [3] = { -1, 0 }, -- west
    }

    -- The side chamber starts at least 32 tiles from the body line. Widen that
    -- clearance automatically if a future Demolisher prototype has a larger
    -- collision box.
    local clearance = 32
    pcall(function()
        local box = cause.prototype and cause.prototype.collision_box
        if box and box.left_top and box.right_bottom then
            local width = math.max(
                math.abs(box.left_top.x), math.abs(box.right_bottom.x),
                math.abs(box.left_top.y), math.abs(box.right_bottom.y)
            )
            clearance = math.max(clearance, math.ceil(width + 20))
        end
    end)
    return true, directions[cardinal], clearance
end

-- Shared by real cover deaths and by the rare emergency floor repair beneath
-- a segmented body.  Resources are deterministic per tile.  Extraction
-- resolution is optional so the repair can preserve one opportunity per body
-- node without treating every collision-width floor tile as a separate room.
local function preserve_demolisher_tile(dig, allow_extraction)
    ore_veins.on_dig(dig)
    region_features.on_dig(dig)
    mobile_factory_resources.on_dig(dig)
    bob_ores_resources.on_dig(dig)
    if not allow_extraction then return end

    local extraction_opened, room_plan, room_label = caverns.on_demolisher_dig(dig)
    if not extraction_opened then return end
    local uranium_created = uranium_caves.on_cavern_opened(dig, room_plan, room_label) == true
    local mineral_created = mineral_caves.on_cavern_opened(dig, room_plan, room_label) == true
    caverns.on_uranium_entrance_result(dig, room_plan, uranium_created)
    caverns.on_mineral_entrance_result(dig, room_plan, mineral_created)
    if (uranium_created or mineral_created) and dig.force then
        dig.force.chart(dig.surface, {
            { room_plan.x1 - 2, room_plan.y1 - 2 },
            { room_plan.x2 + 2, room_plan.y2 + 2 },
        })
    end
end

-- A dig is the death/mining of a cover entity. Snapshot the context up front:
-- handlers may invalidate the dying entity as a side effect, so none of them
-- touch it directly.
local function resolve_dig(dig)
    if not (dig.surface and dig.surface.valid and dig.force and dig.force.valid) then return end
    uranium_caves.prepare_dig(dig)
    mineral_caves.prepare_dig(dig)
    -- The cover entity is leaving the world (the engine removes it after
    -- this event resolves — the mirror must not wait for that).
    -- Rubble re-digs are inert: stress and charting only. The tile's
    -- seed-keyed outcomes (vein, spawns, cavern, treasure, ore yield) fired
    -- when it FIRST opened; re-rolling them respawned the same worms and
    -- re-announced the same tunnels forever.
    if dig.name == "diggy-rubble" then
        collapse.evaluate_around(dig.surface, dig.position, nil, dig.player_index)
        if dig.direct_player_mining or dig.is_tnt_box_dig then charting.on_dig(dig) end
        return
    end

    -- Non-player tunnel-carve mode. Ordinary causes remain geometry-only. A
    -- verified Demolisher additionally materializes deterministic resources on
    -- the exact destroyed tile and may preserve an extraction cave in a safe
    -- side chamber; all ordinary/special rooms and hostile outcomes stay off.
    if not dig.allow_dig_outcomes then
        world.on_dig(dig)
        if dig.is_demolisher then
            preserve_demolisher_tile(dig, true)
        end
        warp_outpost.enforce_enemy_safe_zone_now(dig.surface, dig.position, "post-dig")
        collapse.evaluate_around(dig.surface, dig.position, nil, dig.player_index)
        return
    end

    dig_tracker.on_dig(dig)
    depth_levels.on_dig(dig)
    world.on_dig(dig) -- stress + frontier advance
    if dig.is_uranium_cave then
        uranium_caves.materialize_uranium(dig.surface,
            math.floor(dig.position.x), math.floor(dig.position.y), dig.force)
    elseif dig.is_mineral_cave then
        mineral_caves.materialize_mineral(dig.surface,
            math.floor(dig.position.x), math.floor(dig.position.y), dig.force)
    else
        ore_veins.on_dig(dig)
        region_features.on_dig(dig)
        mobile_factory_resources.on_dig(dig)
        bob_ores_resources.on_dig(dig)
        treasure.on_dig(dig)
    end
    -- Resolve cavern/room generation first. If this rock opened a room, the
    -- room's fixed threat budget is the only combat generated by this dig.
    local room_opened, room_plan, room_label = caverns.on_dig(dig)
    mobile_factory_resources.on_post_dig(dig, room_plan)
    bob_ores_resources.on_post_dig(dig, room_plan)
    dig.room_opened = room_opened == true
    if dig.room_opened then
        local uranium_created = uranium_caves.on_cavern_opened(dig, room_plan, room_label) == true
        local mineral_created = mineral_caves.on_cavern_opened(dig, room_plan, room_label)
        local lost_city_created = lost_city.on_cavern_opened(dig, room_plan, room_label) == true
        caverns.on_uranium_entrance_result(dig, room_plan, uranium_created)
        caverns.on_mineral_entrance_result(dig, room_plan, mineral_created == true)
        caverns.on_lost_city_entrance_result(dig, room_plan, lost_city_created)
    end
    if dig.allow_hostile_spawns and not dig.room_opened then
        dig_spawner.on_dig(dig)
    end
    threats.on_dig(dig)
    advancing_recovery.enforce_surface(dig.surface)
    charting.on_dig(dig)
    warp_outpost.enforce_enemy_safe_zone_now(dig.surface, dig.position, "post-dig")
    -- Geometry changed: re-evaluate stress around the dig (after the
    -- frontier advance and any carving, so the world is current).
    collapse.evaluate_around(dig.surface, dig.position, nil, dig.player_index)
end

local function on_dig(event)
    local entity = event.entity
    if not (entity and entity.valid) then return end
    local weapon = weapon_digging.death_context(event)
    local is_demolisher, direction, clearance = demolisher_dig_context(event)
    local force = weapon and weapon.force or event.force
    if not force and event.player_index then
        local player = game.get_player(event.player_index)
        force = player and player.force
    end
    if not force or not force.valid or force.name == "neutral" or force.name == "enemy" then
        force = cave_teams.owner_force(entity.surface)
    end
    local direct = event.name == defines.events.on_player_mined_entity and event.player_index ~= nil
    local queen = event.name == defines.events.on_entity_died and entity.name == "diggy-rock"
        and enemy_nest_growth.is_active_queen(event.cause)
    local tnt = event.the_cave_tnt_box == true
    local full = (direct and entity.name == "diggy-rock") or queen or tnt or weapon ~= nil
    local dig = {surface = entity.surface, position = entity.position, name = entity.name,
        force = force, player_index = event.player_index or (weapon and weapon.player_index),
        direct_player_mining = direct, is_queen_dig = queen, is_tnt_box_dig = tnt,
        is_demolisher = is_demolisher == true, demolisher_direction = direction,
        demolisher_clearance = clearance, suppress_discovery_messages = is_demolisher == true,
        allow_hostile_spawns = full, allow_room_generation = full, allow_dig_outcomes = full,
        is_tank_dig = weapon and weapon.kind == "tank" or false,
        is_atomic_dig = weapon and weapon.kind == "atomic" or false}
    mirror.set_rock(dig.surface, dig.position, false)
    if dig.is_atomic_dig then
        -- Open only the geometry during the blast. Resources, rooms, enemy
        -- pressure and treasure resolve once the damaging waves have ended.
        world.on_dig(dig)
        weapon_digging.enqueue(dig)
        return
    end
    resolve_dig(dig)
end

weapon_digging.configure {on_dig = resolve_dig}

-- TNT Boxes use the exact normal Dig pipeline without a mining buffer. This
-- preserves rooms, caves, resources and enemy pressure while giving no mined
-- stone/item result for the cover entities destroyed by the blast.
tnt_boxes.configure { on_dig = on_dig }

local DEMOLISHER_ENVELOPE_PLAYER_RADIUS_SQUARED = 256 * 256

local function segmented_unit_reference_position(segmented_unit)
    local position
    pcall(function()
        local nodes = segmented_unit.get_body_nodes()
        position = nodes and nodes[1]
    end)
    return position
end

local function segmented_unit_near_players(segmented_unit, players)
    local position = segmented_unit_reference_position(segmented_unit)
    if not position then return false end
    for _, player in ipairs(players) do
        local dx = player.position.x - position.x
        local dy = player.position.y - position.y
        if dx * dx + dy * dy <= DEMOLISHER_ENVELOPE_PLAYER_RADIUS_SQUARED then return true end
    end
    return false
end

local function repair_nearby_demolisher_envelopes()
    -- No connected observer means no terrain work.  Group players first so
    -- each occupied surface performs at most one segmented-unit query.
    local players_by_surface = {}
    for _, player in pairs(game.connected_players or {}) do
        if player and player.valid and player.surface and player.surface.valid
            and cave_teams.is_world_running(player.surface) then
            local index = player.surface.index
            players_by_surface[index] = players_by_surface[index] or {}
            players_by_surface[index][#players_by_surface[index] + 1] = player
        end
    end

    for surface_index, players in pairs(players_by_surface) do
        local surface = game.surfaces[surface_index]
        if surface and surface.valid then
            local ok, units = pcall(function() return surface.get_segmented_units() end)
            if ok and units then
                for _, segmented_unit in pairs(units) do
                    if segmented_unit_near_players(segmented_unit, players) then
                        local repair = world.ensure_demolisher_envelope(surface, segmented_unit)
                        if repair and repair.opened and #repair.opened > 0 then
                            local opportunities = {}
                            for _, position in ipairs(repair.opportunities or {}) do
                                opportunities[position.x .. "," .. position.y] = true
                            end
                            local force = cave_teams.owner_force(surface)
                            for _, position in ipairs(repair.opened) do
                                local dig = {
                                    surface = surface,
                                    position = { x = position.x + 0.5, y = position.y + 0.5 },
                                    name = "out-of-map",
                                    force = force,
                                    direct_player_mining = false,
                                    allow_hostile_spawns = false,
                                    allow_room_generation = false,
                                    allow_dig_outcomes = false,
                                    is_demolisher = true,
                                    demolisher_direction = repair.direction,
                                    demolisher_clearance = repair.clearance,
                                    suppress_discovery_messages = true,
                                }
                                uranium_caves.prepare_dig(dig)
                                mineral_caves.prepare_dig(dig)
                                preserve_demolisher_tile(
                                    dig,
                                    opportunities[position.x .. "," .. position.y] == true
                                )
                            end
                        end
                    end
                end
            end
        end
    end
end

-- Public API (ADR 0002 door #2): external mods register declarative threat
-- specs; rolls are seed-keyed like everything else.
remote.add_interface("diggy-v1", {
    register_threat = threats.register_external,
    -- Headless test hooks (used by the maintainer's automated benchmarks).
    debug_sim = function(bare) sim.start(nil, bare) end,
    debug_sim_stop = function() sim.stop(nil) end,
    debug_max_stress = function(surface_index, x1, y1, x2, y2)
        return collapse.max_in_area(game.surfaces[surface_index], x1, y1, x2, y2)
    end,
    -- Exactness proof for the mirror's event coverage (ADR 0009).
    debug_mirror_check = function(surface_index, x1, y1, x2, y2)
        return mirror.check(game.surfaces[surface_index], x1, y1, x2, y2)
    end,
    -- Drift probe for the layer-2 stress cache (ADR 0009).
    debug_cache_check = function(surface_index, x1, y1, x2, y2)
        return collapse.cache_check(game.surfaces[surface_index], x1, y1, x2, y2)
    end,
    debug_protected = function(surface_index, x, y)
        return collapse.is_protected(game.surfaces[surface_index], x, y)
    end,
    debug_roof_tile = function(surface_index, x, y)
        return roof_support.is_tile_protected(game.surfaces[surface_index], x, y)
    end,
    debug_roof_bounds = roof_support.bounds,
    debug_roof_stats = roof_support.debug_stats,
    debug_roof_preview = roof_support.draw_preview,
    debug_roof_preview_view = function(key, surface_index, area)
        return roof_support.sync_view(key, game.surfaces[surface_index], area)
    end,
    debug_roof_preview_clear = roof_support.clear_preview,
    debug_sell_items = market_coin.debug_sell_items,
    debug_evaluate_collapse = function(surface_index, x, y, radius)
        collapse.evaluate_around(game.surfaces[surface_index], {x = x, y = y}, radius)
    end,
    debug_sparse_collapse = function(surface_index, cells, seed)
        return collapse.sparse_collapse(game.surfaces[surface_index], cells, game.forces.player, seed)
    end,
    debug_pending_collapses = function(surface_index)
        local result = {}
        for _, p in ipairs(storage.pending_collapses or {}) do
            if p.surface_index == surface_index then
                result[#result + 1] = {x = p.x, y = p.y, at_tick = p.at_tick}
            end
        end
        return result
    end,
})

-- Covers dig; other support entities (walls, reactors) feed the stress map.
local removal_filter = {}
for _, name in pairs(collapse.SUPPORT_NAMES) do
    removal_filter[#removal_filter + 1] = { filter = "name", name = name }
end
for _, name in ipairs(roof_support.names) do
    removal_filter[#removal_filter + 1] = {filter = "name", name = name}
end
for _, name in pairs({ "small-worm-turret", "medium-worm-turret", "big-worm-turret", "behemoth-worm-turret" }) do
    removal_filter[#removal_filter + 1] = { filter = "name", name = name }
end
local ARACHNID_NEST = "arachnid-spawner-unitspawner"
local NESTS = {
    ["biter-spawner"] = true,
    ["spitter-spawner"] = true,
    [ARACHNID_NEST] = true,
}
if prototypes and prototypes.entity and prototypes.entity["armoured-biter-spawner"] then
    -- Removal/collapse tracking only. Armoured nests and their units remain
    -- intentionally absent from every coin and Ore Blood allow-list.
    NESTS["armoured-biter-spawner"] = true
end
if script.active_mods["space-age"] then
    NESTS["gleba-spawner"] = true
    NESTS["small-gleba-spawner"] = true
    NESTS["medium-gleba-spawner"] = true
    NESTS["big-gleba-spawner"] = true
end
for name in pairs(NESTS) do
    if prototypes and prototypes.entity and prototypes.entity[name] then
        removal_filter[#removal_filter + 1] = { filter = "name", name = name }
    end
end
for name in pairs((prototypes and prototypes.entity) or {}) do
    if lost_city.is_house_name(name) then
        removal_filter[#removal_filter + 1] = { filter = "name", name = name }
    end
end
if portable_tanks.is_enabled() then
    removal_filter[#removal_filter + 1] = {
        filter = "name",
        name = portable_tanks.base_tank_name,
    }
end
for _, name in ipairs(portable_cave_accumulators.entity_names) do
    removal_filter[#removal_filter + 1] = {filter = "name", name = name}
end
for _, name in ipairs(tnt_boxes.entity_names) do
    if prototypes and prototypes.entity and prototypes.entity[name] then
        removal_filter[#removal_filter + 1] = { filter = "name", name = name }
    end
end

-- Registered cavern guardians can arm their room (see caverns.on_worm_died).
-- Arachnid spawners are tracked only when they belong to a dedicated room.
local CAVERN_GUARDIANS = {
    ["small-worm-turret"] = true,
    ["medium-worm-turret"] = true,
    ["big-worm-turret"] = true,
    ["behemoth-worm-turret"] = true,
    [ARACHNID_NEST] = true,
}
-- Optional prototypes are added only while Bob's Enemies is actually active.
-- Removal and room-collapse events must see every one of its eight worm tiers.
for _, name in ipairs(bob_enemies.nest_names()) do
    NESTS[name] = true
    removal_filter[#removal_filter + 1] = { filter = "name", name = name }
end
for _, name in ipairs(bob_enemies.worm_names()) do
    CAVERN_GUARDIANS[name] = true
    removal_filter[#removal_filter + 1] = { filter = "name", name = name }
end

local function on_removed(event)
    local entity = event.entity
    if roof_support.is_support(entity) then
        roof_support_mining.on_removed(entity)
        reevaluate_removed_roof(roof_support.remove(entity), event.player_index)
        return
    elseif tnt_boxes.on_removed(event) then
        return
    elseif portable_cave_accumulators.is_supported(entity) then
        if event.name == defines.events.on_player_mined_entity
            or event.name == defines.events.on_robot_mined_entity then
            portable_cave_accumulators.on_mined(event)
        end
    elseif entity.name == portable_tanks.base_tank_name then
        if event.name == defines.events.on_player_mined_entity
            or event.name == defines.events.on_robot_mined_entity then
            portable_tanks.on_mined(event)
        end
    elseif lost_city.is_house_name(entity.name) then
        if event.name == defines.events.on_player_mined_entity
            or event.name == defines.events.on_robot_mined_entity then
            lost_city.on_house_mined(event)
        end
    elseif COVER[entity.name] then
        if event.buffer then
            dig_yield.on_player_mined(event)
        end
        on_dig(event)
    elseif CAVERN_GUARDIANS[entity.name] then
        caverns.on_worm_died(entity)
    elseif NESTS[entity.name] then
        region_features.on_gleba_nest_removed(entity, event.buffer)
        dig_spawner.on_nest_died(entity)
    else
        -- A wall or reactor: gone from the mirror first, then re-evaluate
        -- everything its live reach was holding up.
        mirror.support_removed(entity)
        collapse.evaluate_around(entity.surface, entity.position,
            collapse.reach_radius(entity.force), event.player_index)
    end
end

local REMOVAL_NAME_SET = {}
for _, f in pairs(removal_filter) do
    if f.name then REMOVAL_NAME_SET[f.name] = true end
end

local function on_entity_died_combined(event)
    advancing_collapse.on_entity_died(event)
    lamp_pole.on_removed(event)
    cave_enemy_expansion.on_entity_died(event)
    enemy_nest_growth.on_entity_died(event)
    fortified_vaults.on_entity_died(event)
    cave_evolution.on_enemy_spawner_died(event)
    if event.entity then minimal_wire.on_removed(event.entity) end
    local suppress_brood_rewards = enemy_brood_split.on_entity_died(event)
    market_coin.on_entity_died(event, suppress_brood_rewards)
    ore_blood.on_entity_died(event, suppress_brood_rewards)
    if warp_outpost.check_main_train_part_destroyed and event and event.entity then
        warp_outpost.check_main_train_part_destroyed(event.entity)
    end
    shelter_core.on_entity_died(event)
    train_interiors.on_entity_died(event)
    warp_outpost.check_main_train_defeat()
    if the_cave_damage_indicator_enabled() then cave_damage_indicator.on_entity_gone(event) end
    if event.entity and event.entity.valid and REMOVAL_NAME_SET[event.entity.name] then
        on_removed(event)
    end
end

script.on_event(defines.events.on_player_mined_entity, on_removed, removal_filter)
script.on_event(defines.events.on_robot_mined_entity, on_removed, removal_filter)
if defines.events.on_space_platform_mined_entity then
    local platform_mining_filter = {}
    for _, name in ipairs(portable_cave_accumulators.entity_names) do
        platform_mining_filter[#platform_mining_filter + 1] = {filter = "name", name = name}
    end
    if portable_tanks.is_enabled() then
        platform_mining_filter[#platform_mining_filter + 1] = {filter = "name", name = portable_tanks.base_tank_name}
    end
    script.on_event(
        defines.events.on_space_platform_mined_entity,
        function(event)
            if portable_cave_accumulators.is_supported(event.entity) then
                portable_cave_accumulators.on_mined(event)
            else
                portable_tanks.on_mined(event)
            end
        end,
        platform_mining_filter
    )
end
script.on_event(defines.events.on_entity_died, on_entity_died_combined)
script.on_event(defines.events.on_object_destroyed, function(event)
    reevaluate_removed_roof(roof_support.on_object_destroyed(event))
    enemy_brood_split.on_object_destroyed(event)
    cave_accumulator_visuals.on_object_destroyed(event)
    lamp_pole.on_object_destroyed(event)
end)
script.on_event(
    defines.events.on_ai_command_completed,
    function(event)
        if soft_reset.is_active() or main_train_defeat.blocks_all() then return end
        cave_enemy_expansion.on_ai_command_completed(event)
    end
)

-- Integrated Damage Indicator event hooks (Dummiez, GPLv3; routed through The Cave control.lua).
script.on_event(defines.events.on_entity_damaged, function(event)
    weapon_digging.on_entity_damaged(event)
    enemy_nest_growth.on_entity_damaged(event)
    local shelter_damage_ignored = shelter_core.on_entity_damaged(event) == true
    local damage_ignored = shelter_damage_ignored or train_interiors.on_entity_damaged(event) == true
    if not damage_ignored and the_cave_damage_indicator_enabled() then
        cave_damage_indicator.on_entity_damaged(event)
    end
    -- Apply the Queen's cover-only bonus after other damage consumers have
    -- observed the engine's original hit. A lethal bonus raises the ordinary
    -- on_entity_died path with the Queen preserved as the cause.
    enemy_nest_growth.apply_queen_cover_damage(event)
end, {
    { filter = "final-damage-amount", comparison = ">", value = 0 }
})
script.on_event(defines.events.on_pre_player_mined_item, function(event)
    minimal_wire.on_pre_removed(event.entity)
    train_interiors.on_entity_removed(event.entity)
    if the_cave_damage_indicator_enabled() then cave_damage_indicator.on_entity_gone(event) end
end)
script.on_event(defines.events.on_robot_pre_mined, function(event)
    minimal_wire.on_pre_removed(event.entity)
    train_interiors.on_entity_removed(event.entity)
    if the_cave_damage_indicator_enabled() then cave_damage_indicator.on_entity_gone(event) end
end)
script.on_event(defines.events.script_raised_destroy, function(event)
    if roof_support.is_support(event.entity) then on_removed(event) end
    lamp_pole.on_removed(event)
    if event.entity then minimal_wire.on_removed(event.entity) end
    if the_cave_damage_indicator_enabled() then cave_damage_indicator.on_entity_gone(event) end
end)
script.on_event(defines.events.on_script_trigger_effect, function(event)
    weapon_digging.on_script_trigger_effect(event)
    lamp_pole.on_created(event)
    if the_cave_damage_indicator_enabled() then cave_damage_indicator.on_script_trigger_effect(event) end
end)
script.on_event(defines.events.on_player_removed, function(event)
    roof_support.clear_preview(event.player_index)
    roof_support_mining.clear(event.player_index)
    starting_inventory.on_player_removed(event)
    underground_belt_reach.on_player_removed(event)
    underground_pipe_reach.on_player_removed(event)
    darkness_infestation.on_player_removed(event)
    offline_player_body.on_player_removed(event)
    teleport.on_player_removed(event)
    tnt_boxes.on_player_removed(event)
    if the_cave_damage_indicator_enabled() then cave_damage_indicator.on_player_removed(event) end
end)
script.on_event(defines.events.on_gui_closed, function(event)
    underground_belt_reach.on_gui_closed(event)
    underground_pipe_reach.on_gui_closed(event)
    underground_blueprints.queue(event)
    inserter_config.on_gui_closed(event)
    drill_filter.on_gui_closed(event)
    market_coin.on_gui_closed(event)
    welcome_gui.on_gui_closed(event)
    information_gui.on_gui_closed(event)
    teleport.on_gui_closed(event)
    if the_cave_damage_indicator_enabled() then cave_damage_indicator.on_gui_closed(event) end
end)
script.on_event(defines.events.on_player_changed_position, function(event)
    roof_support.on_context_changed(event)
    roof_support_mining.on_context_changed(event)
    fortified_vaults.on_player_changed_position(event)
    train_interiors.on_player_changed_position(event)
    shelter_core.on_player_changed_position(event)
    if the_cave_damage_indicator_enabled() then cave_damage_indicator.on_player_changed_position(event) end
end)

local SUPPORT_BUILD_NAMES = {
    ["stone-wall"] = true,
    ["nuclear-reactor"] = true,
}

local function on_built(event)
    local entity = event.entity or event.created_entity
    if not (entity and entity.valid) then return end
    interior_maintenance.on_built(entity)

    if tnt_boxes.on_built(event) then return end

    local portable_placement = event.name == defines.events.on_built_entity
        or event.name == defines.events.on_robot_built_entity
    if portable_placement and portable_tanks.on_built(event) then return end
    if not entity.valid then return end

    if shelter_core.on_built(event) then return end

    -- Ore Patch Protection must run before support bookkeeping. If it destroys
    -- the new entity/ghost, no other build-side systems should touch it.
    if ore_protection.on_built(event, portable_cave_accumulators.refund_placement) then return end
    if not entity.valid then return end

    if roof_support.is_support(entity) then
        if roof_support.add(entity) then collapse.cancel_roof_jobs() end
        roof_support.refresh_previews()
    end

    if SUPPORT_BUILD_NAMES[entity.name] then
        mirror.support_added(entity)
        collapse.evaluate_around(entity.surface, entity.position, collapse.reach_radius(entity.force))
    end

    equipment_grid_upgrades.on_built(event)
    if not entity.valid then return end

    drill_filter.on_built(event)
    if not entity.valid then return end

    train_interiors.on_built(event)
    if not entity.valid then return end

    wind_turbine.on_built(event)
    if not entity.valid then return end

    gun_turret_autoload.on_built(event)
    if not entity.valid then return end

    -- Turret Range can replace the just-built Gun Turret with a hidden range
    -- variant. Load ammunition first; its transactional replacement preserves
    -- the inventory while keeping robot/script builds untouched.
    turret_range.on_built(event)
    if not entity.valid then return end

    underground_world_sync.on_built(event)
    underground_belt_reach.on_built(event)
    if not entity.valid then return end

    underground_pipe_reach.on_built(event)
    if not entity.valid then return end

    extra_storage_tanks.on_built(event)
    if not entity.valid then return end

    if entity.valid then industrial_loaders.on_built(event) end
    if entity.valid then minimal_wire.on_built(entity) end
    if (portable_placement or portable_cave_accumulators.is_placement(entity))
        and portable_cave_accumulators.on_built(event) then return end
    if entity.valid then cave_accumulator_visuals.on_built(event) end
    if entity.valid then lamp_pole.on_built(event) end
    if entity.valid then coin_maker.on_built(event) end
end

script.on_event(defines.events.on_built_entity, on_built)
script.on_event(defines.events.on_robot_built_entity, on_built)
script.on_event(defines.events.script_raised_built, on_built)
script.on_event(defines.events.script_raised_revive, on_built)
script.on_event(defines.events.on_area_cloned, cave_lifecycle.on_area_cloned)
if defines.events.on_entity_cloned then
    script.on_event(defines.events.on_entity_cloned, function(event)
        train_interiors.on_entity_cloned(event)
        interior_maintenance.on_built(event.destination)
        if roof_support.is_support(event.destination) then
            roof_support.add(event.destination)
            collapse.cancel_roof_jobs()
        end
        if tnt_boxes.on_built(event) then return end
        wind_turbine.on_entity_cloned(event)
        cave_accumulator_visuals.on_built(event)
        lamp_pole.on_entity_cloned(event)
        coin_maker.on_built(event)
        if event.destination and event.destination.valid then
            minimal_wire.on_built(event.destination)
        end
    end)
end
if defines.events.on_space_platform_built_entity then
    script.on_event(defines.events.on_space_platform_built_entity, function(event)
        local entity = event.entity or event.created_entity
        if not (entity and entity.valid) then return end
        if tnt_boxes.on_built(event) then return end
        if portable_tanks.on_built(event) then return end
        if not entity.valid then return end
        wind_turbine.on_built(event)
        if not entity.valid then return end
        underground_belt_reach.on_built(event)
        if entity.valid then underground_pipe_reach.on_built(event) end
        if entity.valid then extra_storage_tanks.on_built(event) end
        if entity.valid then industrial_loaders.on_built(event) end
        if entity.valid then minimal_wire.on_built(entity) end
        if portable_cave_accumulators.on_built(event) then return end
        if entity.valid then cave_accumulator_visuals.on_built(event) end
        if entity.valid then lamp_pole.on_built(event) end
        if entity.valid then coin_maker.on_built(event) end
    end)
end
if defines.events.script_raised_teleported then
    script.on_event(defines.events.script_raised_teleported, function(event)
        if roof_support.is_support(event.entity) then
            local old = roof_support.remove(event.entity)
            roof_support.add(event.entity)
            collapse.cancel_roof_jobs()
            reevaluate_removed_roof(old)
        end
        lamp_pole.on_built(event)
    end)
end
script.on_event(defines.events.on_gui_opened, function(event)
    underground_belt_reach.on_gui_opened(event)
    underground_pipe_reach.on_gui_opened(event)
    underground_blueprints.on_gui_opened(event)
    if lost_city.on_gui_opened(event) then return end
    if uranium_caves.on_gui_opened(event) then return end
    if mineral_caves.on_gui_opened(event) then return end
    if fortified_vaults.on_gui_opened(event) then return end
    market_coin.on_gui_opened(event)
    inserter_config.on_gui_opened(event)
end)
if defines.events.on_player_display_resolution_changed then
    script.on_event(defines.events.on_player_display_resolution_changed, function(event)
        roof_support.on_context_changed(event)
        roof_support_mining.on_context_changed(event)
        market_coin.on_player_display_changed(event)
        advancing_collapse.on_display_changed(event)
    end)
end
if defines.events.on_player_display_scale_changed then
    script.on_event(defines.events.on_player_display_scale_changed, function(event)
        roof_support.on_context_changed(event)
        roof_support_mining.on_context_changed(event)
        market_coin.on_player_display_changed(event)
        advancing_collapse.on_display_changed(event)
    end)
end
script.on_event(defines.events.on_gui_click, function(event)
    if teleport.on_gui_click(event) then return end
    if shelter_core.on_gui_click(event) then return end
    lost_city.on_gui_click(event)
    inserter_config.on_gui_click(event)
    drill_filter.on_gui_click(event)
    market_coin.on_gui_click(event)
    train_interiors.on_gui_click(event)
    warp_outpost.on_gui_click(event)
    welcome_gui.on_gui_click(event)
    information_gui.on_gui_click(event)
    if the_cave_damage_indicator_enabled() then cave_damage_indicator.on_gui_click(event) end
end)
local function the_cave_on_player_selected_area(event)
    drill_filter.on_player_selected_area(event)
    resource_eraser.on_player_selected_area(event)
end

local function the_cave_on_player_alt_selected_area(event)
    drill_filter.on_player_selected_area(event)
    resource_eraser.on_player_alt_selected_area(event)
end

script.on_event(defines.events.on_player_selected_area, the_cave_on_player_selected_area)
if defines.events.on_player_alt_selected_area then
    script.on_event(defines.events.on_player_alt_selected_area, the_cave_on_player_alt_selected_area)
end
script.on_event(defines.events.on_gui_selection_state_changed, function(event)
    market_coin.on_gui_selection_state_changed(event)
    teleport.on_gui_selection_state_changed(event)
end)
script.on_event(defines.events.on_gui_switch_state_changed, teleport.on_gui_switch_state_changed)
script.on_event(defines.events.on_gui_text_changed, function(event)
    teleport.on_gui_text_changed(event)
end)
script.on_event(defines.events.on_selected_entity_changed, function(event)
    roof_support.on_selected(event)
    roof_support_mining.on_context_changed(event)
    market_coin.on_selected_entity_changed(event)
    train_interiors.on_selected_entity_changed(event)
    shelter_core.on_selected_entity_changed(event)
end)
if defines.events.on_entity_spawned then
    script.on_event(defines.events.on_entity_spawned, function(event)
        if event.entity and event.entity.valid
            and advancing_recovery.contains(event.entity.surface, event.entity.position) then
            advancing_recovery.enforce_surface(event.entity.surface)
            if not event.entity.valid then return end
        end
        advancing_collapse.on_entity_spawned(event)
        if not (event.entity and event.entity.valid) then return end
        region_features.on_entity_spawned(event)
        fortified_vaults.on_entity_spawned(event)
        market_coin.on_entity_spawned(event)
    end)
end

local function on_tiles_changed(surface, tiles, player_index)
    if fortified_vaults.on_tiles_changed(surface,tiles) then return end
    shelter_core.on_tiles_changed(surface, tiles)
    for _, t in pairs(tiles) do
        mirror.refresh_tile(surface, t.position)
        collapse.evaluate_around(surface, t.position, 3, player_index)
    end
    if train_interiors.on_tiles_changed then
        train_interiors.on_tiles_changed(surface, tiles)
    end
end
script.on_event(defines.events.on_player_built_tile, function(event)
    on_tiles_changed(game.surfaces[event.surface_index], event.tiles, event.player_index)
end)
script.on_event(defines.events.on_robot_built_tile, function(event)
    on_tiles_changed(event.robot.surface, event.tiles)
end)
script.on_event(defines.events.on_player_mined_tile, function(event)
    on_tiles_changed(game.surfaces[event.surface_index], event.tiles, event.player_index)
end)
script.on_event(defines.events.on_robot_mined_tile, function(event)
    on_tiles_changed(event.robot.surface, event.tiles)
end)
-- Other mods (MTS included) may re-tile script-side; stay current.
script.on_event(defines.events.script_raised_set_tiles, function(event)
    on_tiles_changed(game.surfaces[event.surface_index], event.tiles)
end)

script.on_nth_tick(6, coin_maker.on_nth_tick)
script.on_nth_tick(10, cave_accumulator_visuals.on_nth_tick)

script.on_nth_tick(30, function()
    if soft_reset.is_active() or main_train_defeat.blocks_all() then return end
    collapse.on_heartbeat()
    caverns.on_heartbeat()
    fulgora_lightning.sync_warning_icons()
    repair_nearby_demolisher_envelopes()
end)

-- Cave Miner-style player-centred darkness check (every 4 seconds).
script.on_nth_tick(240, function(event)
    if soft_reset.is_active() or main_train_defeat.blocks_all() then return end
    darkness_infestation.on_nth_tick(event)
end)
script.on_nth_tick(120, function(event)
    if soft_reset.is_active() or main_train_defeat.blocks_all() then return end
    fulgora_lightning.on_nth_tick(event)
end)
script.on_nth_tick(300, function(event)
    if soft_reset.is_active() or main_train_defeat.blocks_all() then return end
    cave_enemy_expansion.on_nth_tick(event)
end)

-- One handler for both 15-tick jobs: a second on_nth_tick(15) registration
-- would replace the first.
-- Roof supports: refresh only changed support views, reusing drawings and the
-- chunk index. Also catches zoom and cursor ghosts, for which there is no
-- mouse-move hook.
-- Player-local ALT-mode labels only. This reads the official turret-ammo
-- inventory and creates no entities, energy sources or persistent render state.
script.on_nth_tick(nearby_ammo_count.update_interval, function(event)
    roof_support.refresh_previews()
    nearby_ammo_count.on_nth_tick(event)
end)

if defines.events.on_force_friends_changed then
    script.on_event(defines.events.on_force_friends_changed, nearby_ammo_count.on_force_relationship_changed)
end
if defines.events.on_forces_merged then
    script.on_event(defines.events.on_forces_merged, function(event)
        -- Native ownership has changed; rebuild cached support facts before
        -- lifecycle cleanup can evaluate walls from the removed force.
        mirror.wipe()
        collapse.wipe_cache()
        -- Copy the source's progression rooms before the lifecycle clears it.
        caverns.progression.on_forces_merged(event)
        cave_lifecycle.on_forces_merged(event)
        nearby_ammo_count.on_force_relationship_changed(event)
        wind_turbine.on_forces_merged(event)
        underground_world_sync.enqueue(event.destination)
        underground_belt_reach.on_research_finished{research=event.destination.technologies["the-cave-underground-belt-reach-1"]}
        for _,player in pairs(event.destination.players) do underground_blueprints.queue{player_index=player.index} end
        game_settings.lock_advancing_train_recipes(event.destination)
        game_settings.apply_roof_support_research(event.destination)
        roof_support_mining.sync_force(event.destination)
        main_train_defeat.apply_truce()
    end)
end

-- Mirror housekeeping (ADR 0009). Wipe on join: every peer — including the
-- joiner, who starts empty — then derives identical cache content from
-- identical events, which is what lockstep requires of local caches.
script.on_event(defines.events.on_player_joined_game, function(event)
    local joining_player = game.get_player(event.player_index)
    main_train_defeat.on_player_joined(joining_player)
    if soft_reset.hold_player(joining_player) then return end
    train_interiors.on_player_joined_game(event)
    shelter_core.on_player_joined_game(event)
    underground_belt_reach.on_player_joined_game(event)
    underground_pipe_reach.on_player_joined_game(event)
    ore_missing.on_player_joined_game(event)
    market_coin.on_player_joined_game(event)
    equipment_grid_upgrades.on_player_joined_game(event)
    warp_outpost.on_player_joined_game(event)
    inventory_repair.on_player_joined_game(event)
    starting_inventory.on_player_ready(event)
    offline_player_body.on_player_joined_game(event)
    welcome_gui.on_player_joined_game(event)
    information_gui.on_player_joined_game(event)
    teleport.on_player_joined_game(event)
    advancing_collapse.on_player_joined_game(event)
    lost_city.on_player_changed_surface(event)
    mirror.wipe()
    collapse.wipe_cache()
    if the_cave_damage_indicator_enabled() then cave_damage_indicator.on_player_joined_game(event) end
    roof_support_mining.on_context_changed(event)
end)
local function retire_roof_surface(event)
    -- Retire the registry before engine destruction notifications, so each
    -- dying support does not schedule work on a surface being discarded.
    roof_support.drop_surface(event.surface_index)
    collapse.drop_surface_jobs(event.surface_index)
end
script.on_event(defines.events.on_pre_surface_deleted, function(event)
    cave_lifecycle.on_pre_surface_deleted(event)
    retire_roof_surface(event)
end)
script.on_event(defines.events.on_pre_surface_cleared, retire_roof_surface)
script.on_event(defines.events.on_surface_deleted, function(event)
    -- An earlier handler may already have reused the deleted surface index.
    if game.surfaces[event.surface_index] then return end
    cave_lifecycle.on_surface_deleted(event)
    roof_support.drop_surface(event.surface_index)
    collapse.drop_surface_jobs(event.surface_index)
    interior_maintenance.on_surface_deleted(event)
    lamp_pole.on_surface_removed(event)
    cave_accumulator_visuals.on_surface_removed(event)
    world.forget_surface_chunks(event.surface_index)
    advancing_collapse.on_surface_deleted(event)
    lost_city.on_surface_deleted(event)
    uranium_caves.on_surface_deleted(event)
    mineral_caves.on_surface_deleted(event)
    fortified_vaults.on_surface_deleted(event)
    mobile_factory_resources.on_surface_deleted(event)
    bob_ores_resources.on_surface_deleted(event)
    enemy_nest_growth.on_surface_deleted(event)
    cave_enemy_expansion.on_surface_deleted(event)
    caverns.on_surface_deleted(event)
    teleport.on_surface_deleted(event)
    tnt_boxes.on_surface_deleted(event)
    weapon_digging.on_surface_deleted(event)
    mirror.drop_surface(event.surface_index)
    collapse.drop_surface_cache(event.surface_index)
end)
script.on_event(defines.events.on_surface_cleared, function(event)
    roof_support.drop_surface(event.surface_index)
    collapse.drop_surface_jobs(event.surface_index)
    lamp_pole.on_surface_removed(event)
    cave_accumulator_visuals.on_surface_removed(event)
    world.forget_surface_chunks(event.surface_index)
    lost_city.on_surface_deleted(event)
    uranium_caves.on_surface_cleared(event)
    mineral_caves.on_surface_cleared(event)
    fortified_vaults.on_surface_deleted(event)
    mobile_factory_resources.on_surface_deleted(event)
    bob_ores_resources.on_surface_deleted(event)
    enemy_nest_growth.on_surface_deleted(event)
    cave_enemy_expansion.on_surface_deleted(event)
    caverns.on_surface_deleted(event)
    tnt_boxes.on_surface_deleted(event)
    weapon_digging.on_surface_deleted(event)
    mirror.drop_surface(event.surface_index)
    collapse.drop_surface_cache(event.surface_index)
end)
-- Two-strike chunk eviction keeps RAM bounded to active areas.
script.on_nth_tick(1800, function()
    mirror.sweep()
end)

local function on_research_finished(event)
    game_settings.on_roof_support_research(event)
    if event.research then roof_support_mining.sync_force(event.research.force) end
    advancing_collapse.on_research_finished(event)
    market_coin.on_research_finished(event)
    equipment_grid_upgrades.on_research_finished(event)
    wind_turbine.on_research_finished(event)
    train_interiors.on_research_finished(event)
    shelter_core.on_research_finished(event)
    warp_outpost.on_research_finished(event)
    turret_range.on_research_finished(event)
    underground_belt_reach.on_research_finished(event)
    underground_pipe_reach.on_research_finished(event)
    underground_world_sync.on_research_finished(event)
    underground_blueprints.on_research_finished(event)
    belt_stack_sync.on_research_finished(event)
    inserter_config.on_research_finished(event)
    teleport.on_research_finished(event)
    -- Safety net for upgraded/in-progress saves: if Fluid Wagon research ever
    -- completes while a Train mode is active, immediately reapply the force-local
    -- technology and recipe locks after Factorio processes its unlock effects.
    if event.research and event.research.name == "fluid-wagon" then
        game_settings.apply_to_forces()
    end
    if event.research then game_settings.lock_advancing_train_recipes(event.research.force) end
    if not event.research.name:find("diggy-support-reach", 1, true) then return end
    -- Every wall's cached contribution just changed: start over.
    collapse.wipe_cache()
end

script.on_event(defines.events.on_research_finished, on_research_finished)
if defines.events.on_research_reversed then
    script.on_event(defines.events.on_research_reversed, function(event)
        game_settings.on_roof_support_research(event)
        if event.research then roof_support_mining.sync_force(event.research.force) end
        advancing_collapse.on_research_reversed(event)
        wind_turbine.on_research_reversed(event)
        turret_range.on_research_reversed(event)
        underground_belt_reach.on_research_reversed(event)
        underground_pipe_reach.on_research_reversed(event)
        underground_world_sync.on_research_finished(event)
        underground_blueprints.on_research_finished(event)
        inserter_config.on_research_reversed(event)
        teleport.on_research_reversed(event)
        shelter_core.on_research_reversed(event)
    end)
end


commands.add_command("diggy-sim", { "diggy.command-sim" }, function(event)
    local player = event.player_index and game.get_player(event.player_index)
    if not player then return end
    if not player.admin then
        player.print({ "diggy.admin-only" })
        return
    end
    local param = event.parameter or ""
    if param == "stop" then
        sim.stop(player)
    else
        sim.start(player, param:find("bare") ~= nil, param:find("slow") ~= nil)
    end
end)


commands.add_command("the-cave-faster-start", {"the-cave-faster-start.command-help"}, faster_start.command)

commands.add_command("diggy-mine", { "diggy.command-mine" }, function(event)
    local player = event.player_index and game.get_player(event.player_index)
    if not player then return end
    if not player.admin then
        player.print({ "diggy.admin-only" })
        return
    end
    if not player.character then
        player.print({ "diggy.kit-needs-character" })
        return
    end
    local value = tonumber(event.parameter) or 10
    local before = player.character_mining_speed_modifier
    player.character_mining_speed_modifier = value
    roof_support_mining.sync(player)
    player.print({ "diggy.mine-set", string.format("%.1f", before), string.format("%.1f", value) })
end)

commands.add_command("diggy-kit", { "diggy.command-kit" }, function(event)
    local player = event.player_index and game.get_player(event.player_index)
    if not player then return end
    if not player.admin then
        player.print({ "diggy.admin-only" })
        return
    end
    admin_kit.give(player)
    roof_support_mining.sync(player)
end)

commands.add_command("diggy-stress", { "diggy.command-stress" }, function(event)
    local player = event.player_index and game.get_player(event.player_index)
    if not player then return end
    if not player.admin then
        player.print({ "diggy.admin-only" })
        return
    end
    collapse.debug_overlay(player)
end)

commands.add_command("the-cave-warp-now", "[The Cave] Admin debug: force an immediate Warp Outpost test warp.", function(event)
    local player = event.player_index and game.get_player(event.player_index)
    if player and not player.admin then
        player.print("[The Cave] Admin only.")
        return
    end
    warp_outpost.debug_force_warp(player)
end)

commands.add_command("the-cave-warp-profile", "[The Cave] Shows the current experimental Warp Outpost profile.", function(event)
    local player = event.player_index and game.get_player(event.player_index)
    warp_outpost.debug_show_profile(player)
end)

commands.add_command("the-cave-reset-status", "[The Cave] Admin: show the staged in-save restart status.", function(event)
    local player = event.player_index and game.get_player(event.player_index)
    if player and not player.admin then
        player.print("[The Cave] Admin only.")
        return
    end
    local message = "[The Cave] Soft reset status: " .. soft_reset.status_text()
    if player then player.print(message) else log(message) end
end)

commands.add_command("the-cave-safety-ring-wave", "[The Cave] Admin debug: force a Safety Ring attack wave.", function(event)
    local player = event.player_index and game.get_player(event.player_index)
    if player and not player.admin then
        player.print("[The Cave] Admin only.")
        return
    end
    warp_outpost.debug_spawn_safety_ring_wave(player)
end)

commands.add_command("diggy-mirror-check", { "diggy.command-mirror-check" }, function(event)
    local player = event.player_index and game.get_player(event.player_index)
    if not player then return end
    if not player.admin then
        player.print({ "diggy.admin-only" })
        return
    end
    local p = player.position
    local r = mirror.check(player.surface, p.x - 96, p.y - 96, p.x + 96, p.y + 96)
    player.print({ "diggy.mirror-check", r.chunks, r.mismatches, r.first or "-" })
end)

-- Pop-text animation and pending-collapse countdowns: per tick, but a
-- single table check each when nothing is animating.
script.on_event(defines.events.on_tick, function(event)
    -- While a staged restart is active, pause every ordinary The Cave tick
    -- system. The reset coordinator advances one checkpoint at a time and
    -- resumes normal gameplay only after all players are safely returned.
    if soft_reset.on_tick(event) then roof_support_mining.restore_all(); return end
    if main_train_defeat.on_tick(event) then
        roof_support_mining.restore_all()
        advancing_collapse.flush_pending_terrain()
        warp_outpost.on_tick(event) -- Keep each final-team countdown running.
        shelter_core.on_defeat_tick(event)
        return
    end

    cave_lifecycle.on_tick()
    cave_teams.on_tick()
    roof_support_mining.on_tick()
    starting_inventory.on_tick(event)
    minimal_wire.on_tick(event)
    advancing_collapse.on_tick(event)
    if main_train_defeat.blocks_all() then return end
    pop_text.tick(event.tick)
    tnt_boxes.on_tick(event)
    weapon_digging.on_tick(event)
    collapse.tick()
    sim.step()
    if main_train_defeat.blocks_all() then return end
    -- Claim ordinary enemies at the exact 200-tile Train/Shelter boundary
    -- before the nest-growth controller can advance a settler this tick.
    cave_enemy_expansion.on_objective_nth_tick(event)
    enemy_nest_growth.on_tick(event)

    -- Auto-pick dropped enemy coins and Ore Blood resources when players walk over them.
    if event.tick % 5 == 0 then
        market_coin.auto_pickup_coins()
        ore_blood.auto_pickup_resources()
    end

    train_interiors.on_tick(event)
    shelter_core.on_tick(event)
    uranium_caves.on_tick(event)
    mineral_caves.on_tick(event)
    lost_city.on_tick(event)
    fortified_vaults.on_tick(event)
    cave_evolution.on_tick(event)
    warp_outpost.on_tick(event)
    inventory_repair.on_tick(event)
    underground_belt_reach.on_tick(event)
    underground_pipe_reach.on_tick(event)
    underground_world_sync.on_tick(event)
    underground_blueprints.on_tick(event)
    offline_player_body.on_tick(event)
    teleport.on_tick(event)

    -- Keep the Market Portal button synced with the inventory/editor GUI.
    -- This covers cases where vanilla/editor inventory windows do not reliably
    -- fire the normal GUI open/close events in every mode.
    if event.tick % 15 == 0 then
        market_coin.refresh_market_portal_buttons()
    end

    -- Keep enemy cave guard turrets functional: generated gun turrets should not run dry,
    -- and generated laser turrets need their hidden power support kept charged.
    caverns.tick_enemy_guards(event.tick)
    if event.tick % 120 == 0 then caverns.retry_scheduled_caves() end

    if the_cave_damage_indicator_enabled() then cave_damage_indicator.on_tick(event) end

    -- Keep darkness enforced even if another script/scenario changes daytime.
    if event.tick % 60 == 0 then
        make_cave_dark()
    end
    solar_display.on_tick()
    -- Enforce after all ordinary spawners, including enemies entering the area.
    advancing_recovery.on_tick()
end)

script.on_event(defines.events.on_resource_depleted, function(event)
    uranium_caves.on_resource_depleted(event)
    mineral_caves.on_resource_depleted(event)
end)

script.on_event(defines.events.on_biter_base_built, function(event)
    if soft_reset.is_active() or main_train_defeat.blocks_all() then return end
    if fortified_vaults.on_biter_base_built(event) then return end
    cave_enemy_expansion.on_biter_base_built(event)
end)

script.on_event(defines.events.on_chunk_generated, function(event)
    fortified_vaults.on_chunk_generated(event)
    world.on_chunk_generated(event)
    lost_city.on_chunk_generated(event)
    train_interiors.on_chunk_generated(event)
    shelter_core.on_chunk_generated(event)
    warp_outpost.enforce_enemy_safe_zone_now(event.surface, nil, "chunk-generated")
end)
script.on_event(defines.events.on_chunk_charted, function(event)
    world.on_chunk_charted(event)
    train_interiors.on_chunk_charted(event)
    shelter_core.on_chunk_charted(event)
end)

script.on_event(defines.events.on_player_created, function(event)
    local player = game.get_player(event.player_index)
    main_train_defeat.protect_player(player)
    if soft_reset.hold_player(player) then return end
    initialize_existing_player(event.player_index)
end)


-- Preserve player-selected Uranium Cave transfer-port rotations. Inserter
-- Configuration shares the same Factorio rotation event when enabled.
script.on_event(defines.events.on_player_rotated_entity, function(event)
    if roof_support.is_support(event.entity) then
        local old = roof_support.on_rotated(event.entity, event.previous_direction)
        if old then
            collapse.cancel_roof_jobs()
            reevaluate_removed_roof(old, event.player_index)
        end
        roof_support.refresh_previews()
    end
    uranium_caves.on_player_rotated_entity(event)
    mineral_caves.on_player_rotated_entity(event)
    lost_city.on_player_rotated_entity(event)
    extra_storage_tanks.on_player_rotated_entity(event)
    if inserter_config_enabled then inserter_config.on_player_rotated_entity(event) end
end)

-- The Cave Inserter Configuration events.
if inserter_config_enabled then
    script.on_event(defines.events.on_entity_settings_pasted, inserter_config.on_entity_settings_pasted)
    script.on_event("inserter-config-drop-rotate", inserter_config.on_rotation_adjust)
    script.on_event("inserter-config-drop-rotate-reverse", inserter_config.on_rotation_adjust)
    script.on_event("inserter-config-pickup-rotate-reverse", inserter_config.on_rotation_adjust)
    script.on_event("inserter-config-pickup-distance-adjust", inserter_config.on_distance_adjust)
    script.on_event("inserter-config-drop-distance-adjust", inserter_config.on_distance_adjust)
    script.on_event("inserter-config-drop-offset-adjust-lateral", inserter_config.on_offset_adjust)
    script.on_event("inserter-config-drop-offset-adjust-distance", inserter_config.on_offset_adjust)
end

local the_cave_clean_corpses_for_player

script.on_event("inserter-config-pickup-rotate", function(event)
    -- Ctrl+R already rotates an Inserter's pickup point while the optional
    -- Inserter Configuration system is active. Preserve that exact behaviour
    -- whenever the player's cursor is over an Inserter; otherwise Ctrl+R runs
    -- the 20x20 Gun Turret reload.
    if inserter_config_enabled then
        local player = event and event.player_index and game.get_player(event.player_index)
        local selected = player and player.selected
        if selected and selected.valid and selected.type == "inserter" then
            inserter_config.on_rotation_adjust(event)
            return
        end
    end
    gun_turret_autoload.on_area_reload(event)
end)

if defines.events.on_train_created then
    script.on_event(defines.events.on_train_created, train_interiors.on_train_created)
end
script.on_event(defines.events.on_player_driving_changed_state, train_interiors.on_player_driving_changed_state)
script.on_event("the-cave-enter-train-interior", function(event)
    if shelter_core.on_enter_hotkey(event) then return end
    train_interiors.on_enter_interior_hotkey(event)
end)
script.on_event("the-cave-open-teleporter", teleport.on_custom_input)
if defines.events.on_lua_shortcut then
    script.on_event(defines.events.on_lua_shortcut, function(event)
        if event.prototype_name == "the-cave-reload-gun-turrets-shortcut" then
            gun_turret_autoload.on_area_reload(event)
            return
        end
        if event.prototype_name == "the-cave-clean-corpses-shortcut" then
            the_cave_clean_corpses_for_player(game.get_player(event.player_index))
            return
        end
        if teleport.on_lua_shortcut(event) then return end
        if shelter_core.on_lua_shortcut(event) then return end
        train_interiors.on_lua_shortcut(event)
    end)
end
if defines.events.on_player_died then
    script.on_event(defines.events.on_player_died, fortified_vaults.on_player_died)
end
if defines.events.on_player_respawned then
    script.on_event(defines.events.on_player_respawned, function(event)
        main_train_defeat.protect_player(game.get_player(event.player_index))
        if soft_reset.hold_player(game.get_player(event.player_index)) then return end
        train_interiors.on_player_respawned(event)
        shelter_core.on_player_respawned(event)
        uranium_caves.on_player_respawned(event)
        mineral_caves.on_player_respawned(event)
        lost_city.on_player_respawned(event)
        fortified_vaults.on_player_respawned(event)
        advancing_collapse.on_player_respawned(event)
        starting_inventory.on_player_ready(event)
        cave_teams.queue_arrival(event.player_index)
    end)
end
script.on_event(defines.events.on_player_changed_surface, function(event)
    cave_teams.on_player_changed_surface(event)
    offline_player_body.on_player_changed_surface(event)
    roof_support.clear_preview(event.player_index)
    roof_support_mining.clear(event.player_index)
    train_interiors.on_player_changed_surface(event)
    shelter_core.on_player_changed_surface(event)
    uranium_caves.on_player_changed_surface(event)
    mineral_caves.on_player_changed_surface(event)
    lost_city.on_player_changed_surface(event)
    fortified_vaults.on_player_changed_surface(event)
    darkness_infestation.on_player_changed_surface(event)
end)

if defines.events.on_player_main_inventory_changed then
    script.on_event(defines.events.on_player_main_inventory_changed, function(event)
        underground_item_ui.on_inventory_changed(event)
        underground_blueprints.on_inventory_changed(event)
        inventory_repair.on_player_main_inventory_changed(event)
    end)
end
script.on_event(defines.events.on_player_pipette, mining_drill_pipette.on_player_pipette)
script.on_event(defines.events.on_player_cursor_stack_changed, function(event)
    roof_support.on_context_changed(event)
    roof_support_mining.on_context_changed(event)
    underground_belt_reach.on_player_cursor_stack_changed(event)
    underground_pipe_reach.on_player_cursor_stack_changed(event)
    underground_blueprints.queue(event)
end)
if defines.events.on_player_setup_blueprint then
    script.on_event(defines.events.on_player_setup_blueprint, function(event)
        underground_belt_reach.on_player_setup_blueprint(event)
        underground_pipe_reach.on_player_setup_blueprint(event)
    end)
end
if defines.events.on_player_configured_blueprint then
    script.on_event(defines.events.on_player_configured_blueprint, function(event)
        underground_belt_reach.on_player_configured_blueprint(event)
        underground_pipe_reach.on_player_configured_blueprint(event)
    end)
end
if defines.events.on_player_controller_changed then
    script.on_event(defines.events.on_player_controller_changed, function(event)
        roof_support_mining.on_context_changed(event)
        cave_teams.on_player_controller_changed(event)
        offline_player_body.on_player_controller_changed(event)
        underground_blueprints.queue(event)
    end)
end
if defines.events.on_player_changed_force then
    script.on_event(defines.events.on_player_changed_force, function(event)
        roof_support.on_context_changed(event)
        roof_support_mining.on_context_changed(event)
        main_train_defeat.protect_player(game.get_player(event.player_index))
        warp_outpost.refresh_defeat_gui(game.get_player(event.player_index))
        everything_on_nauvis_progression.on_player_changed_force(event)
        underground_belt_reach.on_player_changed_force(event)
        underground_pipe_reach.on_player_changed_force(event)
        underground_blueprints.queue(event)
        shelter_core.on_player_created(event)
    end)
end
if defines.events.on_force_created then
    script.on_event(defines.events.on_force_created, function(event)
        everything_on_nauvis_progression.on_force_created(event)
        quality_everything.on_force_created(event)
        uranium_caves.on_force_created(event)
        fortified_vaults.on_force_created(event)
        game_settings.lock_advancing_train_recipes(event.force)
        game_settings.apply_roof_support_research(event.force)
        roof_support_mining.sync_force(event.force)
    end)
end
if defines.events.on_force_reset then
    script.on_event(defines.events.on_force_reset, function(event)
        cave_lifecycle.on_force_reset(event)
        underground_world_sync.enqueue(event.force)
        underground_belt_reach.on_research_finished{research=event.force.technologies["the-cave-underground-belt-reach-1"]}
        for _,player in pairs(event.force.players) do underground_blueprints.queue{player_index=player.index} end
    end)
end
if defines.events.on_technology_effects_reset then
    script.on_event(defines.events.on_technology_effects_reset, function(event)
        game_settings.apply_roof_support_research(event.force)
        roof_support_mining.sync_force(event.force)
    end)
end
if defines.events.on_pre_player_left_game then
    script.on_event(defines.events.on_pre_player_left_game, function(event)
        roof_support_mining.clear(event.player_index)
        if soft_reset.is_active() then return end
        offline_player_body.on_pre_player_left_game(event)
    end)
end

script.on_event(defines.events.on_player_left_game, function(event)
    roof_support.clear_preview(event.player_index)
    roof_support_mining.clear(event.player_index)
    if soft_reset.is_active() then return end
    offline_player_body.on_player_left_game(event)
    underground_belt_reach.on_player_left_game(event)
    underground_pipe_reach.on_player_left_game(event)
    train_interiors.on_player_left_game(event)
    warp_outpost.on_player_left_game(event)
    inventory_repair.on_player_left_game(event)
    if the_cave_damage_indicator_enabled() then cave_damage_indicator.on_player_left_game(event) end
end)

if defines.events.on_pre_player_died then
    script.on_event(defines.events.on_pre_player_died, function(event)
        cave_respawn.capture(event)
        roof_support_mining.clear(event.player_index)
        underground_belt_reach.on_pre_player_died(event)
        underground_pipe_reach.on_pre_player_died(event)
    end)
end

if defines.events.on_player_armor_inventory_changed then
    script.on_event(defines.events.on_player_armor_inventory_changed, equipment_grid_upgrades.on_player_armor_inventory_changed)
end

script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
    minimal_wire.on_runtime_mod_setting_changed(event)
    inventory_repair.on_runtime_mod_setting_changed(event)
    if the_cave_damage_indicator_enabled() then cave_damage_indicator.on_runtime_mod_setting_changed(event) end
    if event.setting == "diggy-wall-support"
        or event.setting == "diggy-strut-strength-max"
        or event.setting == "diggy-wall-crowding" then
        -- The strength basis moved: wall records carry strength (rebuild
        -- facts), and LUTs and cached values bake it in (rebuild derivations).
        -- Hidden stress updates on the next world event near each cell.
        mirror.wipe()
        collapse.stress_basis_changed()
    end
end)


script.on_nth_tick(60, lamp_pole.on_nth_tick)


script.on_event(defines.events.on_surface_created, function(event)
    advancing_collapse.on_surface_created(event)
    make_cave_dark()
end)



-- The Cave: Backspace and shortcut-bar corpse cleaner
the_cave_clean_corpses_for_player = function(player)
    if not (player and player.valid and player.connected and player.character) then return end
    local surface = player.surface
    if not (surface and surface.valid) then return end

    -- Same idea as remove-biters-corpses:
    -- clean nearby temporary corpses only, so player corpses with items are not removed.
    local radius = settings.get_player_settings(player)["the-cave-corpse-clean-radius"].value
    local corpses = surface.find_entities_filtered{
        position = player.position,
        radius = radius,
        type = "corpse"
    }

    local removed = 0
    for _, entity in pairs(corpses) do
        if entity and entity.valid and entity.corpse_expires then
            entity.destroy()
            removed = removed + 1
        end
    end

    if removed > 0 then
        player.print({"", "[The Cave] Cleaned ", removed, " corpses nearby."})
    else
        player.print("[The Cave] No corpses nearby.")
    end
end

script.on_event("the-cave-clean-corpses", function(event)
    local player = game.get_player(event.player_index)
    the_cave_clean_corpses_for_player(player)
end)

script.on_event(defines.events.on_player_set_quick_bar_slot, underground_item_ui.on_quickbar_changed)
script.on_event(defines.events.on_player_trash_inventory_changed, underground_item_ui.on_inventory_changed)
script.on_event(defines.events.on_player_dropped_item, underground_item_ui.on_dropped_item)
script.on_event(defines.events.on_player_dropped_item_into_entity, underground_item_ui.on_dropped_item_into_entity)
script.on_event("the-cave-clear-underground-cursor", underground_item_ui.on_clear_cursor)
