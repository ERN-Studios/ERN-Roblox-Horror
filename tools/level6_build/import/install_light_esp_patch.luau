-- Apply only the reviewed Level 6 lamp/night/ESP repair to the live Edit place.
-- serve_light_esp_patch.py serves immutable Studio-derived before/after bytes.
local HttpService = game:GetService("HttpService")
local ScriptEditorService = game:GetService("ScriptEditorService")
local RunService = game:GetService("RunService")
local BASE = "http://127.0.0.1:8881"

assert(game.PlaceId == 131311258779917 and game.GameId == 10559217407, "Wrong Roblox place")
assert(not RunService:IsRunning(), "Patch requires Studio Edit mode")
local previousHttp = HttpService.HttpEnabled

local function editorSource(instance)
	return ScriptEditorService:GetEditorSource(instance)
end

local function instanceAt(path)
	local components = string.split(path, ".")
	local node = game:GetService(components[1])
	for index = 2, #components do
		node = assert(node:FindFirstChild(components[index]), "Missing " .. path)
	end
	return node
end

local function readback(instance, expected)
	assert(instance.Source == expected and editorSource(instance) == expected,
		"Source/editor mismatch after update: " .. instance:GetFullName())
end

local function run()
	HttpService.HttpEnabled = true
	local manifest = HttpService:JSONDecode(HttpService:GetAsync(BASE .. "/manifest", true))
	assert(manifest.schema == "level6-light-cd-esp-patch/1" and manifest.placeId == game.PlaceId
		and manifest.universeId == game.GameId, "Wrong patch manifest")
	assert(#manifest.edits == 3, "Unexpected patch edit count")
	local newInfo = manifest.new
	assert(newInfo.path == "StarterPlayer.StarterPlayerScripts.Level 6 CD Dev ESP"
		and newInfo.class == "LocalScript", "Unexpected new script")

	-- Preflight every live Source and open editor buffer before the first write.
	local edits = {}
	for _, item in ipairs(manifest.edits) do
		local instance = instanceAt(item.path)
		assert(instance.ClassName == item.class, "Wrong class: " .. item.path)
		local before = HttpService:GetAsync(BASE .. "/baseline/" .. item.id, true)
		local after = HttpService:GetAsync(BASE .. "/candidate/" .. item.id, true)
		assert(#before == item.beforeBytes and #after == item.afterBytes, "Payload byte drift: " .. item.path)
		assert(instance.Source == before and editorSource(instance) == before,
			"Live Source/editor drift before update: " .. item.path)
		table.insert(edits, {path = item.path, instance = instance, before = before, after = after})
	end
	local scripts = game:GetService("StarterPlayer"):WaitForChild("StarterPlayerScripts")
	assert(scripts:FindFirstChild("Level 6 CD Dev ESP") == nil, "ESP script already exists")
	local espBody = HttpService:GetAsync(BASE .. "/candidate/esp", true)
	assert(#espBody == newInfo.bytes, "ESP payload byte drift")

	local applied = {}
	local newScript = nil
	local success, reason = pcall(function()
		for _, item in ipairs(edits) do
			local drift = false
			ScriptEditorService:UpdateSourceAsync(item.instance, function(current)
				if current ~= item.before or item.instance.Source ~= item.before
					or editorSource(item.instance) ~= item.before then
					drift = true
					return current
				end
				return item.after
			end)
			assert(not drift, "Live source changed inside write: " .. item.path)
			readback(item.instance, item.after)
			table.insert(applied, item)
		end

		-- Stage the new, disabled LocalScript before exposing it to players.
		assert(scripts:FindFirstChild("Level 6 CD Dev ESP") == nil, "ESP appeared during update")
		newScript = Instance.new("LocalScript")
		newScript.Name = "Level 6 CD Dev ESP"
		newScript.Enabled = false
		newScript.Parent = scripts
		ScriptEditorService:UpdateSourceAsync(newScript, function() return espBody end)
		readback(newScript, espBody)
		newScript.Enabled = true
	end)
	if not success then
		if newScript then newScript:Destroy() end
		local rollbackErrors = {}
		for index = #applied, 1, -1 do
			local item = applied[index]
			local reverted, err = pcall(function()
				assert(item.instance.Source == item.after and editorSource(item.instance) == item.after,
					"Source changed before rollback: " .. item.path)
				local drift = false
				ScriptEditorService:UpdateSourceAsync(item.instance, function(current)
					if current ~= item.after then drift = true; return current end
					return item.before
				end)
				assert(not drift, "Source changed inside rollback: " .. item.path)
				readback(item.instance, item.before)
			end)
			if not reverted then table.insert(rollbackErrors, item.path .. ": " .. tostring(err)) end
		end
		return {ok = false, error = tostring(reason), rollbackErrors = rollbackErrors}
	end

	local result = {ok = true, new = newInfo.path, changed = {}}
	for _, item in ipairs(edits) do table.insert(result.changed, item.path) end
	return result
end

local ok, result = pcall(run)
HttpService.HttpEnabled = previousHttp
if not ok then return HttpService:JSONEncode({ok = false, error = tostring(result)}) end
return HttpService:JSONEncode(result)
