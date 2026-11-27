-- ==========================================
-- POCKET iOS 27 (26x20 Liquid Glass + Dynamic Island)
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
  { name = "DOOR",   state = "OFF", msg = "door"   },
  { name = "FARM",   state = "OFF", msg = "farm"   },
  { name = "ALARM",  state = "OFF", msg = "alarm"  }
}

local currentApp = "home"
local glassTinted = false -- iOS 27: ultraclear vs tinted Liquid Glass
local status = "Ready"
local storagePage, storageOk = 1, false
local liveTotals, liveNames, lastCounts, ratesPerMin = {}, {}, {}, {}
local lastScan = os.epoch("utc") / 1000

-- Calling State
local callState = "idle" -- "idle", "ringing_in", "calling", "connected"
local peerID = nil
local callLog = {}
local quickMsgs = { "On my way!", "Need help!", "Check base", "Yo!" }

-- GPS State
local gpsCoords = nil
local gpsChecked = false

-- Insta Feed State
local postIdx = 1
local feed = {
  {
    user = "@creeper_king",
    caption = "1000 IQ Create farm up and running",
    likes = 142,
    liked = false,
    bg = colors.cyan,
    art = "[ /\\  /\\  ]"
  },
  {
    user = "@redstone_nerd",
    caption = "POV: forgot torches in the cave",
    likes = 89,
    liked = false,
    bg = colors.purple,
    art = "[  (o)(o)  ]"
  },
  {
    user = "@andesite_bro",
    caption = "Kelp engine running smooth all day",
    likes = 214,
    liked = false,
    bg = colors.blue,
    art = "[ ~~ === ~~ ]"
  }
}
local extraUsers = { "@villager42", "@ender_girl", "@builder_pro" }
local extraBgs   = { colors.brown, colors.magenta, colors.teal }

-- ==========================================
-- HELPERS
-- ==========================================
local function beep(note, vol)
  if speaker then pcall(speaker.playNote, "bell", vol or 1, note or 12) end
end

local function addLog(txt)
  table.insert(callLog, txt)
  if #callLog > 6 then table.remove(callLog, 1) end
end

local function refreshGPS()
  gpsChecked = true
  local x, y, z = gps.locate(2)
  if x then
    gpsCoords = { x = math.floor(x), y = math.floor(y), z = math.floor(z) }
  else
    gpsCoords = nil
  end
end

