---@diagnostic disable-next-line: undefined-global
local ucp = ucp or {internal = {
  resolveAliasedPath = function(...) error("resolveAliasedPath not found, ucp lib not found") end,
}}
local csv = require("customskirmishtrails.vendor.lua-csv")

local strict = false

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
  "resource_iron",
  "resource_pitch",
  "resource_wheat",
  "resource_bread",
  "resource_cheese",
  "resource_meat",
  "resource_apple",
  "resource_ale",
  "resource_flour",
  "resource_bow",
  "resource_crossbow",
  "resource_spear",
  "resource_pike",
  "resource_mace",
  "resource_sword",
  "resource_leatherarmor",
  "resource_ironarmor",
  "tradeable_wood",
  "tradeable_hops",
  "tradeable_stone",
  "tradeable_iron",
  "tradeable_pitch",
  "tradeable_wheat",
  "tradeable_bread",
  "tradeable_cheese",
  "tradeable_meat",
  "tradeable_apple",
  "tradeable_ale",
  "tradeable_beer",
  "tradeable_flour",
  "tradeable_bow",
  "tradeable_crossbow",
  "tradeable_spear",
  "tradeable_pike",
  "tradeable_mace",
  "tradeable_sword",
  "tradeable_leatherarmor",
  "tradeable_ironarmor",
  "text_description_line_01",
  "text_description_line_02",
  "text_description_line_03",
  "text_description_line_04",
  "text_description_line_05",
  "text_description_line_06",
  "text_description_line_07",
  "text_description_line_08",
  "gold_player_1",
  "gold_player_2",
  "gold_player_3",
  "gold_player_4",
  "gold_player_5",
  "gold_player_6",
  "gold_player_7",
  "gold_player_8",
  "player1_name",
  "player2_name",
  "player3_name",
  "player4_name",
  "player5_name",
  "player6_name",
  "player7_name",
  "player8_name",
  "player1_lord",
  "player1_skip_start_units",
  "player2_color",
  "player3_color",
  "player4_color",
  "player5_color",
  "player6_color",
  "player7_color",
  "player8_color",
  "mission_type",
  "difficulty_scaling",
  "unit_limit",
  "scenario_briefing",
}

---@alias binary 0|1

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
  ["resource_iron"] = "integer",
  ["resource_pitch"] = "integer",
  ["resource_wheat"] = "integer",
  ["resource_bread"] = "integer",
  ["resource_cheese"] = "integer",
  ["resource_meat"] = "integer",
  ["resource_apple"] = "integer",
  ["resource_ale"] = "integer",
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
  ["gold_player_1"] = "integer",
  ["gold_player_2"] = "integer",
  ["gold_player_3"] = "integer",
  ["gold_player_4"] = "integer",
  ["gold_player_5"] = "integer",
  ["gold_player_6"] = "integer",
  ["gold_player_7"] = "integer",
  ["gold_player_8"] = "integer",
  ["player1_name"] = "string",
  ["player2_name"] = "string",
  ["player3_name"] = "string",
  ["player4_name"] = "string",
  ["player5_name"] = "string",
  ["player6_name"] = "string",
  ["player7_name"] = "string",
  ["player8_name"] = "string",
  ["player1_lord"] = "string",
  ["player1_skip_start_units"] = "binary",
  ["player2_color"] = "string",
  ["player3_color"] = "string",
  ["player4_color"] = "string",
  ["player5_color"] = "string",
  ["player6_color"] = "string",
  ["player7_color"] = "string",
  ["player8_color"] = "string",
  ["mission_type"] = "string",
  ["difficulty_scaling"] = "string",
  ["unit_limit"] = "string",
  ["scenario_briefing"] = "string",
  ["icon_locked"] = "integer",
  ["icon_available"] = "integer",
  ["icon_won"] = "integer",
}

