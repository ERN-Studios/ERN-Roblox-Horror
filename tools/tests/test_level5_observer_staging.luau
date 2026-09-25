-- Portable six-assertion regression fixture for the authoritative protectArrival.
-- Before running, compare the embedded function with the current adapter source
-- using the repository-relative command in docs/LEVEL5_QA_2026-09-25.md.
-- This models staging decisions only; it does not simulate Roblox physics.
local total=0
for _,studio in ipairs({true,false}) do
 local moved=0
 local vectorZero={}
 local Vector3={zero=vectorZero}
 local CFrame={new=function(...) return {...} end}
 local frame=setmetatable({}, {__mul=function(_,offset) return offset end})
 local RunService={IsStudio=function() return studio end}
 local r={AssemblyLinearVelocity="before",AssemblyAngularVelocity="before",IsA=function(_,kind) return kind=="BasePart" end}
 local c={FindFirstChild=function(_,name) return name=="HumanoidRootPart" and r or nil end,PivotTo=function() moved+=1 end}
 local Players={GetPlayers=function() return {{Character=c},{Character=c}} end}
local function protectArrival(spawnFrame: CFrame)
	-- Studio keeps the lobby floor: GameManager places only the queued roster.
	-- Moving everyone here would drag an observing developer out of the lobby.
	if RunService:IsStudio() then return end
	-- All present players were checked against DevAccess before any mutation.
	-- Place current rigs onto finished ground before parking their lobby; the
	-- authoritative GameManager entry barrier then reloads/places its roster.
	local index = 0
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if character and root and root:IsA("BasePart") then
			local across = (index % 3 - 1) * 4
			local along = math.floor(index / 3) * 4
			character:PivotTo(spawnFrame * CFrame.new(across, 4, along))
			root.AssemblyLinearVelocity, root.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
			index += 1
		end
	end
end
 protectArrival(frame)
 assert(moved==(studio and 0 or 2),"Studio observer must remain in lobby; live staged rigs still move")
 assert(r.AssemblyLinearVelocity==(studio and "before" or vectorZero),"velocity changes only for staging")
 assert(r.AssemblyAngularVelocity==(studio and "before" or vectorZero),"angular velocity changes only for staging")
 total+=3
end
print("PASS: "..total.." spectator/staging assertions against final protectArrival")
