-- todo.lua - Clean paging version
local monSide = "right"

local mon = peripheral.wrap(monSide)
if not mon then error("No monitor on "..monSide) end

local file = "todo.txt"
local tasks = {}
local currentPage = 1
local tasksPerPage = 8   -- Adjust this number if you want more/less

local taskHitboxes = {}

local function loadTasks()
  if fs.exists(file) then
    local f = fs.open(file, "r")
    tasks = textutils.unserialise(f.readAll()) or {}
    f.close()
  end
end

local function saveTasks()
  local f = fs.open(file, "w")
  f.write(textutils.serialise(tasks))
  f.close()
end

local function wrapText(text, maxW)
  if not text or text == "" then return {""} end
  local lines = {}
  local line = ""
  for word in text:gmatch("%S+") do
    if #line + #word + 1 > maxW then
      table.insert(lines, line)
      line = word
    else
      line = line == "" and word or line .. " " .. word
    end
  end
  if line ~= "" then table.insert(lines, line) end
  return lines
end

local function drawBackground()
  local w, h = mon.getSize()
  mon.setBackgroundColor(colors.black)
  mon.clear()
  mon.setBackgroundColor(colors.blue)
  for x=1,w do
    mon.setCursorPos(x,1); mon.write(" ")
    mon.setCursorPos(x,2); mon.write(" ")
  end
end

local function drawList()
  taskHitboxes = {}
  local w, h = mon.getSize()
  drawBackground()

  mon.setTextColor(colors.white)
  mon.setCursorPos(3,1)
  mon.write("TODO LIST ("..#tasks.." total) - Page "..currentPage)

  local startTask = (currentPage-1) * tasksPerPage + 1
  local endTask = math.min(startTask + tasksPerPage - 1, #tasks)

  local y = 4

  for i = startTask, endTask do
    local startY = y
    mon.setBackgroundColor(colors.black)
    mon.setTextColor(colors.white)
    mon.setCursorPos(2, y)
    mon.write(i .. ".")

    mon.setTextColor(colors.lightGray)
    local wrapped = wrapText(tasks[i], w-7)

    for _, txt in ipairs(wrapped) do
      mon.setCursorPos(6, y)
      mon.write(txt)
      y = y + 1
    end

    table.insert(taskHitboxes, {startY = startY, endY = y, index = i})
    y = y + 1
  end

  -- Footer
  mon.setBackgroundColor(colors.gray)
  for x=1,w do
    mon.setCursorPos(x, h-1); mon.write(" ")
    mon.setCursorPos(x, h); mon.write(" ")
  end

  mon.setTextColor(colors.yellow)
  mon.setCursorPos(3, h-1)
  mon.write("Click task to remove")

  mon.setTextColor(colors.lime)
  mon.setCursorPos(3, h)
  mon.write("< Prev")
  mon.setCursorPos(w-8, h)
  mon.write("Next >")
end

local function showConfirmation(taskText)
  local w, h = mon.getSize()
  drawBackground()

  mon.setBackgroundColor(colors.red)
  mon.setTextColor(colors.white)
  mon.setCursorPos(math.floor(w/2)-7, 5)
  mon.write("DELETE THIS TASK?")

  mon.setBackgroundColor(colors.black)
  mon.setTextColor(colors.lightGray)
  local wrapped = wrapText(taskText, w-10)
  for i, line in ipairs(wrapped) do
    mon.setCursorPos(5, 8+i)
    mon.write(line)
  end

  mon.setBackgroundColor(colors.green)
  mon.setCursorPos(8, h-4)
  mon.write("   YES   ")

  mon.setBackgroundColor(colors.red)
  mon.setCursorPos(w-18, h-4)
  mon.write("   NO   ")
end

local function addTask()
  term.clear()
  term.setCursorPos(1,1)
  write("New task: ")
  local input = read()
  if input and input ~= "" then
    table.insert(tasks, input)
    saveTasks()
    print("Task added!")
    drawList()
  end
end

-- Main
loadTasks()
drawList()

while true do
  local e, p1, p2, p3 = os.pullEvent()

  if e == "monitor_touch" then
    local clickX, clickY = p2, p3
    local w, h = mon.getSize()

    for _, box in ipairs(taskHitboxes) do
      if clickY >= box.startY and clickY <= box.endY then
        local idx = box.index
        if idx and idx <= #tasks then
          showConfirmation(tasks[idx])

          while true do
            local ev, _, cx, cy = os.pullEvent("monitor_touch")
            if cy >= h-5 then
              if cx <= w/2 then
                table.remove(tasks, idx)
                saveTasks()
                print("Task removed.")
              else
                print("Cancelled.")
              end
              break
            end
          end
          drawList()
          break
        end
      end
    end

    if clickY >= h-1 then
      if clickX < w/2 then
        if currentPage > 1 then currentPage = currentPage - 1 end
      else
        if currentPage * tasksPerPage < #tasks then
          currentPage = currentPage + 1
        else
          currentPage = 1
        end
      end
      drawList()
    end

  elseif e == "key" and p1 == keys.enter then
    addTask()
  end
end
