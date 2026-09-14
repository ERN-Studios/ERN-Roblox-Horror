
type AnyTable = {[any]:any}
local checks=0
local function warn(_) end
local function check(v,m) checks+=1; assert(v,m) end
local Vector3={}
local mt={}
function Vector3.new(x,y,z) return setmetatable({X=x,Y=y,Z=z},mt) end
mt.__add=function(a,b) return Vector3.new(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
mt.__sub=function(a,b) return Vector3.new(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
mt.__mul=function(a,b) return Vector3.new(a.X*b,a.Y*b,a.Z*b) end
mt.__div=function(a,b) return a*(1/b) end
mt.__index=function(v,k)
 if k=='Magnitude' then return math.sqrt(v.X*v.X+v.Y*v.Y+v.Z*v.Z) end
 if k=='Unit' then return v/v.Magnitude end
 if k=='Dot' then return function(a,b) return a.X*b.X+a.Y*b.Y+a.Z*b.Z end end
end
Vector3.zero=Vector3.new(0,0,0)
local function attributes()
 return {attrs={},order={},GetAttribute=function(self,k) return self.attrs[k] end,
 SetAttribute=function(self,k,v) self.attrs[k]=v; table.insert(self.order,k) end}
end
local workspace=attributes()
local Players={players={},GetPlayers=function(self) return self.players end}
local function validPlayer(p) return not p.lobby and not p.escaped end
local function livingCharacter(p) if not p.dead then return p.character,{},p.root end end
local function player(id,x,z)
 return {UserId=id,character={},root={Position=Vector3.new(x,3,z or 0)}}
end
local function makeSession()
 local state=attributes(); state.attrs.Level3_RoomSongPhase='DONE'
 return {ExitUnlocked=true,FinalHallCrossed={},State=state,Manifest={World=attributes(),
 FinalHall={Model={Parent=true},StartPoint=Vector3.new(100,0,0),Forward=Vector3.new(1,0,0),Length=560,Width=20,Height=20,FloorY=0},
 MazeStart={Parent=true,Position=Vector3.new(-200,.25,0),CFrame={LookVector=Vector3.new(1,0,0)}}}}
end
local currentRecords={}
local blocked=false
local function eligibleSpawnPlayers() return currentRecords end
local function spawnOverlapParams() return {} end
local function spawnVolumeFits(position) return not blocked and position.X>=-188 end
local function spawnVisibilityCount() return 0 end
local function planarDistance(a,b) return Vector3.new(a.X-b.X,0,a.Z-b.Z).Magnitude end
local function nearestRoomId(p) return if p.X<0 then 'Arrival' else 'SignalHall' end
local function stateFolder() return attributes() end
local Random={new=function() return {} end}
local Tuning={FinaleApproachSpeed=360,PlayerRunSpeedReference=26,
 Normal={ChaseSpeed=22,PatrolSpeed=4},Blackout={ChaseSpeed=31.2,PatrolSpeed=5.25}}
local function profile(s) return s.Blackout and Tuning.Blackout or Tuning.Normal end

local function updateFinalHallChase(session: AnyTable)
	if not session.ExitUnlocked or session.FinalHallChaseTriggered
		or session.State:GetAttribute("Level3_RoomSongPhase") ~= "DONE" then
		return
	end
	local hall = session.Manifest.FinalHall
	if type(hall) ~= "table" or not hall.Model or not hall.Model.Parent then return end
	local horizontalForward = Vector3.new(hall.Forward.X, 0, hall.Forward.Z)
	if horizontalForward.Magnitude <= .001 then return end
	horizontalForward = horizontalForward.Unit
	local eligibleCount = 0
	local crossedCount = 0
	for _, player in ipairs(Players:GetPlayers()) do
		if validPlayer(player, session) then
			local character, _, root = livingCharacter(player)
			if character and root then
				eligibleCount += 1
				if session.FinalHallCrossed[player] ~= character then
					local offset = Vector3.new(
						root.Position.X - hall.StartPoint.X, 0, root.Position.Z - hall.StartPoint.Z)
					local along = offset:Dot(horizontalForward)
					local lateral = (offset - horizontalForward * along).Magnitude
					-- Start the finale as the first survivor commits to the open exit hall.
					local entryProgress = 4
					local insideHallWidth = lateral <= hall.Width * .5 + 2.5
					local insideHallHeight = math.abs(root.Position.Y - hall.FloorY) <= hall.Height + 6
					if along >= entryProgress and along <= hall.Length + 2.5
						and insideHallWidth and insideHallHeight then
						session.FinalHallCrossed[player] = character
					end
				end
				if session.FinalHallCrossed[player] == character then crossedCount += 1 end
			end
		end
	end
	session.FinalHallEligibleCount = eligibleCount
	session.FinalHallCrossedCount = crossedCount
	session.State:SetAttribute("Level3_FinalHallEligibleCount", eligibleCount)
	session.State:SetAttribute("Level3_FinalHallCrossedCount", crossedCount)
	session.Manifest.World:SetAttribute("Level3_FinalHallEligibleCount", eligibleCount)
	session.Manifest.World:SetAttribute("Level3_FinalHallCrossedCount", crossedCount)
	workspace:SetAttribute("Level3FinalHallEligibleCount", eligibleCount)
	workspace:SetAttribute("Level3FinalHallCrossedCount", crossedCount)
	if eligibleCount == 0 or crossedCount == 0 then return end

	session.FinalHallChaseTriggered = true
	session.State:SetAttribute("Level3_FinalHallChaseTriggered", true)
	session.State:SetAttribute("Level3_FinalHallChaseActive", true)
	session.State:SetAttribute("Level3_MallManagerHuntActive", true)
	session.Manifest.World:SetAttribute("Level3_FinalHallChaseTriggered", true)
	session.Manifest.World:SetAttribute("Level3_FinalHallChaseActive", true)
	workspace:SetAttribute("Level3FinalHallChaseTriggered", true)
	-- This must precede HuntActive so the Manager's synchronous Start selects the
	-- level-entry finale spawn rather than a normal hidden random-room spawn.
	workspace:SetAttribute("Level3FinalHallChaseActive", true)
	workspace:SetAttribute("Level3MallManagerHuntActive", true)
end


local insideFinalHall = function(session: any, position: Vector3): boolean
 local hall = session.Manifest.FinalHall
 if type(hall) ~= "table" then return false end
 local forward = Vector3.new(hall.Forward.X, 0, hall.Forward.Z)
 if forward.Magnitude <= .001 then return false end
 forward = forward.Unit
 local offset = Vector3.new(position.X - hall.StartPoint.X, 0, position.Z - hall.StartPoint.Z)
 local along = offset:Dot(forward)
 -- The physical escape sensor is beyond the hall's authored EndPoint. Keep
 -- following this same straight lane until the runner actually crosses it.
 local escape = session.Manifest.EscapeTrigger
 local laneLength = escape and math.max(hall.Length,
  (escape.Position - hall.StartPoint):Dot(forward)) or hall.Length
 return along >= -2 and along <= laneLength + 6
  and (offset - forward * along).Magnitude <= hall.Width * .5 + 2
  and math.abs(position.Y - hall.FloorY) <= hall.Height + 6
end


local function currentSpeed(session: any): number
	local stateName = session.State
	local activeProfile = profile(session)
	if session.FinalHallChase and stateName == "CHASE" then
		-- The entrance can be over a thousand studs away. The fast approach
		-- still follows the maze and uses the normal collision sweep.
		if not insideFinalHall(session, session.Root.Position) then
			return Tuning.FinaleApproachSpeed
		end
		-- Lock the hall speed once, accounting for this layout's approach time.
		-- An uninterrupted sprint reaches the sensor about one second ahead.
		-- Do not keep adapting to the runner: stopping must still get them caught.
		if not session.FinaleHallSpeed then
			local targetRoot = session.Target and session.Target.Character
				and session.Target.Character:FindFirstChild("HumanoidRootPart")
			local exit = session.Manifest.EscapeTrigger
			if targetRoot and exit and insideFinalHall(session, targetRoot.Position) then
				local forward = session.Manifest.FinalHall.Forward
				local runnerRemaining = math.max(0, (exit.Position - targetRoot.Position):Dot(forward))
				local entityRemaining = math.max(0, (exit.Position - session.Root.Position):Dot(forward))
				local timeToExit = runnerRemaining / Tuning.PlayerRunSpeedReference + 1
				session.FinaleHallSpeed = math.clamp(entityRemaining / timeToExit,
					Tuning.PlayerRunSpeedReference, Tuning.PlayerRunSpeedReference * 1.5)
			end
		end
		return session.FinaleHallSpeed or activeProfile.ChaseSpeed
	end
	if stateName == "PATROL" or stateName == "PATROL_LISTEN" or stateName == "AWAKENING" then
		return activeProfile.PatrolSpeed
	end
	if stateName == "INVESTIGATE" or stateName == "ALERT" or stateName == "RECOVER" then
		return activeProfile.InvestigateSpeed
	end
	if stateName == "SEARCH" or stateName == "TRACKING" then return activeProfile.SearchSpeed end
	if stateName == "CHASE" then return activeProfile.ChaseSpeed end
	if stateName == "ATTACK_WINDUP" then return activeProfile.PatrolSpeed end
	return 0
end


local function chooseFinalHallSpawn(manifest: any, generation: number): any?
	local records = eligibleSpawnPlayers()
	if #records == 0 then return nil end
	local hall = manifest.FinalHall
	local entry = manifest.MazeStart
	if type(hall) ~= "table" or not entry or not entry.Parent then return nil end
	local state = stateFolder()
	local cycle = math.floor(tonumber(state:GetAttribute("Level3_RoomSongCycle")) or 0)
	local random = Random.new(generation * 7919 + cycle * 104729 + 20260824)
	-- The finale starts at the player's Level 3 entrance, never beside the exit.
	-- Try a few clear points just inside the arrival room, avoiding the spawn pad.
	local position: Vector3? = nil
	local overlap = spawnOverlapParams(records)
	for _, distance in ipairs({8, 12, 16, 20}) do
		local candidate = entry.Position + entry.CFrame.LookVector * distance
		candidate = Vector3.new(candidate.X, hall.FloorY, candidate.Z)
		if spawnVolumeFits(candidate, overlap) then position = candidate; break end
	end
	if not position then
		warn("[Level 3 Mall Manager] level-entry finale spawn volume is blocked")
		return nil
	end
	table.sort(records, function(a, b)
		local aDistance = planarDistance(position, a.Position)
		local bDistance = planarDistance(position, b.Position)
		if math.abs(aDistance - bDistance) > .001 then return aDistance < bDistance end
		return a.Player.UserId < b.Player.UserId
	end)
	local anchor = records[1]
	local centroid = Vector3.zero
	local nearestDistance = math.huge
	for _, record in ipairs(records) do
		centroid += record.Position
		nearestDistance = math.min(nearestDistance, planarDistance(position, record.Position))
	end
	centroid /= #records
	return {
		Position = position,
		Anchor = anchor,
		GroupSize = #records,
		Centroid = centroid,
		Cycle = cycle,
		RoomId = nearestRoomId(position),
		Random = random,
		-- The spawn volume was genuinely swept clear above; route reachability is
		-- proven later by the authoritative full-route sweep (markPathValidated).
		SpawnClearanceValidated = true,
		Visibility = spawnVisibilityCount(position, records),
		NearestDistance = nearestDistance,
		AnchorDistance = planarDistance(position, anchor.Position),
		FinalHallChase = true,
	}
end



local session=makeSession()
local first=player(1,106)
local laggard=player(2,-50)
Players.players={first,laggard}
session.ExitUnlocked=false
updateFinalHallChase(session)
check(not session.FinalHallChaseTriggered,'started before CDs unlocked exit')
session.ExitUnlocked=true; session.State.attrs.Level3_RoomSongPhase='BLACKOUT'
updateFinalHallChase(session)
check(not session.FinalHallChaseTriggered,'normal gameplay changed')
session.State.attrs.Level3_RoomSongPhase='DONE'
first.root.Position=Vector3.new(102,3,0)
updateFinalHallChase(session)
check(not session.FinalHallChaseTriggered,'started outside entry commitment')
first.root.Position=Vector3.new(106,3,80)
updateFinalHallChase(session)
check(not session.FinalHallChaseTriggered,'started outside hall width')
first.root.Position=Vector3.new(106,3,0); first.dead=true
updateFinalHallChase(session)
check(not session.FinalHallChaseTriggered,'dead player triggered finale')
first.dead=false; first.lobby=true
updateFinalHallChase(session)
check(not session.FinalHallChaseTriggered,'lobby player triggered finale')
first.lobby=false
updateFinalHallChase(session)
check(session.FinalHallChaseTriggered,'first runner did not trigger with laggard still outside')
check(session.FinalHallCrossedCount==1 and session.FinalHallEligibleCount==2,'cohort diagnostic counts wrong')
check(workspace.order[#workspace.order-1]=='Level3FinalHallChaseActive' and workspace.order[#workspace.order]=='Level3MallManagerHuntActive','spawn mode must precede lifecycle edge')
local writes=#workspace.order
updateFinalHallChase(session)
check(#workspace.order==writes,'finale triggered twice')
currentRecords={{Player=first,Position=first.root.Position},{Player=laggard,Position=laggard.root.Position}}
local spawn=chooseFinalHallSpawn(session.Manifest,12)
check(spawn~=nil and spawn.Position.X==-188 and spawn.Position.Y==0,'spawn not at first clear level-entry point')
check(spawn.RoomId=='Arrival' and spawn.FinalHallChase,'wrong spawn mode/room')
check(spawn.Anchor.Player==laggard,'hunt anchor is not nearest living player')
check(spawn.SpawnClearanceValidated,'spawn clearance not checked')
blocked=true
check(chooseFinalHallSpawn(session.Manifest,12)==nil,'blocked entry must retry, not teleport to exit')
blocked=false; currentRecords={}
check(chooseFinalHallSpawn(session.Manifest,12)==nil,'spawned without living player')
check(not insideFinalHall(session,session.Manifest.MazeStart.Position),'entry treated as direct hall route')
check(insideFinalHall(session,Vector3.new(150,0,0)),'hall position rejected')
check(not insideFinalHall(session,Vector3.new(150,0,100)),'unrelated parallel room treated as hall')
session.Manifest.EscapeTrigger={Position=Vector3.new(715,0,0)}
check(insideFinalHall(session,Vector3.new(714,0,0)),'runner beyond authored hall end lost before escape sensor')
check(not insideFinalHall(session,Vector3.new(750,0,0)),'lane extends indefinitely beyond exit')
session.Root={Position=Vector3.new(-180,0,0)}
session.State='CHASE';session.Blackout=true
check(currentSpeed(session)==31.2,'ordinary blackout chase changed')
session.Blackout=false
check(currentSpeed(session)==22,'ordinary chase changed')
session.FinalHallChase=true
check(currentSpeed(session)==360,'finale approach did not accelerate')
session.Root.Position=Vector3.new(102,0,0)
for _,runnerX in ipairs({190,240,300}) do
 session.FinaleHallSpeed=nil
 local targetRoot={Position=Vector3.new(runnerX,0,0)}
 session.Target={Character={FindFirstChild=function() return targetRoot end}}
 local speed=currentSpeed(session)
 local runnerTime=(715-runnerX)/26
 check(math.abs((715-102)/speed-runnerTime-1)<.001,'layout changed sprint escape margin')
 targetRoot.Position=Vector3.new(runnerX+50,0,0)
 check(currentSpeed(session)==speed,'pursuit slowed down to let a hesitant runner escape')
end
print('PASS Level 3 finale: '..checks..' scenario assertions; normal spawn/gameplay source unchanged')
