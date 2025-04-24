---@diagnostic disable-next-line: undefined-global
local ucp = ucp or {internal = {
  resolveAliasedPath = function(...) error("resolveAliasedPath not found, ucp lib not found") end,
}}
local csv = require("customskirmishtrails.vendor.lua-csv")

local HEADERS = {
  "map_name", 
  "fairness",
	"start_levels",
	"num_players",
	"player1",
	"player2",
	"player3",
	"player4",
	"player5",
	"player6",
	"player7",
	"player8",
	"start_position1",
	"start_position2",
	"start_position3",
	"start_position4",
	"start_position5",
	"start_position6",
	"start_position7",
	"start_position8",
	"team1",
	"team2",
	"team3",
	"team4",
	"team5",
	"team6",
	"team7",
	"team8",
	"aiv_type1",
	"aiv_type2",
	"aiv_type3",
	"aiv_type4",
	"aiv_type5",
	"aiv_type6",
	"aiv_type7",
	"aiv_type8",
	}

local HEADERS_EXTRA = {
  "mission_name",
  "gold",
  "producible_bows",
  "producible_crossbows",
  "producible_maces",
  "producible_pikes",
  "producible_spears",
  "producible_swords",
  "recruitable_archers",
  "recruitable_spearmen",
  "recruitable_macemen",
  "recruitable_crossbowmen",
  "recruitable_pikemen",
  "recruitable_swordsmen",
  "recruitable_knights",
  "recruitable_arabian_bows",
  "recruitable_slaves",
  "recruitable_slingers",
  "recruitable_assassins",
  "recruitable_horse_archers",
  "recruitable_arabian_swordsmen",
  "recruitable_fire_throwers",
  "resource_wood",
  "resource_hops",
  "resource_stone",
 -- "resource_partialstone",
  "resource_iron",
  "resource_pitch",
 -- "resource_partialpitch",
  "resource_wheat",
  "resource_bread",
  "resource_cheese",
  "resource_meat",
  "resource_apple",
  "resource_ale",
  "resource_gold",
  "resource_flour",
  "resource_bow",
  "resource_crossbow",
  "resource_spear",
  "resource_pike",
  "resource_mace",
  "resource_sword",
  "resource_leatherarmor",
  "resource_ironarmor",
  "trade_wood",
  "trade_hops",
  "trade_stone",
  "trade_iron",
  "trade_pitch",
  "trade_wheat",
  "trade_bread",
  "trade_cheese",
  "trade_meat",
  "trade_apple",
  "trade_ale",
  "trade_beer",
  "trade_gold",
  "trade_flour",
  "trade_bow",
  "trade_crossbow",
  "trade_spear",
  "trade_pike",
  "trade_mace",
  "trade_sword",
  "trade_leatherarmor",
  "trade_ironarmor",
  "text_description_line_01",
  "text_description_line_02",
  "text_description_line_03",
  "text_description_line_04",
  "text_description_line_05",
  "text_description_line_06",
  "text_description_line_07",
  "text_description_line_08",
}

local HEADERS_TYPES = {
  ["map_name"] = "string", 
  ["fairness"] = "integer",
	["start_levels"] = "integer",
	["num_players"] = "integer",
	["player1"] = "string",
	["player2"] = "string",
	["player3"] = "string",
	["player4"] = "string",
	["player5"] = "string",
	["player6"] = "string",
	["player7"] = "string",
	["player8"] = "string",
	["start_position1"] = "integer",
	["start_position2"] = "integer",
	["start_position3"] = "integer",
	["start_position4"] = "integer",
	["start_position5"] = "integer",
	["start_position6"] = "integer",
	["start_position7"] = "integer",
	["start_position8"] = "integer",
	["team1"] = "integer",
	["team2"] = "integer",
	["team3"] = "integer",
	["team4"] = "integer",
	["team5"] = "integer",
	["team6"] = "integer",
	["team7"] = "integer",
	["team8"] = "integer",
	["aiv_type1"] = "integer",
	["aiv_type2"] = "integer",
	["aiv_type3"] = "integer",
	["aiv_type4"] = "integer",
	["aiv_type5"] = "integer",
	["aiv_type6"] = "integer",
	["aiv_type7"] = "integer",
	["aiv_type8"] = "integer",
  ["mission_name"] = "string",
  ["gold"] = "integer",
  ["producible_bows"] = "binary",
  ["producible_crossbows"] = "binary",
  ["producible_maces"] = "binary",
  ["producible_pikes"] = "binary",
  ["producible_spears"] = "binary",
  ["producible_swords"] = "binary",
  ["recruitable_archers"] = "binary",
  ["recruitable_spearmen"] = "binary",
  ["recruitable_macemen"] = "binary",
  ["recruitable_crossbowmen"] = "binary",
  ["recruitable_pikemen"] = "binary",
  ["recruitable_swordsmen"] = "binary",
  ["recruitable_knights"] = "binary",
  ["recruitable_arabian_bows"] = "binary",
  ["recruitable_slaves"] = "binary",
  ["recruitable_slingers"] = "binary",
  ["recruitable_assassins"] = "binary",
  ["recruitable_horse_archers"] = "binary",
  ["recruitable_arabian_swordsmen"] = "binary",
  ["recruitable_fire_throwers"] = "binary",
  ["resource_wood"] = "integer",
  ["resource_hops"] = "integer",
  ["resource_stone"] = "integer",
 -- ["resource_partialstone"] = "integer",
  ["resource_iron"] = "integer",
  ["resource_pitch"] = "integer",
 -- ["resource_partialpitch"] = "integer",
  ["resource_wheat"] = "integer",
  ["resource_bread"] = "integer",
  ["resource_cheese"] = "integer",
  ["resource_meat"] = "integer",
  ["resource_apple"] = "integer",
  ["resource_ale"] = "integer",
  ["resource_gold"] = "integer",
  ["resource_flour"] = "integer",
  ["resource_bow"] = "integer",
  ["resource_crossbow"] = "integer",
  ["resource_spear"] = "integer",
  ["resource_pike"] = "integer",
  ["resource_mace"] = "integer",
  ["resource_sword"] = "integer",
  ["resource_leatherarmor"] = "integer",
  ["resource_ironarmor"] = "integer",
  ["tradeable_wood"] = "binary",
  ["tradeable_hops"] = "binary",
  ["tradeable_stone"] = "binary",
  ["tradeable_iron"] = "binary",
  ["tradeable_pitch"] = "binary",
  ["tradeable_wheat"] = "binary",
  ["tradeable_bread"] = "binary",
  ["tradeable_cheese"] = "binary",
  ["tradeable_meat"] = "binary",
  ["tradeable_apple"] = "binary",
  ["tradeable_ale"] = "binary",
  ["tradeable_beer"] = "binary",
  ["tradeable_gold"] = "binary",
  ["tradeable_flour"] = "binary",
  ["tradeable_bow"] = "binary",
  ["tradeable_crossbow"] = "binary",
  ["tradeable_spear"] = "binary",
  ["tradeable_pike"] = "binary",
  ["tradeable_mace"] = "binary",
  ["tradeable_sword"] = "binary",
  ["tradeable_leatherarmor"] = "binary",
  ["tradeable_ironarmor"] = "binary",
  ["text_description_line_01"] = "string",
  ["text_description_line_02"] = "string",
  ["text_description_line_03"] = "string",
  ["text_description_line_04"] = "string",
  ["text_description_line_05"] = "string",
  ["text_description_line_06"] = "string",
  ["text_description_line_07"] = "string",
  ["text_description_line_08"] = "string",
}

