
local memory = require("customskirmishtrails.memory")

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
  f(address + offsets[weapon], value)
end

-- 
local function setStartGold(value)
  core.writeInteger(memory.START_GOLD, value) -- check intesnity value validity
end

local RESOURCE_TYPES = {
	["resource_wood"] = 1,
	["resource_hops"] = 2,
	["resource_stone"] = 3,
	["resource_partialstone"] = 4,
	["resource_iron"] = 5,
	["resource_pitch"] = 6,
	["resource_partialpitch"] = 7,
	["resource_wheat"] = 8,
	["resource_bread"] = 9,
	["resource_cheese"] = 10,
	["resource_meat"] = 11,
	["resource_apple"] = 12,
	["resource_ale"] = 13,
	["resource_gold"] = 14,
	["resource_flour"] = 15,
	["resource_bow"] = 16,
	["resource_crossbow"] = 17,
	["resource_spear"] = 18,
	["resource_pike"] = 19,
	["resource_mace"] = 20,
	["resource_sword"] = 21,
	["resource_leatherarmor"] = 22,
	["resource_ironarmor"] = 23,
}

local function setStartGood(good, value)
  local g = RESOURCE_TYPES[good]
  if g == nil then error(string.format("unknown good type: %s", good)) end
  core.writeInteger(memory.START_GOODS + g, value)
end

local function setStartUnit(player, unit, count)

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


local function commitEntry(addr, index, entry)
  local offset = addr + 144 * (index - 1)
  log(2, string.format("commitEntry: %s %X %s %X", entry, addr, index - 1, offset))
  
  local mapName = entry.map_name --#:gsub("_", " ")
  if STRING_ADDRESSES[mapName] == nil then
    local mapNameAddress = core.allocate(mapName:len() + 1, true)
    core.writeString(mapNameAddress, mapName)
    STRING_ADDRESSES[mapName] = mapNameAddress
  end

  local mapNameAddress = STRING_ADDRESSES[mapName]
  log(2, string.format("commitEntry: map name address: %X", mapNameAddress))
  log(2, string.format("commitEntry: map name: %s", mapName))
  core.writeInteger(offset +  (4* 0), mapNameAddress)
  log(2, string.format("commitEntry: fairness: %s", entry.fairness))
  core.writeInteger(offset +  (4* 1), entry.fairness)
  log(2, string.format("commitEntry: start_levels: %s", entry.start_levels))
  core.writeInteger(offset +  (4* 2), entry.start_levels)
  log(2, string.format("commitEntry: num_players: %s %s", entry.num_players, type(entry.num_players)))
  core.writeInteger(offset +  (4* 3), entry.num_players)
  core.writeInteger(offset +  (4* 4), PLAYER_MAPPING[entry.player1])
  core.writeInteger(offset +  (4* 5), PLAYER_MAPPING[entry.player2])
  core.writeInteger(offset +  (4* 6), PLAYER_MAPPING[entry.player3])
  core.writeInteger(offset +  (4* 7), PLAYER_MAPPING[entry.player4])
  core.writeInteger(offset +  (4* 8), PLAYER_MAPPING[entry.player5])
  core.writeInteger(offset +  (4* 9), PLAYER_MAPPING[entry.player6])
  core.writeInteger(offset +  (4*10), PLAYER_MAPPING[entry.player7])
  core.writeInteger(offset +  (4*11), PLAYER_MAPPING[entry.player8])
  core.writeInteger(offset +  (4*12), entry.start_position1)
  core.writeInteger(offset +  (4*13), entry.start_position2)
  core.writeInteger(offset +  (4*14), entry.start_position3)
  core.writeInteger(offset +  (4*15), entry.start_position4)
  core.writeInteger(offset +  (4*16), entry.start_position5)
  core.writeInteger(offset +  (4*17), entry.start_position6)
  core.writeInteger(offset +  (4*18), entry.start_position7)
  core.writeInteger(offset +  (4*19), entry.start_position8)
  core.writeInteger(offset +  (4*20), entry.team1)
  core.writeInteger(offset +  (4*21), entry.team2)
  core.writeInteger(offset +  (4*22), entry.team3)
  core.writeInteger(offset +  (4*23), entry.team4)
  core.writeInteger(offset +  (4*24), entry.team5)
  core.writeInteger(offset +  (4*25), entry.team6)
  core.writeInteger(offset +  (4*26), entry.team7)
  core.writeInteger(offset +  (4*27), entry.team8)
  core.writeInteger(offset +  (4*28), entry.aiv_type1)
  core.writeInteger(offset +  (4*29), entry.aiv_type2)
  core.writeInteger(offset +  (4*30), entry.aiv_type3)
  core.writeInteger(offset +  (4*31), entry.aiv_type4)
  core.writeInteger(offset +  (4*32), entry.aiv_type5)
  core.writeInteger(offset +  (4*33), entry.aiv_type6)
  core.writeInteger(offset +  (4*34), entry.aiv_type7)
  core.writeInteger(offset +  (4*35), entry.aiv_type8)
end

local function commitEntryExtra(entry)
  log(2, string.format("commitEntryExtra: %s", entry))

  for name, offset in pairs(RESOURCE_TYPES) do
    if entry[name] ~= nil then
      setStartGood(name, entry[name])
    end
  end

  for name, offset in pairs(WEAPON_PRODUCIBLE_OFFSETS) do
    if entry[name] ~= nil then
      setWeaponProducible(name, entry[name])
    end
  end

  if entry.gold ~= nil then
    setStartGold(entry.gold)
  end
  
end


return {
  commitEntry = commitEntry,
  commitEntryExtra = commitEntryExtra,
  STRING_ADDRESSES = STRING_ADDRESSES,
}