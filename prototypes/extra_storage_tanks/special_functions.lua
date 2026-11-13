require("util")
local shared = require("prototypes.extra_storage_tanks.shared")
local std_func = require("prototypes.extra_storage_tanks.standard_functions")
local sounds = require("__base__.prototypes.entity.sounds")
local hit_effects = require("__base__.prototypes.entity.hit-effects")
local item_sounds = require("__base__.prototypes.item_sounds")
local explosion_animations = require("__base__.prototypes.entity.explosion-animations")

local special_functions = {}

local function create_collision_box(info)
  local box = info.BoundingBox
  local offset = info.CollisionOffset
  return {
    {box[1][1] - offset, box[1][2] - offset},
    {box[2][1] + offset, box[2][2] + offset}
  }
end

local function create_single_wire_connection_for_set(wire)
  local variation, pixel_x, pixel_y, shadow_pixel_offset_y = table.unpack(wire)
  return {
    variation = variation,
    main_offset = util.by_pixel(pixel_x, pixel_y),
    shadow_offset = util.by_pixel(pixel_x, pixel_y + shadow_pixel_offset_y),
    show_shadow = false
  }
end

function special_functions.create_four_different_wire_connections(north, east, south, west)
  return circuit_connector_definitions.create_vector(
    universal_connector_template,
    {
      create_single_wire_connection_for_set(north),
      create_single_wire_connection_for_set(east),
      create_single_wire_connection_for_set(south),
      create_single_wire_connection_for_set(west)
    }
  )
end

function special_functions.create_four_identical_wire_connections(wire)
  local connection = create_single_wire_connection_for_set(wire)
  return circuit_connector_definitions.create_vector(
    universal_connector_template,
    {connection, table.deepcopy(connection), table.deepcopy(connection), table.deepcopy(connection)}
  )
end

function special_functions.create_entity_graphics_and_shadow(entity_name, info)
  local scale = info.Scale or 0.5
  return {
    {
      filename = shared.GRAPHICS_PATH .. entity_name .. ".png",
      priority = "extra-high",
      scale = scale,
      frames = info.Frames,
      width = info.EntityWidth,
      height = info.EntityHeight,
      shift = info.EntityShift
    },
    {
      filename = shared.GRAPHICS_PATH .. entity_name .. ".png",
      priority = "extra-high",
      scale = scale,
      frames = info.Frames,
      y = info.EntityHeight,
      width = info.ShadowWidth,
      height = info.ShadowHeight,
      shift = info.ShadowShift,
      draw_as_shadow = true
    }
  }
end

local function create_window_background(info)
  if info.WindowIsTall then
    return {
      filename = shared.GRAPHICS_PATH .. "tall-window-background.png",
      priority = "extra-high",
      width = 32,
      height = 132,
      scale = info.Scale,
      shift = util.by_pixel(0, 0.5)
    }
  end
  return {
    filename = shared.GRAPHICS_PATH .. "window-background.png",
    priority = "extra-high",
    width = 20,
    height = 41,
    scale = info.Scale,
    shift = util.by_pixel(0, -0.5)
  }
end

local function create_fluid_background(info)
  return {
    filename = "__base__/graphics/entity/storage-tank/fluid-background.png",
    priority = "extra-high",
    width = 32,
    height = 15,
    scale = info.Scale
  }
end

local function create_flow_sprite(info)
  if info.WindowIsTall then
    return {
      filename = shared.GRAPHICS_PATH .. "fluid-flow-low-temperature-extended.png",
      priority = "extra-high",
      width = 160,
      height = 20,
      scale = info.Scale
    }
  end
  return {
    filename = "__base__/graphics/entity/pipe/fluid-flow-low-temperature.png",
    priority = "extra-high",
    width = 160,
    height = 20,
    scale = info.Scale
  }
end

local function create_gas_flow_sprite(info)
  return {
    filename = shared.GRAPHICS_PATH .. "steam-narrowed-cropped.png",
    priority = "extra-high",
    line_length = 10,
    width = 24,
    height = 28,
    frame_count = 60,
    axially_symmetrical = false,
    animation_speed = 0.25,
    direction_count = 1,
    scale = info.Scale
  }
end

function special_functions.create_entity(entity_name, info)
  local sound_sizes = {
    small = {"metal", sounds.metal_small_open, sounds.metal_small_close},
    large = {"metal-large", sounds.metal_large_open, sounds.metal_large_close}
  }
  local entity = {
    type = "storage-tank",
    name = entity_name,
    icon = shared.ICON_PATH .. entity_name .. ".png",
    icon_size = 64,
    flags = {"placeable-player", "player-creation"},
    minable = {mining_time = info.MiningTime, result = entity_name},
    fast_replaceable_group = info.FastReplaceGroup,
    max_health = info.Health,
    dying_explosion = entity_name .. "-explosion",
    corpse = entity_name .. "-remnants",
    selection_box = info.SelectionBox,
    collision_box = create_collision_box({
      BoundingBox = info.SelectionBox,
      CollisionOffset = info.CollisionOffset
    }),
    tile_height = info.TileHeight,
    drawing_box_vertical_extension = info.DrawBoxVertExt,
    icon_draw_specification = info.IconDrawSpec,
    fluid_box = {
      volume = info.FluidCapacity,
      pipe_covers = pipecoverspictures(),
      pipe_connections = info.PipeConnections
    },
    window_bounding_box = info.WindowBox,
    pictures = {
      picture = {sheets = info.EntitySprites},
      window_background = create_window_background({WindowIsTall = info.WindowIsTall, Scale = info.WindowScale}),
      fluid_background = create_fluid_background({Scale = info.FluidScale}),
      flow_sprite = create_flow_sprite({WindowIsTall = info.WindowIsTall, Scale = info.FluidFlowScale}),
      gas_flow = create_gas_flow_sprite({Scale = info.FluidScale})
    },
    flow_length_in_ticks = info.FluidFlowLength,
    damaged_trigger_effect = hit_effects.entity(),
    impact_category = sound_sizes[info.SoundSizeCategory][1],
    open_sound = sound_sizes[info.SoundSizeCategory][2],
    close_sound = sound_sizes[info.SoundSizeCategory][3],
    working_sound = {
      sound = {
        filename = "__base__/sound/storage-tank.ogg",
        volume = info.SoundVolume,
        audible_distance_modifier = 0.5
      },
      match_volume_to_activity = true,
      max_sounds_per_prototype = 3
    },
    circuit_connector = info.WireConnections,
    circuit_wire_max_distance = default_circuit_wire_max_distance
  }
  if shared.SPACE_AGE_PRESENT then entity.heating_energy = info.HeatingEnergy end
  return entity
