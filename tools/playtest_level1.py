"""Run a bounded Roblox Studio Level 1 smoke test and always return to Edit mode."""

from __future__ import annotations

import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from sync_from_studio import StudioMcpClient, find_mcp_batch, select_studio  # noqa: E402


HEALTH_CODE = r'''
local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")
local entity = workspace:FindFirstChild("Entity")
local elevator = workspace:FindFirstChild("Elevator")
local decor = workspace:FindFirstChild("Decor")
local textureIds = {}
local textureCount = 0
local propTextureCount = 0
local neutralPropTextureCount = 0
local propMaterialCounts = {}
local cardboardPileCount = 0
local cardboardBoxBodyCount = 0
local loosePaperCount = 0
local fingerBoneCount = 0
local eyeGlowCount = 0
local eyeParents = {}
local cableCount = 0
local exactCableOverlapCount = 0
local collinearCableOverlapCount = 0
local collinearCableOverlapPairs = {}
local propModelCount = 0
local propHeightTotal = 0
local propMaxHeight = 0
local plazaPropCount = 0
local decorPuzzleOverlapCount = 0
local plazaPileModelCount = 0
local plazaSightBlockerCount = 0
local plazaPileMinY = math.huge
local plazaPileMaxY = -math.huge
local standaloneChairCount = 0
local miniPropPileModelCount = 0
local miniPropPileGroups = {}
if elevator then
    for _, item in ipairs(elevator:GetDescendants()) do
        if item:IsA("Texture") then
            textureCount += 1
            textureIds[item.Texture] = (textureIds[item.Texture] or 0) + 1
        end
    end
end
local puzzleItems = workspace:FindFirstChild("PuzzleItems")
if puzzleItems then
    local seenCables = {}
    local floorCables = {}
    for _, item in ipairs(puzzleItems:GetDescendants()) do
        if item:IsA("BasePart") and item.Anchored and item.Material == Enum.Material.SmoothPlastic
            and item.Size.Y <= 0.07 and item.Size.X <= 0.26 then
            cableCount += 1
            table.insert(floorCables, item)
            local p = item.Position
            local s = item.Size
            local key = string.format("%.2f,%.2f,%.2f|%.2f,%.2f,%.2f",
                p.X, p.Y, p.Z, s.X, s.Y, s.Z)
            if seenCables[key] then exactCableOverlapCount += 1 end
            seenCables[key] = true
        end
    end
    for ai = 1, #floorCables - 1 do
        local a = floorCables[ai]
        local au = Vector3.new(a.CFrame.LookVector.X, 0, a.CFrame.LookVector.Z).Unit
        local aperp = Vector3.new(-au.Z, 0, au.X)
        for bi = ai + 1, #floorCables do
            local b = floorCables[bi]
            local bu = Vector3.new(b.CFrame.LookVector.X, 0, b.CFrame.LookVector.Z).Unit
            if math.abs(au:Dot(bu)) > 0.999 then
                local delta = b.Position - a.Position
                local centreGap = math.abs(delta:Dot(aperp))
                if centreGap < (a.Size.X + b.Size.X) * 0.5 - 0.01 then
                    local along = delta:Dot(au)
                    local overlap = math.min(a.Size.Z * 0.5, along + b.Size.Z * 0.5)
                        - math.max(-a.Size.Z * 0.5, along - b.Size.Z * 0.5)
                    if overlap > 0.05 then
                        collinearCableOverlapCount += 1
                        table.insert(collinearCableOverlapPairs, {
                            a = { a.Position.X, a.Position.Z, a.Size.Z,
                                a.Color.R, a.Color.G, a.Color.B },
                            b = { b.Position.X, b.Position.Z, b.Size.Z,
                                b.Color.R, b.Color.G, b.Color.B },
                            centreGap = centreGap,
                            overlap = overlap,
                        })
                    end
                end
            end
        end
    end
end
if decor then
	for _, child in ipairs(decor:GetChildren()) do
		if child:IsA("BasePart") and child:GetAttribute("BlocksEntitySight") == true then
			plazaSightBlockerCount += 1
		end
		if child:IsA("Model") then
			if child:GetAttribute("MiniPropPile") == true then
				miniPropPileModelCount += 1
				local group = child:GetAttribute("MiniPropPileIndex")
				if group then miniPropPileGroups[tostring(group)] = true end
			end
			if child.Name == "Chair" and child:GetAttribute("PlazaPile") ~= true then
				standaloneChairCount += 1
			end
			propModelCount += 1
			local cf, size = child:GetBoundingBox()
			propHeightTotal += size.Y
			propMaxHeight = math.max(propMaxHeight, size.Y)
			if child:GetAttribute("PlazaPile") == true then
				plazaPileModelCount += 1
				plazaPileMinY = math.min(plazaPileMinY, cf.Position.Y - size.Y * 0.5)
				plazaPileMaxY = math.max(plazaPileMaxY, cf.Position.Y + size.Y * 0.5)
			end
			local plazaCenter = workspace:GetAttribute("ForcedPlazaCenter")
			if typeof(plazaCenter) == "Vector3"
				and Vector3.new(cf.Position.X - plazaCenter.X, 0, cf.Position.Z - plazaCenter.Z).Magnitude <= 58 then
				plazaPropCount += 1
			end
			if puzzleItems then
				for _, puzzle in ipairs(puzzleItems:GetChildren()) do
					if puzzle:IsA("Model") and (puzzle.Name == "Fuse" or puzzle.Name == "FuseRelay"
						or puzzle.Name == "FuseBox" or puzzle.Name == "Lever") then
						local pcf, ps = puzzle:GetBoundingBox()
						if math.abs(cf.Position.X - pcf.Position.X) < (size.X + ps.X) * 0.5
							and math.abs(cf.Position.Y - pcf.Position.Y) < (size.Y + ps.Y) * 0.5
							and math.abs(cf.Position.Z - pcf.Position.Z) < (size.Z + ps.Z) * 0.5 then
							decorPuzzleOverlapCount += 1
						end
					end
				end
			end
		end
		if child:IsA("Model") and child.Name == "CardboardBoxPile" then
            cardboardPileCount += 1
        end
    end
    for _, item in ipairs(decor:GetDescendants()) do
        if item:IsA("Texture") and item.Name == "PropSurface" then
            propTextureCount += 1
            if item.Color3 == Color3.new(1, 1, 1) then neutralPropTextureCount += 1 end
        elseif item:IsA("BasePart") then
            propMaterialCounts[item.Material.Name] = (propMaterialCounts[item.Material.Name] or 0) + 1
            if item.Name == "BoxBody" then cardboardBoxBodyCount += 1 end
            if item.Name == "LoosePaper" then loosePaperCount += 1 end
        end
    end
end
if entity then
    for _, item in ipairs(entity:GetDescendants()) do
        if item:IsA("Bone") and (string.find(item.Name, "Index", 1, true)
            or string.find(item.Name, "Middle", 1, true)
            or string.find(item.Name, "Ring", 1, true)
            or string.find(item.Name, "Pinky", 1, true)
            or string.find(item.Name, "Thumb", 1, true)) then
            fingerBoneCount += 1
        elseif item.Name == "EyeGlow" and item:IsA("BillboardGui") then
            eyeGlowCount += 1
            table.insert(eyeParents, item.Parent and item.Parent:GetFullName() or "nil")
        end
    end
end
local tracks = {}
if entity then
    local humanoid = entity:FindFirstChildOfClass("Humanoid")
    local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
    if animator then
        for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
            table.insert(tracks, track.Name)
        end
    end
end
return HttpService:JSONEncode({
    entityExists = entity ~= nil,
    entityState = entity and entity:GetAttribute("EntityState") or nil,
    fogStart = Lighting.FogStart,
    fogEnd = Lighting.FogEnd,
    playingTracks = tracks,
    elevatorExists = elevator ~= nil,
    elevatorTextureCount = textureCount,
    elevatorTextureInstances = textureIds,
    propTextureCount = propTextureCount,
    neutralPropTextureCount = neutralPropTextureCount,
    propMaterialCounts = propMaterialCounts,
    cardboardPileCount = cardboardPileCount,
    cardboardBoxBodyCount = cardboardBoxBodyCount,
    loosePaperCount = loosePaperCount,
    fingerBoneCount = fingerBoneCount,
    eyeGlowCount = eyeGlowCount,
    eyeParents = eyeParents,
    lobbySpawnDuration = workspace:FindFirstChild("TunnelLobby", true)
        and workspace:FindFirstChild("LobbySpawn", true)
        and workspace:FindFirstChild("LobbySpawn", true).Duration or nil,
    cableCount = cableCount,
    exactCableOverlapCount = exactCableOverlapCount,
    collinearCableOverlapCount = collinearCableOverlapCount,
	collinearCableOverlapPairs = collinearCableOverlapPairs,
	decorReady = workspace:GetAttribute("DecorReady"),
	propModelCount = propModelCount,
	averagePropHeight = propModelCount > 0 and propHeightTotal / propModelCount or 0,
	propMaxHeight = propMaxHeight,
	plazaPropCount = plazaPropCount,
	decorPuzzleOverlapCount = decorPuzzleOverlapCount,
	clockDongMinSeconds = decor and decor:GetAttribute("ClockDongMinSeconds") or nil,
	clockDongMaxSeconds = decor and decor:GetAttribute("ClockDongMaxSeconds") or nil,
	entityObjectiveStage = workspace:GetAttribute("EntityObjectiveStage"),
	hasEntityObjectiveTarget = typeof(workspace:GetAttribute("EntityObjectiveTarget")) == "Vector3",
	plazaPileModelCount = plazaPileModelCount,
	plazaSightBlockerCount = plazaSightBlockerCount,
	plazaPileHeight = plazaPileModelCount > 0 and plazaPileMaxY - plazaPileMinY or 0,
	plazaHeapCount = workspace:GetAttribute("PlazaHeapCount"),
	standaloneChairCount = standaloneChairCount,
	miniPropPileModelCount = miniPropPileModelCount,
	miniPropPileGroupCount = (function()
		local count = 0
		for _ in pairs(miniPropPileGroups) do count += 1 end
		return count
	end)(),
})
'''


