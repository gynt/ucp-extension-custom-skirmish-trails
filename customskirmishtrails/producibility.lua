local memory = require("customskirmishtrails.memory")
local common = require("customskirmishtrails.common")
local patches = require("customskirmishtrails.patches")

local WEAPON_PRODUCIBLE_OFFSETS = {
  offsets = {
    ["crossbows"] = 0,
    ["pikes"] = 4,
    ["swords"] = 8,
    ["bows"] = 12,
    ["spears"] = 16,
    ["maces"] = 20,
  },
  writeFunction = core.writeInteger,
  readFunction = core.readInteger,
}

local function setWeaponProducible(weapon, value)
  local f = WEAPON_PRODUCIBLE_OFFSETS.writeFunction
  local address = memory.WEAPON_PRODUCIBLE
  local offsets = WEAPON_PRODUCIBLE_OFFSETS.offsets
  if not address then return end
  local addr = address + offsets[weapon]
  f(addr, value)
end

local function setWeaponsProducible(entry)
  for name, offset in pairs(WEAPON_PRODUCIBLE_OFFSETS.offsets) do
    local entry_name = string.format("producible_%s", name)
    if entry[entry_name] ~= nil then
      setWeaponProducible(name, entry[entry_name])
    end
  end
end

local function getWeaponProducible(weapon, value)
  local f = WEAPON_PRODUCIBLE_OFFSETS.readFunction
  local address = memory.WEAPON_PRODUCIBLE
  local offsets = WEAPON_PRODUCIBLE_OFFSETS.offsets
  local addr = address + offsets[weapon]
  local value = f(addr)
  return value
end


local installed = false

return {
  enable = function()
    if installed then return true end
    local pFletcherDetour = patches.find("B8 11 00 00 00 EB E4")
    local pPoleTurnerDetour = patches.find("B8 13 00 00 00 66 89 84 37 A2 02 00 00")
    if pFletcherDetour == nil or pPoleTurnerDetour == nil
        or not memory.bindExtra("WEAPON_PRODUCIBLE") then return false end
    patches.guarded({ { address = pFletcherDetour, size = 5 },
      { address = pPoleTurnerDetour, size = 5 } }, function()
      core.writeCode(pFletcherDetour, {0x90, 0x90, 0x90, 0x90, 0x90, })
      core.detourCode(function(registers)
        local canBow = getWeaponProducible("bows") == 1
        local canCrossBow = getWeaponProducible("crossbows") == 1

        if not canBow then
          if canCrossBow then
            registers.EAX = common.resources.crossbow
          else
            registers.EAX = common.resources.bow
          end
        else
          registers.EAX = common.resources.bow
        end

        return registers
      end, pFletcherDetour, 5)

      core.writeCode(pPoleTurnerDetour, {0x90, 0x90, 0x90, 0x90, 0x90, })
      core.detourCode(function(registers)
        local canSpear = getWeaponProducible("spears") == 1
        local canPike = getWeaponProducible("pikes") == 1

        if not canSpear then
          if canPike then
            registers.EAX = common.resources.pike
          else
            registers.EAX = common.resources.spear
          end
        else
          registers.EAX = common.resources.spear
        end

        return registers
      end, pPoleTurnerDetour, 5)
    end)
    installed = true
    return true
  end,
  setWeaponProducible = setWeaponProducible,
  setWeaponsProducible = setWeaponsProducible,
  WEAPON_PRODUCIBLE_OFFSETS = WEAPON_PRODUCIBLE_OFFSETS,
}