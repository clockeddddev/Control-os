-- ==========================================
-- BASE CONTROL OS 98 (Wireless Client)
-- ==========================================
peripheral.find("modem", rednet.open)
local mon = peripheral.find("monitor")
assert(mon, "No monitor attached!")
mon.setTextScale(0.5)
term.redirect(mon)

local STORAGE_PROTOCOL = "base_storage_sync"

-- ==========================================
-- CONFIG: ITEMS TO TRACK IN "PLANT OUTPUT"
-- ==========================================
local trackedPlants = {
  { id = "create:andesite_alloy", label = "Andesite Alloy" },
  { id = "minecraft:iron_ingot",   label = "Iron Ingots"    },
  { id = "minecraft:gold_ingot",   label = "Gold Ingots"    },
  { id = "minecraft:wheat",        label = "Wheat Farm"     },
  { id = "minecraft:dried_kelp",   label = "Kelp Factory"   }
}

-- ==========================================
-- STATE VARIABLES
-- ==========================================
local currentApp = "desktop"
local startMenuOpen = false
local status = "Ready"
local storagePage = 1
local storageConnected = false

local liveTotals = {}
local liveNames = {}

local btns = {
  { name = "LIGHTS", state = "OFF", msg = "lights" },
  { name = "DOOR  ", state = "OFF", msg = "door"   },
  { name = "FARM  ", state = "OFF", msg = "farm"   },
  { name = "ALARM ", state = "OFF", msg = "alarm"  }
}

local lastCounts = {}
local ratesPerMin = {}
local lastScanTime = os.epoch("utc") / 1000

local function processIncomingStorage(data)
  if type(data) ~= "table" or not data.totals then return end
  liveTotals = data.totals
  liveNames = data.names or {}
  storageConnected = true

  local now = os.epoch("utc") / 1000
  local elapsed = now - lastScanTime
  if elapsed >= 1 then
    for _, p in ipairs(trackedPlants) do
      local current = liveTotals[p.id] or 0
      if lastCounts[p.id] ~= nil then
        local diff = current - lastCounts[p.id]
        ratesPerMin[p.id] = math.floor((diff / elapsed) * 60)
      else
        ratesPerMin[p.id] = 0
      end
      lastCounts[p.id] = current
    end
    lastScanTime = now
  end
end

-- ==========================================
-- WIN98 UI DRAWING PRIMITIVES
-- ==========================================
local function fillRect(x1, y1, x2, y2, bg)
  if x2 < x1 or y2 < y1 then return end
  term.setBackgroundColor(bg)
  for y = y1, y2 do
    term.setCursorPos(x1, y)
    term.write(string.rep(" ", x2 - x1 + 1))
  end
end

local function drawRaisedPanel(x1, y1, x2, y2, bg)
  fillRect(x1, y1, x2, y2, bg or colors.lightGray)
  term.setBackgroundColor(colors.white)
  term.setCursorPos(x1, y1)
  term.write(string.rep(" ", x2 - x1))
  for y = y1, y2 - 1 do
    term.setCursorPos(x1, y)
    term.write(" ")
  end
  term.setBackgroundColor(colors.gray)
  term.setCursorPos(x1, y2)
  term.write(string.rep(" ", x2 - x1 + 1))
  for y = y1 + 1, y2 do
    term.setCursorPos(x2, y)
    term.write(" ")
  end
end

local function drawSunkenBox(x1, y1, x2, y2, bg)
  fillRect(x1, y1, x2, y2, bg or colors.white)
  term.setBackgroundColor(colors.gray)
  term.setCursorPos(x1, y1)
  term.write(string.rep(" ", x2 - x1))
  for y = y1, y2 - 1 do
    term.setCursorPos(x1, y)
    term.write(" ")
  end
  term.setBackgroundColor(colors.white)
  term.setCursorPos(x1, y2)
  term.write(string.rep(" ", x2 - x1 + 1))
  for y = y1 + 1, y2 do
    term.setCursorPos(x2, y)
    term.write(" ")
  end
end