CLIENT_HEALTH_CODE = r'''
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local gui = player.PlayerGui:FindFirstChild("FlashlightPopup")
local torch = gui and gui:FindFirstChild("Silhouette", true)
local rays = 0
if torch then
    for _, item in ipairs(torch:GetDescendants()) do
        if string.find(item.Name, "PowerRay", 1, true) then rays += 1 end
    end
end
local camera = workspace.CurrentCamera
local mount = workspace:FindFirstChild("FlashlightMount")
local body = gui and gui:FindFirstChild("FlashlightPower", true)
local pointLight = mount and mount:FindFirstChildOfClass("PointLight")
local coreLight = mount and mount:FindFirstChildOfClass("SpotLight")
return HttpService:JSONEncode({
    cameraMode = player.CameraMode.Name,
    minZoom = player.CameraMinZoomDistance,
    maxZoom = player.CameraMaxZoomDistance,
    flashlightGui = gui ~= nil,
    torchExists = torch ~= nil,
    rayCount = rays,
    hasCore = mount and mount:FindFirstChildOfClass("SpotLight") ~= nil or false,
    hasPointLight = pointLight ~= nil,
    coreBrightness = coreLight and coreLight.Brightness or 0,
    coreRange = coreLight and coreLight.Range or 0,
    torchRotation = torch and torch.Rotation or nil,
    bodySize = body and {body.AbsoluteSize.X, body.AbsoluteSize.Y} or nil,
    jumpPower = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
        and player.Character:FindFirstChildOfClass("Humanoid").JumpPower or nil,
})
'''


