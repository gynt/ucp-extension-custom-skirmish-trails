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
}