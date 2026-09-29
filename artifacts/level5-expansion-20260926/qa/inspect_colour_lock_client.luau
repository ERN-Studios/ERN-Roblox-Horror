-- QA-only. Reads the real native client UI; never clicks, fires remotes, changes viewport or sets attributes.
local QA = {}
local function round(n) return math.round(n*100)/100 end
local function path(v) return v and v:GetFullName() or nil end
local function rect(v)
	local p,s=v.AbsolutePosition,v.AbsoluteSize
	return {x=round(p.X),y=round(p.Y),width=round(s.X),height=round(s.Y)}
end
local function inside(a,b,epsilon)
	epsilon=epsilon or 1
	return a.x>=b.x-epsilon and a.y>=b.y-epsilon and a.x+a.width<=b.x+b.width+epsilon and a.y+a.height<=b.y+b.height+epsilon
end
local function overlap(a,b)
	return math.min(a.x+a.width,b.x+b.width)-math.max(a.x,b.x)>.5
		and math.min(a.y+a.height,b.y+b.height)-math.max(a.y,b.y)>.5
end
local function context()
	assert(game:GetService("RunService"):IsClient(),"Run this inspector in the real native client")
	local player=assert(game:GetService("Players").LocalPlayer,"LocalPlayer missing")
	local pg=assert(player:FindFirstChildOfClass("PlayerGui"),"PlayerGui missing")
	local gui=assert(pg:FindFirstChild("Level5ColourLockGui"),"Colour-lock client has not created its UI")
	local shade=assert(gui:FindFirstChild("Frame"),"Shade frame missing")
	local panel=assert(shade:FindFirstChild("LockPanel"),"LockPanel missing")
	return player,gui,shade,panel
end
function QA.Inspect()
	local player,gui,shade,panel=context()
	local camera=workspace.CurrentCamera
	local viewport=camera and camera.ViewportSize or Vector2.zero
	local gs=game:GetService("GuiService");local uis=game:GetService("UserInputService")
	local topLeft,bottomRight=gs:GetGuiInset()
	local report={version="2026-09-26.colour-ui.1",status="INCOMPLETE",failures=0,warnings=0,issues={},widgets={},
		viewport={x=viewport.X,y=viewport.Y},inset={topLeft={topLeft.X,topLeft.Y},bottomRight={bottomRight.X,bottomRight.Y}},
		gui={path=path(gui),enabled=gui.Enabled,displayOrder=gui.DisplayOrder,ignoreGuiInset=gui.IgnoreGuiInset},
		panel=rect(panel),shade=rect(shade),touchEnabled=uis.TouchEnabled,gamepadEnabled=uis.GamepadEnabled,
		selectedObject=path(gs.SelectedObject),menuOpen=gs.MenuIsOpen,
		localOpenAttribute=player:GetAttribute("Level5ColourLockOpen"),
		inRound=player:GetAttribute("InRound"),controlsReady=player:GetAttribute("RoundEntryControlsReady"),
		scope="Actual native client widget bounds/text at its current viewport; no simulated button presses or physical-device proof"}
	local function issue(severity,code,object,detail)
		if severity=="FAIL" then report.failures+=1 else report.warnings+=1 end
		table.insert(report.issues,{severity=severity,code=code,path=path(object),detail=detail})
	end
	local names={"Title","Instructions","Feedback","Close","Unlock","Wheel1","Wheel2","Wheel3","Wheel4"}
	local actual={}
	for _,name in ipairs(names) do
		local object=panel:FindFirstChild(name)
		if not object or not object:IsA("GuiObject") then issue("FAIL","MISSING_WIDGET",panel,name)
		else
			actual[name]=object
			local row={name=name,path=path(object),rect=rect(object),visible=object.Visible,active=object.Active}
			if object:IsA("TextLabel") or object:IsA("TextButton") then
				row.text=object.Text;row.textFits=object.TextFits;row.textBounds={round(object.TextBounds.X),round(object.TextBounds.Y)}
				row.textScaled=object.TextScaled;row.textSize=object.TextSize
			end
			if object:IsA("GuiButton") then
				row.selectable=object.Selectable;row.selectionOrder=object.SelectionOrder
				row.selection={left=path(object.NextSelectionLeft),right=path(object.NextSelectionRight),up=path(object.NextSelectionUp),down=path(object.NextSelectionDown)}
			end
			table.insert(report.widgets,row)
			if gui.Enabled then
				if not inside(row.rect,report.panel) then issue("FAIL","WIDGET_OUTSIDE_PANEL",object) end
				if not object.Visible then issue("FAIL","REQUIRED_WIDGET_HIDDEN",object) end
				if row.textFits==false then issue("FAIL","TEXT_DOES_NOT_FIT",object,row.text) end
				if object:IsA("GuiButton") and (row.rect.width<43.5 or row.rect.height<43.5) then
					issue("FAIL","TOUCH_TARGET_UNDER_44PX",object,tostring(row.rect.width).." × "..tostring(row.rect.height))
				end
			end
		end
	end
	if gui.Enabled then
		if not inside(report.panel,report.shade) then issue("FAIL","PANEL_OUTSIDE_USABLE_GUI_AREA",panel) end
		if not inside(report.panel,{x=0,y=0,width=viewport.X,height=viewport.Y}) then issue("FAIL","PANEL_OUTSIDE_VIEWPORT",panel) end
		if player:GetAttribute("Level5ColourLockOpen")~=true then issue("FAIL","OPEN_ATTRIBUTE_MISMATCH",gui) end
		for i,a in ipairs(names) do for j=i+1,#names do
			local b=names[j]
			if actual[a] and actual[b] and overlap(rect(actual[a]),rect(actual[b])) then issue("FAIL","WIDGET_RECT_OVERLAP",actual[a],b) end
		end end
		for index=1,4 do
			local button=actual["Wheel"..index]
			if button then
				local accessible=false
				for choice,pair in ipairs({{"RED","◯"},{"YELLOW","△"},{"BLUE","□"},{"GREEN","◇"}}) do
					if button.Text==tostring(index).."\n"..pair[2].." "..pair[1] then accessible=true end
				end
				if not accessible then issue("FAIL","WHEEL_LABEL_MISSING_INDEX_SYMBOL_OR_WORD",button,button.Text) end
			end
		end
		if gs.MenuIsOpen then issue("WARN","SYSTEM_MENU_OPEN",gui,"Wait for the normal close handler before assessing layout") end
	else
		if player:GetAttribute("Level5ColourLockOpen")==true then issue("FAIL","CLOSED_ATTRIBUTE_MISMATCH",gui) end
	end
	local rf=game:GetService("ReplicatedStorage"):FindFirstChild("Level5Progression")
	report.remoteReady=rf~=nil and type(rf:GetAttribute("WorldToken"))=="string" and #rf:GetAttribute("WorldToken")>0
		and rf:FindFirstChild("State")~=nil and rf:FindFirstChild("Submit")~=nil
	local world=workspace:FindFirstChild("Level 5 Generated World")
	local owner=world and world:FindFirstChild("Level5SectionProgression")
	local gate=owner and owner:FindFirstChild("SectionGate1")
	report.gate1=gate and {unlocked=gate:GetAttribute("Unlocked"),fullyOpen=gate:GetAttribute("FullyOpen"),
		openReason=gate:GetAttribute("OpenReason"),puzzleSolved=owner:GetAttribute("Puzzle1Solved")} or nil
	report.status=report.failures>0 and "FAIL" or (gui.Enabled and "PASS_CURRENT_NATIVE_UI_LAYOUT" or "UI_CLOSED_LAYOUT_NOT_ASSESSED")
	return report