local function addNewPost(caption)
  local u = extraUsers[math.random(#extraUsers)]
  local b = extraBgs[math.random(#extraBgs)]
  table.insert(feed, {
    user = u,
    caption = caption,
    likes = 1,
    liked = true,
    bg = b,
    art = "[ * PHOTO * ]"
  })
  postIdx = #feed
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
-- LIQUID GLASS DRAWING HELPERS
-- ==========================================
local function fill(x1, y1, x2, y2, bg)
  term.setBackgroundColor(bg)
  for y = y1, y2 do
    term.setCursorPos(x1, y)
    term.write(string.rep(" ", math.max(0, x2 - x1 + 1)))
  end
end

local function drawText(x, y, txt, bg, fg)
  term.setCursorPos(x, y)
  if bg then term.setBackgroundColor(bg) end
  if fg then term.setTextColor(fg) end
  term.write(txt)
end

-- Liquid Glass card: subtle top specular edge + glass body + soft lower rim
local function drawGlassCard(x1, y1, x2, y2, tinted)
  local body = tinted and colors.gray or colors.lightGray
  local rim  = tinted and colors.black or colors.gray
  fill(x1, y1, x2, y2, body)
  drawText(x1, y1, string.rep("-", math.max(0, x2 - x1 + 1)), body, colors.white)
  drawText(x1, y2, string.rep("_", math.max(0, x2 - x1 + 1)), body, rim)
end

local function drawWallpaper()
  local w, h = term.getSize()
  for y = 2, h - 1 do
    for x = 1, w do
      local nx, ny = x / w, y / h
      local c = glassTinted and colors.blue or colors.lightBlue
      local wave = 0.56 + 0.09 * math.sin(nx * 4.2 + 0.3) + 0.04 * math.cos(nx * 7.5 - ny * 3.0)
      if ny >= wave + 0.06 then
        c = glassTinted and colors.cyan or colors.lime
      elseif ny >= wave then
        c = glassTinted and colors.lightBlue or colors.green
      elseif ((nx - 0.68) / 0.18)^2 + ((ny - 0.24) / 0.08)^2 <= 1 then
        c = colors.white
      end
      term.setCursorPos(x, y)
      term.setBackgroundColor(c)
      term.write(" ")
    end
  end
end

local function drawStatusAndIsland()
  local w = term.getSize()
  fill(1, 1, w, 1, colors.black)

  local rawTime = textutils.formatTime(os.time(), false)
  local shortTime = rawTime:match("^(%d+:%d+)") or rawTime:sub(1, 5)
  drawText(1, 1, shortTime, colors.black, colors.white)

  -- iOS 27 Dynamic Island centered at top
  local pillText = "(o)"
  local pillFg   = colors.white
  if callState == "ringing_in" then
    pillText = "RING"
    pillFg   = colors.lime
  elseif callState == "calling" or callState == "connected" then
    pillText = "CALL"
    pillFg   = colors.green
  elseif currentApp == "gps" then
    pillText = "GPS "
    pillFg   = colors.cyan
  end
  drawText(11, 1, "[" .. pillText .. "]", colors.gray, pillFg)

  -- Signal + ID on right
  drawText(21, 1, storageOk and "5G" or "--", colors.black, storageOk and colors.lime or colors.orange)
  drawText(24, 1, "#" .. tostring(myID):sub(-2), colors.black, colors.lightGray)
end

local function drawAppHeader(title)
  local w = term.getSize()
  fill(1, 2, w, 2, glassTinted and colors.gray or colors.lightGray)
  drawText(1, 2, "<iOS", glassTinted and colors.gray or colors.lightGray, glassTinted and colors.white or colors.black)
  drawText(6, 2, title:sub(1, w - 5), glassTinted and colors.gray or colors.lightGray, glassTinted and colors.white or colors.black)
end

local function drawDock()
  local w, h = term.getSize()
  drawGlassCard(1, h, w, h, glassTinted)
  local dockBg = glassTinted and colors.gray or colors.lightGray
  local dockFg = glassTinted and colors.white or colors.black

  drawText(2,  h, "Call",  currentApp == "phone" and colors.lime  or dockBg, currentApp == "phone" and colors.black or dockFg)
  drawText(8,  h, "Insta", currentApp == "insta" and colors.pink  or dockBg, currentApp == "insta" and colors.black or dockFg)
  drawText(15, h, "GPS",   currentApp == "gps"   and colors.cyan  or dockBg, currentApp == "gps"   and colors.black or dockFg)
  drawText(20, h, "Home",  currentApp == "home"  and colors.white or dockBg, currentApp == "home"  and colors.black or dockFg)
end

-- ==========================================
-- HOME & APPS
-- ==========================================
local homeTiles = {
  { id = "phone",   label = "Call",  col = colors.lime,    fg = colors.black, icon = "( )" },
  { id = "insta",   label = "Insta", col = colors.magenta, fg = colors.white, icon = "[o]" },
  { id = "gps",     label = "GPS",   col = colors.cyan,    fg = colors.black, icon = "(@)" },
  { id = "control", label = "Ctrl",  col = colors.orange,  fg = colors.white, icon = "SW " },
  { id = "plant",   label = "Crop",  col = colors.green,   fg = colors.white, icon = ">> " },
  { id = "storage", label = "Vault", col = colors.blue,    fg = colors.white, icon = "[=]" }
}

local function drawHome()
  local w, h = term.getSize()
  drawWallpaper()

  local cols = { 3, 11, 19 }
  local rows = { 3, 7 }
  for i, tile in ipairs(homeTiles) do
    local r = (i <= 3) and 1 or 2
    local c = ((i - 1) % 3) + 1
    local x = cols[c]
    local y = rows[r]

    fill(x, y, x + 4, y + 1, tile.col)
    drawText(x, y, ".", tile.col, colors.white) -- glass sheen corner
    drawText(x + 1, y, tile.icon:sub(1, 3), tile.col, tile.fg)
    drawText(x, y + 2, tile.label, colors.blue, colors.white)
  end

  -- Liquid Glass status card + tint toggle
  drawGlassCard(2, 11, w - 1, h - 2, glassTinted)
  local cardBg = glassTinted and colors.gray or colors.lightGray
  local cardFg = glassTinted and colors.white or colors.black

  drawText(3, 12, "Base:", cardBg, glassTinted and colors.lightGray or colors.gray)
  drawText(9, 12, storageOk and "ONLINE" or "OFFLINE", cardBg, storageOk and colors.lime or colors.red)

  drawText(18, 12, glassTinted and "[Tint]" or "[Clr ]", colors.cyan, colors.black)

  if callState ~= "idle" then
    drawText(3, 14, "Call: " .. callState .. " #" .. tostring(peerID or ""), cardBg, colors.lime)
  else
    drawText(3, 14, "Siri AI: Ready", cardBg, cardFg)
  end

  if gpsCoords then
    drawText(3, 16, ("GPS:%d,%d,%d"):format(gpsCoords.x, gpsCoords.y, gpsCoords.z), cardBg, cardFg)
  else
    drawText(3, 16, "GPS: Tap GPS app", cardBg, glassTinted and colors.lightGray or colors.gray)
  end
end

local function drawPhone()
  local w, h = term.getSize()
  drawAppHeader("Phone #" .. myID)
  fill(1, 3, w, h - 1, colors.lightGray)

  fill(2, 3, w - 1, 9, colors.black)
  for i, line in ipairs(callLog) do
    drawText(3, 2 + i, line:sub(1, w - 4), colors.black, colors.lime)
  end

  if callState == "idle" then
    drawText(2,  11, "CALL", colors.green, colors.white)
    drawText(8,  11, "PING", colors.blue,  colors.white)
    drawText(14, 11, "MSG",  colors.cyan,  colors.black)
  elseif callState == "ringing_in" then
    drawText(2,  11, "ANSWER",  colors.lime, colors.black)
    drawText(10, 11, "DECLINE", colors.red,  colors.white)
  else
    drawText(2, 11, "END", colors.red,  colors.white)
    drawText(7, 11, "SAY", colors.blue, colors.white)
  end

  drawText(2,  14, "[1]OMW",  colors.white, colors.black)
  drawText(10, 14, "[2]Help", colors.white, colors.black)
  drawText(2,  15, "[3]Base", colors.white, colors.black)
  drawText(10, 15, "[4]Yo!",  colors.white, colors.black)
end

local function drawInsta()
  local w, h = term.getSize()
  drawAppHeader("Insta (" .. postIdx .. "/" .. #feed .. ")")
  fill(1, 3, w, h - 1, colors.white)

  local post = feed[postIdx]
  drawText(2, 3, post.user, colors.white, colors.black)

  fill(2, 4, w - 1, 9, post.bg)
  drawText(6, 6, post.art, post.bg, colors.white)

  drawText(2,  11, (post.liked and "<3 " or "+  ") .. post.likes, post.liked and colors.red or colors.lightGray, post.liked and colors.white or colors.black)
  drawText(12, 11, "Next>", colors.blue, colors.white)
  drawText(19, 11, "+Post", colors.purple, colors.white)

  drawText(2, 13, post.caption:sub(1, w - 3), colors.white, colors.black)
  if #post.caption > w - 3 then
    drawText(2, 14, post.caption:sub(w - 2, (w - 3) * 2), colors.white, colors.black)
  end
  drawText(2, h - 2, "Scroll wheel also flips", colors.white, colors.gray)
end

local function drawGPS()
  local w, h = term.getSize()
  drawAppHeader("GPS")
  fill(1, 3, w, h - 1, colors.white)

  if gpsCoords then
    drawText(2, 4, "X: " .. gpsCoords.x, colors.white, colors.black)
    drawText(2, 5, "Y: " .. gpsCoords.y, colors.white, colors.black)
    drawText(2, 6, "Z: " .. gpsCoords.z, colors.white, colors.black)
    drawText(2, 8, "Fix: OK", colors.white, colors.green)
  elseif gpsChecked then
    drawText(2, 4, "No GPS fix found.", colors.white, colors.red)
    drawText(2, 6, "Need 4+ GPS hosts", colors.white, colors.gray)
    drawText(2, 7, "in modem range.", colors.white, colors.gray)
  else
    drawText(2, 4, "Tap Locate to scan.", colors.white, colors.gray)
  end

  drawText(2,  11, "Locate", colors.cyan, colors.black)
  drawText(10, 11, "Share Pos", colors.blue, colors.white)
end

local function drawControl()
  local w, h = term.getSize()
  drawAppHeader("Control")
  fill(1, 3, w, h - 1, colors.lightGray)

  for i, b in ipairs(btns) do
    local y = 1 + i * 3
    drawText(2, y, b.name, colors.lightGray, colors.black)
    drawText(10, y, " ON ", b.state == "ON" and colors.lime or colors.gray, b.state == "ON" and colors.black or colors.white)
    drawText(16, y, " OFF ", b.state == "OFF" and colors.red or colors.gray, colors.white)
  end

  drawText(2, h - 2, status:sub(1, w - 3), colors.lightGray, colors.black)
end

local function drawPlant()
  local w, h = term.getSize()
  drawAppHeader("Crop Output")
  fill(1, 3, w, h - 1, colors.white)

  for i, p in ipairs(trackedPlants) do
    local y = 2 + i * 2
    if y <= h - 2 then
      local cnt = liveTotals[p.id] or 0
      local rt  = ratesPerMin[p.id] or 0
      drawText(2, y, p.label, colors.white, colors.black)
      local info = cnt .. " (" .. rt .. "/m)"
      drawText(w - #info, y, info, colors.white, rt > 0 and colors.green or colors.gray)
    end
  end
end

local function drawStorage()
  local w, h = term.getSize()
  drawAppHeader("Base Vault")
  fill(1, 3, w, h - 1, colors.white)

  local list = {}
  for id, cnt in pairs(liveTotals) do
    table.insert(list, { n = liveNames[id] or id:gsub("^.+:", ""), c = cnt })
  end
  table.sort(list, function(a, b) return a.c > b.c end)

  local per = h - 6
  local pages = math.max(1, math.ceil(#list / per))
  if storagePage > pages then storagePage = 1 end

  for i = 1, per do
    local it = list[(storagePage - 1) * per + i]
    if it then
      local cs = tostring(it.c)
      drawText(2, 2 + i, it.n:sub(1, w - #cs - 3), colors.white, colors.black)
      drawText(w - #cs, 2 + i, cs, colors.white, colors.blue)
    end
  end

  drawText(2, h - 2, "<Prev", colors.lightGray, colors.black)
  drawText(9, h - 2, "Next>", colors.gray, colors.white)
  drawText(16, h - 2, storagePage .. "/" .. pages, colors.white, colors.black)
end

local function render()
  if currentApp == "home" then drawHome()
  elseif currentApp == "phone" then drawPhone()
  elseif currentApp == "insta" then drawInsta()
  elseif currentApp == "gps" then drawGPS()
  elseif currentApp == "control" then drawControl()
  elseif currentApp == "plant" then drawPlant()
  elseif currentApp == "storage" then drawStorage()
  end
  drawStatusAndIsland()
  drawDock()
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
        addLog("Incoming #" .. p1)
        beep(18)
      elseif p2.type == "accept" and p1 == peerID then
        callState = "connected"
        addLog("Connected #" .. p1)
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

  elseif ev == "mouse_scroll" and currentApp == "insta" then
    if p1 > 0 and postIdx < #feed then
      postIdx = postIdx + 1
    elseif p1 < 0 and postIdx > 1 then
      postIdx = postIdx - 1
    end
    render()

  elseif ev == "mouse_click" and p1 == 1 then
    local x, y = p2, p3
    local w, h = term.getSize()

    if y == h then
      if x >= 2 and x <= 5 then currentApp = "phone"
      elseif x >= 8 and x <= 12 then currentApp = "insta"
      elseif x >= 15 and x <= 17 then
        currentApp = "gps"
        if not gpsChecked then refreshGPS() end
      elseif x >= 20 and x <= 23 then currentApp = "home" end
      render()

    elseif currentApp ~= "home" and y == 2 and x <= 4 then
      currentApp = "home"
      render()

    elseif currentApp == "home" then
      if y == 12 and x >= 18 and x <= 23 then
        glassTinted = not glassTinted
      else
        local cols = { 3, 11, 19 }
        local rows = { 3, 7 }
        for i, tile in ipairs(homeTiles) do
          local r = (i <= 3) and 1 or 2
          local c = ((i - 1) % 3) + 1
          local tx, ty = cols[c], rows[r]
          if x >= tx and x <= tx + 4 and y >= ty and y <= ty + 2 then
            currentApp = tile.id
            if tile.id == "gps" and not gpsChecked then refreshGPS() end
            break
          end
        end
      end
      render()

    elseif currentApp == "control" then
      for i, b in ipairs(btns) do
        local by = 1 + i * 3
        if y == by and x >= 10 and x <= 13 then
          b.state = "ON"
          rednet.broadcast(b.msg .. "_on")
          status = "Sent " .. b.msg .. "_on"
        elseif y == by and x >= 16 and x <= 20 then
          b.state = "OFF"
          rednet.broadcast(b.msg .. "_off")
          status = "Sent " .. b.msg .. "_off"
        end
      end
      render()

    elseif currentApp == "storage" and y == h - 2 then
      if x >= 2 and x <= 6 then
        storagePage = math.max(1, storagePage - 1)
      elseif x >= 9 and x <= 13 then
        storagePage = storagePage + 1
      end
      render()

    elseif currentApp == "insta" and y == 11 then
      local post = feed[postIdx]
      if x >= 2 and x <= 10 then
        if not post.liked then
          post.liked = true
          post.likes = post.likes + 1
        end
      elseif x >= 12 and x <= 16 then
        if postIdx < #feed then postIdx = postIdx + 1 else postIdx = 1 end
      elseif x >= 19 and x <= 23 then
        fill(2, 12, w - 1, 12, colors.lightGray)
        drawText(2, 12, "Cap:", colors.lightGray, colors.black)
        term.setCursorPos(6, 12)
        local cap = read()
        if cap and cap ~= "" then addNewPost(cap) end
      end
      render()

    elseif currentApp == "gps" and y == 11 then
      if x >= 2 and x <= 7 then
        refreshGPS()
      elseif x >= 10 and x <= 18 and gpsCoords then
        local posStr = ("Pos: %d, %d, %d"):format(gpsCoords.x, gpsCoords.y, gpsCoords.z)
        if peerID then
          rednet.send(peerID, { type = "say", text = posStr }, CALL_PROTO)
        else
          rednet.broadcast({ type = "say", text = posStr }, CALL_PROTO)
        end
        addLog("Shared " .. posStr)
      end
      render()

    elseif currentApp == "phone" then
      if y == 11 then
        if callState == "idle" and x >= 2 and x <= 5 then
          fill(2, 12, w - 1, 12, colors.white)
          drawText(2, 12, "ID:", colors.white, colors.black)
          term.setCursorPos(5, 12)
          local id = tonumber(read())
          if id then
            peerID, callState = id, "calling"
            rednet.send(id, { type = "ring" }, CALL_PROTO)
            addLog("Calling #" .. id .. "...")
          end
        elseif callState == "idle" and x >= 8 and x <= 11 then
          rednet.broadcast({ type = "say", text = "Ping from #" .. myID }, CALL_PROTO)
          addLog("Sent Ping!")
        elseif callState == "idle" and x >= 14 and x <= 16 then
          fill(2, 12, w - 1, 12, colors.white)
          drawText(2, 12, "Msg:", colors.white, colors.black)
          term.setCursorPos(6, 12)
          local msg = read()
          if msg and msg ~= "" then
            rednet.broadcast({ type = "say", text = msg }, CALL_PROTO)
            addLog("Me: " .. msg)
          end
        elseif callState == "ringing_in" and x >= 2 and x <= 7 then
          callState = "connected"
          rednet.send(peerID, { type = "accept" }, CALL_PROTO)
          addLog("In call #" .. peerID)
        elseif callState ~= "idle" and x >= 2 and x <= 4 then
          if peerID then rednet.send(peerID, { type = "hangup" }, CALL_PROTO) end
          callState, peerID = "idle", nil
          addLog("Hung up.")
        elseif callState == "connected" and x >= 7 and x <= 9 then
          fill(2, 12, w - 1, 12, colors.white)
          drawText(2, 12, ">", colors.white, colors.black)
          term.setCursorPos(3, 12)
          local msg = read()
          if msg and msg ~= "" then
            rednet.send(peerID, { type = "say", text = msg }, CALL_PROTO)
            addLog("Me: " .. msg)
          end
        end
      elseif y == 14 or y == 15 then
        local idx = nil
        if y == 14 and x >= 2 and x <= 7 then idx = 1
        elseif y == 14 and x >= 10 and x <= 15 then idx = 2
        elseif y == 15 and x >= 2 and x <= 7 then idx = 3
        elseif y == 15 and x >= 10 and x <= 14 then idx = 4 end
        if idx then
          local txt = quickMsgs[idx]
          if peerID then
            rednet.send(peerID, { type = "say", text = txt }, CALL_PROTO)
          else
            rednet.broadcast({ type = "say", text = txt }, CALL_PROTO)
          end
          addLog("Me: " .. txt)
        end
      end
      render()
    end
  end
end
