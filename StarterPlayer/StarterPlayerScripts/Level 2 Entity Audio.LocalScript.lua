-- Level 2 entity sound design. Presentation only; server attributes own gameplay.
--
-- LEVEL2_GROAN_OWNERSHIP_20260921 -- which script owns which Level 2 voice.
--   THIS script owns every sound that comes out of a BODY: all Pool Foam voices,
--   and the Pool Slide's one spawn groan plus its periodic mouth groans.
--   `Level 2 Sound Controller` owns the DISTANT pipe-groan ambience around the
--   map and stands its scheduler down for exactly as long as the server
--   publishes Level2_PoolSlideActive = true.
--   Neither script reads the other's runtime state; that server flag is the only
--   handshake. It lives on `workspace` and in ReplicatedStorage["Level 2 State"],
--   so a client-side STREAM-OUT of the model never looks like a despawn and can
--   never resume the distant scheduler behind this script's back.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Bank = require(ReplicatedStorage:WaitForChild("Level 2 Entity Audio Bank"))
local player = Players.LocalPlayer
local rng = Random.new()
local records, failedAssets, connections, dying = {}, {}, {}, {}
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

-- SLIDE SPAWN LATCH BEGIN -- exercised offline by tools/tests/test_pool_slide_audio_states.py
local SPAWN_GROAN_GRACE = 5
local MOUTH_IDLE_MIN, MOUTH_IDLE_MAX = 16, 28
local MOUTH_CHASE_MIN, MOUTH_CHASE_MAX = 7, 14
local slideState
local slideSpawnKey, slideSpawnPending, slideSpawnDeadline = nil, false, 0

local function slideStateFolder()
	if slideState and slideState.Parent then return slideState end
	slideState = ReplicatedStorage:FindFirstChild("Level 2 State")
	return slideState
end

-- The server's own answer to "is there a body". `workspace` attributes are never
-- streamed out, so this stays true across a local stream-out and goes false only
-- on a real despawn or round teardown (Controller.Stop -> resetPublished).
local function slideActive()
	return workspace:GetAttribute("Level2_PoolSlideActive") == true
end

-- Monotonic per successful spawn. Read from the State folder in ReplicatedStorage
-- rather than the model, because the model is exactly what a stream-out removes.
local function slideSpawnCount()
	local folder = slideStateFolder()
	local value = folder and folder:GetAttribute("Level2_PoolSlideSpawnCount")
	return type(value) == "number" and value or 0
end

-- One groan per BODY, not per stream-in. The key moves only when the server
-- publishes another spawn (or another generation), so a model that streams out
-- and back re-attaches its emitter silently. The grace window exists because the
-- rig spawns at least 100 studs away and may not have replicated yet; after it
-- expires the announcement is dropped rather than faked from somewhere else.
local function updateSlideSpawnLatch(now, currentGeneration)
	local key = slideActive()
		and (tostring(currentGeneration) .. "/" .. tostring(slideSpawnCount())) or nil
	if key ~= slideSpawnKey then
		slideSpawnKey = key
		slideSpawnPending = key ~= nil
		slideSpawnDeadline = now + SPAWN_GROAN_GRACE
	elseif slideSpawnPending and now >= slideSpawnDeadline then
		slideSpawnPending = false
	end
	return slideSpawnPending
end

local function mouthVoiceDelay(chasing)
	if chasing then return rng:NextNumber(MOUTH_CHASE_MIN, MOUTH_CHASE_MAX) end
	return rng:NextNumber(MOUTH_IDLE_MIN, MOUTH_IDLE_MAX)
end
-- SLIDE SPAWN LATCH END

local function destroyRecord(record)
	for _, channel in pairs(record.Channels) do channel.Sound:Destroy() end
	-- An AUTHORED mouth Attachment belongs to the rig; only emitters this script
	-- created are ours to remove.
	if record.EmitterOwned and record.Emitter.Parent then record.Emitter:Destroy() end
end

local function clear(fade)
	for model, record in pairs(records) do
		records[model] = nil
		if fade and next(record.Channels) then
			-- Round end with the body still present: ride the existing 70 ms
			-- release instead of destroying a playing Sound, which clicks.
			for _, channel in pairs(record.Channels) do
				channel.Releasing, channel.Target = true, 0
			end
			table.insert(dying, record)
		else
			destroyRecord(record)
		end
	end
	if not fade then
		for index = #dying, 1, -1 do
			destroyRecord(dying[index])
			dying[index] = nil
		end
	end
	script:SetAttribute("ActiveEmitters", 0)
	script:SetAttribute("ActiveSounds", 0)
end

