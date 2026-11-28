-- Scenario missions: a trail mission with mission_type "scenario" or "skirmish_scenario" plays a
-- custom scenario map (map type 0). "scenario" is a map made as a scenario, for example an
-- Invasion map from the editor (sync mode 0); "skirmish_scenario" is a skirmish game saved as a map
-- and then edited as a scenario (sync mode 99). Both start the way Custom Scenarios -> Play a Map
-- starts a map, so the map's events, goals, invasions, placed units and AI lords run as they do
-- from Play a Map, and the game's briefing follows. difficulty_scaling "none" skips Play a Map's
-- starting-army cut for one mission. The scenario the trail started ends as the trail's skirmish
-- mission: its end screen shows the skirmish statistics, and leaving it returns to the trail map
-- through the game's own trail code, which advances the trail after a win.
--
-- The trail's Start records which mission it started (the session): its trail, number and map.
-- The session holds while that map is played in this run of the game, through Restart and loaded
-- saves of it; the next trail Start, opening the Play a Map list or loading a save of another map
-- (or one that names no map) ends it. A save of another game on the same map, loaded while the session holds, counts as the
-- session's mission. A skirmish_scenario is also the game's trail mission once its map is loaded,
-- so Restart, its saves, its troop limit and its win go by the game's trail state as well. The
-- sync mode the map loads with is checked against the mission_type.
--
-- Every game site is found by an AOB that matches once in Stronghold Crusader.exe and
-- Stronghold_Crusader_Extreme.exe 1.41, with the same layout in both. If one is missing or
-- has unexpected bytes, scenario missions are switched off and start nothing.

local patches = require("customskirmishtrails.patches")
local memory = require("customskirmishtrails.memory")
local unitlimits = require("customskirmishtrails.unitlimits")
local description = require("customskirmishtrails.description")

local scenario = {}

-- addresses only
local SCANS = {
  -- the Play a Map launcher (cdecl, one int): any value but 0 loads the map named in the chosen
  -- map name, and every value but 1 opens the briefing afterwards for an Invasion map
  launcher = "81 EC E8 07 00 00 A1 ? ? ? ? 33 C4 89 84 24 E4 07 00 00 53 55 56 8B 35 ? ? ? ? 57 BF 01 00 00 00 6A 04 B9",
  -- the Custom Scenarios menu's click handler (cdecl, one int); 4 is Play a Map
  customScenarios = "8B 44 24 04 83 C0 FF 83 F8 04 0F 87 ? ? ? ? FF 24 85 ? ? ? ? 6A 09 B9",
  -- Play a Map's starting-army cut: "cmp eax, 3 / jne / cmp [difficulty], ebx / je skip / call
  -- mapHasCertainEvent". Unless the difficulty is the lowest or the map has an invasion event,
  -- it deletes every 4th (Normal) of the human player's military units until about a quarter of
  -- their troop value is gone.
  armyCut = "83 F8 03 0F 85 ? ? ? ? 39 1D ? ? ? ? 0F 84 ? ? ? ? B9 ? ? ? ? E8 ? ? ? ? 85 C0 0F 85",
  -- the Play a Map list's DoEveryFrame
  listFrame = "81 EC F8 03 00 00 A1 ? ? ? ? 33 C4 89 84 24 F4 03 00 00 A1 ? ? ? ? 2B 05 ? ? ? ? 53 99 55 2B C2 56",
  -- the Load Game button's read of the save: "push / mov ecx / mov [callback], / call read"; after
  -- it the chosen map holds the save's map name. Map Extensions replaces the call with a jump, so
  -- its opcode is any byte, and its own pattern reaches up to SAVE_LOADED_OFFSET, the "mov [x],
  -- ebx" this module hooks.
  saveRead = "68 ? ? ? ? B9 ? ? ? ? C7 05 ? ? ? ? ? ? ? ? ? ? ? ? ? B9 ? ? ? ? 89 2D ? ? ? ? 89 1D ? ? ? ? 89 1D",
  -- the end screens' Prepare (cdecl, no arguments): the mission finished screen's and the game
  -- lost screen's
  wonPrepare = "81 EC 04 01 00 00 A1 ? ? ? ? 33 C4 89 84 24 00 01 00 00 53 FF 15 ? ? ? ? 2B 05 ? ? ? ? 33 DB 83 3D ? ? ? ? 01 A3",
  lostPrepare = "53 FF 15 ? ? ? ? 2B 05 ? ? ? ? 33 DB 53 6A FF B9 ? ? ? ? A3 ? ? ? ? 89 1D ? ? ? ? 89 1D ? ? ? ? 89 1D ? ? ? ? 88 1D",
}
-- with operands
local EXTRACTS = {
  -- inside Custom Scenarios' Play a Map case: "mov byte [chosenMap], 0" and "mov [difficulty], eax"
  playAMap = "C7 05 ? ? ? ? 03 00 00 00 89 35 ? ? ? ? C6 05 I(? ? ? ?) 00 A3 I(? ? ? ?)",
  -- the Play a Map list's Prepare (cdecl, no arguments): it resets the game for Play a Map when
  -- opened from the menu, including the single-player game mode and the human player's slot
  listPrepare = "53 33 DB 83 C8 FF 39 1D ? ? ? ? 89 1D ? ? ? ? 89 1D ? ? ? ? A3 ? ? ? ? 89 1D I(? ? ? ?)"
    .. " C7 05 ? ? ? ? 02 00 00 00 74 61 68 80 38 01 00 53 68 ? ? ? ? 89 1D ? ? ? ?"
    .. " C7 05 ? ? ? ? 01 00 00 00 C7 05 I(? ? ? ?) 01 00 00 00 89 1D ? ? ? ? A3 ? ? ? ?"
    .. " A3 ? ? ? ? 88 1D ? ? ? ?",
  -- in the Play a Map list's DoEveryFrame, once it has faded out after the launcher: "mov
  -- [menuSwitchDelay], 0", then "cmp [reparse], 0": on its first frame the list reads the maps,
  -- selects the chosen map's row and empties the chosen map
  listFaded = "C7 05 ? ? ? ? 20 00 00 00 89 1D I(? ? ? ?) 39 1D I(? ? ? ?) 0F 84",
  -- Restart of a Play a Map game: "mov [currentMenuView], 0x31 / call ResetSomeValues (cdecl, no
  -- arguments)", then the launcher with 1
  restart = "C7 05 I(? ? ? ?) 31 00 00 00 E8 I(? ? ? ?) 0F B7 05",
  -- FilePackager::readMapOrSavFile reads the map's description: "read(file, flag, 4)", "read(file,
  -- index, 4)", then it decodes the text into the text buffer. The game's briefings show the
  -- buffer while the flag is 0, and the index's text otherwise.
  description = "6A 04 68 I(? ? ? ?) 57 E8 ? ? ? ? 6A 04 68 ? ? ? ? 57 E8 ? ? ? ? 8B 44 24 28 8B 4C 24 2C"
    .. " 83 C0 F8 50 51 57 E8 ? ? ? ? 8B 54 24 38 83 C4 24 68 I(? ? ? ?) 52 B9",
}

