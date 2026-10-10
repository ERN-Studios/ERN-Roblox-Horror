return function()
-- Offline engine boundaries for actual LightDirector and CD display contracts.
local checks = 0
local function check(value, message)
    checks += 1
    assert(value, message)
end
local vec = {}
vec.__index = function(v, k)
    if k == "Magnitude" then return math.sqrt(v.X*v.X+v.Y*v.Y+v.Z*v.Z) end
    return vec[k]
end
vec.__add = function(a,b) return setmetatable({X=a.X+b.X,Y=a.Y+b.Y,Z=a.Z+b.Z,kind="Vector3"},vec) end
vec.__sub = function(a,b) return setmetatable({X=a.X-b.X,Y=a.Y-b.Y,Z=a.Z-b.Z,kind="Vector3"},vec) end
vec.__mul = function(a,b)
    if type(a)=="number" then a,b=b,a end
    return setmetatable({X=a.X*b,Y=a.Y*b,Z=a.Z*b,kind="Vector3"},vec)
end
vec.__div = function(a,b) return a*(1/b) end
local Vector3 = {new=function(x,y,z) return setmetatable({X=x,Y=y,Z=z,kind="Vector3"},vec) end}
Vector3.zero=Vector3.new(0,0,0); Vector3.one=Vector3.new(1,1,1)
local colors = {}
colors.__index=colors
function colors:Lerp(other,alpha)
    return setmetatable({R=self.R+(other.R-self.R)*alpha,G=self.G+(other.G-self.G)*alpha,B=self.B+(other.B-self.B)*alpha,kind="Color3"},colors)
end
local Color3={new=function(r,g,b) return setmetatable({R=r,G=g,B=b,kind="Color3"},colors) end}
Color3.fromRGB=function(r,g,b) return Color3.new(r/255,g/255,b/255) end
local cf = {}
cf.__index=cf
local CFrame={}
function CFrame.new(x,y,z)
    return setmetatable({Position=Vector3.new(x or 0,y or 0,z or 0),Yaw=0,kind="CFrame"},cf)
end
function CFrame.Angles(_,yaw,_) local c=CFrame.new(); c.Yaw=yaw; return c end
function cf:PointToWorldSpace(p)
    return self.Position+Vector3.new(math.cos(self.Yaw)*p.X+math.sin(self.Yaw)*p.Z,p.Y,-math.sin(self.Yaw)*p.X+math.cos(self.Yaw)*p.Z)
end
cf.__mul=function(a,b)
    local c=CFrame.new(); c.Position=a:PointToWorldSpace(b.Position); c.Yaw=a.Yaw+b.Yaw; return c
