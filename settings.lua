data:extend({

    {
        type = "string-setting",
        setting_type = "startup",
        name = "the-cave-market",
        default_value = "enabled",
        allowed_values = { "enabled", "disabled" },
        order = "a-c-market",
    },

    -- Startup: controls whether Space Age content is folded into Nauvis cave progression.
    {
        type = "string-setting",
        setting_type = "startup",
        name = "the-cave-everything-on-nauvis",
        default_value = "enabled",
        allowed_values = { "enabled", "disabled" },
        order = "a-a",
    },
    -- Startup: integrated Everything Has Quality. Zero disables the feature
    -- completely; values from 1 to 100 are percentage points of base quality
    -- for assembling machines, furnaces and mining drills.
    {
        type = "double-setting",
        setting_type = "startup",
        name = "the-cave-base-quality",
        default_value = 0,
        minimum_value = 0,
        maximum_value = 100,
        order = "a-a-0",
    },
    -- Startup: optional Alien Biomes floor integration. When both mods are
    -- active, newly generated/revealed Nauvis cave floor uses deterministic
    -- organic Alien Biomes regions. Existing terrain and player flooring are
    -- never migrated. Without Alien Biomes this setting is a no-op.
    {
        type = "string-setting",
        setting_type = "startup",
        name = "the-cave-alien-biomes-support",
        default_value = "enabled",
        allowed_values = { "enabled", "disabled" },
        order = "a-a-1",
    },
    -- Startup: The Cave 2.0 resource generation mode. ON uses the new mixed
    -- resource veins; OFF keeps classic single-resource veins while still
    -- using the new balanced richness values.
    {
        type = "string-setting",
        setting_type = "startup",
        name = "the-cave-mixed-resource-patches",
        default_value = "enabled",
        allowed_values = { "enabled", "disabled" },
        order = "a-b",
    },

    -- Startup: optional Ore Patch Missing challenge. When enabled, one basic ore type
    -- is removed from natural cave patches and becomes available through digging.
    -- Default OFF so normal saves keep the familiar resource layout.
    {
        type = "string-setting",
        setting_type = "startup",
        name = "the-cave-ore-patch-missing",
        default_value = "disabled",
        allowed_values = { "enabled", "disabled" },
        order = "a-b-1",
    },

    -- Startup: Uranium Caves. Medium+ natural entrances use room weight 12,
    -- remain at least 150 tiles apart and have a 12-room anti-drought guarantee.
    -- Every lower cavern reveals a 50/50 uranium/scrap vein; both halves require
    -- sulphuric acid and no fixed cave-wide uranium total is guaranteed.
    {
        type = "string-setting",
        setting_type = "startup",
        name = "the-cave-uranium-caves",
        default_value = "enabled",
        allowed_values = { "enabled", "disabled" },
        order = "a-b-1-1",
    },

    -- Startup: independently selectable timed single-resource jackpot caves.
    -- Enabled resources keep their relative weights from the established
    -- 5 Iron / 3 Copper / 2 Coal deterministic deck. Disabling one resource
    -- never disables either of the other two.
    {
        type = "string-setting",
        setting_type = "startup",
        name = "the-cave-iron-cave",
        default_value = "enabled",
        allowed_values = { "enabled", "disabled" },
        order = "a-b-1-2-a",
    },
    {
        type = "string-setting",
        setting_type = "startup",
        name = "the-cave-copper-cave",
        default_value = "enabled",
        allowed_values = { "enabled", "disabled" },
        order = "a-b-1-2-b",
    },
    {
        type = "string-setting",
        setting_type = "startup",
        name = "the-cave-coal-cave",
        default_value = "enabled",
        allowed_values = { "enabled", "disabled" },
        order = "a-b-1-2-c",
    },

    -- Startup: stop new Fortified entrances without removing saved caves.
    {
        type = "string-setting",
        setting_type = "startup",
        name = "the-cave-fortified-cave",
        default_value = "enabled",
        allowed_values = { "enabled", "disabled" },
        order = "a-b-1-3",
    },

    -- Startup: integrated three-stage Wind Turbine research and entity.
    -- Existing turbines are retained but made inactive while this is disabled.
    {
        type = "string-setting",
        setting_type = "startup",
        name = "the-cave-wind-turbine",
        default_value = "enabled",
        allowed_values = { "enabled", "disabled" },
        order = "a-b-1-4",
    },

    -- Startup: Ore Blood. When enabled, killed biters and spitters drop a small
    -- amount of one random basic resource. Coins are unchanged. Worms, nests,
    -- spawners, bosses, and other enemies are not affected.
    -- Default ON because it is a light reward layer, not a hard challenge mode.
    {
        type = "string-setting",
        setting_type = "startup",
        name = "the-cave-ore-blood",
        default_value = "enabled",
        allowed_values = { "enabled", "disabled" },
        order = "a-b-2",
    },

    -- Startup: optional mining drill resource filter inspired by player feedback.
    -- When enabled, adds a selection tool/shortcut and hidden filtered mining-drill variants
    -- so players can force selected drills to mine only one resource type.
    -- Default ON after player testing/request; players can disable it if they do not want drill filtering.
    {
        type = "string-setting",
        setting_type = "startup",
        name = "the-cave-filter-mining-drills",
        default_value = "enabled",
        allowed_values = { "enabled", "disabled" },
        order = "a-b-3",
    },

    -- Startup: native cargo-wagon-style slot filtering for compatible normal
    -- and logistic chests. Default ON preserves the established prototype
    -- behaviour for existing saves. Disabling skips only the global conversion;
    -- dedicated Filtered Industrial Container family remains filterable.
    {
        type = "string-setting",
        setting_type = "startup",
        name = "the-cave-chest-filtering",
        default_value = "enabled",
        allowed_values = { "enabled", "disabled" },
        order = "a-b-3-0",
    },

    -- Startup: optional destructive resource removal tool inspired by player feedback.
    -- Disabled by default. Admins Only is recommended for multiplayer servers.
    -- The tool removes every selected entity of type "resource", including oil and modded resources.
    {
        type = "string-setting",
        setting_type = "startup",
        name = "the-cave-resource-eraser-access",
        default_value = "disabled",
        allowed_values = { "disabled", "admins-only", "all-players" },
        order = "a-b-3-1",
    },

    -- Startup: optional Underground Belt Reach research chain.
    -- When enabled, adds 7 research levels that increase the maximum placement
    -- reach of official underground belts. Uses a dropdown per The Cave rules.
    {
        type = "string-setting",
        setting_type = "startup",
        name = "the-cave-underground-belt-reach-research",
        default_value = "enabled",
        allowed_values = { "enabled", "disabled" },
        order = "a-b-3-2",
    },

    -- Startup: optional Underground Pipe Reach research chain.
    -- When enabled, adds 7 research levels that increase the maximum placement
    -- reach of Pipe to Ground by +5 tiles per level. Uses a dropdown per The Cave rules.
    {
        type = "string-setting",
        setting_type = "startup",
        name = "the-cave-underground-pipe-reach-research",
        default_value = "enabled",
        allowed_values = { "enabled", "disabled" },
        order = "a-b-3-3",
    },

    -- Startup: optional fixed Shelter Defense objective. This is mutually
    -- exclusive with Train Interiors and is disabled by default.
    {
        type = "string-setting",
        setting_type = "startup",
        name = "the-cave-shelter-defense",
        default_value = "disabled",
        allowed_values = { "enabled", "disabled" },
        order = "0-c",
    },

    -- Startup: Train Interiors. Adds starter train, rolling-stock interiors,
    -- outside camera view while inside trains, train-near respawn, and safe train placement.
    -- Recipes for locomotives/wagons are disabled while this feature is enabled.
    -- Shelter Defense must be disabled before this mode can start.
    {
        type = "string-setting",
        setting_type = "startup",
        name = "the-cave-train-interiors",
        default_value = "disabled",
        allowed_values = { "enabled", "disabled" },
        order = "0-b",
    },

    -- Startup: selects the established Train/Shelter scripted Wave Defense.
    -- Wave Defense and Biter Expansion are independent and may run together;
    -- each system keeps ownership of its own units and commands.
    {
        type = "string-setting",
        setting_type = "startup",
        name = "the-cave-allow-wave-defense",
        default_value = "enabled",
        allowed_values = { "enabled", "disabled" },
        order = "0-c-1",
    },
    {
        type = "string-setting",
        setting_type = "startup",
        name = "the-cave-allow-biter-expansion",
        default_value = "disabled",
        allowed_values = { "enabled", "disabled" },
        order = "0-c-2",
    },

    -- Startup: optional Arachnid Queen ecology. Disabling this removes only
    -- Queens; ordinary three-spawner Nest Rooms and every other enemy system
    -- keep their established behaviour.
    {
        type = "string-setting",
        setting_type = "startup",
        name = "the-cave-arachnid-queen",
        hidden = true,
        default_value = "disabled",
        allowed_values = { "enabled", "disabled" },
        order = "0-c-3",
    },

    -- Startup: independent MTN-style northbound survival mode. The main Cave
    -- becomes a 510-tile ribbon divided into 704-tile zones. After two hours
    -- of connected gameplay, terrain advances from the south and is erased.
    -- Default OFF because this is a destructive new-map scenario choice.
    {
        type = "string-setting",
        setting_type = "startup",
        name = "the-cave-advancing-collapse",
        default_value = "disabled",
        allowed_values = { "enabled", "disabled" },
        order = "0-e",
    },

    -- Startup: CAVETORIO Train Warp / Warp Outpost mode.
    -- When disabled, The Cave plays normally without the warp timer, HUD,
    -- Manual Warp button, or experimental Cavetorio surfaces.
    -- Default OFF so Cavetorio must be intentionally enabled from Mod Settings.
    {
        type = "string-setting",
        setting_type = "startup",
        name = "the-cave-cavetorio",
        default_value = "disabled",
        allowed_values = { "enabled", "disabled" },
        order = "0-d",
    },

    -- Startup: kick players after five minutes of inactivity, then recover the
    -- personal inventory of anyone who remains offline for another five minutes.
    -- Train Interiors recovers near the live Main Train; normal games recover
    -- at the force spawn point on the main Cave surface.
    {
        type = "string-setting",
        setting_type = "startup",
        name = "the-cave-offline-player-body",
        default_value = "enabled",
        allowed_values = { "enabled", "disabled" },
        order = "a-b-5-1",
    },

    -- Startup: optional stable player-centred darkness threat.
    -- Uses an explicit dropdown per The Cave startup-setting design rules.
    {
        type = "string-setting",
        setting_type = "startup",
        name = "the-cave-darkness-infestation",
        default_value = "enabled",
        allowed_values = { "enabled", "disabled" },
        order = "a-b-6",
    },

    -- Startup: complete cave-collapse switch. Enabled uses the original
    -- balance; Disabled removes the system and hides Support Struts.
    {
        type = "string-setting",
        setting_type = "startup",
        name = "the-cave-collapse-mode",
        default_value = "disabled",
        allowed_values = { "enabled", "disabled" },
        order = "0-a",
    },

    -- Startup: one shared 8-level scale core for The Cave resource patches.
    -- Applies to both Mixed Resource Patches ON and classic single-resource patches.
    -- This does not use the vanilla map generator resource sliders. Digging Mode
    -- is a separate scenario and ignores this setting.
    {
        type = "string-setting",
        setting_type = "startup",
        name = "the-cave-resource-patch-size",
        default_value = "level-2",
        allowed_values = { "level-1", "level-2", "level-3", "level-4", "level-5", "level-6", "level-7", "level-8" },
        order = "b-a",
    },

    -- Startup: optional dig-only scenario mode. When enabled, The Cave disables
    -- generated ore patches and makes digging rocks the main resource source.
    -- Oil is intentionally untouched. Tiny starter patches are spawned near
    -- the starting area only to protect progression/unlock triggers.
    {
        type = "string-setting",
        setting_type = "startup",
        name = "the-cave-digging-mode",
        default_value = "disabled",
        allowed_values = { "disabled", "hardcore", "digging-1", "digging-2", "digging-3", "digging-4" },
        order = "0-f",
    },

    -- Startup: optional player-placed TNT Boxes, independent of every scenario.
    -- Only this setting controls the prototypes, research and runtime mechanic.
    {
        type = "string-setting",
        setting_type = "startup",
        name = "the-cave-tnt-boxes",
        default_value = "enabled",
        allowed_values = { "enabled", "disabled" },
        order = "0-g",
    },

    -- Startup: optional integrated Damage Indicator. Default ON so the new visual
    -- combat feedback is enabled, but hosts can disable it for a cleaner UI or
    -- conservative multiplayer/UPS testing.
    {
        type = "string-setting",
        setting_type = "startup",
        name = "the-cave-integrated-damage-indicator",
        default_value = "enabled",
        allowed_values = { "enabled", "disabled" },
        order = "a-d",
    },

    -- Startup: scales all finite technology research costs while The Cave is active. Medium is the normal/base balance.
    -- This is a direct multiplier from the original cost, never cumulative from the previous difficulty.
    {
        type = "string-setting",
        setting_type = "startup",
        name = "the-cave-research-level-difficulty",
        default_value = "medium",
        allowed_values = { "very-easy", "easy", "medium", "hard", "very-hard", "marathon" },
        order = "a-e",
    },
    -- Startup: optional expansion belt-stacking route for Space Age owners.
    -- ON keeps The Cave's Stack Inserter / Transport Belt Capacity path in both normal Factorio
    -- and Space Age. OFF keeps vanilla behaviour for the currently active game mode.
    {
        type = "string-setting",
        setting_type = "startup",
        name = "the-cave-early-stack-size",
        default_value = "enabled",
        allowed_values = { "enabled", "disabled" },
        order = "a-f",
    },
    -- Startup: consumed at data stage by the nauvis map-gen takeover.
    {
        type = "int-setting",
        setting_type = "startup",
        name = "diggy-carve-out-radius",
        default_value = 20,
        minimum_value = 6,
        maximum_value = 40,
        order = "c-a",
    },
    -- Runtime: difficulty knobs, host-tunable mid-game.
    {
        type = "double-setting",
        setting_type = "runtime-global",
        name = "diggy-dig-biter-chance",
        hidden = true,
        default_value = 0.045,
        minimum_value = 0,
        maximum_value = 1,
        order = "b-a",
    },
    {
        type = "double-setting",
        setting_type = "runtime-global",
        name = "diggy-dig-nest-chance",
        hidden = true,
        default_value = 0,
        minimum_value = 0,
        maximum_value = 1,
        order = "b-b",
    },
    {
        type = "bool-setting",
        setting_type = "runtime-global",
        name = "diggy-collapse-enabled",
        hidden = true,
        default_value = false,
        order = "c-a",
    },
    {
        type = "double-setting",
        setting_type = "runtime-global",
        name = "diggy-wall-support",
        hidden = true,
        default_value = 3,
        minimum_value = 1,
        maximum_value = 5,
        order = "c-d",
    },
    {
        type = "double-setting",
        setting_type = "runtime-global",
        name = "diggy-strut-strength-max",
        hidden = true,
        default_value = 1,
        minimum_value = 0.5,
        maximum_value = 1.5,
        order = "c-e",
    },
    {
        type = "int-setting",
        setting_type = "runtime-global",
        name = "diggy-cavern-countdown",
        hidden = true,
        default_value = 12,
        minimum_value = 3,
        maximum_value = 60,
        order = "c-g",
    },
    {
        type = "double-setting",
        setting_type = "runtime-global",
        name = "diggy-wall-crowding",
        hidden = true,
        default_value = 1.2,
        minimum_value = 0,
        maximum_value = 2.4,
        order = "c-f",
    },
    {
        type = "bool-setting",
        setting_type = "runtime-global",
        name = "diggy-collapse-broadcast",
        hidden = true,
        default_value = false,
        order = "c-b",
    },
    {
        type = "bool-setting",
        setting_type = "runtime-global",
        name = "diggy-crushed-remains",
        hidden = true,
        default_value = false,
        order = "c-c",
    },
    {
        type = "double-setting",
        setting_type = "runtime-global",
        name = "diggy-treasure-chance",
        default_value = 0.005,
        minimum_value = 0,
        maximum_value = 1,
        order = "b-d",
    },
    {
        type = "double-setting",
        setting_type = "runtime-global",
        name = "diggy-cavern-chance",
        default_value = 0.05,
        minimum_value = 0,
        maximum_value = 1,
        order = "b-e",
    },
    {
        type = "bool-setting",
        setting_type = "runtime-global",
        name = "diggy-enemy-expansion",
        hidden = true,
        default_value = true,
        order = "b-c",
    },

    -- Startup: automatically repairs damaged placeable items inside player inventories using repair packs.
    -- Default ON because it is a quality-of-life feature requested by players.
    {
        type = "string-setting",
        setting_type = "startup",
        name = "the-cave-auto-inventory-repair",
        default_value = "enabled",
        allowed_values = { "enabled", "disabled" },
        order = "a-f-1",
    },
    {
        type = "double-setting",
        setting_type = "runtime-global",
        name = "diggy-pack-size-multiplier",
        hidden = true,
        default_value = 3.0,
        minimum_value = 0.1,
        maximum_value = 10,
        order = "b-f",
    },
    {
        type = "double-setting",
        setting_type = "runtime-global",
        name = "diggy-cavern-worm-multiplier",
        hidden = true,
        default_value = 1.0,
        minimum_value = 0,
        maximum_value = 10,
        order = "b-g",
    },
})

