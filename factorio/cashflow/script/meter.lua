-- Counts plates passing over a player-placed meter belt, using item unique ids.
-- A plate takes ~32 ticks to cross a yellow belt tile, so frequent sampling sees each one.
local M = {}

local COUNTED = { ["iron-plate"] = "iron", ["copper-plate"] = "copper" }

local function item_name(entry)
  local s = entry.stack or entry.item
  return s and s.name
end

local function scan(line, m, seen_now)
  local ok, contents = pcall(function()
    return line.get_detailed_contents()
  end)
  if not ok or not contents then
    return
  end
  for _, entry in pairs(contents) do
    local kind = COUNTED[item_name(entry)]
    if kind then
      seen_now[entry.unique_id] = true
      if not m.seen[entry.unique_id] then
        m.count[kind] = m.count[kind] + 1
      end
    end
  end
end

function M.add(cf, entity)
  cf.meters[entity.unit_number] = {
    entity = entity,
    seen = {},
    count = { iron = 0, copper = 0 },
    last = { iron = 0, copper = 0 },
  }
end

function M.remove(cf, entity)
  local m = cf.meters[entity.unit_number]
  if m and m.label and m.label.valid then
    m.label.destroy()
  end
  cf.meters[entity.unit_number] = nil
end

function M.sweep(cf)
  for id, m in pairs(cf.meters) do
    if not m.entity.valid then
      cf.meters[id] = nil
    else
      local seen_now = {}
      for i = 1, 2 do
        scan(m.entity.get_transport_line(i), m, seen_now)
      end
      m.seen = seen_now
    end
  end
end

function M.close_month(cf)
  for _, m in pairs(cf.meters) do
    m.last = m.count
    m.count = { iron = 0, copper = 0 }
  end
end

return M
