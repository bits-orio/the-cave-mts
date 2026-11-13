-- Empty items and placed entities retain their identities. Only a mined,
-- non-empty Cave Accumulator becomes a non-stackable item carrying its Joules.
local additions = {}
for _, size in ipairs({3, 6, 10, 20}) do
  local name = "the-cave-accumulator-" .. size .. "x" .. size
  local entity, empty = data.raw.accumulator[name], data.raw.item[name]
  local charged = table.deepcopy(empty)
  charged.type = "item-with-tags"
  charged.name = name .. "-charged"
  charged.localised_name = {"cave-portable-accumulators.charged-name", {"entity-name." .. name}}
  charged.localised_description = {"cave-portable-accumulators.item-description"}
  charged.stack_size = 1
  charged.auto_recycle = false
  charged.order = (empty.order or "") .. "-charged"
  charged.flags = {"not-stackable"}
  charged.place_result = name .. "-portable-placement"
  additions[#additions + 1] = charged
  -- A ghost made from a charged item must request that exact item. Robots do
  -- not use secondary items in an entity's placeable_by list as substitutes.
  local placement = table.deepcopy(entity)
  placement.name = charged.place_result
  placement.localised_name = charged.localised_name
  placement.placeable_by = {{item = charged.name, count = 1}}
  placement.hidden_in_factoriopedia = true
  -- Keep the original replacement group so native replacement retains wires.
  -- Runtime immediately replaces this temporary entity with the original.
  additions[#additions + 1] = placement
end
data:extend(additions)
