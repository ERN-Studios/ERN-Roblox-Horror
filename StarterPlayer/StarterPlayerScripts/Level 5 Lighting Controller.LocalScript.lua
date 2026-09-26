-- One Level 5 lighting owner: profile, server-timed ceiling outage and exact restoration.
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local Logic = require(ReplicatedStorage:WaitForChild("Level5OutageLogic"))
local player = Players.LocalPlayer
local LIGHTING_KEYS = {
	"ClockTime", "Brightness", "Ambient", "OutdoorAmbient", "ColorShift_Top",
	"ColorShift_Bottom", "GlobalShadows", "EnvironmentDiffuseScale",
	"EnvironmentSpecularScale", "ExposureCompensation", "FogColor", "FogStart", "FogEnd",
}
local AIR_KEYS = {"Density", "Offset", "Haze", "Glare", "Color", "Decay"}
local FIXTURE_NAMES = {FluorescentPanel=true, SuspendedSharedFluorescent=true, SharedLowDomesticPanel=true, LastFluorescent=true}
local snapshot, airSnapshot, air = nil, nil, nil
local stateConnection, watchedState, watchedWorld = nil, nil, nil
local worldConnections, fixtures = {}, {}
local schedule, pending, lastAmbient = nil, false, nil
local stopped=false
local connections={}
local function connect(signal,callback) table.insert(connections,signal:Connect(callback)) end
local function scale(value,power)
	if typeof(value)=="Color3" then return Color3.new(value.R*power,value.G*power,value.B*power) end
	return value*power
end
local applyPower, queueSync

local function originalFixture(record)
	local part = record.part
	if part.Parent then part.Material = record.material; part.Color = record.colour end
	for light, base in pairs(record.lights) do
		if light.Parent then light.Enabled = base.enabled; light.Brightness = base.brightness end
	end
	record.lastPower = nil
end

local function detachWorld()
	for _, c in ipairs(worldConnections) do c:Disconnect() end
	table.clear(worldConnections)
	for _, record in pairs(fixtures) do originalFixture(record) end
	table.clear(fixtures)
	if watchedWorld and watchedWorld.Parent then watchedWorld:SetAttribute("Level5OutageVisualPhase",nil) end
	watchedWorld, schedule, lastAmbient = nil, nil, nil
end

local function restore()
	detachWorld()
	if snapshot then
		for property, value in pairs(snapshot) do Lighting[property] = value end
	end
	if airSnapshot and air and air.Parent == Lighting then
		for property, value in pairs(airSnapshot) do air[property] = value end
	end
	snapshot, airSnapshot, air = nil, nil, nil
end

local function readSchedule()
	schedule = nil
	local encoded = watchedWorld and watchedWorld:GetAttribute("Level5OutageSchedule")
	if type(encoded) == "string" then
		local ok, parsed = pcall(HttpService.JSONDecode,HttpService,encoded)
		if ok and Logic.ValidateSchedule(parsed) then schedule = parsed end
	end
	lastAmbient = nil
end

local function applyFixture(record, now, phase)
	local part = record.part
	if not part.Parent or not record.active then return end
	local reduced = player:GetAttribute("ReduceFlashing") ~= false
	local power = Logic.FixturePower(schedule,now,part:GetAttribute("Level5OutageSection") or 1,
		part:GetAttribute("Level5OutageOrder") or 0,reduced)
	local serial = schedule and schedule.startedAt
	if reduced and phase == "FALLING" and record.serial == serial and record.lastPower then
		-- Toggling accessibility mid-flicker must not brighten an already failed tube.
		power = math.min(power,record.lastPower)
	end
	record.serial = serial
	if record.lastPower == power then return end
	record.lastPower = power
	part.Material = power == 0 and Enum.Material.SmoothPlastic or record.material
	part.Color = scale(record.colour,math.max(power,.10))
	for light, base in pairs(record.lights) do
		if light.Parent then
			light.Enabled = base.enabled and power > 0
			light.Brightness = base.brightness * power
		end
	end
end

local function register(object)
	local architecture = watchedWorld and watchedWorld:FindFirstChild("Level5_IndoorSuburbs")
	if not architecture or not object:IsDescendantOf(architecture) then return end
	if object:IsA("BasePart") and FIXTURE_NAMES[object.Name] and not fixtures[object] then
		local record = {part=object,material=object.Material,colour=object.Color,lights={},
			active=object:GetAttribute("TubeState")~="Off" and object:GetAttribute("FailedTube")~=true}
		for _, child in ipairs(object:GetChildren()) do
			if child:IsA("Light") then record.lights[child]={enabled=child.Enabled,brightness=child.Brightness} end
		end
		fixtures[object] = record
		local now=workspace:GetServerTimeNow()
		applyFixture(record,now,Logic.Phase(schedule,now))
	elseif object:IsA("Light") then
		local record=fixtures[object.Parent]
		if record and not record.lights[object] then
			record.lights[object]={enabled=object.Enabled,brightness=object.Brightness}
			record.lastPower=nil
			local now=workspace:GetServerTimeNow()
			applyFixture(record,now,Logic.Phase(schedule,now))
		end
	end