-- The Cave: live Train Wave reward amounts.
-- Zero disables that reward for the selected tier. Values are read when the
-- enemy dies, so server admins can rebalance rewards immediately without a
-- restart or Wave reset. Biters and Spitters share the value for their tier.
data:extend({
  {
    type = "int-setting",
    setting_type = "runtime-global",
    name = "the-cave-train-wave-small-coin-drop",
    default_value = 2,
    minimum_value = 0,
    maximum_value = 1000,
    order = "train-wave-rewards-a-a"
  },
  {
    type = "int-setting",
    setting_type = "runtime-global",
    name = "the-cave-train-wave-small-resource-drop",
    default_value = 0,
    minimum_value = 0,
    maximum_value = 1000,
    order = "train-wave-rewards-a-b"
  },
  {
    type = "int-setting",
    setting_type = "runtime-global",
    name = "the-cave-train-wave-medium-coin-drop",
    default_value = 3,
    minimum_value = 0,
    maximum_value = 1000,
    order = "train-wave-rewards-b-a"
  },
  {
    type = "int-setting",
    setting_type = "runtime-global",
    name = "the-cave-train-wave-medium-resource-drop",
    default_value = 0,
    minimum_value = 0,
    maximum_value = 1000,
    order = "train-wave-rewards-b-b"
  },
  {
    type = "int-setting",
    setting_type = "runtime-global",
    name = "the-cave-train-wave-big-coin-drop",
    default_value = 4,
    minimum_value = 0,
    maximum_value = 1000,
    order = "train-wave-rewards-c-a"
  },
  {
    type = "int-setting",
    setting_type = "runtime-global",
    name = "the-cave-train-wave-big-resource-drop",
    default_value = 0,
    minimum_value = 0,
    maximum_value = 1000,
    order = "train-wave-rewards-c-b"
  },
  {
    type = "int-setting",
    setting_type = "runtime-global",
    name = "the-cave-train-wave-behemoth-coin-drop",
    default_value = 6,
    minimum_value = 0,
    maximum_value = 1000,
    order = "train-wave-rewards-d-a"
  },
  {
    type = "int-setting",
    setting_type = "runtime-global",
    name = "the-cave-train-wave-behemoth-resource-drop",
    default_value = 0,
    minimum_value = 0,
    maximum_value = 1000,
    order = "train-wave-rewards-d-b"
  },
  {
    type = "int-setting",
    setting_type = "runtime-global",
    name = "the-cave-train-wave-boss-coin-drop",
    default_value = 6,
    minimum_value = 0,
    maximum_value = 1000,
    order = "train-wave-rewards-e-a"
  },
  {
    type = "int-setting",
    setting_type = "runtime-global",
    name = "the-cave-train-wave-boss-resource-drop",
    default_value = 0,
    minimum_value = 0,
    maximum_value = 1000,
    order = "train-wave-rewards-e-b"
  }
})


