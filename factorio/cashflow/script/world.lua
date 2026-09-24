local layout = require("script.layout")

local M = {}

local CLEAR_TYPES = { "tree", "simple-entity", "resource", "unit-spawner", "turret", "unit", "cliff", "fish" }

function M.clean_area(surface, area)
  local tiles = {}
  for x = area.left_top.x, area.right_bottom.x - 1 do
    for y = area.left_top.y, area.right_bottom.y - 1 do
      local dark = (math.floor(x) + math.floor(y)) % 2 == 0
      tiles[#tiles + 1] = { name = dark and "lab-dark-1" or "lab-dark-2", position = { x, y } }
    end
  end
  surface.set_tiles(tiles)
  for _, e in pairs(surface.find_entities_filtered({ area = area, type = CLEAR_TYPES })) do
    e.destroy()
  end
  surface.destroy_decoratives({ area = area })
end

local function lock(e)
  e.destructible = false
  e.operable = false
  e.rotatable = false
  return e
end

local function place(surface, name, x, y, direction)
  local e = surface.create_entity({
    name = name,
    position = { x, y },
    direction = direction,
    force = "player",
  })
  return lock(e)
end

local function belt(surface, tx, ty)
  return place(surface, "cf-belt", tx + 0.5, ty + 0.5, defines.direction.east)
end

-- landmark → belts east. Script places plates at the back of the first belt.
local function build_source(surface, s)
  local landmark = place(surface, "cf-landmark", s.x + 0.5, s.y + 0.5)
  local first = belt(surface, s.x + 1, s.y)
  belt(surface, s.x + 2, s.y)
  belt(surface, s.x + 3, s.y)
  return { landmark = landmark, out_first = first, input_at = { s.x + 1, s.y }, output_at = { s.x + 4, s.y } }
end

-- in belts → splitter; right lane goes to the drain stub (priority), left lane passes through.
-- Script removes plates from the drain stub's last belt; when it stops, the stub backs up
-- and the splitter sends everything to the pass-through side.
local function build_drain(surface, s)
  local x, y = s.x, s.y
  belt(surface, x, y)
  belt(surface, x + 1, y)
  local splitter = place(surface, "cf-splitter", x + 2.5, y + 1, defines.direction.east)
  splitter.splitter_output_priority = "right"
  belt(surface, x + 3, y)
  belt(surface, x + 4, y)
  belt(surface, x + 3, y + 1)
  belt(surface, x + 4, y + 1)
  local drain_end = belt(surface, x + 5, y + 1)
  local landmark = place(surface, s.landmark or "cf-landmark", x + 6.5, y + 1.5)
  return {
    landmark = landmark,
    drain_end = drain_end,
    splitter = splitter,
    input_at = { x, y },
    output_at = { x + 5, y },
  }
end

-- in belts → vault chest → out belts.
local function build_vault(surface, s)
  local x, y = s.x, s.y
  belt(surface, x, y)
  belt(surface, x + 1, y)
  local in_end = belt(surface, x + 2, y)
  local chest = place(surface, "cf-vault", x + 3.5, y + 0.5)
  local out_first = belt(surface, x + 4, y)
  belt(surface, x + 5, y)
  belt(surface, x + 6, y)
  return {
    landmark = chest,
    chest = chest,
    in_end = in_end,
    out_first = out_first,
    input_at = { x, y },
    output_at = { x + 7, y },
  }
end

local builders = { source = build_source, drain = build_drain, vault = build_vault }

function M.create_surface()
  local surface = game.surfaces[layout.surface] or game.create_surface(layout.surface)
  surface.always_day = true
  surface.request_to_generate_chunks({ 0, 0 }, 3)
  surface.force_generate_chunk_requests()
  M.clean_area(surface, { left_top = { x = -96, y = -96 }, right_bottom = { x = 96, y = 96 } })
  return surface
end

function M.build_stations(surface)
  local entities = {}
  for _, s in ipairs(layout.stations) do
    entities[s.key] = builders[s.kind](surface, s)
  end
  return entities
end

return M
