-- ==========================================
-- PINEAPPLE STORE (Kiosk OS for CC:Tweaked + Create 6)
-- ==========================================
local mon = peripheral.find("monitor")
assert(mon, "No monitor attached!")
mon.setTextScale(0.5)
term.redirect(mon)
local monName = peripheral.getName(mon)

-- ==========================================
-- CONFIG
-- ==========================================
local CONFIG = {
  paymentChest   = "minecraft:chest_0", -- customers drop currency here (on the counter)
  tillChest      = "minecraft:chest_1", -- shop takings (keep this one out of reach)
  pickupAddress  = "Pineapple Pickup",  -- address on the counter's Frogport/Postbox
  currency       = "minecraft:diamond",
  currencyName   = "Diamond",
  paymentTimeout = 120, -- seconds before an unpaid checkout cancels
  idleTimeout    = 60,  -- seconds without touches before returning to the desktop
}

-- bundle = items per purchase, price = currency per bundle
local products = {
  { id = "create:andesite_alloy", label = "Andesite Alloy", bundle = 32, price = 1 },
  { id = "minecraft:iron_ingot",  label = "Iron Ingots",    bundle = 16, price = 1 },
  { id = "minecraft:gold_ingot",  label = "Gold Ingots",    bundle = 16, price = 2 },
  { id = "minecraft:wheat",       label = "Wheat",          bundle = 64, price = 1 },
  { id = "minecraft:dried_kelp",  label = "Dried Kelp",     bundle = 64, price = 1 },
}

local ticker = peripheral.find("Create_StockTicker")
assert(ticker, "No Stock Ticker attached!")
local payChest = peripheral.wrap(CONFIG.paymentChest)
assert(payChest, "Payment chest not found: " .. CONFIG.paymentChest)
local till = peripheral.wrap(CONFIG.tillChest)
assert(till, "Till chest not found: " .. CONFIG.tillChest)

-- ==========================================
-- APPLE PALETTE
-- ==========================================
local PALETTE = {
  [colors.white]     = 0xFFFFFF, [colors.black]     = 0x1D1D1F,
  [colors.gray]      = 0x86868B, [colors.lightGray] = 0xF5F5F7,
  [colors.cyan]      = 0xD2D2D7, -- hairlines / dock glass
  [colors.brown]     = 0xE8E8ED, -- window title bar
  [colors.lightBlue] = 0x0071E3, -- Apple button blue
  [colors.green]     = 0x34C759,
  [colors.pink]      = 0x9ADCF7, -- pale morning sky
  -- classic Apple rainbow stripes
  [colors.lime]   = 0x61BB46, [colors.yellow] = 0xFDB827, [colors.orange] = 0xF5821F,
  [colors.red]    = 0xE03A3E, [colors.purple] = 0x963D97, [colors.blue]   = 0x009DDC,
}
for c, hex in pairs(PALETTE) do term.setPaletteColour(c, hex) end

-- ==========================================
-- STATE VARIABLES
-- ==========================================
local currentApp = "desktop" -- "desktop", "store", "help", "about"
local menuOpen = false
local storeView = "list"     -- "list", "detail", "checkout", "result"
local storePage = 1
local storageConnected = false
local liveTotals = {}
local selected, qty = nil, 1
local order = nil            -- { product, qty, price, paid, deadline }
local result = nil           -- { title, lines, color, closesAt }
local lastTouch = os.clock()
local lastStock = 0
local hitboxes = {}

local appTitles = { desktop = "Pineapple", store = "Store", help = "Help", about = "About" }

-- ==========================================
-- STOCK & PAYMENT
-- ==========================================
local function refreshStock()
  local ok, list = pcall(ticker.stock)
  storageConnected = ok and type(list) == "table"
  if not storageConnected then return end
  liveTotals = {}
  for _, it in ipairs(list) do
    liveTotals[it.name] = (liveTotals[it.name] or 0) + it.count
  end
end

local function available(p)
  return math.floor((liveTotals[p.id] or 0) / p.bundle)
end

local function money(n)
  return n .. " " .. CONFIG.currencyName .. (n == 1 and "" or "s")
end

local function countPaid()
  local n = 0
  for _, it in pairs(payChest.list()) do
    if it.name == CONFIG.currency then n = n + it.count end
  end
  return n
end

