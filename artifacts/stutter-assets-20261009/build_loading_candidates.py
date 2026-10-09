from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[2]
BEFORE = ROOT / '.git/stutter-assets-20261009/scoped-before'
OUT = Path(__file__).parent / 'candidates'
OUT.mkdir(exist_ok=True)

# Shared as generation input only; both candidates remain ordinary LocalScripts.
CONTENT = r'''local CONTENT_PROPERTIES = {
	MeshPart = { "MeshContent", "TextureContent" },
	SpecialMesh = { "MeshId", "TextureId" },
	Decal = { "Texture" }, Texture = { "Texture" },
	ImageLabel = { "Image" }, ImageButton = { "Image" },
	ParticleEmitter = { "Texture" }, Beam = { "Texture" }, Trail = { "Texture" },
}
local MAP_PROPERTIES = { "ColorMapContent", "NormalMapContent", "RoughnessMapContent", "MetalnessMapContent" }

local function contentKey(value)
	if type(value) == "string" then return value ~= "" and value or nil end
	if typeof(value) == "Content" then
		if value.SourceType == Enum.ContentSourceType.Uri then return value.Uri ~= "" and value.Uri or nil end
		if value.SourceType == Enum.ContentSourceType.Opaque then return value end
	end
	return nil
end

local function collectAsset(instance, ids, carriers)
	local added = 0
	local function add(key, imageId, keys)
		if not key or ids[key] then return end
		ids[key] = "pending"
		added += 1
		if imageId then
			table.insert(carriers, {ImageId = imageId, Keys = {key}})
		else
			table.insert(keys, key)
		end
	end
	if instance:IsA("SurfaceAppearance") then
		-- PreloadAsync ignores SurfaceAppearance. Warm URI images through supported
		-- Decals; this cannot certify that the renderer's processed PBR pack is ready.
		for _, property in ipairs(MAP_PROPERTIES) do
			local ok, value = pcall(function() return instance[property] end)
			if ok and typeof(value) == "Content" and value.SourceType == Enum.ContentSourceType.Uri then
				add(contentKey(value), value.Uri)
			end
		end
	else
		local keys = {}
		for _, property in ipairs(CONTENT_PROPERTIES[instance.ClassName] or {}) do
			local ok, value = pcall(function() return instance[property] end)
			if ok then
				local key = contentKey(value)
				if typeof(key) == "Content" then
					-- Embedded Opaque content without an asset ID has no remote fetch.
					local legacy = property == "MeshContent" and "MeshId" or "TextureID"
					local readable, id = pcall(function() return instance[legacy] end)
					key = readable and type(id) == "string" and id ~= "" and id or nil
				end
				add(key, nil, keys)
			end
		end
		if #keys > 0 then table.insert(carriers, {Instance = instance, Keys = keys}) end
	end
	return added
end

local function loadCarrier(carrier)
	local instance = carrier.Instance
	local reported, failed = false, false
	local ok = pcall(function()
		if carrier.ImageId then
			instance = Instance.new("Decal")
			instance.Texture = carrier.ImageId
		end
		-- Keep mesh instances: a MeshId string does not necessarily fetch the
		-- same content as the actual MeshPart, especially DataModel-scoped meshes.
		ContentProvider:PreloadAsync({instance}, function(_, fetchStatus)
			reported = true
			if fetchStatus ~= Enum.AssetFetchStatus.Success then failed = true end
		end)
	end)
	if carrier.ImageId and instance then
		local cleaned = pcall(function() instance:Destroy() end)
		if not cleaned then ok = false end
	end
	-- A return or absent callback is not evidence of a successful download.
	return ok and reported and not failed
end

local function pendingCarriers(ids, carriers, wanted)
	local out = {}
	for _, carrier in ipairs(carriers) do
		for _, key in ipairs(carrier.Keys) do
			if ids[key] == wanted then table.insert(out, carrier) break end
		end
	end
	return out
end
'''

