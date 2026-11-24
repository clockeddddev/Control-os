-- ==========================================
-- PERIPHERAL SETUP
-- ==========================================
peripheral.find("modem", rednet.open)
local mon = peripheral.find("monitor")
assert(mon, "No monitor attached!")
mon.setTextScale(0.5)
term.redirect(mon)

-- Auto-detect Create Stock Ticker (6.0+) OR Item Vaults/Chests
local ticker = peripheral.find("Create_StockTicker")
local vaults = { peripheral.find("inventory") }

-- ==========================================
-- CONFIG: ITEMS TO TRACK IN "PLANT OUTPUT"
-- (Use exact Minecraft/Create item IDs)
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
local currentApp = "menu" -- "menu", "control", "plant", "storage"
local status = "Ready"
local storagePage = 1

-- Control Panel Buttons
local btns = {
  { name = "LIGHTS", y = 4,  state = "OFF", msg = "lights" },
  { name = "DOOR  ", y = 7,  state = "OFF", msg = "door"   },
  { name = "FARM  ", y = 10, state = "OFF", msg = "farm"   },
  { name = "ALARM ", y = 13, state = "OFF", msg = "alarm"  }
}

-- Rate tracking for Plant Output
local lastCounts = {}
local ratesPerMin = {}
local lastScanTime = os.epoch("utc") / 1000

-- ==========================================
-- STORAGE HELPER FUNCTIONS
-- ==========================================
local function getAllStock()
  local totals = {}
  local names = {}

  if ticker then
    -- Create 6.0+ Stock Ticker API
    local items = ticker.stock(true)
    for _, item in pairs(items) do
      totals[item.name] = (totals[item.name] or 0) + item.count
      names[item.name] = item.displayName or item.name
    end
  else
    -- Fallback: Scan all connected Item Vaults / Chests
    for _, inv in ipairs(vaults) do
      for slot, item in pairs(inv.list()) do
        totals[item.name] = (totals[item.name] or 0) + item.count
        if not names[item.name] then
          local detail = inv.getItemDetail(slot)
          names[item.name] = (detail and detail.displayName) or item.name
        end
      end
    end
  end

  return totals, names
end

local function updatePlantRates()
  local now = os.epoch("utc") / 1000
  local elapsed = now - lastScanTime
  if elapsed < 1 then return end

  local totals = getAllStock()
  for _, p in ipairs(trackedPlants) do
    local current = totals[p.id] or 0
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

-- ==========================================
-- UI DRAWING HELPERS
-- ==========================================
local function drawHeader(title, showHome)
  local w, _ = term.getSize()
  term.setCursorPos(1, 1)
  term.setBackgroundColor(colors.blue)
  term.clearLine()
  term.setTextColor(colors.white)
  term.write(" " .. title)

  if showHome then
    term.setCursorPos(w - 6, 1)
    term.setBackgroundColor(colors.red)
    term.setTextColor(colors.white)
    term.write(" HOME ")
  end
end

local function drawFooter(text)
  local _, h = term.getSize()
  term.setCursorPos(1, h)
  term.setBackgroundColor(colors.black)
  term.clearLine()
  term.setTextColor(colors.yellow)
  term.write(" > " .. text)
end

-- ==========================================
-- APP 1: MAIN MENU
-- ==========================================
local menuItems = {
  { id = "control", label = "Control Panel", desc = "Rednet base switches", y = 4,  color = colors.green  },
  { id = "plant",   label = "Plant Output ", desc = "Live items/min rates", y = 8,  color = colors.orange },
  { id = "storage", label = "Base Storage ", desc = "Browse Create stock ", y = 12, color = colors.cyan   }
}

