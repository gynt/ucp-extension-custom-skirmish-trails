local patches = require("customskirmishtrails.patches")

local LINE_CAPACITY = 1000
local textLines = {}

---Writes `text` in the game's text encoding (textResourceModifier) into the `capacity` bytes at
---`address`, cut to fit.
local function writeGameText(address, capacity, text)
  local modifier = modules.textResourceModifier
  if modifier.TransformText == nil then return end
  local transformed = modifier:TransformText(text)
  local bounded = transformed:match("^[^%z]*"):sub(1, capacity - 1)
  core.writeString(address, bounded)
  core.writeByte(address + #bounded, 0)
end

local function genRenderText(address, line, renderFunc, pColorArray, pTextManagerObj)
  return core.AssemblyLambda([[
    pushad
    
    push 0
    push 0
    push 0x12
    push 0
    mov edx, dword [pColorArray]
    push edx
    push 0
    add eax, yOffset
    push eax
    add ecx, xOffset
    push ecx
    
    mov ecx, stringAddress
    push ecx
    mov ecx, pTextManagerObj
    call func
    
    popad
  ]], {
    func = renderFunc,
    stringAddress = address,
    pColorArray = pColorArray,
    pTextManagerObj = pTextManagerObj,
    yOffset = 0x04 + 0x16 * (line - 1),
    xOffset = 0x100,
  })
end



return {
  enable = function()
    if next(textLines) ~= nil then return true end
    local _, colors = patches.extract("8B ? ? I(? ? ? ?) 6A 13 6A 00 51")
    local _, textManager = patches.extract("8B ? I(? ? ? ?) A1 ? ? ? ? 52 8D 54 01 0A")
    local render = patches.find("8B 44 24 20 8B 54 24 18 53")
    local site = patches.find("8D A4 24 00 00 00 00 83 FD 01")
    if colors == nil or textManager == nil or render == nil or site == nil then return false end
    local codes, lines = {}, {}
    for line = 1, 8 do
      local address = core.allocate(LINE_CAPACITY, true)
      lines[line] = address
      codes[line] = genRenderText(address, line, render, colors, textManager)
    end
    patches.guarded({ { address = site, size = 7 } }, function()
      core.insertCode(site, 7, codes, nil, "after")
    end)
    textLines = lines
    return true
  end,
  setText = function(line, text)
    local address = textLines[line]
    if address == nil or type(text) ~= "string" then return end
    writeGameText(address, LINE_CAPACITY, text)
  end,
  writeGameText = writeGameText,
  getText = function(line)
    local address = textLines[line]
    return address and core.readString(address) or nil
  end,
}
