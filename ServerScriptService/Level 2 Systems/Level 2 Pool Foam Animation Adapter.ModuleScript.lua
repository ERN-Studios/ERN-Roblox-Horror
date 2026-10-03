--!strict
-- Optional animation bridge for final rigs, with a no-rig visual fallback for
-- temporary proxies. The encounter never depends on a track loading or ending.

local Configuration = require(script.Parent:WaitForChild("Level 2 Pool Foam Configuration"))

local AnimationAdapter = {}
AnimationAdapter.__index = AnimationAdapter

local VALID_STATES: { [string]: string } = {}
for _, state in Configuration.States do
	VALID_STATES[string.lower(state)] = state
end

local MOTION_ALIASES: { [string]: string } = {
	dormant = "Idle",
	idle = "Idle",
	stalk = "Walk",
	walk = "Walk",
	wander = "Walk",
	patrol = "Walk",
	move = "Walk",
	investigate = "Walk",
	search = "Walk",
	retreat = "Walk",
	caught = "Caught",
	observed = "Caught",
	frozen = "Caught",
	freeze = "Caught",
	hunt = "Hunt",
	chase = "Hunt",
	run = "Hunt",
	attack = "Attack",
	windup = "Attack",
	strike = "Attack",
	collapse = "Collapse",
	dead = "Collapse",
	defeated = "Collapse",
	despawn = "Collapse",
}

local function normalizedKey(value: any): string
	if type(value) ~= "string" then
		return ""
	end
	return string.lower((string.gsub(value, "[^%w]", "")))
end

local function canonicalState(value: any, allowMotionAliases: boolean): string?
	local key = normalizedKey(value)
	local direct = VALID_STATES[key]
	if direct ~= nil then
		return direct
	end
	if allowMotionAliases then
		return MOTION_ALIASES[key]
	end
	return nil
end

local function normalizedAnimationId(value: any): string?
	if type(value) == "number" and value > 0 then
		return "rbxassetid://" .. tostring(math.floor(value))
	end
	if type(value) ~= "string" or value == "" then
		return nil
	end

	if string.match(value, "^%d+$") ~= nil then
		return "rbxassetid://" .. value
	end
	if string.match(value, "^rbxassetid://%d+$") ~= nil then
		return value
	end
	return nil
end

local function configuredAnimationSlots(value: any): { any }
	local slots = {}
	if type(value) == "table" then
		-- Locomotion exposes exactly four stable authored slots. Blank/invalid
		-- entries stay addressable in Configuration but are not loaded.
		for slotIndex = 1, 4 do
			local animationId = normalizedAnimationId(value[slotIndex])
			if animationId ~= nil then
				table.insert(slots, {SlotIndex = slotIndex, AnimationId = animationId})
			end
		end
	else
		local animationId = normalizedAnimationId(value)
		if animationId ~= nil then
			table.insert(slots, {SlotIndex = 1, AnimationId = animationId})
		end
	end
	return slots
end

local function randomSeedForModel(model: Model): number
	local seed = math.floor(tonumber(model:GetAttribute("Level2_Generation")) or 1)
	local identity = tostring(model:GetAttribute(Configuration.Attributes.InstanceId) or model.Name)
	for index = 1, #identity do
		seed = (seed * 33 + string.byte(identity, index)) % 2147483647
	end
	return math.max(1, seed)
end

local function disconnectAll(connections: { RBXScriptConnection })
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
end

local function resolveSlot(model: Model, requestedSlot: any): any
	local value = requestedSlot
	if value == nil then
		value = model:GetAttribute(Configuration.Attributes.Slot)
	end

	local key = normalizedKey(value)
	if key == "secondary" or key == "second" or key == "b" or key == "2" then
		return Configuration.Slots.Secondary
	end
	return Configuration.Slots.Primary
end

local function captureProxyVisuals(model: Model): { [BasePart]: any }
	local visuals: { [BasePart]: any } = {}
	if model:GetAttribute(Configuration.Attributes.TemporaryProxy) ~= true then
		return visuals
	end

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart")
			and descendant:GetAttribute(Configuration.Attributes.ProxyVisual) == true
		then
			visuals[descendant] = {
				Color = descendant.Color,
				Transparency = descendant.Transparency,
			}
		end
	end
	return visuals
end

