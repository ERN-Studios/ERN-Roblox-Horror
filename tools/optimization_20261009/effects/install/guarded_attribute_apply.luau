-- Root invokes this reviewed function in Edit; it performs no mutation until every guard in this batch passes.
-- Pair with attributes-batch-XX.json and the exact fresh director Source supplied by the root.
local function sameVector(v, t)
	return v.X == t[1] and v.Y == t[2] and v.Z == t[3]
end
local function rootOf(d, dataModel)
	local storage, world = dataModel:GetService("ServerStorage"), dataModel:GetService("Workspace")
	local root = d
	while root.Parent ~= storage and root.Parent ~= world do
		root = root.Parent
		assert(root, "Effect left authored map")
	end
	return root
end

return function(dataModel, plan, Selector, expectedDirectorSource, mode)
	assert(mode == "apply" or mode == "rollback", "Explicit apply/rollback mode required")
	assert(not dataModel:GetService("RunService"):IsRunning(), "Effect metadata write requires Edit")
	assert(dataModel.PlaceId == plan.placeId and dataModel.GameId == plan.universeId, "Wrong place/universe")
	assert(#plan.records <= 100, "Metadata batch is not bounded")
	local director = dataModel:GetService("ServerScriptService")["Level 4 Systems"]["Level 4 Light Director"]
	assert(director:IsA("ModuleScript") and director:GetDebugId(0) == "42773", "Director identity changed")
	local editor = dataModel:GetService("ScriptEditorService"):GetEditorSource(director)
	assert(director.Source == expectedDirectorSource and editor == expectedDirectorSource, "Director Source/editor baseline changed")

	local entries, counts = Selector.Collect(dataModel)
	for map, count in pairs(plan.counts) do assert(counts[map] == count, "Candidate inventory changed: " .. map) end
	local byId = {}
	for _, entry in ipairs(entries) do
		local id = entry.Instance:GetDebugId(0)
		assert(not byId[id], "Duplicate effect identity")
		byId[id] = entry.Instance
	end

	local targets = {}
	for _, baseline in ipairs(plan.records) do
		local d = assert(byId[baseline.id], "Exact effect no longer selected: " .. baseline.id)
		local root = rootOf(d, dataModel)
		assert(d.ClassName == baseline.class and root.Name == baseline.map
			and root:GetDebugId(0) == baseline.rootId and root.Parent.Name == baseline.rootService,
			"Effect map/class identity changed")
		assert(d.Parent:GetDebugId(0) == baseline.holderId, "Effect mount identity changed")
		assert(d.Parent.Anchored == baseline.anchored and sameVector(d.Parent.Position, baseline.position)
			and sameVector(d.Parent.Size, baseline.size), "Effect mount baseline changed")
		assert(d.Enabled == baseline.enabled, "Effect Enabled baseline changed")
		if baseline.range ~= nil then assert(d.Range == baseline.range, "Light Range baseline changed") end
		local wanted, influence = d:GetAttribute("SceneBudgetWantedEnabled"), d:GetAttribute("SceneBudgetInfluenceRadius")
		if mode == "apply" then
			assert((wanted ~= nil) == baseline.hasWanted and wanted == baseline.wanted, "Desired-state attribute changed")
			assert((influence ~= nil) == baseline.hasInfluence and influence == baseline.influence, "Influence attribute changed")
		else
			assert(wanted == baseline.newWanted, "Installed desired-state attribute changed before rollback")
			local installedInfluence = if baseline.newInfluence ~= nil then baseline.newInfluence else baseline.influence
			assert(influence == installedInfluence, "Installed influence changed before rollback")
		end
		table.insert(targets, {instance=d, baseline=baseline})
	end

	local function postcheck()
		for _, target in ipairs(targets) do
			local d,b=target.instance,target.baseline
			assert(d.Enabled==b.enabled and sameVector(d.Parent.Position,b.position) and sameVector(d.Parent.Size,b.size),
				"Metadata changed unrelated visual/mount properties")
			local expectedWanted = if mode=="apply" then b.newWanted else b.wanted
			local expectedInfluence = if mode=="apply" and b.newInfluence~=nil then b.newInfluence else b.influence
			assert(d:GetAttribute("SceneBudgetWantedEnabled")==expectedWanted,"Desired-state postcheck failed")
			assert(d:GetAttribute("SceneBudgetInfluenceRadius")==expectedInfluence,"Influence postcheck failed")
		end
	end
	local touched = {}
	local ok, problem = xpcall(function()
		-- No yield between fresh guards and the scoped writes; <=100 objects per invocation.
		for _, target in ipairs(targets) do
			local d, b = target.instance, target.baseline
			local record = {instance=d, wanted=d:GetAttribute("SceneBudgetWantedEnabled"),
				influence=d:GetAttribute("SceneBudgetInfluenceRadius")}
			table.insert(touched, record)
			if mode == "apply" then
				d:SetAttribute("SceneBudgetWantedEnabled", b.newWanted)
				if b.newInfluence ~= nil then d:SetAttribute("SceneBudgetInfluenceRadius", b.newInfluence) end
			else
				d:SetAttribute("SceneBudgetWantedEnabled", b.wanted)
				d:SetAttribute("SceneBudgetInfluenceRadius", b.influence)
			end
		end
		postcheck()
	end, debug.traceback)
	if not ok then
		-- Restore only the attributes this task touched; no object deletion or unrelated property writes.
		for i=#touched,1,-1 do
			local record=touched[i]
			record.instance:SetAttribute("SceneBudgetWantedEnabled",record.wanted)
			record.instance:SetAttribute("SceneBudgetInfluenceRadius",record.influence)
		end
		error(problem,0)
	end
	return {Mode=mode, Changed=#targets, Offset=plan.offset, Total=plan.total}
end
