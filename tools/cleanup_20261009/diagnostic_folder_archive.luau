-- Offline verification only. Native archive bytes and fresh Studio facts are inputs.
local rbx = require("@lune/roblox")
local serde = require("@lune/serde")

local Module = {}
Module.Names = table.freeze({
	"TEMP_PipeEntityLobbyRigResult_0748Z",
	"TEMP_PipeEntityMPResult_0457Z", "TEMP_PipeEntityMPResult_0503Z",
	"TEMP_PipeEntityMPResult_0508Z", "TEMP_PipeEntityMPResult_0638Z",
	"TEMP_PipeEntityMPResult_0706Z", "TEMP_PipeEntityMPResult_1609Z",
	"TEMP_PipeEntityMPResult_1624Z", "TEMP_PipeEntityMPResult_1633Z",
	"TEMP_PipeEntityMPResult_1640Z", "TEMP_PipeEntityMPResult_1648Z",
	"TEMP_PipeEntityMultiplayerLaunch",
})

local function equal(a, b)
	if type(a) ~= type(b) then return false end
	if type(a) ~= "table" then return a == b end
	for key, value in pairs(a) do if not equal(value, b[key]) then return false end end
	for key in pairs(b) do if a[key] == nil then return false end end
	return true
end

local function encode(value)
	local kind = typeof(value)
	if kind == "string" or kind == "boolean" then return {type = kind, value = value} end
	if kind == "number" then
		assert(value == value and math.abs(value) < math.huge, "Non-finite numeric attribute")
		return {type = kind, value = value}
	end
	local components
	if kind == "Vector2" then components = {value.X, value.Y}
	elseif kind == "Vector3" then components = {value.X, value.Y, value.Z}
	elseif kind == "Color3" then components = {value.R, value.G, value.B}
	elseif kind == "CFrame" then components = {value:GetComponents()}
	elseif kind == "UDim" then components = {value.Scale, value.Offset}
	elseif kind == "UDim2" then components = {value.X.Scale, value.X.Offset, value.Y.Scale, value.Y.Offset}
	elseif kind == "Rect" then components = {value.Min.X, value.Min.Y, value.Max.X, value.Max.Y}
	elseif kind == "NumberRange" then components = {value.Min, value.Max}
	else error("Unsupported attribute type: " .. kind) end
	for _, component in ipairs(components) do
		assert(component == component and math.abs(component) < math.huge, "Non-finite attribute component")
	end
	return {type = kind, value = components}
end

local function tagsOf(inst)
	local tags = inst:GetTags()
	table.sort(tags)
	return tags
end

