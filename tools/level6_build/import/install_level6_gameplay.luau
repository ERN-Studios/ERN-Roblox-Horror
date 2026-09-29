-- Run once through Studio execute_luau in Edit after serve_gameplay_candidates.py starts.
-- Exact live Source/editor checks protect the four existing scripts. New scripts are
-- staged disabled, then mounted only after every candidate has been read back.
local HS = game:GetService("HttpService")
local SES = game:GetService("ScriptEditorService")
local RS = game:GetService("RunService")
local SSS = game:GetService("ServerScriptService")
local SS = game:GetService("ServerStorage")
local SP = game:GetService("StarterPlayer")
local BASE = "http://127.0.0.1:8880"

assert(game.PlaceId == 131311258779917 and game.GameId == 10559217407, "Wrong Level 6 experience")
assert(not RS:IsRunning(), "Level 6 installation requires Edit mode")
local starterScripts = assert(SP:FindFirstChild("StarterPlayerScripts"), "StarterPlayerScripts absent")
local sourceFolder = assert(SS:FindFirstChild("Level6BlenderSource"), "Blender source must be installed first")
assert(sourceFolder:IsA("Folder") and sourceFolder:GetAttribute("Ready") == true
	and sourceFolder:GetAttribute("Version") == "WornParty20260930-v2", "Blender source incomplete or wrong version")
