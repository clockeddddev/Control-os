-- ==========================================
-- BASE CONTROL OS 98 - CC:DirectGPU Edition
-- ==========================================
peripheral.find("modem", rednet.open)
local gpu = peripheral.find("directgpu")
assert(gpu, "No DirectGPU block attached!")

gpu.clearAllDisplays()
local disp = gpu.autoDetectAndCreateDisplay()
assert(disp, "DirectGPU could not find a monitor!")

local info = gpu.getDisplayInfo(disp)
local W, H = info.pixelWidth, info.pixelHeight
local FONT = "Arial"

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
local currentApp = "desktop" -- "desktop", "control", "plant", "storage"
local startMenuOpen = false
local status = "Ready"
local storagePage = 1
local storageConnected = false

local liveTotals = {}
local liveNames = {}

local btns = {
  { name = "Base Lights", state = "OFF", msg = "lights" },
  { name = "Blast Door",  state = "OFF", msg = "door"   },
  { name = "Create Farm", state = "OFF", msg = "farm"   },
  { name = "Base Alarm",  state = "OFF", msg = "alarm"  }
}

local lastCounts = {}
local ratesPerMin = {}
local lastScanTime = os.epoch("utc") / 1000

-- ==========================================
-- STORAGE SYNC HANDLER
-- ==========================================
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
-- WIN98 PIXEL DRAWING PRIMITIVES
-- ==========================================
local function drawBevelBox(x, y, w, h, raised, fillR, fillG, fillB)
  local r, g, b = fillR or 192, fillG or 192, fillB or 192
  gpu.fillRect(disp, x, y, w, h, r, g, b)

  if raised then
    -- Outer top/left white, bottom/right black
    gpu.drawLine(disp, x, y, x + w - 1, y, 255, 255, 255)
    gpu.drawLine(disp, x, y, x, y + h - 1, 255, 255, 255)
    gpu.drawLine(disp, x, y + h - 1, x + w - 1, y + h - 1, 0, 0, 0)
    gpu.drawLine(disp, x + w - 1, y, x + w - 1, y + h - 1, 0, 0, 0)
    -- Inner bottom/right dark gray
    gpu.drawLine(disp, x + 1, y + h - 2, x + w - 2, y + h - 2, 128, 128, 128)
    gpu.drawLine(disp, x + w - 2, y + 1, x + w - 2, y + h - 2, 128, 128, 128)
  else
    -- Sunken: top/left dark gray + black, bottom/right white
    gpu.drawLine(disp, x, y, x + w - 1, y, 128, 128, 128)
    gpu.drawLine(disp, x, y, x, y + h - 1, 128, 128, 128)
    gpu.drawLine(disp, x + 1, y + 1, x + w - 2, y + 1, 0, 0, 0)
    gpu.drawLine(disp, x + 1, y + 1, x + 1, y + h - 2, 0, 0, 0)
    gpu.drawLine(disp, x, y + h - 1, x + w - 1, y + h - 1, 255, 255, 255)
    gpu.drawLine(disp, x + w - 1, y, x + w - 1, y + h - 1, 255, 255, 255)
  end
end

-- Classic Win98 Blue-to-LightBlue Gradient Bar
local function drawTitleGradient(x, y, w, h)
  local steps = 24
  local sliceW = math.ceil(w / steps)
  for i = 0, steps - 1 do
    local t = i / (steps - 1)
    local r = math.floor(0   + t * 16)
    local g = math.floor(0   + t * 132)
    local b = math.floor(128 + t * 80)
    local sx = x + i * sliceW
    local sw = math.min(sliceW, (x + w) - sx)
    if sw > 0 then
      gpu.fillRect(disp, sx, y, sw, h, r, g, b)
    end
  end
end

-- Mini 4-color Windows Flag for Start Button
local function drawWinLogo(x, y)
  gpu.fillRect(disp, x,     y,     5, 5, 255, 60,  30)  -- Red
  gpu.fillRect(disp, x + 6, y,     5, 5, 60,  200, 60)  -- Green
  gpu.fillRect(disp, x,     y + 6, 5, 5, 40,  120, 255) -- Blue
  gpu.fillRect(disp, x + 6, y + 6, 5, 5, 255, 210, 30)  -- Yellow
