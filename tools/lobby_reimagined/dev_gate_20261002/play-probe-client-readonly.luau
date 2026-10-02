-- Read-only actual Client datamodel inspection. Does not move the camera/avatar.
local Players, HS = game:GetService("Players"), game:GetService("HttpService")
local player = Players.LocalPlayer
local model = workspace:FindFirstChild("LobbyReimaginedPreview")
local folder = model and model:FindFirstChild("R4ClientDevGates")
local function vector(v) return {v.X, v.Y, v.Z} end
local output = {scope="Read-only actual Studio Client scene/prompt inspection; not a connected nondeveloper or multiplayer test",
	placeId=game.PlaceId, universeId=game.GameId, playerName=player.Name, userId=player.UserId,
	modelReady=model and model:GetAttribute("Ready") == true or false,
	modelRevision=model and model:GetAttribute("LobbyVisualRevision"),
	localFolderPresent=folder ~= nil, gates={}, blockers={}, originalLobbyHasLocalGateFolder=false}
local lobby = workspace:FindFirstChild("ServerLobby")
output.originalLobbyHasLocalGateFolder=lobby and lobby:FindFirstChild("R4ClientDevGates") ~= nil or false
if folder then
	output.localFolderOwned=folder:GetAttribute("R4DevGateControllerOwned") == true
	output.folderLevel5Allowed=folder:GetAttribute("Level5PreviewAllowed")
	output.folderLevel6Allowed=folder:GetAttribute("Level6PreviewAllowed")
	for _,level in ipairs({5,6}) do
		local gateFolder=folder:FindFirstChild("Level"..level.." Client Gate")
		local signs=model:FindFirstChild("LevelGateSigns")
		local header=signs and signs:FindFirstChild("LEVEL "..level.." Door Header")
		local bay=model:FindFirstChild("QueueBay_Level"..level,true)
		local row={level=level, gatePresent=gateFolder~=nil, mainHeaderPresent=header~=nil,
			previewAllowed=gateFolder and gateFolder:GetAttribute("PreviewAllowed"),
			labelCount=0, hiddenLabelCount=0, promptCount=0, enabledPromptCount=0,
			mainHeaderTexts={}, subtitles={}, shutters={}, mounts={}}
		if header then
			row.mainHeaderSize=vector(header.Size)
			row.mainHeaderPosition=vector(header.Position)
			for _,d in ipairs(header:GetDescendants())do
				if d:IsA("TextLabel")then table.insert(row.mainHeaderTexts,d.Text)end
			end
		end
		local gateFrame=header and header.CFrame*CFrame.new(0,-17.2,-1.42)
		if gateFolder then
			for _,d in ipairs(gateFolder:GetDescendants())do
				if d:IsA("BasePart") then
					local position=gateFrame and gateFrame:PointToObjectSpace(d.Position)
					local record={name=d.Name, size=vector(d.Size), position=vector(d.Position),
						gateLocalPosition=position and vector(position), anchored=d.Anchored,
						colliding=d.CanCollide, touch=d.CanTouch, query=d.CanQuery, transparency=d.Transparency}
					if d.Name=="Coming Soon Shutter" then
						record.localBottomY=position and position.Y-d.Size.Y*.5
						record.localTopY=position and position.Y+d.Size.Y*.5
						local center=model:GetAttribute("PreviewCenter")
						if typeof(center)=="Vector3" then
							local roadward=Vector3.new(center.X-d.Position.X,0,0)
							if roadward.Magnitude>.001 then record.backFaceRoadwardDot=(-d.CFrame.LookVector):Dot(roadward.Unit) end
						end
						table.insert(row.shutters,record)
					elseif d.Name=="Mounted Access Subtitle" then
						record.texts={}
						for _,ui in ipairs(d:GetDescendants())do
							if ui:IsA("TextLabel")then table.insert(record.texts,{text=ui.Text,visible=ui.Visible,textScaled=ui.TextScaled})end
							if ui:IsA("SurfaceGui")then record.face=ui.Face.Name;record.alwaysOnTop=ui.AlwaysOnTop;record.brightness=ui.Brightness;record.lightInfluence=ui.LightInfluence end
						end
						record.headerTextGapY=position and position.Y-d.Size.Y*.5-(17.2+header.Size.Y*.5)
						table.insert(row.subtitles,record)
					elseif d.Name=="Status Mount" then table.insert(row.mounts,record)end
				end
			end
		end
		if bay then
			for _,d in ipairs(bay:GetDescendants())do
				if d:IsA("TextLabel") and (d.Name=="QueueTitle" or d.Name=="QueueSubtitle")then
					row.labelCount+=1;if d.Visible==false then row.hiddenLabelCount+=1 end
				elseif d:IsA("ProximityPrompt") and d.Name=="Level"..level.."DeveloperPreviewPrompt"then
					row.promptCount+=1;if d.Enabled then row.enabledPromptCount+=1 end
				end
			end
		end
		table.insert(output.gates,row)
	end
end
local accessModule=game:GetService("ReplicatedStorage"):FindFirstChild("DevAccess")
local ok,policy=pcall(function()
	local access=require(accessModule)
	return {generalDeveloper=access.IsAllowed(player),level6Preview=access.IsLevel6PreviewAllowed(player),
		ordinaryIdDenied=not access.IsAllowed(1) and not access.IsLevel6PreviewAllowed(1)}
end)
output.policyReadOK=ok
if ok then output.policy=policy else output.policyReadError=tostring(policy)end
local character=player.Character
local root=character and character:FindFirstChild("HumanoidRootPart")
local hum=character and character:FindFirstChildOfClass("Humanoid")
output.avatar={position=root and vector(root.Position),health=hum and hum.Health,
	inRound=player:GetAttribute("InRound"),level6InRound=player:GetAttribute("Level6InRound")}
return HS:JSONEncode(output)
