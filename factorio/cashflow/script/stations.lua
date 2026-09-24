local acc = require("script.accounting")

local M = {}

local IRON = "iron-plate"
local COPPER = "copper-plate"
local P = acc.CENTS_PER_PLATE
local LINES = { 1, 2 }
local ALL = 100000

M.IRON, M.COPPER = IRON, COPPER

-- Output buffers: plates waiting to be placed on a station's output belt.
M.OUTPUTS = {
  { key = "paycheck", station = "paycheck", belt = "out", item = IRON },
  { key = "needs", station = "needs", belt = "out", item = COPPER },
  { key = "wants", station = "wants", belt = "out", item = COPPER },
  { key = "surplus", station = "cashflow", belt = "surplus_out", item = IRON },
  { key = "unpaid", station = "cashflow", belt = "unpaid_out", item = COPPER },
  { key = "interest", station = "debt", belt = "interest_out", item = COPPER },
  { key = "returns", station = "vault", belt = "return_out", item = IRON },
}

function M.new_outputs()
  local out = {}
  for _, o in ipairs(M.OUTPUTS) do
    out[o.key] = 0
  end
  return out
end

function M.new_month_stats()
  return { cash_in = 0, bills_in = 0, paid = 0, borrowed = 0, debt_paid = 0, deposits = 0, picked_copper = 0 }
end

-- Places up to n plates at the back of a belt; returns how many fit.
function M.push(belt, item, n)
  local placed = 0
  while placed < n do
    local progressed = false
    for _, i in ipairs(LINES) do
      if placed < n and belt.get_transport_line(i).insert_at_back({ name = item, count = 1 }) then
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

-- Removes up to n plates of an item from a belt; returns how many were removed.
function M.take(belt, item, n)
  local taken = 0
  for _, i in ipairs(LINES) do
    if taken >= n then
      break
    end
    taken = taken + belt.get_transport_line(i).remove_item({ name = item, count = n - taken })
  end
  return taken
end

function M.sync_ledger(cf)
  local inv = cf.entities.debt.landmark.get_inventory(defines.inventory.chest)
  local target = math.floor(cf.debt_cents / P)
  local have = inv.get_item_count(COPPER)
  if have < target then
    inv.insert({ name = COPPER, count = target - have })
  elseif have > target then
    inv.remove({ name = COPPER, count = have - target })
  end
end

function M.vault_plates(cf)
  return cf.entities.vault.chest.get_inventory(defines.inventory.chest).get_item_count(IRON)
end

function M.seed_vault(cf, plates)
  if plates > 0 then
    cf.entities.vault.chest.get_inventory(defines.inventory.chest).insert({ name = IRON, count = plates })
  end
end

local function emit(cf)
  for _, key in ipairs({ "paycheck", "needs", "wants" }) do
    if not (key == "paycheck" and cf.job_quit) then
      local due = acc.due_by_tick(cf.plan[key], cf.tick_in_month)
      cf.out[key] = cf.out[key] + (due - cf.emitted[key])
      cf.emitted[key] = due
    end
  end
end

-- Both Cashflow inputs accept iron and copper. One iron plate pays one copper bill.
local function sweep_cashflow(cf)
  local c, node, m = cf.entities.cashflow, cf.node, cf.stats
  for _, belt in ipairs({ c.cash_in, c.bills_in }) do
    local iron = M.take(belt, IRON, ALL)
    local copper = M.take(belt, COPPER, ALL)
    node.iron = node.iron + iron
    node.copper = node.copper + copper
    m.cash_in = m.cash_in + iron
    m.bills_in = m.bills_in + copper
  end
  local paired
  paired, node.iron, node.copper = acc.match(node.iron, node.copper)
  m.paid = m.paid + paired
  cf.consumed_total_cents = cf.consumed_total_cents + paired * P
  if m.cash_in > 0 then
    cf.goals.cash_in = true
  end
  if m.bills_in > 0 then
    cf.goals.bills_in = true
  end
end

-- Copper into either Debt input is borrowing; iron pays debt down while there is debt.
-- With no debt, iron is left on the belt: the PAY input backs up and its splitter passes it on.
local function sweep_debt(cf)
  local d, m = cf.entities.debt, cf.stats
  for _, belt in ipairs({ d.borrow_in, d.pay_in }) do
    local borrowed = M.take(belt, COPPER, ALL)
    if borrowed > 0 then
      cf.debt_cents = cf.debt_cents + borrowed * P
      m.borrowed = m.borrowed + borrowed
    end
    if cf.debt_cents > 0 then
      local paid = M.take(belt, IRON, math.floor(cf.debt_cents / P))
      if paid > 0 then
        cf.debt_cents = cf.debt_cents - paid * P
        m.debt_paid = m.debt_paid + paid
        cf.goals.first_payment = true
      end
    end
  end
end

local function sweep_vault(cf)
  local v = cf.entities.vault
  local inv = v.chest.get_inventory(defines.inventory.chest)
  local got = M.take(v.deposit_in, IRON, inv.get_insertable_count(IRON))
  if got > 0 then
    inv.insert({ name = IRON, count = got })
    cf.stats.deposits = cf.stats.deposits + got
    cf.goals.first_deposit = true
  end
end

local function push_outputs(cf)
  for _, o in ipairs(M.OUTPUTS) do
    local waiting = cf.out[o.key]
    if waiting > 0 then
      cf.out[o.key] = waiting - M.push(cf.entities[o.station][o.belt], o.item, waiting)
    end
  end
end

function M.sweep(cf, ticks)
  cf.tick_in_month = cf.tick_in_month + ticks
  emit(cf)
  sweep_cashflow(cf)
  sweep_debt(cf)
  sweep_vault(cf)
  push_outputs(cf)
  M.sync_ledger(cf)
end

return M
