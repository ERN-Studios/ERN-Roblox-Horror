Give a concise code review within 300 words: material blockers first, then necessary real Play checks. Use supplied facts and code only. Do not assert that gameplay or tests passed. No internal reasoning.

User: openLevel5/6loadingbays visible/accessibleonlytoexistingDEVs. Everyoneelse sees solidCOMINGSOON+usualprogressboard. Movemainspawn/reset/returntorevisedlobby besideoriginal. Existing permanentDEVpreviewpredicate includesUID40920547,9488575949,and11374988579Zen;sharedDevAccess unchanged. NoStudioserverautoDEValternative.
AuthoritativefreshEditSource/editorbaselines match all8existingcandidates; newGuardonly. These are file-only candidates, rootwill CAS-write exactlivebaselines+actualPlaytest. RootafterCASwillbuildNEWownedrevisedvisualModel inEdit beforemovingsameexistingWorkspace.ServerLobby.LobbySpawnCFrame+2attributes. Nooriginalgeometrychanged; runtimewrapperrebuildspubliclobbybeforeloadingavatars. Canonicalpad original(0,30.4,-860)→(220,30.4,-860)looking(220,30.4,-760); invisibleenabledcollisionfalse sameobject. Revisedcenter(220,30,-760). StartupwrapperoriginalBuildfirstthenboundedshopcompletionmarkerwaitthennewBuild,validates9floor-raysonallscatteroffsets beforepadmove. Reservedroundserversbypassunchanged. Failurekeepsoldpad. Bootstraponlymonitor now, avoiddoubleBuild.
ServerQueueBridge unchanged: actualservercontrollersregistercallbackallowed, everycohortmember authorizationandlivecharactercheckedbefore/afterstreamingandcommit. GameManagerplayerInsideZonebelowisusedbyCreateParty/JoinStation/countdownmembercollection. ItsoldblanketR4DEV/Studio bypass becomesactualUIDrequirementonlyforlevels5/6; public1–3stayopen; Level4choiceunchanged. DEVphysicalguardbelowexact2bayfootprintsper.2s, noInRound/Anchoredskip so stale flagsdon'tgrantaccess. Clientshutterslocalpresentationonly; remoteparty/previewauthorizationremainsserver-side.
Clientwall20x15.6overlapsactual19.9x15.6doorby.05eachside, solidcollidinglocal. ValidatedsameleveloriginalCOMINGSOONGui clonedwithscriptdescendantsforbidden;fallbackequivalentconfigured70%(5),30%(6). Hideallprivatebayimages/meshesUI toregulars preservinglocalpropertycleanup. DEVsnoComingSoonshutter andusableexistingpreviewprompt. R4BuilderguardStartcalledonnewBuildandexistingReadyreturn.
Level6returnstrictfloorackmustchooseactualR4modeliffcanonicalpadmarker+clientmodel-name whitelist. OtherL4/L5previewreturnsonlyRequestStreamAroundAsync→canonicalpad, nohardcodedflooracks. FriendBoostnewmodelselectorfixesinvitepanelboundsatnewmainlobbybutdoesn'tchangebonus/invite/roundguards. Inspectstartupfailure, modulecache/lifecycle, permissionconsistency, geometryejectionfalsepositives, publicpartyrejectionsandreturnstreaming.
UNCHANGED DevAccess:
```luau
-- One shared whitelist for every client and server developer command.
-- UserIds are permanent; usernames can change and should never be an authority boundary.
local DevAccess = {}

local ALLOWED_USER_IDS = {
	[40920547] = true,   -- mikkelczar
	[9488575949] = true, -- LaverSneglen
}

-- Timeline seeking is intentionally narrower than the shared developer tools.
local LEVEL3_TIMELINE_OWNER_USER_ID = 9488575949 -- LaverSneglen

function DevAccess.IsAllowed(subject)
	local userId
	if typeof(subject) == "Instance" and subject:IsA("Player") then
		userId = subject.UserId
	elseif type(subject) == "number" then
		userId = subject
	end
	return userId ~= nil and ALLOWED_USER_IDS[userId] == true
end

-- Preview access is narrower than the general developer commands.
function DevAccess.IsLevel6PreviewAllowed(subject)
	if DevAccess.IsAllowed(subject) then return true end
	if typeof(subject) == "Instance" and subject:IsA("Player") then
		return subject.UserId == 11374988579 -- ZenMeister02
	end
	return type(subject) == "number" and subject == 11374988579
end

function DevAccess.IsLevel3TimelineOwner(subject)
	local userId
	if typeof(subject) == "Instance" and subject:IsA("Player") then
		userId = subject.UserId
	elseif type(subject) == "number" then
		userId = subject
	end
	return userId == LEVEL3_TIMELINE_OWNER_USER_ID
end

return DevAccess

```

