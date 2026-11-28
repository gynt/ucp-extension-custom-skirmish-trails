-- The trail settings file: one JSON file per trail with the settings that belong to the trail
-- as a whole (see resources/trail-settings.schema.json). Everything in it is optional; what is
-- missing or invalid falls back to the game's own value. Wrong types are errors.

local patches = require("customskirmishtrails.patches")
local cst_io = require("customskirmishtrails.io")

local settings = {}
local decoder = json:new({ strictTypes = true })
local object = getmetatable(decoder:newObject())
local array = getmetatable(decoder:newArray())

settings.TRAIL_TYPES = {
  First = "firstEditionTrail",
  Warchest = "warchestTrail",
  Extreme = "extremeTrail",
}

settings.AI_KEYS = {
  "SK_RAT", "SK_SNAKE", "SK_PIG", "SK_WOLF", "SK_SALADIN", "SK_CALIPH", "SK_SULTAN", "SK_RICHARD",
  "SK_FREDERICK", "SK_PHILLIP", "SK_WAZIR", "SK_EMIR", "SK_NIZAR", "SK_SHERIFF", "SK_MARSHAL", "SK_ABBOT",
}

-- the trail screen is 800 x 600
local MAX_X, MAX_Y = 800, 600

local strict = false
local problems = {}

---Strict mode: every problem and every entry that falls back to the game's
---own value is logged. Otherwise only one line per file that has problems.
function settings.setStrict(value)
  strict = value == true
end

local function report(path, level, message, ...)
  log(level, string.format("%s: " .. message, path, ...))
end

---An invalid entry uses the game's own value. Only warnings are summarized.
local function invalid(path, level, message, ...)
  if level == WARNING and not strict then
    problems[path] = (problems[path] or 0) + 1
    level = VERBOSE
  end
  report(path, level, message, ...)
end

local function info(path, message, ...)
  if strict then
    log(INFO, string.format("%s: " .. message, path, ...))
  end
end

local function readText(path)
  local contents, err = cst_io.readBytes(path)
  if contents == nil then return nil, err end
  -- a UTF-8 byte order mark is not JSON
  if contents:sub(1, 3) == "\239\187\191" then
    contents = contents:sub(4)
  end
  return contents
end
settings.readText = readText

---The folder part of `path`, with its trailing slash ("" for a bare file name).
function settings.directoryOf(path)
  return path:match("^(.*[/\\])") or ""
end

---`path` relative to `baseDirectory` unless it names a game path.
function settings.resolveRelative(baseDirectory, path)
  if path:match("^%a:[/\\]") or path:match("^[/\\]") then
    return io.gameRelativePath(path) or path
  end
  if path:lower():match("^ucp[/\\]") then
    return path
  end
  return baseDirectory .. path
end

local function nonEmptyString(value)
  return type(value) == "string" and value ~= ""
end

local function integer(value)
  if type(value) ~= "number" then
    return nil
  end
  return math.tointeger(value)
end

local function readPositions(path, value, trailName)
  if value == nil then
    return nil
  end
  if getmetatable(value) ~= array or #value == 0 then
    invalid(path, getmetatable(value) == array and WARNING or ERROR,
      "trail_mission_positions must be a non-empty list of positions")
    return nil
  end
  local capacity = patches.CAPACITY[trailName]
  local positions = {}
  for index, entry in ipairs(value) do
    local x, y
    if type(entry) == "table" then
      x, y = entry.x, entry.y
      if getmetatable(entry) == array then x, y = entry[1], entry[2] end
    end
    if type(x) ~= "number" or type(y) ~= "number" then
      report(path, ERROR, "trail_mission_positions entry %d needs numeric x and y coordinates", index)
      return nil
    end
    x, y = math.tointeger(x), math.tointeger(y)
    if x == nil or y == nil or x < 0 or y < 0 or x > MAX_X or y > MAX_Y then
      invalid(path, WARNING, "trail_mission_positions entry %d needs whole coordinates inside 800 x 600", index)
      return nil
    end
    table.insert(positions, { x = x, y = y })
  end
  if #positions > capacity then
    invalid(path, WARNING, "this trail can have at most %d missions; only the first %d positions are used", capacity, capacity)
    while #positions > capacity do
      table.remove(positions)
    end
  end
  return positions
end

settings.DATA_MODES = { csv = true, json_folder = true, automatic = true }

---trail_missions: { "base_name": "missions/trail", "data_mode": "csv" }. base_name names both the
---csv file (<base_name>.csv) and the folder of mission files (<base_name>/<name>_mission_NN.json).
local function readMissions(path, directory, value)
  if value == nil then
    return nil
  end
  if getmetatable(value) ~= object or not nonEmptyString(value.base_name) then
    report(path, ERROR, "trail_missions needs a \"base_name\" (the csv file without .csv)")
    return nil
  end
  local mode = value.data_mode
  if mode == nil or mode == "" then
    mode = "csv"
    info(path, "trail_missions.data_mode is not set; \"csv\" is used")
  elseif not settings.DATA_MODES[mode] then
    invalid(path, type(mode) == "string" and WARNING or ERROR,
      "trail_missions.data_mode must be csv, json_folder or automatic; \"csv\" is used")
    mode = "csv"
  end
  local base = settings.resolveRelative(directory, (value.base_name:gsub("%.[cC][sS][vV]$", "")))
  base = base:gsub("[/\\]+$", "")
  return {
    csv = base .. ".csv",
    folder = base,
    name = base:match("([^/\\]+)$") or base,
    mode = mode,
  }