LOBBY_CENSUS = CONTENT + r'''
local function census(roots, ids, carriers, instances)
	local total, checked = 0, 0
	local function consider(instance)
		total += collectAsset(instance, ids, carriers)
		checked += 1
		if checked % 200 == 0 then task.wait() end
	end
	if instances then
		for _, instance in ipairs(instances) do consider(instance) end
	else
		for _, root in ipairs(roots) do
			for _, instance in ipairs(root:GetDescendants()) do consider(instance) end
		end
	end
	if devFlag("DevLobbyLoadBadAsset") then
		local broken = Instance.new("Decal")
		broken.Texture = "rbxassetid://999999999999999"
		consider(broken)
		-- Store the URI on a test-owned carrier so no destroyed probe is preloaded.
		for _, carrier in ipairs(carriers) do
			if carrier.Instance == broken then carrier.Instance, carrier.ImageId = nil, broken.Texture end
		end
		broken:Destroy()
	end
	return total
end

local settledCount = 0
local preloadBusy = false
local function preload(ids, carriers, total)
	local failed, token, done = 0, retryToken, false
	-- All workers from a retry/skip retain this owner until their engine calls drain.
	while preloadBusy and token == retryToken and not enterAnyway do task.wait(0.1) end
	if token ~= retryToken or enterAnyway then return 0, token ~= retryToken end
	local cursor, running = 1, math.min(4, #carriers)
	if running == 0 then return 0, false end
	preloadBusy = true
	for _ = 1, running do
		task.spawn(function()
			local ok, problem = pcall(function()
				while cursor <= #carriers and token == retryToken and not enterAnyway do
					-- Claim before yielding, so each typed carrier is requested once.
					local carrier = carriers[cursor]
					cursor += 1
					while devFlag("DevLobbyLoadStall") and token == retryToken and not enterAnyway do task.wait(0.2) end
					if token ~= retryToken or enterAnyway then break end
					local loaded = loadCarrier(carrier)
					if token ~= retryToken or enterAnyway then break end
					for _, key in ipairs(carrier.Keys) do
						if ids[key] == "pending" then
							ids[key] = loaded and "ok" or "failed"
							settledCount += 1
							if not loaded then failed += 1 end
						end
					end
					progress = math.max(progress, 0.3 + 0.7 * math.min(1, settledCount / math.max(1, total)))
					status.Text = string.format("LOADING LOBBY ASSETS  %d / %d", math.min(settledCount, total), total)
					touch()
					task.wait()
				end
			end)
			if not ok then warn("[LobbyLoading] worker: " .. tostring(problem)) end
			running -= 1
			if running == 0 then
				if token == retryToken and not enterAnyway then
					-- An unexpected worker error must not turn unreported work into success.
					for _, carrier in ipairs(carriers) do
						for _, key in ipairs(carrier.Keys) do
							if ids[key] == "pending" then ids[key] = "failed" failed += 1 settledCount += 1 end
						end
					end
				end
				preloadBusy, done = false, true
			end
		end)
	end
	while not done and token == retryToken and not enterAnyway do task.wait(0.1) end
	return failed, token ~= retryToken
end
'''

FETCH = r'''	-- Index each streamed root once; arrivals add work without rescanning the map.
	local seen, carriers, watched, queued = {}, {}, {}, {}
	local fetching, fetchGeneration = false, 0
	local function resetFetch()
		fetchGeneration += 1
		for _, state in pairs(watched) do state.Connection:Disconnect() end
		seen, carriers, watched, queued = {}, {}, {}, {}
		-- The old worker still owns `fetching` until its engine request returns.
	end
	local function track(roots, generation, deadline)
		for root, state in pairs(watched) do
			if not root.Parent then state.Connection:Disconnect() watched[root] = nil end
		end
		for _, root in ipairs(roots) do
			if not watched[root] then
				watched[root] = {
					Connection = root.DescendantAdded:Connect(function(instance)
						if generation == fetchGeneration then table.insert(queued, instance) end
					end), Initial = root:GetDescendants(), Cursor = 1,
				}
			end
			local state, added = watched[root], 0
			while state.Initial and state.Cursor <= #state.Initial and added < 2000 do
				if generation ~= fetchGeneration or os.clock() >= deadline then return end
				table.insert(queued, state.Initial[state.Cursor])
				state.Cursor += 1
				added += 1
				if added % 200 == 0 then task.wait() end
			end
			if state.Initial and state.Cursor > #state.Initial then state.Initial = nil end
		end
	end
	local function fetch(roots, cap, report)
		if fetching then return 0 end
		fetching = true
		local deadline, done, count, generation = os.clock() + cap, false, 0, fetchGeneration
		task.spawn(function()
			local ok, problem = pcall(function()
				track(roots, generation, deadline)
				if generation ~= fetchGeneration then return end
				-- One bounded census slice per pass; the unprocessed queue remains queued.
				local slice = table.move(queued, 1, math.min(#queued, 2000), 1, {})
				queued = table.move(queued, #slice + 1, #queued, 1, {})
				census(nil, seen, carriers, slice)
				if generation ~= fetchGeneration then return end
				local work = {}
				for _, carrier in ipairs(carriers) do
					if (carrier.Attempts or 0) < 2 then
						for _, key in ipairs(carrier.Keys) do
							if seen[key] ~= "ok" then table.insert(work, carrier) break end
						end
					end
				end
				count = #work
				for index, carrier in ipairs(work) do
					if generation ~= fetchGeneration or os.clock() >= deadline then break end
					carrier.Attempts = (carrier.Attempts or 0) + 1
					local loaded = loadCarrier(carrier)
					if generation ~= fetchGeneration then break end
					for _, key in ipairs(carrier.Keys) do seen[key] = loaded and "ok" or "failed" end
					if not loaded and carrier.Attempts == 2 then
						warn("[LevelLoading] could not fetch: " .. tostring(carrier.Keys[1]))
					end
					if report then report(index, count) end
					task.wait()
				end
			end)
			if not ok then warn("[LevelLoading] prefetch: " .. tostring(problem)) end
			-- Only the worker releases ownership, even if PreloadAsync exceeded cap.
			fetching, done = false, true
		end)
		while not done and os.clock() < deadline do task.wait(0.1) end
		return count
	end
	local function needsFetch()
		if fetching or #queued > 0 then return true end
		for _, state in pairs(watched) do if state.Initial then return true end end
		for _, carrier in ipairs(carriers) do
			if (carrier.Attempts or 0) < 2 then
				for _, key in ipairs(carrier.Keys) do if seen[key] ~= "ok" then return true end end
			end
		end
		return false
	end
	local function failedFetch()
		for _, state in pairs(seen) do if state == "failed" then return true end end
		return false
	end
'''

