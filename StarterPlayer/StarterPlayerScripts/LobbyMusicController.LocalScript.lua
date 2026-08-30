-- LobbyMusicController
--
-- Owns the local, non-positional music heard in the Zyntra transit lobby.
-- The source track must be original, group-owned, and exported with a tail that
-- can overlap its opening. Two preloaded decks crossfade around the file seam so
-- Roblox transcoding cannot leave a short gap between repetitions.

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer
local roundStatus = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("RoundStatus")

-- Set this after the ElevenLabs track has been uploaded under ERN Roblox
-- Studios and permitted for this universe. A numeric TrackAssetId attribute on
-- this LocalScript overrides the constant, which keeps Studio auditioning easy.
local DEFAULT_TRACK_ASSET_ID = ""

local BASE_VOLUME = 0.22
local BRIEFING_DUCK_MULTIPLIER = 0.24
local FADE_IN_SECONDS = 3.5
local FADE_OUT_SECONDS = 1.4
local DUCK_IN_SECONDS = 0.30
local DUCK_OUT_SECONDS = 1.15
local LOOP_CROSSFADE_SECONDS = 0.80
local MIN_CROSSFADE_TRACK_SECONDS = 12
local PRELOAD_TIMEOUT_SECONDS = 10

local soundGroup = SoundService:FindFirstChild("ZyntraLobbyMusic")
if not (soundGroup and soundGroup:IsA("SoundGroup")) then
	soundGroup = Instance.new("SoundGroup")
	soundGroup.Name = "ZyntraLobbyMusic"
	soundGroup.Volume = 1
	soundGroup.Parent = SoundService
end

local decks = {}
for index = 1, 2 do
	local sound = Instance.new("Sound")
	sound.Name = "LobbyMusicDeck" .. string.char(64 + index)
	sound.Looped = false
	sound.Volume = 0
	sound.SoundGroup = soundGroup
	sound.Parent = SoundService
	decks[index] = sound
end

local trackEpoch = 0
local trackReady = false
local lobbyIntent = false
local activeDeckIndex = 1
local musicStarted = false
local crossfading = false
local crossfadeClock = 0
local masterVolume = 0
local warnedMissingTrack = false

local function normalizeAssetId(raw)
	if typeof(raw) == "number" then
		if raw > 0 then return "rbxassetid://" .. tostring(math.floor(raw)) end
		return nil
	end
	if typeof(raw) ~= "string" then return nil end
	local digits = string.match(raw, "%d+")
	if not digits or tonumber(digits) == 0 then return nil end
	return "rbxassetid://" .. digits
end

local function configuredTrackId()
	return normalizeAssetId(script:GetAttribute("TrackAssetId"))
		or normalizeAssetId(DEFAULT_TRACK_ASSET_ID)
end

local function stopDecks(resetPosition)
	for _, sound in ipairs(decks) do
		sound:Stop()
		sound.Volume = 0
		if resetPosition then sound.TimePosition = 0 end
	end
	activeDeckIndex = 1
	musicStarted = false
	crossfading = false
	crossfadeClock = 0
end

local function hardLobbyEligible()
	return workspace:GetAttribute("ReservedRoundServer") ~= true
		and player:GetAttribute("InRound") ~= true
		and workspace:FindFirstChild("ServerLobby") ~= nil
end

local function shouldPlay()
	return lobbyIntent and hardLobbyEligible()
end

local function dispatchActive()
	return player:GetAttribute("LobbyBriefingActive") == true
		or player:GetAttribute("ZyntraDispatchClientActive") == true
end

local function moveTowards(current, target, maximumDelta)
	if current < target then return math.min(current + maximumDelta, target) end
	return math.max(current - maximumDelta, target)
end

local function beginDeck(index)
	local sound = decks[index]
	sound.TimePosition = 0
	sound:Play()
end

local function beginMusicIfReady()
	if musicStarted or not trackReady or not shouldPlay() then return end
	activeDeckIndex = 1
	crossfading = false
	crossfadeClock = 0
	beginDeck(activeDeckIndex)
	musicStarted = true
end

local function configureTrack()
	trackEpoch += 1
	local epoch = trackEpoch
	trackReady = false
	stopDecks(true)

	local trackId = configuredTrackId()
	if not trackId then
		if not warnedMissingTrack then
			warnedMissingTrack = true
			warn("[LobbyMusicController] TrackAssetId is not configured; lobby music remains silent")
		end
		return
	end
	warnedMissingTrack = false

	for _, sound in ipairs(decks) do sound.SoundId = trackId end

	task.spawn(function()
		local preloadFinished = false
		local preloadSucceeded = false
		task.spawn(function()
			preloadSucceeded = pcall(function()
				ContentProvider:PreloadAsync(decks)
			end)
			preloadFinished = true
		end)

		local deadline = os.clock() + PRELOAD_TIMEOUT_SECONDS
		repeat task.wait(0.10) until preloadFinished or os.clock() >= deadline
		if epoch ~= trackEpoch then return end

		trackReady = preloadSucceeded
			or decks[1].IsLoaded
			or decks[1].TimeLength > 0
		if not trackReady then
			warn("[LobbyMusicController] Lobby track did not preload before the timeout")
			return
		end
		beginMusicIfReady()
	end)