end

function QA.Observe(options)
	options=options or {}
	local player,gui,shade,panel=context()
	local duration=math.clamp(options.Seconds or 120,5,240)
	local maxEvents=math.clamp(options.MaxEvents or 100,10,200)
	local report={version="2026-09-26.colour-ui-observer.1",status="OBSERVING",events={},eventsOmitted=0,
		scope="Observes actual native button Activated/property events; does not trigger interaction or send remotes"}
	local started=os.clock();local finished=false;local connections={};local api={}
	local function event(kind,detail)
		if finished then return end
		if #report.events<maxEvents then table.insert(report.events,{t=round(os.clock()-started),kind=kind,detail=detail}) else report.eventsOmitted+=1 end
	end
	local function connect(signal,callback) table.insert(connections,signal:Connect(callback)) end
	local lastSnapshotKey
	local function snapshot(label)
		local ok,value=pcall(QA.Inspect)
		if ok and label=="sample" then
			local key=tostring(value.gui.enabled)..":"..tostring(value.viewport.x)..":"..tostring(value.viewport.y)..":"..tostring(value.failures)
			for _,widget in ipairs(value.widgets) do key..="|"..widget.name..":"..tostring(widget.text)..":"..tostring(widget.textFits) end
			if key==lastSnapshotKey then return end
			lastSnapshotKey=key
		end
		event(label,ok and value or {inspectionError=tostring(value)})
	end
	local function finish(reason)
		if finished then return end
		snapshot("final_snapshot");finished=true
		for _,c in ipairs(connections) do c:Disconnect() end;table.clear(connections)
		report.status="COMPLETE_OBSERVATION";report.reason=reason;report.seconds=round(os.clock()-started)
		if type(options.OnFinished)=="function" then local ok,err=pcall(options.OnFinished,report);if not ok then report.callbackError=tostring(err) end end
	end
	function api.GetReport() return report end
	function api.Stop() finish("Explicit stop") end
	for _,name in ipairs({"Wheel1","Wheel2","Wheel3","Wheel4","Unlock","Close"}) do
		local b=panel:FindFirstChild(name)
		if b and b:IsA("GuiButton") then
			connect(b.Activated,function() event("button_activated",{name=name,textAtSignal=b.Text}) end)
			if name:match("^Wheel") then connect(b:GetPropertyChangedSignal("Text"),function() event("wheel_text",{name=name,text=b.Text}) end) end
		end
	end
	local feedback=panel:FindFirstChild("Feedback")
	if feedback then connect(feedback:GetPropertyChangedSignal("Text"),function() event("feedback",feedback.Text) end) end
	connect(gui:GetPropertyChangedSignal("Enabled"),function() event("gui_enabled",gui.Enabled) end)
	connect(player:GetAttributeChangedSignal("Level5ColourLockOpen"),function() event("open_attribute",player:GetAttribute("Level5ColourLockOpen")) end)
	connect(gui.Destroying,function() finish("UI destroyed") end)
	local owner=workspace:FindFirstChild("Level 5 Generated World")
	owner=owner and owner:FindFirstChild("Level5SectionProgression")
	local gate=owner and owner:FindFirstChild("SectionGate1")
	if gate then for _,key in ipairs({"Unlocked","FullyOpen","OpenReason"}) do
		connect(gate:GetAttributeChangedSignal(key),function() event("gate1_"..key,gate:GetAttribute(key)) end)
	end end
	local elapsed=0
	connect(game:GetService("RunService").Heartbeat,function(dt)
		elapsed+=dt
		if os.clock()-started>=duration then finish("Bounded observation interval ended")
		elseif elapsed>=1 then elapsed=0;snapshot("sample") end
	end)
	snapshot("initial_snapshot")
	return api
end
return QA
