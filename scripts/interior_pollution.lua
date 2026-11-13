-- Shared Train Interior / Shelter pollution venting.
--
-- Pollution is owned by one Factorio surface. Player factories built on an
-- interior surface therefore cannot naturally affect enemies on the exterior
-- surface. This helper vents five times the pollution which already exists
-- inside. It never creates a fixed baseline, exponential growth or artificial
-- minimum, so an idle interior still produces no exterior pollution.

local interior_pollution = {}

local POLLUTION_MULTIPLIER = 5
local DEBUG_ROOT = "the_cave_interior_pollution_debug"

local function valid_surface(surface)
    return surface and surface.valid
end

local function debug_root()
    storage[DEBUG_ROOT] = storage[DEBUG_ROOT] or { last_by_key = {} }
    local root = storage[DEBUG_ROOT]
    root.last_by_key = root.last_by_key or {}
    return root
end

local function remember_result(spec, source_amount, vented_amount, status)
    if not (storage and spec and spec.key) then return end
    local interior = spec.interior_surface
    local exterior = spec.exterior_surface
    local position = spec.position or { x = 0, y = 0 }
    debug_root().last_by_key[spec.key] = {
        mode = spec.mode or "Interior",
        status = status or "unknown",
        source_amount = tonumber(source_amount) or 0,
        amount = tonumber(vented_amount) or 0,
        multiplier = POLLUTION_MULTIPLIER,
        tick = game and game.tick or 0,
        interior_surface = valid_surface(interior) and interior.name or "invalid",
        exterior_surface = valid_surface(exterior) and exterior.name or "invalid",
        x = tonumber(position.x or position[1]) or 0,
        y = tonumber(position.y or position[2]) or 0,
    }
end

function interior_pollution.clear(surface)
    if not valid_surface(surface) then return false end
    local ok = pcall(function() surface.clear_pollution() end)
    return ok == true
end

function interior_pollution.transfer(spec)
    if not spec then return 0 end
    local interior = spec.interior_surface
    local exterior = spec.exterior_surface
    local position = spec.position
    if not (valid_surface(interior) and valid_surface(exterior) and position)
        or interior.index == exterior.index then
        remember_result(spec, 0, 0, "no-valid-exterior")
        return 0
    end

    local read_ok, amount = pcall(function() return interior.get_total_pollution() end)
    amount = read_ok and tonumber(amount) or 0
    if not amount or amount <= 0 then
        remember_result(spec, 0, 0, "idle")
        return 0
    end

    local vented_amount = amount * POLLUTION_MULTIPLIER

    -- Add five times the real interior amount at the live exterior anchor.
    -- Pollution already emitted at earlier train positions is deliberately untouched:
    -- Factorio remains responsible for its normal diffusion and absorption.
    -- Clear the interior only after the exterior accepted the scripted pollute
    -- call, so a transient missing/invalid target cannot silently erase it.
    local vent_ok = pcall(function() exterior.pollute(position, vented_amount) end)
    if not vent_ok then
        remember_result(spec, amount, 0, "vent-failed")
        return 0
    end

    local clear_ok = pcall(function() interior.clear_pollution() end)
    remember_result(spec, amount, vented_amount, clear_ok and "transferred" or "clear-failed")
    return vented_amount
end

local function command_output(command, message)
    local player = command.player_index and game.get_player(command.player_index) or nil
    if player and player.valid then player.print(message) else game.print(message) end
end

function interior_pollution.register_commands()
    commands.add_command(
        "the-cave-pollution-test",
        "[The Cave] Show the most recent Train Interior / Shelter pollution collection and venting results.",
        function(command)
            local root = storage and storage[DEBUG_ROOT]
            local entries = root and root.last_by_key or nil
            if not entries or not next(entries) then
                command_output(command, "[The Cave] No interior pollution transfer cycle has run yet.")
                return
            end

            local keys = {}
            for key in pairs(entries) do keys[#keys + 1] = key end
            table.sort(keys)
            command_output(command, "[The Cave] Latest interior pollution transfer results:")
            for _, key in ipairs(keys) do
                local entry = entries[key]
                local age_seconds = math.max(0, ((game.tick or 0) - (entry.tick or 0)) / 60)
                local vented_amount = tonumber(entry.amount) or 0
                local source_amount = tonumber(entry.source_amount)
                if source_amount == nil then source_amount = vented_amount end
                local multiplier = tonumber(entry.multiplier)
                    or (source_amount > 0 and vented_amount / source_amount or 1)
                command_output(command, string.format(
                    "  %s: collected %.2f, vented %.2f (x%.2f), %s -> %s at (%.1f, %.1f), status=%s, %.1fs ago",
                    entry.mode or "Interior",
                    source_amount,
                    vented_amount,
                    multiplier,
                    entry.interior_surface or "unknown",
                    entry.exterior_surface or "unknown",
                    tonumber(entry.x) or 0,
                    tonumber(entry.y) or 0,
                    entry.status or "unknown",
                    age_seconds
                ))
            end
        end
    )
end

return interior_pollution
