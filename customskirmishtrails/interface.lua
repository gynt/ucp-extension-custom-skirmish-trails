
local common = require("customskirmishtrails.common")
local tradeability = require("customskirmishtrails.tradeability")
local producibility = require("customskirmishtrails.producibility")
local recruitability = require("customskirmishtrails.recruitability")
local descriptiveTexts = require("customskirmishtrails.descriptive_texts")
local startgoods = require("customskirmishtrails.start_goods")
local patches = require("customskirmishtrails.patches")

local PLAYER_MAPPING = {
  ["SK_RAT"] = 1,
  ["SK_SNAKE"] = 2,
  ["SK_PIG"] = 3,
  ["SK_WOLF"] = 4,
  ["SK_SALADIN"] = 5,
  ["SK_CALIPH"] = 6,
  ["SK_SULTAN"] = 7,
  ["SK_RICHARD"] = 8,
  ["SK_FREDERICK"] = 9,
  ["SK_PHILLIP"] = 10,
  ["SK_WAZIR"] = 11,
  ["SK_EMIR"] = 12,
  ["SK_NIZAR"] = 13,
  ["SK_SHERIFF"] = 14,
  ["SK_MARSHAL"] = 15,
  ["SK_ABBOT"] = 16,
}

local STRING_ADDRESSES = {

}

-- per trail: alias -> AI key, from the trail settings file's ai_character_mapping
local AI_ALIASES = {}

local function setAiAliases(trail, mapping)
  local aliases = {}
  for key, alias in pairs(mapping or {}) do
    aliases[alias] = key
  end
  AI_ALIASES[trail] = aliases
end

---The game's AI id for a player cell: an AI key ("SK_RAT"), an alias from the trail settings
---file's ai_character_mapping, or a number (0 for an empty slot).
local function playerValue(value, trail)
  if PLAYER_MAPPING[value] ~= nil then
    return PLAYER_MAPPING[value]
  end
  local aliases = AI_ALIASES[trail]
  if aliases ~= nil and aliases[value] ~= nil and PLAYER_MAPPING[aliases[value]] ~= nil then
    return PLAYER_MAPPING[aliases[value]]
  end
  return math.tointeger(tonumber(value)) or 0
end

local ENTRY_OFFSETS = {
  ["map_name"] = 0*4,
  ["fairness"] = 1*4,
  ["start_levels"] = 2*4,
  ["num_players"] = 3*4,


  ["player1"] = 4*4,
  ["player2"] = 5*4,
  ["player3"] = 6*4,
  ["player4"] = 7*4,
  ["player5"] = 8*4,
  ["player6"] = 9*4,
  ["player7"] = 10*4,
  ["player8"] = 11*4,

  ["start_position1"] = 12*4,
  ["start_position2"] = 13*4,
  ["start_position3"] = 14*4,
  ["start_position4"] = 15*4,
  ["start_position5"] = 16*4,
  ["start_position6"] = 17*4,
  ["start_position7"] = 18*4,
  ["start_position8"] = 19*4,

  ["team1"] = 20*4,
  ["team2"] = 21*4,
  ["team3"] = 22*4,
  ["team4"] = 23*4,
  ["team5"] = 24*4,
  ["team6"] = 25*4,
  ["team7"] = 26*4,
  ["team8"] = 27*4,

  ["aiv_type1"] = 28*4,
  ["aiv_type2"] = 29*4,
  ["aiv_type3"] = 30*4,
  ["aiv_type4"] = 31*4,
  ["aiv_type5"] = 32*4,
  ["aiv_type6"] = 33*4,
  ["aiv_type7"] = 34*4,
  ["aiv_type8"] = 35*4,
}

local SLOT_COLUMNS = { "player%d", "start_position%d", "team%d", "aiv_type%d", "gold_player_%d", "player%d_name",
  "player%d_color" }
local EMPTY_SLOT = { "player%d", "start_position%d", "team%d", "aiv_type%d" }

local function hasAi(entry, player)
  local value = entry["player" .. player]
  return value ~= nil and value ~= "" and tonumber(value) ~= 0
end