end

-- ==========================================
-- LAYOUT & BOUNDS HELPERS
-- ==========================================
local TASKBAR_H = 28

local function getWindowRect()
  local pad = math.max(12, math.floor(W * 0.04))
  local wx = pad
  local wy = pad
  local ww = W - (pad * 2)
  local wh = H - TASKBAR_H - (pad * 2)
  return wx, wy, ww, wh
end

local function getCloseBtnRect()
  local wx, wy, ww, _ = getWindowRect()
  return wx + ww - 24, wy + 6, 18, 16
end

-- ==========================================
-- WINDOW FRAME
-- ==========================================
local function drawWindow(title)
  local wx, wy, ww, wh = getWindowRect()
  drawBevelBox(wx, wy, ww, wh, true, 192, 192, 192)

  -- Title Bar
  local tx, ty, tw, th = wx + 4, wy + 4, ww - 8, 20
  drawTitleGradient(tx, ty, tw, th)
  gpu.drawText(disp, title, tx + 6, ty + 4, 255, 255, 255, FONT, 12, "bold")

  -- [X] Close Button
  local cx, cy, cw, ch = getCloseBtnRect()
  drawBevelBox(cx, cy, cw, ch, true, 192, 192, 192)
  gpu.drawLine(disp, cx + 5, cy + 4, cx + cw - 6, cy + ch - 5, 0, 0, 0)
  gpu.drawLine(disp, cx + cw - 6, cy + 4, cx + 5, cy + ch - 5, 0, 0, 0)

  -- Return Inner Client Bounds
  return wx + 8, wy + 28, ww - 16, wh - 36
end

-- ==========================================
-- DESKTOP & PIXEL ICONS
-- ==========================================
local desktopIcons = {
  { id = "control", label = "Control Panel", r = 40,  g = 170, b = 70  },
  { id = "plant",   label = "Plant Output",  r = 230, g = 130, b = 30  },
  { id = "storage", label = "Base Storage",  r = 40,  g = 110, b = 220 }
}

local function getIconRect(i)
  return 20, 20 + ((i - 1) * 74), 76, 62
end

local function drawPixelIcon(id, x, y)
  if id == "control" then
    -- Switch Panel Icon
    drawBevelBox(x, y, 32, 32, true, 192, 192, 192)
    gpu.fillRect(disp, x + 5, y + 6,  22, 8, 40, 200, 60)
    gpu.fillRect(disp, x + 5, y + 18, 22, 8, 210, 50, 50)
  elseif id == "plant" then
    -- Factory Chart Icon
    drawBevelBox(x, y, 32, 32, false, 255, 255, 255)
    gpu.fillRect(disp, x + 5,  y + 18, 5, 10, 40, 120, 240)
    gpu.fillRect(disp, x + 13, y + 12, 5, 16, 40, 190, 80)
    gpu.fillRect(disp, x + 21, y + 6,  5, 22, 240, 140, 30)
  elseif id == "storage" then
    -- Create Brass/Vault Crate Icon
    drawBevelBox(x, y, 32, 32, true, 180, 130, 60)
    gpu.fillRect(disp, x + 4, y + 4, 24, 24, 215, 165, 80)
    gpu.drawLine(disp, x + 4, y + 16, x + 27, y + 16, 110, 75, 30)
    gpu.fillRect(disp, x + 13, y + 13, 6, 6, 90, 90, 100)
  end
end

local function drawDesktop()
  gpu.clear(disp, 0, 128, 128) -- Classic Win98 Teal

  for i, icon in ipairs(desktopIcons) do
    local ix, iy, iw, _ = getIconRect(i)
    drawPixelIcon(icon.id, ix + 22, iy)
    local tw = gpu.measureText(icon.label, FONT, 11, "plain").width or 64
    local tx = ix + math.floor((iw - tw) / 2)
    gpu.drawText(disp, icon.label, tx, iy + 36, 255, 255, 255, FONT, 11, "plain")
  end
