-- Accessible household puzzle controls. The server alone validates answers and shared gate progress.
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local RunService=game:GetService("RunService")
local UIS=game:GetService("UserInputService")
local GuiService=game:GetService("GuiService")
local PromptService=game:GetService("ProximityPromptService")
local UIDevice=require(RS:WaitForChild("UIDevice"))
local DevAccess=require(RS:WaitForChild("DevAccess"))
local player=Players.LocalPlayer
local playerGui=player:WaitForChild("PlayerGui")
local CHOICES={"RED","YELLOW","BLUE","GREEN"}
local SYMBOLS={"◯","△","□","◇"}
local COLOURS={Color3.fromRGB(160,44,43),Color3.fromRGB(225,189,73),Color3.fromRGB(54,99,165),Color3.fromRGB(52,122,81)}
local DARK=Color3.fromRGB(27,32,29)
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


local connections={}
local folderConnections={}
local remoteFolder,submitRemote,worldToken
local candidateFolder
local candidateConnections={}
local nonce,lock,openedAt,previousSelection,activeGate
local puzzle={mode="colours",count=4,labels={"1","2","3","4"},options={{label="RED",icon="◯"},{label="YELLOW",icon="△"},{label="BLUE",icon="□"},{label="GREEN",icon="◇"}}}
local compactControls=false
local open=false
local wheels={1,1,1,1}
local wheelButtons={}
local lastSubmit=-math.huge
local stopped=false
local function connect(signal,callback) local c=signal:Connect(callback);table.insert(connections,c);return c end

local gui=Instance.new("ScreenGui");gui.Name="Level5ColourLockGui";gui.ResetOnSpawn=false
assert(not playerGui:FindFirstChild(gui.Name),"Existing colour-lock UI must not be replaced")
gui:SetAttribute("Level5ProgressionOwned",true);gui.DisplayOrder=70;gui.IgnoreGuiInset=false;gui.Enabled=false;gui.Parent=playerGui
local shade=Instance.new("Frame");shade.Size=UDim2.fromScale(1,1);shade.BackgroundColor3=Color3.new(0,0,0)
shade.BackgroundTransparency=.28;shade.BorderSizePixel=0;shade.Active=true;shade.Parent=gui
local panel=Instance.new("Frame");panel.Name="LockPanel";panel.AnchorPoint=Vector2.new(.5,.5)
panel.Position=UDim2.fromScale(.5,.5);panel.Size=UDim2.fromOffset(600,330)
panel.BackgroundColor3=Color3.fromRGB(30,35,31);panel.BorderSizePixel=0;panel.Parent=shade
local corner=Instance.new("UICorner");corner.CornerRadius=UDim.new(0,12);corner.Parent=panel
local stroke=Instance.new("UIStroke");stroke.Color=Color3.fromRGB(155,149,126);stroke.Thickness=2;stroke.Parent=panel
local function text(name,parent,value)
	local t=Instance.new("TextLabel");t.Name=name;t.BackgroundTransparency=1;t.Text=value
	t.Font=Enum.Font.GothamMedium;t.TextSize=16;t.TextColor3=Color3.fromRGB(232,226,204)
	t.TextWrapped=true;t.TextXAlignment=Enum.TextXAlignment.Left;t.Parent=parent;return t
end
local title=text("Title",panel,"HOUSE COLOUR LOCK");title.Font=Enum.Font.GothamBold;title.TextSize=21
local help=text("Instructions",panel,"Find the four numbered house clues. Set wheels 1–4 to match.")
for _, label in ipairs({title, help}) do
	label.TextScaled=true;local limit=Instance.new("UITextSizeConstraint");limit.MinTextSize=12;limit.MaxTextSize=label==title and 21 or 16;limit.Parent=label
end
local feedback=text("Feedback",panel,"Tap a wheel to change its colour.");feedback.TextScaled=true
local feedbackLimit=Instance.new("UITextSizeConstraint");feedbackLimit.MinTextSize=11;feedbackLimit.MaxTextSize=14;feedbackLimit.Parent=feedback
local function button(name,label)
	local b=Instance.new("TextButton");b.Name=name;b.Text=label;b.AutoButtonColor=true
	b.Font=Enum.Font.GothamBold;b.TextSize=18;b.Selectable=true;b.BackgroundColor3=Color3.fromRGB(218,207,171)
	b.TextColor3=DARK;b.BorderSizePixel=0;b.Parent=panel
	local c=Instance.new("UICorner");c.CornerRadius=UDim.new(0,7);c.Parent=b
	return b
