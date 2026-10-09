-- Read-only, root-executed smoke measurement in the actual Client/Server Play DataModel.
-- No fixtures, Instance/source/property writes, gameplay calls or Play transitions.
-- task.wait only spaces observations; CPU times come exclusively from native Stats.
local H = game:GetService("HttpService")
local Run = game:GetService("RunService")
local Stats = game:GetService("Stats")
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
assert(game.PlaceId == 131311258779917 and game.GameId == 10559217407, "Unexpected place/universe")
assert(Run:IsRunning(), "Actual active Play Client/Server required; Edit is not a performance sample")
local IS_CLIENT = Run:IsClient()
local SIDE = if IS_CLIENT then "Client" else "Server"
local WINDOW_SECONDS, SPACING_SECONDS = 3, 0.05
local report = {
	kind = "actual-runtime-stats-smoke-sample", context = SIDE, requestedWindowSeconds = WINDOW_SECONDS,
	requestedSpacingSeconds = SPACING_SECONDS, cpuSource = "Native Stats properties; scheduler wait is not CPU time",
	placeId = game.PlaceId, universeId = game.GameId, verifiedUtc = os.date("!%Y-%m-%dT%H:%M:%SZ"),
	gameplayCoverage = "Current scene only; this sampler does not trigger or verify round objectives",
	performanceComparison = false, fpsClaim = false, mutations = false,
	percentileDefinition = "Median (average middle pair for even n), p95 nearest rank ceil(0.95*n) of spaced native readings",
	sources = {
		"https://create.roblox.com/docs/reference/engine/classes/Stats",
		"https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/Stats.yaml",
		"https://create.roblox.com/docs/reference/engine/enums/DeveloperMemoryTag",
		"https://create.roblox.com/docs/reference/engine/datatypes/RaycastParams",
	},
}
local function observed(getter)
	local ok, value = pcall(getter)
	if not ok then return {available = false, reason = tostring(value)} end
	return {available = true, present = value ~= nil, value = value}
end
local function numberValue(getter)
	local observation = observed(getter)
	local value = observation.value
	if observation.available and (type(value) ~= "number" or value ~= value or math.abs(value) == math.huge) then
		return {available = false, reason = "API returned a missing, nonnumeric or nonfinite value"}
	end
	return observation
end
local function attribute(instance, name)
	return observed(function() return instance:GetAttribute(name) end)
end
local function vector(value)
	return {x = value.X, y = value.Y, z = value.Z}
end
local function namedChildren(parent, name)
	local matches = {}
	for _, child in ipairs(parent:GetChildren()) do if child.Name == name then table.insert(matches, child) end end
	return matches
end
local function scriptPresence(parent, name)
	if not parent then return {available = false, reason = "Container is absent in this DataModel"} end
	local matches, rows = namedChildren(parent, name), {}
	for _, child in ipairs(matches) do
		local row = {path = child:GetFullName(), class = child.ClassName}
		if child:IsA("BaseScript") then row.enabled = observed(function() return child.Enabled end) end
		table.insert(rows, row)
	end
	return {available = true, present = #matches > 0, count = #matches, matches = rows,
		meaning = "Presence/enabled flags only; does not prove that the script ran without errors"}
end
local function guiVisibility(candidate)
	if not candidate then return {available = true, present = false} end
	return observed(function()
		local flags, ancestor = true, candidate
		while ancestor do
			if ancestor:IsA("GuiObject") and not ancestor.Visible then flags = false end
			if ancestor:IsA("LayerCollector") and not ancestor.Enabled then flags = false end
			if ancestor:IsA("CanvasGroup") and ancestor.GroupTransparency >= 1 then flags = false end
			ancestor = ancestor.Parent
		end
		local size = candidate:IsA("GuiObject") and candidate.AbsoluteSize or nil
		return {path = candidate:GetFullName(), class = candidate.ClassName, present = true,
			visibilityFlags = flags, visibleWithPositiveSize = flags and size ~= nil and size.X > 0 and size.Y > 0,
			absoluteSize = if size then {x = size.X, y = size.Y} else nil,
			backgroundTransparency = if candidate:IsA("GuiObject") then candidate.BackgroundTransparency else nil,
			meaning = "Actual visibility/Enabled/CanvasGroup flags and size; not a pixel or occlusion assertion"}
	end)
