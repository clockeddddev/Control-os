-- ==========================================
-- PINEAPPLE STORE: CREATE STOCK TICKER RECEIVER
-- ==========================================
peripheral.find("modem", rednet.open)
local ORDER_PROTOCOL = "pineapple_order"

-- Auto-detect the attached Create Stock Ticker peripheral
local ticker = peripheral.find("create:stock_ticker")
  or peripheral.find("stock_ticker")
assert(ticker, "No Create Stock Ticker attached!")

-- ==========================================
-- CONFIG: LOGISTICS ADDRESS & TAG ITEM IDS
-- ==========================================
-- The Frogport / Packager address where customers pick up their order
local DELIVERY_ADDRESS = "PineapplePickup"

-- Base phone item ID stored in your Create Stock network
local BASE_PHONE_ID = "computercraft:pocket_computer_advanced"

-- Map each capability tag to an item ID in your Create storage network
-- (e.g. upgrade modules, modems, floppy disks, or tag tokens)
-- Leave an entry nil if a tag is software-only and needs no physical item
local TAG_ITEMS = {
  ["data-plan"] = "computercraft:disk",
  ["wireless"]  = "computercraft:wireless_modem_normal",
  ["ender"]     = "computercraft:wireless_modem_advanced",
  ["program"]   = "computercraft:disk",
  ["developer"] = "minecraft:redstone"
}

-- ==========================================
-- HELPER: REQUEST ITEMS VIA STOCK TICKER
-- ==========================================
local function dispatchViaStockTicker(orderList)
  -- Build filter table for Create's Stock Ticker API
  local filters = {}
  for _, entry in ipairs(orderList) do
    table.insert(filters, {
      name  = entry.id,
      count = entry.count
    })
  end

  -- Create 6.0+ CC:Tweaked Stock Ticker API: requestFiltered(address, items)
  if ticker.requestFiltered then
    local ok, err = pcall(ticker.requestFiltered, DELIVERY_ADDRESS, filters)
    return ok, err
  end

  -- Fallback for older/alternate peripheral bridges: request(address, item, count)
  if ticker.request then
    for _, entry in ipairs(orderList) do
      local ok, err = pcall(ticker.request, DELIVERY_ADDRESS, entry.id, entry.count)
      if not ok then return false, err end
    end
    return true
  end

  return false, "Unsupported Stock Ticker peripheral methods"
end

-- ==========================================
-- ORDER PROCESSING LOOP
-- ==========================================
term.clear()
term.setCursorPos(1, 1)
print("=== Pineapple Stock Ticker Fulfillment ===")
print("Delivery Address: " .. DELIVERY_ADDRESS)
print("Listening on: " .. ORDER_PROTOCOL .. "\n")

while true do
  local senderId, msg, protocol = rednet.receive(ORDER_PROTOCOL)

  if type(msg) == "table" and msg.action == "dispense_order" then
    local qty  = tonumber(msg.qty) or 1
    local tags = msg.tags or {}

    print(string.format("[Order #%d] %dx %s", senderId, qty, msg.product or "Pineapple Phone"))

    -- Aggregate items so duplicate item IDs combine cleanly into one package request
    local countsById = {}
    local function addItem(id, n)
      if id and n > 0 then
        countsById[id] = (countsById[id] or 0) + n
      end
    end

    -- 1. Add base Pineapple Phone(s)
    addItem(msg.item or BASE_PHONE_ID, qty)

    -- 2. Add physical items/modules for each selected tag
    for _, tagId in ipairs(tags) do
      local tagItemId = TAG_ITEMS[tagId]
      if tagItemId then
        addItem(tagItemId, qty)
        print("  + Tag [" .. tagId .. "] -> " .. tagItemId .. " x" .. qty)
      else
        print("  + Tag [" .. tagId .. "] (software tag)")
      end
    end

    local orderList = {}
    for id, count in pairs(countsById) do
      table.insert(orderList, { id = id, count = count })
    end

    local ok, err = dispatchViaStockTicker(orderList)
    if ok then
      print("  [OK] Package routed to '" .. DELIVERY_ADDRESS .. "'!\n")
    else
      print("  [ERR] Stock Ticker failed: " .. tostring(err) .. "\n")
    end
  end
end
