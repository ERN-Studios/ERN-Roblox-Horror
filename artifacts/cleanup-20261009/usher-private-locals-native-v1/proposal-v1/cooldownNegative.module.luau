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
-- Actual targeting/think/Stop are inserted verbatim; unrelated private systems
-- are controlled boundaries, not a native navigation/capture/physics claim.
local numericVectorMultiply=vec.__mul
vec.__mul=function(a,b)
    if type(a)=="table" and type(b)=="table" then return Vector3.new(a.X*b.X,a.Y*b.Y,a.Z*b.Z) end
    return numericVectorMultiply(a,b)
end
function vec:Lerp(other,alpha) return self+(other-self)*alpha end
local function actualPort(e)
    local Players=e.Players
    local HttpService={GenerateGUID=function() e.guidCalls+=1; return "FIXTURE-GUID" end}
    local Usher={}
    local C={ThinkSeconds=.1,StunSeconds=.3,StunCooldownSeconds=2,Height=8,SightRange=40,HearingRange=80,
        AttackRange=4,ShushSeconds=1,HopMinPlayerDistance=20,HopMaxTargetDistance=80}
    local BLINK_HOP_MIN_DISTANCE=12
    local session = 0
local manifest, objectives, lights
local proxy, root, head
local connections = {}
local nodes, grid = {}, {}
local motionRemote, clientEvent, stateFolder, jumpscare

