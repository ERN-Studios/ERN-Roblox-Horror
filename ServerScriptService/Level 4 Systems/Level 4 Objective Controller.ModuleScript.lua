-- Level 4 Objective Controller: "Den Sidste Forestilling".
-- 1 Dark start: a note gives a 4-step order for the six breaker switches in the two service POWER cabinets.
-- 2 Power up: the Light Director runs the wave (the "woooow"), then the lights start failing and the Usher wakes.
-- 3 Three film reels lie on random L4ReelSpots (one may sit in the arcade prize case: the arcade HI-SCORE code opens it).
-- 4 Each booth projector is threaded with a reel (hold) while the MAIN BREAKER is engaged: a co-op player holds the
--   lever (anchored there, the Usher hunts them), or, with one survivor left, a fuse locks it for a minute.
-- 5 Finale: everything dark but the screens; Cinema 2's screen is the exit (root inside L4ExitScreen -> Escaped).
-- Hiding: crouched, slow and inside an L4HideZone. All authority is server-side; prompts are only presentation.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local TweenService = game:GetService("TweenService")

local Configuration = require(script.Parent:WaitForChild("Level 4 Configuration"))
local NoiseRegistry = require(ServerScriptService:WaitForChild("NoiseRegistry"))
local PlayerProtection = require(ServerScriptService:WaitForChild("PlayerProtection"))
local TeamObjectives = require(ServerScriptService:WaitForChild("TeamObjectives"))

local Objectives = {}

local session = 0
local manifest
local runtime, state, clientEvent
local connections = {}
local owned = {}                 -- instances we created (destroyed on Stop)
local restoreCFrames = {}        -- authored parts we move (handles, lever, door)
local LightDirector, Usher

local sequence, sequenceProgress = {}, 0
local switchByKey = {}           -- "A2" -> { Model, Handle, Down }
local wrongLock = false
local reels = {}                 -- records { Id, State, Model, Spot, Carrier, Prompt }
local loadedScreens = {}
local holder, holderAnchor       -- main breaker
local fuseUntil, fuseCooldownUntil = 0, 0
local threading = {}             -- player -> { Screen, Started, Prompt }
local escaped = {}
local arcadeCode, prizeOpen = nil, false
local keypadAttempts = {}
local phase = "Idle"

local function now() return workspace:GetServerTimeNow() end

