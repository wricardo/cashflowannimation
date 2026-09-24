-- Minimal stand-in for the Factorio runtime API, enough to load control.lua and run months.
local F = {}

local function new_inventory()
  local inv = { items = {} }
  function inv.get_item_count(name)
    return inv.items[name] or 0
  end
  function inv.insert(stack)
    inv.items[stack.name] = (inv.items[stack.name] or 0) + stack.count
    return stack.count
  end
  function inv.remove(stack)
    local have = inv.items[stack.name] or 0
    local n = math.min(have, stack.count)
    inv.items[stack.name] = have - n
    return n
  end
  function inv.get_insertable_count()
    return 1000000
  end
  return inv
end

-- A belt lane that holds up to `cap` plates.
local function new_line(cap)
  local line = { count = 0, cap = cap }
  function line.insert_at_back()
    if line.count < line.cap then
      line.count = line.count + 1
      return true
    end
    return false
  end
  function line.remove_item(stack)
    local n = math.min(line.count, stack.count)
    line.count = line.count - n
    return n
  end
  function line.get_item_count()
    return line.count
  end
  function line.get_detailed_contents()
    return {}
  end
  return line
end

local next_unit = 1

local function new_entity(surface, spec)
  local e = {
    name = spec.name,
    position = spec.position,
    direction = spec.direction,
    surface = surface,
    valid = true,
    unit_number = next_unit,
  }
  next_unit = next_unit + 1
  local lines = { new_line(4), new_line(4) }
  local inv = new_inventory()
  function e.get_transport_line(i)
    return lines[i]
  end
  function e.get_inventory()
    return inv
  end
  surface.entities[#surface.entities + 1] = e
  return e
end

local function new_surface(name)
  local s = { name = name, entities = {} }
  function s.request_to_generate_chunks() end
  function s.force_generate_chunk_requests() end
  function s.set_tiles() end
  function s.destroy_decoratives() end
  function s.find_entities_filtered()
    return {}
  end
  function s.find_non_colliding_position(_, pos)
    return pos
  end
  function s.create_entity(spec)
    return new_entity(s, spec)
  end
  return s
end

local function new_gui_element(spec)
  local el = { type = spec.type, name = spec.name, caption = spec.caption, value = spec.value, visible = spec.visible ~= false }
  el.children = {}
  function el.add(child_spec)
    local child = new_gui_element(child_spec)
    child.parent = el
    el.children[#el.children + 1] = child
    if child_spec.name then
      el[child_spec.name] = child
    end
    return child
  end
  function el.destroy()
    if el.parent and el.name then
      el.parent[el.name] = nil
    end
  end
  return el
end

function F.new_player(index)
  local p = { index = index, prints = {}, inventory = new_inventory() }
  p.gui = { left = new_gui_element({ type = "flow" }) }
  function p.get_main_inventory()
    return p.inventory
  end
  function p.teleport(pos, surface)
    p.position, p.surface = pos, surface
  end
  function p.print(msg)
    p.prints[#p.prints + 1] = msg
  end
  return p
end

local default_settings = {
  ["cf-job-income"] = 5000,
  ["cf-needs"] = 2000,
  ["cf-wants"] = 800,
  ["cf-starting-debt"] = 18000,
  ["cf-debt-apr"] = 18,
  ["cf-starting-assets"] = 12000,
  ["cf-asset-return"] = 7,
  ["cf-game-speed"] = 1,
}

-- Installs globals and returns a handle for driving events.
function F.install(opts)
  opts = opts or {}
  local h = { events = {}, nth = {}, logs = {}, tick = 0 }
  local event_ids = {}
  local names = {
    "on_player_created", "on_chunk_generated", "on_gui_click", "on_runtime_mod_setting_changed",
    "on_player_main_inventory_changed", "on_built_entity", "on_player_mined_entity", "on_robot_mined_entity",
  }
  for i, name in ipairs(names) do
    event_ids[name] = i
  end

  _G.defines = {
    events = event_ids,
    direction = { north = 0, east = 4, south = 8, west = 12 },
    inventory = { chest = 1 },
  }

  local g = {}
  for k, v in pairs(default_settings) do
    g[k] = { value = (opts.settings and opts.settings[k]) or v }
  end
  _G.settings = { global = g }

  _G.storage = {}

  _G.script = {
    level = opts.level or { mod_name = "cashflow", level_name = "cashflow" },
    on_init = function(fn)
      h.init = fn
    end,
    on_event = function(id, fn)
      h.events[id] = fn
    end,
    on_nth_tick = function(n, fn)
      h.nth[n] = fn
    end,
  }

  local surfaces = { nauvis = new_surface("nauvis") }
  _G.game = {
    surfaces = surfaces,
    players = {},
    speed = 1,
    create_surface = function(name)
      surfaces[name] = new_surface(name)
      return surfaces[name]
    end,
    get_player = function(i)
      return _G.game.players[i]
    end,
    print = function(msg)
      h.logs[#h.logs + 1] = msg
    end,
  }

  _G.rendering = {
    draw_text = function(spec)
      local obj = { text = spec.text, valid = true }
      function obj.destroy()
        obj.valid = false
      end
      return obj
    end,
  }

  _G.log = function(msg)
    h.logs[#h.logs + 1] = msg
  end

  for name in pairs(package.loaded) do
    if name == "control" or name:match("^script%.") then
      package.loaded[name] = nil
    end
  end
  require("control")

  function h.fire(name, event)
    event = event or {}
    event.name = event_ids[name]
    h.events[event_ids[name]](event)
  end

  function h.add_player()
    local p = F.new_player(#_G.game.players + 1)
    _G.game.players[p.index] = p
    h.fire("on_player_created", { player_index = p.index })
    return p
  end

  function h.run_ticks(n)
    for _ = 1, n do
      h.tick = h.tick + 1
      for every, fn in pairs(h.nth) do
        if h.tick % every == 0 then
          fn({ tick = h.tick })
        end
      end
    end
  end

  return h
end

return F