local function getWindowInnerBounds()
  local w, h = term.getSize()
  local x1, y1 = 2, 2
  local x2, y2 = w - 1, h - 2
  return x1 + 2, y1 + 3, x2 - 2, y2 - 1
end

local function drawWindow(title)
  local w, h = term.getSize()
  local x1, y1 = 2, 2
  local x2, y2 = w - 1, h - 2

  drawRaisedPanel(x1, y1, x2, y2, colors.lightGray)

  term.setCursorPos(x1 + 1, y1 + 1)
  term.setBackgroundColor(colors.blue)
  term.setTextColor(colors.white)
  term.write(string.rep(" ", x2 - x1 - 1))
  term.setCursorPos(x1 + 2, y1 + 1)
  term.write(title:sub(1, x2 - x1 - 6))

  term.setCursorPos(x2 - 3, y1 + 1)
  term.setBackgroundColor(colors.lightGray)
  term.setTextColor(colors.black)
  term.write(" X ")

  return getWindowInnerBounds()
end

-- ==========================================
-- TASKBAR & START MENU
-- ==========================================
local startItems = {
  { id = "control", label = "Control Panel", color = colors.green  },
  { id = "plant",   label = "Plant Output ", color = colors.orange },
  { id = "storage", label = "Base Storage ", color = colors.cyan   },
  { id = "desktop", label = "Show Desktop ", color = colors.blue   }
}

