-- ==========================================
-- PINEAPPLE STORE OS (Numismatics + Tag Builder)
-- ==========================================
peripheral.find("modem", rednet.open)
local mon = peripheral.find("monitor")
assert(mon, "No monitor attached!")
mon.setTextScale(0.5)
term.redirect(mon)

-- Optional Numismatics Depositor peripheral (e.g., via CC: Numismatics)
local depositor = peripheral.find("numismatics_depositor")
-- Side where the Numismatics Depositor emits its payment pulse (if using redstone)
local DEPOSITOR_REDSTONE_SIDE = "right"

local STORAGE_PROTOCOL = "base_storage_sync"
local ORDER_PROTOCOL   = "pineapple_order"

-- ==========================================
-- CONFIG: PINEAPPLE PHONE + CAPABILITY TAGS
-- ==========================================
local CURRENCY_LABEL = "Spurs"

local PHONE_CONFIG = {
  name      = "Pineapple Phone",
  tagline   = "One phone. Modular tags.",
  itemId    = "computercraft:pocket_computer_advanced",
  basePrice = 16, -- base price in spurs
  channel   = "pineapple_phone_custom"
}

-- Toggleable tags: players can pick any combination
local PHONE_TAGS = {
  { id = "data-plan", label = "Data Plan",  price = 8,  color = colors.cyan    },
  { id = "wireless",  label = "Wireless",   price = 6,  color = colors.blue    },
  { id = "ender",     label = "Ender",      price = 12, color = colors.purple  },
  { id = "program",   label = "Program",    price = 10, color = colors.orange  },
  { id = "developer", label = "Developer",  price = 15, color = colors.magenta }
}

-- ==========================================
-- STATE VARIABLES
-- ==========================================
local currentView      = "home" -- "home", "builder", "checkout", "receipt"
local selectedTags     = {}     -- map[tagId] = true/false
local orderQty         = 1
local lastOrderSummary = nil
local paymentDetected  = false

local storageConnected = false
local liveTotals       = {}
local liveNames        = {}

local function getSelectedTagList()
  local list = {}
  for _, t in ipairs(PHONE_TAGS) do
    if selectedTags[t.id] then
      table.insert(list, t)
    end
  end
  return list
end

local function getUnitPrice()
  local total = PHONE_CONFIG.basePrice
  for _, t in ipairs(getSelectedTagList()) do
    total = total + t.price
  end
  return total
end

local function getTotalPrice()
  return getUnitPrice() * orderQty
end

local function syncDepositorPrice()
  if depositor and depositor.setTotalPrice then
    pcall(depositor.setTotalPrice, getTotalPrice())
  end
end

local function processIncomingStorage(data)
  if type(data) ~= "table" or not data.totals then return end
  liveTotals = data.totals
  liveNames = data.names or {}
  storageConnected = true
end

-- ==========================================
-- UI PRIMITIVES & APPLE-COLORED PINEAPPLE LOGO
-- ==========================================
local function fillRect(x1, y1, x2, y2, bg)
  if x2 < x1 or y2 < y1 then return end
  term.setBackgroundColor(bg)
  for y = y1, y2 do
    term.setCursorPos(x1, y)
    term.write(string.rep(" ", x2 - x1 + 1))
  end
end

