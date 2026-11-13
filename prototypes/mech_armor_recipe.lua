-- Replace the MK2 ingredient with the agreed direct material cost. Grid
-- research changes the MK2 prototype, so it cannot be a stable ingredient.
local recipe = data.raw.recipe['mech-armor']
if not recipe then return end
local removed = false
for i=#recipe.ingredients,1,-1 do
    if recipe.ingredients[i].name == 'power-armor-mk2' then
        table.remove(recipe.ingredients, i)
        removed = true
    end
end
if not removed then return end
for _,extra in ipairs({{'processing-unit',60}, {'electric-engine-unit',40},
    {'low-density-structure',30}, {'speed-module',100}, {'efficiency-module',100}}) do
    local found = false
    for _,ingredient in ipairs(recipe.ingredients) do
        if ingredient.name == extra[1] and ingredient.type == 'item' then
            ingredient.amount = ingredient.amount + extra[2]
            found = true
            break
        end
    end
    if not found then
        recipe.ingredients[#recipe.ingredients+1] = {type='item',name=extra[1],amount=extra[2]}
    end
end

-- Recycler recipes were generated earlier in data-updates. Rebuild only this
-- reverse recipe and avoid duplicating its existing technology unlock.
if mods["recycler"] then
    local tech=data.raw.technology["recycling"]
    if tech then
        for i=#(tech.effects or {}),1,-1 do
            local effect=tech.effects[i]
            if effect.type=="unlock-recipe" and effect.recipe=="mech-armor-recycling" then table.remove(tech.effects,i) end
        end
    end
    require("__recycler__.recycling").generate_recycling_recipe(recipe)
end
