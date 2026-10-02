-- Read-only live snapshot. Existing HttpEnabled must already be enabled.
local HS = game:GetService("HttpService")
local SER = game:GetService("SerializationService")
local ENC = game:GetService("EncodingService")
local BASE = "http://127.0.0.1:8891"
local EXPECTED_NATIVE_SHA = "eb4c6cb072f55378c4edbd51987482821174e2e7558334b400429c3ca4507f24"
assert(game.PlaceId == 131311258779917 and game.GameId == 10559217407 and game.CreatorId == 1039373905, "Wrong place/universe/owner")
assert(not game:GetService("RunService"):IsRunning(), "Backup must capture Edit state")
assert(HS.HttpEnabled, "Read-only export requires existing HttpEnabled=true; do not change game settings")
assert(not shared.__r4backupRunning, "R4 read-only export already running")
shared.__r4NativeRecovery = nil -- Session-only state; no persistent instances/settings.

local function sha(raw)
	local digest = ENC:ComputeBufferHash(raw, Enum.HashAlgorithm.Sha256)
	local chars = table.create(buffer.len(digest))
	for index = 0, buffer.len(digest)-1 do chars[index+1] = string.format("%02x", buffer.readu8(digest,index)) end
	return table.concat(chars)
end
local function post(path, value, contentType)
	assert(HS:PostAsync(BASE..path,value,contentType)=="saved", "Receiver did not acknowledge "..path)
end

local function encode(value, declaredType)
	local kind = typeof(value)
	if value == nil then return {type = "nil"} end
	if declaredType == "BinaryString" or kind == "buffer" then
		return {type = "binary", value = buffer.tostring(ENC:Base64Encode(if kind == "buffer" then value else buffer.fromstring(value)))}
	end
	if kind == "string" or kind == "boolean" or kind == "number" then return {type = kind, value = value} end
	if kind == "EnumItem" then return {type = kind, enum = tostring(value.EnumType), value = value.Name, ordinal = value.Value} end
	if kind == "Vector3" or kind == "Color3" then
		return {type = kind, value = if kind == "Vector3" then {value.X, value.Y, value.Z} else {value.R, value.G, value.B}}
	end
	if kind == "Vector2" then return {type = kind, value = {value.X, value.Y}} end
	if kind == "CFrame" then return {type = kind, value = {value:GetComponents()}} end
	if kind == "UDim" then return {type = kind, value = {value.Scale, value.Offset}} end
	if kind == "UDim2" then return {type = kind, value = {value.X.Scale, value.X.Offset, value.Y.Scale, value.Y.Offset}} end
	if kind == "BrickColor" then return {type = kind, value = value.Number} end
	if kind == "NumberRange" then return {type = kind, value = {value.Min, value.Max}} end
	if kind == "Instance" then return {type = kind, path = value:GetFullName(), class = value.ClassName} end
	if kind == "Content" then return {type = kind, value = tostring(value)} end
	return {type = "unsupported", originalType = kind, display = tostring(value)}
end

