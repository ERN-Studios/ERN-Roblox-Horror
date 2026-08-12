-- Level 2 Pool Foam Observer
--
-- Receives camera telemetry, never client visibility claims. The server checks
-- report freshness, player state, camera origin, frustum and world occlusion.
-- Observation is conservative: a valid camera OR the character's server-known
-- head view freezes the entity, and any living observer freezes multiplayer
-- movement.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Observer = {}
Observer.__index = Observer

local PROTOCOL = 1
local REMOTE_FOLDER_NAME = "Level 2 Pool Foam Remotes"
local CLIENT_REPORT_NAME = "ClientReport"
local CLIENT_EVENT_NAME = "ClientEvent"

local DEFAULTS = table.freeze({
	MinReportInterval = 0.045,
	ReportMaxAge = 0.45,
	MaxCameraDistance = 18,
	MinimumFieldOfView = 35,
	MaximumFieldOfView = 100,
	MaximumObserveDistance = 185,
	ServerFallbackFieldOfView = 105,
	OcclusionEpsilon = 0.12,
	MinimumViewportAxis = 64,
	MaximumViewportAxis = 16384,
})

local function finiteNumber(value)
	return typeof(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function finiteVector2(value)
	return typeof(value) == "Vector2" and finiteNumber(value.X) and finiteNumber(value.Y)
end

local function finiteVector3(value)
	return typeof(value) == "Vector3"
		and finiteNumber(value.X)
		and finiteNumber(value.Y)
		and finiteNumber(value.Z)
end

local function finiteCFrame(value)
	if typeof(value) ~= "CFrame" then return false end
	for _, component in ipairs({value:GetComponents()}) do
		if not finiteNumber(component) then return false end
	end
	return true
end

local function readNumber(source, key, fallback, minimum, maximum)
	local value = source and source[key]
	if not finiteNumber(value) then value = fallback end
	if minimum then value = math.max(minimum, value) end
	if maximum then value = math.min(maximum, value) end
	return value
end

local function findOrCreate(parent, className, name)
	local existing = parent:FindFirstChild(name)
	if existing then
		if existing.ClassName ~= className then
			return nil, ("%s.%s must be a %s, found %s"):format(parent:GetFullName(), name, className, existing.ClassName)
		end
		return existing
	end
	local instance = Instance.new(className)
	instance.Name = name
	instance.Parent = parent
	return instance
end

function Observer.EnsureRemotes()
	local folder, folderError = findOrCreate(ReplicatedStorage, "Folder", REMOTE_FOLDER_NAME)
	if not folder then return nil, nil, nil, folderError end
	local report, reportError = findOrCreate(folder, "RemoteEvent", CLIENT_REPORT_NAME)
	if not report then return nil, nil, nil, reportError end
	local event, eventError = findOrCreate(folder, "RemoteEvent", CLIENT_EVENT_NAME)
	if not event then return nil, nil, nil, eventError end
	return folder, report, event, nil
end

local function livingRoundCharacter(player)
	if player.Parent ~= Players
		or player:GetAttribute("InRound") ~= true
		or player:GetAttribute("Escaped") == true
		or player:GetAttribute("Spectating") == true
		or player:GetAttribute("IsSpectating") == true
		or workspace:GetAttribute("SelectedLevel") ~= 2
		or workspace:GetAttribute("RoundActive") ~= true
	then
		return nil
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local head = character and character:FindFirstChild("Head")
	if not (character and humanoid and humanoid.Health > 0 and root and root:IsA("BasePart")) then
		return nil
	end
	if not (head and head:IsA("BasePart")) then head = root end
	return character, humanoid, root, head
end

local function targetSamples(target, radius)
	if typeof(target) == "Vector3" then
		local r = math.max(0, tonumber(radius) or 0)
		if r < 0.05 then return {target} end
		return {
			target,
			target + Vector3.new(0, r, 0),
			target + Vector3.new(r, 0, 0),
			target - Vector3.new(r, 0, 0),
		}
	end
	if not (target and target:IsA("Model") and target.Parent) then return {} end
	local boundsCFrame, boundsSize = target:GetBoundingBox()
	local x = math.min(boundsSize.X * 0.35, 3.5)
	local y = math.min(boundsSize.Y * 0.42, 5)
	return {
		boundsCFrame.Position,
		boundsCFrame.Position + Vector3.new(0, y, 0),
		boundsCFrame.Position - Vector3.new(0, y * 0.55, 0),
		boundsCFrame.Position + boundsCFrame.RightVector * x,
		boundsCFrame.Position - boundsCFrame.RightVector * x,
	}
end

local function inFrustum(cameraCFrame, verticalFov, viewport, point, maximumDistance)
	local localPoint = cameraCFrame:PointToObjectSpace(point)
	local depth = -localPoint.Z
	if depth <= 0.05 then return false end
	if (point - cameraCFrame.Position).Magnitude > maximumDistance then return false end
	local aspect = math.clamp(viewport.X / math.max(1, viewport.Y), 0.4, 4)
	local verticalTangent = math.tan(math.rad(verticalFov * 0.5))
	local horizontalTangent = verticalTangent * aspect
	return math.abs(localPoint.X) <= depth * horizontalTangent
		and math.abs(localPoint.Y) <= depth * verticalTangent
end

local function visibleByRay(origin, point, character, targetModel, exclusions, epsilon)
	local offset = point - origin
	if offset.Magnitude <= epsilon then return true end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	-- Terrain water is transparent for gameplay sight. It must not make a
	-- clearly visible foam entity appear occluded to the server.
	params.IgnoreWater = true
	local filter = {character}
	for _, instance in ipairs(exclusions) do
		if instance and instance.Parent then table.insert(filter, instance) end
	end
	params.FilterDescendantsInstances = filter
	local result = workspace:Raycast(origin, offset, params)
	if not result then return true end
	return targetModel ~= nil and result.Instance:IsDescendantOf(targetModel)
end

function Observer.new(manifest, generation, tuning)
	assert(manifest and manifest.World, "Pool Foam Observer requires manifest.World")
	assert(typeof(generation) == "number", "Pool Foam Observer requires a numeric generation")
	tuning = typeof(tuning) == "table" and tuning or {}
	local folder, reportRemote, eventRemote, remoteError = Observer.EnsureRemotes()
	assert(folder and reportRemote and eventRemote, "Pool Foam Observer remote setup failed: " .. tostring(remoteError))

	folder:SetAttribute("Protocol", PROTOCOL)
	folder:SetAttribute("Generation", generation)
	reportRemote:SetAttribute("Protocol", PROTOCOL)
	reportRemote:SetAttribute("Generation", generation)

	local exclusions = {}
	if manifest.EntityNodes then table.insert(exclusions, manifest.EntityNodes) end
	local navigation = manifest.World:FindFirstChild("Level 2 Navigation", true)
	if navigation then table.insert(exclusions, navigation) end

	local self = setmetatable({
		Manifest = manifest,
		Generation = generation,
		Folder = folder,
		ClientReport = reportRemote,
		ClientEvent = eventRemote,
		Tuning = {
			MinReportInterval = readNumber(tuning, "MinReportInterval",
				readNumber(tuning, "ReportInterval", DEFAULTS.MinReportInterval), 0.025, 1),
			ReportMaxAge = readNumber(tuning, "ReportMaxAge",
				readNumber(tuning, "ReportTimeout", DEFAULTS.ReportMaxAge), 0.1, 3),
			MaxCameraDistance = readNumber(tuning, "MaxCameraDistance",
				readNumber(tuning, "MaximumCameraOriginError", DEFAULTS.MaxCameraDistance), 3, 60),
			MinimumFieldOfView = readNumber(tuning, "MinimumFieldOfView", DEFAULTS.MinimumFieldOfView, 15, 80),
			MaximumFieldOfView = readNumber(tuning, "MaximumFieldOfView",
				readNumber(tuning, "BroadPhaseFovDegrees", DEFAULTS.MaximumFieldOfView), 60, 120),
			MaximumObserveDistance = readNumber(tuning, "MaximumObserveDistance",
				readNumber(tuning, "MaximumReportDistance", DEFAULTS.MaximumObserveDistance), 20, 600),
			ServerFallbackFieldOfView = readNumber(tuning, "ServerFallbackFieldOfView",
				readNumber(tuning, "ObservedFovDegrees", DEFAULTS.ServerFallbackFieldOfView), 60, 130),
			OcclusionEpsilon = readNumber(tuning, "OcclusionEpsilon", DEFAULTS.OcclusionEpsilon, 0, 2),
			MinimumViewportAxis = readNumber(tuning, "MinimumViewportAxis", DEFAULTS.MinimumViewportAxis, 1, 1000),
			MaximumViewportAxis = readNumber(tuning, "MaximumViewportAxis", DEFAULTS.MaximumViewportAxis, 1000, 32768),
		},
		Reports = {},
		Attempts = {},
		Connections = {},
		Exclusions = exclusions,
		Destroyed = false,
		Stats = {
			Accepted = 0,
			Rejected = 0,
			RejectReasons = {},
			VisibilityChecks = 0,
		},
	}, Observer)

	-- Edit-mode smoke tests can construct the observer and its remotes, but
	-- RemoteEvent.OnServerEvent is only legal in a live server data model.
	if RunService:IsRunning() and RunService:IsServer() then
		table.insert(self.Connections, reportRemote.OnServerEvent:Connect(function(player, payload)
			self:_consume(player, payload)
		end))
	end
	table.insert(self.Connections, Players.PlayerRemoving:Connect(function(player)
		self.Reports[player] = nil
		self.Attempts[player] = nil
	end))
	return self
end

function Observer:_reject(reason)
	self.Stats.Rejected += 1
	local reasons = self.Stats.RejectReasons
	reasons[reason] = (reasons[reason] or 0) + 1
end

function Observer:_consume(player, payload)
	if self.Destroyed then return end
	local now = os.clock()
	local previous = self.Reports[player]
	local lastAttempt = self.Attempts[player]
	if lastAttempt and now - lastAttempt < self.Tuning.MinReportInterval then
		self:_reject("RATE")
		return
	end
	-- A rejected early packet must not move the throttle window forward; doing
	-- so can lock a normal fixed-rate client into permanent RATE rejection.
	self.Attempts[player] = now
	if typeof(payload) ~= "table" then self:_reject("PAYLOAD") return end
	if payload.Protocol ~= PROTOCOL then self:_reject("PROTOCOL") return end
	if payload.Generation ~= self.Generation then self:_reject("GENERATION") return end

	local sequence = payload.Sequence
	if not finiteNumber(sequence) or sequence < 0 or sequence % 1 ~= 0 then self:_reject("SEQUENCE") return end
	if previous and sequence <= previous.Sequence then self:_reject("ORDER") return end
	local character, _, _, head = livingRoundCharacter(player)
	if not character then self:_reject("PLAYER") return end

	local cameraCFrame = payload.CameraCFrame
	local fieldOfView = payload.FieldOfView
	local viewport = payload.ViewportSize
	if not finiteCFrame(cameraCFrame) then self:_reject("CAMERA") return end
	if not finiteNumber(fieldOfView)
		or fieldOfView < self.Tuning.MinimumFieldOfView
		or fieldOfView > self.Tuning.MaximumFieldOfView
	then
		self:_reject("FOV")
		return
	end
	if not finiteVector2(viewport)
		or viewport.X < self.Tuning.MinimumViewportAxis
		or viewport.Y < self.Tuning.MinimumViewportAxis
		or viewport.X > self.Tuning.MaximumViewportAxis
		or viewport.Y > self.Tuning.MaximumViewportAxis
	then
		self:_reject("VIEWPORT")
		return
	end
	if (cameraCFrame.Position - head.Position).Magnitude > self.Tuning.MaxCameraDistance then
		self:_reject("ORIGIN")
		return
	end

	self.Reports[player] = {
		Sequence = sequence,
		CameraCFrame = cameraCFrame,
		FieldOfView = fieldOfView,
		ViewportSize = viewport,
		ReceivedAt = now,
	}
	self.Stats.Accepted += 1
end

function Observer:_viewSees(character, cameraCFrame, fieldOfView, viewport, samples, targetModel)
	for _, point in ipairs(samples) do
		if inFrustum(cameraCFrame, fieldOfView, viewport, point, self.Tuning.MaximumObserveDistance)
			and visibleByRay(cameraCFrame.Position, point, character, targetModel, self.Exclusions, self.Tuning.OcclusionEpsilon)
		then
			return true
		end
	end
	return false
end

function Observer:_playerSees(player, samples, targetModel, now)
	local character, _, _, head = livingRoundCharacter(player)
	if not character then return false end
	local report = self.Reports[player]
	if report and now - report.ReceivedAt <= self.Tuning.ReportMaxAge
		and (report.CameraCFrame.Position - head.Position).Magnitude <= self.Tuning.MaxCameraDistance
	then
		-- A fresh, validated report represents the actual player camera. The
		-- server/head view is only a stale-report fallback; OR-ing the two would
		-- freeze a statue when the camera is legitimately turned away.
		return self:_viewSees(
			character,
			report.CameraCFrame,
			report.FieldOfView,
			report.ViewportSize,
			samples,
			targetModel
		)
	end
	-- Missing/stale telemetry degrades conservatively to a server-known view.
	return self:_viewSees(
		character,
		head.CFrame,
		self.Tuning.ServerFallbackFieldOfView,
		Vector2.new(16, 9),
		samples,
		targetModel
	)
end

function Observer:_observe(target, radius)
	if self.Destroyed then return false, {} end
	local samples = targetSamples(target, radius)
	if #samples == 0 then return false, {} end
	local targetModel = typeof(target) == "Instance" and target:IsA("Model") and target or nil
	local observers = {}
	local now = os.clock()
	self.Stats.VisibilityChecks += 1
	for _, player in ipairs(Players:GetPlayers()) do
		if self:_playerSees(player, samples, targetModel, now) then
			table.insert(observers, player)
		end
	end
	return #observers > 0, observers
end

function Observer:IsModelObserved(model, radius)
	if not (model and model:IsA("Model")) then return false, {} end
	return self:_observe(model, radius)
end

function Observer:IsPositionObserved(position, radius)
	if not finiteVector3(position) then return false, {} end
	return self:_observe(position, radius)
end

function Observer:GetDebugSnapshot()
	local reports = {}
	local now = os.clock()
	for player, report in pairs(self.Reports) do
		if player.Parent == Players then
			table.insert(reports, {
				UserId = player.UserId,
				Sequence = report.Sequence,
				Age = now - report.ReceivedAt,
				Fresh = now - report.ReceivedAt <= self.Tuning.ReportMaxAge,
			})
		end
	end
	table.sort(reports, function(a, b) return a.UserId < b.UserId end)
	local rejectReasons = {}
	for reason, count in pairs(self.Stats.RejectReasons) do rejectReasons[reason] = count end
	return {
		Protocol = PROTOCOL,
		Generation = self.Generation,
		Accepted = self.Stats.Accepted,
		Rejected = self.Stats.Rejected,
		RejectReasons = rejectReasons,
		VisibilityChecks = self.Stats.VisibilityChecks,
		Reports = reports,
	}
end

function Observer:Destroy()
	if self.Destroyed then return end
	self.Destroyed = true
	for _, connection in ipairs(self.Connections) do connection:Disconnect() end
	table.clear(self.Connections)
	table.clear(self.Reports)
	table.clear(self.Attempts)
	if self.Folder and self.Folder:GetAttribute("Generation") == self.Generation then
		self.Folder:SetAttribute("Generation", 0)
		self.ClientReport:SetAttribute("Generation", 0)
	end
	self.Manifest = nil
	self.ClientReport = nil
	self.ClientEvent = nil
	self.Folder = nil
end

Observer.Protocol = PROTOCOL
Observer.RemoteFolderName = REMOTE_FOLDER_NAME
Observer.ClientReportName = CLIENT_REPORT_NAME
Observer.ClientEventName = CLIENT_EVENT_NAME

return Observer