end
local Enum={Material={Neon="Neon",Metal="Metal",SmoothPlastic="SmoothPlastic"},NormalId={Front="Front",Back="Back",Bottom="Bottom"},PartType={Ball="Ball"}}
local Random={new=function()
    return {NextNumber=function(_,a,b) if a==nil then return .5 end; if b==nil then a,b=0,a end; return (a+b)*.5 end,
        NextInteger=function(_,a,_) return a end}
end}
local RaycastParams={new=function() return {} end}
local function stable(v)
    if type(v)~="table" then return type(v)..":"..tostring(v) end
    if rawget(v,"_class") then return "Instance:"..v.Name end
    local keys={}; for k in pairs(v) do keys[#keys+1]=k end
    table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
    local out={}; for _,k in ipairs(keys) do out[#out+1]=tostring(k).."="..stable(v[k]) end
    return "{"..table.concat(out,";").."}"
end
local Methods={}
local mt={}
mt.__index=function(o,k)
    if k=="Parent" then return rawget(o,"_parent") end
    if k=="Position" then return o._props.Position or (o._props.CFrame and o._props.CFrame.Position) end
    return Methods[k] or o._props[k]
end
mt.__newindex=function(o,k,v)
    if k=="Parent" then
        local old=rawget(o,"_parent")
        if old then local i=table.find(old._children,o); if i then table.remove(old._children,i) end end
        rawset(o,"_parent",v)
        if v then v._children[#v._children+1]=o end
    else o._props[k]=v end
end
function Methods:IsA(class)
    return self._class==class or (class=="BasePart" and self._class=="Part")
        or (class=="Light" and (self._class=="PointLight" or self._class=="SurfaceLight"))
end
function Methods:GetAttribute(k) return self._attrs[k] end
function Methods:SetAttribute(k,v) self._attrs[k]=v end
function Methods:GetAttributes() return table.clone(self._attrs) end
function Methods:GetChildren() return table.clone(self._children) end
function Methods:GetDescendants()
    local out={}
    local function visit(o) for _,c in ipairs(o._children) do out[#out+1]=c; visit(c) end end
    visit(self); return out
end
function Methods:IsDescendantOf(parent)
    local p=self.Parent; while p do if p==parent then return true end; p=p.Parent end; return false
end
function Methods:FindFirstChild(name)
    for _,c in ipairs(self._children) do if c.Name==name then return c end end
end
function Methods:Destroy()
    for _,c in ipairs(self:GetChildren()) do c:Destroy() end
    self.Parent=nil; self._props.Destroyed=true
end
function Methods:Clone()
    local o=self._factory.new(self._class)
    for k,v in pairs(self._props) do o[k]=v end
    for k,v in pairs(self._attrs) do o:SetAttribute(k,v) end
    return o
end
local function engine()
    local e={clock=0,queue={},allocated={},events={},reads={},tags={},failPartAt=nil,partAttempts=0}
    e.Instance={new=function(class)
        if class=="Part" then
            e.partAttempts+=1
            if e.failPartAt==e.partAttempts then error("fixture allocation failure",0) end
        end
        local o=setmetatable({_class=class,_parent=nil,_children={},_attrs={},_factory=e.Instance,
            _props={Name=class,Transparency=0,Enabled=true,Brightness=1}},mt)
        e.allocated[#e.allocated+1]=o
        return o
    end}
    local function resume(token,...)
        if token.Cancelled then return end
        local ok,waited=coroutine.resume(token.Co,...)
        assert(ok,waited)
        if coroutine.status(token.Co)~="dead" then
            token.At=e.clock+(waited or 0); e.queue[#e.queue+1]=token
        end
    end
    e.task={spawn=function(fn,...)
        local token={Co=coroutine.create(fn)}; resume(token,...); return token
    end,wait=function(delay) return coroutine.yield(delay or 0) end,
        delay=function(delay,fn,...)
            local args=table.pack(...); local token={At=e.clock+delay,Co=coroutine.create(function() fn(table.unpack(args,1,args.n)) end)}
            e.queue[#e.queue+1]=token; return token
        end,cancel=function(token) token.Cancelled=true end}
    function e.runTo(target)
        local steps=0
        while true do
            table.sort(e.queue,function(a,b) return a.At<b.At end)
            local token=e.queue[1]
            if not token or token.At>target then break end
            table.remove(e.queue,1); e.clock=token.At; steps+=1; assert(steps<1000,"bounded clock")
            resume(token)
        end
        e.clock=target
    end
    local config={Sequence={PowerUpWaveSeconds=2,FullyLitSeconds=.5},Failing={DeadZones=1,AvoidPlayerZoneChance=.7,
        BlinkEvery={.4,.4,.4,.4},MaxDarkFraction={.7,.7,.7,.7},OffSeconds={{.6,.6},{.6,.6},{.6,.6},{.6,.6}}}}
    e.game={GetService=function(_,name)
        e.reads[#e.reads+1]="service:"..name
        if name=="CollectionService" then return {
            HasTag=function(_,part,tag) return table.find(e.tags[tag] or {},part)~=nil end,
            GetTagged=function(_,tag) return e.tags[tag] or {} end}
        elseif name=="ReplicatedStorage" then return {}
        elseif name=="Players" then return {GetPlayers=function() return {} end} end
        error("unexpected service "..name)
    end}
    e.script={Parent={WaitForChild=function(_,name) e.reads[#e.reads+1]="module:"..name; return config end}}
    e.require=function(module) e.reads[#e.reads+1]="require"; assert(module==config); return config end
    e.workspace={GetServerTimeNow=function() return e.clock end,Raycast=function() return nil end}
    e.new=function(class,name,parent) local o=e.Instance.new(class); o.Name=name; o.Parent=parent; return o end
    e.signature=function(root)
        local rows={}
        for _,o in ipairs(root:GetDescendants()) do
            local props=table.clone(o._props); props.Parent=o.Parent and o.Parent.Name
            rows[#rows+1]=o._class..":"..stable(props)..":"..stable(o._attrs)
        end
        table.sort(rows); return table.concat(rows,"\n")
    end
    return e
end

local function lightFixture(load)
    local e=engine()
    local api=load(e)
    local names={}; for k,v in pairs(api) do names[#names+1]=k..":"..type(v) end; table.sort(names)
    check(#e.allocated==0,"module load registers no instances")
    local root=e.new("Model","Light World")
    local state=e.new("Folder","Light State",root)
    local stars,lights,neons={},{},{}
    for i=1,3 do
        local holder=e.new("Part","Holder"..i,root); holder.Position=Vector3.new((i-1)*60,18,0); holder:SetAttribute("L4Zone",i)
        local light=e.new("PointLight","ZoneLight"..i,holder); light.Enabled=i~=2; light.Brightness=i*.75; lights[i]=light
        local neon=e.new("Part","Neon"..i,root); neon.Position=holder.Position; neon.Material=Enum.Material.Neon
        neon.Color=Color3.fromRGB(20*i,70,150); neon:SetAttribute("L4Zone",i); neons[i]=neon
        if i~=3 then
            local marker=e.new("Part","ZoneMarker"..i,root); marker.Position=Vector3.new((i-1)*60,0,0); marker.Size=Vector3.new(45,1,45)
            marker:SetAttribute("Zone",i); marker:SetAttribute("Radius",25); e.tags.L4LightZone=e.tags.L4LightZone or {}; table.insert(e.tags.L4LightZone,marker)
        end
        local star=e.new("Part","Star"..i,root); star.Transparency=i*.1; stars[i]=star
        e.tags["L4StarTwinkle"..string.char(64+i)]={star}
    end
    local other=e.new("Model","Other World")
    local outsider=e.new("Part","Unowned Star",other); outsider.Transparency=.37
    table.insert(e.tags.L4StarTwinkleA,outsider)
    local remote={FireAllClients=function(_,payload) e.events[#e.events+1]=payload end}
    local stages={}
    local function save(label)
        stages[#stages+1]=label.."\n"..e.signature(root).."\n"..stable(state._attrs).."\n"..stable(e.events)
    end
    check(api.Start({World=root,State=state,ClientEvent=remote,ProtectedLightPoints={Vector3.zero}},17)==3,"three zones including averaged unmarked zone")
    check(api.PowerState()=="Off" and api.ZoneCount()==3,"start publishes Off")
    for _,s in ipairs(stars) do check(s.Transparency==1,"every active STAR_TAG is off") end
    check(outsider.Transparency==.37,"unowned tagged star unaffected")
    check(not lights[1].Enabled and neons[1].Material==Enum.Material.SmoothPlastic,"zone light and neon dark")
    check(not api.IsLit(Vector3.new(0,0,0)) and api.IsDark(Vector3.new(0,0,0)),"authoritative off state")
    local zone,id=api.ZoneAt(Vector3.new(0,0,0)); check(zone~=nil and id==1,"zone containment")
    check(api.ZoneAt(Vector3.new(999,0,0))==nil,"outside zones")
    api.SetEscalation(8); check(state:GetAttribute("Level4_Escalation")==3,"escalation clamps")
    save("Off")
    api.PowerUp(Vector3.zero); e.runTo(.61)
    check(not lights[1].Enabled,"wave announces before authority switch")
    e.runTo(.86); check(lights[1].Enabled,"wave enables first zone after lead")
    e.runTo(3.0); check(api.PowerState()=="On","wave reaches fully lit")
    check(math.abs(stars[1].Transparency-.1)<1e-9 and math.abs(stars[2].Transparency-.2)<1e-9 and math.abs(stars[3].Transparency-.3)<1e-9,"stars restore authored values")
    check(not lights[2].Enabled,"authored disabled light remains disabled")
    save("On")
    e.runTo(3.9); check(api.PowerState()=="Failing","failing phase remains active")
    check(not api.IsZoneOn(2),"protected origin avoids deterministic dead-zone choice")
    save("Failing")
    local screen=e.new("Part","Screen",root)
    api.Finale({screen}); check(api.PowerState()=="Finale" and api.IsDark(Vector3.zero),"finale authority dark")
    check(#screen:GetChildren()==2,"both screen faces receive glow")
    save("Finale")
    api.Stop(); check(api.PowerState()=="Preview","Stop returns preview")
    check(#screen:GetChildren()==0,"Stop removes screen glow")
    check(lights[1].Enabled and not lights[2].Enabled and neons[1].Material==Enum.Material.Neon,"Stop restores authored lights/neon")
    e.runTo(5); check(lights[1].Enabled,"old delayed transition cannot overwrite stopped world")
    save("Stopped")
    local empty=e.new("Model","Empty World")
    check(api.Start({World=empty,State=state,ClientEvent=remote},18)==0,"empty build has zero zones")
    api.PowerUp(Vector3.zero); api.Stop(); e.runTo(10)
    check(api.PowerState()=="Preview","reset cancels old wave")
    root:Destroy(); other:Destroy(); empty:Destroy()
    for _,o in ipairs(e.allocated) do check(o.Parent==nil,"fixture objects destroyed") end
    return {API=names,Reads=e.reads,Stages=stages}
end

local function lampFixture(load,failed)
    local e=engine()
    local root=e.new("Model","CD Player Fixture")
    local playerCF=CFrame.new(18,4,-27)*CFrame.Angles(0,1.1,0)
    e.failPartAt=failed and 9 or nil
    local ok,problem=pcall(load,e,root,playerCF)
    if failed then
        check(not ok and problem=="fixture allocation failure","shade allocation error propagates")
        check(#root:GetChildren()==8,"pre-error constructed parts preserved exactly")
    else
        check(ok,tostring(problem))
        check(#root:GetChildren()==9,"all nine display/support/lamp/shade parts remain")
        local shade=root:FindFirstChild("CD Player Task Lamp Shade")
        check(shade~=nil and shade:IsA("BasePart"),"visible lamp shade is still built")
        check(shade.Parent==root and not shade.CanCollide and not shade.CanTouch and not shade.CanQuery,"shade parent/collision contract")
        check(shade.Size.X==3.65 and shade.Size.Y==.13 and shade.Size.Z==.54,"authored shade dimensions")
        local position=playerCF:PointToWorldSpace(Vector3.new(0,7.16,1.48))
        check((shade.Position-position).Magnitude<1e-9,"shade transformed placement")
        local lamp=root:FindFirstChild("CD Player Task Lamp")
        local light=lamp:FindFirstChild("CD Player Warm Task Light")
        check(light and light.Face==Enum.NormalId.Bottom and light.Brightness==.85 and light.Range==13,"task light stays on lamp with authored profile")
        check(root:FindFirstChild("CD Relay Display Housing"):GetAttribute("Level3_DiscPlayerDisplayHousing")==true,"housing authoring attribute preserved")
    end
    local signature=e.signature(root)
    root:Destroy()
    for _,o in ipairs(e.allocated) do check(o.Parent==nil,"owner fixture cleanup removes constructed objects") end
    return {Signature=signature,Ok=ok,Error=not ok and problem or nil,Attempts=e.partAttempts}
end
-- Extra engine boundaries only for actual RoomDressing authoring/interaction.
local typeof=function(value) return type(value)=="table" and value.kind or type(value) end
local oldCFNew=CFrame.new
CFrame.new=function(x,y,z)
    if type(x)=="table" and x.kind=="Vector3" then return oldCFNew(x.X,x.Y,x.Z) end
    return oldCFNew(x,y,z)
end
cf.__index=function(c,key)
    if key=="RightVector" then return Vector3.new(math.cos(c.Yaw),0,-math.sin(c.Yaw)) end
    if key=="UpVector" then return Vector3.new(0,1,0) end
    if key=="LookVector" then return Vector3.new(-math.sin(c.Yaw),0,-math.cos(c.Yaw)) end
    return cf[key]
end
CFrame.lookAt=function(position,target)
    local c=CFrame.new(position); local direction=target-position
    c.Yaw=math.atan2(-direction.X,-direction.Z); return c
end
Enum.RollOffMode={InverseTapered="InverseTapered"}
function Methods:FindFirstChildOfClass(class)
    for _,c in ipairs(self._children) do if c:IsA(class) then return c end end
end
function Methods:Play() self.Playing=true end
function Methods:Stop() self.Playing=false end
local originalStable=stable
stable=function(value)
    if type(value)=="table" and value.Signal then return "Signal" end
    return originalStable(value)
end
local function dressingEngine()
    local e=engine()
    e.signals={}
    local function signal()
        local s={Signal=true,Connections={}}
        function s:Connect(fn)
            local connection={Connected=true,Fn=fn}
            function connection:Disconnect() self.Connected=false end
            s.Connections[#s.Connections+1]=connection; return connection
        end
        function s:Fire(...)
            for _,connection in ipairs(self.Connections) do if connection.Connected then connection.Fn(...) end end
        end
        e.signals[#e.signals+1]=s; return s
    end
    local originalNew=e.Instance.new
    e.Instance.new=function(class)
        local object=originalNew(class); object.AncestryChanged=signal()
        if class=="ProximityPrompt" then object.Triggered=signal() end
        return object
    end
    e.Players={PlayerRemoving=signal()}
    function e.Players:GetPlayers() return {} end
    local originalService=e.game.GetService
    e.game.GetService=function(self,name)
        if name=="Players" then e.reads[#e.reads+1]="service:Players"; return e.Players end
        return originalService(self,name)
    end
    e.workspace.Attributes={RoundActive=true,SelectedLevel=3}
    function e.workspace:GetAttribute(key) return self.Attributes[key] end
    e.os={clock=function() return e.clock end}
    return e
end

local function planFixture(load)
    local e=dressingEngine(); local api=load(e)
    check(#e.allocated==0,"Room Dressing module load allocates no instances")
    local rows={}
    for _,variant in ipairs({"BudgetArcade","PartySupplyStore","MaintenanceWorkshop","Unknown"}) do
        for _,width in ipairs({30,42,60,80}) do
            for _,seed in ipairs({0,1,2,3,4,-3,10.75}) do
                for _,blocked in ipairs({{},{{x=20,z=17,hx=15,hz=15}},{{x=0,z=0,hx=100,hz=100}}}) do
                    local result=api.Plan({W=width,D=64,ServiceVariant=variant},blocked,seed)
                    check(result~=nil and type(result.Reason)=="string","Plan always returns explicit decision")
                    if variant=="Unknown" then check(result.Variant==nil and result.Reason=="not-service-room","nonservice room bypass") end
                    rows[#rows+1]=stable(result)
                end
            end
        end
    end
    local good=api.Plan({W=80,D=64,ServiceVariant="BudgetArcade"},{},0)
    check(good.Pocket and good.Pocket.sx==1 and good.Pocket.sz==1,"authoring seed0 chooses positive corner")
    local rotated=api.Plan({W=80,D=64,ServiceVariant="BudgetArcade"},{},1)
    check(rotated.Pocket and rotated.Pocket.sx==-1 and rotated.Pocket.sz==-1,"seed1 changes corner deterministically")
    local blocked=api.Plan({W=80,D=64,ServiceVariant="BudgetArcade"},{{x=0,z=0,hx=100,hz=100}},0)
    check(not blocked.Pocket and blocked.Reason=="no-free-18x24-corner","existing obstacle envelopes win over art target")
    local narrow=api.Plan({W=30,D=30,ServiceVariant="BudgetArcade"},{},0)
    check(not narrow.Pocket,"cardinal portal crossing rejected")
    local ok,problem=pcall(api.Plan,{W="invalid",D=64,ServiceVariant="BudgetArcade"},{},0)
    check(not ok and string.find(problem,"Room W/D required",1,true),"invalid dimensions fail explicitly")
    return {Reads=e.reads,Rows=rows}
end

local function dressingFixture(load,blockedAll,failAssets,noParticipant)
    local e=dressingEngine(); e.clock=10
    local api=load(e)
    local stage=e.new("Folder","Unparented Fixture")
    local world=e.new("Model","Dressing World",stage); world:SetAttribute("Level3_Generation",7)
    local manifest={World=world,Generation=7,Rooms={},Layout={Rooms={},ResolvedSeed=123}}
    for i,variant in ipairs({"BudgetArcade","PartySupplyStore","MaintenanceWorkshop"}) do
        local id="Room"..i
        local room={Id=id,Kind="Service",W=80,D=64,H=12,X=i*200,Z=17,ServiceVariant=variant}
        manifest.Layout.Rooms[#manifest.Layout.Rooms+1]=room
        local model=e.new("Model",id,world); manifest.Rooms[id]=model
        if blockedAll then
            local obstacle=e.new("Part","Authoritative Permanent Furniture",model)
            obstacle.CFrame=CFrame.new(14+room.X,2,4); obstacle.Size=Vector3.new(500,8,500); obstacle.CanCollide=true
            obstacle:SetAttribute("Level3_PermanentFurniture",true)
        end
    end
    local placements,noise={},{ }
    local helper={WorldOrigin=Vector3.new(14,2,-13),SoundIds={BreakerInspect="rbxassetid://11",ClawMotor=12,ArcadeInvaders=13}}
    helper.Place=function(asset,frame,parent,options)
        placements[#placements+1]={Asset=asset,Frame=frame,Options=options}
        if failAssets then error("fixture unavailable asset",0) end
        local model=e.new("Model",asset,parent)
        local part=e.new("Part",asset.." Mesh",model)
        part.CFrame=frame; part.Size=Vector3.new(2,4,2); part.CanCollide=options.Collidable
        return model
    end
    local participant={UserId=71,Parent=e.Players}
    local character=e.new("Model","Participant")
    participant.Character=character
    local humanoid=e.new("Humanoid","Humanoid",character); humanoid.Health=100
    local root=e.new("Part","HumanoidRootPart",character); root.Position=Vector3.zero
    if not noParticipant then helper.IsParticipant=function(p) return p==participant end end
    helper.OnNoise=function(p,position,amount) noise[#noise+1]={UserId=p.UserId,Position=position,Amount=amount} end
    local result=api.Apply(manifest,helper,{Seed=123})
    check(result.Report.Rooms==3,"all service rooms authoring result counted")
    if failAssets then
        check(result.Report.PropsPlaced==0 and result.Report.Interactions==0,"failed asset placement makes no interactive ghosts")
        check(next(result.Report.MissingAssets)~=nil,"missing assets reported")
    elseif blockedAll then
        check(result.Report.FullServicePockets==0 and result.Report.FallbackServiceRooms==3,"protected-space authoring fallback")
        check(#result.Report.Skipped==10 and result.Report.Interactions==0,"blocked fallback keeps colliders/prompts absent")
    else
        check(result.Report.FullServicePockets==3 and result.Report.Interactions==5,"three variants preserve arcade/claw/breaker interactions")
        local breaker=result.Owner:FindFirstChild("Room3 | Blender Dressing"):FindFirstChild("BreakerPanel")
        local anchor=breaker:FindFirstChild("Interaction Origin")
        local authored=placements
        local breakerCF
        for _,placement in ipairs(authored) do if placement.Asset=="BreakerPanel" then breakerCF=placement.Frame end end
        check((anchor.Position-breakerCF:PointToWorldSpace(Vector3.new(.98,2.15,.42))).Magnitude<1e-9,"breaker latch prompt uses mounted +2.15 position")
        local prompt=anchor:FindFirstChild("Level3_ServiceInteraction")
        check(prompt.ObjectText=="OLD CIRCUIT PANEL" and prompt.ActionText=="Inspect" and prompt.HoldDuration==.65,"breaker prompt authoring contract")
        check(anchor.Transparency==1 and not anchor.CanCollide and not anchor.CanTouch and not anchor.CanQuery,"invisible carrier remains intact")
        check(prompt.Enabled==not noParticipant,"participant workflow fails closed")
        root.Position=anchor.Position
        prompt.Triggered:Fire(participant)
        if noParticipant then check(breaker:GetAttribute("Level3_InteractionSerial")==nil,"disabled workflow no interaction")
        else
            check(breaker:GetAttribute("Level3_InteractionSerial")==1 and #noise==1 and noise[1].Amount==.15,"validated breaker inspection remains active")
            prompt.Triggered:Fire(participant)
            check(breaker:GetAttribute("Level3_InteractionSerial")==1,"duplicate request stays busy")
            e.runTo(13.51)
            check(prompt.ActionText=="Inspect" and breaker:GetAttribute("Level3_ServiceActive")==false,"delayed lifecycle restores prompt")
            world:SetAttribute("Level3_Generation",8)
            prompt.Triggered:Fire(participant)
            check(breaker:GetAttribute("Level3_InteractionSerial")==1,"old generation cannot activate")
        end
    end
    local signature=e.signature(world)
    local report=stable(result.Report); local placementTrace=stable(placements); local noiseTrace=stable(noise)
    result.Cleanup(); result.Cleanup(); e.runTo(20)
    check(result.Owner.Parent==nil,"repeat cleanup removes owner and delayed work")
    for _,s in ipairs(e.signals) do
        for _,connection in ipairs(s.Connections) do check(not connection.Connected,"owner connections disconnected") end
    end
    stage:Destroy(); character:Destroy()
    for _,o in ipairs(e.allocated) do check(o.Parent==nil,"authoring fixture cleans all allocated objects") end
    return {Graph=signature,Report=report,Placements=placementTrace,Noise=noiseTrace}
end

local function load(e)
 local game,workspace,task,Instance,os=e.game,e.workspace,e.task,e.Instance,e.os
--!strict
-- Blender-authored, round-owned Level 3 alcoves and additive set dressing.
-- No live place mutation: require this candidate only from the Level 3 adapter.
-- RAW imported kit front is +Z, so lookAt(position, position-front) is deliberate.
-- Apply(manifest, helper, options?) returns {Cleanup=function, Report=table}.
-- Required helper.Place(asset, cf, parent, {Collidable=bool,Scale=Vector3?}).
-- Interactions fail closed unless helper.IsParticipant/options.IsParticipant exists.

local Players = game:GetService("Players")
local Dress = {}
local V = Vector3.new
local CLEAR_HALF = 7.0
local WALL_INSET = 1.0
local MANAGER_RADIUS = 5.25

local SIZES = {
	ArcadeInvaders=V(3.30,7.19,3.34), ArcadeMaze=V(3.30,7.19,3.34),
	ArcadePlatform=V(3.30,7.19,3.34), ClawMachine=V(3.51,6.84,4.17),
	PrizeCounter=V(9.42,6.23,2.92), SupplyShelf=V(6.96,7.51,2.23),
	ChairStack=V(2.51,5.18,2.60), FoldedTables=V(4.12,6.80,1.96),
	HeliumTank=V(1.26,4.71,1.26), FlatClownCutout=V(2.66,4.45,.31),
	WorkshopBench=V(9.70,5.35,2.80), Pegboard=V(7.30,4.20,.43),
	BreakerPanel=V(2.77,5.65,.80), MopBucket=V(3.75,5.94,1.67),
	ChairRed=V(2.51,4.30,2.46), CakeTable=V(4.50,4.31,2.65),
	RoomDivider=V(8.25,8,.30),
}

-- Alcove coordinates: u=0 is the inner partition, u=18 the outside room wall;
-- v=0 is the 18-stud open entrance, v=24 is the outside rear wall.
local SERVICE = {
	BudgetArcade = {
		{"ArcadeInvaders",2.4,20.8,0,"entrance","arcade"},
		{"ArcadeMaze",6.4,20.8,0,"entrance","arcade"},
		{"ArcadePlatform",10.4,20.8,0,"entrance","arcade"},
		{"PrizeCounter",16.2,8.0,0,"inward",nil},
		{"ClawMachine",15.0,20.8,0,"entrance","claw"},
	},
	PartySupplyStore = {
		{"SupplyShelf",16.7,7.0,0,"inward",nil},
		{"SupplyShelf",16.7,17.5,0,"inward",nil},
		{"ChairStack",1.95,16.0,0,"entrance",nil},
		{"FoldedTables",1.65,6.5,0,"outward",nil},
		{"HeliumTank",4.0,21.5,0,"entrance",nil},
		{"FlatClownCutout",11.5,23.4,0,"entrance",nil},
	},
	MaintenanceWorkshop = {
		{"WorkshopBench",16.3,14.0,0,"inward",nil},
		{"Pegboard",17.65,14.0,5.0,"inward",nil},
		{"SupplyShelf",1.85,16.2,0,"outward",nil},
		{"BreakerPanel",11.0,23.4,4.55,"entrance","breaker"},
		{"MopBucket",14.0,3.8,0,"inward",nil},
		{"ChairRed",7.0,20.0,0,"entrance",nil},
	},
}

local function overlaps(a,b,padding)
	return math.abs(a.x-b.x) < a.hx+b.hx+(padding or 0)
		and math.abs(a.z-b.z) < a.hz+b.hz+(padding or 0)
end

local function safeRect(rect, room, blocked)
	local inset = WALL_INSET
	if math.abs(rect.x)+rect.hx > room.W*.5-inset+.001
		or math.abs(rect.z)+rect.hz > room.D*.5-inset+.001 then
		return false,"wall"
	end
	-- Every added collider stays outside both full-width cardinal portal lanes.
	if math.abs(rect.x)-rect.hx < CLEAR_HALF-.001
		or math.abs(rect.z)-rect.hz < CLEAR_HALF-.001 then
		return false,"portal-cross"
	end
	for _,box in ipairs(blocked) do
		if overlaps(rect,box,.35) then return false,"existing-envelope" end
	end
	return true,nil
end

function Dress.Plan(room, blocked, seed)
	assert(type(room.W)=="number" and type(room.D)=="number","Room W/D required")
	local variant=room.ServiceVariant
	if not SERVICE[variant] then return {Variant=nil, Pocket=nil, Reason="not-service-room"} end
	local order={{1,1},{-1,-1},{1,-1},{-1,1}}
	local offset=math.floor(math.abs(seed or 0))%4
	for i=1,4 do
		local signs=order[(i+offset-1)%4+1]
		local sx,sz=signs[1],signs[2]
		local pocket={sx=sx,sz=sz,x=sx*(room.W*.5-10),z=sz*(room.D*.5-13),hx=9,hz=12}
		local withPartition={x=pocket.x-sx*.45,z=pocket.z,hx=9.45,hz=12}
		local fits=safeRect(withPartition,room,blocked)
		if fits then
			pocket.xInner=room.W*.5-19
			pocket.zInner=room.D*.5-25
			return {Variant=variant,Pocket=pocket,Reason="validated-open-front-alcove"}
		end
	end
	return {Variant=variant,Pocket=nil,Reason="no-free-18x24-corner"}
end

local function footprint(part, base, padding)
	local cf=part.CFrame
	local size=part.Size
	local x=math.abs(cf.RightVector.X)*size.X*.5+math.abs(cf.UpVector.X)*size.Y*.5+math.abs(cf.LookVector.X)*size.Z*.5
	local z=math.abs(cf.RightVector.Z)*size.X*.5+math.abs(cf.UpVector.Z)*size.Y*.5+math.abs(cf.LookVector.Z)*size.Z*.5
	return {x=part.Position.X-base.X,z=part.Position.Z-base.Z,hx=x+(padding or 0),hz=z+(padding or 0)}
end

local function tagged(object,suffix)
	return object:GetAttribute("Level3_"..suffix)==true
end

local function collectBlocked(roomModel,base)
	local blocked={}
	for _,object in ipairs(roomModel:GetDescendants()) do
		if object:IsA("BasePart") then
			if tagged(object,"ManagerFurnitureNavExclusion") then
				table.insert(blocked,footprint(object,base,.1))
			elseif tagged(object,"HideTableAnchor") then
				table.insert(blocked,footprint(object,base,4))
			elseif tagged(object,"CDTableSocket") or tagged(object,"TableCollision") then
				table.insert(blocked,footprint(object,base,3))
			elseif object.CanCollide and object.Size.Y>1
				and tagged(object,"PermanentFurniture") then
				table.insert(blocked,footprint(object,base,1.5))
			end
		end
	end
	return blocked
end

local function baseFor(room,model,helper,options)
	local origin=options.WorldOrigin or helper.WorldOrigin
	if typeof(origin)=="Vector3" then return origin+V(room.X,0,room.Z) end
	for _,object in ipairs(model:GetDescendants()) do
		if object:IsA("BasePart") and string.find(object.Name,"Room Floor",1,true) then
			return V(object.Position.X,object.Position.Y+object.Size.Y*.5,object.Position.Z)
		end
	end
	error("Dressing needs helper.WorldOrigin or original room floor: "..tostring(room.Id))
end

local function validSoundId(value)
	if type(value)=="number" and value>0 then return "rbxassetid://"..tostring(math.floor(value)) end
	if type(value)=="string" and string.match(value,"^rbxassetid://%d+$") then return value end
	return nil
end

function Dress.Apply(manifest,helper,options)
	options=options or {}
	assert(type(helper)=="table" and type(helper.Place)=="function","Dressing helper.Place required")
	assert(manifest.World and manifest.World.Parent,"Dressing requires a live owned world")
	local layout=manifest.Layout
	assert(type(layout)=="table" and type(layout.Rooms)=="table","Dressing needs layout rooms")
	local owner=Instance.new("Folder")
	owner.Name="Level 3 Blender Set Dressing"
	owner:SetAttribute("Level3_DressingOwned",true)
	owner.Parent=options.Parent or manifest.World
	local report={Rooms=0,PropsPlaced=0,FullServicePockets=0,FallbackServiceRooms=0,Interactions=0,
		MissingAssets={},Skipped={},ServiceRooms={},Navigation={CenterCrossWidth=14,ManagerSweepRadius=5.25,
		PerimeterPolicy="Wall-attached service alcoves; fresh active-round pathfinding verification required"}}
	local connections={}
	local pending={}
	local sounds={}
	local tablewareMarked={}
	local alive=true
	local participantCheck=options.IsParticipant or helper.IsParticipant
	local soundIds=options.SoundIds or helper.SoundIds or {}
	local noiseCallback=options.OnNoise or helper.OnNoise
	local lastPlayerAction={}
	local world=manifest.World
	local generation=manifest.Generation
	local seed=tonumber(options.Seed or layout.ResolvedSeed) or 1
	local dressingId=tostring(generation)..":"..tostring(os.clock())

	local function later(seconds,fn)
		local thread
		thread=task.delay(seconds,function()
			pending[thread]=nil
			if alive and owner.Parent and world.Parent then fn() end
		end)
		pending[thread]=true
	end

	local function cleanup()
		if not alive then return end
		alive=false
		for _,connection in ipairs(connections) do connection:Disconnect() end
		table.clear(connections)
		for thread in pairs(pending) do pcall(task.cancel,thread) end
		table.clear(pending)
		for _,sound in ipairs(sounds) do if sound.Parent then sound:Stop() end end
		table.clear(sounds)
		table.clear(lastPlayerAction)
		for _,part in ipairs(tablewareMarked) do
			if part.Parent and part:GetAttribute("Level3_TablewareDressingOwner")==dressingId then
				part:SetAttribute("Level3_TablewarePlaced",nil)
				part:SetAttribute("Level3_TablewareDressingOwner",nil)
			end
		end
		table.clear(tablewareMarked)
		if owner.Parent then owner:Destroy() end
	end
	table.insert(connections,world.AncestryChanged:Connect(function(_,parent)
		if parent==nil then cleanup() end
	end))
	table.insert(connections,Players.PlayerRemoving:Connect(function(player)
		lastPlayerAction[player.UserId]=nil
	end))

	local function placed(asset,cf,parent,collidable,scale)
		local ok,model=pcall(helper.Place,asset,cf,parent,{Collidable=collidable==true,Scale=scale})
		if not ok or not model then
			report.MissingAssets[asset]=(report.MissingAssets[asset] or 0)+1
			return nil
		end
		model:SetAttribute("Level3_DressingOwned",true)
		model:SetAttribute("Level3_DressingAsset",asset)
		report.PropsPlaced+=1
		return model
	end

	local function carrier(parent,position,name)
		-- Invisible interaction/nav carriers are the only authored BaseParts here.
		local part=Instance.new("Part")
		part.Name=name
		part.Size=V(.10,.10,.10)
		part.CFrame=CFrame.new(position)
		part.Anchored=true
		part.Transparency=1
		part.CanCollide=false
		part.CanTouch=false
		part.CanQuery=false
		part.CastShadow=false
		part:SetAttribute("Level3_DressingOwned",true)
		part.Parent=parent
		return part
	end

	local function navBox(parent,cf,size)
		local blocker=carrier(parent,cf.Position,"Level 3 Service Furniture Nav Exclusion")
		blocker.CFrame=cf*CFrame.new(0,5,0)
		blocker.Size=V(size.X+2*MANAGER_RADIUS,10,size.Z+2*MANAGER_RADIUS)
		blocker.CanQuery=true
		blocker:SetAttribute("Level3_ManagerFurnitureNavExclusion",true)
		local modifier=Instance.new("PathfindingModifier")
		modifier.Label=options.PathLabel or "Level3ManagerFurniture"
		modifier.PassThrough=false
		modifier.Parent=blocker
	end

	local function interactive(model,cf,kind,asset)
		if not model then return end
		local localPosition=if kind=="breaker" then V(.98,6.70,.42)
			elseif kind=="claw" then V(.52,2.65,1.94) else V(0,4.2,1.8)
		-- Breaker asset base is already mounted high; inspect at its latch +2.15.
		local anchor=carrier(model,cf:PointToWorldSpace(localPosition),"Interaction Origin")
		local prompt=Instance.new("ProximityPrompt")
		prompt.Name="Level3_ServiceInteraction"
		prompt.ObjectText=if kind=="breaker" then "OLD CIRCUIT PANEL" elseif kind=="claw" then "PRIZE CLAW" else "ARCADE CABINET"
		prompt.ActionText=if kind=="breaker" then "Inspect" else "Try a credit"
		prompt.HoldDuration=if kind=="breaker" then .65 else .35
		prompt.MaxActivationDistance=8
		prompt.RequiresLineOfSight=true
		prompt.Enabled=type(participantCheck)=="function"
		prompt.Parent=anchor
		local source=validSoundId(soundIds[if kind=="breaker" then "BreakerInspect" elseif kind=="claw" then "ClawMotor" else asset])
		local sound
		if source then
			sound=Instance.new("Sound")
			sound.Name="Level 3 Original Service Sound"
			sound.SoundId=source
			sound.Volume=if kind=="breaker" then .15 else .21
			sound.Looped=false
			sound.RollOffMode=Enum.RollOffMode.InverseTapered
			sound.RollOffMinDistance=4
			sound.RollOffMaxDistance=30
			sound.Parent=anchor
			table.insert(sounds,sound)
		end
		local busy=false
		local machineCooldown=0
		table.insert(connections,prompt.Triggered:Connect(function(player)
			if not alive or not model.Parent or not world.Parent or busy or not prompt.Enabled
				or player.Parent~=Players or workspace:GetAttribute("SelectedLevel")~=3
				or workspace:GetAttribute("RoundActive")~=true then return end
			if generation~=nil and world:GetAttribute("Level3_Generation")~=nil
				and world:GetAttribute("Level3_Generation")~=generation then return end
			local ok,isParticipant=pcall(participantCheck,player)
			if not ok or isParticipant~=true then return end
			local character=player.Character
			local humanoid=character and character:FindFirstChildOfClass("Humanoid")
			local root=character and character:FindFirstChild("HumanoidRootPart")
			if not humanoid or humanoid.Health<=0 or not root or not root:IsA("BasePart")
				or (root.Position-anchor.Position).Magnitude>10 then return end
			local now=os.clock()
			if now-machineCooldown<2 or now-(lastPlayerAction[player.UserId] or -math.huge)<1 then return end
			machineCooldown=now
			lastPlayerAction[player.UserId]=now
			busy=true
			model:SetAttribute("Level3_LastUsedBy",player.UserId)
			model:SetAttribute("Level3_InteractionSerial",(model:GetAttribute("Level3_InteractionSerial") or 0)+1)
			model:SetAttribute("Level3_ServiceActive",true)
			prompt.ActionText=if kind=="breaker" then "LABEL: PARTY WING / SPARE" elseif kind=="claw" then "The claw is stuck..." else "INSERT COIN — credit rejected"
			if sound then sound:Play() end
			if type(noiseCallback)=="function" then pcall(noiseCallback,player,anchor.Position,if kind=="breaker" then .15 else .4) end
			later(if kind=="breaker" then 3.5 else 5,function()
				if model.Parent and prompt.Parent then
					busy=false
					model:SetAttribute("Level3_ServiceActive",false)
					prompt.ActionText=if kind=="breaker" then "Inspect" else "Try a credit"
					if sound then sound:Stop() end
				end
			end)
		end))
		report.Interactions+=1
	end

	local function faceCF(position,front)
		return CFrame.lookAt(position,position-front)
	end

	for roomIndex,room in ipairs(layout.Rooms) do
		local roomModel=manifest.Rooms[room.Id]
		if not roomModel or room.Id=="Arrival" or room.Kind=="Exit" then continue end
		report.Rooms+=1
		local base=baseFor(room,roomModel,helper,options)
		local group=Instance.new("Folder")
		group.Name=tostring(room.Id).." | Blender Dressing"
		group:SetAttribute("Level3_RoomId",room.Id)
		group.Parent=owner
		local blocked=collectBlocked(roomModel,base)
		local plan=Dress.Plan(room,blocked,room.ServicePocketSeed or seed+roomIndex*997)
		local height=tonumber(room.H) or 12

		-- Small table dressing rides the existing authoritative tabletop; never
		-- create a new table, hide anchor, pickup socket or objective prompt here.
		for _,object in ipairs(roomModel:GetDescendants()) do
			if object:IsA("BasePart") and tagged(object,"TableCollision")
				and object:GetAttribute("Level3_TablewarePlaced")~=true then
				local cf=object.CFrame*CFrame.new(3.3,math.max(object.Size.Y*.5, .44)+.02,0)
				if placed("Tableware",cf,group,false,nil) then
					object:SetAttribute("Level3_TablewarePlaced",true)
					object:SetAttribute("Level3_TablewareDressingOwner",dressingId)
					table.insert(tablewareMarked,object)
				end
			end
		end
		-- Fabric/plastic decoration remains noncolliding, outside portal centres.
		local sx=if roomIndex%2==0 then 1 else -1
		local sz=if roomIndex%3==0 then 1 else -1
		placed("BalloonCluster",CFrame.new(base+V(sx*(room.W*.5-3.1),0,sz*(room.D*.5-3.0))),group,false,nil)
		local bannerPos=base+V(-sx*(room.W*.5-8.0),math.min(8.1,height-2.1),sz*(room.D*.5-1.1))
		placed("BirthdayGarland",faceCF(bannerPos,V(0,0,-sz)),group,false,nil)

		if plan.Pocket then
			local p=plan.Pocket
			report.FullServicePockets+=1
			local record={RoomId=room.Id,Variant=plan.Variant,Mode=plan.Reason,Props=0,Width=18,Depth=24,
				Corner={p.sx,p.sz},ExclusionCount=#blocked}
			table.insert(report.ServiceRooms,record)
			local function point(u,v,y)
				return base+V(p.sx*(p.xInner+u),y or 0,p.sz*(p.zInner+v))
			end
			-- Existing outside walls + one authored modular inner wall make a
			-- three-sided service room. The entire 18-stud front stays open.
			local partitionPosition=point(-.15,12,0)
			placed("WallService",faceCF(partitionPosition,V(p.sx,0,0)),group,true,V(3,height/12,1))
			placed("FloorService",CFrame.new(point(9,12,.025)),group,false,V(18/80,1,24/64))
			for _,entry in ipairs(SERVICE[plan.Variant]) do
				local asset,u,v,y,facing,interaction=table.unpack(entry)
				local front=if facing=="inward" then V(-p.sx,0,0)
					elseif facing=="outward" then V(p.sx,0,0) else V(0,0,-p.sz)
				local cf=faceCF(point(u,v,y),front)
				local isWallObject=asset=="Pegboard" or asset=="BreakerPanel" or asset=="FlatClownCutout"
				local model=placed(asset,cf,group,not isWallObject,nil)
				if model then
					record.Props+=1
					if not isWallObject then navBox(model,cf,SIZES[asset]) end
					if interaction then interactive(model,cf,interaction,asset) end
				end
			end
			if plan.Variant=="MaintenanceWorkshop" then
				placed("WallClock",faceCF(point(17.8,6.5,7.2),V(-p.sx,0,0)),group,false,nil)
			end
		elseif plan.Variant then
			-- Concurrency/seed-safe fallback: no colliding object is forced over an
			-- authoritative table/hide/CD envelope just to make an art target fit.
			report.FallbackServiceRooms+=1
			local record={RoomId=room.Id,Variant=plan.Variant,Mode="scattered-open-alcove",Props=0,
				Reason=plan.Reason,ExclusionCount=#blocked}
			table.insert(report.ServiceRooms,record)
			local assets=if plan.Variant=="BudgetArcade" then {"ArcadeInvaders","ArcadeMaze","ArcadePlatform"}
				elseif plan.Variant=="PartySupplyStore" then {"SupplyShelf","ChairStack","HeliumTank","FoldedTables"}
				else {"WorkshopBench","MopBucket","SupplyShelf"}
			for _,asset in ipairs(assets) do
				local size=SIZES[asset]
				local found=false
				for _,signs in ipairs({{sx,sz},{-sx,-sz},{sx,-sz},{-sx,sz}}) do
					if found then break end
					for step=0,8 do
						local x=signs[1]*(room.W*.5-1.4-size.X*.5-step*1.7)
						local z=signs[2]*(room.D*.5-1.4-size.Z*.5)
						local rect={x=x,z=z,hx=size.X*.5,hz=size.Z*.5}
						if safeRect(rect,room,blocked) then
							local cf=faceCF(base+V(x,0,z),V(0,0,-signs[2]))
							local model=placed(asset,cf,group,true,nil)
							if model then
								navBox(model,cf,size)
								table.insert(blocked,rect)
								record.Props+=1
								if string.sub(asset,1,6)=="Arcade" then interactive(model,cf,"arcade",asset) end
							end
							found=true
							break
						end
					end
				end
				if not found then table.insert(report.Skipped,{RoomId=room.Id,Asset=asset,Reason="protected-space"}) end
			end
		end
		if roomIndex%4==0 then task.wait() end
		if not alive then break end
	end
	owner:SetAttribute("Level3_DressingPropCount",report.PropsPlaced)
	owner:SetAttribute("Level3_DressingServicePocketCount",report.FullServicePockets)
	owner:SetAttribute("Level3_DressingInteractionCount",report.Interactions)
	return {Cleanup=cleanup,Report=report,Owner=owner}
end

return Dress

end

-- Execute the unchanged actual cleanup failure behavior, then independently
-- clean only fixture-owned tables. This does not certify or fix live cleanup.
local function cleanupFaultFixture(load,kind)
 local e=dressingEngine();local api=load(e)
 local stage=e.new("Folder","Owned Fault Stage")
 local world=e.new("Model","Fault World",stage)
 world:SetAttribute("Level3_Generation",7)
 local result=api.Apply({World=world,Generation=7,Rooms={},Layout={Rooms={},ResolvedSeed=1}},
  {Place=function()error("No room should request an asset",0)end},{})
 local owner=result.Owner
 local connection=world.AncestryChanged.Connections[1]
 local disconnect=connection.Disconnect
 local destroy=owner.Destroy
 if kind=="disconnect" then
  connection.Disconnect=function()error("controlled disconnect failure",0)end
 else
  rawset(owner,"Destroy",function()error("controlled owner destroy failure",0)end)
 end
 local ok,err=pcall(result.Cleanup)
 check(not ok and err=="controlled "..(kind=="disconnect" and "disconnect" or "owner destroy").." failure",
  "actual cleanup failure propagates unchanged "..kind)
 check(owner.Parent==world,"failed cleanup leaves current owner present "..kind)
 local retry=pcall(result.Cleanup)
 check(retry and owner.Parent==world,"existing alive=false cleanup retry is a no-op "..kind)
 local flags={}
 for _,s in e.signals do for _,c in s.Connections do flags[#flags+1]=c.Connected end end
 local before={Fault=kind,Error=err,OwnerPresent=owner.Parent==world,Connections=flags,Report=stable(result.Report)}
 connection.Disconnect=disconnect;rawset(owner,"Destroy",nil)
 -- Separate harness ownership cleanup after the failure; all objects are fake.
 for _,s in e.signals do for _,c in s.Connections do c:Disconnect() end end
 stage:Destroy()
 for _,s in e.signals do for _,c in s.Connections do check(not c.Connected,"fault fixture disconnects own connections")end end
 for _,o in e.allocated do check(o.Parent==nil,"fault fixture cleans own objects")end
 return before
end

local rows={Plan=planFixture(load),Dressing={},CleanupFailures={}}
for _,scenario in {{false,false,false},{true,false,false},{false,true,false},{false,false,true}} do
 rows.Dressing[#rows.Dressing+1]=dressingFixture(load,table.unpack(scenario))
end
for _,kind in {"disconnect","destroy"} do rows.CleanupFailures[#rows.CleanupFailures+1]=cleanupFaultFixture(load,kind)end
return {checks=checks,signature=stable(rows)}
end
