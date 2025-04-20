local memory = require("customskirmishtrails.memory")

local common = require("customskirmishtrails.common")

local function setStartGood(good, value)
  local g = common.resources[good]
  if g == nil then error(string.format("unknown good type: %s", good)) end

  local addr = memory.START_GOODS + (4*g)
  log(2, string.format("setStartGood: %s @ %X: %s", good,addr, value))
  core.writeInteger(addr, value)
end

local function setStartGoods(entry)
  for name, offset in pairs(common.resources) do
    local rname = "resources_" .. name
    if entry[rname] ~= nil then
      setStartGood(name, entry[rname])
    end
  end
end

return {
  setStartGood = setStartGood,
  setStartGoods = setStartGoods,
}