-- Offline execution of the exact candidate participant predicate and prompt callback.
-- Mocks world/player instances and delays; no Studio objects or gameplay claim.
local fs,luau,serde,r=require("@lune/fs"),require("@lune/luau"),require("@lune/serde"),require("@lune/roblox")
local folder="tools/level3_promotion_20261002/public3/layout-world-candidates/"
local visual=fs.readFile(folder.."Level 3 Worn Party Visual Adapter.ModuleScript.candidate.luau")
local dressing=fs.readFile(folder.."Level 3 Worn Party Room Dressing.ModuleScript.candidate.luau")
local checks=0
local function check(v,m)checks+=1 assert(v,m)end
local function fragment(s,a,b)
    local start=assert(s:find(a,1,true));local finish=assert(s:find(b,start+1,true));return s:sub(start,finish-1)
end
local workspace={attrs={SelectedLevel=3,RoundActive=true}}
function workspace:GetAttribute(k)return self.attrs[k]end
local isParticipant=luau.load("local helper={}\n"..fragment(visual,"helper.IsParticipant = function(player)","helper.OnNoise = function").."return helper.IsParticipant",
    {environment={workspace=workspace}})()
local instances={}
local function signal()
    local result={handlers={}}
    function result:Connect(fn)
        local c={Connected=true};function c:Disconnect()self.Connected=false end
        table.insert(self.handlers,{c,fn});return c
    end
    function result:Fire(...)
        for _,record in ipairs(self.handlers)do if record[1].Connected then record[2](...)end end
    end
    return result
end
local function object(class,parent)
    local self={ClassName=class,Parent=parent,attrs={}}
    function self:GetAttribute(k)return self.attrs[k]end
    function self:SetAttribute(k,v)self.attrs[k]=v end
    function self:IsA(k)return k==self.ClassName or(k=="BasePart" and class=="Part")end
    if class=="ProximityPrompt" then self.Triggered=signal()end
    setmetatable(self,{__index=function(t,k)
        if k=="Position" then return t.CFrame.Position end
        return nil
    end})
    table.insert(instances,self);return self
end
local Players={}
local world=object("Model",workspace);world.attrs.Level3_Generation=71
local model=object("Model",world)
local character={}
local hum={Health=100};local root={Position=r.Vector3.new(0,4.2,1.8)}
function root:IsA(c)return c=="BasePart"end
function character:FindFirstChildOfClass(c)return if c=="Humanoid" then hum else nil end
function character:FindFirstChild(c)return if c=="HumanoidRootPart" then root else nil end
local player=object("Player",Players);player.UserId=111;player.Character=character
player.attrs={InRound=true,Escaped=false,Spectating=false}
local delays,connections,sounds,report,lastPlayerAction={}, {}, {}, {Interactions=0}, {}
local function later(seconds,fn)table.insert(delays,{Seconds=seconds,Fn=fn})end
local source=fragment(dressing,"local function carrier(","local function navBox(")
    ..fragment(dressing,"local function interactive(","local function faceCF(").."\nreturn interactive"
local publicAlive=true
local interactive=luau.load(source,{environment={Instance={new=function(c)return object(c,nil)end},
    V=r.Vector3.new,CFrame=r.CFrame,Players=Players,workspace=workspace,world=world,generation=71,
    alive=true,participantCheck=isParticipant,connections=connections,sounds=sounds,soundIds={},
    validSoundId=function()return nil end,noiseCallback=nil,lastPlayerAction=lastPlayerAction,later=later,report=report}})()
