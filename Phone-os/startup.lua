-- ==========================================
-- POCKET CONTROL OS 98 + CALLING & DOOMSCROLL
-- ==========================================
peripheral.find("modem", rednet.open)

local STORAGE_PROTOCOL = "base_storage_sync"
local CALL_PROTOCOL    = "pocket_phone_call"
local MY_ID            = os.getComputerID()
local MY_NAME          = os.getComputerLabel() or ("Phone-" .. MY_ID)

rednet.host(CALL_PROTOCOL, MY_NAME)

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
local currentApp = "desktop" -- "desktop", "control", "plant", "storage", "phone", "doom"
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

-- ==========================================
-- PHONE / CALLING STATE
-- ==========================================
local callState = "idle" -- "idle", "outgoing", "incoming", "connected"
local peerId = nil
local dialInput = ""
local chatInput = ""
local callLog = {}
local knownPhones = {}

local function refreshPhones()
  knownPhones = {}
  local ids = { rednet.lookup(CALL_PROTOCOL) }
  for _, id in ipairs(ids) do
    if id ~= MY_ID then
      table.insert(knownPhones, id)
    end
  end
end

local function addCallLog(sender, text)
  table.insert(callLog, sender .. ": " .. text)
  if #callLog > 7 then
    table.remove(callLog, 1)
  end
end

local function startCall(targetId)
  if not targetId or targetId == MY_ID then return end
  peerId = targetId
  callState = "outgoing"
  callLog = {}
  rednet.send(peerId, { type = "call_req", from = MY_NAME }, CALL_PROTOCOL)
end

local function endCall(notifyPeer)
  if notifyPeer and peerId then
    rednet.send(peerId, { type = "call_end" }, CALL_PROTOCOL)
  end
  callState = "idle"
  peerId = nil
  chatInput = ""
end

-- ==========================================
-- DOOMSCROLLING SIMULATOR STATE & FEED
-- ==========================================
local brainrot = 0
local feedIndex = 1
local feedPosts = {
  { user = "@create_eng",   text = "10,000 RPM stress test?! Gone wrong (shaft snapped)", likes = 420, liked = false },
  { user = "@villager_ceo", text = "3 Emeralds for 1 Dirt. Take it or leave it.",          likes = 999, liked = false },
  { user = "@creeper_irl",  text = "Nice diamond storage you got there... ssssss",        likes = 133, liked = false },
  { user = "@kelp_lord",    text = "Day 400 of only eating dried kelp. I see in 4D.",    likes = 77,  liked = false },
  { user = "@redstone_wiz", text = "Why use 3 repeaters when 400 lines of Lua works?",    likes = 512, liked = false },
  { user = "@andesite_fan", text = "POV: You ran out of iron nuggets mid-factory build",  likes = 284, liked = false },
  { user = "@base_ai",      text = "Reminder: You haven't touched grass in 6 hours.",     likes = 64,  liked = false },
  { user = "@ender_modem",  text = "5G signal strong even in the End dimension.",         likes = 888, liked = false }
}

local function scrollFeed(dir)
  feedIndex = feedIndex + dir
  if feedIndex < 1 then feedIndex = #feedPosts end
  if feedIndex > #feedPosts then feedIndex = 1 end
  brainrot = math.min(100, brainrot + math.random(4, 11))
