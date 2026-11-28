-- trail_route in the trail settings file: the trail's missions as nodes keyed by id, joined by
-- requires into a graph. A node can be played once the nodes it requires are passed (won, or for a
-- main node skipped with a chicken) and its unlock is met; the trail ends when its end node, the
-- trail's last row, is won. Passed nodes are kept in a file of node ids. The game's furthest row
-- is the first main row not passed (the frontier), so its markers, chicken count and chicken skip
-- keep working for the nodes it can describe. Every win of a node is kept in a results file with
-- the players whose lord, and who themselves, were alive at that win; an unlock's won conditions
-- read these, and a node's reward is given at its first win. Rows are 0-based here, as in the game.

local common = require("customskirmishtrails.common")
local storage = require("customskirmishtrails.storage")

local route = {}

local Route = {}
Route.__index = Route

---`value` when it is a list of node ids ({} for nil), otherwise nil.
local function idList(value)
  if value == nil then
    return {}
  end
  if type(value) ~= "table" then
    return nil
  end
  local count = 0
  for _, id in pairs(value) do
    if type(id) ~= "string" then
      return nil
    end
    count = count + 1
  end
  return count == #value and value or nil
end

local MAX_PLAYERS = 8
local MAX_REWARD = 1000

---True when `value` is a list of at least one entry.
local function isList(value)
  if type(value) ~= "table" or #value == 0 then
    return false
  end
  local count = 0
  for _ in pairs(value) do
    count = count + 1
  end
  return count == #value
end

---The player slots of a list of different colour names, or nil.
local function colourList(value)
  if not isList(value) then
    return nil
  end
  local slots, seen = {}, {}
  for index, colour in ipairs(value) do
    slots[index] = common.COLORS[colour]
    if slots[index] == nil or seen[slots[index]] then
      return nil
    end
    seen[slots[index]] = true
  end
  return slots
end

---A qualifier asking that the players of a list of colours had `fact` (lords, players) at the win.
local function alive(fact)
  return function(value)
    local slots = colourList(value)
    if slots == nil then
      return nil, "must be a list of different player colours"
    end
    return function(result)
      for _, slot in ipairs(slots) do
        if not result[fact][slot] then
          return false
        end
      end
      return true
    end
  end
end

-- What a won condition can ask of that win besides its mission: each reads its value into a test of
-- one win's result, or returns nil and the problem.
local WIN_QUALIFIERS = {
  lords_alive = alive("lords"),
  players_alive = alive("players"),
}

local NEVER = { needs = {}, holds = function() return false end }
local readCondition

-- The condition types, keyed by the one key of a condition: each reads its value into
-- { needs = node ids it reads, holds = function(route) }, or returns nil and the problem. Problems
-- of nested conditions go to `problems`.
local CONDITIONS = {}

function CONDITIONS.won(value)
  if type(value) ~= "table" or type(value.mission) ~= "string" then
    return nil, "needs a mission, a node id"
  end
  local tests = {}
  for key, entry in pairs(value) do
    if key ~= "mission" then
      local read = WIN_QUALIFIERS[key]
      if read == nil then
        return nil, string.format("'%s' is not a qualifier this version knows", tostring(key))
      end
      local test, problem = read(entry)
      if test == nil then
        return nil, string.format("%s %s", key, problem)
      end
      table.insert(tests, test)
    end
  end
  return { needs = { value.mission }, holds = function(r)
    for _, result in ipairs(r.results[value.mission] or {}) do
      local met = true
      for _, test in ipairs(tests) do
        met = met and test(result)
      end
      if met then
        return true
      end
    end
    return false
  end }
end

---A condition type holding when all (`every`) or one of a list of conditions holds.
local function group(every)
  return function(value, problems)
    if not isList(value) then
      return nil, "must be a list of conditions"
    end
    local conditions, needs = {}, {}
    for index, entry in ipairs(value) do
      conditions[index] = readCondition(entry, problems)
      for _, id in ipairs(conditions[index].needs) do
        table.insert(needs, id)
      end
    end
    return { needs = needs, holds = function(r)
      for _, condition in ipairs(conditions) do
        if condition.holds(r) ~= every then
          return not every
        end
      end
      return every
    end }
  end
end
CONDITIONS.all = group(true)
CONDITIONS.any = group(false)

