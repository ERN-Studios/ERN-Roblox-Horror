-- Read-only observation for an existing Studio session. Does not start Play,
-- move characters, fire events, create Instances, or modify GUI/state.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HS = game:GetService("HttpService")
assert(game.PlaceId == 131311258779917 and game.GameId == 10559217407, "Wrong place")
local function vec(v) return {v.X, v.Y, v.Z} end
local result = {scope=RunService:IsClient() and "client" or "server", level3QueuePads={}, players={}}
local lobby = workspace:FindFirstChild("LobbyReimaginedPreview")
result.lobbyReady = lobby ~= nil and lobby:GetAttribute("Ready") == true
if lobby then
    for _, object in ipairs(lobby:GetDescendants()) do
        if object:IsA("BasePart") and object:GetAttribute("LevelNumber") == 3
            and type(object:GetAttribute("R3QueueId")) == "number" then
            table.insert(result.level3QueuePads, {path=object:GetFullName(), queueId=object:GetAttribute("R3QueueId"),
                displayIndex=object:GetAttribute("QueueDisplayIndex"), position=vec(object.Position),
                radius=object:GetAttribute("QueueRadius"), size=vec(object.Size),
                characterRootStandingPosition=vec(object.Position+Vector3.new(0,3,0))})
        end
    end
    table.sort(result.level3QueuePads,function(a,b) return a.queueId < b.queueId end)
end
for _, player in ipairs(Players:GetPlayers()) do
    local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    local row={userId=player.UserId,name=player.Name,inRound=player:GetAttribute("InRound"),
        position=root and vec(root.Position) or nil}
    local pg=player:FindFirstChildOfClass("PlayerGui")
    local gui=pg and pg:FindFirstChild("RoundGui")
    local shade=gui and gui:FindFirstChild("QueueHostShade")
    local panel=shade and shade:FindFirstChild("QueueHostPanel")
    if panel then
        local station=panel:FindFirstChild("StationLabel")
        local count=panel:FindFirstChild("PlayerCount")
        row.hostUI={path=panel:GetFullName(),visible=shade.Visible,launchModes=shade:GetAttribute("QueueLaunchModes"),
            station=station and station.Text or nil,playerCount=count and count.Text or nil,controls={}}
        for _, name in ipairs({"DecreasePlayers","IncreasePlayers","PrivacyToggle","CreateParty","CloseQueue"}) do
            local control=panel:FindFirstChild(name)
            if control and control:IsA("GuiButton") then
                row.hostUI.controls[name]={text=control:IsA("TextButton") and control.Text or nil,
                    active=control.Active,visible=control.Visible,
                    centerPixels={control.AbsolutePosition.X+control.AbsoluteSize.X*.5,
                        control.AbsolutePosition.Y+control.AbsoluteSize.Y*.5},
                    sizePixels={control.AbsoluteSize.X,control.AbsoluteSize.Y}}
            end
        end
    else row.hostUIUnavailable="Client-created RoundGui may be invisible from a server query; inspect the client session" end
    table.insert(result.players,row)
end
print(HS:JSONEncode(result))
return result
