local acc = require("script.accounting")
local config = require("script.config")
local stations = require("script.stations")

local M = {}

function M.plan_month(cfg)
  return {
    paycheck_plates = acc.quota_plates(cfg.job_income),
    needs_quota = acc.quota_plates(cfg.needs),
    wants_quota = acc.quota_plates(cfg.wants),
  }
end

function M.close_month(cf)
  local cfg = config.read()
  local vault_plates = stations.vault_plates(cf)
  local result = acc.close_month(cf, {
    needs_received = cf.received.needs,
    needs_quota = cf.plan.needs_quota,
    wants_received = cf.received.wants,
    wants_quota = cf.plan.wants_quota,
    paycheck_emitted = cf.paycheck_emitted,
    vault_plates = vault_plates,
  }, { debt_apr = cfg.debt_apr, asset_return = cfg.asset_return })

  local r = result.report
  cf.debt_cents = result.debt_cents
  cf.opening_debt_cents = result.opening_debt_cents
  cf.opening_principal_cents = result.opening_principal_cents
  cf.return_carry_cents = result.return_carry_cents
  cf.vault_out_buffer = cf.vault_out_buffer + r.return_plates
  cf.consumed_total_cents = cf.consumed_total_cents + r.consumed_cents
  r.paycheck_plates = cf.paycheck_emitted
  r.debt_paid_plates = cf.debt_paid_plates
  r.deposit_plates = cf.deposit_plates
  cf.last_report = r

  cf.month = cf.month + 1
  cf.tick_in_month = 0
  cf.paycheck_emitted = 0
  cf.received = { needs = 0, wants = 0 }
  cf.debt_paid_plates = 0
  cf.deposit_plates = 0
  cf.plan = M.plan_month(cfg)
  stations.sync_ledger(cf)

  if cf.debt_cents == 0 then
    cf.goals.debt_free = true
  end
  if not cf.won and acc.is_financially_independent(cf.debt_cents, vault_plates * acc.CENTS_PER_PLATE, cfg.asset_return, cfg.needs, cfg.wants) then
    cf.won = true
    cf.goals.fi = true
    game.print({ "", "[color=green]Financial independence![/color] Your vault's monthly return now covers your expenses. You can quit your job from the panel." })
  end

  log(string.format(
    "[cashflow] month=%d debt=%d assets=%d paycheck=%d needs=%d/%d wants=%d/%d deficit=%d interest=%d return=%d carry=%d paid=%d deposit=%d idle=%d",
    cf.month, cf.debt_cents, vault_plates * acc.CENTS_PER_PLATE, r.paycheck_plates,
    r.needs_consumed, r.needs_consumed + r.needs_shortfall, r.wants_consumed, r.wants_consumed + r.wants_shortfall,
    r.deficit_cents, r.interest_cents, r.return_cents, cf.return_carry_cents,
    r.debt_paid_plates, r.deposit_plates, cf.paycheck_buffer + cf.vault_out_buffer
  ))
end

return M
