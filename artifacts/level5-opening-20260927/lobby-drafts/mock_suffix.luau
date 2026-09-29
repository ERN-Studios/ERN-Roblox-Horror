local function object(class,name,parent) local o=Instance.new(class);o.Name=name;o.Parent=parent;return o end
local lobby=object("Model","Lobby")
local rooms=object("Folder","LevelQueueRooms",lobby)
local room=object("Model","Level5QueueRoom",rooms)
room:SetAttribute("LevelNumber",5);room:SetAttribute("CircularBayDiameter",56)
local doors=object("Folder","LevelDoorways",lobby)
local header=object("Part","Level5Information",doors);header.CFrame=CFrame.new(-26.5,15.8,80)
local center=Vector3.new(-63,0,80)
local floor=object("Part","ChamberFloor",room);floor.CFrame=CFrame.new(center+Vector3.new(0,-.42,0))
local ceiling=object("Part","ChamberCeiling",room);ceiling.CFrame=CFrame.new(center+Vector3.new(0,22.6,0))
local stations={}
for index=17,20 do
    local p=object("Part","LaunchZone"..index,room);p.CFrame=CFrame.new(center);p:SetAttribute("Keep",index);stations[index]=p
end
local generic=object("Part","ChamberLight",room)
local genericLight=object("PointLight","PointLight",generic);genericLight.Enabled=true
local decor=Builder.RefreshLevelFiveRoom(room)
local count=#allParts
local minClearance=math.huge
local radius=0
for _,p in ipairs(allParts) do
    check(not p.CanCollide and not p.CanTouch and not p.CanQuery,"Decor has gameplay collision/query/touch")
    for _,x in ipairs({-1,1}) do for _,y in ipairs({-1,1}) do for _,z in ipairs({-1,1}) do
        local point=(p.CFrame*CFrame.new(p.Size.X*x/2,p.Size.Y*y/2,p.Size.Z*z/2)).Position-center
        local radial=math.sqrt(point.X*point.X+point.Z*point.Z)
        radius=math.max(radius,radial)
        check(radial<27.375,"Decor exceeds inner chamber wall")
        check(point.Y>.28 and point.Y<21.7,"Decor intersects floor or ceiling")
        if point.Y<10 then
            local outward=-point.X
            check(outward>16.41,"Low decor enters queue detector X envelope")
            minClearance=math.min(minClearance,outward-16.41)
        end
    end end end
end
check(count<=90,"Lobby decor budget exceeded")
check(generic.Transparency==1 and genericLight.Enabled==false,"Generic fixture not hidden/disabled")
local nextDecor=Builder.RefreshLevelFiveRoom(room)
check(decor.destroyed and nextDecor~=decor,"Repeated styling did not replace only owned decor")
check(#nextDecor:GetChildren()==#allParts-count,"Repeated style multiplied parts")
for index=17,20 do check(room:FindFirstChild("LaunchZone"..index)==stations[index] and stations[index]:GetAttribute("Keep")==index,"Station changed") end
local floorTextures=0
for _,c in ipairs(floor:GetChildren()) do if c:IsA("Texture") then floorTextures+=1 end end
check(floorTextures==1,"Repeated styling multiplied floor textures")
nextDecor:SetAttribute("LobbyBayDecorLevel",nil)
local ok=pcall(Builder.RefreshLevelFiveRoom,room)
check(not ok and not nextDecor.destroyed,"Unowned decoration was overwritten")
nextDecor:SetAttribute("LobbyBayDecorLevel",5)
room:SetAttribute("CircularBayDiameter",60)
ok=pcall(Builder.RefreshLevelFiveRoom,room)
check(not ok and not nextDecor.destroyed,"Changed geometry was styled without review")
room:SetAttribute("CircularBayDiameter",56)
room:SetAttribute("LevelEnabled",false)
local offsets={Vector3.new(-9,.18,-13.2),Vector3.new(9,.18,-13.2),Vector3.new(-9,.18,13.2),Vector3.new(9,.18,13.2)}
local titles,subtitles={},{}
for displayIndex=1,4 do
    local index=16+displayIndex
    local detector=stations[index]
    detector.Name="FutureLaunchZone"..index;detector.CFrame=CFrame.new(center+offsets[displayIndex]);detector.Size=Vector3.new(14.82,.3,14.82);detector.CanCollide=false
    local sign=object("Part","Station"..index.."Sign",room)
    local display=object("SurfaceGui","Display",sign)
    local title=object("TextLabel","Title",display);title.Text="STATION "..displayIndex.."  •  OFFLINE";title.TextColor3=Color3.fromRGB(255,183,72);titles[index]=title
    local subtitle=object("TextLabel","Subtitle",display);subtitle.Text="AWAITING LEVEL AUTHORIZATION";subtitles[index]=subtitle
end
Builder.RefreshLevelFiveRoom(room)
for index=17,20 do check(room:FindFirstChild("FutureLaunchZone"..index)==stations[index],"Cosmetic refresh renamed Future detector") end
subtitles[20].Text="Unrelated developer edit"
ok=pcall(Builder.ActivateLevelFiveStations,room)
check(not ok and room:FindFirstChild("FutureLaunchZone17")==stations[17] and room:GetAttribute("LevelEnabled")==false,"Failed preflight partially activated room")
subtitles[20].Text="AWAITING LEVEL AUTHORIZATION"
local activation=Builder.ActivateLevelFiveStations(room)
check(room:GetAttribute("LevelEnabled")==true,"Room did not activate")
for index=17,20 do
    check(room:FindFirstChild("LaunchZone"..index)==stations[index],"Activation replaced detector identity")
    check(activation.stations[index].zone==stations[index] and activation.stations[index].title==titles[index],"Activation did not return existing queue references")
    check(subtitles[index].Text=="ENTER TO HOST  •  MAX 6 PLAYERS","Activation did not update offline subtitle")
end
local repeatActivation=Builder.ActivateLevelFiveStations(room)
check(#repeatActivation.receipt.changes==0,"Repeated activation rewrote active stations")
titles[18].Text="New player queue state"
ok=pcall(Builder.RestoreLevelFiveStationActivation,activation.receipt)
check(not ok and room:FindFirstChild("LaunchZone17")==stations[17],"Stale rollback partially changed station")
titles[18].Text="STATION 2  •  0/6"
check(Builder.RestoreLevelFiveStationActivation(activation.receipt),"Clean rollback failed")
check(room:GetAttribute("LevelEnabled")==false,"Rollback lost prior false attribute")
for index=17,20 do
    check(room:FindFirstChild("FutureLaunchZone"..index)==stations[index],"Rollback replaced detector identity")
    check(subtitles[index].Text=="AWAITING LEVEL AUTHORIZATION","Rollback lost original label")
end
print(string.format("PASS: %d assertions; %d decorative parts; max radius %.3f / 27.375 studs; low-part queue clearance >= %.3f studs",assertions,count,radius,minClearance))
print("Offline transforms/ownership only. No native rendering, texture load, queue entry, or walk test was performed.")
