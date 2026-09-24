local acc = require("script.accounting")
local config = require("script.config")

local M = {}

local ROWS = { "month", "debt", "assets", "return", "expenses", "cashflow", "idle", "consumed" }
local CAPTIONS = {
  month = "Month",
  debt = "Debt",
  assets = "Assets",
  ["return"] = "Asset return",
  expenses = "Needs + wants",
  cashflow = "Paycheck - expenses",
  idle = "Idle cash",
  consumed = "Total consumed",
}
local GOALS = {
  { key = "needs_fed", text = "Belt your paycheck into Needs" },
  { key = "wants_fed", text = "Feed Wants too" },
  { key = "first_payment", text = "Make a debt payment" },
  { key = "first_deposit", text = "Deposit into the Asset Vault" },
  { key = "debt_free", text = "Pay off all debt" },
  { key = "fi", text = "Financial independence: return covers expenses" },
}

function M.create(player)
  local root = player.gui.left
  if root.cf_panel then
    root.cf_panel.destroy()
  end
  local frame = root.add({ type = "frame", name = "cf_panel", direction = "vertical", caption = "Cashflow" })
  local table_el = frame.add({ type = "table", name = "cf_rows", column_count = 2 })
  for _, key in ipairs(ROWS) do
    table_el.add({ type = "label", name = "cf_k_" .. key, caption = CAPTIONS[key] })
    table_el.add({ type = "label", name = "cf_v_" .. key, caption = "" })
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

local function values(cf, vault_plates)
  local cfg = config.read()
  local principal = vault_plates * acc.CENTS_PER_PLATE
  local monthly_return = acc.monthly_amount(principal, cfg.asset_return)
  local expenses = (cfg.needs + cfg.wants) * 100
  local r = cf.last_report
  local v = {
    month = string.format("%d  (%d%%)%s", cf.month, math.floor(100 * cf.tick_in_month / acc.TICKS_PER_MONTH), cf.running and "" or "  PAUSED"),
    debt = acc.money(cf.debt_cents),
    assets = acc.money(principal),
    ["return"] = acc.money(monthly_return) .. "/mo",
    expenses = acc.money(expenses) .. "/mo",
    cashflow = r and (acc.money(r.cashflow_cents) .. " last month") or "-",
    idle = acc.money((cf.paycheck_buffer + cf.vault_out_buffer) * acc.CENTS_PER_PLATE) .. " (earning 0%)",
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
      for _, key in ipairs(ROWS) do
        frame.cf_rows["cf_v_" .. key].caption = v[key]
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
