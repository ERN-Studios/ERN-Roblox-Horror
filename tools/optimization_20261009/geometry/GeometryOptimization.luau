-- Preparation utility; loading this file does not mutate the DataModel.
-- ROOT ONLY: Prepare in Edit, export/review Manifest chunks, preserve a native
-- place backup, then Apply. Never invoke Apply while the owner is in Play.
-- Contained colliders are archived intact; no authoritative instance is destroyed.
local Geometry = {}
local SS = game:GetService("ServerStorage")
local SES = game:GetService("ScriptEditorService")
local HS = game:GetService("HttpService")
local RS = game:GetService("RunService")
local ARCHIVE_NAME = "PoolroomsContainedColliders_20261009"
local LOD_FOLDERS = {"Frame_DeckPads", "Frame_Decks", "Frame_DecksDeep"}
local BASE_PROPERTIES = {
	"Anchored", "CanCollide", "CanQuery", "CanTouch", "CollisionGroup",
	"Material", "MaterialVariant", "Color", "Reflectance", "Transparency",
	"CastShadow", "Massless", "RootPriority", "Archivable", "Locked",
	"TopSurface", "BottomSurface", "FrontSurface", "BackSurface", "LeftSurface", "RightSurface",
}

local function editOnly()
	assert(not RS:IsRunning(), "Geometry optimization requires Edit; preserve the owner's Play session")
	assert(game.PlaceId == 131311258779917 and game.GameId == 10559217407,
		"Unexpected place/universe; do not modify it")
end

local function encodeValue(value)
	local kind = typeof(value)
	if kind == "Color3" then return {kind, value.R, value.G, value.B} end
	if kind == "Vector3" then return {kind, value.X, value.Y, value.Z} end
	if kind == "Vector2" then return {kind, value.X, value.Y} end
	if kind == "CFrame" then return {kind, value:GetComponents()} end
	if kind == "EnumItem" then return {kind, tostring(value)} end
	if kind == "BrickColor" then return {kind, value.Number} end
	if kind == "NumberRange" then return {kind, value.Min, value.Max} end
	assert(kind == "boolean" or kind == "number" or kind == "string", "Unsupported baseline value: " .. kind)
	return {kind, value}
end

local function attributes(instance)
	local attrs = instance:GetAttributes()
	local keys, result = {}, {}
	for key in pairs(attrs) do table.insert(keys, key) end
	table.sort(keys)
	for _, key in ipairs(keys) do table.insert(result, {key, encodeValue(attrs[key])}) end
	return result
end

local function physicalProperties(instance)
	local p = instance.CustomPhysicalProperties
	return p and {p.Density, p.Friction, p.Elasticity, p.FrictionWeight, p.ElasticityWeight} or false
end

local function snapshot(instance)
	local props = {}
	for _, key in ipairs(BASE_PROPERTIES) do table.insert(props, {key, encodeValue(instance[key])}) end
	if instance:IsA("Part") then table.insert(props, {"Shape", encodeValue(instance.Shape)}) end
	if instance:IsA("UnionOperation") then
		table.insert(props, {"RenderFidelity", encodeValue(instance.RenderFidelity)})
		table.insert(props, {"CollisionFidelity", encodeValue(instance.CollisionFidelity)})
		table.insert(props, {"UsePartColor", encodeValue(instance.UsePartColor)})
	end
	local tags = instance:GetTags()
	table.sort(tags)
	local values = {
		instance.ClassName, instance.Name, {instance.CFrame:GetComponents()},
		{instance.Size.X, instance.Size.Y, instance.Size.Z}, props,
		physicalProperties(instance), attributes(instance), tags, #instance:GetChildren(),
	}
	return {
		Instance = instance, Parent = instance.Parent, Values = values,
		Fingerprint = HS:JSONEncode(values), Path = instance:GetFullName(),
		Id = instance:GetDebugId(), ParentId = instance.Parent:GetDebugId(),
	}
end

local function assertSnapshot(before)
	local instance = before.Instance
	assert(instance.Parent == before.Parent and instance:GetDebugId() == before.Id,
		"Instance or parent changed; reread Studio: " .. before.Path)
	assert(snapshot(instance).Fingerprint == before.Fingerprint,
		"Property/attribute/tag/child baseline changed; reread Studio: " .. before.Path)
end

