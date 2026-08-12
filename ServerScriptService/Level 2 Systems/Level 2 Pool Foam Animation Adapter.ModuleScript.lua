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
	for _, track in self._tracks do
		pcall(function()
			track:Stop(0)
			track:Destroy()
		end)
	end
	table.clear(self._tracks)

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
		local animationId = normalizedAnimationId(ids[state])
		if animationId ~= nil then
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
			animation.Name = state
			animation.AnimationId = animationId
			animation.Parent = self._assetFolder

			local ok, loaded = pcall(function()
				return animator:LoadAnimation(animation)
			end)
			if ok and loaded ~= nil then
				local track = loaded :: AnimationTrack
				local trackConfiguration = Configuration.AnimationTracks[state]
				track.Name = "PoolFoam_" .. state
				track.Looped = trackConfiguration.Looped
				track.Priority = trackConfiguration.Priority
				self._tracks[state] = track
			else
				animation:Destroy()
				warn(string.format("Pool Foam could not load %s animation for %s", state, self._slot.Id))
			end
		end
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
	if self._tracks[state] ~= nil then
		return state
	end
	-- The current final rig has one locomotion clip. Hunt intentionally reuses
	-- Walk without stopping/restarting, so a phase change cannot snap its pose.
	if state == "Hunt" and self._tracks.Walk ~= nil then
		return "Walk"
	end
	return state
end

function AnimationAdapter:_applyPlaybackSpeed(state: string)
	local trackState = self:_resolvedTrackState(state)
	local track = self._tracks[trackState]
	if track == nil or not track.IsPlaying then return end
	local trackConfiguration = Configuration.AnimationTracks[state]
		or Configuration.AnimationTracks[trackState]
	local speed = self._paused and 0 or trackConfiguration.Speed
	pcall(function() track:AdjustSpeed(speed) end)
end

function AnimationAdapter:_applyState(state: string, forceRestart: boolean?)
	if self._destroyed then
		return
	end

	local restart = forceRestart == true
	local targetTrackState = self:_resolvedTrackState(state)
	if self._state == state and not restart then
		self:_applyPlaybackSpeed(state)
		self._model:SetAttribute(Configuration.Attributes.ResolvedAnimationState, state)
		self:_applyProxyVisual(state)
		return
	end

	for trackState, track in self._tracks do
		if trackState ~= targetTrackState and track.IsPlaying then
			local previousConfiguration = Configuration.AnimationTracks[trackState]
			pcall(function()
				track:Stop(previousConfiguration.Fade)
			end)
		end
	end

	local track = self._tracks[targetTrackState]
	if track ~= nil then
		local trackConfiguration = Configuration.AnimationTracks[state]
			or Configuration.AnimationTracks[targetTrackState]
		pcall(function()
			if restart and track.IsPlaying then
				track:Stop(0)
			end
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
	self._tracks = {}
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
