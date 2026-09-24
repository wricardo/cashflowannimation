local acc = require("script.accounting")
local config = require("script.config")
local layout = require("script.layout")
local world = require("script.world")
local stations = require("script.stations")
local pulse = require("script.pulse")
local meter = require("script.meter")
local labels = require("script.labels")
local gui = require("script.gui")
local guard = require("script.guard")

-- Every 2 ticks so output belts can be filled at full yellow-belt speed.
local SWEEP_TICKS = 2
local REFRESH_TICKS = 30

local function in_our_scenario()
  local level = script.level
  return level and level.mod_name == "cashflow" and level.level_name == "cashflow"
end

local function refresh(cf)
  local vault_plates = stations.vault_plates(cf)
  labels.refresh(cf, vault_plates)
  gui.refresh(cf, vault_plates)
end

local function setup_player(cf, player)
  local surface = game.surfaces[layout.surface]
  local pos = surface.find_non_colliding_position("character", layout.spawn, 10, 1) or layout.spawn
  player.teleport(pos, surface)
  gui.create(player)
  guard.check(cf, player)
  guard.give_meter(player)
  refresh(cf)
end

script.on_init(function()
  if not in_our_scenario() then
    return
  end
  local cfg = config.read()
  local surface = world.create_surface()
  local debt_cents = acc.plates(cfg.starting_debt) * acc.CENTS_PER_PLATE
  local cf = {
    running = false,
    won = false,
    job_quit = false,
    month = 0,
    tick_in_month = 0,
    debt_cents = debt_cents,
    opening_debt_cents = debt_cents,
    opening_principal_cents = 0,
    interest_carry_cents = 0,
    return_carry_cents = 0,
    emitted = { paycheck = 0, needs = 0, wants = 0 },
    out = stations.new_outputs(),
    node = { iron = 0, copper = 0 },
    stats = stations.new_month_stats(),
    consumed_total_cents = 0,
    plan = pulse.plan_month(cfg),
    goals = {},
    meters = {},
    entities = world.build_stations(surface),
  }
  storage.cf = cf
  stations.seed_vault(cf, math.floor(cfg.starting_assets / 10))
  cf.opening_principal_cents = stations.vault_plates(cf) * acc.CENTS_PER_PLATE
  stations.sync_ledger(cf)
  labels.create(cf, surface)
  game.speed = cfg.game_speed
  for _, player in pairs(game.players) do
    setup_player(cf, player)
  end
end)

script.on_event(defines.events.on_player_created, function(event)
  local cf = storage.cf
  if cf then
    setup_player(cf, game.get_player(event.player_index))
  end
end)

script.on_event(defines.events.on_chunk_generated, function(event)
  if storage.cf and event.surface.name == layout.surface then
    world.clean_area(event.surface, event.area)
  end
end)

script.on_nth_tick(SWEEP_TICKS, function(event)
  local cf = storage.cf
  if not cf then
    return
  end
  if cf.running then
    stations.sweep(cf, SWEEP_TICKS)
    meter.sweep(cf)
    if cf.tick_in_month >= acc.TICKS_PER_MONTH then
      pulse.close_month(cf)
      meter.close_month(cf)
    end
  end
  if event.tick % REFRESH_TICKS == 0 then
    refresh(cf)
  end
end)

script.on_event(defines.events.on_gui_click, function(event)
  local cf = storage.cf
  if not cf then
    return
  end
  local name = event.element.name
  if name == "cf_toggle" then
    cf.running = not cf.running
  elseif name == "cf_quit_job" and cf.won then
    cf.job_quit = true
    game.print("You quit your job. From now on only your vault's returns pay the bills.")
  else
    return
  end
  refresh(cf)
end)

script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
  if storage.cf and event.setting == "cf-game-speed" then
    game.speed = config.read().game_speed
  end
end)

script.on_event(defines.events.on_player_main_inventory_changed, function(event)
  local cf = storage.cf
  if cf then
    guard.check(cf, game.get_player(event.player_index))
  end
end)

local meter_filter = { { filter = "name", name = "cf-meter-belt" } }

script.on_event(defines.events.on_built_entity, function(event)
  if storage.cf then
    meter.add(storage.cf, event.entity)
  end
end, meter_filter)

local function on_meter_gone(event)
  if storage.cf then
    meter.remove(storage.cf, event.entity)
  end
end

script.on_event(defines.events.on_player_mined_entity, on_meter_gone, meter_filter)
script.on_event(defines.events.on_robot_mined_entity, on_meter_gone, meter_filter)
