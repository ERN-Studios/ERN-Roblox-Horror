-- Five occasional on/off patterns across the lobby's two ceiling-light rows.
-- The server's Party button owns its effect; accessibility remains per player.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
local random = Random.new()

local TICK = 0.05
local DURATION = 6
local lobby = nil
local lighting = nil
local allowed = false
local active = nil
local lastPattern = nil
local nextSweepAt = 0
local accumulated = 0
local partyConnection = nil
local connections = {}

local function restoreItem(item)
 -- Only undo values this controller still owns. A replicated Party colour
 -- arriving before its flag must not be overwritten by a saved baseline.
 pcall(function()
  if item.part.Color == item.lastPartColor then item.part.Color = item.partColor end
  if item.part.Material == item.lastMaterial then item.part.Material = item.material end
  if item.light.Enabled == item.lastEnabled then item.light.Enabled = item.enabled end
 end)
end

local function restore()
 if not active then return end
 local previous = active
 active = nil
 for _, item in ipairs(previous.targets) do restoreItem(item) end
end

local function pauseUntilLater(now)
 nextSweepAt = now + random:NextNumber(9, 16)
end

local function refreshContext(now)
 local currentLobby = workspace:FindFirstChild("ServerLobby")
 local currentLighting = currentLobby and currentLobby:FindFirstChild("TunnelLighting")
 if currentLobby ~= lobby or currentLighting ~= lighting then
  restore()
  if partyConnection then partyConnection:Disconnect(); partyConnection = nil end
  lobby, lighting = currentLobby, currentLighting
  if lobby then
   partyConnection = lobby:GetAttributeChangedSignal("PartyModeActive"):Connect(function()
    refreshContext(os.clock())
   end)
  end
  pauseUntilLater(now)
 end
 local canRun = lighting ~= nil
  and player:GetAttribute("InRound") ~= true
  -- Wait for the loaded preference too: saved ReduceFlashing must never flash
  -- once before its profile attribute arrives.
  and player:GetAttribute("ReduceFlashing") == false
  and workspace:GetAttribute("ReservedRoundServer") ~= true
  and lobby:GetAttribute("PartyModeActive") ~= true
 if canRun ~= allowed then
  restore()
  allowed = canRun
  pauseUntilLater(now)
 end
end

local function collectLights()
 local targets = {}
 local minZ, maxZ = math.huge, -math.huge
 local minX, maxX = math.huge, -math.huge
 for _, part in ipairs(lighting:GetDescendants()) do
  if part:IsA("BasePart") and part:GetAttribute("PartyCeilingLight") == true then
   local light = part:FindFirstChildWhichIsA("PointLight")
   if light and light.Enabled and light.Brightness > 0 then
    table.insert(targets, {
     part = part, light = light, partColor = part.Color,
     lightColor = light.Color, brightness = light.Brightness,
     material = part.Material, enabled = light.Enabled,
    })
    minZ, maxZ = math.min(minZ, part.Position.Z), math.max(maxZ, part.Position.Z)
    minX, maxX = math.min(minX, part.Position.X), math.max(maxX, part.Position.X)
   end
  end
 end
 for _, item in ipairs(targets) do
  item.z = (item.part.Position.Z - minZ) / math.max(1, maxZ - minZ)
  item.left = item.part.Position.X <= (minX + maxX) / 2
 end
 return targets
end

local function patternCoordinate(pattern, item)
 if pattern == 1 then return item.z end                    -- near to far
 if pattern == 2 then return 1 - item.z end                -- far to near
 if pattern == 3 then return math.abs(item.z * 2 - 1) end  -- centre outward
 if pattern == 4 then return 1 - math.abs(item.z * 2 - 1) end -- ends inward
 return item.left and item.z or 1 - item.z                 -- opposing lanes
end

local function lightIsOn(coordinate, progress)
 -- One broad dark band travels across the fixtures. Each switches off once
 -- for about 1.8 seconds, then on; the band starts and finishes outside them.
 local front = -0.24 + progress * 1.48
 return math.abs(coordinate - front) >= 0.22
end

local function beginSweep(now)
 local targets = collectLights()
 if #targets == 0 then pauseUntilLater(now); return end
 local pattern = random:NextInteger(1, lastPattern and 4 or 5)
 if lastPattern and pattern >= lastPattern then pattern += 1 end
 lastPattern = pattern
 active = { targets = targets, pattern = pattern, startedAt = now }
end

local function update(now)
 refreshContext(now)
 if not allowed then return end
 if not active then
  if now >= nextSweepAt then beginSweep(now) end
  return
 end
 -- Check every attached fixture before writing any of them: Party properties
 -- can replicate before PartyModeActive. Before our first write, the captured
 -- baseline is the expected value; afterwards use the native readback.
 for _, item in ipairs(active.targets) do
  if item.part:IsDescendantOf(lighting) and item.light.Parent == item.part
   and (item.part.Color ~= (item.lastPartColor or item.partColor)
    or item.part.Material ~= (item.lastMaterial or item.material)
    or item.light.Color ~= item.lightColor
    or item.light.Brightness ~= item.brightness
    or item.light.Enabled ~= (if item.lastEnabled == nil then item.enabled else item.lastEnabled)) then
   restore()
   pauseUntilLater(now)
   return
  end
 end
 local progress = math.clamp((now - active.startedAt) / DURATION, 0, 1)
 if progress >= 1 then restore(); pauseUntilLater(now); return end
 for index = #active.targets, 1, -1 do
  local item = active.targets[index]
  if not item.part:IsDescendantOf(lighting) or item.light.Parent ~= item.part then
   restoreItem(item)
   table.remove(active.targets, index)
  else
   local on = lightIsOn(patternCoordinate(active.pattern, item), progress)
   item.light.Enabled = on
   -- Remove the fixture's neon emission as well as its real illumination.
   item.part.Material = if on then item.material else Enum.Material.SmoothPlastic
   item.part.Color = if on then item.partColor else item.partColor * 0.14
   -- Read back native property precision for reliable ownership on restoration.
   item.lastPartColor = item.part.Color
   item.lastMaterial = item.part.Material
   item.lastEnabled = item.light.Enabled
  end
 end
end

table.insert(connections, RunService.Heartbeat:Connect(function(dt)
 accumulated += dt
 if accumulated < TICK then return end
 accumulated = 0
 update(os.clock())
end))

local function contextChanged()
 refreshContext(os.clock())
end
table.insert(connections, player:GetAttributeChangedSignal("InRound"):Connect(contextChanged))
table.insert(connections, player:GetAttributeChangedSignal("ReduceFlashing"):Connect(contextChanged))
table.insert(connections, workspace:GetAttributeChangedSignal("ReservedRoundServer"):Connect(contextChanged))

script.Destroying:Connect(function()
 restore()
 if partyConnection then partyConnection:Disconnect() end
 for _, connection in ipairs(connections) do connection:Disconnect() end
 table.clear(connections)
end)
refreshContext(os.clock())
