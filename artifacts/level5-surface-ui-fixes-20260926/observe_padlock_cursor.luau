-- Temporary client QA observer. Does not open UI, change input or move cameras.
-- Install as a separate temporary LocalScript, then operate the actual padlock.
local Players=game:GetService("Players")
local UIS=game:GetService("UserInputService")
local RunService=game:GetService("RunService")
local HttpService=game:GetService("HttpService")
local player=Players.LocalPlayer
local duration=script:GetAttribute("DurationSeconds") or 90
local report={kind="native observed padlock cursor",startedAtUtc=DateTime.now():ToIsoDate(),
	failures={},openFrames=0,mouseOpenFrames=0,openTransitions=0,closeTransitions=0,events={},closedSnapshots={},
	limitations={"Observed real UI only; this script does not create a synthetic open event",
		"Deferred RenderStepped samples observe cursor state, not guaranteed final compositor ordering",
		"Visual reference screenshots and an actual pointer click still need separate evidence",
		"Closing into another modal is allowed to retain the visible free pointer"}}
local alive=true
local connections={}
local failures={}
local function fail(code,detail)
	local key=code..":"..detail
	if not failures[key] then failures[key]=true;table.insert(report.failures,{code=code,detail=detail,time=os.clock()}) end
end
local function gui()
	local pg=player:FindFirstChildOfClass("PlayerGui")
	return pg and pg:FindFirstChild("Level5ColourLockGui")
end
local function state(reason)
	local g=gui()
	return {reason=reason,at=os.clock(),modal=player:GetAttribute("Level5ColourLockOpen")==true,
		guiEnabled=g and g.Enabled or false,mouse=UIS.MouseEnabled,mouseIcon=UIS.MouseIconEnabled,
		mouseBehavior=UIS.MouseBehavior.Name,inRound=player:GetAttribute("InRound")==true,
		cameraMode=player.CameraMode.Name}
end
local previousOpen=player:GetAttribute("Level5ColourLockOpen")==true
local function changed()
	local opened=player:GetAttribute("Level5ColourLockOpen")==true
	if opened==previousOpen then return end
	previousOpen=opened
	if opened then report.openTransitions+=1 else report.closeTransitions+=1 end
	task.defer(function()
		if not alive then return end
		local snapshot=state(opened and "open signal after listeners" or "close signal after listeners")
		table.insert(report.events,snapshot)
		if opened and snapshot.modal and snapshot.mouse then
			if not snapshot.mouseIcon or snapshot.mouseBehavior~="Default" then fail("IMMEDIATE_CURSOR_RELEASE",HttpService:JSONEncode(snapshot)) end
		end
	end)
end
table.insert(connections,player:GetAttributeChangedSignal("Level5ColourLockOpen"):Connect(changed))
local closeFrames=0
local closedMeasured=false
table.insert(connections,RunService.RenderStepped:Connect(function()
	task.defer(function()
		if not alive then return end
		local g=gui();local opened=player:GetAttribute("Level5ColourLockOpen")==true
		if opened then
			closeFrames=0;closedMeasured=false;report.openFrames+=1
			if not g or not g.Enabled then fail("MODAL_GUI_MISMATCH","Flag true without enabled padlock") end
			if UIS.MouseEnabled then
				report.mouseOpenFrames+=1
				if not UIS.MouseIconEnabled then fail("CURSOR_HIDDEN_WHILE_OPEN","MouseIconEnabled false") end
				if UIS.MouseBehavior~=Enum.MouseBehavior.Default then fail("CURSOR_LOCKED_WHILE_OPEN",UIS.MouseBehavior.Name) end
			end
			local blocker=g and g:FindFirstChild("ModalInputBlocker")
			if not blocker or blocker.BackgroundTransparency~=1 or not blocker.Active then fail("BACKDROP_NOT_CLEAR","Expected transparent active input blocker") end
			local panel=blocker and blocker:FindFirstChild("LockPanel")
			local button=panel and panel:FindFirstChild("Close")
			if not panel or not panel.Visible or not button or not button.Visible or not button.Modal then fail("MODAL_BUTTON_MISSING","Real visible Modal close button required") end
		elseif report.openFrames>0 then
			closeFrames+=1
			if g and g.Enabled then fail("CLOSED_GUI_STILL_ENABLED","Modal false with visible padlock") end
			if closeFrames>=4 and not closedMeasured then
				closedMeasured=true;table.insert(report.closedSnapshots,state("four frames after close"))
			end
		end
	end)
end))
task.delay(duration,function()
	alive=false;for _,c in ipairs(connections) do c:Disconnect() end
	report.finishedAtUtc=DateTime.now():ToIsoDate()
	if report.mouseOpenFrames<30 then fail("MISSING_NATIVE_POINTER_EVIDENCE","Observe actual open PC padlock for at least30frames") end
	if report.openTransitions<1 or report.closeTransitions<1 then fail("MISSING_OPEN_CLOSE","Observe an actual open and close") end
	report.pass=#report.failures==0
	script:SetAttribute("Report",HttpService:JSONEncode(report));script:SetAttribute("Finished",true)
end)
