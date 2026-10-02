-- Local-only conversion; never connects to or mutates Studio.
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local rbx = require("@lune/roblox")
local root = assert(process.args[1], "Pass native-backup directory")
local metadata = serde.decode("json", fs.readFile(root .. "/metadata.json"))
local sourceRecords = serde.decode("json", fs.readFile(root .. "/scripts.json"))
local instances = rbx.deserializeModel(fs.readFile(root .. "/all-service-children.rbxm"))
assert(#instances == #metadata.roots, "Native root count mismatch")
local game = rbx.Instance.new("DataModel")
local services, report = {}, {propertyErrors = {}, sourceErrors = {}, rootErrors = {}, limitations = {}}
for _, service in metadata.services do
	local instance = game:GetService(service.class)
	instance.Name = service.name
	services[service.class] = instance
end
for index, instance in instances do
	local map = metadata.roots[index]
	assert(instance.Name == map.name and instance.ClassName == map.class,
		"Native root order mismatch " .. index .. ": " .. instance.Name .. " / " .. map.name)
	instance.Parent = assert(services[map.service])
	local count = #instance:GetDescendants()
	-- Engine-generated Status children have Archivable=false and Studio intentionally omits them.
	local omittedStatus = if map.path == "Workspace.StarterCharacter" or map.path == "Workspace.Dummy" then 1 else 0
	if count ~= map.descendants - omittedStatus then table.insert(report.rootErrors, {path = map.path, expected = map.descendants - omittedStatus, actual = count}) end
end

local function resolve(path)
	local cursor = game
	for token in path:gmatch("[^%.]+") do
		cursor = cursor and cursor:FindFirstChild(token)
	end
	return cursor
end
local function decode(value)
	if value.type == "nil" then return nil end
	if value.type == "number" or value.type == "boolean" or value.type == "string" then return value.value end
	if value.type == "binary" then return serde.decode("base64", value.value) end
	if value.type == "EnumItem" then return rbx.Enum[value.enum][value.value] end
	if value.type == "Instance" then return resolve(value.path) end
	if value.type == "Vector3" then return rbx.Vector3.new(table.unpack(value.value)) end
	if value.type == "Vector2" then return rbx.Vector2.new(table.unpack(value.value)) end
	if value.type == "Color3" then return rbx.Color3.new(table.unpack(value.value)) end
	if value.type == "CFrame" then return rbx.CFrame.new(table.unpack(value.value)) end
	if value.type == "UDim" then return rbx.UDim.new(table.unpack(value.value)) end
	if value.type == "UDim2" then return rbx.UDim2.new(table.unpack(value.value)) end
	if value.type == "BrickColor" then return rbx.BrickColor.new(value.value) end
	if value.type == "NumberRange" then return rbx.NumberRange.new(table.unpack(value.value)) end
	error("Unsupported property type " .. value.type)
end
for _, service in metadata.services do
	local instance = services[service.class]
	for name, value in service.properties do
		local ok, err = pcall(function() instance[name] = decode(value) end)
		if not ok then table.insert(report.propertyErrors, {service = service.class, property = name, error = tostring(err)}) end
	end
	for name, value in service.attributes do
		local ok, err = pcall(function() instance:SetAttribute(name, decode(value)) end)
		if not ok then table.insert(report.propertyErrors, {service = service.class, attribute = name, error = tostring(err)}) end
	end
	for _, tag in service.tags do instance:AddTag(tag) end
	for property, err in service.propertyErrors do
		table.insert(report.limitations, {service = service.class, property = property, reason = "Live Studio cannot read property: " .. err})
	end
end
for _, source in sourceRecords do
	local found = resolve(source.path)
	if not found or found.Source ~= source.source then
		table.insert(report.sourceErrors, {path = source.path, reason = if found then "source mismatch" else "path not found"})
	end
end
for material, override in metadata.materialOverrides do
	local ok, err = pcall(function() services.MaterialService[material .. "Name"] = override end)
	if not ok then table.insert(report.propertyErrors, {service = "MaterialService", property = material .. "Name", error = tostring(err)}) end
end
report.intentionallyOmitted = {
	{path = "Workspace.StarterCharacter.Humanoid.Status", class = "Status", reason = "Archivable=false engine status"},
	{path = "Workspace.Dummy.Humanoid.Status", class = "Status", reason = "Archivable=false engine status"},
}
report.descendants = #game:GetDescendants()
report.nativeContentInstances = metadata.expectedDescendants
report.services = #metadata.services
report.scriptCount = #sourceRecords
if #report.rootErrors > 0 or #report.sourceErrors > 0 then
	print(serde.encode("json", {rootErrors = report.rootErrors, sourceErrors = report.sourceErrors}, true))
end
assert(#report.rootErrors == 0, "Native descendants mismatch")
assert(#report.sourceErrors == 0, "Native script sources mismatch")
local placeFile = if root:match("native%-after/?$") then "AfterLevel6-AuthoritativeStudio.rbxl"
	else "BeforeLevel6-AuthoritativeStudio.rbxl"
local output = root .. "/" .. placeFile
local encoded = rbx.serializePlace(game)
fs.writeFile(output, encoded)
local reopened = rbx.deserializePlace(encoded)
report.reopenedDescendants = #reopened:GetDescendants()
report.nativePlaceBytes = #encoded
report.output = output
assert(report.reopenedDescendants == report.descendants, "Reopened place count mismatch")
fs.writeFile(root .. "/native-place-verification.json", serde.encode("json", report, true))
print(serde.encode("json", {output = output, bytes = #encoded, descendants = report.descendants,
	propertyErrors = #report.propertyErrors, unreadableProperties = #report.limitations,
	sourceErrors = #report.sourceErrors, scriptCount = #sourceRecords}, true))
