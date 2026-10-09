-- Offline policy/lifecycle contracts against an event-capable Instance stand-in.
-- This is not Roblox replication, rendering, streaming or gameplay verification.
local Budget = require("./SceneEffectBudget.ModuleScript")
local Selector = require("./effect_selector.ModuleScript")
local checks = 0
local function check(condition, message)
	checks += 1
	assert(condition, message)
end
local function signal()
	local self = {listeners = {}}
	function self:Connect(fn)
		local connection = {Connected = true}
		self.listeners[connection] = fn
		function connection:Disconnect() self.Connected = false end
		return connection
	end
	function self:Fire(...)
		for connection, fn in pairs(self.listeners) do if connection.Connected then fn(...) end end
	end
	function self:Live()
		local n = 0
		for connection in pairs(self.listeners) do if connection.Connected then n += 1 end end
		return n
	end
	return self
end
local function p(x, y, z) return {X=x or 0,Y=y or 0,Z=z or 0} end
local function object(class, parent)
	local self = {ClassName=class, Parent=parent, signals={}, attributes={}, Position=p(),
		WorldPosition=p(), Anchored=true, Enabled=true, Range=20}
	function self:IsA(name)
		return self.ClassName == name or (name=="BasePart" and self.ClassName=="Part")
			or (name=="Light" and (self.ClassName=="PointLight" or self.ClassName=="SpotLight"))
	end
	function self:IsDescendantOf(root)
		local ancestor = self.Parent
		while ancestor do if ancestor==root then return true end; ancestor=ancestor.Parent end
		return false
	end
	function self:GetAttribute(name) return self.attributes[name] end
	function self:GetAttributeChangedSignal(name)
		local key="attribute:"..name
		if not self.signals[key] then self.signals[key]=signal() end
		return self.signals[key]
	end
	function self:SetAttribute(name,value)
		if self.attributes[name] == value then return end
		self.attributes[name] = value
		self:GetAttributeChangedSignal(name):Fire()
	end
	function self:GetPropertyChangedSignal(name)
		local key="property:"..name
		if not self.signals[key] then self.signals[key]=signal() end
		return self.signals[key]
	end
	function self:Move(at) self.Position=at; self.WorldPosition=at; self:GetPropertyChangedSignal("CFrame"):Fire() end
	return self
end
local function root()
	local self=object("Model",nil)
	self.descendants={}
	self.DescendantAdded=signal(); self.DescendantRemoving=signal()
	function self:GetDescendants() return table.clone(self.descendants) end
	function self:Add(instance)
		table.insert(self.descendants,instance)
		self.DescendantAdded:Fire(instance)
	end
	function self:Remove(instance)
		self.DescendantRemoving:Fire(instance)
		instance.Parent=nil
	end
	return self
end
local function effect(world, at, enabled, class)
	local part=object("Part",world);part.Position=at
	local item=object(class or "PointLight",part)
	item.Enabled=enabled
	item:SetAttribute("SceneBudgetWantedEnabled",enabled)
	world:Add(part);world:Add(item)
	return item,part
end
local function session(world,limit)
	return Budget.new(world,{ActiveDistance=128,Hysteresis=32,MaxInfluence=120,CellSize=128,PendingLimit=limit or 128})
end

