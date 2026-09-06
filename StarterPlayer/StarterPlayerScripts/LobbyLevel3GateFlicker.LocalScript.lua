-- Local, occasional fluorescent faults in the Level 3 lobby queue room.
-- Each burst affects one working fixture; the fourth, dead fitting stays dead.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
local random = Random.new()

local TICK = 0.05
local DARK_COLOR = Color3.fromRGB(92, 88, 72)
local room = nil
local allowed = false
local active = nil
local nextBurstAt = 0
local accumulated = 0
local connections = {}

local function findRoom()
	local lobby = workspace:FindFirstChild("ServerLobby")
	local rooms = lobby and lobby:FindFirstChild("LevelQueueRooms")
	local candidate = rooms and rooms:FindFirstChild("Level3QueueRoom")
	return candidate and candidate:IsA("Model") and candidate or nil
end

local function restore()
	if not active then return end
	local saved = active
	active = nil
	-- Restore detached instances too: a streamed/reparented light must not keep
	-- its temporary dim value if the same instance returns later.
	pcall(function()
		saved.light.Brightness = saved.brightness
	end)
	pcall(function()
		saved.part.Color = saved.color
		saved.part.Material = saved.material
		saved.part.Transparency = saved.transparency
	end)
end

local function refreshContext(now)
	local currentRoom = findRoom()
	local canRun = currentRoom ~= nil
		and player:GetAttribute("InRound") ~= true
		and player:GetAttribute("ReduceFlashing") ~= true
		and workspace:GetAttribute("ReservedRoundServer") ~= true
	if currentRoom ~= room or canRun ~= allowed then
		restore()
		room = currentRoom
		allowed = canRun
		nextBurstAt = now + random:NextNumber(5, 14)
	end
end

local function beginDip(now)
	active.phase = "dip"
	active.phaseAt = now
	active.duration = random:NextNumber(0.12, 0.22)
	active.dimBrightness = active.brightness * random:NextNumber(0.04, 0.14)
	active.dimColor = active.color:Lerp(DARK_COLOR, 0.92)
	active.dimTransparency = math.max(active.transparency, 0.18)
	active.light.Brightness = active.dimBrightness
	active.part.Material = Enum.Material.SmoothPlastic
	active.part.Color = active.dimColor
	active.part.Transparency = active.dimTransparency
end

local function beginBurst(now)
	local candidates = {}
	for index = 1, 3 do
		local part = room:FindFirstChild("Lobby L3 Fluorescent Diffuser " .. index)
		local light = part and part:FindFirstChild("Lobby L3 Party Fluorescent")
		if part and part:IsA("BasePart") and light and light:IsA("SurfaceLight")
			and light.Enabled and light.Brightness > 0 then
			table.insert(candidates, {part = part, light = light})
		end
	end
	if #candidates == 0 then
		nextBurstAt = now + random:NextNumber(5, 14)
		return
	end
	local chosen = candidates[random:NextInteger(1, #candidates)]
	active = {
		part = chosen.part,
		light = chosen.light,
		brightness = chosen.light.Brightness,
		color = chosen.part.Color,
		material = chosen.part.Material,
		transparency = chosen.part.Transparency,
		remaining = random:NextInteger(1, 3),
	}
	beginDip(now)
end

local function update(now)
	refreshContext(now)
	if not allowed then return end
	if not active then
		if now >= nextBurstAt then beginBurst(now) end
		return
	end
	if not active.part:IsDescendantOf(room) or active.light.Parent ~= active.part then
		restore()
		nextBurstAt = now + random:NextNumber(5, 14)
		return
	end
	local progress = math.clamp((now - active.phaseAt) / active.duration, 0, 1)
	if active.phase == "dip" then
		if progress >= 1 then
			active.phase = "recovery"
			active.phaseAt = now
			active.duration = random:NextNumber(0.35, 0.55)
		end
		return
	end
	-- Recover gradually, including the diffuser's emissive appearance.
	active.light.Brightness = active.dimBrightness + (active.brightness - active.dimBrightness) * progress
	active.part.Color = active.dimColor:Lerp(active.color, progress)
	active.part.Transparency = active.dimTransparency + (active.transparency - active.dimTransparency) * progress
	if progress >= 0.5 then active.part.Material = active.material end
	if progress >= 1 then
		active.remaining -= 1
		if active.remaining > 0 then
			beginDip(now)
		else
			restore()
			nextBurstAt = now + random:NextNumber(5, 14)
		end
	end
end

table.insert(connections, RunService.Heartbeat:Connect(function(dt)
	accumulated += dt
	if accumulated < TICK then return end
	accumulated = 0
	update(os.clock())
end))

-- Accessibility and round transitions cancel a dip immediately, without
-- waiting for the next scheduled flicker or the next heartbeat.
local function contextChanged()
	refreshContext(os.clock())
end
table.insert(connections, player:GetAttributeChangedSignal("ReduceFlashing"):Connect(contextChanged))
table.insert(connections, player:GetAttributeChangedSignal("InRound"):Connect(contextChanged))
table.insert(connections, workspace:GetAttributeChangedSignal("ReservedRoundServer"):Connect(contextChanged))

script.Destroying:Connect(function()
	restore()
	for _, connection in ipairs(connections) do connection:Disconnect() end
	table.clear(connections)
end)

refreshContext(os.clock())