end

local function setLobbyIntentFromEvent(eventName)
	if eventName == "lobby" or eventName == "lobbybriefing"
		or eventName == "queuehost" or eventName == "queueconfigured"
		or eventName == "queueconfigclosed" or eventName == "queuewaitinghost"
		or eventName == "queueprivate" or eventName == "queuefull"
		or eventName == "lobbycountdown" or eventName == "lobbycancel" then
		lobbyIntent = true
	elseif eventName == "loadinggame" or eventName == "elevator"
		or eventName == "poolaccess" or eventName == "level3access"
		or eventName == "start" or eventName == "win" or eventName == "lose" then
		lobbyIntent = false
	end
	beginMusicIfReady()
end

roundStatus.OnClientEvent:Connect(setLobbyIntentFromEvent)

player:GetAttributeChangedSignal("InRound"):Connect(beginMusicIfReady)
player:GetAttributeChangedSignal("LobbyBriefingActive"):Connect(beginMusicIfReady)
player:GetAttributeChangedSignal("ZyntraDispatchClientActive"):Connect(beginMusicIfReady)
workspace:GetAttributeChangedSignal("ReservedRoundServer"):Connect(beginMusicIfReady)
workspace.ChildAdded:Connect(function(child)
	if child.Name == "ServerLobby" then
		lobbyIntent = true
		beginMusicIfReady()
	end
end)
workspace.ChildRemoved:Connect(function(child)
	if child.Name == "ServerLobby" then lobbyIntent = false end
end)
script:GetAttributeChangedSignal("TrackAssetId"):Connect(configureTrack)

-- Bootstrap clients that join after the server has already created the lobby.
lobbyIntent = hardLobbyEligible()
configureTrack()

RunService.Heartbeat:Connect(function(deltaTime)
	local audible = shouldPlay()
	if audible then beginMusicIfReady() end

	local targetVolume = 0
	local transitionSeconds = FADE_OUT_SECONDS
	if audible and trackReady then
		targetVolume = BASE_VOLUME
		transitionSeconds = FADE_IN_SECONDS
		if dispatchActive() then
			targetVolume *= BRIEFING_DUCK_MULTIPLIER
			transitionSeconds = DUCK_IN_SECONDS
		elseif masterVolume > 0 and masterVolume < BASE_VOLUME then
			transitionSeconds = DUCK_OUT_SECONDS
		end
	end
	masterVolume = moveTowards(
		masterVolume,
		targetVolume,
		deltaTime * BASE_VOLUME / math.max(transitionSeconds, 0.01)
	)

	local gainA, gainB = 0, 0
	if musicStarted then
		local active = decks[activeDeckIndex]
		local nextIndex = activeDeckIndex == 1 and 2 or 1
		local following = decks[nextIndex]
		local length = active.TimeLength

		if not crossfading and length >= MIN_CROSSFADE_TRACK_SECONDS
			and active.IsPlaying
			and active.TimePosition >= length - LOOP_CROSSFADE_SECONDS then
			following:Stop()
			beginDeck(nextIndex)
			crossfading = true
			crossfadeClock = 0
		elseif not crossfading and not active.IsPlaying and audible then
			-- Fallback for slow metadata or an Ended event between Heartbeats.
			beginDeck(nextIndex)
			activeDeckIndex = nextIndex
			active = decks[activeDeckIndex]
		end

		if crossfading then
			crossfadeClock += deltaTime
			local alpha = math.clamp(crossfadeClock / LOOP_CROSSFADE_SECONDS, 0, 1)
			local outgoingGain = math.sqrt(1 - alpha)
			local incomingGain = math.sqrt(alpha)
			if activeDeckIndex == 1 then
				gainA, gainB = outgoingGain, incomingGain
			else
				gainA, gainB = incomingGain, outgoingGain
			end
			if alpha >= 1 then
				decks[activeDeckIndex]:Stop()
				decks[activeDeckIndex].TimePosition = 0
				activeDeckIndex = nextIndex
				crossfading = false
				crossfadeClock = 0
			end
		else
			if activeDeckIndex == 1 then gainA = 1 else gainB = 1 end
		end
	end

	decks[1].Volume = masterVolume * gainA
	decks[2].Volume = masterVolume * gainB

	if musicStarted and not audible and masterVolume <= 0.0005 then
		stopDecks(false)
	end
end)
