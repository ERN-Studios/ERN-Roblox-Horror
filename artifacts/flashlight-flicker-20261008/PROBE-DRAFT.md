# Probeudkast, kun offline-tekstbilag

Ikke kørt i Roblox. Midlertidige .luau-filer er ryddet; dette bilag bevarer det kompilerede design til frisk gennemgang under en senere Studio-lås. Ingen permanent probe er installeret.

## bounded-frame-probe.luau

SHA256: `25c4824aa5efaabaf4e325f249c6c16a85032d59e77a8b169ce6546b7662f240`

```luau
-- DRAFT: one bounded Client execute_luau call, not a persistent runtime script.
-- Run only for the granted Studio-lock holder. No services/scripts are created.
-- Sampling happens AFTER MongoFlashlight (Camera + 2). All callbacks are removed
-- before this call ends. Save the complete returned JSON string to disk.
-- Observer mode is default. The optional Scriptable sweep restores the camera.
local config = {
	Label = "L1-PC-own-wall-near-before",
	DeviceLabel = "PC", -- explicitly record the real emulator chosen in Studio
	Duration = 8, -- must remain <= 10 (MCP calls must stay below 18 seconds)
	MaxFrames = 1800, -- bounded at 300 fps; capped captures are marked incomplete
	Sweep = false,
	SweepYawDegrees = 60, -- center->left->center->right->center; one cycle
	SweepPitchDegrees = 0,
	ClipJumpStuds = 0.15,
	StationaryEyeStepStuds = 0.02,
	StationaryRawStepStuds = 0.05,
	MaxMates = 1,
}
assert(config.Duration > 0 and config.Duration <= 10, "duration outside bounded range")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local player = assert(Players.LocalPlayer, "Client datamodel required")
local camera = assert(workspace.CurrentCamera, "No current camera")
-- A runtime clone comes from the actual Play session, not the offline mirror.
local liveController = assert(player:FindFirstChild("PlayerScripts")
	and player.PlayerScripts:FindFirstChild("FlashlightController"), "Live controller not found")
assert(liveController:IsA("LocalScript"), "Live controller has unexpected class")
local sourceOk, liveSource = pcall(function() return liveController.Source end)
assert(sourceOk, "Live Source inaccessible; use a fresh scoped source audit before adapting probe")
assert(tonumber(liveSource:match("local%s+HAND_SIDE%s*=%s*([%-%d%.]+)")) == .25,
	"Fresh live HAND_SIDE differs; reconcile probe first")
assert(tonumber(liveSource:match("local%s+HAND_DOWN%s*=%s*([%-%d%.]+)")) == -.25,
	"Fresh live HAND_DOWN differs; reconcile probe first")
assert(tonumber(liveSource:match("local%s+HAND_FORWARD%s*=%s*([%-%d%.]+)")) == .3,
	"Fresh live HAND_FORWARD differs; reconcile probe first")
assert(liveSource:find("mount.CFrame = aimCF.Rotation + handPos", 1, true)
	and liveSource:find("math.max((hit.Position - eye).Magnitude - 0.3, 0)", 1, true),
	"Fresh live origin assignment/clipping differs; reconcile probe first")
local oldCameraType, oldCameraCF = camera.CameraType, camera.CFrame
local samplerName, driverName = "MongoFlashlightFlickerProbe", "MongoFlashlightFlickerSweep"
local rows, lights, lightIds, originIds, origins, hitIds, hits = {}, {}, {}, {}, {}, {}, {}
local summaries = {ClipJumps = 0, AllOriginResidualJumps = 0, ExcludedOriginResidualJumps = 0,
	EnabledEdges = 0, PropertyEdges = 0, MissingMountFrames = 0,
	MaxClipDelta = 0, MaxResidualDelta = 0, MaxCameraDelta = 0, MaxActualDelta = 0, MaxRawDelta = 0,
	MaxReconstructionError = 0, HitSwitches = 0}
local errors, previous, frames, started = {}, nil, 0, time()
local connections, addedCount, removedCount = {}, 0, 0
local ray = RaycastParams.new()
ray.FilterType = Enum.RaycastFilterType.Exclude
local matePlayers = {}
for _, mate in ipairs(Players:GetPlayers()) do
	if mate ~= player and #matePlayers < config.MaxMates then
		table.insert(matePlayers, mate)
	end
end
local function vector(v) return {v.X, v.Y, v.Z} end
local function cf(value) return {value:GetComponents()} end
local function safeProperty(item, key)
	local ok, value = pcall(function() return item[key] end)
	return ok and tostring(value) or "restricted"
end
local function identifyHit(item)
	if not item then return 0 end
	if hitIds[item] then return hitIds[item] end
	local id = #hits + 1
	hitIds[item] = id
	hits[id] = {Path = item:GetFullName(), Class = item.ClassName,
		Material = safeProperty(item, "Material"), Transparency = safeProperty(item, "Transparency"),
		CanCollide = safeProperty(item, "CanCollide"), CanQuery = safeProperty(item, "CanQuery"),
		CastShadow = safeProperty(item, "CastShadow"), RenderFidelity = safeProperty(item, "RenderFidelity"),
		AncestryEdges = 0, DetachedEdges = 0}
	table.insert(connections, item.AncestryChanged:Connect(function(_, parent)
		hits[id].AncestryEdges += 1
		if not parent then hits[id].DetachedEdges += 1 end
	end))
	return id
end
local function originId(item, role)
	if originIds[item] then return originIds[item] end
	local id = #origins + 1
	originIds[item] = id
	origins[id] = {Role = role, Path = item:GetFullName(), Class = item.ClassName}
	return id
end
local function sampleChildren(parent, role, lightRows, originRows)
	if not parent then return end
	local oid = originId(parent, role)
	table.insert(originRows, {oid, cf(parent.CFrame)})
	for _, item in ipairs(parent:GetChildren()) do
		if item:IsA("Light") then
			local lid = lightIds[item]
			if not lid then
				lid = #lights + 1
				lightIds[item] = lid
				lights[lid] = {OriginId = oid, Path = item:GetFullName(), Name = item.Name,
					Class = item.ClassName, Face = safeProperty(item, "Face"), Role = role,
					FirstFrame = frames,
					InitialBrightness = item.Brightness, InitialRange = item.Range,
					InitialAngle = item:IsA("SpotLight") and item.Angle or false,
					InitialShadows = item.Shadows}
			end
			table.insert(lightRows, {lid, item.Enabled, item.Brightness, item.Range,
				item:IsA("SpotLight") and item.Angle or false, item.Shadows})
		end
	end
end
local function snapshotState()
	local char = player.Character
	local flag = char and char:FindFirstChild("FlashlightOn")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return {player:GetAttribute("SpectateBattery") or false,
		player:GetAttribute("DevUnlimited") == true, flag and flag.Value == true or false,
		char and char:GetAttribute("FlashlightFocused") == true or false,
		player:GetAttribute("InRound") == true, player:GetAttribute("Level2NewMapPreview") == true,
		player:GetAttribute("Spectating") == true, workspace:GetAttribute("SelectedLevel") or false,
		workspace:GetAttribute("Level3BlackoutActive") == true, hum and hum.Health or 0}
end
local function sample(dt)
	frames += 1
	local t = time() - started
	local currentCamera = workspace.CurrentCamera
	if currentCamera ~= camera then error("CurrentCamera replaced during capture") end
	local mount = workspace:FindFirstChild("FlashlightMount")
	if not mount then summaries.MissingMountFrames += 1 end
	local lightRows, originRows, shaftRows = {}, {}, {}
	sampleChildren(mount, "own", lightRows, originRows)
	sampleChildren(workspace:FindFirstChild("ReplicatedFlashlight_" .. player.UserId),
		"self-replicated", lightRows, originRows)
	for _, mate in ipairs(matePlayers) do
		local char = mate.Character
		local head = char and char:FindFirstChild("Head")
		sampleChildren(head, "mate-head-" .. mate.UserId, lightRows, originRows)
		sampleChildren(workspace:FindFirstChild("ReplicatedFlashlight_" .. mate.UserId),
			"mate-replicated-" .. mate.UserId, lightRows, originRows)
		local a0 = head and head:FindFirstChild("MateBeamA0")
		local a1 = char and workspace.Terrain:FindFirstChild("MateBeamA1_" .. char.Name)
		local shaft = a1 and a1:FindFirstChild("MateBeamShaft")
		if a0 and a1 then
			table.insert(shaftRows, {mate.UserId, vector(a0.WorldPosition), vector(a1.WorldPosition),
				shaft and shaft.Enabled == true or false})
		end
	end
	local eye, raw, actual, clip, hitId, reconstructionError = currentCamera.CFrame.Position, nil, nil, 0, 0, 0
	if mount then
		-- Exact reconstruction of current source constants/formula, not a proposed fix.
		-- Fresh live-source audit must confirm 0.25/-0.25/0.3 before running.
		local right = mount.CFrame.RightVector
		local flat = Vector3.new(right.X, 0, right.Z)
		flat = flat.Magnitude > .001 and flat.Unit or Vector3.new(1, 0, 0)
		raw = eye + flat * .25 + Vector3.new(0, -.25, 0) + mount.CFrame.LookVector * .3
		actual = mount.Position
		local filter = {currentCamera}
		if player.Character then table.insert(filter, player.Character) end
		ray.FilterDescendantsInstances = filter
		local toHand = raw - eye
		local hit = workspace:Raycast(eye, toHand, ray)
		hitId = identifyHit(hit and hit.Instance)
		local expected = hit and eye + toHand.Unit * math.max((hit.Position-eye).Magnitude-.3, 0) or raw
		reconstructionError = (actual - expected).Magnitude
		clip = (raw - actual).Magnitude
		summaries.MaxReconstructionError = math.max(summaries.MaxReconstructionError, reconstructionError)
	end
	local state = snapshotState()
	local metrics = {0, 0, 0, 0, clip, reconstructionError, hitId, 0}
	if previous then
		metrics[1] = (eye - previous.eye).Magnitude
		if raw and previous.raw then metrics[2] = (raw - previous.raw).Magnitude end
		if actual and previous.actual then metrics[3] = (actual - previous.actual).Magnitude end
		metrics[8] = math.abs(clip - previous.clip)
		if actual and raw and previous.actual and previous.raw then
			metrics[4] = ((actual-raw) - (previous.actual-previous.raw)).Magnitude
		end
		summaries.MaxCameraDelta = math.max(summaries.MaxCameraDelta, metrics[1])
		summaries.MaxRawDelta = math.max(summaries.MaxRawDelta, metrics[2])
		summaries.MaxActualDelta = math.max(summaries.MaxActualDelta, metrics[3])
		summaries.MaxClipDelta = math.max(summaries.MaxClipDelta, metrics[8])
		summaries.MaxResidualDelta = math.max(summaries.MaxResidualDelta, metrics[4])
		if raw and previous.raw and metrics[4] >= config.ClipJumpStuds then
			summaries.AllOriginResidualJumps += 1
			local stable = mount == previous.mount and state[4] == previous.state[4]
				and state[8] == previous.state[8] and state[9] == previous.state[9]
				and state[3] == true and previous.state[3] == true
				and metrics[1] <= config.StationaryEyeStepStuds
				and metrics[2] <= config.StationaryRawStepStuds
			if stable then summaries.ClipJumps += 1 else summaries.ExcludedOriginResidualJumps += 1 end
		end
		if hitId ~= previous.hitId then summaries.HitSwitches += 1 end
		for _, values in ipairs(lightRows) do
			local before = previous.lights[values[1]]
			if before then
				if before[2] ~= values[2] then summaries.EnabledEdges += 1 end
				for i = 3, 6 do
					if before[i] ~= values[i] then summaries.PropertyEdges += 1; break end
				end
			end
		end
	end
	local byId = {}
	for _, values in ipairs(lightRows) do byId[values[1]] = values end
	previous = {eye=eye, raw=raw, actual=actual, clip=clip, hitId=hitId, lights=byId, mount=mount, state=state}
	table.insert(rows, {t, dt, cf(currentCamera.CFrame), mount and cf(mount.CFrame) or false,
		raw and vector(raw) or false, metrics, state, lightRows, originRows, shaftRows,
		{addedCount, removedCount}})
end
local function nearbyShadowLights()
	local entries, descendants = {}, workspace:GetDescendants()
	for _, item in ipairs(descendants) do
		if item:IsA("Light") and item.Shadows then
			local parent, position = item.Parent, nil
			if parent and parent:IsA("BasePart") then position = parent.Position end
			if parent and parent:IsA("Attachment") then position = parent.WorldPosition end
			if position and (position-camera.CFrame.Position).Magnitude <= 120 then
				table.insert(entries, {Path=item:GetFullName(), Class=item.ClassName,
					Position=vector(position), Enabled=item.Enabled, Range=item.Range,
					Brightness=item.Brightness, Angle=item:IsA("SpotLight") and item.Angle or false})
			end
		end
	end
	return {DescendantCount=#descendants, Lights=entries}
end
local function json(value)
	local kind = type(value)
	if kind == "boolean" then return value and "true" or "false" end
	if kind == "number" then
		if value ~= value or math.abs(value) == math.huge then return "null" end
		return tostring(math.round(value * 100000) / 100000)
	end
	if kind == "string" then
		return '"' .. value:gsub('[%z\1-\31\\"]', function(c)
			if c == '"' then return '\\"' end
			if c == '\\' then return '\\\\' end
			return string.format('\\u%04x', string.byte(c))
		end) .. '"'
	end
	if kind == "table" then
		local pieces = {}
		if #value > 0 or next(value) == nil then
			for _, item in ipairs(value) do table.insert(pieces, json(item)) end
			return '[' .. table.concat(pieces, ',') .. ']'
		end
		for key, item in pairs(value) do table.insert(pieces, json(tostring(key)) .. ':' .. json(item)) end
		return '{' .. table.concat(pieces, ',') .. '}'
	end
	return "null"
end
local preScene = nearbyShadowLights()
local ok, failure = pcall(function()
	table.insert(connections, workspace.DescendantAdded:Connect(function() addedCount += 1 end))
	table.insert(connections, workspace.DescendantRemoving:Connect(function() removedCount += 1 end))
	started = time() -- exclude setup scans from the measurement window
	if config.Sweep then
		local state = snapshotState()
		assert(state[10] > 0 and state[7] == false, "Sweep requires living, non-spectating player")
		camera.CameraType = Enum.CameraType.Scriptable
		RunService:BindToRenderStep(driverName, Enum.RenderPriority.Camera.Value + 1, function()
			if #errors > 0 then return end
			local driven, driveError = pcall(function()
				local elapsed = time() - started
				local yaw = math.sin(elapsed / config.Duration * math.pi * 2) * math.rad(config.SweepYawDegrees / 2)
				camera.CFrame = oldCameraCF * CFrame.Angles(math.rad(config.SweepPitchDegrees), yaw, 0)
			end)
			if not driven then table.insert(errors, tostring(driveError)) end
		end)
	end
	RunService:BindToRenderStep(samplerName, Enum.RenderPriority.Camera.Value + 4, function(dt)
		if #errors > 0 or frames >= config.MaxFrames then return end
		local sampled, sampleError = pcall(sample, dt)
		if not sampled then table.insert(errors, tostring(sampleError)) end
	end)
	while time() - started < config.Duration and frames < config.MaxFrames and #errors == 0 do
		task.wait(.05)
	end
end)
-- Finalizer executes even if the setup/wait/sampler failed. No connections survive.
RunService:UnbindFromRenderStep(samplerName)
RunService:UnbindFromRenderStep(driverName)
for _, connection in ipairs(connections) do connection:Disconnect() end
if config.Sweep and workspace.CurrentCamera == camera then
	camera.CFrame, camera.CameraType = oldCameraCF, oldCameraType
end
if not ok then table.insert(errors, tostring(failure)) end
local measuredDuration = rows[#rows] and rows[#rows][1] or 0
local report = {
	Kind = "frame_property_probe_only_not_visual_flicker_verdict", Config = config,
	Complete = #errors == 0 and frames > 0 and frames < config.MaxFrames
		and measuredDuration >= config.Duration*.95 and summaries.MissingMountFrames == 0,
	Errors = errors, FrameCount = frames, Elapsed = time()-started, MeasuredDuration=measuredDuration, Summary = summaries,
	TouchEnabled = UIS.TouchEnabled, ForceTouchUI = workspace:GetAttribute("ForceTouchUI") == true,
	Viewport = {camera.ViewportSize.X, camera.ViewportSize.Y}, StreamingEnabled = safeProperty(workspace, "StreamingEnabled"),
	LiveController = {Path=liveController:GetFullName(), Class=liveController.ClassName, SourceBytes=#liveSource},
	NearbyShadowLightsBefore=preScene, NearbyShadowLightsAfter=nearbyShadowLights(),
	SceneMutationCounts={Added=addedCount, Removed=removedCount},
	RowSchema = {"time", "dt", "cameraCFrame12", "ownCFrame12", "rawHand3", "metrics", "state", "lights", "origins", "mateShafts", "sceneMutationCounts"},
	MetricSchema = {"cameraDelta", "rawDelta", "actualDelta", "originResidualDelta", "clipDistance", "reconstructionError", "hitId", "clipMagnitudeDelta"},
	StateSchema = {"SpectateBatteryProxy", "DevUnlimited", "FlashlightOn", "Focused", "InRound", "L2Preview", "Spectating", "SelectedLevel", "L3Blackout", "Health"},
	LightSchema = {"lightId", "Enabled", "Brightness", "Range", "Angle_or_false", "Shadows"},
	OriginSchema = {"originId", "cFrame12"}, ShaftSchema = {"userId", "start3", "end3", "Enabled"},
	Lights = lights, Origins = origins, Hits = hits, Rows = rows,
}
return json(report)
```

