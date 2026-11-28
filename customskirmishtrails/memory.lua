local patches = require("customskirmishtrails.patches")

local memory = {
  TRAIL_TYPES = { [0] = "firstEditionTrail", [1] = "warchestTrail", [2] = "extremeTrail" },
  TRAIL_PROGRESS_ADDRESSES = {},
  REGISTRY = {},
}

local PROGRESS_AOBS = {
  firstEditionTrail = "8B ? I(? ? ? ?) 8B ? ? ? ? ? ? 89 ? ? ? ? ? 8B C1",
  warchestTrail = "89 ? I(? ? ? ?) E8 ? ? ? ? 8B ? ? ? ? ? 8B ? ? ? ? ? ? 89 ? ? ? ? ?",
  extremeTrail = "89 ? I(? ? ? ?) E8 ? ? ? ? A1 ? ? ? ? 8B ? ? ? ? ? ? 89 ? ? ? ? ?",
}

local EXTRA_AOBS = {
  START_GOODS = "BF I(? ? ? ?) F3 A5 89 ? ? ? ? ?",
  STARTING_TROOPS = "BE I(? ? ? ?) C7 ? ? ? ? ? ? ? 8B 44 24 10",
  WEAPON_PRODUCIBLE = "89 ? I(? ? ? ?) 89 ? ? ? ? ? 89 ? ? ? ? ? 89 ? ? ? ? ? 89 ? ? ? ? ? 89 ? ? ? ? ? 66 ? ? ? ? ? ? 66 ? ? ? ? ? ? 89 ? ? ? ? ?",
}

function memory.bindExtra(field)
  local _, address = patches.extract(EXTRA_AOBS[field])
  memory[field] = address
  return address ~= nil
end

function memory.bindRecruitability()
  local _, european, mercenary = patches.extract("A3 I(? ? ? ?) A3 I(? ? ? ?) A3 ? ? ? ? A3 ? ? ? ? A3 ? ? ? ? A3 ? ? ? ? A3 ? ? ? ? A3 ? ? ? ? A3 ? ? ? ? A3 ? ? ? ? A3 ? ? ? ? A3 ? ? ? ? A3 ? ? ? ? A3 ? ? ? ? 89 44 24 10")
  if european == nil or mercenary == nil then return false end
  memory.EURO_RECRUITABLE, memory.MERC_RECRUITABLE = european, mercenary
  return true
end

function memory.bindProgress(trailName)
  if memory.TRAIL_PROGRESS_ADDRESSES[trailName] == nil then
    local _, address = patches.extract(PROGRESS_AOBS[trailName])
    memory.TRAIL_PROGRESS_ADDRESSES[trailName] = address
  end
  return memory.TRAIL_PROGRESS_ADDRESSES[trailName]
end

function memory.bindTrailType()
  if memory.CURRENT_TRAIL_TYPE == nil then
    local _, address = patches.extract("A1 I(? ? ? ?) 83 C6 70")
    memory.CURRENT_TRAIL_TYPE = address
  end
  return memory.CURRENT_TRAIL_TYPE ~= nil
end

function memory.bindMissionContext()
  local _, isTrail = patches.extract("C7 ? I(? ? ? ?) ? ? ? ? 56 75 23")
  if isTrail == nil or not memory.bindTrailType() then return false end
  memory.IS_SKIRMISH_TRAIL = isTrail
  return true
end

function memory.fetchCurrentTrail()
  if memory.IS_SKIRMISH_TRAIL == nil then return false end
  local isTrail = core.readInteger(memory.IS_SKIRMISH_TRAIL) == 1
  local trail = core.readInteger(memory.CURRENT_TRAIL_TYPE)
  local trailName = memory.TRAIL_TYPES[trail]
  local address = memory.TRAIL_PROGRESS_ADDRESSES[trailName]
  if address == nil then return isTrail, trail end
  return isTrail, trail, trailName, core.readInteger(address) + 1
end

---The mission being prepared or played, and whether the game is in a trail.
function memory.currentEntry()
  local isTrail, _, trailName, mission = memory.fetchCurrentTrail()
  local missions = memory.REGISTRY[trailName]
  return missions ~= nil and missions[mission] or nil, isTrail
end

return memory
