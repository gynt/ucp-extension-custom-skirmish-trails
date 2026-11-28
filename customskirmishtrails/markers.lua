-- Door pictures on the trail screen: trail_visuals.mission_icons and the missions'
-- icon_locked / icon_available / icon_won, each optional. A mission shows its picture of a
-- state in place of the game's marker of that state: locked (its click is not taken) until the
-- trail reaches it, and, with an available picture, its date has come and its map is installed;
-- available after that; a won mission draws its won picture over it. For a state without a
-- picture the game draws its own marker, so a mission without icon looks as it does without a
-- sheet. The game's chicken stays. A mission of the trail's route (route.lua) that the game's
-- furthest mission doesn't describe (a side mission, a parallel path) is reached and won by the
-- route and drawn only by its own pictures.
--
-- All sites lie in the trail screen's draw (render) and click functions, at the same offsets in
-- Stronghold Crusader.exe and Stronghold_Crusader_Extreme.exe.

local memory = require("customskirmishtrails.memory")
local patches = require("customskirmishtrails.patches")
local progress = require("customskirmishtrails.progress")
local scenario = require("customskirmishtrails.scenario")
local cst_io = require("customskirmishtrails.io")

local markers = {}

local STATES = { "locked", "available", "won" }
local SKIPPED = -1200 -- the score of a mission a chicken skipped

-- test edx, edx / mov [esp+14h], 0: the trail is in EDX, and ECX / EAX hold the trail screen's origin
-- ((width - 800) / 2, (height - 600) / 2), from which the click test measures a mission's position
local RENDER_SITE = { fn = "render", offset = 0x125, bytes = "85 D2 C7 44 24 14 00 00 00 00" }
local HALF_PICTURE = 50 -- the sheet's pictures are 100 x 100
local RENDER_SIZE = 10
-- the Warchest's next-mission marker: push sheet / mov ecx, screen / call draw (thiscall: sheet, picture, x, y)
local DRAW_SITE = { fn = "render", offset = 0x88F, bytes = "68 ? ? ? ? B9 ? ? ? ? E8 ? ? ? ?" }

-- furthest: "cmp [furthest], ebp" before the marker loop. scores: "cmp [ebp*4 + scores], -1200".
-- hit: "mov [selected], edx" when a click hits a mission; miss: "add edx, ebp", the next mission.
-- bound: "mov ebx, [furthest]", the last mission the click loop tries.
-- nextRow: "mov reg, [esi*8 + positions + 4]" between the next mission's shadow and marker: ESI holds
-- its row there.
-- flags: the calls that draw the game's markers: shadow, flag (or skipped) of each mission before
-- the furthest one (its row in EBP), the next mission's shadow and marker (its row in ESI). A shadow
-- draw takes one argument more.
local SITES = {
  firstEditionTrail = {
    furthest = { fn = "render", offset = 0x137, bytes = "39 2D ? ? ? ? 0F 8E" },
    scores = { fn = "render", offset = 0x1AC, bytes = "81 3C AD ? ? ? ? 50 FB FF FF" },
    hit = { fn = "click", offset = 0x22A, bytes = "89 15 ? ? ? ?" },
    miss = { fn = "click", offset = 0x21E, bytes = "03 D5 83 FA" },
    bound = { fn = "click", offset = 0x1E6, bytes = "8B 1D ? ? ? ? 33 D2" },
    nextRow = { fn = "render", offset = 0x3CD, bytes = "8B 04 F5 ? ? ? ? 8B 0C F5" },
    flags = { 0x1F8, 0x2D9, 0x3C8, 0x3F3 },
  },
  warchestTrail = {
    furthest = { fn = "render", offset = 0x653, bytes = "39 2D ? ? ? ? 0F 8E" },
    scores = { fn = "render", offset = 0x6A5, bytes = "81 3C AD ? ? ? ? 50 FB FF FF" },
    hit = { fn = "click", offset = 0x27B, bytes = "89 15 ? ? ? ?" },
    miss = { fn = "click", offset = 0x26F, bytes = "03 D5 83 FA" },
    bound = { fn = "click", offset = 0x239, bytes = "8B 1D ? ? ? ? 33 D2" },
    nextRow = { fn = "render", offset = 0x873, bytes = "8B 0C F5 ? ? ? ? 8B 14 F5" },
    flags = { 0x6DD, 0x77A, 0x86E, 0x899 },
  },
  extremeTrail = {
    furthest = { fn = "render", offset = 0xAFA, bytes = "39 2D ? ? ? ? 0F 8E" },
    scores = { fn = "render", offset = 0xB4E, bytes = "81 3C AD ? ? ? ? 50 FB FF FF" },
    hit = { fn = "click", offset = 0x2CA, bytes = "89 15 ? ? ? ?" },
    miss = { fn = "click", offset = 0x2BE, bytes = "03 D5 83 FA" },
    bound = { fn = "click", offset = 0x288, bytes = "8B 1D ? ? ? ? 33 D2" },
    nextRow = { fn = "render", offset = 0xD1C, bytes = "8B 0C F5 ? ? ? ? 8B 14 F5" },
    flags = { 0xB86, 0xC23, 0xD17, 0xD42 },
  },
}
local FLAG_ARGUMENT_BYTES = { 0x14, 0x10, 0x14, 0x10 }
local FLAG_ROWS = { "ebp", "ebp", "esi", "esi" }
local FLAG_TABLES = { "hideWon", "hideWon", "hideNext", "hideNext" }