EXACT ServerScriptService.GameManager DIFF:
```diff
--- ServerScriptService.GameManager.freshlive
+++ ServerScriptService.GameManager.candidate
@@ -590,7 +590,61 @@
 end
 
 local function buildLobby()
- return require(script.Parent:WaitForChild("TunnelLobbyBuilder")).Build(LOBBY_CENTER)
+ local lobby, spawn, stations = require(script.Parent:WaitForChild("TunnelLobbyBuilder")).Build(LOBBY_CENTER)
+ if IS_RESERVED_ROUND_SERVER then return lobby, spawn, stations end
+ -- Preserve the canonical pad/reference used by every join, reset and preview return.
+ -- No lobby character is loaded until this synchronous startup wrapper returns.
+ workspace:SetAttribute("LobbySpawnMigrationReady", false)
+ workspace:SetAttribute("LobbySpawnMigrationError", nil)
+ local originalSpawn = spawn.CFrame
+ local ok, problem = pcall(function()
+  local folder = script.Parent:FindFirstChild("LobbyReimaginedPreview")
+  local builder = folder and folder:FindFirstChild("Builder")
+  assert(builder and builder:IsA("ModuleScript"), "Revised lobby builder is missing")
+  -- The original builder starts its shop asynchronously. The clone must wait
+  -- for its existing completion marker, not merely the early-parented Model.
+  local shop, deadline = nil, os.clock() + 20
+  repeat
+   shop = lobby:FindFirstChild("ZyntraShopDisplay")
+   if shop and shop:IsA("Model") and (tonumber(shop:GetAttribute("ShopItemCount")) or 0) > 0 then break end
+   assert(lobby.Parent == workspace, "Lobby changed while waiting for its shop")
+   task.wait(.05)
+  until os.clock() >= deadline
+  assert(shop and shop:IsA("Model") and (tonumber(shop:GetAttribute("ShopItemCount")) or 0) > 0,
+   "Original lobby shop did not finish before revised lobby startup")
+  local revised = require(builder).Build()
+  assert(revised and revised:IsA("Model") and revised.Parent == workspace
+   and revised.Name == "LobbyReimaginedPreview" and revised:GetAttribute("LobbyReimaginedOwned") == true
+   and revised:GetAttribute("Ready") == true, "Revised lobby is not ready")
+  local center = revised:GetAttribute("PreviewCenter")
+  assert(center == Vector3.new(220, 30, -760), "Unexpected revised lobby center")
+  local position = center + Vector3.new(0, .4, -100)
+  local params = RaycastParams.new()
+  params.FilterType = Enum.RaycastFilterType.Include
+  params.FilterDescendantsInstances = {revised}
+  params.RespectCanCollide = true
+  -- Cover every possible scatter offset; fail safely before moving the pad.
+  for _, dx in ipairs({-2, 0, 2}) do
+   for _, dz in ipairs({-2, 0, 2}) do
+    local hit = workspace:Raycast(position + Vector3.new(dx, 12, dz), Vector3.new(0, -18, 0), params)
+    assert(hit and hit.Instance.CanCollide and hit.Normal.Y > .7
+     and math.abs(hit.Position.Y - position.Y) < 2, "Revised lobby spawn floor is incomplete")
+   end
+  end
+  assert(spawn.Parent == lobby and lobby.Parent == workspace, "Canonical lobby spawn changed during startup")
+  spawn.CFrame = CFrame.lookAt(position, center + Vector3.new(0, .4, 0))
+  spawn:SetAttribute("LobbySpawnFloorModelName", "LobbyReimaginedPreview")
+  spawn:SetAttribute("LobbySpawnRevision", 4)
+  workspace:SetAttribute("LobbySpawnMigrationReady", true)
+ end)
+ if not ok then
+  spawn.CFrame = originalSpawn
+  spawn:SetAttribute("LobbySpawnFloorModelName", nil)
+  spawn:SetAttribute("LobbySpawnRevision", nil)
+  workspace:SetAttribute("LobbySpawnMigrationError", tostring(problem))
+  warn("[GameManager] Revised lobby startup failed; retaining safe original spawn: " .. tostring(problem))
+ end
+ return lobby, spawn, stations
 end
 
 -- Recover automatically if a generated world was accidentally saved into the
@@ -1192,7 +1246,8 @@
 end
 
 local function playerInsideZone(player, station, includeBusy)
- if station.revisionOwned and not (RunService:IsStudio() or DevAccess.IsLevel6PreviewAllowed(player)) then return false end
+ -- Public revision queues stay open; both unfinished bays require real DEV authorization.
+ if station.revisionOwned and station.level >= 5 and not DevAccess.IsLevel6PreviewAllowed(player) then return false end
  if station.previewQueue then
   local bridge = revisedQueueBridge()
   if not (bridge and bridge.AllowsPreview(station, player))

```