end
local closeButton=button("Close","×");closeButton.TextSize=28;closeButton.Modal=true
local submitButton=button("Unlock","UNLOCK");submitButton.SelectionOrder=5
local function idleFeedback()
	return ({colours="Tap a wheel to change its colour.",symbols="Tap a symbol to change it.",address="Tap a digit to change the house number.",
		switches="Tap a switch to flip it.",clocks="Tap a clock to set its hour.",television="Tap a TV to change its channel.",arrows="Tap a house to rotate it."})[puzzle.mode]
end
local function drawWheels()
	for index,b in ipairs(wheelButtons) do
		b.Visible=index<=puzzle.count;b.Selectable=b.Visible
		local old=b:FindFirstChild("PuzzleVisual");if old then old:Destroy() end
		if b.Visible then
			local choice=wheels[index];local option=puzzle.options[choice]
			if puzzle.mode=="colours" then
				b.Text=index.."\n"..(option.icon or "").." "..option.label
				b.BackgroundColor3=COLOURS[choice];b.TextColor3=choice==2 and DARK or Color3.new(1,1,1)
			elseif compactControls then
				b.Text=puzzle.labels[index].."\n"..(option.icon or "").." "..option.label
				b.BackgroundColor3=Color3.fromRGB(224,216,190);b.TextColor3=DARK
			else
				b.Text="";b.BackgroundColor3=Color3.fromRGB(224,216,190)
				local visual=Instance.new("Frame");visual.Name="PuzzleVisual";visual.BackgroundTransparency=1;visual.Size=UDim2.fromScale(1,1);visual.Parent=b
				diagramText(visual,puzzle.labels[index],.02,.02,.96,.15)
				local art=Instance.new("Frame");art.BackgroundTransparency=1;art.Position=UDim2.fromScale(.1,.2);art.Size=UDim2.fromScale(.8,.55);art.AnchorPoint=Vector2.new(.5,0);art.Position=UDim2.fromScale(.5,.2);art.Parent=visual
				local aspect=Instance.new("UIAspectRatioConstraint");aspect.AspectRatio=1;aspect.AspectType=Enum.AspectType.FitWithinMaxSize;aspect.Parent=art
				paintDiagram(art,puzzle.mode,choice,option.label)
				diagramText(visual,option.label,.02,.78,.96,.19)
			end
			b:SetAttribute("ChoiceIndex",choice);b:SetAttribute("ChoiceLabel",option.label)
			b.NextSelectionLeft=wheelButtons[(index+puzzle.count-2)%puzzle.count+1]
			b.NextSelectionRight=wheelButtons[index%puzzle.count+1]
			b.NextSelectionDown=submitButton;b.NextSelectionUp=closeButton
		end
	end
	submitButton.NextSelectionUp=wheelButtons[1];closeButton.NextSelectionDown=wheelButtons[1]
end
for index=1,4 do
	local b=button("Wheel"..index,"");b.SelectionOrder=index;b.TextScaled=true
	local limit=Instance.new("UITextSizeConstraint");limit.MinTextSize=11;limit.MaxTextSize=21;limit.Parent=b
	wheelButtons[index]=b
	connect(b.Activated,function()
		if not open or index>puzzle.count then return end
		wheels[index]=wheels[index]%#puzzle.options+1;drawWheels()
		feedback.Text=idleFeedback();feedback.TextColor3=Color3.fromRGB(232,226,204)
	end)
end
local function layout()
	local camera=workspace.CurrentCamera;local viewport=camera and camera.ViewportSize or Vector2.new(800,600)
	local width=math.clamp(viewport.X-32,248,600);local height=math.clamp(viewport.Y-64,248,330)
	panel.Size=UDim2.fromOffset(width,height)
	title.Position=UDim2.fromOffset(16,12);title.Size=UDim2.fromOffset(width-84,30)
	closeButton.Position=UDim2.fromOffset(width-52,8);closeButton.Size=UDim2.fromOffset(44,44)
	help.Position=UDim2.fromOffset(16,56);help.Size=UDim2.fromOffset(width-32,28)
	local gap=8;local cell=(width-32-gap*(puzzle.count-1))/puzzle.count;local wheelHeight=math.clamp(height-204,44,104)
	local wasCompact=compactControls;compactControls=wheelHeight<80
	if wasCompact~=compactControls then drawWheels() end
	for index,b in ipairs(wheelButtons) do b.Position=UDim2.fromOffset(16+(index-1)*(cell+gap),89);b.Size=UDim2.fromOffset(cell,wheelHeight) end
	feedback.Position=UDim2.fromOffset(16,95+wheelHeight);feedback.Size=UDim2.fromOffset(width-32,36)
	submitButton.Position=UDim2.fromOffset(16,height-60);submitButton.Size=UDim2.fromOffset(width-32,44)