local FLAG_STUB = [[
  cmp byte [%s + HIDE_TABLE], 0
  je near DRAW_MARKER
  ret ARGUMENT_BYTES
]]

local CLICK_STUB = [[
  cmp byte [edx + LOCK_TABLE], 0
  jne near MISS
  mov dword [SELECTED_MISSION], edx
]]

local native = nil -- { render, sheet, screen, draw, detoured } once found
-- trailName -> { gm, count, pictures, locks, hideWon, hideNext, positions, furthest, scores, route, reach, list,
--   day, nextDay, seen, skips, version }
local doors = {}

local function siteOf(site)
  return patches.siteAddress(site, "door pictures")
end

local function resolveNative()
  if native == nil then
    local render, drawSite = siteOf(RENDER_SITE), siteOf(DRAW_SITE)
    native = render ~= nil and drawSite ~= nil and {
      render = render,
      sheet = core.readInteger(drawSite + 1),
      screen = core.readInteger(drawSite + 6),
      draw = core.exposeCode((drawSite + 15 + core.readInteger(drawSite + 11)) & 0xFFFFFFFF, 5, 1),
    } or false
  end
  return native or nil
end

---The icon sheet's pictures of `entry` ({ locked, available, won }, each nil when left out or
---outside the sheet's `count` pictures).
local function picturesOf(trailName, index, entry, count)
  local pictures = {}
  for number, state in ipairs(STATES) do
    local value = entry["icon_" .. state]
    local picture = math.tointeger(value)
    if picture ~= nil and picture >= 0 and picture < count then
      pictures[number] = picture
    elseif value ~= nil and value ~= "" then
      log(WARNING, string.format("%s mission %d: icon %s %s is not a picture 0 to %d "
        .. "of the icon sheet; the game's marker stays", trailName, index, state, tostring(value), count - 1))
    end
  end
  return pictures
end

---Which doors have pictures and which are open (date and map); again at the next midnight.
local function refresh(trailName, door, now)
  -- without isdst, os.time works out daylight saving time for each midnight on its own
  local date = os.date("*t", now)
  door.day = os.time({ year = date.year, month = date.month, day = date.day, hour = 0 })
  door.nextDay = os.time({ year = date.year, month = date.month, day = date.day + 1, hour = 0 })
  door.list = {}
  local missions = memory.REGISTRY[trailName] or {}
  for index = 1, door.count do
    local entry = missions[index]
    local pictures = entry and picturesOf(trailName, index, entry, door.pictures) or {}
    -- the date and the map lock a door that draws its own available picture
    door.list[index] = { pictures = pictures, open = pictures[2] == nil or scenario.isOpen(entry) }
    if pictures[2] == nil and door.route ~= nil and door.route:needsPictures(index - 1) then
      log(WARNING, string.format("%s mission %d is off the trail's order and has no "
        .. "icon_available; it can't be played", trailName, index))
    end
  end
