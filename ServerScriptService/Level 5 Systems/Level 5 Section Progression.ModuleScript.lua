-- Seven small household puzzles and shared section gates. No rewards/completion.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local MaterialService = game:GetService("MaterialService")
local DevAccess = require(RS:WaitForChild("DevAccess"))
local Logic = require(script.Parent:WaitForChild("Level 5 Colour Lock Logic"))
local Catalog = require(script.Parent:WaitForChild("Level 5 Puzzle Catalog"))
local Outage = require(script.Parent:WaitForChild("Level 5 Power Outage"))
local Progression = {}
local sessions = setmetatable({}, {__mode = "k"})
local VERSION = "2026-09-26.seven-household-puzzles.3"
local COLOURS = {Color3.fromRGB(160,44,43), Color3.fromRGB(225,189,73), Color3.fromRGB(54,99,165), Color3.fromRGB(52,122,81)}
local CREAM, DARK = Color3.fromRGB(215,207,181), Color3.fromRGB(43,47,43)
local V, CF = Vector3.new, CFrame.new
local function finishMaterial(object,material,variantName)
	object.Material=material
	local variant=MaterialService:FindFirstChild(variantName)
	if variant and variant:IsA("MaterialVariant") and variant.BaseMaterial==material then object.MaterialVariant=variantName end
	return object
end

-- Native printed diagrams. Labels remain readable without recognising a pictogram.
local function diagramRect(parent,x,y,w,h,colour,rotation)
	local f=Instance.new("Frame");f.BorderSizePixel=0;f.BackgroundColor3=colour
	f.Position=UDim2.fromScale(x,y);f.Size=UDim2.fromScale(w,h);f.Rotation=rotation or 0;f.Parent=parent;return f
end
local function diagramText(parent,value,x,y,w,h,colour)
	local t=Instance.new("TextLabel");t.BackgroundTransparency=1;t.Text=value;t.TextColor3=colour or DARK
	t.Font=Enum.Font.GothamBold;t.TextScaled=true;t.TextWrapped=true;t.Position=UDim2.fromScale(x,y);t.Size=UDim2.fromScale(w,h);t.Parent=parent;return t
end
local function diagramCircle(parent,x,y,w,h,colour)
	local f=diagramRect(parent,x,y,w,h,colour);local c=Instance.new("UICorner");c.CornerRadius=UDim.new(1,0);c.Parent=f;return f
end
local function diagramLine(parent,ax,ay,bx,by,colour)
	local dx,dy=bx-ax,by-ay
	local f=diagramRect(parent,(ax+bx)/2,(ay+by)/2,math.sqrt(dx*dx+dy*dy),.055,colour,math.deg(math.atan2(dy,dx)))
	f.AnchorPoint=Vector2.new(.5,.5);return f
