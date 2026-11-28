-- CSV helpers and mission file loading.

local settingsModule = require("customskirmishtrails.settings")
local missionjson = require("customskirmishtrails.missionjson")

local conversion = {}

-- CSV ------------------------------------------------------------------------------------

---Parses the legacy CSV into rows of raw strings.
local function parseCsv(text)
  if text:sub(1, 3) == "\239\187\191" then
    text = text:sub(4)
  end
  local rows, row, field = {}, {}, {}
  local position, length = 1, #text
  local quoted, fieldStarted = false, false

  local function endField()
    table.insert(row, table.concat(field))
    field, fieldStarted = {}, false
  end
  local function endRow()
    endField()
    table.insert(rows, row)
    row = {}
  end

  while position <= length do
    local char = text:sub(position, position)
    if quoted then
      if char == '"' then
        if text:sub(position + 1, position + 1) == '"' then
          table.insert(field, '"')
          position = position + 1
        else
          quoted = false
        end
      else
        table.insert(field, char)
      end
    elseif char == '"' and not fieldStarted then
      quoted, fieldStarted = true, true
    elseif char == "," then
      endField()
    elseif char == "\r" and text:sub(position + 1, position + 1) == "\n" then
      endRow()
      position = position + 1
    elseif char == "\n" then
      endRow()
    else
      table.insert(field, char)
      fieldStarted = true
    end
    position = position + 1
  end
  if fieldStarted or #row > 0 or #field > 0 then
    endRow()
  end
  local result = {}
  for _, r in ipairs(rows) do
    if not (#r == 1 and r[1] == "") then
      table.insert(result, r)
    end
  end
  return result
end

local function csvField(value)
  if value:find('[,"\r\n]') then
    return '"' .. value:gsub('"', '""') .. '"'
  end
  return value
end

local function formatCsv(rows, newline)
  local lines = {}
  for _, row in ipairs(rows) do
    local fields = {}
    for index, value in ipairs(row) do
      fields[index] = csvField(value)
    end
    table.insert(lines, table.concat(fields, ","))
  end
  return table.concat(lines, newline) .. newline
end

---A legacy trail CSV as { header, missions = { column -> cell } }, or nil and an error.
function conversion.readTable(path)
  local text, err = settingsModule.readText(path)
  if text == nil then
    return nil, string.format("cannot read %s (%s)", path, tostring(err))
  end
  local rows = parseCsv(text)
  if #rows < 1 then
    return nil, path .. " is empty"
  end
  local header, missions = rows[1], {}
  for index = 2, #rows do
    local cells = {}
    for column, key in ipairs(header) do
      if key ~= "" then
        cells[key] = rows[index][column] or ""
      end
    end
    table.insert(missions, cells)
  end
  return { header = header, missions = missions }
end

---The csv columns for missions put together from JSON files: the csv's own header when there is
---one, then the known columns, then any remaining columns.
function conversion.columnOrder(existingHeader, missions, knownHeaders, legacy)
  local order, seen = {}, {}
  local function add(key)
    if key ~= "" and not seen[key] then
      seen[key] = true
      table.insert(order, key)
    end
  end
  if existingHeader ~= nil then
    for _, key in ipairs(existingHeader) do
      add(key)
    end
  end
  local present = {}
  for _, mission in ipairs(missions) do
    for key, value in pairs(mission) do
      present[key] = present[key] or not legacy or value ~= ""
    end
  end
  for _, key in ipairs(knownHeaders or {}) do
    if (legacy and existingHeader == nil) or present[key] then
      add(key)
    end
  end
  local extra = {}
  for key, filled in pairs(present) do
    if filled and not seen[key] then
      table.insert(extra, key)
    end
  end
  table.sort(extra)
  for _, key in ipairs(extra) do
    add(key)
  end
  -- keep the existing header's empty-named columns where they were
  if existingHeader ~= nil then
    local withBlanks = {}
    local index = 1
    for _, key in ipairs(existingHeader) do
      if key == "" then
        table.insert(withBlanks, "")
      else
        table.insert(withBlanks, order[index])
        index = index + 1
      end
    end
    for rest = index, #order do
      table.insert(withBlanks, order[rest])
    end
    return withBlanks
  end
  return order
end

---The csv text for `header` and `missions` (column -> cell).
function conversion.csvText(header, missions, newline)
  local rows = { header }
  for _, mission in ipairs(missions) do
    local row = {}
    for column, key in ipairs(header) do
      row[column] = key ~= "" and (mission[key] or "") or ""
    end
    table.insert(rows, row)
  end
  return formatCsv(rows, newline or "\r\n")
end

-- mission files ----------------------------------------------------------------------------

---The mission files in `folder`: a list of { number, name } sorted by number.
function conversion.listMissionFiles(folder, name)
  local pattern = "^" .. name:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"):lower() .. "_mission_(%d+)%.json$"
  local files = {}
  local listed, entries = pcall(ucp.internal.io.files, folder)
  for _, entry in ipairs(listed and entries or {}) do
    local file = entry:match("([^/\\]+)$")
    local number = file:lower():match(pattern)
    if number ~= nil then
      table.insert(files, { number = tonumber(number), name = file })
    end
  end
  table.sort(files, function(a, b) return a.number < b.number end)
  return files
end

function conversion.reverseMapping(mapping)
  if mapping == nil then
    return nil
  end
  local reverse = {}
  for key, alias in pairs(mapping) do
    reverse[alias] = key
  end
  return reverse
end

---Reads and converts one mission file into csv cells. Raises an error for a broken file.
function conversion.readMission(path, reverse)
  local text, err = settingsModule.readText(path)
  if text == nil then
    error(string.format("cannot read %s (%s)", path, tostring(err)))
  end
  local ok, data = pcall(function() return json:decode(text) end)
  if not ok then
    error(string.format("%s is not valid JSON: %s", path, tostring(data)))
  end
  return missionjson.toRow(data, reverse, path)
end

return conversion