-- Canonical world AABB only for an EXACT signed permutation rotation.
-- No tolerance admits rotated cylinders, sloped stairs or a tiny aperture.
local function box(part)
	local c = {part.CFrame:GetComponents()}
	for i = 4, 12 do if c[i] ~= 0 and math.abs(c[i]) ~= 1 then return nil end end
	local s = {part.Size.X, part.Size.Y, part.Size.Z}
	local extent = {
		math.abs(c[4])*s[1] + math.abs(c[5])*s[2] + math.abs(c[6])*s[3],
		math.abs(c[7])*s[1] + math.abs(c[8])*s[2] + math.abs(c[9])*s[3],
		math.abs(c[10])*s[1] + math.abs(c[11])*s[2] + math.abs(c[12])*s[3],
	}
	local b = {Center = {c[1], c[2], c[3]}, Extent = extent, Min = {}, Max = {}}
	for axis = 1, 3 do
		b.Min[axis] = b.Center[axis] - extent[axis]/2
		b.Max[axis] = b.Center[axis] + extent[axis]/2
	end
	return b
end

local function contains(outer, inner)
	for axis = 1, 3 do
		if outer.Min[axis] > inner.Min[axis] or outer.Max[axis] < inner.Max[axis] then return false end
	end
	return true
end

local function colliderSignature(part)
	local attrs = part:GetAttributes()
	if typeof(attrs.Area) ~= "string" then return nil end
	for key in pairs(attrs) do if key ~= "Area" then return nil end end
	for _, face in ipairs({"TopSurface", "BottomSurface", "FrontSurface", "BackSurface", "LeftSurface", "RightSurface"}) do
		if part[face] ~= Enum.SurfaceType.Smooth then return nil end
	end
	local props = {}
	for _, key in ipairs(BASE_PROPERTIES) do table.insert(props, {key, encodeValue(part[key])}) end
	return HS:JSONEncode({props, physicalProperties(part), attributes(part)})
end

local function eligibleCollider(part, collision)
	return part.Parent == collision and part:IsA("Part") and part.Name == "Part"
		and part.Shape == Enum.PartType.Block and part.Anchored and part.Transparency == 1
		and part.CanCollide and part.CanQuery and not part.CanTouch
		and #part:GetChildren() == 0 and #part:GetTags() == 0
end

local function runtimeSources()
	local result = {}
	local descendants = {}
	-- Source/editor evidence concerns executable production scripts. Traversing
	-- the huge ServerStorage animation-authoring trees cannot add one of these.
	for _, service in ipairs(game:GetChildren()) do
		if service ~= SS then
			table.insert(descendants, service)
			for _, instance in ipairs(service:GetDescendants()) do table.insert(descendants, instance) end
		end
	end
	for i, instance in ipairs(descendants) do
		if instance:IsA("LuaSourceContainer") and not instance:IsDescendantOf(SS) then
			local source = instance.Source
			local editor = SES:GetEditorSource(instance)
			-- Pin ALL executable source/editor pairs, including dynamically computed
			-- names that a literal Collision/Imports grep would miss.
			assert(source == editor, "Resolve Source/editor conflict before geometry changes: " .. instance:GetFullName())
			table.insert(result, {Instance = instance, Parent = instance.Parent, Source = source, EditorSource = editor,
				Path = instance:GetFullName(), ClassName = instance.ClassName, Id = instance:GetDebugId()})
		end
		if i % 1000 == 0 then task.wait() end
	end
	return result
end

local function assertSources(plan)
	for _, before in ipairs(plan.Sources) do
		local s = before.Instance
		assert(s.Parent == before.Parent and s:GetDebugId() == before.Id and s.Source == before.Source,
			"Runtime source/identity changed; reread Studio: " .. before.Path)
		assert(SES:GetEditorSource(s) == before.EditorSource,
			"Runtime editor source changed; reconcile fresh Studio: " .. before.Path)
	end
end

-- Conservatively exclude explicit instance identities referenced anywhere in the
-- DataModel. Untouched guards, hazards, markers, slides and cylindrical/sloped
-- objects never enter the candidate set in the first place.
local function referenceKeys(instance)
	if instance:IsA("ObjectValue") then return {"Value"} end
	if instance:IsA("JointInstance") or instance:IsA("WeldConstraint") or instance:IsA("NoCollisionConstraint") then return {"Part0", "Part1"} end
	if instance:IsA("Model") then return {"PrimaryPart"} end
	if instance:IsA("BillboardGui") or instance:IsA("SurfaceGui") or instance:IsA("PVAdornment") or instance:IsA("Highlight") then return {"Adornee"} end
	if instance:IsA("Camera") then return {"CameraSubject"} end
	return {}
