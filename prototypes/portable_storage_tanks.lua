local ITEM_PREFIX = "portable-storage-tank-"
local PROXY_PREFIX = "portable-storage-tank-proxy-"
local PORTABLE_TANK_WEIGHT = 50 * 1000

local base_tank = data.raw["storage-tank"] and data.raw["storage-tank"]["storage-tank"]
local base_item = data.raw.item and data.raw.item["storage-tank"]

if not base_tank or not base_item then
  error("[The Cave] Portable tanks require the base storage-tank entity and item prototypes.")
end

local function base_icon_layers()
  if base_item.icons then
    local layers = table.deepcopy(base_item.icons)
    for _, layer in pairs(layers) do
      layer.icon_size = layer.icon_size or base_item.icon_size or 64
    end
    return layers
  end

  return {
    {
      icon = base_item.icon,
      icon_size = base_item.icon_size or 64,
      icon_mipmaps = base_item.icon_mipmaps
    }
  }
end

local function add_fluid_badge(layers, fluid)
  local source_layers
  if fluid.icons then
    source_layers = table.deepcopy(fluid.icons)
  else
    source_layers = {
      {
        icon = fluid.icon,
        icon_size = fluid.icon_size or 64,
        icon_mipmaps = fluid.icon_mipmaps
      }
    }
  end

  for _, source in pairs(source_layers) do
    local icon_size = source.icon_size or fluid.icon_size or 64
    local source_scale = source.scale or (32 / icon_size)
    local source_shift = source.shift or {0, 0}

    source.icon_size = icon_size
    source.scale = source_scale * 0.5
    source.shift = {
      (source_shift[1] or source_shift.x or 0) * 0.5 + 8,
      (source_shift[2] or source_shift.y or 0) * 0.5 + 8
    }
    layers[#layers + 1] = source
  end
end

local prototypes_to_add = {}

for fluid_name, fluid in pairs(data.raw.fluid) do
  local item_name = ITEM_PREFIX .. fluid_name
  local proxy_name = PROXY_PREFIX .. fluid_name
  local localised_name = {
    "portable-storage-tanks.filled-tank-name",
    fluid.localised_name or {"fluid-name." .. fluid_name}
  }
  local icons = base_icon_layers()
  add_fluid_badge(icons, fluid)

  local item = {
    type = "item-with-tags",
    name = item_name,
    localised_name = localised_name,
    localised_description = {"portable-storage-tanks.prototype-description"},
    icons = icons,
    subgroup = base_item.subgroup or "storage",
    order = (base_item.order or "b[fluid]-a[storage-tank]") .. "-portable[" .. fluid_name .. "]",
    inventory_move_sound = base_item.inventory_move_sound,
    pick_sound = base_item.pick_sound,
    drop_sound = base_item.drop_sound,
    flags = {"primary-place-result"},
    place_result = proxy_name,
    stack_size = 1,
    auto_recycle = false,
    weight = PORTABLE_TANK_WEIGHT
  }

  local proxy = table.deepcopy(base_tank)
  proxy.name = proxy_name
  proxy.localised_name = localised_name
  proxy.localised_description = {"portable-storage-tanks.proxy-description"}
  proxy.minable = nil
  proxy.placeable_by = {{item = item_name, count = 1}}
  proxy.fast_replaceable_group = nil
  proxy.next_upgrade = nil
  proxy.hidden_in_factoriopedia = true

  prototypes_to_add[#prototypes_to_add + 1] = item
  prototypes_to_add[#prototypes_to_add + 1] = proxy
end

data:extend(prototypes_to_add)