-- the map header reader (thiscall, one int) of the screens that preview a map or a save: it copies
-- the map name stored in the file into the chosen map. Loading a save reads the file elsewhere.
local HEADER = "81 EC 58 04 00 00 A1 ? ? ? ? 33 C4 89 84 24 54 04 00 00 53 33 DB 39 9C 24 60 04 00 00 55"
  .. " 8B E9 89 5C 24 0C 74 2C 68 A0 86 01 00 E8"
local HEADER_SIZE = 6 -- sub esp, 0x458

local ARMY_CUT_JE_OFFSET = 0x0F
local RESTART_CALL_END = 15 -- the end of the restart AOB's call, from which its operand counts
local TRAIL_BRIEFING_VIEW = 0x38 -- the trail's mission briefing (CrusadeMissionIntro)
local RESTART_VIEW = 0x31
local SAVE_LOADED_OFFSET = 0x2A
local SAVE_LOADED_SIZE = 6
local DESCRIPTION_SIZE = 1000 -- the text buffer, with its final 0

-- The end screens' Prepare reads the game mode: the mission finished screen's skips Play a Map's
-- score file for a skirmish ("cmp [gameMode], 3 / je"), the game lost screen's picks the campaign's
-- video for mode 0 ("cmp [gameMode], ebx / jne").
local WON_PREPARE_SIZE = 6  -- sub esp, 0x104
local LOST_PREPARE_SIZE = 7 -- push ebx / call [import]
local WON_PREPARE_MODE = { offset = 0x288, bytes = "83 3D ? ? ? ? 03 74" }
local LOST_PREPARE_MODE = { offset = 0xED, bytes = "39 1D ? ? ? ? 75" }
-- In the mission finished screen's DoEveryFrame ("win" in patches.lua) a skirmish shows its
-- statistics until the player leaves them; then the branch that picks the follow-up by game mode
-- takes the game's trail branch, which credits a win and opens the trail map. The values the trail
-- branch reads follow.
local WIN_BRANCH_SITE = { fn = "win", offset = 0xEF, bytes = "A1 ? ? ? ? 3B C7 0F 85" }   -- mov eax, [gameMode]
local WIN_SYNC_MODE_SITE = { fn = "win", offset = 0xFC, bytes = "A1 ? ? ? ? 83 F8 63 0F 85" } -- mov eax, [syncMode]; cmp eax, 99
local WIN_WINNERS_SITE = { fn = "win", offset = 0x1B0, bytes = "A1 ? ? ? ? 66 39 2C 45 ? ? ? ?" } -- mov eax, [humanSlot]; cmp word [eax*2 + winners], bp

local GAME_MODE_SCENARIO = 2 -- custom scenario (Play a Map)
local GAME_MODE_SKIRMISH = 3
local SYNC_MODE_SINGLE_PLAYER = 0
local SYNC_MODE_SKIRMISH = 99
local PLAY_A_MAP = 4
local LAUNCH_WITH_BRIEFING = 2
local LAUNCH_RESTART = 1
local DIFFICULTY_NORMAL = 1
local MAX_PLAYERS = 8
-- The game resolves "maps\<name>.map" and "<Documents>\Stronghold Crusader\Maps\<name>.map"
-- into 1001-byte path buffers, so names stay well below that.
local MAX_MAP_NAME = 200
local NAME_BUFFER = MAX_MAP_NAME + 1
local MAP_RESOURCE = 15
local RESOURCE_PATH_SIZE = 1001
local RESOURCE_TYPE_OFFSET = 0xBC4
local MAP_PATH_OFFSET = 0x7AEE0 + MAP_RESOURCE * RESOURCE_PATH_SIZE

