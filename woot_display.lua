-- woot_display.lua
-- Modem on right, advanced monitor on left (sized for 5x4 advanced monitors).
-- Tap a mob to install. Tap "Active" to clear front.
-- Tap "Saved" to restore last selection after a turtle reboot.
-- Prev/Next page when the list does not fit one screen.

local MODEM_SIDE = "right"
local MON_SIDE = "left"
local CHANNEL = 1234
local POLL_SECONDS = 5

local modem = peripheral.wrap(MODEM_SIDE)
local mon = peripheral.wrap(MON_SIDE)

if not modem then error("No modem on " .. MODEM_SIDE) end
if not mon then error("No monitor on " .. MON_SIDE) end

modem.open(CHANNEL)

local controllers = {}
local activeMob = "None"
local savedMob = "None"
local statusMsg = "Connecting..."
local currentPage = 1

-- Layout rows (1-based). BUTTON_STEP = button row + blank gap.
local TITLE_Y = 2
local ACTIVE_Y = 4
local SAVED_Y = 6
local LIST_START_Y = 8
local BUTTON_STEP = 2

print("Display started - listening...")

local function requestData()
  modem.transmit(CHANNEL, CHANNEL, "REQUEST_WOOT_DATA")
end

local function sendSwap(slot)
  modem.transmit(CHANNEL, CHANNEL, {
    type = "SWAP_CONTROLLER",
    slot = slot,
  })
  statusMsg = "Swapping..."
end

local function sendClear()
  modem.transmit(CHANNEL, CHANNEL, { type = "CLEAR_CONTROLLER" })
  statusMsg = "Clearing front..."
end

local function sendRestore()
  modem.transmit(CHANNEL, CHANNEL, { type = "RESTORE_SAVED" })
  statusMsg = "Restoring saved..."
end

