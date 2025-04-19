local resources = require("customskirmishtrails.common").resources
local _, pTradeAbilityArray


return {
  enable = function()
    _, pTradeAbilityArray = utils.AOBExtract("89 ? I(? ? ? ?) 83 C0 08 83 C1 04 83 C6 04")
  end,

  setTradeable = function(goodsType, bool)
    if resources[goodsType] == nil then
      error(debug.traceback(string.format("No such goods type: %s", goodsType)))
    end
    
    local addr = pTradeAbilityArray + (4 * resources[goodsType])
    log(2, string.format("setTradeable: %s => %s @ 0x%X", goodsType, bool, addr))
    core.writeInteger(addr, bool)
  end,

  getTradeable = function(goodsType)
    if resources[goodsType] == nil then
      error(debug.traceback(string.format("No such goods type: %s", goodsType)))
    end
    
    local addr = pTradeAbilityArray + (4 * resources[goodsType])
    log(2, string.format("getTradeable: %s @ 0x%X", goodsType, addr))
    return core.readInteger(addr)
  end,
}