lobby = (BEFORE / 'ReplicatedFirst__Lobby Loading Screen.luau').read_text(encoding='utf-8')
lobby = lobby.replace('local MaterialService = game:GetService("MaterialService")\n', '')
lobby = lobby.replace('local WORKERS = 6\nlocal BATCH = 24\n', '')
start = lobby.index('local CONTENT_PROPERTIES = {')
end = lobby.index('---------------------------------------------------------------------------\n-- The sequence', start)
lobby = lobby[:start] + LOBBY_CENSUS + '\n' + lobby[end:]
lobby = lobby.replace('warn("[LobbyLoading] did not load: " .. id)', 'warn("[LobbyLoading] did not load: " .. tostring(id))')
lobby = lobby.replace('-- every mesh/texture/decal/material the lobby references. Nothing here is a',
    '-- supported meshes/images the lobby references. Nothing here is a')
start = lobby.index('\t-- Fetch everything `roots` reference')
end = lobby.index('\tlocal function quiet(', start)
lobby = lobby[:start] + FETCH + lobby[end:]
start = lobby.index('\tlocal function levelWorlds()')
end = lobby.index('\n\t-- GameManager owns release.', start)
lobby = lobby[:start] + r'''	local function levelWorlds()
		local level, list = announced(), {}
		local names = level == 1 and {"Maze", "Elevator", "Decor", "PuzzleItems"}
			or level == 4 and {"Level 4 Cinema Blender", "PuzzleItems"}
			or {"Level " .. tostring(level) .. " Generated World"}
		for _, name in ipairs(names) do
			local root = workspace:FindFirstChild(name)
			if root then table.insert(list, root) end
		end
		return list
	end
''' + lobby[end:]
lobby = lobby.replace('''\tlocal function coverRound(joined)
\t\tup = {round = true}''', '''\tlocal function coverRound(joined)
\t\tresetFetch()
\t\tup = {round = true}''')
lobby = lobby.replace('''\t\tup = nil
\tend

\t-- Level 5 or 6''', '''\t\tresetFetch()
\t\tup = nil
\tend

\t-- Level 5 or 6''')
lobby = lobby.replace('''\tlocal function coverLive(level, standing)
\t\tlocal cover''', '''\tlocal function coverLive(level, standing)
\t\tresetFetch()
\t\tlocal cover''')
lobby = lobby.replace('''\t\tcover.stage("LEVEL READY", 1)
\t\tcover.drop()''', '''\t\tresetFetch()
\t\tcover.stage("LEVEL READY", 1)
\t\tcover.drop()''')
old_live_fetch = '''\t\t\tfetch({model}, 8, function(done, total)
\t\t\t\tcover.stage(string.format("LOADING THE LEVEL  %d / %d", done, total), 0.45 + 0.5 * done / math.max(1, total), "Meshes, textures, decals and materials.")
\t\t\tend)'''
new_live_fetch = '''\t\t\tlocal fetchDeadline = os.clock() + 8
\t\t\trepeat
\t\t\t\tfetch({model}, math.max(0.1, fetchDeadline - os.clock()), nil)
\t\t\t\ttask.wait(0.1) -- An older generation may still own the engine request.
\t\t\tuntil not still() or os.clock() >= fetchDeadline or (watched[model] and not needsFetch())'''
assert old_live_fetch in lobby, 'Fresh live cover fetch changed; reconcile baseline.'
lobby = lobby.replace(old_live_fetch, new_live_fetch)
lobby = lobby.replace('''\t\tresetFetch()
\t\tcover.stage("LEVEL READY", 1)
\t\tcover.drop()''', '''\t\tlocal incomplete = not model or not watched[model] or needsFetch() or failedFetch()
\t\tresetFetch()
\t\tcover.stage(incomplete and "ENTERING THE LEVEL" or "LEVEL READY", 1)
\t\tcover.drop()''')
lobby = lobby.replace('''\t-- PreloadAsync returns when the files are fetched; the renderer then still decodes and uploads them, and
\t-- surface/material maps arrive through the same request queue. Hold the cover until that queue has stayed
\t-- empty for a moment, then a beat more for the sharp mip levels. Capped, so a slow device is never trapped.''',
'''\t-- This is a bounded settling allowance after measured fetches. An empty
\t-- download queue cannot prove GPU upload, mip sharpness or processed PBR readiness.''')
lobby = lobby.replace('Meshes, textures, decals and materials.', 'Meshes and image downloads.')
lobby = lobby.replace('''\t\t\t\tfetch({model}, 8, function(done, total)''', '''\t\t\t\tfetch({model}, 8, function(done, total)''')
lobby = lobby.replace('''\t\t\t\tcover.stage(string.format("LOADING THE LEVEL  %d / %d", done, total), 0.45 + 0.5 * done / math.max(1, total), "Meshes and image downloads.")''',
'''\t\t\t\tif up == cover and cover.open then
\t\t\t\t\tcover.stage(string.format("LOADING THE LEVEL  %d / %d", done, total), 0.45 + 0.5 * done / math.max(1, total), "Meshes and image downloads.")
\t\t\t\tend''')
(OUT / 'Lobby Loading Screen.luau').write_text(lobby, encoding='utf-8', newline='')

