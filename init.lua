local memory = require("customskirmishtrails.memory")
local interface = require("customskirmishtrails.interface")
local cst_io = require("customskirmishtrails.io")
local description = require("customskirmishtrails.description")
local tradeability = require("customskirmishtrails.tradeability")
local producibility = require("customskirmishtrails.producibility")
local recruitability = require("customskirmishtrails.recruitability")
local startgold = require("customskirmishtrails.startgold")
local start_goods = require("customskirmishtrails.start_goods")
local patches = require("customskirmishtrails.patches")
local settingsModule = require("customskirmishtrails.settings")
local visuals = require("customskirmishtrails.visuals")
local menutext = require("customskirmishtrails.menutext")
local textsModule = require("customskirmishtrails.texts")
local sync = require("customskirmishtrails.sync")
local progress = require("customskirmishtrails.progress")
local scenario = require("customskirmishtrails.scenario")
local unitlimits = require("customskirmishtrails.unitlimits")
local markers = require("customskirmishtrails.markers")
local route = require("customskirmishtrails.route")

local REGISTRY = memory.REGISTRY
local fetchCurrentTrail = memory.fetchCurrentTrail

-- The three trails: their name in this module, their key in the GUI config and their
-- trail_type in trail settings files.
local TRAILS = {
  { name = "firstEditionTrail", key = "firstedition", type = "First" },
  { name = "warchestTrail", key = "warchest", type = "Warchest" },
  { name = "extremeTrail", key = "extremetrail", type = "Extreme" },
}

-- per trail: mission number -> map name given by a plugin (setMissionMap)
local MAP_OVERRIDES = {}
-- per trail: the briefing text of a scenario mission that is not open yet
local LOCKED_TEXTS = {}

local currentEntry = memory.currentEntry

local function insertPostSkirmishSetupDetour()
  local site = patches.find("8B 8C 24 ? ? 00 00 5f 5e 89 ? ? ? ? ? 89 ? ? ? ? ? 89 ? ? ? ? ? 89 ? ? ? ? ? 5B 33 CC")
  if site == nil then return false end
  core.detourCode(function(registers)
    local entry, isTrail = currentEntry()
    if isTrail and entry ~= nil then interface.commitEntryExtra(entry) end
    return registers
  end, site, 7)
end

local function insertStartGoodsDetour()
  local site = patches.find("A3 ? ? ? ? A3 ? ? ? ? A3 ? ? ? ? A3 ? ? ? ? A3 ? ? ? ? A3 ? ? ? ? A3 ? ? ? ? A3 ? ? ? ? A3 ? ? ? ? A3 ? ? ? ? A3 ? ? ? ? A3 ? ? ? ? A3 ? ? ? ? A3 ? ? ? ? 89 44 24 10")
  if site == nil then return false end
  core.detourCode(function(registers)
    local entry, isTrail = currentEntry()
    if isTrail and entry ~= nil then
      -- Starting troops are computed from the human player's lord type after this store.
      patches.applyLord(entry)
      interface.setStartGoods(entry)
    end
    return registers
  end, site, 5)
end

local function applyMapOverrides(trailName, entries, keys)
  local overrides = MAP_OVERRIDES[trailName]
  if overrides == nil then return end
  local rowOf = {}
  for row, key in ipairs(keys or {}) do
    rowOf[key] = row
  end
  for mission, mapName in pairs(overrides) do
    local index = rowOf[mission] or mission
    if entries[index] ~= nil then
      entries[index].map_name = mapName
    else
      log(WARNING, string.format("setMissionMap: the trail has no mission %s; %s is not used",
        tostring(mission), mapName))
    end
  end
  MAP_OVERRIDES[trailName] = nil
end