local function arrayOf(value, label)
	assert(type(value) == "table", "Missing " .. label)
	local count = 0
	for key in pairs(value) do
		assert(type(key) == "number" and key % 1 == 0 and key >= 1 and key <= #value,
			"Non-array " .. label)
		count += 1
	end
	assert(count == #value, "Sparse " .. label)
	return value
end

local function expectedTags(tags)
	arrayOf(tags, "tag facts")
	local sorted, seen = {}, {}
	for _, tag in ipairs(tags) do
		assert(type(tag) == "string" and not seen[tag], "Invalid/duplicate tag fact")
		seen[tag] = true
		table.insert(sorted, tag)
	end
	table.sort(sorted)
	return sorted
end

local function propertyOf(root, key)
	-- Lune's DOM retains these newer native properties although its Lua getter
	-- cannot expose them. This is one known Folder with no children, so its
	-- serialized Properties block has exactly one native value per key.
	if key == "Capabilities" or key == "IconTint" then
		local xml = rbx.serializeModel({root}, true)
		if key == "Capabilities" then
			local bits = xml:match('<SecurityCapabilities name="Capabilities">(%d+)</SecurityCapabilities>')
			assert(bits == "0", "Unsupported/missing nonzero native capability bitset")
			return "" -- Studio tostring of the empty capability set.
		end
		local r, g, b = xml:match('<Color3 name="IconTint">%s*<R>([^<]+)</R>%s*<G>([^<]+)</G>%s*<B>([^<]+)</B>%s*</Color3>')
		assert(r and tonumber(r) and tonumber(g) and tonumber(b), "Missing native IconTint components")
		return {tonumber(r), tonumber(g), tonumber(b)}
	end
	local ok, value = pcall(function() return root[key] end)
	assert(ok, "Lune cannot read fact property " .. key .. ": " .. root.Name)
	return value
end

local function checkRoot(root, row)
	assert(root.ClassName == "Folder" and row.class == "Folder", "Root class differs: " .. row.name)
	assert(root.Name == row.name, "Root name differs")
	assert(root.Parent == nil, "Archive root must be unparented: " .. row.name)
	assert(row.children == 0 and #root:GetChildren() == 0, "Root children are not zero: " .. row.name)
	assert(type(row.archivable) == "boolean" and root.Archivable == row.archivable,
		"Archivable differs: " .. row.name)
	assert(equal(tagsOf(root), expectedTags(row.tags)), "Tags differ: " .. row.name)
	local attributes = {}
	for key, value in pairs(root:GetAttributes()) do attributes[key] = encode(value) end
	assert(type(row.attributes) == "table" and equal(attributes, row.attributes), "Attributes differ: " .. row.name)
	for key, expected in pairs(row.properties or {}) do
		assert(key == "Sandboxed" or key == "IconTint" or key == "Capabilities", "Unsupported fact property: " .. key)
		assert(equal(propertyOf(root, key), expected), "Property differs: " .. key .. " / " .. row.name)
	end
end

local function checkRoots(roots, facts)
	arrayOf(facts.roots, "root facts")
	assert(#roots == 12 and #facts.roots == 12, "Archive must contain exactly 12 roots")
	local allowed, found = {}, {}
	for _, name in ipairs(Module.Names) do allowed[name] = true end
	local rows = {}
	for _, row in ipairs(facts.roots) do
		assert(type(row) == "table" and allowed[row.name], "Unexpected fact root")
		assert(not rows[row.name], "Duplicate fact root: " .. row.name)
		rows[row.name] = row
	end
	for _, root in ipairs(roots) do
		assert(allowed[root.Name] and rows[root.Name], "Unexpected native root: " .. root.Name)
		assert(not found[root.Name], "Duplicate native root: " .. root.Name)
		found[root.Name] = true
		checkRoot(root, rows[root.Name])
	end
end

function Module.Verify(facts, nativeBytes)
	assert(type(facts) == "table" and facts.schema == "folder-diagnostic-archive-v1", "Wrong archive schema")
	assert(facts.placeId == 131311258779917 and facts.universeId == 10559217407, "Wrong archive place")
	assert(type(nativeBytes) == "string" and #nativeBytes == facts.nativeBytes, "Native byte length differs")
	local nativeSHA = serde.hash("sha256", nativeBytes)
	assert(nativeSHA == facts.nativeSHA256, "Native SHA256 differs")
	assert(type(facts.roots) == "table", "Missing root facts")
	local roots = rbx.deserializeModel(nativeBytes)
	checkRoots(roots, facts)
	local canonical = rbx.serializeModel(roots)
	local reopened = rbx.deserializeModel(canonical)
	checkRoots(reopened, facts)
	assert(rbx.serializeModel(reopened) == canonical, "Canonical native reload differs")
	return {
		schema = "folder-diagnostic-archive-verification-v1", verified = true,
		placeId = facts.placeId, universeId = facts.universeId, rootCount = 12,
		nativeSHA256 = nativeSHA, nativeBytes = #nativeBytes,
		canonicalSHA256 = serde.hash("sha256", canonical), canonicalBytes = #canonical,
		names = table.clone(Module.Names), nativeReloadEqual = true,
		propertyRead = "Sandboxed getter; preserved XML DOM for IconTint and zero Capabilities",
		limits = "Offline Lune native decode/re-encode/reopen and typed facts only; nonzero capabilities refused. Not Studio referent/CAS, gameplay, restore-to-place or performance certification.",
	}
end

return Module