---Moves each AI player with a player<N>_color into the slot of that colour. The other AI
---players keep their slot when it is free and take the first free one otherwise.
local function applyColors(entry, where)
  local players = math.min(math.tointeger(tonumber(entry.num_players)) or 8, 8)
  local slots, taken, any = {}, { [1] = true }, false
  for player = 2, players do
    local value = entry[string.format("player%d_color", player)]
    if hasAi(entry, player) and value ~= nil and value ~= "" then
      local slot = common.COLORS[tostring(value):lower()] or math.tointeger(tonumber(value))
      if slot == nil or slot < 2 or slot > 8 or taken[slot] then
        log(WARNING, string.format("%s: player%d_color %s is not a free AI colour",
          where, player, tostring(value)))
      else
        slots[player], taken[slot], any = slot, true, true
      end
    end
  end
  if not any then
    return
  end
  local last = players
  for player = 2, players do
    if slots[player] == nil and hasAi(entry, player) then
      local slot = player
      if taken[slot] then
        slot = 2
        while taken[slot] do
          slot = slot + 1
        end
      end
      slots[player], taken[slot] = slot, true
    end
    last = math.max(last, slots[player] or 0)
  end
  local moved = {}
  for player, slot in pairs(slots) do
    for _, column in ipairs(SLOT_COLUMNS) do
      moved[column:format(slot)] = entry[column:format(player)]
    end
  end
  for slot = 2, 8 do
    for _, column in ipairs(SLOT_COLUMNS) do
      entry[column:format(slot)] = moved[column:format(slot)]
    end
    if not taken[slot] then
      for _, column in ipairs(EMPTY_SLOT) do
        entry[column:format(slot)] = 0
      end
    end
  end
  entry.num_players = last
end

local function commitEntry(addr, index, entry, trail)
  local offset = addr + 144 * (index - 1)

  local missionName = entry.mission_name
  if missionName ~= nil and modules.textResourceModifier.SetText ~= nil then
    if trail == "firstEditionTrail" then
      -- first edition
      modules.textResourceModifier:SetText(0xF5, 0x01 + (index - 1), missionName)      
    elseif trail == "warchestTrail" then
      -- warchest
      modules.textResourceModifier:SetText(0xF5, 0x33 + (index - 1), missionName)
    elseif trail == "extremeTrail" then
      -- extreme
      modules.textResourceModifier:SetText(0xF5, 0x51 + (index - 1), missionName)  
    else 
      error(string.format("unknown trail: %s", trail))
    end  
  end
  
  local mapName = entry.map_name --#:gsub("_", " ")
  if mapName ~= nil and STRING_ADDRESSES[mapName] == nil then
    local mapNameAddress = core.allocate(mapName:len() + 1, true)
    core.writeString(mapNameAddress, mapName)
    STRING_ADDRESSES[mapName] = mapNameAddress

  end

  local mapNameAddress = STRING_ADDRESSES[mapName]
  for name, value in pairs(entry) do
    
    if name == "map_name" then
      value = mapNameAddress
      -- core.writeInteger(offset + ENTRY_OFFSETS["map_name"], value)
    end

    if value ~= nil then
      local fieldOffset = ENTRY_OFFSETS[name]
      if fieldOffset ~= nil then
        if name:sub(1, ("player"):len()) == "player" then
          value = playerValue(value, trail)
        end
        core.writeInteger(offset + fieldOffset, value)
      end
    else
      -- set the default value??
    end
  end
end

local function commitEntryExtra(entry)
  -- no json:encode(entry) here: UCP's JSON encoder crashed the game in ucrtbase

  -- set somewhere else!
  -- startgoods.setStartGoods(entry)

  producibility.setWeaponsProducible(entry)
  
  recruitability.setUnitsRecruitable(entry)

  tradeability.setTradeables(entry)

  patches.applyPlayerNames(entry)
  patches.applyLord(entry)
  startgoods.skipStartUnits(entry)
end

local function commitTextDescription(entry)
  descriptiveTexts.setTextDescriptions(entry)
end

return {
  commitEntry = commitEntry,
  commitEntryExtra = commitEntryExtra,
  commitTextDescription = commitTextDescription,
  applyColors = applyColors,
  hasAi = hasAi,
  setStartGoods = startgoods.setStartGoods,
  setAiAliases = setAiAliases,
  STRING_ADDRESSES = STRING_ADDRESSES,
}