---The condition `value`, an object with one key naming its type. A condition this version can't
---read never holds; its problem is added to `problems`.
function readCondition(value, problems)
  local key = type(value) == "table" and next(value)
  local read = CONDITIONS[key]
  local condition, problem
  if type(key) ~= "string" or next(value, key) ~= nil then
    problem = "a condition is an object with one key, its type"
  elseif read == nil then
    problem = string.format("'%s' is not a condition this version knows", key)
  else
    condition, problem = read(value[key], problems)
    problem = problem and string.format("%s %s", key, problem)
  end
  if condition == nil then
    table.insert(problems, problem)
    return NEVER
  end
  return condition
end

---A node's reward { "chickens": n } as { chickens }, or nil and the problem.
local function readReward(value)
  local chickens = type(value) == "table" and math.tointeger(value.chickens)
  if not chickens or chickens < 1 or chickens > MAX_REWARD or next(value, next(value)) ~= nil then
    return nil, string.format("reward must be { \"chickens\": 1 to %d }", MAX_REWARD)
  end
  return { chickens = chickens }
end

---Every node `node` needs before it can be played: requires, requires_any and the nodes its unlock
---reads.
local function needs(node)
  local list = {}
  for _, ids in ipairs({ node.requires, node.requiresAny }) do
    for _, id in ipairs(ids) do
      table.insert(list, id)
    end
  end
  for _, id in ipairs(node.unlock and node.unlock.needs or {}) do
    table.insert(list, id)
  end
  return list
end

---The nodes in or behind a circle of needs (sorted), or nil when there are none.
local function circle(nodes)
  local left, count = {}, {}
  for id, node in pairs(nodes) do
    left[id], count[id] = node, #needs(node)
  end
  local done = true
  while done do
    done = false
    for id, node in pairs(left) do
      if count[id] == 0 then
        left[id], done = nil, true
        for other, otherNode in pairs(left) do
          for _, needed in ipairs(needs(otherNode)) do
            if needed == id then
              count[other] = count[other] - 1
            end
          end
        end
      end
    end
  end
  local ids = {}
  for id in pairs(left) do
    table.insert(ids, id)
  end
  table.sort(ids)
  return #ids > 0 and ids or nil
end

---Marks the chain nodes: main nodes without unlock that need only main nodes on rows before
---theirs and that every main node before them leads to through requires. The game's own markers
---and its furthest row describe such a node right; every other node is drawn by the route.
local function markChain(nodes, rows, count)
  local ancestors = {}
  local function ancestorsOf(node)
    if ancestors[node.id] == nil then
      local set = {}
      ancestors[node.id] = set
      for _, id in ipairs(node.requires) do
        set[id] = true
        for above in pairs(ancestorsOf(nodes[id])) do
          set[above] = true
        end
      end
    end
    return ancestors[node.id]
  end
  for row = 0, count - 1 do
    local node = rows[row]
    local chain = not node.side and node.unlock == nil
    for _, id in ipairs(needs(node)) do
      chain = chain and not nodes[id].side and nodes[id].row < row
    end
    for before = 0, row - 1 do
      chain = chain and (rows[before].side or ancestorsOf(node)[rows[before].id] == true)
    end
    node.chain = chain
  end
end

---True when the route `value` names its missions by file instead of by number.
function route.hasFiles(value)
  for _, entry in pairs(type(value) == "table" and value or {}) do
    if type(entry) == "table" and entry.file ~= nil then
      return true
    end
  end
  return false
end

-- the trail screen is 800 x 600
local MAX_X, MAX_Y = 800, 600

---A node's position { "x": .., "y": .. } on the trail screen, or nil.
local function readPosition(value)
  local x = type(value) == "table" and math.tointeger(value.x)
  local y = type(value) == "table" and math.tointeger(value.y)
  return x and y and x >= 0 and y >= 0 and x <= MAX_X and y <= MAX_Y and { x = x, y = y } or nil
end

---The rows of a route of files: every main node as soon as what it needs is placed, then the side
---nodes the same way (by id where several can go), and the end last.
local function placeRows(nodes, ending, count)
  local rows, placed = {}, {}
  for row = 0, count - 2 do
    local pick = nil
    for id, node in pairs(nodes) do
      local ready = not placed[id] and node ~= ending
      for _, needed in ipairs(needs(node)) do
        ready = ready and placed[needed]
      end
      if ready and (pick == nil or (pick.side and not node.side) or (pick.side == node.side and id < pick.id)) then
        pick = node
      end
    end
    pick.row, rows[row], placed[pick.id] = row, pick, true
  end
  ending.row, rows[count - 1] = count - 1, ending
  return rows
