-- Edit-only tool. Reparent the reviewed import history; never delete originals.
-- Prepare and Apply must run in the same isolated probe invocation after backup.
local Archive = {}
local TARGETS = {"ZyntraShopUI", "ZyntraHUD"}

local function editOnly(dataModel)
	assert(not dataModel:GetService("RunService"):IsRunning(), "Archive requires Edit; preserve the owner's playtest")
	assert(dataModel.PlaceId == 131311258779917 and dataModel.GameId == 10559217407, "Unexpected place/universe")
end

local function unique(parent, name)
	local result
	for _, child in ipairs(parent:GetChildren()) do
		if child.Name == name then
			assert(result == nil, "Ambiguous instance: " .. name)
			result = child
		end
	end
	assert(result, "Missing instance: " .. name)
	return result
end

local function scanReferences(dataModel, roots, editorService, probeScript)
	local scan = {scripts = {}, references = {}}
	local changed = false
	local added = dataModel.DescendantAdded:Connect(function() changed = true end)
	local removed = dataModel.DescendantRemoving:Connect(function() changed = true end)
	local ok, problem = xpcall(function()
	for i, inst in ipairs(dataModel:GetDescendants()) do
		if inst:IsA("LuaSourceContainer") and inst ~= probeScript then
			local source = inst.Source
			assert(editorService:GetEditorSource(inst) == source, "Editor conflict: " .. inst:GetFullName())
			assert(not string.find(source, "Imports", 1, true), "Import reference requires review: " .. inst:GetFullName())
			table.insert(scan.scripts, {instance = inst, source = source, parent = inst.Parent, name = inst.Name})
		end
		local keys = {}
		if inst:IsA("ObjectValue") then keys = {"Value"}
		elseif inst:IsA("BillboardGui") or inst:IsA("SurfaceGui") or inst:IsA("PVAdornment") or inst:IsA("Highlight") then keys = {"Adornee"}
		elseif inst:IsA("JointInstance") or inst:IsA("WeldConstraint") or inst:IsA("NoCollisionConstraint") then keys = {"Part0", "Part1"}
		elseif inst:IsA("Model") then keys = {"PrimaryPart"}
		elseif inst:IsA("Camera") then keys = {"CameraSubject"} end
		for _, key in ipairs(keys) do
			local value = inst[key]
			table.insert(scan.references, {instance = inst, key = key, value = value})
			if value then
				for _, root in ipairs(roots) do
					assert(inst:IsDescendantOf(root) or not (value == root or value:IsDescendantOf(root)),
						"External instance reference targets import history: " .. inst:GetFullName() .. "." .. key)
				end
			end
		end
		if i % 2000 == 0 then task.wait() end
	end
	assert(not changed, "DataModel membership changed during reference scan; reread")
	end, debug.traceback)
	added:Disconnect(); removed:Disconnect()
	if not ok then error(problem) end
	return scan
end

local function verifyScan(scan, dataModel, editorService)
	for _, row in ipairs(scan.scripts) do
		assert(row.instance:IsDescendantOf(dataModel) and row.instance.Parent == row.parent and row.instance.Name == row.name,
			"Source identity changed")
		assert(row.instance.Source == row.source and editorService:GetEditorSource(row.instance) == row.source,
			"Source/editor baseline changed: " .. row.instance:GetFullName())
	end
	for _, row in ipairs(scan.references) do
		assert(row.instance:IsDescendantOf(dataModel) and row.instance[row.key] == row.value,
			"Instance reference changed during scan")
	end
end

