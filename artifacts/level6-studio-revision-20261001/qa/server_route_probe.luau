-- Read-only live SERVER probe. Run after actual E entry or a real gameplay action.
-- Distances are straight-line hints for walking; they are not navigable paths.
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local state = ReplicatedStorage:FindFirstChild("Level 6 State")
local world = workspace:FindFirstChild("Level 6 Generated World")
local player = Players:FindFirstChild("ZenMeister02") or Players:GetPlayers()[1]
local root = player and player.Character and player.Character:FindFirstChild("HumanoidRootPart")

local function xyz(v)
    return if typeof(v) == "Vector3" then {math.round(v.X*10)/10, math.round(v.Y*10)/10, math.round(v.Z*10)/10} else nil
end
local function distance(v)
    return if root and typeof(v) == "Vector3" then math.round((root.Position-v).Magnitude*10)/10 else nil
end
local function promptInfo(prompt)
    if not (prompt and prompt:IsA("ProximityPrompt")) then return nil end
    local part = prompt.Parent
    if not (part and part:IsA("BasePart")) then return nil end
    return {path=prompt:GetFullName(), action=prompt.ActionText, object=prompt.ObjectText,
        enabled=prompt.Enabled, position=xyz(part.Position), straightLineStuds=distance(part.Position),
        maxActivationDistance=prompt.MaxActivationDistance, holdSeconds=prompt.HoldDuration}
end
local out = {player=player and player.Name or nil, position=root and xyz(root.Position) or nil,
    seed=state and state:GetAttribute("Level6_ResolvedSeed") or nil,
    layoutHash=state and state:GetAttribute("Level6_LayoutHash") or nil,
    generation=world and world:GetAttribute("Level6_Generation") or nil,
    generatedRooms=state and state:GetAttribute("Level6_GeneratedRoomCount") or nil,
    cds={}, nearestHide={}, gateways={}, vcr=nil, escape=nil, returnPrompt=nil, manager={}}
for index=1,5 do
    local prefix="Level6_CD"..index
    local pos=state and state:GetAttribute(prefix.."Position")
    out.cds[index]={index=index, state=state and state:GetAttribute(prefix.."State") or nil,
        room=state and state:GetAttribute(prefix.."Room") or nil,
        position=xyz(pos), straightLineStuds=distance(pos), prompt=nil}
end
if state then
    for _, suffix in ipairs({"State", "HuntActive", "PathStatus", "PathValidated",
        "TargetMode", "TargetDistance", "SpawnSerial", "AttackSerial", "FootstepSerial"}) do
        out.manager[suffix]=state:GetAttribute("Level6_MallManager"..suffix)
    end
    out.phase=state:GetAttribute("Level6_RoomSongPhase")
    out.hiddenPlayers=state:GetAttribute("Level6_HiddenPlayers")
    out.collected=state:GetAttribute("Level6_CDCollectedProgress")
    out.inserted=state:GetAttribute("Level6_CDInsertedProgress")
    out.carried=state:GetAttribute("Level6_CDCarriedCount")
    out.exitUnlocked=state:GetAttribute("Level6_ExitUnlocked")
end
if world then
    for _, item in ipairs(world:GetDescendants()) do
        if item:IsA("ProximityPrompt") then
            if item.Name=="CollectPrompt" then
                local ancestor=item.Parent
                while ancestor and ancestor~=world and ancestor:GetAttribute("Level6_CDIndex")==nil do ancestor=ancestor.Parent end
                local index=ancestor and tonumber(ancestor:GetAttribute("Level6_CDIndex"))
                if index and out.cds[index] then out.cds[index].prompt=promptInfo(item) end
            elseif item.Name=="InsertCDPrompt" then out.vcr=promptInfo(item)
            elseif item.Name=="HideUnderTablePrompt" then table.insert(out.nearestHide, promptInfo(item))
            elseif item.Name=="Level6DeveloperPreviewReturnPrompt" then out.returnPrompt=promptInfo(item) end
        elseif item:IsA("BasePart") and item.Name=="EscapeTrigger" then
            out.escape={path=item:GetFullName(), position=xyz(item.Position),
                straightLineStuds=distance(item.Position), canTouch=item.CanTouch}
        elseif item:IsA("BasePart") and item:GetAttribute("Level6_BlenderGatewayRoom")==true then
            table.insert(out.gateways,{family=item.Name, linkId=item:GetAttribute("Level6_BlenderLinkId"),
                sectionIndex=item:GetAttribute("Level6_BlenderSectionIndex"),
                position=xyz(item.Position), straightLineStuds=distance(item.Position)})
        end
    end
end
table.sort(out.nearestHide,function(a,b) return (a.straightLineStuds or math.huge)<(b.straightLineStuds or math.huge) end)
while #out.nearestHide>3 do table.remove(out.nearestHide) end
table.sort(out.gateways,function(a,b) return (a.sectionIndex or 0)<(b.sectionIndex or 0) end)
return HttpService:JSONEncode(out)
