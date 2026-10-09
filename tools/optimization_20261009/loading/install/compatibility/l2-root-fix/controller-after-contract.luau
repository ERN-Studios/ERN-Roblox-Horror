local run=(function()
return function()
local checks = 0
local function check(condition,message) assert(condition,message);checks+=1 end
local function signal()
 local records={}
 return {
  Connect=function(_,callback)
   local c={Connected=true,Callback=callback}
   function c:Disconnect() self.Connected=false end
   table.insert(records,c);return c
  end,
  Fire=function(_,...) for _,c in ipairs(table.clone(records)) do if c.Connected then c.Callback(...) end end end,
  Count=function() local count=0;for _,c in ipairs(records) do if c.Connected then count+=1 end end;return count end,
 }
end
local workspace={Children={},Attributes={},ChildAdded=signal(),ChildRemoved=signal(),CurrentCamera={CFrame={Position="camera"}}}
function workspace:GetChildren() return table.clone(self.Children) end
function workspace:GetAttribute(key) return self.Attributes[key] end
local function model(name,parent)
 local m={Name=name,Parent=parent}
 function m:IsA(class) return class=="Model" end
 return m
end
local function arrive(m)
 m.Parent=workspace;table.insert(workspace.Children,m);workspace.ChildAdded:Fire(m)
end
local function depart(m)
 local index=table.find(workspace.Children,m);if index then table.remove(workspace.Children,index) end
 m.Parent=nil;workspace.ChildRemoved:Fire(m)
end
local initial=model("Level 2 Generated World",workspace)
table.insert(workspace.Children,initial)
local oldTemplate=model("Level2PoolroomsMap",workspace)
table.insert(workspace.Children,oldTemplate)
local created={}
local Budget={new=function(root,options)
 local session={Root=root,Options=options,Destroyed=0,Steps=0}
 function session:Destroy() self.Destroyed+=1 end
 function session:Step(views) self.Steps+=1;self.LastViews=views end
 table.insert(created,session);return session
end}
local module={}
local ReplicatedStorage={WaitForChild=function(_,name,timeout) assert(name=="SceneEffectBudget" and timeout==30);return module end}
local require=function(value) assert(value==module);return Budget end
local Character={FindFirstChild=function(_,name) assert(name=="HumanoidRootPart");return {Position="body"} end}
local Players={LocalPlayer={Character=Character}}
local RunService={Heartbeat=signal()}
local services={Players=Players,ReplicatedStorage=ReplicatedStorage,RunService=RunService}
local game={GetService=function(_,name) return assert(services[name]) end}
local script={Enabled=true,Destroying=signal(),EnabledChanged=signal()}
function script:GetPropertyChangedSignal(name) assert(name=="Enabled");return self.EnabledChanged end
local debug={traceback=debug.traceback,profilebegin=function() end,profileend=function() end}
local warnings={}
local function warn(message) table.insert(warnings,message) end
(function()
-- Client room/sector budget for explicitly marked decorative effects.
-- Server gameplay state remains in SceneBudgetWantedEnabled; only local Enabled is budgeted.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local module = ReplicatedStorage:WaitForChild("SceneEffectBudget", 30)
if not module then warn("[SceneEffectBudget] Module unavailable"); return end
local Budget = require(module)
local player = Players.LocalPlayer
local CONFIG = {
	["Level 4 Cinema Blender"] = {ActiveDistance = 320, Hysteresis = 48, ScanRoots = {"Lights", "Props"}},
	["Level 5 Void"] = {ActiveDistance = 384, Hysteresis = 64, ScanRoots = {"Lights"}},
	["Level 2 Generated World"] = {ActiveDistance = 320, Hysteresis = 48, ScanRoots = {"Water FX"}},
}
-- The Level 6 arena's galleries share long sight lines; all stay visible.
-- Its union LOD is configured at authoring time, independently of this budget.
local sessions = {}
local connections = {}
local stopped = false
local suspended = workspace:GetAttribute("SceneEffectBudgetDisabled") == true
local elapsed = 0

local function release(model)
	local session = sessions[model]
	if session then
		sessions[model] = nil
		session:Destroy()
	end
end

local function bind(model)
	local config = CONFIG[model.Name]
	if stopped or suspended or not config or not model:IsA("Model") or model.Parent ~= workspace or sessions[model] then return end
	local options = {ActiveDistance = config.ActiveDistance, Hysteresis = config.Hysteresis,
		CellSize = 128, MaxInfluence = 120, PendingLimit = 128, ScanRoots = config.ScanRoots}
	sessions[model] = Budget.new(model, options)
end

local function stop()
	if stopped then return end
	stopped = true
	for _, connection in ipairs(connections) do connection:Disconnect() end
	local models = {}
	for model in pairs(sessions) do table.insert(models, model) end
	for _, model in ipairs(models) do release(model) end
	table.clear(connections)
end

table.insert(connections, workspace.ChildAdded:Connect(bind))
table.insert(connections, workspace.ChildRemoved:Connect(release))
table.insert(connections, script.Destroying:Connect(stop))
table.insert(connections, script:GetPropertyChangedSignal("Enabled"):Connect(function()
	if not script.Enabled then stop() end
end))
for _, model in ipairs(workspace:GetChildren()) do bind(model) end

table.insert(connections, RunService.Heartbeat:Connect(function(dt)
	elapsed += dt
	if elapsed < 0.25 then return end
	elapsed = 0
	local disable = workspace:GetAttribute("SceneEffectBudgetDisabled") == true
	if disable ~= suspended then
		suspended = disable
		if disable then
			local models = {}
			for model in pairs(sessions) do table.insert(models, model) end
			for _, model in ipairs(models) do release(model) end
		else
			for _, model in ipairs(workspace:GetChildren()) do bind(model) end
		end
	end
	if suspended then return end
	local views = {}
	local camera = workspace.CurrentCamera
	if camera then table.insert(views, camera.CFrame.Position) end
	local body = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if body then table.insert(views, body.Position) end
	local ok, problem = xpcall(function()
		debug.profilebegin("SceneEffectBudget")
		for _, session in pairs(sessions) do session:Step(views) end
		debug.profileend()
	end, debug.traceback)
	if not ok then
		debug.profileend()
		stop()
		warn("[SceneEffectBudget] Released local suppression: " .. tostring(problem))
	end
end))

end)()
check(#created==1 and created[1].Root==initial,"generated runtime world bound")
check(created[1].Options.ScanRoots[1]=="Water FX" and #created[1].Options.ScanRoots==1,"actual Water FX subtree selected")
check(created[1].Options.ActiveDistance==320 and created[1].Options.Hysteresis==48 and created[1].Options.CellSize==128,"L2 authored budget retained")
workspace.ChildAdded:Fire(initial)
check(#created==1,"duplicate discovery stays bounded")
local foreign=model("Level 2 Generated World",{})
workspace.ChildAdded:Fire(foreign)
check(#created==1,"non-Workspace world rejected")
local l6=model("Level 6 Indoor Playground",workspace)
workspace.ChildAdded:Fire(l6)
check(#created==1,"existing L6 exemption retained")
RunService.Heartbeat:Fire(0.24)
check(created[1].Steps==0,"existing cadence retained")
RunService.Heartbeat:Fire(0.01)
check(created[1].Steps==1 and #created[1].LastViews==2 and created[1].LastViews[1]=="camera" and created[1].LastViews[2]=="body","camera and body views retained")
local l4=model("Level 4 Cinema Blender")
local l5=model("Level 5 Void")
arrive(l4);arrive(l5)
check(#created==3 and created[2].Options.ScanRoots[1]=="Lights" and created[2].Options.ScanRoots[2]=="Props","L4 configuration retained")
check(created[3].Options.ActiveDistance==384 and created[3].Options.Hysteresis==64 and created[3].Options.ScanRoots[1]=="Lights","L5 configuration retained")
depart(initial)
check(created[1].Destroyed==1,"stream-out root releases session")
RunService.Heartbeat:Fire(0.25)
check(created[1].Steps==1,"removed root no longer stepped")
local returning=model("Level 2 Generated World")
arrive(returning)
check(#created==4 and created[4].Root==returning,"returning runtime root obtains fresh session")
workspace.Attributes.SceneEffectBudgetDisabled=true
RunService.Heartbeat:Fire(0.25)
check(created[2].Destroyed==1 and created[3].Destroyed==1 and created[4].Destroyed==1,"disable restores/releases all sessions")
depart(returning)
local returned=model("Level 2 Generated World")
arrive(returned)
check(#created==4,"disabled root arrival remains suspended")
workspace.Attributes.SceneEffectBudgetDisabled=false
RunService.Heartbeat:Fire(0.25)
check(#created==7 and created[7].Root==returned and created[7].Steps==1,"reenable rediscovers actual generated world")
Players.LocalPlayer.Character=nil;workspace.CurrentCamera=nil
RunService.Heartbeat:Fire(0.25)
check(#created[7].LastViews==0 and #warnings==0,"temporarily missing views stand down without errors")
script.Destroying:Fire()
check(created[5].Destroyed==1 and created[6].Destroyed==1 and created[7].Destroyed==1,"script cleanup releases sessions")
check(workspace.ChildAdded.Count()==0 and workspace.ChildRemoved.Count()==0 and RunService.Heartbeat.Count()==0 and script.Destroying.Count()==0 and script.EnabledChanged.Count()==0,"cleanup disconnects all owners")
arrive(model("Level 2 Generated World"));RunService.Heartbeat:Fire(0.25);script.Destroying:Fire()
check(#created==7 and created[7].Destroyed==1,"post-cleanup events cannot leak another session")
return {checks=checks,realGameplayStreamingPerformancePass=false}
end

end)()
local result=run()
print('L2_ROOT_FIX_CHECKS='..result.checks)
