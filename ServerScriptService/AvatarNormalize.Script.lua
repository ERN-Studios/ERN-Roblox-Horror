-- AvatarNormalize
-- PASTE INTO: ServerScriptService → Insert Object → Script → rename to "AvatarNormalize"
--
-- Forces every player to the DEFAULT avatar SIZE. Players' own Roblox avatars can
-- be scaled huge or tiny (the body-scale sliders on their avatar), which would
-- give them longer reach, a higher/lower camera, and inconsistent hitboxes vs the
-- Entity and the maze. We pin the R15 scale values to the authored suit so
-- everyone is identical.
-- (Their outfit / colours are kept — only the SIZE is normalised.)
--
-- NOTE: the fully permanent way is Studio → Game Settings → Avatar (set body-scale
-- min/max to fixed). This script enforces it at runtime regardless of that.
--
-- STATUS: currently inert belt-and-braces. In-round characters all spawn from
-- the single shared hazmat StarterCharacter rig (GameManager parks it only for
-- lobby loads), so no player-controlled scale can reach this path today. Kept
-- in case gameplay spawns ever go back to HumanoidDescription-based loads.

local Players = game:GetService("Players")

-- Match the authored gameplay rig exactly. BodyProportionScale is deliberately
-- zero: Roblox defines 0 as the broad classic R15 shape and 1 as the narrow
-- proportional shape, so treating every scale's default as 1 changes the suit.
local SCALE_TARGETS = {
	BodyHeightScale = 1,
	BodyWidthScale = 1,
	BodyDepthScale = 1,
	HeadScale = 1,
	BodyTypeScale = 1,
	BodyProportionScale = 0,
}

local function normalize(char)
	local player = Players:GetPlayerFromCharacter(char)
	-- Preserve the player's exact personal avatar in the public lobby. Size is
	-- normalized only for the gameplay character where hitbox parity matters.
	if not player or player:GetAttribute("InRound") ~= true then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	for name, target in pairs(SCALE_TARGETS) do
		local o = hum:FindFirstChild(name)
		if o and o:IsA("NumberValue") then
			o.Value = target
			-- keep it pinned: a late-arriving appearance can re-write these
			o:GetPropertyChangedSignal("Value"):Connect(function()
				if o.Value ~= target then o.Value = target end
			end)
		end
	end
end

local function hook(p)
	-- CharacterAppearanceLoaded fires AFTER their avatar's scale is applied, so
	-- we're overriding the final custom size (CharacterAdded can be too early)
	p.CharacterAppearanceLoaded:Connect(normalize)
	if p.Character then task.spawn(normalize, p.Character) end
end

Players.PlayerAdded:Connect(hook)
for _, p in ipairs(Players:GetPlayers()) do hook(p) end