local function applyTrail(trailName, result, missions, languageTexts, startInstalled, keys)
  textsModule.apply(languageTexts, result, keys)
  for index, entry in ipairs(result) do
    interface.applyColors(entry, string.format("%s mission %d", trailName, index))
    if scenario.difficultyScaling(entry) == nil then
      log(WARNING, string.format("%s mission %d: unknown difficulty_scaling '%s'; vanilla is used",
        trailName, index, tostring(entry.difficulty_scaling)))
    end
    if scenario.missionType(entry) == nil then
      log(WARNING, string.format("%s mission %d: unknown mission_type '%s'",
        trailName, index, tostring(entry.mission_type)))
    elseif (scenario.isScenario(entry) or (entry.map_name ~= nil and entry.map_name ~= "")) and not startInstalled then
      result[index] = nil
    elseif scenario.isScenario(entry) then
      local fileName, reason = scenario.mapFileName(entry.map_name)
      if fileName == nil then
        log(WARNING, string.format("%s mission %d: scenario map '%s': %s",
          trailName, index, tostring(entry.map_name), reason))
      else
        entry.map_name = fileName
        scenario.applyMapLords(entry, fileName)
      end
    end
  end

  for index, entry in pairs(result) do
    interface.commitEntry(missions, index, entry, trailName)
  end
  REGISTRY[trailName] = result
end

local function detourSwitchToMenu(showDescription)
  local site = patches.find("C7 ? ? ? ? ? ? ? ? ? ? E8 ? ? ? ? 5D C3")
  if site == nil then return false end
  if showDescription and not description.enable() then return false end
  core.detourCode(function(registers)
    -- The game is preparing a trail mission, so the in-trail flag may not be set yet.
    local _, _, trailName, mission = fetchCurrentTrail()
    local missions = REGISTRY[trailName]
    local entry = missions and missions[mission]
    if showDescription then
      if entry ~= nil then
        interface.commitTextDescription(scenario.briefingEntry(entry, LOCKED_TEXTS[trailName]))
      else
        for line = 1, 8 do description.setText(line, "") end
      end
    end
    patches.applyLord(entry)
    return registers
  end, site, 11)
end

local function hookPlayerNaming(customNames)
  return patches.hookPlayerNaming(function(isTrailBriefing)
    local entry, isTrail = currentEntry()
    if isTrailBriefing or isTrail then
      patches.applyPlayerNames(entry)
      patches.applyLord(entry)
    else
      patches.applyLord(nil)
    end
  end, customNames)
end

---The user data file that keeps the trail's `kind` of state (progress, sides or results).
local function stateFile(kind, settings)
  return string.format("%s-%s.txt", kind, settings.fileName)
end

---The trail_route of a trail settings file; nil when it can't be played (logged).
local function installRoute(trail, settings, count)
  if settings.route == nil then
    return nil
  end
  local r = route.load(settings.routeFiles or route.read(settings.path, settings.route, count), count,
    stateFile("sides", settings), stateFile("results", settings))
  if r == nil then
    log(ERROR, trail.type .. " trail progression could not be applied.")
    return nil
  end
  if memory.bindProgress(trail.name) == nil or not memory.bindTrailType()
      or not progress.installRoute(trail.name, r) then
    log(ERROR, trail.type .. " trail progression could not be applied.")
    log(WARNING, string.format("%s: the trail route is switched off; the trail plays its "
      .. "missions in their order", settings.path))
    return nil
  end
  return r
end