end

---The trail's route from `value` (trail_route) for a trail of `count` missions (nil for a route of
---files, which has one mission per node), or nil and the problem. Other fields of a node are not
---used.
local function parse(value, count)
  if type(value) ~= "table" then
    return nil, "trail_route must be an object of node ids"
  end
  local files = route.hasFiles(value)
  local nodes, rows, rewards, ending, warnings, size = {}, {}, false, nil, {}, 0
  for id, entry in pairs(value) do
    if type(id) ~= "string" or not id:match("^[%w_%-]+$") or type(entry) ~= "table" then
      return nil, "every trail_route entry must be an object under a node id of letters, digits, _ and -"
    end
    local mission = math.tointeger(entry.mission)
    local position = files and readPosition(entry.position)
    if files and (type(entry.file) ~= "string" or entry.file == "" or entry.mission ~= nil or position == nil) then
      return nil, string.format("node '%s' needs a file and a position inside 800 x 600 and no mission, as every "
        .. "node of a route of files", id)
    elseif not files and (mission == nil or mission < 1 or mission > count) then
      return nil, string.format("node '%s' needs a mission from 1 to %d", id, count)
    end
    if not files and rows[mission - 1] ~= nil then
      return nil, string.format("nodes '%s' and '%s' have the same mission %d", rows[mission - 1].id, id, mission)
    end
    local kind = entry.kind or "main"
    if kind ~= "main" and kind ~= "side" then
      return nil, string.format("node '%s': kind must be main or side", id)
    end
    local requires, requiresAny = idList(entry.requires), idList(entry.requires_any)
    if requires == nil or requiresAny == nil then
      return nil, string.format("node '%s': requires and requires_any must be lists of node ids", id)
    end
    if entry["end"] ~= nil and type(entry["end"]) ~= "boolean" or entry["end"] and kind == "side" then
      return nil, string.format("node '%s': end must be true or false, and only a main mission can be the end", id)
    end
    local unlock, reward, problem
    if entry.unlock ~= nil then
      local problems = {}
      unlock = readCondition(entry.unlock, problems)
      for _, never in ipairs(problems) do
        table.insert(warnings, string.format("node '%s': unlock: %s; that condition never holds", id, never))
      end
    end
    if entry.reward ~= nil then
      reward, problem = readReward(entry.reward)
      if reward == nil then
        return nil, string.format("node '%s': %s", id, problem)
      end
      rewards = true
    end
    local node = { id = id, row = mission and mission - 1, side = kind == "side", requires = requires,
      requiresAny = requiresAny, unlock = unlock, reward = reward, file = entry.file, position = position }
    if entry["end"] then
      if ending ~= nil then
        return nil, string.format("nodes '%s' and '%s' are both the end", ending.id, id)
      end
      ending = node
    end
    nodes[id], size = node, size + 1
    if not files then
      rows[mission - 1] = node
    end
  end
  if files then
    count = size
  end
  -- by number, missions the route doesn't name are main missions, and a main mission without
  -- requires follows the main mission before it
  local previous = nil
  for row = 0, files and -1 or count - 1 do
    if rows[row] == nil then
      rows[row] = { id = "#" .. (row + 1), row = row, side = false, requires = {}, requiresAny = {} }
      nodes[rows[row].id] = rows[row]
    end
    local node = rows[row]
    if not node.side then
      if previous ~= nil and #node.requires == 0 and #node.requiresAny == 0 then
        node.requires = { previous.id }
      end
      previous = node
    end
  end
  for id, node in pairs(nodes) do
    for _, needed in ipairs(needs(node)) do
      if nodes[needed] == nil then
        return nil, string.format("node '%s' requires '%s', which is not a node", id, needed)
      end
    end
  end
  -- by file, without "end" the end is the one main node no other node needs
  if files and ending == nil then
    local needed = {}
    for _, node in pairs(nodes) do
      for _, id in ipairs(needs(node)) do
        needed[id] = true
      end
    end
    for id, node in pairs(nodes) do
      if not node.side and not needed[id] then
        if ending ~= nil then
          return nil, string.format("'%s' and '%s' could both be the end; mark the end with \"end\": true", ending.id, id)
        end
        ending = node
      end
    end
  end
  local last = files and ending or rows[count - 1]
  if last == nil or last.side or (ending ~= nil and ending ~= last) then
    return nil, string.format("the trail's end must be a main mission and its last mission (%d)", count)
  end
  for id, node in pairs(nodes) do
    for _, needed in ipairs(needs(node)) do
      if needed == last.id then
        return nil, string.format("node '%s' requires the end '%s'; winning the end ends the trail", id, needed)
      end
    end
  end
  local circled = circle(nodes)
  if circled ~= nil then
    return nil, "these nodes wait on a circle of requires and can never be played: " .. table.concat(circled, ", ")
  end
  local parsed = { nodes = nodes, rows = rows, count = count, rewards = rewards, warnings = warnings }
  if files then
    parsed.rows = placeRows(nodes, last, count)
    parsed.files, parsed.positions, parsed.keys = {}, {}, {}
    for row = 0, count - 1 do
      local node = parsed.rows[row]
      parsed.files[row + 1], parsed.positions[row + 1], parsed.keys[row + 1] = node.file, node.position, node.id
    end
  end
  markChain(nodes, parsed.rows, count)
  return parsed
