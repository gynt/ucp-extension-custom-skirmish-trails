local _, startGoldOffsetAddr = utils.AOBExtract("8B ? ? I(? ? ? ?) 8B C8 6B C9 64")
local _, startGoldAddr = utils.AOBExtract("89 ? I(? ? ? ?) A3 ? ? ? ? A3 ? ? ? ? A3 ? ? ? ? A3 ? ? ? ? A3 ? ? ? ? A3 ? ? ? ? A3 ? ? ? ? A3 ? ? ? ? A3 ? ? ? ? A3 ? ? ? ? A3 ? ? ? ? A3 ? ? ? ? A3 ? ? ? ? A3 ? ? ? ? 89 44 24 10")
local _, startGoodsAddr = utils.AOBExtract("BF I(? ? ? ?) F3 A5 89 ? ? ? ? ? ")
local _, startingTroopsAddr = utils.AOBExtract("BE I(? ? ? ?) C7 ? ? ? ? ? ? ? 8B 44 24 10")
local _, euroRecruitableAddr, mercRecruitableAddr = utils.AOBExtract("A3 I(? ? ? ?) A3 I(? ? ? ?) A3 ? ? ? ? A3 ? ? ? ? A3 ? ? ? ? A3 ? ? ? ? A3 ? ? ? ? A3 ? ? ? ? A3 ? ? ? ? A3 ? ? ? ? A3 ? ? ? ? A3 ? ? ? ? A3 ? ? ? ? A3 ? ? ? ? 89 44 24 10")

-- ints: xbow, pike, sword, bow, spear, mace    0x01fe7e70
local _, weaponProducibleAddr = utils.AOBExtract("89 ? I(? ? ? ?) 89 ? ? ? ? ? 89 ? ? ? ? ? 89 ? ? ? ? ? 89 ? ? ? ? ? 89 ? ? ? ? ? 66 ? ? ? ? ? ? 66 ? ? ? ? ? ? 89 ? ? ? ? ?")
log(2, string.format("memory: WEAPON_PRODUCIBLE: %X", weaponProducibleAddr))
-- shorts: xbow, bow, pike, spear, sword, mace  0x01653df6
local _, weaponProducibleSaveAddr = utils.AOBExtract("0F ? ? I(? ? ? ?) 0F ? ? ? ? ? ? 0F ? ? ? ? ? ? 0F ? ? ? ? ? ? 89 ? ? ? ? ? 0F ? ? ? ? ? ? 89 ? ? ? ? ? 0F ? ? ? ? ? ? 89 ? ? ? ? ? 0F ? ? ? ? ? ? 89 ? ? ? ? ? 0F ? ? ? ? ? ? 89 ? ? ? ? ? 0F ? ? ? ? ? ? 89 ? ? ? ? ? 0F ? ? ? ? ? ? 89 ? ? ? ? ?")
log(2, string.format("memory: WEAPON_SAVE_PRODUCIBLE: %X", weaponProducibleSaveAddr))

local _, isSkirmishTrailAddr = utils.AOBExtract("C7 ? I(? ? ? ?) ? ? ? ? 56 75 23")
local _, currentTrailTypeAddr = utils.AOBExtract("A1 I(? ? ? ?) 83 C6 70")

local _, extremeTrailProgressAddr = utils.AOBExtract("89 ? I(? ? ? ?) E8 ? ? ? ? A1 ? ? ? ? 8B ? ? ? ? ? ? 89 ? ? ? ? ?")
local _, warchestTrailProgressAddr = utils.AOBExtract("89 ? I(? ? ? ?) E8 ? ? ? ? 8B ? ? ? ? ? 8B ? ? ? ? ? ? 89 ? ? ? ? ?")
local _, firstEditionTrailProgressAddr = utils.AOBExtract("8B ? I(? ? ? ?) 8B ? ? ? ? ? ? 89 ? ? ? ? ? 8B C1")

return {
  STARTING_TROOPS = startingTroopsAddr,
  EURO_RECRUITABLE = euroRecruitableAddr,
  MERC_RECRUITABLE = mercRecruitableAddr,
  START_GOODS = startGoodsAddr,
  START_GOLD = startGoldAddr,
  WEAPON_PRODUCIBLE = weaponProducibleAddr,
  IS_SKIRMISH_TRAIL = isSkirmishTrailAddr,
  CURRENT_TRAIL_TYPE = currentTrailTypeAddr,
  EXTREME_TRAIL_PROGRESS = extremeTrailProgressAddr,
  WARCHEST_TRAIL_PROGRESS = warchestTrailProgressAddr,
  FIRST_EDITION_TRAIL_PROGRESS = firstEditionTrailProgressAddr,
}