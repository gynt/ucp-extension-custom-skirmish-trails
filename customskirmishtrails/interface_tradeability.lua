local common = require("customskirmishtrails.common")
local resources = common.resources
local _, pTradeAbilityArray

local tradeability = {}


function tradeability.enable()
  _, pTradeAbilityArray = utils.AOBExtract("89 ? I(? ? ? ?) 83 C0 08 83 C1 04 83 C6 04")
end

function tradeability.setTradeable(goodsType, bool)
  if resources[goodsType] == nil then
    error(debug.traceback(string.format("No such goods type: %s", goodsType)))
  end
  
  local addr = pTradeAbilityArray + (4 * resources[goodsType])
  log(2, string.format("setTradeable: %s => %s @ 0x%X", goodsType, bool, addr))
  core.writeInteger(addr, bool)
end

function tradeability.setTradeables(entry)
  for _, resource in ipairs(common.resources_array) do
    local v = entry[string.format("trade_%s", resource)]
    if v ~= nil then
      log(2, string.format("tradeability: setting resource %s to %s", resource, v))
      tradeability.setTradeable(resource, v)  
    end
  end
end

function tradeability.getTradeable(goodsType)
  if resources[goodsType] == nil then
    error(debug.traceback(string.format("No such goods type: %s", goodsType)))
  end
  
  local addr = pTradeAbilityArray + (4 * resources[goodsType])
  log(2, string.format("getTradeable: %s @ 0x%X", goodsType, addr))
  return core.readInteger(addr)
end

return tradeability