---A route of mission files is the trail's mission data: it gives the order of the missions (the
---rows of the csv the game loads), their positions and their keys in language files.
local function readRouteFiles(trail, settings)
  local parsed = route.read(settings.path, settings.route, nil)
  local problem = parsed == nil and ""
    or settings.missions == nil and "a route of mission files needs trail_missions.base_name"
    or parsed.count > patches.CAPACITY[trail.name]
      and string.format("the route has %d missions; this trail can have at most %d", parsed.count,
        patches.CAPACITY[trail.name])
  if problem then
    if problem ~= "" then
      log(WARNING, string.format("%s: %s; the trail's missions are not loaded",
        settings.path, problem))
    end
    return false
  end
  if settings.positions ~= nil then
    log(WARNING, string.format("%s: a route of mission files has the positions; "
      .. "trail_mission_positions is not used", settings.path))
  end
  local directory = settingsModule.directoryOf(settings.path)
  local files = {}
  for row, file in ipairs(parsed.files) do
    files[row] = settingsModule.resolveRelative(directory, file)
  end
  settings.missions.files, settings.missions.mode = files, "json_folder"
  settings.positions, settings.missionKeys, settings.routeFiles = parsed.positions, parsed.keys, parsed
  return true
end

-- Trail sources ---------------------------------------------------------------------------

local function configuredPath(value, label)
  if value == nil then return end
  if type(value) ~= "table" or (value.path ~= nil and type(value.path) ~= "string") then
    log(ERROR, label .. " must be a file selection.")
    return
  end
  return value.path
end

local function knownHeaders()
  local headers = {}
  for _, header in ipairs(cst_io.HEADERS) do table.insert(headers, header) end
  for _, header in ipairs(cst_io.HEADERS_EXTRA) do table.insert(headers, header) end
  return headers
end

local sourceFailures = {}

local function sourceFailure(trail, path, reason)
  if not sourceFailures[trail.name] then
    sourceFailures[trail.name] = true
    log(ERROR, trail.type .. " custom trail missions could not be loaded.")
  end
  if reason ~= nil then
    log(WARNING, string.format("%s trail source %s: %s; the game's own missions are used",
      trail.type, tostring(path), tostring(reason)))
  end
end

local function readTrailSource(config, trail)
  local options = config[trail.key]
  if options == nil then return end
  if type(options) ~= "table" then
    log(ERROR, trail.type .. " trail settings must be an object.")
    return
  end
  local path = configuredPath(options.source, trail.type .. " trail source")
  local legacy = path == nil or path == ""
  local settingsPath, csvPath
  if legacy then
    -- Accept old profile keys for one release.
    settingsPath = configuredPath(options.settings, trail.type .. " legacy trail settings")
    csvPath = configuredPath(options.csv, trail.type .. " legacy trail CSV")
  elseif type(path) == "string" and path:lower():match("%.csv$") then
    csvPath = path
  elseif type(path) == "string" and path:lower():match("%.json$") then
    settingsPath = path
  else
    log(WARNING, trail.type .. " trail source must end in .csv or .json; the game's own missions are used.")
    return
  end

  if settingsPath ~= nil and settingsPath ~= "" then settingsPath = settingsModule.resolveRelative("", settingsPath) end
  if csvPath ~= nil and csvPath ~= "" then csvPath = settingsModule.resolveRelative("", csvPath) end
  if not legacy then path = settingsPath or csvPath end

  local settings, csvText, jsonRows
  if type(settingsPath) == "string" and settingsPath ~= "" then
    settings = settingsModule.load(settingsPath, trail.name, not legacy)
    if settings == nil and not legacy then
      sourceFailure(trail)
      return
    end
  end
  if settings ~= nil then
    if route.hasFiles(settings.route) and not readRouteFiles(trail, settings) then
      if not legacy then
        sourceFailure(trail)
        return
      end
      settings.route, settings.missions = nil, nil
    end
    local missions = settings.missions
    if missions ~= nil then
      csvPath = missions.csv
      if missions.mode ~= "csv" then
        local ok, result, rows = pcall(sync.run, missions, settings.hasAiMapping and settings.aiMapping or nil,
          knownHeaders(), legacy)
        if ok then
          csvText = result
          if not legacy then jsonRows = rows end
        else
          if not legacy or missions.mode == "json_folder" then
            sourceFailure(trail, settingsPath, result)
            if legacy then return settings end
            return
          end
          log(WARNING, string.format("%s trail source %s: %s",
            trail.type, tostring(settingsPath), tostring(result)))
        end
      end
    end
  end

  local sourcePath = legacy and (csvText and settingsPath or csvPath) or path
  if type(sourcePath) ~= "string" or sourcePath == "" then return settings end
  local plannedCount = settings and settings.positions and #settings.positions or patches.VANILLA_COUNT[trail.name]
  local ok, entries, reason = pcall(cst_io.readCSV, sourcePath, plannedCount + 1, csvText, not legacy, jsonRows)
  if not ok or entries == nil or #entries == 0 then
    sourceFailure(trail, sourcePath, ok and (reason or "no mission rows") or entries)
    if legacy then return settings end
    return
  end
  return settings, entries, sourcePath