function AnimationAdapter:_ensureAnimator(): Animator?
	if self._animator ~= nil and self._animator.Parent ~= nil then
		return self._animator
	end

	local host: Instance?
	local humanoid = self._model:FindFirstChildWhichIsA("Humanoid")
	if humanoid ~= nil then
		host = humanoid
	else
		local controller = self._model:FindFirstChildWhichIsA("AnimationController")
		if controller == nil then
			controller = Instance.new("AnimationController")
			controller.Name = "PoolFoamAnimationController"
			controller.Parent = self._model
			self._createdController = controller
		end
		host = controller
	end

	if host == nil then
		return nil
	end

	local animator = host:FindFirstChildWhichIsA("Animator")
	if animator == nil then
		animator = Instance.new("Animator")
		animator.Parent = host
		self._createdAnimator = animator
	end
	self._animator = animator
	return animator
end

function AnimationAdapter:_destroyTracks()
	for _, bank in self._trackBanks do
		for _, record in bank do
			pcall(function()
				record.Track:Stop(0)
				record.Track:Destroy()
			end)
		end
	end
	table.clear(self._trackBanks)
	self._activeRecord = nil
	self._model:SetAttribute(Configuration.Attributes.AnimationVariant or "PoolFoamAnimationVariant", nil)
	self._model:SetAttribute(Configuration.Attributes.AnimationAssetId or "PoolFoamAnimationAssetId", nil)

	if self._assetFolder ~= nil then
		self._assetFolder:Destroy()
		self._assetFolder = nil
	end
end

function AnimationAdapter:_loadTracks()
	self:_destroyTracks()
	local ids = Configuration.AnimationIds[self._slot.Id]
	if ids == nil then
		return
	end

	for _, state in Configuration.States do
		local bank = {}
		for _, slot in configuredAnimationSlots(ids[state]) do
			local animator = self:_ensureAnimator()
			if animator == nil then
				return
			end

			if self._assetFolder == nil then
				local folder = Instance.new("Folder")
				folder.Name = "PoolFoamAnimationAssets_Runtime"
				folder.Parent = self._model
				self._assetFolder = folder
			end

			local animation = Instance.new("Animation")
			animation.Name = state .. "_" .. tostring(slot.SlotIndex)
			animation.AnimationId = slot.AnimationId
			animation.Parent = self._assetFolder

			local ok, loaded = pcall(function()
				return animator:LoadAnimation(animation)
			end)
			if ok and loaded ~= nil then
				local track = loaded :: AnimationTrack
				local trackConfiguration = Configuration.AnimationTracks[state]
				track.Name = "PoolFoam_" .. state .. "_" .. tostring(slot.SlotIndex)
				track.Looped = trackConfiguration.Looped
				track.Priority = trackConfiguration.Priority
				table.insert(bank, {
					Track = track,
					State = state,
					SlotIndex = slot.SlotIndex,
					AnimationId = slot.AnimationId,
				})
			else
				animation:Destroy()
				warn(string.format("Pool Foam could not load %s animation slot %d for %s",
					state, slot.SlotIndex, self._slot.Id))
			end
		end
		self._trackBanks[state] = bank
	end
end

function AnimationAdapter:_applyProxyVisual(state: string)
	local visualConfiguration = Configuration.ProxyVisualStates[state]
	if visualConfiguration == nil then
		return
	end

	for part, base in self._proxyVisuals do
		if part.Parent ~= nil then
			part.Color = base.Color:Lerp(visualConfiguration.Tint, visualConfiguration.Blend)
			part.Transparency = math.clamp(
				base.Transparency + visualConfiguration.TransparencyAdd,
				0,
				0.95
			)
		end
	end
end

function AnimationAdapter:_resolvedTrackState(state: string): string
	local bank = self._trackBanks[state]
	if bank ~= nil and #bank > 0 then
		return state
	end
	-- Hunt reuses the selected Walk bank without stopping/restarting, so a
	-- phase change or observation release cannot snap the held pose.
	local walkBank = self._trackBanks.Walk
	if state == "Hunt" and walkBank ~= nil and #walkBank > 0 then
		return "Walk"
	end
	return state
end

