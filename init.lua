
local memory = require("customskirmishtrails.memory")
local interface = require("customskirmishtrails.interface")
local input = require("customskirmishtrails.input")
local description = require("customskirmishtrails.description")
local tradeability = require("customskirmishtrails.interface_tradeability")

local TRAIL_TYPES = {
  [0] = "firstEditionTrail",
  [1] = "warchestTrail",
  [2] = "extremeTrail",
}

---@type table<string, table<number, table>>
local REGISTRY = {
  ["firstEditionTrail"] = nil,
  ["warchestTrail"] = nil,
  ["extremeTrail"] = nil,
}

local TRAIL_PROGRESS_ADDRESSES = {
  ["firstEditionTrail"] = memory.FIRST_EDITION_TRAIL_PROGRESS,
  ["warchestTrail"] = memory.WARCHEST_TRAIL_PROGRESS,
  ["extremeTrail"] = memory.EXTREME_TRAIL_PROGRESS,
}


local function removeExtremeMultiplier()
  local visualAddr= core.AOBScan("8D 77 01 8B ? ? ? ? ? A1 ? ? ? ?")
  -- core.writeCode(visualAddr, {0x90, 0x90, 0x90, })
end

local function fetchCurrentTrail()
    local trail =  core.readInteger(memory.CURRENT_TRAIL_TYPE) 
    local trailName = TRAIL_TYPES[trail]

    if trailName == nil then error(string.format("invalid trail: %s", trail)) end

    local progressAddr = TRAIL_PROGRESS_ADDRESSES[trailName]

    local mission = core.readInteger(progressAddr) + 1
    
    return trail, trailName, mission
end

local function insertPostSkirmishSetupDetour()
  log(2, "insertPostSkirmishSetupDetour: setting up detour")
  local detourLocation, detourSize = core.AOBScan("A1 ? ? ? ? 8D 0C 80 03 C9 89 ? ? ? ? ?"), 5
  core.detourCode(function(registers)
    if core.readInteger(memory.IS_SKIRMISH_TRAIL) ~= 1 then
      log(2, "not in skirmish trail")
      return registers
    end

    local trail =  core.readInteger(memory.CURRENT_TRAIL_TYPE) 
    local trailName = TRAIL_TYPES[trail]

    if trailName == nil then error(string.format("invalid trail: %s", trail)) end

    log(2, string.format("trail: %s", trailName))

    local progressAddr = TRAIL_PROGRESS_ADDRESSES[trailName]

    local mission = core.readInteger(progressAddr) + 1

    local missions = REGISTRY[trailName]
    if missions == nil then
      log(2, string.format("No custom missions registered for trail name: %s", trailName))
      return registers
    end

    log(2, string.format("Committing extra parameters for %s mission: %s", trailName, mission))
    
    local entry = missions[mission]
    if entry == nil then log(-1, string.format("skirmish trail (%s) entry is unexpectedly nil: %s", trailName, mission)) end
    interface.commitEntryExtra(entry)

    return registers

  end, detourLocation, detourSize)
end

local function applyTrail(trailName, path, missions, limit)
  local result, err = input.readCSV(path, limit)
  if result == nil then error(err) end
  
  local f = io.open(string.format("ucp/.cache/custom-skirmish-trails-config-%s.yml", trailName), 'w')
  f:write(yaml.dump(result))
  f:close()

  REGISTRY[trailName] = result
  
  for index, entry in pairs(REGISTRY[trailName]) do
    interface.commitEntry(missions, index, entry, trailName)
  end
end

local function detourSwitchToMenu()
  core.detourCode(function(registers)
    log(2, string.format("detour: SetupSkirmishMode: %s", ""))
    local trail, trailName, mission = fetchCurrentTrail()
    if trail ~= nil then
      local missions = REGISTRY[trailName]
      if missions == nil then
        log(2, string.format("No custom missions registered for trail name: %s", trailName))
        return registers
      end

      local entry = missions[mission]
      if entry == nil then log(-1, string.format("skirmish trail (%s) entry is unexpectedly nil: %s", trailName, mission)) end
      
      interface.commitTextDescription(entry)
      
    else
      log(2, "detourSwitchMenu: no text description to set")
    end
  end, core.AOBScan("C7 ? ? ? ? ? ? ? ? ? ? E8 ? ? ? ? 5D C3"), 11)
end

return {
  enable = function(self, config)
    local _, skirmishTrailMissions, extremeTrailMissions, warchestTrailMissions = utils.AOBExtract("8D ? I(? ? ? ?) 75 08 8D ? I(? ? ? ?) EB 0B 83 F9 01 75 06 8D ? I(? ? ? ?) 53")

    hooks.registerHookCallback("afterInit", function()
      local extremePath = config.extremetrail.csv.path
      if extremePath and extremePath ~= "" then
        applyTrail("extremeTrail", extremePath, extremeTrailMissions, 20)
      end

      local firsteditionPath = config.firstedition.csv.path
      if firsteditionPath and firsteditionPath ~= "" then
        applyTrail("firstEditionTrail", firsteditionPath, skirmishTrailMissions, 50)
      end

      local warchestPath = config.warchest.csv.path
      if warchestPath and warchestPath ~= "" then
        applyTrail("warchestTrail", warchestPath, warchestTrailMissions, 30) -- todo: check
      end

      self.REGISTRY = REGISTRY -- debug line
    end)

    insertPostSkirmishSetupDetour()


    -- detour to get the map text displayed right...
    core.detourCode(function(registers)
      if core.readInteger(memory.IS_SKIRMISH_TRAIL) ~= 1 then
        return registers
      end

      if core.readInteger(memory.CURRENT_TRAIL_TYPE) ~= 2 then
        return registers
      end

      local mission = core.readInteger(memory.EXTREME_TRAIL_PROGRESS) + 1
      local entry = REGISTRY.extremeTrail[mission]
      -- todo
    end, core.AOBScan("83 C2 51 52", 9))
    
    log(2, "enable description hijack")
    description.enable()
    tradeability.enable()
    
    detourSwitchToMenu()
  end,
  disable = function(self, config) end,
  setTrailProgress = function(self, trail, progress)
    local progressAddr = TRAIL_PROGRESS_ADDRESSES[trail]

    if progressAddr == nil then
      error(string.format("no such trail: %s", trail))
    end
    
    core.writeInteger(progressAddr, progress)
  end,
  setText = function(self, line, text)
    description.setText(line, text)
  end,
  setTradeable = function(self, resource, tradeable)
    tradeability.setTradeable(resource, tradeable)
  end,
},
{
  public = {
    "setTrailProgress",
    "setText",
    "setTradeable",
  }
}