ENTRY_WORKER = r'''	task.spawn(function()
		local ids, carriers, watched, queued = {}, {}, {}, {}
		local lastArrival = os.clock()
		local cursor = 1
		local function nearby(instance)
			local part = instance:IsA("BasePart") and instance or instance:FindFirstAncestorWhichIsA("BasePart")
			-- Room art has CanQuery=false, so spatial overlap queries omit its ceiling.
			return part and part.Transparency < 1
				and (part.Position - request.Position).Magnitude <= 80 + part.Size.Magnitude * 0.5
		end
		local function enqueue(instance, character)
			if not current(request) then return end
			if not CONTENT_PROPERTIES[instance.ClassName] and not instance:IsA("SurfaceAppearance") then return end
			if character or nearby(instance) then
				table.insert(queued, instance)
				lastArrival = os.clock()
				request.AssetsReady = false
			end
		end
		local function watch(root, character)
			if not root or watched[root] then return end
			local connection = root.DescendantAdded:Connect(function(instance) enqueue(instance, character) end)
			watched[root] = true
			table.insert(request.Connections, connection)
			for index, instance in ipairs(root:GetDescendants()) do
				if not current(request) then return end
				enqueue(instance, character)
				if index % 200 == 0 then task.wait() end
			end
		end
		watch(request.Character, true)
		while current(request) do
			local roots = entryWorlds(request.Level)
			for _, root in ipairs(roots) do watch(root, false) end
			local checks = 0
			while cursor <= #queued and current(request) do
				collectAsset(queued[cursor], ids, carriers)
				cursor += 1
				checks += 1
				if checks % 200 == 0 then task.wait() end
			end
			if cursor > #queued then table.clear(queued) cursor = 1 end
			local ready = #roots > 0
			for _, carrier in ipairs(carriers) do
				if carrier.Loaded ~= true and (carrier.Attempts or 0) < 2 then
					while entryPreloadBusy and current(request) do task.wait(0.1) end
					if not current(request) then break end
					entryPreloadBusy = true
					carrier.Attempts = (carrier.Attempts or 0) + 1
					carrier.Loaded = loadCarrier(carrier)
					entryPreloadBusy = false
					if not carrier.Loaded and carrier.Attempts == 2 then
						warn("[RoundEntry] could not fetch nearby visual: " .. tostring(carrier.Keys[1]))
					end
				end
				if carrier.Loaded ~= true then ready = false end
			end
			if current(request) then
				request.AssetsReady = ready and #queued == 0 and os.clock() - lastArrival >= 0.35
			end
			task.wait(0.1)
		end
		for _, connection in ipairs(request.Connections) do connection:Disconnect() end
		table.clear(request.Connections)
	end)
'''