end
local function close(notifyServer)
	if not open then return end
	local oldNonce=nonce
	open=false;nonce=nil;lock=nil;activeGate=nil;gui.Enabled=false;player:SetAttribute("Level5ColourLockOpen",false)
	gui:SetAttribute("PuzzleGate",nil)
	local selected=GuiService.SelectedObject
	if selected and selected:IsDescendantOf(gui) then
		GuiService.SelectedObject=previousSelection and previousSelection.Parent and previousSelection or nil
	end
	previousSelection=nil
	if notifyServer and submitRemote and submitRemote.Parent and oldNonce then submitRemote:FireServer("close",oldNonce) end
end
local OTHER_MODAL_ATTRIBUTES={"ZyntraStoreOpen","DevPhoneOpen","ZyntraReentryOpen","QueueModalOpen","LuckyWheelOpen","DailyRewardsOpen","DispatchBriefingOpen","ZyntraDispatchClientActive"}
local function allowed()
	local camera=workspace.CurrentCamera;local char=player.Character;local hum=char and char:FindFirstChildOfClass("Humanoid")
	if workspace:GetAttribute("SelectedLevel")~=5 or workspace:GetAttribute("RoundActive")~=true
		or player:GetAttribute("InRound")~=true or player:GetAttribute("Escaped")==true or player:GetAttribute("Spectating")==true
		or not hum or hum.Health<=0 or not camera or camera.CameraType~=Enum.CameraType.Custom or GuiService.MenuIsOpen then return false end
	for _,attribute in ipairs(OTHER_MODAL_ATTRIBUTES) do if player:GetAttribute(attribute)==true then return false end end
	return true
end
connect(closeButton.Activated,function() close(true) end)
connect(submitButton.Activated,function()
	if not open or not submitRemote or not nonce or os.clock()-lastSubmit<.7 then return end
	lastSubmit=os.clock();feedback.Text="Checking the lock…";feedback.TextColor3=Color3.fromRGB(232,226,204)
	submitRemote:FireServer("submit",nonce,table.clone(wheels))
end)
connect(UIS.InputBegan,function(input,processed)
	if not open then return end
	if input.KeyCode==Enum.KeyCode.Escape or input.KeyCode==Enum.KeyCode.ButtonB then close(true) end
end)
connect(PromptService.PromptShown,function(prompt)
	local gate=prompt.Parent and prompt.Parent.Parent;local owner=gate and gate.Parent
	if prompt:GetAttribute("DeveloperOnly")==true and owner and owner.Name=="Level5SectionProgression"
		and owner:GetAttribute("Level5ProgressionOwned")==true and not DevAccess.IsAllowed(player) then prompt.Enabled=false end
end)
local function unbind()
	close(false)
	for _,c in ipairs(folderConnections) do c:Disconnect() end
	table.clear(folderConnections);remoteFolder=nil;submitRemote=nil;worldToken=nil
