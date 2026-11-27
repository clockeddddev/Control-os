-- ==========================================
-- PINEAPPLE STORE OS (Apple Design System)
-- ==========================================
peripheral.find("modem", rednet.open)
local mon = peripheral.find("monitor")
assert(mon, "No monitor attached!")
mon.setTextScale(0.5)
term.redirect(mon)

-- Attach the deposit chest/barrel (wired or adjacent)
local depositor = peripheral.find("minecraft:chest")
  or peripheral.find("minecraft:barrel")
  or peripheral.find("inventory")

local STORAGE_PROTOCOL = "base_storage_sync"
local ORDER_PROTOCOL   = "pineapple_order"

-- ==========================================
-- CONFIG: CURRENCY & CATALOG WITH VARIATIONS
-- ==========================================
local CURRENCY_ID    = "minecraft:diamond"
local CURRENCY_LABEL = "Diamonds"

local CATALOG = {
  {
    name = "Pineapple Phone 16",
    tagline = "Pro titanium. Unmatched power.",
    category = "Phones",
    variations = {
      { label = "Standard (128GB)", id = "computercraft:pocket_computer_normal",   price = 4,  channel = "phone16_std" },
      { label = "Pro (256GB)",      id = "computercraft:pocket_computer_advanced", price = 8,  channel = "phone16_pro" },
      { label = "Pro Max (1TB)",    id = "computercraft:pocket_computer_advanced", price = 14, channel = "phone16_max" }
    }
  },
  {
    name = "Pineapple Phone SE",
    tagline = "Compact. Essential. Fast.",
    category = "Phones",
    variations = {
      { label = "Midnight (64GB)",  id = "computercraft:pocket_computer_normal",   price = 2,  channel = "phonese_blk" },
      { label = "Starlight (128GB)",id = "computercraft:pocket_computer_normal",   price = 3,  channel = "phonese_wht" }
    }
  },
  {
    name = "Create Starter Kit",
    tagline = "Precision mechanical engineering.",
    category = "Hardware",
    variations = {
      { label = "Andesite Pack x16", id = "create:andesite_alloy", price = 2, channel = "kit_andesite" },
      { label = "Brass Pack x16",    id = "create:brass_ingot",    price = 5, channel = "kit_brass"    }
    }
  },
  {
    name = "Factory Materials",
    tagline = "Bulk resources on demand.",
    category = "Materials",
    variations = {
      { label = "Iron Ingots x32",   id = "minecraft:iron_ingot",  price = 2, channel = "mat_iron"     },
      { label = "Gold Ingots x32",   id = "minecraft:gold_ingot",  price = 4, channel = "mat_gold"     }
    }
  }
}

-- ==========================================
-- STATE VARIABLES
-- ==========================================
local currentView      = "home" -- "home", "store", "checkout", "receipt"
local selectedItemIdx  = 1
local selectedVarIdx   = 1
local orderQty         = 1
local scrollOffset     = 0
local statusMessage    = "Ready"
local lastOrderSummary = nil

local storageConnected = false
local liveTotals       = {}
local liveNames        = {}

local function processIncomingStorage(data)
  if type(data) ~= "table" or not data.totals then return end
  liveTotals = data.totals
  liveNames = data.names or {}
  storageConnected = true
end

-- ==========================================
-- PAYMENT DEPOSITOR HELPERS
-- ==========================================
local function countDepositedCurrency()
  if not depositor then return 0 end
  local total = 0
  local items = depositor.list()
  for _, stack in pairs(items) do
    if stack.name == CURRENCY_ID then
      total = total + stack.count
    end
  end
  return total
end

local function consumeDepositedCurrency(amountNeeded)
  if not depositor then return false end
  if countDepositedCurrency() < amountNeeded then return false end

  local remaining = amountNeeded
  local items = depositor.list()
  for slot, stack in pairs(items) do
    if stack.name == CURRENCY_ID and remaining > 0 then
      local take = math.min(stack.count, remaining)
      -- Push to a dummy slot or drop into a void/vault chest if attached,
      -- or pull into the shop computer's own inventory slots:
      local moved = 0
      for mySlot = 1, 16 do
        if remaining <= 0 then break end
        local space = turtle and turtle.getItemSpace(mySlot) or 64
        local current = turtle and turtle.getItemDetail(mySlot) or nil
        if not current or current.name == CURRENCY_ID then
          local pushed = depositor.pushItems(peripheral.getName(depositor), slot, 0) -- no-op check
          -- Pull directly into computer's local inventory if using a wired modem:
          local localName = rednet.isOpen() and "top" or nil
          moved = take
          break
        end
      end
      remaining = remaining - take
    end
  end
  return remaining <= 0