## drift_audit.luau

SHA256: `7178379a94766c504269642c57128f214906cbc0b2a893a9f636e874f497780b`

```luau
-- Read-only. Execute only while Flashlight flicker fix holds the coordinated lock.
assert(game.PlaceId == 131311258779917 and game.GameId == 10559217407, "Unexpected place")
assert(game:GetService("RunService"):IsEdit(), "Fresh baseline requires Edit mode")
local H = game:GetService("HttpService")
local SES = game:GetService("ScriptEditorService")
local paths = {
    {"StarterPlayer", "StarterPlayerScripts", "FlashlightController"},
    {"ServerScriptService", "FlashlightSync"},
    {"ReplicatedStorage", "FlashlightProfiles"},
    {"StarterPlayer", "StarterPlayerScripts", "SpectateController"},
    {"StarterPlayer", "StarterPlayerScripts", "Level 4 Round Client"},
    {"StarterPlayer", "StarterPlayerScripts", "Level 4 Lighting Controller"},
    {"StarterPlayer", "StarterPlayerScripts", "Level 2 Lighting Controller"},
}
local function hash(source)
    local value = 5381
    for i = 1, #source do value = (value * 33 + string.byte(source, i)) % 4294967296 end
    return value
end
local result = {placeId = game.PlaceId, universeId = game.GameId, scripts = {}, properties = {}}
for _, segments in ipairs(paths) do
    local target = game
    for _, segment in ipairs(segments) do target = target and target:FindFirstChild(segment) end
    if target and target:IsA("LuaSourceContainer") then
        local source = target.Source
        local ok, editor = pcall(function() return SES:GetEditorSource(target) end)
        table.insert(result.scripts, {segments = segments, path = target:GetFullName(), className = target.ClassName,
            source = source, sourceBytes = #source, sourceDjb2 = hash(source),
            editorReadable = ok, editorMatches = ok and editor == source,
            editorDjb2 = ok and hash(editor) or nil,
            enabled = target:IsA("BaseScript") and target.Enabled or nil})
    else
        table.insert(result.scripts, {segments = segments, missing = true})
    end
end
for _, item in ipairs({{workspace, "StreamingEnabled"}, {workspace, "StreamingMinRadius"},
    {workspace, "StreamingTargetRadius"}, {game:GetService("Lighting"), "LightingStyle"},
    {game:GetService("Lighting"), "PrioritizeLightingQuality"}, {game:GetService("Lighting"), "Technology"}}) do
    local ok, value = pcall(function() return item[1][item[2]] end)
    result.properties[item[2]] = ok and tostring(value) or "unreadable"
end
return H:JSONEncode(result)
```