assert(not SS:FindFirstChild("Level6BlenderKit"), "Unexpected persistent Blender kit; reconcile before install")
local sourceMeshes = assert(sourceFolder:FindFirstChild("Meshes"), "Blender mesh source absent")
assert(#sourceMeshes:GetChildren() == 49, "Blender mesh source is incomplete")
assert(not SSS:FindFirstChild("Level 6 Systems") and not SSS:FindFirstChild("Level6PreviewAccess")
	and not starterScripts:FindFirstChild("Level6PreviewTransport"), "A Level 6 install target already exists")
assert(game:GetService("ReplicatedStorage"):FindFirstChild("DevAccess"):IsA("ModuleScript"), "DevAccess missing")
local lobby = assert(workspace:FindFirstChild("ServerLobby"), "Server lobby missing")
local doors = assert(lobby:FindFirstChild("LevelDoorways"), "Lobby doorways missing")
assert(doors:FindFirstChild("Level6SealedDoor") and doors.Level6SealedDoor:IsA("BasePart"), "Level 6 preview door missing")

local allowedNew = {
	["ServerScriptService.Level 6 Systems.Level 6 Configuration"]="ModuleScript",
	["ServerScriptService.Level 6 Systems.Level 6 Hiding Controller"]="ModuleScript",
	["ServerScriptService.Level 6 Systems.Level 6 Kit Metadata"]="ModuleScript",
	["ServerScriptService.Level 6 Systems.Level 6 Layout Generator"]="ModuleScript",
	["ServerScriptService.Level 6 Systems.Level 6 Mall Manager AI Controller"]="ModuleScript",
	["ServerScriptService.Level 6 Systems.Level 6 Music Sequence Controller"]="ModuleScript",
	["ServerScriptService.Level 6 Systems.Level 6 Objective Controller"]="ModuleScript",
	["ServerScriptService.Level 6 Systems.Level 6 Preview Runtime"]="ModuleScript",
	["ServerScriptService.Level 6 Systems.Level 6 Visual Adapter"]="ModuleScript",
	["ServerScriptService.Level 6 Systems.Level 6 World Builder"]="ModuleScript",
	["ServerScriptService.Level 6 Systems.Level 6 Room Dressing"]="ModuleScript",
	["ServerScriptService.Level 6 Systems.Level6BlenderRuntimeBake"]="ModuleScript",
	["ServerScriptService.Level6PreviewAccess"]="Script",
	["StarterPlayer.StarterPlayerScripts.Level 6 Lighting Controller"]="LocalScript",
	["StarterPlayer.StarterPlayerScripts.Level 6 Mall Manager Visual Smoother"]="LocalScript",
	["StarterPlayer.StarterPlayerScripts.Level 6 Reader Client"]="LocalScript",
	["StarterPlayer.StarterPlayerScripts.Level 6 Sound Controller"]="LocalScript",
	["StarterPlayer.StarterPlayerScripts.Level 6 Table Hiding Client"]="LocalScript",
	["StarterPlayer.StarterPlayerScripts.Level6PreviewTransport"]="LocalScript",
}
local allowedShared = {
	["StarterPlayer.StarterPlayerScripts.NoiseReporter"]="LocalScript",
	["StarterPlayer.StarterPlayerScripts.LobbyMusicController"]="LocalScript",
	["StarterPlayer.StarterPlayerScripts.Level4PreviewPrompt"]="LocalScript",
	["ServerScriptService.Crouch State Server"]="Script",
}
local function resolve(path)
	local parts = string.split(path, ".")
	local first = table.remove(parts, 1)
	local cursor = if first == "ServerScriptService" then SSS else if first == "StarterPlayer" then SP else nil
	assert(cursor, "Unapproved install root " .. path)
	for _, name in ipairs(parts) do
		cursor = cursor and cursor:FindFirstChild(name)
	end
	return cursor
end
local function editorSource(instance)
	local ok, value = pcall(SES.GetEditorSource, SES, instance)
	assert(ok, "Cannot inspect editor Source for " .. instance:GetFullName() .. ": " .. tostring(value))
	return value
end
local function readback(instance, expected)
	for _ = 1, 100 do
		if instance.Source == expected and editorSource(instance) == expected then return end
		task.wait(.05)
	end
	error("Source/editor readback differs at " .. instance:GetFullName())
end
local function fetchSnapshot()
	local prior = HS.HttpEnabled
	local ok, result = pcall(function()
		HS.HttpEnabled = true
		local manifest = HS:JSONDecode(HS:GetAsync(BASE .. "/manifest", true))
		assert(manifest.schema == "level6-gameplay-install-v1" and manifest.placeId == game.PlaceId
			and manifest.universeId == game.GameId and #manifest.new == 19 and #manifest.shared == 4,
			"Wrong Level 6 install manifest")
		local seen = {}
		for _, item in ipairs(manifest.new) do
			assert(allowedNew[item.path] == item.class and not seen[item.path], "Unapproved new target " .. tostring(item.path))
			seen[item.path] = true
			item.body = HS:GetAsync(BASE .. "/source/" .. item.id, true)
			assert(#item.body == item.bytes, "Short candidate " .. item.path)
		end
		for _, item in ipairs(manifest.shared) do
			assert(allowedShared[item.path] == item.class and not seen[item.path], "Unapproved shared target " .. tostring(item.path))
			seen[item.path] = true
			item.baseline = HS:GetAsync(BASE .. "/baseline/" .. item.id, true)
			item.body = HS:GetAsync(BASE .. "/source/" .. item.id, true)
			assert(#item.baseline == item.baselineBytes and #item.body == item.bytes, "Short shared payload " .. item.path)
		end
		for path in pairs(allowedNew) do assert(seen[path], "Missing new candidate " .. path) end
		for path in pairs(allowedShared) do assert(seen[path], "Missing shared candidate " .. path) end
		return manifest
	end)
	HS.HttpEnabled = prior
	if not ok then error(result) end
	return result
end
local manifest = fetchSnapshot()

-- This is a fresh read just before any Studio source write; the callback below
-- repeats the exact baseline test at the moment of each shared edit.
for _, item in ipairs(manifest.shared) do
	local target = assert(resolve(item.path), "Missing shared script " .. item.path)
	assert(target.ClassName == item.class, "Shared script class changed: " .. item.path)
	assert(target.Source == item.baseline and editorSource(target) == item.baseline,
		"Shared Source/editor changed since backup: " .. item.path)
	item.target = target
end
assert(not SSS:FindFirstChild("Level 6 Systems") and not SSS:FindFirstChild("Level6PreviewAccess")
	and not starterScripts:FindFirstChild("Level6PreviewTransport"), "New Level 6 target appeared during fetch")
for _, item in ipairs(manifest.new) do
	if not string.find(item.path, "^ServerScriptService%.Level 6 Systems%.") then
		assert(not resolve(item.path), "New target appeared during fetch: " .. item.path)
	end
end

local batch = HS:GenerateGUID(false)
local stage = Instance.new("Folder")
stage.Name = "__Level6InstallStage_" .. batch
stage:SetAttribute("Level6InstallBatch", batch)
stage.Parent = SS
local staged, changed, rollbackErrors = {}, {}, {}
local function rollbackShared()
	for index = #changed, 1, -1 do
		local item = changed[index]
		local ok, why = pcall(function()
			local target = item.target
			assert(target.Parent and target.Source == item.body and editorSource(target) == item.body,
				"Shared source changed after install")
			local drift = false
			SES:UpdateSourceAsync(target, function(old)
				if old ~= item.body or target.Source ~= item.body or editorSource(target) ~= item.body then
					drift = true
					return old
				end
				return item.baseline
			end)
			assert(not drift, "Shared source changed during rollback")
			readback(target, item.baseline)
		end)
		if not ok then table.insert(rollbackErrors, item.path .. ": " .. tostring(why)) end
	end
end

local prepared, prepareError = pcall(function()
	for _, item in ipairs(manifest.new) do
		local instance = Instance.new(item.class)
		instance.Name = string.split(item.path, ".")[#string.split(item.path, ".")]
		instance:SetAttribute("Level6InstallBatch", batch)
		instance:SetAttribute("Level6SourceSha256", item.sha256)
		if instance:IsA("BaseScript") then instance.Enabled = false end
		instance.Parent = stage
		SES:UpdateSourceAsync(instance, function() return item.body end)
		readback(instance, item.body)
		staged[item.path] = instance
	end
end)
if not prepared then
	stage:Destroy()
	return HS:JSONEncode({ok=false, phase="stage", error=tostring(prepareError), snapshot=manifest.snapshotSha256})
end

local patched, patchError = pcall(function()
	for _, item in ipairs(manifest.shared) do
		local target = item.target
		assert(target.Parent and target.Source == item.baseline and editorSource(target) == item.baseline,
			"Shared source changed before write: " .. item.path)
		local drift = false
		SES:UpdateSourceAsync(target, function(old)
			if old ~= item.baseline or target.Source ~= item.baseline or editorSource(target) ~= item.baseline then
				drift = true
				return old
			end
			return item.body
		end)
		assert(not drift, "Shared source changed inside write: " .. item.path)
		table.insert(changed, item)
		readback(target, item.body)
	end
end)
if not patched then
	rollbackShared()
	stage:Destroy()
	return HS:JSONEncode({ok=false, phase="shared", error=tostring(patchError),
		rollbackErrors=rollbackErrors, snapshot=manifest.snapshotSha256})
end

local mounted, mountError = pcall(function()
	assert(not SSS:FindFirstChild("Level 6 Systems") and not SSS:FindFirstChild("Level6PreviewAccess")
		and not starterScripts:FindFirstChild("Level6PreviewTransport"), "New Level 6 target appeared before mount")
	local systems = Instance.new("Folder")
	systems.Name = "Level 6 Systems"
	systems:SetAttribute("Level6InstallBatch", batch)
	for _, item in ipairs(manifest.new) do
		if string.find(item.path, "^ServerScriptService%.Level 6 Systems%.") then
			staged[item.path].Parent = systems
		end
	end
	systems.Parent = SSS
	for _, item in ipairs(manifest.new) do
		local instance = staged[item.path]
		if instance.Parent == stage then
			instance.Parent = if string.find(item.path, "^ServerScriptService%.") then SSS else starterScripts
		end
	end
	for _, item in ipairs(manifest.new) do readback(staged[item.path], item.body) end
	for _, item in ipairs(manifest.new) do
		local instance = staged[item.path]
		if instance:IsA("BaseScript") then instance.Enabled = true end
	end
	stage:Destroy()
end)
if not mounted then
	rollbackShared()
	if stage.Parent then stage:SetAttribute("Level6InstallIncomplete", true) end
	local systems = SSS:FindFirstChild("Level 6 Systems")
	if systems and systems:GetAttribute("Level6InstallBatch") == batch then systems:SetAttribute("Level6InstallIncomplete", true) end
	return HS:JSONEncode({ok=false, phase="mount", error=tostring(mountError),
		rollbackErrors=rollbackErrors, batch=batch, snapshot=manifest.snapshotSha256})
end
return HS:JSONEncode({ok=true, batch=batch, snapshot=manifest.snapshotSha256,
	newScripts=#manifest.new, guardedSharedEdits=#manifest.shared, httpEnabledRestored=HS.HttpEnabled})
