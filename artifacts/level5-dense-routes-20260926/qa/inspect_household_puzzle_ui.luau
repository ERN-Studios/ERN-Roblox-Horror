-- Read-only CLIENT inspection after opening a real gate prompt. Run once per gate
-- and once per actual Studio device-emulation orientation. Does not open/submit a
-- puzzle, alter the camera viewport, resize UI, or claim an unobserved device test.
local Players=game:GetService("Players")
local HttpService=game:GetService("HttpService")
local GuiService=game:GetService("GuiService")
local player=Players.LocalPlayer
assert(player,"Run this inspector in the native client context")
local report={status="NOT_OPEN",failures={},warnings={},buttons={},text={},scope="Read-only snapshot of the currently open real puzzle UI"}
local function issue(list,message) if #list<30 then table.insert(list,message) end end
local function rect(object)
	local p,s=object.AbsolutePosition,object.AbsoluteSize
	return {x=p.X,y=p.Y,w=s.X,h=s.Y}
end
local function contains(a,b)
	return b.x>=a.x-1 and b.y>=a.y-1 and b.x+b.w<=a.x+a.w+1 and b.y+b.h<=a.y+a.h+1
end
local function overlap(a,b)
	return math.min(a.x+a.w,b.x+b.w)-math.max(a.x,b.x)>1
		and math.min(a.y+a.h,b.y+b.h)-math.max(a.y,b.y)>1
end
local function shown(object,root)
	local current=object
	while current and current~=root do
		if current:IsA("GuiObject") and not current.Visible then return false end
		current=current.Parent
	end
	return current==root
end
local gui=player:FindFirstChild("PlayerGui") and player.PlayerGui:FindFirstChild("Level5ColourLockGui")
if not gui or not gui.Enabled then return HttpService:JSONEncode(report) end
local shade=gui:FindFirstChild("Frame")
local panel=shade and shade:FindFirstChild("LockPanel")
if not panel then report.status="FAIL";issue(report.failures,"Missing Frame.LockPanel");return HttpService:JSONEncode(report) end
local modes={"colours","symbols","address","switches","clocks","television","arrows"}
local gate=gui:GetAttribute("PuzzleGate")
local mode=gui:GetAttribute("PuzzleMode")
local count=gui:GetAttribute("PuzzleControlCount")
report.gate=gate;report.mode=mode;report.controlCount=count
local camera=workspace.CurrentCamera
report.viewport=camera and {x=camera.ViewportSize.X,y=camera.ViewportSize.Y} or nil
local topLeft,bottomRight=GuiService:GetGuiInset()
report.guiInset={topLeft={x=topLeft.X,y=topLeft.Y},bottomRight={x=bottomRight.X,y=bottomRight.Y}}
report.safeFrame=rect(shade);report.panel=rect(panel)
if not contains(report.safeFrame,report.panel) then issue(report.failures,"Panel exceeds its actual inset-aware shade bounds") end
if type(gate)~="number" or modes[gate]~=mode or count~=(gate==1 and 4 or 3) then
	issue(report.failures,"Gate/mode/control-count presentation mismatch")
end
local topLevel={}
for _,name in ipairs({"Title","Instructions","Feedback","Close","Unlock","Wheel1","Wheel2","Wheel3","Wheel4"}) do
	local object=panel:FindFirstChild(name)
	if not object or not object:IsA("GuiObject") then
		issue(report.failures,"Missing primary control "..name)
	elseif shown(object,gui) then
		local bounds=rect(object)
		if not contains(report.panel,bounds) then issue(report.failures,name.." exceeds panel") end
		for _,prior in ipairs(topLevel) do
			if overlap(bounds,prior.bounds) then issue(report.failures,name.." overlaps "..prior.name) end
		end
		table.insert(topLevel,{name=name,bounds=bounds})
		if object:IsA("GuiButton") then
			local links={}
			for _,key in ipairs({"NextSelectionLeft","NextSelectionRight","NextSelectionUp","NextSelectionDown"}) do
				local target=object[key]
				links[key]=target and target.Name or nil
				if target and (not target.Selectable or not shown(target,gui)) then issue(report.failures,name.." selects hidden/disabled "..target.Name) end
			end
			table.insert(report.buttons,{name=name,bounds=bounds,selectable=object.Selectable,choiceIndex=object:GetAttribute("ChoiceIndex"),choiceLabel=object:GetAttribute("ChoiceLabel"),links=links})
			if bounds.w<44-.5 or bounds.h<44-.5 then issue(report.failures,name.." has a touch target smaller than 44px") end
			if not object.Selectable then issue(report.failures,name.." is not gamepad-selectable") end
		end
	end
end
for index=1,4 do
	local button=panel:FindFirstChild("Wheel"..index)
	if button and type(count)=="number" then
		if button.Visible~=(index<=count) then issue(report.failures,"Unexpected Wheel"..index.." visibility") end
		if index<=count and (type(button:GetAttribute("ChoiceIndex"))~="number" or type(button:GetAttribute("ChoiceLabel"))~="string") then
			issue(report.failures,"Wheel"..index.." has no choice presentation metadata")
		end
	end
end
for _,object in ipairs(panel:GetDescendants()) do
	if (object:IsA("TextLabel") or object:IsA("TextButton")) and object.Text~="" and shown(object,gui) then
		local primary=object.Parent==panel
		local entry={name=primary and object.Name or object:GetFullName():sub(-110),text=object.Text,bounds=rect(object),textFits=object.TextFits,textBounds={x=object.TextBounds.X,y=object.TextBounds.Y}}
		if primary then table.insert(report.text,entry) end
		if not object.TextFits then issue(report.failures,"Text does not fit: "..entry.name) end
		-- Tiny clock numerals may be decorative; their hour is also written below.
		if not primary and object.TextBounds.Y>0 and object.TextBounds.Y<9 then issue(report.warnings,"Small diagram lettering: "..entry.name) end
	end
end
local selected=GuiService.SelectedObject
report.selected=selected and selected:GetFullName() or nil
report.playerOpenFlag=player:GetAttribute("Level5ColourLockOpen")
if report.playerOpenFlag~=true then issue(report.failures,"Visible UI missing player open flag") end
report.status=#report.failures==0 and "PASS" or "FAIL"
report.limitations="Snapshot only: no input, font-independent math, device emulation, multiplayer, or successful submission is inferred. Run with each actual gate open."
return HttpService:JSONEncode(report)
