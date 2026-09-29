-- Read-only live snapshot. HttpEnabled is temporarily enabled for localhost and restored.
local HS = game:GetService("HttpService")
local SER = game:GetService("SerializationService")
local ENC = game:GetService("EncodingService")
local BASE = "http://127.0.0.1:8877"
assert(game.PlaceId == 131311258779917, "Wrong place")
assert(not game:GetService("RunService"):IsRunning(), "Backup must capture Edit state")
assert(not shared.__l6backupRunning, "Backup already running")

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
		HS.HttpEnabled = true
		local schema = HS:JSONDecode(HS:GetAsync(BASE .. "/schema", true))
		local classes = {} for class in pairs(schema) do table.insert(classes, class) end table.sort(classes)
		local roots, mapping, services, scripts, conflicts, skipped = {}, {}, {}, {}, {}, {}
		local metadata = {placeId = game.PlaceId, universeId = game.GameId, placeVersion = game.PlaceVersion,
			studioVersion = version(), capturedAt = DateTime.now():ToIsoDate(), services = services, roots = mapping,
			skipped = skipped, editorConflicts = conflicts, allChildrenJointSerialization = true,
			method = "SerializationService.SerializeInstancesAsync(all place-service children); native properties and cross-references retained."}
		for _, class in ipairs(classes) do
			local service = game:FindService(class)
			if service then
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
					local item = {path = instance:GetFullName(), class = instance.ClassName, source = source,
						editorMatch = edOk and source == editor, editorSource = if edOk and source ~= editor then editor else nil}
					if not edOk then item.editorError = tostring(editor) end
					if not item.editorMatch then table.insert(conflicts, item.path) end
					table.insert(scripts, item)
				end
			end
		end
		metadata.rootCount = #roots; metadata.scriptCount = #scripts
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
		shared.__l6backupStatus = "serializing " .. #roots .. " roots"
		local native = SER:SerializeInstancesAsync(roots)
		metadata.nativeBytes = buffer.len(native)
		metadata.expectedDescendants = 0
		for _, r in ipairs(mapping) do metadata.expectedDescendants += r.descendants + 1 end
		local chunkSize = 750000
		metadata.nativeParts = math.ceil(buffer.len(native) / chunkSize)
		for index = 0, metadata.nativeParts - 1 do
			local offset = index * chunkSize
			HS:PostAsync(BASE .. "/native?index=" .. index, buffer.readstring(native, offset, math.min(chunkSize, buffer.len(native) - offset)), Enum.HttpContentType.TextPlain)
			shared.__l6backupStatus = "received native part " .. (index + 1) .. "/" .. metadata.nativeParts
		end
		local scriptJson = HS:JSONEncode(scripts)
		metadata.scriptJsonParts = math.ceil(#scriptJson / chunkSize)
		for index = 0, metadata.scriptJsonParts - 1 do
			HS:PostAsync(BASE .. "/scriptchunk?index=" .. index, scriptJson:sub(index * chunkSize + 1, (index + 1) * chunkSize), Enum.HttpContentType.TextPlain)
		end
		HS:PostAsync(BASE .. "/metadata", HS:JSONEncode(metadata), Enum.HttpContentType.ApplicationJson)
		shared.__l6backupStatus = "complete bytes=" .. metadata.nativeBytes .. " descendants=" .. metadata.expectedDescendants .. " conflicts=" .. #conflicts
	end)
	HS.HttpEnabled = previousHttp
	shared.__l6backupRunning = nil
	if not ok then shared.__l6backupStatus = "FAILED: " .. tostring(err) end
end

shared.__l6backupRunning = true
task.spawn(run)
return "Native snapshot started. Inspect shared.__l6backupStatus."
