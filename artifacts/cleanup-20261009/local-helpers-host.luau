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
