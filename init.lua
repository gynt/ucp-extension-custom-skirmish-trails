
local memory = require("customskirmishtrails.memory")
local interface = require("customskirmishtrails.interface")
local input = require("customskirmishtrails.input")

local TRAIL_TYPES = {
  [0] = "firstEditionTrail",
  [1] = "warchestTrail",
  [2] = "extremeTrail",
}

local REGISTRY = {
  ["extremeTrail"] = nil,
}


local function removeExtremeMultiplier()
  local visualAddr= core.AOBScan("8D 77 01 8B ? ? ? ? ? A1 ? ? ? ?")
  -- core.writeCode(visualAddr, {0x90, 0x90, 0x90, })
end

local function insertPostSkirmishSetupDetour()
  log(2, "insertPostSkirmishSetupDetour: setting up detour")
  local detourLocation, detourSize = core.AOBScan("A1 ? ? ? ? 8D 0C 80 03 C9 89 ? ? ? ? ?"), 5
  core.detourCode(function(registers)
    if core.readInteger(memory.IS_SKIRMISH_TRAIL) ~= 1 then
      log(2, "not in skirmish trail")
      return registers
    end

    if core.readInteger(memory.CURRENT_TRAIL_TYPE) ~= 2 then
      log(2, "not in trail 2")
      return registers
    end

    local mission = core.readInteger(memory.EXTREME_TRAIL_PROGRESS) + 1

    log(2, string.format("Committing extra parameters for extreme trail mission: %s", mission))
    interface.commitEntryExtra(REGISTRY["extremeTrail"][mission])

    return registers

  end, detourLocation, detourSize)
end


return {
  enable = function(self, config)
    local _, skirmishTrailMissions, extremeTrailMissions, warchestTrailMissions = utils.AOBExtract("8D ? I(? ? ? ?) 75 08 8D ? I(? ? ? ?) EB 0B 83 F9 01 75 06 8D ? I(? ? ? ?) 53")

    hooks.registerHookCallback("afterInit", function()
      local extremePath = config.extreme.csv.path
      if extremePath and extremePath ~= "" then
        local result, err = input.readCSV(extremePath, 20)
        if result == nil then error(err) end
        local f = io.open("ucp/.cache/custom-skirmish-trails-config.yml", 'w')
        f:write(yaml.dump(result))
        f:close()
        REGISTRY["extremeTrail"] = result
        self.REGISTRY = REGISTRY -- debug line

        for index, entry in pairs(REGISTRY["extremeTrail"]) do
          interface.commitEntry(extremeTrailMissions, index, entry)
        end
      end

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
    
  end,
  disable = function(self, config) end,
  setTrailProgress = function(self, trail, progress)
    if trail == 'extremeTrail' then
      local _, progressAddr = utils.AOBExtract("A1 I(? ? ? ?) 83 F8 14 0F ? ? ? ? ?")
      core.writeInteger(progressAddr, progress)

      return
    end
    error(string.format("not implemented for trail: %s", trail))
  end,
},
{
  public = {
    "setTrailProgress",
  }
}