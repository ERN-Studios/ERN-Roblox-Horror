-- FlashlightProfiles
-- Every flashlight beam in the game, in one table, so a tuning pass edits one
-- file instead of four scripts. An entry is Brightness / Range / Angle for the
-- tight core and the wide spill. The four sets differ on purpose: your own torch is
-- drawn at your hand, the others are what you see of somebody else's.

local function beam(coreBrightness, coreRange, coreAngle, spillBrightness, spillRange, spillAngle)
	return {
		Core = {Brightness = coreBrightness, Range = coreRange, Angle = coreAngle},
		Spill = {Brightness = spillBrightness, Range = spillRange, Angle = spillAngle},
	}
end

-- FLASHLIGHT_REWORK_20261002 (owner: "our flashlights are super bad, rework them"; all levels). Under
-- LightingStyle Realistic the old BASE torch (1.2 / 38 studs) barely lit anything, so BASE is now a real torch:
-- a hot core that throws ~60 studs, a soft wide spill, and (own torch only, FlashlightController) a faint fill
-- light around the hand. Level 3 keeps being the strongest set, so its blackout still feels like a step up.
-- Roblox clamps Light.Range at 60 studs and focus multiplies Range by 1.45, so a BASE range stays <= 41 (focus still
-- lands near 60 and is a real gain for Advanced Equipment owners); the stronger torch comes from Brightness.
local Profiles = {
	-- Your own torch (FlashlightController).
	Own = {
		BASE = beam(6.5, 41, 34, 1.7, 41, 76),
		L3 = beam(7.5, 58, 38, 1.65, 68, 78),
		L3_BLACKOUT = beam(11.0, 66, 38, 2.6, 76, 82),
	},
	-- The server mount everyone else sees of that torch (FlashlightSync).
	Mount = {
		BASE = beam(5.0, 41, 36, 1.2, 41, 80),
		L3 = beam(5.5, 52, 40, 1.3, 62, 86),
		L3_BLACKOUT = beam(8.5, 52, 40, 2.1, 62, 86),
	},
	-- The client-side beam drawn on the heads of teammates (FlashlightController).
	Mate = {
		BASE = beam(4.5, 40, 32, 1.1, 40, 72),
		L3 = beam(5.5, 52, 40, 1.3, 62, 86),
		L3_BLACKOUT = beam(8.5, 52, 40, 2.1, 62, 86),
	},
	-- The borrowed beam while spectating a teammate (SpectateController).
	Spectate = {
		BASE = beam(6.0, 41, 34, 1.4, 41, 74),
		L3 = beam(5.5, 52, 40, 1.3, 62, 86),
		L3_BLACKOUT = beam(8.5, 52, 40, 2.1, 62, 86),
	},
}

-- Which profile the current level state calls for; shared by every consumer.
function Profiles.Current()
	if workspace:GetAttribute("SelectedLevel") ~= 3 then return "BASE" end
	return workspace:GetAttribute("Level3BlackoutActive") == true and "L3_BLACKOUT" or "L3"
end

-- Write one profile of a set onto a core and a spill SpotLight (either may be nil).
function Profiles.Apply(set, name, core, spill, focused)
	local profile = set[name]
	if core then
		core.Brightness, core.Range, core.Angle = profile.Core.Brightness, profile.Core.Range, profile.Core.Angle
	end
	if spill then
		spill.Brightness, spill.Range, spill.Angle = profile.Spill.Brightness, profile.Spill.Range, profile.Spill.Angle
	end
	if focused == true then
		if core then
			core.Range = profile.Core.Range * 1.45
			core.Angle = profile.Core.Angle * .60
		end
		if spill then
			spill.Range = profile.Spill.Range * 1.45
			spill.Angle = profile.Spill.Angle * .65
		end
	end
end

return Profiles
