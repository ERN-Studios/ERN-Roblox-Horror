-- Level 2 Sound Controller
-- All audio for the Sunken Leisure Complex lives here, in one small file.
--
-- ══════════════════════ HOW TO TWEAK (read me!) ══════════════════════════
-- 1. Sound IDs live in ReplicatedStorage["Level 2 Sound Library"] as
--    StringValues. Paste a Roblox asset id into a slot's Value (just the
--    number, or the full rbxassetid:// url — both work). Empty = silent.
-- 2. Volumes: change the numbers in AMBIENCE and CUE_VOLUME below.
-- 3. The server fires one-shot cues through the "Level 2 Sound Event"
--    RemoteEvent; the cue name is the library slot name. Cues in use today:
--       "Level 2 Pump Start"     — a pump comes online
--       "Level 2 Drain Rush"     — a corridor drains
--       "Level 2 Pressure Door"  — the grand hall unseals
--       "Level 2 Slide Rush"     — riding the exit flume
-- 4. Ambience loops below play while you are in a Level 2 round.
-- ═════════════════════════════════════════════════════════════════════════

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

-- Looping beds: {library slot name, target volume}
local AMBIENCE = {
	{"Level 2 Room Tone", 0.35},
	{"Level 2 Ventilation Hum", 0.18},
	{"Level 2 Distant Water", 0.3},
}
local CUE_VOLUME = 0.6
local FADE_SECONDS = 1.5

local library = ReplicatedStorage:WaitForChild("Level 2 Sound Library", 30)
local event = ReplicatedStorage:WaitForChild("Level 2 Sound Event", 30)

local function resolveId(slotName)
	local slot = library and library:FindFirstChild(slotName)
	local raw = slot and slot:IsA("StringValue") and slot.Value or ""
	raw = tostring(raw):gsub("%s", "")
	if raw == "" then return nil end
	if raw:match("^%d+$") then return "rbxassetid://" .. raw end
	return raw
end

local function active()
	return workspace:GetAttribute("SelectedLevel") == 2
		and player:GetAttribute("InRound") == true
end

-- Ambience loops (created lazily so empty slots cost nothing).
local loops = {}
local function ensureLoop(slotName, volume)
	local id = resolveId(slotName)
	if not id then return nil end
	local loop = loops[slotName]
	if not loop then
		loop = Instance.new("Sound")
		loop.Name = "Level 2 Ambience - " .. slotName
		loop.Looped = true
		loop.Volume = 0
		loop.Parent = SoundService
		loops[slotName] = loop
	end
	if loop.SoundId ~= id then loop.SoundId = id end
	if not loop.IsPlaying then loop:Play() end
	return loop, volume
end

RunService.Heartbeat:Connect(function(dt)
	local blend = math.clamp(dt / FADE_SECONDS, 0, 1)
	for _, entry in ipairs(AMBIENCE) do
		local slotName, volume = entry[1], entry[2]
		if active() then
			local loop = ensureLoop(slotName, volume)
			if loop then
				loop.Volume += (volume - loop.Volume) * blend
			end
		else
			local loop = loops[slotName]
			if loop then
				loop.Volume += (0 - loop.Volume) * blend
				if loop.Volume < .01 and loop.IsPlaying then loop:Stop() end
			end
		end
	end
end)

-- One-shot cues from the server.
if event then
	event.OnClientEvent:Connect(function(cueName)
		if not active() then return end
		if typeof(cueName) ~= "string" then return end
		local id = resolveId(cueName)
		if not id then return end
		local cue = Instance.new("Sound")
		cue.Name = "Level 2 Cue - " .. cueName
		cue.SoundId = id
		cue.Volume = CUE_VOLUME
		cue.Parent = SoundService
		cue.Ended:Once(function() cue:Destroy() end)
		cue:Play()
		task.delay(20, function()
			if cue.Parent then cue:Destroy() end
		end)
	end)
end
