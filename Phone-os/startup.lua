-- ==========================================
-- POCKET CONTROL OS 98 (26x20 Handheld)
-- ==========================================
peripheral.find("modem", rednet.open)

local STORAGE_PROTOCOL = "base_storage_sync"

-- ==========================================
-- CONFIG: ITEMS TO TRACK IN "PLANT OUTPUT"
-- ==========================================
local trackedPlants = {
  { id = "create:andesite_alloy", label = "Andesite" },
  { id = "minecraft:iron_ingot",   label = "Iron"     },
  { id = "minecraft:gold_ingot",   label = "Gold"     },
  { id = "minecraft:wheat",        label = "Wheat"    },
  { id = "minecraft:dried_kelp",   label = "Kelp"     }
}

-- ==========================================
-- STATE VARIABLES
-- ==========================================
local currentApp = "desktop" -- "desktop", "control", "plant", "storage"
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
-- BLISS WALLPAPER & WIN98 UI PRIMITIVES
-- ==========================================
local function getWallpaperColor(x, y, w, h)
  local nx, ny = x / w, y / h
  local frontHill = 0.56 + 0.08 * math.sin(nx * 4.5 + 0.5)
  local backHill  = 0.52 + 0.06 * math.cos(nx * 5.0 - 0.8)

  if ny >= frontHill then return colors.lime
  elseif ny >= backHill then return colors.green end

  local c1 = ((nx - 0.62) / 0.14)^2 + ((ny - 0.22) / 0.07)^2
  local c2 = ((nx - 0.72) / 0.11)^2 + ((ny - 0.25) / 0.06)^2
  local c3 = ((nx - 0.28) / 0.10)^2 + ((ny - 0.16) / 0.05)^2
  if c1 <= 1.0 or c2 <= 1.0 or c3 <= 1.0 then return colors.white end

  return colors.lightBlue
end

local function drawWallpaper()
  local w, h = term.getSize()
  for y = 1, h - 1 do
    for x = 1, w do
      term.setCursorPos(x, y)
      term.setBackgroundColor(getWallpaperColor(x, y, w, h))
      term.write(" ")
    end
  end
end

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
  return 3, 4, w - 2, h - 3
end

local function drawWindow(title)
  local w, h = term.getSize()
  local x1, y1, x2, y2 = 1, 1, w, h - 1

  drawRaisedPanel(x1, y1, x2, y2, colors.lightGray)

  term.setCursorPos(x1 + 1, y1 + 1)
  term.setBackgroundColor(colors.blue)
  term.setTextColor(colors.white)
  term.write(string.rep(" ", x2 - x1 - 1))
  term.setCursorPos(x1 + 2, y1 + 1)
  term.write(title:sub(1, x2 - x1 - 5))

  term.setCursorPos(x2 - 3, y1 + 1)
  term.setBackgroundColor(colors.red)
  term.setTextColor(colors.white)
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
  local step = 2
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

  local timeStr = textutils.formatTime(os.time(), false)
  local trayW = #timeStr + 3
  term.setCursorPos(w - trayW + 1, h)
  term.setBackgroundColor(colors.gray)
  term.setTextColor(storageConnected and colors.lime or colors.orange)
  term.write("*")
  term.setTextColor(colors.white)
  term.write(" " .. timeStr)
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
-- DESKTOP & APP VIEWS (26x20 POCKET FIT)
-- ==========================================
local desktopIcons = {
  { id = "control", label = "Control Panel", color = colors.green,  glyph = "SW" },
  { id = "plant",   label = "Plant Output ", color = colors.orange, glyph = ">>" },
  { id = "storage", label = "Base Storage ", color = colors.blue,   glyph = "[]" }
}

local function drawDesktop()
  drawWallpaper()
  for i, icon in ipairs(desktopIcons) do
    local x, y = 3, 2 + ((i - 1) * 5)
    drawRaisedPanel(x, y, x + 3, y + 2, icon.color)
    term.setCursorPos(x + 1, y + 1)
    term.setBackgroundColor(icon.color)
    term.setTextColor(colors.white)
    term.write(icon.glyph)

    term.setCursorPos(x + 5, y + 1)
    term.setBackgroundColor(colors.blue)
    term.setTextColor(colors.white)
    term.write(" " .. icon.label .. " ")
  end
end