end

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
  { id = "phone",   label = "Phone Call   ", color = colors.lime   },
  { id = "doom",    label = "DoomScroll   ", color = colors.red    },
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

  -- Active call indicator on taskbar
  if callState ~= "idle" then
    term.setCursorPos(9, h)
    term.setBackgroundColor(callState == "incoming" and colors.red or colors.lime)
    term.setTextColor(colors.black)
    term.write(callState == "incoming" and " RING! " or " CALL  ")
  end

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
-- DESKTOP & APPS (26x20 POCKET FIT)
-- ==========================================
local desktopIcons = {
{ id = "control", label = "Controls", color = colors.green,  glyph = "SW", col = 1, row = 1 },
{ id = "plant",   label = "Plants  ", color = colors.orange, glyph = ">>", col = 1, row = 2 },
{ id = "storage", label = "Storage ", color = colors.blue,   glyph = "[]", col = 1, row = 3 },
{ id = "phone",   label = "Phone   ", color = colors.lime,   glyph = "()", col = 2, row = 1 },
{ id = "doom",    label = "Scroll  ", color = colors.red,    glyph = "@@", col = 2, row = 2 }
}
local function getIconCoords(icon)
local x = (icon.col == 1) and 3 or 15
local y = 2 + ((icon.row - 1) * 5)
return x, y
end
local function drawDesktop()
drawWallpaper()
for _, icon in ipairs(desktopIcons) do
local x, y = getIconCoords(icon)
drawRaisedPanel(x + 2, y, x + 5, y + 2, icon.color)
term.setCursorPos(x + 3, y + 1)
term.setBackgroundColor(icon.color)
term.setTextColor(colors.white)
term.write(icon.glyph)
term.setCursorPos(x, y + 3)
term.setBackgroundColor(colors.blue)
term.setTextColor(colors.white)
term.write(icon.label:sub(1, 8))
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
term.setCursorPos(ix1 + 8, by)
term.setBackgroundColor(isOn and colors.lime or colors.gray)
term.setTextColor(isOn and colors.black or colors.white)
term.write(" ON  ")
term.setCursorPos(ix1 + 14, by)
term.setBackgroundColor((not isOn) and colors.red or colors.gray)
term.setTextColor(colors.white)
term.write(" OFF ")
end
end
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
-- PHONE APP VIEW
-- ==========================================
local function drawPhoneApp()
local ix1, iy1, ix2, iy2 = drawWindow("Phone (ID:" .. MY_ID .. ")")
if callState == "idle" then
term.setCursorPos(ix1, iy1)
term.setBackgroundColor(colors.lightGray)
term.setTextColor(colors.black)
term.write("Dial ID:")
drawSunkenBox(ix1 + 9, iy1, ix1 + 14, iy1, colors.white)
term.setCursorPos(ix1 + 10, iy1)
term.setTextColor(colors.black)
term.write(dialInput .. "_")
term.setCursorPos(ix2 - 5, iy1)
term.setBackgroundColor(colors.green)
term.setTextColor(colors.white)
term.write(" CALL ")
term.setCursorPos(ix1, iy1 + 2)
term.setBackgroundColor(colors.lightGray)
term.setTextColor(colors.blue)
term.write("Online Phones:")
term.setCursorPos(ix2 - 5, iy1 + 2)
term.setBackgroundColor(colors.gray)
term.setTextColor(colors.white)
term.write(" SCAN ")
drawSunkenBox(ix1, iy1 + 3, ix2, iy2, colors.white)
if #knownPhones == 0 then
term.setCursorPos(ix1 + 1, iy1 + 4)
term.setBackgroundColor(colors.white)
term.setTextColor(colors.gray)
term.write("No other phones found")
else
for i, id in ipairs(knownPhones) do
if iy1 + 3 + i < iy2 then
term.setCursorPos(ix1 + 1, iy1 + 3 + i)
term.setBackgroundColor(colors.white)
term.setTextColor(colors.black)
term.write("Phone #" .. id)
term.setCursorPos(ix2 - 6, iy1 + 3 + i)
term.setBackgroundColor(colors.lime)
term.write(" RING ")
end
end
end
elseif callState == "outgoing" then
term.setCursorPos(ix1 + 2, iy1 + 3)
term.setBackgroundColor(colors.lightGray)
term.setTextColor(colors.black)
term.write("Calling #" .. tostring(peerId) .. "...")
term.setCursorPos(ix1 + 5, iy1 + 7)
term.setBackgroundColor(colors.red)
term.setTextColor(colors.white)
term.write("   CANCEL   ")
elseif callState == "incoming" then
term.setCursorPos(ix1 + 1, iy1 + 2)
term.setBackgroundColor(colors.lightGray)
term.setTextColor(colors.blue)
term.write("INCOMING CALL!")
term.setCursorPos(ix1 + 1, iy1 + 4)
term.setTextColor(colors.black)
term.write("From: Phone #" .. tostring(peerId))
term.setCursorPos(ix1 + 1, iy1 + 7)
term.setBackgroundColor(colors.green)
term.setTextColor(colors.white)
term.write(" ANSWER ")
term.setCursorPos(ix2 - 8, iy1 + 7)
term.setBackgroundColor(colors.red)
term.setTextColor(colors.white)
term.write(" DECLINE ")
elseif callState == "connected" then
term.setCursorPos(ix1, iy1)
term.setBackgroundColor(colors.lightGray)
term.setTextColor(colors.green)
term.write("Connected #" .. tostring(peerId))
term.setCursorPos(ix2 - 4, iy1)
term.setBackgroundColor(colors.red)
term.setTextColor(colors.white)
term.write(" END ")
drawSunkenBox(ix1, iy1 + 1, ix2, iy2 - 2, colors.white)
for i, line in ipairs(callLog) do
if iy1 + 1 + i <= iy2 - 3 then
term.setCursorPos(ix1 + 1, iy1 + 1 + i)
term.setBackgroundColor(colors.white)
term.setTextColor(colors.black)
term.write(line:sub(1, ix2 - ix1 - 1))
end
end
-- Type bar
drawSunkenBox(ix1, iy2 - 1, ix2, iy2 - 1, colors.white)
term.setCursorPos(ix1 + 1, iy2 - 1)
term.setTextColor(colors.black)
local visibleInput = chatInput:sub(-(ix2 - ix1 - 2))
term.write(visibleInput .. "_")
term.setCursorPos(ix1, iy2)
term.setBackgroundColor(colors.lightGray)
term.setTextColor(colors.gray)
term.write("Type + Enter to send")
end
end
-- ==========================================
-- DOOMSCROLLING SIMULATOR VIEW
-- ==========================================
local function wrapText(str, maxW)
local lines = {}
local line = ""
for word in str:gmatch("%S+") do
if #line + #word + 1 > maxW then
table.insert(lines, line)
line = word
else
line = (line == "") and word or (line .. " " .. word)
end
end
if line ~= "" then table.insert(lines, line) end
return lines
end
local function drawDoomApp()
local ix1, iy1, ix2, iy2 = drawWindow("DoomScroll 98")
local post = feedPosts[feedIndex]
-- Brainrot meter
term.setCursorPos(ix1, iy1)
term.setBackgroundColor(colors.lightGray)
term.setTextColor(brainrot >= 80 and colors.red or colors.black)
term.write("Brainrot: " .. brainrot .. "%")
-- Post card
drawSunkenBox(ix1, iy1 + 1, ix2, iy2 - 2, colors.white)
term.setCursorPos(ix1 + 1, iy1 + 2)
term.setBackgroundColor(colors.white)
term.setTextColor(colors.blue)
term.write(post.user)
local lines = wrapText(post.text, ix2 - ix1 - 1)
for i = 1, math.min(5, #lines) do
term.setCursorPos(ix1 + 1, iy1 + 3 + i)
term.setBackgroundColor(colors.white)
term.setTextColor(colors.black)
term.write(lines[i])
end
if brainrot >= 100 then
term.setCursorPos(ix1 + 1, iy2 - 3)
term.setBackgroundColor(colors.red)
term.setTextColor(colors.white)
term.write(" MAX ROT! GO MINE! ")
end
-- Bottom action buttons: Like & Next Post
term.setCursorPos(ix1, iy2)
term.setBackgroundColor(post.liked and colors.red or colors.gray)
term.setTextColor(colors.white)
term.write(" <3 " .. post.likes .. " ")
term.setCursorPos(ix2 - 7, iy2)
term.setBackgroundColor(colors.blue)
term.setTextColor(colors.white)
term.write(" Next v ")
end
-- ==========================================
-- MASTER RENDER & EVENT LOOP
-- ==========================================
local function render()
if currentApp == "desktop" then drawDesktop()
elseif currentApp == "control" then drawControlPanel()
elseif currentApp == "plant" then drawPlantOutput()
elseif currentApp == "storage" then drawStorage()
elseif currentApp == "phone" then drawPhoneApp()
elseif currentApp == "doom" then drawDoomApp() end
drawTaskbar()
if startMenuOpen then drawStartMenu() end
end
refreshPhones()
render()
local clockTimer = os.startTimer(5)
while true do
local event, p1, p2, p3 = os.pullEvent()
if event == "timer" and p1 == clockTimer then
render()
clockTimer = os.startTimer(5)
elseif event == "rednet_message" then
local senderId, msg, protocol = p1, p2, p3
if protocol == STORAGE_PROTOCOL then
processIncomingStorage(msg)
render()
