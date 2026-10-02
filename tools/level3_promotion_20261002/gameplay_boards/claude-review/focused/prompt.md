Read-only focused Roblox Luau integration review. No tools. Return <=450 words with verdict (clear/material fix/uncertain), concrete severity/function/trigger/effect/minimal fix. Do not give private internal reasoning. Omitted code is not verified. Source inference is not gameplay evidence.

Twelve candidates pinned below; only four integration excerpts supplied. Do not claim whole-twelve review. Revised Level6 kit enters public Level3; keep SelectedLevel=3, InRound, RoundActive, Escaped, rewards, L3Manager death key. Preserve Level5/6 previews. Visual precedes objective. Native Level6BlenderKit names intentional. Root handles backup and fresh Source/editor CAS.

Review separate concealed wall skin plus original invisible full-size collision wall, reactive material chunks, all8 new portal frames (only one frame has Light), client blackout/restoration, CD carrier clones/movement, and R4 original board transfer. New mesh chunks have Level3_KitVisualChunk=true; clone does not preserve event connections, so client lights and CD controllers explicitly sync cloned parts. World teardown destroys round objects/connections. Final ServiceDoor stays closed with authoritative escape trigger in front; no opening animation expected.

Board: actual original one combined TOP SUPPORTERS provider/ten-row renderer tracks recorded donations + utility products + storefront passes + private servers. Source search found no distinct buyer leaderboard. Preserve live subscriptions/provider/IDs/stores by direct nonnil reparent, no DataStore/monetization source changes. Root fresh Edit contains ServerLobby2904 descendants but no R4 model and no revision plaque; remove only exact source plaque creation for next runtime build. Original panel orientation is unrotated; Right SurfaceGui normal +X, size(.62,12.6,18). Fresh authored R4center(220,30,-760), target panel center= center+(-30,7.15,-35)=(190,37.15,-795), so face points toward centerX220. Historical board collision Xrelative[-33.05,-29.69], Z[-44,-26]; lower R4 wall X[-34.85,-33.55], Z[-60,-20]. Runtime occlusion/readability/replication unverified; evaluate source placement, do not invent a passed visual test. Current startup originalLobby then R4 once. Consider original lobby rebuild while R4 persists as edge case.

Local:4 syntax compiles;18 mocked cases pass (midpoint, clearance, CD chunks, wall fade,8frames, board transfer/rollback/reentry). Other agent reports8 compiles/1349 layout checks. No live gameplay/performance/multiplayer or board-renderer test.