end

local function identityReferences(candidates)
	local referenced, states = {}, {}
	for i, instance in ipairs(game:GetDescendants()) do
		for _, key in ipairs(referenceKeys(instance)) do
			local ok, target = pcall(function() return instance[key] end)
			if ok then
				table.insert(states, {Instance = instance, Parent = instance.Parent, Key = key, Value = target})
				if target and candidates[target] then referenced[target] = instance:GetFullName() .. "." .. key end
			end
		end
		if i % 1000 == 0 then task.wait() end
	end
	return referenced, states
end

function Geometry.Prepare()
	editOnly()
	local world = assert(SS:FindFirstChild("Level2PoolroomsMap"), "Fresh Poolrooms template is missing")
	assert(world:IsA("Model") and world:GetAttribute("Level2NewMap") == true, "Unexpected Poolrooms identity")
	local collision = assert(world:FindFirstChild("Collision"), "Collision model is missing")
	assert(collision:IsA("Model"), "Unexpected Collision class")
	local level6 = assert(SS:FindFirstChild("Level 6 Indoor Playground"), "Fresh parked Level 6 model is missing")
	assert(level6:IsA("Model"), "Unexpected Level 6 class")
	assert(not SS:FindFirstChild(ARCHIVE_NAME), "Archive already exists; verify/reconcile instead of repeating Apply")
	local plan = {World = world, Collision = collision, Level6 = level6, WorldId = world:GetDebugId(),
		CollisionId = collision:GetDebugId(), Level6Id = level6:GetDebugId(), Removals = {}, LOD = {},
		ChangedCollision = {}, ChangedLOD = {}, Sources = runtimeSources(), CandidateCount = 0, ReferencedCount = 0,
		CollisionBeforeCount = #collision:GetDescendants(), Phase = "prepared", LODFolders = {},
		WorldAttributes = HS:JSONEncode(attributes(world)),
		CollisionAttributes = HS:JSONEncode(attributes(collision)), Level6Attributes = HS:JSONEncode(attributes(level6))}
	local candidates, records, buckets = {}, {}, {}
	for i, part in ipairs(collision:GetChildren()) do
		if eligibleCollider(part, collision) then
			local bounds, signature = box(part), colliderSignature(part)
			if bounds and signature then
				local rec = {Before = snapshot(part), Bounds = bounds, Signature = signature, Instance = part}
				candidates[part] = true; records[part] = rec; plan.CandidateCount += 1
			end
		end
		if i % 1000 == 0 then task.wait() end
	end
	local referenced = identityReferences(candidates)
	plan.Candidates = candidates
	plan.IdentityReferences = referenced
	for part, rec in pairs(records) do
		if referenced[part] then plan.ReferencedCount += 1
		else
			for axis = 1, 3 do
				local key = {rec.Signature, tostring(axis)}
				for other = 1, 3 do if other ~= axis then
					table.insert(key, string.format("%.17g", rec.Bounds.Center[other]))
					table.insert(key, string.format("%.17g", rec.Bounds.Extent[other]))
				end end
				local k = table.concat(key, "|")
				buckets[k] = buckets[k] or {}; table.insert(buckets[k], {Record = rec, Axis = axis})
			end
		end
	end
	local aliases, bucketCount = {}, 0
	for _, rows in pairs(buckets) do
		table.sort(rows, function(a, b)
			local aa, bb = a.Record, b.Record
			local axis = a.Axis
			if aa.Bounds.Min[axis] ~= bb.Bounds.Min[axis] then return aa.Bounds.Min[axis] < bb.Bounds.Min[axis] end
			if aa.Bounds.Max[axis] ~= bb.Bounds.Max[axis] then return aa.Bounds.Max[axis] > bb.Bounds.Max[axis] end
			return aa.Before.Id < bb.Before.Id
		end)
		local keep
		for _, row in ipairs(rows) do
			local rec = row.Record
			if keep and contains(keep.Bounds, rec.Bounds) then
				local old = aliases[rec.Instance]
				if not old or keep.Before.Id < old.Before.Id then aliases[rec.Instance] = keep end
			else keep = rec end
		end
		bucketCount += 1; if bucketCount % 1000 == 0 then task.wait() end
	end
	for instance, keep in pairs(aliases) do
		local seen = {}
		while aliases[keep.Instance] do
			assert(not seen[keep.Instance], "Containment alias cycle")
			seen[keep.Instance] = true; keep = aliases[keep.Instance]
		end
		local rec = records[instance]
		assert(rec.Signature == keep.Signature and contains(keep.Bounds, rec.Bounds), "Invalid final containment")
		table.insert(plan.Removals, {Before = rec.Before, Keep = keep.Before, Bounds = rec.Bounds, KeepBounds = keep.Bounds})
	end
	table.sort(plan.Removals, function(a, b) return a.Before.Id < b.Before.Id end)
	for _, name in ipairs(LOD_FOLDERS) do
		local folder = assert(level6:FindFirstChild(name), "Missing scoped Level 6 folder: " .. name)
		table.insert(plan.LODFolders, {Instance = folder, Name = name, Id = folder:GetDebugId()})
		for i, part in ipairs(folder:GetDescendants()) do
			if part:IsA("UnionOperation") and part.Anchored and part.RenderFidelity == Enum.RenderFidelity.Precise then
				table.insert(plan.LOD, snapshot(part))
			end
			if i % 1000 == 0 then task.wait() end
		end
	end
	table.sort(plan.LOD, function(a, b) return a.Id < b.Id end)
	Geometry.AssertPlan(plan)
	return plan
