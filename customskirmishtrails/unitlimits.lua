-- Troop limits per trail mission (unit_limit). The game computes the player's
-- troop limit every tick in one function: in single-player games (custom scenarios) it is 10000,
-- otherwise base / living lords - offset (base 2400 in Crusader, 9900 in Extreme, offset 40). A
-- mission's policy replaces the stored value while that mission is played:
--   native               the game's own value
--   formula BASE OFFSET  BASE / living lords - OFFSET ("formula 2400 40" = Crusader limits)
--   by_alive L=N ...     N troops at L living lords, linear between the listed counts and
--                        rounded down ("by_alive 8=250 4=500 2=1000 1=2000")
-- The result never exceeds the game's skirmish formula for the living lords, also in scenarios,
-- where the game itself has no limit (10000). The mission comes from the game's trail state
-- (skirmish missions) or the scenario the trail started (see scenario.session).
--
-- The function is found by AOB, the same in both 1.41 executables, with the operands decoded.
-- The game counts the lords of the skirmish lobby's slots, which don't describe a scenario. So
-- the scenario the trail started, when its mission has a policy, goes straight to the store, and
-- its living lords are the players with a lord (as the game's single-player defeat check reads
-- it) that isn't marked killed (as the game's count reads it).

local patches = require("customskirmishtrails.patches")
local memory = require("customskirmishtrails.memory")

local unitlimits = {}

-- "cmp dword [syncMode], 0 / jne count / mov dword [ecx + limit], 10000 / ret / push esi ... /
-- mov edx, players / ... / cmp dword [edx + killed], 0" (the lord-killed marker of player 1)
local ENTRY_AOB = "83 3D I(? ? ? ?) 00 75 0B C7 81 I(? ? ? ?) I(? ? ? ?) C3 56 57 33 F6 BA I(? ? ? ?) "
  .. "B8 ? ? ? ? 83 CF FF 39 78 94 75 05 83 38 00 74 0C 83 BA I(? ? ? ?) 00"
-- "mov eax, base / cdq / idiv esi / pop edi / pop esi / sub eax, offset / mov [ecx + limit], eax / ret"
local STORE_AOB = "B8 I(? ? ? ?) 99 F7 FE 5F 5E 83 E8 ? 89 81 I(? ? ? ?) C3 5F C7 81 ? ? ? ? ? ? ? ? 5E C3"
local STORE_OFFSET = 0x0D
local STORE_PATCH_SIZE = 6   -- mov [ecx + limit], eax
local ENTRY_PATCH_SIZE = 9   -- the compare (7 bytes) and the short jne (2 bytes)
local COUNT_OFFSET = 0x14    -- where the jne goes: the counting part
-- The single-player defeat check: "imul ecx, ecx, player size / cmp dword [ecx + campground], 0 /
-- jle lost / cmp dword [ecx + lord], 0 / jg playing" (the lord of player 0, the players follow).
local SCENARIO_LORD_AOB = "69 C9 I(? ? ? ?) 83 B9 I(? ? ? ?) 00 7E 09 83 B9 I(? ? ? ?) 00 7F 0C"
local GAME_MODE_SCENARIO = 2
local SYNC_MODE_SKIRMISH = 99
local MAX_LORDS = 8
local MAX_LIMIT = 100000 -- above every limit the game computes

local bindings = nil
local registry = nil
local session = nil
local isPlayedMission = function() return true end
local installed = { skirmish = false, scenario = false }