-- Map body section 1124 (uncompressed): the AI lord of each slot (dwords from +0x84, slot 0
-- first; 0 is none) and each slot's team (bytes from +0x62 for slots 1 .. 8; -1 unused, 0 none).
-- The file layout before the sections is sourcehold-maps'.
local LORDS_SECTION = 1124
local LORDS_AI_OFFSET = 0x84
local LORDS_TEAM_OFFSET = 0x62
local LORDS_SIZE = LORDS_AI_OFFSET + 4 * (MAX_PLAYERS + 1)
local MAP_HEADER_BLOCKS = 5 -- description and U1 .. U4, each a size and its data
local MAP_DIRECTORY_SLOTS = { old = 100, new = 150, newFrom = 161 }
local OPEN_READ_BINARY = 0x8000

local bindings = nil
local mapLookup = nil
local mapReader = nil -- { open, read, seek, close, path, buffer } once the map lookup is bound
local trailOf = nil -- function(trailName) -> missions of that trail, set by enable
local active = nil  -- the session: { trailName, index, entry, fileName }

local function asciiLower(text)
  return (text:gsub("[A-Z]", string.lower))
end

---The file name of a scenario map as the game's file functions spell it, or nil and a reason.
---Map files in the game's folders have Windows code page names; a UTF-8 name from a csv,
---mission or plugin file is written in its Latin-1 form, the same rule the files module uses for
---availability.json. A trailing ".map" is dropped, because the launcher adds it.
function scenario.mapFileName(name, skirmish)
  if type(name) ~= "string" then
    return nil, "no map name"
  end
  if not skirmish and name:lower():sub(-4) == ".map" then
    name = name:sub(1, -5)
  end
  if name == "" or name:find("[%c/\\:*?\"<>|]") then
    return nil, "not a map file name"
  end
  if not skirmish and name:find("[\128-\255]") and utf8 ~= nil and utf8.len(name) ~= nil then
    local bytes = {}
    for _, codepoint in utf8.codes(name) do
      if codepoint > 255 then
        return nil, "letters outside Latin-1"
      end
      bytes[#bytes + 1] = string.char(codepoint)
    end
    name = table.concat(bytes)
  end
  if #name > MAX_MAP_NAME then
    return nil, string.format("longer than %d bytes", MAX_MAP_NAME)
  end
  return name
end

local MISSION_TYPES = { skirmish = true, scenario = true, skirmish_scenario = true }
local DIFFICULTY_SCALINGS = { vanilla = true, none = true }
-- the sync mode the map of each scenario mission_type loads with
local TYPE_SYNC_MODE = { scenario = SYNC_MODE_SINGLE_PLAYER, skirmish_scenario = SYNC_MODE_SKIRMISH }

---`entry[field]` in lower case (`default` when empty), or nil for a value not in `known`.
local function choice(entry, field, known, default)
  local value = type(entry) == "table" and entry[field] or nil
  if value == nil or value == "" then
    return default
  end
  value = type(value) == "string" and asciiLower(value:match("^%s*(.-)%s*$")) or nil
  return known[value] and value or nil
end

---The mission_type ("skirmish" when empty), or nil for a type this version doesn't know.
function scenario.missionType(entry)
  return choice(entry, "mission_type", MISSION_TYPES, "skirmish")
end

---The difficulty_scaling ("vanilla" when empty), or nil for a value this version doesn't know.
function scenario.difficultyScaling(entry)
  return choice(entry, "difficulty_scaling", DIFFICULTY_SCALINGS, "vanilla")
end

---True when `entry` starts as Play a Map starts a map (mission_type scenario or skirmish_scenario).
function scenario.isScenario(entry)
  return TYPE_SYNC_MODE[scenario.missionType(entry)] ~= nil
end

---Whether a scenario mission's map can be played today, and the date it opens when it is dated
---in an availability.json of the files module. Dates come with files 1.5.0
---(getMapAvailability); without that function no map is dated. A failing lookup counts as not
---open yet.
function scenario.availability(entry)
  local files = modules.files
  if files == nil or files.getMapAvailability == nil then
    return true, nil
  end
  local game = data.version.isExtreme() and "extreme" or "crusader"
  local ok, result = pcall(function() return files:getMapAvailability(entry.map_name, game) end)
  if not ok or type(result) ~= "table" or type(result.available) ~= "boolean" then
    log(WARNING, string.format("map availability of %s: %s", tostring(entry.map_name),
      tostring(ok and "no answer" or result)))
    return false, nil
  end
  return result.available, result.from
end

local function resolve()
  local header = patches.find(HEADER)
  assert(header ~= nil, "map header reader: not found")
  local found = {}
  for name, aob in pairs(SCANS) do
    local address = patches.find(aob)
    assert(address ~= nil, "could not bind scenario " .. name .. ": not found")
    found[name] = { address = address }
  end
  for name, aob in pairs(EXTRACTS) do
    local address, a, b = patches.extract(aob)
    assert(address ~= nil, "could not bind scenario " .. name)
    found[name] = { address = address, a, b }
  end
  local branch = patches.siteAddress(WIN_BRANCH_SITE, "the mission finished screen")
  local syncModeSite = patches.siteAddress(WIN_SYNC_MODE_SITE, "the mission finished screen")
  local winnersSite = patches.siteAddress(WIN_WINNERS_SITE, "the mission finished screen")
  local jeSite = found.armyCut.address + ARMY_CUT_JE_OFFSET
  local wonMode = found.wonPrepare.address + WON_PREPARE_MODE.offset
  local lostMode = found.lostPrepare.address + LOST_PREPARE_MODE.offset
  if branch == nil or syncModeSite == nil or winnersSite == nil or not patches.matches(jeSite, "0F 84 ? ? ? ?")
      or not patches.matches(wonMode, WON_PREPARE_MODE.bytes) or not patches.matches(lostMode, LOST_PREPARE_MODE.bytes) then
    log(WARNING, "unexpected game code; scenario missions are switched off")
    return nil
  end
  local list = found.listPrepare
  local gameMode = core.readInteger(branch + 1)
  -- the list and the end screens must name the same sync mode, human slot and game mode
  if core.readInteger(syncModeSite + 1) ~= list[1] or core.readInteger(winnersSite + 1) ~= list[2]
      or core.readInteger(wonMode + 2) ~= gameMode or core.readInteger(lostMode + 2) ~= gameMode then
    log(WARNING, "the game's mode and player slot don't match; scenario missions are switched off")
    return nil
  end
  return {
    header = header,
    launcher = core.exposeCode(found.launcher.address, 1, 0),
    customScenarios = core.exposeCode(found.customScenarios.address, 1, 0),
    listPrepare = list.address,
    listFrame = found.listFrame.address,
    saveLoaded = found.saveRead.address + SAVE_LOADED_OFFSET,
    chosenMap = found.playAMap[1],
    difficulty = found.playAMap[2],
    syncMode = list[1],
    humanSlot = list[2],
    menuSwitchDelay = found.listFaded[1],
    currentView = found.restart[1],
    resetGame = core.exposeCode(found.restart.address + RESTART_CALL_END + found.restart[2], 0, 0),
    listReparse = found.listFaded[2],
    gameMode = gameMode,
    wonPrepare = found.wonPrepare.address,
    lostPrepare = found.lostPrepare.address,
    winners = core.readInteger(winnersSite + 9),
    armyCutJe = jeSite,
    armyCutSkip = jeSite + 6 + core.readInteger(jeSite + 2),
    descriptionFlag = found.description[1],
    descriptionText = found.description[2],
  }
end

---A routine (call, no arguments) that sets ZF when the chosen map is the session's map; it keeps
---every register.
local function installSameMap(b)
  local code = {
    0x50,                                    -- push eax
    0x56,                                    -- push esi
    0x57,                                    -- push edi
    0xBE, core.itob(b.trailMap),             -- mov esi, trailMap
    0xBF, core.itob(b.chosenMap),            -- mov edi, chosenMap
    "compare",
    0x8A, 0x06,                              -- mov al, [esi]
    0x3A, 0x07,                              -- cmp al, [edi]
    0x0F, 0x85, core.relTo("done", -4),      -- jne done (ZF clear)
    0x46,                                    -- inc esi
    0x47,                                    -- inc edi
    0x84, 0xC0,                              -- test al, al
    0x0F, 0x85, core.relTo("compare", -4),   -- jnz compare (at the end ZF is set)
    "done",
    0x5F,                                    -- pop edi
    0x5E,                                    -- pop esi
    0x58,                                    -- pop eax
    0xC3,                                    -- ret
  }
  b.sameMap = core.allocateCode(core.calculateCodeSize(code))
  core.writeCode(b.sameMap, code)
end

---Starting-army cut: a Play a Map start skips it when it loads the session's map and the
---session's mission has difficulty_scaling "none" (Restart of it too).
local function installArmyCutSkip(b)
  local skip = b.armyCutSkip
  core.insertCode(b.armyCutJe, 6, {
    core.jeTo(skip),
    0x80, 0x3D, core.itob(b.keepArmy), 0x00, -- cmp byte [keepArmy], 0
    0x0F, 0x84, core.relTo("cut", -4),       -- je cut
    core.callTo(b.sameMap),
    0x0F, 0x85, core.relTo("cut", -4),       -- jne cut
    core.jmpTo(skip),
    "cut",
  })
end

local function writeName(address, name)
  core.writeString(address, name)
  core.writeByte(address + #name, 0)
end

local function bindMapLookup()
  -- ResourceManager: resolve a map through the game folder and Documents. The native
  -- existence check opens through the Files module's existing redirect.
  local managerPattern = "A1 I(? ? ? ?) 89 46 74 33 C0 39 ? ? ? ? ? 7E 15"
  local resolvePattern = "83 EC 24 A1 ? ? ? ? 33 C4 89 44 24 20 53 55 8B 6C 24 34 56 8B 74 24 34"
    .. " 8D 46 FF 83 F8 12 8B D9 57 89 B3 C4 0B 00 00"
  local existsPattern = "8B 44 24 04 6A 00 68 00 80 00 00 50 E8 ? ? ? ? 83 C4 0C 83 F8 FF 75 05 33 C0 C2 04 00 50"
  local managerAddress = patches.find(patches.plain(managerPattern))
  assert(managerAddress ~= nil, "resource manager: not found")
  local resolveAddress = patches.find(resolvePattern)
  assert(resolveAddress ~= nil, "map filename resolver: not found")
  local existsAddress = patches.find(existsPattern)
  assert(existsAddress ~= nil, "map file existence check: not found")
  local _, manager = utils.AOBExtract(managerPattern, managerAddress, managerAddress)
  local resolveMap = core.exposeCode(resolveAddress, 3, 1)
  local fileExists = core.exposeCode(existsAddress, 2, 1)
  -- the existence check's "call _open": the game's open, which the Files module redirects and
  -- answers with a ucrt file descriptor
  local openCall = existsAddress + 12
  mapReader = {
    open = core.exposeCode(openCall + 5 + core.readInteger(openCall + 1), 3, 0),
    read = core.exposeCode(io.ucrt._read, 3, 0),
    seek = core.exposeCode(io.ucrt._lseek, 3, 0),
    close = core.exposeCode(io.ucrt._close, 1, 0),
    path = core.allocate(RESOURCE_PATH_SIZE, true),
    buffer = core.allocate(12 * MAP_DIRECTORY_SLOTS.new, true),
  }
  local nameBuffer = core.allocate(NAME_BUFFER + #".map", true)
  local resourceType = manager + RESOURCE_TYPE_OFFSET
  local mapPath = manager + MAP_PATH_OFFSET
  return function(name)
    writeName(nameBuffer, name .. ".map")
    local savedType = core.readInteger(resourceType)
    local savedPath = core.readBytes(mapPath, RESOURCE_PATH_SIZE)
    local ok, path = pcall(function()
      resolveMap(manager, MAP_RESOURCE, nameBuffer)
      return fileExists(manager, mapPath) == 1 and core.readString(mapPath) or nil
    end)
    core.writeBytes(mapPath, savedPath)
    core.writeInteger(resourceType, savedType)
    if not ok then error(path, 0) end
    return path
  end
end

---Reads `size` bytes of section `wanted` of the map file at `path` into mapReader.buffer. False
---when the file can't be opened, has no such section or it is compressed or shorter.
local function readMapSection(path, wanted, size)
  local r = mapReader
  writeName(r.path, path)
  local fd = r.open(r.path, OPEN_READ_BINARY, 0)
  if fd < 0 or fd == 0xFFFFFFFF then
    return false
  end
  local function at(offset, count)
    if r.seek(fd, offset, 0) ~= offset or r.read(fd, r.buffer, count) ~= count then
      error("the map file ends early")
    end
  end
  local function int(offset)
    at(offset, 4)
    return core.readInteger(r.buffer)
  end
  local ok, found = pcall(function()
    local pos = 8 + int(4) -- magic, preview
    for _ = 1, MAP_HEADER_BLOCKS do
      pos = pos + 4 + int(pos)
    end
    pos = pos + 4
    at(pos, 16)
    local directorySize, count = core.readInteger(r.buffer), core.readInteger(r.buffer + 8)
    local slots = core.readInteger(r.buffer + 12) >= MAP_DIRECTORY_SLOTS.newFrom and MAP_DIRECTORY_SLOTS.new
      or MAP_DIRECTORY_SLOTS.old
    if count < 0 or count > slots then
      return false
    end
    at(pos + 32 + 4 * slots, 12 * slots) -- lengths, section numbers, compressed flags
    local section = pos + directorySize
    for i = 0, count - 1 do
      local length = core.readInteger(r.buffer + 4 * i)
      if core.readInteger(r.buffer + 4 * (slots + i)) == wanted then
        if core.readInteger(r.buffer + 4 * (2 * slots + i)) == 1 or length < size then
          return false
        end
        at(section, size)
        return true
      end
      section = section + length
    end
    return false
  end)
  r.close(fd)
  return ok and found
end

local function signedByte(address)
  local value = core.readByte(address) & 0xFF
  return value >= 0x80 and value - 0x100 or value
end

local function isEmpty(value)
  return value == nil or value == ""
end

---A scenario mission's briefing shows the AI lords and teams of its map: player2 .. player8 and
---team1 .. team8 come from the map where the mission leaves them empty or the slot lies past
---num_players (the game ignores those columns), and num_players then counts up to the map's last
---AI lord. The scenario start doesn't use these columns.
function scenario.applyMapLords(entry, fileName)
  if mapLookup == nil or not scenario.availability(entry) then
    return
  end
  local ok, read = pcall(function()
    local path = mapLookup(fileName)
    return path ~= nil and readMapSection(path, LORDS_SECTION, LORDS_SIZE)
  end)
  if not ok or not read then
    log(VERBOSE, string.format("no lords from map %s: %s", fileName, tostring(read)))
    return
  end
  local buffer, last = mapReader.buffer, 0
  local players = math.tointeger(tonumber(entry.num_players)) or 0
  for slot = 1, MAX_PLAYERS do
    local ai = slot > 1 and core.readInteger(buffer + LORDS_AI_OFFSET + 4 * slot) or 0
    local playerColumn, teamColumn = "player" .. slot, "team" .. slot
    if slot > 1 and (slot > players or isEmpty(entry[playerColumn])) then
      entry[playerColumn] = ai
      if ai ~= 0 then
        last = slot
      end
    end
    if slot > players or isEmpty(entry[teamColumn]) then
      entry[teamColumn] = math.max(signedByte(buffer + LORDS_TEAM_OFFSET + slot - 1), 0)
    end
  end
  if last > players then
    entry.num_players = last
  end
end

---True when the mission keeps the player's whole starting army (difficulty_scaling "none").
local function keepsStartArmy(entry)
  return scenario.difficultyScaling(entry) == "none"
end

---The session, or nil when there is none or the Play a Map list ended it.
local function session()
  if active ~= nil and core.readByte(bindings.trailMap) ~= 0 then
    return active
  end
  return nil
end

---Makes `trailName` mission `index` (a scenario mission playing `fileName`) the session, or ends
---the session (no arguments).
local function setSession(trailName, index, entry, fileName)
  local b = bindings
  active = trailName and { trailName = trailName, index = index, entry = entry, fileName = fileName } or nil
  writeName(b.trailMap, active and fileName or "")
  core.writeByte(b.keepArmy, active and keepsStartArmy(entry) and 1 or 0)
  core.writeByte(b.cap, active and unitlimits.policy(entry) ~= nil and 1 or 0)
end

local TRAIL_INDEX = {}
for index, name in pairs(memory.TRAIL_TYPES) do
  TRAIL_INDEX[name] = index
end

---Makes the game's trail state name `trailName` mission `mission` as the trail mission played.
local function selectTrailMission(trailName, mission)
  core.writeInteger(memory.CURRENT_TRAIL_TYPE, TRAIL_INDEX[trailName])
  core.writeInteger(memory.TRAIL_PROGRESS_ADDRESSES[trailName], mission - 1)
  core.writeInteger(memory.IS_SKIRMISH_TRAIL, 1)
end

---Launches `mission` as the Play a Map list's Start (`how` LAUNCH_WITH_BRIEFING) or Restart
---(LAUNCH_RESTART) does: the session, the chosen map, Normal difficulty, the launcher; its next
---screen opens at once. The map of a skirmish_scenario keeps the skirmish mode and its rules (for
---example, winning when every enemy lord is dead); the game then takes it for the trail mission,
---as for a skirmish mission: Restart starts it again from the trail, and the troop limit, a win and
---its saves go by the game's trail state. A map whose sync mode doesn't match the mission_type is
---reported, and only a skirmish_scenario on a skirmish map becomes the game's trail mission.
local function launch(b, mission, how)
  setSession(mission.trailName, mission.index, mission.entry, mission.fileName)
  core.writeInteger(memory.IS_SKIRMISH_TRAIL, 0)
  writeName(b.chosenMap, mission.fileName)
  core.writeInteger(b.difficulty, DIFFICULTY_NORMAL)
  b.launcher(how)
  -- scenario_briefing: the mission's own briefing text instead of the map's description
  local briefing = mission.entry.scenario_briefing
  if type(briefing) == "string" and briefing ~= "" then
    core.writeInteger(b.descriptionFlag, 0)
    description.writeGameText(b.descriptionText, DESCRIPTION_SIZE, briefing)
  end
  local missionType = scenario.missionType(mission.entry)
  local syncMode = core.readInteger(b.syncMode)
  if syncMode ~= TYPE_SYNC_MODE[missionType] then
    log(WARNING, string.format("%s mission %d is a %s, and its map %s loads with sync mode %d",
      mission.trailName, mission.index, missionType, mission.fileName, syncMode))
  elseif missionType == "skirmish_scenario" then
    selectTrailMission(mission.trailName, mission.index)
  end
  core.writeInteger(b.menuSwitchDelay, 0)
end

-- the scenario mission the Play a Map list starts when it opens: { trailName, index, entry, fileName }
local pending = nil

local missingMapReported = {}
local function hasMap(fileName)
  if mapLookup ~= nil and mapLookup(fileName) then
    return true
  end
  if mapLookup ~= nil and not missingMapReported[fileName] then
    missingMapReported[fileName] = true
    log(ERROR, string.format("This trail mission cannot start. Map %s could not be found.", fileName))
  end
  log(WARNING, string.format("cannot find map '%s'; the mission doesn't start", fileName))
  return false
end

---Starts `trailName` mission `index` (a scenario mission playing `fileName`) as Play a Map does.
---From the trail's briefing, which loads its own mission every frame until it closes, the Custom
---Scenarios handler's Play a Map case opens the Play a Map list, whose first frame launches it.
---Restart in the game launches it as Play a Map's Restart does.
local function start(trailName, index, entry, fileName)
  local b = bindings
  local mission = { trailName = trailName, index = index, entry = entry, fileName = fileName }
  if core.readInteger(b.currentView) ~= TRAIL_BRIEFING_VIEW then
    core.writeInteger(b.currentView, RESTART_VIEW)
    b.resetGame()
    launch(b, mission, LAUNCH_RESTART)
    return
  end
  b.customScenarios(PLAY_A_MAP)
  pending = mission
end

local reportedLaunchFailures = {}

local function reportLaunchFailure(trailName, index, err)
  if trailName ~= nil then
    local mission = trailName .. ":" .. index
    if not reportedLaunchFailures[mission] then
      reportedLaunchFailures[mission] = true
      log(ERROR, string.format("Custom trail mission %d could not start.", index))
    end
  end
  log(WARNING, "starting a scenario mission failed: " .. tostring(err))
end

---The Play a Map list's first frame, after its Prepare (which ends a session), launches the
---pending mission. Then the list doesn't read the maps, which would empty the chosen map that
---Restart and saves need.
local function installListStart(b)
  core.detourCode(function(registers)
    local mission = pending
    if mission == nil then
      return registers
    end
    pending = nil
    local ok, err = pcall(function()
      launch(b, mission, LAUNCH_WITH_BRIEFING)
      core.writeInteger(b.listReparse, 0)
    end)
    if not ok then
      reportLaunchFailure(mission.trailName, mission.index, err)
      setSession()
    end
    return registers
  end, b.listFrame, 6)
end

---The trail and mission of the scenario played, or nil and the check that failed. It is the
---session's mission while the chosen map name is the session's map. Otherwise a skirmish map (sync
---99) is the trail mission the game's trail state names, when that mission is a skirmish_scenario
---playing the chosen map.
local function playedMission()
  local syncMode = core.readInteger(bindings.syncMode)
  if syncMode ~= SYNC_MODE_SINGLE_PLAYER and syncMode ~= SYNC_MODE_SKIRMISH then
    return nil, "sync " .. syncMode
  end
  local current = session()
  local chosen = core.readString(bindings.chosenMap) or ""
  if current ~= nil and chosen == current.fileName then
    return current.trailName, current.index
  end
  local sessionCheck = current == nil and "session" or string.format("name '%s' (session '%s')", chosen,
    current.fileName)
  if syncMode ~= SYNC_MODE_SKIRMISH then
    return nil, sessionCheck
  end
  local ok, isTrail, _, trailName, mission = pcall(memory.fetchCurrentTrail)
  local missions = ok and isTrail and trailOf(trailName) or nil
  local entry = missions and missions[mission] or nil
  if scenario.missionType(entry) ~= "skirmish_scenario" or not scenario.isPlayedMission(entry) then
    return nil, string.format("%s, trail %s %s mission %s map '%s'", sessionCheck, tostring(isTrail),
      tostring(trailName), tostring(mission), tostring(entry and entry.map_name))
  end
  return trailName, mission
end

local function declined(check)
  log(INFO, "end screen without trail hand-over: " .. check)
end

---Before an end screen of a trail scenario prepares (`won`: the mission finished screen, else the
---game lost screen), the game takes it for the trail's skirmish mission: the screen shows the
---skirmish statistics, and leaving it takes the game's trail branch to the trail map, which
---credits a win. That branch counts a win only when the human player's winner flag is set, which
---skirmish games set and scenarios don't.
local function handOver(b, won)
  local mode = core.readInteger(b.gameMode)
  if mode ~= GAME_MODE_SCENARIO then
    if session() ~= nil then
      declined("mode " .. mode)
    end
    return
  end
  local slot = core.readInteger(b.humanSlot)
  if slot < 1 or slot > MAX_PLAYERS then
    declined("slot " .. slot)
    return
  end
  local trailName, mission = playedMission()
  if trailName == nil then
    declined(mission)
    return
  end
  log(INFO, string.format("%s mission %d %s", trailName, mission, won and "won" or "lost"))
  selectTrailMission(trailName, mission)
  core.writeInteger(b.syncMode, SYNC_MODE_SKIRMISH)
  if won then
    core.writeSmallInteger(b.winners + 2 * slot, 1)
  end
  core.writeInteger(b.gameMode, GAME_MODE_SKIRMISH)
end

---The hand-over runs at the start of both end screens' Prepare, before it reads the game mode.
local function installEndScreens(b)
  core.detourCode(function(registers)
    handOver(b, true)
    return registers
  end, b.wonPrepare, WON_PREPARE_SIZE)
  core.detourCode(function(registers)
    handOver(b, false)
    return registers
  end, b.lostPrepare, LOST_PREPARE_SIZE)
end

---Opening the Play a Map list ends the session, and so does loading a save of another map.
local function installSessionEnd(b)
  local clear = {
    0xC6, 0x05, core.itob(b.trailMap), 0x00, -- mov byte [trailMap], 0
    0xC6, 0x05, core.itob(b.keepArmy), 0x00, -- mov byte [keepArmy], 0
    0xC6, 0x05, core.itob(b.cap), 0x00,      -- mov byte [cap], 0
  }
  core.insertCode(b.listPrepare, 6, { clear }, nil, "after")
  core.insertCode(b.saveLoaded, SAVE_LOADED_SIZE, {
    core.callTo(b.sameMap),
    0x0F, 0x84, core.relTo("keep", -4),      -- je keep
    clear,
    "keep",
  }, nil, "after")
end

---Previews of a map or a save (the trail roster, the Load screen) put the map name stored in that
---file into the chosen map that Restart, saves, the troop limit and the end screen need. While a
---session holds, they leave the chosen map as it was.
local function installHeaderKeep(b)
  local original
  original = core.hookCode(function(this, flag)
    local kept = session() ~= nil and core.readString(b.chosenMap) or nil
    local result = original(this, flag)
    if kept ~= nil then writeName(b.chosenMap, kept) end
    return result
  end, b.header, 2, 1, HEADER_SIZE)
  assert(original ~= nil, "the map header reader has no original handler")
end

---Starts `entry` (`trailName` mission `index`) when it is a scenario mission. Returns true when
---the trail's own skirmish setup must not run: the scenario started, or it can't start (switched
---off, invalid map name, not open yet, troop limit unavailable).
function scenario.startIfScenario(trailName, index, entry)
  local missionType = scenario.missionType(entry)
  if missionType == "skirmish" then
    if entry ~= nil and entry.map_name ~= nil then
      local fileName, reason = scenario.mapFileName(entry.map_name, true)
      if fileName == nil then
        log(WARNING, string.format("skirmish map '%s': %s",
          tostring(entry.map_name), reason))
        return true
      end
      if not hasMap(fileName) then return true end
    end
    if not unitlimits.available(entry, false) then
      log(WARNING, string.format("%s has a unit_limit, and the troop limit is switched off; "
        .. "the mission doesn't start", tostring(entry.map_name)))
      return true
    end
    return false
  end
  if missionType == nil then
    log(WARNING, string.format("%s: unknown mission_type '%s'; the mission doesn't start",
      tostring(entry.map_name), tostring(entry.mission_type)))
    return true
  end
  if bindings == nil then
    log(WARNING, string.format("%s is a scenario mission, and scenario missions are switched off",
      tostring(entry.map_name)))
    return true
  end
  local fileName, reason = scenario.mapFileName(entry.map_name)
  if fileName == nil then
    log(WARNING, string.format("scenario map '%s': %s; the mission doesn't start",
      tostring(entry.map_name), reason))
    return true
  end
  local available, from = scenario.availability(entry)
  if not available then
    log(INFO, string.format("%s opens on %s", fileName, tostring(from)))
    return true
  end
  if not hasMap(fileName) then return true end
  if not unitlimits.available(entry, true) then
    log(WARNING, string.format("%s has a unit_limit, and the troop limit of scenario missions "
      .. "is switched off; the mission doesn't start", fileName))
    return true
  end
  start(trailName, index, entry, fileName)
  return true
end

---True when the trail's Start can play `entry` today as far as its map goes: a valid map name,
---the date has come (scenario missions) and the map is installed. Logs nothing.
function scenario.isOpen(entry)
  local missionType = scenario.missionType(entry)
  local isScenario = scenario.isScenario(entry)
  if missionType == "skirmish" and entry.map_name == nil then
    return true
  end
  if missionType == nil or (isScenario and bindings == nil) or mapLookup == nil then
    return false
  end
  local fileName = scenario.mapFileName(entry.map_name, not isScenario)
  if fileName == nil or (isScenario and not scenario.availability(entry)) then
    return false
  end
  local ok, path = pcall(mapLookup, fileName)
  return ok and path ~= nil
end

---The mission as its briefing shows it: a scenario mission that isn't open yet shows
---`lockedText` ({date} becomes the date it opens) instead of its description. Asking files also
---gives a dated map that is due its file redirect, which the trail's Start needs to find the map.
function scenario.briefingEntry(entry, lockedText)
  if not scenario.isScenario(entry) then
    return entry
  end
  local available, from = scenario.availability(entry)
  if available or type(lockedText) ~= "string" then
    return entry
  end
  local shown = {}
  for key, value in pairs(entry) do
    shown[key] = value
  end
  local text = lockedText:gsub("{date}", function() return tostring(from or "") end)
  for line = 1, 8 do
    shown[string.format("text_description_line_%02d", line)] = line == 1 and text or ""
  end
  return shown
end

---The trail's Start (SetupSkirmishMode, cdecl, the selected mission's index): scenario missions
---start as above, every other mission runs the game's skirmish setup.
local function installStartHook()
  local setup = patches.functionAddress("setup")
  if setup == nil or not patches.matches(setup, "8B 44 24 04 8B 0D ? ? ? ?") then
    return false
  end
  local original
  local function onStart(index)
    local trailName = memory.TRAIL_TYPES[core.readInteger(memory.CURRENT_TRAIL_TYPE)]
    local missions = trailName and trailOf(trailName) or nil
    local entry = missions and missions[index + 1] or nil
    pending = nil
    if active ~= nil then
      setSession()
    end
    local ok, handled = pcall(scenario.startIfScenario, trailName, index + 1, entry)
    if not ok then
      reportLaunchFailure(entry ~= nil and trailName or nil, index + 1, handled)
      if bindings ~= nil then setSession() end
      return 0
    end
    if handled then
      return 0
    end
    return original(index)
  end
  patches.guarded({ { address = setup, size = 10 } }, function()
    original = core.hookCode(onStart, setup, 1, 0, 10)
    assert(original ~= nil, "the trail's Start has no original handler")
  end)
  return true
end

---Installs scenario missions. `missionsOf(trailName)` gives a trail's missions (1-based).
---Returns true when they can be played and whether the Start hook was installed.
function scenario.enable(missionsOf, scenarios, maps, limits)
  if not (scenarios or maps or limits) then return true, false end
  trailOf = missionsOf
  if maps or scenarios then
    local found, lookup = patches.apply("Custom trail map lookup", bindMapLookup)
    if found then mapLookup = lookup end
  end
  local ready, result
  if scenarios and mapLookup ~= nil then
    ready, result = patches.apply("Scenario trail missions", function()
      return resolve() or false
    end)
  end
  -- The Start hook also stops an unavailable custom mission from running as a skirmish.
  local started = patches.apply("Custom trail Start control", installStartHook)
  if not started or not ready then return false, started end
  local installed = patches.apply("Scenario trail missions", function()
    result.trailMap = core.allocate(NAME_BUFFER, true)
    result.keepArmy = core.allocate(1, true)
    result.cap = core.allocate(1, true)
    local sites = {
      { address = result.header, size = HEADER_SIZE },
      { address = result.armyCutJe, size = 6 },
      { address = result.listPrepare, size = 6 },
      { address = result.saveLoaded, size = SAVE_LOADED_SIZE },
      { address = result.listFrame, size = 6 },
      { address = result.wonPrepare, size = WON_PREPARE_SIZE },
      { address = result.lostPrepare, size = LOST_PREPARE_SIZE },
    }
    patches.guarded(sites, function()
      installSameMap(result)
      installHeaderKeep(result)
      installArmyCutSkip(result)
      installSessionEnd(result)
      installEndScreens(result)
      installListStart(result)
    end)
  end)
  if not installed then return false, true end
  bindings = result
  return true, true
end

---False when `entry` is a scenario mission whose map isn't the chosen map (a save from before the
---mission got another map, for example) or can't be checked (scenario missions switched off);
---true for a scenario mission playing it and for any other mission.
function scenario.isPlayedMission(entry)
  if not scenario.isScenario(entry) then
    return true
  end
  return bindings ~= nil and scenario.mapFileName(entry.map_name) == core.readString(bindings.chosenMap)
end

---The session for the troop limit, or nil when scenario missions are switched off: the addresses
---of the routine "the chosen map is the session's" (sameMap), the game mode and the flag "the
---session's mission has a troop limit", and entry() for the session's mission.
function scenario.session()
  if bindings == nil then
    return nil
  end
  return {
    sameMap = bindings.sameMap,
    gameMode = bindings.gameMode,
    cap = bindings.cap,
    entry = function()
      local current = session()
      return current and current.entry or nil
    end,
  }
end

return scenario
