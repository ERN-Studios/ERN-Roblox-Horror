local S=require(game.ServerScriptService.ZyntraDetectorSensing) local C=require(game.ReplicatedStorage.ZyntraConfig).Detector local CS=game:GetService("CollectionService")
local fixture=Instance.new("Folder") fixture.Name="DetectorTestFixtures" fixture.Parent=workspace
local model=Instance.new("Model") model.Name="DetectorProbe" model.Parent=fixture local root=Instance.new("Part") root.Anchored=true root.CanCollide=false root.Parent=model model.PrimaryPart=root local hum=Instance.new("Humanoid") hum.Parent=model
local p=game.Players:GetPlayers()[1] local pos=p.Character.HumanoidRootPart.Position
CS:AddTag(model,"Level2HostileEntity")
local results={} for _,pair in {{15,"HIGH"},{40,"MEDIUM"},{80,"LOW"}} do root.Position=pos+Vector3.new(pair[1],0,0) local value=S.Read(pos,2,C) assert(value==pair[2],value) table.insert(results,value) end
hum.Health=0 assert(S.Read(pos,2,C)=="LOW") hum:Destroy()
model:SetAttribute("ZyntraDetectorLevel",4) CS:AddTag(model,"ZyntraDetectableEntity") root.Position=pos+Vector3.new(15,0,0) assert(S.Read(pos,4,C)=="HIGH") model.Parent=game.ServerStorage assert(S.Read(pos,4,C)=="LOW") model.Parent=fixture
workspace:SetAttribute("SelectedLevel",4) workspace:SetAttribute("RoundActive",true) workspace:SetAttribute("RoundLoadingState","ready") p:SetAttribute("InRound",true) p:SetAttribute("RoundEntryControlsReady",true) p:SetAttribute("Escaped",false)
return game.HttpService:JSONEncode({bands=results,deadIgnored=true,despawnedIgnored=true,futureEntityTag=true})