---Reads a unit_limit cell ("native", "formula 2400 40"; empty is native). Returns the policy or
---nil and a reason.
function unitlimits.parse(text)
  if text == nil or text == "" then
    return { kind = "native" }
  end
  if type(text) ~= "string" then
    return nil, "must be a text"
  end
  local words = {}
  for word in text:gmatch("%S+") do words[#words + 1] = word:lower() end
  if #words == 1 and words[1] == "native" then
    return { kind = "native" }
  end
  if #words == 3 and words[1] == "formula" then
    local base, offset = math.tointeger(tonumber(words[2])), math.tointeger(tonumber(words[3]))
    if base ~= nil and offset ~= nil and base > 0 and base <= MAX_LIMIT and offset >= 0 and offset <= MAX_LIMIT then
      return { kind = "formula", base = base, offset = offset }
    end
  end
  if #words >= 2 and words[1] == "by_alive" then
    local points, seen = {}, {}
    for index = 2, #words do
      local lords, limit = words[index]:match("^(%d+)=(%d+)$")
      lords, limit = math.tointeger(tonumber(lords)), math.tointeger(tonumber(limit))
      if lords == nil or lords < 1 or lords > MAX_LORDS or seen[lords] or limit == nil or limit > MAX_LIMIT then
        points = nil
        break
      end
      seen[lords] = true
      points[#points + 1] = { lords = lords, limit = limit }
    end
    if points ~= nil then
      table.sort(points, function(a, b) return a.lords < b.lords end)
      return { kind = "by_alive", points = points }
    end
  end
  return nil, string.format("'%s' is not 'native', 'formula BASE OFFSET' or 'by_alive LORDS=LIMIT ...' "
    .. "(BASE 1-%d, OFFSET 0-%d, each LORDS 1-8 once, LIMIT at most %d)", text, MAX_LIMIT, MAX_LIMIT, MAX_LIMIT)
end

---A policy's limit for `lords` living lords. by_alive interpolates linearly between the listed
---counts and keeps the nearest listed limit outside them.
function unitlimits.value(policy, lords)
  if policy.kind == "formula" then
    return policy.base // lords - policy.offset
  end
  local points = policy.points
  if lords <= points[1].lords then
    return points[1].limit
  end
  for index = 2, #points do
    local low, high = points[index - 1], points[index]
    if lords <= high.lords then
      return low.limit + (high.limit - low.limit) * (lords - low.lords) // (high.lords - low.lords)
    end
  end
  return points[#points].limit
end

---The policy a mission plays with, or nil for the game's own value.
function unitlimits.policy(entry)
  return type(entry) == "table" and entry.unit_limit_policy or nil
end

---False when the mission has a policy that can't be applied (the game code was not found), so
---that it doesn't start without its limit. `isScenario`: the mission starts as a scenario.
function unitlimits.available(entry, isScenario)
  if unitlimits.policy(entry) == nil then
    return true
  end
  return installed.skirmish and (not isScenario or installed.scenario)
end

local function resolve()
  local okEntry, entry, syncMode, limitField, singlePlayerValue, players, killed =
    pcall(patches.extract, ENTRY_AOB)
  local okStore, store, base, storeField = pcall(patches.extract, STORE_AOB)
  if not okEntry or not okStore or entry == nil or store == nil then
    log(WARNING, "could not find the troop limit; unit_limit is switched off")
    return nil
  end
  if limitField ~= storeField or store <= entry or store - entry > 0x100 then
    log(WARNING, "unexpected troop limit code; unit_limit is switched off")
    return nil
  end
  return {
    entry = entry,
    store = store,
    syncMode = syncMode,
    field = limitField,
    singlePlayerValue = singlePlayerValue,
    firstLordKilled = players + killed,
    base = base,
    offset = core.readByte(store + STORE_OFFSET - 1),
    storeSite = store + STORE_OFFSET,
  }
end

---True when both sites still hold the code and operands found by resolve (another patch may
---have changed them since).
local function unchanged(b)
  return patches.matches(b.entry, patches.plain(ENTRY_AOB)) and patches.matches(b.store, patches.plain(STORE_AOB))
    and core.readInteger(b.entry + 2) == b.syncMode and core.readInteger(b.entry + 11) == b.field
    and core.readInteger(b.entry + 15) == b.singlePlayerValue and core.readInteger(b.store + 1) == b.base
    and core.readInteger(b.store + 15) == b.field and core.readByte(b.store + STORE_OFFSET - 1) == b.offset
end

---The number of living lords the game's formula used, from its result.
local function livingLords(value)
  for lords = 1, MAX_LORDS do
    if bindings.base // lords - bindings.offset == value then
      return lords
    end
  end
  return nil
end

---The players' lords and keeps from the single-player defeat check, into `b`; false and the
---reason when it is not found.
local function resolvePlayers(b)
  local okSite, lordSite, playerSize, campgrounds, lordIds = pcall(patches.extract, SCENARIO_LORD_AOB)
  if not okSite or lordSite == nil then
    return false, "the single-player defeat check was not found"
  end
  b.playerSize, b.firstLordId, b.firstCampground = playerSize, lordIds + playerSize, campgrounds + playerSize
  return true
end

---Player `player` (1-8) has a lord that isn't marked killed.
local function lordAlive(b, player)
  local offset = (player - 1) * b.playerSize
  return core.readInteger(b.firstLordId + offset) > 0 and core.readInteger(b.firstLordKilled + offset) == 0
end

---The living lords of a scenario: players 1-8 with a lord that isn't marked killed.
local function scenarioLords(b)
  local count = 0
  for player = 1, MAX_LORDS do
    if lordAlive(b, player) then
      count = count + 1
    end
  end
  return count > 0 and count or nil
end

---Players 1-8 now: `lords` holds those whose lord is alive (a lord that isn't marked killed, as the
---troop limit counts it), `players` those who also still have their keep (as the single-player
---defeat check reads it). nil when the game code was not found.
function unitlimits.playerFacts()
  local b = bindings
  if b == nil or b.playerSize == nil then
    return nil
  end
  local facts = { lords = {}, players = {} }
  for player = 1, MAX_LORDS do
    if lordAlive(b, player) then
      facts.lords[player] = true
      if core.readInteger(b.firstCampground + (player - 1) * b.playerSize) > 0 then
        facts.players[player] = true
      end
    end
  end
  return facts
end

---The trail mission being played: in single-player mode only the trail's scenario reaches the
---store (the entry patch checks it); in single-player skirmish the game's trail state names it,
---unless it is a scenario mission whose map isn't the one played.
local function playedEntry(syncMode)
  if syncMode == 0 then
    return session ~= nil and session.entry() or nil
  end
  if syncMode ~= SYNC_MODE_SKIRMISH then
    return nil
  end
  local ok, isTrail, _, trailName, index = pcall(memory.fetchCurrentTrail)
  if not ok or not isTrail then
    return nil
  end
  local missions = registry[trailName]
  local entry = missions and missions[index] or nil
  return isPlayedMission(entry) and entry or nil
end

local function installStore(b)
  patches.guarded({ { address = b.storeSite, size = STORE_PATCH_SIZE } }, function()
    core.detourCode(function(registers)
      local syncMode = core.readInteger(b.syncMode)
      local singlePlayer = syncMode == 0
      local policy = unitlimits.policy(playedEntry(syncMode))
      local lords = nil
      if policy ~= nil and singlePlayer then
        lords = scenarioLords(b)
      elseif policy ~= nil then
        lords = livingLords(registers.EAX)
      end
      if lords ~= nil then
        registers.EAX = math.max(0, math.min(unitlimits.value(policy, lords), b.base // lords - b.offset))
      elseif singlePlayer then
        registers.EAX = b.singlePlayerValue
      end
      return registers
    end, b.storeSite, STORE_PATCH_SIZE)
  end)
end

---Single-player games go to the store only for the trail's scenario: the scenario mode is on, its
---mission has a policy (session.cap) and the chosen map is the session's (session.sameMap).
---Otherwise the game's own compare is repeated, so its single-player store runs with the flags it had.
local function installEntry(b, s)
  if b.playerSize == nil then
    error(b.playersProblem)
  end
  patches.guarded({ { address = b.entry, size = ENTRY_PATCH_SIZE } }, function()
    core.insertCode(b.entry, ENTRY_PATCH_SIZE, { core.AssemblyLambda([[
      cmp dword [syncMode], 0
      jne near countPart
      cmp byte [cap], 0
      je notTrail
      cmp dword [gameMode], scenarioMode
      jne notTrail
      call near sameMap
      jne notTrail
      mov eax, singlePlayerValue ; the store's detour replaces it
      jmp near storeSite
    notTrail:
      cmp dword [syncMode], 0
    ]], {
      syncMode = b.syncMode,
      countPart = b.entry + COUNT_OFFSET,
      cap = s.cap,
      gameMode = s.gameMode,
      scenarioMode = GAME_MODE_SCENARIO,
      sameMap = s.sameMap,
      singlePlayerValue = b.singlePlayerValue,
      storeSite = b.storeSite,
    }) })
  end)
end

---Binds the troop limit once before a route or custom limit needs it.
function unitlimits.enable()
  if bindings ~= nil then return end
  bindings = resolve()
end

function unitlimits.bindPlayerFacts()
  unitlimits.enable()
  if bindings == nil then return false end
  if bindings.playerSize ~= nil then return true end
  return resolvePlayers(bindings)
end

---Reads the unit_limit of every mission and installs the troop limit when a mission has a policy
---other than native. Call it after the trails' missions are loaded.
---`scenarioSession` (scenario.session(), or nil) is needed for scenario missions;
---`playedMission(entry)` (scenario.isPlayedMission) is false for a scenario mission not played.
function unitlimits.apply(trails, scenarioSession, playedMission)
  isPlayedMission = playedMission or isPlayedMission
  registry = trails
  local any = false
  for trailName, missions in pairs(trails) do
    for index, entry in ipairs(missions) do
      local policy, reason = unitlimits.parse(entry.unit_limit)
      if policy == nil then
        log(WARNING, string.format("%s mission %d: unit_limit %s", trailName, index, reason))
      end
      entry.unit_limit_policy = (policy ~= nil and policy.kind ~= "native") and policy or nil
      any = any or entry.unit_limit_policy ~= nil
    end
  end
  if not any or installed.skirmish then
    return
  end
  patches.apply("Custom troop limits in trail missions", function()
    unitlimits.enable()
    if bindings == nil or not unchanged(bindings) then return false end
    installStore(bindings)
    installed.skirmish = true
  end)
  if not installed.skirmish or scenarioSession == nil then return end
  patches.apply("Custom troop limits in scenario missions", function()
    if not unitlimits.bindPlayerFacts() then return false end
    installEntry(bindings, scenarioSession)
    session = scenarioSession
    installed.scenario = true
  end)
end

return unitlimits