Pinned candidate SHA256s:
ServerScriptService.Level 3 Systems.Level 3 World Builder 507da2f517db2b31c2806db082244c5e07c299dd72e163d9223a29bd08d33ab2
ServerScriptService.Level 3 Systems.Level 3 Layout Generator 0369a1f11fa20c90bee2fda67191bf58a6a543f1ce66ee554a4fd3c0dfcab594
ServerScriptService.Level 3 Systems.Level 3 Crayon Wall Art 19a59fc800920a881463159c0f724179671355936e4cfca2e8b2fd588e1a6911
ServerScriptService.Level 3 Systems.Level 3 Balloon Dressing 81118f18a222559da860961d23727b876a46298d12609d91c3fbd460425e2ce6
ServerScriptService.Level 3 Systems.Level 3 Worn Party Room Dressing 4424920501f4fafa63788f1fb70a3263e23d75e31741d68a37bd6f55b48f511a
ServerScriptService.Level 3 Systems.Level 3 Configuration c510b59dc310b719b127a2ff53e4ccf83a215a47ebb63a1b30e2a1d3ab8855ba
ServerScriptService.Level 3 Systems.Level 3 Round Adapter bfb6470711f716e4ea94c25fd3d3ac45bf6e6cc85eb50418c7e1aac61e566ef1
ServerScriptService.Level 3 Systems.Level 3 Worn Party Visual Adapter 799f8de629fd3ebfa452d67242d3ef6548248f87a61e844ac060f26adedd24b9
StarterPlayer.StarterPlayerScripts.Level 3 Lighting Controller 52033d8e5480398a1e54fe44349c277659e0ea66d97f64e6cf826100a408061b
ServerScriptService.Level 3 Systems.Level 3 Objective Controller 5474b27128d9d48deaa5503f4e340b138a06596534d87bff0a21d695ad2f39e8
ServerScriptService.Level 3 Systems.Level 3 Mall Manager AI Controller af5885402a9d42760e7ba059057d186a97395fab20819a8bd6e7aab481f7598d
ServerScriptService.LobbyReimaginedPreview.Builder f5df8fc430d985722cd400cd69dc2af6db85b3f9e5a6043c72ee63c03b6c1799
### Visual exact helper.Place plus portal excerpts (ordinary geometry omitted)
```luau
    helper.Place = function(name, worldCF, parent, options)
        options = options or {}
        local data = assert(Metadata[name], "Unknown Blender prefab " .. tostring(name))
        local template = assert(kit:FindFirstChild(name), "Missing Blender prefab " .. name)
        local scale = options.Scale or options.scale or Vector3.one
        if type(scale) == "number" then scale = Vector3.one * scale end
        local carrier = Instance.new("Part")
        carrier.Name = name
        carrier.Size = Vector3.new(.05, .05, .05)
        carrier.CFrame = worldCF
        carrier.Anchored = true
        carrier.Transparency = if options.Reactive == true then 0 else 1
        carrier.CanCollide = false
        carrier.CanTouch = false
        carrier.CanQuery = false
        carrier.CastShadow = false
        carrier:SetAttribute("Level3_KitAsset", name)
        carrier:SetAttribute("Level3_KitPivot", worldCF)
        carrier:SetAttribute("Level3_KitScale", scale)
        carrier:SetAttribute("Level3_KitVisual", true)
        local templatePivot = template:GetPivot()
        local visualParts = {}
        local originalVariants = {}
        for _, source in ipairs(template:GetDescendants()) do
            if not source:IsA("MeshPart") then continue end
            local visual = source:Clone()
            local localCF = templatePivot:ToObjectSpace(source.CFrame)
            visual.CFrame = worldCF * CFrame.new(multiply(localCF.Position, scale)) * localCF.Rotation
            visual.Size = multiply(source.Size, scale)
            visual.Anchored = options.Dynamic ~= true
            visual.CanCollide = false
            visual.CanTouch = false
            visual.CanQuery = false
            visual.CastShadow = true
            visual:SetAttribute("Level3_KitVisualChunk", true)
            visual.Parent = carrier
            if options.Dynamic == true then
                local weld = Instance.new("Weld")
                weld.Part0 = carrier
                weld.Part1 = visual
                weld.C0 = carrier.CFrame:ToObjectSpace(visual.CFrame)
                weld.C1 = CFrame.identity
                weld.Parent = visual
            end
            table.insert(visualParts, visual)
            originalVariants[visual] = visual.MaterialVariant
        end
        assert(#visualParts == data.ChunkCount, "Blender chunk count drifted for " .. name)
        if options.Reactive == true then
            carrier:GetPropertyChangedSignal("Transparency"):Connect(function()
                for _, visual in ipairs(visualParts) do
                    if visual.Parent then visual.Transparency = carrier.Transparency end
                end
            end)
            carrier:GetPropertyChangedSignal("Color"):Connect(function()
                for _, visual in ipairs(visualParts) do
                    if visual.Parent then visual.Color = carrier.Color end
                end
            end)
            carrier:GetPropertyChangedSignal("Material"):Connect(function()
                for _, visual in ipairs(visualParts) do
                    if visual.Parent then
                        visual.Material = carrier.Material
                        visual.MaterialVariant = if carrier.Material == Enum.Material.Neon
                            then "" else originalVariants[visual]
                    end
                end
            end)
        end
        carrier.Parent = parent
        counts.Meshes += #visualParts
        counts.Triangles += data.Triangles
        if options.Collidable == true or options.collidable == true then
            for index, box in ipairs(data.Colliders or {}) do
                local center = box.center or box.center_xyz
                local size = box.size or box.size_xyz
                local proxy = Instance.new("Part")
                proxy.Name = "Level3 Blender Collision " .. index
                proxy.Size = multiply(Vector3.new(size[1], size[3], size[2]), scale)
                proxy.CFrame = worldCF * CFrame.new(multiply(blender(center), scale))
                proxy.Anchored = true
                proxy.Transparency = 1
                proxy.CanCollide = true
                proxy.CanTouch = false
                proxy.CanQuery = true
                proxy.CastShadow = false
                proxy:SetAttribute("Level3_BlenderCollision", true)
                proxy.Parent = carrier
                counts.CollisionBoxes += 1
            end
        end
        for anchorName, position in pairs(data.Anchors or {}) do
            local anchor = Instance.new("Attachment")
            anchor.Name = anchorName
            anchor.CFrame = CFrame.new(multiply(blender(position), scale))
            anchor.Parent = carrier
        end
        return carrier
    end
    end
    local portal = manifest.ExitPortal
    local proxy = portal.Wall
    local newWall = centered("WallRed", proxy.CFrame, proxy.Size, portal.Model, nil, true)
    newWall.Name = "Blender Concealed Exit Wall"
    newWall:SetAttribute("Level3_HiddenExitWall", true)
    portal.VisualWall = newWall
    local newFrames={}
    for _, frame in ipairs(portal.FrameParts) do
        local skin = centered("FluorescentDiffuser", frame.CFrame, frame.Size,
            portal.Model, frame.Color, true)
        skin.Transparency=1 skin.Material=Enum.Material.Neon
        skin:SetAttribute("Level3_HiddenExitFrame", true)
        for _, child in ipairs(frame:GetChildren()) do if child:IsA("Light") then child.Parent=skin end end
        table.insert(newFrames,skin)
    end
    portal.FrameParts=newFrames
```