end

---Works out which doors are open and won, and writes the game's click and marker tables for them.
local function update(door, furthest, skips)
  local r, reach = door.route, furthest
  for index = 1, door.count do
    local slot, item = index - 1, door.list[index]
    local pictures = item.pictures
    -- the game's markers follow its furthest mission: right for every mission without a route, and
    -- for the route's chain missions
    local gameDraws = r == nil or not r:needsPictures(slot)
    local open = slot <= furthest
    local skipped = skips & (1 << slot) ~= 0
    local won = slot < furthest and not skipped
    if not gameDraws then
      open, won = pictures[2] ~= nil and r:isOpen(slot), r:isPassed(slot) and not skipped
    end
    item.isOpen, item.won = open and item.open, won
    core.writeByte(door.locks + slot, item.isOpen and 0 or 1)
    core.writeByte(door.hideWon + slot, (not gameDraws or pictures[3] ~= nil) and 1 or 0)
    core.writeByte(door.hideNext + slot, (not gameDraws or pictures[2] ~= nil) and 1 or 0)
    if item.isOpen and slot > reach then
      reach = slot
    end
  end
  if door.reach ~= nil then
    core.writeInteger(door.reach, reach)
  end
end

local function onRender(registers)
  local trailName = memory.TRAIL_TYPES[registers.EDX]
  local door = trailName and doors[trailName]
  if door == nil then
    return registers
  end
  local furthest = core.readInteger(door.furthest)
  if door.gm < 0 then
    if door.seen ~= furthest then
      door.seen = furthest
      for slot = 0, door.count - 1 do
        core.writeByte(door.hideWon + slot, 0)
        core.writeByte(door.hideNext + slot, 0)
      end
      if door.reach ~= nil then
        core.writeInteger(door.reach, furthest)
      end
    end
    return registers
  end
  local now = os.time()
  local skips = 0
  for slot = 0, door.count - 1 do
    if core.readInteger(door.scores + slot * 4) == SKIPPED then
      skips = skips | (1 << slot)
    end
  end
  local version = door.route and door.route.version or 0
  local stale = door.nextDay == nil or now < door.day or now >= door.nextDay
  if stale then
    refresh(trailName, door, now)
  end
  if stale or door.seen ~= furthest or door.skips ~= skips or door.version ~= version then
    door.seen, door.skips, door.version = furthest, skips, version
    update(door, furthest, skips)
  end
  for index = 1, door.count do
    local slot, item = index - 1, door.list[index]
    local pictures = item.pictures
    -- a door is centred where the click test takes the mission
    local x = core.readInteger(door.positions + slot * 8) + registers.ECX - HALF_PICTURE
    local y = core.readInteger(door.positions + slot * 8 + 4) + registers.EAX - HALF_PICTURE
    -- the game's draw counts pictures from 1
    local picture = item.isOpen and pictures[2] or not item.isOpen and pictures[1]
    if picture then
      native.draw(native.screen, door.gm, picture + 1, x, y)
    end
    if item.won and pictures[3] ~= nil then
      native.draw(native.screen, door.gm, pictures[3] + 1, x, y)
    end
  end
  return registers
end