-- The Cave: Underground lighting mode
data:extend({
  {
    type = "string-setting",
    name = "the-cave-underground-lighting-mode",
    setting_type = "startup",
    default_value = "permanent-night",
    allowed_values = {"normal", "permanent-day", "permanent-night", "pitch-black"},
    order = "b-c"
  }
})

-- The Cave: corpse cleaner radius
data:extend({
  {
    type = "int-setting",
    name = "the-cave-corpse-clean-radius",
    setting_type = "runtime-per-user",
    default_value = 80,
    minimum_value = 1,
    maximum_value = 1600,
    order = "zz-corpse-radius"
  }
})

-- The Cave: automatic corpse/stump/remnant fade settings
data:extend({
  {
    type = "int-setting",
    name = "the-cave-tree-stump-fade-time",
    setting_type = "runtime-per-user",
    default_value = 54000,
    minimum_value = 0,
    maximum_value = 216000,
    order = "zz-auto-fade-a"
  },
  {
    type = "int-setting",
    name = "the-cave-enemy-corpse-fade-time",
    setting_type = "runtime-per-user",
    default_value = 54000,
    minimum_value = 0,
    maximum_value = 216000,
    order = "zz-auto-fade-b"
  },
  {
    type = "int-setting",
    name = "the-cave-building-remnant-fade-time",
    setting_type = "runtime-per-user",
    default_value = 54000,
    minimum_value = 0,
    maximum_value = 216000,
    order = "zz-auto-fade-c"
  },
  {
    type = "int-setting",
    name = "the-cave-rail-remnant-fade-time",
    setting_type = "runtime-per-user",
    default_value = 54000,
    minimum_value = 0,
    maximum_value = 216000,
    order = "zz-auto-fade-d"
  }
})



