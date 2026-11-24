-- ==========================================
-- POCKET CONTROL OS 98 (26x20 + Calls + BlockTok)
-- ==========================================
peripheral.find("modem", rednet.open)
local speaker = peripheral.find("speaker")

local STORAGE_PROTO = "base_storage_sync"
local CALL_PROTO    = "pocket_phone_call"
local myID          = os.getComputerID()

-- ==========================================
-- CONFIG & STATE
-- ==========================================
local trackedPlants = {
  { id = "create:andesite_alloy", label = "Andesite" },
  { id = "minecraft:iron_ingot",   label = "Iron"     },
  { id = "minecraft:gold_ingot",   label = "Gold"     },
  { id = "minecraft:wheat",        label = "Wheat"    },
  { id = "minecraft:dried_kelp",   label = "Kelp"     }
}

local btns = {
  { name = "LIGHTS", state = "OFF", msg = "lights" },
  { name = "DOOR  ", state = "OFF", msg = "door"   },
  { name = "FARM  ", state = "OFF", msg = "farm"   },
  { name = "ALARM ", state = "OFF", msg = "alarm"  }
}

local currentApp = "desktop"
local startOpen = false
local status = "Ready (ID:" .. myID .. ")"
local storagePage, storageOk = 1, false
local liveTotals, liveNames, lastCounts, ratesPerMin = {}, {}, {}, {}
local lastScan = os.epoch("utc") / 1000

-- Calling State
local callState = "idle" -- "idle", "ringing_in", "calling", "connected"
local peerID = nil
local callLog = {}
local quickMsgs = { "On my way!", "Need help!", "Check base", "Yo!" }

-- Doomscroll State
local scrollIdx, brainrot, totalViews = 1, 0, 1
local feed = {}
local authors = { "@creeper_king", "@redstone_nerd", "@villager42", "@andesite_bro", "@ender_girl" }
local topics = {
  "1000 IQ Create farm",
  "POV: forgot torches",
  "Why is my vault open",
  "Kelp engine exploded",
  "Mending for 1 emerald",
  "Digging straight down",
  "Rate my cobble box"
}