EXACT ServerScriptService.LobbyReimaginedPreview.Bootstrap DIFF:
```diff
--- ServerScriptService.LobbyReimaginedPreview.Bootstrap.freshlive
+++ ServerScriptService.LobbyReimaginedPreview.Bootstrap.candidate
@@ -1,23 +1,38 @@
--- Build after a DEV joins; ordinary public servers avoid the preview bake cost.
-local Players = game:GetService("Players")
-local RunService = game:GetService("RunService")
-local DevAccess = require(game:GetService("ReplicatedStorage"):WaitForChild("DevAccess"))
-local started = false
-local attempts, retryAt = 0, 0
-local function begin(player)
-	if started or attempts >= 2 or os.clock() < retryAt or (not RunService:IsStudio() and not DevAccess.IsLevel6PreviewAllowed(player)) then return end
-	started = true
-	attempts += 1; script:SetAttribute("BuildAttempts",attempts)
-	task.spawn(function()
-		local began = os.clock()
-		local ok, result = pcall(function() return require(script.Parent:WaitForChild("Builder")).Build() end)
-		if ok then script:SetAttribute("PreviewReady",true); script:SetAttribute("BuildSeconds",os.clock()-began)
-		else
-			script:SetAttribute("PreviewError",tostring(result)); warn("[Isolated Lobby Preview] "..tostring(result))
-			started = false; retryAt = os.clock()+30
-			task.delay(30,function() for _,candidate in ipairs(Players:GetPlayers()) do begin(candidate) end end)
-		end
-	end)
+-- GameManager builds and validates the public revised lobby before loading characters.
+-- This script only reports bounded readiness; it never races a second Build transaction.
+if game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0 then
+ script:SetAttribute("PreviewReady", false)
+ script:SetAttribute("BuildStatus", "Reserved round server")
+ return
 end
-Players.PlayerAdded:Connect(begin)
-for _,player in ipairs(Players:GetPlayers()) do begin(player) end
+local began, deadline = os.clock(), os.clock() + 60
+script:SetAttribute("BuildAttempts", 0)
+script:SetAttribute("BuildStatus", "Waiting for authoritative lobby startup")
+repeat
+ local model = workspace:FindFirstChild("LobbyReimaginedPreview")
+ local lobby = workspace:FindFirstChild("ServerLobby")
+ local spawn = lobby and lobby:FindFirstChild("LobbySpawn")
+ if workspace:GetAttribute("LobbySpawnMigrationReady") == true and model and model:IsA("Model")
+  and model:GetAttribute("LobbyReimaginedOwned") == true and model:GetAttribute("Ready") == true
+  and spawn and spawn:IsA("SpawnLocation") and spawn:GetAttribute("LobbySpawnRevision") == 4
+  and spawn:GetAttribute("LobbySpawnFloorModelName") == model.Name then
+  script:SetAttribute("PreviewReady", true)
+  script:SetAttribute("PreviewError", nil)
+  script:SetAttribute("BuildSeconds", os.clock() - began)
+  script:SetAttribute("BuildStatus", "Public lobby ready")
+  return
+ end
+ local problem = workspace:GetAttribute("LobbySpawnMigrationError")
+ if type(problem) == "string" and problem ~= "" then
+  script:SetAttribute("PreviewReady", false)
+  script:SetAttribute("PreviewError", problem)
+  script:SetAttribute("BuildStatus", "Safe original spawn retained")
+  warn("[Lobby startup monitor] " .. problem)
+  return
+ end
+ task.wait(.1)
+until os.clock() >= deadline
+script:SetAttribute("PreviewReady", false)
+script:SetAttribute("PreviewError", "Authoritative revised lobby readiness timed out")
+script:SetAttribute("BuildStatus", "Readiness timeout")
+warn("[Lobby startup monitor] Authoritative revised lobby readiness timed out")

```