end

local function assertRootScope(plan)
	assert(plan.World.Parent == SS and plan.World:GetDebugId() == plan.WorldId and plan.World.Name == "Level2PoolroomsMap",
		"Poolrooms was moved/replaced; reread Studio")
	assert(plan.Collision.Parent == plan.World and plan.Collision:GetDebugId() == plan.CollisionId and plan.Collision.Name == "Collision",
		"Poolrooms Collision was moved/replaced; reread Studio")
	assert(plan.Level6.Parent == SS and plan.Level6:GetDebugId() == plan.Level6Id and plan.Level6.Name == "Level 6 Indoor Playground",
		"Level 6 was moved/replaced; reread Studio")
	assert(HS:JSONEncode(attributes(plan.World)) == plan.WorldAttributes
		and HS:JSONEncode(attributes(plan.Collision)) == plan.CollisionAttributes
		and HS:JSONEncode(attributes(plan.Level6)) == plan.Level6Attributes,
		"Scoped root attributes changed; reread Studio")
	for _, before in ipairs(plan.LODFolders) do
		assert(before.Instance.Parent == plan.Level6 and before.Instance.Name == before.Name and before.Instance:GetDebugId() == before.Id,
			"Scoped LOD folder moved/renamed/replaced; reread Studio: " .. before.Name)
	end
	return true
end

function Geometry.AssertPlan(plan)
	editOnly()
	assertRootScope(plan)
	assertSources(plan)
	for i, row in ipairs(plan.Removals) do
		assertSnapshot(row.Before); assertSnapshot(row.Keep)
		assert(contains(box(row.Keep.Instance), box(row.Before.Instance)), "Live occupancy differs")
		if i % 500 == 0 then task.wait(); editOnly() end
	end
	for i, before in ipairs(plan.LOD) do
		assertSnapshot(before)
		if i % 500 == 0 then task.wait(); editOnly() end
	end
end