end

local function missionOptions(trailEntries, trailSettings)
  local requested = {}
  for trailName, entries in pairs(trailEntries) do
    local settings = trailSettings[trailName]
    if settings ~= nil then
      requested.names = requested.names or settings.textFiles ~= nil
      requested.description = requested.description or settings.textFiles ~= nil
    end
    for _, entry in ipairs(entries) do
      requested.scenarios = requested.scenarios or scenario.isScenario(entry)
      requested.limits = requested.limits or (entry.unit_limit ~= nil and entry.unit_limit ~= "")
      requested.lord = requested.lord or (entry.player1_lord ~= nil and entry.player1_lord ~= "")
      requested.troops = requested.troops or tonumber(entry.player1_skip_start_units) == 1
      requested.mode = requested.mode or entry.start_levels ~= nil
      for field, value in pairs(entry) do
        if value ~= "" then
          if field:match("^player%d_name$") then requested.names = true end
          if field:match("^text_description_line_") then requested.description = true end
          if field:match("^gold_player_") then requested.gold = true end
          if field:match("^producible_") then requested.production = true end
          if field:match("^recruitable_") then requested.recruitment = true end
          if field:match("^tradeable_") then requested.trade = true end
          if field:match("^resources?_") then requested.goods = true end
        end
      end
    end
  end
  return requested
end