### Objective complete unlock/CD movement/configuration functions
```luau
unlockExit = function(session: AnyTable, startRoomId: string)
	if session.ExitUnlocked or not validSession(session) then return end
	session.ExitUnlocked = true
	local completionStartedAt = workspace:GetServerTimeNow()
	session.State:SetAttribute("Level3_CompletionSongStartServerTime", completionStartedAt)
	session.State:SetAttribute("Level3_CompletionDimStartedAtServerTime", completionStartedAt)
	session.State:SetAttribute("Level3_CompletionDimDuration", Configuration.MusicSequence.CompletionDimSeconds)
	workspace:SetAttribute("Level3CompletionDimStartedAtServerTime", completionStartedAt)
	workspace:SetAttribute("Level3CompletionDimDuration", Configuration.MusicSequence.CompletionDimSeconds)
	session.ExitGuideStartRoom = ""
	session.ExitGuideCount = 0
	session.Manifest.World:SetAttribute("Level3_ExitGuideActive", false)
	session.Manifest.World:SetAttribute("Level3_ExitGuideStartRoom", "")
	session.Manifest.World:SetAttribute("Level3_ExitGuideLampCount", 0)
	updateSharedState(session)
	local portal = session.Manifest.ExitPortal
	portal.Model:SetAttribute("Level3_ExitUnlocked", true)
	if portal.Wall and portal.Wall.Parent then
		portal.Wall.CanCollide = false
		portal.Wall.CanTouch = false
		portal.Wall.CanQuery = true
	end
	local visualWall = portal.VisualWall
	if visualWall and visualWall.Parent then
		playTween(session, visualWall, TweenInfo.new(0.60, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Transparency = 1,
		})
	end
	for _, framePart in ipairs(portal.FrameParts) do
		if framePart and framePart.Parent then
			playTween(session, framePart, TweenInfo.new(0.60, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Transparency = 0.08,
			})
		end
	end
	if portal.Light and portal.Light.Parent then
		portal.Light.Enabled = false
	end
	local finalExit = session.Manifest.FinalExit
	if finalExit and finalExit.Parent then
		finalExit:SetAttribute("Level3_ExitPowered", true)
		for _, object in ipairs(finalExit:GetDescendants()) do
			if object:IsA("BasePart") and (object.Name == "Final Exit Energon Rail" or object.Name == "Final Exit Lock Core") then
				playTween(session, object, TweenInfo.new(0.65, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Transparency = 0.06,
				})
			elseif object:IsA("PointLight") and object.Name == "Final Exit Energon Spill" then
				object.Enabled = false
			end
		end
	end
	firePayload(session, {
		Type = "ExitUnlocked",
		Progress = session.ModuleCount,
		Goal = session.ModuleGoal,
		ExitPosition = session.Manifest.ExitPosition,
	})
	fireSound(session, "ExitUnlocked", session.Manifest.ExitPosition, nil)
end
local function configureRuntimeDiscPart(part: BasePart, anchored: boolean, queryable: boolean)
	part.Anchored = anchored
	part.Massless = not anchored
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = queryable
	part.CastShadow = true
	part.Transparency = 0
	for _, object in ipairs(part:GetDescendants()) do
		if object:IsA("ProximityPrompt") or object:IsA("Light") then
			object:Destroy()
		elseif object:IsA("BasePart") and object:GetAttribute("Level3_KitVisualChunk") == true then
			object.Transparency = 0
			object.CanCollide = false
			object.CanTouch = false
			object.CanQuery = false
		end
	end
end
local function setDiscVisualCFrame(carrier: BasePart, targetCF: CFrame)
	local offsets = {}
	for _, object in ipairs(carrier:GetDescendants()) do
		if object:IsA("BasePart") and object:GetAttribute("Level3_KitVisualChunk") == true then
			offsets[object] = carrier.CFrame:ToObjectSpace(object.CFrame)
		end
	end
	carrier.CFrame = targetCF
	for object, localCF in pairs(offsets) do object.CFrame = targetCF * localCF end
end
```