local function drawMenu()
  term.setBackgroundColor(colors.gray)
  term.clear()
  drawHeader("BASE CONTROL OS", false)

  for _, item in ipairs(menuItems) do
    term.setCursorPos(3, item.y)
    term.setBackgroundColor(item.color)
    term.setTextColor(colors.black)
    term.write("  " .. item.label .. "  ")

    term.setCursorPos(3, item.y + 1)
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.lightGray)
    term.write(item.desc)
  end

  local linkStatus = ticker and "Create Stock Link OK" or (#vaults .. " Vault(s) Connected")
  drawFooter(linkStatus)
end

-- ==========================================
-- APP 2: CONTROL PANEL (Your Rednet App)
-- ==========================================
local function drawControlPanel()
  term.setBackgroundColor(colors.gray)
  term.clear()
  drawHeader("CONTROL PANEL", true)

  for _, b in ipairs(btns) do
    term.setCursorPos(3, b.y)
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    term.write(b.name)

    term.setCursorPos(11, b.y)
    term.setBackgroundColor(b.state == "ON" and colors.lime or colors.green)
    term.setTextColor(colors.black)
    term.write(" ON ")

    term.setCursorPos(17, b.y)
    term.setBackgroundColor(b.state == "OFF" and colors.red or colors.brown)
    term.setTextColor(colors.white)
    term.write(" OFF ")
  end

  drawFooter(status)
end

-- ==========================================
-- APP 3: PLANT OUTPUT MONITOR
-- ==========================================
local function drawPlantOutput()
  term.setBackgroundColor(colors.black)
  term.clear()
  drawHeader("PLANT OUTPUT", true)

  local totals = getAllStock()

  term.setCursorPos(2, 3)
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.lightGray)
  term.write("ITEM            STOCK    RATE")

  for i, p in ipairs(trackedPlants) do
    local y = 4 + (i * 2)
    local count = totals[p.id] or 0
    local rate = ratesPerMin[p.id] or 0

    term.setCursorPos(2, y)
    term.setTextColor(colors.white)
    term.write(string.format("%-15s", p.label:sub(1, 15)))

    term.setCursorPos(18, y)
    term.setTextColor(colors.cyan)
    term.write(string.format("%-8d", count))

    term.setCursorPos(26, y)
    term.setTextColor(rate > 0 and colors.lime or colors.gray)
    term.write((rate >= 0 and "+" or "") .. rate .. "/m")
  end

  drawFooter("Auto-refreshing every 3s")
end

-- ==========================================
-- APP 4: BASE STORAGE BROWSER
-- ==========================================
local function drawStorage()
  local w, h = term.getSize()
  term.setBackgroundColor(colors.black)
  term.clear()
  drawHeader("BASE STORAGE", true)

  local totals, names = getAllStock()
  local list = {}
  for id, count in pairs(totals) do
    table.insert(list, { name = names[id], count = count })
  end
  table.sort(list, function(a, b) return a.count > b.count end)

  local perPage = h - 6
  local maxPages = math.max(1, math.ceil(#list / perPage))
  if storagePage > maxPages then storagePage = 1 end

  local startIdx = (storagePage - 1) * perPage + 1
  for i = 0, perPage - 1 do
    local item = list[startIdx + i]
    if item then
      term.setCursorPos(2, 3 + i)
      term.setTextColor(colors.white)
      term.write(string.format("%-20s", item.name:sub(1, 20)))
      term.setCursorPos(23, 3 + i)
      term.setTextColor(colors.lime)
      term.write(tostring(item.count))
    end
  end

  -- Page Controls
  term.setCursorPos(2, h - 2)
  term.setBackgroundColor(colors.blue)
  term.setTextColor(colors.white)
  term.write(" NEXT PAGE ")

  term.setCursorPos(15, h - 2)
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.lightGray)
  term.write("Page " .. storagePage .. "/" .. maxPages)

  drawFooter("Total unique items: " .. #list)
end

-- ==========================================
-- MASTER RENDER & EVENT LOOP
-- ==========================================
local function render()
  if currentApp == "menu" then
    drawMenu()
  elseif currentApp == "control" then
    drawControlPanel()
  elseif currentApp == "plant" then
    drawPlantOutput()
  elseif currentApp == "storage" then
    drawStorage()
  end
end

updatePlantRates()
render()
local refreshTimer = os.startTimer(3)

while true do
  local event, p1, p2, p3 = os.pullEvent()

  if event == "timer" and p1 == refreshTimer then
    updatePlantRates()
    if currentApp == "plant" or currentApp == "storage" then
      render()
    end
    refreshTimer = os.startTimer(3)

  elseif event == "monitor_touch" then
    local x, y = p2, p3
    local w, h = term.getSize()

    -- Check Top-Right [ HOME ] Button when inside an app
    if currentApp ~= "menu" and y == 1 and x >= w - 6 then
      currentApp = "menu"
      render()

    -- Main Menu Touches
    elseif currentApp == "menu" then
      for _, item in ipairs(menuItems) do
        if y == item.y or y == item.y + 1 then
          currentApp = item.id
          storagePage = 1
          render()
          break
        end
      end

    -- Control Panel Touches
    elseif currentApp == "control" then
      for _, b in ipairs(btns) do
        if y == b.y then
          if x >= 11 and x <= 14 then
            b.state = "ON"
            rednet.broadcast(b.msg .. "_on")
            status = "Sent: " .. b.msg .. "_on"
            render()
          elseif x >= 17 and x <= 21 then
            b.state = "OFF"
            rednet.broadcast(b.msg .. "_off")
            status = "Sent: " .. b.msg .. "_off"
            render()
          end
        end
      end

    -- Base Storage Touches
    elseif currentApp == "storage" then
      if y == h - 2 and x >= 2 and x <= 12 then
        storagePage = storagePage + 1
        render()
      end
    end
  end
end