return {
  enable = function(self, config)
    config = config or {}
    local strict
    if config.csv ~= nil then
      if type(config.csv) ~= "table" then
        log(ERROR, "Trail CSV options must be an object.")
      elseif config.csv.strict_format ~= nil and type(config.csv.strict_format) ~= "boolean" then
        log(ERROR, "Trail CSV strict_format must be a boolean.")
      else
        strict = config.csv.strict_format == true
      end
    end
    cst_io.setStrict(strict == true)
    settingsModule.setStrict(strict)
    textsModule.setStrict(strict)

    -- trail settings files: mission count and positions, start years, texts, visuals, progress
    local trailSettings = {}
    local trailEntries, sourcePaths, missionTables = {}, {}, {}
    local routes = {}
    local missionCounts = {}
    local startYears = {}
    for _, trail in ipairs(TRAILS) do
      local okSource, settings, entries, sourcePath = pcall(readTrailSource, config, trail)
      if not okSource then
        sourceFailure(trail, nil, settings)
      else
        trailSettings[trail.name], trailEntries[trail.name], sourcePaths[trail.name] = settings, entries, sourcePath
      end
    end
    if next(trailSettings) == nil and next(trailEntries) == nil then return end

    local extremePositions = trailSettings.extremeTrail and trailSettings.extremeTrail.positions
    local expandsExtreme = extremePositions ~= nil and #extremePositions > patches.VANILLA_COUNT.extremeTrail
    if next(trailEntries) ~= nil or expandsExtreme then
      local applied, tables = patches.apply("Custom trail mission tables", function()
        local site, first, extreme, warchest = patches.extract("8D ? I(? ? ? ?) 75 08 8D ? I(? ? ? ?) EB 0B 83 F9 01 75 06 8D ? I(? ? ? ?) 53")
        if site == nil or first == nil or extreme == nil or warchest == nil then return false end
        return { firstEditionTrail = first, warchestTrail = warchest, extremeTrail = extreme }
      end)
      if applied then
        missionTables = tables
      else
        trailEntries = {}
      end
    end
    if next(trailEntries) ~= nil then
      if patches.apply("Custom trail mission context", memory.bindMissionContext) then
        for _, trail in ipairs(TRAILS) do
          if trailEntries[trail.name] ~= nil then
            local bound = patches.apply(trail.type .. " trail selected mission", function()
              return memory.bindProgress(trail.name) ~= nil
            end)
            if not bound then trailEntries[trail.name] = nil end
          end
        end
      else
        trailEntries = {}
      end
    end

    for _, trail in ipairs(TRAILS) do
      local settings = trailSettings[trail.name]
      missionCounts[trail.name] = patches.VANILLA_COUNT[trail.name]
      if settings ~= nil then
        patches.apply(trail.type .. " trail artwork", visuals.applyVisuals, trail.name, settings.visuals)
        -- A source path is recorded only when its mission rows were loaded.
        if (sourcePaths[trail.name] ~= nil and trailEntries[trail.name] == nil)
            or (trail.name == "extremeTrail" and expandsExtreme and missionTables[trail.name] == nil) then
          trailSettings[trail.name], settings = nil, nil
        end
      end
      if settings ~= nil then
        if settings.positions ~= nil then
          local applied, missionTable = patches.apply(trail.type .. " trail mission layout",
            patches.setMissionLayout, trail.name, settings.positions, missionTables[trail.name])
          if applied then
            missionCounts[trail.name] = #settings.positions
            if type(missionTable) == "number" then missionTables[trail.name] = missionTable end
          end
          -- Extreme missions past the game's 20 have no name in the game's texts; a csv
          -- line's mission_name replaces this one
          for index = patches.VANILLA_COUNT[trail.name] + 1, missionCounts[trail.name] do
            local modifier = modules.textResourceModifier
            if modifier.SetText ~= nil then
              modifier:SetText(0xF5, 0x51 + (index - 1), string.format("Mission %d", index))
            end
          end
        end
        startYears[trail.name] = settings.startingYear
        if settings.id ~= nil then
          patches.apply(trail.type .. " trail progress", function()
            if memory.bindProgress(trail.name) == nil then return false end
            return progress.install(trail.name, stateFile("progress", settings), missionCounts[trail.name])
          end)
        end
        local okRoute, sides = pcall(installRoute, trail, settings, missionCounts[trail.name])
        if not okRoute then
          log(ERROR, trail.type .. " trail progression could not be applied.")
          log(WARNING, string.format("%s trail route: %s", trail.type, tostring(sides)))
          sides = nil
        end
        routes[trail.name] = sides
        local pictures = false
        if settings.visuals.iconSheet ~= nil then
          local okMarkers, installed = pcall(markers.install, trail.name, settings.visuals.iconSheet,
            missionCounts[trail.name], sides)
          if not okMarkers then
            log(WARNING, tostring(installed))
          end
          if not (okMarkers and installed) then
            log(ERROR, trail.type .. " trail door pictures are off.")
          end
          pictures = okMarkers and installed
        end
        if not pictures then
          progress.withoutPictures(trail.name, sides)
        end
        if settings.hasAiMapping then
          interface.setAiAliases(trail.name, settings.aiMapping)
        end
      end
    end
    patches.apply("Custom trail starting years", patches.setStartYears, startYears)

    for trailName, entries in pairs(trailEntries) do
      for index = #entries, missionCounts[trailName] + 1, -1 do
        entries[index] = nil
      end
    end
    local requested = missionOptions(trailEntries, trailSettings)
    if next(trailEntries) ~= nil then
      if requested.production then patches.apply("Trail weapon production", producibility.enable) end
      if requested.recruitment then patches.apply("Trail recruitment", memory.bindRecruitability) end
      local trade = requested.trade and patches.apply("Trail tradeability", tradeability.enable)
      if requested.troops then
        patches.apply("Custom starting troops in trail missions", memory.bindExtra, "STARTING_TROOPS")
      end
      if requested.goods then
        patches.apply("Custom starting goods in trail missions", memory.bindExtra, "START_GOODS")
      end
      local lord = requested.lord and patches.apply("Custom player lord type in trail missions", patches.bindLord)
      if requested.names or memory.WEAPON_PRODUCIBLE or memory.EURO_RECRUITABLE
          or trade or memory.STARTING_TROOPS or lord then
        patches.apply("Custom trail mission setup", insertPostSkirmishSetupDetour)
      end
      if memory.START_GOODS or lord then
        patches.apply("Custom trail starting goods and lord setup", insertStartGoodsDetour)
      end
      local showDescription = requested.description or requested.scenarios
      if showDescription or lord then
        patches.apply("Custom trail briefing setup", detourSwitchToMenu, showDescription)
      end
      if requested.names or lord then
        patches.apply("Custom player names and lord type in trail missions", hookPlayerNaming, requested.names)
      end
      if requested.gold or requested.scenarios then
        startgold.enable(requested.gold, requested.scenarios)
      end
      if requested.mode then patches.apply("Custom starting mode pictures", patches.showStartModeIcons) end
      patches.apply("The team separator in trail briefings", patches.separateBriefingTeams)
    end
    -- after the routes have read their files from the user data folder (their afterInit callbacks)
    hooks.registerHookCallback("afterInit", function()
      local chickenBudgets = {}
      for index, trailName in pairs(memory.TRAIL_TYPES) do
        local settings = trailSettings[trailName]
        local budget = settings and settings.chickens
        -- the chickens of the route's rewards won so far
        local r = routes[trailName]
        if r ~= nil and r.rewards and budget ~= "unlimited" then
          budget = math.min((budget or patches.NATIVE_CHICKENS) + r:earnedChickens(), 2147483647)
        end
        -- One more than the number of rows keeps a chicken available after every possible skip.
        chickenBudgets[index] = budget == "unlimited" and patches.CAPACITY[trailName] + 1 or budget
      end
      patches.apply("Custom trail chicken budgets", patches.setChickenBudgets, chickenBudgets)

      local maps
      for trailName, entries in pairs(trailEntries) do
        local settings = trailSettings[trailName]
        applyMapOverrides(trailName, entries, settings and settings.missionKeys)
        for _, entry in ipairs(entries) do
          if entry.map_name ~= nil and entry.map_name ~= "" then
            maps = true
            break
          end
        end
      end
      local _, startInstalled = scenario.enable(function(trailName) return REGISTRY[trailName] end,
        requested.scenarios, maps, requested.limits)

      local language = data.version.getGameLanguage() or ""

      for _, trail in ipairs(TRAILS) do
        local trailSettingsForTexts = trailSettings[trail.name]
        -- the game language's text file, if the trail settings file names one
        local languageTexts = nil
        if trailSettingsForTexts ~= nil then
          local textFile = textsModule.fileFor(trailSettingsForTexts.textFiles, language)
          if textFile ~= nil then
            languageTexts = textsModule.load(textFile)
            if languageTexts ~= nil then
              log(INFO, string.format("%s trail texts (%s): %s", trail.type, language, textFile))
            end
          elseif trailSettingsForTexts.textFiles ~= nil then
            log(INFO, string.format("no %s text file for the %s trail; the default texts are shown",
              language, trail.type))
          end
          LOCKED_TEXTS[trail.name] = (languageTexts and languageTexts.lockedText) or trailSettingsForTexts.lockedText
          patches.apply(trail.type .. " trail title and summary", menutext.apply, trail.name,
            (languageTexts and languageTexts.title) or trailSettingsForTexts.title,
            (languageTexts and languageTexts.summary) or trailSettingsForTexts.summary)
        end
        local entries, path = trailEntries[trail.name], sourcePaths[trail.name]
        if entries ~= nil then
          log(INFO, string.format("%s trail (%s): %s", trail.type, language, path))
          local okTrail, trailError = pcall(applyTrail, trail.name, entries, missionTables[trail.name],
            languageTexts, startInstalled, trailSettingsForTexts and trailSettingsForTexts.missionKeys)
          if not okTrail then sourceFailure(trail, path, trailError) end
        end
      end

      for trailName, overrides in pairs(MAP_OVERRIDES) do
        if next(overrides) ~= nil then
          log(WARNING, string.format("setMissionMap: %s has no mission data of its own; "
            .. "its maps are not changed", trailName))
        end
      end

      unitlimits.apply(REGISTRY, scenario.session(), scenario.isPlayedMission)

    end)
  end,
  disable = function(self, config) end,
  getTrailProgress = function(self, trail)
    if patches.TRAIL_INDEX[trail] == nil then
      error(string.format("no such trail: %s", trail))
    end
    
    local address = memory.bindProgress(trail)
    if address ~= nil then return core.readInteger(address) end
    log(ERROR, trail .. " progress could not be read.")
  end,
  setTrailProgress = function(self, trail, progress)
    if patches.TRAIL_INDEX[trail] == nil then
      error(string.format("no such trail: %s", trail))
    end
    
    local address = memory.bindProgress(trail)
    if address == nil then
      log(ERROR, trail .. " progress could not be changed.")
      return
    end
    core.writeInteger(address, progress)
  end,
  ---A plugin gives mission `mission` (1, 2, ..., or a node id of a route of mission files) of a
  ---trail ("First", "Warchest" or "Extreme") another map file, for example the map in the language
  ---a player chose. Call it while extensions are enabled; it applies when the trail's missions are
  ---loaded.
  setMissionMap = function(self, trailType, mission, mapName)
    local trailName = settingsModule.TRAIL_TYPES[trailType]
    if trailName == nil then
      error(string.format("no such trail: %s", tostring(trailType)))
    end
    local index = type(mission) == "string" and mission ~= "" and mission or math.tointeger(mission)
    if index == nil or (type(index) == "number" and index < 1) or type(mapName) ~= "string" or mapName == "" then
      error("setMissionMap: a mission number or node id and a map name are needed")
    end
    MAP_OVERRIDES[trailName] = MAP_OVERRIDES[trailName] or {}
    MAP_OVERRIDES[trailName][index] = mapName
  end,
  setText = function(self, line, text)
    if patches.apply("Custom trail briefing descriptions", description.enable) then description.setText(line, text) end
  end,
  getStartGood = function(self, good)
    return start_goods.getStartGood(good)
  end,
  setStartGood = function(self, good, value)
    start_goods.setStartGood(good, value)
  end,
  getTradeable = function(self, resource)
    return tradeability.getTradeable(resource)
  end,
  setTradeable = function(self, resource, tradeable)
    if patches.apply("Trail tradeability", tradeability.enable) then tradeability.setTradeable(resource, tradeable) end
  end,
  setProducible = function(self, weapon, producible)
    if patches.apply("Trail weapon production", producibility.enable) then producibility.setWeaponProducible(weapon, producible) end
  end,
  getRecruitable = function(self, unit)
    return recruitability.getUnitRecruitable(unit)
  end,
  setRecruitable = function(self, unit, value)
    recruitability.setUnitRecruitable(unit, value)
  end,
  getTextDescription = function(self, index)
    return description.getText(index)
  end,
  setTextDescription = function(self, index, value)
    return description.setText(index, value)
  end,
},
{
  public = {
    "setTrailProgress",
    "setMissionMap",
    "setText",
    "setTradeable",
    "setProducible",
  }
}
