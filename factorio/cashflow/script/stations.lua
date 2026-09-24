local acc = require("script.accounting")

local M = {}

local PLATE = "iron-plate"
local DEBT = "copper-plate"
local LINES = { 1, 2 }

-- Places up to n plates at the back of a belt; returns how many fit.
function M.push(belt, n)
  local placed = 0
  while placed < n do
    local progressed = false
    for _, i in ipairs(LINES) do
      if placed < n and belt.get_transport_line(i).insert_at_back({ name = PLATE, count = 1 }) then
        placed = placed + 1
        progressed = true
      end
    end
    if not progressed then
      break
    end
  end
  return placed
end

-- Removes up to n plates from a belt; returns how many were removed.
function M.take(belt, n)
  local taken = 0
  for _, i in ipairs(LINES) do
    if taken >= n then
      break
    end
    taken = taken + belt.get_transport_line(i).remove_item({ name = PLATE, count = n - taken })
  end
  return taken
end

function M.sync_ledger(cf)
  local inv = cf.entities.debt.landmark.get_inventory(defines.inventory.chest)
  local target = acc.plates_for_debt(cf.debt_cents)
  local have = inv.get_item_count(DEBT)
  if have < target then
    inv.insert({ name = DEBT, count = target - have })
  elseif have > target then
    inv.remove({ name = DEBT, count = have - target })
  end
end

function M.vault_plates(cf)
  return cf.entities.vault.chest.get_inventory(defines.inventory.chest).get_item_count(PLATE)
end

function M.seed_vault(cf, plates)
  if plates > 0 then
    cf.entities.vault.chest.get_inventory(defines.inventory.chest).insert({ name = PLATE, count = plates })
  end
end

local function sweep_paycheck(cf)
  if not cf.job_quit then
    local due = acc.paycheck_due(cf.plan.paycheck_plates, cf.tick_in_month)
    cf.paycheck_buffer = cf.paycheck_buffer + (due - cf.paycheck_emitted)
    cf.paycheck_emitted = due
  end
  cf.paycheck_buffer = cf.paycheck_buffer - M.push(cf.entities.paycheck.out_first, cf.paycheck_buffer)
end

local function sweep_drain(cf, key, quota)
  local remaining = quota - cf.received[key]
  if remaining > 0 then
    cf.received[key] = cf.received[key] + M.take(cf.entities[key].drain_end, remaining)
  end
end

local function sweep_debt(cf)
  if cf.debt_cents <= 0 then
    return
  end
  local got = M.take(cf.entities.debt.drain_end, acc.plates_for_debt(cf.debt_cents))
  if got > 0 then
    cf.debt_cents = math.max(0, cf.debt_cents - got * acc.CENTS_PER_PLATE)
    cf.debt_paid_plates = cf.debt_paid_plates + got
    cf.goals.first_payment = true
  end
end

local function sweep_vault(cf)
  local v = cf.entities.vault
  local inv = v.chest.get_inventory(defines.inventory.chest)
  local waiting = 0
  for _, i in ipairs(LINES) do
    waiting = waiting + v.in_end.get_transport_line(i).get_item_count(PLATE)
  end
  if waiting > 0 then
    local fits = inv.get_insertable_count(PLATE)
    local got = M.take(v.in_end, math.min(waiting, fits))
    if got > 0 then
      inv.insert({ name = PLATE, count = got })
      cf.deposit_plates = cf.deposit_plates + got
      cf.goals.first_deposit = true
    end
  end
  cf.vault_out_buffer = cf.vault_out_buffer - M.push(v.out_first, cf.vault_out_buffer)
end

function M.sweep(cf, ticks)
  cf.tick_in_month = cf.tick_in_month + ticks
  sweep_paycheck(cf)
  sweep_drain(cf, "needs", cf.plan.needs_quota)
  sweep_drain(cf, "wants", cf.plan.wants_quota)
  if cf.received.needs > 0 then
    cf.goals.needs_fed = true
  end
  if cf.received.wants > 0 then
    cf.goals.wants_fed = true
  end
  sweep_debt(cf)
  sweep_vault(cf)
  M.sync_ledger(cf)
end

return M
