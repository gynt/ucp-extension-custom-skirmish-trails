local memory = require("customskirmishtrails.memory")
local patches = require("customskirmishtrails.patches")
local unitlimits = require("customskirmishtrails.unitlimits")
local storage = require("customskirmishtrails.storage")

local progress = {}

-- Each native victory branch computes the new furthest row in EAX, then stores it.
-- These sites are downstream of the winner check and the scenario win handover.
local WIN_STORES = {
  firstEditionTrail = { fn = "win", offset = 0x359, bytes = "8D 41 01 A3 ? ? ? ? 7D" },
  warchestTrail = { fn = "win", offset = 0x2F7, bytes = "8D 47 01 A3 ? ? ? ? 7D" },
  extremeTrail = { fn = "win", offset = 0x286, bytes = "8D 42 01 A3 ? ? ? ? 7D" },
}
-- After a win both branches store the next selected row from a register: "mov [selected], reg".
local SELECT_STORES = {
  firstEditionTrail = { fn = "win", offset = 0x374, bytes = "89 0D ? ? ? ? 66 85 D2", register = "ECX" },
  warchestTrail = { fn = "win", offset = 0x312, bytes = "89 3D ? ? ? ? 66 85 C9", register = "EDI" },
  extremeTrail = { fn = "win", offset = 0x2A1, bytes = "89 15 ? ? ? ? 66 85 C9", register = "EDX" },
}
-- Every win of a trail mission, a replay and the end included, reaches "cmp row, [furthest]" before
-- the game branches on them.
local WIN_COMPARES = {
  firstEditionTrail = { fn = "win", offset = 0x34E, bytes = "3B 0D ? ? ? ? 7C 11" },
  warchestTrail = { fn = "win", offset = 0x2EC, bytes = "3B 3D ? ? ? ? 7C 11" },
  extremeTrail = { fn = "win", offset = 0x27B, bytes = "3B 15 ? ? ? ? 7C 11" },
}
-- A chicken has advanced the selected and the furthest row of every trail when the click handler
-- reaches "mov ecx, trails / call" (the trail's number is pushed).
local CHICKEN_SITE = { fn = "click", offset = 0x71, bytes = "B9 ? ? ? ? E8 ? ? ? ? 29 2D" }

local stores = {} -- trailName -> { trail, furthest, selected, path, count, route } once the win store is detoured
local chickenHooked = false

local function readProgress(name, count)
  local value = tonumber((storage.read(name) or ""):match("^%s*(%d+)%s*$"))
  return value and math.min(value, count) or 0
end

---A node's reward of `chickens` on `trail`, added to its chicken budget for the next trail screen.
local function giveChickens(trail, chickens)
  for index, name in pairs(memory.TRAIL_TYPES) do
    if name == trail and patches.addChickens(index, chickens) then
      return
    end
  end
  log(WARNING, "the trail screen's chicken code was not found; a reward of chickens is not given")
end

---Keeps the win of the route's node at `row` with the players alive now and gives its reward.
local function recordWin(state, row)
  local chickens = state.route:recordResult(row, unitlimits.playerFacts())
  if chickens > 0 then
    giveChickens(state.trail, chickens)
  end
end

---The win store of `trail`, detoured once: with a route the won row is passed and, for a route of
---side missions or parallel paths, the furthest row becomes its frontier; the furthest row is saved
---when a path is set.
local function winStore(trail, purpose)
  if stores[trail] ~= nil then
    return stores[trail]
  end
  local site = patches.siteAddress(WIN_STORES[trail], purpose)
  local selected = memory.TRAIL_PROGRESS_ADDRESSES[trail]
  if site == nil or selected == nil then return nil end
  local store = site + 3
  local state = { trail = trail, furthest = core.readInteger(store + 1), selected = selected }
  local stub = patches.luaStub(function(registers)
    local r = state.route
    if r ~= nil then
      local row = core.readInteger(state.selected)
      r:pass(row)
      if row == r.count - 1 then
        -- the end: the game ends the trail without reaching the select store
        registers.EAX = r.count
      elseif r.graph then
        registers.EAX = r:frontier()
      end
    end
    local value = registers.EAX
    if state.path ~= nil and value >= 1 and value <= state.count then
      local ok, err = storage.write(state.path, tostring(value) .. "\n")
      if not ok then
        log(WARNING, "could not save trail progress: " .. tostring(err))
      end
    end
    return registers
  end)
  -- pushfd / call stub / popfd, then the store: the jge after the store reads the flags of the
  -- row's compare before it, which a Lua detour doesn't keep
  core.insertCode(store, 5, { 0x9C, core.callTo(stub), 0x9D }, nil, "after")
  stores[trail] = state
  return state
end

---Keeps the furthest row of `trail` in the user data file `path` instead of the game's own progress.
function progress.install(trail, path, count)
  local state = winStore(trail, "the trail's own progress file")
  if state == nil then return false end
  state.count = count
  state.path = path

  hooks.registerHookCallback("afterInit", function()
    local value = readProgress(state.path, count)
    core.writeInteger(state.furthest, value)
    core.writeInteger(state.selected, math.min(value, count - 1))
  end)
end

local function onChicken()
  local trail = memory.TRAIL_TYPES[core.readInteger(memory.CURRENT_TRAIL_TYPE)]
  local state = trail and stores[trail]
  local r = state and state.route
  if r ~= nil then
    -- the game skipped its furthest row and moved past it
    r:pass(core.readInteger(state.furthest) - 1)
    if r.graph then
      core.writeInteger(state.furthest, r:frontier())
      core.writeInteger(state.selected, r:suggest())
    end
  end
end

---For a route of side missions or parallel paths the furthest row becomes its frontier, and a
---selected row that can't be played its suggestion. Otherwise the game's furthest row leads, and a
---selected row past it becomes that row.
local function follow(state)
  local r = state.route
  local selected = core.readInteger(state.selected)
  if not r.graph then
    local furthest = math.min(core.readInteger(state.furthest), r.count - 1)
    if selected < 0 or selected > furthest then
      core.writeInteger(state.selected, furthest)
    end
    return
  end
  core.writeInteger(state.furthest, r:frontier())
  if selected < 0 or selected >= r.count or not r:isOpen(selected) then
    core.writeInteger(state.selected, r:suggest())
  end
end

---Without door pictures the route `r` of `trail` (nil for none) can't show side missions and
---parallel paths: a route that has them plays its rows in order from now on.
function progress.withoutPictures(trail, r)
  if r == nil or not r.graph then
    return
  end
  log(WARNING, string.format("%s: side missions and parallel paths need door pictures "
    .. "(mission_icons); the trail plays its missions in their order", trail))
  r:playLinear()
  local state = stores[trail]
  if state ~= nil and state.route == r then
    -- the game's rows from before the route's frontier replaced them
    core.writeInteger(state.furthest, state.gameRows.furthest)
    core.writeInteger(state.selected, state.gameRows.selected)
    follow(state)
  end
end

---Plays `trail` by the route `r` (route.lua): every win and chicken skip passes its node; for a
---route of side missions or parallel paths the furthest row is the route's frontier and the next
---playable main mission is selected. Each node's win is kept with the players alive then, and its
---reward of chickens is given at its first win. False when a game site is not found.
function progress.installRoute(trail, r)
  local selectSite = SELECT_STORES[trail]
  local selected = memory.TRAIL_PROGRESS_ADDRESSES[trail]
  local select = patches.siteAddress(selectSite, "side missions")
  local compare = patches.siteAddress(WIN_COMPARES[trail], "trail results")
  local chicken = chickenHooked or patches.siteAddress(CHICKEN_SITE, "side missions")
  if selected == nil or select == nil or compare == nil or not chicken
      or core.readInteger(select + 2) ~= selected then
    return false
  end
  local state = winStore(trail, "side missions")
  if state == nil then return false end
  patches.apply("Player facts for trail route results", unitlimits.bindPlayerFacts)
  local won = patches.luaStub(function(registers)
    local row = core.readInteger(state.selected)
    r:pass(row)
    recordWin(state, row)
    return registers
  end)
  -- the call runs before the compare, so the branch after it reads the compare's flags
  core.insertCode(compare, 6, { core.callTo(won) }, nil, "after")
  core.detourCode(function(registers)
    if r.graph then
      registers[selectSite.register] = r:suggest()
    end
    return registers
  end, select, 6)
  if not chickenHooked then
    core.detourCode(function(registers)
      onChicken()
      return registers
    end, chicken, 5)
    chickenHooked = true
  end
  -- the trail's wins and chickens come after afterInit, when the game has loaded its progress
  hooks.registerHookCallback("afterInit", function()
    r:readFiles()
    state.route = r
    r:seed(core.readInteger(state.furthest))
    state.gameRows = { furthest = core.readInteger(state.furthest), selected = core.readInteger(state.selected) }
    follow(state)
  end)
  return true
end

return progress
