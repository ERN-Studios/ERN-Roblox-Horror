-- First four-colour lock and seven physical section gates. No rewards/completion.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local DevAccess = require(RS:WaitForChild("DevAccess"))
local Logic = require(script.Parent:WaitForChild("Level 5 Colour Lock Logic"))
local Progression = {}
local sessions = setmetatable({}, {__mode = "k"})
local VERSION = "2026-09-26.colour-lock.1"
local COLOURS = {Color3.fromRGB(160,44,43), Color3.fromRGB(225,189,73), Color3.fromRGB(54,99,165), Color3.fromRGB(52,122,81)}
local CREAM, DARK = Color3.fromRGB(215,207,181), Color3.fromRGB(43,47,43)
local V, CF = Vector3.new, CFrame.new

function Progression.Cleanup(world)
	local s = sessions[world]
	if not s or s.closed then return end
	s.closed = true; sessions[world] = nil
	for _, c in ipairs(s.connections) do c:Disconnect() end
	for _, t in ipairs(s.tweens) do t:Cancel() end
	table.clear(s.clients)
	for _, gui in ipairs(s.clueGuis) do gui:Destroy() end
	if s.remoteFolder then s.remoteFolder:Destroy() end
	if s.owner then s.owner:Destroy() end
end

function Progression.Start(world, manifest, config)
	assert(RunService:IsServer() and RunService:IsRunning(), "Section progression requires a running server")
	assert(world and world:IsA("Model") and world.Parent == workspace and world:GetAttribute("Level5_MapOnly") == true,
		"Expected the current Level 5 generated world")
	assert(type(manifest) == "table" and type(manifest.Zones) == "table" and #manifest.Zones == 8, "Expected eight section bounds")
	assert(typeof(manifest.Origin) == "Vector3", "Manifest Origin must be a world Vector3")
	if sessions[world] then return {ok = false, error = "Already started"} end
	assert(not world:FindFirstChild("Level5SectionProgression"), "Preserve foreign section owner")
	assert(not RS:FindFirstChild("Level5Progression"), "Preserve existing progression remote folder")
	config = config or {}
	local s = {world = world, connections = {}, tweens = {}, clients = {}, gates = {}, clueGuis = {}, closed = false}
	sessions[world] = s
	local ok, result = pcall(function()
		local token = HttpService:GenerateGUID(false)
		local owner = Instance.new("Folder"); owner.Name = "Level5SectionProgression"
		owner:SetAttribute("Level5ProgressionOwned", true); owner:SetAttribute("WorldToken", token)
		owner:SetAttribute("Version", VERSION); owner:SetAttribute("Puzzle1Solved", false)
		owner.Parent = world; s.owner = owner
		local remoteFolder = Instance.new("Folder"); remoteFolder.Name = "Level5Progression"
		remoteFolder:SetAttribute("Level5ProgressionOwned", true); remoteFolder:SetAttribute("WorldToken", token)
		s.remoteFolder = remoteFolder
		local submit = Instance.new("RemoteEvent"); submit.Name = "Submit"; submit.Parent = remoteFolder
		local state = Instance.new("RemoteEvent"); state.Name = "State"; state.Parent = remoteFolder
		local function connect(signal, callback) table.insert(s.connections, signal:Connect(callback)) end
		local function part(parent, name, size, cf, colour, collision)
			local p = Instance.new("Part"); p.Name = name; p.Size = size; p.CFrame = cf
			p.Anchored = true; p.Color = colour or CREAM; p.Material = Enum.Material.SmoothPlastic
			p.CanCollide = collision == true; p.CanQuery = collision == true; p.CanTouch = false
			p.TopSurface = Enum.SurfaceType.Smooth; p.BottomSurface = Enum.SurfaceType.Smooth
			p:SetAttribute("Level5ProgressionOwned", true); p.Parent = parent; return p
		end
		local function surface(parent, text, size)
			local gui = Instance.new("SurfaceGui"); gui.Name = "LockLabel"; gui.Face = Enum.NormalId.Front
			gui.AlwaysOnTop = false; gui.LightInfluence = 1; gui.CanvasSize = size or Vector2.new(640,256)
			gui.Parent = parent
			local label = Instance.new("TextLabel"); label.Size = UDim2.fromScale(1,1)
			label.BackgroundColor3 = CREAM; label.BackgroundTransparency = .04; label.BorderSizePixel = 0
			label.TextColor3 = DARK; label.Font = Enum.Font.GothamBold; label.TextScaled = true
			label.TextWrapped = true; label.Text = text; label.Parent = gui
			local padding = Instance.new("UIPadding"); padding.PaddingLeft = UDim.new(.05,0); padding.PaddingRight = UDim.new(.05,0)
			padding.PaddingTop = UDim.new(.08,0); padding.PaddingBottom = UDim.new(.08,0); padding.Parent = label
			return gui, label
		end
		local function live()
			return not s.closed and world.Parent == workspace and owner.Parent == world and remoteFolder.Parent == RS
		end
		local function canUse(player, gate)
			if not player or player.Parent ~= Players or not gate then return false end
			local char = player.Character; local root = char and char:FindFirstChild("HumanoidRootPart")
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			local distance = root and (root.Position - gate.lock.Position).Magnitude or math.huge
			local lineOfSight = false
			if root and distance <= 14 then
				local rp = RaycastParams.new(); rp.FilterType = Enum.RaycastFilterType.Exclude
				rp.FilterDescendantsInstances = {char, gate.model}
				lineOfSight = workspace:Raycast(root.Position, gate.lock.Position - root.Position, rp) == nil
			end
			return Logic.CanUse({live = live(), roundActive = workspace:GetAttribute("RoundActive"), level = workspace:GetAttribute("SelectedLevel"),
				inRound = player:GetAttribute("InRound"), escaped = player:GetAttribute("Escaped"), spectating = player:GetAttribute("Spectating"),
				health = hum and hum.Health or 0, distance = distance, lineOfSight = lineOfSight})
		end
		local function unlock(index, mode)
			local gate = s.gates[index]
			if not live() or not gate or gate.open then return false end
			gate.open = true; gate.model:SetAttribute("Unlocked", true); gate.model:SetAttribute("OpenReason", mode)
			for _, prompt in ipairs(gate.prompts) do prompt.Enabled = false end
			gate.label.Text = index == 1 and (mode == "SOLVED" and "COLOUR LOCK OPEN\nSECTION 2" or "DEVELOPER BYPASS\nSECTION 2") or "DEVELOPER PREVIEW\nSECTION "..(index+1)
			if index == 1 then
				owner:SetAttribute("Puzzle1Solved", mode == "SOLVED")
				if mode == "SOLVED" then
					for wheelIndex, visual in ipairs(gate.wheelLabels) do
						visual.part.Color=COLOURS[wheelIndex]
						visual.label.Text=wheelIndex.."\n"..Logic.Symbols[wheelIndex].."\n"..Logic.Choices[wheelIndex]
						visual.label.TextColor3=wheelIndex==2 and DARK or Color3.new(1,1,1)
					end
				end
				state:FireAllClients("unlocked", {worldToken = token, gate = 1, solved = mode == "SOLVED"})
				table.clear(s.clients)
			end
			for side, leaf in pairs(gate.leaves) do
				local tween = TweenService:Create(leaf, TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
					{CFrame = leaf.CFrame * CF(side * 11.8, 0, 0)})
				table.insert(s.tweens, tween)
				connect(tween.Completed, function(playback)
					if not s.closed and playback == Enum.PlaybackState.Completed and leaf.Parent then
						leaf.CanCollide = false; leaf.CanQuery = false
						gate.completed += 1
						if gate.completed == 2 then gate.model:SetAttribute("FullyOpen", true) end
					end
				end)
				tween:Play()
			end
			return true
		end
		for index = 1, 7 do
			local zone = manifest.Zones[index]
			assert(typeof(zone.Max) == "Vector3", "Each section needs local Max Vector3")
			local frame = CF(manifest.Origin + V(0,0,zone.Max.Z))
			local gateModel = Instance.new("Model"); gateModel.Name = "SectionGate"..index
			gateModel:SetAttribute("Level5ProgressionOwned", true); gateModel:SetAttribute("GateIndex", index)
			gateModel:SetAttribute("Unlocked", false); gateModel:SetAttribute("FullyOpen", false); gateModel.Parent = owner
			local gate = {model = gateModel, leaves = {}, prompts = {}, wheelLabels = {}, completed = 0, open = false}; s.gates[index] = gate
			-- A 22x14 clear opening; structural boundary walls are authored by Architecture.
			part(gateModel,"Lintel",V(24.4,1.0,1.2),frame*CF(0,14.5,0),CREAM,true)
			part(gateModel,"SlideTrack",V(45, .38, .55),frame*CF(0,14.03,-.5),DARK,false)
			for _, side in ipairs({-1,1}) do
				part(gateModel,"Jamb"..side,V(1.0,14,1.2),frame*CF(side*11.5,7,0),CREAM,true)
				local leaf = part(gateModel,"SlidingLeaf"..side,V(11,13.96,.55),frame*CF(side*5.5,7,0),CREAM,true)
				gate.leaves[side] = leaf
				-- Decorative recessed rectangles are welded via child CFrames by tweening a model-free leaf only.
				local face = Instance.new("SurfaceGui"); face.Name = "DomesticPanels"; face.Face = Enum.NormalId.Front
				face.LightInfluence = 1; face.CanvasSize = Vector2.new(440,560); face.Parent = leaf
				for row = 0,1 do
					local panel = Instance.new("Frame"); panel.Position = UDim2.new(.12,0,.10+row*.44,0)
					panel.Size = UDim2.new(.76,0,.34,0); panel.BackgroundColor3 = Color3.fromRGB(195,187,163)
					panel.BorderSizePixel = 3; panel.BorderColor3 = Color3.fromRGB(233,225,202); panel.Parent = face
				end
			end
			local lockFrame = frame*CF(12.85,4.4,-1.3)
			gate.lock = part(gateModel,"ColourPadlock",V(2.6,3,1.1),lockFrame,DARK,false)
			gate.lock.Material = Enum.Material.Metal
			-- A real industrial U shackle and four raised combination drums.
			local steel = Color3.fromRGB(163,166,153)
			for _, side in ipairs({-1,1}) do
				local leg = part(gateModel,"ShackleLeg"..side,V(.23,1.5,.28),lockFrame*CF(side*.85,2.05,0),steel,false)
				leg.Material = Enum.Material.Metal
			end
			local shackleTop = part(gateModel,"ShackleTop",V(1.93,.23,.28),lockFrame*CF(0,2.8,0),steel,false)
			shackleTop.Material = Enum.Material.Metal
			for wheelIndex=1,4 do
				local x = (wheelIndex-2.5)*.55
				local drum = part(gateModel,"CombinationDrum"..wheelIndex,V(.45,1.05,1.05),lockFrame*CF(x,-.12,-.45),Color3.fromRGB(116,120,108),false)
				drum.Shape = Enum.PartType.Cylinder; drum.Material = Enum.Material.Metal
				local dial = part(gateModel,"DialFace"..wheelIndex,V(.38,.86,.025),lockFrame*CF(x,-.12,-.99),COLOURS[1],false)
				local _, dialLabel = surface(dial,wheelIndex.."\n"..Logic.Symbols[1].."\n"..Logic.Choices[1],Vector2.new(128,220))
				dialLabel.BackgroundTransparency=1;dialLabel.TextColor3=Color3.new(1,1,1)
				table.insert(gate.wheelLabels,{part=dial,label=dialLabel})
				if wheelIndex<4 then
					part(gateModel,"DialSeparator"..wheelIndex,V(.025,1.16,.025),lockFrame*CF(x+.275,-.12,-1.01),Color3.fromRGB(235,232,218),false)
				end
			end
			local sign = part(gateModel,"SectionLabel",V(10,1.8,.1),frame*CF(0,15.7,-.72),CREAM,false)
			-- The fixed plaque sits above the 14-stud clear opening.
			local _, label = surface(sign,index==1 and "FOUR HOUSE CLUES\nCOLOUR LOCK • 1 2 3 4" or "UNSOLVED\nDEVELOPER PREVIEW")
			gate.label = label
			if index == 1 then
				local prompt = Instance.new("ProximityPrompt"); prompt.Name = "ColourLockPrompt"
				prompt.ActionText = "Set four colours"; prompt.ObjectText = "House colour lock"
				prompt.HoldDuration = 0; prompt.MaxActivationDistance = 12; prompt.RequiresLineOfSight = false
				prompt.KeyboardKeyCode = Enum.KeyCode.E; prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
				prompt.Parent = gate.lock; table.insert(gate.prompts,prompt)
				connect(prompt.Triggered,function(player)
					if gate.open or not canUse(player,gate) then return end
					local last = s.clients[player]
					if last and os.clock() - last.opened < .5 then return end
					local entry = {nonce = HttpService:GenerateGUID(false), opened = os.clock(), lastSubmit = -math.huge}
					s.clients[player] = entry
					state:FireClient(player,"open",{worldToken=token,nonce=entry.nonce,gate=1,lock=gate.lock})
				end)
			end
			if config.AllowDeveloperBypass ~= false then
				local prompt = Instance.new("ProximityPrompt"); prompt.Name = "DeveloperBypass"
				prompt:SetAttribute("DeveloperOnly",true); prompt.ActionText = "DEV: bypass this gate"
				prompt.ObjectText = "Skip puzzle • section "..(index+1); prompt.HoldDuration = 1.5
				prompt.MaxActivationDistance = 12; prompt.RequiresLineOfSight = false
				prompt.KeyboardKeyCode = Enum.KeyCode.F; prompt.GamepadKeyCode = Enum.KeyCode.ButtonY
				prompt.UIOffset = Vector2.new(0,index==1 and 84 or 0); prompt.Exclusivity = Enum.ProximityPromptExclusivity.AlwaysShow
				prompt.Parent = gate.lock; table.insert(gate.prompts,prompt)
				connect(prompt.Triggered,function(player)
					if DevAccess.IsAllowed(player) and canUse(player,gate) then unlock(index,"DEVELOPER_BYPASS") end
				end)
			end
		end
		local seen = {}
		for _, house in ipairs(world:GetDescendants()) do
			local index = house:GetAttribute("PuzzleClueIndex")
			if house:IsA("Model") and index ~= nil then
				assert(type(index)=="number" and index%1==0 and index>=1 and index<=4 and not seen[index],"Invalid/duplicate clue house index")
				seen[index]=true
				local marker = house:FindFirstChild("PuzzleClueSurface",true)
				assert(marker and marker:IsA("BasePart"),"Clue house needs PuzzleClueSurface")
				assert(not marker:FindFirstChild("Level5ColourClue"),"Preserve existing clue surface UI")
				local gui,label = surface(marker,"",Vector2.new(512,640)); gui.Name="Level5ColourClue"
				table.insert(s.clueGuis,gui)
				gui:SetAttribute("Level5ProgressionOwned",true); label:Destroy()
				local backing = Instance.new("Frame"); backing.Size=UDim2.fromScale(1,1); backing.BackgroundTransparency=1
				backing.BorderSizePixel=0; backing.Parent=gui
				local texture = config.ClueTextures and config.ClueTextures[index]
				if type(texture)=="number" then texture="rbxassetid://"..texture end
				if type(texture)=="string" and texture:match("^rbxassetid://%d+$") then
					local picture=Instance.new("ImageLabel"); picture.Name="ClueArtwork"; picture.Size=UDim2.fromScale(1,.77)
					picture.BackgroundTransparency=1; picture.Image=texture; picture.ScaleType=Enum.ScaleType.Fit; picture.Parent=backing
				end
				local label=Instance.new("TextLabel"); label.Position=UDim2.fromScale(.03,.77); label.Size=UDim2.fromScale(.94,.2)
				label.BackgroundTransparency=1; label.BorderSizePixel=0
				label.TextColor3=index==2 and Color3.fromRGB(132,94,17) or COLOURS[index]; label.Font=Enum.Font.GothamBold
				label.TextScaled=true; label.Text=tostring(index).."  "..Logic.Symbols[index].."  "..Logic.Choices[index]; label.Parent=backing
				-- Clue surfaces belong to geometry; clean only our SurfaceGui if Cleanup runs on a retained world.
			end
		end
		for index=1,4 do assert(seen[index],"Missing numbered clue house "..index) end
		connect(submit.OnServerEvent,function(player,action,nonce,sequence)
			local entry=s.clients[player]
			if not entry or type(nonce)~="string" or #nonce>64 or nonce~=entry.nonce then return end
			if action=="close" then s.clients[player]=nil; return end
			if action~="submit" or os.clock()-entry.lastSubmit<.65 then return end
			entry.lastSubmit=os.clock()
			if os.clock()-entry.opened>120 or not canUse(player,s.gates[1]) then
				s.clients[player]=nil; state:FireClient(player,"close",{worldToken=token}); return
			end
			if s.gates[1].open then state:FireClient(player,"unlocked",{worldToken=token,gate=1}); return end
			if not Logic.ValidateSequence(sequence) then state:FireClient(player,"result",{worldToken=token,correct=false,text="Choose one colour on each of the four wheels."}); return end
			if Logic.Matches(sequence) then unlock(1,"SOLVED")
			else state:FireClient(player,"result",{worldToken=token,correct=false,text="That order does not match. Check house clues 1–4 and try again."}) end
		end)
		connect(Players.PlayerRemoving,function(player) s.clients[player]=nil end)
		connect(world.Destroying,function() Progression.Cleanup(world) end)
		connect(world.AncestryChanged,function() if world.Parent~=workspace then Progression.Cleanup(world) end end)
		connect(owner.Destroying,function() if not s.closed then Progression.Cleanup(world) end end)
		connect(remoteFolder.Destroying,function() if not s.closed then Progression.Cleanup(world) end end)
		remoteFolder.Parent=RS
		return {ok=true,folder=owner,version=VERSION,gateCount=7,clueCount=4}
	end)
	if not ok then Progression.Cleanup(world); return {ok=false,error=tostring(result)} end
	return result
end
return Progression