EXACT ServerScriptService.Level6PreviewAccess DIFF:
```diff
--- ServerScriptService.Level6PreviewAccess.freshlive
+++ ServerScriptService.Level6PreviewAccess.candidate
@@ -209,7 +209,8 @@
 	nextUse[player] = math.huge
 	local ok, err = pcall(function()
 		local landing = spawn.Position + Vector3.new(0, 4, 0)
-		if not streamReady(player, landing, "ServerLobby") then error("Lobby streaming confirmation timed out") end
+		local floorModelName = if spawn:GetAttribute("LobbySpawnFloorModelName") == "LobbyReimaginedPreview" then "LobbyReimaginedPreview" else "ServerLobby"
+		if not streamReady(player, landing, floorModelName) then error("Lobby streaming confirmation timed out") end
 		local currentCharacter, currentRoot = playerReady(player)
 		if currentCharacter ~= character or not exit.Parent or not validReturnPrompt(prompt, exit)
 			or (currentRoot.Position - exit.Position).Magnitude > 12 or lobbyPart("LobbySpawn") ~= spawn then return end

```

EXACT StarterPlayer.StarterPlayerScripts.Level6PreviewTransport DIFF:
```diff
--- StarterPlayer.StarterPlayerScripts.Level6PreviewTransport.freshlive
+++ StarterPlayer.StarterPlayerScripts.Level6PreviewTransport.candidate
@@ -34,7 +34,8 @@
 		return
 	end
 	if type(nonce) ~= "string" or typeof(target) ~= "Vector3"
-		or (modelName ~= "Level 6 Generated World" and modelName ~= "ServerLobby") then return end
+		or (modelName ~= "Level 6 Generated World" and modelName ~= "ServerLobby"
+			and modelName ~= "LobbyReimaginedPreview") then return end
 	generation += 1
 	local token = generation
 	task.spawn(function()

```

EXACT StarterPlayer.StarterPlayerScripts.Friend Boost Client DIFF:
```diff
--- StarterPlayer.StarterPlayerScripts.Friend Boost Client.freshlive
+++ StarterPlayer.StarterPlayerScripts.Friend Boost Client.candidate
@@ -12,7 +12,7 @@
 --
 -- WHERE IT IS: the top-right panel, LOBBY ONLY (owner, 2026-09-17: never inside a
 -- game). "Lobby" is read off the world, not off one flag: the chip shows only
--- while the player's root is inside the ServerLobby model's bounding box AND no
+-- while the player's root is inside the selected lobby model's bounding box AND no
 -- round flag is up (InRound, RoundActive, a round loading). A level server has
 -- no ServerLobby at all; in Studio the lobby is parked away while a Level 2/3
 -- round runs and a Level 1 maze is built far outside it (measured 2026-09-17:
@@ -129,6 +129,14 @@
 local lobbyBox = nil
 local function lobbyBounds()
 	local lobby = workspace:FindFirstChild("ServerLobby")
+	local spawn = lobby and lobby:FindFirstChild("LobbySpawn")
+	-- Follow only the server-selected, complete lobby; preserve the safe fallback.
+	if spawn and spawn:IsA("SpawnLocation")
+		and spawn:GetAttribute("LobbySpawnFloorModelName") == "LobbyReimaginedPreview" then
+		local revised = workspace:FindFirstChild("LobbyReimaginedPreview")
+		if revised and revised:IsA("Model") and revised:GetAttribute("LobbyReimaginedOwned") == true
+			and revised:GetAttribute("Ready") == true then lobby = revised end
+	end
 	if not lobby or not lobby:IsA("Model") then
 		lobbyBox = nil
 		return nil

```

EXACT ServerScriptService.Level5PreviewAccess DIFF:
```diff
--- ServerScriptService.Level5PreviewAccess.freshlive
+++ ServerScriptService.Level5PreviewAccess.candidate
@@ -63,7 +63,7 @@
 end
 
 local function readyPlayer(player)
-	if player.Parent ~= Players or not DevAccess.IsAllowed(player)
+	if player.Parent ~= Players or not DevAccess.IsLevel6PreviewAllowed(player)
 		or player:GetAttribute("InRound") == true
 		or workspace:GetAttribute("ReservedRoundServer") == true then return nil end
 	local character = player.Character
@@ -260,7 +260,7 @@
 				boundedModel = model
 			end
 			for _, player in ipairs(Players:GetPlayers()) do
-				if not DevAccess.IsAllowed(player) then
+				if not DevAccess.IsLevel6PreviewAllowed(player) then
 					local character = player.Character
 					local humanoid = character and character:FindFirstChildOfClass("Humanoid")
 					local root = humanoid and humanoid.RootPart

```