-- The Cave: Chest capacity settings
data:extend({
  {
    type = "int-setting",
    name = "the-cave-wooden-chest-capacity",
    setting_type = "startup",
    default_value = 16,
    minimum_value = 16,
    maximum_value = 28,
    order = "d-a"
  },
  {
    type = "int-setting",
    name = "the-cave-iron-chest-capacity",
    setting_type = "startup",
    default_value = 32,
    minimum_value = 32,
    maximum_value = 60,
    order = "d-b"
  },
  {
    type = "int-setting",
    name = "the-cave-steel-chest-capacity",
    setting_type = "startup",
    default_value = 48,
    minimum_value = 48,
    maximum_value = 80,
    order = "d-c"
  },
  {
    type = "int-setting",
    name = "the-cave-logistic-chest-capacity",
    setting_type = "startup",
    default_value = 48,
    minimum_value = 48,
    maximum_value = 80,
    order = "d-d"
  }
})


-- The Cave: Selected resource and crop stack size settings
-- Startup-only because item prototype stack sizes are defined during the data stage.
data:extend({
  {
    type = "int-setting",
    name = "the-cave-iron-ore-stack-size",
    setting_type = "startup",
    default_value = 200,
    minimum_value = 50,
    maximum_value = 400,
    order = "e-a"
  },
  {
    type = "int-setting",
    name = "the-cave-copper-ore-stack-size",
    setting_type = "startup",
    default_value = 200,
    minimum_value = 50,
    maximum_value = 400,
    order = "e-b"
  },
  {
    type = "int-setting",
    name = "the-cave-coal-stack-size",
    setting_type = "startup",
    default_value = 200,
    minimum_value = 50,
    maximum_value = 400,
    order = "e-c"
  },
  {
    type = "int-setting",
    name = "the-cave-stone-stack-size",
    setting_type = "startup",
    default_value = 200,
    minimum_value = 50,
    maximum_value = 400,
    order = "e-d"
  },
  {
    type = "int-setting",
    name = "the-cave-uranium-ore-stack-size",
    setting_type = "startup",
    default_value = 200,
    minimum_value = 50,
    maximum_value = 400,
    order = "e-e"
  },
  {
    type = "int-setting",
    name = "the-cave-scrap-stack-size",
    setting_type = "startup",
    default_value = 200,
    minimum_value = 50,
    maximum_value = 400,
    order = "e-f"
  },
  {
    type = "int-setting",
    name = "the-cave-calcite-stack-size",
    setting_type = "startup",
    default_value = 200,
    minimum_value = 50,
    maximum_value = 400,
    order = "e-g"
  },
  {
    type = "int-setting",
    name = "the-cave-tungsten-ore-stack-size",
    setting_type = "startup",
    default_value = 200,
    minimum_value = 50,
    maximum_value = 400,
    order = "e-h"
  },
  {
    type = "int-setting",
    name = "the-cave-fulgora-scrap-stack-size",
    setting_type = "startup",
    default_value = 200,
    minimum_value = 50,
    maximum_value = 400,
    order = "e-i"
  },
  {
    type = "int-setting",
    name = "the-cave-yumako-stack-size",
    setting_type = "startup",
    default_value = 200,
    minimum_value = 50,
    maximum_value = 400,
    order = "e-j"
  },
  {
    type = "int-setting",
    name = "the-cave-jellynut-stack-size",
    setting_type = "startup",
    default_value = 200,
    minimum_value = 50,
    maximum_value = 400,
    order = "e-k"
  }
})



