--!strict
-- Blender-authored, round-owned Level 6 alcoves and additive set dressing.
-- No live place mutation: require this candidate only from the Level 6 adapter.
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

local function safeRect(rect, room, blocked, reservePerimeter)
	local inset = if reservePerimeter then 11.5 else WALL_INSET
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
		local fits=safeRect(withPartition,room,blocked,false)
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
	return object:GetAttribute("Level6_"..suffix)==true or object:GetAttribute("Level3_"..suffix)==true
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
	owner.Name="Level 6 Blender Set Dressing"
	owner:SetAttribute("Level6_DressingOwned",true)
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
			if part.Parent and part:GetAttribute("Level6_TablewareDressingOwner")==dressingId then
				part:SetAttribute("Level6_TablewarePlaced",nil)
				part:SetAttribute("Level6_TablewareDressingOwner",nil)
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
		model:SetAttribute("Level6_DressingOwned",true)
		model:SetAttribute("Level6_DressingAsset",asset)
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
		part:SetAttribute("Level6_DressingOwned",true)
		part.Parent=parent
		return part
	end

	local function navBox(parent,cf,size)
		local blocker=carrier(parent,cf.Position,"Level 6 Service Furniture Nav Exclusion")
		blocker.CFrame=cf*CFrame.new(0,5,0)
		blocker.Size=V(size.X+2*MANAGER_RADIUS,10,size.Z+2*MANAGER_RADIUS)
		blocker.CanQuery=true
		blocker:SetAttribute("Level6_ManagerFurnitureNavExclusion",true)
		local modifier=Instance.new("PathfindingModifier")
		modifier.Label=options.PathLabel or "Level6ManagerFurniture"
		modifier.PassThrough=false
		modifier.Parent=blocker
	end

	local function interactive(model,cf,kind,asset)
		if not model then return end
		local localPosition=if kind=="breaker" then V(.98,6.70,.42)
			elseif kind=="claw" then V(.52,2.65,1.94) else V(0,4.2,1.8)
		-- Breaker asset base is already mounted high; inspect at its latch +2.15.
		if kind=="breaker" then localPosition=V(.98,2.15,.42) end
		local anchor=carrier(model,cf:PointToWorldSpace(localPosition),"Interaction Origin")
		local prompt=Instance.new("ProximityPrompt")
		prompt.Name="Level6_ServiceInteraction"
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
			sound.Name="Level 6 Original Service Sound"
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
				or player.Parent~=Players or workspace:GetAttribute("Level6SelectedLevel")~=6
				or workspace:GetAttribute("Level6RoundActive")~=true then return end
			if generation~=nil and world:GetAttribute("Level6_Generation")~=nil
				and world:GetAttribute("Level6_Generation")~=generation then return end
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
			model:SetAttribute("Level6_LastUsedBy",player.UserId)
			model:SetAttribute("Level6_InteractionSerial",(model:GetAttribute("Level6_InteractionSerial") or 0)+1)
			model:SetAttribute("Level6_ServiceActive",true)
			prompt.ActionText=if kind=="breaker" then "LABEL: PARTY WING / SPARE" elseif kind=="claw" then "The claw is stuck..." else "INSERT COIN — credit rejected"
			if sound then sound:Play() end
			if type(noiseCallback)=="function" then pcall(noiseCallback,player,anchor.Position,if kind=="breaker" then .15 else .4) end
			later(if kind=="breaker" then 3.5 else 5,function()
				if model.Parent and prompt.Parent then
					busy=false
					model:SetAttribute("Level6_ServiceActive",false)
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
		group:SetAttribute("Level6_RoomId",room.Id)
		group.Parent=owner
		local blocked=collectBlocked(roomModel,base)
		local plan=Dress.Plan(room,blocked,room.ServicePocketSeed or seed+roomIndex*997)
		local height=tonumber(room.H) or 12

		-- Small table dressing rides the existing authoritative tabletop; never
		-- create a new table, hide anchor, pickup socket or objective prompt here.
		for _,object in ipairs(roomModel:GetDescendants()) do
			if object:IsA("BasePart") and tagged(object,"TableCollision")
				and object:GetAttribute("Level6_TablewarePlaced")~=true then
				local cf=object.CFrame*CFrame.new(3.3,math.max(object.Size.Y*.5, .44)+.02,0)
				if placed("Tableware",cf,group,false,nil) then
					object:SetAttribute("Level6_TablewarePlaced",true)
					object:SetAttribute("Level6_TablewareDressingOwner",dressingId)
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
						if safeRect(rect,room,blocked,false) then
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
	owner:SetAttribute("Level6_DressingPropCount",report.PropsPlaced)
	owner:SetAttribute("Level6_DressingServicePocketCount",report.FullServicePockets)
	owner:SetAttribute("Level6_DressingInteractionCount",report.Interactions)
	return {Cleanup=cleanup,Report=report,Owner=owner}
end

return Dress