local function run()
	local previousHttp = HS.HttpEnabled
	local ok, err = pcall(function()
		assert(HS.HttpEnabled == previousHttp, "HttpEnabled changed during export")
		local schema = HS:JSONDecode(HS:GetAsync(BASE .. "/schema", true))
		local classes = {} for class in pairs(schema) do table.insert(classes, class) end table.sort(classes)
		local roots, mapping, services, serviceClasses, scripts, scriptRefs, conflicts, skipped = {}, {}, {}, {}, {}, {}, {}, {}
		local captureId, captureStartMillis = HS:GenerateGUID(false), DateTime.now().UnixTimestampMillis
		local metadata = {placeId = game.PlaceId, universeId = game.GameId, creatorId = game.CreatorId, groupId = game.CreatorId, placeVersion = game.PlaceVersion,
			captureId = captureId, captureStartUnixMillis = captureStartMillis,
			studioVersion = version(), capturedAt = DateTime.now():ToIsoDate(), services = services, roots = mapping,
			skipped = skipped, editorConflicts = conflicts, allChildrenJointSerialization = true,
			method = "SerializationService.SerializeInstancesAsync(all place-service children); native properties and cross-references retained."}
		for _, class in ipairs(classes) do
			local service = game:FindService(class)
			if service then
				if class ~= "Players" then table.insert(serviceClasses,class) end
				local record = {class = class, name = service.Name, properties = {}, propertyErrors = {}, attributes = {}, tags = service:GetTags()}
				for _, property in ipairs(schema[class]) do
					local success, value = pcall(function() return service[property.name] end)
					if property.name == "HttpEnabled" then value = previousHttp end
					if success then record.properties[property.name] = encode(value, property.type)
					else record.propertyErrors[property.name] = tostring(value) end
				end
				for key, value in pairs(service:GetAttributes()) do record.attributes[key] = encode(value) end
				table.insert(services, record)
				-- Editor-session players are not saved game content.
				if class ~= "Players" then
					for _, root in ipairs(service:GetChildren()) do
						if root.Archivable then
							table.insert(roots, root)
							table.insert(mapping, {index = #roots, service = class, name = root.Name, class = root.ClassName,
								path = root:GetFullName(), descendants = #root:GetDescendants()})
						else table.insert(skipped, {path = root:GetFullName(), reason = "Archivable=false"}) end
					end
				end
			end
		end
		for _, root in ipairs(roots) do
			local scan = root:GetDescendants(); table.insert(scan, root)
			for _, instance in ipairs(scan) do
				if instance:IsA("LuaSourceContainer") then
					local source = instance.Source
					local edOk, editor = pcall(function() return game:GetService("ScriptEditorService"):GetEditorSource(instance) end)
					local sourceSHA = sha(buffer.fromstring(source))
					local item = {path = instance:GetFullName(), class = instance.ClassName, source = source,
						sourceBytes = #source, sourceSha256 = sourceSHA, editorSourceSha256 = if edOk then sha(buffer.fromstring(editor)) else nil,
						editorMatch = edOk and source == editor, editorSource = if edOk and source ~= editor then editor else nil}
					if not edOk then item.editorError = tostring(editor) end
					if not item.editorMatch then table.insert(conflicts, item.path) end
					table.insert(scripts, item)
					table.insert(scriptRefs, instance)
				end
			end
		end
		metadata.rootCount = #roots; metadata.scriptCount = #scripts
		assert(#conflicts == 0 and #skipped == 0, "Export has Source/editor conflicts or skipped roots")
		-- Studio caps each HTTP POST at 1 MB. Preserve exact JSON bytes across bounded chunks.
		local sourceJSON = HS:JSONEncode(scripts)
		local sourceChunkSize = 750000
		local sourceParts = math.ceil(#sourceJSON / sourceChunkSize)
		local sourceSHA = sha(buffer.fromstring(sourceJSON))
		metadata.sourceTransfer = {parts=sourceParts,bytes=#sourceJSON,sha256=sourceSHA,chunkBytes=sourceChunkSize}
		for index = 0, sourceParts-1 do
			local first = index*sourceChunkSize+1
			post("/source-part?index="..index, string.sub(sourceJSON,first,math.min(first+sourceChunkSize-1,#sourceJSON)),Enum.HttpContentType.TextPlain)
			shared.__r4backupStatus = "received source part "..(index+1).."/"..sourceParts
		end
		post("/sources-finalize", HS:JSONEncode(metadata.sourceTransfer),Enum.HttpContentType.ApplicationJson)
		local groups = game:GetService("PhysicsService"):GetRegisteredCollisionGroups()
		metadata.collisionGroups = groups
		metadata.collisionMatrix = {}
		for _, a in ipairs(groups) do for _, b in ipairs(groups) do
			table.insert(metadata.collisionMatrix, {a.name, b.name, game:GetService("PhysicsService"):CollisionGroupsAreCollidable(a.name, b.name)})
		end end
		metadata.materialOverrides = {}
		for _, material in ipairs(Enum.Material:GetEnumItems()) do
			local materialOk, override = pcall(function() return game:GetService("MaterialService"):GetBaseMaterialOverride(material) end)
			if materialOk and override ~= "" then metadata.materialOverrides[material.Name] = override end
		end
		shared.__r4backupStatus = "serializing " .. #roots .. " roots"
		local native = SER:SerializeInstancesAsync(roots)
		metadata.nativeBytes = buffer.len(native)
		metadata.expectedDescendants = 0
		for _, r in ipairs(mapping) do metadata.expectedDescendants += r.descendants + 1 end
		local chunkSize = 750000
		metadata.nativeParts = math.ceil(buffer.len(native) / chunkSize)
		metadata.nativeSHA256 = sha(native)
		metadata.nativeMatchesPriorCheckpoint = metadata.nativeSHA256 == EXPECTED_NATIVE_SHA
		if not metadata.nativeMatchesPriorCheckpoint then
			for index = 0, metadata.nativeParts - 1 do
				local offset = index * chunkSize
				post("/native?index=" .. index, buffer.readstring(native, offset, math.min(chunkSize, buffer.len(native) - offset)), Enum.HttpContentType.TextPlain)
				shared.__r4backupStatus = "received native part " .. (index + 1) .. "/" .. metadata.nativeParts
			end
		end
		-- Recheck every exact Source/editor baseline after native serialization.
		local markerSources = {}
		for index, row in ipairs(scripts) do
			local cursor = scriptRefs[index]
			assert(cursor:IsDescendantOf(game) and cursor:GetFullName() == row.path and cursor.ClassName == row.class and cursor.Source == row.source
				and game:GetService("ScriptEditorService"):GetEditorSource(cursor) == row.source,
				"Source/editor changed during capture: " .. row.path)
			table.insert(markerSources, {instance=cursor,path=row.path,class=row.class,source=row.source,
				sourceBytes=row.sourceBytes,sha256=row.sourceSha256,editorSourceSha256=row.editorSourceSha256,editorMatch=true})
		end
		for index, root in ipairs(roots) do
			local row=mapping[index]
			assert(root.Parent==game:FindService(row.service) and root:GetFullName()==row.path
				and root.ClassName==row.class and #root:GetDescendants()==row.descendants,"Native root changed during capture: "..row.path)
		end
		metadata.captureFinishedUnixMillis = DateTime.now().UnixTimestampMillis
		post("/metadata", HS:JSONEncode(metadata), Enum.HttpContentType.ApplicationJson)
		-- This proves receipt of the capture, not recoverability of disk artifacts.
		-- A separate verified /checkpoint receipt must match before any installer trusts it.
		shared.__r4NativeRecovery = {
			schema="lobby-r4-session-recovery-baseline-v1",captureId=captureId,
			placeId=game.PlaceId,universeId=game.GameId,groupId=game.CreatorId,
			capturedAtUnix=math.floor(metadata.captureFinishedUnixMillis/1000),
			capturedAt=metadata.capturedAt,captureStartUnixMillis=captureStartMillis,
			captureFinishedUnixMillis=metadata.captureFinishedUnixMillis,createdAtMonotonic=time(),
			nativeSHA256=metadata.nativeSHA256,nativeBytes=metadata.nativeBytes,
			roots=roots,rootMappings=mapping,serviceClasses=serviceClasses,sourceRows=markerSources,sourceCount=#scripts,
			allPostsAcknowledged=true,diskRecoveryVerified=false,
		}
		shared.__r4backupStatus = "complete bytes=" .. metadata.nativeBytes .. " descendants=" .. metadata.expectedDescendants .. " conflicts=" .. #conflicts
	end)
	assert(HS.HttpEnabled == previousHttp, "Read-only export unexpectedly changed HttpEnabled")
	shared.__r4backupRunning = nil
	if not ok then shared.__r4backupStatus = "FAILED: " .. tostring(err)
		shared.__r4NativeRecovery = nil
		pcall(function() HS:PostAsync(BASE .. "/error", HS:JSONEncode({error=tostring(err)}), Enum.HttpContentType.ApplicationJson) end)
	end
end

shared.__r4backupRunning = true
task.spawn(run)
return "R4 read-only export started. Inspect shared.__r4backupStatus; receiver will save fresh-source files."