end

---The route of `value` (trail_route of the settings file `settingsPath`) for a trail with `count`
---missions (nil for a route of files), with its problems logged; nil when it can't be used.
function route.read(settingsPath, value, count)
  local parsed, problem = parse(value, count)
  if parsed == nil then
    log(WARNING, string.format("%s: %s; %s", settingsPath, problem, route.hasFiles(value)
      and "the trail's missions are not loaded" or "the trail plays its missions in their order"))
    return nil
  end
  for _, warning in ipairs(parsed.warnings) do
    log(WARNING, string.format("%s: %s", settingsPath, warning))
  end
  return parsed
end

local function readLines(path)
  local lines = {}
  local file = storage.open(path, "rb")
  if file == nil then
    return lines
  end
  for line in file:read("*a"):gmatch("[^\r\n]+") do
    table.insert(lines, line)
  end
  file:close()
  return lines
end

---Writes `lines` sorted into `path`; `what` names them in the log when that fails.
local function writeLines(path, lines, what)
  table.sort(lines)
  local ok, err = storage.write(path, table.concat(lines, "\n") .. "\n")
  if not ok then
    log(WARNING, string.format("could not save %s: %s", what, tostring(err)))
  end
end

local function readWins(path)
  local wins = {}
  for _, id in ipairs(readLines(path)) do
    wins[id] = true
  end
  return wins
end

-- A results line, one per different win: "<node id> lords=1,3 players=1"
local function resultLine(id, facts)
  local fields = { id }
  for _, key in ipairs({ "lords", "players" }) do
    local players = {}
    for player = 1, MAX_PLAYERS do
      if facts[key][player] then
        table.insert(players, tostring(player))
      end
    end
    table.insert(fields, key .. "=" .. table.concat(players, ","))
  end
  return table.concat(fields, " ")
end

---Adds the win of results line `line` to the route; false when it is kept already or not a line.
---Other words after the node id, such as a difficulty, are skipped.
local function addResult(r, line)
  local id, rest = line:match("^(%S+)(.*)$")
  if id == nil or r.lines[line] then
    return false
  end
  local result = { lords = {}, players = {} }
  for key, list in rest:gmatch("(%a+)=(%S*)") do
    if key == "lords" or key == "players" then
      for player in list:gmatch("%d+") do
        result[key][tonumber(player)] = true
      end
    end
  end
  r.lines[line] = true
  r.results[id] = r.results[id] or {}
  table.insert(r.results[id], result)
  return true
end

---The route `parsed` (route.read) of a trail with `count` missions; passed nodes are kept in the
---user data file `passedPath`, the results of node wins in `resultsPath` (read by readFiles), also
---for a route of chain nodes alone, so a node added later can read them. nil when `parsed` is not
---a route of `count` missions.
function route.load(parsed, count, passedPath, resultsPath)
  if parsed == nil or parsed.count ~= count then
    return nil
  end
  parsed.graph = false
  for row = 0, count - 1 do
    parsed.graph = parsed.graph or not parsed.rows[row].chain
  end
  parsed.path, parsed.passed = passedPath, {}
  parsed.resultsPath, parsed.results, parsed.lines = resultsPath, {}, {}
  parsed.version = 0 -- counts the changes of passed nodes, results and rows
  return setmetatable(parsed, Route)
