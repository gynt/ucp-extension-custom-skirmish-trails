
local memory = require("customskirmishtrails.memory")
local description = require("customskirmishtrails.description")

local WEAPON_PRODUCIBLE_OFFSETS = {
  address = memory.WEAPON_PRODUCIBLE,
  offsets = {
    ["producible_crossbows"] = 0,
    ["producible_pikes"] = 4,
    ["producible_swords"] = 8,
    ["producible_bows"] = 12,
    ["producible_spears"] = 14,
    ["producible_maces"] = 16,
  },
  writeFunction = core.writeInteger,
}

local function setWeaponProducible(weapon, value)
  local f = WEAPON_PRODUCIBLE_OFFSETS.writeFunction
  local address = WEAPON_PRODUCIBLE_OFFSETS.address
  local offsets = WEAPON_PRODUCIBLE_OFFSETS.offsets
  local addr = address + offsets[weapon]
  log(2, string.format("setWeaponProducible: %s @ %X: %s", weapon,addr, value))
  f(addr, value)
end

-- 
local function setStartGold(value)
  log(2, string.format("setStartGold: %s @ %X: %s", "gold",memory.START_GOLD, value))
  core.writeInteger(memory.START_GOLD, value) -- check intesnity value validity
end

local RESOURCE_TYPES = {
	["resource_wood"] =         2,
	["resource_hops"] =         3,
	["resource_stone"] =        4,
	["resource_partialstone"] = 5,
	["resource_iron"] =         6,
	["resource_pitch"] =        7,
	["resource_partialpitch"] = 8,
	["resource_wheat"] =        9,
	["resource_bread"] =        10,
	["resource_cheese"] =       11,
	["resource_meat"] =         12,
	["resource_apple"] =        13,
	["resource_ale"] =          14,
	["resource_gold"] =         15,
  ["resource_flour"] =        16,
	["resource_bow"] =          17,
	["resource_crossbow"] =     18,
	["resource_spear"] =        19,
	["resource_pike"] =         20,
	["resource_mace"] =         21,
	["resource_sword"] =        22,
	["resource_leatherarmor"] = 23,
	["resource_ironarmor"] =    24,
}

local function setStartGood(good, value)
  local g = RESOURCE_TYPES[good]
  if g == nil then error(string.format("unknown good type: %s", good)) end

  local addr = memory.START_GOODS + (4*g)
  log(2, string.format("setStartGood: %s @ %X: %s", good,addr, value))
  core.writeInteger(addr, value)
end

local function setStartUnit(player, unit, count)

end

local EURO_RECRUITABLE_OFFSETS = {
  ["recruitable_archers"] = 0*4,
  ["recruitable_spearmen"] = 1*4,
  ["recruitable_macemen"] = 2*4,
  ["recruitable_crossbowmen"] = 3*4,
  ["recruitable_pikemen"] = 4*4,
  ["recruitable_swordsmen"] = 5*4,
  ["recruitable_knights"] = 6*4,
}

local MERC_RECRUITABLE_OFFSETS = {
  ["recruitable_arabian_bows"] = 0*4,
  ["recruitable_slaves"] = 1*4,
  ["recruitable_slingers"] = 2*4,
  ["recruitable_assassins"] = 3*4,
  ["recruitable_horse_archers"] = 4*4,
  ["recruitable_arabian_swordsmen"] = 5*4,
  ["recruitable_fire_throwers"] = 6*4,
}


local function setUnitRecruitable(unit, value)
  local euroOffset = EURO_RECRUITABLE_OFFSETS[unit]
  if euroOffset ~= nil then
    local addr = memory.EURO_RECRUITABLE + euroOffset
    log(2, string.format("setUnitRecruitable: setting %s at %X to %s", unit,  addr, value))
    core.writeInteger(addr, value)
    return
  end

  local mercOffset = MERC_RECRUITABLE_OFFSETS[unit]
  if mercOffset ~= nil then
    local addr = memory.MERC_RECRUITABLE + mercOffset
    log(2, string.format("setUnitRecruitable: setting %s at %X to %s", unit,  addr, value))
    core.writeInteger(addr, value)
    return
  end

  error( string.format("unknown unit: %s", unit))
end

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

local function commitEntry(addr, index, entry, trail)
  local offset = addr + 144 * (index - 1)
  log(2, string.format("commitEntry: %s %X %s %X", entry, addr, index - 1, offset))

  local missionName = entry.mission_name
  if missionName ~=  nil then
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

    log(2, string.format("commitEntry: map name: %s", mapName))
  end

  local mapNameAddress = STRING_ADDRESSES[mapName]
  for name, value in pairs(entry) do
    
    if name == "map_name" then
      -- log(2, string.format("commitEntry: writing map name: %X", mapNameAddress))
      value = mapNameAddress
      -- core.writeInteger(offset + ENTRY_OFFSETS["map_name"], value)
    end

    if value ~= nil then
      local fieldOffset = ENTRY_OFFSETS[name]
      if fieldOffset ~= nil then
        if name:sub(1, ("player"):len()) == "player" then
          value = PLAYER_MAPPING[value]
        end
        log(2, string.format("commitEntry: %s @ %X: %s", name,offset + fieldOffset, value))
        core.writeInteger(offset + fieldOffset, value)
      end
    else
      -- set the default value??
    end
  end
end

local function commitEntryExtra(entry)
  log(2, string.format("commitEntryExtra: %s", entry))

  for name, offset in pairs(RESOURCE_TYPES) do
    if entry[name] ~= nil then
      setStartGood(name, entry[name])
    end
  end

  for name, offset in pairs(WEAPON_PRODUCIBLE_OFFSETS.offsets) do
    if entry[name] ~= nil then
      setWeaponProducible(name, entry[name])
    else
      log(2, string.format("commitEntryExtra: no weapon producible set: %s", name))
    end
  end

  if entry.gold ~= nil then
    setStartGold(entry.gold)
  end
  
  for name, offset in pairs(EURO_RECRUITABLE_OFFSETS) do
    setUnitRecruitable(name, entry[name])
  end

  for name, offset in pairs(MERC_RECRUITABLE_OFFSETS) do
    setUnitRecruitable(name, entry[name])
  end
end

local function commitTextDescription(entry)
  log(2, string.format("commitTextDescription: %s => %s", entry, entry.text_description_line_01))
  description.setText(1, entry.text_description_line_01 or "")
  description.setText(2, entry.text_description_line_02 or "")
  description.setText(3, entry.text_description_line_03 or "")
  description.setText(4, entry.text_description_line_04 or "")
  description.setText(5, entry.text_description_line_05 or "")
  description.setText(6, entry.text_description_line_06 or "")
  description.setText(7, entry.text_description_line_07 or "")
  description.setText(8, entry.text_description_line_08 or "")
end


return {
  commitEntry = commitEntry,
  commitEntryExtra = commitEntryExtra,
  commitTextDescription = commitTextDescription,
  STRING_ADDRESSES = STRING_ADDRESSES,
}