do
	local world=root();local light,holder=effect(world,p(0),true)
	local untouched=object("PointLight",holder);world:Add(untouched)
	local dark=effect(world,p(0),false)
	local b=session(world)
	b:Step({p(0)})
	check(light.Enabled and not dark.Enabled and untouched.Enabled,"Authored false and unmarked state preserved")
	b:Step({p(179)})
	check(light.Enabled,"Stay enabled in hysteresis band")
	b:Step({p(181)})
	check(not light.Enabled,"Leave band switches light off")
	b:Step({p(160)})
	check(not light.Enabled,"Do not flicker on at exit threshold")
	b:Step({p(147)})
	check(light.Enabled,"Re-enter threshold enables lamp")
	check(b:Stats().Writes>=1,"Writes exposed for native profiling")
	-- A blackout arriving while Enabled is already locally false is a same-value write.
	b:Step({p(1000)});check(not light.Enabled,"Distant state")
	light.Enabled=true;light:GetPropertyChangedSignal("Enabled"):Fire()
	check(not light.Enabled,"Repeated server Enabled=true re-suppressed without a desired attribute change")
	light.Enabled=false
	light:SetAttribute("SceneBudgetWantedEnabled",false)
	b:Step({p(0)})
	check(not light.Enabled,"Server desired attribute prevents hidden same-value blackout race")
	light:SetAttribute("SceneBudgetWantedEnabled",true)
	check(light.Enabled,"Power restored in nearby sector")
	light.Brightness=0;light.Color="red";light.Angle=24
	b:Step({p(1000)});b:Step({p(0)})
	check(light.Brightness==0 and light.Color=="red" and light.Angle==24,"Flicker/finale properties untouched")
	holder:Move(p(1000));b:Step({p(0)})
	check(not light.Enabled,"Moved mount rebucketed")
	check(b.pendingTail-b.pendingHead<3,"Movement queue remains deduplicated")
	light:SetAttribute("SceneBudgetWantedEnabled",false)
	b:Destroy()
	check(not light.Enabled,"Destroy restores authoritative darkness")
	check(untouched.Enabled and not dark.Enabled,"Unmarked/initially-disabled preserved on cleanup")
	check(next(b.records)==nil and next(b.sectors)==nil and next(b.watchers)==nil,"All indices released")
	check(world.DescendantAdded:Live()==0 and world.DescendantRemoving:Live()==0,"Root connections disconnected")
	check(holder:GetPropertyChangedSignal("CFrame"):Live()==0,"Mount connection disconnected")
	check(light:GetAttributeChangedSignal("SceneBudgetWantedEnabled"):Live()==0,"Desired-state connection disconnected")
	check(light:GetPropertyChangedSignal("Enabled"):Live()==0,"Enabled repair connection disconnected")
	b:Destroy()
end

do
	local world=root();local b=session(world)
	local light,holder=effect(world,p(1000),true)
	b:Step({p(0)});check(not light.Enabled,"Streamed-in distant light suppressed")
	world:Remove(light)
	check(light.Enabled and b:Stats().Tracked==0,"Stream-out restores and unregisters")
	check(holder:GetPropertyChangedSignal("CFrame"):Live()==0,"Stream-out disconnects mount")
	light.Parent=holder;world:Add(light);b:Step({p(1000)})
	check(light.Enabled and b:Stats().Tracked==1,"Stream-in re-adopts fresh identity")
	b:Step({p(0)})
	light:SetAttribute("SceneBudgetWantedEnabled",nil)
	check(light.Enabled and b:Stats().Tracked==0,"Removing opt-in releases suppression")
	b:Destroy()
end

do
	local world=root();local particle=effect(world,p(1000),true,"ParticleEmitter")
	local b=session(world)
	check(b:Stats().Tracked==0,"Particles require an authored influence bound")
	particle:SetAttribute("SceneBudgetInfluenceRadius",24)
	particle:SetAttribute("SceneBudgetWantedEnabled",false)
	particle:SetAttribute("SceneBudgetWantedEnabled",true)
	b:Step({p(0)});check(not particle.Enabled,"Bounded static particle emission suppressed")
	particle:SetAttribute("SceneBudgetInfluenceRadius",200)
	check(particle.Enabled and b:Stats().Tracked==0,"Unsupported extent fails open")
	b:Destroy()
end

do
	local world=root()
	for i=1,1000 do effect(world,p(i*1000),true) end
	local b=session(world,32)
	for _=1,32 do b:Step({p(0)}) end
	check(b:Stats().Tracked==1000,"Large effect inventory")
	b:Step({p(0)})
	check(b:Stats().Checks==0,"Far stationary sectors are not rescanned each update")
	local light,holder=effect(world,p(0),true)
	for i=1,1000 do holder:Move(p(i%2)) end
	check(b.pendingTail-b.pendingHead<=1,"Repeated mount updates coalesce")
	b:Step({p(1000000)})
	check(light.Enabled==false,"Camera teleport disables former near sectors")
	b:Step({})
	check(light.Enabled,"Missing viewpoint restores suppression")
	b:Destroy()
end

check(Selector.ParticleBound(0.9,13,8,9.62,4,false) <= 32,"Measured foam bound fits envelope")
check(not pcall(Selector.ParticleBound,1.61,13,9,9.62,4,false),"Future combined travel bounds fail safely")
check(not pcall(Selector.ParticleBound,0.9,13,8,9.62,4,true),"Unaccounted wind fails safely")
print("SceneEffectBudget offline contracts passed: "..checks)