### Lighting complete chunk/frame capture/watch/ownership functions
```luau
local function syncKitFixtureVisuals(carrier: BasePart)
	for _, child in ipairs(carrier:GetChildren()) do
		if child:IsA("MeshPart") and child:GetAttribute("Level3_KitVisualChunk") == true then
			if kitVisualVariants[child] == nil then
				kitVisualVariants[child] = child.MaterialVariant
			end
			child.Material = carrier.Material
			child.Color = carrier.Color
			child.Transparency = carrier.Transparency
			child.MaterialVariant = if carrier.Material == Enum.Material.Neon
				or carrier.Material == Enum.Material.SmoothPlastic
				then "" else kitVisualVariants[child]
		end
	end
end
local function tryWatchKitFixture(instance: Instance)
	if not instance:IsA("BasePart") or kitFixtureSeen[instance]
		or instance:GetAttribute("Level3_KitAsset") ~= "FluorescentDiffuser" then return end
	if not instance:FindFirstChildWhichIsA("Light")
		and instance:GetAttribute("Level3_HiddenExitFrame") ~= true then return end
	kitFixtureSeen[instance] = true
	table.insert(kitFixtureConnections,
		instance:GetPropertyChangedSignal("Material"):Connect(function()
			syncKitFixtureVisuals(instance)
		end))
	table.insert(kitFixtureConnections,
		instance:GetPropertyChangedSignal("Color"):Connect(function()
			syncKitFixtureVisuals(instance)
		end))
	table.insert(kitFixtureConnections,
		instance:GetPropertyChangedSignal("Transparency"):Connect(function()
			syncKitFixtureVisuals(instance)
		end))
	syncKitFixtureVisuals(instance)
end
local function clearKitFixtureWatchers()
	for _, connection in ipairs(kitFixtureConnections) do connection:Disconnect() end
	table.clear(kitFixtureConnections)
	table.clear(kitFixtureSeen)
	table.clear(kitVisualVariants)
	table.clear(ceilingBounceSeen)
end
local function captureAuthoredRoomGlow(instance: Instance)
	if instance:IsA("BasePart") and instance:GetAttribute("Level3_HiddenExitFrame") == true then
		if not blackoutPartSeen[instance] then
			blackoutPartSeen[instance] = true
			table.insert(blackoutParts, {Part=instance, Material=instance.Material, Color=instance.Color})
		end
		return
	end
	if not instance:IsA("MeshPart")
		or instance:GetAttribute("Level3_KitVisualChunk") ~= true
		or instance.Name:sub(-6) ~= "__glow" then return end
	local carrier = instance.Parent
	if not (carrier and carrier:IsA("BasePart")
		and carrier:GetAttribute("Level3_BlenderGatewayRoom") == true)
		or blackoutPartSeen[instance] then return end
	blackoutPartSeen[instance] = true
	table.insert(blackoutParts, {
		Part = instance,
		Material = instance.Material,
		Color = instance.Color,
	})
end
local function captureWorldLightBaseline()
	table.clear(blackoutLights)
	table.clear(blackoutParts)
	table.clear(blackoutPartSeen)
	blackoutSweptUnlocked = nil
	local world = boundWorld
	if not world then return end
	for _, descendant in ipairs(world:GetDescendants()) do
		captureAuthoredRoomGlow(descendant)
		if descendant:IsA("Light") and descendant:GetAttribute("Level3_CeilingBounce") ~= true then
			table.insert(blackoutLights, {
				Light = descendant,
				Enabled = descendant.Enabled,
				Brightness = descendant.Brightness,
			})
			local parent = descendant.Parent
			if parent and parent:IsA("BasePart") and not blackoutPartSeen[parent] then
				blackoutPartSeen[parent] = true
				table.insert(blackoutParts, {
					Part = parent,
					Material = parent.Material,
					Color = parent.Color,
				})
			end
		end
	end
end
local function shouldOwnLighting(): boolean
	return workspace:GetAttribute("SelectedLevel") == LEVEL
		and workspace:GetAttribute("Level3LightingOwnedByController") == true
		and player:GetAttribute("InRound") == true
end
```


