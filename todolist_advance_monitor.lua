-- todo.lua - Height-aware paging (wraps drive pages, not fixed task count)
local monSide = "right"

local mon = peripheral.wrap(monSide)
if not mon then error("No monitor on " .. monSide) end

local file = "todo.txt"
local tasks = {}
local currentPage = 1
local taskHitboxes = {}
local pages = {} -- { {first=, last=}, ... }
local prevBtn = nil -- {x, y, w}
local nextBtn = nil

local function loadTasks()
  tasks = {}
  if fs.exists(file) then
    local f = fs.open(file, "r")
    local raw = f.readAll()
    f.close()
    local ok, data = pcall(textutils.unserialise, raw)
    if ok and type(data) == "table" then
      tasks = data
    end
  end
end

local function saveTasks()
  local f = fs.open(file, "w")
  f.write(textutils.serialise(tasks))
  f.close()
end

-- Word-wrap; also breaks overlong words so paging height stays accurate
local function wrapText(text, maxW)
  if not text or text == "" then return {""} end
  if maxW < 1 then maxW = 1 end

  local lines = {}
  local line = ""

  local function pushLine()
    if line ~= "" then
      table.insert(lines, line)
      line = ""
    end
  end

  local function emitChunk(chunk)
    if #chunk <= maxW then
      if line == "" then
        line = chunk
      elseif #line + 1 + #chunk <= maxW then
        line = line .. " " .. chunk
      else
        pushLine()
        line = chunk
      end
      return
    end
    -- Hard-break words longer than the column width
    pushLine()
    local i = 1
    while i <= #chunk do
      table.insert(lines, chunk:sub(i, i + maxW - 1))
      i = i + maxW
    end
  end

  for word in text:gmatch("%S+") do
    emitChunk(word)
  end
  pushLine()

  if #lines == 0 then return {""} end
  return lines
end

local function layout()
  local w, h = mon.getSize()
  local listStartY = 4
  local listEndY = h - 3 -- leave footer (h-1, h)
  local textWidth = math.max(1, w - 7)
  local available = math.max(1, listEndY - listStartY + 1)
  return w, h, listStartY, listEndY, textWidth, available
end

-- Rows used by one task: wrapped lines + 1 blank gap after
local function taskHeight(text, textWidth)
  return #wrapText(text, textWidth) + 1
end

local function rebuildPages()
  local _, _, _, _, textWidth, available = layout()
  pages = {}

  if #tasks == 0 then
    pages = { { first = 1, last = 0 } }
    currentPage = 1
    return
  end

  local i = 1
  while i <= #tasks do
    local first = i
    local used = 0

    while i <= #tasks do
      local need = taskHeight(tasks[i], textWidth)
      -- Always allow at least one task on a page (may clip when drawing)
      if used > 0 and used + need > available then
        break
      end
      used = used + math.min(need, available) -- count at most a full page for a lone long task
      i = i + 1
      if used >= available then
        break
      end
    end

    table.insert(pages, { first = first, last = i - 1 })
  end

  if currentPage > #pages then currentPage = #pages end
  if currentPage < 1 then currentPage = 1 end
end

local function drawBackground()
  local w = mon.getSize()
  mon.setBackgroundColor(colors.black)
  mon.clear()
  mon.setBackgroundColor(colors.blue)
  for x = 1, w do
    mon.setCursorPos(x, 1)
    mon.write(" ")
    mon.setCursorPos(x, 2)
    mon.write(" ")
  end
  mon.setBackgroundColor(colors.black)
end