local function own(inst)
	owned[#owned + 1] = inst
	return inst
end

-- DEV_ESP_L4_20261002: developer ESP (DevCheats) highlights everything tagged L4DevESP and labels it by L4ESPKind.
-- Runtime objects are destroyed with their tag; authored anchors are untagged again in Stop.
local espTagged = {}
local function espTag(inst, kind)
	if not inst then return end
	inst:SetAttribute("L4ESPKind", kind)
	CollectionService:AddTag(inst, "L4DevESP")
	espTagged[inst] = true
end
local function espUntag(inst)
	if not inst then return end
	CollectionService:RemoveTag(inst, "L4DevESP")
	inst:SetAttribute("L4ESPKind", nil)
	espTagged[inst] = nil
end

local function connect(signal, fn)
	local c = signal:Connect(fn)
	connections[#connections + 1] = c
	return c
end

local function setState(name, value)
	if state then state:SetAttribute(name, value) end
end

local function cue(target, payload)
	if not clientEvent then return end
	if target then clientEvent:FireClient(target, payload) else clientEvent:FireAllClients(payload) end
end

local function liveCharacter(player)
	local character = player and player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid and humanoid.Health > 0 and root then return character, humanoid, root end
	return nil
end

local function participant(player)
	return player and player.Parent == Players and player:GetAttribute("InRound") == true
		and player:GetAttribute("Escaped") ~= true and not escaped[player]
end

local function roundLive()
	return workspace:GetAttribute("SelectedLevel") == Configuration.Level and workspace:GetAttribute("RoundActive") == true
end

function Objectives.LivingParticipants()
	local list = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if participant(player) and liveCharacter(player) then list[#list + 1] = player end
	end
	return list
end

local function announce(player, detail)
	pcall(TeamObjectives.Announce, player and player.Name or "The cinema", detail, Configuration.Level)
end

-- the validation every prompt passes (forged Triggered events included)
local function canUse(player, prompt)
	if not (roundLive() and participant(player)) then return false end
	local character, _, root = liveCharacter(player)
	if not character or not prompt or not prompt.Parent or not prompt.Enabled then return false end
	local anchor = prompt.Parent
	local pos = anchor:IsA("Attachment") and anchor.WorldPosition or (anchor:IsA("BasePart") and anchor.Position)
	if not pos then return false end
	return (root.Position - pos).Magnitude <= prompt.MaxActivationDistance + 2.5
end

local function makePrompt(part, action, object, hold, distance)
	local attachment = Instance.new("Attachment")
	attachment.Name = "L4PromptAnchor"
	attachment.Parent = part
	own(attachment)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = action
	prompt.ObjectText = object or ""
	prompt.HoldDuration = hold or 0
	prompt.MaxActivationDistance = distance or 8
	prompt.RequiresLineOfSight = false
	prompt.Style = Enum.ProximityPromptStyle.Default
	prompt.Parent = attachment
	return prompt
end

local function sound(parent, id, volume, rolloff)
	if not id or id == 0 then return nil end
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. tostring(id)
	s.Volume = volume or 1
	s.RollOffMinDistance = 8
	s.RollOffMaxDistance = rolloff or 90
	s.Parent = parent
	own(s)
	s:Play()
	task.delay(12, function() if s.Parent then s:Destroy() end end)
	return s
end

local function spark(part)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(Color3.fromRGB(255, 220, 140))
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new(0.25, 0)
	emitter.Lifetime = NumberRange.new(0.15, 0.4)
	emitter.Speed = NumberRange.new(8, 16)
	emitter.SpreadAngle = Vector2.new(80, 80)
	emitter.Rate = 0
	emitter.Parent = part
	own(emitter)
	emitter:Emit(30)
	task.delay(2, function() if emitter.Parent then emitter:Destroy() end end)
end

local function remember(part)
	if part and not restoreCFrames[part] then restoreCFrames[part] = part.CFrame end
end

local tweens = {}
local restoreCollide = {}
local function tweenTo(part, cf, t)
	local tween = TweenService:Create(part, TweenInfo.new(t or 0.18, Enum.EasingStyle.Quad), { CFrame = cf })
	tweens[#tweens + 1] = tween
	tween:Play()
end

-- authored moving parts carry their hinge in PivotOffset (contract: switch/lever hinge axis = local X, door = local Y)
local function hinged(part, base, rotation)
	local hinge = base * part.PivotOffset
	return hinge * rotation * hinge:Inverse() * base
end

local function floorBelow(position)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { manifest.World:FindFirstChild("Collision") or manifest.World }
	local hit = workspace:Raycast(position + Vector3.new(0, 3, 0), Vector3.new(0, -40, 0), params)
	return hit and hit.Position or nil
end

-- ---------------------------------------------------------------- 1. note + breaker switches

local function switchKey(model)
	return tostring(model:GetAttribute("CabinetId") or "?") .. tostring(model:GetAttribute("SwitchIndex") or "?")
end

local function setSwitch(entry, down)
	entry.Down = down
	if not entry.Handle then return end
	remember(entry.Handle)
	local base = restoreCFrames[entry.Handle]
	tweenTo(entry.Handle, down and hinged(entry.Handle, base, CFrame.Angles(math.rad(-65), 0, 0)) or base, 0.16)
end

local function placeNote(text)
	local spots = manifest.NoteSpots
	if #spots == 0 then return end
	-- spots near an entry spawn first (the power must come on fairly quickly)
	local near = {}
	for _, spot in ipairs(spots) do
		for _, spawn in ipairs(manifest.EntrySpawns) do
			if (spot.Position - spawn.Position).Magnitude <= Configuration.Sequence.NoteMaxDistance then
				near[#near + 1] = spot; break
			end
		end
	end
	local pool = #near > 0 and near or spots
	local spot = pool[math.random(1, #pool)]
	local template = manifest.Templates and manifest.Templates:FindFirstChild("Note")
	local note
	if template then
		note = template:Clone()
		note:PivotTo(spot.CFrame)
	else
		note = Instance.new("Model")
		local paper = Instance.new("Part")
		paper.Name = "Paper"
		paper.Size = Vector3.new(1.05, 0.05, 0.75)
		paper.Color = Color3.fromRGB(226, 220, 196)
		paper.Material = Enum.Material.SmoothPlastic
		paper.CFrame = spot.CFrame
		paper.Parent = note
		note.PrimaryPart = paper
	end
	note.Name = "L4Note"
	note.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	espTag(note, "Note")
	for _, d in ipairs(note:GetDescendants()) do
		if d:IsA("BasePart") then d.Anchored = true; d.CanCollide = false; d.CanQuery = false end
	end
	local paper = note:FindFirstChild("Paper", true) or note.PrimaryPart
	-- the Note template carries its own Paper.NoteText.Text label (asset contract); a placeholder note gets one here
	local templateGui = paper and paper:FindFirstChildWhichIsA("SurfaceGui")
	local label = templateGui and templateGui:FindFirstChildWhichIsA("TextLabel")
	if not label then
		local gui = Instance.new("SurfaceGui")
		gui.Name = "NoteText"
		gui.Face = Enum.NormalId.Top
		gui.CanvasSize = Vector2.new(420, 300)
		gui.LightInfluence = 0.6
		gui.Parent = paper
		label = Instance.new("TextLabel")
		label.Name = "Text"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.PatrickHand
		label.TextColor3 = Color3.fromRGB(40, 30, 40)
		label.TextScaled = true
		label.TextWrapped = true
		label.Parent = gui
	end
	label.Text = text
	note.Parent = runtime
	own(note)
	setState("Level4_NotePosition", spot.Position)
end

local function powerOn(player)
	phase = "Reels"
	setState("Level4_Phase", phase)
	announce(player, "turned the power back on")
	local origin = manifest.MainBreaker and manifest.MainBreaker:GetPivot().Position
		or (manifest.EntrySpawns[1] and manifest.EntrySpawns[1].Position) or Vector3.zero
	LightDirector.PowerUp(origin, function()
		if Usher then Usher.Activate() end
	end)
end

local function onSwitch(player, entry, prompt)
	if not canUse(player, prompt) or phase ~= "Dark" or wrongLock or entry.Down then return end
	local expected = sequence[sequenceProgress + 1]
	setSwitch(entry, true)
	sound(entry.Handle or prompt.Parent, manifest.Audio.Switch, 1)
	NoiseRegistry.Add(prompt.Parent.WorldPosition, Configuration.Noise.Breaker, player)
	if entry.Key == expected then
		sequenceProgress += 1
		setState("Level4_SequenceProgress", sequenceProgress)
		if sequenceProgress >= #sequence then powerOn(player) end
	else
		wrongLock = true
		spark(entry.Handle or prompt.Parent.Parent)
		sound(entry.Handle or prompt.Parent, manifest.Audio.Wrong, 1)
		cue(nil, { Type = "Wrong", Position = prompt.Parent.WorldPosition })
		local mySession = session
		task.delay(Configuration.Sequence.WrongResetSeconds, function()
			if session ~= mySession then return end
			for _, e in pairs(switchByKey) do setSwitch(e, false) end
			sequenceProgress = 0
			setState("Level4_SequenceProgress", 0)
			wrongLock = false
		end)
	end
end

-- A cabinet's three switches sit in one vertical column, and ProximityPrompt's default Exclusivity (OnePerButton)
-- only ever shows the CLOSEST prompt for E: from the floor that is always the lowest switch, so the other two could
-- never be flipped (found in the 2026-10-02 Studio QA). Each switch's prompt therefore lives at eye height in front
-- of its cabinet, spread sideways by SwitchIndex: stand in front of 1, 2 or 3 to get that switch.
local SWITCH_SPREAD, SWITCH_EYE = 3.5, 4.5
local function placeSwitchAnchor(attachment, model, handle)
	local cabinet = model.Parent
	while cabinet and not CollectionService:HasTag(cabinet, "L4PowerCabinet") do cabinet = cabinet.Parent end
	if not (attachment and handle and cabinet and cabinet:IsA("Model")) then return end
	-- front = from the cabinet's body to its handles (the bounding box would include the open door, which swings
	-- out several studs and drags the centre into the room)
	local body
	for _, d in ipairs(cabinet:GetDescendants()) do
		if d:IsA("BasePart") and not d:IsDescendantOf(model) and d.Name == "Body"
			and (not body or d.Size.X * d.Size.Y > body.Size.X * body.Size.Y) then
			body = d
		end
	end
	if not body then return end
	local front = handle.Position - body.Position
	front = Vector3.new(front.X, 0, front.Z)
	if front.Magnitude < 0.05 then front = body.CFrame.LookVector * Vector3.new(1, 0, 1) end
	if front.Magnitude < 0.05 then return end
	front = front.Unit
	local right = front:Cross(Vector3.yAxis)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { manifest.World:FindFirstChild("Collision") or manifest.World }
	local probe = Vector3.new(body.Position.X, handle.Position.Y, body.Position.Z) + front * 3
	local floorHit = workspace:Raycast(probe, Vector3.new(0, -40, 0), params)
	if not floorHit then return end
	local index = tonumber(model:GetAttribute("SwitchIndex")) or 2
	local world = Vector3.new(probe.X, floorHit.Position.Y + SWITCH_EYE, probe.Z) + right * (index - 2) * SWITCH_SPREAD
	-- a low, horizontal panel (v6, owner 2026-10-02): the switches already sit side by side at hand height, so each
	-- prompt goes on its own switch, just in front of it (the prompt matches the switch you see)
	local nearest = math.huge
	for _, other in ipairs(cabinet:GetDescendants()) do
		if other ~= model and other:IsA("Model") and CollectionService:HasTag(other, "L4Breaker") then
			local otherHandle = other:FindFirstChild("Handle", true)
			if otherHandle then
				local gap = otherHandle.Position - handle.Position
				nearest = math.min(nearest, Vector3.new(gap.X, 0, gap.Z).Magnitude)
			end
		end
	end
	if nearest >= SWITCH_SPREAD - 0.6 and handle.Position.Y - floorHit.Position.Y <= 6 then
		world = handle.Position + front * 0.6
	end
	-- parent to the still cabinet body, not the moving handle
	attachment.Parent = cabinet.PrimaryPart or cabinet:FindFirstChildWhichIsA("BasePart", true) or attachment.Parent
	attachment.WorldPosition = world
end

local function setupSwitches()
	table.clear(switchByKey)
	local keys = {}
	for _, model in ipairs(manifest.Breakers) do
		local key = switchKey(model)
		local handle = model:FindFirstChild("Handle", true)
		local entry = { Key = key, Model = model, Handle = handle, Down = false }
		switchByKey[key] = entry
		keys[#keys + 1] = key
		local prompt = makePrompt(handle or model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true),
			"Flip", "Switch " .. key, 0, Configuration.Sequence.SwitchPromptDistance or Configuration.Breaker.PromptDistance)
		placeSwitchAnchor(prompt.Parent, model, handle)
		connect(prompt.Triggered, function(player) onSwitch(player, entry, prompt) end)
	end
	-- a random order of distinct switches
	local rng = Random.new()
	for i = #keys, 2, -1 do
		local j = rng:NextInteger(1, i)
		keys[i], keys[j] = keys[j], keys[i]
	end
	table.clear(sequence)
	for i = 1, math.min(Configuration.Sequence.Length, #keys) do sequence[i] = keys[i] end
	sequenceProgress = 0
	setState("Level4_SequenceGoal", #sequence)
	setState("Level4_SequenceProgress", 0)
	placeNote("POWER\n" .. table.concat(sequence, "  >  ") .. "\n\n- in this order -")
end

-- ---------------------------------------------------------------- 2. reels

local function carriedCount(player)
	local n = 0
	for _, r in ipairs(reels) do if r.State == "CARRIED" and r.Carrier == player then n += 1 end end
	return n
end

local function refreshCarry(player)
	if not player or player.Parent ~= Players then return end
	local n = carriedCount(player)
	player:SetAttribute("Level4_ReelsCarried", n)
	local factor = math.max(Configuration.Reels.MinSpeedFactor, Configuration.Reels.CarrySpeedFactor ^ n)
	player:SetAttribute("Level4_CarrySpeedFactor", n > 0 and factor or nil)
	local collected = 0
	for _, r in ipairs(reels) do if r.State == "CARRIED" or r.State == "INSERTED" then collected += 1 end end
	setState("Level4_ReelsCollected", collected)
end

local function reelModel(record)
	local template = manifest.Templates and manifest.Templates:FindFirstChild("FilmReel")
	local model
	if template then
		model = template:Clone()
	else
		model = Instance.new("Model")
		local can = Instance.new("Part")
		can.Shape = Enum.PartType.Cylinder
		can.Size = Vector3.new(0.3, 1.36, 1.36)
		can.Color = Color3.fromRGB(130, 128, 120)
		can.Material = Enum.Material.Metal
		can.Parent = model
		model.PrimaryPart = can
	end
	model.Name = "L4FilmReel_" .. record.Id
	local scale = Configuration.Reels.Scale or 1
	if scale ~= 1 then model:ScaleTo(model:GetScale() * scale) end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then d.CanCollide = false; d.CanQuery = false; d.CanTouch = false; d.Massless = true end
	end
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent   -- three reels: always on every client
	espTag(model, "Reel")
	return model
end

local REEL_LIFT = 0.35 * (Configuration.Reels.Scale or 1)

local function placeReelInWorld(record, cf)
	if record.Model then record.Model:Destroy() end
	local model = reelModel(record)
	model:PivotTo(cf)
	for _, d in ipairs(model:GetDescendants()) do if d:IsA("BasePart") then d.Anchored = true end end
	model.Parent = runtime
	own(model)
	record.Model = model
	local part = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	record.Prompt = makePrompt(part, "Pick up", "Film reel", 0.4, Configuration.Reels.PromptDistance)
	record.Prompt.Enabled = not record.Locked
	connect(record.Prompt.Triggered, function(player) Objectives.PickUp(player, record) end)
end

function Objectives.PickUp(player, record)
	if not canUse(player, record.Prompt) or (record.State ~= "WORLD" and record.State ~= "DROPPED") then return end
	local character, _, root = liveCharacter(player)
	if not character then return end
	record.State = "CARRIED"
	record.Carrier = player
	if record.Prompt then record.Prompt.Enabled = false end
	if record.Model then record.Model:Destroy() end
	local model = reelModel(record)
	local slot = carriedCount(player) - 1
	local scale = Configuration.Reels.Scale or 1
	model:PivotTo(root.CFrame * CFrame.new(0.25, 0.3 + slot * 0.38 * scale, 0.95 + 0.4 * (scale - 1))
		* CFrame.Angles(0, 0, math.rad(90)))
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root; weld.Part1 = d; weld.Parent = d
		end
	end
	model.Parent = character
	record.Model = model
	sound(root, manifest.Audio.Reel, 0.8)
	refreshCarry(player)
	announce(player, "found a film reel")
end

local function dropReels(player, position)
	local dropped = 0
	for _, r in ipairs(reels) do
		if r.State == "CARRIED" and r.Carrier == player then
			dropped += 1
			r.State = "DROPPED"
			r.Carrier = nil
			-- no floor under the drop (a fall into the void): the reel goes home, it can never be lost
			local base = position and floorBelow(position)
			if base then
				placeReelInWorld(r, CFrame.new(base + Vector3.new((dropped - 1) * 1.6 * (Configuration.Reels.Scale or 1), REEL_LIFT, 0)) * CFrame.Angles(0, math.random() * 6.28, math.rad(90)))
			else
				r.State = "WORLD"
				placeReelInWorld(r, r.Spot.CFrame * CFrame.new(0, REEL_LIFT, 0) * CFrame.Angles(0, 0, math.rad(90)))
			end
		end
	end
	if dropped > 0 then refreshCarry(player) end
end

local function setupReels()
	table.clear(reels)
	local spots = table.clone(manifest.ReelSpots)
	local rng = Random.new()
	for i = 1, math.min(Configuration.Reels.Goal, #spots) do
		local j = rng:NextInteger(1, #spots)
		local spot = table.remove(spots, j)
		local record = { Id = i, State = "WORLD", Spot = spot, Locked = spot:GetAttribute("Locked") == true }
		reels[i] = record
		placeReelInWorld(record, spot.CFrame * CFrame.new(0, REEL_LIFT, 0) * CFrame.Angles(0, 0, math.rad(90)))
	end
	setState("Level4_ReelGoal", #reels)
	setState("Level4_ReelsCollected", 0)
	setState("Level4_ReelsLoaded", 0)
end

-- ---------------------------------------------------------------- 3. main breaker (hold / fuse)

local function breakerEngaged()
	if fuseUntil > now() then return true end
	if holder and participant(holder) then
		local _, _, root = liveCharacter(holder)
		local lever = manifest.MainBreakerLever
		if root and lever and (root.Position - lever.Position).Magnitude <= Configuration.Breaker.HoldDistance + 2 then
			return true
		end
	end
	return false
end

local function setLever(down)
	local lever = manifest.MainBreakerLever
	if not lever then return end
	remember(lever)
	local base = restoreCFrames[lever]
	tweenTo(lever, down and hinged(lever, base, CFrame.Angles(math.rad(-80), 0, 0)) or base, 0.25)
end

local function releaseHolder(reason)
	if not holder then return end
	local was = holder
	holder = nil
	if holderAnchor and holderAnchor.Parent then holderAnchor.Anchored = false end
	holderAnchor = nil
	setState("Level4_BreakerHolder", 0)
	if fuseUntil <= now() then setLever(false) end
	cue(was, { Type = "BreakerReleased", Reason = reason })
end

function Objectives.BreakerHolder()
	return holder
end

local function soloMode()
	return #Objectives.LivingParticipants() <= 1
end

local function onMainBreaker(player, prompt)
	if not canUse(player, prompt) or phase ~= "Reels" then return end
	if holder == player then releaseHolder("let go"); return end
	if holder and participant(holder) and liveCharacter(holder) then return end
	if soloMode() then
		cue(player, { Type = "Hint", Text = "Alone, you can lock the breaker with the fuse." })
		return
	end
	local _, _, root = liveCharacter(player)
	holder = player
	holderAnchor = root
	root.Anchored = true
	setLever(true)
	setState("Level4_BreakerHolder", player.UserId)
	sound(prompt.Parent.Parent, manifest.Audio.Breaker, 1.1)
	NoiseRegistry.Add(prompt.Parent.WorldPosition, Configuration.Noise.Breaker, player)
	announce(player, "is holding the main breaker")
end

local function onFuse(player, prompt)
	if not canUse(player, prompt) or phase ~= "Reels" then return end
	if not soloMode() then
		cue(player, { Type = "Hint", Text = "The fuse only works for the last survivor. Someone must hold the breaker." })
		return
	end
	if fuseUntil > now() or now() < fuseCooldownUntil then return end
	fuseUntil = now() + Configuration.Breaker.FuseSeconds
	setState("Level4_FuseUntil", fuseUntil)
	setLever(true)
	sound(prompt.Parent.Parent, manifest.Audio.Breaker, 1.1)
	NoiseRegistry.Add(prompt.Parent.WorldPosition, Configuration.Noise.Breaker, player)
	announce(player, "locked the breaker with a fuse")
	local mySession = session
	task.delay(Configuration.Breaker.FuseSeconds, function()
		if session ~= mySession then return end
		if fuseUntil <= now() + 0.05 then
			fuseUntil = 0
			fuseCooldownUntil = now() + Configuration.Breaker.FuseCooldownSeconds
			setState("Level4_FuseUntil", 0)
			if not holder then setLever(false) end
			local socket = manifest.FuseSocket
			if socket then spark(socket); sound(socket, manifest.Audio.Wrong, 1) end
			cue(nil, { Type = "FuseBlown" })
		end
	end)
end

local function setupBreaker()
	local lever = manifest.MainBreakerLever
	if lever then
		local prompt = makePrompt(lever, "Hold", "Main breaker", 0.25, Configuration.Breaker.PromptDistance)
		prompt.Name = "L4MainBreakerPrompt"
		connect(prompt.Triggered, function(player) onMainBreaker(player, prompt) end)
		manifest.MainBreakerPrompt = prompt
	end
	if manifest.FuseSocket then
		local prompt = makePrompt(manifest.FuseSocket, "Insert fuse", "Fuse (60 s)", 0.6, Configuration.Breaker.PromptDistance)
		connect(prompt.Triggered, function(player) onFuse(player, prompt) end)
		manifest.FusePrompt = prompt
	end
	setState("Level4_BreakerHolder", 0)
	setState("Level4_FuseUntil", 0)
end

-- ---------------------------------------------------------------- 4. projectors

local function startScreen(index)
	local screen = manifest.Screens[index]
	if not screen then return end
	local light = Instance.new("SurfaceLight")
	light.Name = "L4FilmLight"
	light.Range = 34
	light.Angle = 110
	light.Brightness = 1.4
	light.Color = Color3.fromRGB(205, 215, 255)
	light.Face = Enum.NormalId.Front
	light.Parent = screen
	own(light)
	local back = light:Clone()
	back.Face = Enum.NormalId.Back
	back.Parent = screen
	own(back)
	screen:SetAttribute("L4FilmRunning", true)
end

local function finishThread(player, screenIndex)
	local record
	for _, r in ipairs(reels) do
		if r.State == "CARRIED" and r.Carrier == player then record = r; break end
	end
	if not record then return false end
	record.State = "INSERTED"
	record.Carrier = nil
	if record.Model then record.Model:Destroy(); record.Model = nil end
	loadedScreens[screenIndex] = true
	espUntag(manifest.Projectors[screenIndex])
	refreshCarry(player)
	local loaded = 0
	for _ in pairs(loadedScreens) do loaded += 1 end
	setState("Level4_ReelsLoaded", loaded)
	LightDirector.SetEscalation(loaded)
	startScreen(screenIndex)
	local projector = manifest.Projectors[screenIndex]
	if projector then
		local s = sound(projector.PrimaryPart or projector:FindFirstChildWhichIsA("BasePart", true), manifest.Audio.Projector, 1.2, 120)
		if s then s.Looped = true end
	end
	cue(nil, { Type = "ProjectorStart", Screen = screenIndex })
	announce(player, "started projector " .. screenIndex)
	if loaded >= Configuration.Reels.Goal then
		task.defer(Objectives.StartFinale)
	end
	return true
end

local function setupProjectors()
	table.clear(loadedScreens)
	for index, projector in pairs(manifest.Projectors) do
		local part = projector.PrimaryPart or projector:FindFirstChildWhichIsA("BasePart", true)
		local prompt = makePrompt(part, "Thread reel", "Projector " .. index, Configuration.Projectors.ThreadSeconds,
			Configuration.Projectors.PromptDistance)
		connect(prompt.PromptButtonHoldBegan, function(player)
			if not canUse(player, prompt) or loadedScreens[index] then return end
			if carriedCount(player) == 0 then
				cue(player, { Type = "Hint", Text = "You need a film reel." }); return
			end
			if not breakerEngaged() then
				cue(player, { Type = "Hint", Text = "The main breaker in the service room must be on." }); return
			end
			local mySession = session
			local entry = { Screen = index, Started = now(), Character = player.Character }
			threading[player] = entry
			setState("Level4_ThreadScreen", index)
			cue(nil, { Type = "Thread", Screen = index, Player = player.UserId })
			task.spawn(function()
				local nextNoise = 0
				while threading[player] == entry and session == mySession do
					if not (canUse(player, prompt) and player.Character == entry.Character and breakerEngaged()
						and carriedCount(player) > 0 and not loadedScreens[index]) then
						threading[player] = nil
						cue(player, { Type = "Hint", Text = breakerEngaged() and "Threading interrupted." or "The projector lost power." })
						break
					end
					if os.clock() >= nextNoise then
						nextNoise = os.clock() + Configuration.Projectors.NoiseEvery
						NoiseRegistry.Add(part.Position, Configuration.Noise.Projector, player)
					end
					task.wait(0.2)
				end
				if not next(threading) then setState("Level4_ThreadScreen", 0) end
			end)
		end)
		connect(prompt.PromptButtonHoldEnded, function(player)
			-- a completed hold fires HoldEnded BEFORE Triggered: keep the entry a moment so Triggered can consume it
			local entry = threading[player]
			if entry and entry.Screen == index then
				task.delay(0.3, function() if threading[player] == entry then threading[player] = nil end end)
			end
		end)
		connect(prompt.Triggered, function(player)
			local entry = threading[player]
			threading[player] = nil
			if not entry or entry.Screen ~= index or not canUse(player, prompt) or loadedScreens[index]
				or player.Character ~= entry.Character then return end
			if now() - entry.Started < Configuration.Projectors.ThreadSeconds - 0.35 then return end
			if not breakerEngaged() then
				cue(player, { Type = "Hint", Text = "The projector lost power." }); return
			end
			if finishThread(player, index) then prompt.Enabled = false end
		end)
	end
	setState("Level4_ThreadScreen", 0)
end

-- ---------------------------------------------------------------- 5. finale + exit

local function escapePlayer(player)
	if escaped[player] or not participant(player) then return end
	local character, _, root = liveCharacter(player)
	if not character then return end
	escaped[player] = true
	dropReels(player, root.Position)
	if holder == player then releaseHolder("escaped") end
	player:SetAttribute("Escaped", true)
	local slots = manifest.ExitSafeSpawns
	local slot = slots[((#Players:GetPlayers()) % math.max(#slots, 1)) + 1]
	if slot then
		root.AssemblyLinearVelocity = Vector3.zero
		character:PivotTo(slot.CFrame + Vector3.new(0, 3, 0))
	end
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local roundStatus = remotes and remotes:FindFirstChild("RoundStatus")
	if roundStatus then
		for _, recipient in ipairs(Players:GetPlayers()) do
			if recipient:GetAttribute("InRound") == true then roundStatus:FireClient(recipient, "escape", player.Name) end
		end
	end
	announce(player, "stepped into the screen")
end

function Objectives.StartFinale()
	if phase == "Finale" or phase == "Done" then return end
	phase = "Finale"
	setState("Level4_Phase", phase)
	releaseHolder("finale")
	local screens = {}
	for _, s in pairs(manifest.Screens) do screens[#screens + 1] = s end
	LightDirector.Finale(screens)
	setState("Level4_ExitUnlocked", true)
	espTag(manifest.ExitScreen, "Exit")
	if manifest.ExitScreen then setState("Level4_ExitPosition", manifest.ExitScreen.Position) end
	if Usher then Usher.Finale() end
	cue(nil, { Type = "Finale", Credits = Configuration.Finale.CreditsSeconds })
end

local function insideBox(part, position, depthSlack)
	local p = part.CFrame:PointToObjectSpace(position)
	local h = part.Size * 0.5
	return math.abs(p.X) <= h.X + 0.6 and math.abs(p.Y) <= h.Y + 3 and math.abs(p.Z) <= h.Z + (depthSlack or 1.2)
end

-- ---------------------------------------------------------------- hiding

function Objectives.IsHidden(player)
	if not participant(player) then return false end
	return player:GetAttribute("Level4_Hidden") == true
end

local function updateHiding(player)
	local character, humanoid, root = liveCharacter(player)
	local hidden = false
	if character and participant(player) and (not Configuration.Hiding.RequireCrouch or player:GetAttribute("Crouching") == true)
		and root.AssemblyLinearVelocity.Magnitude <= Configuration.Hiding.MaxSpeed and holder ~= player then
		for _, zone in ipairs(manifest.HideZones) do
			if insideBox(zone, root.Position) then hidden = true; break end
		end
	end
	if player:GetAttribute("Level4_Hidden") ~= hidden then player:SetAttribute("Level4_Hidden", hidden or nil) end
end

-- ---------------------------------------------------------------- bonus: arcade code

local function setupArcade()
	arcadeCode = nil
	prizeOpen = false
	local cabinet = manifest.ArcadeCode
	local keypad = manifest.PrizeKeypad
	if not (cabinet and keypad) then return end
	local rng = Random.new()
	local digits = {}
	for i = 1, Configuration.Bonus.CodeLength do digits[i] = tostring(rng:NextInteger(0, 9)) end
	arcadeCode = table.concat(digits)
	local screen = cabinet:FindFirstChild("Screen", true) or cabinet.PrimaryPart
	if screen then
		local gui = Instance.new("SurfaceGui")
		gui.Name = "L4HiScore"
		gui.Face = Enum.NormalId.Front
		gui.CanvasSize = Vector2.new(400, 300)
		gui.LightInfluence = 0
		gui.Brightness = 2
		gui.Parent = screen
		own(gui)
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundColor3 = Color3.fromRGB(4, 6, 18)
		label.Font = Enum.Font.Arcade
		label.TextColor3 = Color3.fromRGB(80, 255, 230)
		label.TextScaled = true
		label.Text = "HI-SCORE\n1. ZEN  " .. arcadeCode .. "0\n2. KRL  41210\n3. ???  00000"
		label.Parent = gui
	end
	local prompt = makePrompt(keypad, "Enter code", "Prize case", 0, Configuration.Bonus.KeypadDistance)
	connect(prompt.Triggered, function(player)
		if not canUse(player, prompt) or prizeOpen then return end
		cue(player, { Type = "Keypad" })
	end)
	manifest.KeypadPrompt = prompt
end

local function openPrize(player)
	prizeOpen = true
	espUntag(manifest.PrizeCase)
	espUntag(manifest.ArcadeCode)
	local case = manifest.PrizeCase
	local door = case and case:FindFirstChild("Door", true)
	if door then
		remember(door)
		tweenTo(door, hinged(door, restoreCFrames[door], CFrame.Angles(0, math.rad(-100), 0)), 0.6)
		if restoreCollide[door] == nil then restoreCollide[door] = door.CanCollide end
		door.CanCollide = false
	end
	sound(door or manifest.PrizeKeypad, manifest.Audio.Prize, 1)
	if manifest.KeypadPrompt then manifest.KeypadPrompt.Enabled = false end
	local unlockedReel = false
	for _, r in ipairs(reels) do
		if r.Locked and r.State == "WORLD" then
			r.Locked = false
			if r.Prompt then r.Prompt.Enabled = true end
			unlockedReel = true
		end
	end
	if not unlockedReel then
		-- a battery pack instead
		local spot = manifest.PrizeKeypad
		local template = manifest.Templates and manifest.Templates:FindFirstChild("BatteryPack")
		local pack = template and template:Clone() or Instance.new("Model")
		if not template then
			local p = Instance.new("Part"); p.Size = Vector3.new(0.8, 1.1, 0.5); p.Color = Color3.fromRGB(30, 30, 34); p.Parent = pack
			pack.PrimaryPart = p
		end
		pack.Name = "L4BatteryPack"
		espTag(pack, "Battery")
		pack:PivotTo((case and case:GetPivot() or spot.CFrame) * CFrame.new(0, 0.6, 0))
		for _, d in ipairs(pack:GetDescendants()) do if d:IsA("BasePart") then d.Anchored = true; d.CanCollide = false end end
		pack.Parent = runtime
		own(pack)
		local part = pack.PrimaryPart or pack:FindFirstChildWhichIsA("BasePart", true)
		local prompt = makePrompt(part, "Take", "Battery pack", 0.3, 8)
		connect(prompt.Triggered, function(taker)
			if not canUse(taker, prompt) then return end
			prompt.Enabled = false
			pack:Destroy()
			taker:SetAttribute("Level4_BatteryRefill", (taker:GetAttribute("Level4_BatteryRefill") or 0) + 1)
			announce(taker, "found a battery pack")
		end)
	end
	announce(player, "cracked the high-score code")
end

-- ---------------------------------------------------------------- lifecycle

local function bindPlayer(player)
	connect(player.CharacterRemoving, function(character)
		local root = character:FindFirstChild("HumanoidRootPart")
		dropReels(player, root and root.Position)
		if holder == player then releaseHolder("gone") end
		threading[player] = nil
	end)
	connect(player:GetAttributeChangedSignal("InRound"), function()
		if player:GetAttribute("InRound") ~= true then
			if holder == player then releaseHolder("left") end
			threading[player] = nil
		end
	end)
	local function hookCharacter(character)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid then
			connect(humanoid.Died, function()
				local root = character:FindFirstChild("HumanoidRootPart")
				dropReels(player, root and root.Position)
				if holder == player then releaseHolder("died") end
				threading[player] = nil
			end)
		end
	end
	if player.Character then task.spawn(hookCharacter, player.Character) end
	connect(player.CharacterAdded, hookCharacter)
end

local function heartbeat()
	local lastNoise = {}
	return function()
		if not roundLive() then return end
		local t = now()
		for _, player in ipairs(Players:GetPlayers()) do
			if participant(player) then
				updateHiding(player)
				local _, _, root = liveCharacter(player)
				-- rattling reels
				if root and carriedCount(player) > 0 and root.AssemblyLinearVelocity.Magnitude > Configuration.Reels.RunNoiseSpeed
					and (t - (lastNoise[player] or 0)) > 0.5 then
					lastNoise[player] = t
					NoiseRegistry.Add(root.Position, Configuration.Noise.Reel, player)
				end
				-- the holder must stay at the lever
				if holder == player and root then
					local lever = manifest.MainBreakerLever
					if lever and (root.Position - lever.Position).Magnitude > Configuration.Breaker.HoldDistance + 4 then
						releaseHolder("walked away")
					end
				end
				-- the exit
				if phase == "Finale" and root and manifest.ExitScreen and insideBox(manifest.ExitScreen, root.Position, 3) then
					escapePlayer(player)
				end
			end
		end
		if holder and (not participant(holder) or not liveCharacter(holder)) then releaseHolder("gone") end
		-- a loose reel whose model vanished (destroyed below the map, removed by anything) goes home
		for _, r in ipairs(reels) do
			if r.State == "CARRIED" and not (r.Carrier and participant(r.Carrier) and liveCharacter(r.Carrier)) then
				local _, _, croot = liveCharacter(r.Carrier)
				dropReels(r.Carrier, croot and croot.Position)
			end
			if (r.State == "WORLD" or r.State == "DROPPED") and not (r.Model and r.Model.Parent) then
				r.State = "WORLD"
				placeReelInWorld(r, r.Spot.CFrame * CFrame.new(0, REEL_LIFT, 0) * CFrame.Angles(0, 0, math.rad(90)))
			end
		end
		-- prompts follow the breaker state for clarity
		local prompt = manifest.MainBreakerPrompt
		if prompt then
			local solo = soloMode()
			if solo and holder then releaseHolder("alone") end
			prompt.Enabled = phase == "Reels" and (not solo or holder ~= nil)
			prompt.ActionText = holder and "Let go" or "Hold"
		end
		if manifest.FusePrompt then
			manifest.FusePrompt.Enabled = phase == "Reels" and soloMode() and fuseUntil <= t and t >= fuseCooldownUntil
		end
		setState("Level4_BreakerEngaged", breakerEngaged())
	end
end

function Objectives.Start(m, generation, lightDirector, usher)
	Objectives.Stop()
	session += 1
	manifest = m
	LightDirector = lightDirector
	Usher = usher
	runtime = m.Runtime
	state = m.State
	clientEvent = m.ClientEvent
	phase = "Dark"
	wrongLock = false
	escaped = {}
	fuseUntil, fuseCooldownUntil = 0, 0
	setState("Level4_Phase", phase)
	setState("Level4_ExitUnlocked", false)
	setupSwitches()
	setupReels()
	setupBreaker()
	setupProjectors()
	setupArcade()
	for _, cabinet in ipairs(CollectionService:GetTagged("L4PowerCabinet")) do
		if cabinet:IsDescendantOf(m.World) then espTag(cabinet, "Power") end
	end
	espTag(m.MainBreaker, "Breaker")
	for _, projector in pairs(m.Projectors) do espTag(projector, "Projector") end
	if arcadeCode then
		espTag(m.ArcadeCode, "ArcadeCode")
		espTag(m.PrizeCase, "PrizeCase")
	end
	for _, player in ipairs(Players:GetPlayers()) do bindPlayer(player) end
	connect(Players.PlayerAdded, bindPlayer)
	connect(Players.PlayerRemoving, function(player)
		for _, r in ipairs(reels) do
			if r.State == "CARRIED" and r.Carrier == player then
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				dropReels(player, root and root.Position or (r.Spot and r.Spot.Position) or Vector3.zero)
				break
			end
		end
		if holder == player then releaseHolder("left") end
	end)
	connect(RunService.Heartbeat, heartbeat())
	if m.KeypadSubmit then
		connect(m.KeypadSubmit.OnServerEvent, function(player, code)
			if type(code) ~= "string" or #code ~= Configuration.Bonus.CodeLength or not code:match("^%d+$") then return end
			if prizeOpen or not arcadeCode or not participant(player) then return end
			local t = now()
			if (keypadAttempts[player] or 0) > t then return end
			keypadAttempts[player] = t + 1
			local _, _, root = liveCharacter(player)
			if not root or not m.PrizeKeypad or (root.Position - m.PrizeKeypad.Position).Magnitude > Configuration.Bonus.KeypadDistance + 3 then return end
			if code == arcadeCode then
				openPrize(player)
				cue(player, { Type = "KeypadResult", Ok = true })
			else
				sound(m.PrizeKeypad, m.Audio.Wrong, 0.7)
				cue(player, { Type = "KeypadResult", Ok = false })
			end
		end)
	end
	return true
end

function Objectives.Stop()
	session += 1
	for inst in pairs(espTagged) do
		if inst.Parent then espUntag(inst) end
	end
	table.clear(espTagged)
	for _, c in ipairs(connections) do c:Disconnect() end
	table.clear(connections)
	if holder then releaseHolder("stop") end
	for _, player in ipairs(Players:GetPlayers()) do
		player:SetAttribute("Level4_ReelsCarried", nil)
		player:SetAttribute("Level4_CarrySpeedFactor", nil)
		player:SetAttribute("Level4_Hidden", nil)
		player:SetAttribute("Level4_BatteryRefill", nil)
		local character = player.Character
		if character then
			for _, child in ipairs(character:GetChildren()) do
				if child:IsA("Model") and child.Name:match("^L4FilmReel_") then child:Destroy() end
			end
		end
	end
	if manifest then
		for _, screen in pairs(manifest.Screens or {}) do screen:SetAttribute("L4FilmRunning", nil) end
	end
	for _, inst in ipairs(owned) do if inst.Parent then inst:Destroy() end end
	table.clear(owned)
	for _, tween in ipairs(tweens) do tween:Cancel() end
	table.clear(tweens)
	for part, cf in pairs(restoreCFrames) do if part.Parent then part.CFrame = cf end end
	for part, collide in pairs(restoreCollide) do if part.Parent then part.CanCollide = collide end end
	table.clear(restoreCollide)
	wrongLock = false
	table.clear(restoreCFrames)
	table.clear(reels); table.clear(threading); table.clear(loadedScreens)
	phase = "Idle"
	manifest = nil
end

function Objectives.Phase()
	return phase
end

return Objectives
