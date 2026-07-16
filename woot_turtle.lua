-- woot_scanner.lua (advanced turtle) - FTB Revelations / MC 1.12
-- Chest on top, modem on right. Places/digs Woot controller in FRONT.
-- Creates woot_init on first run (in-world fs — not via SFTP).
-- Turtle screen: assign custom names per chest slot. Modem service runs in parallel.

local MODEM_SIDE = "right"
local CHEST_SIDE = "top"
local CHANNEL = 1234
local INIT_FILE = "woot_init"
local OLD_STATE_FILE = "woot_state"

local modem = peripheral.wrap(MODEM_SIDE)
local chest = peripheral.wrap(CHEST_SIDE)

if not modem then error("No modem on " .. MODEM_SIDE) end
if not chest then error("No chest on " .. CHEST_SIDE) end
if not turtle then error("This program must run on a turtle") end

modem.open(CHANNEL)

-- Persistent data (written by this program into the turtle's computer folder)
local initData = {
  version = 1,
  slotNames = {}, -- ["slotNumber"] = "Custom Name"
  saved = {
    mobName = nil,
    displayName = nil,
    slot = nil,
  },
}

local uiMode = "status" -- status | names | edit
local uiCursor = 1
local uiStatus = ""
local editSlot = nil
local nameList = {} -- cached rows for name UI: {slot, defaultName, customName}

local function isWootController(item)
  if not item then return false end
  local name = item.name or item.id
  return name and tostring(name):lower():find("woot") ~= nil
end

local function mobFromDisplay(display, fallback)
  display = display or fallback or "Unknown"
  return display:gsub("^%[.-%]%s*", ""):gsub(" Controller$", "")
end

local function listChest()
  if chest.list then
    return chest.list() or {}
  end
  local items = {}
  local size = chest.size and chest.size() or 27
  for i = 1, size do
    local meta = chest.getItemMeta(i)
    if meta and (meta.name or meta.displayName) then
      items[i] = meta
    end
  end
  return items
end

local function metaAt(slot)
  if chest.getItemMeta then
    local meta = chest.getItemMeta(slot)
    if meta then return meta end
  end
  return listChest()[slot]
end

local function saveInit()
  local f = fs.open(INIT_FILE, "w")
  if not f then
    uiStatus = "ERROR: cannot write " .. INIT_FILE
    return false
  end
  f.write(textutils.serialize(initData))
  f.close()
  return true
end

local function loadInit()
  if fs.exists(INIT_FILE) then
    local f = fs.open(INIT_FILE, "r")
    if f then
      local raw = f.readAll()
      f.close()
      local ok, data = pcall(textutils.unserialize, raw)
      if ok and type(data) == "table" then
        initData.version = data.version or 1
        initData.slotNames = data.slotNames or {}
        if type(data.saved) == "table" then
          initData.saved = data.saved
        end
        print("Loaded " .. INIT_FILE)
        return
      end
    end
  end

  -- Migrate old woot_state if present
  if fs.exists(OLD_STATE_FILE) then
    local f = fs.open(OLD_STATE_FILE, "r")
    if f then
      local raw = f.readAll()
      f.close()
      local ok, data = pcall(textutils.unserialize, raw)
      if ok and type(data) == "table" then
        initData.saved.mobName = data.mobName
        initData.saved.displayName = data.displayName
        initData.saved.slot = data.slot
      end
    end
  end

  saveInit()
  print("Created " .. INIT_FILE)
end

local function getSlotName(slot)
  return initData.slotNames[tostring(slot)]
end

local function setSlotName(slot, name)
  slot = tostring(slot)
  if not name or name == "" then
    initData.slotNames[slot] = nil
  else
    initData.slotNames[slot] = name
  end
  saveInit()
end

local function labelFor(slot, display, itemName)
  local custom = getSlotName(slot)
  if custom and custom ~= "" then
    return custom
  end
  return mobFromDisplay(display, itemName)
end

local function dropAllUp()
  for i = 1, 16 do
    if turtle.getItemCount(i) > 0 then
      turtle.select(i)
      local guard = 0
      while turtle.getItemCount(i) > 0 and guard < 64 do
        if not turtle.dropUp() then
          return false, "Chest is full (cannot dropUp)"
        end
        guard = guard + 1
      end
    end
  end
  return true
end

local function scanChest()
  local data = {}
  for slot, item in pairs(listChest()) do
    if isWootController(item) then
      local meta = metaAt(slot) or item
      local display = meta.displayName or meta.name or item.name or "Controller"
      local defaultMob = mobFromDisplay(display, meta.name or item.name)
      local label = labelFor(slot, display, meta.name or item.name)
      table.insert(data, {
        displayName = display,
        mobName = label,          -- shown on monitor / used as id
        defaultName = defaultMob, -- raw woot-ish name
        customName = getSlotName(slot),
        slot = slot,
      })
    end
  end
  table.sort(data, function(a, b)
    return (a.mobName or "") < (b.mobName or "")
  end)
  return data
end

local function buildNameList()
  nameList = {}
  local ordered = {}
  for slot, item in pairs(listChest()) do
    if isWootController(item) then
      table.insert(ordered, slot)
    end
  end
  table.sort(ordered)
  for _, slot in ipairs(ordered) do
    local meta = metaAt(slot) or listChest()[slot]
    local display = (meta and (meta.displayName or meta.name)) or "Controller"
    local defaultMob = mobFromDisplay(display, meta and meta.name)
    table.insert(nameList, {
      slot = slot,
      defaultName = defaultMob,
      customName = getSlotName(slot),
    })
  end
  if uiCursor > #nameList then uiCursor = math.max(1, #nameList) end
  if uiCursor < 1 then uiCursor = 1 end
end

local function clearFront()
  if turtle.detect() then
    turtle.select(1)
    if not turtle.dig() then
      return false, "Failed to dig block in front"
    end
  end
  local ok, err = dropAllUp()
  if not ok then return false, err end
  return true
end

local function extractChestSlot(targetSlot)
  local ok, err = dropAllUp()
  if not ok then return nil, err end

  local ordered = {}
  for slot, item in pairs(listChest()) do
    if item then table.insert(ordered, slot) end
  end
  table.sort(ordered)

  local found = false
  for _, slot in ipairs(ordered) do
    if slot == targetSlot then found = true break end
  end
  if not found then
    return nil, "No item in chest slot " .. tostring(targetSlot)
  end

  local turtleSlot = 1
  for _, slot in ipairs(ordered) do
    if turtleSlot > 16 then
      dropAllUp()
      return nil, "Turtle inventory full while extracting"
    end
    turtle.select(turtleSlot)
    if not turtle.suckUp(1) then
      dropAllUp()
      return nil, "suckUp failed at chest slot " .. tostring(slot)
    end
    if slot == targetSlot then
      return turtleSlot
    end
    turtleSlot = turtleSlot + 1
  end

  dropAllUp()
  return nil, "Target slot never reached"
end

local function placeController(turtleSlot)
  turtle.select(turtleSlot)
  if turtle.detect() then
    if not turtle.dig() then
      return false, "Front blocked and cannot dig"
    end
  end
  if not turtle.place() then
    return false, "turtle.place() failed - is the factory face free?"
  end
  return true
end

local function swapController(slot)
  slot = tonumber(slot)
  if not slot then
    return false, "Invalid slot"
  end

  local meta = metaAt(slot)
  if not isWootController(meta) then
    local listed = listChest()[slot]
    if not isWootController(listed) then
      return false, "No controller in chest slot " .. tostring(slot)
    end
    meta = listed
  end

  local display = meta.displayName or meta.name or "Controller"
  local mobName = labelFor(slot, display, meta.name)

  local ok, err = clearFront()
  if not ok then return false, err end

  local turtleSlot, extractErr = extractChestSlot(slot)
  if not turtleSlot then
    return false, extractErr or "Extract failed"
  end

  ok, err = placeController(turtleSlot)
  if not ok then
    dropAllUp()
    return false, err
  end

  ok, err = dropAllUp()
  if not ok then
    return false, err
  end

  initData.saved.mobName = mobName
  initData.saved.displayName = display
  initData.saved.slot = slot
  saveInit()

  return true, mobName
end

local function findChestSlotByMob(mobName)
  if not mobName then return nil end
  for _, c in ipairs(scanChest()) do
    if c.mobName == mobName then
      return c.slot
    end
  end
  return nil
end

local function activeLabel()
  if not turtle.detect() then return "None" end
  return initData.saved.mobName or "Unknown"
end

local function sendData(replyCh)
  local data = scanChest()
  local active = activeLabel()
  modem.transmit(replyCh, CHANNEL, {
    type = "WOOT_DATA",
    controllers = data,
    activeMob = active,
    savedMob = initData.saved.mobName or "None",
  })
end

------------------------------------------------------------
-- Turtle screen UI
------------------------------------------------------------

local function clip(text, width)
  text = tostring(text or "")
  if #text > width then return text:sub(1, width) end
  return text
end

local function drawStatusScreen()
  local w, h = term.getSize()
  term.setBackgroundColor(colors.black)
  term.clear()

  term.setCursorPos(1, 1)
  term.setTextColor(colors.cyan)
  term.write("WOOT TURTLE")

  term.setCursorPos(1, 3)
  term.setTextColor(colors.white)
  term.write("Channel: " .. CHANNEL)

  term.setCursorPos(1, 4)
  term.write("Active: " .. activeLabel())

  term.setCursorPos(1, 5)
  term.write("Saved:  " .. tostring(initData.saved.mobName or "None"))

  local named = 0
  for _ in pairs(initData.slotNames) do named = named + 1 end
  term.setCursorPos(1, 6)
  term.write("Named slots: " .. named)

  term.setCursorPos(1, 8)
  term.setTextColor(colors.lime)
  term.write("[N] Name slots")

  term.setCursorPos(1, 9)
  term.setTextColor(colors.yellow)
  term.write("[C] Clear front")

  term.setCursorPos(1, 10)
  term.setTextColor(colors.lightBlue)
  term.write("[R] Refresh / save init")

  term.setCursorPos(1, h)
  term.setTextColor(colors.orange)
  term.write(clip(uiStatus ~= "" and uiStatus or "Modem listening...", w))
end

local function drawNamesScreen()
  local w, h = term.getSize()
  term.setBackgroundColor(colors.black)
  term.clear()

  term.setCursorPos(1, 1)
  term.setTextColor(colors.cyan)
  term.write("ASSIGN SLOT NAMES")

  term.setCursorPos(1, 2)
  term.setTextColor(colors.gray)
  term.write("Up/Dn Enter edit  Backspace clear  Q back")

  local listTop = 4
  local listBottom = h - 2
  local visible = listBottom - listTop + 1
  local start = 1
  if uiCursor > visible then
    start = uiCursor - visible + 1
  end

  if #nameList == 0 then
    term.setCursorPos(1, listTop)
    term.setTextColor(colors.orange)
    term.write("No controllers in chest")
  else
    for row = 0, visible - 1 do
      local i = start + row
      if i > #nameList then break end
      local entry = nameList[i]
      local y = listTop + row
      local selected = (i == uiCursor)

      term.setCursorPos(1, y)
      if selected then
        term.setBackgroundColor(colors.gray)
        term.setTextColor(colors.yellow)
      else
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.white)
      end

      local custom = entry.customName or "-"
      local line = string.format(
        "%s#%d %s -> %s",
        selected and ">" or " ",
        entry.slot,
        entry.defaultName or "?",
        custom
      )
      term.write(clip(line, w))
      term.setBackgroundColor(colors.black)
    end
  end

  term.setCursorPos(1, h)
  term.setTextColor(colors.orange)
  term.setBackgroundColor(colors.black)
  term.write(clip(uiStatus, w))