end

---trail_text_files: a folder of <language>.json files, or a map of languages to files.
local function readTextFiles(path, directory, value)
  if value == nil then
    return nil
  end
  if type(value) == "string" then
    if value == "" then
      return nil
    end
    local folder = settings.resolveRelative(directory, value)
    if not folder:match("[/\\]$") then
      folder = folder .. "/"
    end
    return { folder = folder }
  end
  if getmetatable(value) ~= object then
    report(path, ERROR, "trail_text_files must be a folder or map languages to language files")
    return nil
  end
  local files, count = {}, 0
  for language, file in pairs(value) do
    if nonEmptyString(file) then
      files[language:lower()] = settings.resolveRelative(directory, file)
      count = count + 1
    elseif file ~= "" then
      report(path, ERROR, "trail_text_files entry '%s' must be a file name", language)
    end
  end
  return count > 0 and { files = files } or nil
end

local function readAiMapping(path, value)
  local mapping = {}
  for _, key in ipairs(settings.AI_KEYS) do
    mapping[key] = key
  end
  if value == nil then
    return mapping, false
  end
  if getmetatable(value) ~= object then
    report(path, ERROR, "ai_character_mapping must be an object")
    return mapping, false
  end
  for key in pairs(value) do
    if mapping[key] == nil then
      invalid(path, WARNING, "ai_character_mapping has an unknown key '%s'", key)
    end
  end
  local seen = {}
  for _, key in ipairs(settings.AI_KEYS) do
    local alias = value[key]
    if nonEmptyString(alias) then
      -- every alias names one AI only, so a name in a trail file resolves to one AI
      if alias ~= key and mapping[alias] ~= nil then
        invalid(path, WARNING, "ai_character_mapping alias '%s' for %s is another AI's key; %s keeps its own name",
          alias, key, key)
      elseif seen[alias] ~= nil then
        invalid(path, WARNING, "ai_character_mapping gives '%s' to both %s and %s; %s keeps its own name",
          alias, seen[alias], key, key)
      else
        mapping[key] = alias
        seen[alias] = key
      end
    elseif alias ~= nil and type(alias) ~= "string" then
      report(path, ERROR, "ai_character_mapping.%s must be a string", key)
    end
  end
  return mapping, true
end

