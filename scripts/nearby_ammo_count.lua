local nearby_ammo_count = {}

nearby_ammo_count.update_interval = 15

local SETTING_NAME = "the-cave-nearby-ammo-display-mode"
local SCAN_RADIUS = 100
local TURRET_AMMO_INVENTORY = defines.inventory.turret_ammo

local COLOR_NORMAL = { r = 0, g = 1, b = 0, a = 0.70 }
local COLOR_LOW = { r = 1, g = 0.77, b = 0, a = 1 }
local COLOR_CRITICAL = { r = 1, g = 0.22, b = 0.18, a = 1 }

-- This is derived runtime data only. It is rebuilt after load and invalidated
-- whenever force friendship changes; nothing from this feature enters storage.
local visible_turret_forces = {}

local function get_visible_turret_forces(player_force)
    local cached = visible_turret_forces[player_force.index]
    if cached then return cached end

    local forces = {}
    for _, candidate in pairs(game.forces) do
        -- Match Factorio's directional friendship rule: a turret is visible
        -- when its owning force regards the viewing player's force as a friend.
        if candidate == player_force or candidate.get_friend(player_force) then
            forces[#forces + 1] = candidate.name
        end
    end

    visible_turret_forces[player_force.index] = forces
    return forces
end

local function read_magazine_count(turret)
    local inventory = turret.get_inventory(TURRET_AMMO_INVENTORY)
    if not inventory then return 0 end
    return inventory.get_item_count()
end

local function ammo_color(turret, magazines)
    if magazines <= 1 then return COLOR_CRITICAL end

    local insertion_target = turret.prototype.automated_ammo_count
    if insertion_target and magazines < insertion_target then
        return COLOR_LOW
    end

    return COLOR_NORMAL
end

local function draw_count(player, turret)
    local magazines = read_magazine_count(turret)
    rendering.draw_text({
        text = tostring(magazines),
        surface = turret.surface,
        target = { entity = turret, offset = { 0, -0.1 } },
        color = ammo_color(turret, magazines),
        only_in_alt_mode = true,
        scale = 1.35,
        scale_with_zoom = true,
        alignment = "center",
        players = { player.index },
        time_to_live = nearby_ammo_count.update_interval,
    })
end

function nearby_ammo_count.on_nth_tick()
    for _, player in pairs(game.connected_players) do
        if player.valid then
            local player_settings = settings.get_player_settings(player)
            local mode_setting = player_settings and player_settings[SETTING_NAME]
            local mode = mode_setting and mode_setting.value or "magazine"

            if mode ~= "disabled" then
                local turrets = player.surface.find_entities_filtered({
                    type = "ammo-turret",
                    position = player.position,
                    radius = SCAN_RADIUS,
                    force = get_visible_turret_forces(player.force),
                })

                for _, turret in pairs(turrets) do
                    if turret.valid then
                        draw_count(player, turret)
                    end
                end
            end
        end
    end
end

function nearby_ammo_count.on_force_relationship_changed()
    visible_turret_forces = {}
end

return nearby_ammo_count