interactive(model,r.CFrame.identity,"arcade","ArcadeInvaders")
local prompt
for _,x in ipairs(instances)do if x.ClassName=="ProximityPrompt"then prompt=x end end
check(prompt and prompt.Name=="Level3_ServiceInteraction" and prompt.Enabled,"public prompt enabled")
check(report.Interactions==1 and #connections==1,"single owned prompt callback")
for _,case in ipairs({
    {InRound=false},{Escaped=true},{Spectating=true},{RoundActive=false},{SelectedLevel=6},
})do
    local saved={InRound=player.attrs.InRound,Escaped=player.attrs.Escaped,Spectating=player.attrs.Spectating,
        SelectedLevel=workspace.attrs.SelectedLevel,RoundActive=workspace.attrs.RoundActive}
    for k,v in pairs(case)do if workspace.attrs[k]~=nil then workspace.attrs[k]=v else player.attrs[k]=v end end
    check(not isParticipant(player),"unauthorized membership refused")
    prompt.Triggered:Fire(player)
    check(model.attrs.Level3_InteractionSerial==nil,"unauthorized prompt refused")
    for k,v in pairs(saved)do if k=="SelectedLevel"or k=="RoundActive"then workspace.attrs[k]=v else player.attrs[k]=v end end
end
world.attrs.Level3_Generation=72
prompt.Triggered:Fire(player)
check(model.attrs.Level3_InteractionSerial==nil,"stale generation refused")
world.attrs.Level3_Generation=71
root.Position=r.Vector3.new(100,4.2,1.8)
prompt.Triggered:Fire(player)
check(model.attrs.Level3_InteractionSerial==nil,"distant trigger refused")
root.Position=r.Vector3.new(0,4.2,1.8)
prompt.Triggered:Fire(player)
check(model.attrs.Level3_InteractionSerial==1 and model.attrs.Level3_LastUsedBy==111,"living public participant interacts")
check(model.attrs.Level3_ServiceActive and #delays==1,"one bounded cooldown callback")
prompt.Triggered:Fire(player)
check(model.attrs.Level3_InteractionSerial==1 and #delays==1,"busy prompt refuses duplicate work")
delays[1].Fn()
check(model.attrs.Level3_ServiceActive==false and prompt.ActionText=="Try a credit","cooldown resets prompt")
connections[1]:Disconnect()
prompt.Triggered:Fire(player)
check(model.attrs.Level3_InteractionSerial==1,"owned disconnect stops callbacks")
-- Execute the exact room-owned cleanup/delay functions with mock scheduler/events.
local owner=object("Folder",world)
function owner:Destroy()self.Parent=nil self.Destroyed=true end
world.AncestryChanged=signal();Players.PlayerRemoving=signal()
local delayed,cancelled={},{}
local scheduled={}
function scheduled.delay(seconds,fn)
    local thread={Seconds=seconds,Fn=fn};table.insert(delayed,thread);return thread
end
function scheduled.cancel(thread)cancelled[thread]=true end
local sound={Parent=owner,Stopped=false}
function sound:Stop()self.Stopped=true end
local tableware=object("Part",world)
tableware.attrs={Level3_TablewarePlaced=true,Level3_TablewareDressingOwner="fixture-71"}
local cleanupConnections,cleanupPending,cleanupSounds,cleanupMarked,cleanupActions={}, {}, {sound}, {tableware}, {[111]=1}
local lifecycle=luau.load(fragment(dressing,"local function later(","local function placed(").."\nreturn {Later=later,Cleanup=cleanup}",
    {environment={alive=true,owner=owner,world=world,Players=Players,task=scheduled,pending=cleanupPending,
        connections=cleanupConnections,sounds=cleanupSounds,tablewareMarked=cleanupMarked,
        lastPlayerAction=cleanupActions,dressingId="fixture-71"}})()
local calls=0
lifecycle.Later(5,function()calls+=1 end)
check(#cleanupConnections==2 and #delayed==1,"world/player lifetime and bounded owned delay")
lifecycle.Cleanup()
check(cancelled[delayed[1]] and next(cleanupPending)==nil,"cleanup cancels and clears delay")
check(#cleanupConnections==0 and #cleanupSounds==0 and next(cleanupActions)==nil,"cleanup clears all owned records")
check(sound.Stopped and owner.Destroyed,"cleanup stops sound and destroys only owned dressing")
check(tableware.attrs.Level3_TablewarePlaced==nil and tableware.attrs.Level3_TablewareDressingOwner==nil,"cleanup releases tableware marks")
delayed[1].Fn()
check(calls==0,"late callback cannot mutate reset world")
lifecycle.Cleanup()
check(calls==0,"cleanup idempotent")
local receipt={Passed=true,Checks=checks,Scope="Exact public participant predicate/prompt callback and owned cleanup/delay functions with mocks; gameplay and engine lifecycle unverified"}
fs.writeFile("tools/level3_promotion_20261002/public3/public-dressing-lifecycle-receipt.json",serde.encode("json",receipt,true).."\n")
print(serde.encode("json",receipt,true))