local ALLOW_NIL = {
  ["player1_name"] = true,
  ["player2_name"] = true,
  ["player3_name"] = true,
  ["player4_name"] = true,
  ["player5_name"] = true,
  ["player6_name"] = true,
  ["player7_name"] = true,
  ["player8_name"] = true,
  ["player1_lord"] = true,
  ["player1_skip_start_units"] = true,
  ["icon_locked"] = true,
  ["icon_available"] = true,
  ["icon_won"] = true,
  ["gold_player_1"] = true,
  ["gold_player_2"] = true,
  ["gold_player_3"] = true,
  ["gold_player_4"] = true,
  ["gold_player_5"] = true,
  ["gold_player_6"] = true,
  ["gold_player_7"] = true,
  ["gold_player_8"] = true,

  ["resource_wood"] = true,
  ["resource_hops"] = true,
  ["resource_stone"] = true,
  ["resource_iron"] = true,
  ["resource_pitch"] = true,
  ["resource_wheat"] = true,
  ["resource_bread"] = true,
  ["resource_cheese"] = true,
  ["resource_meat"] = true,
  ["resource_apple"] = true,
  ["resource_ale"] = true,
  ["resource_flour"] = true,
  ["resource_bow"] = true,
  ["resource_crossbow"] = true,
  ["resource_spear"] = true,
  ["resource_pike"] = true,
  ["resource_mace"] = true,
  ["resource_sword"] = true,
  ["resource_leatherarmor"] = true,
  ["resource_ironarmor"] = true,
  ["producible_bows"] = true,
  ["producible_crossbows"] = true,
  ["producible_maces"] = true,
  ["producible_pikes"] = true,
  ["producible_spears"] = true,
  ["producible_swords"] = true,
  ["recruitable_archers"] = true,
  ["recruitable_spearmen"] = true,
  ["recruitable_macemen"] = true,
  ["recruitable_crossbowmen"] = true,
  ["recruitable_pikemen"] = true,
  ["recruitable_swordsmen"] = true,
  ["recruitable_knights"] = true,
  ["recruitable_arabian_bows"] = true,
  ["recruitable_slaves"] = true,
  ["recruitable_slingers"] = true,
  ["recruitable_assassins"] = true,
  ["recruitable_horse_archers"] = true,
  ["recruitable_arabian_swordsmen"] = true,
  ["recruitable_fire_throwers"] = true,
  ["tradeable_wood"] = true,
  ["tradeable_hops"] = true,
  ["tradeable_stone"] = true,
  ["tradeable_iron"] = true,
  ["tradeable_pitch"] = true,
  ["tradeable_wheat"] = true,
  ["tradeable_bread"] = true,
  ["tradeable_cheese"] = true,
  ["tradeable_meat"] = true,
  ["tradeable_apple"] = true,
  ["tradeable_ale"] = true,
  ["tradeable_beer"] = true,
  ["tradeable_flour"] = true,
  ["tradeable_bow"] = true,
  ["tradeable_crossbow"] = true,
  ["tradeable_spear"] = true,
  ["tradeable_pike"] = true,
  ["tradeable_mace"] = true,
  ["tradeable_sword"] = true,
  ["tradeable_leatherarmor"] = true,
  ["tradeable_ironarmor"] = true,
}

local function readBytes(path)
  local opened, handle, err = pcall(io.open, path, "rb")
  if not opened or handle == nil then return nil, opened and err or handle end
  local contents, readError = handle:read("a")
  handle:close()
  return contents, readError
end

local fails = {}

local function fail(name, index, expected, received, value)
  local text = tostring(value or "")
  local msg = string.format("header %s: entry %s, expected a '%s' but received a '%s' (length: %d): %s ", name, index, expected, received, text:len(), text)
  table.insert(fails, msg)
  -- every single problem only in strict mode; otherwise one summary line per file
  log(strict and WARNING or VERBOSE, msg)
end