local function drawList()
  rebuildPages()
  taskHitboxes = {}

  local w, h, listStartY, listEndY, textWidth = layout()
  drawBackground()

  local page = pages[currentPage] or { first = 1, last = 0 }
  local totalPages = math.max(1, #pages)

  mon.setBackgroundColor(colors.blue)
  mon.setTextColor(colors.white)
  mon.setCursorPos(3, 1)
  local title = string.format("TODO (%d)  %d/%d", #tasks, currentPage, totalPages)
  if #title > w - 4 then title = title:sub(1, w - 4) end
  mon.write(title)

  mon.setBackgroundColor(colors.black)
  local y = listStartY

  if #tasks == 0 then
    mon.setTextColor(colors.lightGray)
    mon.setCursorPos(3, y)
    mon.write("No tasks - press Enter on computer")
  else
    for i = page.first, page.last do
      if y > listEndY then break end

      local startY = y
      mon.setTextColor(colors.white)
      mon.setCursorPos(2, y)
      mon.write(tostring(i) .. ".")

      mon.setTextColor(colors.lightGray)
      local wrapped = wrapText(tasks[i], textWidth)
      local drawn = 0

      for _, txt in ipairs(wrapped) do
        if y > listEndY then
          -- Clip leftover wrap onto this page
          mon.setCursorPos(6, listEndY)
          mon.setTextColor(colors.gray)
          mon.write("...")
          break
        end
        mon.setCursorPos(6, y)
        mon.write(txt:sub(1, textWidth))
        y = y + 1
        drawn = drawn + 1
      end

      local endY = math.max(startY, y - 1)
      table.insert(taskHitboxes, { startY = startY, endY = endY, index = i })

      -- Gap between tasks (if room)
      if y <= listEndY and i < page.last then
        y = y + 1
      end
    end
  end

  -- Footer: dark bar + high-contrast hint; colored nav buttons
  mon.setBackgroundColor(colors.black)
  for x = 1, w do
    mon.setCursorPos(x, h - 1)
    mon.write(" ")
    mon.setCursorPos(x, h)
    mon.write(" ")
  end

  -- Hint row (white on black — readable on advanced monitors)
  local hint = "Tap a task to delete it"
  mon.setBackgroundColor(colors.black)
  mon.setTextColor(colors.white)
  mon.setCursorPos(math.max(1, math.floor((w - #hint) / 2) + 1), h - 1)
  if #hint > w then
    mon.setCursorPos(1, h - 1)
    mon.write(hint:sub(1, w))
  else
    mon.write(hint)
  end

  local canPrev = currentPage > 1
  local canNext = currentPage < totalPages
  local prevLabel = "< Prev"
  local nextLabel = "Next >"
  local prevW = #prevLabel + 2
  local nextW = #nextLabel + 2
  local prevX = 2
  local nextX = w - nextW

  mon.setBackgroundColor(canPrev and colors.green or colors.gray)
  mon.setTextColor(canPrev and colors.white or colors.lightGray)
  mon.setCursorPos(prevX, h)
  mon.write(" " .. prevLabel .. " ")

  -- Page indicator centered (only if it won't collide with buttons)
  local mid = string.format("%d / %d", currentPage, totalPages)
  local midX = math.max(1, math.floor((w - #mid) / 2) + 1)
  if midX > prevX + prevW and midX + #mid - 1 < nextX then
    mon.setBackgroundColor(colors.black)
    mon.setTextColor(colors.lightBlue)
    mon.setCursorPos(midX, h)
    mon.write(mid)
  end

  mon.setBackgroundColor(canNext and colors.green or colors.gray)
  mon.setTextColor(canNext and colors.white or colors.lightGray)
  mon.setCursorPos(nextX, h)
  mon.write(" " .. nextLabel .. " ")

  prevBtn = { x = prevX, y = h, w = prevW }
  nextBtn = { x = nextX, y = h, w = nextW }

  mon.setBackgroundColor(colors.black)
  mon.setTextColor(colors.white)
end

local function showConfirmation(taskText)
  local w, h = mon.getSize()
  drawBackground()

  mon.setBackgroundColor(colors.red)
  mon.setTextColor(colors.white)
  local header = "DELETE THIS TASK?"
  mon.setCursorPos(math.max(1, math.floor((w - #header) / 2) + 1), 4)
  mon.write(header)

  mon.setBackgroundColor(colors.black)
  mon.setTextColor(colors.lightGray)
  local wrapped = wrapText(taskText, math.max(1, w - 6))
  local y = 6
  for _, line in ipairs(wrapped) do
    if y >= h - 5 then
      mon.setCursorPos(4, y)
      mon.write("...")
      break
    end
    mon.setCursorPos(4, y)
    mon.write(line)
    y = y + 1
  end

  local yesX, noX = 4, math.max(4, w - 12)
  local btnY = h - 3

  mon.setBackgroundColor(colors.green)
  mon.setTextColor(colors.white)
  mon.setCursorPos(yesX, btnY)
  mon.write("  YES  ")

  mon.setBackgroundColor(colors.red)
  mon.setCursorPos(noX, btnY)
  mon.write("  NO  ")

  mon.setBackgroundColor(colors.black)
  return yesX, noX, btnY
end

local function addTask()
  term.clear()
  term.setCursorPos(1, 1)
  term.setTextColor(colors.white)
  write("New task: ")
  local input = read()
  if input and input ~= "" then
    table.insert(tasks, input)
    saveTasks()
    rebuildPages()
    currentPage = #pages
    print("Task added!")
  end
  drawList()
end

loadTasks()
rebuildPages()
drawList()
print("Todo ready. Enter = add task")

while true do
  local e, p1, p2, p3 = os.pullEvent()

  if e == "monitor_touch" and p1 == monSide then
    local clickX, clickY = p2, p3
    local w, h = mon.getSize()

    -- Footer nav (only the actual buttons)
    if prevBtn and clickY == prevBtn.y
      and clickX >= prevBtn.x and clickX < prevBtn.x + prevBtn.w then
      rebuildPages()
      if currentPage > 1 then
        currentPage = currentPage - 1
        drawList()
      end

    elseif nextBtn and clickY == nextBtn.y
      and clickX >= nextBtn.x and clickX < nextBtn.x + nextBtn.w then
      rebuildPages()
      if currentPage < #pages then
        currentPage = currentPage + 1
        drawList()
      end

    else
      for _, box in ipairs(taskHitboxes) do
        if clickY >= box.startY and clickY <= box.endY then
          local idx = box.index
          if idx and tasks[idx] then
            local yesX, noX, btnY = showConfirmation(tasks[idx])
            local yesW, noW = 7, 6

            while true do
              local _, side, cx, cy = os.pullEvent("monitor_touch")
              if side == monSide and cy == btnY then
                if cx >= yesX and cx < yesX + yesW then
                  table.remove(tasks, idx)
                  saveTasks()
                  rebuildPages()
                  print("Task removed.")
                  break
                elseif cx >= noX and cx < noX + noW then
                  print("Cancelled.")
                  break
                end
              end
            end
            drawList()
          end
          break
        end
      end
    end

  elseif e == "key" and p1 == keys.enter then
    addTask()

  elseif e == "monitor_resize" and p1 == monSide then
    rebuildPages()
    drawList()
  end
end
