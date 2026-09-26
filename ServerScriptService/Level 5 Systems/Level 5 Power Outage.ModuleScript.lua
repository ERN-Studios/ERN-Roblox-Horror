-- Server-owned schedule and fixture metadata only. Client owns light/material changes.
local RunService=game:GetService("RunService")
local RS=game:GetService("ReplicatedStorage")
local HttpService=game:GetService("HttpService")
local Logic=require(RS:WaitForChild("Level5OutageLogic"))
local Outage={}
local sessions=setmetatable({},{__mode="k"})
local SCHEDULE_ATTRIBUTE="Level5OutageSchedule"
local SECTION_ATTRIBUTE="Level5OutageSection"
local ORDER_ATTRIBUTE="Level5OutageOrder"
local FIXTURES={FluorescentPanel=true,SuspendedSharedFluorescent=true,SharedLowDomesticPanel=true,LastFluorescent=true}
local function integer(v,lo,hi) return type(v)=="number" and v==v and v%1==0 and v>=lo and v<=hi end

function Outage.Cleanup(world)
	local s=sessions[world]
	if not s or s.closed then return end
	s.closed=true;sessions[world]=nil
	for _,connection in ipairs(s.connections) do connection:Disconnect() end
	table.clear(s.connections)
	for _,entry in ipairs(s.attributes) do
		-- Restore only values that remain ours; another owner changing a value wins.
		pcall(function()
			if entry.object:GetAttribute(entry.name)==entry.written then entry.object:SetAttribute(entry.name,entry.before) end
		end)
	end
	if s.scheduleJSON then
		pcall(function()
			if world:GetAttribute(SCHEDULE_ATTRIBUTE)==s.scheduleJSON then world:SetAttribute(SCHEDULE_ATTRIBUTE,s.beforeSchedule) end
		end)
	end
	table.clear(s.attributes);table.clear(s.seen);s.schedule=nil;s.scheduleJSON=nil
end

local function live(s)
	return not s.closed and s.world.Parent==workspace and s.world:GetAttribute("Level5_MapOnly")==true
		and s.architecture.Parent==s.world
end

