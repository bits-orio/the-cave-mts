-- Internal release policy, shared by ordinary and scheduled cave generation.
-- Keep Lost Village code/prototypes and existing discovered operations intact.
-- This switch only permits NEW entrances; it is not a player setting.
local cave_policy = {
    LOST_VILLAGE_GENERATION_ENABLED = false,
}

-- Iron, Copper and Coal share the mineral-cave surface namespace. Match only
-- underground mission surfaces, never their entrances on the parent map.
local COLLAPSE_EXEMPT_PREFIXES = {
    "the-cave-mineral-cave-",
    "the-cave-uranium-cave-",
    "the-cave-lost-city-",
    "the-cave-fortified-vault-",
}

function cave_policy.is_collapse_exempt(surface)
    if not (surface and surface.valid and type(surface.name) == "string") then return false end
    for _, prefix in ipairs(COLLAPSE_EXEMPT_PREFIXES) do
        if surface.name:sub(1, #prefix) == prefix then return true end
    end
    return false
end

return cave_policy
