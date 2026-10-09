"""Generate a passive Level 4 Play snapshot; never connect to Studio or start Play.

Use the generated Luau only after the owner releases the shared Studio test slot.
No preload, queue, readiness, Source, attribute, Parent or character writes.
"""
from pathlib import Path
import argparse
import hashlib

ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / "artifacts/lazy-levels-20261009/level4_native_qa.luau"
SOURCE = ROOT / "StarterPlayer/StarterPlayerScripts/Round Entry Client.LocalScript.lua"


def code_for(mode, source):
    if mode not in {"server", "client"}:
        raise ValueError("Select server or client")
    observer = HELPER.read_text(encoding="utf-8")
    if observer.count('local MODE = "__MODE__"') != 1:
        raise ValueError("Unexpected read-only observer")
    observer = observer.replace('local MODE = "__MODE__"', f'local MODE = "{mode}"')
    # Loading snapshots need neither door transforms nor a second geometry scan.
    # Exact markers deliberately fail closed if the reusable observer changes.
    doors = observer.index('local doors = world and unique(world, "Doors")')
    state = observer.index('local state = game:GetService("ReplicatedStorage")', doors)
    observer = observer[:doors] + observer[state:]
    census = observer.index('local clientParts, filmGuis, exitGuis = 0, 0, 0')
    returned = observer.index('return HS:JSONEncode(result)', census)
    observer = observer[:census] + 'result.cinemaPresent = cinema ~= nil\n' + observer[returned:]
    # Extract only property discovery. Never include the production preload worker.
    start = source.index("local CONTENT_PROPERTIES = {")
    end = source.index("\nlocal function fetchKey(value)", start)
    discovery = source[start:end]
    if "local function collectAsset(instance, ids, carriers)" not in discovery:
        raise ValueError("Unexpected asset discovery contract; reread the live source")
    prefix = '''local HS = game:GetService("HttpService")
local function observe()
'''
    code = prefix + observer + '''
end
local result = HS:JSONDecode(observe())
result.doors = nil -- Loading diagnosis does not need door transforms.
result.observationOnly = true
result.privateEntryRequestObserved = false
result.serverTime = workspace:GetServerTimeNow()
local levelState = game:GetService("ReplicatedStorage"):FindFirstChild("Level 4 State")
result.level4Error = levelState and levelState:GetAttribute("Level4_Error") or nil
local deadline = workspace:GetAttribute("RoundLoadingDeadline")
result.remainingSeconds = type(deadline) == "number" and deadline - result.serverTime or nil
local Players = game:GetService("Players")
for _, row in ipairs(result.players) do
    local player = Players:GetPlayerByUserId(row.userId)
    if player then
        row.readyToken = player:GetAttribute("RoundEntryReadyToken")
        row.devHoldEntryReady = player:GetAttribute("DevHoldEntryReady")
        local readable, paused = pcall(function() return player.GameplayPaused end)
        if readable then row.gameplayPaused = paused end
    end
end
'''
    if mode == "server":
        return code + '''result.serverTimeAtEnd = workspace:GetServerTimeNow()
result.selectedLevelAtEnd = workspace:GetAttribute("SelectedLevel")
result.loadingStateAtEnd = workspace:GetAttribute("RoundLoadingState")
result.loadingTokenAtEnd = workspace:GetAttribute("RoundLoadingToken")
result.loadingDeadlineAtEnd = workspace:GetAttribute("RoundLoadingDeadline")
result.changedDuringObservation = result.attributes.SelectedLevel ~= result.selectedLevelAtEnd
    or result.attributes.RoundLoadingState ~= result.loadingStateAtEnd
    or result.attributes.RoundLoadingToken ~= result.loadingTokenAtEnd
    or result.attributes.RoundLoadingDeadline ~= result.loadingDeadlineAtEnd
return HS:JSONEncode(result)
'''
    code += discovery + f'\nresult.discoverySourceSHA256 = "{hashlib.sha256(source.encode()).hexdigest()}"\n'
    code += '''local CP = game:GetService("ContentProvider")
local player = Players.LocalPlayer
local character = player.Character
local root = character and character:FindFirstChild("HumanoidRootPart")
result.gameLoaded = game:IsLoaded()
result.requestQueueSize = CP.RequestQueueSize
local worlds = {}
for _, name in ipairs({"Level 4 Cinema Blender", "ElevatorSpawn"}) do
    local instance = workspace:FindFirstChild(name)
    if instance then table.insert(worlds, instance) end
end
result.entryWorldCount = #worlds
if root and result.attributes.SelectedLevel == 4 then
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Include
    params.FilterDescendantsInstances = worlds
    params.IgnoreWater = true
    params.RespectCanCollide = true
    local hit = workspace:Raycast(root.Position + Vector3.yAxis * 2, -Vector3.yAxis * 14, params)
    result.entryFloorRay = {
        present = hit ~= nil,
        path = hit and hit.Instance:GetFullName() or nil,
        distance = hit and hit.Distance or nil,
        upwardNormal = hit and hit.Normal.Y or nil,
        collidable = hit and hit.Instance:IsA("BasePart") and hit.Instance.CanCollide or false,
    }
    local position = root.Position
    local ids, carriers = {}, {}
    local scanned, stopAt = 0, os.clock() + 4
    local function scan(owner, isCharacter)
        if not owner then return end
        for index, instance in ipairs(owner:GetDescendants()) do
            if scanned >= 30000 or os.clock() >= stopAt or player.Character ~= character then
                result.assetCensusIncomplete = true
                return
            end
            local part = instance:IsA("BasePart") and instance or instance:FindFirstAncestorWhichIsA("BasePart")
            local nearby = part and part.Transparency < 1
                and (part.Position - position).Magnitude <= 80 + part.Size.Magnitude * 0.5
            if isCharacter or nearby then collectAsset(instance, ids, carriers) end
            scanned += 1
            if index % 200 == 0 then task.wait() end
        end
    end
    scan(character, true)
    for _, world in ipairs(worlds) do scan(world, false) end
    local counts, sample, keys = {}, {}, 0
    for _, carrier in ipairs(carriers) do
        if os.clock() >= stopAt then result.assetCensusIncomplete = true break end
        for _, key in ipairs(carrier.Keys) do
            if os.clock() >= stopAt then result.assetCensusIncomplete = true break end
            keys += 1
            local ok, value = pcall(CP.GetAssetFetchStatus, CP, key)
            local status = ok and tostring(value) or "unreadable"
            counts[status] = (counts[status] or 0) + 1
            if (not ok or value ~= Enum.AssetFetchStatus.Success) and #sample < 30 then
                table.insert(sample, {
                    key = tostring(key), status = status,
                    path = carrier.Instance and carrier.Instance:GetFullName() or "SurfaceAppearance URI",
                    class = carrier.Instance and carrier.Instance.ClassName or "SurfaceAppearance",
                })
            end
        end
    end
    result.assetCensus = {scanned = scanned, keys = keys, statusCounts = counts, nonSuccessSample = sample}
    result.characterChangedDuringCensus = player.Character ~= character
    for _, world in ipairs(worlds) do
        if world.Parent ~= workspace then result.assetCensusIncomplete = true end
    end
end
result.serverTimeAtEnd = workspace:GetServerTimeNow()
result.selectedLevelAtEnd = workspace:GetAttribute("SelectedLevel")
result.loadingStateAtEnd = workspace:GetAttribute("RoundLoadingState")
result.loadingTokenAtEnd = workspace:GetAttribute("RoundLoadingToken")
result.loadingDeadlineAtEnd = workspace:GetAttribute("RoundLoadingDeadline")
result.changedDuringObservation = result.attributes.SelectedLevel ~= result.selectedLevelAtEnd
    or result.attributes.RoundLoadingState ~= result.loadingStateAtEnd
    or result.attributes.RoundLoadingToken ~= result.loadingTokenAtEnd
    or result.attributes.RoundLoadingDeadline ~= result.loadingDeadlineAtEnd
if result.characterChangedDuringCensus or result.changedDuringObservation then
    result.assetCensusIncomplete = true
end
return HS:JSONEncode(result)
'''
    return code


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("server", "client"))
    parser.add_argument("--source", type=Path, default=SOURCE,
                        help="Exact captured Round Entry source used for asset discovery")
    args = parser.parse_args()
    print(code_for(args.mode, args.source.read_text(encoding="utf-8")), end="")


if __name__ == "__main__":
    main()