local function drawControlPanel()
  local ix1, iy1, ix2, iy2 = drawWindow("Control Panel")
  for i, b in ipairs(btns) do
    local by = iy1 + ((i - 1) * 3)
    if by <= iy2 - 2 then
      local isOn = (b.state == "ON")
      term.setCursorPos(ix1, by)
      term.setBackgroundColor(colors.lightGray)
      term.setTextColor(colors.black)
      term.write(b.name)

      -- Explicit ON button (matches ix1+8 .. ix1+12)
      term.setCursorPos(ix1 + 8, by)
      term.setBackgroundColor(isOn and colors.lime or colors.gray)
      term.setTextColor(isOn and colors.black or colors.white)
      term.write(" ON  ")

      -- Explicit OFF button (matches ix1+14 .. ix1+18)
      term.setCursorPos(ix1 + 14, by)
      term.setBackgroundColor((not isOn) and colors.red or colors.gray)
      term.setTextColor(colors.white)
      term.write(" OFF ")
    end
  end

  -- Status bar at bottom of window
  term.setCursorPos(ix1, iy2)
  term.setBackgroundColor(colors.lightGray)
  term.setTextColor(colors.gray)
  term.write(status:sub(1, ix2 - ix1 + 1))
end

local function drawPlantOutput()
  local ix1, iy1, ix2, iy2 = drawWindow("Plant Output")
  drawSunkenBox(ix1, iy1, ix2, iy2, colors.white)

  for i, p in ipairs(trackedPlants) do
    local rowY = iy1 + (i * 2) - 1
    if rowY < iy2 then
      local count = liveTotals[p.id] or 0
      local rate = ratesPerMin[p.id] or 0
      term.setCursorPos(ix1 + 1, rowY)
      term.setBackgroundColor(colors.white)
      term.setTextColor(colors.black)
      term.write(p.label:sub(1, 9))

      local stat = string.format("%d (%d/m)", count, rate)
      term.setCursorPos(ix2 - #stat, rowY)
      term.setTextColor(rate > 0 and colors.green or colors.gray)
      term.write(stat)
    end
  end
end

local function drawStorage()
  local ix1, iy1, ix2, iy2 = drawWindow("Base Storage")
  drawSunkenBox(ix1, iy1, ix2, iy2 - 2, colors.white)

  local list = {}
  for id, count in pairs(liveTotals) do
    table.insert(list, { name = liveNames[id] or id:gsub("^.+:", ""), count = count })
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
local countStr = string.format("%d", item.count)
local maxName = (ix2 - ix1 - 2) - #countStr
term.setCursorPos(ix1 + 1, listTop + i)
term.setBackgroundColor(colors.white)
term.setTextColor(colors.black)
term.write(item.name:sub(1, maxName))
term.setCursorPos(ix2 - #countStr, listTop + i)
term.setTextColor(colors.blue)
term.write(countStr)
end
end
term.setCursorPos(ix1, iy2)
term.setBackgroundColor(colors.gray)
term.setTextColor(colors.white)
term.write(" Next > ")
term.setCursorPos(ix1 + 10, iy2)
term.setBackgroundColor(colors.lightGray)
term.setTextColor(colors.black)
term.write("Pg " .. storagePage .. "/" .. maxPages)
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
elseif event == "rednet_message" then
if p3 == STORAGE_PROTOCOL then
processIncomingStorage(p2)
render()
elseif type(p2) == "string" then
-- Keep pocket button states synced if main monitor toggles something
for _, b in ipairs(btns) do
if p2 == b.msg .. "_on" then
b.state = "ON"
status = "Synced: " .. p2
render()
elseif p2 == b.msg .. "_off" then
b.state = "OFF"
status = "Synced: " .. p2
render()
end
end
end
elseif event == "mouse_click" and p1 == 1 then
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
elseif currentApp ~= "desktop" and y == 2 and x >= w - 3 and x <= w - 1 then
currentApp = "desktop"
render()
elseif currentApp == "desktop" then
for i, icon in ipairs(desktopIcons) do
local dy = 2 + ((i - 1) * 5)
if y >= dy and y <= dy + 2 and x >= 3 and x <= 22 then
currentApp = icon.id
storagePage = 1
render()
break
end
end
elseif currentApp == "control" then
for i, b in ipairs(btns) do
local by = iy1 + ((i - 1) * 3)
if y == by then
if x >= ix1 + 8 and x <= ix1 + 12 then
b.state = "ON"
rednet.broadcast(b.msg .. "_on")
status = "Sent: " .. b.msg .. "_on"
render()
elseif x >= ix1 + 14 and x <= ix1 + 18 then
b.state = "OFF"
rednet.broadcast(b.msg .. "_off")
status = "Sent: " .. b.msg .. "_off"
render()
end
end
end
elseif currentApp == "storage" then
if y == iy2 and x >= ix1 and x <= ix1 + 8 then
storagePage = storagePage + 1
render()
end
end
::continue::
end
end