end

local function drawUI()
  if uiMode == "names" or uiMode == "edit" then
    drawNamesScreen()
  else
    drawStatusScreen()
  end
end

local function beginEdit()
  if #nameList == 0 then
    uiStatus = "Nothing to name"
    return
  end
  local entry = nameList[uiCursor]
  if not entry then return end

  editSlot = entry.slot
  uiMode = "edit"
  drawNamesScreen()

  local w, h = term.getSize()
  term.setCursorPos(1, h - 1)
  term.setTextColor(colors.lime)
  term.setBackgroundColor(colors.black)
  term.clearLine()
  term.write("Name for slot " .. editSlot .. ": ")

  term.setTextColor(colors.white)
  local current = entry.customName or ""
  local ok, result = pcall(function()
    return read(nil, nil, nil, current)
  end)

  if ok and result ~= nil then
    local name = result:match("^%s*(.-)%s*$")
    setSlotName(editSlot, name)
    if name == "" then
      uiStatus = "Cleared name for slot " .. editSlot
    else
      uiStatus = "Saved: #" .. editSlot .. " = " .. name
    end
  else
    uiStatus = "Edit cancelled"
  end

  editSlot = nil
  uiMode = "names"
  buildNameList()
  drawUI()
end

------------------------------------------------------------
-- Event loops (parallel)
------------------------------------------------------------