end

local function attachWorld(world)
	if watchedWorld == world then return end
	detachWorld()
	watchedWorld = world
	readSchedule()
	for _, object in ipairs(world:GetDescendants()) do register(object) end
	table.insert(worldConnections,world.DescendantAdded:Connect(register))
	table.insert(worldConnections,world.DescendantRemoving:Connect(function(object)
		local record=fixtures[object]
		if record then originalFixture(record); fixtures[object]=nil
		elseif object:IsA("Light") then
			local parentRecord=fixtures[object.Parent]
			local base=parentRecord and parentRecord.lights[object]
			if base then object.Enabled=base.enabled; object.Brightness=base.brightness;parentRecord.lights[object]=nil end
		end
	end))
	table.insert(worldConnections,world:GetAttributeChangedSignal("Level5OutageSchedule"):Connect(function()
		readSchedule(); queueSync()
	end))
end

applyPower = function()
	if not snapshot or not watchedState or not watchedWorld then return end
	local now=workspace:GetServerTimeNow()
	local power=Logic.AmbientPower(schedule,now)
	local phase=Logic.Phase(schedule,now)
	if watchedWorld:GetAttribute("Level5OutageVisualPhase")~=phase then watchedWorld:SetAttribute("Level5OutageVisualPhase",phase) end
	if power~=lastAmbient then
		lastAmbient=power
		for _, key in ipairs({"Brightness","Ambient","OutdoorAmbient","EnvironmentDiffuseScale","EnvironmentSpecularScale","FogColor"}) do
			local base=watchedState:GetAttribute("Lighting_"..key)
			if base~=nil then Lighting[key]=scale(base,power) end
		end
		if air and air.Parent==Lighting then
			for _, key in ipairs({"Color","Decay","Haze","Glare"}) do
				local base=watchedState:GetAttribute("Atmosphere_"..key)
				if base~=nil then air[key]=scale(base,power) end
			end
		end
	end
	for _, record in pairs(fixtures) do applyFixture(record,now,phase) end
end

local function sync()
	if stopped then return end
	local state=ReplicatedStorage:FindFirstChild("Level 5 State")
	local world=workspace:FindFirstChild("Level 5 Generated World")
	local owns=world~=nil and workspace:GetAttribute("SelectedLevel")==5
		and workspace:GetAttribute("Level5LightingOwnedByController")==true
		and player:GetAttribute("InRound")==true
		and state~=nil and state:GetAttribute("Level5_MapOnly")==true
	if not owns then restore(); return end
	if not snapshot then
		snapshot={}
		for _, property in ipairs(LIGHTING_KEYS) do snapshot[property]=Lighting[property] end
		air=Lighting:FindFirstChildOfClass("Atmosphere")
		if air then
			airSnapshot={}
			for _, property in ipairs(AIR_KEYS) do airSnapshot[property]=air[property] end
		end
	end
	attachWorld(world)
	for _, property in ipairs(LIGHTING_KEYS) do
		local value=state:GetAttribute("Lighting_"..property)
		if value~=nil then Lighting[property]=value end
	end
	if air and air.Parent==Lighting then
		for _, property in ipairs(AIR_KEYS) do
			local value=state:GetAttribute("Atmosphere_"..property)
			if value~=nil then air[property]=value end
		end
	end
	lastAmbient=nil
	applyPower()
end

queueSync = function()
	if stopped or pending then return end
	pending=true
	task.defer(function() pending=false;if not stopped then sync() end end)
end

local function watchState()
	local state=ReplicatedStorage:FindFirstChild("Level 5 State")
	if state==watchedState then return end
	if stateConnection then stateConnection:Disconnect(); stateConnection=nil end
	watchedState=state
	if state then stateConnection=state.AttributeChanged:Connect(queueSync) end
	queueSync()
end

local elapsed=0
local heartbeat=RunService.Heartbeat:Connect(function(dt)
	if not snapshot or not schedule then return end
	elapsed+=dt
	if elapsed<.05 then return end
	elapsed=0
	applyPower()
end)
connect(workspace:GetAttributeChangedSignal("SelectedLevel"),queueSync)
connect(workspace:GetAttributeChangedSignal("Level5LightingOwnedByController"),queueSync)
connect(player:GetAttributeChangedSignal("InRound"),queueSync)
connect(player:GetAttributeChangedSignal("ReduceFlashing"),queueSync)
connect(workspace.ChildAdded,function(child) if child.Name=="Level 5 Generated World" then queueSync() end end)
connect(workspace.ChildRemoved,function(child) if child.Name=="Level 5 Generated World" then queueSync() end end)
connect(ReplicatedStorage.ChildAdded,watchState)
connect(ReplicatedStorage.ChildRemoved,watchState)
script.Destroying:Connect(function()
	stopped=true;heartbeat:Disconnect()
	for _,c in ipairs(connections) do c:Disconnect() end
	table.clear(connections)
	if stateConnection then stateConnection:Disconnect() end
	restore()
end)
watchState()
queueSync()
