-- Trail visuals and texts from the trail settings file: the trail's button in the skirmish
-- menu (idle and highlighted picture), the trail screen's background and buttons, and the
-- trail's title and summary under the button.

local memory = require("customskirmishtrails.memory")
local patches = require("customskirmishtrails.patches")
local tgx = require("customskirmishtrails.tgx")
local cst_io = require("customskirmishtrails.io")

local visuals = {}
local backgroundTgx

-- The skirmish menu's trail buttons are image buttons: the idle picture is the frame shown,
-- the highlighted one the next frame. Stronghold Crusader shows the first and the Warchest
-- trail, Crusader Extreme only the Extreme trail. Frames are 0-based.
local BUTTON_FRAMES = {
  crusader = {
    firstEditionTrail = { gm = 46, idle = 667, highlighted = 668 },  -- interface_icons2
    warchestTrail = { gm = 46, idle = 758, highlighted = 759 },      -- interface_icons2
  },
  extreme = {
    extremeTrail = { gm = 156, idle = 305, highlighted = 306 },      -- interface_icons3
  },
}

-- The trail screen's buttons, the same for all trails and in both game versions: gm and idle
-- frame (0-based) of each; the highlighted picture, shown under the mouse, is the next frame.
local SCREEN_BUTTONS = {
  chicken = { gm = 206, frame = 0 },          -- super chicken
  skirmishMasters = { gm = 46, frame = 756 }, -- interface_icons2
  back = { gm = 150, frame = 68 },            -- icons_front_end_combat
  next = { gm = 150, frame = 70 },            -- icons_front_end_combat
}
-- RenderCurrentMenuView calls the prepare function of the menu view that opens:
-- "mov eax, [esi + 0xC] / call eax", the view in ESI. The trail screen's prepare is "open".
local VIEW_PREPARE_SITE = { fn = "menuview", offset = 0x36, bytes = "8B 46 0C FF D0" }
local VIEW_PREPARE_OFFSET = 0xC

local BACKGROUND_FILES = {
  firstEditionTrail = "skirmish_trail.tgx",
  warchestTrail = "skirmish_trail2.tgx",
  extremeTrail = "shcx_map.tgx",
}

-- text group, line: the title and the summary shown under the trail's button
local TEXTS = {
  firstEditionTrail = { title = { 0xF2, 1 }, summary = { 0xF2, 2 } },
  warchestTrail = { title = { 0xFA, 0x15 }, summary = { 0xFA, 0x16 } },
  extremeTrail = { title = { 0xFA, 0x17 }, summary = { 0xFA, 0x18 } },
}

local backgrounds = {}
local overrideRegistered = false
local screenPictures = {} -- trailName -> { { gm, frame, path }, ... }
local shownPictures = {}  -- the pictures set for the trail screen shown
local shownTrail = nil
local viewHooked = false
local loaded = {} -- path -> resource, or false when the picture cannot be loaded

local pictureFailures = {}

local function reportPictureFailure(trailName, feature)
  pictureFailures[trailName] = pictureFailures[trailName] or {}
  if pictureFailures[trailName][feature] then return end
  pictureFailures[trailName][feature] = true
  local label = trailName == "firstEditionTrail" and "First Edition"
    or trailName == "warchestTrail" and "Warchest" or "Extreme"
  log(ERROR, string.format("%s trail %s could not be applied.", label, feature))
end

local function isExtreme()
  local ok, extreme = pcall(function() return data.version.isExtreme() end)
  return ok and extreme == true
end

local function readImage(path)
  local gm = modules.gmResourceModifier
  if gm == nil or gm.LoadResourceFromImageData == nil then
    log(WARNING, "gmResourceModifier is not active; trail button pictures stay")
    return nil
  end
  local bytes, reason = cst_io.readBytes(path)
  if bytes == nil then
    log(WARNING, string.format("cannot read the picture %s: %s", path, tostring(reason)))
    return nil
  end
  local ok, resource = pcall(function() return gm:LoadResourceFromImageData(bytes) end)
  resource = ok and resource ~= nil and resource >= 0 and resource or nil
  if resource == nil then
    log(WARNING, string.format("cannot load the picture %s", path))
  end
  return resource
end

local function loadImage(path)
  if loaded[path] == nil then
    loaded[path] = readImage(path) or false
  end
  return loaded[path] or nil
end

---True when the picture at `path` replaces frame `frame` of gm `gmId`.
local function setFrame(gmId, frame, path)
  local resource = loadImage(path)
  if resource == nil then
    return false
  end
  local ok, done = pcall(function() return modules.gmResourceModifier:SetGm(gmId, frame, resource, 0) end)
  if not ok or done == false then
    log(WARNING, string.format("the picture %s does not fit gm %d frame %d", path, gmId, frame))
    return false
  end
  return true
end