### R4 Builder complete actual scoped source diff
```luau
+++ candidate
@@ -25,17 +25,63 @@
 	label.Font = Enum.Font.GothamBold; label.TextScaled = true; label.Parent = gui
 	return label
 end
+-- Move the original live renderer; its existing Value/attribute connections
+-- are closure-held and would not survive cloning just the display model.
+local function supportBoardTransfer(destination, center)
+    local installed = destination:FindFirstChild("ZyntraDonationLeaderboardBoard", true)
+    if installed then
+        assert(installed:IsA("Model"), "Inspect conflicting R4 support board")
+        return nil
+    end
+    local lobby = assert(workspace:FindFirstChild("ServerLobby"), "Original server lobby must precede R4")
+    local board
+    for _, descendant in ipairs(lobby:GetDescendants()) do
+        if descendant.Name == "ZyntraDonationLeaderboardBoard" then
+            assert(descendant:IsA("Model") and board == nil, "Inspect conflicting original support boards")
+            board = descendant
+        end
+    end
+    assert(board, "Original support board is not ready")
+    local panel = board:FindFirstChild("LeaderboardPanel")
+    assert(panel and panel:IsA("BasePart") and panel:FindFirstChild("DonationLeaderboardDisplay"),
+        "Inspect original support-board renderer before relocation")
+    return {
+        Board = board,
+        Parent = board.Parent,
+        Pivot = board:GetPivot(),
+        TargetPivot = CFrame.new(center + Vector3.new(-30, 7.15, -35) - panel.Position) * board:GetPivot(),
+    }
+end
+local function applySupportBoardTransfer(transfer, destination)
+    if not transfer then return end
+    transfer.Board:PivotTo(transfer.TargetPivot)
+    -- Never assign a nil direct Parent: the original renderer tears down on nil.
+    transfer.Board.Parent = destination
+end
+local function restoreSupportBoardTransfer(transfer)
+    if not transfer then return end
+    transfer.Board.Parent = transfer.Parent
+    transfer.Board:PivotTo(transfer.Pivot)
+end
 function Module.Build()
 	assert(not RunService:IsClient(), "Server preview only")
 	local existing = workspace:FindFirstChild(NAME)
 	if existing then
 		assert(existing:GetAttribute(OWNED) == true and existing:GetAttribute("Ready") == true, "Inspect conflicting preview first")
-		require(script.Parent:WaitForChild("DevBayAccessGuard")).Start(existing)
+		local center = existing:GetAttribute("PreviewCenter")
+		assert(typeof(center) == "Vector3", "Inspect R4 lobby center before relocating support board")
+		local transfer = supportBoardTransfer(existing, center)
+		local ok, failure = pcall(function()
+			applySupportBoardTransfer(transfer, existing)
+			require(script.Parent:WaitForChild("DevBayAccessGuard")).Start(existing)
+		end)
+		if not ok then restoreSupportBoardTransfer(transfer); error(failure) end
 		return existing
 	end
 	local manifest, kit = Bake.GetManifest(), Bake.Ensure()
 	local center = vec(manifest.previewCenter)
 	local model = Instance.new("Model"); model.Name = NAME; model.WorldPivot = CFrame.new(center)
+	local transfer
 	local ok, built = pcall(function()
 	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
 	model:SetAttribute(OWNED,true); model:SetAttribute("Ready",false)
@@ -168,23 +214,20 @@
 			wall:SetAttribute("HologramFullSize",wall.Size); wall:SetAttribute("HologramFullCFrame",wall.CFrame)
 		end
 	end
-	local notice=manifest.notice
-	if notice then
-		local host=part(signs,"Mounted Revision Notice",vec(notice.size),CFrame.new(center+vec(notice.position))*CFrame.Angles(0,notice.yaw,0),false)
-		text(host,Enum.NormalId.Back,"LOBBY REVISION · DEV",Color3.fromRGB(192,244,223),Vector2.new(440,100))
-	end
 	assert(not workspace:FindFirstChild(NAME), "Concurrent preview appeared; refusing overwrite")
 	local endPiles = require(script.Parent:WaitForChild("EndBlockades")).Add(model, kit, manifest)
 	local bayPolish = require(script.Parent:WaitForChild("LobbyPolishBays")).Add(model, kit, manifest)
 	require(script.Parent:WaitForChild("MaterialPolish")).Apply(model)
 	require(script.Parent:WaitForChild("LobbyPolishScene")).Apply(model)
+	transfer = supportBoardTransfer(model, center)
+	applySupportBoardTransfer(transfer, model)
 	model:SetAttribute("Ready",true); model:SetAttribute("InstantiatedTriangles",manifest.instantiatedTriangles + endPiles:GetAttribute("AddedInstancedTriangles") + bayPolish:GetAttribute("AddedInstancedTriangles"))
 	model.Parent = workspace
 	require(script.Parent:WaitForChild("DevBayAccessGuard")).Start(model)
 	return model
 	end)
-	if not ok then model:Destroy(); error(built) end
+	if not ok then restoreSupportBoardTransfer(transfer); model:Destroy(); error(built) end
 	return built
 end
 return Module
```


