-- ==========================================
-- CREATE STORAGE SLAVE NODE (Wireless)
-- ==========================================
peripheral.find("modem", rednet.open)
assert(rednet.isOpen(), "No wireless modem attached!")

local ticker = peripheral.find("Create_StockTicker")
local vaults = { peripheral.find("inventory") }

local PROTOCOL = "base_storage_sync"

local function scanStorage()
  local totals = {}
  local names = {}

  if ticker then
    local items = ticker.stock(true)
    for _, item in pairs(items) do
      totals[item.name] = (totals[item.name] or 0) + item.count
      names[item.name] = item.displayName or item.name
    end
  else
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

  return { totals = totals, names = names }
end

print("Storage Slave Online (Wireless)")
print(ticker and "Mode: Create Stock Ticker" or ("Mode: " .. #vaults .. " Vault(s)"))

while true do
  local payload = scanStorage()
  rednet.broadcast(payload, PROTOCOL)
  print("Broadcasted stock @ " .. textutils.formatTime(os.time(), true))
  sleep(3)
end
