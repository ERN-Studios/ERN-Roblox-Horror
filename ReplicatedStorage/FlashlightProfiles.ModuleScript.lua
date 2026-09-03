-- FlashlightProfiles
-- Every flashlight beam in the game, in one table, so a tuning pass edits one
-- file instead of four scripts. An entry is Brightness / Range / Angle for the
-- tight core and the wide spill. The four sets deliberately keep the numbers
-- each script carried on 2026-09-03 -- they do not agree with each other, and
-- unifying them is a visual decision, not a refactor.

local function beam(coreBrightness, coreRange, coreAngle, spillBrightness, spillRange, spillAngle)
	return {
		Core = {Brightness = coreBrightness, Range = coreRange, Angle = coreAngle},
		Spill = {Brightness = spillBrightness, Range = spillRange, Angle = spillAngle},
	}
end

local Profiles = {
	-- Your own torch (FlashlightController).
	Own = {
		BASE = beam(1.2, 38, 38, 0.3, 45, 75),
		L3 = beam(6.0, 58, 38, 1.30, 68, 78),
		L3_BLACKOUT = beam(10.0, 66, 38, 2.25, 76, 82),
	},
	-- The server mount everyone else sees of that torch (FlashlightSync).
	Mount = {
		BASE = beam(1.2, 38, 38, 0.3, 45, 75),
		L3 = beam(4.5, 52, 40, 1.05, 62, 86),
		L3_BLACKOUT = beam(7.5, 52, 40, 1.85, 62, 86),
	},
	-- The client-side beam drawn on the heads of teammates (FlashlightController).
	Mate = {
		BASE = beam(1.2, 32, 30, 0.24, 40, 70),
		L3 = beam(4.5, 52, 40, 1.05, 62, 86),
		L3_BLACKOUT = beam(7.5, 52, 40, 1.85, 62, 86),
	},
	-- The borrowed beam while spectating a teammate (SpectateController).
	Spectate = {
		BASE = beam(5, 35, 32, 1, 45, 75),
		L3 = beam(4.5, 52, 40, 1.05, 62, 86),
		L3_BLACKOUT = beam(7.5, 52, 40, 1.85, 62, 86),
	},
}

-- Which profile the current level state calls for; shared by every consumer.
function Profiles.Current()
	if workspace:GetAttribute("SelectedLevel") ~= 3 then return "BASE" end
	return workspace:GetAttribute("Level3BlackoutActive") == true and "L3_BLACKOUT" or "L3"
end

-- Write one profile of a set onto a core and a spill SpotLight (either may be nil).
function Profiles.Apply(set, name, core, spill)
	local profile = set[name]
	if core then
		core.Brightness, core.Range, core.Angle = profile.Core.Brightness, profile.Core.Range, profile.Core.Angle
	end
	if spill then
		spill.Brightness, spill.Range, spill.Angle = profile.Spill.Brightness, profile.Spill.Range, profile.Spill.Angle
	end
end

return Profiles