end

-- ==========================================
-- APPLE DESIGN UI PRIMITIVES
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

-- ==========================================
-- CLASSIC APPLE-COLORED PINEAPPLE LOGO
-- ==========================================
-- Crown leaves in Green/Lime, striped body in classic Apple Rainbow:
-- Green, Yellow, Orange, Red, Magenta, Purple, Blue
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
-- TOP APPLE MENU BAR
-- ==========================================
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
  term.setTextColor(currentView == "store" and colors.white or colors.lightGray)
  term.write("Store")

  local timeStr = textutils.formatTime(os.time(), false)
  local statusDot = storageConnected and "*" or "o"
  local rightStr = statusDot .. " " .. timeStr
  term.setCursorPos(w - #rightStr, 1)
  term.setTextColor(storageConnected and colors.lime or colors.orange)
  term.write(statusDot)
  term.setTextColor(colors.lightGray)
  term.write(" " .. timeStr)
end

-- ==========================================
-- VIEW 1: HERO HOME SCREEN
-- ==========================================
local btnHomeShop = {}

local function drawHomeView()
  local w, h = term.getSize()
  fillRect(1, 2, w, h, colors.white)

  local centerX = math.floor(w / 2)
  local logoTop = math.max(3, math.floor(h / 2) - 7)
  drawPineappleLogo(centerX, logoTop)

  local textY = logoTop + #PINEAPPLE_ART + 1
  writeCentered(textY, "Pineapple Store", colors.black, colors.white)
  writeCentered(textY + 1, "Think Different. Build Mechanical.", colors.gray, colors.white)

  local btnLabel = "Browse Products >"
  local bx = math.max(2, math.floor((w - (#btnLabel + 2)) / 2) + 1)
  local by = math.min(h - 1, textY + 3)
  btnHomeShop = { drawPillButton(bx, by, btnLabel, colors.blue, colors.white) }
end

-- ==========================================
-- VIEW 2: STORE CATALOG & VARIATION SELECTOR
-- ==========================================
local hitBoxes = {}

local function drawStoreView()
  local w, h = term.getSize()
  fillRect(1, 2, w, h, colors.lightGray)
  hitBoxes = {}

  local leftW = math.max(18, math.floor(w * 0.44))
  local rightX = leftW + 2

  -- Left Column: Product Cards
  fillRect(2, 3, leftW, h - 1, colors.white)
  term.setCursorPos(3, 3)
  term.setBackgroundColor(colors.white)
  term.setTextColor(colors.gray)
  term.write("PRODUCTS")

  for idx, prod in ipairs(CATALOG) do
    local cardY = 4 + (idx - 1) * 3
    if cardY + 1 <= h - 1 then
      local isSel = (idx == selectedItemIdx)
      local cardBg = isSel and colors.blue or colors.white
      local titleFg = isSel and colors.white or colors.black
      local subFg   = isSel and colors.lightBlue or colors.gray

      fillRect(2, cardY, leftW, cardY + 1, cardBg)
      term.setCursorPos(3, cardY)
      term.setTextColor(titleFg)
      term.write(prod.name:sub(1, leftW - 3))

      term.setCursorPos(3, cardY + 1)
      term.setTextColor(subFg)
      local minPrice = prod.variations[1].price
      term.write(("From " .. minPrice .. " " .. CURRENCY_LABEL):sub(1, leftW - 3))

      table.insert(hitBoxes, {
        x1 = 2, y1 = cardY, x2 = leftW, y2 = cardY + 1,
        action = "select_product", idx = idx
      })
    end
  end

  -- Right Column: Selected Product & Variations
  fillRect(rightX, 3, w - 1, h - 1, colors.white)
  local prod = CATALOG[selectedItemIdx]
  if not prod then return end
  local var = prod.variations[selectedVarIdx] or prod.variations[1]

  term.setCursorPos(rightX + 1, 4)
  term.setBackgroundColor(colors.white)
  term.setTextColor(colors.black)
  term.write(prod.name:sub(1, w - rightX - 2))

  term.setCursorPos(rightX + 1, 5)
  term.setTextColor(colors.gray)
  term.write(prod.tagline:sub(1, w - rightX - 2))

  -- Variation / Model Selector Pills
  term.setCursorPos(rightX + 1, 7)
  term.setTextColor(colors.black)
  term.write("Choose Model / Variation:")

  local vy = 8
  for vIdx, v in ipairs(prod.variations) do
    if vy <= h - 6 then
      local active = (vIdx == selectedVarIdx)
      local bg = active and colors.black or colors.lightGray
      local fg = active and colors.white or colors.black
      local label = string.format("%s - %d %s", v.label, v.price, CURRENCY_LABEL)
      local x1, y1, x2, y2 = drawPillButton(rightX + 1, vy, label:sub(1, w - rightX - 4), bg, fg)
      table.insert(hitBoxes, {
        x1 = x1, y1 = y1, x2 = x2, y2 = y2,
        action = "select_var", idx = vIdx
      })
      vy = vy + 2
    end
  end

  -- Live Stock & Quantity Controls
  local stock = liveTotals[var.id]
  local stockText = storageConnected
    and ("In Stock: " .. tostring(stock or 0))
    or "Stock: Live Sync Standby"

  local ctrlY = math.max(vy + 1, h - 4)
  term.setCursorPos(rightX + 1, ctrlY - 1)
  term.setBackgroundColor(colors.white)
  term.setTextColor(colors.gray)
  term.write(stockText)

  -- Quantity [-] [qty] [+]
  local mx1, my1, mx2, my2 = drawPillButton(rightX + 1, ctrlY, "-", colors.lightGray, colors.black)
  table.insert(hitBoxes, { x1 = mx1, y1 = my1, x2 = mx2, y2 = my2, action = "qty_minus" })

  term.setCursorPos(mx2 + 2, ctrlY)
  term.setBackgroundColor(colors.white)
  term.setTextColor(colors.black)
  term.write(tostring(orderQty))

  local px1, py1, px2, py2 = drawPillButton(mx2 + 5, ctrlY, "+", colors.lightGray, colors.black)
  table.insert(hitBoxes, { x1 = px1, y1 = py1, x2 = px2, y2 = py2, action = "qty_plus" })

  -- Buy CTA Button
  local totalCost = var.price * orderQty
  local buyLabel = "Buy (" .. totalCost .. " " .. CURRENCY_LABEL .. ")"
  local bx1, by1, bx2, by2 = drawPillButton(rightX + 1, h - 2, buyLabel, colors.blue, colors.white)
  table.insert(hitBoxes, { x1 = bx1, y1 = by1, x2 = bx2, y2 = by2, action = "go_checkout" })
end

-- ==========================================
-- VIEW 3: DEPOSITOR CHECKOUT SCREEN
-- ==========================================
local function drawCheckoutView()
  local w, h = term.getSize()
  fillRect(1, 2, w, h, colors.lightGray)
  hitBoxes = {}

  local prod = CATALOG[selectedItemIdx]
  local var = prod.variations[selectedVarIdx]
  local totalCost = var.price * orderQty
  local deposited = countDepositedCurrency()
  local enough = (deposited >= totalCost)

  local boxX1 = math.max(3, math.floor(w * 0.15))
  local boxX2 = math.min(w - 2, math.floor(w * 0.85))
  fillRect(boxX1, 3, boxX2, h - 2, colors.white)

  writeCentered(4, "Checkout & Payment", colors.black, colors.white)
  writeCentered(6, prod.name .. " - " .. var.label, colors.blue, colors.white)
  writeCentered(7, "Quantity: " .. orderQty .. "   |   Total Due: " .. totalCost .. " " .. CURRENCY_LABEL, colors.black, colors.white)

  -- Depositor Status Box
  local depY = 9
  fillRect(boxX1 + 2, depY, boxX2 - 2, depY + 2, colors.lightGray)
  if not depositor then
    writeCentered(depY + 1, "ERROR: No Payment Depositor Chest Attached!", colors.red, colors.lightGray)
  else
    writeCentered(depY, "Insert " .. CURRENCY_LABEL .. " into the Depositor Chest", colors.black, colors.lightGray)
    local statusStr = string.format("Deposited: %d / %d %s", deposited, totalCost, CURRENCY_LABEL)
    writeCentered(depY + 1, statusStr, enough and colors.green or colors.orange, colors.lightGray)
  end

  -- Action Buttons
  local btnY = h - 4
  local cx1, cy1, cx2, cy2 = drawPillButton(boxX1 + 3, btnY, "< Back", colors.gray, colors.white)
  table.insert(hitBoxes, { x1 = cx1, y1 = cy1, x2 = cx2, y2 = cy2, action = "back_store" })

  local payBg = (depositor and enough) and colors.green or colors.gray
  local payLabel = enough and "Confirm & Dispense" or "Waiting for Deposit..."
  local px1, py1, px2, py2 = drawPillButton(boxX2 - #payLabel - 4, btnY, payLabel, payBg, colors.white)
  if depositor and enough then
    table.insert(hitBoxes, { x1 = px1, y1 = py1, x2 = px2, y2 = py2, action = "confirm_order" })
  end
end

-- ==========================================
-- VIEW 4: ORDER DISPATCHED RECEIPT
-- ==========================================
local function drawReceiptView()
  local w, h = term.getSize()
  fillRect(1, 2, w, h, colors.white)
  hitBoxes = {}

  local centerX = math.floor(w / 2)
  drawPineappleLogo(centerX, 3)

  writeCentered(14, "Order Sent to Create Fulfillment!", colors.green, colors.white)
  if lastOrderSummary then
    writeCentered(15, lastOrderSummary, colors.black, colors.white)
  end
  writeCentered(16, "Collect your package at the delivery depot.", colors.gray, colors.white)

  local label = "Continue Shopping"
  local bx = math.max(2, math.floor((w - (#label + 2)) / 2) + 1)
  local x1, y1, x2, y2 = drawPillButton(bx, math.min(h - 1, 18), label, colors.blue, colors.white)
  table.insert(hitBoxes, { x1 = x1, y1 = y1, x2 = x2, y2 = y2, action = "back_store" })
end

-- ==========================================
-- ORDER EXECUTION (CONSUME + CREATE DISPATCH)
-- ==========================================
local function executeOrder()
  local prod = CATALOG[selectedItemIdx]
  local var = prod.variations[selectedVarIdx]
  local totalCost = var.price * orderQty

  if countDepositedCurrency() < totalCost then
    return false
  end

  -- Pull payment items out of the depositor into an internal vault/buffer or drop
  -- Note: Attach a locked "vault_chest" to the wired network to store collected profits!
  local vault = peripheral.find("minecraft:barrel")
  local remaining = totalCost
  for slot, stack in pairs(depositor.list()) do
    if stack.name == CURRENCY_ID and remaining > 0 then
      local take = math.min(stack.count, remaining)
      if vault and peripheral.getName(vault) ~= peripheral.getName(depositor) then
        depositor.pushItems(peripheral.getName(vault), slot, take)
      else
        -- Fallback: drop into rear redstone/hopper if no separate vault peripheral
        depositor.pushItems("bottom", slot, take)
      end
      remaining = remaining - take
    end
  end

  -- Broadcast order to Create fulfillment controller
  local orderPayload = {
    action  = "dispense_order",
    product = prod.name,
    variant = var.label,
    item    = var.id,
    channel = var.channel,
    qty     = orderQty,
    paid    = totalCost
  }
  rednet.broadcast(orderPayload, ORDER_PROTOCOL)

  lastOrderSummary = string.format("%dx %s (%s)", orderQty, prod.name, var.label)
  orderQty = 1
  return true
end

-- ==========================================
-- MASTER RENDER & EVENT LOOP
-- ==========================================
local function render()
  drawTopBar()
  if currentView == "home" then
    drawHomeView()
  elseif currentView == "store" then
    drawStoreView()
  elseif currentView == "checkout" then
    drawCheckoutView()
  elseif currentView == "receipt" then
    drawReceiptView()
  end
end

render()
local refreshTimer = os.startTimer(1)

while true do
  local event, p1, p2, p3 = os.pullEvent()

  if event == "timer" and p1 == refreshTimer then
    -- Refresh clock & live depositor count during checkout
    render()
    refreshTimer = os.startTimer(1)

  elseif event == "rednet_message" and p3 == STORAGE_PROTOCOL then
    processIncomingStorage(p2)
    render()

  elseif event == "monitor_touch" then
    local x, y = p2, p3

    -- Top Menu Bar Navigation
    if y == 1 then
      if x >= 2 and x <= 18 then
        currentView = "home"
        render()
      elseif x >= 20 and x <= 26 then
        currentView = "store"
        render()
      end

    elseif currentView == "home" then
      if #btnHomeShop == 4 and x >= btnHomeShop[1] and x <= btnHomeShop[3] and y == btnHomeShop[2] then
        currentView = "store"
        render()
      end

    else
      for _, hb in ipairs(hitBoxes) do
        if x >= hb.x1 and x <= hb.x2 and y >= hb.y1 and y <= hb.y2 then
          if hb.action == "select_product" then
            selectedItemIdx = hb.idx
            selectedVarIdx = 1
            orderQty = 1
          elseif hb.action == "select_var" then
            selectedVarIdx = hb.idx
          elseif hb.action == "qty_minus" then
            orderQty = math.max(1, orderQty - 1)
          elseif hb.action == "qty_plus" then
            orderQty = math.min(64, orderQty + 1)
          elseif hb.action == "go_checkout" then
            currentView = "checkout"
          elseif hb.action == "back_store" then
            currentView = "store"
          elseif hb.action == "confirm_order" then
            if executeOrder() then
              currentView = "receipt"
            end
          end
          render()
          break
        end
      end
    end
  end
end