function Outage.Start(world,manifest)
	assert(RunService:IsServer() and RunService:IsRunning(),"Power outage requires the running server")
	assert(world and world:IsA("Model") and world.Parent==workspace and world:GetAttribute("Level5_MapOnly")==true,
		"Current Level 5 generated world required")
	assert(type(manifest)=="table" and type(manifest.Zones)=="table" and #manifest.Zones==8,"Eight actual section models required")
	if sessions[world] then return {ok=false,error="Outage controller already started"} end
	local architecture=world:FindFirstChild("Level5_IndoorSuburbs")
	assert(architecture and architecture:IsA("Model"),"Level 5 architecture root missing")
	assert(world:GetAttribute(SCHEDULE_ATTRIBUTE)==nil,"Preserve an existing outage schedule owner")
	local s={world=world,architecture=architecture,attributes={},connections={},seen={},serial=0,
		schedule=nil,scheduleJSON=nil,beforeSchedule=world:GetAttribute(SCHEDULE_ATTRIBUTE),closed=false}
	sessions[world]=s
	local ok,result=pcall(function()
		local sectionByModel={};local fixtures={}
		for index,zone in ipairs(manifest.Zones) do
			assert(typeof(zone.Model)=="Instance" and zone.Model:IsA("Model") and zone.Model:IsDescendantOf(architecture),
				"Each section must reference its actual architecture model")
			assert(not sectionByModel[zone.Model],"Duplicate section model")
			sectionByModel[zone.Model]=index;fixtures[index]={}
		end
		local function sectionFor(part)
			local parent=part.Parent
			while parent and parent~=architecture do
				local section=sectionByModel[parent]
				if section then return section end
				parent=parent.Parent
			end
			return nil
		end
		local fixtureCount=0
		for _,object in ipairs(architecture:GetDescendants()) do
			if object:IsA("BasePart") and FIXTURES[object.Name] then
				local section=assert(sectionFor(object),"Ceiling fixture has no owning section")
				fixtureCount+=1;assert(fixtureCount<=2048,"Unexpected fixture count exceeds outage annotation bound")
				local p=object.Position
				table.insert(fixtures[section],{object=object,x=p.X,y=p.Y,z=p.Z,path=object:GetFullName(),name=object.Name})
			end
		end
		local function same(a,b) return a.x==b.x and a.y==b.y and a.z==b.z and a.path==b.path and a.name==b.name end
		local function write(object,name,value)
			local entry={object=object,name=name,before=object:GetAttribute(name),written=value}
			table.insert(s.attributes,entry);object:SetAttribute(name,value)
		end
		local counts={}
		for section=1,8 do
			local entries=fixtures[section];assert(#entries>0,"No ceiling fixture in section "..section)
			table.sort(entries,function(a,b)
				if a.z~=b.z then return a.z<b.z end
				if a.x~=b.x then return a.x<b.x end
				if a.y~=b.y then return a.y<b.y end
				if a.name~=b.name then return a.name<b.name end
				return a.path<b.path
			end)
			-- Identical spatial/name keys share an order rather than depending on GetDescendants order.
			local groupCount=0;local previous
			for _,entry in ipairs(entries) do
				if not previous or not same(previous,entry) then groupCount+=1 end
				entry.group=groupCount;previous=entry
			end
			for _,entry in ipairs(entries) do
				write(entry.object,SECTION_ATTRIBUTE,section)
				write(entry.object,ORDER_ATTRIBUTE,groupCount>1 and (entry.group-1)/(groupCount-1) or 0)
			end
			counts[section]=#entries
		end
		local function connect(signal,callback) table.insert(s.connections,signal:Connect(callback)) end
		connect(world.Destroying,function() Outage.Cleanup(world) end)
		connect(world.AncestryChanged,function() if not live(s) then Outage.Cleanup(world) end end)
		connect(architecture.AncestryChanged,function() if not live(s) then Outage.Cleanup(world) end end)
		local elapsed=0
		connect(RunService.Heartbeat,function(dt)
			elapsed+=dt;if elapsed<.2 then return end;elapsed=0
			if not live(s) then Outage.Cleanup(world);return end
			if s.schedule and workspace:GetServerTimeNow()>=s.schedule.restoreAt+Logic.RESTORE_SECONDS then
				if world:GetAttribute(SCHEDULE_ATTRIBUTE)==s.scheduleJSON then world:SetAttribute(SCHEDULE_ATTRIBUTE,s.beforeSchedule) end
				s.schedule=nil;s.scheduleJSON=nil
			end
		end)
		return {ok=true,fixtureCount=fixtureCount,sectionCounts=counts,version="2026-09-26.outage.1"}
	end)
	if not ok then Outage.Cleanup(world);return {ok=false,error=tostring(result)} end
	return result
end

function Outage.Trigger(world,gate)
	local s=sessions[world]
	if not s or not live(s) then return false,"No live outage controller" end
	if not integer(gate,1,7) then return false,"Gate outside 1..7" end
	if s.seen[gate] then return false,"Gate already triggered" end
	if workspace:GetAttribute("SelectedLevel")~=5 or workspace:GetAttribute("RoundActive")~=true then return false,"Level 5 round is inactive" end
	local owner=world:FindFirstChild("Level5SectionProgression")
	local gateModel=owner and owner:FindFirstChild("SectionGate"..gate)
	if not gateModel or gateModel:GetAttribute("FullyOpen")~=true then return false,"Gate must be fully open" end
	-- Never overwrite an attribute that another owner changed while this controller was active.
	if world:GetAttribute(SCHEDULE_ATTRIBUTE)~=s.scheduleJSON then return false,"Outage schedule ownership changed" end
	local now=workspace:GetServerTimeNow()
	local serial=s.serial+1
	local schedule=Logic.NewSchedule(s.schedule,now,gate,serial)
	local encoded=HttpService:JSONEncode(schedule)
	world:SetAttribute(SCHEDULE_ATTRIBUTE,encoded)
	s.serial=serial;s.schedule=schedule;s.scheduleJSON=encoded;s.seen[gate]=true
	return true,schedule
end
return Outage
