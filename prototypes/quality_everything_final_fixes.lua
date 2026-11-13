-- Integrated behaviour based on Everything has Quality by LuckyLMJ.
-- A zero startup value is a strict no-op. The official Quality mod remains an
-- optional dependency so The Cave can still load in normal Factorio setups.

local setting = settings and settings.startup and settings.startup["the-cave-base-quality"]
local percentage = setting and tonumber(setting.value) or 0

if percentage <= 0 or not (mods and mods["quality"]) then return end

local quality_effect = percentage / 100

local function add_allowed_quality_effect(machine)
    local allowed_effects = machine.allowed_effects
    if allowed_effects == nil then return end

    if type(allowed_effects) ~= "table" then
        allowed_effects = { allowed_effects }
        machine.allowed_effects = allowed_effects
    end

    for _, effect_name in pairs(allowed_effects) do
        if effect_name == "quality" then return end
    end
    allowed_effects[#allowed_effects + 1] = "quality"
end

local function apply_base_quality(machine)
    machine.effect_receiver = machine.effect_receiver or {}
    machine.effect_receiver.base_effect = machine.effect_receiver.base_effect or {}
    machine.effect_receiver.base_effect.quality = quality_effect
    add_allowed_quality_effect(machine)
end

for _, prototype_type in ipairs({ "assembling-machine", "furnace", "mining-drill" }) do
    for _, machine in pairs(data.raw[prototype_type] or {}) do
        apply_base_quality(machine)
    end
end

-- Prevent negative module quality effects from cancelling the configured base
-- quality. Existing positive quality effects are preserved unchanged.
for _, module in pairs(data.raw.module or {}) do
    local effect = module.effect
    if effect then
        if effect.quality == nil or effect.quality < 0 then
            effect.quality = 0
        end
    end
end