end
local function validPublic(data)
	if type(data)~="table" or (data.count~=3 and data.count~=4) or type(data.title)~="string" or #data.title>64
		or type(data.instructions)~="string" or #data.instructions>100 or type(data.options)~="table" or #data.options<2 or #data.options>10
		or type(data.labels)~="table" or #data.labels~=data.count or type(data.startingIndices)~="table" or #data.startingIndices~=data.count then return false end
	if not ({colours=true,symbols=true,address=true,switches=true,clocks=true,television=true,arrows=true})[data.mode] then return false end
	for _,option in ipairs(data.options) do if type(option)~="table" or type(option.label)~="string" or #option.label>12
		or (option.icon~=nil and (type(option.icon)~="string" or #option.icon>12)) then return false end end
	for index=1,data.count do
		local choice=data.startingIndices[index]
		if type(data.labels[index])~="string" or #data.labels[index]>12 or type(choice)~="number" or choice%1~=0 or choice<1 or choice>#data.options then return false end
	end
	return true
end
local function bind(folder)
	if stopped or folder.Name~="Level5Progression" or not folder:IsA("Folder") or folder:GetAttribute("Level5ProgressionOwned")~=true then return end
	local nextToken=folder:GetAttribute("WorldToken")
	if type(nextToken)~="string" or #nextToken==0 then return end
	if remoteFolder==folder and worldToken==nextToken then return end
	local state=folder:FindFirstChild("State");local submit=folder:FindFirstChild("Submit")
	if not state or not state:IsA("RemoteEvent") or not submit or not submit:IsA("RemoteEvent") then return end
	unbind();remoteFolder=folder;submitRemote=submit;worldToken=nextToken
	table.insert(folderConnections,state.OnClientEvent:Connect(function(action,data)
		if type(data)~="table" or data.worldToken~=worldToken then return end
		if action=="open" then
			if not allowed() or type(data.nonce)~="string" or typeof(data.lock)~="Instance" or not data.lock:IsA("BasePart")
				or type(data.gate)~="number" or data.gate%1~=0 or data.gate<1 or data.gate>7 or not validPublic(data.puzzle) then return end
			close(false);nonce=data.nonce;lock=data.lock;activeGate=data.gate;puzzle=data.puzzle
			openedAt=os.clock();lastSubmit=-math.huge;wheels=table.clone(puzzle.startingIndices)
			title.Text=string.upper(puzzle.title);help.Text=puzzle.instructions
			gui:SetAttribute("PuzzleGate",activeGate);gui:SetAttribute("PuzzleMode",puzzle.mode);gui:SetAttribute("PuzzleControlCount",puzzle.count)
			previousSelection=GuiService.SelectedObject;open=true;gui.Enabled=true;player:SetAttribute("Level5ColourLockOpen",true)
			feedback.Text=idleFeedback();feedback.TextColor3=Color3.fromRGB(232,226,204)
			layout();drawWheels()
			if UIS.GamepadEnabled then GuiService.SelectedObject=wheelButtons[1] end
		elseif action=="result" and open and data.gate==activeGate and data.nonce==nonce then
			feedback.Text=type(data.text)=="string" and data.text or "Check the house clue and try again."
			feedback.TextColor3=Color3.fromRGB(244,176,156)
		elseif action=="close" and open and data.gate==activeGate and data.nonce==nonce then close(false)
		elseif action=="unlocked" and open and data.gate==activeGate then close(false) end
	end))
	table.insert(folderConnections,folder.AncestryChanged:Connect(function() if folder.Parent~=RS then unbind() end end))
end
local function clearCandidate()
	for _,c in ipairs(candidateConnections) do c:Disconnect() end
	table.clear(candidateConnections);candidateFolder=nil
end
local function watch(folder)
	if stopped or folder.Name~="Level5Progression" or not folder:IsA("Folder") or folder.Parent~=RS then return end
	if candidateFolder~=folder then
		clearCandidate();candidateFolder=folder
		for _,attribute in ipairs({"WorldToken","Level5ProgressionOwned"}) do
			table.insert(candidateConnections,folder:GetAttributeChangedSignal(attribute):Connect(function() bind(folder) end))
		end
		table.insert(candidateConnections,folder.AncestryChanged:Connect(function()
			if folder.Parent~=RS and candidateFolder==folder then
				if remoteFolder==folder then unbind() end
				clearCandidate()
			end
		end))
	end
	bind(folder)
end
connect(RS.ChildAdded,watch)
local initial=RS:FindFirstChild("Level5Progression");if initial then watch(initial) end
-- Covers replication that delivers the folder before its two RemoteEvent children.
connect(RS.DescendantAdded,function(object)
	local parent=object.Parent
	if parent and parent.Name=="Level5Progression" and parent.Parent==RS then watch(parent) end
end)
local elapsed=0
connect(RunService.Heartbeat,function(dt)
	if not open then return end
	elapsed+=dt;if elapsed<.1 then return end;elapsed=0
	local char=player.Character;local root=char and char:FindFirstChild("HumanoidRootPart")
	if not allowed() or not lock or not lock:IsDescendantOf(workspace) or not root or (root.Position-lock.Position).Magnitude>14
		or os.clock()-openedAt>120 then close(true);return end
	layout()
end)
connect(script.Destroying,function()
	if stopped then return end;stopped=true;unbind();clearCandidate()
	for _,c in ipairs(connections) do c:Disconnect() end
	gui:Destroy();player:SetAttribute("Level5ColourLockOpen",false)
end)
drawWheels();layout()