-- moves up to `amount` currency between inventories, returns how many moved
local function moveCurrency(from, toName, amount)
  local moved = 0
  for slot, it in pairs(from.list()) do
    if moved >= amount then break end
    if it.name == CONFIG.currency then
      moved = moved + from.pushItems(toName, slot, amount - moved)
    end
  end
  return moved
end

-- ==========================================
-- SUNRISE HILLS WALLPAPER GENERATOR
-- ==========================================
local function getWallpaperColor(x, y, w, h)
  local nx = x / w
  local ny = y / h

  -- Rolling hills in the Apple stripes, front ridge first
  local ridges = {
    { colors.lime,   0.80, 0.05, 3.0, 0.3 },
    { colors.yellow, 0.72, 0.06, 3.8, 1.9 },
    { colors.orange, 0.64, 0.06, 4.5, 0.8 },
    { colors.red,    0.57, 0.05, 5.2, 2.6 },
    { colors.purple, 0.50, 0.05, 6.0, 1.2 },
  }
  for _, r in ipairs(ridges) do
    if ny >= r[2] + r[3] * math.sin(nx * r[4] + r[5]) then return r[1] end
  end

  -- A couple of soft clouds
  local c1 = ((nx - 0.80) / 0.10)^2 + ((ny - 0.18) / 0.04)^2
  local c2 = ((nx - 0.18) / 0.08)^2 + ((ny - 0.26) / 0.035)^2
  if c1 <= 1.0 or c2 <= 1.0 then return colors.white end

  -- Sky: deeper blue at the top
  return ny < 0.2 and colors.blue or colors.pink
end

local wallpaperRows, wallpaperW, wallpaperH = nil, 0, 0

local function drawWallpaper()
  local w, h = term.getSize()
  if not wallpaperRows or w ~= wallpaperW or h ~= wallpaperH then
    wallpaperRows, wallpaperW, wallpaperH = {}, w, h
    for y = 2, h do
      local bg = {}
      for x = 1, w do bg[x] = colors.toBlit(getWallpaperColor(x, y, w, h)) end
      wallpaperRows[y] = table.concat(bg)
    end
  end
  local blank, fg = string.rep(" ", w), string.rep("f", w)
  for y = 2, h do
    term.setCursorPos(1, y)
    term.blit(blank, fg, wallpaperRows[y])
  end
end

-- ==========================================
-- UI DRAWING PRIMITIVES
-- ==========================================
local function fillRect(x1, y1, x2, y2, bg)
  if x2 < x1 or y2 < y1 then return end
  term.setBackgroundColor(bg)
  for y = y1, y2 do
    term.setCursorPos(x1, y)
    term.write(string.rep(" ", x2 - x1 + 1))
  end
end

local function writeAt(x, y, s, fg, bg)
  term.setCursorPos(x, y)
  term.setTextColor(fg)
  term.setBackgroundColor(bg)
  term.write(s)
end