local function prefixHeaders(contents)
  return table.concat(HEADERS,",") .. "\r\n" .. contents
end

local function getContents(path)
  local path = ucp.internal.resolveAliasedPath(path)
  local handle, err = io.open(path,'rb')
  if handle == nil then error(debug.traceback(err)) end
  local contents = handle:read("*all")
  log(2, string.format("raw csv contents\n%s", contents))
  if contents:sub(1, ("map_name"):len()) ~= "map_name" then
    log(2, string.format("getContents: prefixing headers"))
     contents = prefixHeaders(contents)
  end
  handle:close()  
  return contents
end

local function fail(name, expected, received, value)
  error(string.format("header %s: expected a '%s' but received a '%s': %s", name, expected, received, value))
end

local function numberify(name, expected, received, value)
  local nvalue = tonumber(value)
  if nvalue == nil then
    fail(name, expected, received, value)
  end
  return nvalue
end

local function validateInput(input)

  for name, value in pairs(input) do
    local t = HEADERS_TYPES[name]
    if t == nil then error(string.format("undefined header: %s", name)) end
    local ty = type(value)
    if ty == "string" then
      -- always fine?
      if t == "binary" then
        local nvalue = numberify(name, t, ty, value)
        input[name] = nvalue
        if nvalue ~= 1 and nvalue ~= 0 then
          fail(name, t, ty, value)
        end
      elseif t == "number" or t == "integer" then
        input[name] = numberify(name, t, ty, value)
      elseif t ~= "string" then
        fail(name, t, ty, value)
      end
    elseif ty == "number" then
      if t == "integer" then
        local iv = tonumber(string.format("%i", value), 10)
        if iv == nil or iv ~= value then
          fail(name, t, ty, value)
        end
      elseif t == "binary" then
        if value ~= 0 and value ~= 1 then
          fail(name, t, ty, value)
        end
      else
        fail(name, t, ty, value)
      end
    elseif ty == "boolean" then
      if t ~= "boolean" then fail(name, t, ty, value) end
    else
      error(string.format("unsupported type for '%s': %s", name, value))
    end
  end

end

local function pvalidateInput(input)
  return pcall(validateInput, input)
end

local function readCSV(path, limit)
  log(2, string.format("readCSV: %s", path))
  local contents = getContents(path)
  local c = csv.openstring(contents, {header = true, })

  local entries = {}
  for line in c:lines() do
    limit = limit - 1
    if limit < 1 then
      break
    end
    table.insert(entries, line)
  end

  for index, entry in ipairs(entries) do
    local valid, err = pvalidateInput(entry)
    if not valid then
      log(WARNING, string.format("entry #%i contains invalid information: %s", index, err))
    end
  end

  return entries
end

-- local originalContents
-- local handle = io.open("extremeTrail.csv",'rb')
-- originalContents =  prefixHeaders(handle:read("*all"))
-- handle:close()

return {
  readCSV = readCSV,
  HEADERS =  HEADERS,
  HEADERS_EXTRA = HEADERS_EXTRA,
  HEADERS_TYPES = HEADERS_TYPES,
}