EXACT ServerScriptService.LobbyReimaginedPreview.Builder DIFF:
```diff
--- ServerScriptService.LobbyReimaginedPreview.Builder.freshlive
+++ ServerScriptService.LobbyReimaginedPreview.Builder.candidate
@@ -30,6 +30,7 @@
 	local existing = workspace:FindFirstChild(NAME)
 	if existing then
 		assert(existing:GetAttribute(OWNED) == true and existing:GetAttribute("Ready") == true, "Inspect conflicting preview first")
+		require(script.Parent:WaitForChild("DevBayAccessGuard")).Start(existing)
 		return existing
 	end
 	local manifest, kit = Bake.GetManifest(), Bake.Ensure()
@@ -180,6 +181,7 @@
 	require(script.Parent:WaitForChild("LobbyPolishScene")).Apply(model)
 	model:SetAttribute("Ready",true); model:SetAttribute("InstantiatedTriangles",manifest.instantiatedTriangles + endPiles:GetAttribute("AddedInstancedTriangles") + bayPolish:GetAttribute("AddedInstancedTriangles"))
 	model.Parent = workspace
+	require(script.Parent:WaitForChild("DevBayAccessGuard")).Start(model)
 	return model
 	end)
 	if not ok then model:Destroy(); error(built) end

```

CLIENT allowed excerpt:
```luau
local function allowed(level)
	if not accessOK or type(access) ~= "table" then return false end
	local predicate = access.IsLevel6PreviewAllowed
	if type(predicate) ~= "function" then return false end
	local ok, result = pcall(predicate, player)
	return ok and result == true
end
local permissions = {[5] = allowed(5), [6] = allowed(6)}
local observed, observeConnections, active = nil, {}, nil

```

CLIENT cleanup excerpt:
```luau
local function cleanup()
	if not active then return end
	local previous = active
	active = nil
	disconnect(previous.connections)
	for instance, saved in pairs(previous.hidden) do
		if saved.connection then saved.connection:Disconnect() end
		if instance.Parent and instance[saved.property] == false then
			instance[saved.property] = saved.previous
		end
	end
	if previous.folder.Parent and previous.folder:GetAttribute(OWNER) == true then
		previous.folder:Destroy()
	end
end

```

CLIENT comingSoonDisplay excerpt:
```luau
local function comingSoonDisplay(panel, level)
	local original = workspace:FindFirstChild("ServerLobby")
	local doorways = original and original:FindFirstChild("LevelDoorways")
	local template, fallback
	if doorways then
		for _, candidate in ipairs(doorways:GetDescendants()) do
			if validOriginalDisplay(candidate) then
				if candidate:GetAttribute("FutureLevel") == level then template = candidate; break end
				fallback = fallback or candidate
			end
		end
	end
	template = template or fallback
	if not template then
		local gui = addComingSoonBoard(panel, Enum.NormalId.Back, level)
		gui:SetAttribute("TemplateSource", "FreshTunnelLobbyBuilderFallback")
		return gui
	end
	local gui = template:Clone()
	gui.Face, gui.CanvasSize = Enum.NormalId.Back, Vector2.new(900, 690)
	gui.LightInfluence, gui.Brightness, gui.AlwaysOnTop, gui.MaxDistance = 0, 1.35, false, 130
	gui:SetAttribute("FutureLevel", level)
	gui:SetAttribute("ProgressPercent", COMING_SOON_PROGRESS[level])
	gui:SetAttribute("TemplateSource", "OriginalLobbyComingSoonDisplay")
	local screen = gui:FindFirstChild("Screen")
	local kicker = screen:FindFirstChild("GateKicker")
	if kicker and kicker:IsA("TextLabel") then kicker.Text = string.format("ZYNTRA TRANSIT // GATE %02d", level) end
	screen.ProgressTrack.ProgressFill.Size = UDim2.fromScale(COMING_SOON_PROGRESS[level] / 100, 1)
	screen.ProgressPercent.Text = string.format("%d%% COMPLETE", COMING_SOON_PROGRESS[level])
	gui.Parent = panel
	return gui
end


```

