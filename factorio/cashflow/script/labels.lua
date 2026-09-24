local acc = require("script.accounting")

local M = {}

local PLATE = acc.CENTS_PER_PLATE
local WHITE = { r = 1, g = 1, b = 1 }
local GREEN = { r = 0.45, g = 0.9, b = 0.5 }
local RED = { r = 1, g = 0.45, b = 0.4 }
local GREY = { r = 0.7, g = 0.7, b = 0.7 }

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

local function at_tile(pos)
  return { pos[1] + 0.5, pos[2] - 0.6 }
end

function M.create(cf, surface)
  local e = cf.entities
  local L = {}
  L.paycheck = text_at(surface, on_entity(e.paycheck.landmark, -1.4), "", GREEN)
  L.needs = text_at(surface, on_entity(e.needs.landmark, -1.4), "", RED)
  L.wants = text_at(surface, on_entity(e.wants.landmark, -1.4), "", RED)
  L.debt = text_at(surface, on_entity(e.debt.landmark, -1.4), "", RED)
  L.vault = text_at(surface, on_entity(e.vault.landmark, -1.4), "", GREEN)
  for key, s in pairs(e) do
    if s.input_at and key ~= "paycheck" then
      text_at(surface, at_tile(s.input_at), "IN >", GREY, 1)
    end
    text_at(surface, at_tile(s.output_at), "OUT >", GREY, 1)
  end
  cf.labels = L
end

local function dollars(plates)
  return acc.money(plates * PLATE)
end

function M.refresh(cf, vault_plates)
  local L, p = cf.labels, cf.plan
  if not L then
    return
  end
  L.paycheck.text = "PAYCHECK " .. dollars(p.paycheck_plates) .. "/mo  idle " .. dollars(cf.paycheck_buffer)
  L.needs.text = "NEEDS " .. dollars(cf.received.needs) .. " / " .. dollars(p.needs_quota)
  L.wants.text = "WANTS " .. dollars(cf.received.wants) .. " / " .. dollars(p.wants_quota)
  L.debt.text = "DEBT " .. acc.money(cf.debt_cents)
  L.vault.text = "VAULT " .. dollars(vault_plates) .. "  returns waiting " .. dollars(cf.vault_out_buffer)
  for _, m in pairs(cf.meters) do
    if m.entity.valid then
      local text = "METER " .. dollars(m.count) .. " this month, " .. dollars(m.last) .. " last"
      if m.label and m.label.valid then
        m.label.text = text
      else
        m.label = text_at(m.entity.surface, on_entity(m.entity, -0.8), text, WHITE, 1.1)
      end
    end
  end
end

return M