end

---Reads the passed nodes and results kept from earlier games, once the game has started.
function Route:readFiles()
  self.passed = readWins(self.path)
  for _, line in ipairs(readLines(self.resultsPath)) do
    addResult(self, line)
  end
  self.version = self.version + 1
end

---False when the game's own markers and its furthest row describe the node at `row` right (a
---chain node, see markChain); its door then needs pictures of its own.
function Route:needsPictures(row)
  return not self.rows[row].chain
end

---Makes every row a main node that requires the row before it, so the route plays its rows in
---order as the game does, by the game's furthest row. Passed nodes, results and rewards stay.
function Route:playLinear()
  for row = 0, self.count - 1 do
    local node = self.rows[row]
    node.side, node.chain, node.unlock, node.requiresAny = false, true, nil, {}
    node.requires = row > 0 and { self.rows[row - 1].id } or {}
  end
  self.graph = false
  self.version = self.version + 1
end

---A node is passed once it is won, or, for a main node, skipped with a chicken.
function Route:isPassed(row)
  return self.passed[self.rows[row].id] == true
end

---The first main row not passed yet (count when every main node is passed): the game's furthest
---row. Every row before it is passed or a side mission's.
function Route:frontier()
  for row = 0, self.count - 1 do
    local node = self.rows[row]
    if not node.side and not self.passed[node.id] then
      return row
    end
  end
  return self.count
end

---The row to select on the trail map: the first main row that can be played and is not passed,
---otherwise the frontier.
function Route:suggest()
  for row = 0, self.count - 1 do
    if not self.rows[row].side and not self:isPassed(row) and self:isAvailable(row) then
      return row
    end
  end
  return math.min(self:frontier(), self.count - 1)
end

function Route:pass(row)
  local id = self.rows[row].id
  if self.passed[id] then
    return
  end
  self.passed[id] = true
  self.version = self.version + 1
  local ids = {}
  for passed in pairs(self.passed) do
    table.insert(ids, passed)
  end
  writeLines(self.path, ids, "passed trail missions")
end

---Progress kept from before the route kept its main nodes passed: while no main node is kept,
---every main row before the game's furthest row `furthest` counts as passed.
function Route:seed(furthest)
  for id in pairs(self.passed) do
    if self.nodes[id] ~= nil and not self.nodes[id].side then
      return
    end
  end
  for row = 0, math.min(furthest, self.count) - 1 do
    if not self.rows[row].side then
      self:pass(row)
    end
  end
end

---A node can be played when every node of requires and one of requires_any is passed, and its
---unlock is met.
function Route:isAvailable(row)
  local node = self.rows[row]
  if node.unlock ~= nil and not node.unlock.holds(self) then
    return false
  end
  for _, id in ipairs(node.requires) do
    if not self.passed[id] then
      return false
    end
  end
  for _, id in ipairs(node.requiresAny) do
    if self.passed[id] then
      return true
    end
  end
  return #node.requiresAny == 0
end

---A passed node stays open to be played again.
function Route:isOpen(row)
  return self:isPassed(row) or self:isAvailable(row)
end

---Keeps the win of the node at `row` with `facts` ({ lords = { [player] = true },
---players = ... }, nil when the game's players can't be read). Returns the chickens of the node's
---reward at its first win, 0 otherwise.
function Route:recordResult(row, facts)
  local node = self.rows[row]
  if node == nil then
    return 0
  end
  local first = self.results[node.id] == nil
  if addResult(self, resultLine(node.id, facts or { lords = {}, players = {} })) then
    self.version = self.version + 1
    local lines = {}
    for line in pairs(self.lines) do
      table.insert(lines, line)
    end
    writeLines(self.resultsPath, lines, "trail results")
  end
  return first and node.reward ~= nil and node.reward.chickens or 0
end

---The chickens of the rewards of every node won so far.
function Route:earnedChickens()
  local total = 0
  for id in pairs(self.results) do
    local node = self.nodes[id]
    total = total + (node ~= nil and node.reward ~= nil and node.reward.chickens or 0)
  end
  return total
end

return route
