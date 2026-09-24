local acc = require("script.accounting")

local M = {}

local WHITE = { r = 1, g = 1, b = 1 }
local GREEN = { r = 0.45, g = 0.9, b = 0.5 }
local RED = { r = 1, g = 0.55, b = 0.35 }
local GOLD = { r = 1, g = 0.85, b = 0.4 }
local GREY = { r = 0.7, g = 0.7, b = 0.7 }

local COLORS = { paycheck = GREEN, needs = RED, wants = RED, cashflow = GOLD, debt = RED, vault = GREEN }

local function text_at(surface, target, text, color, scale)
  return rendering.draw_text({
    text = text,
    surface = surface,
    target = target,
    color = color,
    scale = scale or 1.4,
    alignment = "center",
    vertical_alignment = "middle",
  })
end

local function on_entity(e, dy)
  return { entity = e, offset = { 0, dy } }
end

function M.create(cf, surface)
  cf.labels = {}
  for key, s in pairs(cf.entities) do
    cf.labels[key] = text_at(surface, on_entity(s.landmark, -1.4), "", COLORS[key] or WHITE)
    for _, port in ipairs(s.ports) do
      text_at(surface, { port[1] + 0.5, port[2] - 0.4 }, port[3], GREY, 0.9)
    end
  end
end

local function d(plates)
  return acc.money(plates * acc.CENTS_PER_PLATE)
end

-- Copper stuck in an output buffer is added to debt at month end.
local function overdue(plates)
  if plates <= 0 then
    return ""
  end
  return "  unbelted " .. d(plates) .. " -> debt at month end"
end

function M.refresh(cf, vault_plates)
  local L, p, out, node = cf.labels, cf.plan, cf.out, cf.node
  if not L then
    return
  end
  L.paycheck.text = "PAYCHECK cash " .. d(p.paycheck) .. "/mo" .. (out.paycheck > 0 and ("  waiting " .. d(out.paycheck)) or "")
  L.needs.text = "NEEDS bills " .. d(p.needs) .. "/mo" .. overdue(out.needs)
  L.wants.text = "WANTS bills " .. d(p.wants) .. "/mo" .. overdue(out.wants)
  L.cashflow.text = "CASHFLOW cash " .. d(node.iron) .. "  bills " .. d(node.copper) .. "  paid " .. d(cf.stats.paid) .. overdue(out.unpaid)
  L.debt.text = "DEBT " .. acc.money(cf.debt_cents) .. overdue(out.interest)
  L.vault.text = "VAULT " .. d(vault_plates) .. (out.returns > 0 and ("  returns waiting " .. d(out.returns)) or "")
  for _, m in pairs(cf.meters) do
    if m.entity.valid then
      local text = "METER cash " .. d(m.count.iron) .. " bills " .. d(m.count.copper) .. " (last month " .. d(m.last.iron) .. " / " .. d(m.last.copper) .. ")"
      if m.label and m.label.valid then
        m.label.text = text
      else
        m.label = text_at(m.entity.surface, on_entity(m.entity, -0.8), text, WHITE, 1.1)
      end
    end
  end
end

return M
