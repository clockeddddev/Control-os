-- ==========================================
-- PINEAPPLE STORE: VAULT ORDER RECEIVER
-- ==========================================
peripheral.find("modem", rednet.open)
assert(rednet.isOpen(), "No wireless/wired modem attached!")

local ORDER_PROTOCOL = "pineapple_order"

-- Optional: set exact peripheral name of your delivery chest/barrel/hopper,
-- or leave nil to automatically use the first inventory that isn't a vault
local DELIVERY_INVENTORY_NAME = nil

-- Map capability tags to item IDs stored in your vaults (nil = software-only tag)
local TAG_ITEMS = {
  ["data-plan"] = "computercraft:disk",
  ["wireless"]  = "computercraft:wireless_modem_normal",
  ["ender"]     = "computercraft:wireless_modem_advanced",
  ["program"]   = "computercraft:disk",
  ["developer"] = "minecraft:redstone"
}

local function getAllInventories()
  return { peripheral.find("inventory") }
end

local function isVaultName(name)
  return name:find("vault") ~= nil
end

local function findDeliveryTarget(allInvs)
  if DELIVERY_INVENTORY_NAME then
    return DELIVERY_INVENTORY_NAME
  end
  for _, inv in ipairs(allInvs) do
    local name = peripheral.getName(inv)
    if not isVaultName(name) then
      return name
    end
  end
  return nil
end

local function pullFromVaults(itemId, neededCount, allInvs, destName)
  local remaining = neededCount
  if not destName or not itemId or remaining <= 0 then
    return 0, remaining
  end

  for _, inv in ipairs(allInvs) do
    local invName = peripheral.getName(inv)
    if isVaultName(invName) and invName ~= destName then
      local ok, list = pcall(inv.list)
      if ok and type(list) == "table" then
        for slot, stack in pairs(list) do
          if remaining <= 0 then break end
          if stack.name == itemId then
            local toMove = math.min(stack.count, remaining)
            local moved = inv.pushItems(destName, slot, toMove) or 0
            remaining = remaining - moved
          end
        end
      end
    end
    if remaining <= 0 then break end
  end

  local dispensed = neededCount - remaining
  return dispensed, remaining
end

term.clear()
term.setCursorPos(1, 1)
print("=== Pineapple Vault Order Receiver ===")
print("Listening on: " .. ORDER_PROTOCOL .. "\n")

while true do
  local senderId, msg, protocol = rednet.receive(ORDER_PROTOCOL)

  if type(msg) == "table" and msg.action == "dispense_order" then
    local qty  = tonumber(msg.qty) or 1
    local tags = msg.tags or {}
    local allInvs = getAllInventories()
    local destName = findDeliveryTarget(allInvs)

    print(string.format("[Order #%d] %dx %s", senderId, qty, msg.product or "Pineapple Phone"))
    if not destName then
      print("  [ERR] No delivery chest/barrel found on network! Set DELIVERY_INVENTORY_NAME.\n")
    else
      -- 1. Dispense base phone(s) from vaults
      local phoneId = msg.item or "computercraft:pocket_computer_advanced"
      local gotPhone, missPhone = pullFromVaults(phoneId, qty, allInvs, destName)
      print(string.format("  Phone (%s): %d/%d -> %s", phoneId, gotPhone, qty, destName))
      if missPhone > 0 then
        print("    [WARN] Short by " .. missPhone .. " in vaults")
      end

      -- 2. Dispense tag items from vaults
      for _, tagId in ipairs(tags) do
        local tagItemId = TAG_ITEMS[tagId]
        if tagItemId then
          local gotTag, missTag = pullFromVaults(tagItemId, qty, allInvs, destName)
          print(string.format("  Tag [%s] (%s): %d/%d", tagId, tagItemId, gotTag, qty))
          if missTag > 0 then
            print("    [WARN] Short by " .. missTag .. " in vaults")
          end
        else
          print("  Tag [" .. tagId .. "] (software tag)")
        end
      end
      print("  [DONE]\n")
    end
  end
end
