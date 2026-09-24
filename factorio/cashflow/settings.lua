data:extend({
  { type = "int-setting", name = "cf-job-income", setting_type = "runtime-global", default_value = 5000, minimum_value = 0, order = "a" },
  { type = "int-setting", name = "cf-needs", setting_type = "runtime-global", default_value = 2000, minimum_value = 0, order = "b" },
  { type = "int-setting", name = "cf-wants", setting_type = "runtime-global", default_value = 800, minimum_value = 0, order = "c" },
  { type = "int-setting", name = "cf-starting-debt", setting_type = "runtime-global", default_value = 18000, minimum_value = 0, order = "d" },
  { type = "double-setting", name = "cf-debt-apr", setting_type = "runtime-global", default_value = 18, minimum_value = 0, maximum_value = 100, order = "e" },
  { type = "int-setting", name = "cf-starting-assets", setting_type = "runtime-global", default_value = 12000, minimum_value = 0, order = "f" },
  { type = "double-setting", name = "cf-asset-return", setting_type = "runtime-global", default_value = 7, minimum_value = 0, maximum_value = 100, order = "g" },
  { type = "double-setting", name = "cf-game-speed", setting_type = "runtime-global", default_value = 1, minimum_value = 1, maximum_value = 10, order = "h" },
})