end
local function paintDiagram(parent,mode,choice,label)
	local ink=Color3.fromRGB(35,43,37);local paper=Color3.fromRGB(224,216,190)
	if mode=="symbols" then
		if label=="KEY" then
			diagramCircle(parent,.08,.19,.34,.42,ink);diagramCircle(parent,.15,.28,.2,.24,paper)
			diagramRect(parent,.32,.36,.57,.11,ink);diagramRect(parent,.7,.41,.08,.2,ink);diagramRect(parent,.83,.41,.08,.16,ink)
		elseif label=="LAMP" then
			diagramRect(parent,.18,.15,.64,.26,ink);diagramRect(parent,.47,.35,.07,.4,ink);diagramRect(parent,.25,.73,.5,.08,ink)
		elseif label=="CHAIR" then
			diagramRect(parent,.21,.12,.11,.5,ink);diagramRect(parent,.24,.51,.54,.1,ink)
			diagramRect(parent,.25,.6,.09,.26,ink);diagramRect(parent,.67,.6,.09,.26,ink)
		else
			diagramCircle(parent,.57,.29,.35,.4,ink);diagramCircle(parent,.66,.38,.18,.21,paper)
			diagramRect(parent,.16,.25,.49,.47,ink);diagramRect(parent,.16,.73,.62,.055,ink)
		end
	elseif mode=="switches" then
		diagramRect(parent,.28,.08,.44,.81,ink);diagramRect(parent,.34,choice==2 and .15 or .52,.32,.29,paper)
		diagramText(parent,choice==2 and "↑" or "↓",.36,.18,.28,.58,choice==2 and ink or paper)
	elseif mode=="clocks" then
		diagramCircle(parent,.12,.03,.76,.9,ink);diagramCircle(parent,.17,.09,.66,.78,paper)
		for _,tick in ipairs({{"12",.40,.07},{"3",.73,.4},{"6",.42,.70},{"9",.12,.4}}) do diagramText(parent,tick[1],tick[2],tick[3],.17,.18,ink) end
		local hours=({12,3,6,9})[choice];local angle=math.rad(hours*30-90)
		diagramLine(parent,.5,.48,.5+math.cos(angle)*.20,.48+math.sin(angle)*.25,ink)
		diagramLine(parent,.5,.48,.5,.17,ink);diagramCircle(parent,.465,.445,.07,.07,ink)
	elseif mode=="television" then
		local shell=diagramRect(parent,.07,.17,.85,.65,ink);local corner=Instance.new("UICorner");corner.CornerRadius=UDim.new(.12,0);corner.Parent=shell
		diagramRect(parent,.13,.24,.62,.45,Color3.fromRGB(144,155,124));diagramText(parent,label,.15,.30,.58,.32,ink)
		diagramCircle(parent,.81,.33,.06,.09,paper);diagramCircle(parent,.81,.51,.06,.09,paper)
		diagramLine(parent,.48,.16,.29,.025,ink);diagramLine(parent,.49,.16,.66,.025,ink)
	elseif mode=="arrows" then
		local house=Instance.new("Frame");house.BackgroundTransparency=1;house.Size=UDim2.fromScale(1,1);house.Rotation=(choice-1)*90;house.Parent=parent
		diagramLine(house,.18,.36,.5,.1,ink);diagramLine(house,.5,.1,.82,.36,ink)
		diagramRect(house,.25,.38,.5,.43,ink);diagramRect(house,.43,.57,.14,.25,paper)
		diagramText(house,"↑",.38,.28,.24,.34,paper)
	else diagramText(parent,label,.08,.04,.84,.89,ink) end
end