-- The Cave: Global difficulty system
data:extend({
  {
    type = "string-setting",
    name = "the-cave-global-difficulty",
    setting_type = "startup",
    default_value = "medium",
    allowed_values = {"easy", "medium", "hard", "nightmare"},
    order = "b-b"
  }
})


-- The Cave: Ore Patch Protection
data:extend({
  {
    type = "string-setting",
    name = "the-cave-ore-patch-protection",
    setting_type = "startup",
    default_value = "disabled",
    allowed_values = { "enabled", "disabled" },
    order = "a-e"
  }
})



-- The Cave integrated Damage Indicator settings (Dummiez, GPLv3)
-- Integrated Damage Indicator settings (original by Dummiez, GPLv3)

local function damage_type_color_setting(name, default_value, order)
  return {
    type = "color-setting",
    name = "damage-indicator-color-" .. name,
    setting_type = "runtime-per-user",
    default_value = default_value,
    order = order
  }
end

data:extend({
  {
    type = "int-setting",
    name = "damage-indicator-lifetime",
    setting_type = "runtime-per-user",
    default_value = 72,
    minimum_value = 24,
    maximum_value = 180,
    order = "aa"
  },
  {
    type = "double-setting",
    name = "damage-indicator-animation-speed",
    setting_type = "runtime-per-user",
    default_value = 1,
    minimum_value = 0.5,
    maximum_value = 3,
    order = "ab"
  },
  {
    type = "double-setting",
    name = "damage-indicator-color-intensity-cap",
    setting_type = "runtime-per-user",
    default_value = 3000,
    minimum_value = 10,
    maximum_value = 100000,
    order = "ac"
  },
  {
    type = "string-setting",
    name = "damage-indicator-color-mode",
    setting_type = "runtime-per-user",
    default_value = "damage-type",
    allowed_values = { "damage-type", "damage-ramp" },
    order = "ad"
  },
  {
    type = "bool-setting",
    name = "damage-indicator-blend-damage-type-colors",
    setting_type = "runtime-per-user",
    default_value = true,
    order = "ad2"
  },
  damage_type_color_setting("physical", { r = 255 / 255, g = 241 / 255, b = 92 / 255 }, "ad3a"),
  damage_type_color_setting("impact", { r = 255 / 255, g = 216 / 255, b = 187 / 255 }, "ad3b"),
  damage_type_color_setting("explosion", { r = 255 / 255, g = 92 / 255, b = 40 / 255 }, "ad3c"),
  damage_type_color_setting("fire", { r = 226 / 255, g = 132 / 255, b = 28 / 255 }, "ad3d"),
  damage_type_color_setting("laser", { r = 255 / 255, g = 112 / 255, b = 104 / 255 }, "ad3e"),
  damage_type_color_setting("electric", { r = 94 / 255, g = 218 / 255, b = 255 / 255 }, "ad3f"),
  damage_type_color_setting("acid", { r = 168 / 255, g = 210 / 255, b = 82 / 255 }, "ad3g"),
  damage_type_color_setting("poison", { r = 205 / 255, g = 146 / 255, b = 255 / 255 }, "ad3h"),
  {
    type = "string-setting",
    name = "damage-indicator-font-family",
    setting_type = "runtime-per-user",
    default_value = "default-bold",
    allowed_values = { "default-bold", "default-semibold", "default", "default-mono" },
    order = "ae"
  },
  {
    type = "int-setting",
    name = "damage-indicator-font-size",
    setting_type = "runtime-per-user",
    default_value = 16,
    minimum_value = 8,
    maximum_value = 64,
    order = "af"
  },
  {
    type = "bool-setting",
    name = "damage-indicator-color-intensity",
    setting_type = "runtime-per-user",
    default_value = true,
    order = "ag"
  },
  {
    type = "double-setting",
    name = "damage-indicator-drift-distance",
    setting_type = "runtime-per-user",
    default_value = 3,
    minimum_value = 0,
    maximum_value = 10,
    order = "ah"
  },
  {
    type = "string-setting",
    name = "damage-indicator-drift-style",
    setting_type = "runtime-per-user",
    default_value = "away-from-shooter",
    allowed_values = { "away-from-shooter", "upward", "mixed" },
    order = "ai"
  },
  {
    type = "int-setting",
    name = "damage-indicator-max-active",
    setting_type = "runtime-global",
    default_value = 300,
    minimum_value = 100,
    maximum_value = 1000,
    order = "ak"
  },
  {
    type = "double-setting",
    name = "damage-indicator-group-similar-distance",
    setting_type = "runtime-global",
    default_value = 5,
    minimum_value = 0,
    maximum_value = 20,
    order = "ak2"
  },
  {
    type = "string-setting",
    name = "damage-indicator-whitelist-entity-types",
    setting_type = "runtime-global",
    default_value = "asteroid",
    allow_blank = true,
    order = "ak2a"
  },
  {
    type = "double-setting",
    name = "damage-indicator-whitelist-distance-bonus",
    setting_type = "runtime-global",
    default_value = 15,
    minimum_value = 0,
    maximum_value = 50,
    order = "ak2b"
  },
  {
    type = "int-setting",
    name = "damage-indicator-saturation-threshold",
    setting_type = "runtime-global",
    default_value = 10,
    minimum_value = 2,
    maximum_value = 50,
    order = "ak2b2"
  },
  {
    type = "string-setting",
    name = "damage-indicator-blacklist-entity-names",
    setting_type = "runtime-global",
    default_value = "",
    allow_blank = true,
    order = "ak2c"
  },
  {
    -- Group-key normalization patterns for entities whose internal names contain
    -- a versioned/tiered suffix (e.g. Rampant's `spitter-spawn-v1-t10-rampant`,
    -- `behemoth-biter-v3-t8-rampant`). Each comma-separated entry is a Lua pattern
    -- with ONE capture group `(...)` that extracts the base name. The captured
    -- portion becomes the grouping identity (so all variants merge) and is also
    -- title-cased for display in the group count tag. Patterns are tried in order;
    -- the first match wins. Use `%-` to escape literal hyphens in patterns.
    -- Empty value disables normalization. Eg: ^(.-)%-v%d+%-t%d+%-rampant$
    type = "string-setting",
    name = "damage-indicator-group-name-normalize",
    setting_type = "runtime-global",
    default_value = "^(.-)%-v%d+%-t%d+.*$",
    allow_blank = true,
    order = "ak2d"
  },
  {
    type = "bool-setting",
    name = "damage-indicator-show-group-count",
    setting_type = "runtime-per-user",
    default_value = true,
    order = "ak3"
  },
  {
    type = "int-setting",
    name = "damage-indicator-combine-ticks",
    setting_type = "runtime-global",
    default_value = 30,
    minimum_value = 6,
    maximum_value = 120,
    order = "am"
  },
  {
    type = "string-setting",
    name = "damage-indicator-font",
    setting_type = "runtime-global",
    default_value = "damage-indicator-font",
    allowed_values = {
      "damage-indicator-font",
      "compi",
      "console",
      "count-font",
      "debug",
      "debug-mono",
      "default",
      "default-bold",
      "default-dialog-button",
      "default-dropdown",
      "default-game",
      "default-game-font",
      "default-large",
      "default-large-bold",
      "default-large-semibold",
      "default-listbox",
      "default-semibold",
      "default-small",
      "default-small-bold",
      "default-small-semibold",
      "default-tiny-bold",
      "heading-1",
      "heading-2",
      "infinite",
      "item-count",
      "locale-pick",
      "scenario-message-dialog",
      "technology-slot-level-font",
      "var"
    },
    order = "aea"
  },
  {
    type = "bool-setting",
    name = "damage-indicator-compact-numbers",
    setting_type = "runtime-per-user",
    default_value = false,
    order = "ao"
  },
  {
    type = "string-setting",
    name = "damage-indicator-number-separator",
    setting_type = "runtime-per-user",
    default_value = "commas",
    allowed_values = { "none", "commas", "points" },
    order = "ao2"
  },
  {
    type = "string-setting",
    name = "damage-indicator-shadow-style",
    setting_type = "runtime-per-user",
    default_value = "light",
    allowed_values = { "off", "light", "heavy" },
    order = "ap"
  },
  {
    type = "bool-setting",
    name = "damage-indicator-show-reductions",
    setting_type = "runtime-per-user",
    default_value = true,
    order = "ar"
  },
  {
    type = "bool-setting",
    name = "damage-indicator-alt-mode",
    setting_type = "runtime-per-user",
    default_value = false,
    order = "ar2"
  },
  {
    type = "bool-setting",
    name = "damage-indicator-debug-info",
    setting_type = "runtime-per-user",
    default_value = false,
    order = "az3"
  },
  {
    type = "string-setting",
    name = "damage-indicator-text-template",
    setting_type = "runtime-per-user",
    default_value = "__damage__",
    order = "at"
  },
  {
    type = "int-setting",
    name = "damage-indicator-text-update-interval",
    setting_type = "runtime-global",
    default_value = 6,
    minimum_value = 1,
    maximum_value = 60,
    order = "au"
  },
  -- Server-side override for per-user display settings. When a valid encoded string
  -- is present, all players see indicators using the encoded settings (with the
  -- exception of `damage-indicator-enabled`, which each player still controls). Use
  -- the in-game command /damage-indicators-override to produce a string from
  -- the current player's settings, then paste it into this setting.
  {
    type = "string-setting",
    name = "damage-indicator-server-override-string",
    setting_type = "runtime-global",
    default_value = "",
    allow_blank = true,
    order = "zz2"
  },
  -- {
  --   type = "bool-setting",
  --   name = "damage-indicator-rich-text",
  --   setting_type = "startup",
  --   default_value = true,
  --   order = "av"
  -- },
  {
    type = "bool-setting",
    name = "damage-indicator-viewport-culling",
    setting_type = "runtime-global",
    default_value = true,
    order = "aw"
  },
  {
    type = "double-setting",
    name = "damage-indicator-viewport-margin",
    setting_type = "runtime-global",
    default_value = 12,
    minimum_value = 0,
    maximum_value = 100,
    order = "ax"
  },
  {
    type = "bool-setting",
    name = "damage-indicator-killing-blow",
    setting_type = "runtime-per-user",
    default_value = true,
    order = "az"
  },
  {
    type = "string-setting",
    name = "damage-indicator-killing-blow-marker",
    setting_type = "runtime-per-user",
    default_value = "!",
    allow_blank = true,
    order = "az2"
  },
  {
    type = "bool-setting",
    name = "damage-indicator-enabled",
    setting_type = "runtime-per-user",
    default_value = true,
    order = "aa1"
  },
  {
    type = "int-setting",
    name = "damage-indicator-radius",
    setting_type = "runtime-per-user",
    default_value = 80,
    minimum_value = 10,
    maximum_value = 200,
    order = "aa2"
  },
  {
    type = "string-setting",
    name = "damage-indicator-visibility",
    setting_type = "runtime-per-user",
    default_value = "nearby",
    allowed_values = { "nearby", "own-force", "outgoing" },
    order = "aa3"
  },
  {
    type = "double-setting",
    name = "damage-indicator-scale",
    setting_type = "runtime-per-user",
    default_value = 1,
    minimum_value = 0.5,
    maximum_value = 2,
    order = "aa4"
  },
  {
    type = "double-setting",
    name = "damage-indicator-minimum-damage",
    setting_type = "runtime-per-user",
    default_value = 0.1,
    minimum_value = 0,
    maximum_value = 1000,
    order = "aa5"
  },
})