### Original board renderer subscriptions and teardown unchanged
```luau
	local function renderRow(entry, value, text)
		local rank = value:GetAttribute("Rank")
		local name = value:GetAttribute("Name")
		local robux = value:GetAttribute("Robux")
		if type(rank) ~= "number" then
			local legacyRank, legacyName, legacyRobux = string.match(text, "^(%d+)%s+(.-)%s+•%s+(%d+) R%$$")
			rank, name, robux = tonumber(legacyRank), legacyName, tonumber(legacyRobux)
		end
		if type(rank) == "number" and rank == rank and rank >= 1 and rank <= 99 then
			entry.Rank.Text = string.format("%02d", math.floor(rank))
			entry.Name.Text = type(name) == "string" and name or ""
			entry.Robux.Text = robuxText(robux)
		else
			entry.Rank.Text = ""
			entry.Name.Text = text
			entry.Robux.Text = ""
		end
	end
	local ROW_ATTRIBUTES = {"Rank", "Name", "Robux"}
	task.spawn(function()
		local values = ReplicatedStorage:WaitForChild("ZyntraDonationLeaderboard", 15)
		if not values or not model.Parent then return end
		local connections = {}
		local function bind(value, render, attributes)
			if not value or not value:IsA("StringValue") then return end
			render(value.Value)
			local function update()
				if model.Parent then render(value.Value) end
			end
			connections[#connections + 1] = value:GetPropertyChangedSignal("Value"):Connect(update)
			for _, attribute in ipairs(attributes or {}) do
				connections[#connections + 1] = value:GetAttributeChangedSignal(attribute):Connect(update)
			end
		end
		bind(values:FindFirstChild("Status"), function(value) status.Text = value end)
		for rank, entry in ipairs(rows) do
			local value = values:FindFirstChild(string.format("Row%02d", rank))
			bind(value, function(text) renderRow(entry, value, text) end, ROW_ATTRIBUTES)
		end
		connections[#connections + 1] = model.AncestryChanged:Connect(function(_, newParent)
			if newParent then return end
			for _, connection in ipairs(connections) do connection:Disconnect() end
			table.clear(connections)
		end)
	end)
	return model
end
```