local function writeCentered(y, text, fg, bg)
  local w, _ = term.getSize()
  local x = math.max(1, math.floor((w - #text) / 2) + 1)
  term.setCursorPos(x, y)
  if bg then term.setBackgroundColor(bg) end
  if fg then term.setTextColor(fg) end
  term.write(text:sub(1, w))
end

local function drawPillButton(x, y, label, bg, fg)
  term.setCursorPos(x, y)
  term.setBackgroundColor(bg)
  term.setTextColor(fg)
  term.write(" " .. label .. " ")
  return x, y, x + #label + 1, y
end

-- Green/Lime crown + classic Apple rainbow body
local PINEAPPLE_ART = {
  { row = "    GLG    ", cols = { G = colors.green, L = colors.lime } },
  { row = "   GLLLG   ", cols = { G = colors.green, L = colors.lime } },
  { row = "    GLG    ", cols = { G = colors.green, L = colors.lime } },
  { row = "  GGGGGGG  ", cols = { G = colors.green } },
  { row = " YYYYYYYYY ", cols = { Y = colors.yellow } },
  { row = "OOOOOOOOOOO", cols = { O = colors.orange } },
  { row = "RRRRRRRRRRR", cols = { R = colors.red } },
  { row = "MMMMMMMMMMM", cols = { M = colors.magenta } },
  { row = " PPPPPPPPP ", cols = { P = colors.purple } },
  { row = "  BBBBBBB  ", cols = { B = colors.blue } }
}

local function drawPineappleLogo(centerX, topY)
  for rIdx, line in ipairs(PINEAPPLE_ART) do
    local y = topY + rIdx - 1
    local startX = centerX - math.floor(#line.row / 2)
    for cIdx = 1, #line.row do
      local ch = line.row:sub(cIdx, cIdx)
      local col = line.cols[ch]
      if col then
        term.setCursorPos(startX + cIdx - 1, y)
        term.setBackgroundColor(col)
        term.write(" ")
      end
    end
  end
end

-- ==========================================
-- TOP BAR & VIEWS
-- ==========================================
local hitBoxes = {}
local btnHomeShop = {}

local function drawTopBar()
  local w, _ = term.getSize()
  fillRect(1, 1, w, 1, colors.black)

  term.setCursorPos(2, 1)
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.yellow)
  term.write("@ ")
  term.setTextColor(colors.white)
  term.write("Pineapple")

  term.setCursorPos(14, 1)
  term.setTextColor(currentView == "home" and colors.white or colors.lightGray)
  term.write("Home")

  term.setCursorPos(20, 1)
  term.setTextColor(currentView == "builder" and colors.white or colors.lightGray)
  term.write("Configure")

  local timeStr = textutils.formatTime(os.time(), false)
  local dot = storageConnected and "*" or "o"
  local rightStr = dot .. " " .. timeStr
  term.setCursorPos(w - #rightStr, 1)
  term.setTextColor(storageConnected and colors.lime or colors.orange)
  term.write(dot)
  term.setTextColor(colors.lightGray)
  term.write(" " .. timeStr)
end

local function drawHomeView()
  local w, h = term.getSize()
  fillRect(1, 2, w, h, colors.white)

  local centerX = math.floor(w / 2)
  local logoTop = math.max(3, math.floor(h / 2) - 7)
  drawPineappleLogo(centerX, logoTop)

  local textY = logoTop + #PINEAPPLE_ART + 1
  writeCentered(textY, PHONE_CONFIG.name, colors.black, colors.white)
  writeCentered(textY + 1, PHONE_CONFIG.tagline, colors.gray, colors.white)

  local label = "Configure Phone >"
  local bx = math.max(2, math.floor((w - (#label + 2)) / 2) + 1)
  local by = math.min(h - 1, textY + 3)
  btnHomeShop = { drawPillButton(bx, by, label, colors.blue, colors.white) }
end

local function drawBuilderView()
  local w, h = term.getSize()
  fillRect(1, 2, w, h, colors.lightGray)
  hitBoxes = {}

  fillRect(2, 3, w - 1, h - 1, colors.white)
  term.setCursorPos(3, 3)
  term.setBackgroundColor(colors.white)
  term.setTextColor(colors.black)
  term.write(PHONE_CONFIG.name .. " (Base: " .. PHONE_CONFIG.basePrice .. " " .. CURRENCY_LABEL .. ")")

  term.setCursorPos(3, 4)
  term.setTextColor(colors.gray)
  term.write("Select capability tags:")

  local ty = 6
  for _, t in ipairs(PHONE_TAGS) do
    if ty <= h - 5 then
      local active = selectedTags[t.id] == true
      local prefix = active and "[x] " or "[ ] "
      local pillText = string.format("%s%s (+%d %s)", prefix, t.label, t.price, CURRENCY_LABEL)
      local bg = active and t.color or colors.lightGray
      local fg = (active and t.color == colors.yellow) and colors.black or (active and colors.white or colors.black)

      local x1, y1, x2, y2 = drawPillButton(3, ty, pillText:sub(1, w - 6), bg, fg)
      table.insert(hitBoxes, {
        x1 = x1, y1 = y1, x2 = x2, y2 = y2,
        action = "toggle_tag", tagId = t.id
      })
      ty = ty + 2
    end
  end

  -- Stock & Quantity row
  local ctrlY = h - 4
  local stock = liveTotals[PHONE_CONFIG.itemId]
  local stockStr = storageConnected and ("Stock: " .. tostring(stock or 0)) or "Stock: Standby"
  term.setCursorPos(3, ctrlY)
  term.setBackgroundColor(colors.white)
  term.setTextColor(colors.gray)
  term.write(stockStr)

  local mx1, my1, mx2, my2 = drawPillButton(w - 13, ctrlY, "-", colors.lightGray, colors.black)
  table.insert(hitBoxes, { x1 = mx1, y1 = my1, x2 = mx2, y2 = my2, action = "qty_minus" })

  term.setCursorPos(w - 9, ctrlY)
  term.setBackgroundColor(colors.white)
  term.setTextColor(colors.black)
  term.write(tostring(orderQty))

  local px1, py1, px2, py2 = drawPillButton(w - 6, ctrlY, "+", colors.lightGray, colors.black)
  table.insert(hitBoxes, { x1 = px1, y1 = py1, x2 = px2, y2 = py2, action = "qty_plus" })

  -- Checkout button
  local totalCost = getTotalPrice()
  local buyLabel = "Pay at Depositor (" .. totalCost .. " " .. CURRENCY_LABEL .. ")"
  local bx1, by1, bx2, by2 = drawPillButton(3, h - 2, buyLabel:sub(1, w - 6), colors.blue, colors.white)
  table.insert(hitBoxes, { x1 = bx1, y1 = by1, x2 = bx2, y2 = by2, action = "go_checkout" })
end

local function drawCheckoutView()
  local w, h = term.getSize()
  fillRect(1, 2, w, h, colors.lightGray)
  hitBoxes = {}

  local tags = getSelectedTagList()
  local tagNames = {}
  for _, t in ipairs(tags) do table.insert(tagNames, t.id) end
  local tagSummary = (#tagNames > 0) and table.concat(tagNames, ", ") or "base-only"

  local totalCost = getTotalPrice()
  syncDepositorPrice()

  local boxX1 = math.max(3, math.floor(w * 0.12))
  local boxX2 = math.min(w - 2, math.floor(w * 0.88))
  fillRect(boxX1, 3, boxX2, h - 2, colors.white)

  writeCentered(4, "Numismatics Depositor Checkout", colors.black, colors.white)
  writeCentered(6, string.format("%dx %s", orderQty, PHONE_CONFIG.name), colors.blue, colors.white)
  writeCentered(7, "Tags: " .. tagSummary, colors.gray, colors.white)
  writeCentered(8, string.format("Price: %d %s", totalCost, CURRENCY_LABEL), colors.black, colors.white)

  fillRect(boxX1 + 2, 10, boxX2 - 2, 12, colors.lightGray)
  writeCentered(11, "Pay at Numismatics Depositor to dispense...", colors.black, colors.lightGray)

  local cx1, cy1, cx2, cy2 = drawPillButton(boxX1 + 3, h - 4, "< Back", colors.gray, colors.white)
  table.insert(hitBoxes, { x1 = cx1, y1 = cy1, x2 = cx2, y2 = cy2, action = "back_builder" })
end

local function drawReceiptView()
  local w, h = term.getSize()
  fillRect(1, 2, w, h, colors.white)
  hitBoxes = {}

  drawPineappleLogo(math.floor(w / 2), 3)
  writeCentered(14, "Payment Confirmed! Order Dispatched.", colors.green, colors.white)
  if lastOrderSummary then
    writeCentered(15, lastOrderSummary, colors.black, colors.white)
  end

  local label = "Build Another"
  local bx = math.max(2, math.floor((w - (#label + 2)) / 2) + 1)
  local x1, y1, x2, y2 = drawPillButton(bx, math.min(h - 1, 17), label, colors.blue, colors.white)
  table.insert(hitBoxes, { x1 = x1, y1 = y1, x2 = x2, y2 = y2, action = "back_builder" })
end

local function dispatchPhoneOrder()
  local tags = {}
  for _, t in ipairs(getSelectedTagList()) do
    table.insert(tags, t.id)
  end

  local payload = {
    action  = "dispense_order",
    product = PHONE_CONFIG.name,
    item    = PHONE_CONFIG.itemId,
    channel = PHONE_CONFIG.channel,
    tags    = tags,
    qty     = orderQty,
    paid    = getTotalPrice()
  }
  rednet.broadcast(payload, ORDER_PROTOCOL)

  local tagStr = (#tags > 0) and (" [" .. table.concat(tags, ", ") .. "]") or ""
  lastOrderSummary = string.format("%dx %s%s", orderQty, PHONE_CONFIG.name, tagStr)
  orderQty = 1
  currentView = "receipt"
end

-- ==========================================
-- MASTER RENDER & EVENT LOOP
-- ==========================================
local function render()
  drawTopBar()
  if currentView == "home" then
    drawHomeView()
  elseif currentView == "builder" then
    drawBuilderView()
  elseif currentView == "checkout" then
    drawCheckoutView()
  elseif currentView == "receipt" then
    drawReceiptView()
  end
end

render()
local clockTimer = os.startTimer(5)
local prevRedstone = redstone.getInput(DEPOSITOR_REDSTONE_SIDE)

while true do
  local event, p1, p2, p3 = os.pullEvent()

  if event == "timer" and p1 == clockTimer then
    render()
    clockTimer = os.startTimer(5)

  elseif event == "redstone" and currentView == "checkout" then
    local nowRedstone = redstone.getInput(DEPOSITOR_REDSTONE_SIDE)
    if nowRedstone and not prevRedstone then
      dispatchPhoneOrder()
      render()
    end
    prevRedstone = nowRedstone

  elseif event == "rednet_message" and p3 == STORAGE_PROTOCOL then
    processIncomingStorage(p2)
    render()

  elseif event == "monitor_touch" then
    local x, y = p2, p3

    if y == 1 then
      if x >= 2 and x <= 18 then
        currentView = "home"
        render()
      elseif x >= 20 and x <= 28 then
        currentView = "builder"
        syncDepositorPrice()
        render()
      end

    elseif currentView == "home" then
      if #btnHomeShop == 4 and x >= btnHomeShop[1] and x <= btnHomeShop[3] and y == btnHomeShop[2] then
        currentView = "builder"
        syncDepositorPrice()
        render()
      end

    else
      for _, hb in ipairs(hitBoxes) do
        if x >= hb.x1 and x <= hb.x2 and y >= hb.y1 and y <= hb.y2 then
          if hb.action == "toggle_tag" then
            selectedTags[hb.tagId] = not selectedTags[hb.tagId]
            syncDepositorPrice()
          elseif hb.action == "qty_minus" then
            orderQty = math.max(1, orderQty - 1)
            syncDepositorPrice()
          elseif hb.action == "qty_plus" then
            orderQty = math.min(64, orderQty + 1)
            syncDepositorPrice()
          elseif hb.action == "go_checkout" then
            currentView = "checkout"
            syncDepositorPrice()
          elseif hb.action == "back_builder" then
            currentView = "builder"
            syncDepositorPrice()
          end
          render()
          break
        end
      end
    end
  end
end