-- The Cave Inserter Configuration settings.
require("prototypes.inserter_config_settings")

-- The Cave 2.4.16: integrated Squeak Through Startup settings.
-- Kept as one ordered block at the bottom of The Cave's Startup tab.
require("prototypes.squeak_through_settings")

-- The Cave 2.5.29: integrated Lamp Post startup setting.
require("prototypes.lamp_post_settings")

-- The Cave 2.5.31: integrated Electric Furnaces startup settings.
require("prototypes.electric_furnaces_settings")


-- The Cave 2.5.81: configurable per-player Starter Pack.
require("prototypes.starter_pack_settings")

-- The Cave 2.5.32: integrated Faster Start startup setting.
require("prototypes.faster_start_settings")

-- The Cave 2.5.35: integrated Chemical Rockets startup setting.
require("prototypes.chemical_rocket_settings")

-- The Cave 2.5.36: integrated Superheating startup settings.
require("prototypes.superheating_settings")

-- The Cave 2.6.14: capacities for independent industrial containers.
require("prototypes.industrial_container_settings")

-- The Cave 2.6.16: native, fixed-colour production status indicators.
require("prototypes.production_status_settings")

-- The Cave 2.6.23: optional fixed-capacity Extra Storage Tanks.
require("prototypes.extra_storage_tank_settings")

-- The Cave 2.7.15: per-player ALT-mode ammo count for nearby ammo turrets.
require("prototypes.nearby_ammo_count_settings")

-- The Cave 2.7.22: event-driven local copper-wire cleanup for player poles.
require("prototypes.minimal_wire_settings")

-- The Cave 2.7.23: integrated FuelGlow startup settings.
require("prototypes.fuel_glow_settings")
