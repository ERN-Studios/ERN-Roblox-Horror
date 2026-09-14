-- Level 2 entity sound design. Presentation only; server attributes own gameplay.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Bank = require(ReplicatedStorage:WaitForChild("Level 2 Entity Audio Bank"))
local player = Players.LocalPlayer
local rng = Random.new()
local records, failedAssets, connections = {}, {}, {}
local world, generation
local pollClock, scanClock, voiceCooldown = 0, 0, 0

local function listenerActive()
	if not Bank.Enabled or workspace:GetAttribute("SelectedLevel") ~= 2
		or workspace:GetAttribute("RoundActive") ~= true
		or player:GetAttribute("InRound") ~= true then return false end
	if player:GetAttribute("Spectating") == true then
		local id = player:GetAttribute("SpectateTargetUserId")
		local watched = type(id) == "number" and Players:GetPlayerByUserId(id) or nil
		local h = watched and watched.Character and watched.Character:FindFirstChildOfClass("Humanoid")
		return watched ~= nil and watched:GetAttribute("InRound") == true
			and watched:GetAttribute("Escaped") ~= true and h ~= nil and h.Health > 0
	end
	return player:GetAttribute("Escaped") ~= true or player:GetAttribute("Level2_ExitTransition") == true
end

local function destroyRecord(record)
	for _, channel in pairs(record.Channels) do channel.Sound:Destroy() end
	record.Emitter:Destroy()
end

local function clear()
	for model, record in pairs(records) do destroyRecord(record) records[model] = nil end
	script:SetAttribute("ActiveEmitters", 0)
	script:SetAttribute("ActiveSounds", 0)
end

local function add(model, kind)
	if records[model] or not model:IsA("Model") or not model.PrimaryPart
		or not world or not model:IsDescendantOf(world)
		or model:GetAttribute("Level2_Generation") ~= generation then return end
	local emitter = Instance.new("Attachment")
	emitter.Name = "Level 2 " .. kind .. " Clean Audio Emitter"
	emitter:SetAttribute("Level2_ClientOnlyAudio", true)
	emitter.Parent = model.PrimaryPart
	records[model] = {Model = model, Kind = kind, Emitter = emitter, Channels = {}, Last = {},
		Position = model.PrimaryPart.Position, MovingUntil = 0,
		Serial = model:GetAttribute(kind == "Foam" and "ActionSerial" or "Level2_PoolSlideAttackSerial") or 0,
		NextVoice = os.clock() + rng:NextNumber(3, 10)}
end

local function scan()
	for _, model in ipairs(CollectionService:GetTagged("Level2PoolFoamEntity")) do add(model, "Foam") end
	local runtime = world and world:FindFirstChild("Level 2 Pool Slide Runtime")
	local model = runtime and runtime:FindFirstChild("Level 2 Pool Slide")
	if model then add(model, "Slide") end
end

