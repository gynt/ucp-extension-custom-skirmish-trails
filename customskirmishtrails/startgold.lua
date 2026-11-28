-- Start gold per player: the game's own start gold (its skirmish value for the mission's
-- advantage and start mode), or the mission's gold_player_1 .. gold_player_8 where it has one.
-- The trail briefing shows the same: the human player's gold and, when the mission gives an AI
-- player its own gold, one value per AI player, or the lowest and highest where those don't fit.
-- A scenario mission starts with its map's gold (docs/trail-files.md): gold_player_1 ..
-- gold_player_8 don't apply, and its briefing shows no gold.

local memory = require('customskirmishtrails.memory')
local patches = require('customskirmishtrails.patches')
local interface = require('customskirmishtrails.interface')
local menutext = require('customskirmishtrails.menutext')
local scenario = require('customskirmishtrails.scenario')

local startgold = {}

-- The briefing's gold lines: each reads the game's gold table and applies the trail's factor
-- ("mov eax, [edx*8 + table]", "imul eax, esi"), then draws it ("push eax", "mov ecx, text",
-- "call number"). The AI line's label just before is drawn by the game's text routine
-- ("call text").
local LINE_BYTES = "8B 04 D5 ? ? ? ? 0F AF C6 50 B9 ? ? ? ? E8 ? ? ? ?"
local HUMAN_SITE = { fn = "brief", offset = 0x3B2, bytes = LINE_BYTES }
local AI_SITE = { fn = "brief", offset = 0x3FC, bytes = LINE_BYTES }
local AI_LABEL_CALL_SITE = { fn = "brief", offset = 0x368, bytes = "E8 ? ? ? ?" }
local GAME_VALUE_SIZE = 10
local LINE_SIZE = 21
local AI_TEXT_SIZE = 128
-- The AI line's coin is drawn 0x46 px right of its number. The text routine right-aligns a text
-- at x when its fourth argument is negative, so the AI players' gold text ends 8 px before the coin.
local AI_TEXT_RIGHT = 0x3E
-- The AI line's label (game text 0xF2, 8) starts 0xF8 px left of its number; both use font 0x11.
local AI_LABEL_TEXT = { 0xF2, 8 }
local AI_LABEL_LEFT = -0xF8
local AI_FONT = 0x11
local AI_TEXT_GAP = 8

---The mission's own start gold for a player slot (1 is the human player), or nil.
local function gold(entry, player)
  return entry ~= nil and math.tointeger(tonumber(entry[string.format("gold_player_%d", player)])) or nil
end

---The AI players' gold in player order, or nil when the mission gives no AI player its own gold.
local function aiGold(entry, gameValue)
  if entry == nil then
    return nil
  end
  local players = math.min(math.tointeger(tonumber(entry.num_players)) or 8, 8)
  local values, own = {}, false
  for player = 2, players do
    if interface.hasAi(entry, player) then
      local value = gold(entry, player)
      own = own or value ~= nil
      table.insert(values, value or gameValue)
    end
  end
  return own and values or nil
end

---The AI players' gold as the briefing shows it: every value ("4000 / 3000 / 4000") when that
---fits between the label and the coin, else the lowest and highest ("3000 - 4000").
local function aiGoldText(textObject, values)
  local text = table.concat(values, " / ")
  local modifier = modules.textResourceModifier
  local labelText = modifier.GetText ~= nil and modifier:GetText(AI_LABEL_TEXT[1], AI_LABEL_TEXT[2])
  local label = labelText and menutext.measure(textObject, labelText, AI_FONT)
  local width = menutext.measure(textObject, text, AI_FONT)
  if not label or width == nil or AI_LABEL_LEFT + label + AI_TEXT_GAP + width <= AI_TEXT_RIGHT then
    return text
  end
  local low, high = math.min(table.unpack(values)), math.max(table.unpack(values))
  return low == high and tostring(low) or string.format("%d - %d", low, high)
end

