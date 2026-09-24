local fake = require("fake_factorio")

local function eq(actual, expected, msg)
  if actual ~= expected then
    error((msg or "") .. " expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
  end
end

local MONTH = 3600

local function start()
  local h = fake.install()
  h.init()
  local cf = storage.cf
  local player = h.add_player()
  return h, cf, player
end

local function press_start(h, player)
  h.fire("on_gui_click", { player_index = player.index, element = { name = "cf_toggle" } })
end

local T = {}

function T.inert_outside_scenario()
  local h = fake.install({ level = { level_name = "freeplay" } })
  h.init()
  eq(storage.cf, nil)
  h.run_ticks(60)
end

function T.setup_seeds_vault_ledger_and_player()
  local _, cf, player = start()
  eq(cf.entities.vault.chest.get_inventory().get_item_count("iron-plate"), 1200)
  eq(cf.entities.debt.landmark.get_inventory().get_item_count("copper-plate"), 1800)
  eq(cf.entities.needs.splitter.splitter_output_priority, "right")
  assert(player.gui.left.cf_panel, "panel created")
  eq(player.inventory.get_item_count("transport-belt"), 400)
  eq(player.inventory.get_item_count("cf-meter-belt"), 1)
  eq(player.surface.name, "cashflow")
end

function T.clock_paused_until_start()
  local h, cf = start()
  h.run_ticks(MONTH * 2)
  eq(cf.month, 0)
  eq(cf.paycheck_emitted, 0)
end

function T.unconnected_month_borrows_everything()
  local h, cf, player = start()
  press_start(h, player)
  h.run_ticks(MONTH)
  eq(cf.month, 1)
  -- $18,000 + $2,800 unpaid expenses + $270 interest
  eq(cf.debt_cents, 1800000 + 280000 + 27000)
  eq(cf.entities.debt.landmark.get_inventory().get_item_count("copper-plate"), 2107)
  -- 8 plates fit on the paycheck belt stub, the rest waits as idle cash
  eq(cf.paycheck_buffer, 492)
  -- $70 return is queued at the pulse and placed on the vault output at the next sweep
  eq(cf.last_report.return_plates, 7)
  eq(cf.vault_out_buffer, 7)
  assert(h.logs[#h.logs]:match("^%[cashflow%] month=1 "), "pulse logged")
  h.run_ticks(6)
  eq(cf.vault_out_buffer, 0)
end

function T.fed_drains_stop_at_quota_and_payments_reduce_debt()
  local h, cf, player = start()
  press_start(h, player)
  local needs_end = cf.entities.needs.drain_end.get_transport_line(1)
  local wants_end = cf.entities.wants.drain_end.get_transport_line(1)
  local debt_end = cf.entities.debt.drain_end.get_transport_line(1)
  needs_end.cap, wants_end.cap, debt_end.cap = 1000, 1000, 1000
  needs_end.count, wants_end.count, debt_end.count = 250, 80, 30
  h.run_ticks(MONTH)
  eq(cf.month, 1)
  eq(needs_end.count, 50, "needs leaves plates past quota on the belt")
  eq(cf.last_report.deficit_cents, 0)
  eq(cf.last_report.debt_paid_plates, 30)
  eq(cf.debt_cents, 1800000 - 30000 + 27000)
  assert(cf.goals.needs_fed and cf.goals.wants_fed and cf.goals.first_payment)
end

function T.vault_deposits_move_into_chest()
  local h, cf, player = start()
  press_start(h, player)
  local vin = cf.entities.vault.in_end.get_transport_line(2)
  vin.count = 4
  h.run_ticks(12)
  eq(vin.count, 0)
  eq(cf.entities.vault.chest.get_inventory().get_item_count("iron-plate"), 1204)
  assert(cf.goals.first_deposit)
end

function T.hand_picked_plates_return_to_paycheck()
  local h, cf, player = start()
  player.inventory.insert({ name = "iron-plate", count = 5 })
  h.fire("on_player_main_inventory_changed", { player_index = player.index })
  eq(player.inventory.get_item_count("iron-plate"), 0)
  eq(cf.paycheck_buffer, 5)
end

function T.win_and_quit_job()
  local h = fake.install({ settings = { ["cf-starting-debt"] = 0, ["cf-starting-assets"] = 480000 } })
  h.init()
  local cf = storage.cf
  local player = h.add_player()
  cf.entities.needs.drain_end.get_transport_line(1).cap = 1000
  cf.entities.needs.drain_end.get_transport_line(1).count = 200
  cf.entities.wants.drain_end.get_transport_line(1).cap = 1000
  cf.entities.wants.drain_end.get_transport_line(1).count = 80
  press_start(h, player)
  h.run_ticks(MONTH)
  assert(cf.won, "financially independent with $480k at 7% and $2,800 expenses")
  assert(player.gui.left.cf_panel.cf_buttons.cf_quit_job.visible, "quit button shown")
  h.fire("on_gui_click", { player_index = player.index, element = { name = "cf_quit_job" } })
  h.run_ticks(MONTH)
  eq(cf.last_report.paycheck_plates, 0)
end

return T