---Reads the trail settings file at `path`, meant for `trailName`. Returns nil when the file
---cannot be used at all.
function settings.load(path, trailName, jsonSource)
  local contents, err = readText(path)
  if contents == nil then
    report(path, WARNING, "cannot read the trail settings file (%s)", tostring(err))
    return nil
  end
  local ok, data = pcall(decoder.decode, decoder, contents)
  if not ok then
    report(path, ERROR, "the trail settings file is not valid JSON: %s", tostring(data))
    return nil
  end
  if getmetatable(data) ~= object then
    report(path, ERROR, "the trail settings file must contain a JSON object")
    return nil
  end

  if data.trail_type ~= nil and type(data.trail_type) ~= "string" then
    report(path, ERROR, "trail_type must be a string")
  elseif data.trail_type ~= nil then
    local declared = settings.TRAIL_TYPES[data.trail_type]
    if declared == nil then
      report(path, WARNING, "trail_type must be First, Warchest or Extreme; the selected trail is used")
    elseif declared ~= trailName then
      report(path, WARNING, "this file is for the %s trail but is set for another trail; it is not used", data.trail_type)
      return nil
    end
  end

  if jsonSource then
    local missions = data.trail_missions
    if getmetatable(missions) ~= object or not nonEmptyString(missions.base_name) then
      report(path, ERROR, "a JSON trail source needs trail_missions.base_name")
      return nil
    end
    if missions.data_mode ~= nil and missions.data_mode ~= "json_folder" then
      invalid(path, type(missions.data_mode) == "string" and WARNING or ERROR,
        'a JSON trail source uses json_folder mission data')
    end
    missions.data_mode = "json_folder"
  end

  local directory = settings.directoryOf(path)
  local result = { path = path, trail = trailName }
  -- Without a trail_id the trail's files are named by its trail_type in lowercase, which no trail_id can be.
  local ownName, reserved = nil, false
  for trailType, name in pairs(settings.TRAIL_TYPES) do
    if name == trailName then
      ownName = trailType:lower()
    end
    reserved = reserved or trailType:lower() == data.trail_id
  end
  if type(data.trail_id) == "string" and #data.trail_id <= 64 and data.trail_id:match("^[%l%d][%l%d_-]*$")
      and not reserved then
    result.id = data.trail_id
  elseif data.trail_id ~= nil then
    invalid(path, type(data.trail_id) == "string" and WARNING or ERROR,
      "trail_id must be 1 to 64 lowercase letters, digits, '-' or '_', starting with a letter or digit, "
      .. "and not first, warchest or extreme")
  end
  result.fileName = result.id or ownName

  for key, field in pairs({ trail_title = "title", trail_summary = "summary", mission_locked_text = "lockedText" }) do
    local value = data[key]
    if nonEmptyString(value) then
      result[field] = value
    elseif value ~= nil and type(value) ~= "string" then
      report(path, ERROR, "%s must be a string", key)
    end
  end

  local chickens = data.chickens
  if chickens == "unlimited" or (type(chickens) == "number" and math.tointeger(chickens) ~= nil
      and chickens >= 0 and chickens <= 2147483647) then
    result.chickens = chickens
  elseif chickens ~= nil then
    local kind = type(chickens)
    invalid(path, (kind == "number" or kind == "string") and WARNING or ERROR,
      "chickens must be a non-negative 32-bit integer or 'unlimited'")
  end

  if data.starting_year ~= nil then
    local year = integer(data.starting_year)
    if year == nil or year < 1 or year > 9999 then
      invalid(path, type(data.starting_year) == "number" and WARNING or ERROR,
        "starting_year must be a whole year between 1 and 9999")
    else
      result.startingYear = year
    end
  end

  local visuals = data.trail_visuals
  if visuals ~= nil and getmetatable(visuals) ~= object then
    report(path, ERROR, "trail_visuals must be an object")
    visuals = nil
  end
  result.visuals = {}
  for jsonKey, key in pairs({ trail_button_idle = "buttonIdle", trail_button_highlighted = "buttonHighlighted",
                              trail_background = "background", mission_icons = "iconSheet",
                              chicken_idle = "chickenIdle", chicken_highlighted = "chickenHighlighted",
                              skirmish_masters_idle = "skirmishMastersIdle",
                              skirmish_masters_highlighted = "skirmishMastersHighlighted",
                              back_idle = "backIdle", back_highlighted = "backHighlighted",
                              next_idle = "nextIdle", next_highlighted = "nextHighlighted" }) do
    local value = visuals and visuals[jsonKey]
    if nonEmptyString(value) then
      result.visuals[key] = settings.resolveRelative(directory, value)
    elseif value ~= nil and type(value) ~= "string" then
      report(path, ERROR, "trail_visuals.%s must be a string", jsonKey)
    end
  end

  result.positions = readPositions(path, data.trail_mission_positions, trailName)
  -- read by route.lua: by init.lua before the mission count for a route of files, after it otherwise
  result.route = data.trail_route
  if result.route ~= nil and getmetatable(result.route) ~= object then
    report(path, ERROR, "trail_route must be an object")
    result.route = nil
  end
  result.missions = readMissions(path, directory, data.trail_missions)
  result.textFiles = readTextFiles(path, directory, data.trail_text_files)
  result.aiMapping, result.hasAiMapping = readAiMapping(path, data.ai_character_mapping)

  -- what falls back to the game's own values (strict mode only)
  if data.trail_type == nil then
    info(path, "trail_type is not set; the file is used for the trail it is set for in the GUI")
  end
  if result.title == nil then
    info(path, "trail_title is not set; the game's own title is shown (unless a language file has one)")
  end
  if result.summary == nil then
    info(path, "trail_summary is not set; the game's own summary is shown (unless a language file has one)")
  end
  if result.startingYear == nil then
    info(path, "starting_year is not set; the trail starts in the game's own year")
  end
  for _, jsonKey in ipairs({ "trail_button_idle", "trail_button_highlighted", "trail_background" }) do
    local key = ({ trail_button_idle = "buttonIdle", trail_button_highlighted = "buttonHighlighted",
                   trail_background = "background" })[jsonKey]
    if result.visuals[key] == nil then
      info(path, "trail_visuals.%s is not set; the game's own picture is shown", jsonKey)
    end
  end
  if result.positions == nil then
    info(path, "trail_mission_positions is not set; the trail keeps the game's mission count and button positions")
  end
  if result.missions == nil then
    info(path, "trail_missions is not set; the legacy CSV path is used")
  end
  if result.textFiles == nil then
    info(path, "trail_text_files is not set; every game language shows the texts of the mission data")
  end
  if not result.hasAiMapping then
    info(path, "ai_character_mapping is not set; mission files use the AI keys (SK_RAT, ...)")
  else
    local value = type(data.ai_character_mapping) == "table" and data.ai_character_mapping or {}
    for _, key in ipairs(settings.AI_KEYS) do
      if not nonEmptyString(value[key]) then
        info(path, "ai_character_mapping.%s is not set; it keeps its own name", key)
      end
    end
  end

  if not strict and (problems[path] or 0) > 0 then
    log(WARNING, string.format("%d problems in the trail settings file %s; those entries use "
      .. "the game's own values. Turn on strict mode in your profile to see them.", problems[path], path))
  end
  problems[path] = nil
  return result
end

return settings
