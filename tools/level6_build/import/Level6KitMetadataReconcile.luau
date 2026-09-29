-- Prepared offline for a later, owner-authorized Studio Edit run. Do not run now.
-- Reconciles exactly one installed Level 6 ModuleScript against its source/editor
-- baseline from guarded install batch c0736c08-00a4-44a9-9153-456be94dee95.
-- Start serve_gameplay_candidates.py on loopback before executing in Studio.
local HS = game:GetService("HttpService")
local SES = game:GetService("ScriptEditorService")
local RS = game:GetService("RunService")
local SSS = game:GetService("ServerScriptService")

local BASE = "http://127.0.0.1:8880"
local BATCH = "c0736c08-00a4-44a9-9153-456be94dee95"
local PATH = "ServerScriptService.Level 6 Systems.Level 6 Kit Metadata"
local INSTALLED_SHA = "6270f72d32a197a002cd18815f203225f7f3660dd3a9c6da261eea48900870f6"
local OFFLINE_SHA = "c141f4c5246ece81288d1cefdedd8243057149d4844f8fea7c14ee428ff66f4b"
local OFFLINE_SNAPSHOT = "23a305861ebff83d884b77cf504212abc3728f52a400f0e41e83ec5d60c7eae9"

assert(game.PlaceId == 131311258779917 and game.GameId == 10559217407, "Wrong Level 6 experience")
assert(not RS:IsRunning(), "Kit metadata reconciliation requires Studio Edit mode")

local systems = assert(SSS:FindFirstChild("Level 6 Systems"), "Level 6 Systems absent")
assert(systems:IsA("Folder") and systems:GetAttribute("Level6InstallBatch") == BATCH,
	"Level 6 Systems no longer matches the installed batch")
local target = assert(systems:FindFirstChild("Level 6 Kit Metadata"), "Kit Metadata absent")
assert(target:IsA("ModuleScript") and target.Parent == systems
	and target:GetAttribute("Level6InstallBatch") == BATCH, "Wrong kit metadata instance")

local function editorSource()
	local ok, value = pcall(SES.GetEditorSource, SES, target)
	assert(ok and type(value) == "string", "Cannot inspect live kit metadata editor source: " .. tostring(value))
	return value
end

local priorHttp = HS.HttpEnabled
local fetched, payload = pcall(function()
	HS.HttpEnabled = true
	local manifest = HS:JSONDecode(HS:GetAsync(BASE .. "/manifest", true))
	assert(manifest.schema == "level6-gameplay-install-v1"
		and manifest.placeId == game.PlaceId and manifest.universeId == game.GameId
		and manifest.snapshotSha256 == OFFLINE_SNAPSHOT
		and #manifest.new == 19 and #manifest.shared == 4, "Offline snapshot changed")
	local item
	for _, candidate in ipairs(manifest.new) do
		if candidate.path == PATH then
			assert(not item, "Duplicate kit metadata target")
			item = candidate
		end
	end
	assert(item and item.class == "ModuleScript" and item.bytes == 8763
		and item.sha256 == OFFLINE_SHA, "Unexpected kit metadata candidate")
	local installed = HS:GetAsync(BASE .. "/metadata/installed", true)
	local offline = HS:GetAsync(BASE .. "/metadata/offline", true)
	assert(#installed == 8761 and #offline == item.bytes and installed ~= offline,
		"Kit metadata payload lengths differ from the reviewed package")
	return {Installed = installed, Offline = offline}
end)
HS.HttpEnabled = priorHttp
assert(fetched, "Could not fetch reviewed kit metadata package: " .. tostring(payload))

-- Exact bytes are stronger than trusting a stored digest alone. Check both
-- Studio's Source property and the current unsaved editor buffer immediately
-- before the update and again inside UpdateSourceAsync's callback.
assert(target.Parent == systems and target:GetAttribute("Level6SourceSha256") == INSTALLED_SHA,
	"Kit metadata instance or recorded installed SHA changed")
assert(target.Source == payload.Installed and editorSource() == payload.Installed,
	"Kit metadata Source/editor changed since guarded install; reread and reconcile manually")

local drift = false
SES:UpdateSourceAsync(target, function(old)
	if target.Parent ~= systems or target:GetAttribute("Level6InstallBatch") ~= BATCH
		or target:GetAttribute("Level6SourceSha256") ~= INSTALLED_SHA
		or old ~= payload.Installed or target.Source ~= payload.Installed
		or editorSource() ~= payload.Installed then
		drift = true
		return old
	end
	return payload.Offline
end)
assert(not drift, "Kit metadata changed during UpdateSourceAsync; no source was applied")

local matched = false
for _ = 1, 100 do
	if target.Parent == systems and target.Source == payload.Offline
		and editorSource() == payload.Offline then
		matched = true
		break
	end
	task.wait(.05)
end
assert(matched, "Kit metadata source/editor readback differs; inspect Studio before retrying")
target:SetAttribute("Level6SourceSha256", OFFLINE_SHA)
assert(target.Source == payload.Offline and editorSource() == payload.Offline
	and target:GetAttribute("Level6SourceSha256") == OFFLINE_SHA,
	"Kit metadata changed after readback")

return HS:JSONEncode({ok = true, target = PATH, installedSha256 = INSTALLED_SHA,
	newSha256 = OFFLINE_SHA, snapshotSha256 = OFFLINE_SNAPSHOT,
	sourceEditorParity = true, httpEnabledRestored = HS.HttpEnabled == priorHttp})
