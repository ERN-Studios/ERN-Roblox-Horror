-- Level 1 Sound Controller
-- Per-level ambience slots for the Yellow Maze, kept separate so each level
-- has one obvious audio file.
--
-- ══════════════════════ HOW TO TWEAK (read me!) ══════════════════════════
-- 1. Sound IDs live in ReplicatedStorage["Level 1 Sound Library"] as
--    StringValues. Paste an asset id into a slot's Value. Empty = silent.
-- 2. Volumes: the numbers in AMBIENCE below.
-- 3. NOTE: the big shared "SoundController" script still owns footsteps,
--    sprint/stamina, the office fluorescent drone and the entity audio for
--    Level 1 — this file only ADDS extra ambience beds on top, so filling a
--    slot here never fights the existing mix.
-- ═════════════════════════════════════════════════════════════════════════

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local AMBIENCE = {
	{"Level 1 Room Tone", 0.3},
	{"Level 1 Deep Hum", 0.2},
	{"Level 1 Distant Machinery", 0.22},
}
local FADE_SECONDS = 1.5

local library = ReplicatedStorage:WaitForChild("Level 1 Sound Library", 30)

local function resolveId(slotName)
	local slot = library and library:FindFirstChild(slotName)
	local raw = slot and slot:IsA("StringValue") and slot.Value or ""
	raw = tostring(raw):gsub("%s", "")
	if raw == "" then return nil end
	if raw:match("^%d+$") then return "rbxassetid://" .. raw end
	return raw
end

local function active()
	local level = workspace:GetAttribute("SelectedLevel")
	return (level == 1 or level == nil)
		and player:GetAttribute("InRound") == true
end

local loops = {}
local function ensureLoop(slotName)
	local id = resolveId(slotName)
	if not id then return nil end
	local loop = loops[slotName]
	if not loop then
		loop = Instance.new("Sound")
		loop.Name = "Level 1 Ambience - " .. slotName
		loop.Looped = true
		loop.Volume = 0
		loop.Parent = SoundService
		loops[slotName] = loop
	end
	if loop.SoundId ~= id then loop.SoundId = id end
	if not loop.IsPlaying then loop:Play() end
	return loop
end

RunService.Heartbeat:Connect(function(dt)
	local blend = math.clamp(dt / FADE_SECONDS, 0, 1)
	for _, entry in ipairs(AMBIENCE) do
		local slotName, volume = entry[1], entry[2]
		if active() then
			local loop = ensureLoop(slotName)
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