-- MOUTH EMITTER BEGIN -- exercised offline by tools/tests/test_pool_slide_audio_states.py
-- The live template's rig is 20 plainly named bones (Root, Hips, .. Neck, Head)
-- under the skinned MeshPart, with no authored mouth marker, so this lands on
-- the `Head` bone.
--
-- A Sound parented to a Bone is mixed from that bone's BIND-POSE WorldCFrame,
-- not its animated one, so it would not move with the animation. A bone host
-- therefore gets an OWNED Attachment on the bone's nearest BasePart ancestor
-- (an Attachment cannot be parented to a Bone, and a bone's own parent is
-- usually the next bone up), and the Heartbeat pass writes the bone's ANIMATED
-- pose -- TransformedWorldCFrame -- into it once a frame.
--
-- The other rungs stay as fallbacks: an authored `Level2_PoolSlideMouth`
-- Attachment wins outright, then a named head/jaw MeshPart, then a point derived
-- from the model's own bounding box. Anything rather than RootPart at floor level.
local MOUTH_NAMES = {"Level2_PoolSlideMouth", "MouthAttachment", "Mouth", "Jaw", "Head", "head"}
local MOUTH_BONE_HINTS = {"mouth", "jaw", "head"}

local function boneEmitter(model, bone, scale)
	local host = bone:FindFirstAncestorWhichIsA("BasePart") or model.PrimaryPart
	local attachment = Instance.new("Attachment")
	attachment.Name = "Level 2 Slide Clean Audio Emitter"
	attachment.Parent = host
	-- Resolved once per spawn, so the per-frame cost is one multiply and one write.
	return attachment, true, bone, CFrame.new(Bank.Slide.MouthBoneOffset * scale)
end

local function mouthEmitter(model)
	local box, size = model:GetBoundingBox()
	-- The bone nudge is authored against a 12-stud rig; carry it to this one.
	local scale = size.Y / Bank.Slide.MouthReferenceHeight
	for _, name in ipairs(MOUTH_NAMES) do
		local found = model:FindFirstChild(name, true)
		-- Bone first: a Bone IS an Attachment, but it needs the follow treatment.
		if found and found:IsA("Bone") then return boneEmitter(model, found, scale) end
		if found and found:IsA("Attachment") then return found, false end
		if found and found:IsA("BasePart") then
			local attachment = Instance.new("Attachment")
			attachment.Name = "Level 2 Slide Clean Audio Emitter"
			attachment.Position = Vector3.new(0, found.Size.Y * .2, -found.Size.Z * .35)
			attachment.Parent = found
			return attachment, true
		end
	end
	-- Imported skeletons prefix their bones (`mixamorig:Head`), so try a
	-- case-insensitive substring, most specific hint first. One pass per spawn.
	local descendants = model:GetDescendants()
	for _, hint in ipairs(MOUTH_BONE_HINTS) do
		for _, object in ipairs(descendants) do
			if object:IsA("Bone") and object.Name:lower():find(hint, 1, true) then
				return boneEmitter(model, object, scale)
			end
		end
	end
	local root = model.PrimaryPart
	local offset = Bank.Slide.MouthOffset
	local attachment = Instance.new("Attachment")
	attachment.Name = "Level 2 Slide Clean Audio Emitter"
	attachment.Position = root.CFrame:ToObjectSpace(box).Position
		+ Vector3.new(0, size.Y * offset.Height, -size.Z * offset.Forward)
	attachment.Parent = root
	return attachment, true
end

-- The entire per-frame cost of the mouth: one CFrame write, for the one record
-- that has a bone. Every other record returns on the first line. No extra
-- connection, no thread, nothing allocated.
local function followMouthBone(record)
	local bone = record.MouthBone
	if bone and bone.Parent then
		record.Emitter.WorldCFrame = bone.TransformedWorldCFrame * record.MouthOffset
	end
end
-- MOUTH EMITTER END

local function add(model, kind)
	if records[model] or not model:IsA("Model") or not model.PrimaryPart
		or not world or not model:IsDescendantOf(world)
		or model:GetAttribute("Level2_Generation") ~= generation then return end
	local emitter, owned, bone, boneOffset
	if kind == "Slide" then
		emitter, owned, bone, boneOffset = mouthEmitter(model)
	else
		emitter, owned = Instance.new("Attachment"), true
		emitter.Name = "Level 2 " .. kind .. " Clean Audio Emitter"
		emitter.Parent = model.PrimaryPart
	end
	if owned then emitter:SetAttribute("Level2_ClientOnlyAudio", true) end
	local record = {Model = model, Kind = kind, Emitter = emitter, Channels = {}, Last = {},
		EmitterOwned = owned, Host = emitter.Parent,
		MouthBone = bone, MouthOffset = boneOffset,
		Position = model.PrimaryPart.Position, MovingUntil = 0,
		Serial = model:GetAttribute(kind == "Foam" and "ActionSerial" or "Level2_PoolSlideAttackSerial") or 0,
		NextVoice = os.clock() + rng:NextNumber(3, 10)}
	records[model] = record
	followMouthBone(record) -- place it before the first frame, not at the bind pose
end

local function scan()
	for _, model in ipairs(CollectionService:GetTagged("Level2PoolFoamEntity")) do add(model, "Foam") end
	local runtime = world and world:FindFirstChild("Level 2 Pool Slide Runtime")
	local model = runtime and runtime:FindFirstChild("Level 2 Pool Slide")
	if model then add(model, "Slide") end
end