SETUP_LEVEL1_CODE = r'''
local generator = require(game.ServerScriptService.Level2Generator)
generator.Cleanup()
workspace:SetAttribute("GenerateWorld", true)
return "Level 1 requested"
'''


START_PUZZLE_CODE = r'''
local player = game:GetService("Players"):GetPlayers()[1]
if player then player:SetAttribute("InRound", true) end
workspace:SetAttribute("RoundActive", true)
return "Level 1 puzzle requested"
'''


LUNGE_TEST_CODE = r'''
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players:GetPlayers()[1]
if not player then
    return HttpService:JSONEncode({ ok = false, reason = "no player" })
end

if not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then
    player:LoadCharacter()
end
local character = player.Character or player.CharacterAdded:Wait()
local root = character:WaitForChild("HumanoidRootPart", 10)
local humanoid = character:FindFirstChildOfClass("Humanoid")
local entity = workspace:WaitForChild("Entity", 10)
local entityRoot = entity and entity:FindFirstChild("HumanoidRootPart")
if not root or not humanoid or not entityRoot then
    return HttpService:JSONEncode({ ok = false, reason = "missing character or entity" })
end

humanoid.Health = humanoid.MaxHealth
root.Anchored = true

local originalTouch = {}
for _, part in ipairs(entity:GetDescendants()) do
    if part:IsA("BasePart") then
        originalTouch[part] = part.CanTouch
        part.CanTouch = false
    end
end

local origin = workspace:FindFirstChild("EntityStart")
local testFloor = Instance.new("Part")
testFloor.Name = "LungeTestFloor"
testFloor.Anchored = true
testFloor.Size = Vector3.new(90, 1, 30)
testFloor.CFrame = CFrame.new(0, 90, 0)
testFloor.Parent = workspace
local originCFrame = CFrame.lookAt(Vector3.new(0, 96, 0), Vector3.new(0, 96, -1))
entity:PivotTo(originCFrame)
root.CFrame = CFrame.lookAt(
	entityRoot.Position + entityRoot.CFrame.LookVector * 26,
	entityRoot.Position
)

workspace:SetAttribute("TestForceEntityLunge", true)
workspace:SetAttribute("EntityPaused", false)
workspace:SetAttribute("EntityKillActive", false)

local started = false
local startY = entityRoot.Position.Y
local maxRise = 0
local maxVerticalVelocity = -math.huge
local startPosition = entityRoot.Position
local maxHorizontalDistance = 0
local deadline = os.clock() + 12
while os.clock() < deadline do
    RunService.Heartbeat:Wait()
    if workspace:GetAttribute("EntityIsLunging") then
        started = true
        maxRise = math.max(maxRise, entityRoot.Position.Y - startY)
        maxVerticalVelocity = math.max(maxVerticalVelocity, entityRoot.AssemblyLinearVelocity.Y)
        local moved = entityRoot.Position - startPosition
        maxHorizontalDistance = math.max(maxHorizontalDistance,
            Vector3.new(moved.X, 0, moved.Z).Magnitude)
    elseif started then
        break
    end
end

for part, canTouch in pairs(originalTouch) do
    if part.Parent then
        part.CanTouch = canTouch
    end
end
root.Anchored = false
testFloor:Destroy()

return HttpService:JSONEncode({
    ok = started,
    maxRise = maxRise,
    maxVerticalVelocity = maxVerticalVelocity == -math.huge and 0 or maxVerticalVelocity,
    maxHorizontalDistance = maxHorizontalDistance,
    forceAttribute = workspace:GetAttribute("TestForceEntityLunge"),
    lungeAttribute = workspace:GetAttribute("EntityIsLunging"),
    entityPaused = workspace:GetAttribute("EntityPaused"),
    killActive = workspace:GetAttribute("EntityKillActive"),
    entityHealth = entity:FindFirstChildOfClass("Humanoid").Health,
    characterHealth = humanoid.Health,
})
'''


