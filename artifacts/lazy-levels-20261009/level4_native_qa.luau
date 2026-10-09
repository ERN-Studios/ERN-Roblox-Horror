-- Read-only observations for an explicitly started Studio session. This never starts/stops Play,
-- requires a controller, changes a Source/attribute/Parent, or creates native probe objects.
-- Replace the single __MODE__ token with sources (Edit), server (Play Server), or client (Play Client).
local MODE = "__MODE__"
local HS = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
assert(game.PlaceId == 131311258779917 and game.GameId == 10559217407, "Wrong place/universe")
local function unique(parent, name)
	local result
	for _, child in parent:GetChildren() do
		if child.Name == name then assert(not result, "Duplicate native path: " .. name); result = child end
	end
	return result
end
local function resolve(path)
	local current = game
	for name in path:gmatch("[^.]+") do current = assert(unique(current, name), "Missing native source: " .. path) end
	return current
end
local NAMES = {"Level 4 Cinema Blender", "Level 5 Void", "Level 6 Indoor Playground"}
local serverStorage = game:GetService("ServerStorage")
local world = unique(workspace, NAMES[1]) or unique(serverStorage, NAMES[1])
if MODE == "sources" then
	assert(not RunService:IsRunning(), "Source/editor guard requires Edit")
	local SES, encoding = game:GetService("ScriptEditorService"), game:GetService("EncodingService")
	local function sha(source)
		local hash = encoding:ComputeBufferHash(buffer.fromstring(source), Enum.HashAlgorithm.Sha256)
		local chars = {}
		for i = 0, buffer.len(hash) - 1 do chars[i+1] = string.format("%02x", buffer.readu8(hash, i)) end
		return table.concat(chars)
	end
	assert(world and world.Parent == serverStorage, "Cinema is not parked in Edit")
	local rows = {
		{"ServerScriptService.LevelWorldStorage", "ModuleScript", "42a3baf2011c779ab72e8e6ff71eda8add9da05e2ac0cb44c79ec91de323bc7a"},
		{"ServerScriptService.Level4RoundGenerator", "ModuleScript", "e52aedfa7ca13f98af4a4381fedd8ed87ca818c638e65872d0be533119077566"},
		{"ServerStorage.Level 4 Cinema Blender.OccasionalFixtureFlicker", "Script", "d7f63f21b4a827e4fcc91e0246424438fa871aa7f90013b8599ef18a51d64991"},
		{"ServerStorage.Level 4 Cinema Blender.Doors.PushDoors", "Script", "58a68c6b32aa9e7aa03f5cf2649e7ccbaf70b88db991e2061b6558ac66add55c"},
		{"StarterPlayer.StarterPlayerScripts.Level 4 Round Client", "LocalScript", "6909fa9518d2c6ff5d58f6958871bdf7ec18eb8115118a8311900c04f38bfd27"},
		{"ServerScriptService.GameManager", "Script", "0969202a4cbb3898b32608608905e19179eb7f8b645d1613c2f5a91980984ebe"},
	}
	local result = {}
	for _, row in ipairs(rows) do
		local source = resolve(row[1])
		assert(source.ClassName == row[2] and SES:GetEditorSource(source) == source.Source, "Source/editor conflict")
		assert(sha(source.Source) == row[3], "Authoritative Source changed: " .. row[1])
		result[#result+1] = {path = row[1], class = row[2], bytes = #source.Source, sha256 = row[3]}
	end
	return HS:JSONEncode({mode = MODE, originalsVerified = result, nativeWrites = 0})
end
assert(MODE == "server" or MODE == "client", "Select sources/server/client")
assert(RunService:IsRunning() and RunService:IsStudio(), "Runtime observation requires Studio Play")
assert((MODE == "client") == (Players.LocalPlayer ~= nil), "Wrong Play DataModel")
local result = {mode = MODE, nativeWrites = 0, maps = {}, players = {}, doors = {}, attributes = {}}
for _, name in ipairs(NAMES) do
	local live, parked = unique(workspace, name), unique(serverStorage, name)
	assert(not (live and parked), "Duplicate live/parked map")
	result.maps[#result.maps+1] = {name = name, inWorkspace = live ~= nil, inServerStorage = parked ~= nil,
		streamingMode = live and tostring(live.ModelStreamingMode) or nil}
end
for _, name in ipairs({"SelectedLevel", "WorldGenerated", "RoundActive", "Level4RoundActive", "RoundLoadingState",
	"RoundLoadingToken", "RoundLoadingDeadline", "LoadStage", "Level5InUse", "Level6InUse"}) do
	result.attributes[name] = workspace:GetAttribute(name)
end
local cinema = unique(workspace, NAMES[1])
local collision = cinema and unique(cinema, "Collision")
local persistent = {}
if MODE == "server" and collision then
	assert(collision:IsA("Model"), "Cinema Collision is not a Model")
	for _, player in ipairs(collision:GetPersistentPlayers()) do persistent[player] = true end
	result.collisionMode = tostring(collision.ModelStreamingMode)
end
local seen = MODE == "client" and {Players.LocalPlayer} or Players:GetPlayers()
for _, player in ipairs(seen) do
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local floor
	if root and collision then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.RespectCanCollide = true
		params.FilterDescendantsInstances = {collision}
		local hit = workspace:Raycast(root.Position + Vector3.yAxis, -Vector3.yAxis * 20, params)
		floor = hit and hit.Instance:IsA("BasePart") and hit.Instance.CanCollide and hit.Normal.Y > 0.15
			and hit.Instance:GetFullName() or nil
	end
	result.players[#result.players+1] = {
		name = player.Name, userId = player.UserId, inRound = player:GetAttribute("InRound"),
		escaped = player:GetAttribute("Escaped"), spectating = player:GetAttribute("Spectating"),
		preview6 = player:GetAttribute("Level6PlaygroundPreview"), preview2 = player:GetAttribute("Level2NewMapPreview"),
		persistentCollision = MODE == "server" and persistent[player] == true or nil,
		uiReady = player:GetAttribute("RoundEntryUIReady"), controlsReady = player:GetAttribute("RoundEntryControlsReady"),
		loadingError = player:GetAttribute("RoundLoadingError"), anchored = root and root.Anchored,
		health = humanoid and humanoid.Health, floor = floor,
		position = root and {root.Position.X, root.Position.Y, root.Position.Z},
	}
end
local doors = world and unique(world, "Doors")
for i, door in ipairs(doors and doors:GetChildren() or {}) do
	if i > 200 then result.doorsTruncated = true; break end
	local hingePart = door:IsA("Model") and unique(door, "Hinge")
	local leaf = door:IsA("Model") and unique(door, "Leaf")
	local hinge = hingePart and hingePart:FindFirstChildOfClass("HingeConstraint")
	if leaf and leaf:IsA("BasePart") and hinge then
		result.doors[#result.doors+1] = {name = door.Name, pushDoor = door:GetAttribute("PushDoor"),
			cframe = {leaf.CFrame:GetComponents()}, anchored = leaf.Anchored, canCollide = leaf.CanCollide,
			hingeEnabled = hinge.Enabled, targetAngle = hinge.TargetAngle, currentAngle = hinge.CurrentAngle,
			linearSpeed = leaf.AssemblyLinearVelocity.Magnitude, angularSpeed = leaf.AssemblyAngularVelocity.Magnitude}
	end
end
local state = game:GetService("ReplicatedStorage"):FindFirstChild("Level 4 State")
result.roundPhase = state and state:GetAttribute("Level4_Phase")
result.usherVisual = game:GetService("ReplicatedStorage"):FindFirstChild("Level 4 Usher Visual") ~= nil
local clientParts, filmGuis, exitGuis = 0, 0, 0
local deadline = os.clock() + 4
for i, instance in ipairs(cinema and cinema:GetDescendants() or {}) do
	if i > 20000 or os.clock() > deadline then result.censusIncomplete = true; break end
	if instance:IsA("BasePart") then clientParts += 1 end
	if instance:IsA("SurfaceGui") and instance.Name == "L4Film" then filmGuis += 1 end
	if instance:IsA("SurfaceGui") and instance.Name == "L4Exit" then exitGuis += 1 end
	if i % 500 == 0 then task.wait() end
end
result.cinemaParts, result.filmGuis, result.exitGuis = clientParts, filmGuis, exitGuis
return HS:JSONEncode(result)
