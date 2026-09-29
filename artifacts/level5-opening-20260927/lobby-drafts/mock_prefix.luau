-- Offline geometry and ownership harness. This does not simulate rendering.
local Builder={}
local allParts={}
local assertions=0
local function check(ok,message) assertions+=1;assert(ok,message) end
local vm={};vm.__index=function(o,k) if k=="Magnitude" then return math.sqrt(o.X*o.X+o.Y*o.Y+o.Z*o.Z) end;return vm[k] end
local function vec(x,y,z) return setmetatable({X=x,Y=y,Z=z},vm) end
vm.__add=function(a,b) return vec(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
vm.__sub=function(a,b) return vec(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
vm.__mul=function(a,b) if type(a)=="number" then return vec(a*b.X,a*b.Y,a*b.Z) end;return vec(a.X*b,a.Y*b,a.Z*b) end
vm.__div=function(a,b) return vec(a.X/b,a.Y/b,a.Z/b) end
function vm:Dot(b) return self.X*b.X+self.Y*b.Y+self.Z*b.Z end
function vm:Cross(b) return vec(self.Y*b.Z-self.Z*b.Y,self.Z*b.X-self.X*b.Z,self.X*b.Y-self.Y*b.X) end
Vector3={new=vec}
local cm={};cm.__index=cm
local function cf(p,x,y,z) return setmetatable({Position=p,x=x or vec(1,0,0),y=y or vec(0,1,0),z=z or vec(0,0,1)},cm) end
local function rotate(c,p) return c.x*p.X+c.y*p.Y+c.z*p.Z end
cm.__mul=function(a,b) return cf(a.Position+rotate(a,b.Position),rotate(a,b.x),rotate(a,b.y),rotate(a,b.z)) end
CFrame={new=function(x,y,z) return cf(type(x)=="table" and x or vec(x or 0,y or 0,z or 0)) end,
    lookAt=function(p,t) local z=p-t;z=z/math.sqrt(z:Dot(z));local y=vec(0,1,0);return cf(p,y:Cross(z),y,z) end}
Color3={new=function(r,g,b) return {R=r,G=g,B=b} end,fromRGB=function(r,g,b) return {R=r/255,G=g/255,B=b/255} end}
Enum={Material={},NormalId={},PartType={}}
for _,n in ipairs({"Plaster","WoodPlanks","Wood","Fabric","Metal","Glass","SmoothPlastic","Neon"}) do Enum.Material[n]=n end
for _,n in ipairs({"Right","Left","Top","Bottom","Front","Back"}) do Enum.NormalId[n]=n end
local om={}
local methods={}
om.__index=function(o,k) return methods[k] or o.p[k] end
om.__newindex=function(o,k,v)
    if k=="Parent" then
        local old=o.p.Parent
        if old then local i=table.find(old.children,o);if i then table.remove(old.children,i) end end
        if v then table.insert(v.children,o) end
    end
    o.p[k]=v
    if k=="CFrame" then o.p.Position=v.Position end
end
function methods:IsA(c) return c==self.class or (c=="BasePart" and self.class=="Part") or (c=="Light" and (self.class=="PointLight" or self.class=="SurfaceLight")) end
function methods:SetAttribute(k,v) self.attributes[k]=v end
function methods:GetAttribute(k) return self.attributes[k] end
function methods:GetChildren() return table.clone(self.children) end
function methods:FindFirstChild(n,recursive)
    for _,c in ipairs(self.children) do if c.Name==n then return c end end
    if recursive then for _,c in ipairs(self.children) do local found=c:FindFirstChild(n,true);if found then return found end end end
end
function methods:Destroy() for _,c in ipairs(self:GetChildren()) do c:Destroy() end;self.Parent=nil;self.destroyed=true end
Instance={new=function(class) return setmetatable({class=class,p={},children={},attributes={}},om) end}
local materials=Instance.new("Folder")
game={GetService=function(_,name) assert(name=="MaterialService");return materials end}
local function clearLobbyConcreteTextures(part)
    for _,c in ipairs(part:GetChildren()) do if c:IsA("Texture") and c.Name=="LobbyConcreteTexture" then c:Destroy() end end
end
local function addLobbyThemeTexture(p,name,id,faces,tile)
    clearLobbyConcreteTextures(p)
    for _,face in ipairs(faces) do local t=Instance.new("Texture");t.Name=name;t.Texture=id;t.Face=face;t.Parent=p end
end
local function makeLobbyThemePart(parent,level,name,frame,size,tint,material)
    local p=Instance.new("Part");p.Name=name;p.CFrame=frame;p.Size=size;p.Color=tint;p.Material=material
    p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;p:SetAttribute("LobbyBayDecorLevel",level);p.Parent=parent
    table.insert(allParts,p);return p
end
