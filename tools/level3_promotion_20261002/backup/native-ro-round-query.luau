-- Read-only observations from an already-built Level 3 round. GetManifest and
-- GetSnapshot are the existing cached runtime read APIs. No Debug hooks,
-- player movement, events, Play-start, state writes, or automated assertions.
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local SSS=game:GetService("ServerScriptService")
local HS=game:GetService("HttpService")
assert(game.PlaceId==131311258779917 and game.GameId==10559217407,"Wrong place")
local function clean(v)
    local t=typeof(v)
    if t=="Vector3" then return {v.X,v.Y,v.Z} end
    if t=="CFrame" then return {v:GetComponents()} end
    if t=="Instance" then return v:GetFullName() end
    if t=="EnumItem" then return tostring(v) end
    if t=="table" then local out={} for k,x in pairs(v) do out[k]=clean(x) end return out end
    return v
end
local world=workspace:FindFirstChild("Level 3 Generated World")
local state=RS:FindFirstChild("Level 3 State")
local result={selectedLevel=workspace:GetAttribute("SelectedLevel"),roundActive=workspace:GetAttribute("RoundActive"),
    worldPresent=world~=nil,state=state and clean(state:GetAttributes()) or nil,players={}}
for _, player in ipairs(Players:GetPlayers()) do
    local char=player.Character
    local hum=char and char:FindFirstChildOfClass("Humanoid")
    local root=char and char:FindFirstChild("HumanoidRootPart")
    table.insert(result.players,{userId=player.UserId,name=player.Name,inRound=player:GetAttribute("InRound"),
        escaped=player:GetAttribute("Escaped"),health=hum and hum.Health or nil,position=root and clean(root.Position) or nil,
        room=player:GetAttribute("Level3_Room"),heldCDCount=player:GetAttribute("Level3_HeldCDCount"),
        heldCDMask=player:GetAttribute("Level3_HeldCDMask")})
end
if not world or result.selectedLevel~=3 or result.roundActive~=true then
    result.note="No active built Level 3 round; cached runtime APIs were not required"
    print(HS:JSONEncode(result));return result
end
local systems=assert(SSS:FindFirstChild("Level 3 Systems"))
local function cached(name) return require(assert(systems:FindFirstChild(name),"Missing runtime API "..name)) end
local manifest=assert(cached("Level 3 Round Adapter").GetManifest(),"Active world has no manifest")
result.worldAttributes=clean(world:GetAttributes())
result.objectives=clean(cached("Level 3 Objective Controller").GetSnapshot())
local entitySnapshot=cached("Level 3 Mall Manager AI Controller").GetSnapshot()
if entitySnapshot then
    result.entity={}
    for _, key in ipairs({"Generation","State","Position","TargetUserId","TargetMode","TargetDistance",
        "FinalHallChase","Blackout","DesiredSpeed","MovementSpeed","SpawnSerial","SpawnRoomId","SpawnDistance",
        "SpawnAnchorUserId","SpawnGroupSize","SpawnCycle","PathStatus","PathComputing","PathFailures",
        "PathComputeSerial","PathComputesLastSecond","PeakConcurrentPathComputes","StuckRecoveries",
        "GenuineProgressSerial","LastGenuineProgressAgeSeconds","FootstepSerial","ChaseScreamSerial"}) do
        result.entity[key]=clean(entitySnapshot[key])
    end
else result.entityAbsent=true end
result.cdPrompts={}
for _, module in ipairs(manifest.Modules) do
    local p=module.Prompt
    local parent=p.Parent
    local pos=parent:IsA("BasePart") and parent.Position or parent:IsA("Attachment") and parent.WorldPosition or nil
    table.insert(result.cdPrompts,{index=module.Index,roomId=module.RoomId,path=p:GetFullName(),enabled=p.Enabled,
        position=clean(pos),key=tostring(p.KeyboardKeyCode),holdSeconds=p.HoldDuration,
        maxDistance=p.MaxActivationDistance,lineOfSight=p.RequiresLineOfSight,state=module.Model:GetAttribute("Level3_CDState")})
end
local insert=manifest.DiscPlayer.Prompt
result.insertPrompt={path=insert:GetFullName(),position=clean(insert.Parent.Position),enabled=insert.Enabled,
    key=tostring(insert.KeyboardKeyCode),holdSeconds=insert.HoldDuration,maxDistance=insert.MaxActivationDistance}
local hall=manifest.FinalHall
local f=Vector3.new(hall.Forward.X,0,hall.Forward.Z).Unit
local half=hall.Length*(hall.HalfwayProgress or .5)
local function positionAt(distance) return hall.StartPoint+f*distance+Vector3.new(0,3,0) end
result.finalHall={length=hall.Length,width=hall.Width,height=hall.Height,floorY=hall.FloorY,
    startPoint=clean(hall.StartPoint),endPoint=clean(hall.EndPoint),forward=clean(f),halfDistance=half,
    firstPlayerBeforeHalf=clean(positionAt(half-1)),firstPlayerAtExactHalf=clean(positionAt(half)),
    firstPlayerBeyondHalf=clean(positionAt(half+1)),secondPlayerBehindHalf=clean(positionAt(half-8)),
    finaleSpawn=clean(hall.SpawnMarker.Position),strictCondition="along > halfDistance; any first eligible living survivor",
    triggerGates="ExitUnlocked and Level3_RoomSongPhase == DONE"}
for index,player in ipairs(Players:GetPlayers()) do
    local root=player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    if root then
        local offset=Vector3.new(root.Position.X-hall.StartPoint.X,0,root.Position.Z-hall.StartPoint.Z)
        result.players[index].hallAlong=offset:Dot(f)
        result.players[index].hallLateral=(offset-f*offset:Dot(f)).Magnitude
        result.players[index].hallAboveHalf=offset:Dot(f)>half
    end
end
local trigger=manifest.EscapeTrigger
local safe=manifest.ExitSafeSpawn
result.freightExit={triggerPath=trigger:GetFullName(),triggerCenter=clean(trigger.Position),triggerSize=clean(trigger.Size),
    canTouch=trigger.CanTouch,exitUnlocked=state:GetAttribute("Level3_ExitUnlocked"),
    firstEscapeWaitingPosition=clean((safe.CFrame*CFrame.new(-6,3,-4)).Position),
    secondEscapeWaitingPosition=clean((safe.CFrame*CFrame.new(0,3,-4)).Position),
    acceptance="Living character root must be inside trigger CFrame half-size bounds; touching a limb alone is insufficient"}
result.representativeRooms={}
for district=1,3 do
    local chosen
    for _, room in ipairs(manifest.Layout.Rooms) do
        if room.SectionIndex==district and room.Id~=manifest.Layout.Roles.ExitRoomId then chosen=room;break end
    end
    if chosen then
        local model=manifest.Rooms[chosen.Id]
        local floor=model:FindFirstChild("Level 3 Room Floor")
        local textures={}
        for _, object in ipairs(model:GetDescendants()) do
            if object:IsA("Texture") and #textures<4 then
                table.insert(textures,{path=object:GetFullName(),id=object.Texture,face=tostring(object.Face)})
            end
        end
        table.insert(result.representativeRooms,{id=chosen.Id,district=district,theme=chosen.ThemeId,kind=chosen.Kind,
            decor=chosen.Decor,path=model:GetFullName(),floorPosition=clean(floor.Position),
            characterStandingPosition=clean(floor.Position+Vector3.new(0,3.5,0)),size=clean(floor.Size),textures=textures})
    end
end
print(HS:JSONEncode(result))
return result
