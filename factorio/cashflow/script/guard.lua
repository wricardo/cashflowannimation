-- Money only moves on belts: plates picked up by hand go back into the paycheck buffer,
-- copper is dropped (the ledger re-syncs from the debt balance). Building supplies stay topped up.
local M = {}

local SUPPLIES = {
  { name = "transport-belt", count = 400 },
  { name = "underground-belt", count = 50 },
  { name = "splitter", count = 50 },
}

function M.check(cf, player)
  local inv = player.get_main_inventory()
  if not inv then
    return
  end
  local iron = inv.get_item_count("iron-plate")
  if iron > 0 then
    inv.remove({ name = "iron-plate", count = iron })
    cf.paycheck_buffer = cf.paycheck_buffer + iron
    player.print("Cash only moves on belts. Returned " .. iron .. " plates to your paycheck.")
  end
  local copper = inv.get_item_count("copper-plate")
  if copper > 0 then
    inv.remove({ name = "copper-plate", count = copper })
  end
  for _, s in ipairs(SUPPLIES) do
    local have = inv.get_item_count(s.name)
    if have < s.count then
      inv.insert({ name = s.name, count = s.count - have })
    end
  end
end

function M.give_meter(player)
  local inv = player.get_main_inventory()
  if inv and inv.get_item_count("cf-meter-belt") == 0 then
    inv.insert({ name = "cf-meter-belt", count = 1 })
  end
end

return M
