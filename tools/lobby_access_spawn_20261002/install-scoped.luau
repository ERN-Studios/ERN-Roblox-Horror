-- Native Edit command only; scoped fresh instance/Source/editor CAS.
local H, E = game:GetService("HttpService"), game:GetService("EncodingService")
local SES, RunService = game:GetService("ScriptEditorService"), game:GetService("RunService")
local BASE = "http://127.0.0.1:8913"
assert(not RunService:IsRunning(), "Edit only")
assert(game.PlaceId == 131311258779917 and game.GameId == 10559217407 and game.CreatorId == 1039373905, "Wrong place")
local function hash(s) return (E:ComputeStringHash(s, Enum.HashAlgorithm.Sha256):gsub(".", function(c) return string.format("%02x", string.byte(c)) end)) end
local function at(path)
 local x = game
 for segment in path:gmatch("[^.]+") do x = assert(x:FindFirstChild(segment), "Missing live path: " .. path) end
 return x
end
local raw = H:GetAsync(BASE .. "/payload", true)
assert(hash(raw) == "__PAYLOAD_SHA256__", "Frozen payload changed")
local data = H:JSONDecode(raw)
assert(data.nativeBeforeVerified == true and data.nativeBeforeCaptureId == "dd47c97b-033d-40a3-9ae3-f23d88cacab1", "Verified native before checkpoint missing")
local parent = at("ServerScriptService.LobbyReimaginedPreview")
assert(parent:IsA("Folder") and parent:GetAttribute("LobbyReimaginedOwned") == true, "Wrong preview owner")
local targets, expected, prepared = {}, {}, {}
for _, row in ipairs(data.rows) do
 assert(hash(row.source) == row.candidateSHA256 and #row.source == row.candidateBytes, "Candidate bytes changed: " .. row.path)
 local compiled, errorText = loadstring(row.source, "=" .. row.path)
 assert(compiled, "Compile failed: " .. tostring(errorText))
 if not row.new then targets[row.path] = at(row.path); expected[row.path] = row.baselineSHA256 end
end
local function verify()
 assert(not RunService:IsRunning() and at("ServerScriptService.LobbyReimaginedPreview") == parent, "Context changed")
 for _, row in ipairs(data.rows) do
  if row.new then
   local path, name = row.path:match("^(.*)%.([^.]*)$")
   local existing = at(path):FindFirstChild(name)
   assert(existing == nil or existing == prepared[row.path], "New helper conflict: " .. row.path)
  else
   local x = at(row.path)
   assert(x == targets[row.path] and x.ClassName == row.className
    and hash(x.Source) == expected[row.path] and hash(SES:GetEditorSource(x)) == expected[row.path], "Fresh baseline changed: " .. row.path)
  end
 end
end
verify()
for _, row in ipairs(data.rows) do
 if row.new then
  local x = Instance.new(row.className)
  x.Name = row.path:match("([^.]*)$")
  x:SetAttribute("LobbyReimaginedOwned", true)
  x:SetAttribute("LobbyAccessSpawnTask", "20261002")
  SES:UpdateSourceAsync(x, function(current) assert(current == "", "Prepared source conflict"); return row.source end)
  assert(hash(x.Source) == row.candidateSHA256 and SES:GetEditorSource(x) == row.source, "Prepared source/editor conflict")
  prepared[row.path] = x
 end
end
verify()
for _, row in ipairs(data.rows) do
 if row.new then prepared[row.path].Parent = at(row.path:match("^(.*)%.[^.]+$")) end
end
for _, row in ipairs(data.rows) do
 if not row.new then
  local x = targets[row.path]
  SES:UpdateSourceAsync(x, function(current)
   verify()
   assert(hash(current) == expected[row.path], "Editor callback baseline changed: " .. row.path)
   return row.source
  end)
  assert(x.Source == row.source and SES:GetEditorSource(x) == row.source, "Post-write conflict: " .. row.path)
  expected[row.path] = row.candidateSHA256
 end
end
verify()
local receipt = {installedAt = DateTime.now():ToIsoDate(), placeId = game.PlaceId, universeId = game.GameId,
 nativeBeforeCaptureId = data.nativeBeforeCaptureId, sceneChanged = false, sources = {}}
for _, row in ipairs(data.rows) do
 local x = at(row.path)
 assert(hash(x.Source) == row.candidateSHA256 and SES:GetEditorSource(x) == row.source, "Final source mismatch")
 table.insert(receipt.sources, {path = row.path, className = x.ClassName, sha256 = row.candidateSHA256, bytes = #x.Source, editorMatch = true})
end
assert(H:PostAsync(BASE .. "/receipt/install", H:JSONEncode(receipt), Enum.HttpContentType.ApplicationJson) == "saved", "Receipt failed")
return receipt