local function handleModem()
  while true do
    local _, _, ch, replyCh, msg = os.pullEvent("modem_message")
    if ch == CHANNEL then
      if msg == "REQUEST_WOOT_DATA" then
        sendData(replyCh)
        uiStatus = "Sent list (" .. #scanChest() .. ")"
        if uiMode == "status" then drawUI() end
      elseif type(msg) == "table" and msg.type == "SWAP_CONTROLLER" then
        local ok, result = swapController(msg.slot)
        modem.transmit(replyCh, CHANNEL, {
          type = "SWAP_RESULT",
          ok = ok,
          message = ok and ("Placed " .. tostring(result)) or tostring(result),
          activeMob = activeLabel(),
          savedMob = initData.saved.mobName or "None",
        })
        sendData(replyCh)
        uiStatus = ok and ("Placed " .. tostring(result)) or tostring(result)
        if uiMode ~= "edit" then drawUI() end
      elseif type(msg) == "table" and msg.type == "CLEAR_CONTROLLER" then
        local ok, result = clearFront()
        modem.transmit(replyCh, CHANNEL, {
          type = "SWAP_RESULT",
          ok = ok,
          message = ok and "Controller removed (front empty)" or tostring(result),
          activeMob = "None",
          savedMob = initData.saved.mobName or "None",
        })
        sendData(replyCh)
        uiStatus = ok and "Front cleared" or tostring(result)
        if uiMode ~= "edit" then drawUI() end
      elseif type(msg) == "table" and msg.type == "RESTORE_SAVED" then
        local slot = findChestSlotByMob(initData.saved.mobName)
        if not slot then
          modem.transmit(replyCh, CHANNEL, {
            type = "SWAP_RESULT",
            ok = false,
            message = "Saved controller not in chest: " .. tostring(initData.saved.mobName or "None"),
            activeMob = "None",
            savedMob = initData.saved.mobName or "None",
          })
          sendData(replyCh)
          uiStatus = "Restore failed"
        else
          local ok, result = swapController(slot)
          modem.transmit(replyCh, CHANNEL, {
            type = "SWAP_RESULT",
            ok = ok,
            message = ok and ("Restored " .. tostring(result)) or tostring(result),
            activeMob = activeLabel(),
            savedMob = initData.saved.mobName or "None",
          })
          sendData(replyCh)
          uiStatus = ok and ("Restored " .. tostring(result)) or tostring(result)
        end
        if uiMode ~= "edit" then drawUI() end
      end
    end
  end
