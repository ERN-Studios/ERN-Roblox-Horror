-- Four accessible colour wheels. The server alone checks answers/range and opens gates.
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
local connections={}
local folderConnections={}
local remoteFolder,submitRemote,worldToken
local candidateFolder
local candidateConnections={}
local nonce,lock,openedAt,previousSelection
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
local feedback=text("Feedback",panel,"Tap a wheel to change its colour.");feedback.TextSize=14
local function button(name,label)
	local b=Instance.new("TextButton");b.Name=name;b.Text=label;b.AutoButtonColor=true
	b.Font=Enum.Font.GothamBold;b.TextSize=18;b.Selectable=true;b.BackgroundColor3=Color3.fromRGB(218,207,171)
	b.TextColor3=DARK;b.BorderSizePixel=0;b.Parent=panel
	local c=Instance.new("UICorner");c.CornerRadius=UDim.new(0,7);c.Parent=b
	return b
end
local closeButton=button("Close","×");closeButton.TextSize=28;closeButton.Modal=true
local submitButton=button("Unlock","UNLOCK");submitButton.SelectionOrder=5
local function drawWheels()
	for index,b in ipairs(wheelButtons) do
		local choice=wheels[index];b.Text=index.."\n"..SYMBOLS[choice].." "..CHOICES[choice]
		b.BackgroundColor3=COLOURS[choice];b.TextColor3=choice==2 and DARK or Color3.new(1,1,1)
	end
end
for index=1,4 do
	local b=button("Wheel"..index,"");b.SelectionOrder=index;b.TextScaled=true
	local limit=Instance.new("UITextSizeConstraint");limit.MinTextSize=11;limit.MaxTextSize=21;limit.Parent=b
	wheelButtons[index]=b
	connect(b.Activated,function()
		if not open then return end
		wheels[index]=wheels[index]%4+1;drawWheels()
		feedback.Text="Tap a wheel to change its colour.";feedback.TextColor3=Color3.fromRGB(232,226,204)
	end)
end
for index,b in ipairs(wheelButtons) do
	b.NextSelectionLeft=wheelButtons[(index+2)%4+1];b.NextSelectionRight=wheelButtons[index%4+1]
	b.NextSelectionDown=submitButton;b.NextSelectionUp=closeButton
end
submitButton.NextSelectionUp=wheelButtons[1];closeButton.NextSelectionDown=wheelButtons[1]
local function layout()
	local camera=workspace.CurrentCamera;local viewport=camera and camera.ViewportSize or Vector2.new(800,600)
	local width=math.clamp(viewport.X-32,248,600);local height=math.clamp(viewport.Y-64,248,330)
	panel.Size=UDim2.fromOffset(width,height)
	title.Position=UDim2.fromOffset(16,12);title.Size=UDim2.fromOffset(width-84,30)
	closeButton.Position=UDim2.fromOffset(width-52,8);closeButton.Size=UDim2.fromOffset(44,44)
	help.Position=UDim2.fromOffset(16,56);help.Size=UDim2.fromOffset(width-32,28)
	local gap=8;local cell=(width-32-gap*3)/4;local wheelHeight=math.clamp(height-204,44,104)
	for index,b in ipairs(wheelButtons) do b.Position=UDim2.fromOffset(16+(index-1)*(cell+gap),89);b.Size=UDim2.fromOffset(cell,wheelHeight) end
	feedback.Position=UDim2.fromOffset(16,95+wheelHeight);feedback.Size=UDim2.fromOffset(width-32,36)
	submitButton.Position=UDim2.fromOffset(16,height-60);submitButton.Size=UDim2.fromOffset(width-32,44)
end
local function close(notifyServer)
	if not open then return end
	local oldNonce=nonce
	open=false;nonce=nil;lock=nil;gui.Enabled=false;player:SetAttribute("Level5ColourLockOpen",false)
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
			if not allowed() or type(data.nonce)~="string" or typeof(data.lock)~="Instance" or not data.lock:IsA("BasePart") then return end
			close(false);nonce=data.nonce;lock=data.lock;openedAt=os.clock();lastSubmit=-math.huge;wheels={1,1,1,1}
			previousSelection=GuiService.SelectedObject;open=true;gui.Enabled=true;player:SetAttribute("Level5ColourLockOpen",true)
			feedback.Text="Tap a wheel to change its colour.";feedback.TextColor3=Color3.fromRGB(232,226,204)
			layout();drawWheels()
			if UIS.GamepadEnabled then GuiService.SelectedObject=wheelButtons[1] end
		elseif action=="result" and open then
			feedback.Text=type(data.text)=="string" and data.text or "Check the numbered clues and try again."
			feedback.TextColor3=Color3.fromRGB(244,176,156)
		elseif action=="close" or action=="unlocked" then close(false) end
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
