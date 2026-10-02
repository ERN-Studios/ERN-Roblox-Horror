-- R4-only scene presentation. Original lobby/shop and global Lighting are untouched.
local Module = {}
local OWNER, FOLDER = "LobbyPolishScene20261002Owned", "R4ScenePresentation"
local function own(instance)
	instance:SetAttribute(OWNER,true); instance:SetAttribute("LobbyReimaginedOwned",true)
end
local function visualPart(parent,name,size,frame,color,material)
	local p = Instance.new("Part")
	p.Name,p.Size,p.CFrame = name,size,frame
	p.Anchored = true
	p.CanCollide,p.CanTouch,p.CanQuery,p.CastShadow = false,false,false,false
	p.Color,p.Material = color,material or Enum.Material.SmoothPlastic
	own(p);p.Parent = parent
	return p
end
local function exactFill(parent)
	local fill = parent:FindFirstChild("Preview Fill")
	assert(parent:IsA("BasePart") and fill and fill:IsA("PointLight"),"Unexpected preview fill carrier")
	return fill
end
local function polishLighting(model)
	local center = model:GetAttribute("PreviewCenter")
	assert(typeof(center)=="Vector3", "Missing authoritative preview center")
	local lighting = assert(model:FindFirstChild("PreviewLighting"),"Missing preview lights")
	local tunnels,stage,ends,shop = {},{},{},{}
	for _, carrier in ipairs(lighting:GetChildren()) do
		if not carrier:IsA("BasePart") then continue end
		local p = carrier.CFrame.Position-center
		if carrier.Name=="Tunnel Lamp" then
			assert(math.abs(math.abs(p.X)-11)<.02 and math.abs(p.Y-29.5)<.02 and math.abs(p.Z)<=130.02,
				"Tunnel light layout changed; reconcile fresh Studio baseline")
			table.insert(tunnels,{carrier=carrier,fill=exactFill(carrier),localPosition=p})
		elseif carrier.Name=="Stage Fill" then
			assert(math.abs(p.Y-17)<.02 and math.abs(p.Z-114)<.02 and math.abs(p.X)<=10.02,
				"Stage light layout changed; reconcile fresh Studio baseline")
			table.insert(stage,{carrier=carrier,fill=exactFill(carrier),localPosition=p})
		elseif carrier.Name=="Warm Wall Fill" then
			if math.abs(math.abs(p.Z)-120)<.02 then table.insert(ends,{carrier=carrier,fill=exactFill(carrier)}) end
			if math.abs(p.X-27)<.02 and math.abs(p.Z+40)<.02 then table.insert(shop,{carrier=carrier,fill=exactFill(carrier)}) end
		end
	end
	assert(#tunnels==28 and #stage==3 and #ends==4 and #shop==1,"Unexpected R4 emitter ownership/count")
	-- Reuse the 28 invisible fixture carriers, bringing their quiet fill nearer the
	-- road/avatar and away from the ceiling. No added light, shadow or global change.
	for _, item in ipairs(tunnels) do
		local p = item.localPosition
		item.carrier.CFrame = CFrame.new(center+Vector3.new(p.X,17,p.Z))*item.carrier.CFrame.Rotation
		item.fill.Color = Color3.fromRGB(226,230,213)
		item.fill.Brightness,item.fill.Range,item.fill.Shadows = .42,28,false
		item.carrier:SetAttribute(OWNER,true)
	end
	-- These three shorter, lower fills cover the stair treads/console rather than
	-- the upper furniture crown behind them. This is lighting intent, not a profile.
	for _, item in ipairs(stage) do
		local p = item.localPosition
		item.carrier.CFrame = CFrame.new(center+Vector3.new(p.X,10.5,111))*item.carrier.CFrame.Rotation
		item.fill.Color = Color3.fromRGB(243,227,193)
		item.fill.Brightness,item.fill.Range,item.fill.Shadows = .62,18,false
		item.carrier:SetAttribute(OWNER,true)
	end
	for _, item in ipairs(ends) do
		item.fill.Color = Color3.fromRGB(230,215,182)
		item.fill.Brightness,item.fill.Range = .3,21
		item.carrier:SetAttribute(OWNER,true)
	end
	local fill = shop[1].fill
	fill.Color = Color3.fromRGB(229,227,207)
	fill.Brightness,fill.Range = .3,25
	shop[1].carrier:SetAttribute(OWNER,true)
	return #tunnels+#stage+#ends+#shop
end
local function polishStage(model,root)
	local center = model:GetAttribute("PreviewCenter")
	local collisions = assert(model:FindFirstChild("PreviewCollisions"),"Missing authoritative collision folder")
	local steps,deck = {},nil
	for _, collider in ipairs(collisions:GetChildren()) do
		if collider.Name=="Stage Step" and collider:IsA("BasePart") then
			local p = collider.CFrame.Position-center
			assert(math.abs(p.X)<.02 and math.abs(collider.Size.X-30)<.02,"Stage collider layout changed")
			table.insert(steps,{collider=collider,front=p.Z-collider.Size.Z/2,back=p.Z+collider.Size.Z/2,top=p.Y+collider.Size.Y/2})
		elseif collider.Name=="Stage Deck" and collider:IsA("BasePart") then
			assert(not deck,"Ambiguous stage deck");deck=collider
		end
	end
	assert(#steps==6 and deck,"Expected exact six stage steps/deck")
	table.sort(steps,function(a,b)return a.top<b.top end)
	for i,step in ipairs(steps) do
		assert(math.abs(step.top-i*.75)<.02 and math.abs(step.front-(i==6 and 109.49 or 103.99+i))<.02,
			"Stage elevations changed; reconcile current geometry")
	end
	local deckP = deck.CFrame.Position-center
	local deckTop = deckP.Y+deck.Size.Y/2
	assert(math.abs(deckTop-4.5)<.02 and math.abs(deckP.Z-120)<.02,"Stage deck moved")
	local cloth = Color3.fromRGB(103,91,66)
	local trim = Color3.fromRGB(165,149,109)
	local parts = 0
	local function make(name,size,p,color,material)
		parts+=1;return visualPart(root,name,size,CFrame.new(center+p),color,material)
	end
	-- The existing authored asphalt top is .0325 above the road collider. The
	-- approach cloth starts .0015 above that visual surface and stops before step 1.
	local approachBack = steps[1].front-.05
	local approachFront = 89.4
	make("Stage Approach Runner",Vector3.new(5.8,.016,approachBack-approachFront),
		Vector3.new(0,.042,(approachFront+approachBack)/2),cloth,Enum.Material.Fabric)
	local previousTop = 0
	for i,step in ipairs(steps) do
		-- Clip each cloth tread at the next higher collider's front: the last two
		-- original blocks overlap .52 studs, so treating their full sizes as treads
		-- would bury or intersect a new carpet strip.
		local exposedBack = if i<#steps then math.min(step.back,steps[i+1].front) else deckP.Z-deck.Size.Z/2
		local front,back = step.front+.09,exposedBack-.025
		assert(back-front>.25,"No exposed stage tread")
		make("Stage Carpet Tread "..i,Vector3.new(5.8,.016,back-front),
			Vector3.new(0,step.top+.009,(front+back)/2),cloth,Enum.Material.Fabric)
		make("Stage Carpet Riser "..i,Vector3.new(5.8,step.top-previousTop-.04,.012),
			Vector3.new(0,(step.top+previousTop)/2,step.front-.007),cloth,Enum.Material.Fabric)
		-- Quiet matte nosings span the existing steps; no neon or light source.
		make("Stage Step Nosing "..i,Vector3.new(26.4,.058,.065),
			Vector3.new(0,step.top+.03,step.front+.035),trim,Enum.Material.Metal)
		previousTop = step.top
	end
	local deckFront,deckBack = deckP.Z-deck.Size.Z/2+.025,117.5
	make("Stage Deck Runner",Vector3.new(5.8,.016,deckBack-deckFront),
		Vector3.new(0,deckTop+.009,(deckFront+deckBack)/2),cloth,Enum.Material.Fabric)
	return parts
end