CLIENT mountGates excerpt:
```luau
local function mountGates(state)
	local signs = state.model:FindFirstChild("LevelGateSigns")
	if not signs then return end
	for _, level in ipairs({5, 6}) do
		local header = signs:FindFirstChild("LEVEL " .. level .. " Door Header")
		if state.mounted[level] or not header or not header:IsA("BasePart")
			or header:GetAttribute("Level") ~= level then continue end
		state.mounted[level] = true -- Set before parenting parts triggers DescendantAdded.
		local gate = header.CFrame * CFrame.new(0, -17.2, -1.42)
		local container = Instance.new("Model")
		container.Name = "Level" .. level .. " Client Gate"
		container:SetAttribute("LevelNumber", level)
		container:SetAttribute("PreviewAllowed", permissions[level])
		container.Parent = state.folder
		local amber, cyan = Color3.fromRGB(243, 194, 87), Color3.fromRGB(194, 248, 229)
		for _, x in ipairs({-5, 5}) do
			newPart(container, "Status Mount", Vector3.new(.12, .85, .18),
				gate * CFrame.new(x, 19.06, 1.2), Color3.fromRGB(48, 48, 42), false)
		end
		local status = newPart(container, "Mounted Access Subtitle", Vector3.new(14, .75, .08),
			gate * CFrame.new(0, 19.6, 1.46), Color3.fromRGB(20, 24, 22), false)
		sign(status, if permissions[level] then "DEV PREVIEW" else "COMING SOON",
			if permissions[level] then cyan else amber, Vector2.new(900, 80))
		if permissions[level] then continue end
		-- Door clear opening is 19.9 x 15.6 studs; the shutter overlaps its jambs .05 each side.
		newPart(container, "Coming Soon Shutter", Vector3.new(20, 15.6, .35),
			gate * CFrame.new(0, 7.8, 0), Color3.fromRGB(71, 69, 55), true)
		for y = 1, 15, 1 do
			newPart(container, "Shutter Rib", Vector3.new(19.8, .10, .06),
				gate * CFrame.new(0, y, .205), Color3.fromRGB(91, 88, 69), false)
		end
		local notice = newPart(container, "Coming Soon Notice", Vector3.new(15.9, 11.9, .07),
			gate * CFrame.new(0, 7.8, .255), Color3.fromRGB(9, 14, 13), false)
		comingSoonDisplay(notice, level)
		local warning = newPart(container, "Lower Safety Stripe", Vector3.new(19.6, .28, .06),
			gate * CFrame.new(0, .68, .24), amber, false)
		warning.CastShadow = false
	end
end

```

CLIENT bayLevel excerpt:
```luau
local function bayLevel(instance, model)
	local current = instance
	while current and current ~= model do
		if current:IsA("Model") then
			if current.Name == "QueueBay_Level5" then return 5 end
			if current.Name == "QueueBay_Level6" then return 6 end
		end
		current = current.Parent
	end
	return nil
end

```

CLIENT hideBlocked excerpt:
```luau
local function hideBlocked(state, instance)
	local level = bayLevel(instance, state.model)
	if not level or permissions[level] or state.hidden[instance] then return end
	local property
	if instance:IsA("TextLabel") and (instance.Name == "QueueTitle" or instance.Name == "QueueSubtitle") then
		property = "Visible"
	elseif instance:IsA("ProximityPrompt") and instance.Name == "Level" .. level .. "DeveloperPreviewPrompt" then
		property = "Enabled"
	end
	if not property then return end
	local saved = {property = property, previous = instance[property]}
	state.hidden[instance] = saved
	instance[property] = false
	saved.connection = instance:GetPropertyChangedSignal(property):Connect(function()
		if active == state and instance[property] ~= false then instance[property] = false end
	end)
end

```