local function centerIn(x1, x2, y, s, fg, bg)
  writeAt(x1 + math.floor((x2 - x1 + 1 - #s) / 2), y, s, fg, bg)
end

local function addHit(id, x1, y1, x2, y2, data)
  hitboxes[#hitboxes + 1] = { id = id, x1 = x1, y1 = y1, x2 = x2, y2 = y2, data = data }
end

-- last drawn wins, so menus and the dock sit above windows
local function findHit(x, y)
  for i = #hitboxes, 1, -1 do
    local b = hitboxes[i]
    if x >= b.x1 and x <= b.x2 and y >= b.y1 and y <= b.y2 then return b end
  end
end

local function button(id, x, y, w, label, bg, fg, data)
  fillRect(x, y, x + w - 1, y + 2, bg)
  writeAt(x + math.floor((w - #label) / 2), y + 1, label, fg, bg)
  addHit(id, x, y, x + w - 1, y + 2, data)
end

-- Pineapple in Apple's six stripes: green crown, then yellow/orange/red/purple/blue
local LOGO = {
  "    g g    ",
  "  g  g  g  ",
  "   g g g   ",
  "    ggg    ",
  "   yyyyy   ",
  " yyyyyyyyy ",
  " ooooooooo ",
  "ooooooooooo",
  "rrrrrrrrrrr",
  "rrrrrrrrrrr",
  " ppppppppp ",
  " ppppppppp ",
  "  bbbbbbb  ",
  "    bbb    ",
}
local MINI = { " g ", "yyy", "rpb" }
local LOGO_COL = { g = colors.lime, y = colors.yellow, o = colors.orange,
                   r = colors.red, p = colors.purple, b = colors.blue }

local function drawLogo(x, y, art)
  for row, line in ipairs(art) do
    for col = 1, #line do
      local c = LOGO_COL[line:sub(col, col)]
      if c then
        term.setCursorPos(x + col - 1, y + row - 1)
        term.setBackgroundColor(c)
        term.write(" ")
      end
    end
  end
end

local function getWindowBounds()
  local w, h = term.getSize()
  return 3, 3, w - 2, h - 8
end

local function getWindowInnerBounds()
  local x1, y1, x2, y2 = getWindowBounds()
  return x1 + 2, y1 + 2, x2 - 2, y2 - 1
end

local function drawWindow(title)
  local x1, y1, x2, y2 = getWindowBounds()

  -- soft shadow, body, title bar
  fillRect(x1 + 1, y2 + 1, x2 + 1, y2 + 1, colors.gray)
  fillRect(x2 + 1, y1 + 1, x2 + 1, y2, colors.gray)
  fillRect(x1, y1, x2, y2, colors.white)
  fillRect(x1, y1, x2, y1, colors.brown)

  -- traffic lights (any of them closes the window)
  writeAt(x1 + 1, y1, "\7", colors.red, colors.brown)
  writeAt(x1 + 3, y1, "\7", colors.yellow, colors.brown)
  writeAt(x1 + 5, y1, "\7", colors.green, colors.brown)
  addHit("close", x1, y1, x1 + 6, y1)

  centerIn(x1, x2, y1, title, colors.black, colors.brown)
  return getWindowInnerBounds()
end

-- ==========================================
-- MENU BAR, PINEAPPLE MENU & DOCK
-- ==========================================
local menuItems = {
  { id = "about",   label = "About Pineapple" },
  { id = "store",   label = "Open Store"      },
  { id = "help",    label = "How to Buy"      },
  { id = "desktop", label = "Home"            },
}

local dockApps = {
  { id = "store", label = "Store", color = colors.lightBlue, glyph = "$" },
  { id = "help",  label = "Help",  color = colors.purple,    glyph = "?" },
  { id = "about", label = "About", color = colors.white                  },
}

local function drawMenuBar()
  local w = term.getSize()
  fillRect(1, 1, w, 1, colors.white)
  writeAt(2, 1, "\30", colors.lime, menuOpen and colors.cyan or colors.yellow)
  addHit("menu", 1, 1, 3, 1)
  writeAt(5, 1, appTitles[currentApp], colors.black, colors.white)

  local timeStr = textutils.formatTime(os.time(), false)
  writeAt(w - #timeStr - 3, 1, "\7", storageConnected and colors.green or colors.orange, colors.white)
  writeAt(w - #timeStr, 1, timeStr, colors.black, colors.white)
end

local function drawMenu()
  local x1, x2 = 1, 20
  for i, item in ipairs(menuItems) do
    local y = 1 + i
    fillRect(x1, y, x2, y, colors.white)
    writeAt(x1 + 2, y, item.label, colors.black, colors.white)
    addHit("open", x1, y, x2, y, item.id)
  end
  fillRect(x1, 2 + #menuItems, x2, 2 + #menuItems, colors.cyan)
end

local function drawDock()
  local w, h = term.getSize()
  local dw = #dockApps * 7 + 2
  local dx = math.floor((w - dw) / 2) + 1
  fillRect(dx, h - 5, dx + dw - 1, h, colors.cyan)

  for i, app in ipairs(dockApps) do
    local ix = dx + 2 + (i - 1) * 7
    fillRect(ix, h - 4, ix + 4, h - 2, app.color)
    if app.glyph then
      writeAt(ix + 2, h - 3, app.glyph, colors.white, app.color)
    else
      drawLogo(ix + 1, h - 4, MINI)
    end
    centerIn(ix, ix + 4, h - 1, app.label, colors.black, colors.cyan)
    if currentApp == app.id then writeAt(ix + 2, h, "\7", colors.gray, colors.cyan) end
    addHit("open", ix, h - 4, ix + 4, h - 1, app.id)
  end
end

-- ==========================================
-- DESKTOP & APP VIEWS
-- ==========================================
local function drawDesktop()
  local w = term.getSize()
  drawLogo(math.floor((w - 11) / 2) + 1, 3, LOGO)

  local msg = "Welcome to Pineapple"
  local bw = #msg + 6
  local bx = math.floor((w - bw) / 2) + 1
  fillRect(bx, 18, bx + bw - 1, 20, colors.white)
  writeAt(bx + 3, 19, msg, colors.black, colors.white)
  button("start", math.floor((w - 20) / 2) + 1, 22, 20, "Start Shopping", colors.lightBlue, colors.white)
end

local function drawStoreList(ix1, iy1, ix2, iy2)
  writeAt(ix1, iy1, "Shop the latest.", colors.black, colors.white)
  writeAt(ix1, iy1 + 1, "Pay with " .. CONFIG.currencyName .. "s. Collect at the pickup counter.",
          colors.gray, colors.white)

  local top, rowH = iy1 + 3, 5
  local perPage = math.max(1, math.floor((iy2 - 1 - top - 3) / rowH) + 1)
  local pages = math.max(1, math.ceil(#products / perPage))
  if storePage > pages then storePage = pages end

  for i = 1, perPage do
    local p = products[(storePage - 1) * perPage + i]
    if not p then break end
    local y = top + (i - 1) * rowH
    local left = available(p)
    local priceTxt = money(p.price)
    local status = left > 0 and (left .. " left") or "Sold out"

    fillRect(ix1, y, ix2, y + 3, colors.lightGray)
    writeAt(ix1 + 2, y + 1, p.label, colors.black, colors.lightGray)
    writeAt(ix2 - #priceTxt - 1, y + 1, priceTxt, colors.lightBlue, colors.lightGray)
    writeAt(ix1 + 2, y + 2, p.bundle .. " per bundle", colors.gray, colors.lightGray)
    writeAt(ix2 - #status - 1, y + 2, status, left > 0 and colors.green or colors.red, colors.lightGray)
    addHit("product", ix1, y, ix2, y + 3, p)
  end

  if pages > 1 then
    if storePage > 1 then
      writeAt(ix1, iy2, "< Prev", colors.lightBlue, colors.white)
      addHit("prev", ix1, iy2, ix1 + 5, iy2)
    end
    centerIn(ix1, ix2, iy2, "Page " .. storePage .. "/" .. pages, colors.gray, colors.white)
    if storePage < pages then
      writeAt(ix2 - 5, iy2, "Next >", colors.lightBlue, colors.white)
      addHit("next", ix2 - 5, iy2, ix2, iy2)
    end
  end
end

local function drawStoreDetail(ix1, iy1, ix2, iy2)
  local p = selected
  local left = available(p)
  writeAt(ix1, iy1, "< Store", colors.lightBlue, colors.white)
  addHit("back", ix1, iy1, ix1 + 6, iy1)

  local cx = math.floor((ix1 + ix2) / 2)
  local y = iy1 + 3
  centerIn(ix1, ix2, y, p.label, colors.black, colors.white)
  centerIn(ix1, ix2, y + 1, p.bundle .. " per bundle  -  " .. money(p.price) .. " each",
           colors.gray, colors.white)
  centerIn(ix1, ix2, y + 2, left > 0 and (left .. " bundles available") or "Sold out",
           left > 0 and colors.green or colors.red, colors.white)

  button("minus", cx - 9, y + 5, 5, "-", colors.lightGray, colors.black)
  centerIn(ix1, ix2, y + 6, tostring(qty), colors.black, colors.white)
  button("plus", cx + 5, y + 5, 5, "+", colors.lightGray, colors.black)

  centerIn(ix1, ix2, y + 9, "Total  " .. money(p.price * qty), colors.black, colors.white)
  button("buy", cx - 8, y + 11, 17, "Buy", left > 0 and colors.lightBlue or colors.cyan, colors.white)
end

local function drawStoreCheckout(ix1, iy1, ix2, iy2)
  local y = iy1 + 3
  centerIn(ix1, ix2, y, "Insert " .. money(order.price), colors.black, colors.white)
  centerIn(ix1, ix2, y + 1, "into the payment chest on the counter", colors.gray, colors.white)

  local bw = math.min(40, ix2 - ix1 - 3)
  local bx = ix1 + math.floor((ix2 - ix1 + 1 - bw) / 2)
  fillRect(bx, y + 4, bx + bw - 1, y + 4, colors.cyan)
  local done = math.floor(bw * math.min(order.paid, order.price) / order.price)
  if done > 0 then fillRect(bx, y + 4, bx + done - 1, y + 4, colors.lightBlue) end

  centerIn(ix1, ix2, y + 6, math.min(order.paid, order.price) .. " / " .. order.price .. " paid",
           colors.black, colors.white)
  local secs = math.max(0, math.ceil(order.deadline - os.clock()))
  centerIn(ix1, ix2, y + 8, "Cancels in " .. secs .. "s", colors.gray, colors.white)
  button("cancel", math.floor((ix1 + ix2) / 2) - 7, y + 10, 15, "Cancel", colors.lightGray, colors.red)
end

local function drawStoreResult(ix1, iy1, ix2, iy2)
  local y = iy1 + 4
  centerIn(ix1, ix2, y, result.title, result.color, colors.white)
  for i, line in ipairs(result.lines) do
    centerIn(ix1, ix2, y + 1 + i, line, colors.gray, colors.white)
  end
  button("done", math.floor((ix1 + ix2) / 2) - 7, y + #result.lines + 4, 15, "Done",
         colors.lightBlue, colors.white)
end

local function drawHelp(ix1, iy1, ix2, iy2)
  local lines = {
    "1. Tap Store and pick an item.",
    "2. Choose how many bundles, then tap Buy.",
    "3. Drop " .. CONFIG.currencyName .. "s into the payment chest.",
    "4. Collect your package at the pickup counter.",
  }
  writeAt(ix1, iy1, "How to buy", colors.black, colors.white)
  for i, line in ipairs(lines) do writeAt(ix1, iy1 + 1 + i, line, colors.black, colors.white) end
  writeAt(ix1, iy1 + 7, "Change and refunds go back into the payment chest.", colors.gray, colors.white)
  button("start", ix1, iy1 + 9, 18, "Open Store", colors.lightBlue, colors.white)
end

local function drawAbout(ix1, iy1, ix2, iy2)
  drawLogo(ix1 + math.floor((ix2 - ix1 + 1 - 11) / 2), iy1, LOGO)
  centerIn(ix1, ix2, iy1 + 16, "Pineapple Store", colors.black, colors.white)
  centerIn(ix1, ix2, iy1 + 17, "Version 1.0", colors.gray, colors.white)
  centerIn(ix1, ix2, iy1 + 19, "Delivered by Create. Powered by CC:Tweaked.", colors.gray, colors.white)
end

-- ==========================================
-- MASTER RENDER
-- ==========================================
local function render()
  hitboxes = {}
  drawWallpaper()

  if currentApp == "desktop" then
    drawDesktop()
  else
    local title = currentApp == "store" and "Pineapple Store" or appTitles[currentApp]
    local ix1, iy1, ix2, iy2 = drawWindow(title)
    if currentApp == "store" then
      if storeView == "list" then drawStoreList(ix1, iy1, ix2, iy2)
      elseif storeView == "detail" then drawStoreDetail(ix1, iy1, ix2, iy2)
      elseif storeView == "checkout" then drawStoreCheckout(ix1, iy1, ix2, iy2)
      elseif storeView == "result" then drawStoreResult(ix1, iy1, ix2, iy2)
      end
    elseif currentApp == "help" then
      drawHelp(ix1, iy1, ix2, iy2)
    elseif currentApp == "about" then
      drawAbout(ix1, iy1, ix2, iy2)
    end
  end

  drawDock()
  drawMenuBar()
  if menuOpen then drawMenu() end
end

-- ==========================================
-- STORE ACTIONS
-- ==========================================
local function openApp(id)
  currentApp = id
  storeView, order, result = "list", nil, nil
  if id == "store" then storePage = 1 end
end

local function showResult(title, lines, color)
  result = { title = title, lines = lines, color = color, closesAt = os.clock() + 10 }
  storeView, order = "result", nil
end

local function fulfil()
  local p, price = order.product, order.price
  local want = p.bundle * order.qty
  local ok, got = pcall(ticker.requestFiltered, CONFIG.pickupAddress,
                        { name = p.id, _requestCount = want })
  got = (ok and tonumber(got)) or 0

  -- refund any bundles the network couldn't send
  local refund = price - math.floor(got / p.bundle) * p.price
  if refund > 0 then moveCurrency(till, CONFIG.paymentChest, refund) end

  if got >= want then
    showResult("Thank you!", {
      "Your " .. p.label .. " is on its way to the pickup counter.",
      "Any change is waiting in the payment chest." }, colors.green)
  elseif got > 0 then
    showResult("Partly delivered", {
      "Only " .. got .. " of " .. want .. " were in stock.",
      money(refund) .. " refunded to the payment chest." }, colors.black)
  else
    showResult("Sorry, that just sold out", {
      "Your " .. money(price) .. " are back in the payment chest." }, colors.red)
  end
  refreshStock()
end

local function pollPayment()
  order.paid = countPaid()
  if order.paid >= order.price then
    local moved = moveCurrency(payChest, CONFIG.tillChest, order.price)
    if moved >= order.price then return fulfil() end
    moveCurrency(till, CONFIG.paymentChest, moved) -- items taken mid-transfer: put them back
  end
  if os.clock() >= order.deadline then
    showResult("Checkout timed out", {
      "Take your " .. CONFIG.currencyName .. "s back from the payment chest." }, colors.black)
  end
end

local function handleTouch(x, y)
  local hit = findHit(x, y)

  -- tapping anywhere outside the open menu just closes it
  if menuOpen and not (hit and (hit.id == "open" or hit.id == "menu")) then
    menuOpen = false
    return
  end
  if not hit then return end

  local id = hit.id
  if id == "menu" then
    menuOpen = not menuOpen
  elseif id == "open" then
    menuOpen = false
    openApp(hit.data)
  elseif id == "close" then
    openApp("desktop")
  elseif id == "start" then
    openApp("store")
  elseif id == "prev" then
    storePage = math.max(1, storePage - 1)
  elseif id == "next" then
    storePage = storePage + 1
  elseif id == "product" then
    selected, qty, storeView = hit.data, 1, "detail"
  elseif id == "back" then
    storeView = "list"
  elseif id == "minus" then
    qty = math.max(1, qty - 1)
  elseif id == "plus" then
    qty = math.min(qty + 1, math.max(1, available(selected)))
  elseif id == "buy" then
    refreshStock()
    local left = available(selected)
    if left >= qty then
      order = { product = selected, qty = qty, price = selected.price * qty, paid = countPaid(),
                deadline = os.clock() + CONFIG.paymentTimeout }
      storeView = "checkout"
    else
      qty = math.max(1, left)
    end
  elseif id == "cancel" then
    showResult("Order cancelled", {
      "Take your " .. CONFIG.currencyName .. "s back from the payment chest." }, colors.black)
  elseif id == "done" then
    storeView, result = "list", nil
  end
end

local function tick()
  local now = os.clock()
  if now - lastStock >= 5 then
    refreshStock()
    lastStock = now
  end

  if currentApp == "store" and storeView == "checkout" then
    pollPayment()
  elseif currentApp == "store" and storeView == "result" and now >= result.closesAt then
    storeView, result = "list", nil
  elseif currentApp ~= "desktop" and now - lastTouch >= CONFIG.idleTimeout then
    menuOpen = false
    openApp("desktop")
  end
end

-- ==========================================
-- EVENT LOOP
-- ==========================================
local function mainLoop()
  refreshStock()
  render()
  local clockTimer = os.startTimer(1)
  while true do
    local event, p1, p2, p3 = os.pullEvent()
    if event == "timer" and p1 == clockTimer then
      tick()
      render()
      clockTimer = os.startTimer(1)
    elseif event == "monitor_touch" and p1 == monName then
      lastTouch = os.clock()
      handleTouch(p2, p3)
      render()
    elseif event == "monitor_resize" then
      render()
    end
  end
end

-- restart after errors so the kiosk never stays frozen
while true do
  local ok, err = pcall(mainLoop)
  if not ok then
    term.setBackgroundColor(colors.white)
    term.clear()
    term.setCursorPos(2, 2)
    term.setTextColor(colors.red)
    print("Pineapple is restarting: " .. tostring(err))
    sleep(5)
    openApp("desktop")
  end
end