local function clip(text, width)
  text = tostring(text or "")
  if #text > width then
    return text:sub(1, width)
  end
  return text .. string.rep(" ", width - #text)
end

local function drawButton(x, y, width, text, fg, bg)
  mon.setBackgroundColor(bg)
  mon.setTextColor(fg)
  mon.setCursorPos(x, y)
  mon.write(clip(" " .. text, width))
end

local function drawBox(x1, y1, x2, y2, color)
  local old = term.redirect(mon)
  paintutils.drawBox(x1, y1, x2, y2, color)
  term.redirect(old)
end

local function drawFilled(x1, y1, x2, y2, color)
  local old = term.redirect(mon)
  paintutils.drawFilledBox(x1, y1, x2, y2, color)
  term.redirect(old)
end

-- Returns perPage, totalPages, pageBarY, listMaxY, nav button geometry
local function getLayout()
  local w, h = mon.getSize()
  local pageBarY = h - 2
  local listMaxY = h - 4
  local slots = 0
  local y = LIST_START_Y
  while y <= listMaxY do
    slots = slots + 1
    y = y + BUTTON_STEP
  end
  local perPage = math.max(1, slots)
  local totalPages = math.max(1, math.ceil(math.max(#controllers, 1) / perPage))
  if #controllers == 0 then totalPages = 1 end
  if currentPage > totalPages then currentPage = totalPages end
  if currentPage < 1 then currentPage = 1 end

  local innerX = 3
  local btnW = math.max(8, w - 4)
  local navW = math.max(8, math.floor((btnW - 2) / 3))
  local prevX = innerX
  local pageX = innerX + navW + 1
  local nextX = innerX + (navW + 1) * 2

  return {
    w = w,
    h = h,
    innerX = innerX,
    btnW = btnW,
    perPage = perPage,
    totalPages = totalPages,
    pageBarY = pageBarY,
    listMaxY = listMaxY,
    prevX = prevX,
    pageX = pageX,
    nextX = nextX,
    navW = navW,
  }
end

local function draw()
  local L = getLayout()
  mon.setTextScale(1)

  drawFilled(1, 1, L.w, L.h, colors.black)
  drawBox(1, 1, L.w, L.h, colors.gray)

  mon.setBackgroundColor(colors.black)
  mon.setTextColor(colors.cyan)
  mon.setCursorPos(L.innerX, TITLE_Y)
  mon.write(clip("WOOT CONTROLLERS", L.btnW))

  drawButton(L.innerX, ACTIVE_Y, L.btnW, "Active: " .. (activeMob or "None"), colors.white, colors.green)
  drawButton(L.innerX, SAVED_Y, L.btnW, "Saved: " .. (savedMob or "None"), colors.white, colors.blue)

  local startIndex = (currentPage - 1) * L.perPage + 1
  local endIndex = math.min(#controllers, startIndex + L.perPage - 1)
  local y = LIST_START_Y

  for i = startIndex, endIndex do
    if y > L.listMaxY then break end
    local c = controllers[i]
    local name = c.mobName or "Unknown"
    local selected = (c.mobName == activeMob)

    local fg, bg
    if selected then
      fg, bg = colors.lightGray, colors.gray
    else
      fg, bg = colors.white, colors.lightGray
    end

    local label = selected and (name .. " (active)") or name
    drawButton(L.innerX, y, L.btnW, label, fg, bg)
    y = y + BUTTON_STEP
  end

  -- Page navigation bar
  local canPrev = currentPage > 1
  local canNext = currentPage < L.totalPages
  drawButton(L.prevX, L.pageBarY, L.navW, "< Prev",
    canPrev and colors.white or colors.gray,
    canPrev and colors.purple or colors.gray)
  drawButton(L.pageX, L.pageBarY, L.navW,
    "Page " .. currentPage .. "/" .. L.totalPages,
    colors.white, colors.gray)
  drawButton(L.nextX, L.pageBarY, L.navW, "Next >",
    canNext and colors.white or colors.gray,
    canNext and colors.purple or colors.gray)

  mon.setBackgroundColor(colors.black)
  mon.setTextColor(colors.orange)
  mon.setCursorPos(L.innerX, L.h - 1)
  mon.write(clip(statusMsg or "", L.btnW))

  drawBox(1, 1, L.w, L.h, colors.gray)
  mon.setBackgroundColor(colors.black)
  mon.setTextColor(colors.white)
end

-- Map a touch Y to the absolute controller index on the current page
local function indexFromTouch(y)
  local L = getLayout()
  if y < LIST_START_Y or y > L.listMaxY then return nil end
  local offset = y - LIST_START_Y
  if offset % BUTTON_STEP ~= 0 then return nil end
  local localIndex = (offset / BUTTON_STEP) + 1
  if localIndex < 1 or localIndex > L.perPage then return nil end
  local index = (currentPage - 1) * L.perPage + localIndex
  if index >= 1 and index <= #controllers then
    return index
  end
  return nil
end

local function handlePageTouch(x, y)
  local L = getLayout()
  if y ~= L.pageBarY then return false end

  if x >= L.prevX and x < L.prevX + L.navW then
    if currentPage > 1 then
      currentPage = currentPage - 1
      statusMsg = "Page " .. currentPage .. "/" .. L.totalPages
      draw()
    end
    return true
  end

  if x >= L.nextX and x < L.nextX + L.navW then
    if currentPage < L.totalPages then
      currentPage = currentPage + 1
      statusMsg = "Page " .. currentPage .. "/" .. L.totalPages
      draw()
    end
    return true
  end

  return true -- tapped page label; consume but no action
end

draw()
requestData()

local pollTimer = os.startTimer(POLL_SECONDS)

while true do
  local e, p1, p2, p3, p4 = os.pullEvent()

  if e == "timer" and p1 == pollTimer then
    requestData()
    pollTimer = os.startTimer(POLL_SECONDS)

  elseif e == "modem_message" then
    local ch, msg = p2, p4
    if ch == CHANNEL and type(msg) == "table" then
      if msg.type == "WOOT_DATA" then
        controllers = msg.controllers or {}
        activeMob = msg.activeMob or "None"
        savedMob = msg.savedMob or "None"
        getLayout() -- clamp page
        statusMsg = #controllers .. " loaded - tap to swap"
        draw()
      elseif msg.type == "SWAP_RESULT" then
        statusMsg = msg.message or (msg.ok and "Done" or "Swap failed")
        if msg.activeMob then activeMob = msg.activeMob end
        if msg.savedMob then savedMob = msg.savedMob end
        draw()
      end
    end

  elseif e == "monitor_touch" and p1 == MON_SIDE then
    local x, y = p2, p3
    if y == ACTIVE_Y then
      print("Touch: clear front")
      sendClear()
      draw()
    elseif y == SAVED_Y then
      print("Touch: restore saved")
      sendRestore()
      draw()
    elseif handlePageTouch(x, y) then
      -- handled
    else
      local index = indexFromTouch(y)
      if index then
        local c = controllers[index]
        if c and c.slot then
          if c.mobName == activeMob then
            statusMsg = "Already active"
            draw()
          else
            print("Touch: " .. (c.mobName or "?") .. " slot " .. c.slot)
            sendSwap(c.slot)
            draw()
          end
        end
      end
    end
  elseif e == "monitor_resize" and p1 == MON_SIDE then
    getLayout()
    draw()
  end
end