RUN_TEST_CODE = r'''
local H=game:GetService("HttpService")
local RunService=game:GetService("RunService")
local entity=workspace:FindFirstChild("Entity")
local root=entity and entity:FindFirstChild("HumanoidRootPart")
local hum=entity and entity:FindFirstChildOfClass("Humanoid")
local animator=hum and hum:FindFirstChildOfClass("Animator")
local leftKnee=entity and entity:FindFirstChild("LeftLeg",true)
local rightKnee=entity and entity:FindFirstChild("RightLeg",true)
if not (root and animator and leftKnee and rightKnee) then
    return H:JSONEncode({ok=false})
end
workspace:SetAttribute("EntityPaused",true)
workspace:SetAttribute("EntityState","CHASE")
root.Anchored=false
local maxLeftLateral,maxRightLateral=0,0
local name,id="",""
local deadline=os.clock()+1.7
while os.clock()<deadline do
    workspace:SetAttribute("EntityState","CHASE")
    root.AssemblyLinearVelocity=root.CFrame.LookVector*15
    RunService.Heartbeat:Wait()
    maxLeftLateral=math.max(maxLeftLateral,
        math.abs((leftKnee.WorldPosition-root.Position):Dot(root.CFrame.RightVector)))
    maxRightLateral=math.max(maxRightLateral,
        math.abs((rightKnee.WorldPosition-root.Position):Dot(root.CFrame.RightVector)))
    for _,track in ipairs(animator:GetPlayingAnimationTracks()) do
        if string.find(track.Name,"Run",1,true) then
            name=track.Name
            id=track.Animation and track.Animation.AnimationId or id
        end
    end
end
root.AssemblyLinearVelocity=Vector3.zero
workspace:SetAttribute("EntityPaused",false)
return H:JSONEncode({ok=name~="",trackName=name,animationId=id,
    maxLeftKneeLateral=maxLeftLateral,maxRightKneeLateral=maxRightLateral})
'''


