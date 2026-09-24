-- Counts iron plates passing over a player-placed meter belt, using item unique ids.
-- A plate takes ~32 ticks to cross a yellow belt tile, so sampling every 6 ticks sees each one.
local M = {}

local function item_name(entry)
  local s = entry.stack or entry.item
  return s and s.name
end

local function scan(line, seen_now, seen_before)
  local ok, contents = pcall(function()
    return line.get_detailed_contents()
  end)
  if not ok or not contents then
    return 0
  end
  local fresh = 0
  for _, entry in pairs(contents) do
    if item_name(entry) == "iron-plate" then
      seen_now[entry.unique_id] = true
      if not seen_before[entry.unique_id] then
        fresh = fresh + 1
      end
    end
  end
  return fresh
end

function M.add(cf, entity)
  cf.meters[entity.unit_number] = { entity = entity, seen = {}, count = 0, last = 0 }
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
        m.count = m.count + scan(m.entity.get_transport_line(i), seen_now, m.seen)
      end
      m.seen = seen_now
    end
  end
end

function M.close_month(cf)
  for _, m in pairs(cf.meters) do
    m.last = m.count
    m.count = 0
  end
end

return M
