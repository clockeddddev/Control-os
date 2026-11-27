-- ==========================================
-- PINEAPPLE STORE: LOGISTICS NETWORK ORDER RECEIVER
-- ==========================================
peripheral.find("modem", rednet.open)
assert(rednet.isOpen(), "No wireless/wired modem attached!")

local ORDER_PROTOCOL = "pineapple_order"

-- Address on your destination Bee Port / Frogport
local BEE_PORT_ADDRESS = "PineapplePickup"

local TAG_ITEMS = {
  ["data-plan"] = "computercraft:disk",
  ["wireless"]  = "computercraft:wireless_modem_normal",
  ["ender"]     = "computercraft:wireless_modem_advanced",
  ["program"]   = "computercraft:disk",
  ["developer"] = "minecraft:redstone"
}

local function findStockTicker()
  return peripheral.find("Create_StockTicker")
    or peripheral.find("create:stock_ticker")
    or peripheral.find("stock_ticker")
end

local function sendNetworkOrder(address, countsById)
  local ticker = findStockTicker()
  local filters = {}

  for id, count in pairs(countsById) do
    table.insert(filters, {
      name  = id,
      count = count
    })
  end

  if #filters == 0 then
    return false, "No items in order"
  end

  -- 1. Stock Ticker: requestFiltered(address, filter1, filter2, ...)
  if ticker and ticker.requestFiltered then
    local ok, err = pcall(ticker.requestFiltered, address, table.unpack(filters))
    return ok, err
  end

  -- 2. Fallback: Redstone Requester if attached instead of Stock Ticker
  local requester = peripheral.find("create:redstone_requester")
    or peripheral.find("redstone_requester")
  if requester and requester.request then
    if requester.setAddress then
      pcall(requester.setAddress, address)
    end
    local ok, err = pcall(requester.request)
    return ok, err
  end

  return false, "No Stock Ticker or Redstone Requester peripheral found"
end

term.clear()
term.setCursorPos(1, 1)
print("=== Pineapple Network Order Receiver ===")
print("Bee Port Address: " .. BEE_PORT_ADDRESS)
print("Listening on: " .. ORDER_PROTOCOL .. "\n")

while true do
  local senderId, msg, protocol = rednet.receive(ORDER_PROTOCOL)

  if type(msg) == "table" and msg.action == "dispense_order" then
    local qty  = tonumber(msg.qty) or 1
    local tags = msg.tags or {}

    local countsById = {}
    local function addItem(id, n)
      if id and n > 0 then
        countsById[id] = (countsById[id] or 0) + n
      end
    end

    -- Base Pineapple Phone
    addItem(msg.item or "computercraft:pocket_computer_advanced", qty)

    -- Selected capability tag items
    for _, tagId in ipairs(tags) do
      addItem(TAG_ITEMS[tagId], qty)
    end

    print(string.format("[Order #%d] Ordering %dx %s -> '%s'",
      senderId, qty, msg.product or "Pineapple Phone", BEE_PORT_ADDRESS))

    local ok, err = sendNetworkOrder(BEE_PORT_ADDRESS, countsById)
    if ok then
      print("  [OK] Network package order placed!\n")
    else
      print("  [ERR] " .. tostring(err) .. "\n")
    end
  end
end