local function choose(record, key)
	local list = Bank[record.Kind][key]
	if not list then return nil end
	local candidates = {}
	for _, clip in ipairs(list) do
		if not failedAssets[clip.Id] and (#list == 1 or clip.Id ~= record.Last[key]) then
			table.insert(candidates, clip)
		end
	end
	if #candidates == 0 then
		for _, clip in ipairs(list) do if not failedAssets[clip.Id] then table.insert(candidates, clip) end end
	end
	if #candidates == 0 then return nil end
	local clip = candidates[rng:NextInteger(1, #candidates)]
	record.Last[key] = clip.Id
	return clip
end

local function start(record, channelName, key, looped, now)
	local clip = choose(record, key)
	if not clip then return nil end
	local tuning = Bank.Mix[record.Kind][key]
	local sound = Instance.new("Sound")
	sound.Name = "Level 2 " .. record.Kind .. " " .. key
	sound.SoundId = clip.Id
	sound.Volume = 0
	sound.Looped = looped
	sound.PlayOnRemove = false
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = tuning.Min
	sound.RollOffMaxDistance = tuning.Max
	sound.Parent = record.Emitter
	-- Echo is already authored into the corridor files. Extra long reverb would
	-- re-amplify their noise floor and smear the pauses between sounds.
	local channel = {Sound = sound, Key = key, Target = tuning.Volume, Started = false,
		LoadDeadline = now + 8, Duration = clip.Seconds, Looped = looped}
	record.Channels[channelName] = channel
	return channel
end

local function setLoop(record, key, now)
	local old = record.Channels.Loop
	if old and old.Key == key and not old.Releasing then return end
	if old then
		local tail = record.Channels.Tail
		if tail then tail.Sound:Destroy() end
		old.Releasing, old.Target = true, 0
		record.Channels.Tail = old
		record.Channels.Loop = nil
	end
	if key then start(record, "Loop", key, true, now) end
end

local function oneShot(record, key, now, attack)
	local old = record.Channels.Voice
	if old and not attack then return false end
	if old then old.Sound:Destroy() record.Channels.Voice = nil end
	local channel = start(record, "Voice", key, false, now)
	if channel then channel.IsAttack = attack == true end
	return channel ~= nil
end

local function updateChannels(record, dt, now)
	for name, channel in pairs(record.Channels) do
		local sound = channel.Sound
		local remove = not sound.Parent
		if not remove and not channel.Started then
			if channel.Releasing then remove = true
			elseif sound.IsLoaded then
				channel.Started = true
				channel.EndAt = now + channel.Duration + .3
				sound:Play()
			elseif now >= channel.LoadDeadline then
				failedAssets[sound.SoundId] = true
				warn("[Level 2 Entity Audio] Asset unavailable: " .. sound.SoundId)
				remove = true
			end
		end
		if not remove and channel.Started then
			sound.Volume += (channel.Target - sound.Volume) * (1 - math.exp(-dt / .07))
			if channel.Releasing and sound.Volume < .001 then remove = true end
			if not channel.Looped and (now >= channel.EndAt or not sound.IsPlaying) then remove = true end
		end
		if remove then sound:Stop() sound:Destroy() record.Channels[name] = nil end
	end
end

local function updateRecord(record, dt, now, cameraPosition)
	local model, kind = record.Model, record.Kind
	local position = model.PrimaryPart.Position
	local delta = position - record.Position
	record.Position = position
	local speed = Vector3.new(delta.X, 0, delta.Z).Magnitude / math.max(dt, .001)
	-- Anchored rigs have no useful AssemblyLinearVelocity. Measure replicated
	-- travel and hold briefly across network updates, without steps while blocked.
	if speed > .6 and speed < 100 then record.MovingUntil = now + .18 end
	local paused = workspace:GetAttribute("EntityPaused") == true
	local active, moving, hunting, key
	if kind == "Foam" then
		active = model:GetAttribute("Level2_PoolFoamActiveMover") == true
		paused = paused or model:GetAttribute("PoolFoamAnimationPaused") == true
		hunting = model:GetAttribute("Level2_PoolFoamChasing") == true
		moving = now < record.MovingUntil and model:GetAttribute("PoolFoamAnimationState") ~= "Idle"
		key = moving and (hunting and "Run" or "Walk") or "Idle"
	else
		active = model:GetAttribute("Level2_PoolSlideActive") == true
		hunting = model:GetAttribute("Level2_PoolSlideEnraged") == true
		moving = now < record.MovingUntil and model:GetAttribute("Level2_PoolSlideMoving") == true
		local animation = model:GetAttribute("Level2_PoolSlideAnimationState")
		key = moving and (hunting and "EnragedRun" or animation == "Run" and "Run" or "Walk") or "Idle"
		if animation == "Attack" then key = nil end
	end
	local distance = (position - cameraPosition).Magnitude
	local inRange = active and workspace:GetAttribute("EntityPaused") ~= true and distance < 240
	local audible = inRange and not paused
	if not audible then key = nil end
	setLoop(record, key, now)
	local serial = model:GetAttribute(kind == "Foam" and "ActionSerial" or "Level2_PoolSlideAttackSerial") or 0
	if serial > record.Serial and inRange then oneShot(record, "Attack", now, true) end
	record.Serial = serial
	if not audible then
		local voice = record.Channels.Voice
		if voice and (not voice.IsAttack or not inRange) then voice.Releasing, voice.Target = true, 0 end
		record.NextVoice = math.max(record.NextVoice, now + 2)
	elseif now >= record.NextVoice and now >= voiceCooldown then
		local cue
		if kind == "Slide" then cue = "Alert"
		elseif moving then cue = hunting and "Hunt" or (rng:NextNumber() < .65 and "Groan" or "Squeal") end
		if cue and oneShot(record, cue, now, false) then
			voiceCooldown = now + 4 -- Stagger five Foam entities; avoid a wall of voices.
			record.NextVoice = now + rng:NextNumber(16, 28)
		else record.NextVoice = now + 2 end
	end
	updateChannels(record, dt, now)
end

table.insert(connections, RunService.Heartbeat:Connect(function(dt)
	pollClock += dt
	if pollClock < .1 then return end
	local elapsed = pollClock
	pollClock = 0
	local nextWorld = workspace:FindFirstChild("Level 2 Generated World")
	local nextGeneration = nextWorld and nextWorld:GetAttribute("Level2_Generation")
	if world ~= nextWorld or generation ~= nextGeneration then
		clear()
		world, generation = nextWorld, nextGeneration
		scanClock, voiceCooldown = 1, 0
	end
	local camera = workspace.CurrentCamera
	if not world or not camera or not listenerActive() then clear() return end
	scanClock += elapsed
	if scanClock >= 1 then scanClock = 0 scan() end
	local now, emitterCount, soundCount = os.clock(), 0, 0
	for model, record in pairs(records) do
		if not model:IsDescendantOf(world) or not model.PrimaryPart
			or record.Emitter.Parent ~= model.PrimaryPart then
			destroyRecord(record)
			records[model] = nil
		else
			updateRecord(record, elapsed, now, camera.CFrame.Position)
			emitterCount += 1
			for _ in pairs(record.Channels) do soundCount += 1 end
		end
	end
	script:SetAttribute("ActiveEmitters", emitterCount)
	script:SetAttribute("ActiveSounds", soundCount)
end))

script.Destroying:Connect(function()
	for _, connection in ipairs(connections) do connection:Disconnect() end
	clear()
end)
