local memory = require('customskirmishtrails.memory')
local startgold = {

}

local pCurrentTrail = core.allocate(4, true)
local pCurrentMission = core.allocate(4, true)
-- 0 = human, 1 = ai
local pStartGoldValues = core.allocate(4 * 2, true)

local t = function()
  return [[
    push ecx
    mov EAX, dword [pType]
    mov ecx, dword [pCurrentTrail]
    cmp eax, ecx
    jne original
    
  firstTrail:
    cmp eax, 0
    jne warchestTrail
    mov eax, dword [pFirstProgress]
    mov ecx, dword [pCurrentMission]
    cmp eax, ecx
    jne original
    jmp modification
  warchestTrail:
    cmp eax, 1
    jne extremeTrail
    mov eax, dword [pWarchestProgress]
    mov ecx, dword [pCurrentMission]
    cmp eax, ecx
    jne original
    jmp modification
  extremeTrail:
    cmp eax, 2
    jne original
    mov eax, dword [pExtremeProgress]
    mov ecx, dword [pCurrentMission]
    cmp eax, ecx
    jne original
  modification:
    mov EAX, dword [pStartGoldValues]; use + 4 for ai
    jmp skip_original
  original:
    mov EAX, dword [EDX*8 + pData]
  skip_original:
    pop ecx
]]
end

function startgold.enable()
  -- AOB for: 0x00456063
  local detourAddress, detourSize = core.AOBScan("89 86 00 E4 FF FF"), 6
  log(VERBOSE, string.format('startgold: enabling hook @ 0x%X', detourAddress))
  -- pointer start gold = ESI - 7618
  -- playerID = EBX
  core.detourCode(function (registers)
    log(VERBOSE, string.format("startgold: ..."))
    local trail, trailName, mission = memory.fetchCurrentTrail()
    if trail ~= nil then
      local missions = memory.REGISTRY[trailName]
      if missions == nil then
        log(VERBOSE, string.format("No custom missions registered for trail name: %s", trailName))
        return registers
      end

      local entry = missions[mission]
      if entry == nil then log(-1, string.format("skirmish trail (%s) entry is unexpectedly nil: %s", trailName, mission)) end
      
      local playerID = registers.EBX

      local value = tonumber(entry[string.format("gold_player_%i", playerID)]) or nil
      if value == nil then
        log(VERBOSE, string.format("no gold value specified for player: %i", playerID))
        return registers
      end
      
      log(VERBOSE, string.format("gold value set for player '%i' to: %i", playerID, value))
      registers.EAX = value
    end

    return registers
  end, detourAddress, detourSize)
  
  -- humans
  local pRenderHook1, pData1 = utils.AOBExtract("8B ? ? I(? ? ? ?) 0F AF C6 50 B9 ? ? ? ? E8 ? ? ? ? 8B ? ? ? ? ? 8B ? ? ? ? ? A1 ? ? ? ?")
  core.insertCode(pRenderHook1, 7, {
    core.AssemblyLambda(t(), {
      pData = pData1,
      pType = memory.CURRENT_TRAIL_TYPE,
      pFirstProgress = memory.FIRST_EDITION_TRAIL_PROGRESS,
      pWarchestProgress = memory.WARCHEST_TRAIL_PROGRESS,
      pExtremeProgress = memory.EXTREME_TRAIL_PROGRESS,
      pCurrentTrail = pCurrentTrail,
      pCurrentMission = pCurrentMission,
      pStartGoldValues = pStartGoldValues,
    })
  }, nil, 'before')

  -- ai
  local pRenderHook2, pData2 = utils.AOBExtract("8B ? ? I(? ? ? ?) 0F AF C6 50 B9 ? ? ? ? E8 ? ? ? ? 8B ? ? ? ? ? 8B ? ? ? ? ? 83 C1 5C")
  core.insertCode(pRenderHook2, 7, {
    core.AssemblyLambda(t(), {
      pData = pData2,
      pType = memory.CURRENT_TRAIL_TYPE,
      pFirstProgress = memory.FIRST_EDITION_TRAIL_PROGRESS,
      pWarchestProgress = memory.WARCHEST_TRAIL_PROGRESS,
      pExtremeProgress = memory.EXTREME_TRAIL_PROGRESS,
      pCurrentTrail = pCurrentTrail,
      pCurrentMission = pCurrentMission,
      pStartGoldValues = pStartGoldValues + 4, -- for ai
    })
  }, nil, 'before')

  core.writeCode(core.AOBScan("8D 77 01 8B ? ? ? ? ? A1 ? ? ? ?"), {0x90, 0x90, 0x90, })

  log(VERBOSE, 'startgold: enabling done!')
end

function startgold.setStartGoldDisplay(entry)
  local trail, trailName, mission = memory.fetchCurrentTrail()

  core.writeInteger(pCurrentTrail, trail)
  core.writeInteger(pCurrentMission, mission - 1)

  local highest = 0
  for playerID=2,8 do
    local value = tonumber(entry[string.format("gold_player_%i", playerID)]) or 0
    if value > highest then highest = value end
  end
  local player = tonumber(entry["gold_player_1"]) or 0
  log(VERBOSE, string.format("setStartGoldDisplay: %s %s", player, highest))
  core.writeInteger(pStartGoldValues + (4 * 0), player)
  core.writeInteger(pStartGoldValues + (4 * 1), highest)
end

return startgold