---The code that replaces the gold line at `address`: `stub` gets the game's value in EAX and sets
---EAX to the number to draw and EDX to a text to draw instead, or 0.
local function lineCode(address, stub, drawText)
  local gameValue = {}
  for index, byte in ipairs(core.readBytes(address, GAME_VALUE_SIZE)) do
    gameValue[index] = byte & 0xFF
  end
  local textObject = core.readInteger(address + 12)
  local drawNumber = address + LINE_SIZE + core.readInteger(address + 17)
  return { gameValue, core.AssemblyLambda([[
    call near ON_GOLD
    push eax
    test edx, edx
    jz number
    mov [esp], edx
    add dword [esp + 4], TEXT_RIGHT
    mov dword [esp + 0x0C], -1
    mov ecx, TEXT_OBJECT
    call near DRAW_TEXT
    jmp done
  number:
    mov ecx, TEXT_OBJECT
    call near DRAW_NUMBER
  done:
  ]], { ON_GOLD = stub, TEXT_RIGHT = AI_TEXT_RIGHT, TEXT_OBJECT = textObject,
    DRAW_TEXT = drawText, DRAW_NUMBER = drawNumber }) }
end

---`ownGold`: whether the mission's gold_player_N reach the game, so the briefing shows them.
local function showInBriefing(ownGold)
  local human = patches.siteAddress(HUMAN_SITE, "the human player's gold in the briefing")
  local ai = patches.siteAddress(AI_SITE, "the AI players' gold in the briefing")
  local label = patches.siteAddress(AI_LABEL_CALL_SITE, "the AI players' gold in the briefing")
  if human == nil or ai == nil or label == nil or (ownGold and not menutext.bindMeasure()) then
    return false
  end
  local textObject = core.readInteger(ai + 12)
  local drawText = label + 5 + core.readInteger(label + 1)
  local aiText = core.allocate(AI_TEXT_SIZE, true)
  local noText = core.allocate(1, true)
  assert(aiText ~= nil and aiText ~= 0 and noText ~= nil and noText ~= 0, "out of memory")
  local shownValues = nil

  local humanStub = patches.luaStub(function(registers)
    local entry = memory.currentEntry()
    local value = ownGold and gold(entry, 1) or nil
    if value ~= nil then
      registers.EAX = value
    end
    registers.EDX = scenario.isScenario(entry) and noText or 0
    return registers
  end)
  local aiStub = patches.luaStub(function(registers)
    local entry = memory.currentEntry()
    if scenario.isScenario(entry) then
      registers.EDX = noText
      return registers
    end
    local values = ownGold and aiGold(entry, registers.EAX) or nil
    local key = values and table.concat(values, " / ")
    if key ~= nil and key ~= shownValues then
      core.writeString(aiText, aiGoldText(textObject, values):sub(1, AI_TEXT_SIZE - 1) .. "\0")
      shownValues = key
    end
    registers.EDX = values ~= nil and aiText or 0
    return registers
  end)

  patches.guarded({ { address = human, size = LINE_SIZE }, { address = ai, size = LINE_SIZE } }, function()
    core.insertCode(human, LINE_SIZE, lineCode(human, humanStub, drawText))
    core.insertCode(ai, LINE_SIZE, lineCode(ai, aiStub, drawText))
  end)
end

function startgold.enable(customGold, scenarios)
  -- every player's start gold as the game sets up a skirmish (EBX: the player's slot)
  local ownGold = customGold and patches.apply("Custom start gold in trail missions", function()
    local detourAddress = patches.find("89 86 00 E4 FF FF")
    if detourAddress == nil then return false end
    core.detourCode(function(registers)
      local entry, isTrail = memory.currentEntry()
      local value = isTrail and not scenario.isScenario(entry) and gold(entry, registers.EBX) or nil
      if value ~= nil then
        registers.EAX = value
      end
      return registers
    end, detourAddress, 6)
  end)
  if ownGold or scenarios then patches.apply("Custom gold in trail briefings", showInBriefing, ownGold) end
end

return startgold