function Progression.Cleanup(world)
	local s = sessions[world]
	if not s or s.closed then return end
	s.closed = true; sessions[world] = nil
	Outage.Cleanup(world)
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
		local outageResult=Outage.Start(world,manifest)
		assert(outageResult.ok,outageResult.error)
		local token = HttpService:GenerateGUID(false)
		local owner = Instance.new("Folder"); owner.Name = "Level5SectionProgression"
		owner:SetAttribute("Level5ProgressionOwned", true); owner:SetAttribute("WorldToken", token)
		owner:SetAttribute("Version", VERSION)
		for index=1,7 do owner:SetAttribute("Puzzle"..index.."Solved",false) end
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
		local function previousOpen(index)
			return index==1 or (s.gates[index-1] and s.gates[index-1].model:GetAttribute("FullyOpen")==true)
		end
		local function unlock(index, mode)
			local gate = s.gates[index]
			if not live() or not gate or gate.open or not Catalog.CanAttempt(index,previousOpen(index)) then return false end
			gate.open = true; gate.model:SetAttribute("Unlocked", true); gate.model:SetAttribute("OpenReason", mode)
			owner:SetAttribute("Puzzle"..index.."Solved",mode=="SOLVED")
			for _, prompt in ipairs(gate.prompts) do prompt.Enabled = false end
			gate.label.Text=(mode=="SOLVED" and "PUZZLE SOLVED" or "DEVELOPER BYPASS").."\nSECTION "..(index+1)
			if mode=="SOLVED" and index==1 then
				for wheelIndex,visual in ipairs(gate.wheelLabels) do
					visual.part.Color=COLOURS[wheelIndex]
					visual.label.Text=wheelIndex.."\n"..Logic.Symbols[wheelIndex].."\n"..Logic.Choices[wheelIndex]
					visual.label.TextColor3=wheelIndex==2 and DARK or Color3.new(1,1,1)
				end
			end
			state:FireAllClients("unlocked",{worldToken=token,gate=index,solved=mode=="SOLVED"})
			for player,entry in pairs(s.clients) do if entry.gate==index then s.clients[player]=nil end end
			for side,leaf in pairs(gate.leaves) do
				local tween=TweenService:Create(leaf,TweenInfo.new(1.6,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut),
					{CFrame=leaf.CFrame*CF(side*11.8,0,0)})
				table.insert(s.tweens,tween)
				connect(tween.Completed,function(playback)
					if not s.closed and playback==Enum.PlaybackState.Completed and leaf.Parent then
						leaf.CanCollide=false;leaf.CanQuery=false;gate.completed+=1
						if gate.completed==2 then
							gate.model:SetAttribute("FullyOpen",true)
							Outage.Trigger(world,index)
						end
					end
				end)
				tween:Play()
			end
			return true
		end
		for index = 1, 7 do
			local zone = manifest.Zones[index]
			assert(typeof(zone.Max) == "Vector3", "Each section needs local Max Vector3")
			local placement=manifest.SectionGates and manifest.SectionGates[index]
			local frame=placement and placement.Frame or CF(manifest.Origin+V(0,0,zone.Max.Z))
			assert(typeof(frame)=="CFrame","Section gate needs a world CFrame")
			local wallThickness=placement and placement.WallThickness or 1.2
			assert(type(wallThickness)=="number" and wallThickness>=1 and wallThickness<=32,"Invalid gate shell thickness")
			local front=-wallThickness/2
			local definition=Catalog.Get(index)
			local gateModel = Instance.new("Model"); gateModel.Name = "SectionGate"..index
			gateModel:SetAttribute("Level5ProgressionOwned", true); gateModel:SetAttribute("GateIndex", index)
			gateModel:SetAttribute("Unlocked", false); gateModel:SetAttribute("FullyOpen", false); gateModel.Parent = owner
			local gate = {index=index,definition=definition,model = gateModel, leaves = {}, prompts = {}, wheelLabels = {}, completed = 0, open = false}; s.gates[index] = gate
			gateModel:SetAttribute("PuzzleMode",definition.mode)
			gateModel:SetAttribute("GateFrame",frame)
			-- A 22x14 clear opening; structural boundary walls are authored by Architecture.
			finishMaterial(part(gateModel,"Lintel",V(24.4,1.0,wallThickness+.4),frame*CF(0,14.5,0),CREAM,true),Enum.Material.Plaster,"Level5AgedPlaster")
			part(gateModel,"SlideTrack",V(45, .38, .55),frame*CF(0,14.03,front-.35),DARK,false).Material=Enum.Material.Metal
			for _, side in ipairs({-1,1}) do
				finishMaterial(part(gateModel,"Jamb"..side,V(1.0,14,wallThickness+.4),frame*CF(side*11.5,7,0),CREAM,true),Enum.Material.Plaster,"Level5AgedPlaster")
				local leaf = part(gateModel,"SlidingLeaf"..side,V(11,13.96,.55),frame*CF(side*5.5,7,0),CREAM,true)
				finishMaterial(leaf,Enum.Material.Wood,"Level5VeneerWood")
				gate.leaves[side] = leaf
				-- Decorative recessed rectangles are welded via child CFrames by tweening a model-free leaf only.
				local face = Instance.new("SurfaceGui"); face.Name = "DomesticPanels"; face.Face = Enum.NormalId.Front
				face.LightInfluence = 1; face.CanvasSize = Vector2.new(440,560); face.Parent = leaf
				for row = 0,1 do
					local panel = Instance.new("Frame"); panel.Position = UDim2.new(.12,0,.10+row*.44,0)
					panel.Size = UDim2.new(.76,0,.34,0); panel.BackgroundColor3 = Color3.fromRGB(195,187,163)
					panel.BackgroundTransparency=.65
					panel.BorderSizePixel = 3; panel.BorderColor3 = Color3.fromRGB(233,225,202); panel.Parent = face
				end
			end
			local lockFrame = frame*CF(12.85,4.4,front-1.2)
			gate.lock = part(gateModel,"ColourPadlock",V(2.6,3,1.1),lockFrame,DARK,false)
			gate.lock.Material = Enum.Material.Metal
			if index==1 then
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
			else
				gate.lock.Size=V(4.4,3.3,.65);gate.lock.Color=CREAM
				local consoleGui,oldLabel=surface(gate.lock,"",Vector2.new(720,500));oldLabel:Destroy()
				consoleGui.Name="HouseholdControlFace"
				for slot=1,definition.count do
					local cell=Instance.new("Frame");cell.BackgroundColor3=Color3.fromRGB(224,216,190);cell.BorderSizePixel=0
					cell.Position=UDim2.fromScale(.025+(slot-1)*.325,.02);cell.Size=UDim2.fromScale(.30,.96);cell.Parent=consoleGui
					diagramText(cell,definition.labels[slot],0,0,1,.17)
					local art=Instance.new("Frame");art.BackgroundTransparency=1;art.Position=UDim2.fromScale(.04,.19);art.Size=UDim2.fromScale(.92,.58);art.AnchorPoint=Vector2.new(.5,0);art.Position=UDim2.fromScale(.5,.19);art.Parent=cell
					local aspect=Instance.new("UIAspectRatioConstraint");aspect.AspectRatio=1;aspect.AspectType=Enum.AspectType.FitWithinMaxSize;aspect.Parent=art
					paintDiagram(art,definition.mode,1,definition.options[1].label)
					diagramText(cell,definition.options[1].label,0,.79,1,.18)
				end
				-- Distinct tactile silhouettes; all decoration stays outside the passage and noncolliding.
				if definition.mode=="television" then
					part(gateModel,"TelevisionConsoleBack",V(4.8,3.5,.9),lockFrame*CF(0,0,.35),DARK,false)
				elseif definition.mode=="switches" then
					for slot=1,3 do part(gateModel,"RockerSwitch"..slot,V(.30,.64,.19),lockFrame*CF((slot-2)*1.35,0,-.48)*CFrame.Angles(math.rad(18),0,0),DARK,false) end
				elseif definition.mode=="clocks" then
					for slot=1,3 do local knob=part(gateModel,"ClockAdjustmentKnob"..slot,V(.22,.22,.2),lockFrame*CF((slot-2)*1.35,-1.45,-.4),DARK,false);knob.Shape=Enum.PartType.Ball end
				end
			end
			local sign = part(gateModel,"SectionLabel",V(10,1.8,.1),frame*CF(0,15.7,front-.25),CREAM,false)
			finishMaterial(sign,Enum.Material.Wood,"Level5VeneerWood")
			-- The fixed plaque sits above the 14-stud clear opening.
			local _, label = surface(sign,definition.title.."\nSECTION "..index.." → "..(index+1))
			gate.label = label
			do
				local prompt=Instance.new("ProximityPrompt");prompt.Name="ColourLockPrompt"
				prompt.ActionText=index==1 and "Set four colours" or "Solve household puzzle";prompt.ObjectText=definition.title
				prompt.HoldDuration=0;prompt.MaxActivationDistance=12;prompt.RequiresLineOfSight=false
				prompt.KeyboardKeyCode=Enum.KeyCode.E;prompt.GamepadKeyCode=Enum.KeyCode.ButtonX
				prompt.Parent=gate.lock;table.insert(gate.prompts,prompt)
				connect(prompt.Triggered,function(player)
					if gate.open or not previousOpen(index) or not canUse(player,gate) then return end
					local last=s.clients[player]
					if last and os.clock()-last.opened<.5 then return end
					local entry={nonce=HttpService:GenerateGUID(false),gate=index,opened=os.clock(),lastSubmit=nil}
					s.clients[player]=entry
					state:FireClient(player,"open",{worldToken=token,nonce=entry.nonce,gate=index,lock=gate.lock,puzzle=Catalog.Public(index)})
				end)
			end
			if config.AllowDeveloperBypass ~= false then
				local prompt = Instance.new("ProximityPrompt"); prompt.Name = "DeveloperBypass"
				prompt:SetAttribute("DeveloperOnly",true); prompt.ActionText = "DEV: bypass this gate"
				prompt.ObjectText = "Skip puzzle • section "..(index+1); prompt.HoldDuration = 1.5
				prompt.MaxActivationDistance = 12; prompt.RequiresLineOfSight = false
				prompt.KeyboardKeyCode = Enum.KeyCode.F; prompt.GamepadKeyCode = Enum.KeyCode.ButtonY
				prompt.UIOffset = Vector2.new(0,84); prompt.Exclusivity = Enum.ProximityPromptExclusivity.AlwaysShow
				prompt.Parent = gate.lock; table.insert(gate.prompts,prompt)
				connect(prompt.Triggered,function(player)
					if DevAccess.IsAllowed(player) and canUse(player,gate) then unlock(index,"DEVELOPER_BYPASS") end
				end)
			end
		end
		local laterClueCount=0
		for gateIndex=2,7 do
			local definition=Catalog.Get(gateIndex);local zone=manifest.Zones[gateIndex]
			local candidates={}
			for _,home in ipairs(zone.Model:GetDescendants()) do
				if home:IsA("Model") and home:GetAttribute("Enterable")==true and home:GetAttribute("HousePuzzleCandidate")==true then
					local marker=home:FindFirstChild("PuzzleHintSurface",true)
					local floor=home:GetAttribute("HouseFloorFrame")
					if marker and marker:IsA("BasePart") and typeof(floor)=="CFrame" then table.insert(candidates,{home=home,marker=marker,floor=floor}) end
				end
			end
			table.sort(candidates,function(a,b)
				if a.floor.Position.Z~=b.floor.Position.Z then return a.floor.Position.Z<b.floor.Position.Z end
				if a.floor.Position.X~=b.floor.Position.X then return a.floor.Position.X<b.floor.Position.X end
				return a.home:GetFullName()<b.home:GetFullName()
			end)
			local wanted=gateIndex==3 and 3 or 1
			assert(#candidates>=wanted,"Section "..gateIndex.." needs "..wanted.." reachable marked clue homes")
			for clueSlot=1,wanted do
				local selected=wanted==1 and math.ceil(#candidates/2) or math.floor((clueSlot-1)*(#candidates-1)/(wanted-1))+1
				local candidate=candidates[selected]
				local model=Instance.new("Model");model.Name="SectionPuzzleClue_"..gateIndex.."_"..clueSlot
				model:SetAttribute("PuzzleGateIndex",gateIndex);model:SetAttribute("PuzzleClueSlot",clueSlot);model:SetAttribute("PuzzleMode",definition.mode)
				model:SetAttribute("Level5ProgressionOwned",true);model.Parent=owner
				local reference=Instance.new("ObjectValue");reference.Name="SourceHome";reference.Value=candidate.home;reference.Parent=model
				-- A consistent small paper mark identifies the few relevant homes without a HUD arrow.
				local frontZ=-.43
				for _,edge in ipairs(candidate.home:GetDescendants()) do
					if edge:IsA("BasePart") and edge.Name=="DoorJamb" then
						local relative=candidate.floor:ToObjectSpace(edge.CFrame)
						if relative.Position.Z<.5 then
							local halfDepth=(math.abs(relative.XVector.Z)*edge.Size.X+math.abs(relative.YVector.Z)*edge.Size.Y+math.abs(relative.ZVector.Z)*edge.Size.Z)/2
							frontZ=math.min(frontZ,relative.Position.Z-halfDepth-.04)
						end
					end
				end
				local tag=part(model,"HouseCluePaper",V(1,2.5,.025),candidate.floor*CF(3.35,6.2,frontZ),Color3.fromRGB(226,216,182),false)
				tag:SetAttribute("PuzzleGateIndex",gateIndex)
				local hintText="HOUSE\nCLUE"..(gateIndex==3 and "\n"..definition.labels[clueSlot] or "")
				local paperGui,paperLabel=surface(tag,hintText,Vector2.new(240,540));paperGui.Name="HouseClueMark"
				paperLabel.TextColor3=Color3.fromRGB(106,42,32);paperLabel.BackgroundTransparency=1
				local board=part(model,"HintSurface",V(6,4.8,.13),candidate.marker.CFrame*CF(0,0,-.10),CREAM,false)
				board:SetAttribute("PuzzleGateIndex",gateIndex)
				local gui,oldLabel=surface(board,"",Vector2.new(900,720));oldLabel:Destroy();gui.Name="PuzzleClueGui"
				local root=Instance.new("Frame");root.Size=UDim2.fromScale(1,1);root.BackgroundColor3=Color3.fromRGB(224,216,190);root.BorderSizePixel=0;root.Parent=gui
				diagramText(root,definition.title,.035,.025,.93,.14)
				local slots=wanted==3 and {clueSlot} or {1,2,3}
				for visibleSlot,answerSlot in ipairs(slots) do
					local count=#slots;local cell=Instance.new("Frame");cell.BackgroundTransparency=1
					cell.Position=UDim2.fromScale(.03+(visibleSlot-1)*(.94/count),.2);cell.Size=UDim2.fromScale(.94/count-.025,.73);cell.Parent=root
					diagramText(cell,definition.labels[answerSlot],0,0,1,.15)
					local art=Instance.new("Frame");art.BackgroundTransparency=1;art.Position=UDim2.fromScale(.03,.17);art.Size=UDim2.fromScale(.94,.62);art.AnchorPoint=Vector2.new(.5,0);art.Position=UDim2.fromScale(.5,.17);art.Parent=cell
					local aspect=Instance.new("UIAspectRatioConstraint");aspect.AspectRatio=1;aspect.AspectType=Enum.AspectType.FitWithinMaxSize;aspect.Parent=art
					local choice=definition.solution[answerSlot]
					paintDiagram(art,definition.mode,choice,definition.options[choice].label)
					diagramText(cell,definition.options[choice].label,0,.81,1,.16)
					if definition.mode=="address" then
						local colour=({COLOURS[1],COLOURS[3],COLOURS[2]})[answerSlot]
						diagramRect(root,.015,.175,.97,.035,colour);board.Color=colour
					end
				end
				laterClueCount+=1
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
			if action=="close" then s.clients[player]=nil;return end
			if action~="submit" then return end
			local now=os.clock();local since=entry.lastSubmit and now-entry.lastSubmit or 1e9
			if since<.65 then return end
			entry.lastSubmit=now
			local gate=s.gates[entry.gate]
			if not gate then s.clients[player]=nil;return end
			local valid,reason=Catalog.ValidateSubmission({gate=entry.gate,expectedGate=gate.index,nonce=nonce,expectedNonce=entry.nonce,
				elapsedSinceOpen=now-entry.opened,elapsedSinceSubmit=since,previousFullyOpen=previousOpen(entry.gate),canUse=canUse(player,gate)},sequence)
			if gate.open then
				s.clients[player]=nil;state:FireClient(player,"unlocked",{worldToken=token,gate=entry.gate});return
			end
			if valid then unlock(entry.gate,"SOLVED")
			elseif reason=="WRONG_ANSWER" or reason=="MALFORMED_ANSWER" then
				state:FireClient(player,"result",{worldToken=token,gate=entry.gate,nonce=entry.nonce,correct=false,text=gate.definition.incorrectText})
			else
				s.clients[player]=nil;state:FireClient(player,"close",{worldToken=token,gate=entry.gate,nonce=entry.nonce})
			end
		end)
		connect(Players.PlayerRemoving,function(player) s.clients[player]=nil end)
		connect(world.Destroying,function() Progression.Cleanup(world) end)
		connect(world.AncestryChanged,function() if world.Parent~=workspace then Progression.Cleanup(world) end end)
		connect(owner.Destroying,function() if not s.closed then Progression.Cleanup(world) end end)
		connect(remoteFolder.Destroying,function() if not s.closed then Progression.Cleanup(world) end end)
		remoteFolder.Parent=RS
		return {ok=true,folder=owner,version=VERSION,gateCount=7,clueCount=4+laterClueCount,puzzleCount=7}
	end)
	if not ok then Progression.Cleanup(world); return {ok=false,error=tostring(result)} end
	return result
end
return Progression