function Archive.Prepare(dataModel, editorService, probeScript)
	editOnly(dataModel)
	assert(probeScript and probeScript.ClassName == "ModuleScript", "Supply the exact fresh staging ModuleScript")
	local rs = dataModel:GetService("ReplicatedStorage")
	local ss = dataModel:GetService("ServerStorage")
	assert(ss:FindFirstChild("OptimizationAuthoringArchive") == nil, "Archive already exists; review rather than overwrite")
	local plan = {dataModel = dataModel, editorService = editorService, probeScript = probeScript, replicatedStorage = rs,
		serverStorage = ss, roots = {}, rows = {}}
	for _, name in ipairs(TARGETS) do
		local owner = unique(rs, name)
		local root = unique(owner, "Imports")
		assert(root:IsA("Folder"), "Imports is not a Folder: " .. name)
		local members = root:GetDescendants()
		local identities = {}
		for _, member in ipairs(members) do
			assert(not member:IsA("LuaSourceContainer"), "Code within import history requires separate review")
			table.insert(identities, {instance = member, parent = member.Parent, name = member.Name})
		end
		table.insert(plan.roots, root)
		table.insert(plan.rows, {instance = root, owner = owner, name = name, identities = identities,
			beforePath = root:GetFullName(), descendantCount = #members})
	end
	plan.scan = scanReferences(dataModel, plan.roots, editorService, probeScript)
	return plan
end

local function verifyBaseline(plan)
	assert(plan.serverStorage:FindFirstChild("OptimizationAuthoringArchive") == nil, "Archive appeared concurrently")
	for _, row in ipairs(plan.rows) do
		assert(unique(plan.replicatedStorage, row.name) == row.owner and row.owner.Parent == plan.replicatedStorage,
			"Zyntra owner identity changed")
		assert(unique(row.owner, "Imports") == row.instance, "Import identity changed")
		assert(row.instance.Parent == row.owner and row.instance.Name == "Imports", "Import root changed")
		assert(#row.instance:GetDescendants() == row.descendantCount, "Import membership changed")
		for _, identity in ipairs(row.identities) do
			assert(identity.instance.Parent == identity.parent and identity.instance.Name == identity.name,
				"Import hierarchy changed")
		end
	end
	verifyScan(plan.scan, plan.dataModel, plan.editorService)
end

function Archive.Apply(plan)
	editOnly(plan.dataModel)
	-- Scan once more after preparation to include newly added reference containers.
	local fresh = scanReferences(plan.dataModel, plan.roots, plan.editorService, plan.probeScript)
	verifyBaseline(plan) -- no yield between this guard and parenting the two roots
	verifyScan(fresh, plan.dataModel, plan.editorService)
	local archive = Instance.new("Folder")
	archive.Name = "OptimizationAuthoringArchive"
	local moved = {}
	local ok, problem = xpcall(function()
		archive.Parent = plan.serverStorage
		for _, row in ipairs(plan.rows) do
			local owner = Instance.new("Folder")
			owner.Name = row.name
			owner.Parent = archive
			row.wrapper = owner
			table.insert(moved, row)
			row.instance.Parent = owner
			assert(#row.instance:GetDescendants() == row.descendantCount, "Archive membership mismatch")
		end
	end, debug.traceback)
	if not ok then
		for i = #moved, 1, -1 do moved[i].instance.Parent = moved[i].owner end
		archive:Destroy() -- only the empty, test-owned wrapper; originals have been restored
		error(problem)
	end
	plan.archive = archive
	return Archive.Report(plan)
end

function Archive.Report(plan)
	local out = {roots = {}, archivedDescendants = 0, scannedScripts = #plan.scan.scripts}
	for _, row in ipairs(plan.rows) do
		table.insert(out.roots, {beforePath = row.beforePath, afterPath = row.instance:GetFullName(),
			class = row.instance.ClassName, descendants = #row.instance:GetDescendants()})
		out.archivedDescendants += row.descendantCount
	end
	return out
end

function Archive.Rollback(plan)
	editOnly(plan.dataModel)
	assert(plan.archive and plan.archive.Parent == plan.serverStorage, "Archive changed; manual review required")
	assert(#plan.archive:GetChildren() == #plan.rows, "Archive wrapper changed")
	local expectedTotal = #plan.rows
	for _, row in ipairs(plan.rows) do
		assert(unique(plan.replicatedStorage, row.name) == row.owner and row.owner.Parent == plan.replicatedStorage,
			"Zyntra owner identity changed; do not restore to a detached owner")
		assert(row.wrapper and row.wrapper.Parent == plan.archive and row.wrapper.Name == row.name
			and #row.wrapper:GetChildren() == 1 and row.instance.Parent == row.wrapper,
			"Archive wrapper identity changed")
		assert(row.owner:FindFirstChild("Imports") == nil, "New Imports exists; do not overwrite")
		assert(row.instance:IsDescendantOf(plan.archive), "Original moved concurrently")
		assert(#row.instance:GetDescendants() == row.descendantCount, "Archive membership changed")
		expectedTotal += row.descendantCount + 1
	end
	assert(#plan.archive:GetDescendants() == expectedTotal, "Unexpected archive content; do not destroy")
	for _, row in ipairs(plan.rows) do row.instance.Parent = row.owner end
	plan.archive:Destroy() -- wrappers only
	plan.archive = nil
end

return Archive
