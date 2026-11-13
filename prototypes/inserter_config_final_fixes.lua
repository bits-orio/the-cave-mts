-- The Cave: enable runtime pickup/drop editing without changing inserter speed,
-- belt-chasing behaviour, energy use, hand capacity or any other prototype field.
local setting = settings.startup["the-cave-inserter-configurable"]
local enabled = not setting or setting.value == "enabled"
if not enabled then return end

for _, inserter in pairs(data.raw.inserter or {}) do
  inserter.allow_custom_vectors = true
end