entry = (BEFORE / 'StarterPlayer__StarterPlayerScripts__Round Entry Client.luau').read_text(encoding='utf-8')
entry_content = CONTENT[:CONTENT.index('local function pendingCarriers')]
entry = entry.replace('local active\n', 'local active\nlocal entryPreloadBusy = false\n\n' + entry_content + '\n')
entry = entry.replace('''local function cancel()
	active = nil''', '''local function cancel()
	if active then
		for _, connection in ipairs(active.Connections) do connection:Disconnect() end
		table.clear(active.Connections)
	end
	active = nil''')
root_start = entry.index('\tlocal allowed = {}', entry.index('local function groundReady'))
root_end = entry.index('\tif #allowed == 0 then return false end', root_start)
ROOTS = entry[root_start:root_end].replace('request.Level', 'level')
entry = entry[:root_start] + '\tlocal allowed = entryWorlds(request.Level)\n' + entry[root_end:]
insert = entry.index('local function groundReady')
entry = entry[:insert] + 'local function entryWorlds(level)\n' + ROOTS + '\treturn allowed\nend\n\n' + entry[insert:]
entry = entry.replace('AssetsReady = false, Raycast = RaycastParams.new(),', 'AssetsReady = false, Raycast = RaycastParams.new(), Connections = {},')
start = entry.index('\ttask.spawn(function()\n\t\tlocal assets = {}')
end = entry.index('\ttask.spawn(function()\n\t\tlocal stable', start)
entry = entry[:start] + ENTRY_WORKER + entry[end:]
(OUT / 'Round Entry Client.luau').write_text(entry, encoding='utf-8', newline='')
receipt = []
for name, original in (
    ('Lobby Loading Screen', 'ReplicatedFirst__Lobby Loading Screen'),
    ('Round Entry Client', 'StarterPlayer__StarterPlayerScripts__Round Entry Client'),
):
    baseline = (BEFORE / (original + '.luau')).read_bytes()
    candidate = (OUT / (name + '.luau')).read_bytes()
    row = {
        'name': name, 'baselineSha256': hashlib.sha256(baseline).hexdigest(),
        'baselineBytes': len(baseline), 'candidateSha256': hashlib.sha256(candidate).hexdigest(),
        'candidateBytes': len(candidate), 'candidateFile': (OUT / (name + '.luau')).relative_to(ROOT).as_posix(),
    }
    current_file = ROOT / '.git/stutter-assets-20261009/loading-pool-before' / (original + '.luau')
    if current_file.exists():
        current = current_file.read_bytes()
        # Reconcile only the initial lobby preload owner against the newly
        # verified installed Studio source. Entry and background work are exact.
        reconciled = current.decode('utf-8')
        if name == 'Lobby Loading Screen':
            start = reconciled.index('local settledCount = 0')
            end = reconciled.index('---------------------------------------------------------------------------\n-- The sequence', start)
            preload_region = LOBBY_CENSUS[LOBBY_CENSUS.index('local settledCount = 0'):]
            reconciled = reconciled[:start] + preload_region + '\n' + reconciled[end:]
        reconciled = reconciled.encode('utf-8')
        assert candidate == reconciled, 'Current Studio export differs: reconcile before generating candidates.'
        row.update(scopedBaselineSha256=hashlib.sha256(current).hexdigest(), scopedBaselineBytes=len(current),
                   scopedBaselineFile=current_file.relative_to(ROOT).as_posix())
    receipt.append(row)
(OUT.parent / 'candidate-receipt.json').write_text(json.dumps(receipt, indent=2) + '\n', encoding='utf-8')
print('Wrote two candidates from fresh live exports.')