NEW PHYSICAL SERVER GUARD FULLCODE:
```luau
-- Authoritative, bounded Level 5/6 lobby bay access; client shutters are presentation.
-- No character collision groups, other levels, campaign progression or map geometry change.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local DevAccess = require(game:GetService("ReplicatedStorage"):WaitForChild("DevAccess"))
local Module = {}
local states = setmetatable({}, {__mode = "k"})
local INTERVAL = .2
local LEVELS = {5, 6}

local function ownedReady(model)
	return typeof(model) == "Instance" and model:IsA("Model")
		and model.Name == "LobbyReimaginedPreview" and model.Parent == workspace
		and model:GetAttribute("LobbyReimaginedOwned") == true
		and model:GetAttribute("LobbyVisualRevision") == 4
		and model:GetAttribute("Ready") == true
end

local function allowed(player)
	local ok, result = pcall(DevAccess.IsLevel6PreviewAllowed, player)
	return ok and result == true
end

local function insideProtectedBay(record, position)
	-- Circular chamber floor and actual portal transform are the only protected volumes.
	-- The rectangle is just the narrow connector/aperture, never the tunnel or sidewalk.
	local gate = record.header.CFrame * CFrame.new(0, -17.2, -1.42)
	local localPoint = gate:PointToObjectSpace(position)
	if math.abs(localPoint.X) <= 10 and localPoint.Y >= -2 and localPoint.Y <= 18
		and localPoint.Z < -.12 and localPoint.Z >= -14 then return true, gate end
	local floor = record.floor
	local delta = position - floor.Position
	local halfThickness = math.min(floor.Size.X, floor.Size.Y, floor.Size.Z) * .5
	local top = floor.Position.Y + halfThickness
	local radius = record.radius
	return delta.X * delta.X + delta.Z * delta.Z <= radius * radius
		and position.Y >= top - 2 and position.Y <= top + 24, gate
end

local function stop(state)
	if state.stopped then return end
	state.stopped = true
	for _, connection in ipairs(state.connections) do connection:Disconnect() end
	table.clear(state.connections)
	if states[state.model] == state then states[state.model] = nil end
end

function Module.Start(model)
	assert(not RunService:IsClient(), "Developer bay guard is server-only")
	assert(ownedReady(model), "Developer bay guard requires the exact ready owned R4 lobby")
	if states[model] then return states[model] end
	local pads = assert(model:FindFirstChild("PreviewQueuePads"), "Missing queue bay folder")
	local signs = assert(model:FindFirstChild("LevelGateSigns"), "Missing gate signs")
	local records = {}
	for _, level in ipairs(LEVELS) do
		local bay = pads:FindFirstChild("QueueBay_Level" .. level)
		local floor = bay and bay:FindFirstChild("ChamberFloor")
		local header = signs:FindFirstChild("LEVEL " .. level .. " Door Header")
		local diameter = bay and bay:GetAttribute("CircularBayDiameter")
		assert(bay and bay:IsA("Model") and floor and floor:IsA("BasePart")
			and floor.Anchored and floor.CanCollide and floor.Parent == bay
			and header and header:IsA("BasePart") and header.Parent == signs
			and header:GetAttribute("Level") == level
			and type(diameter) == "number" and diameter > 40 and diameter < 65,
			"Wrong Level " .. level .. " bay guard geometry")
		table.insert(records, {level = level, bay = bay, floor = floor, header = header,
			radius = diameter * .5 + .5})
	end
	local state = {model = model, records = records, connections = {}, stopped = false, elapsed = 0}
	states[model] = state
	model:SetAttribute("DevBayAccessGuardVersion", 1)
	model:SetAttribute("DevBayProtectedLevels", "5,6")
	model:SetAttribute("DevBayGuardInterval", INTERVAL)
	if model:GetAttribute("DevBayDeniedEntryCount") == nil then model:SetAttribute("DevBayDeniedEntryCount", 0) end
	table.insert(state.connections, model.Destroying:Connect(function() stop(state) end))
	table.insert(state.connections, model.AncestryChanged:Connect(function()
		if model.Parent ~= workspace then stop(state) end
	end))
	table.insert(state.connections, RunService.Heartbeat:Connect(function(deltaTime)
		if state.stopped then return end
		state.elapsed += deltaTime
		if state.elapsed < INTERVAL then return end
		state.elapsed = 0 -- One sweep, never accumulated catch-up work after a long frame.
		if not ownedReady(model) or workspace:GetAttribute("ReservedRoundServer") == true then return end
		for _, player in ipairs(Players:GetPlayers()) do
			if player.Parent ~= Players or allowed(player) then continue end
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local root = humanoid and humanoid.RootPart
			if not root or humanoid.Health <= 0 or not character:IsDescendantOf(workspace) then continue end
			for _, record in ipairs(records) do
				if record.bay.Parent ~= pads or record.floor.Parent ~= record.bay
					or record.header.Parent ~= signs then continue end
				local inside, gate = insideProtectedBay(record, root.Position)
				if not inside then continue end
				-- Let the seat release before moving so a welded chair is never moved with a player.
				if humanoid.SeatPart then humanoid.Sit = false; break end
				local target = (gate * CFrame.new(0, 3, 3.75)).Position
				local outward = Vector3.new(gate.ZVector.X, 0, gate.ZVector.Z)
				local safe = CFrame.lookAt(target, target - outward)
				-- Move the exact live character, preserving its pivot relative to the root.
				character:PivotTo(safe * root.CFrame:ToObjectSpace(character:GetPivot()))
				root.AssemblyLinearVelocity, root.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
				model:SetAttribute("DevBayDeniedEntryCount", model:GetAttribute("DevBayDeniedEntryCount") + 1)
				break
			end
		end
	end))
	return state
end

return Module

```

