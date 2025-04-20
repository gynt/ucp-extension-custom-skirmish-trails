local memory = require("customskirmishtrails.memory")


local EURO_RECRUITABLE_OFFSETS = {
  ["archers"] = 0*4,
  ["crossbowmen"] = 1*4,
  ["spearmen"] = 2*4,
  ["pikemen"] = 3*4,
  ["macemen"] = 4*4,
  ["swordsmen"] = 5*4,
  ["knights"] = 6*4,
}

local MERC_RECRUITABLE_OFFSETS = {
  ["arabian_bows"] = 0*4,
  ["slaves"] = 1*4,
  ["slingers"] = 2*4,
  ["assassins"] = 3*4,
  ["horse_archers"] = 4*4,
  ["arabian_swordsmen"] = 5*4,
  ["fire_throwers"] = 6*4,
}

local function getUnitRecruitable(unit)
  local euroOffset = EURO_RECRUITABLE_OFFSETS[unit]
  if euroOffset ~= nil then
    local addr = memory.EURO_RECRUITABLE + euroOffset
    log(2, string.format("getUnitRecruitable: getting %s at %X", unit,  addr))
    return core.writeInteger(addr)
  end

  local mercOffset = MERC_RECRUITABLE_OFFSETS[unit]
  if mercOffset ~= nil then
    local addr = memory.MERC_RECRUITABLE + mercOffset
    log(2, string.format("getUnitRecruitable: getting %s at %X ", unit,  addr))
    return core.writeInteger(addr)
  end

  error( string.format("unknown unit: %s", unit))
end

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

local function setUnitsRecruitable(entry)
  for name, offset in pairs(EURO_RECRUITABLE_OFFSETS) do
    setUnitRecruitable(name, entry["recruitable_" .. name])
  end

  for name, offset in pairs(MERC_RECRUITABLE_OFFSETS) do
    setUnitRecruitable(name, entry["recruitable_" .. name])
  end
end

return {
  setUnitRecruitable = setUnitRecruitable,
  getUnitRecruitable = getUnitRecruitable,
  setUnitsRecruitable = setUnitsRecruitable,
  EURO_RECRUITABLE_OFFSETS = EURO_RECRUITABLE_OFFSETS,
  MERC_RECRUITABLE_OFFSETS = MERC_RECRUITABLE_OFFSETS,
}