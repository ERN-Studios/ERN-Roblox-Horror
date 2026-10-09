-- Offline guards/lifecycle test; not a native GUI/gameplay pass.
local Archive = require("./AuthoringArchive")
local methods = {}
local signal = {Connect = function() return {Disconnect = function() end} end}
local function new(class, name, parent)
	local fields = {ClassName = class, Name = name, children = {}, Source = "", editor = ""}
	local object = setmetatable({}, {
		__index = function(_, key) return methods[key] or fields[key] end,
		__newindex = function(self, key, value)
			if key == "Parent" then
				if fields.Parent then
					for i, child in ipairs(fields.Parent.children) do
						if child == self then table.remove(fields.Parent.children, i); break end
					end
				end
				if value then table.insert(value.children, self) end
			end
			fields[key] = value
		end,
	})
	object.Parent = parent
	return object
end
function methods:GetChildren() return table.clone(self.children) end
function methods:GetDescendants()
	local result = {}
	local function walk(root)
		for _, child in ipairs(root.children) do table.insert(result, child); walk(child) end
	end
	walk(self)
	return result
end
function methods:FindFirstChild(name)
	for _, child in ipairs(self.children) do if child.Name == name then return child end end
	return nil
end
function methods:GetService(name) return self:FindFirstChild(name) end
function methods:IsA(class)
	return self.ClassName == class or (class == "LuaSourceContainer" and
		(self.ClassName == "ModuleScript" or self.ClassName == "Script" or self.ClassName == "LocalScript"))
end
function methods:IsDescendantOf(root)
	local p = self.Parent
	while p do if p == root then return true end; p = p.Parent end
	return false
end
function methods:GetFullName()
	return self.Parent and self.Parent:GetFullName() .. "." .. self.Name or self.Name
end
function methods:Destroy()
	assert(not self.original, "Destroy attempted on an authoritative original")
	for _, child in ipairs(self:GetChildren()) do child:Destroy() end
	self.Parent = nil
end

local function fixture()
	local data = new("DataModel", "game")
	data.PlaceId = 131311258779917; data.GameId = 10559217407
	data.DescendantAdded = signal; data.DescendantRemoving = signal
	local runService = new("RunService", "RunService", data)
	runService.IsRunning = function() return false end
	local rs = new("ReplicatedStorage", "ReplicatedStorage", data)
	local ss = new("ServerStorage", "ServerStorage", data)
	local roots, owners = {}, {}
	for _, name in ipairs({"ZyntraShopUI", "ZyntraHUD"}) do
		local owner = new("Folder", name, rs)
		local root = new("Folder", "Imports", owner)
		root.original = true
		local frame = new("Frame", "History", root); frame.original = true
		local image = new("ImageLabel", "Image", frame); image.original = true
		new("Folder", "Templates", owner).original = true
		table.insert(roots, root); table.insert(owners, owner)
	end
	local runtime = new("Script", "Runtime", data)
	runtime.Source = "return true"; runtime.editor = runtime.Source
	local probe = new("ModuleScript", "FreshProbe", ss)
	probe.Source = "Imports tool source"; probe.editor = probe.Source
	local editor = {GetEditorSource = function(_, object) return object.editor end}
	return data, rs, ss, roots, owners, runtime, probe, editor
end

local checks = 0
local function rejects(callback, expected)
	local ok, problem = pcall(callback)
	assert(not ok and string.find(tostring(problem), expected, 1, true), tostring(problem))
	checks += 1
end

-- Provide only native constructors/scheduling at the module's isolated boundary.
-- Luau require sandboxes globals, so an injectable environment is applied below.
return {fixture = fixture, rejects = rejects, new = new, run = function(archive)
	local data, _, ss, roots, owners, _, probe, editor = fixture()
	local plan = archive.Prepare(data, editor, probe)
	local report = archive.Apply(plan)
	assert(report.archivedDescendants == 4 and report.scannedScripts == 1)
	assert(roots[1]:IsDescendantOf(ss) and roots[2]:IsDescendantOf(ss))
	assert(owners[1]:FindFirstChild("Templates") and owners[2]:FindFirstChild("Templates"))
	archive.Rollback(plan)
	assert(roots[1].Parent == owners[1] and roots[2].Parent == owners[2])
	assert(ss:FindFirstChild("OptimizationAuthoringArchive") == nil)
	checks += 1

	for _, case in ipairs({"reference", "source", "editor", "hierarchy"}) do
		local d, _, storage, candidates, _, runtime, staged, ses = fixture()
		local prepared = archive.Prepare(d, ses, staged)
		if case == "reference" then new("ObjectValue", "Ref", d).Value = candidates[1]
		elseif case == "source" then runtime.Source = "return false"; runtime.editor = runtime.Source
		elseif case == "editor" then runtime.editor = "unsaved change"
		else candidates[1]:GetChildren()[1].Name = "Concurrent rename" end
		rejects(function() archive.Apply(prepared) end,
			case == "reference" and "External instance reference" or case == "editor" and "Editor conflict" or
			case == "source" and "baseline changed" or "hierarchy changed")
		assert(candidates[1].Parent == prepared.rows[1].owner)
		assert(storage:FindFirstChild("OptimizationAuthoringArchive") == nil)
	end

	local d, _, _, candidates, _, runtime, staged, ses = fixture()
	runtime.Source = "return script.Parent.Imports"; runtime.editor = runtime.Source
	rejects(function() archive.Prepare(d, ses, staged) end, "Import reference")
	runtime.Source = "return true"; runtime.editor = runtime.Source
	local prepared = archive.Prepare(d, ses, staged)
	archive.Apply(prepared)
	new("Folder", "Unexpected", prepared.archive).original = true
	rejects(function() archive.Rollback(prepared) end, "wrapper changed")
	assert(candidates[1]:IsDescendantOf(prepared.archive))

	for _, case in ipairs({"owner", "play", "place", "adornee"}) do
		local model, rs, storage, imports, folders, _, exactProbe, service = fixture()
		local plan = archive.Prepare(model, service, exactProbe)
		if case == "owner" then folders[1].Parent = storage
		elseif case == "play" then model:GetService("RunService").IsRunning = function() return true end
		elseif case == "place" then model.PlaceId = 1
		else new("Highlight", "OutsideAdornee", rs).Adornee = imports[1]:GetChildren()[1] end
		rejects(function() archive.Apply(plan) end, case == "owner" and "Missing instance" or
			case == "play" and "requires Edit" or case == "place" and "Unexpected place" or "External instance reference")
		assert(storage:FindFirstChild("OptimizationAuthoringArchive") == nil)
	end
	local model, rs, storage, imports, folders, _, exactProbe, service = fixture()
	local plan = archive.Prepare(model, service, exactProbe)
	archive.Apply(plan)
	folders[1].Parent = storage
	rejects(function() archive.Rollback(plan) end, "Missing instance")
	assert(imports[1]:IsDescendantOf(plan.archive))
	folders[1].Parent = rs
	archive.Rollback(plan)
	print("archive guards/lifecycle: " .. tostring(checks) .. " cases passed")
end}
