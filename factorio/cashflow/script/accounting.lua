-- Pure money math. No Factorio API here so it can be unit-tested with plain Lua.
-- Money is integer cents; one plate is $10.

local M = {}

M.CENTS_PER_PLATE = 1000
M.TICKS_PER_MONTH = 3600

-- Matches Math.round in simulation.js for the non-negative values used here.
function M.round(v)
  return math.floor(v + 0.5)
end

function M.monthly_amount(cents, annual_pct)
  return M.round(cents * (annual_pct / 100 / 12))
end

function M.quota_plates(dollars)
  return math.ceil(dollars / 10)
end

function M.plates_for_debt(debt_cents)
  return math.ceil(debt_cents / M.CENTS_PER_PLATE)
end

-- Plates that should have been emitted by this point of the month, spread evenly.
function M.paycheck_due(plates_per_month, tick_in_month, ticks_per_month)
  ticks_per_month = ticks_per_month or M.TICKS_PER_MONTH
  local t = math.min(math.max(tick_in_month, 0), ticks_per_month)
  return math.floor(plates_per_month * t / ticks_per_month)
end

function M.close_drain(received, quota)
  local consumed = math.min(received, quota)
  return consumed, quota - consumed
end

function M.split_return(return_cents, carry_cents)
  local total = return_cents + carry_cents
  local plates = math.floor(total / M.CENTS_PER_PLATE)
  return plates, total - plates * M.CENTS_PER_PLATE
end

-- state:  debt_cents, opening_debt_cents, opening_principal_cents, return_carry_cents
-- inputs: needs_received, needs_quota, wants_received, wants_quota, paycheck_emitted, vault_plates
-- rates:  debt_apr, asset_return (annual percent)
function M.close_month(state, inputs, rates)
  local needs_consumed, needs_shortfall = M.close_drain(inputs.needs_received, inputs.needs_quota)
  local wants_consumed, wants_shortfall = M.close_drain(inputs.wants_received, inputs.wants_quota)

  local deficit_cents = (needs_shortfall + wants_shortfall) * M.CENTS_PER_PLATE
  local interest_cents = M.monthly_amount(state.opening_debt_cents, rates.debt_apr)
  local debt_cents = state.debt_cents + deficit_cents + interest_cents

  local return_cents = M.monthly_amount(state.opening_principal_cents, rates.asset_return)
  local return_plates, carry = M.split_return(return_cents, state.return_carry_cents)

  local consumed_plates = needs_consumed + wants_consumed

  return {
    debt_cents = debt_cents,
    opening_debt_cents = debt_cents,
    opening_principal_cents = inputs.vault_plates * M.CENTS_PER_PLATE,
    return_carry_cents = carry,
    report = {
      needs_consumed = needs_consumed,
      wants_consumed = wants_consumed,
      needs_shortfall = needs_shortfall,
      wants_shortfall = wants_shortfall,
      deficit_cents = deficit_cents,
      interest_cents = interest_cents,
      return_cents = return_cents,
      return_plates = return_plates,
      consumed_cents = consumed_plates * M.CENTS_PER_PLATE,
      cashflow_cents = (inputs.paycheck_emitted - consumed_plates) * M.CENTS_PER_PLATE,
    },
  }
end

function M.is_financially_independent(debt_cents, principal_cents, asset_return, needs_dollars, wants_dollars)
  if debt_cents > 0 then
    return false
  end
  local expenses_cents = (needs_dollars + wants_dollars) * 100
  return M.monthly_amount(principal_cents, asset_return) >= expenses_cents
end

function M.money(cents)
  local negative = cents < 0
  local dollars = math.floor(math.abs(cents) / 100)
  local s = tostring(dollars)
  local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
  if out:sub(1, 1) == "," then
    out = out:sub(2)
  end
  return (negative and "-$" or "$") .. out
end

return M
