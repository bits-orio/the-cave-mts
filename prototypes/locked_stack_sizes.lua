-- Only the specifically approved items. Optional content is never invented.
local sizes = {
    ammo = {
        ["firearm-magazine"] = 300, ["piercing-rounds-magazine"] = 300,
        ["uranium-rounds-magazine"] = 300, ["rocket"] = 300,
        ["explosive-rocket"] = 300, ["chemical-rocket"] = 300,
        ["incendiary-rocket"] = 300, ["artillery-shell"] = 100,
    },
    item = {
        ["iron-gear-wheel"] = 400, ["ice"] = 200, ["solid-fuel"] = 400,
        ["yumako-seed"] = 100, ["jellynut-seed"] = 100, ["stone-wall"] = 400,
        ["rocket-fuel"] = 100, ["nuclear-fuel"] = 100,
        ["the-cave-tnt-box-small"] = 100,
        ["the-cave-tnt-box-medium"] = 100,
        ["the-cave-tnt-box-large"] = 100,
    },
}
for kind, items in pairs(sizes) do
    for name, size in pairs(items) do
        local prototype = data.raw[kind] and data.raw[kind][name]
        if prototype then prototype.stack_size = size end
    end
end
