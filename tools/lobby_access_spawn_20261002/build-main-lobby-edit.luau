-- Create only the new owned lobby, then move the existing canonical spawn.
local H, E = game:GetService("HttpService"), game:GetService("EncodingService")
local SES = game:GetService("ScriptEditorService")
assert(not game:GetService("RunService"):IsRunning(), "Edit only")
assert(game.PlaceId == 131311258779917 and game.GameId == 10559217407, "Wrong place")
local function hash(s) return (E:ComputeStringHash(s, Enum.HashAlgorithm.Sha256):gsub(".", function(c) return string.format("%02x", string.byte(c)) end)) end
local raw = H:GetAsync("http://127.0.0.1:8913/payload", true)
assert(hash(raw) == "__PAYLOAD_SHA256__", "Frozen payload changed")
local data = H:JSONDecode(raw)
local function at(path) local x = game; for s in path:gmatch("[^.]+") do x = assert(x:FindFirstChild(s)) end; return x end
for _, row in ipairs(data.rows) do local x = at(row.path); assert(x.ClassName == row.className and hash(x.Source) == row.candidateSHA256 and SES:GetEditorSource(x) == row.source, "Installed baseline changed") end
assert(not workspace:FindFirstChild("LobbyReimaginedPreview"), "Inspect existing revision before creating a second one")
local lobby = assert(workspace:FindFirstChild("ServerLobby"))
local spawn = assert(lobby:FindFirstChild("LobbySpawn"))
assert(spawn:IsA("SpawnLocation") and spawn.CFrame == CFrame.new(0, 30.399999618530275, -860, -1, 0, 0, 0, 1, 0, 0, 0, -1), "Canonical spawn baseline changed")
assert(spawn:GetAttribute("LobbySpawnFloorModelName") == nil and spawn:GetAttribute("LobbySpawnRevision") == nil, "Spawn marker conflict")
local before = {spawn.CFrame:GetComponents()}
-- Compile the fresh exact Builder source to avoid an Edit require() cache from an earlier attempt.
local builder = at("ServerScriptService.LobbyReimaginedPreview.Builder")
local loader, compileError = loadstring(builder.Source, "=" .. builder:GetFullName())
assert(loader, compileError)
setfenv(loader, setmetatable({script = builder}, {__index = getfenv()}))
local model = loader().Build()
assert(model.Parent == workspace and model:GetAttribute("LobbyReimaginedOwned") == true and model:GetAttribute("Ready") == true, "New lobby failed readiness")
local params = RaycastParams.new(); params.FilterType = Enum.RaycastFilterType.Include; params.FilterDescendantsInstances = {model}; params.RespectCanCollide = true
local position = Vector3.new(220, 30.4, -860)
local rays = {}
for _, dx in ipairs({-2, 0, 2}) do for _, dz in ipairs({-2, 0, 2}) do
 local hit = workspace:Raycast(position + Vector3.new(dx, 12, dz), Vector3.new(0, -18, 0), params)
 assert(hit and hit.Instance.CanCollide and hit.Normal.Y > .7 and math.abs(hit.Position.Y - position.Y) < 2, "New spawn floor incomplete")
 table.insert(rays, {dx = dx, dz = dz, floor = hit.Instance:GetFullName(), height = hit.Position.Y})
end end
assert(lobby.Parent == workspace and spawn.Parent == lobby and spawn == lobby:FindFirstChild("LobbySpawn")
 and spawn.CFrame == CFrame.new(table.unpack(before)), "Spawn baseline changed during build")
spawn.CFrame = CFrame.lookAt(position, Vector3.new(220, 30.4, -760))
spawn:SetAttribute("LobbySpawnFloorModelName", model.Name)
spawn:SetAttribute("LobbySpawnRevision", 4)
local receipt = {builtAt = DateTime.now():ToIsoDate(), placeId = game.PlaceId, universeId = game.GameId,
 nativeBeforeCaptureId = data.nativeBeforeCaptureId, newModel = model:GetFullName(), descendants = #model:GetDescendants(),
 canonicalSpawnPath = spawn:GetFullName(), beforeSpawnCFrame = before, afterSpawnCFrame = {spawn.CFrame:GetComponents()},
 spawnAttributes = spawn:GetAttributes(), spawnFloorRays = rays, originalLobbyGeometryChanged = false,
 authorizedNonScriptScope = "New owned Workspace.LobbyReimaginedPreview; original canonical SpawnLocation CFrame and two lobby floor/revision attributes"}
assert(H:PostAsync("http://127.0.0.1:8913/receipt/scene", H:JSONEncode(receipt), Enum.HttpContentType.ApplicationJson) == "saved", "Receipt failed")
return receipt