---Reserves `sheetPath` (a .gm1 file of the type of skirmish_trail_icons.gm1) for `trailName`, which
---has `count` missions, and takes over its markers and clicks. With `r` (route.lua), the missions
---off the trail's order are drawn and clicked by their own state. Call while extensions are enabled.
---True when the doors are taken over.
function markers.install(trailName, sheetPath, count, r)
  local sites = SITES[trailName]
  local furthest, scores = siteOf(sites.furthest), siteOf(sites.scores)
  local hit, miss, nextRow = siteOf(sites.hit), siteOf(sites.miss), siteOf(sites.nextRow)
  local bound = r ~= nil and siteOf(sites.bound)
  if bound == nil then return end
  local positions = patches.positionTable(trailName)
  local flags = {}
  for index, offset in ipairs(sites.flags) do
    flags[index] = siteOf({ fn = "render", offset = offset, bytes = "E8 ? ? ? ?" })
    if flags[index] == nil then return end
  end
  if furthest == nil or scores == nil or hit == nil or miss == nil or nextRow == nil or positions == nil
      or resolveNative() == nil then
    return
  end
  if core.readInteger(nextRow + 3) ~= positions + 4 then
    log(WARNING, "unexpected game code for the next mission's marker; door pictures are switched off")
    return
  end
  if bound and core.readInteger(bound + 2) ~= core.readInteger(furthest + 2) then
    log(WARNING, "unexpected game code for side missions; door pictures are switched off")
    return
  end
  local bytes, reason = cst_io.readBytes(sheetPath)
  if bytes == nil then
    log(WARNING, string.format("cannot read the marker sheet %s: %s", sheetPath, tostring(reason)))
    return
  end
  local modifier = modules.gmResourceModifier
  local sheet = modifier:LoadGm1ResourceFromData(bytes)
  local token = sheet and modifier:ReserveGm(native.sheet, sheet.id) or -1
  if token < 0 then
    if sheet ~= nil then modifier:FreeGm1Resource(sheet.id) end
    log(WARNING, string.format("%s is not a .gm1 sheet; the game's markers stay", sheetPath))
    return
  end

  local locks = core.allocate(patches.CAPACITY[trailName], true)
  local tables = { hideWon = core.allocate(patches.CAPACITY[trailName], true),
    hideNext = core.allocate(patches.CAPACITY[trailName], true) }
  local reach = bound and core.allocate(4, true)
  local hitSize = 6
  local patched = { { address = hit, size = hitSize } }
  if bound then
    table.insert(patched, { address = bound, size = 6 })
  end
  for _, flag in ipairs(flags) do
    table.insert(patched, { address = flag, size = 5 })
  end
  if not native.detoured then
    table.insert(patched, { address = native.render, size = RENDER_SIZE })
  end
  local ok, err = pcall(patches.guarded, patched, function()
    if not native.detoured then
      core.detourCode(onRender, native.render, RENDER_SIZE)
    end
    for index, flag in ipairs(flags) do
      -- cmp byte [row + table], 0 / je draw / ret: the game's marker of a mission's state is drawn
      -- only where the mission has no picture of its own for it
      local target = (flag + 5 + core.readInteger(flag + 1)) & 0xFFFFFFFF
      local stub = core.allocateAssembly(FLAG_STUB:format(FLAG_ROWS[index]), {
        HIDE_TABLE = tables[FLAG_TABLES[index]], DRAW_MARKER = target,
        ARGUMENT_BYTES = FLAG_ARGUMENT_BYTES[index],
      })
      core.writeCodeInteger(flag + 1, core.getRelativeAddress(flag, stub, -5))
    end
    core.insertCode(hit, hitSize, { core.AssemblyLambda(CLICK_STUB, {
      LOCK_TABLE = locks, MISS = miss, SELECTED_MISSION = core.readInteger(hit + 2),
    }) })
    if bound then
      -- mov ebx, [reach]: the last mission that can be clicked, side missions included
      core.writeInteger(reach, core.readInteger(core.readInteger(furthest + 2)))
      core.writeCodeInteger(bound + 2, reach)
    end
  end)
  if not ok then
    log(WARNING, "door pictures are switched off: " .. tostring(err))
    return
  end
  native.detoured = true
  local door = {
    count = count, pictures = sheet.pictures, locks = locks, hideWon = tables.hideWon, hideNext = tables.hideNext,
    positions = positions, route = r, reach = reach or nil,
    furthest = core.readInteger(furthest + 2), scores = core.readInteger(scores + 3),
  }
  doors[trailName] = door
  -- the game loads its gm files before afterInit
  hooks.registerHookCallback("afterInit", function()
    door.gm = modifier:GetReservedGm(token)
    if door.gm < 0 then
      log(ERROR, "Trail door pictures are off. The graphics modifier did not load the sheet.")
      progress.withoutPictures(trailName, r)
    end
  end)
  log(INFO, string.format("%s door pictures from %s", trailName, sheetPath))
  return true
end

return markers