GAME MANAGER CRITICAL ADMISSION FULLFUNCTION:
```luau
local function playerInsideZone(player, station, includeBusy)
 -- Public revision queues stay open; both unfinished bays require real DEV authorization.
 if station.revisionOwned and station.level >= 5 and not DevAccess.IsLevel6PreviewAllowed(player) then return false end
 if station.previewQueue then
  local bridge = revisedQueueBridge()
  if not (bridge and bridge.AllowsPreview(station, player))
   and not (isLevel4Choice(station) and not station.launchMode and canAccessLevel(station.level, {player})) then
   return false
  end
 elseif station.level > Routing.MaxLevel and not canAccessLevel(station.level, {player}) then return false end
 if inRound[player] or (station.busy and not includeBusy) then return false end
 local char = player.Character
 local hum = char and char:FindFirstChildOfClass("Humanoid")
 local root = char and char:FindFirstChild("HumanoidRootPart")
 if player.Parent ~= Players or not (char and char.Parent and hum and hum.Health > 0
  and root and root:IsA("BasePart")) then return false end
 local zone = station.zone
 if not zone or not zone.Parent then return false end
 local p = zone.CFrame:PointToObjectSpace(root.Position)
 local radius = queueRadius(station)
 local inside = if radius then p.X * p.X + p.Z * p.Z <= radius * radius
  else math.abs(p.X) <= zone.Size.X * .5 and math.abs(p.Z) <= zone.Size.Z * .5
 return inside and p.Y > -6 and p.Y < 12
end


```

UNCHANGED BRIDGE AllowsPreview excerpt:
```luau
function Bridge.AllowsPreview(station, player, context)
    local callbacks = liveLauncher(station)
    if not callbacks or player:GetAttribute("Level6InRound") == true then return false end
    local previous = preparations[station]
    if previous and not previous.active then return false end
    local ok, allowed = pcall(callbacks.allowed, player, context, station)
    return ok and allowed == true
end


```

UNCHANGED BRIDGE ValidateQueueAdmission excerpt:
```luau
function Bridge.ValidateQueueAdmission(context, player, character, requireZone)
    local state = contexts[context]
    if not state or not state.active or os.clock() > state.deadline then return nil end
    local station = state.station
    if not station.busy or station.cancelRequested or station.admissionEpoch ~= state.epoch
        or state.characters[player] ~= character or not ownedStation(station)
        or liveLauncher(station) ~= state.callbacks then return nil end
    local root, humanoid = livingRoot(player, character)
    if not root then return nil end
    -- Once committed, Runtime.Join sets Level6InRound. Admission was already
    -- checked for the whole frozen cohort; the living character is still checked.
    if requireZone ~= false then
        if not Bridge.AllowsPreview(station, player, context) or not insideZone(station, root) then return nil end
    else
        local ok, allowed = pcall(state.callbacks.allowed, player, context, station)
        if not ok or allowed ~= true then return nil end
    end
    return root, humanoid
end


```

UNCHANGED BRIDGE LaunchPreviewGroup excerpt:
```luau
function Bridge.LaunchPreviewGroup(station, players)
    local callbacks = liveLauncher(station)
    if not callbacks or not station.busy or type(players) ~= "table" or #players < 1 or #players > 6 then
        return false, "PREVIEW_LAUNCHER_UNAVAILABLE"
    end
    -- An abandoned EnsureWorld must finish its own bounded cleanup. Never
    -- task.cancel it or create another waiting job for this same station.
    if preparations[station] then return false, "PREVIEW_PREPARATION_BUSY" end
    local context = {}
    local state = {active=true, station=station, callbacks=callbacks, epoch=station.admissionEpoch,
        deadline=os.clock()+1400, players={}, characters={}, finalizers={}}
    contexts[context] = state
    for _, player in ipairs(players) do
        local character = player.Character
        if state.characters[player] or not character then closeContext(context,state); return false, "INVALID_COHORT" end
        state.characters[player] = character; table.insert(state.players, player)
        if not Bridge.ValidateQueueAdmission(context, player, character) then
            closeContext(context,state); return false, "QUEUE_COHORT_CHANGED"
        end
    end
    preparations[station] = state
    local done, ok, joined, problem = false, false, false, nil
    task.spawn(function()
        ok, joined, problem = pcall(callbacks.launch, context)
        state.finished = true
        if not state.active then closeContext(context, state) end
        done = true
        if preparations[station] == state then preparations[station] = nil end
    end)
    while not done do
        local valid = true
        for _, player in ipairs(state.players) do
            if not Bridge.ValidateQueueAdmission(context, player, state.characters[player], not state.committing) then
                valid = false; break
            end
        end
        if not valid then
            closeContext(context,state)
            if state.committing then
                -- A Join already in flight owns rollback. Keep this station
                -- busy until it finishes so no new queue can replace its epoch.
                while not done do task.wait(.1) end
            end
            return false, "QUEUE_COHORT_CHANGED"
        end
        task.wait(.1)
    end
    closeContext(context,state)
    return ok and joined == true, if ok then problem else tostring(joined)
end


```
