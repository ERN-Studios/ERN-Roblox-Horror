-- Minimal Roblox presentation mock. The real controller source is concatenated
-- immediately after this prefix by run_controller_mock.py; no controller copy.
local Logic=require("../patches/Level5AudioLogic.ModuleScript")
local OriginalCatalog=require("../patches/Level5AudioCatalog.ModuleScript")
local Outage=require("../baseline/sources/ReplicatedStorage/Level5OutageLogic.ModuleScript")
local Catalog={}
for key,cue in pairs(OriginalCatalog) do Catalog[key]=table.clone(cue);Catalog[key].AssetId=123456 end
local now=100
local os={clock=function() return now end}
local assertions=0
local function eq(actual,expected,label)
	assertions+=1;assert(actual==expected,(label or "equal")..": expected "..tostring(expected)..", got "..tostring(actual))
end
local function signal()
	local listeners={};local object={}
	function object:Connect(callback)
		local c={Connected=true};function c:Disconnect() self.Connected=false end
		table.insert(listeners,{connection=c,callback=callback});return c
	end
	function object:Fire(...)
		for _,entry in ipairs(table.clone(listeners)) do if entry.connection.Connected then entry.callback(...) end end
	end
	return object
end
local vectorMeta={}
local Vector3={}
function Vector3.new(x,y,z) return setmetatable({_type="Vector3",X=x,Y=y,Z=z},vectorMeta) end
vectorMeta.__sub=function(a,b) return Vector3.new(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
vectorMeta.__index=function(v,key) if key=="Magnitude" then return math.sqrt(v.X*v.X+v.Y*v.Y+v.Z*v.Z) end end
local CFrame={new=function(v) return {_type="CFrame",Position=v} end}
local function typeof(value) return type(value)=="table" and value._type or type(value) end
local Enum={RollOffMode={InverseTapered="InverseTapered"},CameraType={Custom="Custom",Scriptable="Scriptable"}}
local allObjects={}
local methods={}
local instanceMeta={}
instanceMeta.__index=function(self,key) return methods[key] or self._props[key] end
instanceMeta.__newindex=function(self,key,value)
	if key=="Parent" then
		local prior=self._props.Parent
		if prior then local index=table.find(prior._children,self);if index then table.remove(prior._children,index) end end
		self._props.Parent=value
		if value then table.insert(value._children,self) end
	else self._props[key]=value end
end
local Instance={}
function Instance.new(class)
	local obj=setmetatable({_type="Instance",_props={ClassName=class,Name=class,Destroying=signal()},_children={},_attributes={},_signals={},_destroyed=false},instanceMeta)
	if class=="Sound" then obj.IsLoaded=true;obj.IsPlaying=false;obj.Volume=0;obj.plays=0 end
	if class=="BindableEvent" then obj.Event=signal() end
	if class=="LocalScript" then obj.Enabled=true end
	table.insert(allObjects,obj);return obj
end
function methods:IsA(class) return self.ClassName==class or (class=="BasePart" and self.ClassName=="Part") end
function methods:GetAttribute(key) return self._attributes[key] end
function methods:SetAttribute(key,value)
	if self._attributes[key]~=value then self._attributes[key]=value;if self._signals[key] then self._signals[key]:Fire() end end
end
function methods:GetAttributeChangedSignal(key) if not self._signals[key] then self._signals[key]=signal() end;return self._signals[key] end
function methods:FindFirstChild(name) for _,child in ipairs(self._children) do if child.Name==name then return child end end end
function methods:FindFirstChildOfClass(class) for _,child in ipairs(self._children) do if child:IsA(class) then return child end end end
function methods:WaitForChild(name) return assert(self:FindFirstChild(name),"Mock missing child: "..name) end
function methods:Destroy()
	if self._destroyed then return end
	self.Destroying:Fire();self._destroyed=true
	for _,child in ipairs(table.clone(self._children)) do child:Destroy() end
	self.Parent=nil
end
function methods:Stop() self.IsPlaying=false end
function methods:Play() self.IsPlaying=true;self.plays+=1 end
function methods:Fire(...) self.Event:Fire(...) end
function methods:GetPivot() return self.CFrame or CFrame.new(Vector3.new(0,0,10)) end
function methods:GetServerTimeNow() return now end
local function object(class,name,parent)
	local o=Instance.new(class);o.Name=name;o.Parent=parent;return o
end
local workspace=object("Workspace","Workspace")
local camera=object("Camera","Camera",workspace);camera.CFrame=CFrame.new(Vector3.new(0,0,0));camera.CameraType=Enum.CameraType.Custom
workspace.CurrentCamera=camera
workspace:SetAttribute("SelectedLevel",5);workspace:SetAttribute("RoundActive",true)
local player=object("Player","LocalPlayer");player.CharacterRemoving=signal()
local playerGui=object("PlayerGui","PlayerGui",player)
local playerScripts=object("PlayerScripts","PlayerScripts",player)
local character=object("Model","Character",workspace);player.Character=character
local humanoid=object("Humanoid","Humanoid",character);humanoid.Health=100
local root=object("Part","HumanoidRootPart",character);root.Position=Vector3.new(0,0,0)
player:SetAttribute("InRound",true);player:SetAttribute("RoundEntryControlsReady",true)
local script=object("LocalScript","Level5SoundController",playerScripts)
local gaze=object("LocalScript","WindowWatcherGazeClient",playerScripts)
local world=object("Model","Level 5 Generated World",workspace)
world:SetAttribute("Level5_MapOnly",true);world:SetAttribute("Level5_Generation",1)
world:SetAttribute("Level5OutageExemptMin",Vector3.new(100,-100,-100));world:SetAttribute("Level5OutageExemptMax",Vector3.new(200,100,100))
world:SetAttribute("Level5OutageExitMin",Vector3.new(300,-100,-100));world:SetAttribute("Level5OutageExitMax",Vector3.new(400,100,100))
local progression=object("Folder","Level5SectionProgression",world);progression:SetAttribute("Level5ProgressionOwned",true)
local gate=object("Model","SectionGate1",progression);gate:SetAttribute("Level5ProgressionOwned",true);gate:SetAttribute("Unlocked",false)
local lock=object("Part","ColourPadlock",gate);lock.Position=Vector3.new(0,0,20)
local gui=object("ScreenGui","Level5ColourLockGui",playerGui);gui:SetAttribute("Level5ProgressionOwned",true)
local cueEvent=object("BindableEvent","Level5AudioCue",gui)
local encounters=object("Folder","Level5WindowWatcherEncounters",world);encounters:SetAttribute("Level5WindowWatcherOwned",true)
encounters:SetAttribute("AppearanceCount",1);encounters:SetAttribute("Visible",false)
local actor=object("Model","WindowWatcher",encounters);actor:SetAttribute("Level5WindowWatcherOwned",true)
actor:SetAttribute("SourceGlbSha256","cbf260ff36b8c7226f27271456eae6bf4db7fd266bdce82dda8b0eae7cbc051e")
actor:SetAttribute("WindowWatcherVisualReady",true)
local modal=false
local runService={Heartbeat=signal()}
local soundService=object("SoundService","SoundService")
local rs=object("ReplicatedStorage","ReplicatedStorage")
for _,name in ipairs({"Level5AudioCatalog","Level5AudioLogic","Level5OutageLogic","UIDevice"}) do object("ModuleScript",name,rs) end
local guiService={MenuIsOpen=false}
local focused=nil
local schedules={}
local services={Players={LocalPlayer=player},ReplicatedStorage=rs,RunService=runService,SoundService=soundService,
	HttpService={JSONDecode=function(_,key) return assert(schedules[key],"bad JSON") end},
	ContentProvider={PreloadAsync=function() end},GuiService=guiService,UserInputService={GetFocusedTextBox=function() return focused end}}
local game={GetService=function(_,name) return assert(services[name],name) end}
local task={spawn=function(callback) callback() end}
local modules={Level5AudioCatalog=Catalog,Level5AudioLogic=Logic,Level5OutageLogic=Outage,UIDevice={ScreenOwningModalOpen=function() return modal end}}
local function require(module) return assert(modules[module.Name],module.Name) end
local function tick(dt)
	now+=dt or .1;runService.Heartbeat:Fire(dt or .1)
	eq(script:GetAttribute("AudioError"),nil,"controller runtime error")
end
local function voice(key)
	for i=#allObjects,1,-1 do local o=allObjects[i];if not o._destroyed and o.ClassName=="Sound" and o.Name==key then return o end end
end
local function alive(class)
	local n=0;for _,o in ipairs(allObjects) do if not o._destroyed and o.ClassName==class then n+=1 end end;return n
end
local function cueCount() return script:GetAttribute("AudioCueCount") end
local function ownsWorldSound()
	for _,o in ipairs(allObjects) do
		if not o._destroyed and (o.ClassName=="Sound" or o.Name:match("Emitter$")) then
			local p=o.Parent;while p do if p==world then return true end;p=p.Parent end
		end
	end
	return false
end
