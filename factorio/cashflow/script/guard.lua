-- Money only moves on belts. Cash picked up by hand goes back to the paycheck; bills picked up
-- by hand are charged to debt, so mining a belt full of copper doesn't make expenses vanish.
local acc = require("script.accounting")

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
    cf.out.paycheck = cf.out.paycheck + iron
    player.print("Cash only moves on belts: " .. iron .. " iron plates went back to your paycheck.")
  end
  local copper = inv.get_item_count("copper-plate")
  if copper > 0 then
    inv.remove({ name = "copper-plate", count = copper })
    cf.debt_cents = cf.debt_cents + copper * acc.CENTS_PER_PLATE
    cf.stats.picked_copper = cf.stats.picked_copper + copper
    player.print("Bills only move on belts: " .. copper .. " copper plates were charged to your debt.")
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