end
local function loadingCovers()
	if not IS_CLIENT or not Players.LocalPlayer then
		return {available = false, reason = "Loading cover rendering belongs to the local Client PlayerGui"}
	end
	local player = Players.LocalPlayer
	local gui = player:FindFirstChild("PlayerGui")
	if not gui then return {available = false, reason = "Current LocalPlayer PlayerGui is absent"} end
	local lobby, live, round = gui:FindFirstChild("LobbyLoadingGui"), gui:FindFirstChild("LevelLoadingGui"), gui:FindFirstChild("RoundGui")
	return {available = true, playerGuiPath = gui:GetFullName(),
		lobbyCover = guiVisibility(lobby and lobby:FindFirstChild("Cover")),
		liveLevelCover = guiVisibility(live and live:FindFirstChild("Cover")),
		roundLevelLoading = guiVisibility(round and round:FindFirstChild("LevelLoading")),
		LobbyLoadingOpen = attribute(player, "LobbyLoadingOpen"), LobbyLoadingDone = attribute(player, "LobbyLoadingDone"),
		LevelLoadingOpen = attribute(player, "LevelLoadingOpen"), LoadingLevel = attribute(player, "LoadingLevel")}
end
local function worldObjects()
	local characters, roots = {}, {}
	for _, player in ipairs(Players:GetPlayers()) do if player.Character then characters[player.Character] = true end end
	for _, child in ipairs(workspace:GetChildren()) do
		if not characters[child] and not (child:IsA("Model") and child:FindFirstChildWhichIsA("Humanoid"))
			and (child:IsA("Model") or child:IsA("Folder") or child:IsA("BasePart") or child:IsA("Terrain")) then
			table.insert(roots, child)
		end
	end
	return roots
end
local function floorAt(position, roots)
	return observed(function()
		local params = RaycastParams.new() -- query value only; no DataModel instance/fixture
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = roots
		params.RespectCanCollide = true
		local hit = workspace:Raycast(position + Vector3.new(0, 2, 0), Vector3.new(0, -18, 0), params)
		if not hit then return {hit = false, rayLengthStuds = 18, filter = "Actual workspace world objects; characters excluded"} end
		local root = hit.Instance
		while root.Parent and root.Parent ~= workspace do root = root.Parent end
		return {hit = true, path = hit.Instance:GetFullName(), worldRoot = root.Name, class = hit.Instance.ClassName,
			position = vector(hit.Position), normal = vector(hit.Normal), rayDistanceStuds = hit.Distance,
			verticalDistanceBelowRootStuds = position.Y - hit.Position.Y,
			canCollide = observed(function() return hit.Instance.CanCollide end),
			filter = "Include actual available workspace world roots/parts/terrain; all player characters and direct Humanoid models excluded"}
	end)
end
local function runtimeContext()
	local roots, players = worldObjects(), {}
	local list = if IS_CLIENT and Players.LocalPlayer then {Players.LocalPlayer} else Players:GetPlayers()
	for index, player in ipairs(list) do
		if index > 32 then break end
		local character = player.Character
		local body = character and character:FindFirstChild("HumanoidRootPart")
		local row = {userId = player.UserId, name = player.Name, InRound = attribute(player, "InRound"),
			SelectedLevel = attribute(player, "SelectedLevel"), rootPresent = body ~= nil}
		if body and body:IsA("BasePart") then row.position = vector(body.Position); row.floor = floorAt(body.Position, roots) end
		table.insert(players, row)
	end
	local rootPaths = {}
	for _, root in ipairs(roots) do table.insert(rootPaths, root:GetFullName()) end
	local camera = workspace.CurrentCamera
	local state = RS:FindFirstChild("Level 4 State")
	return {players = players, playerCount = #list, playerRecordsLimitedTo32 = #list > 32,
		camera = if IS_CLIENT and camera then {position = vector(camera.CFrame.Position), lookVector = vector(camera.CFrame.LookVector)} else nil,
		floorQueryWorldRoots = rootPaths, loadingCovers = loadingCovers(),
		SelectedLevel = attribute(workspace, "SelectedLevel"), Level4RoundActive = attribute(workspace, "Level4RoundActive"),
		WorldGenerated = attribute(workspace, "WorldGenerated"), SceneEffectBudgetDisabled = attribute(workspace, "SceneEffectBudgetDisabled"),
		Level4_PowerState = if state then attribute(state, "Level4_PowerState") else {available = false, reason = "Level 4 State absent"},
		Level4_Phase = if state then attribute(state, "Level4_Phase") else {available = false, reason = "Level 4 State absent"}}
end
-- L2's live round reparents/renames the authored map; keep its parked alias too.
local AUTHORED_MAPS = {"Level 2 Generated World", "Level2PoolroomsMap", "Level 4 Cinema Blender", "Level 5 Void", "Level 6 Indoor Playground"}
local function effectCounter()
	return {total = 0, enabled = 0, disabled = 0, marked = 0, markedEnabled = 0, wantedTrue = 0, wantedFalse = 0,
		wantedTrueEnabled = 0, wantedTrueDisabled = 0, wantedFalseEnabled = 0, wantedFalseDisabled = 0}