function AnimationAdapter:_chooseRecord(trackState: string): any?
	local bank = self._trackBanks[trackState]
	if bank == nil or #bank == 0 then return nil end
	if #bank == 1 then
		self._lastVariantByState[trackState] = bank[1].SlotIndex
		return bank[1]
	end
	local previousSlot = self._lastVariantByState[trackState]
	local choices = {}
	for _, record in bank do
		if record.SlotIndex ~= previousSlot then table.insert(choices, record) end
	end
	if #choices == 0 then choices = bank end
	local selected = choices[self._random:NextInteger(1, #choices)]
	self._lastVariantByState[trackState] = selected.SlotIndex
	return selected
end

function AnimationAdapter:_publishActiveRecord(record: any?)
	self._activeRecord = record
	self._model:SetAttribute(Configuration.Attributes.AnimationVariant or "PoolFoamAnimationVariant",
		record and record.SlotIndex or nil)
	self._model:SetAttribute(Configuration.Attributes.AnimationAssetId or "PoolFoamAnimationAssetId",
		record and record.AnimationId or nil)
end

function AnimationAdapter:_applyPlaybackSpeed(state: string)
	local record = self._activeRecord
	local track = record and record.Track
	if track == nil or not track.IsPlaying then return end
	local trackConfiguration = Configuration.AnimationTracks[state]
		or Configuration.AnimationTracks[record.State]
	local speed = self._paused and 0 or trackConfiguration.Speed
	pcall(function() track:AdjustSpeed(speed) end)
end

function AnimationAdapter:_applyState(state: string, forceRestart: boolean?)
	if self._destroyed then return end

	local restart = forceRestart == true
	local targetTrackState = self:_resolvedTrackState(state)
	if self._state == state and not restart then
		self:_applyPlaybackSpeed(state)
		self._model:SetAttribute(Configuration.Attributes.ResolvedAnimationState, state)
		self:_applyProxyVisual(state)
		return
	end

	-- Walk and a Hunt fallback resolve to the same bank and must retain the
	-- exact selected clip/time. A genuine exit and later re-entry chooses a
	-- fresh non-repeating variant; repeated heartbeat SetState calls do not.
	local targetRecord = nil
	if not restart and self._activeRecord ~= nil
		and self._activeRecord.State == targetTrackState
	then
		targetRecord = self._activeRecord
	else
		targetRecord = self:_chooseRecord(targetTrackState)
	end

	for _, bank in self._trackBanks do
		for _, record in bank do
			if record ~= targetRecord and record.Track.IsPlaying then
				local previousConfiguration = Configuration.AnimationTracks[record.State]
				pcall(function() record.Track:Stop(previousConfiguration.Fade) end)
			end
		end
	end

	self:_publishActiveRecord(targetRecord)
	if targetRecord ~= nil then
		local track = targetRecord.Track
		local trackConfiguration = Configuration.AnimationTracks[state]
			or Configuration.AnimationTracks[targetRecord.State]
		pcall(function()
			if restart and track.IsPlaying then track:Stop(0) end
			if restart or not track.IsPlaying then
				track:Play(trackConfiguration.Fade, 1,
					self._paused and 0 or trackConfiguration.Speed)
			end
		end)
	end

	self._state = state
	self:_applyPlaybackSpeed(state)
	self._model:SetAttribute(Configuration.Attributes.ResolvedAnimationState, state)
	self:_applyProxyVisual(state)
end

function AnimationAdapter.new(model: Model, slot: any?)
	assert(typeof(model) == "Instance" and model:IsA("Model"), "AnimationAdapter.new expects a Model")

	local self = setmetatable({}, AnimationAdapter)
	self._model = model
	self._slot = resolveSlot(model, slot)
	-- Start outside the public state set so the first Refresh always enters the
	-- resolved state and starts its track. Initializing this to "Idle" caused
	-- _applyState to take its same-state fast path, leaving an authored Idle
	-- animation loaded but never played.
	self._state = ""
	self._trackBanks = {}
	self._lastVariantByState = {}
	self._random = Random.new(randomSeedForModel(model))
	self._activeRecord = nil
	self._connections = {}
	self._proxyVisuals = captureProxyVisuals(model)
	self._animator = nil
	self._createdAnimator = nil
	self._assetFolder = nil
	self._createdController = nil
	self._destroyed = false
	self._writingStateAttribute = false
	self._paused = false
	model:SetAttribute(Configuration.Attributes.AnimationPaused or "PoolFoamAnimationPaused", false)

	self:_loadTracks()

	table.insert(self._connections, model:GetAttributeChangedSignal(Configuration.Attributes.AnimationState):Connect(function()
		if self._writingStateAttribute or self._destroyed then
			return
		end
		local state = canonicalState(model:GetAttribute(Configuration.Attributes.AnimationState), false)
		if state ~= nil then
			self:_applyState(state, false)
		else
			self:Refresh(false)
		end
	end))

	table.insert(self._connections, model:GetAttributeChangedSignal(Configuration.Attributes.MotionState):Connect(function()
		if self._destroyed then
			return
		end
		local state = canonicalState(model:GetAttribute(Configuration.Attributes.MotionState), true)
		if state ~= nil then
			self:_applyState(state, false)
		end
	end))

	table.insert(self._connections, model:GetAttributeChangedSignal(Configuration.Attributes.ActionSerial):Connect(function()
		self:_applyState(self._state, true)
	end))

	table.insert(self._connections, model:GetAttributeChangedSignal(Configuration.Attributes.Slot):Connect(function()
		if self._destroyed then
			return
		end
		self._slot = resolveSlot(model, nil)
		self:_loadTracks()
		self:_applyState(self._state, true)
	end))

	table.insert(self._connections, model.Destroying:Connect(function()
		self:Destroy()
	end))

	self:Refresh(false)
	return self
end

function AnimationAdapter:GetState(): string
	return self._state
end

function AnimationAdapter:IsPaused(): boolean
	return self._paused == true
end

function AnimationAdapter:SetPaused(value: any): boolean
	if self._destroyed then return false end
	local paused = value == true
	self._paused = paused
	self._model:SetAttribute(Configuration.Attributes.AnimationPaused or "PoolFoamAnimationPaused", paused)
	self:_applyPlaybackSpeed(self._state)
	return true
end

function AnimationAdapter:SetState(value: any, forceRestart: boolean?): boolean
	local state = canonicalState(value, true)
	if state == nil or self._destroyed then
		return false
	end

	self._writingStateAttribute = true
	self._model:SetAttribute(Configuration.Attributes.AnimationState, state)
	self._writingStateAttribute = false
	self:_applyState(state, forceRestart)
	return true
end

function AnimationAdapter:Refresh(forceRestart: boolean?): string
	if self._destroyed then
		return self._state
	end

	local state = canonicalState(
		self._model:GetAttribute(Configuration.Attributes.AnimationState),
		false
	)
	if state == nil then
		state = canonicalState(self._model:GetAttribute(Configuration.Attributes.MotionState), true)
	end
	state = state or "Idle"
	self:_applyState(state, forceRestart)
	return state
end

function AnimationAdapter:GetDebugSnapshot()
	local record = self._activeRecord
	local track = record and record.Track
	local timePosition, length, playbackSpeed, isPlaying = 0, 0, 0, false
	if track ~= nil then
		pcall(function()
			timePosition = track.TimePosition
			length = track.Length
			playbackSpeed = track.Speed
			isPlaying = track.IsPlaying
		end)
	end
	return {
		State = self._state,
		Paused = self._paused == true,
		TrackState = record and record.State or nil,
		VariantIndex = record and record.SlotIndex or nil,
		AnimationId = record and record.AnimationId or nil,
		TimePosition = timePosition,
		Length = length,
		PlaybackSpeed = playbackSpeed,
		IsPlaying = isPlaying,
	}
end

function AnimationAdapter:Destroy()
	if self._destroyed then
		return
	end
	self._destroyed = true
	self._paused = false
	if self._model and self._model.Parent then
		self._model:SetAttribute(Configuration.Attributes.AnimationPaused or "PoolFoamAnimationPaused", false)
	end

	disconnectAll(self._connections)
	self:_destroyTracks()

	for part, base in self._proxyVisuals do
		if part.Parent ~= nil then
			part.Color = base.Color
			part.Transparency = base.Transparency
		end
	end
	table.clear(self._proxyVisuals)

	if self._createdController ~= nil and self._createdController.Parent ~= nil then
		self._createdController:Destroy()
	end
	self._createdController = nil

	-- If the rig already supplied a Humanoid or AnimationController but lacked
	-- an Animator, remove the Animator this adapter added. An Animator beneath
	-- a controller we created is already removed with that controller.
	if self._createdAnimator ~= nil and self._createdAnimator.Parent ~= nil then
		self._createdAnimator:Destroy()
	end
	self._createdAnimator = nil
	self._animator = nil
end

AnimationAdapter.Attach = AnimationAdapter.new

return table.freeze(AnimationAdapter)
