local acc = require("script.accounting")
local config = require("script.config")

local M = {}

local ROWS = {
  { "month", "Month" },
  { "debt", "Debt" },
  { "assets", "Assets" },
  { "return", "Asset return" },
  { "bills", "Needs + wants bills" },
  { "node", "Cashflow holding" },
  { "last", "Last month" },
  { "idle", "Idle cash" },
  { "consumed", "Total spent" },
}

local GOALS = {
  { key = "cash_in", text = "Belt Paycheck cash into Cashflow" },
  { key = "bills_in", text = "Belt Needs and Wants bills into Cashflow" },
  { key = "first_payment", text = "Pay debt with cash (Debt PAY IN)" },
  { key = "first_deposit", text = "Deposit surplus cash into the Asset Vault" },
  { key = "debt_free", text = "Pay off all debt" },
  { key = "fi", text = "Financial independence: return covers bills" },
}

function M.create(player)
  local root = player.gui.left
  if root.cf_panel then
    root.cf_panel.destroy()
  end
  local frame = root.add({ type = "frame", name = "cf_panel", direction = "vertical", caption = "Cashflow" })
  local rows = frame.add({ type = "table", name = "cf_rows", column_count = 2 })
  for _, row in ipairs(ROWS) do
    rows.add({ type = "label", caption = row[2] })
    rows.add({ type = "label", name = "cf_v_" .. row[1], caption = "" })
  end
  frame.add({ type = "label", caption = "Progress to financial independence" })
  frame.add({ type = "progressbar", name = "cf_fi", value = 0 })
  local buttons = frame.add({ type = "flow", name = "cf_buttons", direction = "horizontal" })
  buttons.add({ type = "button", name = "cf_toggle", caption = "Start" })
  buttons.add({ type = "button", name = "cf_quit_job", caption = "Quit job", visible = false })
  frame.add({ type = "line" })
  local goals = frame.add({ type = "flow", name = "cf_goals", direction = "vertical" })
  for _, g in ipairs(GOALS) do
    goals.add({ type = "label", name = "cf_goal_" .. g.key, caption = "[ ] " .. g.text })
  end
end

local function d(plates)
  return acc.money(plates * acc.CENTS_PER_PLATE)
end

local function last_month(r)
  if not r then
    return "-"
  end
  return string.format("paid %s, surplus %s, unpaid %s, interest %s, charged to debt %s",
    d(r.paid), d(r.surplus_plates), d(r.unpaid_plates), d(r.interest_plates), d(r.collected_plates))
end

local function values(cf, vault_plates)
  local cfg = config.read()
  local principal = vault_plates * acc.CENTS_PER_PLATE
  local monthly_return = acc.monthly_amount(principal, cfg.asset_return)
  local expenses = (cfg.needs + cfg.wants) * 100
  local pct = math.floor(100 * cf.tick_in_month / acc.TICKS_PER_MONTH)
  local v = {
    month = string.format("%d  (%d%%)%s", cf.month, pct, cf.running and "" or "  PAUSED"),
    debt = acc.money(cf.debt_cents),
    assets = acc.money(principal),
    ["return"] = acc.money(monthly_return) .. "/mo",
    bills = acc.money(expenses) .. "/mo",
    node = "cash " .. d(cf.node.iron) .. ", bills " .. d(cf.node.copper),
    last = last_month(cf.last_report),
    idle = d(cf.out.paycheck + cf.out.surplus + cf.out.returns) .. " (earning 0%)",
    consumed = acc.money(cf.consumed_total_cents),
  }
  local progress = 0
  if expenses > 0 then
    progress = math.min(1, monthly_return / expenses)
  end
  if cf.debt_cents > 0 then
    progress = math.min(progress, 0.99)
  end
  return v, progress
end

function M.refresh(cf, vault_plates)
  local v, progress = values(cf, vault_plates)
  for _, player in pairs(game.players) do
    local frame = player.gui.left.cf_panel
    if frame then
      for _, row in ipairs(ROWS) do
        frame.cf_rows["cf_v_" .. row[1]].caption = v[row[1]]
      end
      frame.cf_fi.value = progress
      frame.cf_buttons.cf_toggle.caption = cf.running and "Pause" or "Start"
      frame.cf_buttons.cf_quit_job.visible = cf.won and not cf.job_quit
      for _, g in ipairs(GOALS) do
        frame.cf_goals["cf_goal_" .. g.key].caption = (cf.goals[g.key] and "[x] " or "[ ] ") .. g.text
      end
    end
  end
end

return M