local function numberify(name, index, expected, received, value)
  local nvalue = tonumber(value)
  if value == "" and ALLOW_NIL[name] then return nil end
  if nvalue == nil or (expected == "binary" and nvalue ~= 1 and nvalue ~= 0)
      or (expected == "integer" and math.tointeger(nvalue) == nil) then
    fail(name, index, expected, received, value)
    return nil
  end
  return nvalue
end

-- a scenario mission plays the map with its own players and ignores these columns
local function scenarioUnused(name)
  return name == "fairness" or name == "start_levels" or name:match("^start_position%d$")
    or name:match("^team%d$") or name:match("^aiv_type%d$")
end

local function validateInput(input, index, source, jsonRow)
  index = index or "<NA>"
  local isScenario = require("customskirmishtrails.scenario").isScenario(input)

  for name, value in pairs(input) do
    local t = HEADERS_TYPES[name]
    if name == "" or (name == "map_name" and value == "") then
      -- Unnamed columns and blank map names leave the native row unchanged.
      input[name] = nil
    elseif value == "" and jsonRow ~= nil and t ~= nil and t ~= "string" and jsonRow[name] == nil then
      -- Absent JSON numbers and flags use the same defaults as absent CSV columns.
      input[name] = nil
    elseif isScenario and scenarioUnused(name) and tostring(value):match("^%s*$") then
      input[name] = nil
    elseif t == nil then
      if not source then
        fail(name, index, "nil", type(value), value)
      end
    else
      local ty = type(value)
      if ty == "string" then
        -- always fine?
        if t == "binary" then
          input[name] = numberify(name, index,t, ty, value)
        elseif t == "number" or t == "integer" then
          input[name] = numberify(name, index,t, ty, value)
        elseif t ~= "string" then
          fail(name, index, t, ty, value)
        end
      elseif ty == "number" then
        if t == "integer" then
          input[name] = numberify(name, index,t, ty, value)
        elseif t == "binary" then
          input[name] = numberify(name, index,t, ty, value)
        else
          fail(name, index, t, ty, value)
        end
      elseif ty == "boolean" then
        if t ~= "boolean" then fail(name, index, t, ty, value) end
      else
        error(string.format("unsupported type for '%s': %s", name, value))
      end
    end
  end

end

---Reads the trail csv file `path`, or `contents` in its place.
local function readCSV(path, limit, contents, requireMissions, jsonRows)
  log(2, string.format("readCSV: %s", path))
  local reason
  if contents == nil then
    contents, reason = readBytes(path)
  end
  if contents == nil then
    return nil, string.format("%s: %s", tostring(path), tostring(reason))
  end
  local c = csv.openstring(contents, { header = true, separator = requireMissions and ',' or nil, filename = path })

  local entries = {}
  for line in c:lines() do
    limit = limit - 1
    if limit < 1 then
      break
    end
    if requireMissions and (type(line.map_name) ~= "string" or line.map_name == "") then
      return nil, string.format("mission %d has no map_name", #entries + 1)
    end
    table.insert(entries, line)
  end

  if requireMissions and #entries == 0 then
    return nil, "no mission rows"
  end

  -- clear fails table
  fails = {}

  for index, entry in ipairs(entries) do
    local valid, err = pcall(validateInput, entry, index, requireMissions, jsonRows and jsonRows[index])
    if not valid then
      local msg = string.format("entry #%i contains invalid information: %s", index, err)
      if requireMissions then return nil, msg end
      log(WARNING, msg)
      table.insert(fails, msg)
    end
  end

  if #fails > 0 and not strict then
    log(WARNING, string.format("%d problems in the trail csv file %s; turn on strict mode in your profile to see them", #fails, path))
  end

  return entries
end

return {
  setStrict = function(value) strict = value end,
  readCSV = readCSV,
  readBytes = readBytes,
  HEADERS =  HEADERS,
  HEADERS_EXTRA = HEADERS_EXTRA,
  HEADERS_TYPES = HEADERS_TYPES,
}
