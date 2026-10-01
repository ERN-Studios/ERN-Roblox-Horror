-- Local vinyl and hologram rendering; GameManager owns the real queue state.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local player = Players.LocalPlayer
local model, vinyls, stations, connections = nil, {}, {}, {}
local registered, tweens = {}, {}
local pending = {}
local function reduceMotion()
	return player:GetAttribute("ReduceFlashing") ~= false
end
local function animate(station)
	local active = station:GetAttribute("QueueActive") == true
	local base = station:GetAttribute("HologramBase")
	if typeof(base) ~= "CFrame" then return end
	local duration = reduceMotion() and 0 or 1
	local ring = station:FindFirstChild("Active Queue Ring")
	if ring then
		if tweens[ring] then tweens[ring]:Cancel() end
		local tween = TweenService:Create(ring,TweenInfo.new(duration),{Transparency=active and .12 or .8})
		tweens[ring] = tween; tween:Play()
	end
	for _,wall in ipairs(station:GetChildren()) do
		local i = wall:GetAttribute("HologramBandIndex")
		if wall:IsA("MeshPart") and i then
			if tweens[wall] then tweens[wall]:Cancel(); tweens[wall] = nil end
			local full = wall:GetAttribute("HologramFullSize")
			local target = wall:GetAttribute("HologramFullCFrame")
			local alpha = .62 + .38*((i-1)/9)^.85
			local goal = active and {Size=full,CFrame=target,Transparency=alpha} or {Size=Vector3.new(full.X,.015,full.Z),CFrame=base*CFrame.new(0,.008,0),Transparency=1}
			local tween = TweenService:Create(wall,TweenInfo.new(duration,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),goal)
			tweens[wall] = tween; tween:Play()
		end
	end
end
local function schedule(station)
	if pending[station] then return end
	pending[station] = true
	task.defer(function()
		pending[station] = nil
		if station.Parent and model and station:IsDescendantOf(model) then animate(station) end
	end)
end
local function bind(nextModel)
	if model == nextModel then return end
	for _,c in ipairs(connections) do c:Disconnect() end; table.clear(connections);table.clear(vinyls);table.clear(stations)
	for _,t in pairs(tweens) do t:Cancel() end; table.clear(tweens); table.clear(registered);table.clear(pending)
	model = nextModel
	if not model then return end
	local function register(p)
		if registered[p] then return end
		if p:IsA("MeshPart") and p:GetAttribute("PreviewVinylDisc") == true then table.insert(vinyls,p) end
		if p:IsA("Model") and p:GetAttribute("HologramBase") then
			table.insert(stations,p); schedule(p)
			table.insert(connections,p:GetAttributeChangedSignal("QueueActive"):Connect(function() animate(p) end))
		end
		if p:IsA("MeshPart") and p:GetAttribute("HologramBandIndex") then schedule(p.Parent) end
		registered[p] = true
	end
	for _,p in ipairs(model:GetDescendants()) do register(p) end
	table.insert(connections,model.DescendantAdded:Connect(register))
	table.insert(connections,model.DescendantRemoving:Connect(function(p)
		if tweens[p] then tweens[p]:Cancel(); tweens[p] = nil end
		registered[p] = nil
		local index = table.find(vinyls,p); if index then table.remove(vinyls,index) end
	end))
end
local tickBudget, angle = 0, 0
player:GetAttributeChangedSignal("ReduceFlashing"):Connect(function()
	for _,station in ipairs(stations) do if station.Parent then animate(station) end end
end)
RunService.Heartbeat:Connect(function(dt)
	local current = workspace:FindFirstChild("LobbyReimaginedPreview")
	if current ~= model then bind(current) end
	if not model then return end
	tickBudget += dt; if tickBudget < 1/30 then return end; local elapsed = tickBudget; tickBudget = 0
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local center = model:GetAttribute("PreviewCenter")
	if not root or typeof(center) ~= "Vector3" or (root.Position-center).Magnitude > 220 then return end
	if reduceMotion() then return end
	angle = (angle + elapsed*math.rad(12)) % (math.pi*2)
	for _,disc in ipairs(vinyls) do
		if disc.Parent then disc.CFrame = disc:GetAttribute("RecordPivot")*CFrame.Angles(0,angle,0)*disc:GetAttribute("RecordMeshOffset") end
	end
end)