end

-- ==========================================
-- APP 1: CONTROL PANEL
-- ==========================================
local function getSwitchRects(i, cx, cy, cw, ch)
  local usableH = ch - 24
  local rowH = math.floor(usableH / #btns)
  local ry = cy + ((i - 1) * rowH) + 6
  local btnW = 48
  local btnH = math.min(24, rowH - 8)
  local offX = cx + cw - btnW - 8
  local onX  = offX - btnW - 8
  return ry, onX, offX, btnW, btnH
end

local function drawControlPanel()
  gpu.clear(disp, 0, 128, 128)
  local cx, cy, cw, ch = drawWindow("Control Panel")

  for i, b in ipairs(btns) do
    local ry, onX, offX, btnW, btnH = getSwitchRects(i, cx, cy, cw, ch)
    gpu.drawText(disp, b.name, cx + 8, ry + 5, 0, 0, 0, FONT, 13, "bold")

    -- [ ON ] Button
    local isOn = (b.state == "ON")
    drawBevelBox(onX, ry, btnW, btnH, not isOn, isOn and 60 or 192, isOn and 210 or 192, isOn and 80 or 192)
    gpu.drawText(disp, "ON", onX + 14, ry + 5, 0, 0, 0, FONT, 12, "bold")

    -- [ OFF ] Button
    local isOff = (b.state == "OFF")
    drawBevelBox(offX, ry, btnW, btnH, not isOff, isOff and 210 or 192, isOff and 60 or 192, isOff and 60 or 192)
    gpu.drawText(disp, "OFF", offX + 11, ry + 5, isOff and 255 or 0, isOff and 255 or 0, isOff and 255 or 0, FONT, 12, "bold")
  end

  -- Sunken Status Bar
  drawBevelBox(cx, cy + ch - 20, cw, 20, false, 192, 192, 192)
  gpu.drawText(disp, status, cx + 6, cy + ch - 16, 0, 0, 0, FONT, 11, "plain")
end

-- ==========================================
-- APP 2: PLANT OUTPUT
-- ==========================================
local function drawPlantOutput()
  gpu.clear(disp, 0, 128, 128)
  local cx, cy, cw, ch = drawWindow("Plant Output")

  local listH = ch - 24
  drawBevelBox(cx, cy, cw, listH, false, 255, 255, 255)

  -- Column Header Bar
  drawBevelBox(cx + 2, cy + 2, cw - 4, 20, true, 192, 192, 192)
  local colStock = cx + math.floor(cw * 0.52)
  local colRate  = cx + math.floor(cw * 0.76)

  gpu.drawText(disp, "Factory Line", cx + 8,   cy + 6, 0, 0, 0, FONT, 11, "bold")
  gpu.drawText(disp, "Stock",        colStock, cy + 6, 0, 0, 0, FONT, 11, "bold")
  gpu.drawText(disp, "Rate",         colRate,  cy + 6, 0, 0, 0, FONT, 11, "bold")

  local rowH = math.floor((listH - 26) / #trackedPlants)
  for i, p in ipairs(trackedPlants) do
    local ry = cy + 24 + ((i - 1) * rowH)
    local count = liveTotals[p.id] or 0
    local rate = ratesPerMin[p.id] or 0

    if i % 2 == 0 then
gpu.fillRect(disp, cx + 2, ry, cw - 4, rowH, 242, 245, 250)
end
gpu.drawText(disp, p.label, cx + 8, ry + 4, 0, 0, 0, FONT, 12, "plain")
gpu.drawText(disp, tostring(count), colStock, ry + 4, 0, 0, 160, FONT, 12, "bold")
local rStr = (rate >= 0 and "+" or "") .. rate .. "/m"
local rr, rg, rb = 120, 120, 120
if rate > 0 then rr, rg, rb = 0, 140, 0 end
gpu.drawText(disp, rStr, colRate, ry + 4, rr, rg, rb, FONT, 12, "bold")
end
-- Sunken Status Bar
drawBevelBox(cx, cy + ch - 20, cw, 20, false, 192, 192, 192)
local syncTxt = storageConnected and "Wireless Storage Sync: ONLINE" or "Waiting for Storage Slave..."
gpu.drawText(disp, syncTxt, cx + 6, cy + ch - 16, 0, 0, 0, FONT, 11, "plain")
end
-- ==========================================
-- APP 3: BASE STORAGE EXPLORER
-- ==========================================
local function getNextBtnRect(cx, cy, cw, ch)
return cx, cy + ch - 22, 92, 22
end
local function drawStorage()
gpu.clear(disp, 0, 128, 128)
local cx, cy, cw, ch = drawWindow("Base Storage")
local listH = ch - 28
drawBevelBox(cx, cy, cw, listH, false, 255, 255, 255)
local list = {}
for id, count in pairs(liveTotals) do
table.insert(list, { name = liveNames[id] or id, count = count })
end
table.sort(list, function(a, b) return a.count > b.count end)
local rowH = 20
local perPage = math.max(1, math.floor((listH - 8) / rowH))
local maxPages = math.max(1, math.ceil(#list / perPage))
if storagePage > maxPages then storagePage = 1 end
local startIdx = (storagePage - 1) * perPage + 1
for i = 0, perPage - 1 do
local item = list[startIdx + i]
if item then
local ry = cy + 4 + (i * rowH)
if i % 2 == 1 then
gpu.fillRect(disp, cx + 2, ry, cw - 4, rowH, 242, 245, 250)
end
gpu.drawText(disp, item.name, cx + 8, ry + 4, 0, 0, 0, FONT, 12, "plain")
gpu.drawText(disp, tostring(item.count), cx + cw - 68, ry + 4, 0, 0, 160, FONT, 12, "bold")
end
end
-- Win98 Next Page Button
local bx, by, bw, bh = getNextBtnRect(cx, cy, cw, ch)
drawBevelBox(bx, by, bw, bh, true, 192, 192, 192)
gpu.drawText(disp, "Next Page >", bx + 10, by + 5, 0, 0, 0, FONT, 11, "bold")
gpu.drawText(disp, "Page " .. storagePage .. " of " .. maxPages .. " (" .. #list .. " items)", bx + bw + 12, by + 5, 0, 0, 0, FONT, 11, "plain")
end
-- ==========================================
-- TASKBAR & START MENU
-- ==========================================
local startItems = {
{ id = "control", label = "Control Panel" },
{ id = "plant",   label = "Plant Output"  },
{ id = "storage", label = "Base Storage"  },
{ id = "desktop", label = "Show Desktop"  }
}
local function getStartMenuRect()
local mw = 156
local mh = (#startItems * 28) + 8
return 2, H - TASKBAR_H - mh, mw, mh
end
local function drawTaskbar()
local ty = H - TASKBAR_H
drawBevelBox(0, ty, W, TASKBAR_H, true, 192, 192, 192)
-- [Start] Button
drawBevelBox(4, ty + 4, 66, 20, not startMenuOpen, 192, 192, 192)
drawWinLogo(9, ty + 8)
gpu.drawText(disp, "Start", 25, ty + 8, 0, 0, 0, FONT, 12, "bold")
-- Active Window Tab
if currentApp ~= "desktop" then
local tabNames = {
control = "Control Panel",
plant   = "Plant Output",
storage = "Base Storage"
}
drawBevelBox(76, ty + 4, 116, 20, false, 215, 215, 215)
gpu.drawText(disp, tabNames[currentApp] or currentApp, 84, ty + 8, 0, 0, 0, FONT, 11, "bold")
end
-- System Tray
local trayW = 78
local trayX = W - trayW - 4
drawBevelBox(trayX, ty + 4, trayW, 20, false, 192, 192, 192)
-- Wireless Sync Status LED
if storageConnected then
gpu.drawCircle(disp, trayX + 11, ty + 14, 4, 40, 200, 60, true)
else
gpu.drawCircle(disp, trayX + 11, ty + 14, 4, 230, 140, 20, true)
end
local timeStr = textutils.formatTime(os.time(), false)
gpu.drawText(disp, timeStr, trayX + 20, ty + 8, 0, 0, 0, FONT, 11, "plain")
end
local function drawStartMenu()
local mx, my, mw, mh = getStartMenuRect()
drawBevelBox(mx, my, mw, mh, true, 192, 192, 192)
-- Classic Vertical Blue "Win98" Sidebar
gpu.fillRect(disp, mx + 3, my + 3, 20, mh - 6, 0, 0, 128)
gpu.drawText(disp, "98", mx + 6, my + mh - 20, 192, 192, 192, FONT, 12, "bold")
for i, item in ipairs(startItems) do
local iy = my + 4 + ((i - 1) * 28)
drawPixelIcon(item.id == "desktop" and "control" or item.id, mx + 28, iy - 2)
gpu.drawText(disp, item.label, mx + 66, iy + 6, 0, 0, 0, FONT, 12, "plain")
end
end
-- ==========================================
-- MASTER RENDER & HIT-TEST HELPER
-- ==========================================
local function hit(px, py, x, y, w, h)
return px >= x and px <= x + w and py >= y and py <= y + h
end
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
gpu.updateDisplay(disp)
end
-- ==========================================
-- PARALLEL EVENT LOOPS (GPU + REDNET + CLOCK)
-- ==========================================
render()
parallel.waitForAny(
-- Loop 1: DirectGPU Touch / Mouse Input
function()
while true do
if gpu.hasEvents(disp) then
local ev = gpu.pollEvent(disp)
if ev and ev.type == "mouse_click" then
local px, py = ev.x, ev.y
local cx, cy, cw, ch = getWindowRect()
cx, cy, cw, ch = cx + 8, cy + 28, cw - 16, ch - 36
-- 1. Start Menu Clicks
if startMenuOpen then
local mx, my, mw, mh = getStartMenuRect()
local picked = false
if hit(px, py, mx, my, mw, mh) then
for i, item in ipairs(startItems) do
local iy = my + 4 + ((i - 1) * 28)
if hit(px, py, mx + 24, iy, mw - 26, 26) then
currentApp = item.id
storagePage = 1
picked = true
break
end
end
end
startMenuOpen = false
render()
if picked then goto next_ev end
end
-- 2. Taskbar [Start] Button
if hit(px, py, 4, H - TASKBAR_H + 4, 66, 20) then
startMenuOpen = not startMenuOpen
render()
-- 3. Window [X] Close Button
elseif currentApp ~= "desktop" and hit(px, py, getCloseBtnRect()) then
currentApp = "desktop"
render()
-- 4. Desktop Icon Clicks
elseif currentApp == "desktop" then
for i, icon in ipairs(desktopIcons) do
if hit(px, py, getIconRect(i)) then
currentApp = icon.id
storagePage = 1
render()
break
end
end
-- 5. Control Panel Switch Clicks
elseif currentApp == "control" then
for i, b in ipairs(btns) do
local ry, onX, offX, btnW, btnH = getSwitchRects(i, cx, cy, cw, ch)
if hit(px, py, onX, ry, btnW, btnH) then
b.state = "ON"
rednet.broadcast(b.msg .. "_on")
status = "Sent: " .. b.msg .. "_on"
render()
elseif hit(px, py, offX, ry, btnW, btnH) then
b.state = "OFF"
rednet.broadcast(b.msg .. "_off")
status = "Sent: " .. b.msg .. "_off"
render()
end
end
-- 6. Base Storage Next Page Button
elseif currentApp == "storage" then
if hit(px, py, getNextBtnRect(cx, cy, cw, ch)) then
storagePage = storagePage + 1
render()
end
end
::next_ev::
end
end
sleep(0.05)
end
end,
-- Loop 2: Wireless Storage Slave & Clock Updates
function()
local clockTimer = os.startTimer(5)
while true do
local event, p1, p2, p3 = os.pullEvent()
if event == "rednet_message" and p3 == STORAGE_PROTOCOL then
processIncomingStorage(p2)
render()
elseif event == "timer" and p1 == clockTimer then
render()
clockTimer = os.startTimer(5)
end
end
end
)