end
local function countEffect(count, effect)
	count.total += 1
	if effect.Enabled then count.enabled += 1 else count.disabled += 1 end
	local wanted = effect:GetAttribute("SceneBudgetWantedEnabled")
	if type(wanted) ~= "boolean" then return end
	count.marked += 1
	if effect.Enabled then count.markedEnabled += 1 end
	if wanted then
		count.wantedTrue += 1
		if effect.Enabled then count.wantedTrueEnabled += 1 else count.wantedTrueDisabled += 1 end
	else
		count.wantedFalse += 1
		if effect.Enabled then count.wantedFalseEnabled += 1 else count.wantedFalseDisabled += 1 end
	end
end
local function loadedWorldsAndEffects()
	local worlds, candidates, loadedCount = {}, {}, 0
	for _, child in ipairs(workspace:GetChildren()) do
		if child:IsA("Model") or child:IsA("Folder") then
			table.insert(candidates, {name = child.Name, class = child.ClassName, path = child:GetFullName()})
		end
	end
	for _, name in ipairs(AUTHORED_MAPS) do
		local matches, rows = namedChildren(workspace, name), {}
		for _, root in ipairs(matches) do
			local row = {path = root:GetFullName(), class = root.ClassName, lights = effectCounter(), particles = effectCounter()}
			local ok, problem = pcall(function()
				local descendants = root:GetDescendants()
				row.loadedDescendants = #descendants
				for _, descendant in ipairs(descendants) do
					if descendant:IsA("Light") then countEffect(row.lights, descendant)
					elseif descendant:IsA("ParticleEmitter") then countEffect(row.particles, descendant) end
				end
			end)
			row.censusAvailable = ok
			if not ok then
				row.censusError = tostring(problem)
				row.lights, row.particles, row.loadedDescendants = nil, nil, nil -- partial/failed counts are unavailable, never zero
			end
			table.insert(rows, row); loadedCount += 1
		end
		table.insert(worlds, {name = name, loaded = #matches > 0, matches = rows, duplicateRootCount = #matches})
	end
	return {knownAuthoredLoadedCount = loadedCount, knownAuthoredMaps = worlds, workspaceTopLevelWorldCandidates = candidates,
		meaning = "Client: currently received descendants, not complete authored maps. Count covers named L2/L4/L5/L6; candidates include other generated/lobby worlds."}
end
local function importsAndBudget()
	local imports = {}
	for _, name in ipairs({"ZyntraShopUI", "ZyntraHUD"}) do
		local owners, count = namedChildren(RS, name), 0
		for _, owner in ipairs(owners) do count += #namedChildren(owner, "Imports") end
		table.insert(imports, {owner = name, ownerCount = #owners, importsCount = count,
			absenceVerified = #owners == 1 and count == 0})
	end
	local starter = game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
	local localScripts = IS_CLIENT and Players.LocalPlayer and Players.LocalPlayer:FindFirstChild("PlayerScripts") or nil
	return {replicatedStorageImports = imports, budgetModule = scriptPresence(RS, "SceneEffectBudget"),
		budgetTemplate = scriptPresence(starter, "SceneEffectBudgetClient"),
		actualLocalBudgetScript = if IS_CLIENT then scriptPresence(localScripts, "SceneEffectBudgetClient")
			else {available = false, reason = "Actual PlayerScripts execution is Client scoped"}}
end
-- FrameTime is documented client-only seconds. HeartbeatTime is documented
-- server scheduler job seconds. Undocumented time units remain raw native values.
local definitions = {
	{"FrameTime", "seconds", "Client renderer"}, {"RenderCPUFrameTime", "native time value", "Client renderer"},
	{"RenderGPUFrameTime", "native time value", "Client renderer"}, {"PhysicsStepTime", "native time value", "Simulation"},
	{"HeartbeatTime", "seconds", "Scheduler jobs; documented server metric"},
	{"DataReceiveKbps", "kilobytes/second", "Network"}, {"DataSendKbps", "kilobytes/second", "Network"},
	{"PhysicsReceiveKbps", "kilobytes/second", "Network physics"}, {"PhysicsSendKbps", "kilobytes/second", "Network physics"},
	{"PrimitivesCount", "count", "Simulation"}, {"MovingPrimitivesCount", "count", "Simulation"}, {"ContactsCount", "count", "Simulation"},
	{"InstanceCount", "count", "Current process/DataModel memory including unparented live Instances"},
	{"SceneTriangleCount", "count", "Client renderer"}, {"SceneDrawcallCount", "count", "Client renderer"},
	{"ShadowsTriangleCount", "count", "Client renderer"}, {"ShadowsDrawcallCount", "count", "Client renderer"},
	{"UI2DDrawcallCount", "count", "Client renderer"}, {"UI3DDrawcallCount", "count", "Client renderer"},
}
local metrics = {}
for _, definition in ipairs(definitions) do
	local name, unit, scope = definition[1], definition[2], definition[3]
	metrics[name] = {values = {}, unit = unit, scope = scope, failures = 0}
	if scope == "Client renderer" and not IS_CLIENT then
		metrics[name].inapplicable = "Server has no client rendering/FPS measurement"
	end
end
metrics.TotalMemoryUsageMb = {values = {}, unit = "megabytes", scope = "OS-reported process/session memory, not sum of tags", failures = 0}
local memoryTracking = observed(function() return Stats.MemoryTrackingEnabled end)
report.memoryTrackingEnabled = memoryTracking
local memoryTags = {}
if memoryTracking.available and memoryTracking.value == true then
	local tags = observed(function() return Enum.DeveloperMemoryTag:GetEnumItems() end)
	if tags.available then
		for _, tag in ipairs(tags.value) do
			local key = "MemoryTag." .. tag.Name
			metrics[key] = {values = {}, unit = "megabytes", scope = "DeveloperMemoryTag", failures = 0}
			table.insert(memoryTags, {tag = tag, key = key})
		end
	else report.memoryTagsUnavailable = tags.reason end
else
	report.memoryTagsUnavailable = if memoryTracking.available and memoryTracking.value == false then "MemoryTrackingEnabled is false; tag APIs would return warning/zero, so skipped"
		else "MemoryTrackingEnabled unavailable; tag memory is not assumed to be zero"
end
local function collect(key, getter)
	local metric = metrics[key]
	local value = numberValue(getter)
	if value.available then table.insert(metric.values, value.value)
	else metric.failures += 1; metric.lastUnavailableReason = value.reason end
end
report.before = runtimeContext()
local began, nextMemoryAt, sampleCount = os.clock(), 0, 0
while os.clock() - began < WINDOW_SECONDS and sampleCount < 240 do
	if not Run:IsRunning() then report.interrupted = "Play ended during sampling"; break end
	for _, definition in ipairs(definitions) do
		local key = definition[1]
		if not metrics[key].inapplicable then collect(key, function() return Stats[key] end) end
	end
	local elapsed = os.clock() - began
	if elapsed >= nextMemoryAt then
		collect("TotalMemoryUsageMb", function() return Stats:GetTotalMemoryUsageMb() end)
		for _, entry in ipairs(memoryTags) do collect(entry.key, function() return Stats:GetMemoryUsageMbForTag(entry.tag) end) end
		nextMemoryAt = elapsed + 0.5
	end
	sampleCount += 1
	local remaining = WINDOW_SECONDS - (os.clock() - began)
	if remaining > 0 then task.wait(math.min(SPACING_SECONDS, remaining)) end
end
report.actualSampleWindowSeconds = os.clock() - began
report.readingTicks = sampleCount
report.samplingLimitReached = sampleCount == 240
local function summarize(metric)
	local values = metric.values
	table.sort(values)
	local n = #values
	local out = {unit = metric.unit, scope = metric.scope, available = n > 0, samples = n, unavailableSamples = metric.failures,
		unavailableReason = metric.inapplicable or metric.lastUnavailableReason}
	if n > 0 then
		local middle = math.floor(n / 2)
		out.median = if n % 2 == 0 then (values[middle] + values[middle + 1]) / 2 else values[middle + 1]
		out.p95 = values[math.max(1, math.ceil(n * 0.95))]
		out.minimum, out.maximum = values[1], values[n]
		out.allReadingsWereZero = values[n] == 0 and values[1] == 0
		if out.allReadingsWereZero then out.zeroInterpretation = "Native API returned zero; not assumed to prove absence of work" end
	end
	return out
end
report.stats = {}
for key, metric in pairs(metrics) do report.stats[key] = summarize(metric) end
-- Census/raycast/UI work is outside the sampled window to avoid folding its
-- traversal cost into the measured CPU/render statistics. Record its own duration.
local censusBegan = os.clock()
report.after = runtimeContext()
report.worlds = loadedWorldsAndEffects()
report.optimizationPresence = importsAndBudget()
report.afterSampleCensusSeconds = os.clock() - censusBegan
report.censusTiming = "End snapshot after the 3-second Stats window; not synchronized to every Stats reading"
report.completeSampleWindow = report.interrupted == nil and not report.samplingLimitReached and report.actualSampleWindowSeconds >= WINDOW_SECONDS
return H:JSONEncode(report)
