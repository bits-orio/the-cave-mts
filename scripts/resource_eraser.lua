local settings = require("scripts.game_settings").proxy(settings)

local resource_eraser = {}

local TOOL_NAME = "the-cave-resource-eraser-tool"
local MAX_RESOURCES_PER_SELECTION = 10000

local function access_mode()
    local setting = settings and settings.startup and settings.startup["the-cave-resource-eraser-access"]
    return setting and setting.value or "disabled"
end

local function player_has_access(player)
    local access = access_mode()
    if access == "all-players" then return true end
    if access == "admins-only" then return player.admin == true end
    return false
end

function resource_eraser.on_player_selected_area(event)
    if not event or event.item ~= TOOL_NAME then return end

    local player = game.get_player(event.player_index)
    if not (player and player.valid) then return end

    local access = access_mode()
    if access == "disabled" then
        player.print({"the-cave-resource-eraser.disabled"})
        return
    end
    if not player_has_access(player) then
        player.print({"the-cave-resource-eraser.admin-only"})
        return
    end

    -- Query the selected surface and bounding box directly. This is deliberately
    -- independent of event.entities so the eraser still works if another mod or
    -- an inherited selection-tool prototype changes which entities are returned.
    local surface = event.surface
    if not (surface and surface.valid) then
        surface = player.surface
    end
    if not (surface and surface.valid and event.area) then
        player.print({"the-cave-resource-eraser.none-found"})
        return
    end

    local search = {area = event.area, type = "resource"}
    local resource_count = surface.count_entities_filtered(search)

    if resource_count == 0 then
        player.print({"the-cave-resource-eraser.none-found"})
        return
    end
    if resource_count > MAX_RESOURCES_PER_SELECTION then
        player.print({"the-cave-resource-eraser.too-many", tostring(MAX_RESOURCES_PER_SELECTION)})
        return
    end

    local resources = surface.find_entities_filtered(search)
    local removed = 0
    for _, entity in ipairs(resources) do
        if entity and entity.valid and entity.type == "resource" and entity.destroy() then
            removed = removed + 1
        end
    end

    if removed == 0 then
        player.print({"the-cave-resource-eraser.none-found"})
    else
        player.print({"the-cave-resource-eraser.removed", tostring(removed)})
    end
end

-- Shift-selection is intentionally reserved and performs no action in the first release.
function resource_eraser.on_player_alt_selected_area(_event)
end

return resource_eraser