-- The mouth groans are authored as StringValue slots in the shared Level 2 Sound
-- Library, not as ids in the Bank. Resolve once, and only once the library has
-- replicated -- a miss is not cached, or an early run would leave them silent.
local mouthClips
local function mouthClipList()
	if mouthClips then return mouthClips end
	local library = ReplicatedStorage:FindFirstChild("Level 2 Sound Library")
	if not library then return nil end
	local clips = {}
	for _, slotName in ipairs(Bank.Slide.MouthSlots) do
		local slot = library:FindFirstChild(slotName)
		local raw = slot and slot:IsA("StringValue") and tostring(slot.Value):gsub("%s", "") or ""
		if raw ~= "" then
			table.insert(clips, {Id = raw:match("^%d+$") and ("rbxassetid://" .. raw) or raw,
				Seconds = Bank.Slide.MouthClipSeconds})
		end
	end
	if #clips == 0 then return nil end
	mouthClips = clips
	return mouthClips
end

local function choose(record, key)
	local list = key == "Mouth" and mouthClipList() or Bank[record.Kind][key]
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
	-- Pitch variation on the one-shot voices only; a detuned movement LOOP would
	-- beat against the next one when setLoop crossfades them.
	if not looped then sound.PlaybackSpeed = rng:NextNumber(.97, 1.03) end
	sound.Looped = looped
	sound.PlayOnRemove = false
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = tuning.Min
	sound.RollOffMaxDistance = tuning.Max
	sound.Parent = record.Emitter
	-- Echo is already authored into the corridor files. Extra long reverb would
	-- re-amplify their noise floor and smear the pauses between sounds.
	local channel = {Sound = sound, Key = key, Target = tuning.Volume, Started = false,
		LoadDeadline = now + 8, Duration = clip.Seconds / sound.PlaybackSpeed, Looped = looped}
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
	if channel then
		channel.IsAttack = attack == true
		channel.StartAfter = now + (attack and record.Kind == "Slide" and .5 or 0)
	end
	return channel ~= nil
end

local function updateChannels(record, dt, now)
	for name, channel in pairs(record.Channels) do
		local sound = channel.Sound
		local remove = not sound.Parent
		if not remove and not channel.Started then
			if channel.Releasing then remove = true
			elseif sound.IsLoaded and now >= (channel.StartAfter or 0) then
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
	local active, moving, hunting, chasing, key
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
		-- "Chase" is the controller's own state, not the pump-3 enrage: the mouth
		-- speeds up whenever it is actually coming for somebody.
		local pursuit = model:GetAttribute("Level2_PoolSlideState")
		chasing = pursuit == "CHASE" or pursuit == "ENRAGED" or pursuit == "ATTACK"
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
	elseif kind == "Slide" and slideSpawnPending then
		-- The one spawn announcement outranks the shared voice stagger; it must not
		-- be swallowed because a Pool Foam entity happened to speak a second ago.
		if oneShot(record, "Alert", now, false) then
			slideSpawnPending = false
			voiceCooldown = now + 4
			record.NextVoice = now + mouthVoiceDelay(chasing)
		end
	elseif now >= record.NextVoice and now >= voiceCooldown then
		local cue
		if kind == "Slide" then cue = "Mouth"
		elseif moving then cue = hunting and "Hunt" or (rng:NextNumber() < .65 and "Groan" or "Squeal") end
		if cue and oneShot(record, cue, now, false) then
			voiceCooldown = now + 4 -- Stagger five Foam entities; avoid a wall of voices.
			record.NextVoice = now + (kind == "Slide" and mouthVoiceDelay(chasing)
				or rng:NextNumber(16, 28))
		else record.NextVoice = now + 2 end
	end
end

table.insert(connections, RunService.Heartbeat:Connect(function(dt)
	local frameNow = os.clock()
	for _, record in pairs(records) do
		followMouthBone(record)
		updateChannels(record, dt, frameNow)
	end
	-- Records released by clear(true) keep fading on this same pass and are torn
	-- down the moment their last channel has gone; nothing survives a round.
	for index = #dying, 1, -1 do
		local record = dying[index]
		updateChannels(record, dt, frameNow)
		if next(record.Channels) == nil then
			destroyRecord(record)
			table.remove(dying, index)
		end
	end
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
	-- Tracked even while this client is not listening (dead, or between spectate
	-- targets), so coming back does not fire an announcement for an old body.
	updateSlideSpawnLatch(frameNow, generation)
	local camera = workspace.CurrentCamera
	if not world or not camera or not listenerActive() then clear(true) return end
	scanClock += elapsed
	if scanClock >= 1 then scanClock = 0 scan() end
	local now, emitterCount, soundCount = os.clock(), 0, 0
	for model, record in pairs(records) do
		-- Host, not PrimaryPart: the Slide's emitter lives on the part its mouth
		-- bone hangs off. A bone that has gone away rebuilds the record too, so
		-- the emitter cannot quietly freeze at the last pose it was written.
		if not model:IsDescendantOf(world) or not model.PrimaryPart
			or record.Emitter.Parent ~= record.Host
			or not record.Host:IsDescendantOf(model)
			or (record.MouthBone and not record.MouthBone:IsDescendantOf(model)) then
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