end

local function handleUI()
  drawUI()
  while true do
    local e, p1, p2, p3 = os.pullEvent()

    if e == "key" and uiMode ~= "edit" then
      local key = p1

      if uiMode == "status" then
        if key == keys.n then
          uiMode = "names"
          buildNameList()
          uiStatus = "Select a slot, Enter to name"
          drawUI()
        elseif key == keys.c then
          local ok, err = clearFront()
          uiStatus = ok and "Front cleared" or tostring(err)
          drawUI()
        elseif key == keys.r then
          saveInit()
          uiStatus = "Init saved (" .. INIT_FILE .. ")"
          drawUI()
        end

      elseif uiMode == "names" then
        if key == keys.up then
          uiCursor = math.max(1, uiCursor - 1)
          drawUI()
        elseif key == keys.down then
          uiCursor = math.min(math.max(1, #nameList), uiCursor + 1)
          drawUI()
        elseif key == keys.enter then
          beginEdit()
        elseif key == keys.backspace then
          local entry = nameList[uiCursor]
          if entry then
            setSlotName(entry.slot, nil)
            uiStatus = "Cleared slot " .. entry.slot
            buildNameList()
            drawUI()
          end
        elseif key == keys.r then
          buildNameList()
          uiStatus = "Chest refreshed"
          drawUI()
        elseif key == keys.q then
          uiMode = "status"
          uiStatus = "Modem listening..."
          drawUI()
        end
      end

    elseif e == "term_resize" and uiMode ~= "edit" then
      drawUI()
    end
  end
end

------------------------------------------------------------
-- Boot
------------------------------------------------------------

term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1, 1)

loadInit()
do
  local ok, err = clearFront()
  if not ok then
    uiStatus = "Boot clear: " .. tostring(err)
  else
    uiStatus = "Ready - modem on " .. CHANNEL
  end
end

print("Init file: " .. INIT_FILE)
print("Press N on turtle to name slots")

parallel.waitForAny(handleModem, handleUI)