local active, finale = false, false
local current = nil               -- node index the Usher stands on / last passed
local position = Vector3.zero     -- feet position
local facing = Vector3.new(0, 0, -1)
local path, pathIndex = nil, 1
local state = "Dormant"
local target = nil
local lastKnown = nil
local nextHopAt, nextReplanAt = 0, 0
local beamTime, stunCooldownUntil = 0, 0
local beamers = {}
local shush = nil                 -- { Player, Character, EndsAt }
local capture = nil               -- leased capture record
local captureSerial = 0
local captureGeneration = HttpService:GenerateGUID(false)
local hidden = true               -- vanished (between hops / dormant)
local hopping = false             -- a hop is in flight (landing scheduled)
local lastMotion = 0
local searchUntil = 0


    local function now() return e.clock end
    local function bodyOf(player) return player.Character,{},player.Root end
    local function huntable(player) return player.Huntable end
    local function rayClear(_,_) return e.clearRay end
    local function eyes() return position+Vector3.new(0,C.Height-.6,0) end
    local function validRound() return e.valid end
    local function tickBatteries(elapsed) e.batteryTicks[#e.batteryTicks+1]=elapsed end
    local function beamedBy() return e.beam end
    local function nodeDark(_) return e.dark end
    local function pickHopNode(_,_,_) return e.hopNode end
    local function hopTo(index,reason,minD)
        e.hops[#e.hops+1]={Index=index,Reason=reason,Min=minD}
        nextHopAt=e.clock+1
    end
    local function goTowards(pos) e.paths[#e.paths+1]=pos; return e.pathAvailable end
    local function syncProxy(force) e.syncs[#e.syncs+1]=force end
    local function startCapture(player) e.captures[#e.captures+1]=player.UserId end
    local function finishCapture(record,cancelled) e.finish[#e.finish+1]={Player=record.Player.UserId,Cancelled=cancelled} end
    local function onZoneChanged() end
    local NoiseRegistry={Prune=function() e.prunes+=1 end,GetBest=function() return e.noise end}
    local function setState(name)
	if state == name then return end
	state = name
	if stateFolder then stateFolder:SetAttribute("Level4_UsherState", name) end
	if proxy then proxy:SetAttribute("State", name) end
end


    local function setBeamers(list)
	local set = {}
	for _, p in ipairs(list) do set[p] = true end
	for p in pairs(beamers) do
		if not set[p] and p.Parent == Players then p:SetAttribute("Level4_BeamingUsher", nil) end
	end
	for p in pairs(set) do
		if not beamers[p] then p:SetAttribute("Level4_BeamingUsher", true) end
	end
	beamers = set
end


    local function chooseTarget()
	-- 1. the breaker holder is always wanted
	local holder = objectives.BreakerHolder and objectives.BreakerHolder()
	if holder and huntable(holder) then return holder, "holder" end
	-- 2. someone it can see (in its sight range, line of sight)
	local best, bestD
	for _, player in ipairs(Players:GetPlayers()) do
		if huntable(player) then
			local _, _, r = bodyOf(player)
			local d = (r.Position - position).Magnitude
			local range = finale and C.SightRange * 1.6 or C.SightRange
			if d <= range and (not bestD or d < bestD) and rayClear(eyes(), r.Position + Vector3.new(0, 1.5, 0)) then
				best, bestD = player, d
			end
		end
	end
	if best then return best, "sight" end
	-- 3. noise
	NoiseRegistry.Prune()
	local noise = NoiseRegistry.GetBest(position, C.HearingRange)
	if noise then
		local source = noise.SourcePlayer
		if source and huntable(source) then return source, "noise" end
		lastKnown = noise.pos
		return nil, "noise"
	end
	-- 4. finale: it knows where everyone is
	if finale then
		for _, player in ipairs(Players:GetPlayers()) do
			if huntable(player) then
				local _, _, r = bodyOf(player)
				local d = (r.Position - position).Magnitude
				if not bestD or d < bestD then best, bestD = player, d end
			end
		end
		if best then return best, "finale" end
	end
	return nil, nil
end


    local function think(elapsed)
	local t = now()
	tickBatteries(elapsed or C.ThinkSeconds)
	if not validRound() or hidden then setBeamers({}) end
	if not validRound() then
		path = nil
		if shush then shush = nil end
		return
	end
	if hidden then
		-- (re)appear: only somewhere dark and away from players
		if t >= nextHopAt and not hopping then
			local r = target and select(3, bodyOf(target))
			local spot = pickHopNode(r and r.Position, C.HopMinPlayerDistance, C.HopMaxTargetDistance)
				or pickHopNode(nil, C.HopMinPlayerDistance, math.huge)
			if spot then hopTo(spot, "appear", C.HopMinPlayerDistance) else nextHopAt = t + 1 end
		end
		return
	end
	-- lit: vanish at once
	if current and not nodeDark(current) then
		local r = target and select(3, bodyOf(target))
		local spot = pickHopNode(r and r.Position or position, BLINK_HOP_MIN_DISTANCE, 90)
			or pickHopNode(nil, C.HopMinPlayerDistance, math.huge)
		hidden = true
		setBeamers({})
		if spot then hopTo(spot, "lit", BLINK_HOP_MIN_DISTANCE) else setState("Hop"); syncProxy(true); nextHopAt = t + 1 end
		shush = nil
		return
	end
	-- flashlight
	local beam = (t >= stunCooldownUntil) and beamedBy() or {}
	setBeamers(beam)
	if #beam > 0 then
		beamTime += C.ThinkSeconds
		shush = nil
		path = nil
		setState("Stunned")
		if beamTime >= C.StunSeconds then
			beamTime = 0
			stunCooldownUntil = 0
			setBeamers({})
			local away = pickHopNode(nil, 50, math.huge)
			if away then hopTo(away, "stunned", 50) end
			if clientEvent then clientEvent:FireAllClients({ Type = "Stun", By = beam[1].UserId }) end
		end
		return
	end
	beamTime = math.max(0, beamTime - C.ThinkSeconds * 0.5)
	-- the windup
	if shush then
		local _, _, r = bodyOf(shush.Player)
		if not r or not huntable(shush.Player) or (r.Position - position).Magnitude > C.AttackRange + 3
			or not rayClear(eyes(), r.Position) then
			shush = nil
			setState("Stalk")
		elseif t >= shush.EndsAt then
			local player = shush.Player
			shush = nil
			startCapture(player)
			return
		else
			facing = (r.Position - position) * Vector3.new(1, 0, 1)
			return
		end
	end
	if capture then return end
	-- targets
	local newTarget, reason = chooseTarget()
	if newTarget ~= target then
		target = newTarget
		nextReplanAt = 0
	end
	if stateFolder then stateFolder:SetAttribute("Level4_UsherTarget", target and target.UserId or 0) end
	if target then
		local _, _, r = bodyOf(target)
		lastKnown = r.Position
		searchUntil = t + 6
		local d = (r.Position - position).Magnitude
		-- attack
		if d <= C.AttackRange and rayClear(eyes(), r.Position) then
			shush = { Player = target, EndsAt = t + C.ShushSeconds }
			path = nil
			setState("Shush")
			facing = (r.Position - position) * Vector3.new(1, 0, 1)
			if clientEvent then clientEvent:FireAllClients({ Type = "Shush", Player = target.UserId, Position = eyes() }) end
			if manifest.Audio.Shush and manifest.Audio.Shush ~= 0 then
				local s = Instance.new("Sound")
				s.SoundId = "rbxassetid://" .. manifest.Audio.Shush
				s.Volume = 1.4
				s.RollOffMinDistance = 6
				s.RollOffMaxDistance = 60
				s.Parent = head
				s:Play()
				task.delay(4, function() s:Destroy() end)
			end
			return
		end
		setState((reason == "sight" or reason == "holder" or finale) and "Chase" or "Stalk")
		-- too far, or no dark way there: hop closer when allowed
		if t >= nextReplanAt then
			nextReplanAt = t + 0.5
			local ok = d <= C.HopMaxTargetDistance * 1.6 and goTowards(r.Position)
			if proxy then proxy:SetAttribute("DbgHopIn", math.floor(nextHopAt - t)) end
			if not ok and t >= nextHopAt then
				local spot = pickHopNode(r.Position, C.HopMinPlayerDistance, C.HopMaxTargetDistance)
				if spot then hopTo(spot, "close in", C.HopMinPlayerDistance); return end
			end
			if not ok then
				-- wait at the edge of the dark, facing them
				path = nil
				setState("Wait")
				facing = (r.Position - position) * Vector3.new(1, 0, 1)
			end
		end
		return
	end
	-- no target: investigate the last noise, then wander
	if lastKnown and t < searchUntil + 4 then
		setState("Search")
		if t >= nextReplanAt then
			nextReplanAt = t + 1
			if (lastKnown - position).Magnitude < 6 then lastKnown = nil else goTowards(lastKnown) end
		end
		return
	end
	setState("Stalk")
	if (not path or pathIndex > #path) and t >= nextReplanAt then
		nextReplanAt = t + 2
		-- wander toward the living, through the dark
		local living = objectives.LivingParticipants()
		local focus = position
		if #living > 0 then
			local _, _, r = bodyOf(living[math.random(1, #living)])
			if r then focus = r.Position end
		end
		if t >= nextHopAt and math.random() < 0.35 then
			local spot = pickHopNode(focus, C.HopMinPlayerDistance, C.HopMaxTargetDistance)
			if spot then hopTo(spot, "wander", C.HopMinPlayerDistance); return end
		end
		local spot = pickHopNode(position:Lerp(focus, 0.5), 10, 60)
		if spot then goTowards(nodes[spot].Pos) end
	end
end


    function Usher.Stop()
	session += 1
	active, finale, hopping = false, false, false
	if capture then finishCapture(capture, true) end
	capture, shush, target, path, lastKnown = nil, nil, nil, nil, nil
	for _, c in ipairs(connections) do c:Disconnect() end
	table.clear(connections)
	setBeamers({})
	if lights and lights.OnZoneChanged == onZoneChanged then lights.OnZoneChanged = nil end
	if proxy then proxy:Destroy() end
	proxy, root, head = nil, nil, nil
	hidden = true
	state = "Dormant"
	if stateFolder then
		stateFolder:SetAttribute("Level4_UsherActive", false)
		stateFolder:SetAttribute("Level4_UsherState", "Dormant")
		stateFolder:SetAttribute("Level4_UsherTarget", 0)
	end
	beamTime, stunCooldownUntil, nextHopAt = 0, 0, 0
end


    local function snapshot()
        return {State=state,Target=target and target.UserId,LastKnown=lastKnown,SearchUntil=searchUntil,
            NextHopAt=nextHopAt,NextReplanAt=nextReplanAt,BeamTime=beamTime,StunCooldownUntil=stunCooldownUntil,
            Hidden=hidden,Path=path,PathIndex=pathIndex,Shush=shush and {Player=shush.Player.UserId,EndsAt=shush.EndsAt},
            StateAttributes=stateFolder:GetAttributes(),PlayerAttributes=e.player:GetAttributes(),Events=e.events,Hops=e.hops,
            Paths=e.paths,BatteryTicks=e.batteryTicks,Prunes=e.prunes,Finish=e.finish,GuidCalls=e.guidCalls}
    end
    local function setMode(mode)
        target=nil; lastKnown=nil; searchUntil=0; nextHopAt=0; nextReplanAt=0
        hidden=false; active=true; finale=false; current=1; state="Stalk"; path=nil; shush=nil; capture=nil
        position=Vector3.zero; beamTime=0; stunCooldownUntil=0
        e.beam={}; e.noise=nil; e.valid=true; e.dark=true; e.clearRay=false; e.hopNode=nil; e.pathAvailable=true
        e.player.Huntable=true; e.player.Root.Position=Vector3.new(20,0,0)
        objectives={BreakerHolder=function() return mode=="holder" and e.player or nil end,LivingParticipants=function() return {} end}
        if mode=="sight" then e.clearRay=true end
        if mode=="noise" then e.noise={SourcePlayer=e.player,pos=Vector3.new(25,0,0)} end
        if mode=="finale" then finale=true; e.player.Root.Position=Vector3.new(100,0,0) end
    end
    stateFolder=e.new("Folder","Usher State")
    clientEvent={FireAllClients=function(_,payload) e.events[#e.events+1]=payload end}
    manifest={Audio={Shush=0}}
    lights={OnZoneChanged=onZoneChanged}
    local rows={}
    for _,mode in ipairs({"holder","sight","noise","finale"}) do
        setMode(mode); e.clock=10
        think(.17)
        check(target==e.player,"actual chooseTarget selects "..mode)
        check(state==(mode=="noise" and "Stalk" or "Chase"),"reason still controls target mode "..mode)
        rows[#rows+1]=snapshot()
    end
    setMode("none"); e.player.Huntable=false; e.noise={pos=Vector3.new(30,0,0)}
    e.clock=20; searchUntil=20; think(.1)
    check(target==nil and state=="Search" and lastKnown.X==30,"anonymous noise remains search target")
    rows[#rows+1]=snapshot()
    setMode("sight"); e.player.Root.Position=Vector3.new(2,0,0); e.clock=30
    think(.1); check(state=="Shush" and shush.Player==e.player,"close target enters windup")
    e.clock=30.5; think(.1); check(#e.captures==0,"windup does not capture early")
    e.clock=31.1; think(.1); check(#e.captures==1,"windup reaches existing capture boundary")
    rows[#rows+1]=snapshot()
    setMode("holder"); e.clock=40; e.beam={e.player}; e.hopNode=7
    think(.1); think(.1)
    check(state=="Stunned" and e.player:GetAttribute("Level4_BeamingUsher")==true,"flashlight freeze and authored beamer attribute")
    think(.1)
    check(beamTime==0 and stunCooldownUntil==42,"held stun keeps existing cooldown")
    check(e.hops[#e.hops].Reason=="stunned" and e.hops[#e.hops].Min==50,"stun retreat retains 50-stud boundary")
    check(e.player:GetAttribute("Level4_BeamingUsher")==nil and e.events[#e.events].Type=="Stun","beamer cleanup and Stun payload")
    e.clock=40.1; think(.1)
    check(state=="Chase" and beamTime==0,"cooldown suppresses repeated stun")
    rows[#rows+1]=snapshot()
    e.clock=43; e.beam={e.player}; think(.1)
    check(state=="Stunned","stun becomes eligible after cooldown")
    e.valid=false; think(.1)
    check(path==nil and e.player:GetAttribute("Level4_BeamingUsher")==nil,"invalid round clears beam/path")
    proxy=e.new("Model","Usher Proxy"); root=e.new("Part","Root",proxy); head=e.new("Part","Head",proxy)
    local disconnected=0
    connections={{Disconnect=function() disconnected+=1 end},{Disconnect=function() disconnected+=1 end}}
    capture={Player=e.player}
    Usher.Stop()
    check(state=="Dormant" and hidden and not active and not finale and beamTime==0 and stunCooldownUntil==0 and nextHopAt==0,"Stop resets only active lifecycle state")
    check(target==nil and path==nil and capture==nil and #connections==0 and disconnected==2,"Stop clears active targets/capture/connections")
    check(lights.OnZoneChanged==nil and proxy==nil and e.finish[#e.finish].Cancelled,"Stop removes hook/proxy and cancels capture at boundary")
    rows[#rows+1]=snapshot()
    Usher.Stop(); check(#connections==0,"Stop reentry safe")

    -- Actual Stop boundaries fail once; retry is the same actual function.
    for _,kind in {"capture","disconnect","proxy"} do
        setMode("holder");e.clock=80
        target=e.player;path={Vector3.new(1,0,1)};beamTime=.2;stunCooldownUntil=99;nextHopAt=120
        setBeamers({e.player})
        proxy=e.new("Model","Fault Usher Proxy");root=e.new("Part","Fault Root",proxy);head=e.new("Part","Fault Head",proxy)
        lights={OnZoneChanged=onZoneChanged};capture={Player=e.player}
        local injected=true;local disconnected=0;local priorFinish=#e.finish;local oldFinish=finishCapture
        finishCapture=function(record,cancelled)
            oldFinish(record,cancelled)
            if kind=="capture" and injected then error("controlled capture finish failure",0)end
        end
        connections={{Disconnect=function()
            disconnected+=1
            if kind=="disconnect" and injected then error("controlled connection failure",0)end
        end},{Disconnect=function()disconnected+=1 end}}
        if kind=="proxy" then rawset(proxy,"Destroy",function()error("controlled proxy destroy failure",0)end)end
        local ownedProxy=proxy;local originalSession=session
        local ok,err=pcall(Usher.Stop)
        local expected=kind=="capture" and "controlled capture finish failure" or kind=="disconnect" and "controlled connection failure" or "controlled proxy destroy failure"
        check(not ok and err==expected,"actual Stop failure propagates unchanged "..kind)
        check(not active and not finale and not hopping and session==originalSession+1,"failed Stop still invalidates active/session "..kind)
        check(proxy==ownedProxy and not ownedProxy.Destroyed,"failed Stop preserves current proxy until retry "..kind)
        if kind=="capture" then
            check(capture~=nil and disconnected==0,"capture error stops before capture/connection clear")
        elseif kind=="disconnect" then
            check(capture==nil and #connections==2 and disconnected==1,"disconnect error preserves remaining connection list")
        else
            check(capture==nil and #connections==0 and disconnected==2 and lights.OnZoneChanged==nil,"proxy error occurs after prior cleanup")
        end
        rows[#rows+1]={Failure=kind,Error=err,State=snapshot(),Session=session,Disconnected=disconnected}
        injected=false;rawset(ownedProxy,"Destroy",nil)
        Usher.Stop();finishCapture=oldFinish
        check(session==originalSession+2 and not active and state=="Dormant" and hidden,"same Stop retries and reaches dormant "..kind)
        check(capture==nil and target==nil and path==nil and proxy==nil and #connections==0,"retry clears active capture/target/proxy/connections "..kind)
        check(beamTime==0 and stunCooldownUntil==0 and nextHopAt==0 and e.player:GetAttribute("Level4_BeamingUsher")==nil,"retry clears active cooldown/beamer fields "..kind)
        check(disconnected==(kind=="disconnect" and 3 or 2),"retry disconnect ordering retained "..kind)
        check(#e.finish==priorFinish+(kind=="capture" and 2 or 1),"same capture finish retry boundary retained "..kind)
        rows[#rows+1]={Retried=kind,State=snapshot(),Session=session,Disconnected=disconnected}
        Usher.Stop();check(session==originalSession+3 and proxy==nil and #connections==0,"Stop reentry remains idempotent for owned resources "..kind)
    end
    stateFolder:Destroy()
    return rows
end

local function usherFixture(port)
    local e=dressingEngine()
    e.guidCalls=0; e.batteryTicks={}; e.hops={}; e.paths={}; e.syncs={}; e.captures={}; e.finish={}; e.prunes=0
    e.player=e.new("Player","Fixture Player")
    e.Players._children={}
    e.player.UserId=71; e.player.Parent=e.Players
    function e.Players:GetPlayers() return {e.player} end
    e.player.Root=e.new("Part","Player Root")
    local rows=port(e)
    e.player.Parent=nil; e.player.Root:Destroy(); e.player:Destroy()
    for _,o in ipairs(e.allocated) do check(o.Parent==nil,"Usher fixture cleans allocated objects") end
    return rows
end

local rows=usherFixture(actualPort)
return {checks=checks,signature=stable(rows)}
end
