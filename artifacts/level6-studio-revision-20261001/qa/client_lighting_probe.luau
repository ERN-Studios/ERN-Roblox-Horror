-- Read-only CLIENT probe. Compare the same fixture before/during/after blackout.
-- Local client material changes cannot be certified from a server snapshot.
local HttpService=game:GetService("HttpService")
local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local player=assert(Players.LocalPlayer,"CLIENT context required")
local root=player.Character and player.Character:FindFirstChild("HumanoidRootPart")
local world=workspace:FindFirstChild("Level 6 Generated World")
local state=ReplicatedStorage:FindFirstChild("Level 6 State")
local out={phase=state and state:GetAttribute("Level6_RoomSongPhase") or nil,
    blackout=state and state:GetAttribute("Level6_BlackoutActive") or nil,
    exitUnlocked=state and state:GetAttribute("Level6_ExitUnlocked") or nil,
    lights={total=0,enabled=0}, fixtureSamples={}, gatewayGlowSamples={}}
local function sample(part)
    local children={}
    for _, child in ipairs(part:GetChildren()) do
        if child:IsA("MeshPart") and child:GetAttribute("Level6_KitVisualChunk")==true then
            table.insert(children,{name=child.Name,material=child.Material.Name,
                variant=child.MaterialVariant,transparency=child.Transparency})
        end
    end
    return {path=part:GetFullName(),material=part.Material.Name,
        transparency=part.Transparency,children=children,
        straightLineStuds=root and math.round((part.Position-root.Position).Magnitude*10)/10 or nil}
end
if world then
    for _, item in ipairs(world:GetDescendants()) do
        if item:IsA("Light") then
            out.lights.total+=1
            if item.Enabled then out.lights.enabled+=1 end
        elseif item:IsA("BasePart") and item:GetAttribute("Level6_KitAsset")=="FluorescentDiffuser"
            and item:GetAttribute("Level6_KitVisual")==true then
            table.insert(out.fixtureSamples,sample(item))
        elseif item:IsA("BasePart") and item:GetAttribute("Level6_BlenderGatewayRoom")==true then
            local glow=sample(item)
            local onlyGlow={}
            for _, child in ipairs(glow.children) do
                if child.name:sub(-6)=="__glow" then table.insert(onlyGlow,child) end
            end
            glow.children=onlyGlow
            table.insert(out.gatewayGlowSamples,glow)
        end
    end
end
table.sort(out.fixtureSamples,function(a,b) return (a.straightLineStuds or math.huge)<(b.straightLineStuds or math.huge) end)
while #out.fixtureSamples>3 do table.remove(out.fixtureSamples) end
table.sort(out.gatewayGlowSamples,function(a,b) return (a.straightLineStuds or math.huge)<(b.straightLineStuds or math.huge) end)
while #out.gatewayGlowSamples>3 do table.remove(out.gatewayGlowSamples) end
return HttpService:JSONEncode(out)