INTRO_TICKS_CODE = r'''
local remote = game.ReplicatedStorage.Remotes.RoundStatus
for second = 19, 15, -1 do
    remote:FireAllClients("elevator", second)
    task.wait(0.15)
end
return "elevator ticks sent"
'''


INTRO_HEALTH_CODE = r'''
local HttpService = game:GetService("HttpService")
task.wait(1.5)
local player = game:GetService("Players").LocalPlayer
local gui = player.PlayerGui:FindFirstChild("RoundGui")
local label = gui and gui:FindFirstChildOfClass("TextLabel")
return HttpService:JSONEncode({
    visible = label and label.Visible or false,
    text = label and label.Text or "",
})
'''


def main() -> int:
    client = StudioMcpClient(find_mcp_batch())
    started = False
    try:
        client.initialize()
        time.sleep(3)
        select_studio(client, "BACKROOMS: STAY QUIET [CO-OP HORROR]", 20)
        print("START", client.call("start_stop_play", {"is_start": True}))
        started = True

        deadline = time.monotonic() + 25
        state = ""
        while time.monotonic() < deadline:
            time.sleep(2)
            state = client.call("get_studio_state")
            if "Server" in state:
                break
        print("STATE", state)

        # GameManager sets GenerateWorld=false during its own startup. Let that
        # initialization finish so our explicit Level 1 request cannot be lost
        # to the startup write racing the smoke test.
        time.sleep(4)
        print("SETUP", client.call("execute_luau", {
            "datamodel_type": "Server",
            "code": SETUP_LEVEL1_CODE,
        }))

        # Allow maze generation, elevator construction, and the entity controller to boot.
        time.sleep(25)
        print("PUZZLE", client.call("execute_luau", {
            "datamodel_type": "Server",
            "code": START_PUZZLE_CODE,
        }))
        time.sleep(7)
        print("HEALTH", client.call("execute_luau", {
            "datamodel_type": "Server",
            "code": HEALTH_CODE,
        }))
        print("CLIENT_HEALTH", client.call("execute_luau", {
            "datamodel_type": "Client",
            "code": CLIENT_HEALTH_CODE,
        }))
        print("INTRO_TICKS", client.call("execute_luau", {
            "datamodel_type": "Server",
            "code": INTRO_TICKS_CODE,
        }))
        print("INTRO_HEALTH", client.call("execute_luau", {
            "datamodel_type": "Client",
            "code": INTRO_HEALTH_CODE,
        }))
        print("RUN", client.call("execute_luau", {
            "datamodel_type": "Server",
            "code": RUN_TEST_CODE,
        }))
        print("LUNGE", client.call("execute_luau", {
            "datamodel_type": "Server",
            "code": LUNGE_TEST_CODE,
        }))
        print("CONSOLE_BEGIN")
        print(client.call("get_console_output"))
        print("CONSOLE_END")
    finally:
        if started:
            try:
                print("STOP", client.call("start_stop_play", {"is_start": False}))
            except Exception as error:  # noqa: BLE001
                print(f"STOP_ERROR {error}", file=sys.stderr)
        client.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
