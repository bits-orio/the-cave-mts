-- Shared reward-only exclusions. World-placed rolling stock, discovered train
-- parts, player inventories, crafting and train registration are deliberately
-- outside this policy.

local game_mode = require("scripts.game_mode")

local reward_policy = {}

local TRAIN_REWARD_ITEMS = {
    ["locomotive"] = true,
    ["cargo-wagon"] = true,
    ["fluid-wagon"] = true,
    ["artillery-wagon"] = true,
}

function reward_policy.train_reward_blacklist_active()
    return game_mode.train_enabled()
end

function reward_policy.is_train_reward_item(name)
    return TRAIN_REWARD_ITEMS[name] == true
end

function reward_policy.is_allowed(name)
    return not (reward_policy.train_reward_blacklist_active()
        and reward_policy.is_train_reward_item(name))
end

function reward_policy.is_blocked(name)
    return not reward_policy.is_allowed(name)
end

return reward_policy
