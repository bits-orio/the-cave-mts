local function dropdown(name, default_enabled, order)
  return {
    type = "string-setting",
    setting_type = "startup",
    name = name,
    default_value = default_enabled and "enabled" or "disabled",
    allowed_values = { "enabled", "disabled" },
    order = order,
  }
end

-- Factorio groups settings by the owning mod, so this block is placed at the
-- bottom of The Cave's Startup settings and every row carries a clear
-- "Squeak Through" prefix to keep it visually separate from the core options.
data:extend({
  dropdown("the-cave-squeak-through", true, "zz[squeak-through]-a[master]"),

  dropdown("the-cave-squeak-through-modify-chests", true, "zz[squeak-through]-b[categories]-a[chests]"),
  dropdown("the-cave-squeak-through-modify-circuits", true, "zz[squeak-through]-b[categories]-b[circuits]"),
  dropdown("the-cave-squeak-through-modify-drills", true, "zz[squeak-through]-b[categories]-c[drills]"),
  dropdown("the-cave-squeak-through-modify-machines", true, "zz[squeak-through]-b[categories]-d[machines]"),
  dropdown("the-cave-squeak-through-modify-pipes", true, "zz[squeak-through]-b[categories]-e[pipes]"),
  dropdown("the-cave-squeak-through-modify-solar", true, "zz[squeak-through]-b[categories]-f[solar]"),
  dropdown("the-cave-squeak-through-modify-steam", true, "zz[squeak-through]-b[categories]-g[steam]"),
  dropdown("the-cave-squeak-through-modify-trees", true, "zz[squeak-through]-b[categories]-h[trees]"),
  dropdown("the-cave-squeak-through-modify-turrets", true, "zz[squeak-through]-b[categories]-i[turrets]"),
  dropdown("the-cave-squeak-through-modify-misc", true, "zz[squeak-through]-b[categories]-j[misc]"),

  {
    type = "string-setting",
    setting_type = "startup",
    name = "the-cave-squeak-through-blacklist-types",
    default_value = "",
    allow_blank = true,
    order = "zz[squeak-through]-c[blacklists]-a[types]",
  },
  {
    type = "string-setting",
    setting_type = "startup",
    name = "the-cave-squeak-through-blacklist-names",
    default_value = "",
    allow_blank = true,
    order = "zz[squeak-through]-c[blacklists]-b[names]",
  },

  dropdown("the-cave-squeak-through-remove-collision", false, "zz[squeak-through]-d[remove]-a[enabled]"),
  {
    type = "string-setting",
    setting_type = "startup",
    name = "the-cave-squeak-through-remove-collision-types",
    default_value = "tree",
    allow_blank = true,
    order = "zz[squeak-through]-d[remove]-b[types]",
  },
  {
    type = "string-setting",
    setting_type = "startup",
    name = "the-cave-squeak-through-remove-collision-names",
    default_value = "",
    allow_blank = true,
    order = "zz[squeak-through]-d[remove]-c[names]",
  },
})
