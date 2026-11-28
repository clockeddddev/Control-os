-- ==========================================
-- RADIO / GPS TOWER SLAVE (startup.lua)
-- ==========================================
-- Set THIS slave computer's exact coordinates, or nil to try gps.locate()
local POS = { x = 0, y = 120, z = 0 }

-- Protocols to relay across tower nodes
local RELAY_PROTOS = {
  ["pocket_phone_call"] = true,
  ["base_storage_sync"] = true
}

local modem = peripheral.find("modem")
if not modem then
  print("ERROR: Attach a wireless or ender modem.")
  return
end

local side = peripheral.getName(modem)
if not rednet.isOpen(side) then
  rednet.open(side)
end

local myID = os.getComputerID()
local seen = {} -- deduplicate relayed messages: seen[key] = expireTime

local function makeMsgKey(senderID, msg, proto)
  if type(msg) == "table" then
    return tostring(senderID) .. "|" .. tostring(proto) .. "|" .. textutils.serialize(msg)
  end
  return tostring(senderID) .. "|" .. tostring(proto) .. "|" .. tostring(msg)
end

local function cleanSeen(now)
  for k, exp in pairs(seen) do
    if now >= exp then
      seen[k] = nil
    end
  end
end

local function getCoords()
  if type(POS) == "table" and POS.x and POS.y and POS.z then
    return math.floor(POS.x), math.floor(POS.y), math.floor(POS.z)
  end
  print("No fixed POS set; trying gps.locate(3)...")
  local x, y, z = gps.locate(3)
  if x then
    return math.floor(x), math.floor(y), math.floor(z)
  end
  return nil
end

-- ==========================================
-- 1. START GPS HOST IN PARALLEL
-- ==========================================
local function gpsHostTask()
  local x, y, z = getCoords()
  if not x then
    print("GPS host skipped: set POS = { x=..., y=..., z=... }")
    return
  end
  print(("GPS Host active at %d, %d, %d"):format(x, y, z))
  shell.run("gps", "host", tostring(x), tostring(y), tostring(z))
end

-- ==========================================
-- 2. RADIO RELAY / REPEATER LOOP
-- ==========================================
local function radioRelayTask()
  print(("Radio Slave #%d relaying on %s..."):format(myID, side))
  local relayedCount = 0

  while true do
    local senderID, msg, proto = rednet.receive()
    local now = os.clock()
    cleanSeen(now)

    -- Ignore built-in GPS protocol traffic so we don't interfere with gps.lua
    if proto ~= "gps" then
      local shouldRelay = false
      if proto and RELAY_PROTOS[proto] then
        shouldRelay = true
      elseif not proto and type(msg) == "string" then
        -- Relay simple control strings (e.g., "lights_on", "door_off")
        if msg:match("_[onf]+$") then
          shouldRelay = true
        end
      end

      if shouldRelay then
        local key = makeMsgKey(senderID, msg, proto)
        if not seen[key] then
          seen[key] = now + 4 -- 4s window prevents echo loops
          relayedCount = relayedCount + 1
          if proto then
            rednet.broadcast(msg, proto)
          else
            rednet.broadcast(msg)
          end
        end
      end
    end
  end
end

parallel.waitForAny(gpsHostTask, radioRelayTask)