end

function special_functions.create_item(entity_name, info)
  return {
    type = "item",
    name = entity_name,
    icon = shared.ICON_PATH .. entity_name .. ".png",
    icon_size = 64,
    subgroup = "storage",
    order = info.Order,
    inventory_move_sound = item_sounds["metal-" .. info.SoundSizeCat .. "-inventory_move"],
    pick_sound = item_sounds["metal-" .. info.SoundSizeCat .. "-inventory_pickup"],
    drop_sound = item_sounds["metal-" .. info.SoundSizeCat .. "-inventory_move"],
    place_result = entity_name,
    stack_size = info.StackSize,
    weight = info.Weight * kg
  }
end

function special_functions.create_recipe(entity_name, info)
  local ingredients = {
    {type = "item", name = "iron-plate", amount = info.IronPlates}
  }
  if info.SteelPlates and info.SteelPlates > 0 then
    ingredients[#ingredients + 1] = {type = "item", name = "steel-plate", amount = info.SteelPlates}
  end
  return {
    type = "recipe",
    name = entity_name,
    enabled = false,
    energy_required = info.EnergyNeed,
    ingredients = ingredients,
    results = {{type = "item", name = entity_name, amount = 1}}
  }
end

function special_functions.create_explosion(entity_name, info)
  local sound_sizes = {
    small = sounds.small_explosion,
    medium = sounds.medium_explosion,
    large = sounds.large_explosion(info.SoundVolMin or 1, info.SoundVolMax or 1)
  }
  local animation_sizes = {
    small = explosion_animations.small_explosion(info.AnimScale or 1),
    medium = explosion_animations.medium_explosion(info.AnimScale or 1),
    big = explosion_animations.big_explosion(info.AnimScale or 1)
  }
  local explosion = table.deepcopy(data.raw.explosion["storage-tank-explosion"])
  explosion.name = entity_name .. "-explosion"
  explosion.icon = shared.ICON_PATH .. entity_name .. ".png"
  explosion.icon_size = 64
  explosion.animations = animation_sizes[info.AnimSizeCat]
  explosion.height = info.AnimHeight or 0
  explosion.sound = sound_sizes[info.SoundSizeCat]
  local effects = explosion.created_effect.action_delivery.target_effects
  for _, effect in pairs(effects) do
    if effect.repeat_count then effect.repeat_count = std_func.round_number(effect.repeat_count * info.DebrisAmountX) end
    if effect.initial_vertical_speed then effect.initial_vertical_speed = effect.initial_vertical_speed * info.DebrisSpeedX end
    if effect.initial_vertical_speed_deviation then effect.initial_vertical_speed_deviation = effect.initial_vertical_speed_deviation * info.DebrisSpeedX end
    if effect.speed_from_center then effect.speed_from_center = effect.speed_from_center * info.DebrisSpeedX end
    if effect.speed_from_center_deviation then effect.speed_from_center_deviation = effect.speed_from_center_deviation * info.DebrisSpeedX end
  end
  return explosion
end

function special_functions.create_remnants(entity_name, info)
  local tile_radius = info.TileRadius or 1.5
  local pixel_shift = info.PixelShift or {0, 0}
  return {
    type = "corpse",
    name = entity_name .. "-remnants",
    icon = shared.ICON_PATH .. entity_name .. ".png",
    icon_size = 64,
    flags = {"placeable-neutral", "not-on-map"},
    hidden_in_factoriopedia = true,
    subgroup = "storage-remnants",
    order = "a-d-a",
    selection_box = {{-tile_radius, -tile_radius}, {tile_radius, tile_radius}},
    tile_width = tile_radius * 2,
    tile_height = tile_radius * 2,
    selectable_in_game = false,
    time_before_removed = 60 * 60 * 15,
    expires = false,
    final_render_layer = "remnants",
    remove_on_tile_placement = false,
    animation = make_rotated_animation_variations_from_sheet(1, {
      filename = "__base__/graphics/entity/storage-tank/remnants/storage-tank-remnants.png",
      line_length = 1,
      width = 426,
      height = 282,
      direction_count = 1,
      shift = util.by_pixel(table.unpack(pixel_shift)),
      scale = 0.5 * (tile_radius / 1.5)
    })
  }
end

return special_functions
