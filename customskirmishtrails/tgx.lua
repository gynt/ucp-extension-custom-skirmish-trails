local cst_io = require("customskirmishtrails.io")
local storage = require("customskirmishtrails.storage")

local tgx = {}

---The width and height in a TGX file, or nil.
function tgx.size(path)
  local ok, handle = pcall(io.open, path, "rb")
  if not ok or handle == nil then return nil end
  local header = handle:read(8)
  handle:close()
  if header ~= nil and #header == 8 then
    local width, height = string.unpack("<I4I4", header)
    return width, height
  end
end

---Converts the image at `path` to a TGX file the game can open by name.
function tgx.convert(path, name)
  local image, reason = cst_io.readBytes(path)
  if image == nil then error(string.format("cannot read %s: %s", path, tostring(reason))) end

  local picture = modules.gmResourceModifier:EncodeImageAsTgx(image)
  if picture == nil then error("cannot decode " .. path) end

  local target = storage.path(name)
  if target == nil then error("the user data folder is not ready") end
  local written, writeError = storage.write(name, picture.bytes)
  if not written then error(writeError) end
  return target, picture.width, picture.height
end

return tgx
