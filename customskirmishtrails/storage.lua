-- The module's own files (progress, route results, converted backgrounds) in its UCP
-- user data folder: <Crusader user folder>/ucp/userdata/custom-skirmish-trails/. The folder is
-- ready once the game has started (afterInit).

local storage = {}

local EXTENSION = "custom-skirmish-trails"

local folder = nil

---`name` as the user data folder takes it: letters, digits, '.', '_', '~' and '-' in each part.
local function safeName(name)
  return (name:gsub("[^%w._~/-]", "-"))
end

local function interface()
  if folder == nil then
    local ok, result = pcall(userdata.interface)
    if not ok then
      log(WARNING, "the user data folder cannot be opened: " .. tostring(result))
      return nil, tostring(result)
    end
    folder = result
  end
  if folder == nil then
    log(WARNING, "the user data folder is used before the game has started")
    return nil, "the user data folder is not ready"
  end
  return folder
end

---Opens the file `name` of the user data folder, as io.open does.
function storage.open(name, mode)
  local f, err = interface()
  if f == nil then
    return nil, err
  end
  return f:open(safeName(name), mode)
end

---Writes `contents` to the file `name` of the user data interface `f`. True, or false and the reason.
local function writeFile(f, name, contents)
  local file, openError = f:open(name, "wb")
  if file == nil then
    return false, string.format("cannot write %s: %s", name, tostring(openError))
  end
  local written, writeError = file:write(contents)
  local closed, closeError = file:close()
  if written == nil or not closed then
    return false, string.format("cannot write %s: %s", name, tostring(writeError or closeError))
  end
  return true
end

local renames = true

---Writes `contents` to the file `name` of the user data folder, replacing it. The contents go to
---a temporary file of this writer's own first that then replaces `name`; without the framework's
---rename (its native part before 3.0.8) `name` is written directly. True, or false and the reason.
function storage.write(name, contents)
  local f, err = interface()
  if f == nil then
    return false, err
  end
  local target = safeName(name)
  local directory = target:match("^(.+)/[^/]+$")
  if directory ~= nil then
    local made, mkdirError = f:mkdir(directory, true)
    if not made then
      return false, string.format("cannot make the folder %s: %s", directory, tostring(mkdirError))
    end
  end
  if renames and f.rename ~= nil then
    local temporary = string.format("%s.%d-%x.tmp", target, os.time(), math.random(0, 0x7FFFFFFF))
    local written, writeError = writeFile(f, temporary, contents)
    if not written then
      f:remove(temporary)
      return false, writeError
    end
    local called, renamed, renameError = pcall(f.rename, f, temporary, target)
    if called and renamed then
      return true
    end
    f:remove(temporary)
    if called then
      return false, string.format("cannot replace %s: %s", name, tostring(renameError))
    end
    renames = false
    log(WARNING, "the framework cannot rename files; files are written in place")
  end
  return writeFile(f, target, contents)
end

---The contents of the file `name` of the user data folder, or nil.
function storage.read(name)
  local file = storage.open(name, "rb")
  if file == nil then
    return nil
  end
  local contents = file:read("a")
  file:close()
  return contents
end

---The absolute path of the file `name` of the user data folder, for code that opens it by path.
function storage.path(name)
  if interface() == nil then
    return nil
  end
  return data.userdata.getPathInUserDataFolder(EXTENSION .. "/" .. safeName(name))
end

return storage