local function assertFreshEvidence(plan)
	-- Include relevant scripts and identity-reference containers added after
	-- Prepare. The fresh scan yields in bounded batches; the existing full source
	-- snapshots are checked again synchronously after the scan, before any write.
	local hierarchyChanged = false
	local connections = {}
	local function changed(instance)
		if instance:IsA("LuaSourceContainer") or #referenceKeys(instance) > 0 then hierarchyChanged = true end
	end
	-- Read-only subscriptions catch a new source/reference object that arrives
	-- after GetDescendants returned but while a bounded scan yields.
	if game.DescendantAdded and game.DescendantRemoving then
		table.insert(connections, game.DescendantAdded:Connect(changed))
		table.insert(connections, game.DescendantRemoving:Connect(changed))
	end
	local ok, problem = xpcall(function()
		local currentSources = runtimeSources()
		assert(#currentSources == #plan.Sources, "Executable runtime source set changed; reread fresh Studio")
		local expected = {}
		for _, before in ipairs(plan.Sources) do expected[before.Instance] = before end
		for _, current in ipairs(currentSources) do
			local before = expected[current.Instance]
			assert(before and current.Parent == before.Parent and current.Id == before.Id
				and current.Source == before.Source and current.EditorSource == before.EditorSource,
				"Executable runtime source set/baseline changed: " .. current.Path)
		end
		local currentReferences, states = identityReferences(plan.Candidates)
		for instance, path in pairs(currentReferences) do
			assert(plan.IdentityReferences[instance] == path,
				"New or changed explicit collider identity reference; reread Studio: " .. path)
		end
		for _, state in ipairs(states) do
			assert(state.Instance.Parent == state.Parent and state.Instance[state.Key] == state.Value,
				"Reference changed during yielding scan; reread Studio: " .. state.Instance:GetFullName())
		end
		assert(not hierarchyChanged, "Source/reference hierarchy changed during yielding scan; reread Studio")
		assertSources(plan)
		editOnly()
	end, debug.traceback)
	for _, connection in ipairs(connections) do connection:Disconnect() end
	assert(ok, problem)
end

local function exported(before)
	return {path = before.Path, id = before.Id, parentId = before.ParentId,
		className = before.Values[1], values = before.Values, fingerprint = before.Fingerprint}
end

function Geometry.Summary(plan)
	local areas, folders = {}, {}
	for _, row in ipairs(plan.Removals) do local area = row.Before.Instance:GetAttribute("Area"); areas[area] = (areas[area] or 0) + 1 end
	for _, row in ipairs(plan.LOD) do local name = row.Parent.Name; folders[name] = (folders[name] or 0) + 1 end
	return {phase = plan.Phase, placeId = game.PlaceId, universeId = game.GameId,
		poolroomsPath = plan.World:GetFullName(), collisionPath = plan.Collision:GetFullName(),
		collisionBeforeDescendants = plan.CollisionBeforeCount, candidateCount = plan.CandidateCount,
		referencedExcluded = plan.ReferencedCount, redundantColliders = #plan.Removals, areas = areas,
		lodPath = plan.Level6:GetFullName(), unionsToAutomatic = #plan.LOD, lodFolders = folders,
		sourceEvidenceCount = #plan.Sources, archiveName = ARCHIVE_NAME,
		geometryPolicy = "Exact containment only; no resized boxes, no epsilon, no removed volumes",
		limitations = "No native gameplay, multiplayer, streaming or actual-asset performance result"}
end

function Geometry.Manifest(plan, startIndex, count)
	local start = startIndex or 1
	local limit = math.min(count or 250, 250)
	local output = {summary = Geometry.Summary(plan), startIndex = start, total = #plan.Removals + #plan.LOD, rows = {}}
	for i = start, math.min(start + limit - 1, output.total) do
		if i <= #plan.Removals then
			local row = plan.Removals[i]
			table.insert(output.rows, {kind = "containedCollider", before = exported(row.Before), survivor = exported(row.Keep),
				bounds = row.Bounds, survivorBounds = row.KeepBounds})
		else table.insert(output.rows, {kind = "renderFidelity", before = exported(plan.LOD[i - #plan.Removals]), after = "Enum.RenderFidelity.Automatic"}) end
	end
	return output
end

-- Invoke only AFTER manifest review and a successfully saved full native place
-- backup. Supply the concrete backup path/receipt; a source-only mirror is insufficient.
function Geometry.Apply(plan, nativeBackupReceipt)
	editOnly()
	assert(plan.Phase == "prepared", "Plan has already been applied or rolled back")
	assert(type(nativeBackupReceipt) == "string" and #nativeBackupReceipt > 10, "A verified full native backup receipt is required")
	assert(not SS:FindFirstChild(ARCHIVE_NAME), "Concurrent archive appeared")
	assertFreshEvidence(plan)
	Geometry.AssertPlan(plan)
	local archive = Instance.new("Folder")
	archive.Name = ARCHIVE_NAME
	plan.Archive = archive; plan.NativeBackupReceipt = nativeBackupReceipt
	local ok, failure = xpcall(function()
		assert(not SS:FindFirstChild(ARCHIVE_NAME), "Concurrent archive appeared immediately before write")
		assertRootScope(plan)
		archive.Parent = SS
		for i, row in ipairs(plan.Removals) do
			-- No yield occurs between these exact checks and this single Parent write.
			assertSnapshot(row.Before); assertSnapshot(row.Keep)
			assert(contains(box(row.Keep.Instance), box(row.Before.Instance)), "Fresh containment is false")
			row.Before.Instance.Parent = archive
			table.insert(plan.ChangedCollision, row)
			if i % 250 == 0 then task.wait(); editOnly(); assertRootScope(plan); assertSources(plan) end
		end
		for i, before in ipairs(plan.LOD) do
			assertSnapshot(before)
			before.Instance.RenderFidelity = Enum.RenderFidelity.Automatic
			table.insert(plan.ChangedLOD, before)
			if i % 500 == 0 then task.wait(); editOnly(); assertRootScope(plan); assertSources(plan) end
		end
		assertFreshEvidence(plan)
		assertRootScope(plan)
		plan.Phase = "applied"
	end, debug.traceback)
	if not ok then
		local restored, rollbackError = pcall(Geometry.Rollback, plan)
		error(tostring(failure) .. "\nRollback: " .. (restored and "completed" or tostring(rollbackError)))
	end
	return Geometry.Verify(plan)
end

function Geometry.Verify(plan)
	editOnly()
	assertRootScope(plan)
	assertSources(plan)
	for i, row in ipairs(plan.ChangedCollision) do
		assert(row.Before.Instance.Parent == plan.Archive, "Archived collider changed parent")
		assert(snapshot(row.Before.Instance).Fingerprint == row.Before.Fingerprint, "Archived collider properties changed")
		assertSnapshot(row.Keep)
		assert(contains(box(row.Keep.Instance), box(row.Before.Instance)), "Archived volume is not covered by survivor")
		if i % 500 == 0 then task.wait(); editOnly() end
	end
	for i, before in ipairs(plan.ChangedLOD) do
		local instance = before.Instance
		assert(instance.Parent == before.Parent and instance.RenderFidelity == Enum.RenderFidelity.Automatic, "LOD instance changed")
		local after = snapshot(instance)
		-- Every snapshot field except RenderFidelity must be exactly unchanged.
		for _, pair in ipairs(after.Values[5]) do
			if pair[1] == "RenderFidelity" then pair[2] = {"EnumItem", "Enum.RenderFidelity.Precise"} end
		end
		assert(HS:JSONEncode(after.Values) == before.Fingerprint, "Unexpected LOD property/attribute change")
		if i % 500 == 0 then task.wait(); editOnly() end
	end
	return {summary = Geometry.Summary(plan), archived = #plan.ChangedCollision,
		lodChanged = #plan.ChangedLOD, collisionDescendantsNow = #plan.Collision:GetDescendants(),
		exactContainmentVerified = true, runtimeGameplayVerified = false, performanceVerified = false,
		nativeBackupReceipt = plan.NativeBackupReceipt}
end

function Geometry.Rollback(plan)
	editOnly()
	local conflicts = {}
	for i = #plan.ChangedLOD, 1, -1 do
		local before = plan.ChangedLOD[i]
		-- Restore only our property, preserving unrelated concurrent property work.
		if before.Instance.RenderFidelity == Enum.RenderFidelity.Automatic then
			before.Instance.RenderFidelity = Enum.RenderFidelity.Precise
		else table.insert(conflicts, before.Path .. " RenderFidelity changed concurrently") end
		if i % 500 == 0 then task.wait(); editOnly() end
	end
	for i = #plan.ChangedCollision, 1, -1 do
		local before = plan.ChangedCollision[i].Before
		if before.Instance.Parent == plan.Archive and plan.Collision.Parent == plan.World then
			before.Instance.Parent = before.Parent
		else table.insert(conflicts, before.Path .. " parent changed concurrently") end
		if i % 250 == 0 then task.wait(); editOnly() end
	end
	plan.Phase = "rolledBack"
	-- The empty archive remains a reviewable task-owned receipt; delete nothing.
	assert(#conflicts == 0, "Rollback needs reconciliation: " .. table.concat(conflicts, "; "))
	return Geometry.Summary(plan)
end

return Geometry