---Gives the trail screen's buttons the pictures of `trailName` (nil: no trail screen) and the
---game's pictures back where it has none.
local function showScreenPictures(trailName)
  if trailName == shownTrail then
    return
  end
  for _, picture in ipairs(shownPictures) do
    pcall(function() modules.gmResourceModifier:SetGm(picture.gm, picture.frame, -1, -1) end)
  end
  shownPictures, shownTrail = {}, trailName
  for _, picture in ipairs(trailName and screenPictures[trailName] or {}) do
    if not picture.failed and setFrame(picture.gm, picture.frame, picture.path) then
      table.insert(shownPictures, picture)
    else
      reportPictureFailure(trailName, "screen button artwork")
      picture.failed = true
    end
  end
end

local function hookTrailScreen()
  if viewHooked then
    return true
  end
  local site = patches.siteAddress(VIEW_PREPARE_SITE, "the trail screen's button pictures")
  local open = patches.functionAddress("open")
  if site == nil or open == nil or not memory.bindTrailType() then
    return
  end
  core.detourCode(function(registers)
    local opening = core.readInteger(registers.ESI + VIEW_PREPARE_OFFSET) == open
    showScreenPictures(opening and memory.TRAIL_TYPES[core.readInteger(memory.CURRENT_TRAIL_TYPE)] or nil)
    return registers
  end, site, 5)
  viewHooked = true
  return true
end

local function registerBackgroundOverride()
  if overrideRegistered then
    return true
  end
  local files = modules.files
  if files == nil or files.registerOverrideFunction == nil then
    log(WARNING, "the files module is not active; trail backgrounds stay")
    return
  end
  files:registerOverrideFunction(function(file)
    local name = tostring(file):lower():match("([^/\\]+)$")
    return name ~= nil and backgrounds[name] or nil
  end)
  overrideRegistered = true
  return true
end

---The .tgx file to show for a trail_background: a .tgx is used as it is, any other picture
---(.png, .jpg, .bmp, .gif) is turned into a .tgx in the user data folder first.
function backgroundTgx(trailName, path)
  local original = "gfx/" .. BACKGROUND_FILES[trailName]
  local result, width, height = path, nil, nil
  if not path:lower():match("%.tgx$") then
    local ok, made, madeWidth, madeHeight = pcall(tgx.convert, path,
      string.format("background-%s.tgx", trailName))
    if not ok or made == nil then
      log(WARNING, string.format("the trail background stays: %s", tostring(made)))
      return nil
    end
    result, width, height = made, madeWidth, madeHeight
  else
    width, height = tgx.size(path)
    if width == nil then
      log(WARNING, string.format("the trail background stays: %s cannot be read as a .tgx file",
        tostring(path)))
      return nil
    end
  end
  local originalWidth, originalHeight = tgx.size(original)
  if width ~= nil and originalWidth ~= nil and (width ~= originalWidth or height ~= originalHeight) then
    log(WARNING, string.format("%s is %d x %d, the game's %s is %d x %d",
      path, width, height, original, originalWidth, originalHeight))
  end
  return result
end

---Applies the trail_visuals of a trail settings file.
function visuals.applyVisuals(trailName, trailVisuals)
  if trailVisuals == nil then
    return
  end
  if trailVisuals.buttonIdle ~= nil or trailVisuals.buttonHighlighted ~= nil then
    local frames = BUTTON_FRAMES[isExtreme() and "extreme" or "crusader"][trailName]
    if frames == nil then
      log(INFO, string.format("this game version has no menu button for the %s", trailName))
    else
      -- loaded once the game has started (COM is ready then, as for aiSwapper's portraits)
      hooks.registerHookCallback("afterInit", function()
        if trailVisuals.buttonIdle ~= nil and not setFrame(frames.gm, frames.idle, trailVisuals.buttonIdle) then
          reportPictureFailure(trailName, "menu button artwork")
        end
        if trailVisuals.buttonHighlighted ~= nil and not setFrame(frames.gm, frames.highlighted, trailVisuals.buttonHighlighted) then
          reportPictureFailure(trailName, "menu button artwork")
        end
      end)
    end
  end
  local pictures = {}
  for name, button in pairs(SCREEN_BUTTONS) do
    for offset, state in ipairs({ "Idle", "Highlighted" }) do
      local path = trailVisuals[name .. state]
      if path ~= nil then
        table.insert(pictures, { gm = button.gm, frame = button.frame + offset - 1, path = path })
      end
    end
  end
  if #pictures > 0 then
    screenPictures[trailName] = pictures
    if not hookTrailScreen() then reportPictureFailure(trailName, "screen button artwork") end
  end
  if trailVisuals.background ~= nil then
    -- the user data folder is ready once the game has started
    hooks.registerHookCallback("afterInit", function()
      local background = backgroundTgx(trailName, trailVisuals.background)
      if background ~= nil then
        backgrounds[BACKGROUND_FILES[trailName]] = background
      end
      if background == nil or not registerBackgroundOverride() then
        reportPictureFailure(trailName, "background")
      end
    end)
  end
end

---Applies trail_title and trail_summary of a trail settings file.
function visuals.applyTexts(trailName, title, summary)
  local texts = TEXTS[trailName]
  if title ~= nil then
    modules.textResourceModifier:SetText(texts.title[1], texts.title[2], title)
  end
  if summary ~= nil then
    modules.textResourceModifier:SetText(texts.summary[1], texts.summary[2], summary)
  end
end

return visuals
