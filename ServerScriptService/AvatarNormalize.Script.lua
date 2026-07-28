-- AvatarNormalize
-- PASTE INTO: ServerScriptService → Insert Object → Script → rename to "AvatarNormalize"
--
-- Forces every player to the DEFAULT avatar SIZE. Players' own Roblox avatars can
-- be scaled huge or tiny (the body-scale sliders on their avatar), which would
-- give them longer reach, a higher/lower camera, and inconsistent hitboxes vs the
-- Entity and the maze. We pin the R15 scale values to 1 so everyone is identical.
-- (Their outfit / colours are kept — only the SIZE is normalised.)
--
-- NOTE: the fully permanent way is Studio → Game Settings → Avatar (set body-scale
-- min/max to fixed). This script enforces it at runtime regardless of that.

local Players = game:GetService("Players")

-- the four R15 body-scale NumberValues that live under the Humanoid
local SCALES = { "BodyHeightScale", "BodyWidthScale", "BodyDepthScale", "HeadScale" }

local function normalize(char)
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	for _, name in ipairs(SCALES) do
		local o = hum:FindFirstChild(name)
		if o and o:IsA("NumberValue") then
			o.Value = 1 -- default size
			-- keep it pinned: a late-arriving appearance can re-write these
			o:GetPropertyChangedSignal("Value"):Connect(function()
				if o.Value ~= 1 then o.Value = 1 end
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
