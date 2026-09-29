"""Run the actual draft with bounded Roblox fakes for ownership/failure cleanup.

Usage: python3 test_window_watcher_lifecycle.py /path/to/luau
This checks server lifecycle logic, not Roblox asset playback or replication.
"""
from pathlib import Path
import subprocess
import sys
import tempfile

module = Path(__file__).resolve().parents[1] / "patches/Level 5 Window Watcher Encounters.ModuleScript.lua"
header = r'''
local assertions=0
local function check(value,message) assertions+=1;assert(value,message) end
local clock=0
local os={clock=function() return clock end}
local nativeTypeof=typeof
local function typeof(value)
    if type(value)=="table" and value._class then return "Instance" end
    if type(value)=="table" and value._vector then return "Vector3" end
    return nativeTypeof(value)
end
local Vector3={}
local vectorMt={}
vectorMt.__add=function(a,b) return Vector3.new(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
vectorMt.__sub=function(a,b) return Vector3.new(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
vectorMt.__index=function(a,key) if key=="Magnitude" then return math.sqrt(a.X*a.X+a.Y*a.Y+a.Z*a.Z) end end
function Vector3.new(x,y,z) return setmetatable({_vector=true,X=x,Y=y,Z=z},vectorMt) end
local CFrame={}
local frameMt={}
frameMt.__mul=function(a,b) return CFrame.new(a.x+b.x,a.y+b.y,a.z+b.z) end
frameMt.__index={
    PointToWorldSpace=function(a,v) return Vector3.new(a.x+v.X,a.y+v.Y,a.z+v.Z) end,
    PointToObjectSpace=function(a,v) return Vector3.new(v.X-a.x,v.Y-a.y,v.Z-a.z) end,
}
function CFrame.new(x,y,z) return setmetatable({x=x or 0,y=y or 0,z=z or 0},frameMt) end
local Enum={Material={Glass="Glass"},AnimationPriority={Idle="Idle"},RaycastFilterType={Exclude="Exclude"}}
local Random={new=function() return {NextNumber=function() return .5 end} end}
local RaycastParams={new=function() return {} end}
local connections={}
local function signal()
    local listeners={}
    return {
        Connect=function(_,callback)
            local connection={Connected=true,callback=callback}
            function connection:Disconnect() self.Connected=false end
            table.insert(listeners,connection);table.insert(connections,connection)
            return connection
        end,
        Fire=function(_,...)
            for _,connection in ipairs(table.clone(listeners)) do
                if connection.Connected then connection.callback(...) end
            end
        end,
    }
end
local Instance={}
local methods={}
local loadCount,failLoadAt,trackLength=0,nil,5
local tracks={}
local mt={}
mt.__index=function(self,key) return methods[key] or self._props[key] end
mt.__newindex=function(self,key,value)
    if key=="Parent" then
        local old=self._props.Parent
        if old then for index,child in ipairs(old._children) do if child==self then table.remove(old._children,index);break end end end
        self._props.Parent=value
        if value then table.insert(value._children,self) end
        self.AncestryChanged:Fire(self,value)
    else self._props[key]=value end
end
function Instance.new(class)
    return setmetatable({_class=class,_children={},_attrs={},_props={Name=class,Archivable=true,Transparency=0,
        Enabled=true,Destroying=signal(),AncestryChanged=signal(),CFrame=CFrame.new(),Position=Vector3.new(0,0,0)}},mt)
end
function methods:IsA(class)
    return self._class==class or class=="Instance"
        or (class=="BasePart" and (self._class=="Part" or self._class=="MeshPart"))
        or (class=="Light" and self._class=="SpotLight")
        or (class=="BaseScript" and self._class=="Script")
end
function methods:SetAttribute(name,value) self._attrs[name]=value end
function methods:GetAttribute(name) return self._attrs[name] end
function methods:GetChildren() return table.clone(self._children) end
function methods:GetDescendants()
    local results={}
    for _,child in ipairs(self._children) do
        table.insert(results,child)
        for _,descendant in ipairs(child:GetDescendants()) do table.insert(results,descendant) end
    end
    return results
end
function methods:FindFirstChild(name)
    for _,child in ipairs(self._children) do if child.Name==name then return child end end
end
function methods:FindFirstChildOfClass(class)
    for _,child in ipairs(self._children) do if child._class==class then return child end end
end
function methods:IsDescendantOf(target)
    local parent=self.Parent
    while parent do if parent==target then return true end;parent=parent.Parent end
    return false
end
function methods:Destroy()
    if self._props.destroyed then return end
    self._props.destroyed=true;self.Destroying:Fire()
    for _,child in ipairs(self:GetChildren()) do child:Destroy() end
    self.Parent=nil
end
function methods:Clone()
    local clone=Instance.new(self._class)
    for key,value in pairs(self._props) do
        if key~="Parent" and key~="Destroying" and key~="AncestryChanged" then clone[key]=value end
    end
    for key,value in pairs(self._attrs) do clone:SetAttribute(key,value) end
    for _,child in ipairs(self:GetChildren()) do child:Clone().Parent=clone end
    return clone
end
function methods:PivotTo(frame) self._props.pivot=frame end
function methods:LoadAnimation(animation)
    loadCount+=1
    if loadCount==failLoadAt then error("simulated permission failure") end
    local track={Length=trackLength,playing=false,destroyed=false,animation=animation}
    function track:Play() self.playing=true end
    function track:Stop() self.playing=false end
    function track:Destroy() self.destroyed=true end
    table.insert(tracks,track)
    return track
end
local workspace=Instance.new("Workspace")
function methods:Raycast() return nil end
local RunService={Heartbeat=signal(),IsServer=function() return true end,IsRunning=function() return true end}
local Players=Instance.new("Players")
local ServerStorage=Instance.new("ServerStorage")
local game={GetService=function(_,name) return ({RunService=RunService,Players=Players,ServerStorage=ServerStorage})[name] end}
local warnings={}
local function warn(text) table.insert(warnings,text) end
local function create(class,name,parent)
    local object=Instance.new(class);object.Name=name;object.Parent=parent;return object
end
workspace:SetAttribute("Level5DevEnabled",true)
workspace:SetAttribute("SelectedLevel",5)
workspace:SetAttribute("RoundActive",true)
local container=create("Folder","Level5WindowWatcher",ServerStorage)
local template=create("Model","WindowWatcherRig",container)
local body=create("MeshPart","Body",template)
local eyes=create("BillboardGui","WhiteEyes",body);eyes.AlwaysOnTop=true
local eyeLight=create("SpotLight","EyeLight",body)
create("Script","ImportedScript",template)
create("Sound","ImportedSound",template)
create("AnimationController","AnimationController",template)
local animations=create("Folder","Animations",container)
for i,name in ipairs({"WatchingIdle","SlowWindowLean","GlassTap"}) do
    local animation=create("Animation",name,animations);animation.AnimationId="rbxassetid://"..(100+i)
end
local player=create("Player","Developer",Players)
player:SetAttribute("InRound",true)
local character=create("Model","Character",workspace);player.Character=character
local root=create("Part","HumanoidRootPart",character);root.Position=Vector3.new(0,3,820)
local human=create("Humanoid","Humanoid",character);human.Health=100
local function newWorld()
    local world=create("Model","Level 5 Generated World",workspace);world:SetAttribute("Level5_MapOnly",true)
    local architecture=create("Model","Level5_IndoorSuburbs",world)
    local district=create("Model","F_BayWindowCanyon",architecture)
    local anchors=create("Model","WindowWatcherAnchors",district)
    for i,name in ipairs({"FarUpperWindow","MiddleCourtWindow","NearGroundWindow"}) do
        local pane=create("Part","WindowGlass"..i,district)
        pane.Material="Glass";pane:SetAttribute("Level5TintedWindow",true);pane.CFrame=CFrame.new(i*10,6.55,840)
        local anchor=create("Part",name,anchors);anchor:SetAttribute("Level5WindowWatcherAnchor",true)
        local reference=create("ObjectValue","WindowGlass",anchor);reference.Value=pane
    end
    return world
end
local options={Origin=Vector3.new(0,0,0),GetParticipants=function() return {player} end}
local function tick(seconds) clock+=seconds;RunService.Heartbeat:Fire(seconds) end
local function connected()
    local total=0;for _,connection in ipairs(connections) do if connection.Connected then total+=1 end end;return total
end
local Encounters=(function()
'''
footer = r'''
end)()
local world=newWorld()
local start=Encounters.Start(world,options)
check(start.ok and start.actorCount==1,"one actor is installed")
local folder=start.folder
local actor=folder:FindFirstChild("WindowWatcher")
local actorBody=actor:FindFirstChild("Body")
local actorEyes=actorBody:FindFirstChild("WhiteEyes")
local actorLight=actorBody:FindFirstChild("EyeLight")
check(#folder:GetChildren()==1,"no second simultaneous rig")
check(actor:FindFirstChild("ImportedScript")==nil and actor:FindFirstChild("ImportedSound")==nil,"no importer scripts/audio")
check(actorBody.Transparency==1 and not actorEyes.Enabled and not actorLight.Enabled,"body and glowing eyes hidden during warmup")
check(not actorEyes.AlwaysOnTop,"white eyes cannot draw through walls")
check(actorBody.Anchored and not actorBody.CanCollide and not actorBody.CanTouch and not actorBody.CanQuery,"passive geometry")
check(not Encounters.Start(world,options).ok and #folder:GetChildren()==1,"double installation preserves current owner")
tick(.25);tick(3);tick(.25)
check(folder:GetAttribute("Visible")==true and actorBody.Transparency==0,"one appearance after first delay and warmup")
check(actorEyes.Enabled and actorLight.Enabled,"white eyes enabled only with visible body")
check(folder:GetAttribute("AppearanceCount")==1,"appearance counter")
local playing=0;for _,track in ipairs(tracks) do if track.playing then playing+=1 end end
check(playing==1,"only chosen animation is playing")
player:SetAttribute("InRound",false);tick(.25)
check(not folder:GetAttribute("Visible") and not actorEyes.Enabled and not actorLight.Enabled,"leaving roster hides all visuals immediately")
player:SetAttribute("InRound",true);tick(.25);tick(3);tick(.25)
check(folder:GetAttribute("Visible"),"fresh encounter after participant returns")
world:Destroy()
check(folder.destroyed and connected()==0,"world destruction removes folder and every connection")
for _,track in ipairs(tracks) do check(track.destroyed and not track.playing,"world cleanup destroys every track") end
Encounters.Cleanup(world);tick(100)
check(connected()==0,"cleanup is idempotent; old round has no callback")

world=newWorld();loadCount=0;failLoadAt=2
local failed=Encounters.Start(world,options)
check(not failed.ok and string.find(failed.error,"permission failure",1,true),"load failure is reported")
check(world:FindFirstChild("Level5WindowWatcherEncounters")==nil and connected()==0,"partial load failure rolls back rig and connections")
failLoadAt=nil;loadCount=0
local retry=Encounters.Start(world,options)
check(retry.ok,"rollback releases the owner so retry is possible")
world.Parent=ServerStorage
check(retry.folder.destroyed and connected()==0,"moving world out of Workspace cancels encounters")
world:Destroy()

world=newWorld();trackLength=0
local timeout=Encounters.Start(world,options)
check(timeout.ok,"asynchronous assets start hidden")
tick(21)
check(timeout.folder.destroyed and connected()==0,"asset timeout leaves no immortal heartbeat")
check(string.find(world:GetAttribute("WindowWatcherError"),"timeout",1,true),"asset timeout leaves clear diagnostic")
trackLength=5;world:Destroy()

world=newWorld()
local clip=animations:FindFirstChild("GlassTap");local id=clip.AnimationId;clip.AnimationId=""
local missing=Encounters.Start(world,options)
check(not missing.ok and world:FindFirstChild("Level5WindowWatcherEncounters")==nil,"invalid clip fails before any installation")
check(connected()==0,"read-only validation installs no connections")
clip.AnimationId=id;world:Destroy()

world=newWorld()
local final=Encounters.Start(world,options)
check(final.ok,"new world is independent of destroyed rounds")
final.folder:Destroy()
check(connected()==0,"direct encounter folder destruction cancels all callbacks")
Encounters.Cleanup(world);world:Destroy()
print("PASS Window Watcher mocked lifecycle: "..assertions.." assertions; native playback/replication not covered")
'''
with tempfile.TemporaryDirectory(prefix="watcher-lifecycle-") as temporary:
    test = Path(temporary) / "test.luau"
    test.write_text(header + module.read_text() + footer)
    subprocess.run([sys.argv[1], str(test)], check=True)