local function makePost(idx)
  if not feed[idx] then
    feed[idx] = {
      user = authors[math.random(#authors)],
      text = topics[math.random(#topics)],
      likes = math.random(12, 999),
      liked = false,
      bg = ({ colors.cyan, colors.purple, colors.blue, colors.brown, colors.gray })[math.random(5)]
    }
  end
  return feed[idx]
end
makePost(1)

local function beep(note, vol)
  if speaker then pcall(speaker.playNote, "bell", vol or 1, note or 12) end
end

local function addLog(txt)
  table.insert(callLog, txt)
  if #callLog > 6 then table.remove(callLog, 1) end
end

local function processStorage(data)
  if type(data) ~= "table" or not data.totals then return end
  liveTotals, liveNames, storageOk = data.totals, data.names or {}, true
  local now = os.epoch("utc") / 1000
  local dt = now - lastScan
  if dt >= 1 then
    for _, p in ipairs(trackedPlants) do
      local cur = liveTotals[p.id] or 0
      ratesPerMin[p.id] = lastCounts[p.id] and math.floor(((cur - lastCounts[p.id]) / dt) * 60) or 0
      lastCounts[p.id] = cur
    end
    lastScan = now
  end
end

-- ==========================================
-- UI DRAWING HELPERS
-- ==========================================
local function fill(x1, y1, x2, y2, bg)
  term.setBackgroundColor(bg)
  for y = y1, y2 do
    term.setCursorPos(x1, y)
    term.write(string.rep(" ", x2 - x1 + 1))
  end
end

local function panel(x1, y1, x2, y2, bg)
  fill(x1, y1, x2, y2, bg or colors.lightGray)
  term.setBackgroundColor(colors.white)
  term.setCursorPos(x1, y1) term.write(string.rep(" ", x2 - x1))
  for y = y1, y2 - 1 do term.setCursorPos(x1, y) term.write(" ") end
  term.setBackgroundColor(colors.gray)
  term.setCursorPos(x1, y2) term.write(string.rep(" ", x2 - x1 + 1))
  for y = y1 + 1, y2 do term.setCursorPos(x2, y) term.write(" ") end
end

local function drawBliss()
  local w, h = term.getSize()
  for y = 1, h - 1 do
    for x = 1, w do
      local nx, ny = x / w, y / h
      local c = colors.lightBlue
      if ny >= 0.56 + 0.08 * math.sin(nx * 4.5 + 0.5) then c = colors.lime
      elseif ny >= 0.52 + 0.06 * math.cos(nx * 5.0 - 0.8) then c = colors.green
      elseif ((nx - 0.65) / 0.16)^2 + ((ny - 0.22) / 0.07)^2 <= 1 then c = colors.white end
      term.setCursorPos(x, y) term.setBackgroundColor(c) term.write(" ")
    end
  end
end

local function drawWin(title)
  local w, h = term.getSize()
  panel(1, 1, w, h - 1, colors.lightGray)
  fill(2, 2, w - 1, 2, colors.blue)
  term.setCursorPos(3, 2) term.setTextColor(colors.white) term.write(title)
  term.setCursorPos(w - 3, 2) term.setBackgroundColor(colors.red) term.write(" X ")
  return 3, 4, w - 2, h - 3
end

-- ==========================================
-- APPS
-- ==========================================
local icons = {
  { id = "control", name = "Control", col = colors.green,  tag = "SW" },
  { id = "plant",   name = "Plants ", col = colors.orange, tag = ">>" },
  { id = "storage", name = "Storage", col = colors.blue,   tag = "[]" },
  { id = "phone",   name = "Phone  ", col = colors.lime,   tag = "()" },
  { id = "scroll",  name = "BlockTk", col = colors.purple, tag = "TV" }
}

local function drawDesktop()
  drawBliss()
  for i, ic in ipairs(icons) do
    local y = 2 + (i - 1) * 3
    fill(3, y, 6, y + 1, ic.col)
    term.setCursorPos(4, y) term.setTextColor(colors.white) term.write(ic.tag)
    term.setCursorPos(8, y) term.setBackgroundColor(colors.blue) term.write(" " .. ic.name .. " ")
  end
end

local function drawControl()
  local x1, y1, x2, y2 = drawWin("Control Panel")
  for i, b in ipairs(btns) do
    local y = y1 + (i - 1) * 3
    term.setCursorPos(x1, y) term.setBackgroundColor(colors.lightGray) term.setTextColor(colors.black)
    term.write(b.name)
    term.setCursorPos(x1 + 8, y)
    term.setBackgroundColor(b.state == "ON" and colors.lime or colors.gray)
    term.setTextColor(b.state == "ON" and colors.black or colors.white)
    term.write(" ON  ")
    term.setCursorPos(x1 + 14, y)
    term.setBackgroundColor(b.state == "OFF" and colors.red or colors.gray)
    term.setTextColor(colors.white)
    term.write(" OFF ")
  end
  term.setCursorPos(x1, y2) term.setBackgroundColor(colors.lightGray) term.setTextColor(colors.gray)
  term.write(status:sub(1, x2 - x1 + 1))
end

local function drawPlant()
  local x1, y1, x2, y2 = drawWin("Plant Output")
  fill(x1, y1, x2, y2, colors.white)
  for i, p in ipairs(trackedPlants) do
    local y = y1 + (i - 1) * 2 + 1
    if y <= y2 then
      local cnt, rt = liveTotals[p.id] or 0, ratesPerMin[p.id] or 0
      term.setCursorPos(x1 + 1, y) term.setBackgroundColor(colors.white) term.setTextColor(colors.black)
      term.write(p.label)
      local s = cnt .. " (" .. rt .. "/m)"
      term.setCursorPos(x2 - #s, y) term.setTextColor(rt > 0 and colors.green or colors.gray)
      term.write(s)
    end
  end
end

local function drawStorage()
  local x1, y1, x2, y2 = drawWin("Base Storage")
  fill(x1, y1, x2, y2 - 2, colors.white)
  local list = {}
  for id, cnt in pairs(liveTotals) do
    table.insert(list, { n = liveNames[id] or id:gsub("^.+:", ""), c = cnt })
  end
  table.sort(list, function(a, b) return a.c > b.c end)
  local per = y2 - y1 - 2
  local pages = math.max(1, math.ceil(#list / per))
  if storagePage > pages then storagePage = 1 end
  for i = 1, per do
    local it = list[(storagePage - 1) * per + i]
    if it then
      local cs = tostring(it.c)
      term.setCursorPos(x1 + 1, y1 + i - 1) term.setBackgroundColor(colors.white) term.setTextColor(colors.black)
      term.write(it.n:sub(1, x2 - x1 - #cs - 1))
      term.setCursorPos(x2 - #cs, y1 + i - 1) term.setTextColor(colors.blue) term.write(cs)
    end
  end
  term.setCursorPos(x1, y2) term.setBackgroundColor(colors.gray) term.setTextColor(colors.white)
  term.write(" Next > ")
  term.setCursorPos(x1 + 10, y2) term.setBackgroundColor(colors.lightGray) term.setTextColor(colors.black)
  term.write("Pg " .. storagePage .. "/" .. pages)
end

local function drawPhone()
  local x1, y1, x2, y2 = drawWin("Phone (ID:" .. myID .. ")")
  fill(x1, y1, x2, y1 + 6, colors.black)
  for i, line in ipairs(callLog) do
    term.setCursorPos(x1 + 1, y1 + i - 1) term.setBackgroundColor(colors.black) term.setTextColor(colors.lime)
    term.write(line:sub(1, x2 - x1 - 1))
  end

  if callState == "idle" then
    term.setCursorPos(x1, y1 + 8) term.setBackgroundColor(colors.green) term.setTextColor(colors.white)
    term.write(" [CALL ID] ")
    term.setCursorPos(x1 + 12, y1 + 8) term.setBackgroundColor(colors.blue)
    term.write(" [PING] ")
  elseif callState == "ringing_in" then
    term.setCursorPos(x1, y1 + 8) term.setBackgroundColor(colors.lime) term.setTextColor(colors.black)
    term.write(" ANSWER #" .. tostring(peerID) .. " ")
    term.setCursorPos(x1 + 14, y1 + 8) term.setBackgroundColor(colors.red) term.setTextColor(colors.white)
    term.write(" DENY ")
  else
    term.setCursorPos(x1, y1 + 8) term.setBackgroundColor(colors.red) term.setTextColor(colors.white)
    term.write(" END CALL ")
    term.setCursorPos(x1 + 11, y1 + 8) term.setBackgroundColor(colors.blue)
    term.write(" [SAY] ")
  end

  -- Quick reply bar
  term.setCursorPos(x1, y2 - 1) term.setBackgroundColor(colors.lightGray) term.setTextColor(colors.black)
  term.write("Quick: [1]OMW [2]Help")
  term.setCursorPos(x1, y2)
  term.write("       [3]Base [4]Yo!")
end

local function drawScroll()
  local x1, y1, x2, y2 = drawWin("BlockTok #" .. scrollIdx)
  local post = makePost(scrollIdx)
  fill(x1, y1, x2, y2 - 3, post.bg)

  term.setCursorPos(x1 + 1, y1 + 1) term.setBackgroundColor(post.bg) term.setTextColor(colors.yellow)
  term.write(post.user)
  term.setCursorPos(x1 + 1, y1 + 3) term.setTextColor(colors.white)
  term.write(post.text:sub(1, x2 - x1 - 1))
  term.setCursorPos(x1 + 1, y1 + 4)
  term.write(post.text:sub(x2 - x1))

  -- Brainrot meter
  term.setCursorPos(x1, y2 - 2) term.setBackgroundColor(colors.lightGray) term.setTextColor(colors.red)
  term.write("Brainrot: " .. brainrot .. "%  Views:" .. totalViews)

  -- Action buttons
  term.setCursorPos(x1, y2)
term.setBackgroundColor(post.liked and colors.red or colors.gray) term.setTextColor(colors.white)
term.write(" <3 " .. post.likes .. " ")
term.setCursorPos(x1 + 11, y2) term.setBackgroundColor(colors.blue)
term.write(" NEXT v ")
end
local function drawTaskbar()
local w, h = term.getSize()
fill(1, h, w, h, colors.lightGray)
term.setCursorPos(1, h)
term.setBackgroundColor(startOpen and colors.gray or colors.green) term.setTextColor(colors.white)
term.write(" Start ")
local t = textutils.formatTime(os.time(), false)
term.setCursorPos(w - #t - 2, h) term.setBackgroundColor(colors.gray)
term.setTextColor(storageOk and colors.lime or colors.orange) term.write("*")
term.setTextColor(colors.white) term.write(" " .. t)
end
local function render()
if currentApp == "desktop" then drawDesktop()
elseif currentApp == "control" then drawControl()
elseif currentApp == "plant" then drawPlant()
elseif currentApp == "storage" then drawStorage()
elseif currentApp == "phone" then drawPhone()
elseif currentApp == "scroll" then drawScroll() end
drawTaskbar()
if startOpen then
panel(1, 7, 17, 19, colors.lightGray)
for i, ic in ipairs(icons) do
term.setCursorPos(3, 6 + i * 2) term.setBackgroundColor(colors.lightGray) term.setTextColor(colors.black)
term.write(ic.name)
end
end
end
-- ==========================================
-- MAIN EVENT LOOP
-- ==========================================
render()
local timer = os.startTimer(2)
while true do
local ev, p1, p2, p3 = os.pullEvent()
if ev == "timer" and p1 == timer then
if callState == "ringing_in" then beep(14) end
render()
timer = os.startTimer(2)
elseif ev == "rednet_message" then
if p3 == STORAGE_PROTO then
processStorage(p2)
render()
elseif p3 == CALL_PROTO and type(p2) == "table" then
if p2.type == "ring" and callState == "idle" then
peerID, callState, currentApp = p1, "ringing_in", "phone"
addLog("Incoming call #" .. p1)
beep(18)
elseif p2.type == "accept" and p1 == peerID then
callState = "connected"
addLog("Connected to #" .. p1)
elseif p2.type == "hangup" and p1 == peerID then
callState, peerID = "idle", nil
addLog("Call ended.")
elseif p2.type == "say" then
addLog("#" .. p1 .. ": " .. tostring(p2.text))
beep(10)
end
render()
elseif type(p2) == "string" then
for _, b in ipairs(btns) do
if p2 == b.msg .. "_on" then b.state = "ON"
elseif p2 == b.msg .. "_off" then b.state = "OFF" end
end
render()
end
elseif ev == "mouse_scroll" and currentApp == "scroll" then
if p1 > 0 then
scrollIdx = scrollIdx + 1
totalViews = totalViews + 1
brainrot = math.min(100, brainrot + math.random(2, 5))
elseif scrollIdx > 1 then
scrollIdx = scrollIdx - 1
end
render()
elseif ev == "mouse_click" and p1 == 1 then
local x, y = p2, p3
local w, h = term.getSize()
local x1, y1, x2, y2 = 3, 4, w - 2, h - 3
if startOpen then
if x <= 17 and y >= 7 and y <= 19 then
for i, ic in ipairs(icons) do
if y == 6 + i * 2 then currentApp = ic.id end
end
end
startOpen = false
render()
elseif y == h and x <= 7 then
startOpen = not startOpen
render()
elseif currentApp ~= "desktop" and y == 2 and x >= w - 3 then
currentApp = "desktop"
render()
elseif currentApp == "desktop" then
for i, ic in ipairs(icons) do
local iy = 2 + (i - 1) * 3
if y >= iy and y <= iy + 1 and x >= 3 and x <= 18 then
currentApp = ic.id
end
end
render()
elseif currentApp == "control" then
for i, b in ipairs(btns) do
local by = y1 + (i - 1) * 3
if y == by and x >= x1 + 8 and x <= x1 + 12 then
b.state = "ON" rednet.broadcast(b.msg .. "_on") status = "Sent " .. b.msg .. "_on"
elseif y == by and x >= x1 + 14 and x <= x1 + 18 then
b.state = "OFF" rednet.broadcast(b.msg .. "_off") status = "Sent " .. b.msg .. "_off"
end
end
render()
elseif currentApp == "storage" and y == y2 and x <= x1 + 8 then
storagePage = storagePage + 1
render()
elseif currentApp == "phone" then
if y == y1 + 8 then
if callState == "idle" and x <= x1 + 10 then
term.setCursorPos(x1, y1 + 8) term.setBackgroundColor(colors.white) term.setTextColor(colors.black)
term.write("Target ID:       ") term.setCursorPos(x1 + 11, y1 + 8)
local id = tonumber(read())
if id then
peerID, callState = id, "calling"
rednet.send(id, { type = "ring" }, CALL_PROTO)
addLog("Calling #" .. id .. "...")
end
elseif callState == "idle" and x >= x1 + 12 then
rednet.broadcast({ type = "say", text = "Ping from #" .. myID }, CALL_PROTO)
addLog("Broadcasted Ping!")
elseif callState == "ringing_in" and x <= x1 + 12 then
callState = "connected"
rednet.send(peerID, { type = "accept" }, CALL_PROTO)
addLog("In call with #" .. peerID)
elseif callState ~= "idle" and x >= x1 + 11 and callState == "connected" then
term.setCursorPos(x1, y1 + 8) term.setBackgroundColor(colors.white) term.setTextColor(colors.black)
term.write(">                ") term.setCursorPos(x1 + 2, y1 + 8)
local msg = read()
if msg ~= "" then
rednet.send(peerID, { type = "say", text = msg }, CALL_PROTO)
addLog("Me: " .. msg)
end
elseif callState ~= "idle" then
if peerID then rednet.send(peerID, { type = "hangup" }, CALL_PROTO) end
callState, peerID = "idle", nil
addLog("Hung up.")
end
elseif y == y2 - 1 or y == y2 then
local idx = (y == y2 - 1) and (x < 14 and 1 or 2) or (x < 14 and 3 or 4)
local txt = quickMsgs[idx]
if peerID then rednet.send(peerID, { type = "say", text = txt }, CALL_PROTO)
else rednet.broadcast({ type = "say", text = txt }, CALL_PROTO) end
addLog("Me: " .. txt)
end
render()
elseif currentApp == "scroll" and y == y2 then
local post = makePost(scrollIdx)
if x <= x1 + 9 and not post.liked then
post.liked = true
post.likes = post.likes + 1
elseif x >= x1 + 11 then
scrollIdx = scrollIdx + 1
totalViews = totalViews + 1
brainrot = math.min(100, brainrot + math.random(2, 5))
end
render()
end
end
end
