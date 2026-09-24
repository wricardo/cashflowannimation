local acc = require("script.accounting")

local function eq(actual, expected, msg)
  if actual ~= expected then
    error((msg or "") .. " expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
  end
end

local T = {}

-- Same numbers as the default scenario in simulation.js / readme.md.
function T.debt_interest_matches_simulation()
  eq(acc.monthly_amount(1800000, 18), 27000)
end

function T.asset_return_matches_simulation()
  eq(acc.monthly_amount(1200000, 7), 7000)
end

function T.quota_rounds_up_to_whole_plates()
  eq(acc.quota_plates(2000), 200)
  eq(acc.quota_plates(805), 81)
  eq(acc.quota_plates(0), 0)
end

function T.plates_for_debt_rounds_up()
  eq(acc.plates_for_debt(0), 0)
  eq(acc.plates_for_debt(1), 1)
  eq(acc.plates_for_debt(27000), 27)
  eq(acc.plates_for_debt(27001), 28)
end

function T.paycheck_spreads_evenly_and_hits_total()
  eq(acc.paycheck_due(500, 0), 0)
  eq(acc.paycheck_due(500, 1800), 250)
  eq(acc.paycheck_due(500, 3600), 500)
  eq(acc.paycheck_due(500, 9999), 500)
  local prev = 0
  for t = 6, 3600, 6 do
    local due = acc.paycheck_due(500, t)
    assert(due >= prev, "paycheck must never go backwards")
    prev = due
  end
end

function T.close_drain_shortfall()
  local consumed, shortfall = acc.close_drain(120, 200)
  eq(consumed, 120)
  eq(shortfall, 80)
  consumed, shortfall = acc.close_drain(200, 200)
  eq(consumed, 200)
  eq(shortfall, 0)
end

function T.return_carry_accumulates_fractions()
  -- $5 return each month = half a plate
  local plates, carry = acc.split_return(500, 0)
  eq(plates, 0)
  eq(carry, 500)
  plates, carry = acc.split_return(500, carry)
  eq(plates, 1)
  eq(carry, 0)
end

local function default_state()
  return {
    debt_cents = 1800000,
    opening_debt_cents = 1800000,
    opening_principal_cents = 1200000,
    return_carry_cents = 0,
  }
end

local rates = { debt_apr = 18, asset_return = 7 }

function T.month_fully_paid_adds_only_interest()
  local r = acc.close_month(default_state(), {
    needs_received = 200, needs_quota = 200,
    wants_received = 80, wants_quota = 80,
    paycheck_emitted = 500, vault_plates = 1200,
  }, rates)
  eq(r.debt_cents, 1827000)
  eq(r.opening_debt_cents, 1827000)
  eq(r.report.deficit_cents, 0)
  eq(r.report.return_plates, 7)
  eq(r.return_carry_cents, 0)
  eq(r.report.cashflow_cents, 220000)
  eq(r.report.consumed_cents, 280000)
end

function T.starved_drains_are_borrowed()
  local r = acc.close_month(default_state(), {
    needs_received = 150, needs_quota = 200,
    wants_received = 0, wants_quota = 80,
    paycheck_emitted = 150, vault_plates = 1200,
  }, rates)
  eq(r.report.needs_shortfall, 50)
  eq(r.report.wants_shortfall, 80)
  eq(r.report.deficit_cents, 130000)
  eq(r.debt_cents, 1800000 + 130000 + 27000)
end

function T.interest_uses_opening_debt_not_current()
  local s = default_state()
  s.debt_cents = 0 -- paid off during the month
  local r = acc.close_month(s, {
    needs_received = 200, needs_quota = 200,
    wants_received = 80, wants_quota = 80,
    paycheck_emitted = 500, vault_plates = 1200,
  }, rates)
  eq(r.report.interest_cents, 27000)
end

function T.deposits_start_earning_next_month()
  local r = acc.close_month(default_state(), {
    needs_received = 200, needs_quota = 200,
    wants_received = 80, wants_quota = 80,
    paycheck_emitted = 500, vault_plates = 1400,
  }, rates)
  eq(r.report.return_cents, 7000)
  eq(r.opening_principal_cents, 1400000)
end

function T.financial_independence_requires_zero_debt()
  -- $480,000 at 7% returns exactly $2,800/month
  eq(acc.is_financially_independent(0, 48000000, 7, 2000, 800), true)
  eq(acc.is_financially_independent(0, 47990000, 7, 2000, 800), false)
  eq(acc.is_financially_independent(100, 48000000, 7, 2000, 800), false)
end

function T.money_formatting()
  eq(acc.money(0), "$0")
  eq(acc.money(99), "$0")
  eq(acc.money(100000), "$1,000")
  eq(acc.money(1823456789), "$18,234,567")
  eq(acc.money(-50000), "-$500")
end

return T