local function getStartMenuBounds()
  local _, h = term.getSize()
  local compact = (h < 14)
  local step = compact and 1 or 2
  local top = math.max(1, h - (#startItems * step) - 1)
  return 1, top, 20, h - 1, step
end

local function drawTaskbar()
  local w, h = term.getSize()
  term.setCursorPos(1, h)
  term.setBackgroundColor(colors.lightGray)
  term.clearLine()

  term.setCursorPos(1, h)
  term.setBackgroundColor(startMenuOpen and colors.gray or colors.green)
  term.setTextColor(colors.white)
  term.write(" Start ")

  if currentApp ~= "desktop" then
    local tabNames = {
      control = "Control Panel",
      plant   = "Plant Output",
      storage = "Base Storage"
    }
    term.setCursorPos(9, h)
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    term.write(" " .. (tabNames[currentApp] or currentApp) .. " ")
  end

  local timeStr = textutils.formatTime(os.time(), false)
  local trayW = #timeStr + 4
  term.setCursorPos(w - trayW + 1, h)
  term.setBackgroundColor(colors.gray)
  term.setTextColor(storageConnected and colors.lime or colors.orange)
  term.write(" *")
  term.setTextColor(colors.white)
  term.write(" " .. timeStr .. " ")
end

local function drawStartMenu()
  local x1, top, x2, bottom, step = getStartMenuBounds()
  drawRaisedPanel(x1, top, x2, bottom, colors.lightGray)

  for y = top + 1, bottom - 1 do
    term.setCursorPos(x1 + 1, y)
    term.setBackgroundColor(colors.blue)
    term.setTextColor(colors.lightGray)
    term.write("98")
  end

  for i, item in ipairs(startItems) do
    local y = top + 1 + ((i - 1) * step)
    if y < bottom then
      term.setCursorPos(x1 + 4, y)
      term.setBackgroundColor(item.color)
      term.write(" ")
      term.setBackgroundColor(colors.lightGray)
      term.setTextColor(colors.black)
      term.write(" " .. item.label:sub(1, x2 - x1 - 6))
    end
  end
end

-- ==========================================
-- DESKTOP & APP VIEWS
-- ==========================================
local desktopIcons = {
  { id = "control", label = "Control Panel", color = colors.green,  glyph = "SW" },
  { id = "plant",   label = "Plant Output ", color = colors.orange, glyph = ">>" },
  { id = "storage", label = "Base Storage ", color = colors.blue,   glyph = "[]" }
}

local function getDesktopIconPos(i)
  local _, h = term.getSize()
  local step = (h <= 14) and 3 or 4
  return 3, 2 + ((i - 1) * step)
end

local function drawDesktop()
  term.setBackgroundColor(colors.cyan)
  term.clear()

  for i, icon in ipairs(desktopIcons) do
    local ix, iy = getDesktopIconPos(i)
    term.setCursorPos(ix, iy)
    term.setBackgroundColor(colors.white)
    term.setTextColor(colors.black)
    term.write(" ")
    term.setBackgroundColor(icon.color)
    term.setTextColor(colors.white)
    term.write(icon.glyph)
    term.setBackgroundColor(colors.gray)
    term.write(" ")

    term.setCursorPos(ix + 5, iy)
    term.setBackgroundColor(colors.cyan)
    term.setTextColor(colors.white)
    term.write(icon.label)
  end
end

local function getControlBtnY(i, iy1, iy2)
  local avail = math.max(1, (iy2 - 1) - iy1)
  local step = math.max(1, math.min(3, math.floor(avail / #btns)))
  return iy1 + ((i - 1) * step)
end

local function drawControlPanel()
  term.setBackgroundColor(colors.cyan)
  term.clear()
  local ix1, iy1, ix2, iy2 = drawWindow("Control Panel")

  for i, b in ipairs(btns) do
    local by = getControlBtnY(i, iy1, iy2)
    if by < iy2 then
      term.setCursorPos(ix1 + 1, by)
      term.setBackgroundColor(colors.lightGray)
      term.setTextColor(colors.black)
      term.write(b.name)

      term.setCursorPos(ix1 + 9, by)
      term.setBackgroundColor(b.state == "ON" and colors.lime or colors.gray)
      term.setTextColor(b.state == "ON" and colors.black or colors.white)
      term.write(" ON ")

      term.setCursorPos(ix1 + 15, by)
      term.setBackgroundColor(b.state == "OFF" and colors.red or colors.gray)
      term.setTextColor(colors.white)
      term.write(" OFF ")
    end
  end

  term.setCursorPos(ix1, iy2)
  term.setBackgroundColor(colors.gray)
  term.setTextColor(colors.white)
  local innerW = math.max(1, ix2 - ix1 + 1)
  term.write((" " .. status):sub(1, innerW) .. string.rep(" ", math.max(0, innerW - #status - 1)))
end

local function drawPlantOutput()
  term.setBackgroundColor(colors.cyan)
  term.clear()
  local ix1, iy1, ix2, iy2 = drawWindow("Plant Output")

  drawSunkenBox(ix1, iy1, ix2, iy2 - 1, colors.white)

  local innerW = math.max(1, (ix2 - 1) - (ix1 + 1) + 1)
  term.setCursorPos(ix1 + 1, iy1 + 1)
  term.setBackgroundColor(colors.lightGray)
  term.setTextColor(colors.black)
  local hdr = "ITEM          STOCK   RATE"
  term.write(hdr:sub(1, innerW) .. string.rep(" ", math.max(0, innerW - #hdr)))

  for i, p in ipairs(trackedPlants) do
    local y = iy1 + 1 + i
    if y <= iy2 - 2 then
      local count = liveTotals[p.id] or 0
      local rate = ratesPerMin[p.id] or 0

      term.setCursorPos(ix1 + 1, y)
      term.setBackgroundColor(colors.white)
      term.setTextColor(colors.black)
      term.write(string.format("%-13s", p.label:sub(1, 13)))

      term.setCursorPos(ix1 + 15, y)
      term.setTextColor(colors.blue)
      term.write(string.format("%-7d", count))

      term.setCursorPos(ix1 + 23, y)
      term.setTextColor(rate > 0 and colors.green or colors.gray)
      term.write((rate >= 0 and "+" or "") .. rate .. "/m")
    end
  end

  term.setCursorPos(ix1, iy2)
term.setBackgroundColor(colors.lightGray)
term.setTextColor(colors.black)
term.write(storageConnected and "Status: Live Wireless Sync" or "Status: Waiting for Slave...")
end
local function drawStorage()
term.setBackgroundColor(colors.cyan)
term.clear()
local ix1, iy1, ix2, iy2 = drawWindow("Base Storage")
drawSunkenBox(ix1, iy1, ix2, iy2 - 2, colors.white)
local list = {}
for id, count in pairs(liveTotals) do
table.insert(list, { name = liveNames[id] or id, count = count })
end
table.sort(list, function(a, b) return a.count > b.count end)
local listTop = iy1 + 1
local listBottom = iy2 - 3
local perPage = math.max(1, listBottom - listTop + 1)
local maxPages = math.max(1, math.ceil(#list / perPage))
if storagePage > maxPages then storagePage = 1 end
local startIdx = (storagePage - 1) * perPage + 1
for i = 0, perPage - 1 do
local item = list[startIdx + i]
if item then
term.setCursorPos(ix1 + 1, listTop + i)
term.setBackgroundColor(colors.white)
term.setTextColor(colors.black)
term.write(string.format("%-18s", item.name:sub(1, 18)))
term.setCursorPos(ix2 - 7, listTop + i)
term.setTextColor(colors.blue)
term.write(string.format("%6d", item.count))
end
end
term.setCursorPos(ix1, iy2)
term.setBackgroundColor(colors.gray)
term.setTextColor(colors.white)
term.write(" Next Page > ")
term.setCursorPos(ix1 + 15, iy2)
term.setBackgroundColor(colors.lightGray)
term.setTextColor(colors.black)
term.write("Page " .. storagePage .. "/" .. maxPages)
end
-- ==========================================
-- MASTER RENDER & EVENT LOOP
-- ==========================================
local function render()
if currentApp == "desktop" then
drawDesktop()
elseif currentApp == "control" then
drawControlPanel()
elseif currentApp == "plant" then
drawPlantOutput()
elseif currentApp == "storage" then
drawStorage()
end
drawTaskbar()
if startMenuOpen then
drawStartMenu()
end
end
render()
local clockTimer = os.startTimer(5)
while true do
local event, p1, p2, p3 = os.pullEvent()
if event == "timer" and p1 == clockTimer then
render()
clockTimer = os.startTimer(5)
elseif event == "rednet_message" and p3 == STORAGE_PROTOCOL then
processIncomingStorage(p2)
render()
elseif event == "monitor_touch" then
local x, y = p2, p3
local w, h = term.getSize()
local ix1, iy1, _, iy2 = getWindowInnerBounds()
if startMenuOpen then
local sx1, top, sx2, bottom, step = getStartMenuBounds()
local clickedMenu = false
if x >= sx1 and x <= sx2 and y >= top and y <= bottom then
for i, item in ipairs(startItems) do
local iy = top + 1 + ((i - 1) * step)
if y == iy then
currentApp = item.id
storagePage = 1
clickedMenu = true
break
end
end
end
startMenuOpen = false
render()
if clickedMenu then goto continue end
end
if y == h and x >= 1 and x <= 7 then
startMenuOpen = not startMenuOpen
render()
elseif currentApp ~= "desktop" and y == 3 and x >= w - 4 and x <= w - 2 then
currentApp = "desktop"
render()
elseif currentApp == "desktop" then
for i, icon in ipairs(desktopIcons) do
local dx, dy = getDesktopIconPos(i)
if y == dy and x >= dx and x <= dx + 18 then
currentApp = icon.id
storagePage = 1
render()
break
end
end
elseif currentApp == "control" then
for i, b in ipairs(btns) do
local by = getControlBtnY(i, iy1, iy2)
if y == by then
if x >= ix1 + 9 and x <= ix1 + 12 then
b.state = "ON"
rednet.broadcast(b.msg .. "_on")
status = "Sent: " .. b.msg .. "_on"
render()
elseif x >= ix1 + 15 and x <= ix1 + 19 then
b.state = "OFF"
rednet.broadcast(b.msg .. "_off")
status = "Sent: " .. b.msg .. "_off"
render()
end
end
end
elseif currentApp == "storage" then
if y == iy2 and x >= ix1 and x <= ix1 + 12 then
storagePage = storagePage + 1
render()
end
end
::continue::
end
end
