local acc = require("script.accounting")
local config = require("script.config")
local stations = require("script.stations")

local M = {}

local P = acc.CENTS_PER_PLATE

-- Copper that never made it onto a belt by month end is charged to debt.
local COLLECTED = { "needs", "wants", "interest", "unpaid" }

function M.plan_month(cfg)
  return {
    paycheck = acc.plates(cfg.job_income),
    needs = acc.plates(cfg.needs),
    wants = acc.plates(cfg.wants),
  }
end

function M.close_month(cf)
  local cfg = config.read()
  local vault_plates = stations.vault_plates(cf)

  local copper_waiting = 0
  for _, key in ipairs(COLLECTED) do
    copper_waiting = copper_waiting + cf.out[key]
    cf.out[key] = 0
  end

  local result = acc.close_month(cf, {
    copper_waiting = copper_waiting,
    node_iron = cf.node.iron,
    node_copper = cf.node.copper,
    vault_plates = vault_plates,
  }, { debt_apr = cfg.debt_apr, asset_return = cfg.asset_return })

  local r = result.report
  cf.debt_cents = result.debt_cents
  cf.opening_debt_cents = result.opening_debt_cents
  cf.opening_principal_cents = result.opening_principal_cents
  cf.interest_carry_cents = result.interest_carry_cents
  cf.return_carry_cents = result.return_carry_cents

  cf.out.surplus = cf.out.surplus + r.surplus_plates
  cf.out.unpaid = cf.out.unpaid + r.unpaid_plates
  cf.out.interest = cf.out.interest + r.interest_plates
  cf.out.returns = cf.out.returns + r.return_plates
  cf.node = { iron = 0, copper = 0 }

  for k, v in pairs(cf.stats) do
    r[k] = v
  end
  r.paycheck = cf.emitted.paycheck
  r.bills = cf.emitted.needs + cf.emitted.wants
  cf.last_report = r

  cf.month = cf.month + 1
  cf.tick_in_month = 0
  cf.emitted = { paycheck = 0, needs = 0, wants = 0 }
  cf.stats = stations.new_month_stats()
  cf.plan = M.plan_month(cfg)
  stations.sync_ledger(cf)

  if cf.debt_cents == 0 then
    cf.goals.debt_free = true
  end
  if not cf.won and acc.is_financially_independent(cf.debt_cents, vault_plates * P, cfg.asset_return, cfg.needs, cfg.wants) then
    cf.won = true
    cf.goals.fi = true
    game.print("[color=green]Financial independence![/color] Your vault's monthly return now covers your needs and wants. You can quit your job from the panel.")
  end

  log(string.format(
    "[cashflow] month=%d debt=%d assets=%d paycheck=%d bills=%d cash_in=%d bills_in=%d paid=%d surplus=%d unpaid=%d borrowed=%d debt_paid=%d collected=%d interest=%d return=%d deposits=%d",
    cf.month, cf.debt_cents, vault_plates * P, r.paycheck, r.bills, r.cash_in, r.bills_in, r.paid,
    r.surplus_plates, r.unpaid_plates, r.borrowed, r.debt_paid, r.collected_plates,
    r.interest_cents, r.return_cents, r.deposits
  ))
end

return M
